import os
import shutil
import re

# Paths
catalog_dir = r"c:\Users\Hussein\Desktop\shopcloud\services\catalog"
images_dir = os.path.join(catalog_dir, "images")
os.makedirs(images_dir, exist_ok=True)

# Copy images
art_dir = r"C:\Users\Hussein\.gemini\antigravity\brain\76c6f874-c768-49d4-a7c1-244eb3f0cf13"
images_to_copy = {
    "sku_1001_1777651101591.png": "sku-1001.png",
    "sku_1002_1777651194454.png": "sku-1002.png",
    "sku_1003_1777651455613.png": "sku-1003.png",
}
for src, dst in images_to_copy.items():
    src_path = os.path.join(art_dir, src)
    if os.path.exists(src_path):
        shutil.copy(src_path, os.path.join(images_dir, dst))
        print(f"Copied {src} to {dst}")
    else:
        print(f"File not found: {src_path}")

# Update Dockerfile
dockerfile_path = os.path.join(catalog_dir, "Dockerfile")
with open(dockerfile_path, "r") as f:
    df_content = f.read()

if "COPY images/ ./images/" not in df_content:
    df_content = df_content.replace("COPY app.py ./", "COPY app.py ./\nCOPY images/ ./images/")
    with open(dockerfile_path, "w") as f:
        f.write(df_content)
    print("Updated Dockerfile")

# Update app.py
app_py_path = os.path.join(catalog_dir, "app.py")
with open(app_py_path, "r", encoding="utf-8") as f:
    app_content = f.read()

# Add staticfiles import
if "from fastapi.staticfiles import StaticFiles" not in app_content:
    app_content = app_content.replace(
        "from fastapi.responses import HTMLResponse",
        "from fastapi.responses import HTMLResponse\nfrom fastapi.staticfiles import StaticFiles"
    )

# Mount images
if 'app.mount("/images"' not in app_content:
    app_content = app_content.replace(
        'app = FastAPI(title="shopcloud-catalog")\nlog = logging.getLogger("catalog")',
        'app = FastAPI(title="shopcloud-catalog")\napp.mount("/images", StaticFiles(directory="images"), name="images")\nlog = logging.getLogger("catalog")'
    )

# Change SEED_PRODUCTS
app_content = re.sub(
    r'"https://cdn\.shopcloud\.com/images/sku-(\d+)\.jpg"',
    r'"/images/sku-\1.png"',
    app_content
)

# Update existing rows in startup
startup_update_code = """
def _update_image_urls() -> None:
    try:
        with _db() as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE products SET image_url = '/images/' || id || '.png' WHERE image_url LIKE 'https://cdn.shopcloud.com/images/%'")
                log.info("Updated existing image URLs")
    except Exception as e:
        log.error("Failed to update image URLs: %s", e)

@app.on_event("startup")
def startup() -> None:
    if SKIP_DB_SCHEMA_INIT:
        log.info("Skipping catalog schema initialization")
        return
    _init_schema()
    _update_image_urls()
"""

# Replace startup
app_content = re.sub(
    r'@app\.on_event\("startup"\)\ndef startup\(\) -> None:\n\s+if SKIP_DB_SCHEMA_INIT:\n\s+log\.info\("Skipping catalog schema initialization"\)\n\s+return\n\s+_init_schema\(\)',
    startup_update_code.strip(),
    app_content
)

with open(app_py_path, "w", encoding="utf-8") as f:
    f.write(app_content)

print("Updated app.py")
