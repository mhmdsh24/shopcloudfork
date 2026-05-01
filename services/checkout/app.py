"""Checkout service — persists orders to RDS, deducts stock, publishes to SQS."""
from __future__ import annotations

import json
import logging
import os
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone

import boto3
import psycopg2
import psycopg2.pool
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel

app = FastAPI(title="shopcloud-checkout")
log = logging.getLogger("checkout")

SQS_URL = os.environ.get("INVOICE_QUEUE_URL", "")
sqs = boto3.client("sqs", region_name=os.environ.get("AWS_REGION", "us-east-1"))

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "shopcloud")
DB_USER = os.environ.get("DB_USER", "shopcloud_admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
SKIP_DB_SCHEMA_INIT = os.environ.get("SKIP_DB_SCHEMA_INIT", "").lower() in {"1", "true", "yes"}

_pool: psycopg2.pool.SimpleConnectionPool | None = None


def _get_pool() -> psycopg2.pool.SimpleConnectionPool:
    global _pool
    if _pool is None:
        for attempt in range(30):
            try:
                _pool = psycopg2.pool.SimpleConnectionPool(
                    1, 10,
                    host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                    user=DB_USER, password=DB_PASSWORD,
                    sslmode="require",
                )
                break
            except psycopg2.OperationalError:
                if attempt == 29:
                    raise
                time.sleep(2)
    return _pool


@contextmanager
def _db():
    pool = _get_pool()
    conn = pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def _init_schema() -> None:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS orders (
                    id               VARCHAR(20) PRIMARY KEY,
                    customer_email   VARCHAR(255) NOT NULL,
                    total            NUMERIC(10,2) NOT NULL,
                    currency         VARCHAR(3) DEFAULT 'USD',
                    status           VARCHAR(20) DEFAULT 'completed',
                    transaction_id   VARCHAR(50),
                    created_at       TIMESTAMPTZ DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS order_items (
                    id           SERIAL PRIMARY KEY,
                    order_id     VARCHAR(20) REFERENCES orders(id),
                    product_id   VARCHAR(20),
                    product_name VARCHAR(255),
                    quantity     INTEGER NOT NULL,
                    unit_price   NUMERIC(10,2) NOT NULL
                )
            """)


@app.on_event("startup")
def startup() -> None:
    if SKIP_DB_SCHEMA_INIT:
        log.info("Skipping checkout schema initialization")
        return
    _init_schema()


class OrderItem(BaseModel):
    product_id: str
    product_name: str = ""
    quantity: int
    unit_price: float


class Order(BaseModel):
    customer_email: str
    items: list[OrderItem]
    total: float
    currency: str = "USD"


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "checkout"}


@app.get("/ready")
def ready() -> dict:
    try:
        with _db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return {"ready": True, "service": "checkout"}
    except Exception:
        return {"ready": False, "service": "checkout"}


def _simulate_payment(order: Order) -> dict:
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
    payment = _simulate_payment(order)

    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO orders (id, customer_email, total, currency, status, transaction_id) "
                "VALUES (%s, %s, %s, %s, %s, %s)",
                (order_id, order.customer_email, order.total, order.currency,
                 "completed", payment["transaction_id"]),
            )
            for item in order.items:
                cur.execute(
                    "INSERT INTO order_items (order_id, product_id, product_name, quantity, unit_price) "
                    "VALUES (%s, %s, %s, %s, %s)",
                    (order_id, item.product_id, item.product_name, item.quantity, item.unit_price),
                )
                cur.execute(
                    "UPDATE products SET stock = GREATEST(stock - %s, 0), updated_at = NOW() "
                    "WHERE id = %s",
                    (item.quantity, item.product_id),
                )

    sqs_items = [
        {"name": it.product_name or it.product_id, "qty": it.quantity, "price": it.unit_price}
        for it in order.items
    ]
    message = {
        "event_type": "OrderCompleted",
        "order_id": order_id,
        "customer_email": order.customer_email,
        "items": sqs_items,
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
        "sqs_publish_error": sqs_error,
        "region": os.environ.get("AWS_REGION", "unknown"),
    }
    if sqs_error:
        return JSONResponse(status_code=207, content=response)
    return response


@app.get("/api/checkout/orders")
def list_orders(email: str = Query(min_length=1)) -> dict:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, customer_email, total, currency, status, transaction_id, created_at "
                "FROM orders WHERE customer_email = %s ORDER BY created_at DESC LIMIT 50",
                (email,),
            )
            cols = ("id", "customer_email", "total", "currency", "status", "transaction_id", "created_at")
            orders = []
            for row in cur.fetchall():
                o = dict(zip(cols, row))
                o["total"] = float(o["total"])
                o["created_at"] = o["created_at"].isoformat() if o["created_at"] else None
                cur.execute(
                    "SELECT product_id, product_name, quantity, unit_price FROM order_items WHERE order_id = %s",
                    (o["id"],),
                )
                o["items"] = [
                    {"product_id": r[0], "product_name": r[1], "quantity": r[2], "unit_price": float(r[3])}
                    for r in cur.fetchall()
                ]
                orders.append(o)
    return {"orders": orders, "count": len(orders)}
