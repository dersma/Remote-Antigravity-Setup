import os
import sys

# Add python executable directory to DLL search path for pythonw.exe
if hasattr(os, "add_dll_directory"):
    try:
        os.add_dll_directory(os.path.dirname(sys.executable))
    except Exception:
        pass

# Fix sys.stdout / sys.stderr for pythonw.exe (GUI mode without console)
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w")

import asyncio
import json
import glob
import re
import secrets
import time
import logging
import subprocess
import threading
import webbrowser
import urllib.parse
from datetime import datetime
from typing import List, Dict, Optional

try:
    import psutil
except Exception:
    psutil = None

import pystray
from PIL import Image

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, Header, Query, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("antigravity-bridge")

app = FastAPI(title="Remote Antigravity PC Bridge API & Web Dashboard", version="4.5.0")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://.*",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Portable configuration
#
# Nothing machine specific is hardcoded anymore. Values are resolved in this
# order:
#   1. Environment variable (ANTIGRAVITY_*)
#   2. Local config file  pc_bridge/config.json  (created by
#      scripts/setup_remote_antigravity.ps1, git-ignored)
#   3. Sensible default derived from the repository location
# ---------------------------------------------------------------------------

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRIDGE_DIR = os.path.join(BASE_DIR, "pc_bridge")
FRONTEND_DIR = os.path.join(BASE_DIR, "frontend")
CONFIG_PATH = os.path.join(BRIDGE_DIR, "config.json")

def _load_local_config() -> Dict:
    """Read optional local config file, never raises.

    Use utf-8-sig so a file written by Windows PowerShell (which adds a UTF-8
    BOM) or by Notepad is still parsed correctly.
    """
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8-sig") as f:
                data = json.load(f)
            if isinstance(data, dict):
                return data
    except Exception as e:
        logger.warning(f"Could not read local config {CONFIG_PATH}: {e}")
    return {}

LOCAL_CONFIG = _load_local_config()

def _resolve_config(key: str, env_var, default: str) -> str:
    """Resolve a value: environment variable(s) -> config.json -> default."""
    names = [env_var] if isinstance(env_var, str) else list(env_var)
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    value = LOCAL_CONFIG.get(key)
    if value:
        return str(value)
    return default

def _resolve_api_token() -> str:
    env_token = os.getenv("ANTIGRAVITY_API_TOKEN")
    if env_token:
        return env_token
    token = LOCAL_CONFIG.get("api_token")
    if token:
        return str(token)
    # First start without configuration: generate a random token and persist it
    # so the dashboard keeps working across restarts.
    token = secrets.token_urlsafe(24)
    LOCAL_CONFIG["api_token"] = token
    try:
        os.makedirs(BRIDGE_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(LOCAL_CONFIG, f, indent=2)
        logger.info(f"Generated new API token and stored it in {CONFIG_PATH}")
    except Exception as e:
        logger.warning(f"Could not persist generated API token: {e}")
    return token

API_TOKEN = _resolve_api_token()

# Default workspace = repository root, projects root = its parent folder.
DEFAULT_WORKSPACE = os.path.normpath(_resolve_config("workspace", "ANTIGRAVITY_WORKSPACE", BASE_DIR))
PROJECTS_ROOT = os.path.normpath(_resolve_config(
    "projects_root", "ANTIGRAVITY_PROJECTS_ROOT", os.path.dirname(BASE_DIR)
))
DASHBOARD_URL = _resolve_config("dashboard_url", "ANTIGRAVITY_DASHBOARD_URL", "")
# Eindeutige Namen zuerst; HOST/PORT bleiben als Altlast-Fallback erhalten.
HOST = _resolve_config("host", ("ANTIGRAVITY_HOST", "HOST"), "0.0.0.0")

def _resolve_int(key: str, env_var, default: int) -> int:
    try:
        return int(_resolve_config(key, env_var, str(default)))
    except (TypeError, ValueError):
        return default

PORT = _resolve_int("port", ("ANTIGRAVITY_PORT", "PORT"), 8900)

# Kennung, damit das Setup-Skript erkennt, ob auf einem Port wirklich DIESE
# Bridge laeuft (und nicht ein fremdes Programm).
SERVICE_ID = "remote-antigravity-bridge"

GEMINI_DIR = os.path.expanduser(r"~\.gemini")
GEMINI_CONFIG_PROJECTS = os.path.join(GEMINI_DIR, "config", "projects")
GEMINI_BRAIN_DIR = os.path.join(GEMINI_DIR, "antigravity", "brain")
HOME_DIR = os.path.expanduser("~")

AGENTAPI_BAT = os.path.join(GEMINI_DIR, "antigravity", "bin", "agentapi.bat")

# Regex to strip all unicode emojis
EMOJI_PATTERN = re.compile(
    "["
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F680-\U0001F6FF"  # transport & map symbols
    "\U0001F1E0-\U0001F1FF"  # flags (iOS)
    "\U0001F900-\U0001F9FF"  # Supplemental Symbols and Pictographs
    "\U0001FA70-\U0001FAFF"  # Symbols and Pictographs Extended-A
    "\U00002702-\U000027B0"
    "\U000024C2-\U0001F251"
    "]+",
    flags=re.UNICODE,
)

def strip_emojis(text: str) -> str:
    if not isinstance(text, str):
        return ""
    return EMOJI_PATTERN.sub("", text).strip()

def normalize_workspace_path(p: Optional[str]) -> str:
    if not p:
        return ""
    if p.startswith("file:///"):
        p = urllib.parse.unquote(p[8:])
    p = p.replace("%3A", ":").replace("%5C", "/").replace("%20", " ")
    return os.path.normpath(p).lower()

class TaskState:
    def __init__(self):
        self.current_process: Optional[asyncio.subprocess.Process] = None
        self.logs: List[Dict[str, str]] = []
        self.status: str = "idle"
        self.connected_websockets: List[WebSocket] = []
        self.active_workspace: str = DEFAULT_WORKSPACE

state = TaskState()

def is_antigravity_running() -> bool:
    if psutil:
        try:
            for proc in psutil.process_iter(['name']):
                name = proc.info.get('name') or ''
                if 'antigravity' in name.lower() or 'language_server' in name.lower():
                    return True
            return False
        except Exception:
            return True
    return True

def ensure_antigravity_running(timeout: float = 8.0):
    if not is_antigravity_running():
        antigravity_exe = os.path.expanduser(r"~\AppData\Local\Programs\antigravity\Antigravity.exe")
        if os.path.exists(antigravity_exe):
            try:
                subprocess.Popen([antigravity_exe])
                logger.info("Launched Antigravity IDE on startup")
                start_wait = time.time()
                while time.time() - start_wait < timeout:
                    if get_ls_connection_info(timeout=1.0):
                        break
                    time.sleep(0.5)
            except Exception as e:
                logger.error(f"Failed to launch Antigravity IDE: {e}")

def get_ls_connection_info(timeout: float = 3.0) -> Optional[Dict]:
    start = time.time()
    while time.time() - start < timeout:
        if psutil:
            for proc in psutil.process_iter(["name", "cmdline", "pid"]):
                try:
                    name = proc.info.get("name") or ""
                    if "language_server" in name.lower():
                        cmdline = proc.info.get("cmdline") or []
                        cmd_str = " ".join(cmdline)
                        m_csrf = re.search(r"--csrf_token[\s=]([0-9a-fA-F\-]+)", cmd_str)
                        csrf = m_csrf.group(1) if m_csrf else ""
                        
                        ports = []
                        for c in proc.net_connections(kind="inet"):
                            if c.status == "LISTEN" and c.laddr.ip in ("127.0.0.1", "0.0.0.0", "::1", "::"):
                                ports.append(c.laddr.port)
                        
                        if ports:
                            ports.sort()
                            grpc_port = ports[-1] if len(ports) > 1 else ports[0]
                            return {
                                "pid": proc.info["pid"],
                                "csrf_token": csrf,
                                "grpc_port": grpc_port,
                                "address": f"localhost:{grpc_port}"
                            }
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        time.sleep(0.3)
    return None

def _is_user_home(path: str) -> bool:
    """True, wenn der Pfad das Benutzerprofil ist (dort liegen viele Systemordner)."""
    try:
        return os.path.normcase(os.path.normpath(path)) == os.path.normcase(os.path.normpath(HOME_DIR))
    except Exception:
        return False

def discover_projects() -> List[Dict[str, str]]:
    projects = []
    seen_paths = set()
    
    # 1. Load from ~/.gemini/config/projects/*.json
    if os.path.exists(GEMINI_CONFIG_PROJECTS):
        for p in glob.glob(os.path.join(GEMINI_CONFIG_PROJECTS, "*.json")):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    d = json.load(f)
                    pid = d.get("id")
                    name = d.get("name")
                    if not pid or pid == "outside-of-project":
                        continue
                    resources = d.get("projectResources", {}).get("resources", [])
                    main_path = ""
                    for r in resources:
                        f_uri = r.get("folderUri") or r.get("gitFolder", {}).get("folderUri")
                        if f_uri:
                            norm = normalize_workspace_path(f_uri)
                            if not main_path and os.path.exists(norm):
                                main_path = norm
                            seen_paths.add(norm)
                    if main_path:
                        projects.append({"id": pid, "name": name, "path": main_path})
            except Exception:
                pass
                
    # 2. Add any folders in PROJECTS_ROOT not yet listed.
    #    Ist PROJECTS_ROOT das Benutzerprofil, werden nur echte Projektordner
    #    (mit .git) und der aktive Workspace uebernommen - sonst landen Desktop,
    #    Downloads, AppData und Co. im Projekt-Dropdown.
    norm_default_ws = normalize_workspace_path(DEFAULT_WORKSPACE)
    scan_home = _is_user_home(PROJECTS_ROOT)
    if os.path.exists(PROJECTS_ROOT):
        for item in os.listdir(PROJECTS_ROOT):
            full_p = os.path.join(PROJECTS_ROOT, item)
            norm = normalize_workspace_path(full_p)
            if not os.path.isdir(full_p) or item.startswith(".") or norm in seen_paths:
                continue
            if scan_home and norm != norm_default_ws and not os.path.isdir(os.path.join(full_p, ".git")):
                continue
            projects.append({"id": "", "name": item, "path": norm})
            seen_paths.add(norm)

    # 3. Der aktive Workspace muss immer auswaehlbar sein
    if DEFAULT_WORKSPACE and os.path.isdir(DEFAULT_WORKSPACE) and norm_default_ws not in seen_paths:
        projects.insert(0, {
            "id": get_project_id_for_workspace(DEFAULT_WORKSPACE),
            "name": os.path.basename(DEFAULT_WORKSPACE.rstrip("\\/")) or DEFAULT_WORKSPACE,
            "path": norm_default_ws
        })
        seen_paths.add(norm_default_ws)

    return projects

def get_project_id_for_workspace(target_ws: str) -> str:
    norm_target = normalize_workspace_path(target_ws)
    if os.path.exists(GEMINI_CONFIG_PROJECTS):
        for p in glob.glob(os.path.join(GEMINI_CONFIG_PROJECTS, "*.json")):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    d = json.load(f)
                    pid = d.get("id")
                    if not pid or pid == "outside-of-project":
                        continue
                    resources = d.get("projectResources", {}).get("resources", [])
                    for r in resources:
                        f_uri = r.get("folderUri") or r.get("gitFolder", {}).get("folderUri")
                        if f_uri and normalize_workspace_path(f_uri) == norm_target:
                            return pid
            except Exception:
                pass
    return ""

conv_metadata_cache: Dict[str, Dict] = {}

def update_conversation_cache():
    if not os.path.exists(GEMINI_BRAIN_DIR):
        return
    pattern = os.path.join(GEMINI_BRAIN_DIR, "*", ".system_generated", "logs", "transcript.jsonl")
    for log_path in glob.glob(pattern):
        lp_norm = os.path.normpath(log_path)
        parts = lp_norm.split(os.sep)
        try:
            brain_idx = parts.index("brain")
            conv_id = parts[brain_idx + 1]
        except (ValueError, IndexError):
            continue

        if not os.path.exists(log_path):
            continue

        try:
            mtime = os.path.getmtime(log_path)
        except OSError:
            continue

        if conv_id in conv_metadata_cache and conv_metadata_cache[conv_id].get("mtime") == mtime:
            continue

        proj_id = ""
        ws_norm = ""
        if os.path.exists(AGENTAPI_BAT):
            try:
                res = subprocess.run(
                    ["cmd.exe", "/c", AGENTAPI_BAT, "get-conversation-metadata", conv_id],
                    capture_output=True,
                    text=True,
                    timeout=2,
                    creationflags=0x08000000
                )
                if res.returncode == 0:
                    data = json.loads(res.stdout)
                    meta = data.get("response", {}).get("conversationMetadata", {}).get("metadata", {})
                    proj_id = meta.get("projectId", "")
                    workspaces = meta.get("workspaces", [])
                    if workspaces:
                        raw_uri = workspaces[0].get("workspaceFolderAbsoluteUri", "")
                        ws_norm = normalize_workspace_path(raw_uri)
            except Exception:
                pass

        if not ws_norm:
            try:
                with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
                    for _ in range(50):
                        line = f.readline()
                        if not line:
                            break
                        if "Projects" in line or "file:///" in line:
                            m = re.search(r"file:///[^\s\"\'\>]+", line)
                            if m:
                                ws_norm = normalize_workspace_path(m.group(0))
                                break
                            m2 = re.search(r"([a-zA-Z]:\\[^\"\'\>\n\r]+)", line)
                            if m2:
                                ws_norm = normalize_workspace_path(m2.group(1))
                                break
            except Exception:
                pass

        conv_metadata_cache[conv_id] = {
            "conversation_id": conv_id,
            "project_id": proj_id,
            "workspace": ws_norm,
            "mtime": mtime,
            "log_path": log_path
        }

def get_latest_conversation_info(target_workspace: Optional[str] = None) -> Optional[Dict]:
    update_conversation_cache()
    if not conv_metadata_cache:
        return None

    if target_workspace:
        norm_target = normalize_workspace_path(target_workspace)
        target_pid = get_project_id_for_workspace(target_workspace)
        
        matches = []
        for cid, info in conv_metadata_cache.items():
            # Exact Project ID match (primary) or exact normalized path match (secondary)
            if target_pid and info["project_id"] == target_pid:
                matches.append(info)
            elif info["workspace"] and info["workspace"] == norm_target:
                matches.append(info)

        if matches:
            matches.sort(key=lambda x: x["mtime"], reverse=True)
            return matches[0]

    sorted_all = sorted(conv_metadata_cache.values(), key=lambda x: x["mtime"], reverse=True)
    if sorted_all:
        return sorted_all[0]
    return None

def get_latest_transcript_file(target_workspace: Optional[str] = None) -> Optional[str]:
    info = get_latest_conversation_info(target_workspace)
    return info["log_path"] if info else None

def get_active_conversation_id(target_workspace: Optional[str] = None) -> Optional[str]:
    info = get_latest_conversation_info(target_workspace)
    return info["conversation_id"] if info else None

def parse_transcript_messages(transcript_path: str) -> List[Dict[str, str]]:
    messages = []
    if not transcript_path or not os.path.exists(transcript_path):
        return messages

    try:
        with open(transcript_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    step_type = data.get("type")
                    if step_type in ("USER_INPUT", "SYSTEM_MESSAGE"):
                        content = data.get("content", "")
                        if isinstance(content, str) and content.strip():
                            text = content
                            if "<USER_REQUEST>" in text:
                                text = text.split("<USER_REQUEST>")[1].split("</USER_REQUEST>")[0].strip()
                            elif "content=" in text:
                                if "finished with result:" not in text and "was canceled with result:" not in text and "finished with status" not in text:
                                    parts = text.split("content=")
                                    if len(parts) > 1:
                                        text = parts[1].split("</SYSTEM_MESSAGE>")[0].strip()
                                else:
                                    text = ""
                            else:
                                text = ""

                            ignore_prefixes = ("Task id ", "Check ", "Timer:", "[Notice]", "[Message]")
                            if text and not any(text.startswith(p) for p in ignore_prefixes):
                                clean_text = strip_emojis(text).strip()
                                if clean_text:
                                    messages.append({"role": "user", "text": clean_text})
                    elif step_type == "PLANNER_RESPONSE":
                        content = data.get("content", "")
                        clean_text = strip_emojis(content) if isinstance(content, str) else ""
                        
                        tool_actions = []
                        if "tool_calls" in data and isinstance(data["tool_calls"], list):
                            for tc in data["tool_calls"]:
                                args = tc.get("args", {}) or {}
                                name = tc.get("name", "")
                                action_desc = args.get("toolAction") or args.get("toolSummary") or args.get("Description") or name
                                if action_desc and isinstance(action_desc, str):
                                    cleaned_action = strip_emojis(action_desc).strip()
                                    if cleaned_action and cleaned_action not in tool_actions:
                                        tool_actions.append(cleaned_action)

                        if clean_text:
                            messages.append({"role": "assistant", "text": clean_text})
                        elif tool_actions:
                            summary = " | ".join(tool_actions)
                            messages.append({"role": "assistant", "text": f"[Aktion]: {summary}"})
                except Exception:
                    pass
    except Exception as e:
        logger.error(f"Error parsing transcript: {e}")
    return messages

def verify_token(x_api_token: Optional[str] = Header(None), token: Optional[str] = Query(None)):
    req_token = x_api_token or token
    if API_TOKEN and req_token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid API Token")
    return True

class PromptRequest(BaseModel):
    prompt: str
    workspace: Optional[str] = None
    attachments: Optional[List[str]] = None
    model: Optional[str] = None

class ActionRequest(BaseModel):
    action: str
    params: Optional[dict] = None

async def broadcast_message(msg_type: str, data: dict):
    payload = json.dumps({"type": msg_type, "data": data, "status": state.status})
    state.logs.append({"type": msg_type, "data": json.dumps(data)})
    if len(state.logs) > 500:
        state.logs = state.logs[-500:]
        
    disconnected = []
    for ws in state.connected_websockets:
        try:
            await ws.send_text(payload)
        except Exception:
            disconnected.append(ws)
    for ws in disconnected:
        if ws in state.connected_websockets:
            state.connected_websockets.remove(ws)

# Static Frontend Routes & Favicons with No-Cache Headers
@app.get("/")
async def read_index():
    index_path = os.path.join(FRONTEND_DIR, "index.html")
    if os.path.exists(index_path):
        return FileResponse(index_path, headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("<h2>Frontend files missing</h2>")

@app.get("/manifest.json")
async def read_manifest():
    manifest_path = os.path.join(FRONTEND_DIR, "manifest.json")
    if os.path.exists(manifest_path):
        return FileResponse(manifest_path, media_type="application/json", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("{}", status_code=404)

@app.get("/favicon.svg")
async def read_favicon_svg():
    path = os.path.join(FRONTEND_DIR, "favicon.svg")
    if os.path.exists(path):
        return FileResponse(path, media_type="image/svg+xml", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/favicon.png")
async def read_favicon_png():
    path = os.path.join(FRONTEND_DIR, "favicon.png")
    if os.path.exists(path):
        return FileResponse(path, media_type="image/png", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/favicon.ico")
async def read_favicon_ico():
    path = os.path.join(FRONTEND_DIR, "favicon.ico")
    if os.path.exists(path):
        return FileResponse(path, media_type="image/x-icon", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

# Catches all iOS Safari apple-touch-icon requested variations
@app.get("/apple-touch-icon{rest_of_path:path}")
async def read_apple_touch_icon_any(rest_of_path: str = ""):
    path = os.path.join(FRONTEND_DIR, "apple-touch-icon.png")
    if os.path.exists(path):
        return FileResponse(path, media_type="image/png", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/logo-icon.png")
async def read_logo_icon():
    path = os.path.join(FRONTEND_DIR, "logo-icon.png")
    if os.path.exists(path):
        return FileResponse(path, media_type="image/png", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/icon-192.png")
async def read_icon_192():
    path = os.path.join(FRONTEND_DIR, "icon-192.png")
    if os.path.exists(path):
        return FileResponse(path, media_type="image/png", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/icon-512.png")
async def read_icon_512():
    path = os.path.join(FRONTEND_DIR, "icon-512.png")
    if os.path.exists(path):
        return FileResponse(path, media_type="image/png", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/style.css")
async def read_css():
    css_path = os.path.join(FRONTEND_DIR, "style.css")
    if os.path.exists(css_path):
        return FileResponse(css_path, media_type="text/css", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/app.js")
async def read_js():
    js_path = os.path.join(FRONTEND_DIR, "app.js")
    if os.path.exists(js_path):
        return FileResponse(js_path, media_type="application/javascript", headers={"Cache-Control": "no-cache, no-store, must-revalidate"})
    return HTMLResponse("", status_code=404)

@app.get("/health")
def health_check(workspace: Optional[str] = None, authenticated: bool = Depends(verify_token)):
    target_ws = workspace or state.active_workspace
    conv_id = get_active_conversation_id(target_ws)
    return {
        "status": "online",
        "service": SERVICE_ID,
        "bridge_file": os.path.abspath(__file__),
        "port": PORT,
        "agent_status": state.status,
        "active_workspace": target_ws,
        "active_conversation_id": conv_id,
        "agentapi_available": os.path.exists(AGENTAPI_BAT),
        "ide_running": is_antigravity_running()
    }

@app.get("/chat/history")
def get_chat_history(workspace: Optional[str] = None, authenticated: bool = Depends(verify_token)):
    target_ws = workspace or state.active_workspace
    latest_transcript = get_latest_transcript_file(target_ws)
    all_messages = parse_transcript_messages(latest_transcript)
    active_chat_messages = all_messages[-40:] if len(all_messages) > 40 else all_messages
    return {
        "status": state.status,
        "workspace": target_ws,
        "conversation_id": get_active_conversation_id(target_ws),
        "chat_messages": active_chat_messages
    }

@app.get("/models")
def list_models(authenticated: bool = Depends(verify_token)):
    models_file = os.path.join(BASE_DIR, "pc_bridge", "antigravity_models.json")
    if os.path.exists(models_file):
        try:
            with open(models_file, "r", encoding="utf-8") as f:
                models_data = json.load(f)
                return {"models": models_data}
        except Exception:
            pass
    return {"models": []}

@app.get("/projects")
def list_projects(authenticated: bool = Depends(verify_token)):
    projects = discover_projects()
    return {"projects": projects, "current": state.active_workspace}

@app.get("/workspace/files")
def list_workspace_files(workspace: Optional[str] = None, authenticated: bool = Depends(verify_token)):
    target_dir = workspace or state.active_workspace
    files_list = []
    if os.path.exists(target_dir):
        for root, dirs, files in os.walk(target_dir):
            dirs[:] = [d for d in dirs if d not in [".git", "node_modules", "venv", "dist", "build", ".uploads"]]
            for f in files:
                rel_path = os.path.relpath(os.path.join(root, f), target_dir)
                files_list.append(rel_path.replace("\\", "/"))
                if len(files_list) > 200:
                    break
            if len(files_list) > 200:
                break
    return {"workspace": target_dir, "files": files_list[:150]}

@app.get("/conversation/messages")
def get_conversation(workspace: Optional[str] = None, authenticated: bool = Depends(verify_token)):
    target_ws = workspace or state.active_workspace
    latest_transcript = get_latest_transcript_file(target_ws)
    messages = parse_transcript_messages(latest_transcript)
    return {
        "workspace": target_ws,
        "conversation_id": get_active_conversation_id(target_ws),
        "transcript_path": latest_transcript,
        "messages": messages
    }

@app.get("/workspace/git-diff")
async def get_git_diff(workspace: Optional[str] = None, authenticated: bool = Depends(verify_token)):
    target_dir = workspace or state.active_workspace
    if not os.path.exists(target_dir):
        raise HTTPException(status_code=400, detail="Workspace directory does not exist")
    
    try:
        proc = await asyncio.create_subprocess_exec(
            "git", "diff",
            cwd=target_dir,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            creationflags=0x08000000
        )
        stdout, stderr = await proc.communicate()
        diff_output = stdout.decode("utf-8", errors="replace")
        return {"workspace": target_dir, "diff": diff_output}
    except Exception as e:
        return {"workspace": target_dir, "error": str(e), "diff": ""}

@app.post("/upload")
async def upload_attachment(file: UploadFile = File(...), authenticated: bool = Depends(verify_token)):
    uploads_dir = os.path.join(state.active_workspace, ".uploads")
    os.makedirs(uploads_dir, exist_ok=True)
    file_path = os.path.join(uploads_dir, file.filename)
    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)
    return {"filename": file.filename, "path": file_path}

@app.post("/prompt")
async def run_prompt(req: PromptRequest, authenticated: bool = Depends(verify_token)):
    ensure_antigravity_running()

    target_workspace = req.workspace or state.active_workspace
    state.active_workspace = target_workspace
    state.status = "running"

    ls_info = get_ls_connection_info(timeout=6.0)
    target_pid = get_project_id_for_workspace(target_workspace)
    conv_info = get_latest_conversation_info(target_workspace)
    conv_id = conv_info["conversation_id"] if conv_info else None

    logger.info(f"Sending prompt for workspace '{target_workspace}' [proj_id={target_pid}, conv_id={conv_id}]: {req.prompt}")

    env = os.environ.copy()
    env["ANTIGRAVITY_AGENT"] = "1"
    if target_pid:
        env["ANTIGRAVITY_PROJECT_ID"] = target_pid
    if conv_id:
        env["ANTIGRAVITY_CONVERSATION_ID"] = conv_id
    if ls_info:
        if ls_info.get("csrf_token"):
            env["ANTIGRAVITY_CSRF_TOKEN"] = ls_info["csrf_token"]
        if ls_info.get("address"):
            env["ANTIGRAVITY_LS_ADDRESS"] = ls_info["address"]

    success = False
    out_str = ""
    err_str = ""

    if os.path.exists(AGENTAPI_BAT):
        try:
            if conv_id:
                logger.info(f"Dispatching send-message to conversation {conv_id}...")
                cmd_args = ["cmd.exe", "/c", AGENTAPI_BAT, "send-message", conv_id, req.prompt]
                proc = await asyncio.create_subprocess_exec(
                    *cmd_args,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    cwd=target_workspace if os.path.exists(target_workspace) else None,
                    env=env,
                    creationflags=0x08000000
                )
                stdout, stderr = await proc.communicate()
                out_str = stdout.decode("utf-8", errors="replace")
                err_str = stderr.decode("utf-8", errors="replace")
                logger.info(f"agentapi send-message output: {out_str} {err_str}")

                if proc.returncode == 0 and "error" not in out_str.lower() and "permission_denied" not in out_str.lower():
                    success = True

            if not success:
                logger.info(f"Starting new conversation via agentapi for {target_workspace}...")
                cmd_args = ["cmd.exe", "/c", AGENTAPI_BAT, "new-conversation"]
                if req.model:
                    cmd_args.append(f"--model={req.model}")
                cmd_args.append(req.prompt)
                
                proc = await asyncio.create_subprocess_exec(
                    *cmd_args,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    cwd=target_workspace if os.path.exists(target_workspace) else None,
                    env=env,
                    creationflags=0x08000000
                )
                stdout, stderr = await proc.communicate()
                out_str = stdout.decode("utf-8", errors="replace")
                err_str = stderr.decode("utf-8", errors="replace")
                logger.info(f"agentapi new-conversation output: {out_str} {err_str}")
        except Exception as e:
            logger.error(f"agentapi execution error: {e}")

    await broadcast_message("status", {"message": f"Prompt übermittelt: {req.prompt}", "prompt": req.prompt, "workspace": target_workspace})

    # Wait briefly and refresh transcript
    await asyncio.sleep(0.5)
    update_conversation_cache()
    latest_transcript = get_latest_transcript_file(target_workspace)
    if latest_transcript:
        updated_messages = parse_transcript_messages(latest_transcript)
        await broadcast_message("chat_update", {
            "chat_messages": updated_messages,
            "workspace": target_workspace,
            "conversation_id": get_active_conversation_id(target_workspace)
        })

    return {
        "status": "sent_to_antigravity" if success else "not_delivered",
        "delivered": bool(success),
        "agentapi_available": os.path.exists(AGENTAPI_BAT),
        "conversation_id": conv_id or "new",
        "workspace": target_workspace,
        "prompt": req.prompt
    }

@app.post("/action")
async def trigger_action(req: ActionRequest, authenticated: bool = Depends(verify_token)):
    if req.action == "stop":
        if state.current_process and state.current_process.returncode is None:
            try:
                state.current_process.terminate()
                await asyncio.sleep(0.5)
                if state.current_process.returncode is None:
                    state.current_process.kill()
                state.status = "stopped"
                await broadcast_message("status", {"message": "Task gestoppt"})
                return {"status": "stopped"}
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Fehler beim Stoppen: {str(e)}")
        else:
            state.status = "idle"
            await broadcast_message("status", {"message": "Kein aktiver Task"})
            return {"status": "no task running"}
    elif req.action == "change_workspace":
        new_ws = req.params.get("workspace") if req.params else None
        if new_ws and os.path.exists(new_ws):
            state.active_workspace = new_ws
            update_conversation_cache()
            conv_id = get_active_conversation_id(new_ws)
            latest_transcript = get_latest_transcript_file(new_ws)
            chat_messages = parse_transcript_messages(latest_transcript)
            logger.info(f"Switched workspace to: {new_ws} (conv_id={conv_id}, messages={len(chat_messages)})")
            await broadcast_message("chat_update", {
                "chat_messages": chat_messages[-40:] if len(chat_messages) > 40 else chat_messages,
                "workspace": new_ws,
                "conversation_id": conv_id
            })
            return {"status": "workspace_changed", "workspace": new_ws, "conversation_id": conv_id}
        raise HTTPException(status_code=400, detail="Invalid workspace path")
    elif req.action == "status":
        return {"status": state.status, "active_workspace": state.active_workspace}
    else:
        raise HTTPException(status_code=400, detail="Unknown action")

@app.websocket("/ws/logs")
async def websocket_logs(websocket: WebSocket, token: Optional[str] = Query(None)):
    if API_TOKEN and token != API_TOKEN:
        await websocket.close(code=4001, reason="Unauthorized")
        return
        
    await websocket.accept()
    state.connected_websockets.append(websocket)
    
    current_ws = state.active_workspace
    update_conversation_cache()
    latest_transcript = get_latest_transcript_file(current_ws)
    all_messages = parse_transcript_messages(latest_transcript)
    active_chat_messages = all_messages[-40:] if len(all_messages) > 40 else all_messages
    
    await websocket.send_text(json.dumps({
        "type": "init",
        "data": {
            "status": state.status,
            "workspace": current_ws,
            "conversation_id": get_active_conversation_id(current_ws),
            "chat_messages": active_chat_messages,
            "history": state.logs[-50:]
        }
    }))
    
    try:
        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
                if payload.get("type") == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))
                elif payload.get("type") == "refresh_chat":
                    req_ws = payload.get("workspace") or state.active_workspace
                    update_conversation_cache()
                    latest_transcript = get_latest_transcript_file(req_ws)
                    all_msgs = parse_transcript_messages(latest_transcript)
                    chat_messages = all_msgs[-40:] if len(all_msgs) > 40 else all_msgs
                    await websocket.send_text(json.dumps({
                        "type": "chat_update",
                        "data": {
                            "chat_messages": chat_messages,
                            "workspace": req_ws,
                            "conversation_id": get_active_conversation_id(req_ws)
                        }
                    }))
            except Exception:
                pass
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected")
    finally:
        if websocket in state.connected_websockets:
            state.connected_websockets.remove(websocket)

async def transcript_watcher():
    last_mtimes = {}
    while True:
        try:
            current_ws = state.active_workspace
            latest_file = get_latest_transcript_file(current_ws)
            if latest_file and os.path.exists(latest_file):
                mtime = os.path.getmtime(latest_file)
                if last_mtimes.get(current_ws, 0.0) < mtime:
                    last_mtimes[current_ws] = mtime
                    all_messages = parse_transcript_messages(latest_file)
                    active_chat_messages = all_messages[-40:] if len(all_messages) > 40 else all_messages
                    await broadcast_message("chat_update", {
                        "chat_messages": active_chat_messages,
                        "workspace": current_ws,
                        "conversation_id": get_active_conversation_id(current_ws)
                    })
        except Exception:
            pass
        await asyncio.sleep(1.0)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(transcript_watcher())

def setup_tray_icon():
    log_file = os.path.join(BASE_DIR, "pc_bridge", "tray.log")
    with open(log_file, "w", encoding="utf-8") as f:
        f.write("Starting setup_tray_icon...\n")
    try:
        icon_path = os.path.join(FRONTEND_DIR, "favicon.ico")
        if not os.path.exists(icon_path):
            icon_path = os.path.join(FRONTEND_DIR, "apple-touch-icon.png")
        
        image = Image.open(icon_path).convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS)
        
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"Loaded tray image from {icon_path}, size={image.size}\n")

        def on_open_dashboard(icon, item):
            webbrowser.open(DASHBOARD_URL or f"http://localhost:{PORT}")
            
        def on_exit(icon, item):
            with open(log_file, "a", encoding="utf-8") as f:
                f.write("Exit clicked in Tray menu.\n")
            try:
                icon.stop()
            except Exception:
                pass
            os._exit(0)

        menu = pystray.Menu(
            pystray.MenuItem(f"Antigravity PC Bridge (Port {PORT})", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Dashboard im Browser öffnen", on_open_dashboard),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Beenden", on_exit)
        )
        
        tray_icon = pystray.Icon("antigravity_bridge_icon", image, "Antigravity PC Bridge", menu)
        
        with open(log_file, "a", encoding="utf-8") as f:
            f.write("Running pystray tray_icon.run()...\n")

        def on_ready(icon):
            try:
                icon.notify(f"PC Bridge läuft im System Tray (Port {PORT}).", "Antigravity Remote Control")
            except Exception:
                pass

        tray_icon.run(setup=on_ready)
    except Exception as e:
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"Tray error: {e}\n")

if __name__ == "__main__":
    import uvicorn
    import traceback

    host = HOST
    port = PORT
    
    def run_uvicorn():
        try:
            config = uvicorn.Config(app, host=host, port=port, log_level="info")
            server = uvicorn.Server(config)
            server.run()
        except Exception as e:
            try:
                with open(os.path.join(BASE_DIR, "pc_bridge", "crash.log"), "a", encoding="utf-8") as f:
                    f.write(f"[{datetime.now().isoformat(timespec='seconds')}] "
                            f"Uvicorn error: {e}\n{traceback.format_exc()}\n")
            except Exception:
                pass

    server_thread = threading.Thread(target=run_uvicorn, daemon=True)
    server_thread.start()
    
    setup_tray_icon()
