# 🔒 Tailscale Setup Guide (Synology NAS + PC + iPhone)

> 💡 **Automatische Variante:** Für einen frischen Windows-PC (ohne NAS, ohne Docker, ohne eigene
> Domain) erledigt `scripts/setup_remote_antigravity.ps1` die Schritte 1 und 3 vollständig
> automatisch – inklusive Tailscale-Installation, Browser-Login und Firewall-Regel.
> Siehe [`SETUP_FRIEND.md`](SETUP_FRIEND.md) und [`AGENTS.md`](AGENTS.md).
> Die Anleitung hier ist die **manuelle** Variante (und gilt weiterhin für NAS + Docker).

Tailscale ermöglicht dir eine **100 % kostenlose**, Ende-zu-Ende verschlüsselte Verbindung von deinem iPhone (Handynetz) zu deiner Synology NAS und deinem Windows-PC – **ohne Portfreigaben** im Router!

---

## Schritt 1: Kostenlosen Tailscale Account erstellen
1. Gehe auf [tailscale.com](https://tailscale.com/) und registriere einen kostenlosen Account (Personal Plan).

---

## Schritt 2: Tailscale auf der Synology NAS installieren
**Option A (Über das Synology Paketzentrum - Empfohlen):**
1. Öffne das **Synology DSM** im Browser.
2. Gehe in das **Paketzentrum**.
3. Suche nach **Tailscale** und klicke auf **Installieren**.
4. Nach der Installation öffne die Tailscale App auf der NAS und klicke auf **Login**.
5. Bestätige die Verknüpfung mit deinem Tailscale Account.

---

## Schritt 3: Tailscale auf dem Windows PC installieren
1. Lade Tailscale für Windows von [tailscale.com/download/windows](https://tailscale.com/download/windows) herunter.
2. Installiere und starte Tailscale.
3. Klicke im Infobereich (unten rechts neben der Uhr) auf das Tailscale-Symbol und melde dich mit demselben Account an.
4. **Notiere dir die Tailscale IP deines PCs** (z. B. `100.110.120.130`).

---

## Schritt 4: Tailscale App auf dem iPhone installieren
1. Öffne den **App Store** auf dem iPhone.
2. Suche nach **Tailscale** und installiere die App.
3. Melde dich mit demselben Account an.
4. Aktiviere den VPN-Schalter in der App.

---

## 🎉 Test der Verbindung über das Handynetz
1. Schalte das WLAN auf deinem iPhone aus (nur Mobiles Netz / LTE / 5G).
2. Öffne die Tailscale-App auf dem iPhone und vergewissere dich, dass der VPN-Status auf **Connected** steht.
3. Öffne Safari und gib die Tailscale-IP deiner Synology NAS mit Port `8899` ein (z. B. `http://100.x.y.z:8899`).
4. Du gelangst sofort auf das **Remote Antigravity Dashboard**!
