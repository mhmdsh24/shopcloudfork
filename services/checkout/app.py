"""Checkout service — validates order and publishes directly to SQS."""
from __future__ import annotations

import os
import uuid
import json
from datetime import datetime, timezone
import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

app = FastAPI(title="shopcloud-checkout")
SQS_URL = os.environ.get("INVOICE_QUEUE_URL", "")
sqs = boto3.client("sqs", region_name=os.environ.get("AWS_REGION", "us-east-1"))


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


def simulate_payment(order: Order) -> dict:
    return {
        "success": True,
        "transaction_id": f"txn-{uuid.uuid4().hex[:10]}",
        "confirmed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "provider": "simulated-gateway",
    }


@app.post("/api/checkout")
def checkout(order: Order) -> dict:
    if not order.items:
        raise HTTPException(status_code=400, detail="Cart is empty")
    if order.total <= 0:
        raise HTTPException(status_code=400, detail="Order total must be positive")

    order_id = f"ord-{uuid.uuid4().hex[:8]}"
    payment = simulate_payment(order)
    message = {
        "event_type": "OrderCompleted",
        "order_id": order_id,
        "customer_email": order.customer_email,
        "items": order.items,
        "total": order.total,
        "currency": order.currency,
        "payment": payment,
    }
    sqs_error: str | None = None
    if SQS_URL:
        try:
            sqs.send_message(QueueUrl=SQS_URL, MessageBody=json.dumps(message))
        except (ClientError, BotoCoreError) as exc:
            sqs_error = str(exc)
    response = {
        "order_id": order_id,
        "customer_email": order.customer_email,
        "total": order.total,
        "currency": order.currency,
        "payment": payment,
        "invoice_queue_url": SQS_URL,
        "sqs_publish_error": sqs_error,
        "region": os.environ.get("AWS_REGION", "unknown"),
    }
    if sqs_error:
        return JSONResponse(status_code=207, content=response)
    return response
