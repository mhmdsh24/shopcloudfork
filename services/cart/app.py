"""Cart service with Redis-backed session cart persistence."""
from __future__ import annotations

import json
import os
from typing import Any

import redis
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

app = FastAPI(title="shopcloud-cart")

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
REDIS_DB = int(os.environ.get("REDIS_DB", "0"))
CART_TTL_SECONDS = int(os.environ.get("CART_TTL_SECONDS", "86400"))

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)


class CartItem(BaseModel):
    product_id: str
    quantity: int = Field(ge=1)
    unit_price: float = Field(gt=0)


class CartAddBody(BaseModel):
    """Body for POST /api/cart/add (compose-friendly alias)."""

    session_id: str = Field(default="default")
    product_id: str
    quantity: int = Field(ge=1)
    unit_price: float = Field(gt=0)


def _cart_key(session_id: str) -> str:
    return f"cart:{session_id}"


def _read_cart(session_id: str) -> dict[str, Any]:
    raw = r.get(_cart_key(session_id))
    if not raw:
        return {"session_id": session_id, "items": []}
    return json.loads(raw)


def _write_cart(session_id: str, cart: dict[str, Any]) -> None:
    r.setex(_cart_key(session_id), CART_TTL_SECONDS, json.dumps(cart))


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "cart"}


@app.get("/ready")
def ready() -> dict[str, Any]:
    try:
        r.ping()
        return {"ready": True, "service": "cart", "redis": "ok"}
    except redis.RedisError:
        return {"ready": False, "service": "cart", "redis": "down"}


@app.get("/api/cart")
def get_cart_query(session_id: str = Query(default="default")) -> dict[str, Any]:
    """GET /api/cart?session_id=... — alias for local/docker-compose testing."""
    return get_cart(session_id)


@app.post("/api/cart/add")
def add_cart_compat(body: CartAddBody) -> dict[str, Any]:
    """POST /api/cart/add — alias that accepts session_id in JSON body."""
    return add_item(
        body.session_id,
        CartItem(
            product_id=body.product_id,
            quantity=body.quantity,
            unit_price=body.unit_price,
        ),
    )


@app.get("/api/cart/{session_id}")
def get_cart(session_id: str) -> dict[str, Any]:
    try:
        cart = _read_cart(session_id)
        return {"region": os.environ.get("AWS_REGION", "unknown"), **cart}
    except redis.RedisError as exc:
        raise HTTPException(status_code=503, detail=f"Redis unavailable: {exc}") from exc


@app.post("/api/cart/{session_id}/items")
def add_item(session_id: str, item: CartItem) -> dict[str, Any]:
    try:
        cart = _read_cart(session_id)
        updated = False
        for existing in cart["items"]:
            if existing["product_id"] == item.product_id:
                existing["quantity"] += item.quantity
                updated = True
                break
        if not updated:
            cart["items"].append(item.model_dump())
        _write_cart(session_id, cart)
        return cart
    except redis.RedisError as exc:
        raise HTTPException(status_code=503, detail=f"Redis unavailable: {exc}") from exc
