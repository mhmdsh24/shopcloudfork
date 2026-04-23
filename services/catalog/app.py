"""Catalog service — product listing stub."""
from __future__ import annotations

import os
from fastapi import FastAPI

app = FastAPI(title="shopcloud-catalog")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "catalog"}


@app.get("/ready")
def ready() -> dict:
    return {"ready": True, "service": "catalog"}


@app.get("/api/catalog")
def list_products() -> dict:
    return {
        "products": [
            {"id": "sku-001", "name": "Cloud Sticker Pack", "price": 9.99},
            {"id": "sku-002", "name": "ShopCloud Mug",       "price": 14.99},
            {"id": "sku-003", "name": "Terraform T-Shirt",   "price": 24.99},
        ],
        "region": os.environ.get("AWS_REGION", "unknown"),
    }
