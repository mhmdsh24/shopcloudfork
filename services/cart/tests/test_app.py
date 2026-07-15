"""
Unit tests for the cart service.

Like catalog, cart has no dependency injection for its data layer -
routes call the module-level `r` (a redis.Redis client) directly.
redis-py's Redis() constructor doesn't connect eagerly (the socket
opens on first command), so importing the module is safe without a
real Redis - but calling any route would still try to reach
REDIS_HOST=localhost:6379 unless we replace `r` with a fake.
"""
import pytest
from fastapi.testclient import TestClient

import app as cart_app


class FakeRedis:
    """In-memory stand-in for the subset of redis-py's API cart uses."""

    def __init__(self):
        self._store: dict[str, str] = {}

    def get(self, key):
        return self._store.get(key)

    def setex(self, key, ttl, value):
        self._store[key] = value

    def delete(self, key):
        self._store.pop(key, None)

    def ping(self):
        return True


@pytest.fixture
def fake_redis(monkeypatch):
    fake = FakeRedis()
    monkeypatch.setattr(cart_app, "r", fake)
    return fake


@pytest.fixture
def client():
    return TestClient(cart_app.app)


def test_healthz_does_not_touch_redis(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "cart"}


def test_ready_reports_down_when_redis_unreachable(client, monkeypatch):
    # Exercise the real failure path: r.ping() raising, not just a
    # contrived mock - this is what actually happens if ElastiCache
    # is unreachable.
    import redis as redis_module

    class BrokenRedis:
        def ping(self):
            raise redis_module.RedisError("connection refused")

    monkeypatch.setattr(cart_app, "r", BrokenRedis())

    resp = client.get("/ready")

    assert resp.status_code == 200
    assert resp.json() == {"ready": False, "service": "cart", "redis": "down"}


def test_get_cart_for_new_session_is_empty(client, fake_redis):
    resp = client.get("/api/cart/brand-new-session")

    assert resp.status_code == 200
    body = resp.json()
    assert body["session_id"] == "brand-new-session"
    assert body["items"] == []


def test_add_item_then_get_cart_round_trips(client, fake_redis):
    add_resp = client.post(
        "/api/cart/session-1/items",
        json={"product_id": "sku-1001", "quantity": 2, "unit_price": 49.0},
    )
    assert add_resp.status_code == 200

    get_resp = client.get("/api/cart/session-1")
    items = get_resp.json()["items"]
    assert len(items) == 1
    assert items[0] == {"product_id": "sku-1001", "quantity": 2, "unit_price": 49.0}


def test_add_item_twice_increments_quantity_instead_of_duplicating(client, fake_redis):
    # This is the real merge behavior the route implements (see the
    # "for existing in cart["items"]" loop in app.py) - worth pinning
    # down explicitly since it's easy to accidentally break into
    # "always append" during a refactor.
    client.post("/api/cart/session-2/items", json={"product_id": "sku-1002", "quantity": 1, "unit_price": 12.5})
    client.post("/api/cart/session-2/items", json={"product_id": "sku-1002", "quantity": 3, "unit_price": 12.5})

    cart = client.get("/api/cart/session-2").json()

    assert len(cart["items"]) == 1
    assert cart["items"][0]["quantity"] == 4


def test_delete_cart_empties_it(client, fake_redis):
    client.post("/api/cart/session-3/items", json={"product_id": "sku-1003", "quantity": 1, "unit_price": 16.0})

    del_resp = client.delete("/api/cart/session-3")
    assert del_resp.status_code == 200
    assert del_resp.json() == {"session_id": "session-3", "deleted": True}

    cart = client.get("/api/cart/session-3").json()
    assert cart["items"] == []


def test_add_item_rejects_non_positive_quantity(client, fake_redis):
    # quantity has Field(ge=1) - FastAPI/Pydantic should reject this
    # before the route body ever runs, with no Redis call needed.
    resp = client.post(
        "/api/cart/session-4/items",
        json={"product_id": "sku-1001", "quantity": 0, "unit_price": 49.0},
    )
    assert resp.status_code == 422
