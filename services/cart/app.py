"""Cart service — session/cart operations (Redis-backed in production)."""
from __future__ import annotations

import os
from fastapi import FastAPI

app = FastAPI(title="shopcloud-cart")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "cart"}


@app.get("/ready")
def ready() -> dict:
    return {"ready": True, "service": "cart"}


@app.get("/api/cart/{user_id}")
def get_cart(user_id: str) -> dict:
    return {
        "user_id": user_id,
        "items": [],
        "region": os.environ.get("AWS_REGION", "unknown"),
    }
