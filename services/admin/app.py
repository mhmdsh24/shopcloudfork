"""Admin service — product CRUD, order management, and email/password admin sessions."""
from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import time
from contextlib import contextmanager
from typing import Any

import psycopg2
import psycopg2.errors
import psycopg2.pool
from fastapi import Cookie, Depends, FastAPI, HTTPException, Query, Response
from fastapi.responses import HTMLResponse
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

app = FastAPI(title="shopcloud-admin")
Instrumentator().instrument(app).expose(app)

log = logging.getLogger("admin")

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "shopcloud")
DB_USER = os.environ.get("DB_USER", "shopcloud_admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
DB_SSLMODE = os.environ.get("DB_SSLMODE", "require")
SKIP_DB_SCHEMA_INIT = os.environ.get("SKIP_DB_SCHEMA_INIT", "").lower() in {"1", "true", "yes"}

ADMIN_SESSION_COOKIE = "shopcloud_admin_session"
ADMIN_SESSION_TTL_SECONDS = int(os.environ.get("ADMIN_SESSION_TTL_SECONDS", "43200"))
ADMIN_SESSION_SECRET = os.environ.get("ADMIN_SESSION_SECRET") or DB_PASSWORD or "shopcloud-admin-local"
ADMIN_COOKIE_SECURE = os.environ.get("ADMIN_COOKIE_SECURE", "").lower() in {"1", "true", "yes"}
PASSWORD_HASH_ITERATIONS = int(os.environ.get("ADMIN_PASSWORD_HASH_ITERATIONS", "260000"))
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

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
                    sslmode=DB_SSLMODE,
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
# Schema
# ---------------------------------------------------------------------------

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
            cur.execute("""
                CREATE TABLE IF NOT EXISTS admin_users (
                    id            SERIAL PRIMARY KEY,
                    email         VARCHAR(255) NOT NULL,
                    password_hash TEXT NOT NULL,
                    created_at    TIMESTAMPTZ DEFAULT NOW(),
                    updated_at    TIMESTAMPTZ DEFAULT NOW()
                )
            """)
            cur.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS admin_users_email_lower_idx "
                "ON admin_users (LOWER(email))"
            )


@app.on_event("startup")
def startup() -> None:
    if SKIP_DB_SCHEMA_INIT:
        log.info("Skipping admin schema initialization")
        return
    _init_schema()


# ---------------------------------------------------------------------------
# Email/password auth
# ---------------------------------------------------------------------------

def _normalize_email(email: str) -> str:
    normalized = email.strip().lower()
    if not EMAIL_RE.match(normalized):
        raise HTTPException(status_code=400, detail="A valid email address is required")
    return normalized


def _hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        PASSWORD_HASH_ITERATIONS,
    )
    return (
        f"pbkdf2_sha256${PASSWORD_HASH_ITERATIONS}$"
        f"{base64.b64encode(salt).decode('ascii')}$"
        f"{base64.b64encode(digest).decode('ascii')}"
    )


def _verify_password(password: str, stored_hash: str) -> bool:
    try:
        algorithm, iterations_s, salt_s, digest_s = stored_hash.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        iterations = int(iterations_s)
        salt = base64.b64decode(salt_s.encode("ascii"))
        expected = base64.b64decode(digest_s.encode("ascii"))
    except (ValueError, binascii.Error):
        return False
    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(actual, expected)


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))


def _session_signature(payload: str) -> str:
    digest = hmac.new(
        ADMIN_SESSION_SECRET.encode("utf-8"),
        payload.encode("ascii"),
        hashlib.sha256,
    ).digest()
    return _b64url_encode(digest)


def _make_session(user_id: int, email: str) -> str:
    payload = _b64url_encode(json.dumps(
        {
            "sub": user_id,
            "email": email,
            "exp": int(time.time()) + ADMIN_SESSION_TTL_SECONDS,
            "nonce": secrets.token_urlsafe(16),
        },
        separators=(",", ":"),
    ).encode("utf-8"))
    return f"{payload}.{_session_signature(payload)}"


def _decode_session(token: str) -> dict[str, Any]:
    try:
        payload, signature = token.split(".", 1)
        expected = _session_signature(payload)
        if not hmac.compare_digest(signature, expected):
            raise ValueError("bad signature")
        claims = json.loads(_b64url_decode(payload))
    except (ValueError, json.JSONDecodeError, binascii.Error) as exc:
        raise HTTPException(status_code=401, detail="Invalid admin session") from exc
    if int(claims.get("exp", 0)) < int(time.time()):
        raise HTTPException(status_code=401, detail="Admin session expired")
    return claims


def _set_session_cookie(response: Response, user_id: int, email: str) -> None:
    response.set_cookie(
        key=ADMIN_SESSION_COOKIE,
        value=_make_session(user_id, email),
        max_age=ADMIN_SESSION_TTL_SECONDS,
        httponly=True,
        secure=ADMIN_COOKIE_SECURE,
        samesite="lax",
        path="/",
    )


def admin_required(
    admin_session: str | None = Cookie(default=None, alias=ADMIN_SESSION_COOKIE),
) -> dict[str, Any]:
    if not admin_session:
        raise HTTPException(status_code=401, detail="Admin login required")
    return _decode_session(admin_session)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class AdminAuthIn(BaseModel):
    email: str
    password: str


class ProductIn(BaseModel):
    id: str
    name: str
    description: str = ""
    category: str
    image_url: str = ""
    price: float = Field(ge=0)
    stock: int = Field(default=0, ge=0)


class ProductUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    category: str | None = None
    image_url: str | None = None
    price: float | None = Field(default=None, ge=0)
    stock: int | None = Field(default=None, ge=0)


class StockUpdate(BaseModel):
    stock: int = Field(ge=0)


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
# Admin auth
# ---------------------------------------------------------------------------

@app.post("/api/admin/signup", status_code=201)
def admin_signup(payload: AdminAuthIn, response: Response) -> dict[str, Any]:
    email = _normalize_email(payload.email)
    if len(payload.password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")

    try:
        with _db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO admin_users (email, password_hash) VALUES (%s, %s) "
                    "RETURNING id, email",
                    (email, _hash_password(payload.password)),
                )
                row = cur.fetchone()
    except psycopg2.errors.UniqueViolation as exc:
        raise HTTPException(status_code=409, detail="Admin email already exists") from exc

    user_id, saved_email = row
    _set_session_cookie(response, user_id, saved_email)
    return {"authenticated": True, "admin": {"id": user_id, "email": saved_email}}


@app.post("/api/admin/login")
def admin_login(payload: AdminAuthIn, response: Response) -> dict[str, Any]:
    email = _normalize_email(payload.email)
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, email, password_hash FROM admin_users WHERE LOWER(email) = LOWER(%s)",
                (email,),
            )
            row = cur.fetchone()

    if not row or not _verify_password(payload.password, row[2]):
        raise HTTPException(status_code=401, detail="Invalid admin email or password")

    user_id, saved_email, _ = row
    _set_session_cookie(response, user_id, saved_email)
    return {"authenticated": True, "admin": {"id": user_id, "email": saved_email}}


@app.post("/api/admin/logout")
def admin_logout(response: Response) -> dict[str, bool]:
    response.delete_cookie(ADMIN_SESSION_COOKIE, path="/")
    return {"authenticated": False}


@app.get("/api/admin/me")
def admin_me(claims: dict[str, Any] = Depends(admin_required)) -> dict[str, Any]:
    return {
        "authenticated": True,
        "admin": {"id": claims["sub"], "email": claims["email"]},
        "expires_at": claims["exp"],
    }


# ---------------------------------------------------------------------------
# Product CRUD  (all require an admin session)
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
    try:
        with _db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO products (id, name, description, category, image_url, price, stock) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    (product.id, product.name, product.description, product.category,
                     product.image_url, product.price, product.stock),
                )
    except psycopg2.errors.UniqueViolation as exc:
        raise HTTPException(status_code=409, detail="Product ID already exists") from exc
    return {"created": product.id}


@app.put("/api/admin/products/{product_id}")
def update_product(product_id: str, body: ProductUpdate, _: dict = Depends(admin_required)) -> dict:
    fields = body.model_dump(exclude_none=True)
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


@app.patch("/api/admin/products/{product_id}/stock")
def update_stock(product_id: str, body: StockUpdate, _: dict = Depends(admin_required)) -> dict:
    with _db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE products SET stock = %s, updated_at = NOW() WHERE id = %s",
                (body.stock, product_id),
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Product not found")
    return {"updated": product_id, "stock": body.stock}


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
.auth-input {
  width: min(220px, 70vw);
  padding: 10px 16px; background: rgba(0,0,0,0.2);
  border: 1px solid var(--border-light); border-radius: 999px;
  color: var(--text-main); font-family: var(--font-body); font-size: 0.88rem;
  transition: all 0.3s ease;
}
.auth-input::placeholder { color: var(--text-muted); }
.auth-input:focus { outline: none; border-color: var(--accent-cyan); box-shadow: var(--shadow-glow); background: rgba(0,0,0,0.35); }
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
.modal.modal-lg { width: min(720px, 96vw); }
textarea.field-input {
  width: 100%; min-height: 88px; resize: vertical; padding: 12px 14px;
  border: 1px solid rgba(255,255,255,0.1); border-radius: var(--radius-sm);
  font-size: 0.95rem; background: rgba(0,0,0,0.35); color: #FFF; font-family: var(--font-body);
  transition: all 0.25s;
}
textarea.field-input:focus {
  outline: none; border-color: var(--accent-cyan); box-shadow: 0 0 0 4px rgba(6, 182, 212, 0.12);
}
.lbl-hint { font-weight: 400; opacity: 0.75; text-transform: none; letter-spacing: 0; font-size: 0.7rem; }
.prod-thumb {
  width: 44px; height: 44px; object-fit: cover; border-radius: var(--radius-sm);
  background: rgba(0,0,0,0.4); vertical-align: middle; border: 1px solid var(--border-light);
}
.prod-thumb-ph {
  width: 44px; height: 44px; border-radius: var(--radius-sm); border: 1px dashed var(--border-light);
  display: inline-flex; align-items: center; justify-content: center; font-size: 0.65rem; color: var(--text-muted);
}
.cell-clamp { max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.cell-desc { max-width: 240px; font-size: 0.82rem; color: var(--text-muted); line-height: 1.35; }
.mono { font-family: ui-monospace, monospace; font-size: 0.82em; }
.badge-muted {
  background: rgba(148, 163, 184, 0.12); color: #CBD5E1;
  border: 1px solid rgba(148, 163, 184, 0.22);
}
.badge-bad {
  background: rgba(239, 68, 68, 0.12); color: #FCA5A5;
  border: 1px solid rgba(239, 68, 68, 0.25);
}
.select-limit {
  padding: 8px 14px; border-radius: 999px; border: 1px solid var(--border-light);
  background: rgba(0,0,0,0.35); color: #FFF; font-family: var(--font-body); font-size: 0.85rem;
}
.stock-control { display: inline-flex; align-items: center; gap: 8px; min-width: 132px; }
.stock-input {
  width: 72px; padding: 7px 10px; border-radius: 10px; border: 1px solid var(--border-light);
  background: rgba(0,0,0,0.35); color: #FFF; font-family: var(--font-body); font-size: 0.85rem;
}
.stock-input:focus { outline: none; border-color: var(--accent-cyan); box-shadow: 0 0 0 3px rgba(6, 182, 212, 0.12); }
.capabilities-hint {
  font-size: 0.84rem; color: var(--text-muted); line-height: 1.5; margin-bottom: 20px; padding: 14px 18px;
  background: var(--bg-glass-card); border: 1px solid var(--border-light); border-radius: var(--radius-sm);
}
.detail-meta { display: grid; gap: 8px; margin-bottom: 18px; font-size: 0.88rem; color: var(--text-muted); }
.detail-meta div strong { color: #fff; font-weight: 600; margin-right: 6px; }
.subtle { font-size: 0.78rem; color: var(--text-muted); }
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
      <input id="emailInput" class="auth-input" type="email" placeholder="Admin email" autocomplete="username"/>
      <input id="passwordInput" class="auth-input" type="password" placeholder="Password" autocomplete="current-password"/>
      <button type="button" class="btn btn-primary" onclick="loginAdmin()">Log in</button>
      <button type="button" class="btn btn-ghost" onclick="signupAdmin()">Sign up</button>
    </div>
    <button type="button" class="btn btn-ghost hidden" id="btnRefresh" onclick="load()">Refresh</button>
    <button type="button" class="btn btn-ghost hidden" id="btnSignOut" onclick="clearToken()">Sign out</button>
    <span id="authStatus"></span>
  </div>
</header>
</div>

<div class="wrap">
  <p class="capabilities-hint" id="capHint">
    <strong style="color:#fff">This console maps to the admin API:</strong>
    Products — list from PostgreSQL, create, update, quick stock changes, delete.
    Orders — list with adjustable limit (API default 50, max 200), read-only; open any order for line items (<code class="mono">GET /api/admin/orders/{id}</code>).
  </p>
  <div id="msgBox"></div>
  <div class="stat-row">
    <div class="stat"><div class="val" id="statProducts">—</div><div class="lbl">Products</div></div>
    <div class="stat"><div class="val" id="statOrders">—</div><div class="lbl">Orders</div></div>
    <div class="stat"><div class="val" id="statRevenue">—</div><div class="lbl">Revenue</div></div>
  </div>
  <div class="tabs">
    <div class="tab active" data-tab="products" onclick="switchTab('products')">Products</div>
    <div class="tab" data-tab="orders" onclick="switchTab('orders')">Orders</div>
  </div>
  <div id="productsTab"><p class="subtle">Sign in to load products.</p></div>
  <div id="ordersTab" class="hidden"><p class="subtle">Sign in to load orders.</p></div>
</div>
<div id="modalRoot"></div>
<script>
let AUTHED = false;
let ADMIN_EMAIL = '';
const API = '/api/admin';

function hdr(){ return {'Content-Type':'application/json'} }

function escapeHtml(s){
  if(s==null)return '';
  const d=document.createElement('div'); d.textContent=String(s); return d.innerHTML;
}
function escapeAttr(s){
  return String(s==null?'':s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
function fmtApiErr(detail){
  if(detail==null) return 'Request failed';
  if(typeof detail==='string') return detail;
  if(Array.isArray(detail)) return detail.map(x=>x.msg||x.type||JSON.stringify(x)).join('; ');
  return JSON.stringify(detail);
}
function orderStatusClass(st){
  const u=String(st||'').toLowerCase();
  if(/fail|cancel|void|refund/.test(u)) return 'badge-bad';
  if(/pending|process|hold|draft/.test(u)) return 'badge-warn';
  if(/paid|complet|ship|confirm|ok|success/.test(u)) return 'badge-ok';
  return 'badge-muted';
}
function formatDt(iso){
  if(!iso) return '—';
  try{ return new Date(iso).toLocaleString(); }catch(_){ return iso; }
}

function updateAuthUI(){
  const has=!!AUTHED;
  document.getElementById('loginSection').classList.toggle('hidden',has);
  document.getElementById('btnRefresh').classList.toggle('hidden',!has);
  document.getElementById('btnSignOut').classList.toggle('hidden',!has);
  document.getElementById('authStatus').textContent=has
    ? 'Signed in as '+ADMIN_EMAIL
    : 'Use your admin email and password.';
}

function authBody(){
  return {
    email:document.getElementById('emailInput').value.trim(),
    password:document.getElementById('passwordInput').value
  };
}

async function authRequest(path, okText){
  const body=authBody();
  if(!body.email||!body.password){msg('Email and password are required',false);return;}
  const r=await fetch(API+path,{method:'POST',headers:hdr(),credentials:'same-origin',body:JSON.stringify(body)});
  const d=await r.json().catch(()=>({}));
  if(!r.ok){msg(fmtApiErr(d.detail)||'Authentication failed',false);return;}
  AUTHED=true;
  ADMIN_EMAIL=(d.admin&&d.admin.email)||body.email;
  document.getElementById('passwordInput').value='';
  updateAuthUI();
  msg(okText,true);
  load();
}

function loginAdmin(){ authRequest('/login','Signed in'); }
function signupAdmin(){ authRequest('/signup','Admin account created'); }

async function clearToken(){
  await fetch(API+'/logout',{method:'POST',credentials:'same-origin'}).catch(()=>{});
  AUTHED=false;
  ADMIN_EMAIL='';
  document.getElementById('passwordInput').value='';
  updateAuthUI();
  document.getElementById('statProducts').textContent='—';
  document.getElementById('statOrders').textContent='—';
  document.getElementById('statRevenue').textContent='—';
  document.getElementById('productsTab').innerHTML='<p class="subtle">Sign in to manage products.</p>';
  document.getElementById('ordersTab').innerHTML='<p class="subtle">Sign in to view orders.</p>';
}

function msg(text, ok){
  const b=document.getElementById('msgBox');
  b.innerHTML='<div class="msg '+(ok?'msg-ok':'msg-err')+'">'+escapeHtml(text)+'</div>';
  setTimeout(()=>b.innerHTML='',5000);
}

async function api(path, opts={}){
  const r=await fetch(API+path,{headers:hdr(),credentials:'same-origin',...opts});
  if(r.status===401){
    AUTHED=false;
    ADMIN_EMAIL='';
    updateAuthUI();
    msg('Admin login required',false);
    throw new Error('401');
  }
  if(!r.ok){
    const e=await r.json().catch(()=>({}));
    msg(fmtApiErr(e.detail)||r.statusText,false);
    throw new Error(String(r.status));
  }
  return r.json();
}

async function checkSession(){
  try{
    const r=await fetch(API+'/me',{credentials:'same-origin'});
    if(!r.ok){updateAuthUI();return;}
    const d=await r.json();
    AUTHED=true;
    ADMIN_EMAIL=(d.admin&&d.admin.email)||'admin';
    updateAuthUI();
    load();
  }catch(e){updateAuthUI();}
}

function switchTab(t){
  document.querySelectorAll('.tab').forEach(el=>{
    const name=el.getAttribute('data-tab');
    el.classList.toggle('active',name===t);
  });
  document.getElementById('productsTab').classList.toggle('hidden',t!=='products');
  document.getElementById('ordersTab').classList.toggle('hidden',t!=='orders');
}

function prodThumb(p){
  const u=(p.image_url||'').trim();
  if(!u) return '<span class="prod-thumb-ph" title="No image">—</span>';
  const safe=escapeAttr(u);
  return '<img class="prod-thumb" src="'+safe+'" alt="" loading="lazy" referrerpolicy="no-referrer"/>';
}

async function loadProducts(){
  try{
    const d=await api('/products');
    document.getElementById('statProducts').textContent=d.count;
    let h='<div class="toolbar-row"><button type="button" class="btn btn-primary" onclick="showAddProduct()">+ Add product</button><span class="subtle">'+escapeHtml(d.count)+' SKU(s) · columns match <code class="mono">GET /api/admin/products</code></span></div>';
    h+='<div class="table-wrap"><div class="table-scroll"><table><thead><tr><th></th><th>ID</th><th>Name</th><th>Description</th><th>Category</th><th>Price</th><th>Stock</th><th>Updated</th><th>Actions</th></tr></thead><tbody>';
    d.products.forEach(p=>{
      const desc=(p.description||'').trim();
      const descShort=desc.length>100?desc.slice(0,100)+'…':desc;
      h+='<tr>';
      h+='<td>'+prodThumb(p)+'</td>';
      h+='<td><span class="mono">'+escapeHtml(p.id)+'</span></td>';
      h+='<td class="cell-clamp" title="'+escapeAttr(p.name)+'">'+escapeHtml(p.name)+'</td>';
      h+='<td class="cell-desc" title="'+escapeAttr(desc)+'">'+(desc?escapeHtml(descShort):'<span class="subtle">—</span>')+'</td>';
      h+='<td>'+escapeHtml(p.category)+'</td>';
      h+='<td>$'+Number(p.price).toFixed(2)+'</td>';
      h+='<td><div class="stock-control"><input class="stock-input" type="number" min="0" step="1" value="'+escapeAttr(p.stock)+'" aria-label="Stock for '+escapeAttr(p.name)+'"/>';
      h+='<button type="button" class="btn btn-sm btn-ghost" data-pid="'+escapeAttr(p.id)+'" onclick="saveStockFromBtn(this)">Save</button></div></td>';
      h+='<td class="subtle">'+(p.updated_at?escapeHtml(formatDt(p.updated_at)):'—')+'</td>';
      h+='<td><button type="button" class="btn btn-sm btn-primary" data-pid="'+escapeAttr(p.id)+'" onclick="showEditProductFromBtn(this)">Edit</button> ';
      h+='<button type="button" class="btn btn-sm btn-danger" data-pid="'+escapeAttr(p.id)+'" onclick="delProductFromBtn(this)">Delete</button></td>';
      h+='</tr>';
    });
    h+='</tbody></table></div></div>';
    document.getElementById('productsTab').innerHTML=h;
  }catch(e){}
}

async function loadOrders(){
  try{
    const prev=document.getElementById('orderLimit');
    const lim=(prev&&prev.value)?prev.value:'100';
    const d=await api('/orders?limit='+encodeURIComponent(lim));
    document.getElementById('statOrders').textContent=d.count;
    const rev=d.orders.reduce((s,o)=>s+o.total,0);
    const cur=d.orders.length?((d.orders[0].currency||'USD').trim()||'USD'):'USD';
    document.getElementById('statRevenue').textContent=cur+' '+rev.toFixed(2);
    let h='<div class="toolbar-row">';
    h+='<label class="subtle" for="orderLimit">List limit</label> ';
    h+='<select id="orderLimit" class="select-limit" onchange="loadOrders()"><option value="50">50</option><option value="100">100</option><option value="200">200</option></select>';
    h+='<span class="subtle">Read-only · currency &amp; transaction id · line items via View</span></div>';
    h+='<div class="table-wrap"><div class="table-scroll"><table><thead><tr><th>Order</th><th>Email</th><th>Total</th><th>Status</th><th>Transaction</th><th>Placed</th><th></th></tr></thead><tbody>';
    d.orders.forEach(o=>{
      const bc=orderStatusClass(o.status);
      const cur=(o.currency||'').trim()||'USD';
      h+='<tr>';
      h+='<td><span class="mono">'+escapeHtml(o.id)+'</span></td>';
      h+='<td class="cell-clamp" title="'+escapeAttr(o.customer_email)+'">'+escapeHtml(o.customer_email)+'</td>';
      h+='<td><strong>'+escapeHtml(cur)+'</strong> '+Number(o.total).toFixed(2)+'</td>';
      h+='<td><span class="badge '+bc+'">'+escapeHtml(o.status||'—')+'</span></td>';
      h+='<td class="mono subtle">'+(o.transaction_id?escapeHtml(o.transaction_id):'—')+'</td>';
      h+='<td class="subtle">'+escapeHtml(formatDt(o.created_at))+'</td>';
      h+='<td><button type="button" class="btn btn-sm btn-primary" data-oid="'+escapeAttr(o.id)+'" onclick="showOrderDetailFromBtn(this)">View</button></td>';
      h+='</tr>';
    });
    h+='</tbody></table></div></div>';
    document.getElementById('ordersTab').innerHTML=h;
    const sel=document.getElementById('orderLimit');
    if(sel) sel.value=lim;
  }catch(e){}
}

function load(){ loadProducts(); loadOrders(); }

function closeModal(){ document.getElementById('modalRoot').innerHTML=''; }

function saveStockFromBtn(btn){
  const row=btn.closest('tr');
  const input=row?row.querySelector('.stock-input'):null;
  if(!input)return;
  saveStock(btn.getAttribute('data-pid'),input.value);
}

async function saveStock(id,value){
  const stock=parseInt(value,10);
  if(!id||Number.isNaN(stock)||stock<0){msg('Stock must be a non-negative whole number',false);return;}
  await api('/products/'+encodeURIComponent(id)+'/stock',{method:'PATCH',body:JSON.stringify({stock:stock})});
  msg('Stock updated',true);
  loadProducts();
}

function showAddProduct(){
  document.getElementById('modalRoot').innerHTML=
  '<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">'+
    '<h2>Add product</h2>'+
    '<p class="subtle" style="margin-bottom:16px">Maps to <code class="mono">POST /api/admin/products</code></p>'+
    '<div class="field"><label>ID <span class="lbl-hint">unique SKU</span></label><input id="pId" autocomplete="off"/></div>'+
    '<div class="field"><label>Name</label><input id="pName"/></div>'+
    '<div class="field"><label>Description</label><textarea id="pDesc" class="field-input"></textarea></div>'+
    '<div class="field"><label>Category</label><input id="pCat"/></div>'+
    '<div class="field"><label>Image URL <span class="lbl-hint">optional</span></label><input id="pImg" placeholder="/images/sku-1001.png"/></div>'+
    '<div class="field"><label>Price</label><input id="pPrice" type="number" step="0.01" min="0"/></div>'+
    '<div class="field"><label>Stock</label><input id="pStock" type="number" min="0" step="1"/></div>'+
    '<div class="btn-row">'+
      '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
      '<button type="button" class="btn btn-primary" onclick="addProduct()">Create</button>'+
    '</div>'+
  '</div></div>';
}

async function addProduct(){
  const body={
    id:pId.value.trim(),name:pName.value.trim(),description:pDesc.value,category:pCat.value.trim(),
    image_url:pImg.value.trim(),price:parseFloat(pPrice.value),stock:parseInt(pStock.value,10)||0
  };
  if(!body.id||!body.name){msg('ID and name are required',false);return;}
  await api('/products',{method:'POST',body:JSON.stringify(body)});
  closeModal();msg('Product created',true);loadProducts();loadOrders();
}

function showEditProductFromBtn(el){ showEditProduct(el.getAttribute('data-pid')); }

async function showEditProduct(id){
  if(!id)return;
  const d=await api('/products');
  const p=d.products.find(x=>x.id===id);
  if(!p)return;
  document.getElementById('modalRoot').innerHTML=
  '<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">'+
    '<h2>Edit product</h2>'+
    '<input type="hidden" id="editPid" value="'+escapeAttr(id)+'"/>'+
    '<p class="subtle" style="margin-bottom:16px"><code class="mono">PUT /api/admin/products/%s</code></p>'.replace('%s', escapeHtml(id))+
    '<div class="field"><label>Name</label><input id="eName" value="'+escapeAttr(p.name)+'"/></div>'+
    '<div class="field"><label>Description</label><textarea id="eDesc" class="field-input">'+escapeHtml(p.description||'')+'</textarea></div>'+
    '<div class="field"><label>Category</label><input id="eCat" value="'+escapeAttr(p.category)+'"/></div>'+
    '<div class="field"><label>Image URL</label><input id="eImg" value="'+escapeAttr(p.image_url||'')+'"/></div>'+
    '<div class="field"><label>Price</label><input id="ePrice" type="number" step="0.01" min="0" value="'+escapeAttr(p.price)+'"/></div>'+
    '<div class="field"><label>Stock</label><input id="eStock" type="number" min="0" step="1" value="'+escapeAttr(p.stock)+'"/></div>'+
    '<div class="btn-row">'+
      '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
      '<button type="button" class="btn btn-primary" onclick="submitEditProduct()">Save</button>'+
    '</div>'+
  '</div></div>';
}

async function submitEditProduct(){
  const id=document.getElementById('editPid').value;
  if(!id)return;
  const body={
    name:eName.value.trim(),description:eDesc.value,category:eCat.value.trim(),
    image_url:eImg.value.trim(),price:parseFloat(ePrice.value),stock:parseInt(eStock.value,10)||0
  };
  await api('/products/'+encodeURIComponent(id),{method:'PUT',body:JSON.stringify(body)});
  closeModal();msg('Product updated',true);loadProducts();
}

function delProductFromBtn(el){ delProduct(el.getAttribute('data-pid')); }

async function delProduct(id){
  if(!id)return;
  if(!confirm('Delete product '+id+'?'))return;
  await api('/products/'+encodeURIComponent(id),{method:'DELETE'});
  msg('Product deleted',true);loadProducts();
}

function showOrderDetailFromBtn(el){ showOrderDetail(el.getAttribute('data-oid')); }

async function showOrderDetail(orderId){
  if(!orderId)return;
  const o=await api('/orders/'+encodeURIComponent(orderId));
  const items=o.items||[];
  let rows='';
  items.forEach(it=>{
    const line=(it.quantity||0)*(it.unit_price||0);
    rows+='<tr><td><span class="mono">'+escapeHtml(it.product_id)+'</span></td><td>'+escapeHtml(it.product_name||'')+'</td>'+
      '<td>'+escapeHtml(String(it.quantity))+'</td><td>'+Number(it.unit_price).toFixed(2)+'</td><td><strong>'+line.toFixed(2)+'</strong></td></tr>';
  });
  const cur=(o.currency||'').trim()||'USD';
  document.getElementById('modalRoot').innerHTML=
  '<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal modal-lg">'+
    '<h2>Order detail</h2>'+
    '<p class="subtle" style="margin-bottom:12px"><code class="mono">GET /api/admin/orders/'+escapeHtml(o.id)+'</code> · read-only</p>'+
    '<div class="detail-meta">'+
      '<div><strong>Order</strong> <span class="mono">'+escapeHtml(o.id)+'</span></div>'+
      '<div><strong>Customer</strong> '+escapeHtml(o.customer_email||'—')+'</div>'+
      '<div><strong>Total</strong> '+escapeHtml(cur)+' '+Number(o.total).toFixed(2)+'</div>'+
      '<div><strong>Status</strong> '+escapeHtml(o.status||'—')+'</div>'+
      '<div><strong>Transaction</strong> '+(o.transaction_id?'<span class="mono">'+escapeHtml(o.transaction_id)+'</span>':'—')+'</div>'+
      '<div><strong>Placed</strong> '+escapeHtml(formatDt(o.created_at))+'</div>'+
    '</div>'+
    '<h3 class="subtle" style="margin-bottom:10px;font-size:0.85rem;text-transform:uppercase;letter-spacing:0.06em">Line items</h3>'+
    '<div class="table-wrap" style="margin-bottom:0"><div class="table-scroll">'+
    '<table><thead><tr><th>SKU</th><th>Name</th><th>Qty</th><th>Unit</th><th>Line</th></tr></thead><tbody>'+
    (rows||'<tr><td colspan="5" class="subtle">No line items</td></tr>')+
    '</tbody></table></div></div>'+
    '<div class="btn-row"><button type="button" class="btn btn-primary" onclick="closeModal()">Close</button></div>'+
  '</div></div>';
}

updateAuthUI();
checkSession();
</script>
</body>
</html>"""
