"""Auth service with separate customer/admin Cognito flows and JWT validation."""
from __future__ import annotations

import os
from functools import lru_cache
from typing import Any

import boto3
import requests
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import Depends, FastAPI, Header, HTTPException
from jose import JWTError, jwt
from pydantic import BaseModel

app = FastAPI(title="shopcloud-auth")
region = os.environ.get("AWS_REGION", "us-east-1")
cognito = boto3.client("cognito-idp", region_name=region)

CUSTOMER_POOL_ID = os.environ.get("CUSTOMER_POOL_ID", "")
CUSTOMER_CLIENT_ID = os.environ.get("CUSTOMER_CLIENT_ID", "")
ADMIN_POOL_ID = os.environ.get("ADMIN_POOL_ID", "")
ADMIN_CLIENT_ID = os.environ.get("ADMIN_CLIENT_ID", "")


class LoginRequest(BaseModel):
    username: str
    password: str


@lru_cache(maxsize=4)
def _jwks(pool_id: str) -> dict[str, Any]:
    url = f"https://cognito-idp.{region}.amazonaws.com/{pool_id}/.well-known/jwks.json"
    return requests.get(url, timeout=5).json()


def _decode_token(token: str, pool_id: str, client_id: str) -> dict[str, Any]:
    headers = jwt.get_unverified_header(token)
    kid = headers.get("kid")
    for key in _jwks(pool_id).get("keys", []):
        if key.get("kid") == kid:
            try:
                return jwt.decode(
                    token,
                    key,
                    algorithms=["RS256"],
                    audience=client_id,
                    issuer=f"https://cognito-idp.{region}.amazonaws.com/{pool_id}",
                )
            except JWTError as exc:
                raise HTTPException(status_code=401, detail=f"Invalid token: {exc}") from exc
    raise HTTPException(status_code=401, detail="Signing key not found")


def _bearer_token(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    return authorization.split(" ", 1)[1]


def customer_claims(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    return _decode_token(_bearer_token(authorization), CUSTOMER_POOL_ID, CUSTOMER_CLIENT_ID)


def admin_claims(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    return _decode_token(_bearer_token(authorization), ADMIN_POOL_ID, ADMIN_CLIENT_ID)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "auth"}


@app.get("/ready")
def ready() -> dict[str, Any]:
    return {"ready": True, "service": "auth", "region": region}


@app.post("/api/auth/customer/login")
def customer_login(payload: LoginRequest) -> dict[str, Any]:
    try:
        response = cognito.initiate_auth(
            ClientId=CUSTOMER_CLIENT_ID,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": payload.username, "PASSWORD": payload.password},
        )
        return {"flow": "customer", "tokens": response.get("AuthenticationResult", {})}
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "ClientError")
        raise HTTPException(
            status_code=502,
            detail={"flow": "customer", "error": "cognito_client_error", "code": code},
        ) from exc
    except BotoCoreError as exc:
        raise HTTPException(
            status_code=503,
            detail={"flow": "customer", "error": "cognito_unavailable", "message": str(exc)},
        ) from exc


@app.post("/api/auth/admin/login")
def admin_login(payload: LoginRequest) -> dict[str, Any]:
    try:
        response = cognito.initiate_auth(
            ClientId=ADMIN_CLIENT_ID,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": payload.username, "PASSWORD": payload.password},
        )
        return {"flow": "admin", "tokens": response.get("AuthenticationResult", {})}
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "ClientError")
        raise HTTPException(
            status_code=502,
            detail={"flow": "admin", "error": "cognito_client_error", "code": code},
        ) from exc
    except BotoCoreError as exc:
        raise HTTPException(
            status_code=503,
            detail={"flow": "admin", "error": "cognito_unavailable", "message": str(exc)},
        ) from exc


@app.get("/api/auth/customer/me")
def customer_me(claims: dict[str, Any] = Depends(customer_claims)) -> dict[str, Any]:
    return {"flow": "customer", "claims": claims}


@app.get("/api/auth/admin/me")
def admin_me(claims: dict[str, Any] = Depends(admin_claims)) -> dict[str, Any]:
    return {"flow": "admin", "claims": claims}
