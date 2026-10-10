# 🚀 Remote Antigravity – Einrichtung für Freunde (Tailscale, ohne eigene Domain)

Diese Anleitung richtet **deinen eigenen** Windows-PC so ein, dass du deine Antigravity-IDE
von unterwegs über das Handy steuern kannst.

- ✅ **Keine Domain** nötig (kein Cloudflare, kein Tunnel-Account)
- ✅ **Keine Portfreigabe** im Router
- ✅ **Keine NAS / kein Docker** nötig
- ✅ **Kostenlos** (Tailscale Personal Plan)

---

## ⬇️ Der allereinfachste Weg: eine einzige Datei

1. Im GitHub-Release **`Remote-Antigravity-Installer.bat`** herunterladen (eine Datei, ein Doppelklick).
2. Doppelklick auf die Datei – sie lädt das Paket, entpackt es nach `%USERPROFILE%\Projects`
   und startet automatisch die geführte Einrichtung.

Falls Windows beim Start der heruntergeladenen Datei nachfragt: **„Weitere Informationen“ →
„Trotzdem ausführen“** wählen (die Datei ist nicht signiert).

Alternativ gibt es im Release die ZIP-Datei `Remote-Antigravity.zip`: herunterladen, entpacken und
im Ordner `Remote-Antigravity` die **`INSTALL.bat`** doppelklicken.

---

## ⚡ Zweiter Weg: `INSTALL.bat` doppelklicken

1. Du bekommst den **Projektordner** (als ZIP oder per GitHub-Zugriff).
2. ZIP entpacken – der Ordner heißt `Remote-Antigravity`.
3. **`INSTALL.bat` doppelklicken.** Fertig.

Der Installer führt dich durch alles: er prüft Python und die Antigravity IDE, fragt einmalig
Adminrechte an (für Tailscale + Firewall), installiert Tailscale, öffnet den Browser für den
**Tailscale-Login**, startet die Bridge, richtet den Autostart ein und zeigt am Ende eine
Seite mit **QR-Code** für dein Handy. Diesen QR-Code scannst du mit der Handy-Kamera – fertig.

> Optional: `INSTALL.bat -Port 8900` (anderer Port), `INSTALL.bat -NoElevate` (ohne Adminneustart).

---

## 🤖 Zweiter Weg: deinem Antigravity den Auftrag geben

Wenn du das Projekt bereits als Ordner hast (geklont oder entpackt) und Antigravity installiert ist:

1. In Antigravity den Ordner öffnen (`File → Open Folder`).
2. Diesen Text in den Antigravity-Chat kopieren und absenden:

   ```text
   Lies die Datei AGENTS.md in diesem Repository und richte das Projekt "Remote Antigravity"
   vollständig auf diesem Windows-PC ein. Führe dazu aus:

   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_remote_antigravity.ps1

   Das Skript erledigt Python, die virtuelle Umgebung, Installation und Anmeldung von Tailscale,
   die Konfiguration, die Firewall-Regel, den Start der PC-Bridge und den Autostart.

   Prüfe anschließend bitte alles genau wie in AGENTS.md im Abschnitt "3. Verifikation"
   beschrieben und fasse mir das Ergebnis zusammen: Dashboard-URL, Tailscale-IP und Token.

   Wichtig: Nichts am Design des Projekts ändern, pc_bridge/config.json niemals committen und
   keine Ports im Router freigeben.
   ```

3. **Tailscale-Login:** Dabei öffnet sich einmalig ein Browser. Dort mit dem Konto anmelden,
   das du auch auf dem Handy benutzt (z. B. Google).

---

## 🔗 Wozu genau ist „klonen" nötig? (und was heißt das?)

GitHub ist nur die **Quelle** des Projekts. Damit ein Werkzeug (oder ein KI-Agent wie Antigravity)
damit arbeiten kann, müssen die Dateien **auf deinem PC liegen**. Das nennt man „klonen" –
es ist technisch nur ein Befehl, der den Ordner herunterlädt:

```powershell
git clone https://github.com/dersma/Remote-Antigravity-Setup.git
```

**Wichtig – dabei ist deine Repo privat!**

Ich habe geprüft: `github.com/dersma/Remote-Antigravity-Setup` ist **nicht öffentlich** (die GitHub-API
antwortet anonym mit „404 Not Found"). Ein einfacher Link zum Klonen funktioniert deshalb nur,
wenn eine dieser drei Sachen zutrifft:

| Variante | Was nötig ist |
|---|---|
| **A) ZIP weitergeben** (am einfachsten) | Der Besitzer schickt dir den Ordner als ZIP → entpacken → `INSTALL.bat`. Kein GitHub-Konto nötig. |
| **B) Repo öffentlich stellen** | Repo auf GitHub → *Settings → General → Danger Zone → Change visibility → Public*. Danach geht auch der Einzeiler unten. |
| **C) Als Collaborator einladen** | GitHub → *Settings → Collaborators → Add people*. Du brauchst einen GitHub-Account und meldest dich beim Klonen an. |

**Einzeiler (nur bei öffentlichem Repository)** – lädt und startet alles in einem Schritt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='https://raw.githubusercontent.com/dersma/Remote-Antigravity/main/scripts/install_remote_antigravity.ps1'; $f=Join-Path $env:TEMP 'ra-install.ps1'; Invoke-WebRequest $u -OutFile $f; & $f"
```

Danach klont sich der Installer das Projekt selbst nach `%USERPROFILE%\Projects\Remote Antigravity`.


---

## 📱 Handy einrichten (einmalig)

1. **Tailscale-App** installieren: App Store (iPhone) oder Play Store (Android).
2. Mit **demselben Account** anmelden wie am PC und den VPN-Schalter aktivieren.
3. **Den QR-Code** aus dem Installer mit der Handy-Kamera scannen (oder die Dashboard-URL öffnen,
   die der Installer anzeigt) → das Token wird automatisch übernommen, du musst nichts eintippen.
4. Optional: In Safari/Chrome **„Zum Home-Bildschirm hinzufügen"** → fühlt sich an wie eine App.
5. Test: WLAN am Handy ausschalten (nur Mobilfunk) – die Seite muss weiter funktionieren.

---

## 🖱️ Dritter Weg: manuell (falls du alles selbst machen willst)

Zuerst den Projektordner auf den PC bringen – bei einer **privaten** Repo per ZIP:

```powershell
# Ordner entpacken, dann im Projektordner:
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_remote_antigravity.ps1
```

Oder – nur wenn die Repo öffentlich ist – direkt klonen:

```powershell
git clone https://github.com/dersma/Remote-Antigravity-Setup.git
cd Remote-Antigravity
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_remote_antigravity.ps1
```

Für die Tailscale-Installation und die Firewall-Regel ist eine **PowerShell als Administrator**
empfohlen. Läuft das Skript ohne Adminrechte, überspringt es genau diese zwei Schritte und zeigt
dir die Befehle zum Nachholen an.

Nützliche Schalter:

| Befehl | Wirkung |
|---|---|
| `... install_remote_antigravity.ps1` | kompletter, geführter Installer (empfohlen) |
| `... install_remote_antigravity.ps1 -InstallDir D:\Remote` | anderer Zielordner |
| `... install_remote_antigravity.ps1 -Yes` | unbeaufsichtigt (keine Rückfragen) |
| `... setup_remote_antigravity.ps1 -Port 8900` | anderer Port |
| `... setup_remote_antigravity.ps1 -SkipTailscale` | Tailscale-Schritte überspringen |
| `... setup_remote_antigravity.ps1 -SkipAutostart` | keinen Autostart-Eintrag anlegen |

---

## ✅ Was danach automatisch passiert

- Die **PC-Bridge** (Dashboard + API) läuft auf Port `8900` und startet bei jedem Windows-Start mit
  (Autostart-Verknüpfung „Remote Antigravity").
- Die Antigravity-IDE wird beim Start mitgestartet.
- Konfiguration und Token liegen in `pc_bridge/config.json` (nicht im Git).
- Ein System-Tray-Symbol zeigt den Status und öffnet das Dashboard.

## 🔧 Wenn etwas nicht klappt

| Problem | Lösung |
|---|---|
| Handy lädt die Seite nicht | Tailscale-App am Handy an? Gleicher Account wie am PC? |
| Seite lädt, aber ein anderer Port war angegeben | Bei belegtem Port 8900 weicht der Installer automatisch aus – den gültigen Port findest du in `pc_bridge\config.json` (Feld `port`). |
| „Token ungültig" | In den Dashboard-Einstellungen (⚙️) das Token aus `pc_bridge/config.json` eintragen |
| Bridge läuft nicht | `pc_bridge\start_pc_bridge.bat` doppelklicken; Log: `pc_bridge\crash.log` |
| Tailscale nicht installiert | `winget install --id Tailscale.Tailscale -e` oder manuell von tailscale.com/download |
| „agentapi: False" | Antigravity IDE einmal normal starten (erzeugt `%USERPROFILE%\.gemini\antigravity\bin\agentapi.bat`) |

Details, Verifikationsbefehle und die Agenten-Anleitung stehen in [`AGENTS.md`](AGENTS.md).
Die ursprüngliche NAS/Tailscale-Anleitung bleibt in [`SETUP_TAILSCALE.md`](SETUP_TAILSCALE.md).

**Kurzfassung für Ungeduldige:** ZIP erhalten → entpacken → `INSTALL.bat` doppelklicken → QR-Code
mit dem Handy scannen. Alles andere macht der Installer.
