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
SKIP_DB_SCHEMA_INIT = os.environ.get("SKIP_DB_SCHEMA_INIT", "").lower() in {"1", "true", "yes"}

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
    if SKIP_DB_SCHEMA_INIT:
        log.info("Skipping catalog schema initialization")
        return
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
<meta name="theme-color" content="#6366f1"/>
<title>ShopCloud — Curated commerce</title>
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,400..700;1,9..40,400..700&family=Fraunces:ital,opsz,wght@0,9..144,500..800;1,9..144,500..800&display=swap" rel="stylesheet"/>
<style>
:root{
  --bg0:#f3f1fb;
  --bg1:#ebe7ff;
  --surface:rgba(255,255,255,.78);
  --surface-solid:#fff;
  --stroke:rgba(99,102,241,.12);
  --text:#14121d;
  --muted:#615d73;
  --accent:#6366f1;
  --accent-d:#4f46e5;
  --accent-glow:rgba(99,102,241,.35);
  --success:#059669;
  --danger:#e11d48;
  --radius:18px;
  --radius-sm:12px;
  --font-body:'DM Sans',system-ui,sans-serif;
  --font-display:'Fraunces',Georgia,serif;
  --shadow:0 8px 32px rgba(20,18,29,.06),0 2px 8px rgba(20,18,29,.04);
  --shadow-hover:0 16px 48px rgba(99,102,241,.14),0 4px 16px rgba(20,18,29,.08);
}
@media (prefers-color-scheme: dark){
  :root{
    --bg0:#0f0e14;
    --bg1:#161422;
    --surface:rgba(28,26,40,.72);
    --surface-solid:#1c1a28;
    --stroke:rgba(165,180,252,.15);
    --text:#f4f2ff;
    --muted:#a09bb8;
    --accent:#818cf8;
    --accent-d:#6366f1;
    --accent-glow:rgba(129,140,248,.4);
    --shadow:0 8px 32px rgba(0,0,0,.35),0 2px 8px rgba(0,0,0,.25);
    --shadow-hover:0 16px 48px rgba(99,102,241,.25),0 4px 16px rgba(0,0,0,.35);
  }
}
*{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{
  font-family:var(--font-body);
  background:var(--bg0);
  color:var(--text);
  min-height:100vh;
  line-height:1.5;
  position:relative;
  overflow-x:hidden;
}
body::before,body::after{
  content:'';
  position:fixed;
  border-radius:50%;
  filter:blur(80px);
  opacity:.55;
  z-index:-1;
  pointer-events:none;
}
body::before{
  width:min(72vw,560px);height:min(72vw,560px);
  background:radial-gradient(circle at 30% 30%,#c4b5fd 0%,transparent 65%);
  top:-12%;right:-8%;
  animation:float1 22s ease-in-out infinite;
}
body::after{
  width:min(65vw,480px);height:min(65vw,480px);
  background:radial-gradient(circle at 70% 70%,#a5b4fc 0%,transparent 60%);
  bottom:-8%;left:-10%;
  animation:float2 26s ease-in-out infinite;
}
@keyframes float1{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(-4%,6%) scale(1.05)}}
@keyframes float2{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(6%,-4%) scale(1.06)}}
@keyframes rise{from{opacity:0;transform:translateY(16px)}to{opacity:1;transform:translateY(0)}}
@keyframes pulse-soft{0%,100%{transform:scale(1)}50%{transform:scale(1.06)}}
@media (prefers-reduced-motion: reduce){
  *,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important}
}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}

.hdr-wrap{position:sticky;top:0;z-index:50;padding:12px 20px 0}
.hdr{
  max-width:1180px;margin:0 auto;
  display:flex;align-items:center;gap:16px;
  min-height:64px;padding:10px 18px;
  background:var(--surface);
  backdrop-filter:saturate(180%) blur(16px);
  -webkit-backdrop-filter:saturate(180%) blur(16px);
  border:1px solid var(--stroke);
  border-radius:var(--radius);
  box-shadow:var(--shadow);
}
.hdr .brand{display:flex;flex-direction:column;gap:2px;cursor:default}
.hdr .logo{font-family:var(--font-display);font-size:1.35rem;font-weight:700;letter-spacing:-.03em;color:var(--text);line-height:1.15}
.hdr .logo span{background:linear-gradient(125deg,var(--accent),#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent}
.hdr .tag{font-size:.72rem;color:var(--muted);letter-spacing:.06em;text-transform:uppercase;font-weight:600}
.hdr .spacer{flex:1}
.search-wrap{flex:1;max-width:380px;position:relative}
.search-wrap svg{position:absolute;left:14px;top:50%;transform:translateY(-50%);opacity:.45;width:18px;height:18px;pointer-events:none}
.hdr .search{
  width:100%;padding:11px 14px 11px 42px;
  border:1px solid var(--stroke);border-radius:999px;font-size:.925rem;
  background:var(--surface-solid);color:var(--text);
  transition:border-color .2s, box-shadow .2s;
}
.hdr .search::placeholder{color:var(--muted);opacity:.85}
.hdr .search:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 4px var(--accent-glow)}
.hdr-actions{display:flex;align-items:center;gap:10px}
.cart-btn{
  position:relative;display:flex;align-items:center;justify-content:center;
  width:48px;height:48px;border:none;border-radius:14px;
  background:linear-gradient(145deg,var(--surface-solid),var(--surface));
  border:1px solid var(--stroke);cursor:pointer;color:var(--text);
  transition:transform .2s, box-shadow .2s;
}
.cart-btn:hover{transform:translateY(-2px);box-shadow:var(--shadow-hover)}
.cart-btn:active{transform:translateY(0)}
.cart-btn svg{width:22px;height:22px}
.cart-btn .count{
  position:absolute;top:6px;right:8px;background:var(--danger);color:#fff;
  font-size:10px;font-weight:700;border-radius:999px;min-width:18px;height:18px;
  display:flex;align-items:center;justify-content:center;padding:0 5px;
  animation:pulse-soft 2s ease-in-out infinite;
}
.cart-btn .count:empty,.cart-btn .count[data-n="0"]{display:none}
.auth-btn{
  padding:11px 18px;border-radius:999px;border:1px solid var(--stroke);
  background:linear-gradient(180deg,var(--accent),var(--accent-d));color:#fff;
  cursor:pointer;font-size:.88rem;font-weight:600;
  box-shadow:0 4px 14px var(--accent-glow);
  transition:transform .2s, filter .2s;
}
.auth-btn:hover{filter:brightness(1.08);transform:translateY(-1px)}
.auth-btn:active{transform:translateY(0)}
.auth-btn.ghost{background:var(--surface-solid);color:var(--text);box-shadow:none;border-color:var(--stroke)}
.auth-btn.ghost:hover{filter:none;background:var(--bg1)}
.user-badge{font-size:.78rem;color:var(--muted);max-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

.hero{
  max-width:1180px;margin:28px auto 0;padding:0 24px;
  animation:rise .7s ease backwards;
}
.hero-inner{
  position:relative;border-radius:calc(var(--radius) + 6px);overflow:hidden;
  padding:clamp(28px,5vw,52px) clamp(24px,4vw,48px);
  background:linear-gradient(135deg,var(--surface-solid) 0%,rgba(255,255,255,.4) 50%,var(--surface-solid) 100%);
  border:1px solid var(--stroke);box-shadow:var(--shadow);
}
@media (prefers-color-scheme: dark){
  .hero-inner{background:linear-gradient(135deg,var(--surface-solid) 0%,rgba(99,102,241,.08) 40%,var(--surface-solid) 100%)}
}
.hero-inner::before{
  content:'';position:absolute;inset:0;background:
    radial-gradient(ellipse 80% 60% at 100% 0%,rgba(168,85,247,.15),transparent),
    radial-gradient(ellipse 60% 50% at 0% 100%,rgba(99,102,241,.18),transparent);
  pointer-events:none;
}
.hero-copy{position:relative;z-index:1;max-width:560px}
.hero h1{font-family:var(--font-display);font-size:clamp(1.85rem,4vw,2.65rem);font-weight:700;line-height:1.12;margin-bottom:12px;letter-spacing:-.03em}
.hero p{font-size:1.05rem;color:var(--muted);margin-bottom:22px}
.hero-cta{display:flex;flex-wrap:wrap;gap:12px;align-items:center}
.hero-scroll{
  display:inline-flex;align-items:center;gap:8px;padding:12px 22px;border-radius:999px;
  border:1px solid var(--stroke);background:var(--surface-solid);cursor:pointer;font-weight:600;font-size:.9rem;color:var(--text);
  transition:transform .2s, border-color .2s;
}
.hero-scroll:hover{border-color:var(--accent);transform:translateY(-2px)}
.hero-badge{display:inline-flex;align-items:center;gap:8px;font-size:.8rem;font-weight:600;color:var(--accent);margin-bottom:14px}
.hero-badge span{width:8px;height:8px;border-radius:50%;background:var(--accent);box-shadow:0 0 12px var(--accent-glow);animation:pulse-soft 2.5s ease-in-out infinite}

.toolbar-wrap{max-width:1180px;margin:28px auto 0;padding:0 24px}
.toolbar-label{font-size:.72rem;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);margin-bottom:10px}
.category-chips{display:flex;flex-wrap:wrap;gap:8px}
.chip{
  padding:9px 18px;border-radius:999px;border:1px solid var(--stroke);
  background:var(--surface-solid);color:var(--muted);font-size:.875rem;font-weight:600;
  cursor:pointer;transition:background .2s, color .2s, transform .15s, border-color .2s;
}
.chip:hover{color:var(--text);border-color:var(--accent);transform:translateY(-1px)}
.chip-active{background:linear-gradient(180deg,var(--accent),var(--accent-d));color:#fff;border-color:transparent;box-shadow:0 4px 16px var(--accent-glow)}

.wrap{max-width:1180px;margin:0 auto;padding:24px 24px 80px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(268px,1fr));gap:22px}
.card{
  background:var(--surface-solid);border:1px solid var(--stroke);border-radius:var(--radius);
  overflow:hidden;box-shadow:var(--shadow);
  transition:transform .35s cubic-bezier(.34,1.56,.64,1), box-shadow .35s;
}
.card:hover{transform:translateY(-6px);box-shadow:var(--shadow-hover)}
.card-visual{position:relative;width:100%;aspect-ratio:4/3;background:linear-gradient(145deg,var(--bg1),var(--bg0));overflow:hidden}
.card-visual img{width:100%;height:100%;object-fit:cover;transition:transform .5s cubic-bezier(.34,1.56,.64,1)}
.card:hover .card-visual img{transform:scale(1.06)}
.card-visual-fallback{display:flex;align-items:center;justify-content:center;font-family:var(--font-display);font-size:3rem;font-weight:700;color:var(--accent);opacity:.35}
.category-pill{
  position:absolute;top:12px;left:12px;font-size:.68rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;
  padding:5px 10px;border-radius:999px;background:rgba(255,255,255,.92);color:var(--accent-d);
  backdrop-filter:blur(8px);border:1px solid rgba(255,255,255,.6);
}
@media (prefers-color-scheme: dark){
  .category-pill{background:rgba(28,26,40,.85);border-color:var(--stroke);color:var(--accent)}
}
.card .body{padding:18px}
.card h3{font-family:var(--font-display);font-size:1.1rem;margin-bottom:6px;font-weight:650}
.card .desc{font-size:.875rem;color:var(--muted);margin-bottom:14px;line-height:1.55;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.card .row{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;margin-bottom:14px}
.card .price{font-family:var(--font-display);font-size:1.35rem;font-weight:700;color:var(--text)}
.card .stock{font-size:.78rem;color:var(--muted)}
.card .stock.low{color:#d97706}
.card-actions{display:flex;justify-content:stretch}
.add-btn{
  flex:1;padding:11px 16px;border-radius:var(--radius-sm);border:none;
  background:linear-gradient(180deg,var(--accent),var(--accent-d));color:#fff;
  cursor:pointer;font-size:.875rem;font-weight:700;
  transition:filter .2s, transform .15s;
}
.add-btn:hover{filter:brightness(1.06)}
.add-btn:active{transform:scale(.98)}
.add-btn:disabled{background:var(--muted);cursor:not-allowed;filter:none;opacity:.55}

.card.anim{opacity:0;animation:rise .55s cubic-bezier(.22,1,.36,1) forwards}
.card.anim:nth-child(1){animation-delay:.03s}.card.anim:nth-child(2){animation-delay:.06s}.card.anim:nth-child(3){animation-delay:.09s}
.card.anim:nth-child(4){animation-delay:.12s}.card.anim:nth-child(5){animation-delay:.15s}.card.anim:nth-child(6){animation-delay:.18s}
.card.anim:nth-child(7){animation-delay:.21s}.card.anim:nth-child(8){animation-delay:.24s}.card.anim:nth-child(9){animation-delay:.27s}
.card.anim:nth-child(n+10){animation-delay:.3s}

.empty-state,.grid .empty{
  grid-column:1/-1;text-align:center;padding:56px 24px;border-radius:var(--radius);
  background:var(--surface);border:1px dashed var(--stroke);color:var(--muted);
}
.empty-state h2{font-family:var(--font-display);font-size:1.25rem;color:var(--text);margin-bottom:8px}

.drawer-bg{position:fixed;inset:0;background:rgba(10,8,18,.35);backdrop-filter:blur(4px);z-index:90;opacity:0;pointer-events:none;transition:opacity .3s ease}
.drawer-bg.open{opacity:1;pointer-events:auto}
.drawer{
  position:fixed;top:12px;right:12px;bottom:12px;width:min(420px,92vw);
  background:var(--surface-solid);z-index:91;border-radius:var(--radius);
  border:1px solid var(--stroke);box-shadow:var(--shadow-hover);
  transform:translateX(calc(100% + 24px));transition:transform .4s cubic-bezier(.32,.72,0,1);
  display:flex;flex-direction:column;overflow:hidden;
}
.drawer.open{transform:translateX(0)}
.drawer .dh{padding:22px 22px 18px;border-bottom:1px solid var(--stroke);display:flex;align-items:center;justify-content:space-between}
.drawer .dh h2{font-family:var(--font-display);font-size:1.25rem}
.drawer .close-btn{background:none;border:none;font-size:28px;line-height:1;cursor:pointer;color:var(--muted);padding:4px;border-radius:8px;transition:background .15s,color .15s}
.drawer .close-btn:hover{background:var(--bg1);color:var(--text)}
.drawer .items{flex:1;overflow-y:auto;padding:16px 22px}
.drawer .empty{text-align:center;color:var(--muted);padding:48px 16px;font-size:.95rem}
.ci{display:flex;gap:14px;padding:16px 0;border-bottom:1px solid var(--stroke)}
.ci .ci-info{flex:1;min-width:0}
.ci .ci-name{font-size:.93rem;font-weight:700;color:var(--text);word-break:break-word}
.ci .ci-price{font-size:.82rem;color:var(--muted);margin-top:2px}
.ci .ci-qty{display:flex;align-items:center;gap:10px;margin-top:10px}
.ci .ci-qty button{width:32px;height:32px;border-radius:10px;border:1px solid var(--stroke);background:var(--surface-solid);cursor:pointer;font-size:16px;display:flex;align-items:center;justify-content:center;color:var(--text);transition:background .15s,border-color .15s}
.ci .ci-qty button:hover{border-color:var(--accent);background:var(--bg1)}
.ci .ci-qty span{font-size:.9rem;min-width:24px;text-align:center;font-weight:600}
.ci .ci-remove{background:none;border:none;color:var(--danger);cursor:pointer;font-size:.78rem;margin-top:8px;font-weight:600}
.drawer .footer{padding:20px 22px;border-top:1px solid var(--stroke);background:var(--bg0)}
.drawer .total{display:flex;justify-content:space-between;font-size:1.1rem;font-weight:700;margin-bottom:14px;font-family:var(--font-display)}
.checkout-btn{
  width:100%;padding:14px;border:none;border-radius:var(--radius-sm);
  background:linear-gradient(180deg,var(--accent),var(--accent-d));color:#fff;font-size:.95rem;font-weight:700;cursor:pointer;
  box-shadow:0 6px 20px var(--accent-glow);transition:filter .2s,transform .15s;
}
.checkout-btn:hover{filter:brightness(1.06)}
.checkout-btn:active{transform:scale(.99)}

.modal-bg{position:fixed;inset:0;background:rgba(10,8,18,.45);backdrop-filter:blur(6px);display:flex;align-items:center;justify-content:center;z-index:100;padding:20px;animation:rise .25s ease}
.modal{background:var(--surface-solid);border-radius:var(--radius);padding:28px;width:440px;max-width:100%;border:1px solid var(--stroke);box-shadow:var(--shadow-hover);animation:rise .35s cubic-bezier(.22,1,.36,1)}
.modal h2{font-family:var(--font-display);font-size:1.35rem;margin-bottom:18px;color:var(--text)}
.field{margin-bottom:14px}
.field label{display:block;font-size:.78rem;color:var(--muted);margin-bottom:6px;font-weight:700;text-transform:uppercase;letter-spacing:.05em}
.field input{width:100%;padding:12px 14px;border:1px solid var(--stroke);border-radius:var(--radius-sm);font-size:.9rem;background:var(--surface-solid);color:var(--text);transition:border-color .2s, box-shadow .2s}
.field input:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-glow)}
.btn-row{display:flex;gap:10px;justify-content:flex-end;margin-top:20px;flex-wrap:wrap}
.btn{padding:11px 20px;border-radius:var(--radius-sm);border:none;cursor:pointer;font-size:.875rem;font-weight:600;transition:filter .15s, transform .1s}
.btn-primary{background:linear-gradient(180deg,var(--accent),var(--accent-d));color:#fff}
.btn-primary:hover{filter:brightness(1.06)}
.btn-ghost{background:transparent;color:var(--muted);border:1px solid var(--stroke)}
.btn-ghost:hover{border-color:var(--accent);color:var(--text)}
.btn-link{background:none;border:none;color:var(--accent);cursor:pointer;font-size:.82rem;padding:0;font-weight:700}
.alert{padding:11px 14px;border-radius:var(--radius-sm);font-size:.82rem;margin-bottom:12px}
.alert-err{background:rgba(225,29,72,.08);color:var(--danger);border:1px solid rgba(225,29,72,.2)}
.alert-ok{background:rgba(5,150,105,.08);color:var(--success);border:1px solid rgba(5,150,105,.22)}

.confirm-box{max-width:520px;background:var(--surface-solid);border-radius:var(--radius);padding:36px;text-align:center;border:1px solid var(--stroke);box-shadow:var(--shadow-hover)}
.confirm-box .icon{font-size:52px;margin-bottom:14px;line-height:1}
.confirm-box h2{font-family:var(--font-display);color:var(--success);margin-bottom:8px;font-size:1.5rem}
.confirm-box .oid{font-size:.82rem;color:var(--muted);margin-bottom:20px}
.confirm-box table{width:100%;text-align:left;margin:16px 0;font-size:.875rem}
.confirm-box th{color:var(--muted);font-weight:700;padding:8px 0;border-bottom:1px solid var(--stroke)}
.confirm-box td{padding:8px 0;border-bottom:1px solid var(--stroke)}
.continue-btn{margin-top:22px;padding:12px 28px;border-radius:999px;border:none;background:linear-gradient(180deg,var(--accent),var(--accent-d));color:#fff;cursor:pointer;font-size:.9rem;font-weight:700;box-shadow:0 6px 20px var(--accent-glow)}
</style>
</head>
<body>

<div class="hdr-wrap">
<header class="hdr">
  <div class="brand">
    <div class="logo">Shop<span>Cloud</span></div>
    <span class="tag">Cloud-native storefront</span>
  </div>
  <div class="search-wrap">
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path stroke-linecap="round" d="M20 20l-3-3"/></svg>
    <input class="search" id="q" placeholder="Search by name, category, or vibe..." autocomplete="off"/>
  </div>
  <div class="spacer" aria-hidden="true"></div>
  <div class="hdr-actions">
    <button type="button" class="cart-btn" onclick="openCart()" title="Open cart" aria-label="Shopping cart">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"/></svg>
      <span class="count" id="cartCount" data-n="0"></span>
    </button>
    <span class="user-badge" id="userBadge"></span>
    <button type="button" class="auth-btn" id="authBtn" onclick="showLogin()">Sign In</button>
  </div>
</header>
</div>

<section class="hero">
  <div class="hero-inner">
    <div class="hero-copy">
      <div class="hero-badge"><span></span> New season drop</div>
      <h1>Gear built for builders who ship.</h1>
      <p>Browse curated merch, notebooks, and essentials — fast cart, instant checkout, and a storefront that feels as polished as your infra.</p>
      <div class="hero-cta">
        <button type="button" class="hero-scroll" onclick="document.getElementById('catalog').scrollIntoView({behavior:'smooth'})">Explore catalog ↓</button>
      </div>
    </div>
  </div>
</section>

<div class="toolbar-wrap">
  <p class="toolbar-label">Categories</p>
  <div class="category-chips" id="categoryChips"></div>
</div>

<div class="wrap" id="catalog"><div class="grid" id="products"></div></div>

<div class="drawer-bg" id="drawerBg" onclick="closeCart()" aria-hidden="true"></div>
<div class="drawer" id="drawer" role="dialog" aria-label="Shopping cart">
  <div class="dh"><h2>Your cart</h2><button type="button" class="close-btn" onclick="closeCart()" aria-label="Close">&times;</button></div>
  <div class="items" id="cartItems"></div>
  <div class="footer" id="cartFooter" style="display:none">
    <div class="total"><span>Total</span><span id="cartTotal">$0.00</span></div>
    <button type="button" class="checkout-btn" onclick="showCheckout()">Proceed to checkout</button>
  </div>
</div>

<div id="modalRoot"></div>

<script>
function makeSessionId(){
  const c=window.crypto;
  if(c&&typeof c.randomUUID==='function') return c.randomUUID();
  if(c&&typeof c.getRandomValues==='function'){
    const bytes=new Uint8Array(16);
    c.getRandomValues(bytes);
    return Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
  }
  return 'sid-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
}
var SID = localStorage.getItem('sc_sid');
if(!SID){SID=makeSessionId();localStorage.setItem('sc_sid',SID)}
var AUTH = localStorage.getItem('sc_token')||'';
var USER_EMAIL = localStorage.getItem('sc_email')||'';
var cart = {items:[]};
var SEL_CAT='';

function $(id){return document.getElementById(id)}
function authHdr(){return AUTH?{Authorization:'Bearer '+AUTH}:{}}
function escH(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}
function escAttr(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;').replace(/</g,'&lt;')}
function safeImgUrl(u){if(!u||typeof u!=='string')return '';var t=u.trim();return /^https?:\/\//i.test(t)?t:''}

async function loadCategories(){
  const r=await fetch('/api/catalog/categories');
  const d=await r.json();
  const wrap=$('categoryChips');
  wrap.innerHTML='<button type="button" class="chip chip-active" data-cat="">All</button>';
  d.categories.forEach(function(c){
    const b=document.createElement('button');
    b.type='button'; b.className='chip'; b.dataset.cat=c; b.textContent=c;
    wrap.appendChild(b);
  });
  wrap.querySelectorAll('.chip').forEach(function(btn){
    btn.addEventListener('click',function(){
      wrap.querySelectorAll('.chip').forEach(function(x){x.classList.remove('chip-active')});
      btn.classList.add('chip-active');
      SEL_CAT=btn.dataset.cat||'';
      loadProducts();
    });
  });
}

var _searchTimer;
function scheduleSearch(){clearTimeout(_searchTimer);_searchTimer=setTimeout(loadProducts,260)}
$('q').addEventListener('input',scheduleSearch);

async function loadProducts(){
  try{
    const q=$('q').value.trim();
    let url='/api/catalog/products';
    if(q.length>0) url='/api/catalog/search?q='+encodeURIComponent(q);
    else if(SEL_CAT) url='/api/catalog/products?category='+encodeURIComponent(SEL_CAT);
    const r=await fetch(url);
    if(!r.ok) throw new Error('Catalog request failed: '+r.status);
    const d=await r.json();
    renderProducts(d.products||d.results||[]);
  }catch(e){
    console.error('products',e);
    $('products').innerHTML='<div class="empty-state"><h2>We couldn’t load products</h2><p>Check your connection or try again in a moment.</p></div>';
  }
}

function renderProducts(list){
  if(!list.length){
    $('products').innerHTML='<div class="empty-state"><h2>No matches yet</h2><p>Try another search or pick a different category.</p></div>';
    return;
  }
  $('products').innerHTML=list.map(function(p,i){
    const low=p.stock<10;
    const oos=p.stock<=0;
    const img=safeImgUrl(p.image_url);
    const initial=escH((p.name||'?').charAt(0).toUpperCase());
    const vis=img
      ?'<div class="card-visual"><img src="'+escAttr(img)+'" alt="'+escAttr(p.name)+'" loading="lazy" decoding="async"/></div>'
      :'<div class="card-visual card-visual-fallback" aria-hidden="true"><span>'+initial+'</span></div>';
    return '<article class="card anim" style="animation-delay:'+Math.min(i*.05,.35)+'s">'+
      vis+'<span class="category-pill">'+escH(p.category)+'</span>'+
      '<div class="body"><h3>'+escH(p.name)+'</h3>'+
      '<p class="desc">'+escH(p.description)+'</p>'+
      '<div class="row"><span class="price">$'+Number(p.price).toFixed(2)+'</span>'+
      '<span class="stock'+(low?' low':'')+'">'+(oos?'Out of stock':p.stock+' in stock')+'</span></div>'+
      '<div class="card-actions"><button type="button" class="add-btn" '+(oos?'disabled':'')+
      " onclick='addToCart("+JSON.stringify(p.id)+","+JSON.stringify(p.name)+","+Number(p.price)+")'>Add to cart</button></div>"+
      '</div></article>';
  }).join('');
}

async function loadCart(){
  try{
    const r=await fetch('/api/cart?session_id='+SID);
    cart=await r.json();
  }catch(e){cart={items:[]};}
  updateCartBadge();
}

function updateCartBadge(){
  const n=(cart.items||[]).reduce(function(s,i){return s+i.quantity},0);
  const el=$('cartCount');
  el.textContent=n;
  el.dataset.n=n;
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
    $('cartItems').innerHTML='<div class="empty">Your cart is empty — add something you love.</div>';
    $('cartFooter').style.display='none';
    return;
  }
  let total=0;
  $('cartItems').innerHTML=items.map(function(it,i){
    const sub=it.quantity*it.unit_price; total+=sub;
    const label=it.product_name&&String(it.product_name).trim()?it.product_name:it.product_id;
    return '<div class="ci"><div class="ci-info">'+
      '<div class="ci-name">'+escH(label)+'</div>'+
      '<div class="ci-price">$'+it.unit_price.toFixed(2)+' each</div>'+
      '<div class="ci-qty">'+
      '<button type="button" onclick="changeQty('+i+',-1)" aria-label="Decrease">&minus;</button>'+
      '<span>'+it.quantity+'</span>'+
      '<button type="button" onclick="changeQty('+i+',1)" aria-label="Increase">+</button></div>'+
      '<button type="button" class="ci-remove" onclick="removeItem('+i+')">Remove</button></div>'+
      '<div style="font-weight:700;white-space:nowrap;font-family:var(--font-display,Georgia,serif)">$'+sub.toFixed(2)+'</div></div>';
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
  await fetch('/api/cart/'+SID,{method:'DELETE'});
  for(const it of cart.items){
    await fetch('/api/cart/add',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({session_id:SID,product_id:it.product_id,quantity:it.quantity,unit_price:it.unit_price})});
  }
  await loadCart(); renderCart();
}

function updateAuthUI(){
  const btn=$('authBtn');
  if(AUTH){
    btn.textContent='Sign Out';
    btn.classList.add('ghost');
    btn.onclick=logout;
    $('userBadge').textContent=USER_EMAIL;
  }else{
    btn.textContent='Sign In';
    btn.classList.remove('ghost');
    btn.onclick=showLogin;
    $('userBadge').textContent='';
  }
}

function showLogin(){
  $('modalRoot').innerHTML='<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">'+
    '<h2>Welcome back</h2><div id="authAlert"></div>'+
    '<div class="field"><label>Email</label><input id="lEmail" type="email" autocomplete="username"/></div>'+
    '<div class="field"><label>Password</label><input id="lPass" type="password" autocomplete="current-password"/></div>'+
    '<div class="btn-row">'+
    '<button type="button" class="btn-link" onclick="showSignup()">Create account</button>'+
    '<div style="flex:1"></div>'+
    '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
    '<button type="button" class="btn btn-primary" onclick="doLogin()">Sign in</button></div></div></div>';
}

function showSignup(){
  $('modalRoot').innerHTML='<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">'+
    '<h2>Create account</h2><div id="authAlert"></div>'+
    '<div class="field"><label>Email</label><input id="sEmail" type="email" autocomplete="email"/></div>'+
    '<div class="field"><label>Password</label><input id="sPass" type="password" autocomplete="new-password"/></div>'+
    '<div class="btn-row">'+
    '<button type="button" class="btn-link" onclick="showLogin()">Already registered?</button>'+
    '<div style="flex:1"></div>'+
    '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
    '<button type="button" class="btn btn-primary" onclick="doSignup()">Sign up</button></div></div></div>';
}

async function doLogin(){
  const email=$('lEmail').value, pass=$('lPass').value;
  const alertEl=$('authAlert');
  const setErr=function(msg){if(alertEl)alertEl.innerHTML='<div class="alert alert-err">'+escH(msg)+'</div>'};
  try{
    const r=await fetch('/api/auth/customer/login',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({username:email,password:pass})});
    let d;
    try{d=await r.json();}catch(_){setErr('Invalid response from server');return;}
    if(!r.ok){
      const detail=d&&d.detail;
      const msg=(detail&&typeof detail==='object'&&detail.message)||(typeof detail==='string'?detail:JSON.stringify(detail||d))||'Login failed';
      setErr(msg);return;
    }
    const tok=d.tokens&&(d.tokens.IdToken||d.tokens.AccessToken);
    if(!tok){setErr('Login succeeded but no token in response');return;}
    AUTH=tok;
    USER_EMAIL=email;
    try{
      localStorage.setItem('sc_token',AUTH);
      localStorage.setItem('sc_email',USER_EMAIL);
    }catch(se){
      console.error('login storage',se);
      setErr(se.name==='SecurityError'||se.name==='QuotaExceededError'
        ?'Could not save your session (browser blocked storage). Try a non-private window or allow site data.'
        :'Could not save session: '+se.message);
      return;
    }
    updateAuthUI(); closeModal();
  }catch(e){
    console.error('login',e);
    setErr(e&&e.message?e.message:'Network error');
  }
}

async function doSignup(){
  const email=$('sEmail').value, pass=$('sPass').value;
  try{
    const r=await fetch('/api/auth/customer/signup',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({email:email,password:pass})});
    if(!r.ok){const e=await r.json();$('authAlert').innerHTML='<div class="alert alert-err">'+(e.detail?.message||e.detail||'Signup failed')+'</div>';return;}
    $('authAlert').innerHTML='<div class="alert alert-ok">Account created! You can sign in now.</div>';
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

function showCheckout(){
  closeCart();
  const items=cart.items||[];
  const total=items.reduce(function(s,i){return s+i.quantity*i.unit_price},0);
  let rows=items.map(function(i){return '<tr><td>'+escH(i.product_id)+'</td><td>'+i.quantity+'</td><td>$'+(i.quantity*i.unit_price).toFixed(2)+'</td></tr>'}).join('');
  $('modalRoot').innerHTML='<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">'+
    '<h2>Checkout</h2><div id="coAlert"></div>'+
    '<table style="width:100%;font-size:14px;margin-bottom:14px">'+
    '<tr style="color:var(--muted)"><th>Product</th><th>Qty</th><th>Subtotal</th></tr>'+rows+
    '<tr style="font-weight:700;font-family:var(--font-display,Georgia,serif)"><td colspan="2">Total</td><td>$'+total.toFixed(2)+'</td></tr></table>'+
    '<div class="field"><label>Email</label><input id="coEmail" type="email" value="'+escAttr(USER_EMAIL)+'"/></div>'+
    '<div class="btn-row">'+
    '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
    '<button type="button" class="btn btn-primary" id="placeBtn" onclick="placeOrder()">Place order</button></div></div></div>';
}

async function placeOrder(){
  const email=$('coEmail').value.trim();
  if(!email){$('coAlert').innerHTML='<div class="alert alert-err">Email is required</div>';return;}
  $('placeBtn').disabled=true;$('placeBtn').textContent='Placing…';
  const items=cart.items.map(function(i){return {product_id:i.product_id,product_name:i.product_id,quantity:i.quantity,unit_price:i.unit_price}});
  const total=items.reduce(function(s,i){return s+i.quantity*i.unit_price},0);
  try{
    const r=await fetch('/api/checkout',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({customer_email:email,items:items,total:total})});
    const d=await r.json();
    if(!r.ok&&r.status!==207){$('coAlert').innerHTML='<div class="alert alert-err">'+(d.detail||'Checkout failed')+'</div>';$('placeBtn').disabled=false;$('placeBtn').textContent='Place order';return;}
    await fetch('/api/cart/'+SID,{method:'DELETE'});
    cart={items:[]};updateCartBadge();
    showConfirmation(d,items,total);
    loadProducts();
  }catch(e){$('coAlert').innerHTML='<div class="alert alert-err">Network error</div>';$('placeBtn').disabled=false;$('placeBtn').textContent='Place order';}
}

function showConfirmation(order,items,total){
  let rows=items.map(function(i){return '<tr><td>'+escH(i.product_id)+'</td><td>'+i.quantity+'</td><td>$'+(i.quantity*i.unit_price).toFixed(2)+'</td></tr>'}).join('');
  $('modalRoot').innerHTML='<div class="modal-bg"><div class="confirm-box">'+
    '<div class="icon">\u2705</div>'+
    '<h2>Order placed</h2>'+
    '<div class="oid">Order ID: '+escH(order.order_id)+'</div>'+
    '<table><tr><th>Product</th><th>Qty</th><th>Subtotal</th></tr>'+rows+
    '<tr style="font-weight:700"><td colspan="2">Total</td><td>$'+total.toFixed(2)+'</td></tr></table>'+
    '<p style="font-size:.82rem;color:var(--muted);margin-top:14px">Confirmation sent to '+escH(order.customer_email)+'</p>'+
    '<button type="button" class="continue-btn" onclick="closeModal()">Continue shopping</button></div></div>';
}

updateAuthUI();
loadCategories().catch(function(e){console.error('categories',e)}).finally(loadProducts);
loadCart();
</script>
</body>
</html>"""
