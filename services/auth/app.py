"""Auth service — wraps Cognito user pool operations."""
from __future__ import annotations

import os
from fastapi import FastAPI

app = FastAPI(title="shopcloud-auth")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "auth"}


@app.get("/ready")
def ready() -> dict:
    return {"ready": True, "service": "auth"}


@app.get("/api/auth/config")
def config() -> dict:
    return {
        "customer_pool_id":  os.environ.get("CUSTOMER_POOL_ID", ""),
        "customer_client":   os.environ.get("CUSTOMER_CLIENT_ID", ""),
        "admin_pool_id":     os.environ.get("ADMIN_POOL_ID", ""),
        "admin_client":      os.environ.get("ADMIN_CLIENT_ID", ""),
        "region":            os.environ.get("AWS_REGION", "unknown"),
    }
