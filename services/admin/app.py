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

_ADMIN_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>ShopCloud Admin</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#e2e8f0}
.top{background:#1e293b;padding:16px 24px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #334155}
.top h1{font-size:20px;color:#38bdf8}
.top .actions{display:flex;gap:8px}
#loginSection input{background:#0f172a;border:1px solid #475569;color:#e2e8f0;padding:6px 10px;border-radius:6px;font-size:13px}
.wrap{max-width:1200px;margin:0 auto;padding:24px}
.tabs{display:flex;gap:8px;margin-bottom:20px}
.tab{padding:8px 16px;border-radius:8px;cursor:pointer;border:1px solid #334155;background:#1e293b;color:#94a3b8;font-size:14px}
.tab.active{background:#0ea5e9;color:#fff;border-color:#0ea5e9}
table{width:100%;border-collapse:collapse;font-size:14px}
th{text-align:left;padding:10px;background:#1e293b;color:#94a3b8;border-bottom:1px solid #334155;font-weight:600}
td{padding:10px;border-bottom:1px solid #1e293b}
tr:hover{background:#1e293b}
.badge{display:inline-block;padding:2px 8px;border-radius:9999px;font-size:12px;font-weight:600}
.badge-ok{background:#065f46;color:#6ee7b7}
.badge-warn{background:#78350f;color:#fbbf24}
.btn{padding:6px 14px;border-radius:6px;border:none;cursor:pointer;font-size:13px;font-weight:600}
.btn-primary{background:#0ea5e9;color:#fff}
.btn-danger{background:#dc2626;color:#fff}
.btn-sm{padding:4px 10px;font-size:12px}
.modal-bg{position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:100}
.modal{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:24px;width:480px;max-width:95vw}
.modal h2{margin-bottom:16px;color:#38bdf8;font-size:18px}
.field{margin-bottom:12px}
.field label{display:block;font-size:13px;color:#94a3b8;margin-bottom:4px}
.field input,.field select{width:100%;padding:8px;background:#0f172a;border:1px solid #475569;border-radius:6px;color:#e2e8f0;font-size:14px}
.msg{padding:12px;border-radius:8px;margin-bottom:16px;font-size:14px}
.msg-err{background:#450a0a;color:#fca5a5;border:1px solid #7f1d1d}
.msg-ok{background:#052e16;color:#86efac;border:1px solid #166534}
.hidden{display:none}
.stat-row{display:flex;gap:16px;margin-bottom:24px}
.stat{flex:1;background:#1e293b;border:1px solid #334155;border-radius:10px;padding:16px}
.stat .val{font-size:28px;font-weight:700;color:#38bdf8}
.stat .lbl{font-size:13px;color:#94a3b8;margin-top:4px}
</style>
</head>
<body>
<div class="top">
  <h1>ShopCloud Admin</h1>
  <div class="actions">
    <div id="loginSection">
      <input id="tokenInput" type="password" placeholder="Paste admin JWT..." style="width:300px"/>
      <button class="btn btn-primary" onclick="setToken()">Authenticate</button>
    </div>
    <span id="authStatus" style="color:#94a3b8;font-size:13px"></span>
  </div>
</div>
<div class="wrap">
  <div id="msgBox"></div>
  <div class="stat-row">
    <div class="stat"><div class="val" id="statProducts">-</div><div class="lbl">Products</div></div>
    <div class="stat"><div class="val" id="statOrders">-</div><div class="lbl">Orders</div></div>
    <div class="stat"><div class="val" id="statRevenue">-</div><div class="lbl">Revenue</div></div>
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
    let h='<div style="margin-bottom:12px"><button class="btn btn-primary" onclick="showAddProduct()">+ Add Product</button></div>';
    h+='<table><tr><th>ID</th><th>Name</th><th>Category</th><th>Price</th><th>Stock</th><th>Actions</th></tr>';
    d.products.forEach(p=>{
      const sc = p.stock < 10 ? 'badge-warn' : 'badge-ok';
      h+=`<tr><td>${p.id}</td><td>${p.name}</td><td>${p.category}</td><td>$${Number(p.price).toFixed(2)}</td>`;
      h+=`<td><span class="badge ${sc}">${p.stock}</span></td>`;
      h+=`<td><button class="btn btn-sm btn-primary" onclick="showEditProduct('${p.id}')">Edit</button> `;
      h+=`<button class="btn btn-sm btn-danger" onclick="delProduct('${p.id}')">Del</button></td></tr>`;
    });
    h+='</table>';
    document.getElementById('productsTab').innerHTML=h;
  }catch(e){}
}

async function loadOrders(){
  try{
    const d = await api('/orders?limit=100');
    document.getElementById('statOrders').textContent = d.count;
    const rev = d.orders.reduce((s,o)=>s+o.total,0);
    document.getElementById('statRevenue').textContent = '$'+rev.toFixed(2);
    let h='<table><tr><th>Order ID</th><th>Email</th><th>Total</th><th>Status</th><th>Date</th></tr>';
    d.orders.forEach(o=>{
      h+=`<tr><td>${o.id}</td><td>${o.customer_email}</td><td>$${Number(o.total).toFixed(2)}</td>`;
      h+=`<td><span class="badge badge-ok">${o.status}</span></td>`;
      h+=`<td>${o.created_at?new Date(o.created_at).toLocaleString():'-'}</td></tr>`;
    });
    h+='</table>';
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
    <div style="display:flex;gap:8px;justify-content:flex-end">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" onclick="addProduct()">Create</button>
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
    <div style="display:flex;gap:8px;justify-content:flex-end">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" onclick="editProduct('${id}')">Save</button>
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
