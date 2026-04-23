// ShopCloud storefront — talks to the backend microservices through
// the public ALB (same origin). All API paths are prefixed with /api.

const API = {
  catalog:  "/api/catalog",
  cart:    (userId) => `/api/cart/${userId}`,
  checkout: "/api/checkout",
  auth:     "/api/auth/config",
};

const state = {
  products: [],
  cart: [],
  userId: "demo-user",
};

function $(sel) { return document.querySelector(sel); }

function setStatus(msg, kind) {
  const el = $("#status");
  el.textContent = msg;
  el.className = kind || "";
}

async function loadCatalog() {
  setStatus("Loading catalog…");
  try {
    const res = await fetch(API.catalog);
    if (!res.ok) throw new Error(`${res.status}`);
    const data = await res.json();
    state.products = data.products || [];
    $("#region").textContent = data.region || "—";
    renderCatalog();
    setStatus(`Loaded ${state.products.length} products from ${data.region}.`, "ok");
  } catch (err) {
    setStatus(`Failed to load catalog: ${err.message}`, "err");
  }
}

function renderCatalog() {
  const host = $("#products");
  host.innerHTML = "";
  for (const p of state.products) {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <div class="sku">${p.id}</div>
      <h3>${p.name}</h3>
      <div class="price">$${p.price.toFixed(2)}</div>
      <button data-id="${p.id}">Add to cart</button>
    `;
    card.querySelector("button").onclick = () => addToCart(p);
    host.appendChild(card);
  }
}

function addToCart(product) {
  const existing = state.cart.find((i) => i.id === product.id);
  if (existing) existing.qty += 1;
  else state.cart.push({ ...product, qty: 1 });
  renderCart();
}

function renderCart() {
  const host = $("#cart-items");
  host.innerHTML = "";
  let total = 0;
  for (const item of state.cart) {
    const row = document.createElement("div");
    row.className = "cart-row";
    row.innerHTML = `<span>${item.name} × ${item.qty}</span>
                     <span>$${(item.qty * item.price).toFixed(2)}</span>`;
    host.appendChild(row);
    total += item.qty * item.price;
  }
  $("#cart-total").textContent = state.cart.length
    ? `Total: $${total.toFixed(2)}`
    : "Cart is empty.";
  $("#cart-count").textContent = state.cart.reduce((n, i) => n + i.qty, 0);
  $("#checkout-btn").disabled = state.cart.length === 0;
}

async function checkout() {
  if (state.cart.length === 0) return;
  const total = state.cart.reduce((n, i) => n + i.qty * i.price, 0);
  setStatus("Placing order…");
  try {
    const res = await fetch(API.checkout, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        customer_email: "demo@shopcloud.com",
        items: state.cart,
        total: Number(total.toFixed(2)),
        currency: "USD",
      }),
    });
    if (!res.ok) throw new Error(`${res.status}`);
    const data = await res.json();
    state.cart = [];
    renderCart();
    setStatus(`Order ${data.order_id} placed. Invoice email dispatched.`, "ok");
  } catch (err) {
    setStatus(`Checkout failed: ${err.message}`, "err");
  }
}

window.loadCatalog = loadCatalog;
window.checkout    = checkout;

document.addEventListener("DOMContentLoaded", () => {
  loadCatalog();
  renderCart();
});
