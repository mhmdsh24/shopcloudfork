"""
Unit tests for the auth service.

Unlike catalog/cart/checkout, auth actually uses FastAPI's Depends()
for the token-validation dependencies (customer_claims/admin_claims),
so the /me routes can be tested with app.dependency_overrides instead
of monkeypatching internals - the cleaner, FastAPI-native way to test
a route that depends on something you don't want to exercise for
real (here: decoding a genuine Cognito JWT against live JWKS).

The signup/login routes call the module-level `cognito` boto3 client
directly, so those still need a fake client via monkeypatch.
"""
import pytest
from botocore.exceptions import ClientError
from fastapi.testclient import TestClient

import app as auth_app


class FakeCognito:
    """Records calls and returns/raises whatever the test configured."""

    def __init__(self, sign_up_result=None, initiate_auth_result=None, raise_error=None):
        self.calls = []
        self._sign_up_result = sign_up_result or {"UserConfirmed": True, "UserSub": "sub-123"}
        self._initiate_auth_result = initiate_auth_result or {
            "AuthenticationResult": {"IdToken": "fake-id-token", "AccessToken": "fake-access-token"}
        }
        self._raise_error = raise_error

    def sign_up(self, **kwargs):
        self.calls.append(("sign_up", kwargs))
        if self._raise_error:
            raise self._raise_error
        return self._sign_up_result

    def admin_confirm_sign_up(self, **kwargs):
        self.calls.append(("admin_confirm_sign_up", kwargs))

    def initiate_auth(self, **kwargs):
        self.calls.append(("initiate_auth", kwargs))
        if self._raise_error:
            raise self._raise_error
        return self._initiate_auth_result


@pytest.fixture
def client():
    test_client = TestClient(auth_app.app)
    yield test_client
    # dependency_overrides is process-global state on the app object -
    # clear it after every test so one test's override can't leak into
    # the next.
    auth_app.app.dependency_overrides.clear()


def test_healthz_does_not_touch_cognito(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "auth"}


def test_customer_signup_success(client, monkeypatch):
    fake = FakeCognito(sign_up_result={"UserConfirmed": True, "UserSub": "sub-abc"})
    monkeypatch.setattr(auth_app, "cognito", fake)

    resp = client.post("/api/auth/customer/signup", json={"email": "new@example.com", "password": "hunter2!"})

    assert resp.status_code == 200
    body = resp.json()
    assert body["flow"] == "customer"
    assert body["user_sub"] == "sub-abc"
    # UserConfirmed=True means admin_confirm_sign_up should NOT have
    # been called - worth pinning down since calling it unnecessarily
    # would be a real (if harmless) extra Cognito API call in prod.
    assert [c[0] for c in fake.calls] == ["sign_up"]


def test_customer_signup_auto_confirms_when_not_pre_confirmed(client, monkeypatch):
    fake = FakeCognito(sign_up_result={"UserConfirmed": False, "UserSub": "sub-def"})
    monkeypatch.setattr(auth_app, "cognito", fake)

    resp = client.post("/api/auth/customer/signup", json={"email": "new2@example.com", "password": "hunter2!"})

    assert resp.status_code == 200
    assert [c[0] for c in fake.calls] == ["sign_up", "admin_confirm_sign_up"]


def test_customer_signup_translates_cognito_error(client, monkeypatch):
    error = ClientError(
        error_response={"Error": {"Code": "UsernameExistsException", "Message": "User already exists"}},
        operation_name="SignUp",
    )
    monkeypatch.setattr(auth_app, "cognito", FakeCognito(raise_error=error))

    resp = client.post("/api/auth/customer/signup", json={"email": "dup@example.com", "password": "hunter2!"})

    assert resp.status_code == 400
    assert resp.json()["detail"]["error"] == "UsernameExistsException"


def test_customer_login_success_returns_tokens(client, monkeypatch):
    fake = FakeCognito(initiate_auth_result={"AuthenticationResult": {"IdToken": "tok-1", "AccessToken": "tok-2"}})
    monkeypatch.setattr(auth_app, "cognito", fake)

    resp = client.post("/api/auth/customer/login", json={"username": "user@example.com", "password": "hunter2!"})

    assert resp.status_code == 200
    assert resp.json()["tokens"]["IdToken"] == "tok-1"


def test_customer_login_wrong_password_returns_502_with_cognito_code(client, monkeypatch):
    # NotAuthorizedException is what real Cognito returns for a wrong
    # password - the route maps this to 502, not 401, which is worth
    # knowing if you're building a frontend against this API.
    error = ClientError(
        error_response={"Error": {"Code": "NotAuthorizedException", "Message": "Incorrect username or password."}},
        operation_name="InitiateAuth",
    )
    monkeypatch.setattr(auth_app, "cognito", FakeCognito(raise_error=error))

    resp = client.post("/api/auth/customer/login", json={"username": "user@example.com", "password": "wrong"})

    assert resp.status_code == 502
    assert resp.json()["detail"]["code"] == "NotAuthorizedException"


def test_customer_me_requires_bearer_token(client):
    # No dependency override here - _bearer_token() raises before
    # touching Cognito/JWT at all, so this exercises the real path.
    resp = client.get("/api/auth/customer/me")
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Missing bearer token"


def test_customer_me_returns_claims_from_valid_token(client):
    # Overriding the dependency instead of forging a real signed JWT -
    # this is what Depends() is for: testing "what does the route do
    # with these claims" separately from "how do we validate a token."
    auth_app.app.dependency_overrides[auth_app.customer_claims] = lambda: {
        "sub": "user-123",
        "email": "user@example.com",
    }

    resp = client.get("/api/auth/customer/me", headers={"Authorization": "Bearer irrelevant-because-overridden"})

    assert resp.status_code == 200
    assert resp.json() == {"flow": "customer", "claims": {"sub": "user-123", "email": "user@example.com"}}
