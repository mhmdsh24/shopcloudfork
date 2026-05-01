"""Admin service — product CRUD, order management, JWT-protected dashboard."""
from __future__ import annotations

import logging
import os
import time
from contextlib import contextmanager
from functools import lru_cache
from typing import Any

import boto3
import psycopg2
import psycopg2.pool
import requests as http_requests
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import HTMLResponse
from jose import JWTError, jwt
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

app = FastAPI(title="shopcloud-admin")
Instrumentator().instrument(app).expose(app)

log = logging.getLogger("admin")

region = os.environ.get("AWS_REGION", "us-east-1")
ADMIN_POOL_ID = os.environ.get("ADMIN_POOL_ID", "")
ADMIN_CLIENT_ID = os.environ.get("ADMIN_CLIENT_ID", "")

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "shopcloud")
DB_USER = os.environ.get("DB_USER", "shopcloud_admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

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


# ---------------------------------------------------------------------------
# JWT auth — mirrors the auth service pattern
# ---------------------------------------------------------------------------

@lru_cache(maxsize=4)
def _jwks(pool_id: str) -> dict[str, Any]:
    url = f"https://cognito-idp.{region}.amazonaws.com/{pool_id}/.well-known/jwks.json"
    return http_requests.get(url, timeout=5).json()


def _decode_token(token: str) -> dict[str, Any]:
    headers = jwt.get_unverified_header(token)
    kid = headers.get("kid")
    for key in _jwks(ADMIN_POOL_ID).get("keys", []):
        if key.get("kid") == kid:
            try:
                return jwt.decode(
                    token, key, algorithms=["RS256"],
                    audience=ADMIN_CLIENT_ID,
                    issuer=f"https://cognito-idp.{region}.amazonaws.com/{ADMIN_POOL_ID}",
                )
            except JWTError as exc:
                raise HTTPException(status_code=401, detail=f"Invalid token: {exc}") from exc
    raise HTTPException(status_code=401, detail="Signing key not found")


def admin_required(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    return _decode_token(authorization.split(" ", 1)[1])


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class ProductIn(BaseModel):
    id: str
    name: str
    description: str = ""
    category: str
    image_url: str = ""
    price: float
    stock: int = 0


class ProductUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    category: str | None = None
    image_url: str | None = None
    price: float | None = None
    stock: int | None = None


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "admin"}


@app.get("/ready")
def ready() -> dict:
    try:
        with _db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return {"ready": True, "service": "admin"}
    except Exception:
        return {"ready": False, "service": "admin"}


# ---------------------------------------------------------------------------
# Dashboard HTML
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
def dashboard() -> str:
    return _ADMIN_HTML


# ---------------------------------------------------------------------------
# Product CRUD  (all require admin JWT)
# ---------------------------------------------------------------------------

@app.get("/api/admin/products")
def list_products(_: dict = Depends(admin_required)) -> dict:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, description, category, image_url, price, stock, created_at, updated_at "
                "FROM products ORDER BY name"
            )
            cols = ("id", "name", "description", "category", "image_url", "price", "stock", "created_at", "updated_at")
            products = []
            for row in cur.fetchall():
                p = dict(zip(cols, row))
                p["price"] = float(p["price"])
                p["created_at"] = p["created_at"].isoformat() if p["created_at"] else None
                p["updated_at"] = p["updated_at"].isoformat() if p["updated_at"] else None
                products.append(p)
    return {"products": products, "count": len(products)}


@app.post("/api/admin/products", status_code=201)
def create_product(product: ProductIn, _: dict = Depends(admin_required)) -> dict:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO products (id, name, description, category, image_url, price, stock) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                (product.id, product.name, product.description, product.category,
                 product.image_url, product.price, product.stock),
            )
    return {"created": product.id}


@app.put("/api/admin/products/{product_id}")
def update_product(product_id: str, body: ProductUpdate, _: dict = Depends(admin_required)) -> dict:
    fields = {k: v for k, v in body.model_dump().items() if v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")
    sets = ", ".join(f"{k} = %s" for k in fields)
    vals = list(fields.values()) + [product_id]
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE products SET {sets}, updated_at = NOW() WHERE id = %s", vals)
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Product not found")
    return {"updated": product_id}


@app.delete("/api/admin/products/{product_id}")
def delete_product(product_id: str, _: dict = Depends(admin_required)) -> dict:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM products WHERE id = %s", (product_id,))
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Product not found")
    return {"deleted": product_id}


# ---------------------------------------------------------------------------
# Order management (read-only for admins)
# ---------------------------------------------------------------------------

@app.get("/api/admin/orders")
def list_orders(
    _: dict = Depends(admin_required),
    limit: int = Query(default=50, ge=1, le=200),
) -> dict:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, customer_email, total, currency, status, transaction_id, created_at "
                "FROM orders ORDER BY created_at DESC LIMIT %s",
                (limit,),
            )
            cols = ("id", "customer_email", "total", "currency", "status", "transaction_id", "created_at")
            orders = []
            for row in cur.fetchall():
                o = dict(zip(cols, row))
                o["total"] = float(o["total"])
                o["created_at"] = o["created_at"].isoformat() if o["created_at"] else None
                orders.append(o)
    return {"orders": orders, "count": len(orders)}


@app.get("/api/admin/orders/{order_id}")
def get_order(order_id: str, _: dict = Depends(admin_required)) -> dict:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, customer_email, total, currency, status, transaction_id, created_at "
                "FROM orders WHERE id = %s",
                (order_id,),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Order not found")
            cols = ("id", "customer_email", "total", "currency", "status", "transaction_id", "created_at")
            order = dict(zip(cols, row))
            order["total"] = float(order["total"])
            order["created_at"] = order["created_at"].isoformat() if order["created_at"] else None

            cur.execute(
                "SELECT product_id, product_name, quantity, unit_price FROM order_items WHERE order_id = %s",
                (order_id,),
            )
            order["items"] = [
                {"product_id": r[0], "product_name": r[1], "quantity": r[2], "unit_price": float(r[3])}
                for r in cur.fetchall()
            ]
    return order


# ---------------------------------------------------------------------------
# Admin dashboard HTML
# ---------------------------------------------------------------------------

_ADMIN_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<meta name="theme-color" content="#0B0E14"/>
<title>ShopCloud — Admin</title>
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Outfit:wght@300;400;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root {
  --bg-base: #0B0E14;
  --bg-surface: #121620;
  --bg-glass: rgba(18, 22, 32, 0.65);
  --bg-glass-card: rgba(255, 255, 255, 0.03);
  --text-main: #FFFFFF;
  --text-muted: #94A3B8;
  --accent-cyan: #06B6D4;
  --accent-cyan-d: #0891B2;
  --accent-purple: #8B5CF6;
  --border-light: rgba(255, 255, 255, 0.08);
  --border-hover: rgba(6, 182, 212, 0.4);
  --shadow-glow: 0 0 24px rgba(6, 182, 212, 0.25);
  --shadow-glow-purple: 0 0 24px rgba(139, 92, 246, 0.25);
  --font-body: 'Inter', system-ui, sans-serif;
  --font-display: 'Outfit', system-ui, sans-serif;
  --radius: 20px;
  --radius-sm: 12px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html { scroll-behavior: smooth; }
body {
  font-family: var(--font-body);
  background: var(--bg-base);
  color: var(--text-main);
  min-height: 100vh;
  line-height: 1.6;
  overflow-x: hidden;
  position: relative;
}
.orb {
  position: fixed; border-radius: 50%; filter: blur(120px); opacity: 0.35; z-index: -1;
  pointer-events: none; animation: float 14s infinite alternate ease-in-out;
}
.orb.purple { background: var(--accent-purple); width: 500px; height: 500px; top: -150px; left: -100px; animation-delay: -2s; }
.orb.cyan { background: var(--accent-cyan); width: 400px; height: 400px; bottom: -100px; right: -50px; }
@keyframes float { 0% { transform: translate(0, 0) scale(1); } 100% { transform: translate(30px, 40px) scale(1.1); } }

.hdr-wrap { position: sticky; top: 0; z-index: 50; padding: 16px 24px 0; }
.hdr {
  max-width: 1200px; margin: 0 auto; display: flex; align-items: center; gap: 20px; flex-wrap: wrap;
  padding: 12px 24px; background: var(--bg-glass);
  backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
  border: 1px solid var(--border-light); border-radius: var(--radius);
  box-shadow: 0 8px 32px rgba(0,0,0,0.4);
}
.hdr-brand { display: flex; flex-direction: column; gap: 2px; }
.hdr .logo { font-family: var(--font-display); font-size: 1.5rem; font-weight: 800; color: #FFF; letter-spacing: -0.02em; }
.hdr .logo span { background: linear-gradient(135deg, var(--accent-cyan), var(--accent-purple)); -webkit-background-clip: text; color: transparent; }
.hdr .tag { font-size: 0.72rem; color: var(--text-muted); font-weight: 600; letter-spacing: 0.1em; text-transform: uppercase; }
.hdr .spacer { flex: 1; min-width: 8px; }
.hdr-actions { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
#loginSection { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
#tokenInput {
  width: min(320px, 70vw);
  padding: 10px 16px; background: rgba(0,0,0,0.2);
  border: 1px solid var(--border-light); border-radius: 999px;
  color: var(--text-main); font-family: var(--font-body); font-size: 0.88rem;
  transition: all 0.3s ease;
}
#tokenInput::placeholder { color: var(--text-muted); }
#tokenInput:focus { outline: none; border-color: var(--accent-cyan); box-shadow: var(--shadow-glow); background: rgba(0,0,0,0.35); }
#authStatus { font-size: 0.82rem; color: var(--text-muted); max-width: 200px; }

.btn {
  padding: 10px 18px; border-radius: 999px; border: none; cursor: pointer;
  font-family: var(--font-display); font-size: 0.88rem; font-weight: 600; transition: all 0.25s;
}
.btn-primary {
  background: linear-gradient(135deg, var(--accent-cyan), #0284C7); color: #FFF;
  box-shadow: 0 4px 15px rgba(6, 182, 212, 0.3);
}
.btn-primary:hover { filter: brightness(1.08); transform: translateY(-2px); box-shadow: 0 6px 20px rgba(6, 182, 212, 0.45); }
.btn-ghost { background: transparent; border: 1px solid var(--border-light); color: var(--text-main); box-shadow: none; }
.btn-ghost:hover { background: rgba(255,255,255,0.06); border-color: var(--text-muted); }
.btn-danger {
  background: linear-gradient(135deg, #DC2626, #991B1B); color: #FFF;
  box-shadow: 0 4px 14px rgba(220, 38, 38, 0.3);
}
.btn-danger:hover { filter: brightness(1.08); transform: translateY(-1px); }
.btn-sm { padding: 7px 14px; font-size: 0.8rem; }

.wrap { max-width: 1200px; margin: 0 auto; padding: 28px 24px 80px; }

#msgBox { margin-bottom: 20px; }
.msg { padding: 14px 18px; border-radius: var(--radius-sm); font-size: 0.92rem; font-weight: 500; border: 1px solid transparent; }
.msg-err { background: rgba(239, 68, 68, 0.1); color: #FCA5A5; border-color: rgba(239, 68, 68, 0.25); }
.msg-ok { background: rgba(16, 185, 129, 0.1); color: #6EE7B7; border-color: rgba(16, 185, 129, 0.22); }

.stat-row { display: flex; gap: 20px; margin-bottom: 28px; flex-wrap: wrap; }
.stat {
  flex: 1; min-width: 160px;
  background: var(--bg-surface); border: 1px solid var(--border-light); border-radius: var(--radius);
  padding: 22px 24px; position: relative; overflow: hidden;
  transition: transform 0.25s, box-shadow 0.25s;
}
.stat::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
  background: linear-gradient(90deg, var(--accent-cyan), var(--accent-purple)); opacity: 0.85; }
.stat:hover { transform: translateY(-4px); box-shadow: 0 16px 40px rgba(0,0,0,0.45), var(--shadow-glow); }
.stat .val { font-family: var(--font-display); font-size: 2rem; font-weight: 800; color: #FFF; letter-spacing: -0.02em; }
.stat .lbl { font-size: 0.78rem; color: var(--text-muted); margin-top: 6px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; }

.tabs { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 24px; }
.tab {
  padding: 10px 22px; border-radius: 999px; border: 1px solid var(--border-light);
  background: var(--bg-glass-card); color: var(--text-muted); font-family: var(--font-display);
  font-size: 0.92rem; font-weight: 600; cursor: pointer; transition: all 0.3s;
  backdrop-filter: blur(10px);
}
.tab:hover { border-color: var(--accent-purple); color: #FFF; background: rgba(139, 92, 246, 0.12); box-shadow: var(--shadow-glow-purple); }
.tab.active {
  background: linear-gradient(135deg, var(--accent-purple), #6D28D9); color: #FFF;
  border-color: transparent; box-shadow: var(--shadow-glow-purple);
}

.table-wrap {
  background: var(--bg-surface); border: 1px solid var(--border-light); border-radius: var(--radius);
  overflow: hidden; box-shadow: 0 12px 40px rgba(0,0,0,0.35);
}
.table-scroll { overflow-x: auto; }
.toolbar-row { margin-bottom: 16px; display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }

table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
th {
  text-align: left; padding: 14px 18px; background: rgba(0,0,0,0.35);
  color: var(--text-muted); border-bottom: 1px solid var(--border-light);
  font-weight: 700; font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.06em;
}
td { padding: 14px 18px; border-bottom: 1px solid rgba(255,255,255,0.04); color: #E2E8F0; }
tbody tr { transition: background 0.2s; }
tbody tr:hover { background: rgba(6, 182, 212, 0.06); }
tbody tr:last-child td { border-bottom: none; }

.badge { display: inline-block; padding: 4px 10px; border-radius: 999px; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.02em; }
.badge-ok { background: rgba(16, 185, 129, 0.15); color: #6EE7B7; border: 1px solid rgba(16, 185, 129, 0.3); }
.badge-warn { background: rgba(245, 158, 11, 0.12); color: #FBBF24; border: 1px solid rgba(245, 158, 11, 0.28); }

.hidden { display: none !important; }

.modal-bg {
  position: fixed; inset: 0; background: rgba(0,0,0,0.7); backdrop-filter: blur(10px);
  display: flex; align-items: center; justify-content: center; z-index: 200; padding: 20px;
  animation: fadeIn 0.25s ease;
}
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
.modal {
  background: var(--bg-surface); border-radius: var(--radius); padding: 36px; width: 500px; max-width: 100%;
  border: 1px solid var(--border-light); box-shadow: 0 24px 48px rgba(0,0,0,0.8), inset 0 1px 0 rgba(255,255,255,0.06);
  position: relative; overflow: hidden; animation: slideUp 0.35s cubic-bezier(0.16, 1, 0.3, 1);
}
.modal::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px;
  background: linear-gradient(90deg, var(--accent-cyan), var(--accent-purple)); }
@keyframes slideUp { from { opacity: 0; transform: translateY(28px) scale(0.97); } to { opacity: 1; transform: translateY(0) scale(1); } }
.modal h2 { font-family: var(--font-display); font-size: 1.5rem; margin-bottom: 22px; color: #FFF; font-weight: 800; }
.field { margin-bottom: 18px; }
.field label {
  display: block; font-size: 0.78rem; color: var(--text-muted); margin-bottom: 8px;
  font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em;
}
.field input, .field select {
  width: 100%; padding: 12px 14px; border: 1px solid rgba(255,255,255,0.1); border-radius: var(--radius-sm);
  font-size: 0.95rem; background: rgba(0,0,0,0.35); color: #FFF; transition: all 0.25s; font-family: var(--font-body);
}
.field input:focus, .field select:focus {
  outline: none; border-color: var(--accent-cyan); background: rgba(0,0,0,0.5);
  box-shadow: 0 0 0 4px rgba(6, 182, 212, 0.12);
}
.modal .btn-row { display: flex; gap: 10px; justify-content: flex-end; margin-top: 26px; flex-wrap: wrap; }
</style>
</head>
<body>

<div class="orb purple"></div>
<div class="orb cyan"></div>

<div class="hdr-wrap">
<header class="hdr">
  <div class="hdr-brand">
    <div class="logo">Shop<span>Cloud</span></div>
    <span class="tag">Operations console</span>
  </div>
  <div class="spacer" aria-hidden="true"></div>
  <div class="hdr-actions">
    <div id="loginSection">
      <input id="tokenInput" type="password" placeholder="Admin JWT…" autocomplete="off"/>
      <button type="button" class="btn btn-primary" onclick="setToken()">Authenticate</button>
    </div>
    <span id="authStatus"></span>
  </div>
</header>
</div>

<div class="wrap">
  <div id="msgBox"></div>
  <div class="stat-row">
    <div class="stat"><div class="val" id="statProducts">—</div><div class="lbl">Products</div></div>
    <div class="stat"><div class="val" id="statOrders">—</div><div class="lbl">Orders</div></div>
    <div class="stat"><div class="val" id="statRevenue">—</div><div class="lbl">Revenue</div></div>
  </div>
  <div class="tabs">
    <div class="tab active" onclick="switchTab('products')">Products</div>
    <div class="tab" onclick="switchTab('orders')">Orders</div>
  </div>
  <div id="productsTab"></div>
  <div id="ordersTab" class="hidden"></div>
</div>
<div id="modalRoot"></div>
<script>
let TOKEN = localStorage.getItem('admin_token') || '';
const API = '/api/admin';

function hdr(){ return {Authorization:'Bearer '+TOKEN,'Content-Type':'application/json'} }

function setToken(){
  TOKEN = document.getElementById('tokenInput').value.trim();
  localStorage.setItem('admin_token', TOKEN);
  load();
}

function msg(text, ok){
  const b = document.getElementById('msgBox');
  b.innerHTML = '<div class="msg '+(ok?'msg-ok':'msg-err')+'">'+text+'</div>';
  setTimeout(()=>b.innerHTML='', 4000);
}

async function api(path, opts={}){
  const r = await fetch(API+path, {headers:hdr(),...opts});
  if(r.status===401){msg('Unauthorized — paste a valid admin JWT',false);throw new Error('401')}
  if(!r.ok){const e=await r.json().catch(()=>({}));msg(e.detail||r.statusText,false);throw new Error(r.status)}
  return r.json();
}

function switchTab(t){
  document.querySelectorAll('.tab').forEach((el,i)=>el.classList.toggle('active',el.textContent.toLowerCase()===t));
  document.getElementById('productsTab').classList.toggle('hidden',t!=='products');
  document.getElementById('ordersTab').classList.toggle('hidden',t!=='orders');
}

async function loadProducts(){
  try{
    const d = await api('/products');
    document.getElementById('statProducts').textContent = d.count;
    let h='<div class="toolbar-row"><button type="button" class="btn btn-primary" onclick="showAddProduct()">+ Add product</button></div>';
    h+='<div class="table-wrap"><div class="table-scroll"><table><thead><tr><th>ID</th><th>Name</th><th>Category</th><th>Price</th><th>Stock</th><th>Actions</th></tr></thead><tbody>';
    d.products.forEach(p=>{
      const sc = p.stock < 10 ? 'badge-warn' : 'badge-ok';
      h+=`<tr><td><code style="font-size:0.85em;opacity:.9">${p.id}</code></td><td>${p.name}</td><td>${p.category}</td><td>$${Number(p.price).toFixed(2)}</td>`;
      h+=`<td><span class="badge ${sc}">${p.stock}</span></td>`;
      h+=`<td><button type="button" class="btn btn-sm btn-primary" onclick="showEditProduct('${p.id}')">Edit</button> `;
      h+=`<button type="button" class="btn btn-sm btn-danger" onclick="delProduct('${p.id}')">Delete</button></td></tr>`;
    });
    h+='</tbody></table></div></div>';
    document.getElementById('productsTab').innerHTML=h;
  }catch(e){}
}

async function loadOrders(){
  try{
    const d = await api('/orders?limit=100');
    document.getElementById('statOrders').textContent = d.count;
    const rev = d.orders.reduce((s,o)=>s+o.total,0);
    document.getElementById('statRevenue').textContent = '$'+rev.toFixed(2);
    let h='<div class="table-wrap"><div class="table-scroll"><table><thead><tr><th>Order ID</th><th>Email</th><th>Total</th><th>Status</th><th>Date</th></tr></thead><tbody>';
    d.orders.forEach(o=>{
      h+=`<tr><td><code style="font-size:0.85em;opacity:.9">${o.id}</code></td><td>${o.customer_email}</td><td>$${Number(o.total).toFixed(2)}</td>`;
      h+=`<td><span class="badge badge-ok">${o.status}</span></td>`;
      h+=`<td>${o.created_at?new Date(o.created_at).toLocaleString():'—'}</td></tr>`;
    });
    h+='</tbody></table></div></div>';
    document.getElementById('ordersTab').innerHTML=h;
  }catch(e){}
}

function load(){ loadProducts(); loadOrders(); }

function closeModal(){ document.getElementById('modalRoot').innerHTML=''; }

function showAddProduct(){
  document.getElementById('modalRoot').innerHTML=`
  <div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">
    <h2>Add Product</h2>
    <div class="field"><label>ID</label><input id="pId"/></div>
    <div class="field"><label>Name</label><input id="pName"/></div>
    <div class="field"><label>Description</label><input id="pDesc"/></div>
    <div class="field"><label>Category</label><input id="pCat"/></div>
    <div class="field"><label>Image URL</label><input id="pImg"/></div>
    <div class="field"><label>Price</label><input id="pPrice" type="number" step="0.01"/></div>
    <div class="field"><label>Stock</label><input id="pStock" type="number"/></div>
    <div class="btn-row">
      <button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      <button type="button" class="btn btn-primary" onclick="addProduct()">Create</button>
    </div>
  </div></div>`;
}

async function addProduct(){
  const body={id:pId.value,name:pName.value,description:pDesc.value,category:pCat.value,
    image_url:pImg.value,price:parseFloat(pPrice.value),stock:parseInt(pStock.value)||0};
  await api('/products',{method:'POST',body:JSON.stringify(body)});
  closeModal(); msg('Product created',true); loadProducts();
}

let _editCache={};
async function showEditProduct(id){
  const d = await api('/products');
  const p = d.products.find(x=>x.id===id); if(!p)return;
  _editCache=p;
  document.getElementById('modalRoot').innerHTML=`
  <div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">
    <h2>Edit: ${p.name}</h2>
    <div class="field"><label>Name</label><input id="eName" value="${p.name}"/></div>
    <div class="field"><label>Description</label><input id="eDesc" value="${p.description||''}"/></div>
    <div class="field"><label>Category</label><input id="eCat" value="${p.category}"/></div>
    <div class="field"><label>Image URL</label><input id="eImg" value="${p.image_url||''}"/></div>
    <div class="field"><label>Price</label><input id="ePrice" type="number" step="0.01" value="${p.price}"/></div>
    <div class="field"><label>Stock</label><input id="eStock" type="number" value="${p.stock}"/></div>
    <div class="btn-row">
      <button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      <button type="button" class="btn btn-primary" onclick="editProduct('${id}')">Save</button>
    </div>
  </div></div>`;
}

async function editProduct(id){
  const body={name:eName.value,description:eDesc.value,category:eCat.value,
    image_url:eImg.value,price:parseFloat(ePrice.value),stock:parseInt(eStock.value)||0};
  await api('/products/'+id,{method:'PUT',body:JSON.stringify(body)});
  closeModal(); msg('Product updated',true); loadProducts();
}

async function delProduct(id){
  if(!confirm('Delete product '+id+'?'))return;
  await api('/products/'+id,{method:'DELETE'});
  msg('Product deleted',true); loadProducts();
}

if(TOKEN) load();
document.getElementById('authStatus').textContent = TOKEN ? 'Authenticated' : 'Not authenticated';
</script>
</body>
</html>"""
