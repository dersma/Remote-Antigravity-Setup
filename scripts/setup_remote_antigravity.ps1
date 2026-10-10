#Requires -Version 5.1
<#
.SYNOPSIS
    One-shot Setup fuer "Remote Antigravity" auf einem frischen Windows-PC.

.DESCRIPTION
    Richtet den kompletten Remote-Antigravity-Stack auf DIESEM Rechner ein:

      1. Python erkennen (und bei Bedarf via winget installieren)
      2. Lokale virtuelle Umgebung (.venv) anlegen und Abhaengigkeiten installieren
      3. Tailscale installieren (winget, Fallback: offizielles MSI) und anmelden
      4. Lokale Konfiguration schreiben (pc_bridge/config.json) inkl. Zufalls-Token
         und der Tailscale-IP des PCs
      5. Windows-Firewall: Port nur fuer das Tailscale-Netz (100.64.0.0/10) oeffnen
      6. PC-Bridge (Dashboard + API) starten und Erreichbarkeit pruefen
      7. Autostart anlegen (optional)

    Es werden KEINE projektspezifischen Pfade hardcodiert - das Skript arbeitet
    immer relativ zu seiner eigenen Position im Repository.

.PARAMETER Port
    Port fuer Dashboard und API. Standard: 8900.

.PARAMETER SkipTailscale
    Tailscale-Schritte ueberspringen (z. B. wenn es schon laeuft/eingerichtet ist).

.PARAMETER SkipAutostart
    Keinen Autostart-Eintrag anlegen.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_remote_antigravity.ps1
#>
[CmdletBinding()]
param(
    [int]$Port = 8900,
    [switch]$SkipTailscale,
    [switch]$SkipAutostart
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- Paths (immer relativ zur Repository-Position) ---------------------------
$RepoRoot     = Split-Path -Parent $PSScriptRoot
$BridgeDir    = Join-Path $RepoRoot 'pc_bridge'
$VenvDir      = Join-Path $RepoRoot '.venv'
$Requirements = Join-Path $BridgeDir 'requirements.txt'
$ConfigPath   = Join-Path $BridgeDir 'config.json'
$HiddenVbs    = Join-Path $BridgeDir 'start_hidden.vbs'
$AutostartVbs = Join-Path $BridgeDir 'autostart_remote_antigravity.vbs'
$FirewallName = "Remote Antigravity Bridge (TCP $Port)"

function Write-Step { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  [ok]  $Text" -ForegroundColor Green }
function Write-Info { param([string]$Text) Write-Host "  [..]  $Text" -ForegroundColor Gray }
function Write-Warn { param([string]$Text) Write-Host "  [!]   $Text" -ForegroundColor Yellow }
function Write-Fail { param([string]$Text) Write-Host "  [x]   $Text" -ForegroundColor Red }

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-PythonExe {
    # 1) py launcher  ->  echter Interpreterpfad
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $out = & $py.Source -3 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -First 1).Trim() }
        } catch { }
    }
    # 2) ALLE python/python3-Treffer im PATH pruefen. Der WindowsApps-Stub liefert
    #    keinen Output und der Python-2-Check liefert einen leeren String - beides
    #    faellt dadurch heraus.
    foreach ($name in @('python', 'python3')) {
        foreach ($cmd in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
            if (-not $cmd.Source) { continue }
            try {
                $out = & $cmd.Source -c "import sys;print(sys.executable if sys.version_info[0]==3 else '')" 2>$null
                if ($LASTEXITCODE -eq 0 -and $out -and ($out | Select-Object -First 1).Trim()) {
                    return ($out | Select-Object -First 1).Trim()
                }
            } catch { }
        }
    }
    # 3) Standard-Installationsordner (frisch per winget installiert)
    $found = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe') `
                           -ErrorAction SilentlyContinue |
             Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Install-Python {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Fail "Python fehlt und winget ist nicht verfuegbar."
        Write-Info "Bitte Python 3.12 von https://www.python.org/downloads/windows/ installieren"
        Write-Info "(Haken bei 'Add python.exe to PATH' setzen) und das Skript erneut ausfuehren."
        return $false
    }
    Write-Info "Installiere Python 3.12 via winget ..."
    & $winget.Source install --id Python.Python.3.12 -e --silent `
        --accept-source-agreements --accept-package-agreements
    # 0 = ok, -1978335189 = bereits installiert
    return (($LASTEXITCODE -eq 0) -or ($LASTEXITCODE -eq -1978335189))
}

function Resolve-TailscaleExe {
    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @((Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'))
    if (Test-Path 'Env:ProgramFiles(x86)') {
        $paths += (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe')
    }
    foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Install-Tailscale {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "winget install --id Tailscale.Tailscale -e --silent"
        & $winget.Source install --id Tailscale.Tailscale -e --silent `
            --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { return $true }
        Write-Warn "winget-Installation fehlgeschlagen (Exitcode $LASTEXITCODE) - Fallback: MSI-Download"
    } else {
        Write-Warn "winget nicht verfuegbar - Fallback: MSI-Download"
    }

    try {
        Write-Info "Ermittle aktuelle Tailscale-Version ..."
        $index = (Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/' -UseBasicParsing).Content
        $match = [regex]::Match($index, 'tailscale-setup-([0-9]+\.[0-9]+\.[0-9]+)-amd64\.msi')
        if (-not $match.Success) { throw 'MSI-Dateiname auf pkgs.tailscale.com nicht gefunden' }
        $url = "https://pkgs.tailscale.com/stable/tailscale-setup-$($match.Groups[1].Value)-amd64.msi"
        $msi = Join-Path $env:TEMP 'tailscale-setup-amd64.msi'
        Write-Info "Download: $url"
        Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
        Write-Info "Installiere MSI (silent) ..."
        $proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
            '/i', "`"$msi`"", '/qn', '/norestart',
            'TS_NOLAUNCH=1', 'TS_ALLOWINCOMINGCONNECTIONS=always')
        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) { return $true }
        throw "msiexec Exitcode $($proc.ExitCode)"
    } catch {
        Write-Fail "Tailscale-Installation fehlgeschlagen: $_"
        return $false
    }
}

function Get-TailscaleState {
    param([string]$Exe)
    try {
        $raw = & $Exe status --json 2>$null | Out-String
        if ($raw -and $raw.TrimStart().StartsWith('{')) { return ($raw | ConvertFrom-Json) }
    } catch { }
    return $null
}

function Connect-Tailscale {
    param([string]$Exe)

    $state = Get-TailscaleState -Exe $Exe
    if ($state -and $state.BackendState -eq 'Running') {
        Write-Ok "Tailscale ist bereits verbunden (BackendState=Running)"
        return $true
    }

    Write-Info "Tailscale-Anmeldung startet gleich. Es oeffnet sich ein Browserfenster -"
    Write-Info "bitte dort anmelden (z. B. mit dem Google-Konto). Danach laeuft das Setup weiter."
    & $Exe up 2>&1 | ForEach-Object { Write-Info "$_" }

    $state = Get-TailscaleState -Exe $Exe
    if ($state -and $state.BackendState -eq 'Running') {
        Write-Ok "Tailscale ist verbunden"
        return $true
    }
    Write-Warn "Tailscale ist noch nicht verbunden. Bitte spaeter 'tailscale up' ausfuehren."
    return $false
}

function Get-TailscaleIPv4 {
    param([string]$Exe)
    try {
        $out = & $Exe ip -4 2>$null | Select-Object -First 1
        if ($out) { return $out.Trim() }
    } catch { }
    return ''
}

function New-ApiToken {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    return (-join (1..40 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }))
}

function Get-OrCreateApiToken {
    if (Test-Path $ConfigPath) {
        try {
            $existing = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            if ($existing.api_token) { return [string]$existing.api_token }
        } catch { }
    }
    return (New-ApiToken)
}

function Write-BridgeConfig {
    param([string]$Token, [string]$DashboardUrl)

    $config = [ordered]@{
        api_token     = $Token
        workspace     = $RepoRoot
        projects_root = (Split-Path -Parent $RepoRoot)
        host          = '0.0.0.0'
        port          = $Port
        dashboard_url = $DashboardUrl
    }
    $json = $config | ConvertTo-Json -Depth 4
    # UTF-8 OHNE BOM schreiben: Windows PowerShell wuerde mit "-Encoding UTF8"
    # ein BOM anhaengen, ueber das andere JSON-Werkzeuge stolpern. Die Bridge
    # selbst liest tolerant mit utf-8-sig.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ConfigPath, $json, $utf8NoBom)
    Write-Ok "Konfiguration geschrieben: $ConfigPath (Port $Port)"
}

function Add-BridgeFirewallRule {
    if (-not (Test-IsAdmin)) {
        Write-Warn "Firewall-Regel uebersprungen (Skript laeuft ohne Adminrechte)."
        Write-Info "Manuell: New-NetFirewallRule -DisplayName `"$FirewallName`" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress 100.64.0.0/10"
        return $false
    }
    try {
        Get-NetFirewallRule -DisplayName $FirewallName -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName $FirewallName -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $Port -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
        Write-Ok "Firewall: TCP $Port ist nur fuer das Tailscale-Netz (100.64.0.0/10) offen"
        return $true
    } catch {
        Write-Warn "Firewall-Regel konnte nicht angelegt werden: $_"
        return $false
    }
}

function Enable-Autostart {
    try {
        $startup = [Environment]::GetFolderPath('Startup')
        if (-not $startup) {
            $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
        }
        $lnk = Join-Path $startup 'Remote Antigravity.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($lnk)
        $shortcut.TargetPath = 'wscript.exe'
        $shortcut.Arguments = '"' + $AutostartVbs + '"'
        $shortcut.WorkingDirectory = $BridgeDir
        $shortcut.WindowStyle = 7
        $shortcut.Description = 'Startet die Antigravity PC Bridge und die Antigravity IDE'
        $shortcut.Save()
        Write-Ok "Autostart angelegt: $lnk"
        return $true
    } catch {
        Write-Warn "Autostart konnte nicht angelegt werden: $_"
        return $false
    }
}

function Start-Bridge {
    $listening = $null
    try {
        $listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    } catch { }
    if ($listening) {
        Write-Info "Auf Port $Port lauscht bereits ein Prozess - Bridge wird nicht erneut gestartet."
        return
    }
    if (-not (Test-Path $HiddenVbs)) {
        Write-Fail "Startskript fehlt: $HiddenVbs"
        return
    }
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $HiddenVbs + '"') -WindowStyle Hidden
    Write-Ok "PC Bridge gestartet (versteckt, Port $Port)"
}

function Wait-BridgeHealthy {
    param([string]$Token, [int]$Port = 8900, [int]$TimeoutSeconds = 60)
    $encoded = [uri]::EscapeDataString($Token)
    $url = "http://127.0.0.1:$Port/health?token=$encoded"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $res = Invoke-RestMethod -Uri $url -TimeoutSec 5
            if ($res.status -eq 'online') { return $res }
        } catch { }
        Start-Sleep -Seconds 2
    }
    return $null
}

function Test-PortOccupied {
    param([int]$P)
    try {
        $listener = Get-NetTCPConnection -LocalPort $P -State Listen -ErrorAction SilentlyContinue
        return [bool]$listener
    } catch {
        return $false
    }
}

function Resolve-BridgePort {
    param([int]$RequestedPort, [string]$Token)

    if (-not (Test-PortOccupied -P $RequestedPort)) {
        return @{ Port = $RequestedPort; Reused = $false }
    }

    # Laeuft dort bereits unsere eigene Bridge? Dann alles unveraendert lassen (idempotent).
    # Achtung: nur uebernehmen, wenn der Dienst sich als Remote Antigravity meldet
    # (aeltere Versionen ohne Kennung werden weiterhin akzeptiert).
    $existing = Wait-BridgeHealthy -Token $Token -Port $RequestedPort -TimeoutSeconds 6
    if ($existing) {
        $serviceId = ''
        if ($existing.PSObject.Properties['service']) { $serviceId = [string]$existing.service }
        if ($serviceId -eq '' -or $serviceId -eq 'remote-antigravity-bridge') {
            Write-Ok "Unsere Bridge laeuft bereits auf Port $RequestedPort"
            return @{ Port = $RequestedPort; Reused = $true }
        }
        Write-Warn "Auf Port $RequestedPort antwortet ein anderer Dienst ('$serviceId')."
    }

    Write-Warn "Port $RequestedPort ist von einem anderen Programm belegt."
    for ($candidate = $RequestedPort + 1; $candidate -le ($RequestedPort + 25); $candidate++) {
        if (-not (Test-PortOccupied -P $candidate)) {
            Write-Info "Verwende automatisch den freien Port $candidate"
            return @{ Port = $candidate; Reused = $false }
        }
    }
    Write-Fail "Kein freier Port im Bereich $RequestedPort bis $($RequestedPort + 25) gefunden."
    Write-Info "Bitte das blockierende Programm beenden oder den Installer mit '-Port <nummer>' starten."
    exit 1
}

# =============================================================================
# Main
# =============================================================================

Write-Host "Remote Antigravity - Setup" -ForegroundColor Magenta
Write-Info "Repository: $RepoRoot"

if (-not (Test-Path $Requirements)) {
    Write-Fail "pc_bridge\requirements.txt nicht gefunden. Bitte das komplette Repository verwenden."
    exit 1
}

# --- 1. Python ---------------------------------------------------------------
Write-Step "1/7 Python"
$pythonExe = Resolve-PythonExe
if (-not $pythonExe) {
    $installed = Install-Python
    if ($installed) { $pythonExe = Resolve-PythonExe }
}
if (-not $pythonExe) {
    Write-Fail "Kein Python 3 gefunden. Setup abgebrochen."
    exit 1
}
Write-Ok "Python: $pythonExe"

# --- 2. Virtuelle Umgebung + Abhaengigkeiten ---------------------------------
Write-Step "2/7 Python-Umgebung"
$venvPython = Join-Path $VenvDir 'Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    Write-Info "Erstelle virtuelle Umgebung in $VenvDir ..."
    try { & $pythonExe -m venv $VenvDir } catch { }
}
if (Test-Path $venvPython) {
    Write-Info "Installiere Abhaengigkeiten in .venv ..."
    & $venvPython -m pip install --upgrade pip --quiet
    & $venvPython -m pip install --quiet -r $Requirements
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Installation der Abhaengigkeiten fehlgeschlagen."
        exit 1
    }
    Write-Ok "Abhaengigkeiten installiert (.venv)"
} else {
    Write-Warn "venv konnte nicht erstellt werden - installiere Abhaengigkeiten direkt."
    & $pythonExe -m pip install --quiet -r $Requirements
    if ($LASTEXITCODE -ne 0) {
        & $pythonExe -m pip install --quiet --user -r $Requirements
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Installation der Abhaengigkeiten fehlgeschlagen."
        exit 1
    }
    Write-Ok "Abhaengigkeiten installiert (pythonw.exe aus dem PATH wird verwendet)"
}

# --- 3. Tailscale ------------------------------------------------------------
Write-Step "3/7 Tailscale"
$tailscaleExe = Resolve-TailscaleExe
$tailscaleIp = ''
if ($SkipTailscale) {
    Write-Info "Tailscale-Schritte uebersprungen (-SkipTailscale)"
    if ($tailscaleExe) { $tailscaleIp = Get-TailscaleIPv4 -Exe $tailscaleExe }
} else {
    if (-not $tailscaleExe) {
        if (-not (Test-IsAdmin)) {
            Write-Warn "Tailscale-Installation braucht Adminrechte."
            Write-Info "Bitte dieses Skript in einer PowerShell als Administrator erneut ausfuehren,"
            Write-Info "oder Tailscale manuell installieren: https://tailscale.com/download/windows"
        } else {
            [void](Install-Tailscale)
        }
        $tailscaleExe = Resolve-TailscaleExe
    }
    if ($tailscaleExe) {
        Write-Ok "Tailscale: $tailscaleExe"
        [void](Connect-Tailscale -Exe $tailscaleExe)
        $tailscaleIp = Get-TailscaleIPv4 -Exe $tailscaleExe
        if ($tailscaleIp) { Write-Ok "Tailscale-IP dieses PCs: $tailscaleIp" }
        else { Write-Warn "Keine Tailscale-IP ermittelbar (noch nicht angemeldet?)" }
    } else {
        Write-Warn "Tailscale nicht verfuegbar - das Dashboard ist dann nur lokal erreichbar."
    }
}

# --- 4. Port und Konfiguration ----------------------------------------------
Write-Step "4/7 Port und Konfiguration"
$token = Get-OrCreateApiToken
$portState = Resolve-BridgePort -RequestedPort $Port -Token $token
$Port = $portState.Port
$FirewallName = "Remote Antigravity Bridge (TCP $Port)"
if ($tailscaleIp) {
    $dashboardUrl = "http://${tailscaleIp}:$Port"
} else {
    $dashboardUrl = "http://localhost:$Port"
}
Write-BridgeConfig -Token $token -DashboardUrl $dashboardUrl

# --- 5. Firewall -------------------------------------------------------------
Write-Step "5/7 Firewall"
[void](Add-BridgeFirewallRule)

# --- 6. Bridge starten -------------------------------------------------------
Write-Step "6/7 PC Bridge starten"
Start-Bridge
Start-Sleep -Seconds 2
$health = Wait-BridgeHealthy -Token $token -Port $Port -TimeoutSeconds 60
if ($health) {
    Write-Ok "Bridge antwortet (IDE laeuft: $($health.ide_running), agentapi: $($health.agentapi_available))"
    if (-not $health.agentapi_available) {
        Write-Warn "agentapi.bat nicht gefunden - bitte pruefen, ob die Antigravity IDE auf diesem PC installiert und einmal gestartet wurde."
    }
} else {
    Write-Warn "Bridge antwortet noch nicht. Log pruefen: $BridgeDir\crash.log"
}

# Selbstkontrolle: hat die Bridge Token und Port unveraendert uebernommen?
if (Test-Path $ConfigPath) {
    try {
        $verify = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if ($verify.api_token -ne $token -or [int]$verify.port -ne $Port) {
            Write-Warn "Die Bridge verwendet eine andere Konfiguration als erwartet!"
            Write-Info "Erwartet: Token $token / Port $Port"
            Write-Info "In $ConfigPath steht: Token $($verify.api_token) / Port $($verify.port)"
            Write-Info "Bitte diese Datei pruefen und das Setup erneut ausfuehren."
        } elseif ($health) {
            Write-Ok "Selbstkontrolle: Token und Port stimmen mit der Bridge ueberein"
        }
    } catch {
        Write-Warn "Konfiguration konnte nicht erneut gelesen werden: $_"
    }
}

# --- 7. Autostart ------------------------------------------------------------
Write-Step "7/7 Autostart"
if ($SkipAutostart) {
    Write-Info "Autostart uebersprungen (-SkipAutostart)"
} else {
    [void](Enable-Autostart)
}

# --- Zusammenfassung ---------------------------------------------------------
$launchUrl = "$dashboardUrl/?token=$token"

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host " FERTIG - Remote Antigravity wurde eingerichtet" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host " Dashboard (dieser PC):    " -NoNewline; Write-Host "$launchUrl" -ForegroundColor Green
if ($tailscaleIp) {
    Write-Host " Vom Handy (unterwegs):    " -NoNewline
    Write-Host "$launchUrl" -ForegroundColor Green
} else {
    Write-Host " Vom Handy (unterwegs):    " -NoNewline
    Write-Host "Tailscale zuerst anmelden, dann 'tailscale ip -4' ausfuehren" -ForegroundColor Yellow
}
Write-Host " API-Token:                " -NoNewline; Write-Host "$token" -ForegroundColor Green
Write-Host ""
Write-Host " Naechste Schritte auf dem Handy:" -ForegroundColor Cyan
Write-Host "   1. Tailscale-App installieren (App Store / Play Store)"
Write-Host "   2. Mit DEM SELBEN Account anmelden wie hier am PC"
Write-Host "   3. Die obige Dashboard-URL im Browser oeffnen"
Write-Host "   4. Optional: 'Zum Home-Bildschirm hinzufuegen' fuer App-Feeling"
Write-Host ""
Write-Host " Neustart: Die Bridge startet automatisch mit Windows (Autostart-Symbol)." -ForegroundColor Gray
Write-Host " Manuell starten: pc_bridge\start_pc_bridge.bat" -ForegroundColor Gray
Write-Host ""



