import re

new_html = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<meta name="theme-color" content="#0B0E14"/>
<title>ShopCloud — Premium Infrastructure Gear</title>
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
/* Ambient Orbs */
.orb {
  position: fixed; border-radius: 50%; filter: blur(120px); opacity: 0.35; z-index: -1;
  pointer-events: none; animation: float 14s infinite alternate ease-in-out;
}
.orb.purple { background: var(--accent-purple); width: 500px; height: 500px; top: -150px; left: -100px; animation-delay: -2s; }
.orb.cyan { background: var(--accent-cyan); width: 400px; height: 400px; bottom: -100px; right: -50px; }
@keyframes float { 0% { transform: translate(0, 0) scale(1); } 100% { transform: translate(30px, 40px) scale(1.1); } }

a { color: var(--accent-cyan); text-decoration: none; transition: color 0.2s; }
a:hover { color: #FFF; }

/* Header */
.hdr-wrap { position: sticky; top: 0; z-index: 50; padding: 16px 24px 0; }
.hdr {
  max-width: 1200px; margin: 0 auto; display: flex; align-items: center; gap: 20px;
  padding: 12px 24px; background: var(--bg-glass);
  backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
  border: 1px solid var(--border-light); border-radius: var(--radius);
  box-shadow: 0 8px 32px rgba(0,0,0,0.4);
}
.hdr .logo { font-family: var(--font-display); font-size: 1.6rem; font-weight: 800; color: #FFF; letter-spacing: -0.02em; cursor: pointer; }
.hdr .logo span { background: linear-gradient(135deg, var(--accent-cyan), var(--accent-purple)); -webkit-background-clip: text; color: transparent; }
.hdr .tag { font-size: 0.75rem; color: var(--text-muted); font-weight: 600; letter-spacing: 0.1em; text-transform: uppercase; }
.hdr .spacer { flex: 1; }
.search-wrap { position: relative; max-width: 320px; width: 100%; }
.search-wrap svg { position: absolute; left: 16px; top: 50%; transform: translateY(-50%); width: 18px; color: var(--text-muted); pointer-events: none; }
.search {
  width: 100%; padding: 10px 16px 10px 44px; background: rgba(0,0,0,0.2);
  border: 1px solid var(--border-light); border-radius: 999px;
  color: var(--text-main); font-family: var(--font-body); font-size: 0.9rem;
  transition: all 0.3s ease;
}
.search::placeholder { color: var(--text-muted); }
.search:focus { outline: none; border-color: var(--accent-cyan); background: rgba(0,0,0,0.4); box-shadow: var(--shadow-glow); }
.hdr-actions { display: flex; align-items: center; gap: 16px; }

/* Buttons */
.btn-icon {
  position: relative; background: rgba(255,255,255,0.05); border: 1px solid var(--border-light);
  width: 44px; height: 44px; border-radius: 50%; display: flex; align-items: center; justify-content: center;
  color: var(--text-main); cursor: pointer; transition: all 0.2s;
}
.btn-icon:hover { background: rgba(255,255,255,0.1); border-color: var(--border-hover); transform: translateY(-2px); box-shadow: var(--shadow-glow); }
.btn-icon .count {
  position: absolute; top: -2px; right: -4px; background: var(--accent-purple); color: #FFF;
  font-size: 10px; font-weight: 700; border-radius: 10px; padding: 2px 6px; border: 2px solid var(--bg-surface);
}
.btn-icon .count:empty, .btn-icon .count[data-n="0"] { display: none; }

.auth-btn {
  padding: 10px 20px; border-radius: 999px; border: none;
  background: linear-gradient(135deg, var(--accent-cyan), #0284C7); color: #FFF;
  font-family: var(--font-display); font-size: 0.9rem; font-weight: 600; cursor: pointer;
  transition: all 0.3s; box-shadow: 0 4px 15px rgba(6, 182, 212, 0.3);
}
.auth-btn:hover { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(6, 182, 212, 0.5); filter: brightness(1.1); }
.auth-btn.ghost { background: transparent; border: 1px solid var(--border-light); box-shadow: none; color: var(--text-main); }
.auth-btn.ghost:hover { background: rgba(255,255,255,0.05); border-color: var(--text-muted); }
.user-badge { font-size: 0.85rem; color: var(--text-muted); max-width: 150px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* Hero */
.hero { max-width: 1200px; margin: 40px auto; padding: 0 24px; text-align: center; position: relative; }
.hero-inner {
  padding: 80px 40px; border-radius: 32px; background: var(--bg-glass-card);
  border: 1px solid var(--border-light); backdrop-filter: blur(10px);
  box-shadow: 0 20px 40px rgba(0,0,0,0.5); position: relative; overflow: hidden;
}
.hero-inner::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 1px; background: linear-gradient(90deg, transparent, var(--accent-cyan), transparent); opacity: 0.5; }
.hero h1 { font-family: var(--font-display); font-size: clamp(2.5rem, 6vw, 4rem); font-weight: 800; line-height: 1.1; margin-bottom: 20px; letter-spacing: -0.03em; }
.hero p { font-size: 1.1rem; color: var(--text-muted); max-width: 600px; margin: 0 auto 30px; }
.hero-badge {
  display: inline-flex; align-items: center; gap: 8px; padding: 6px 14px; border-radius: 999px;
  background: rgba(6, 182, 212, 0.1); border: 1px solid rgba(6, 182, 212, 0.3);
  color: var(--accent-cyan); font-weight: 600; font-size: 0.8rem; margin-bottom: 24px; text-transform: uppercase; letter-spacing: 0.05em;
}

/* Toolbar */
.toolbar-wrap { max-width: 1200px; margin: 40px auto 20px; padding: 0 24px; }
.category-chips { display: flex; flex-wrap: wrap; gap: 12px; }
.chip {
  padding: 10px 24px; border-radius: 999px; border: 1px solid var(--border-light);
  background: var(--bg-glass-card); color: var(--text-muted); font-family: var(--font-display);
  font-size: 0.95rem; font-weight: 600; cursor: pointer; transition: all 0.3s;
  backdrop-filter: blur(10px);
}
.chip:hover { border-color: var(--accent-purple); color: #FFF; background: rgba(139, 92, 246, 0.1); transform: translateY(-2px); box-shadow: var(--shadow-glow-purple); }
.chip-active { background: linear-gradient(135deg, var(--accent-purple), #6D28D9); color: #FFF; border-color: transparent; box-shadow: var(--shadow-glow-purple); }

/* Grid */
.wrap { max-width: 1200px; margin: 0 auto; padding: 20px 24px 80px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 32px; }
.card {
  background: var(--bg-surface); border: 1px solid var(--border-light); border-radius: var(--radius);
  overflow: hidden; position: relative; display: flex; flex-direction: column;
  transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
}
.card::after { content: ''; position: absolute; inset: 0; border-radius: var(--radius); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.05); pointer-events: none; }
.card:hover { transform: translateY(-10px); border-color: var(--border-hover); box-shadow: 0 20px 40px rgba(0,0,0,0.6), var(--shadow-glow); z-index: 10; }
.card-visual { width: 100%; aspect-ratio: 4/3; overflow: hidden; background: #000; position: relative; }
.card-visual img { width: 100%; height: 100%; object-fit: cover; transition: transform 0.6s ease; opacity: 0.85; }
.card:hover .card-visual img { transform: scale(1.1); opacity: 1; }
.card-visual-fallback { display: flex; align-items: center; justify-content: center; font-family: var(--font-display); font-size: 4rem; color: rgba(255,255,255,0.1); background: linear-gradient(135deg, #1A1A24, #0B0E14); }
.category-pill {
  position: absolute; top: 16px; left: 16px; font-size: 0.7rem; font-weight: 700; text-transform: uppercase;
  padding: 6px 12px; border-radius: 8px; background: rgba(0,0,0,0.6); color: var(--accent-cyan);
  backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.1); letter-spacing: 0.05em;
}
.card .body { padding: 24px; display: flex; flex-direction: column; flex: 1; background: linear-gradient(180deg, transparent, rgba(0,0,0,0.4)); }
.card h3 { font-family: var(--font-display); font-size: 1.25rem; font-weight: 700; margin-bottom: 8px; color: #FFF; }
.card .desc { font-size: 0.9rem; color: var(--text-muted); margin-bottom: 20px; flex: 1; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.card .row { display: flex; align-items: flex-end; justify-content: space-between; margin-bottom: 20px; }
.card .price { font-family: var(--font-display); font-size: 1.5rem; font-weight: 800; color: #FFF; }
.card .stock { font-size: 0.8rem; color: var(--text-muted); font-weight: 500; }
.card .stock.low { color: #F59E0B; }
.add-btn {
  width: 100%; padding: 12px; border-radius: var(--radius-sm); border: none;
  background: rgba(255,255,255,0.05); color: #FFF; font-family: var(--font-display);
  font-size: 0.95rem; font-weight: 600; cursor: pointer; transition: all 0.3s;
  border: 1px solid rgba(255,255,255,0.1);
}
.card:hover .add-btn { background: linear-gradient(135deg, var(--accent-cyan), #0284C7); border-color: transparent; box-shadow: 0 4px 15px rgba(6, 182, 212, 0.4); }
.add-btn:active { transform: scale(0.97); }
.add-btn:disabled { background: rgba(255,255,255,0.02); color: rgba(255,255,255,0.2); cursor: not-allowed; border-color: transparent; box-shadow: none; }

/* Empty state */
.empty-state { grid-column: 1/-1; text-align: center; padding: 80px 20px; border-radius: var(--radius); background: var(--bg-glass-card); border: 1px dashed rgba(255,255,255,0.2); backdrop-filter: blur(10px); }
.empty-state h2 { font-family: var(--font-display); font-size: 1.5rem; margin-bottom: 10px; }

/* Drawer */
.drawer-bg { position: fixed; inset: 0; background: rgba(0,0,0,0.6); backdrop-filter: blur(8px); z-index: 100; opacity: 0; pointer-events: none; transition: opacity 0.4s ease; }
.drawer-bg.open { opacity: 1; pointer-events: auto; }
.drawer {
  position: fixed; top: 16px; right: 16px; bottom: 16px; width: min(440px, calc(100vw - 32px));
  background: var(--bg-surface); z-index: 101; border-radius: var(--radius); border: 1px solid var(--border-light);
  box-shadow: -10px 0 40px rgba(0,0,0,0.8); transform: translateX(calc(100% + 32px)); transition: transform 0.5s cubic-bezier(0.16, 1, 0.3, 1);
  display: flex; flex-direction: column; overflow: hidden;
}
.drawer.open { transform: translateX(0); }
.drawer .dh { padding: 24px; border-bottom: 1px solid var(--border-light); display: flex; align-items: center; justify-content: space-between; background: rgba(0,0,0,0.2); }
.drawer .dh h2 { font-family: var(--font-display); font-size: 1.4rem; font-weight: 700; }
.drawer .close-btn { background: rgba(255,255,255,0.05); border: 1px solid transparent; width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 20px; color: var(--text-muted); cursor: pointer; transition: all 0.2s; }
.drawer .close-btn:hover { background: rgba(255,255,255,0.1); border-color: var(--border-light); color: #FFF; transform: rotate(90deg); }
.drawer .items { flex: 1; overflow-y: auto; padding: 20px 24px; }
.drawer .empty { text-align: center; color: var(--text-muted); padding: 60px 20px; font-size: 1rem; }
.ci { display: flex; gap: 16px; padding: 20px 0; border-bottom: 1px solid var(--border-light); }
.ci:last-child { border-bottom: none; }
.ci .ci-info { flex: 1; }
.ci .ci-name { font-family: var(--font-display); font-size: 1.1rem; font-weight: 700; color: #FFF; margin-bottom: 4px; }
.ci .ci-price { font-size: 0.9rem; color: var(--accent-cyan); font-weight: 600; }
.ci .ci-qty { display: flex; align-items: center; gap: 12px; margin-top: 12px; }
.ci .ci-qty button { width: 32px; height: 32px; border-radius: 8px; border: 1px solid var(--border-light); background: rgba(255,255,255,0.05); color: #FFF; cursor: pointer; font-size: 16px; transition: all 0.2s; }
.ci .ci-qty button:hover { background: rgba(255,255,255,0.15); border-color: var(--accent-cyan); }
.ci .ci-qty span { font-size: 1rem; font-weight: 600; min-width: 20px; text-align: center; }
.ci .ci-remove { background: none; border: none; color: #EF4444; cursor: pointer; font-size: 0.8rem; font-weight: 600; margin-top: 12px; transition: color 0.2s; }
.ci .ci-remove:hover { color: #F87171; text-decoration: underline; }
.ci .ci-sub { font-family: var(--font-display); font-size: 1.2rem; font-weight: 800; }
.drawer .footer { padding: 24px; border-top: 1px solid var(--border-light); background: rgba(0,0,0,0.3); }
.drawer .total { display: flex; justify-content: space-between; align-items: center; font-size: 1.2rem; margin-bottom: 20px; color: var(--text-muted); }
.drawer .total span:last-child { font-family: var(--font-display); font-size: 1.8rem; font-weight: 800; color: #FFF; }
.checkout-btn { width: 100%; padding: 16px; border-radius: var(--radius-sm); border: none; background: linear-gradient(135deg, var(--accent-purple), #6D28D9); color: #FFF; font-family: var(--font-display); font-size: 1.1rem; font-weight: 700; cursor: pointer; box-shadow: var(--shadow-glow-purple); transition: all 0.3s; }
.checkout-btn:hover { filter: brightness(1.1); transform: translateY(-2px); box-shadow: 0 8px 25px rgba(139, 92, 246, 0.4); }

/* Modals */
.modal-bg { position: fixed; inset: 0; background: rgba(0,0,0,0.7); backdrop-filter: blur(10px); display: flex; align-items: center; justify-content: center; z-index: 200; padding: 20px; animation: fadeIn 0.3s ease; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
.modal { background: var(--bg-surface); border-radius: var(--radius); padding: 40px; width: 480px; max-width: 100%; border: 1px solid var(--border-light); box-shadow: 0 24px 48px rgba(0,0,0,0.8), inset 0 1px 0 rgba(255,255,255,0.1); position: relative; overflow: hidden; animation: slideUp 0.4s cubic-bezier(0.16, 1, 0.3, 1); }
.modal::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px; background: linear-gradient(90deg, var(--accent-cyan), var(--accent-purple)); }
@keyframes slideUp { from { opacity: 0; transform: translateY(40px) scale(0.95); } to { opacity: 1; transform: translateY(0) scale(1); } }
.modal h2 { font-family: var(--font-display); font-size: 1.8rem; margin-bottom: 24px; color: #FFF; font-weight: 800; }
.field { margin-bottom: 20px; }
.field label { display: block; font-size: 0.8rem; color: var(--text-muted); margin-bottom: 8px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; }
.field input { width: 100%; padding: 14px 16px; border: 1px solid rgba(255,255,255,0.1); border-radius: var(--radius-sm); font-size: 1rem; background: rgba(0,0,0,0.3); color: #FFF; transition: all 0.3s; font-family: var(--font-body); }
.field input:focus { outline: none; border-color: var(--accent-cyan); background: rgba(0,0,0,0.5); box-shadow: 0 0 0 4px rgba(6, 182, 212, 0.15); }
.btn-row { display: flex; gap: 12px; justify-content: flex-end; margin-top: 32px; align-items: center; }
.btn { padding: 12px 24px; border-radius: var(--radius-sm); border: none; cursor: pointer; font-size: 0.95rem; font-weight: 600; transition: all 0.2s; font-family: var(--font-display); }
.btn-primary { background: linear-gradient(135deg, var(--accent-cyan), #0284C7); color: #FFF; box-shadow: 0 4px 15px rgba(6, 182, 212, 0.3); }
.btn-primary:hover { filter: brightness(1.1); transform: translateY(-2px); }
.btn-ghost { background: transparent; color: var(--text-muted); border: 1px solid var(--border-light); }
.btn-ghost:hover { border-color: #FFF; color: #FFF; background: rgba(255,255,255,0.05); }
.btn-link { background: none; border: none; color: var(--accent-purple); cursor: pointer; font-size: 0.9rem; padding: 0; font-weight: 600; transition: color 0.2s; }
.btn-link:hover { color: #A78BFA; text-decoration: underline; }
.alert { padding: 12px 16px; border-radius: var(--radius-sm); font-size: 0.9rem; margin-bottom: 20px; font-weight: 500; }
.alert-err { background: rgba(239, 68, 68, 0.1); color: #FCA5A5; border: 1px solid rgba(239, 68, 68, 0.2); }
.alert-ok { background: rgba(16, 185, 129, 0.1); color: #6EE7B7; border: 1px solid rgba(16, 185, 129, 0.2); }

.confirm-box { text-align: center; }
.confirm-box .icon { font-size: 64px; margin-bottom: 20px; text-shadow: 0 0 30px rgba(16, 185, 129, 0.4); animation: bounceIn 0.6s cubic-bezier(0.175, 0.885, 0.32, 1.275); }
@keyframes bounceIn { 0% { transform: scale(0); } 50% { transform: scale(1.2); } 100% { transform: scale(1); } }
.confirm-box h2 { color: #34D399; margin-bottom: 12px; }
.confirm-box .oid { font-family: monospace; font-size: 0.9rem; color: var(--text-muted); margin-bottom: 30px; background: rgba(0,0,0,0.3); padding: 8px; border-radius: 8px; border: 1px solid var(--border-light); }
.confirm-box table { width: 100%; text-align: left; margin: 24px 0; border-collapse: collapse; }
.confirm-box th { color: var(--text-muted); font-weight: 600; padding: 12px 0; border-bottom: 1px solid rgba(255,255,255,0.1); font-size: 0.85rem; text-transform: uppercase; }
.confirm-box td { padding: 16px 0; border-bottom: 1px solid rgba(255,255,255,0.05); font-size: 0.95rem; }
.continue-btn { margin-top: 30px; padding: 16px 32px; border-radius: 999px; border: none; background: rgba(255,255,255,0.1); color: #FFF; cursor: pointer; font-size: 1rem; font-weight: 600; transition: all 0.2s; border: 1px solid rgba(255,255,255,0.2); font-family: var(--font-display); }
.continue-btn:hover { background: rgba(255,255,255,0.2); border-color: #FFF; transform: translateY(-2px); }
</style>
</head>
<body>

<div class="orb purple"></div>
<div class="orb cyan"></div>

<div class="hdr-wrap">
<header class="hdr">
  <div class="logo" onclick="window.scrollTo(0,0)">Shop<span>Cloud</span></div>
  <div class="spacer" aria-hidden="true"></div>
  <div class="search-wrap">
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path stroke-linecap="round" d="M20 20l-3-3"/></svg>
    <input class="search" id="q" placeholder="Search components, merch..." autocomplete="off"/>
  </div>
  <div class="hdr-actions">
    <button type="button" class="btn-icon" onclick="openCart()" title="Open cart" aria-label="Shopping cart">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"/></svg>
      <span class="count" id="cartCount" data-n="0"></span>
    </button>
    <span class="user-badge" id="userBadge"></span>
    <button type="button" class="auth-btn" id="authBtn" onclick="showLogin()">Sign In</button>
  </div>
</header>
</div>

<section class="hero">
  <div class="hero-inner">
    <div class="hero-badge"><span></span> Verified Cloud Native</div>
    <h1>Gear built for<br/>builders who ship.</h1>
    <p>Browse curated merch, notebooks, and essentials. Fast cart, instant checkout, and a storefront that feels as polished as your infrastructure.</p>
    <button type="button" class="auth-btn" style="padding: 14px 32px; font-size: 1.05rem;" onclick="document.getElementById('catalog').scrollIntoView({behavior:'smooth'})">Explore Catalog</button>
  </div>
</section>

<div class="toolbar-wrap">
  <div class="category-chips" id="categoryChips"></div>
</div>

<div class="wrap" id="catalog"><div class="grid" id="products"></div></div>

<div class="drawer-bg" id="drawerBg" onclick="closeCart()" aria-hidden="true"></div>
<div class="drawer" id="drawer" role="dialog" aria-label="Shopping cart">
  <div class="dh"><h2>Your Cart</h2><button type="button" class="close-btn" onclick="closeCart()" aria-label="Close">&times;</button></div>
  <div class="items" id="cartItems"></div>
  <div class="footer" id="cartFooter" style="display:none">
    <div class="total"><span>Estimated Total</span><span id="cartTotal">$0.00</span></div>
    <button type="button" class="checkout-btn" onclick="showCheckout()">Secure Checkout →</button>
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
  wrap.innerHTML='<button type="button" class="chip chip-active" data-cat="">All Drops</button>';
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
    $('products').innerHTML='<div class="empty-state"><h2>Offline</h2><p>Our uplink to the product database is temporarily down.</p></div>';
  }
}

function renderProducts(list){
  if(!list.length){
    $('products').innerHTML='<div class="empty-state"><h2>No matches found</h2><p>Try adjusting your search query.</p></div>';
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
    return '<article class="card">'+
      vis+'<span class="category-pill">'+escH(p.category)+'</span>'+
      '<div class="body"><h3>'+escH(p.name)+'</h3>'+
      '<p class="desc">'+escH(p.description)+'</p>'+
      '<div class="row"><span class="price">$'+Number(p.price).toFixed(2)+'</span>'+
      '<span class="stock'+(low?' low':'')+'">'+(oos?'Out of stock':p.stock+' units left')+'</span></div>'+
      '<button type="button" class="add-btn" '+(oos?'disabled':'')+
      " onclick='addToCart("+JSON.stringify(p.id)+","+JSON.stringify(p.name)+","+Number(p.price)+")'>"+(oos?'Sold Out':'Add to Loadout')+"</button>"+
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
    $('cartItems').innerHTML='<div class="empty">Your cart is empty. Add some gear!</div>';
    $('cartFooter').style.display='none';
    return;
  }
  let total=0;
  $('cartItems').innerHTML=items.map(function(it,i){
    const sub=it.quantity*it.unit_price; total+=sub;
    const label=it.product_name&&String(it.product_name).trim()?it.product_name:it.product_id;
    return '<div class="ci"><div class="ci-info">'+
      '<div class="ci-name">'+escH(label)+'</div>'+
      '<div class="ci-price">$'+it.unit_price.toFixed(2)+' per unit</div>'+
      '<div class="ci-qty">'+
      '<button type="button" onclick="changeQty('+i+',-1)" aria-label="Decrease">&minus;</button>'+
      '<span>'+it.quantity+'</span>'+
      '<button type="button" onclick="changeQty('+i+',1)" aria-label="Increase">+</button></div>'+
      '<button type="button" class="ci-remove" onclick="removeItem('+i+')">Remove Item</button></div>'+
      '<div class="ci-sub">$'+sub.toFixed(2)+'</div></div>';
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
    '<h2>Welcome Back</h2><div id="authAlert"></div>'+
    '<div class="field"><label>Email Address</label><input id="lEmail" type="email" autocomplete="username" placeholder="name@domain.com"/></div>'+
    '<div class="field"><label>Password</label><input id="lPass" type="password" autocomplete="current-password" placeholder="••••••••"/></div>'+
    '<div class="btn-row">'+
    '<button type="button" class="btn-link" onclick="showSignup()">Create an account</button>'+
    '<div style="flex:1"></div>'+
    '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
    '<button type="button" class="btn btn-primary" onclick="doLogin()">Authenticate</button></div></div></div>';
}

function showSignup(){
  $('modalRoot').innerHTML='<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal">'+
    '<h2>Initialize Account</h2><div id="authAlert"></div>'+
    '<div class="field"><label>Email Address</label><input id="sEmail" type="email" autocomplete="email" placeholder="name@domain.com"/></div>'+
    '<div class="field"><label>Password</label><input id="sPass" type="password" autocomplete="new-password" placeholder="Secure password"/></div>'+
    '<div class="btn-row">'+
    '<button type="button" class="btn-link" onclick="showLogin()">Already registered?</button>'+
    '<div style="flex:1"></div>'+
    '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
    '<button type="button" class="btn btn-primary" onclick="doSignup()">Provision Account</button></div></div></div>';
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
      setErr('Could not save session: '+se.message);
      return;
    }
    updateAuthUI(); closeModal();
  }catch(e){
    setErr(e&&e.message?e.message:'Network error');
  }
}

async function doSignup(){
  const email=$('sEmail').value, pass=$('sPass').value;
  try{
    const r=await fetch('/api/auth/customer/signup',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({email:email,password:pass})});
    if(!r.ok){const e=await r.json();$('authAlert').innerHTML='<div class="alert alert-err">'+(e.detail?.message||e.detail||'Signup failed')+'</div>';return;}
    $('authAlert').innerHTML='<div class="alert alert-ok">Account successfully provisioned! You can sign in now.</div>';
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
  $('modalRoot').innerHTML='<div class="modal-bg" onclick="if(event.target===this)closeModal()"><div class="modal" style="width: 540px;">'+
    '<h2>Secure Checkout</h2><div id="coAlert"></div>'+
    '<table style="width:100%;font-size:14px;margin-bottom:24px">'+
    '<tr><th>Product</th><th>Qty</th><th>Subtotal</th></tr>'+rows+
    '<tr style="font-weight:800;font-family:var(--font-display);font-size:1.1rem;"><td colspan="2">Total</td><td style="color:var(--accent-cyan)">$'+total.toFixed(2)+'</td></tr></table>'+
    '<div class="field"><label>Email Address</label><input id="coEmail" type="email" value="'+escAttr(USER_EMAIL)+'"/></div>'+
    '<div class="btn-row">'+
    '<button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>'+
    '<button type="button" class="btn btn-primary" id="placeBtn" onclick="placeOrder()">Confirm & Place Order</button></div></div></div>';
}

async function placeOrder(){
  const email=$('coEmail').value.trim();
  if(!email){$('coAlert').innerHTML='<div class="alert alert-err">Email is required</div>';return;}
  $('placeBtn').disabled=true;$('placeBtn').textContent='Processing Transaction...';
  const items=cart.items.map(function(i){return {product_id:i.product_id,product_name:i.product_id,quantity:i.quantity,unit_price:i.unit_price}});
  const total=items.reduce(function(s,i){return s+i.quantity*i.unit_price},0);
  try{
    const r=await fetch('/api/checkout',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({customer_email:email,items:items,total:total})});
    const d=await r.json();
    if(!r.ok&&r.status!==207){$('coAlert').innerHTML='<div class="alert alert-err">'+(d.detail||'Checkout failed')+'</div>';$('placeBtn').disabled=false;$('placeBtn').textContent='Confirm & Place Order';return;}
    await fetch('/api/cart/'+SID,{method:'DELETE'});
    cart={items:[]};updateCartBadge();
    showConfirmation(d,items,total);
    loadProducts();
  }catch(e){$('coAlert').innerHTML='<div class="alert alert-err">Network error</div>';$('placeBtn').disabled=false;$('placeBtn').textContent='Confirm & Place Order';}
}

function showConfirmation(order,items,total){
  let rows=items.map(function(i){return '<tr><td>'+escH(i.product_id)+'</td><td>'+i.quantity+'</td><td>$'+(i.quantity*i.unit_price).toFixed(2)+'</td></tr>'}).join('');
  $('modalRoot').innerHTML='<div class="modal-bg"><div class="modal confirm-box">'+
    '<div class="icon">\u2728</div>'+
    '<h2>Order Verified</h2>'+
    '<div class="oid">TX_ID: '+escH(order.order_id)+'</div>'+
    '<table><tr><th>Item</th><th>Qty</th><th>Subtotal</th></tr>'+rows+
    '<tr style="font-weight:800;font-family:var(--font-display);font-size:1.1rem;color:#FFF"><td colspan="2">Total Settled</td><td>$'+total.toFixed(2)+'</td></tr></table>'+
    '<p style="font-size:0.9rem;color:var(--text-muted);margin-top:20px">Receipt dispatched to '+escH(order.customer_email)+'</p>'+
    '<button type="button" class="continue-btn" onclick="closeModal()">Back to Catalog</button></div></div>';
}

updateAuthUI();
loadCategories().catch(function(e){console.error('categories',e)}).finally(loadProducts);
loadCart();
</script>
</body>
</html>'''

with open(r'c:\Users\Hussein\Desktop\shopcloud\services\catalog\app.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace using regex
pattern = re.compile(r'_STOREFRONT_HTML\s*=\s*r"""<!doctype html>.*?</html>"""', re.DOTALL)
new_content = pattern.sub(f'_STOREFRONT_HTML = r"""{new_html}"""', content)

with open(r'c:\Users\Hussein\Desktop\shopcloud\services\catalog\app.py', 'w', encoding='utf-8') as f:
    f.write(new_content)
print("Updated successfully")
