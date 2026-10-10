#Requires -Version 5.1
<#
.SYNOPSIS
    Ein-Klick-Installer fuer "Remote Antigravity" auf einem fremden Windows-PC.

.DESCRIPTION
    Fuehrt den Nutzer interaktiv durch die komplette Einrichtung:

      1. Repo ermitteln (lokal, wenn dieser Ordner schon vorliegt) oder bei Bedarf
         automatisch von GitHub klonen / als ZIP herunterladen
      2. Pruefen, ob die Antigravity IDE installiert ist
      3. Bei Bedarf automatisch mit Adminrechten neu starten (fuer Tailscale + Firewall)
      4. Das eigentliche Setup ausfuehren (scripts\setup_remote_antigravity.ps1)
      5. Eine Onboarding-Seite mit QR-Code fuer das Handy erzeugen und im Browser oeffnen

.NOTES
    Aufruf aus dem Repo heraus:  .\scripts\install_remote_antigravity.ps1
    Aufruf als Einzeiler (nur bei oeffentlichem Repo):
      powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='<RAW-URL>/scripts/install_remote_antigravity.ps1'; $f=\"$env:TEMP\ra-install.ps1\"; irm $u -OutFile $f; & $f"

.PARAMETER InstallDir
    Zielordner fuer den Klon. Standard: %USERPROFILE%\Projects\Remote Antigravity

.PARAMETER RepoUrl
    Git-URL des Repositories.

.PARAMETER Port
    Port fuer Dashboard und API. Standard: 8900.

.PARAMETER Yes
    Unbeaufsichtigter Modus: keine Rueckfragen, am Ende nicht warten.

.PARAMETER NoElevate
    Nicht automatisch mit Adminrechten neu starten.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = '',
    [string]$RepoUrl = 'https://github.com/dersma/Remote-Antigravity-Setup.git',
    [int]$Port = 8900,
    [switch]$Elevated,
    [switch]$NoElevate,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if (-not $InstallDir) { $InstallDir = Join-Path $env:USERPROFILE 'Projects\Remote Antigravity' }

function Write-Title { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Text) Write-Host "  [ok]  $Text" -ForegroundColor Green }
function Write-Info  { param([string]$Text) Write-Host "  [..]  $Text" -ForegroundColor Gray }
function Write-Warn  { param([string]$Text) Write-Host "  [!]   $Text" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Text) Write-Host "  [x]   $Text" -ForegroundColor Red }

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Pause-ForUser {
    param([string]$Text = 'Weiter mit ENTER ...')
    if ($Yes) { return }
    try { [void](Read-Host "`n$Text") } catch { }
}

function Test-RepoRoot {
    param([string]$Path)
    if (-not $Path) { return $false }
    return (Test-Path (Join-Path $Path 'pc_bridge\antigravity_bridge.py'))
}

function Resolve-RepoRoot {
    # 1) Skript liegt bereits in einem ausgecheckten Repository
    $scriptDir = $PSScriptRoot
    if ($scriptDir) {
        $candidate = Split-Path -Parent $scriptDir
        if (Test-RepoRoot -Path $candidate) { return $candidate }
    }
    # 2) Zielordner enthaelt bereits ein Repository
    if (Test-RepoRoot -Path $InstallDir) { return $InstallDir }
    return ''
}

function Get-ZipUrlFromGitUrl {
    param([string]$Url)
    $m = [regex]::Match($Url, 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)')
    if (-not $m.Success) { return '' }
    return "https://codeload.github.com/$($m.Groups['owner'].Value)/$($m.Groups['repo'].Value)/zip/refs/heads/main"
}

function Get-RepoFromGitHub {
    Write-Title "Repository besorgen"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        Write-Info "git clone $RepoUrl"
        Write-Info "Ziel: $InstallDir"
        # Verhindert, dass eine interaktive Passwortabfrage das Skript blockiert
        $env:GIT_TERMINAL_PROMPT = '0'
        & $git.Source clone --depth 1 $RepoUrl $InstallDir
        if ((Test-RepoRoot -Path $InstallDir)) {
            Write-Ok "Repository geklont"
            return $InstallDir
        }
        Write-Warn "git clone war nicht erfolgreich (privates Repository? Schreibrechte?)."
    } else {
        Write-Warn "git ist nicht installiert."
    }

    # Fallback: ZIP-Download (funktioniert nur bei oeffentlichen Repositories)
    $zipUrl = Get-ZipUrlFromGitUrl -Url $RepoUrl
    if (-not $zipUrl) { return '' }
    try {
        Write-Info "Lade ZIP: $zipUrl"
        $zip = Join-Path $env:TEMP 'remote-antigravity.zip'
        Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
        $extract = Join-Path $env:TEMP 'remote-antigravity-extract'
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        $inner = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
        if ($inner) {
            Get-ChildItem -Path $inner.FullName | Copy-Item -Destination $InstallDir -Recurse -Force
        }
        if (Test-RepoRoot -Path $InstallDir) {
            Write-Ok "Repository entpackt"
            return $InstallDir
        }
    } catch {
        Write-Warn "Download fehlgeschlagen: $_"
    }
    return ''
}

function New-OnboardingPage {
    param(
        [string]$RepoRoot,
        [string]$LaunchUrl,
        [string]$Token
    )

    $template = @'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Remote Antigravity &ndash; Einrichtung</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; padding:32px 20px; font-family:-apple-system,Segoe UI,Roboto,sans-serif;
         background:radial-gradient(1200px 600px at 20% -10%, #1b2740 0%, #090d16 60%); color:#e8edf7; }
  .wrap { max-width:720px; margin:0 auto; }
  h1 { font-size:28px; margin:0 0 6px; }
  .ok { color:#4ade80; }
  .sub { color:#93a4c3; margin:0 0 28px; }
  .card { background:rgba(255,255,255,.05); border:1px solid rgba(255,255,255,.1);
          border-radius:18px; padding:22px; margin-bottom:18px; }
  .qr { display:flex; justify-content:center; align-items:center; min-height:280px;
        background:#fff; border-radius:14px; padding:14px; }
  .url { font-family:ui-monospace,Consolas,monospace; font-size:15px; word-break:break-all;
         margin:14px 0 0; text-align:center; }
  .url a { color:#8ab4ff; }
  ol { margin:0; padding-left:22px; line-height:1.8; }
  .hint { color:#93a4c3; font-size:13px; }
  code { background:rgba(255,255,255,.08); padding:2px 6px; border-radius:6px; font-size:13px; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Remote Antigravity ist bereit <span class="ok">&#10003;</span></h1>
  <p class="sub">Scanne den QR-Code mit der Handy-Kamera &ndash; die Verbindung wird automatisch hergestellt.</p>

  <div class="card">
    <div class="qr"><div id="qrcode"></div></div>
    <p class="url"><a href="__LAUNCHURL__">__LAUNCHURL__</a></p>
  </div>

  <div class="card">
    <ol>
      <li><strong>Tailscale</strong> am Handy installieren (App Store / Play Store)</li>
      <li>Mit <strong>demselben Konto</strong> anmelden wie hier am PC</li>
      <li>VPN-Schalter aktivieren &ndash; dann den QR-Code scannen</li>
      <li>Optional: &bdquo;Zum Home-Bildschirm hinzuf&uuml;gen&ldquo; f&uuml;r App-Feeling</li>
    </ol>
  </div>

  <p class="hint">Token f&uuml;r die manuelle Eingabe: <code>__TOKEN__</code><br>
  Diese Datei hei&szlig;t <code>onboarding.html</code> und kann danach gel&ouml;scht werden.</p>
</div>
<script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
<script>
  (function () {
    var url = "__LAUNCHURL__";
    try {
      new QRCode(document.getElementById("qrcode"), {
        text: url,
        width: 260,
        height: 260,
        colorDark: "#000000",
        colorLight: "#ffffff",
        correctLevel: QRCode.CorrectLevel.M
      });
    } catch (e) {
      var box = document.getElementById("qrcode");
      box.style.color = "#222";
      box.style.fontWeight = "600";
      box.style.textAlign = "center";
      box.style.padding = "40px 10px";
      box.textContent = "QR-Code konnte nicht erzeugt werden (offline?). Nutze einfach den Link oben.";
    }
  })();
</script>
</body>
</html>
'@

    $html = $template.Replace('__LAUNCHURL__', $LaunchUrl).Replace('__TOKEN__', $Token)
    $path = Join-Path $RepoRoot 'onboarding.html'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $html, $utf8NoBom)
    return $path
}

function Restart-Elevated {
    param([string]$RepoRoot)

    $scriptPath = Join-Path $RepoRoot 'scripts\install_remote_antigravity.ps1'
    if (-not (Test-Path $scriptPath)) {
        Write-Warn "Installerskript nicht gefunden: $scriptPath"
        return $false
    }
    Write-Info "Starte den Installer mit Administratorrechten neu (bitte die UAC-Abfrage bestaetigen) ..."
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if (-not $Yes) { $argList += '-NoExit' }
    $argList += @('-File', "`"$scriptPath`"", '-Elevated',
                  '-InstallDir', "`"$($InstallDir.TrimEnd('\'))`"", '-Port', $Port)
    if ($Yes) { $argList += '-Yes' }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
        return $true
    } catch {
        Write-Warn "Neustart mit Adminrechten abgebrochen oder fehlgeschlagen: $_"
        return $false
    }
}

function Get-TailscaleExePath {
    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $p = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path $p) { return $p }
    return ''
}

# =============================================================================
# Ablauf
# =============================================================================

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "   Remote Antigravity - Installer" -ForegroundColor Magenta
Write-Host "   Deine Antigravity IDE vom Handy aus steuern." -ForegroundColor Magenta
Write-Host "   Ohne Domain, ohne Router-Freigabe, ohne NAS." -ForegroundColor DarkGray
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host " Der Installer richtet alles automatisch ein:" -ForegroundColor Gray
Write-Host "   Python-Umgebung  -  Tailscale  -  Firewall  -  Autostart  -  QR-Code" -ForegroundColor Gray
Pause-ForUser 'ENTER druecken zum Starten ...'

# --- 1/5 Repository ----------------------------------------------------------
Write-Title "1/5  Repository"
$repoRoot = Resolve-RepoRoot
if (-not $repoRoot) {
    Write-Info "Kein lokales Repository gefunden - hole es von GitHub ..."
    $repoRoot = Get-RepoFromGitHub
}
if (-not $repoRoot) {
    Write-Host ""
    Write-Fail "Das Repository konnte nicht automatisch besorgt werden."
    Write-Host ""
    Write-Host " Moegliche Ursachen und Loesungen:" -ForegroundColor Yellow
    Write-Host "   - Das Repository ist PRIVAT. Dann bitte:" -ForegroundColor Gray
    Write-Host "       a) den Projektordner als ZIP erhalten, entpacken und INSTALL.bat doppelklicken"
    Write-Host "       b) oder das Repository auf GitHub auf 'public' stellen"
    Write-Host "       c) oder sich als Collaborator einladen lassen (GitHub-Login noetig)"
    Write-Host "   - Kein git und keine Internetverbindung: Variante (a) verwenden."
    Pause-ForUser
    exit 1
}
Write-Ok "Projektordner: $repoRoot"

# --- 2/5 Antigravity IDE -----------------------------------------------------
Write-Title "2/5  Antigravity IDE"
$antigravityExe = Join-Path $env:LOCALAPPDATA 'Programs\antigravity\Antigravity.exe'
$agentApiBat = Join-Path $env:USERPROFILE '.gemini\antigravity\bin\agentapi.bat'
if (Test-Path $antigravityExe) {
    Write-Ok "Antigravity IDE gefunden"
    if (-not (Test-Path $agentApiBat)) {
        Write-Warn "agentapi.bat fehlt noch - bitte die Antigravity IDE einmal normal starten."
    }
} else {
    Write-Warn "Antigravity IDE wurde auf diesem PC nicht gefunden."
    Write-Info "Download: https://antigravity.google   (danach einmal normal starten)"
    if (-not $Yes) { try { Start-Process 'https://antigravity.google' } catch { } }
    Pause-ForUser 'ENTER zum Fortfahren (die Einrichtung laeuft auch ohne IDE durch) ...'
}

# --- 3/5 Rechte --------------------------------------------------------------
Write-Title "3/5  Rechte pruefen"
if (Test-IsAdmin) {
    Write-Ok "Administratorrechte vorhanden"
} else {
    $needAdmin = $false
    if (-not (Get-TailscaleExePath)) { $needAdmin = $true }
    else {
        try {
            if (-not (Get-NetFirewallRule -DisplayName "Remote Antigravity Bridge (TCP $Port)" -ErrorAction SilentlyContinue)) {
                $needAdmin = $true
            }
        } catch { $needAdmin = $true }
    }

    if ($needAdmin -and -not $NoElevate -and -not $Elevated) {
        if (Restart-Elevated -RepoRoot $repoRoot) { exit 0 }
        Write-Warn "Weiter ohne Adminrechte."
    } elseif ($needAdmin) {
        Write-Warn "Ohne Adminrechte koennen Tailscale-Installation und Firewall-Regel nicht gesetzt werden."
        Write-Info "Bitte danach einmal ausfuehren: powershell -ExecutionPolicy Bypass -File `"$repoRoot\scripts\setup_remote_antigravity.ps1`""
    } else {
        Write-Ok "Keine Adminrechte noetig (Tailscale und Firewall sind schon eingerichtet)"
    }
}

# --- 4/5 Einrichtung ---------------------------------------------------------
Write-Title "4/5  Einrichtung laufen lassen"
$setupScript = Join-Path $repoRoot 'scripts\setup_remote_antigravity.ps1'
if (-not (Test-Path $setupScript)) {
    Write-Fail "Setupskript nicht gefunden: $setupScript"
    Pause-ForUser
    exit 1
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript -Port $Port
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
    Write-Warn "Das Setupskript wurde mit Code $LASTEXITCODE beendet."
}

# --- 5/5 QR-Code und Abschluss ----------------------------------------------
Write-Title "5/5  Handy verbinden"

$configPath = Join-Path $repoRoot 'pc_bridge\config.json'
$token = ''
$dashboardUrl = ''
$configPort = $Port
if (Test-Path $configPath) {
    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($cfg.api_token) { $token = [string]$cfg.api_token }
        if ($cfg.dashboard_url) { $dashboardUrl = [string]$cfg.dashboard_url }
        if ($cfg.port) { $configPort = [int]$cfg.port }
    } catch { }
}

# Das Setup waehlt bei einem belegten Port automatisch einen anderen. Deshalb
# wird hier immer der Port aus der config.json verwendet - sonst zeigt der
# QR-Code auf einen falschen Port.
if (-not $dashboardUrl -or $dashboardUrl -match 'localhost') {
    $tsExe = Get-TailscaleExePath
    if ($tsExe) {
        try {
            $ip = & $tsExe ip -4 2>$null | Select-Object -First 1
            if ($ip) { $dashboardUrl = "http://$($ip.Trim()):$configPort" }
        } catch { }
    }
}
if (-not $dashboardUrl) { $dashboardUrl = "http://localhost:$configPort" }

if (-not $token -or -not (Test-Path $configPath)) {
    Write-Host ""
    Write-Fail "Die Einrichtung ist NICHT vollstaendig: $configPath fehlt oder enthaelt keinen Token."
    Write-Info "Bitte das Setup erneut ausfuehren:"
    Write-Info "  powershell -ExecutionPolicy Bypass -File `"$repoRoot\scripts\setup_remote_antigravity.ps1`""
    Pause-ForUser
    exit 1
}

$launchUrl = "$dashboardUrl/?token=$token"

$page = New-OnboardingPage -RepoRoot $repoRoot -LaunchUrl $launchUrl -Token $token
Write-Ok "Onboarding-Seite erstellt: $page"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host " FERTIG!" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host " Dashboard-URL fuer das Handy:" -ForegroundColor Cyan
Write-Host "   $launchUrl" -ForegroundColor Green
Write-Host ""
if ($dashboardUrl -match 'localhost') {
    Write-Host " Hinweis: Tailscale ist noch nicht verbunden. Nach 'tailscale up'" -ForegroundColor Yellow
    Write-Host " noch einmal den Installer starten, dann erscheint die 100.x.y.z-Adresse." -ForegroundColor Yellow
    Write-Host ""
}
Write-Host " Naechste Schritte:" -ForegroundColor Cyan
Write-Host "   1. Tailscale-App am Handy installieren und mit DEMSELBEN Konto anmelden"
Write-Host "   2. VPN aktivieren und den QR-Code auf der geoeffneten Seite scannen"
Write-Host "   3. Optional: 'Zum Home-Bildschirm hinzufuegen'"
Write-Host ""

if (-not $Yes) {
    Start-Process $page
    Write-Info "Der QR-Code wurde im Browser geoeffnet."
}

Write-Host " Die Bridge startet ab jetzt automatisch mit Windows." -ForegroundColor Gray
Write-Host " Manuell starten: $repoRoot\pc_bridge\start_pc_bridge.bat" -ForegroundColor Gray
Write-Host ""
Pause-ForUser 'Fertig - ENTER zum Schliessen ...'

