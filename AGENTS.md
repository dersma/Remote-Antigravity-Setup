# AGENTS.md – Setup-Anleitung für KI-Agenten

Diese Datei ist für KI-Agenten (Antigravity, Cline, Cursor, Codex, ...) gedacht, die dieses
Repository auf einen **fremden Windows-PC** einrichten sollen.

**Projekt:** Remote Antigravity – ein PWA-Dashboard, mit dem ein iPhone/Android-Handy eine
Antigravity-IDE auf einem Windows-PC fernsteuert (Prompts senden, Logs streamen, Git-Diff ansehen).
**Transport:** Tailscale (kostenloses Mesh-VPN) – **keine** eigene Domain, **kein** Cloudflare,
**keine** Portfreigabe im Router, **keine** NAS nötig.

---

## 1. Aufgabe

Wenn der Nutzer sagt: *"Richte Remote Antigravity ein"* / *"Setz das Projekt auf"*, dann führe
**genau einen** Befehl aus (aus dem Repository-Stammverzeichnis):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_remote_antigravity.ps1
```

Das Skript ist idempotent – es kann beliebig oft erneut ausgeführt werden.

### Geführter Installer (für Menschen gedacht)

Für Endnutzer gibt es zusätzlich `INSTALL.bat` (Doppelklick) bzw.
`scripts\install_remote_antigravity.ps1`. Dieser Installer:

- prüft Python und die **Antigravity IDE** (und öffnet ggf. die Download-Seite),
- startet sich bei Bedarf **selbst mit Adminrechten neu** (UAC),
- holt das Repository (lokal, per `git clone` oder ZIP-Download),
- ruft anschließend `setup_remote_antigravity.ps1` auf,
- erzeugt `onboarding.html` mit **QR-Code** der Dashboard-URL und öffnet sie im Browser.

> ⚠️ **Repository-Sichtbarkeit prüfen:** Ist das Repository **privat**, kann weder `git clone`
> noch der ZIP-/Raw-Download ohne Zugangsdaten funktionieren. In dem Fall den Projektordner als
> ZIP weitergeben (Nutzer entpackt ihn und startet `INSTALL.bat`) oder das Repository öffentlich
> stellen / den Nutzer als Collaborator einladen. Der Installer erkennt das Problem und nennt
> dem Nutzer genau diese Optionen.

### Was das Skript automatisch macht

| # | Schritt | Details |
|---|---------|---------|
| 1 | Python erkennen | `py -3` → `python` → Standard-Installationsordner; bei Bedarf `winget install Python.Python.3.12` |
| 2 | `.venv` + Abhängigkeiten | erstellt `<repo>\.venv` und installiert `pc_bridge\requirements.txt` |
| 3 | Tailscale | `winget install --id Tailscale.Tailscale` (Fallback: offizielles MSI von `pkgs.tailscale.com`), danach `tailscale up` (= Browser-Login durch den Nutzer) |
| 4 | Konfiguration | schreibt `pc_bridge\config.json` mit Zufalls-Token, Workspace-Pfad und Tailscale-IP |
| 5 | Firewall | öffnet TCP **8900** ausschließlich für das Tailscale-Netz `100.64.0.0/10` (benötigt Admin) |
| 6 | Start + Prüfung | startet die Bridge versteckt und pollt `http://127.0.0.1:8900/health` |
| 7 | Autostart | Verknüpfung `Remote Antigravity.lnk` im Autostart-Ordner des Nutzers |

Am Ende gibt das Skript eine **fertige Dashboard-URL inkl. Token** aus, z. B.
`http://100.101.102.103:8900/?token=AbC123...` – diese URL öffnet der Nutzer auf dem Handy.

---

## 2. Voraussetzungen

- **Windows 10/11** mit PowerShell 5.1+
- **Antigravity IDE** installiert (`%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe`) und
  mindestens **einmal gestartet**, damit `%USERPROFILE%\.gemini\antigravity\bin\agentapi.bat` existiert
- **Admin-Rechte** für Schritt 3 (Tailscale) und 5 (Firewall). Ohne Adminrechte überspringt das
  Skript diese Schritte mit einer Warnung und nennt den manuellen Befehl.
- **Internetverbindung** (winget, Tailscale-Login)

---

## 3. Verifikation (immer durchführen!)

Nach dem Setup **musst** du diese Checks ausführen und ihre Ergebnisse dem Nutzer zeigen:

```powershell
# a) Läuft die Bridge?
Get-NetTCPConnection -LocalPort 8900 -State Listen | Select-Object LocalAddress, LocalPort

# b) Antwortet die API? (Token wird automatisch aus der Config gelesen)
$cfg = Get-Content .\pc_bridge\config.json -Raw | ConvertFrom-Json
Invoke-RestMethod "http://127.0.0.1:8900/health?token=$($cfg.api_token)" | Format-List

# c) Tailscale verbunden + IP?
tailscale status
tailscale ip -4

# d) Firewall-Regel vorhanden?
Get-NetFirewallRule -DisplayName "Remote Antigravity Bridge (TCP 8900)" |
  Select-Object DisplayName, Enabled, Direction, Action
```

**Erwartet:** (a) ein Listener auf `0.0.0.0:8900`, (b) `status : online`, (c)
`BackendState = Running` + eine `100.x.y.z`-Adresse, (d) eine aktive Allow-Regel.

Host-Check vom Handy aus (optional, wenn Tailscale auf dem Handy läuft):
`http://<100.x.y.z>:8900/health?token=<token>` → muss `{"status":"online"}` liefern.

---

## 4. Manueller Fallback (falls winget o. Ä. nicht verfügbar ist)

```powershell
# 1. Python-Abhängigkeiten
py -3 -m venv .venv                      # oder: python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\pc_bridge\requirements.txt

# 2. Tailscale installieren und anmelden
winget install --id Tailscale.Tailscale -e --silent --accept-package-agreements --accept-source-agreements
tailscale up                             # Browser-Login bestätigen
tailscale ip -4                          # -> 100.x.y.z notieren

# 3. config.json anlegen (Vorlage: pc_bridge\config.example.json) und anpassen
notepad .\pc_bridge\config.json

# 4. Firewall (nur Tailscale-Netz)
New-NetFirewallRule -DisplayName "Remote Antigravity Bridge (TCP 8900)" -Direction Inbound `
  -Action Allow -Protocol TCP -LocalPort 8900 -RemoteAddress 100.64.0.0/10 -Profile Any

# 5. Bridge starten
.\pc_bridge\start_pc_bridge.bat
```

---

## 5. Architektur (Kurzüberblick)

```
Handy (Tailscale-App)  ──HTTP──►  Windows-PC
                                  ├── pc_bridge/antigravity_bridge.py  (Port 8900)
                                  │     ├─ Dashboard/PWA  (frontend/)
                                  │     ├─ REST + WebSocket API
                                  │     └─ ruft agentapi.bat der Antigravity IDE auf
                                  └── .venv/  (Python-Abhängigkeiten)
```

- **Port 8900** wird von Dashboard **und** API gemeinsam genutzt → der Nutzer braucht nur eine URL.
- `pc_bridge/config.json` (git-ignoriert) enthält Token + Pfade. **Niemals committen!**
- `server/` ist nur für den optionalen Synology-/Docker-Betrieb; für private Setups nicht nötig.
- Werte werden in dieser Reihenfolge aufgelöst: **Umgebungsvariable** → **`config.json`** → **Standard**
  (`workspace` = Repository-Ordner, `projects_root` = dessen Elternordner).

---

## 6. Guardrails für Agenten

- **Nicht** den API-Token, `pc_bridge/config.json` oder `onboarding.html` committen
  (`onboarding.html` enthält die Dashboard-URL inkl. Token!).
- **Nicht** den Firewall-Port für alle Profile/alle Adressen öffnen – immer auf `100.64.0.0/10`
  (Tailscale) beschränken.
- **Nicht** Ports im Router freigeben und **kein** Cloudflare/Tunnel einrichten – Tailscale genügt.
- **Nicht** `git push --force` verwenden.
- Pfade nie hardcodieren: Skripte und Bridge leiten alles relativ zur Repository-Position ab.
- Kein Setup-Schritt erfordert eine NAS, Docker oder eine eigene Domain.

---

## 7. Troubleshooting

| Symptom | Ursache / Lösung |
|---|---|
| `Bridge antwortet noch nicht` | Log prüfen: `pc_bridge\crash.log` und `pc_bridge\tray.log`; Port belegt? `Get-NetTCPConnection -LocalPort 8900` |
| Port 8900 ist anderweitig belegt | Das Setup weicht **automatisch** auf den nächsten freien Port aus (8901, 8902, ...) und schreibt ihn in `pc_bridge\config.json`. Die angezeigte Dashboard-URL gilt jeweils. |
| Handy erreicht das Dashboard nicht | Tailscale auf dem **Handy** aktiv? Gleicher Account? `tailscale status` am PC zeigt das Handy? Firewall-Regel vorhanden (Schritt 3d)? |
| `agentapi: False` im Health-Check | Antigravity IDE einmal starten; prüfen ob `%USERPROFILE%\.gemini\antigravity\bin\agentapi.bat` existiert |
| Token vergessen | `pc_bridge\config.json` öffnen (Feld `api_token`) |
| Tailscale „NeedsLogin" | `tailscale up` erneut ausführen und Browser-Login bestätigen |
| Python wurde nicht gefunden | `py -3 --version` prüfen; sonst Python 3.12 von python.org installieren („Add to PATH" aktivieren) |

