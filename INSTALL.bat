@echo off
rem ===========================================================================
rem  Remote Antigravity - Ein-Klick-Installer
rem
rem  Einfach diese Datei doppelklicken. Der Installer richtet alles automatisch
rem  ein: Python-Umgebung, Tailscale, Firewall-Regel, Autostart und den
rem  QR-Code fuer das Handy.
rem
rem  Optional koennen Argumente uebergeben werden, z. B.:
rem    INSTALL.bat -Port 8900
rem    INSTALL.bat -NoElevate
rem ===========================================================================
title Remote Antigravity - Installer
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install_remote_antigravity.ps1" %*

if errorlevel 1 (
    echo.
    echo Der Installer wurde mit einem Fehler beendet.
    pause
)
exit /b 0
