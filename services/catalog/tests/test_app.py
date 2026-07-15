"""
Unit tests for the catalog service.

app.py has no dependency injection for its database access (no
Depends(get_db)) - every route calls the module-level `_db()`
context manager directly, which opens a real psycopg2 connection
pool from environment variables. To test routes without a real
Postgres, we monkeypatch `app._db` itself to hand back a fake
connection/cursor with canned data instead.
"""
import contextlib

import pytest
from fastapi.testclient import TestClient

import app as catalog_app


class FakeCursor:
    """Stands in for a psycopg2 cursor. Records what was executed and
    returns whatever rows the test configured, instead of hitting a
    real database."""

    def __init__(self, rows=None, one=None):
        self._rows = rows or []
        self._one = one
        self.executed = []

    def execute(self, query, params=None):
        self.executed.append((query, params))

    def fetchall(self):
        return self._rows

    def fetchone(self):
        return self._one

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False


class FakeConnection:
    """Stands in for a psycopg2 connection. commit()/rollback() are
    no-ops since there's nothing real to commit."""

    def __init__(self, cursor: FakeCursor):
        self._cursor = cursor

    def cursor(self):
        return self._cursor

    def commit(self):
        pass

    def rollback(self):
        pass


def fake_db(cursor: FakeCursor):
    """Builds a drop-in replacement for app._db that hands back a
    FakeConnection wrapping the given cursor, matching the real
    `with _db() as conn:` contract."""

    @contextlib.contextmanager
    def _fake():
        yield FakeConnection(cursor)

    return _fake


@pytest.fixture
def client():
    return TestClient(catalog_app.app)


def test_healthz_does_not_touch_the_database(client):
    # /healthz never calls _db() at all - it's a pure liveness check.
    # No mocking needed, which makes it a good "does TestClient even
    # work" sanity check before testing anything DB-backed.
    resp = client.get("/healthz")

    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "catalog"}


def test_list_products_returns_seeded_shape(client, monkeypatch):
    rows = [
        ("sku-1001", "ShopCloud Hoodie", "Fleece hoodie for cloud builders.",
         "apparel", "/images/sku-1001.png", 49.00, 42),
    ]
    monkeypatch.setattr(catalog_app, "_db", fake_db(FakeCursor(rows=rows)))

    resp = client.get("/api/catalog/products")

    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 1
    assert body["products"][0]["id"] == "sku-1001"
    # _row_to_dict casts price to float - verifying that cast actually happens
    assert body["products"][0]["price"] == 49.00
    assert isinstance(body["products"][0]["price"], float)


def test_get_product_not_found_returns_404(client, monkeypatch):
    # fetchone() returning None is exactly what happens when a real
    # query matches zero rows - this is the real "not found" path,
    # not a contrived error case.
    monkeypatch.setattr(catalog_app, "_db", fake_db(FakeCursor(one=None)))

    resp = client.get("/api/catalog/products/does-not-exist")

    assert resp.status_code == 404


def test_search_products_lowercases_and_wraps_query(client, monkeypatch):
    cursor = FakeCursor(rows=[])
    monkeypatch.setattr(catalog_app, "_db", fake_db(cursor))

    client.get("/api/catalog/search?q=Hoodie")

    # Verify the route actually built the SQL LIKE pattern we expect,
    # not just that it returned 200 - this is what catches a future
    # refactor that silently breaks the search behavior.
    query, params = cursor.executed[0]
    assert params == ("%hoodie%", "%hoodie%", "%hoodie%")
