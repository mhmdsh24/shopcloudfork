"""Catalog service with products, categories, images, and search."""
from __future__ import annotations

import os
from typing import Any

from fastapi import FastAPI, Query
from fastapi.responses import HTMLResponse

app = FastAPI(title="shopcloud-catalog")

PRODUCTS: list[dict[str, Any]] = [
    {
        "id": "sku-1001",
        "name": "ShopCloud Hoodie",
        "description": "Fleece hoodie for cloud builders.",
        "category": "apparel",
        "image_url": "https://cdn.shopcloud.com/images/sku-1001.jpg",
        "price": 49.0,
        "stock": 42,
    },
    {
        "id": "sku-1002",
        "name": "Kubernetes Field Notebook",
        "description": "Pocket notebook for architecture sketches.",
        "category": "stationery",
        "image_url": "https://cdn.shopcloud.com/images/sku-1002.jpg",
        "price": 12.5,
        "stock": 128,
    },
    {
        "id": "sku-1003",
        "name": "Infrastructure Mug",
        "description": "Ceramic mug for long apply sessions.",
        "category": "accessories",
        "image_url": "https://cdn.shopcloud.com/images/sku-1003.jpg",
        "price": 16.0,
        "stock": 67,
    },
]


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "catalog"}


@app.get("/ready")
def ready() -> dict[str, Any]:
    return {"ready": True, "service": "catalog", "products": len(PRODUCTS)}


@app.get("/", response_class=HTMLResponse)
def storefront() -> str:
    return """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>ShopCloud Storefront</title>
    <style>
      body { font-family: Arial, sans-serif; margin: 0; background: #f5f7fb; color: #1d2939; }
      .wrap { max-width: 960px; margin: 0 auto; padding: 24px; }
      h1 { margin-top: 0; }
      .toolbar { display: flex; gap: 12px; margin-bottom: 16px; flex-wrap: wrap; }
      input, select { padding: 8px; border: 1px solid #d0d5dd; border-radius: 8px; }
      .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; }
      .card { background: #fff; border: 1px solid #e4e7ec; border-radius: 10px; padding: 12px; }
      .card img { width: 100%; height: 140px; object-fit: cover; border-radius: 8px; background: #eef2f6; }
      .meta { font-size: 13px; color: #475467; margin-top: 6px; }
    </style>
  </head>
  <body>
    <div class="wrap">
      <h1>ShopCloud Storefront</h1>
      <div class="toolbar">
        <input id="q" placeholder="Search products..." />
        <select id="category"><option value="">All categories</option></select>
      </div>
      <div id="products" class="grid"></div>
    </div>
    <script>
      const productsEl = document.getElementById("products");
      const categoryEl = document.getElementById("category");
      const queryEl = document.getElementById("q");

      function render(products) {
        productsEl.innerHTML = products.map(p => `
          <article class="card">
            <img src="${p.image_url}" alt="${p.name}" />
            <h3>${p.name}</h3>
            <p>${p.description}</p>
            <div class="meta">Category: ${p.category}</div>
            <div class="meta">Price: $${p.price.toFixed(2)}</div>
          </article>
        `).join("");
      }

      async function loadCategories() {
        const res = await fetch("/api/catalog/categories");
        const data = await res.json();
        for (const c of data.categories) {
          const opt = document.createElement("option");
          opt.value = c;
          opt.textContent = c;
          categoryEl.appendChild(opt);
        }
      }

      async function loadProducts() {
        const q = queryEl.value.trim();
        const category = categoryEl.value;
        if (q.length > 0) {
          const res = await fetch(`/api/catalog/search?q=${encodeURIComponent(q)}`);
          const data = await res.json();
          render(data.results);
          return;
        }
        const url = category ? `/api/catalog/products?category=${encodeURIComponent(category)}` : "/api/catalog/products";
        const res = await fetch(url);
        const data = await res.json();
        render(data.products);
      }

      queryEl.addEventListener("input", loadProducts);
      categoryEl.addEventListener("change", loadProducts);
      loadCategories().then(loadProducts);
    </script>
  </body>
</html>
"""


@app.get("/api/catalog/products")
def list_products(category: str | None = Query(default=None)) -> dict[str, Any]:
    items = PRODUCTS
    if category:
        items = [p for p in PRODUCTS if p["category"] == category]
    return {"products": items, "count": len(items), "region": os.environ.get("AWS_REGION", "unknown")}


@app.get("/api/catalog/categories")
def list_categories() -> dict[str, list[str]]:
    categories = sorted({p["category"] for p in PRODUCTS})
    return {"categories": categories}


@app.get("/api/catalog/search")
def search_products(q: str = Query(min_length=1)) -> dict[str, Any]:
    needle = q.lower().strip()
    results = [
        p
        for p in PRODUCTS
        if needle in p["name"].lower()
        or needle in p["description"].lower()
        or needle in p["category"].lower()
    ]
    return {"query": q, "results": results, "count": len(results)}
