"""
Unit tests for the admin service.

Covers three distinct pieces:
1. The hand-rolled password hashing (_hash_password/_verify_password)
   as plain function tests - no FastAPI, no DB, no mocking needed.
2. Signup/login routes, DB-mocked the same way as catalog/checkout.
3. The admin_required dependency, tested via dependency_overrides
   (same technique as auth) for the session-gated CRUD routes.
"""
import contextlib

import psycopg2.errors
import pytest
from fastapi.testclient import TestClient

import app as admin_app


class FakeCursor:
    def __init__(self, fetchone_result=None, fetchall_result=None, rowcount=1, raise_error=None):
        self._fetchone = fetchone_result
        self._fetchall = fetchall_result or []
        self.rowcount = rowcount
        self.executed = []
        self._raise_error = raise_error

    def execute(self, query, params=None):
        self.executed.append((query, params))
        if self._raise_error:
            raise self._raise_error

    def fetchone(self):
        return self._fetchone

    def fetchall(self):
        return self._fetchall

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


@pytest.fixture(autouse=True)
def fast_password_hashing(monkeypatch):
    # 260000 PBKDF2 iterations is the right call in production but
    # would make every test that touches signup/login noticeably
    # slow. Applies to every test in this file automatically.
    monkeypatch.setattr(admin_app, "PASSWORD_HASH_ITERATIONS", 1000)


@pytest.fixture
def client():
    test_client = TestClient(admin_app.app)
    yield test_client
    admin_app.app.dependency_overrides.clear()


def test_healthz_does_not_touch_the_database(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "admin"}


# ---------------------------------------------------------------------------
# Password hashing - pure functions, no app/DB involved
# ---------------------------------------------------------------------------


def test_password_hash_round_trips():
    hashed = admin_app._hash_password("correct-horse-battery-staple")
    assert admin_app._verify_password("correct-horse-battery-staple", hashed)


def test_password_hash_rejects_wrong_password():
    hashed = admin_app._hash_password("correct-horse-battery-staple")
    assert not admin_app._verify_password("wrong-password", hashed)


def test_password_hash_is_salted_differently_each_time():
    # Same password, hashed twice, must produce different stored
    # hashes (different random salt) - otherwise two admins with the
    # same password would be trivially linkable/crackable together.
    a = admin_app._hash_password("same-password")
    b = admin_app._hash_password("same-password")
    assert a != b
    assert admin_app._verify_password("same-password", a)
    assert admin_app._verify_password("same-password", b)


# ---------------------------------------------------------------------------
# Signup / login
# ---------------------------------------------------------------------------


def test_admin_signup_success_sets_session_cookie(client, monkeypatch):
    cursor = FakeCursor(fetchone_result=(1, "owner@example.com"))
    monkeypatch.setattr(admin_app, "_db", fake_db(cursor))

    resp = client.post("/api/admin/signup", json={"email": "owner@example.com", "password": "hunter2!"})

    assert resp.status_code == 201
    assert resp.json() == {"authenticated": True, "admin": {"id": 1, "email": "owner@example.com"}}
    assert admin_app.ADMIN_SESSION_COOKIE in resp.cookies


def test_admin_signup_rejects_short_password(client, monkeypatch):
    monkeypatch.setattr(admin_app, "_db", fake_db(FakeCursor()))

    resp = client.post("/api/admin/signup", json={"email": "owner@example.com", "password": "short"})

    assert resp.status_code == 400


def test_admin_signup_duplicate_email_returns_409(client, monkeypatch):
    cursor = FakeCursor(raise_error=psycopg2.errors.UniqueViolation("dup"))
    monkeypatch.setattr(admin_app, "_db", fake_db(cursor))

    resp = client.post("/api/admin/signup", json={"email": "owner@example.com", "password": "hunter2!"})

    assert resp.status_code == 409


def test_admin_login_success_sets_session_cookie(client, monkeypatch):
    stored_hash = admin_app._hash_password("hunter2!")
    cursor = FakeCursor(fetchone_result=(1, "owner@example.com", stored_hash))
    monkeypatch.setattr(admin_app, "_db", fake_db(cursor))

    resp = client.post("/api/admin/login", json={"email": "owner@example.com", "password": "hunter2!"})

    assert resp.status_code == 200
    assert admin_app.ADMIN_SESSION_COOKIE in resp.cookies


def test_admin_login_wrong_password_returns_401(client, monkeypatch):
    stored_hash = admin_app._hash_password("hunter2!")
    cursor = FakeCursor(fetchone_result=(1, "owner@example.com", stored_hash))
    monkeypatch.setattr(admin_app, "_db", fake_db(cursor))

    resp = client.post("/api/admin/login", json={"email": "owner@example.com", "password": "wrong"})

    assert resp.status_code == 401


def test_admin_login_unknown_email_returns_401_not_404(client, monkeypatch):
    # Deliberately the same 401 as a wrong password, not a 404 - a
    # 404 here would let an attacker enumerate which admin emails
    # exist. Worth pinning down as intentional behavior.
    cursor = FakeCursor(fetchone_result=None)
    monkeypatch.setattr(admin_app, "_db", fake_db(cursor))

    resp = client.post("/api/admin/login", json={"email": "nobody@example.com", "password": "hunter2!"})

    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Session-gated routes - tested via dependency_overrides, same as auth
# ---------------------------------------------------------------------------


def test_admin_only_routes_require_a_session(client):
    resp = client.get("/api/admin/products")
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Admin login required"


def test_list_products_returns_data_once_authenticated(client, monkeypatch):
    admin_app.app.dependency_overrides[admin_app.admin_required] = lambda: {
        "sub": 1,
        "email": "owner@example.com",
    }
    rows = [("sku-1001", "Hoodie", "desc", "apparel", "", 49.0, 42, None, None)]
    monkeypatch.setattr(admin_app, "_db", fake_db(FakeCursor(fetchall_result=rows)))

    resp = client.get("/api/admin/products")

    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 1
    assert body["products"][0]["id"] == "sku-1001"


def test_create_product_duplicate_id_returns_409(client, monkeypatch):
    admin_app.app.dependency_overrides[admin_app.admin_required] = lambda: {"sub": 1, "email": "owner@example.com"}
    cursor = FakeCursor(raise_error=psycopg2.errors.UniqueViolation("dup"))
    monkeypatch.setattr(admin_app, "_db", fake_db(cursor))

    resp = client.post(
        "/api/admin/products",
        json={"id": "sku-1001", "name": "Hoodie", "category": "apparel", "price": 49.0},
    )

    assert resp.status_code == 409


def test_update_stock_missing_product_returns_404(client, monkeypatch):
    admin_app.app.dependency_overrides[admin_app.admin_required] = lambda: {"sub": 1, "email": "owner@example.com"}
    # rowcount=0 is exactly what a real UPDATE ... WHERE id = %s
    # produces when no row matches - the route's actual "not found"
    # signal, not a fetchone() returning None.
    monkeypatch.setattr(admin_app, "_db", fake_db(FakeCursor(rowcount=0)))

    resp = client.patch("/api/admin/products/does-not-exist/stock", json={"stock": 5})

    assert resp.status_code == 404


def test_update_product_with_no_fields_returns_400(client, monkeypatch):
    admin_app.app.dependency_overrides[admin_app.admin_required] = lambda: {"sub": 1, "email": "owner@example.com"}
    monkeypatch.setattr(admin_app, "_db", fake_db(FakeCursor()))

    resp = client.put("/api/admin/products/sku-1001", json={})

    assert resp.status_code == 400
