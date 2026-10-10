import os
import logging
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("antigravity-nas-server")

app = FastAPI(title="Remote Antigravity Synology NAS Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Get path to static frontend directory
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRONTEND_DIR = os.path.join(BASE_DIR, "frontend")

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "Remote Antigravity NAS Dashboard"}

# Serve static frontend assets
if os.path.exists(FRONTEND_DIR):
    app.mount("/static", StaticFiles(directory=FRONTEND_DIR), name="static")

@app.get("/")
async def read_index():
    index_path = os.path.join(FRONTEND_DIR, "index.html")
    if os.path.exists(index_path):
        return FileResponse(index_path)
    return HTMLResponse("<h2>Frontend files missing in Docker container</h2>")

@app.get("/manifest.json")
async def read_manifest():
    manifest_path = os.path.join(FRONTEND_DIR, "manifest.json")
    if os.path.exists(manifest_path):
        return FileResponse(manifest_path, media_type="application/json")
    return HTMLResponse("{}", status_code=404)

@app.get("/style.css")
async def read_css():
    css_path = os.path.join(FRONTEND_DIR, "style.css")
    if os.path.exists(css_path):
        return FileResponse(css_path, media_type="text/css")
    return HTMLResponse("", status_code=404)

@app.get("/app.js")
async def read_js():
    js_path = os.path.join(FRONTEND_DIR, "app.js")
    if os.path.exists(js_path):
        return FileResponse(js_path, media_type="application/javascript")
    return HTMLResponse("", status_code=404)

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8899"))
    logger.info(f"Starting Synology NAS Antigravity Dashboard on port {port}")
    uvicorn.run(app, host="0.0.0.0", port=port)
