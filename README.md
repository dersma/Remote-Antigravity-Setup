# Remote Antigravity

Steuert die **Antigravity IDE** auf einem Windows-PC vom Handy (iPhone/Android) aus – über
**Tailscale**, ohne eigene Domain, ohne Cloudflare, ohne Router-Freigabe und ohne NAS.
Dashboard, API und Bridge laufen vollständig auf dem Windows-PC.

## Installation

**Download:** <https://github.com/dersma/Remote-Antigravity-Setup/releases/latest>

1. `Remote-Antigravity-Installer.bat` herunterladen und doppelklicken.
   Falls Windows warnt: „Weitere Informationen“ → „Trotzdem ausführen“.
2. `ENTER` drücken, die UAC-Abfrage bestätigen und im Browser den **Tailscale-Login** abschließen.
3. Den angezeigten **QR-Code** mit dem Handy scannen.

Offline-Variante: `Remote-Antigravity.zip` herunterladen, entpacken und `INSTALL.bat` doppelklicken.

## Voraussetzungen

| Voraussetzung | Details |
|---|---|
| System | Windows 10/11 |
| Antigravity IDE | installiert und einmal gestartet (erzeugt `%USERPROFILE%\.gemini\antigravity\bin\agentapi.bat`) |
| Rechte | einmalig Adminrechte für Tailscale-Installation und Firewall-Regel (UAC) |
| Handy | Tailscale-App, angemeldet mit demselben Konto wie der PC |
| Netz | Internetzugang für Python- und Tailscale-Download |

## Was der Installer automatisch einrichtet

- prüft Python und installiert es bei Bedarf
- legt `.venv` an und installiert alle Abhängigkeiten
- installiert **Tailscale** und startet den Login
- schreibt `pc_bridge/config.json` (Token, Pfade, Port) und öffnet die Firewall **nur für das
  Tailscale-Netz** `100.64.0.0/10`
- startet die Bridge auf Port `8900` (bei belegtem Port automatisch auf den nächsten freien) und prüft sie
- richtet den Autostart ein und öffnet die Onboarding-Seite mit dem QR-Code

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `frontend/` | Mobile Oberfläche (PWA, HTML/CSS/JavaScript) |
| `pc_bridge/` | Dashboard und REST-/WebSocket-API (Port 8900) |
| `scripts/` | Setup- und Installationsskripte |
| `INSTALL.bat`, `INSTALL_FROM_GITHUB.bat` | Einstiegspunkte der Installation |
| `pc_bridge/config.json` | lokale Konfiguration, wird beim Setup erzeugt (nicht im Git) |
| `AGENTS.md` | Einrichtung durch KI-Agenten (Antigravity, Cline, …) |

## Problembehandlung

| Symptom | Lösung |
|---|---|
| Handy lädt das Dashboard nicht | Tailscale am Handy aktiv? Gleiches Konto? Firewall-Regel vorhanden? |
| „Token ungültig“ | Token aus `pc_bridge/config.json` in den Einstellungen der Oberfläche eintragen |
| Bridge läuft nicht | `pc_bridge\start_pc_bridge.bat` doppelklicken; Log: `pc_bridge\crash.log` |
| „agentapi: False“ | Antigravity IDE einmal normal starten |
| Anderer Port als 8900 | der verwendete Port steht in `pc_bridge/config.json` (Feld `port`) |
