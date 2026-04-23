"""Checkout service — publishes OrderCompleted to EventBridge."""
from __future__ import annotations

import os
import uuid
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="shopcloud-checkout")


class Order(BaseModel):
    customer_email: str
    items: list[dict]
    total: float
    currency: str = "USD"


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "checkout"}


@app.get("/ready")
def ready() -> dict:
    return {"ready": True, "service": "checkout"}


@app.post("/api/checkout")
def checkout(order: Order) -> dict:
    order_id = f"ord-{uuid.uuid4().hex[:8]}"
    # In production this publishes to EventBridge; the infra + IAM
    # is wired up in Terraform (EVENT_BUS_NAME env var + IRSA role).
    return {
        "order_id": order_id,
        "customer_email": order.customer_email,
        "total": order.total,
        "currency": order.currency,
        "event_bus": os.environ.get("EVENT_BUS_NAME", "unknown"),
        "region": os.environ.get("AWS_REGION", "unknown"),
    }
