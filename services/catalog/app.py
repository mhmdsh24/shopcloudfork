"""Catalog service — products, categories, search backed by PostgreSQL."""
from __future__ import annotations

import logging
import os
import time
from contextlib import contextmanager
from typing import Any

import psycopg2
import psycopg2.pool
from fastapi import FastAPI, Query
from fastapi.responses import HTMLResponse

app = FastAPI(title="shopcloud-catalog")
log = logging.getLogger("catalog")

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "shopcloud")
DB_USER = os.environ.get("DB_USER", "shopcloud_admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

_pool: psycopg2.pool.SimpleConnectionPool | None = None

SEED_PRODUCTS = [
    ("sku-1001", "ShopCloud Hoodie", "Fleece hoodie for cloud builders.", "apparel",
     "https://cdn.shopcloud.com/images/sku-1001.jpg", 49.00, 42),
    ("sku-1002", "Kubernetes Field Notebook", "Pocket notebook for architecture sketches.", "stationery",
     "https://cdn.shopcloud.com/images/sku-1002.jpg", 12.50, 128),
    ("sku-1003", "Infrastructure Mug", "Ceramic mug for long apply sessions.", "accessories",
     "https://cdn.shopcloud.com/images/sku-1003.jpg", 16.00, 67),
]


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
                CREATE TABLE IF NOT EXISTS products (
                    id          VARCHAR(20) PRIMARY KEY,
                    name        VARCHAR(255) NOT NULL,
                    description TEXT,
                    category    VARCHAR(100) NOT NULL,
                    image_url   VARCHAR(500),
                    price       NUMERIC(10,2) NOT NULL,
                    stock       INTEGER NOT NULL DEFAULT 0,
                    created_at  TIMESTAMPTZ DEFAULT NOW(),
                    updated_at  TIMESTAMPTZ DEFAULT NOW()
                )
            """)
            cur.execute("SELECT count(*) FROM products")
            if cur.fetchone()[0] == 0:
                cur.executemany(
                    "INSERT INTO products (id, name, description, category, image_url, price, stock) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    SEED_PRODUCTS,
                )
                log.info("Seeded %d products", len(SEED_PRODUCTS))


@app.on_event("startup")
def startup() -> None:
    _init_schema()


def _row_to_dict(row, columns) -> dict[str, Any]:
    d = dict(zip(columns, row))
    d["price"] = float(d["price"])
    return d


_PRODUCT_COLS = ("id", "name", "description", "category", "image_url", "price", "stock")


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "catalog"}


@app.get("/ready")
def ready() -> dict[str, Any]:
    try:
        with _db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT count(*) FROM products")
                cnt = cur.fetchone()[0]
        return {"ready": True, "service": "catalog", "products": cnt}
    except Exception:
        return {"ready": False, "service": "catalog"}


@app.get("/", response_class=HTMLResponse)
def storefront() -> str:
    return _STOREFRONT_HTML


@app.get("/api/catalog/products")
def list_products(category: str | None = Query(default=None)) -> dict[str, Any]:
    with _db() as conn:
        with conn.cursor() as cur:
            if category:
                cur.execute(
                    "SELECT id, name, description, category, image_url, price, stock "
                    "FROM products WHERE category = %s ORDER BY name", (category,)
                )
            else:
                cur.execute(
                    "SELECT id, name, description, category, image_url, price, stock "
                    "FROM products ORDER BY name"
                )
            rows = cur.fetchall()
    items = [_row_to_dict(r, _PRODUCT_COLS) for r in rows]
    return {"products": items, "count": len(items), "region": os.environ.get("AWS_REGION", "unknown")}


@app.get("/api/catalog/categories")
def list_categories() -> dict[str, list[str]]:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT DISTINCT category FROM products ORDER BY category")
            categories = [r[0] for r in cur.fetchall()]
    return {"categories": categories}


@app.get("/api/catalog/search")
def search_products(q: str = Query(min_length=1)) -> dict[str, Any]:
    needle = f"%{q.lower().strip()}%"
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, description, category, image_url, price, stock "
                "FROM products WHERE LOWER(name) LIKE %s OR LOWER(description) LIKE %s "
                "OR LOWER(category) LIKE %s ORDER BY name",
                (needle, needle, needle),
            )
            rows = cur.fetchall()
    items = [_row_to_dict(r, _PRODUCT_COLS) for r in rows]
    return {"query": q, "results": items, "count": len(items)}


@app.get("/api/catalog/products/{product_id}")
def get_product(product_id: str) -> dict[str, Any]:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, description, category, image_url, price, stock "
                "FROM products WHERE id = %s", (product_id,)
            )
            row = cur.fetchone()
    if not row:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Product not found")
    return _row_to_dict(row, _PRODUCT_COLS)


# ---------------------------------------------------------------------------
# Storefront HTML — full single-page shop with cart, checkout, auth
# ---------------------------------------------------------------------------
_STOREFRONT_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>ShopCloud</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,BlinkMacSystemFont,sans-serif;background:#f8fafc;color:#1e293b}
a{color:#0ea5e9;text-decoration:none}

/* --- Header --- */
.hdr{background:#fff;border-bottom:1px solid #e2e8f0;padding:0 24px;display:flex;align-items:center;height:60px;position:sticky;top:0;z-index:50}
.hdr .logo{font-size:20px;font-weight:800;color:#0f172a;letter-spacing:-.5px}
.hdr .logo span{color:#0ea5e9}
.hdr .spacer{flex:1}
.hdr .search{width:280px;padding:8px 14px;border:1px solid #e2e8f0;border-radius:8px;font-size:14px;background:#f8fafc}
.hdr .search:focus{outline:none;border-color:#0ea5e9}
.hdr-actions{display:flex;align-items:center;gap:12px;margin-left:16px}
.cart-btn{position:relative;background:none;border:none;cursor:pointer;font-size:22px;padding:6px}
.cart-btn .count{position:absolute;top:-2px;right:-6px;background:#ef4444;color:#fff;font-size:10px;font-weight:700;border-radius:9999px;min-width:18px;height:18px;display:flex;align-items:center;justify-content:center}
.auth-btn{padding:6px 14px;border-radius:8px;border:1px solid #e2e8f0;background:#fff;cursor:pointer;font-size:13px;font-weight:600;color:#334155}
.auth-btn:hover{background:#f1f5f9}
.user-badge{font-size:13px;color:#64748b}

/* --- Toolbar --- */
.toolbar{max-width:1100px;margin:20px auto 0;padding:0 24px;display:flex;gap:10px;flex-wrap:wrap}
.toolbar select{padding:8px 12px;border:1px solid #e2e8f0;border-radius:8px;font-size:14px;background:#fff}

/* --- Grid --- */
.wrap{max-width:1100px;margin:0 auto;padding:20px 24px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}
.card{background:#fff;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden;transition:box-shadow .2s}
.card:hover{box-shadow:0 4px 12px rgba(0,0,0,.08)}
.card .img{width:100%;height:160px;background:#f1f5f9;display:flex;align-items:center;justify-content:center;color:#94a3b8;font-size:48px}
.card .body{padding:14px}
.card h3{font-size:15px;margin-bottom:4px}
.card .desc{font-size:13px;color:#64748b;margin-bottom:8px;line-height:1.4}
.card .row{display:flex;align-items:center;justify-content:space-between}
.card .price{font-size:18px;font-weight:700;color:#0f172a}
.card .stock{font-size:12px;color:#94a3b8}
.card .stock.low{color:#f59e0b}
.add-btn{padding:6px 14px;border-radius:8px;border:none;background:#0ea5e9;color:#fff;cursor:pointer;font-size:13px;font-weight:600;transition:background .2s}
.add-btn:hover{background:#0284c7}
.add-btn:disabled{background:#94a3b8;cursor:default}

/* --- Cart Drawer --- */
.drawer-bg{position:fixed;inset:0;background:rgba(0,0,0,.4);z-index:90;opacity:0;pointer-events:none;transition:opacity .25s}
.drawer-bg.open{opacity:1;pointer-events:auto}
.drawer{position:fixed;top:0;right:0;bottom:0;width:400px;max-width:90vw;background:#fff;z-index:91;transform:translateX(100%);transition:transform .25s;display:flex;flex-direction:column}
.drawer.open{transform:translateX(0)}
.drawer .dh{padding:16px 20px;border-bottom:1px solid #e2e8f0;display:flex;align-items:center;justify-content:space-between}
.drawer .dh h2{font-size:18px}
.drawer .close-btn{background:none;border:none;font-size:24px;cursor:pointer;color:#64748b}
.drawer .items{flex:1;overflow-y:auto;padding:16px 20px}
.drawer .empty{text-align:center;color:#94a3b8;padding:40px 0}
.ci{display:flex;gap:12px;padding:12px 0;border-bottom:1px solid #f1f5f9}
.ci .ci-info{flex:1}
.ci .ci-name{font-size:14px;font-weight:600}
.ci .ci-price{font-size:13px;color:#64748b}
.ci .ci-qty{display:flex;align-items:center;gap:8px;margin-top:6px}
.ci .ci-qty button{width:26px;height:26px;border-radius:6px;border:1px solid #e2e8f0;background:#fff;cursor:pointer;font-size:14px;display:flex;align-items:center;justify-content:center}
.ci .ci-qty span{font-size:14px;min-width:20px;text-align:center}
.ci .ci-remove{background:none;border:none;color:#ef4444;cursor:pointer;font-size:12px;margin-top:4px}
.drawer .footer{padding:16px 20px;border-top:1px solid #e2e8f0}
.drawer .total{display:flex;justify-content:space-between;font-size:16px;font-weight:700;margin-bottom:12px}
.checkout-btn{width:100%;padding:12px;border:none;border-radius:8px;background:#0ea5e9;color:#fff;font-size:15px;font-weight:700;cursor:pointer}
.checkout-btn:hover{background:#0284c7}

/* --- Modals --- */
.modal-bg{position:fixed;inset:0;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;z-index:100}
.modal{background:#fff;border-radius:12px;padding:28px;width:420px;max-width:92vw;box-shadow:0 20px 40px rgba(0,0,0,.15)}
.modal h2{font-size:20px;margin-bottom:16px;color:#0f172a}
.field{margin-bottom:14px}
.field label{display:block;font-size:13px;color:#64748b;margin-bottom:4px;font-weight:600}
.field input{width:100%;padding:10px 12px;border:1px solid #e2e8f0;border-radius:8px;font-size:14px}
.field input:focus{outline:none;border-color:#0ea5e9}
.btn-row{display:flex;gap:8px;justify-content:flex-end;margin-top:16px}
.btn{padding:10px 20px;border-radius:8px;border:none;cursor:pointer;font-size:14px;font-weight:600}
.btn-primary{background:#0ea5e9;color:#fff}
.btn-primary:hover{background:#0284c7}
.btn-ghost{background:transparent;color:#64748b;border:1px solid #e2e8f0}
.btn-link{background:none;border:none;color:#0ea5e9;cursor:pointer;font-size:13px;padding:0;font-weight:600}
.alert{padding:10px 14px;border-radius:8px;font-size:13px;margin-bottom:12px}
.alert-err{background:#fef2f2;color:#dc2626;border:1px solid #fecaca}
.alert-ok{background:#f0fdf4;color:#16a34a;border:1px solid #bbf7d0}

/* --- Order confirmation --- */
.confirm-box{max-width:520px;margin:40px auto;background:#fff;border-radius:12px;padding:32px;text-align:center;border:1px solid #e2e8f0}
.confirm-box .icon{font-size:48px;margin-bottom:12px}
.confirm-box h2{color:#16a34a;margin-bottom:8px}
.confirm-box .oid{font-size:13px;color:#64748b;margin-bottom:20px}
.confirm-box table{width:100%;text-align:left;margin:16px 0;font-size:14px}
.confirm-box th{color:#64748b;font-weight:600;padding:6px 0;border-bottom:1px solid #e2e8f0}
.confirm-box td{padding:6px 0;border-bottom:1px solid #f1f5f9}
.continue-btn{margin-top:20px;padding:10px 24px;border-radius:8px;border:none;background:#0ea5e9;color:#fff;cursor:pointer;font-size:14px;font-weight:600}
</style>
</head>
<body>

<!-- Header -->
<header class="hdr">
  <div class="logo">Shop<span>Cloud</span></div>
  <div class="spacer"></div>
  <input class="search" id="q" placeholder="Search products..." autocomplete="off"/>
  <div class="hdr-actions">
    <button class="cart-btn" onclick="openCart()" title="Cart">&#128722;<span class="count" id="cartCount">0</span></button>
    <span class="user-badge" id="userBadge"></span>
    <button class="auth-btn" id="authBtn" onclick="showLogin()">Sign In</button>
  </div>
</header>

<!-- Toolbar -->
<div class="toolbar">
  <select id="category"><option value="">All categories</option></select>
</div>

<!-- Products -->
<div class="wrap"><div class="grid" id="products"></div></div>

<!-- Cart Drawer Backdrop -->
<div class="drawer-bg" id="drawerBg" onclick="closeCart()"></div>
<!-- Cart Drawer -->
<div class="drawer" id="drawer">
  <div class="dh"><h2>Your Cart</h2><button class="close-btn" onclick="closeCart()">&times;</button></div>
  <div class="items" id="cartItems"></div>
  <div class="footer" id="cartFooter" style="display:none">
    <div class="total"><span>Total</span><span id="cartTotal">$0.00</span></div>
    <button class="checkout-btn" onclick="showCheckout()">Proceed to Checkout</button>
  </div>
</div>

<!-- Modal root -->
<div id="modalRoot"></div>

<script>
/* ---- State ---- */
let SID = localStorage.getItem('sc_sid');
if(!SID){SID=crypto.randomUUID();localStorage.setItem('sc_sid',SID)}
let AUTH = localStorage.getItem('sc_token')||'';
let USER_EMAIL = localStorage.getItem('sc_email')||'';
let cart = {items:[]};

/* ---- Helpers ---- */
function $(id){return document.getElementById(id)}
function authHdr(){return AUTH?{Authorization:'Bearer '+AUTH}:{}}
function escH(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}

/* ---- Products ---- */
async function loadCategories(){
  const r=await fetch('/api/catalog/categories');
  const d=await r.json();
  const el=$('category');
  el.innerHTML='<option value="">All categories</option>';
  d.categories.forEach(c=>{const o=document.createElement('option');o.value=c;o.textContent=c;el.appendChild(o)});
}

async function loadProducts(){
  const q=$('q').value.trim(), cat=$('category').value;
  let url='/api/catalog/products';
  if(q.length>0) url='/api/catalog/search?q='+encodeURIComponent(q);
  else if(cat) url='/api/catalog/products?category='+encodeURIComponent(cat);
  const r=await fetch(url);
  const d=await r.json();
  renderProducts(d.products||d.results||[]);
}

function renderProducts(list){
  $('products').innerHTML=list.map(p=>{
    const low=p.stock<10;
    const oos=p.stock<=0;
    return `<article class="card">
      <div class="img">\u{1F6D2}</div>
      <div class="body">
        <h3>${escH(p.name)}</h3>
        <p class="desc">${escH(p.description)}</p>
        <div class="row">
          <span class="price">$${Number(p.price).toFixed(2)}</span>
          <span class="stock${low?' low':''}">${oos?'Out of stock':p.stock+' in stock'}</span>
        </div>
        <div style="margin-top:10px;text-align:right">
          <button class="add-btn" ${oos?'disabled':''} onclick="addToCart('${escH(p.id)}','${escH(p.name)}',${p.price})">Add to Cart</button>
        </div>
      </div>
    </article>`;
  }).join('');
}

$('q').addEventListener('input',loadProducts);
$('category').addEventListener('change',loadProducts);

/* ---- Cart ---- */
async function loadCart(){
  try{
    const r=await fetch('/api/cart?session_id='+SID);
    cart=await r.json();
  }catch(e){cart={items:[]};}
  updateCartBadge();
}

function updateCartBadge(){
  const n=(cart.items||[]).reduce((s,i)=>s+i.quantity,0);
  $('cartCount').textContent=n;
  $('cartCount').style.display=n?'flex':'none';
}

async function addToCart(pid,name,price){
  await fetch('/api/cart/add',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({session_id:SID,product_id:pid,quantity:1,unit_price:price})});
  await loadCart();
  openCart();
}

function openCart(){
  renderCart();
  $('drawerBg').classList.add('open');
  $('drawer').classList.add('open');
}

function closeCart(){
  $('drawerBg').classList.remove('open');
  $('drawer').classList.remove('open');
}

function renderCart(){
  const items=cart.items||[];
  if(!items.length){
    $('cartItems').innerHTML='<div class="empty">Your cart is empty</div>';
    $('cartFooter').style.display='none';
    return;
  }
  let total=0;
  $('cartItems').innerHTML=items.map((it,i)=>{
    const sub=it.quantity*it.unit_price; total+=sub;
    return `<div class="ci">
      <div class="ci-info">
        <div class="ci-name">${escH(it.product_id)}</div>
        <div class="ci-price">$${it.unit_price.toFixed(2)} each</div>
        <div class="ci-qty">
          <button onclick="changeQty(${i},-1)">&minus;</button>
          <span>${it.quantity}</span>
          <button onclick="changeQty(${i},1)">+</button>
        </div>
        <button class="ci-remove" onclick="removeItem(${i})">Remove</button>
      </div>
      <div style="font-weight:600;white-space:nowrap">$${sub.toFixed(2)}</div>
    </div>`;
  }).join('');
  $('cartTotal').textContent='$'+total.toFixed(2);
  $('cartFooter').style.display='block';
}

async function changeQty(idx,delta){
  const it=cart.items[idx]; if(!it)return;
  const nq=it.quantity+delta;
  if(nq<=0){removeItem(idx);return;}
  cart.items[idx].quantity=nq;
  await fetch('/api/cart/'+SID+'/items',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({product_id:it.product_id,quantity:delta,unit_price:it.unit_price})});
  await loadCart(); renderCart();
}

async function removeItem(idx){
  cart.items.splice(idx,1);
  const full={session_id:SID,items:cart.items};
  await fetch('/api/cart/'+SID,{method:'DELETE'});
  for(const it of cart.items){
    await fetch('/api/cart/add',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({session_id:SID,product_id:it.product_id,quantity:it.quantity,unit_price:it.unit_price})});
  }
  await loadCart(); renderCart();
}

/* ---- Auth ---- */
function updateAuthUI(){
  if(AUTH){
    $('authBtn').textContent='Sign Out';
    $('authBtn').onclick=logout;
    $('userBadge').textContent=USER_EMAIL;
  }else{
    $('authBtn').textContent='Sign In';
    $('authBtn').onclick=showLogin;
    $('userBadge').textContent='';
  }
}

function showLogin(){
  $('modalRoot').innerHTML=`<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">
    <h2>Sign In</h2>
    <div id="authAlert"></div>
    <div class="field"><label>Email</label><input id="lEmail" type="email"/></div>
    <div class="field"><label>Password</label><input id="lPass" type="password"/></div>
    <div class="btn-row">
      <button class="btn-link" onclick="showSignup()">Create account</button>
      <div style="flex:1"></div>
      <button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" onclick="doLogin()">Sign In</button>
    </div>
  </div></div>`;
}

function showSignup(){
  $('modalRoot').innerHTML=`<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">
    <h2>Create Account</h2>
    <div id="authAlert"></div>
    <div class="field"><label>Email</label><input id="sEmail" type="email"/></div>
    <div class="field"><label>Password</label><input id="sPass" type="password"/></div>
    <div class="btn-row">
      <button class="btn-link" onclick="showLogin()">Already have an account?</button>
      <div style="flex:1"></div>
      <button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" onclick="doSignup()">Sign Up</button>
    </div>
  </div></div>`;
}

async function doLogin(){
  const email=$('lEmail').value, pass=$('lPass').value;
  try{
    const r=await fetch('/api/auth/customer/login',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({username:email,password:pass})});
    if(!r.ok){const e=await r.json();$('authAlert').innerHTML='<div class="alert alert-err">'+(e.detail?.message||e.detail||'Login failed')+'</div>';return;}
    const d=await r.json();
    AUTH=d.tokens?.IdToken||d.tokens?.AccessToken||'';
    USER_EMAIL=email;
    localStorage.setItem('sc_token',AUTH);
    localStorage.setItem('sc_email',USER_EMAIL);
    updateAuthUI(); closeModal();
  }catch(e){$('authAlert').innerHTML='<div class="alert alert-err">Network error</div>';}
}

async function doSignup(){
  const email=$('sEmail').value, pass=$('sPass').value;
  try{
    const r=await fetch('/api/auth/customer/signup',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({email:email,password:pass})});
    if(!r.ok){const e=await r.json();$('authAlert').innerHTML='<div class="alert alert-err">'+(e.detail?.message||e.detail||'Signup failed')+'</div>';return;}
    $('authAlert').innerHTML='<div class="alert alert-ok">Account created! Check your email for verification, then sign in.</div>';
    setTimeout(showLogin,3000);
  }catch(e){$('authAlert').innerHTML='<div class="alert alert-err">Network error</div>';}
}

function logout(){
  AUTH=''; USER_EMAIL='';
  localStorage.removeItem('sc_token');
  localStorage.removeItem('sc_email');
  updateAuthUI();
}

function closeModal(){$('modalRoot').innerHTML='';}

/* ---- Checkout ---- */
function showCheckout(){
  closeCart();
  const items=cart.items||[];
  const total=items.reduce((s,i)=>s+i.quantity*i.unit_price,0);
  let rows=items.map(i=>`<tr><td>${escH(i.product_id)}</td><td>${i.quantity}</td><td>$${(i.quantity*i.unit_price).toFixed(2)}</td></tr>`).join('');
  $('modalRoot').innerHTML=`<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">
    <h2>Checkout</h2>
    <div id="coAlert"></div>
    <table style="width:100%;font-size:14px;margin-bottom:14px">
      <tr style="color:#64748b"><th>Product</th><th>Qty</th><th>Subtotal</th></tr>
      ${rows}
      <tr style="font-weight:700"><td colspan="2">Total</td><td>$${total.toFixed(2)}</td></tr>
    </table>
    <div class="field"><label>Email</label><input id="coEmail" type="email" value="${escH(USER_EMAIL)}"/></div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" id="placeBtn" onclick="placeOrder()">Place Order</button>
    </div>
  </div></div>`;
}

async function placeOrder(){
  const email=$('coEmail').value.trim();
  if(!email){$('coAlert').innerHTML='<div class="alert alert-err">Email is required</div>';return;}
  $('placeBtn').disabled=true;$('placeBtn').textContent='Placing...';
  const items=cart.items.map(i=>({product_id:i.product_id,product_name:i.product_id,quantity:i.quantity,unit_price:i.unit_price}));
  const total=items.reduce((s,i)=>s+i.quantity*i.unit_price,0);
  try{
    const r=await fetch('/api/checkout',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({customer_email:email,items:items,total:total})});
    const d=await r.json();
    if(!r.ok&&r.status!==207){$('coAlert').innerHTML='<div class="alert alert-err">'+(d.detail||'Checkout failed')+'</div>';$('placeBtn').disabled=false;$('placeBtn').textContent='Place Order';return;}
    await fetch('/api/cart/'+SID,{method:'DELETE'});
    cart={items:[]};updateCartBadge();
    showConfirmation(d,items,total);
    loadProducts();
  }catch(e){$('coAlert').innerHTML='<div class="alert alert-err">Network error</div>';$('placeBtn').disabled=false;$('placeBtn').textContent='Place Order';}
}

function showConfirmation(order,items,total){
  let rows=items.map(i=>`<tr><td>${escH(i.product_id)}</td><td>${i.quantity}</td><td>$${(i.quantity*i.unit_price).toFixed(2)}</td></tr>`).join('');
  $('modalRoot').innerHTML=`<div class="modal-bg"><div class="confirm-box">
    <div class="icon">\u2705</div>
    <h2>Order Placed!</h2>
    <div class="oid">Order ID: ${escH(order.order_id)}</div>
    <table><tr><th>Product</th><th>Qty</th><th>Subtotal</th></tr>${rows}
      <tr style="font-weight:700"><td colspan="2">Total</td><td>$${total.toFixed(2)}</td></tr></table>
    <p style="font-size:13px;color:#64748b;margin-top:12px">Confirmation sent to ${escH(order.customer_email)}</p>
    <button class="continue-btn" onclick="closeModal()">Continue Shopping</button>
  </div></div>`;
}

/* ---- Init ---- */
updateAuthUI();
loadCategories().then(loadProducts);
loadCart();
</script>
</body>
</html>"""
