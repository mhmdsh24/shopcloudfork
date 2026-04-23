"""Admin service — back office dashboard stub."""
from __future__ import annotations

import os
from fastapi import FastAPI

app = FastAPI(title="shopcloud-admin")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "admin"}


@app.get("/ready")
def ready() -> dict:
    return {"ready": True, "service": "admin"}


@app.get("/")
def index() -> dict:
    return {
        "service": "admin",
        "message": "ShopCloud admin panel — VPN-only access",
        "region": os.environ.get("AWS_REGION", "unknown"),
    }
