# AGENTS.md – Einrichtung durch KI-Agenten

Anleitung für KI-Agenten (Antigravity, Cline, Cursor, Codex), die dieses Repository auf einem
Windows-PC einrichten.

Projekt: PWA-Dashboard zur Fernsteuerung einer Antigravity IDE auf einem Windows-PC.
Transport: Tailscale. Keine Domain, kein Cloudflare, keine Portfreigabe, keine NAS erforderlich.

## Aufgabe

Wenn der Nutzer die Einrichtung verlangt, führe im Repository-Stammverzeichnis genau einen Befehl aus:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_remote_antigravity.ps1
```

Das Skript ist idempotent und kann beliebig oft erneut ausgeführt werden.

Für Endnutzer gibt es zusätzlich `INSTALL.bat` (Doppelklick) bzw.
`scripts\install_remote_antigravity.ps1`. Dieser geführte Installer:

- prüft Python und die Antigravity IDE (öffnet bei Bedarf die Download-Seite)
- startet sich bei Bedarf mit Adminrechten neu (UAC)
- besorgt das Repository (lokal, per `git clone` oder ZIP-Download)
- ruft `setup_remote_antigravity.ps1` auf
- erzeugt `onboarding.html` mit QR-Code der Dashboard-URL und öffnet sie im Browser

Ist das Repository privat, funktionieren `git clone` und der ZIP-/Raw-Download ohne Zugangsdaten
nicht. Dann den Projektordner als ZIP weitergeben und dort `INSTALL.bat` starten, das Repository
öffentlich stellen oder den Nutzer als Collaborator einladen.

## Ablauf des Setupskripts

| Schritt | Inhalt |
|---|---|
| 1 | Python erkennen (`py -3`, `python`, Standardpfad); bei Bedarf per winget installieren |
| 2 | `.venv` anlegen und `pc_bridge\requirements.txt` installieren |
| 3 | Tailscale installieren (winget, sonst offizielles MSI), `tailscale up` (Browser-Login) |
| 4 | Port ermitteln (belegter Port → nächster freier) und `pc_bridge\config.json` schreiben |
| 5 | Firewall-Regel für den Port nur auf `100.64.0.0/10` freigeben (Admin erforderlich) |
| 6 | Bridge starten und über `http://127.0.0.1:<port>/health` prüfen |
| 7 | Autostart-Verknüpfung anlegen |

## Voraussetzungen

- Windows 10/11, PowerShell 5.1+
- Antigravity IDE installiert und einmal gestartet
  (erzeugt `%USERPROFILE%\.gemini\antigravity\bin\agentapi.bat`)
- Adminrechte für Schritt 3 und 5; ohne Adminrechte überspringt das Skript diese Schritte mit Hinweis
- Internetverbindung

## Verifikation

```powershell
# a) Listener auf dem konfigurierten Port
Get-NetTCPConnection -LocalPort 8900 -State Listen | Select-Object LocalAddress, LocalPort

# b) API-Antwort (Token und Port aus der Konfiguration)
$cfg = Get-Content .\pc_bridge\config.json -Raw | ConvertFrom-Json
Invoke-RestMethod "http://127.0.0.1:$($cfg.port)/health?token=$($cfg.api_token)" | Format-List

# c) Tailscale
tailscale status
tailscale ip -4

# d) Firewall-Regel
Get-NetFirewallRule -DisplayName "Remote Antigravity Bridge (TCP 8900)" |
  Select-Object DisplayName, Enabled, Direction, Action
```

Erwartet: (a) Listener auf `0.0.0.0:<port>`, (b) `status : online`, (c) `BackendState = Running`
und eine `100.x.y.z`-Adresse, (d) aktive Allow-Regel.

## Manueller Fallback

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\pc_bridge\requirements.txt

winget install --id Tailscale.Tailscale -e --silent --accept-package-agreements --accept-source-agreements
tailscale up
tailscale ip -4

# pc_bridge\config.json anlegen (Vorlage: pc_bridge\config.example.json)

New-NetFirewallRule -DisplayName "Remote Antigravity Bridge (TCP 8900)" -Direction Inbound `
  -Action Allow -Protocol TCP -LocalPort 8900 -RemoteAddress 100.64.0.0/10 -Profile Any

.\pc_bridge\start_pc_bridge.bat
```

## Architektur

```
Handy (Tailscale-App) -> Windows-PC
                        ├── pc_bridge/antigravity_bridge.py (Port 8900: Dashboard + API)
                        │     └── ruft agentapi.bat der Antigravity IDE auf
                        └── .venv/
```

- Port 8900 wird von Dashboard und API gemeinsam genutzt.
- `pc_bridge/config.json` ist git-ignoriert und enthält Token, Pfade und Port.
- Auflösungsreihenfolge: Umgebungsvariable → `config.json` → Standard
  (`workspace` = Repository-Ordner, `projects_root` = dessen Elternordner).

## Guardrails

- Token, `pc_bridge/config.json` und `onboarding.html` niemals committen.
- Firewall-Port nur auf `100.64.0.0/10` beschränken, nicht für alle Adressen öffnen.
- Keine Portfreigabe im Router, kein Cloudflare/Tunnel einrichten.
- Kein `git push --force`.
- Keine Pfade hartcodieren; alles relativ zur Repository-Position ableiten.

## Problembehandlung

| Symptom | Lösung |
|---|---|
| Bridge antwortet nicht | `pc_bridge\crash.log` prüfen; Port belegt? |
| Port 8900 belegt | Das Setup weicht automatisch auf den nächsten freien Port aus; Port steht in `config.json` |
| Handy erreicht das Dashboard nicht | Tailscale am Handy aktiv, gleiches Konto, Firewall-Regel vorhanden |
| `agentapi: False` | Antigravity IDE einmal normal starten |
| Tailscale „NeedsLogin“ | `tailscale up` erneut ausführen |
| Kein Python gefunden | `py -3 --version` prüfen, sonst Python 3.12 installieren („Add to PATH“) |
