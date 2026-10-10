# 🚀 Remote Antigravity

Steuere deine **Antigravity IDE** vom Handy aus (iPhone/Android) – über **Tailscale**, also
**ohne eigene Domain, ohne Cloudflare, ohne Router-Freigabe und ohne NAS**.
Dashboard, API und Bridge laufen komplett auf deinem Windows-PC.

---

## ⚡ Installation (Ein-Klick)

**Download:** **[Neueste Version herunterladen](https://github.com/dersma/Remote-Antigravity-Setup/releases/latest)**

1. Die Datei **`Remote-Antigravity-Installer.bat`** herunterladen (eine einzige Datei) und **doppelklicken**.
   *Falls Windows warnt: „Weitere Informationen“ → „Trotzdem ausführen“.*
2. **ENTER** drücken, **UAC bestätigen** und im Browser den **Tailscale-Login** abschließen.
3. Am Ende erscheint eine Seite mit **QR-Code** – mit der Handy-Kamera scannen.
   *(Tailscale-App am Handy vorher installieren und mit **demselben Konto** anmelden.)*

Der Installer macht alles automatisch:

- Python prüfen/installieren und eine virtuelle Umgebung mit allen Abhängigkeiten anlegen
- **Tailscale installieren** (winget, sonst offizielles MSI) und den Login starten
- Firewall-Regel **nur für das Tailscale-Netz** (`100.64.0.0/10`) setzen
- Bridge/Dashboard starten (Port `8900`, bei belegtem Port automatisch `8901`+), Autostart anlegen
- **QR-Code** mit der fertigen Dashboard-URL erzeugen

**Voraussetzungen:** Windows 10/11 · **Antigravity IDE installiert und einmal gestartet**
(erzeugt `%USERPROFILE%\.gemini\antigravity\bin\agentapi.bat`) · Internet ·
am Handy die Tailscale-App mit demselben Konto.

**Offline-Variante:** im Release die ZIP-Datei `Remote-Antigravity.zip` herunterladen → entpacken →
im Ordner `Remote-Antigravity` die **`INSTALL.bat`** doppelklicken.

👉 Ausführliche Schritt-für-Schritt-Anleitung: [`SETUP_FRIEND.md`](SETUP_FRIEND.md)
👉 Für KI-Agenten (Antigravity, Cline …): [`AGENTS.md`](AGENTS.md)

---

## 🌟 Features

- 📱 **Mobile PWA Dashboard**: Für iPhone Safari optimierte Web-Oberfläche. Kann auf dem iPhone wie eine App zum Home-Bildschirm hinzugefügt werden.
- 🎛️ **Dynamische Modellauswahl**: Lila Glassmorphism Dropdown-Pill direkt über der Prompt-Eingabe (Gemini 3.7 Flash, Gemini 3.6 Flash High, Claude Sonnet 4.6 Thinking, Claude Opus 4.6 Thinking, GPT-OSS 120B etc.), exakt synchron mit den Modellen deiner PC IDE.
- ⚡ **Slash Command Chips**: Antippen von `/goal`, `/schedule`, `/browser`, `/grill-me`, `/learn` fügt den Befehl direkt mit Leerzeichen in die Eingabezeile ein.
- ⚡ **Echtzeit Log-Streaming**: Beobachte Antigravity Agenten-Ausgaben live via WebSocket.
- 💬 **Prompts & Actions**: Anweisungen absenden, laufende Tasks stoppen oder pausieren.
- 📄 **Git Diff Viewer**: Code-Änderungen auf dem PC direkt von unterwegs prüfen.
- 🔒 **100% Kostenlos & Sicher**: Verschlüsselte Tailscale VPN Verbindung ohne Portweiterleitungen im Router.

---

## 🏗️ Architektur & Ordnerstruktur

```text
Remote Antigravity/
├── INSTALL.bat                     # Ein-Klick-Installer (Doppelklick) für fremde PCs
├── AGENTS.md                       # Setup-Anleitung für KI-Agenten (Antigravity, Cline, ...)
├── SETUP_FRIEND.md                 # Einrichtung für Freunde (Tailscale, ohne Domain)
├── SETUP_TAILSCALE.md              # Manuelle Tailscale-Anleitung (NAS + PC + iPhone)
├── docker-compose.yml              # Docker Compose für Synology Container Manager (optional)
├── Dockerfile                      # Multi-stage Docker Image für NAS Dashboard (optional)
├── README.md                       # Diese Dokumentation
├── scripts/
│   ├── install_remote_antigravity.ps1  # Geführter Installer (Prüfungen, UAC, Repo, QR-Code)
│   └── setup_remote_antigravity.ps1    # One-Shot-Setup: Python, venv, Tailscale, Firewall, Autostart
├── frontend/                       # Mobile PWA Frontend (HTML5, CSS3, JS)
│   ├── index.html                  # Dashboard UI mit Modellauswahl & Chips
│   ├── style.css                   # Glassmorphism Styling & Responsive Breakpoints
│   ├── app.js                      # WebSocket Client, Model Selector & Session State
│   └── manifest.json
├── server/                         # Optionaler NAS Webserver (FastAPI / Static File Host)
│   ├── server.py
│   └── requirements.txt
└── pc_bridge/                      # Windows PC Hintergrunddienst für Antigravity
    ├── antigravity_bridge.py       # FastAPI PC Bridge & Web Dashboard (Port 8900)
    ├── antigravity_models.json     # Konfiguration der verfügbaren Antigravity-Modelle
    ├── config.example.json         # Vorlage für die lokale config.json (Token + Pfade)
    ├── start_pc_bridge.bat         # Start-Skript für PC-Hintergrunddienst
    └── requirements.txt
```

> ℹ️ `pc_bridge/config.json` wird beim Setup automatisch erzeugt (Token, Pfade, Tailscale-IP) und ist
> per `.gitignore` ausgeschlossen. Das Gleiche gilt für die vom Installer erzeugte `onboarding.html`
> (enthält Token). Für private Setups ist **keine NAS und kein Docker** nötig – die PC Bridge liefert
> das Dashboard auf Port `8900` selbst mit aus.

---

## 🎁 Für Freunde / eigene Geräte: Ein-Klick-Installation

Du brauchst **keine Domain, keinen Cloudflare-Account, keine NAS und keine Portfreigabe** – nur einen
Windows-PC mit installierter Antigravity IDE.

**Variante 1 – einfachste (empfohlen):** Im GitHub-Release die Datei
**`Remote-Antigravity-Installer.bat`** herunterladen und doppelklicken. Sie lädt das Paket selbst,
entpackt es nach `%USERPROFILE%\Projects` und startet den geführten Installer (Prüfungen, UAC,
**Tailscale**-Installation und -Login, Bridge, Autostart, **QR-Code** für das Handy).

**Variante 1b – Offline:** im Release die `Remote-Antigravity.zip` herunterladen → entpacken →
**`INSTALL.bat`** doppelklicken.

**Variante 2 – per Befehl (Repository vorher klonen):**

```powershell
git clone https://github.com/dersma/Remote-Antigravity-Setup.git
cd Remote-Antigravity
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_remote_antigravity.ps1
```

Beide Wege richten Python, die virtuelle Umgebung, **Tailscale** (Installation + Login), die
Konfiguration, die Firewall-Regel (Port `8900` nur für das Tailscale-Netz), den Bridge-Start und den
Autostart ein – und geben am Ende die fertige Dashboard-URL inkl. Token aus.

> ⚠️ **Hinweis zur Sichtbarkeit:** Ist dieses Repository **privat**, funktioniert das Klonen nur mit
> Zugangsdaten. Gib den Ordner dann als ZIP weiter, stelle das Repository öffentlich oder lade die
> Person als Collaborator ein.

👉 Details, der Copy-Paste-Prompt für einen KI-Agenten und die Varianten stehen in
[`SETUP_FRIEND.md`](SETUP_FRIEND.md); Agenten finden die vollständige Anleitung in
[`AGENTS.md`](AGENTS.md).

---


## 🚀 Schnellanleitung zur Inbetriebnahme

> 💡 **Abkürzung:** Für einen frischen PC (auch bei Freunden) macht das Skript
> `scripts/setup_remote_antigravity.ps1` alle Schritte aus Teil 1–3 automatisch. Die manuelle
> Variante unten ist für den NAS-/Docker-Betrieb weiterhin gültig.

### Teil 1: PC Bridge auf dem Windows-PC starten
1. Gehe in den Ordner `pc_bridge`.
2. Doppelklicke auf `start_pc_bridge.bat`.
3. Der Dienst startet den Server auf Port `8900` (das Dashboard wird direkt mit ausgeliefert).
   Beim **ersten Start** wird automatisch eine `pc_bridge/config.json` mit einem zufälligen
   API-Token erzeugt, falls noch keine existiert – den Token findest du dort im Feld `api_token`.
4. (Optional) Lege ein Kürzel für `start_pc_bridge.bat` in deinen Windows-Autostart-Ordner (`shell:startup`).
5. Python-Abhängigkeiten fehlen? `py -3 -m venv .venv` und
   `.\.venv\Scripts\python.exe -m pip install -r pc_bridge\requirements.txt` (oder das Setup-Skript nutzen).

---

### Teil 2: Dashboard auf der Synology NAS (Docker) starten
1. Kopiere dieses Projektverzeichnis auf deine Synology NAS (z. B. nach `/volume1/docker/remote-antigravity`).
2. Öffne den **Container Manager** (Docker) in Synology DSM.
3. Gehe zu **Projekt** -> **Erstellen**.
4. Wähle das Projektverzeichnis aus und klicke auf **Weiter** (verwendet `docker-compose.yml`).
5. Starte das Projekt. Das Dashboard ist jetzt unter `http://<SYNOLOGY-IP>:8899` erreichbar.

---

### Teil 3: Verbindung auf dem iPhone herstellen
1. Befolge die Schritte in [`SETUP_TAILSCALE.md`](SETUP_TAILSCALE.md) zur Aktivierung von Tailscale.
2. Öffne Safari auf dem iPhone und rufe `http://<SYNOLOGY-TAILSCALE-IP>:8899` auf.
3. Klicke in Safari auf **Teilen** -> **Zum Home-Bildschirm** für App-Feeling.
4. Tippe oben rechts auf **⚙️ Einstellungen** und trage die **Tailscale IP deines PCs** (Port `8900`)
   sowie den Token ein – **oder** öffne direkt die Onboarding-URL `http://<PC-TAILSCALE-IP>:8900/?token=<TOKEN>`,
   dann wird der Token automatisch gespeichert und du musst nichts eintippen.
5. **Fertig!** Du kannst jetzt von überall unterwegs Antigravity auf deinem PC steuern.
