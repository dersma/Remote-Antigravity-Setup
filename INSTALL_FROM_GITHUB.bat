@echo off
rem ===========================================================================
rem  Remote Antigravity - Ein-Datei-Installer
rem
rem  Einfach diese Datei doppelklicken. Sie laedt das aktuelle Release von
rem  GitHub, entpackt es nach %USERPROFILE%\Projects und startet dort den
rem  gefuehrten Installer (INSTALL.bat), der alles einrichtet:
rem  Python-Umgebung, Tailscale, Firewall-Regel, Autostart und QR-Code.
rem
rem  Testmodus (ohne Installation):
rem    INSTALL_FROM_GITHUB.bat <zip-url-oder-pfad> --extract-only
rem ===========================================================================
setlocal EnableExtensions
title Remote Antigravity - Installer

set "ZIPURL=https://github.com/dersma/Remote-Antigravity-Setup/releases/latest/download/Remote-Antigravity.zip"
set "ZIPFALLBACK=https://github.com/dersma/Remote-Antigravity-Setup/releases/download/v1.0.0/Remote-Antigravity.zip"
set "EXTRACTONLY=0"
if not "%~1"=="" set "ZIPURL=%~1"
if /I "%~2"=="--extract-only" set "EXTRACTONLY=1"

set "TARGETDIR=%USERPROFILE%\Projects"
set "APPDIR=%TARGETDIR%\Remote-Antigravity"
set "ZIPFILE=%TEMP%\Remote-Antigravity-release.zip"

echo.
echo ===============================================================
echo   Remote Antigravity - Installation
echo ===============================================================
echo.
echo   Ziel : %APPDIR%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $zip=$env:ZIPFILE; $target=$env:TARGETDIR; $app=$env:APPDIR; $urls=@($env:ZIPURL); if ($env:ZIPFALLBACK -and $env:ZIPFALLBACK -ne $env:ZIPURL) { $urls += $env:ZIPFALLBACK }; $ok=$false; foreach ($u in $urls) { Write-Host '  [..]  Lade Paket herunter ...' $u; try { Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing; $ok=$true; break } catch { Write-Host '  [!]   Nicht erreichbar, naechste Quelle ...' -ForegroundColor Yellow } }; if (-not $ok) { Write-Host '  [x]   Download fehlgeschlagen.' -ForegroundColor Red; Write-Host '        Bitte die ZIP-Datei manuell aus dem GitHub-Release herunterladen und' -ForegroundColor Yellow; Write-Host '        im entpackten Ordner die Datei INSTALL.bat doppelklicken.' -ForegroundColor Yellow; exit 1 }; Write-Host '  [ok]  Download fertig'; New-Item -ItemType Directory -Force -Path $target | Out-Null; Write-Host '  [..]  Entpacke ...'; Expand-Archive -Path $zip -DestinationPath $target -Force; Write-Host '  [ok]  Entpackt'; Remove-Item $zip -Force -ErrorAction SilentlyContinue; if (-not (Test-Path $app)) { Write-Host '  [x]   Ordner nicht gefunden:' $app -ForegroundColor Red; exit 1 }; Write-Host '  [ok]  Bereit:' $app"

if errorlevel 1 (
    echo.
    echo Die Installation konnte nicht vorbereitet werden.
    pause
    exit /b 1
)

if "%EXTRACTONLY%"=="1" (
    echo.
    echo Testmodus: nur entpackt, INSTALL.bat wurde nicht gestartet.
    pause
    exit /b 0
)

echo.
echo   [..]  Starte jetzt die Einrichtung in einem neuen Fenster ...
echo.
start "" "%APPDIR%\INSTALL.bat"
exit /b 0
