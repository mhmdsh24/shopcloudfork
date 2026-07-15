"""
Unit tests for the checkout service.

Two things make this one trickier than catalog/cart:

1. list_orders() re-uses the *same* cursor for an outer query (all
   orders) and then, inside a loop, an inner query per order (that
   order's line items). A cursor that only knows one canned result
   can't model that - FakeCursor here takes a *queue* of results and
   returns the next one on each fetchall() call, in call order.

2. checkout() calls boto3's SQS client directly (module-level `sqs`),
   so we monkeypatch that too, separately from the DB.
"""
import contextlib

import pytest
from fastapi.testclient import TestClient

import app as checkout_app


class FakeCursor:
    """Cursor that returns a different canned fetchall() result each
    time it's called, in the order the test configures - models
    checkout's outer-query/inner-query-per-row pattern."""

    def __init__(self, fetchall_results=None):
        self._queue = list(fetchall_results or [])
        self.executed = []

    def execute(self, query, params=None):
        self.executed.append((query, params))

    def fetchall(self):
        return self._queue.pop(0) if self._queue else []

    def fetchone(self):
        return None

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False


class FakeConnection:
    def __init__(self, cursor: FakeCursor):
        self._cursor = cursor

    def cursor(self):
        return self._cursor

    def commit(self):
        pass

    def rollback(self):
        pass


def fake_db(cursor: FakeCursor):
    @contextlib.contextmanager
    def _fake():
        yield FakeConnection(cursor)

    return _fake


class FakeSQS:
    def __init__(self, raise_error: Exception | None = None):
        self.sent_messages = []
        self._raise_error = raise_error

    def send_message(self, QueueUrl, MessageBody):
        if self._raise_error:
            raise self._raise_error
        self.sent_messages.append((QueueUrl, MessageBody))


@pytest.fixture
def client():
    return TestClient(checkout_app.app)


VALID_ORDER = {
    "customer_email": "buyer@example.com",
    "items": [{"product_id": "sku-1001", "product_name": "Hoodie", "quantity": 1, "unit_price": 49.0}],
    "total": 49.0,
}


def test_healthz_does_not_touch_the_database(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "checkout"}


def test_checkout_rejects_empty_cart(client, monkeypatch):
    monkeypatch.setattr(checkout_app, "_db", fake_db(FakeCursor()))
    monkeypatch.setattr(checkout_app, "sqs", FakeSQS())
    monkeypatch.setattr(checkout_app, "SQS_URL", "")

    resp = client.post("/api/checkout", json={**VALID_ORDER, "items": []})

    assert resp.status_code == 400
    assert resp.json()["detail"] == "Cart is empty"


def test_checkout_rejects_non_positive_total(client, monkeypatch):
    monkeypatch.setattr(checkout_app, "_db", fake_db(FakeCursor()))
    monkeypatch.setattr(checkout_app, "sqs", FakeSQS())
    monkeypatch.setattr(checkout_app, "SQS_URL", "")

    resp = client.post("/api/checkout", json={**VALID_ORDER, "total": 0})

    assert resp.status_code == 400
    assert resp.json()["detail"] == "Order total must be positive"


def test_checkout_success_writes_order_and_publishes_to_sqs(client, monkeypatch):
    fake_sqs = FakeSQS()
    monkeypatch.setattr(checkout_app, "_db", fake_db(FakeCursor()))
    monkeypatch.setattr(checkout_app, "sqs", fake_sqs)
    monkeypatch.setattr(checkout_app, "SQS_URL", "https://sqs.example/queue")

    resp = client.post("/api/checkout", json=VALID_ORDER)

    assert resp.status_code == 200
    body = resp.json()
    assert body["order_id"].startswith("ord-")
    assert body["sqs_publish_error"] is None
    assert body["payment"]["success"] is True

    # A real message actually went to the (fake) queue, with the order
    # details in it - not just a 200 status with no side effect.
    assert len(fake_sqs.sent_messages) == 1
    queue_url, message_body = fake_sqs.sent_messages[0]
    assert queue_url == "https://sqs.example/queue"
    assert body["order_id"] in message_body


def test_checkout_degrades_gracefully_when_sqs_publish_fails(client, monkeypatch):
    # This is the real degraded-mode path: the order is still saved to
    # Postgres (money isn't lost), but the response reports the SQS
    # failure via 207 instead of silently returning 200.
    # The app only catches (ClientError, BotoCoreError) - a real SQS
    # failure (queue missing, throttled, etc.) surfaces as one of
    # these, not a bare Exception, so the test raises the same thing
    # AWS actually would.
    from botocore.exceptions import ClientError

    sqs_error = ClientError(
        error_response={"Error": {"Code": "AWS.SimpleQueueService.NonExistentQueue", "Message": "Queue does not exist"}},
        operation_name="SendMessage",
    )
    monkeypatch.setattr(checkout_app, "_db", fake_db(FakeCursor()))
    monkeypatch.setattr(checkout_app, "sqs", FakeSQS(raise_error=sqs_error))
    monkeypatch.setattr(checkout_app, "SQS_URL", "https://sqs.example/queue")

    resp = client.post("/api/checkout", json=VALID_ORDER)

    assert resp.status_code == 207
    assert resp.json()["sqs_publish_error"] is not None


def test_list_orders_nests_items_under_each_order(client, monkeypatch):
    order_row = [("ord-abc12345", "buyer@example.com", 49.0, "USD", "completed", "txn-xyz", None)]
    item_rows = [("sku-1001", "Hoodie", 1, 49.0)]
    # First fetchall() call is the outer orders query, second is the
    # inner order_items query triggered inside the loop for that order.
    cursor = FakeCursor(fetchall_results=[order_row, item_rows])
    monkeypatch.setattr(checkout_app, "_db", fake_db(cursor))

    resp = client.get("/api/checkout/orders?email=buyer@example.com")

    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 1
    order = body["orders"][0]
    assert order["id"] == "ord-abc12345"
    assert order["items"] == [
        {"product_id": "sku-1001", "product_name": "Hoodie", "quantity": 1, "unit_price": 49.0}
    ]


def test_list_orders_requires_email(client, monkeypatch):
    # email has no default and min_length=1 - FastAPI should 422
    # before any DB call happens.
    monkeypatch.setattr(checkout_app, "_db", fake_db(FakeCursor()))

    resp = client.get("/api/checkout/orders")

    assert resp.status_code == 422
