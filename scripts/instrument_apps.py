import os
import re

SERVICES = ["catalog", "checkout", "cart", "auth", "admin"]
BASE_DIR = r"c:\Users\Hussein\Desktop\shopcloud\services"

def instrument_service(service):
    app_py = os.path.join(BASE_DIR, service, "app.py")
    req_txt = os.path.join(BASE_DIR, service, "requirements.txt")
    
    # 1. Update requirements.txt
    if os.path.exists(req_txt):
        with open(req_txt, "r") as f:
            reqs = f.read()
        if "prometheus-client" not in reqs:
            with open(req_txt, "a") as f:
                f.write("\nprometheus-client==0.20.0\nprometheus-fastapi-instrumentator==7.0.0\n")
    
    # 2. Update app.py
    if not os.path.exists(app_py):
        return
        
    with open(app_py, "r", encoding="utf-8") as f:
        content = f.read()
        
    if "prometheus_fastapi_instrumentator" in content:
        return # already instrumented
        
    # Inject imports
    imports = "from prometheus_fastapi_instrumentator import Instrumentator\nfrom prometheus_client import Counter\n"
    content = content.replace("from fastapi import FastAPI", f"{imports}from fastapi import FastAPI")
    
    # Inject Instrumentator
    inst_code = '\nInstrumentator().instrument(app).expose(app)\n'
    content = re.sub(r'(app\s*=\s*FastAPI\([^\)]*\))', r'\1' + inst_code, content)
    
    # Custom metrics
    if service == "catalog":
        content = content.replace(
            'def search_products(q: str = Query(min_length=1)) -> dict[str, Any]:',
            'searches_counter = Counter("shopcloud_searches_total", "Total searches performed")\n\n@app.get("/api/catalog/search")\ndef search_products(q: str = Query(min_length=1)) -> dict[str, Any]:\n    searches_counter.inc()'
        )
        content = content.replace('@app.get("/api/catalog/search")\nsearches_counter =', 'searches_counter =')
        
    elif service == "checkout":
        content = content.replace(
            'def checkout(order: Order) -> dict:',
            'orders_counter = Counter("shopcloud_orders_total", "Total orders placed")\nrevenue_counter = Counter("shopcloud_revenue_total", "Total revenue")\n\n@app.post("/api/checkout")\ndef checkout(order: Order) -> dict:\n    orders_counter.inc()\n    revenue_counter.inc(order.total)'
        )
        content = content.replace('@app.post("/api/checkout")\norders_counter =', 'orders_counter =')
        
    elif service == "cart":
        content = content.replace(
            'def add_item(session_id: str, item: CartItem) -> dict[str, Any]:',
            'items_added_counter = Counter("shopcloud_cart_items_added_total", "Total items added to cart")\n\n@app.post("/api/cart/{session_id}/items")\ndef add_item(session_id: str, item: CartItem) -> dict[str, Any]:\n    items_added_counter.inc(item.quantity)'
        )
        content = content.replace('@app.post("/api/cart/{session_id}/items")\nitems_added_counter =', 'items_added_counter =')
        
    elif service == "auth":
        content = content.replace(
            'def customer_login(payload: LoginRequest) -> dict[str, Any]:',
            'logins_counter = Counter("shopcloud_logins_total", "Total successful logins")\n\n@app.post("/api/auth/customer/login")\ndef customer_login(payload: LoginRequest) -> dict[str, Any]:\n    logins_counter.inc()'
        )
        content = content.replace('@app.post("/api/auth/customer/login")\nlogins_counter =', 'logins_counter =')
        
        content = content.replace(
            'def customer_signup(payload: SignupRequest) -> dict[str, Any]:',
            'signups_counter = Counter("shopcloud_signups_total", "Total signups")\n\n@app.post("/api/auth/customer/signup")\ndef customer_signup(payload: SignupRequest) -> dict[str, Any]:\n    signups_counter.inc()'
        )
        content = content.replace('@app.post("/api/auth/customer/signup")\nsignups_counter =', 'signups_counter =')

    with open(app_py, "w", encoding="utf-8") as f:
        f.write(content)
        
    print(f"Instrumented {service}")

for svc in SERVICES:
    instrument_service(svc)
