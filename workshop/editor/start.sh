#!/usr/bin/env bash
# Startet den Workshop-Editor (oder startet ihn neu). Braucht kein root.
# Aufruf aus beliebigem Ordner: /var/www/Inklite/workshop/editor/start.sh
#
# Läuft immer als Nutzer brat, damit Regelsätze und Läufe brat gehören. Als root aufgerufen,
# gibt das Skript an brat ab, sonst entstünden Dateien, die brats Sitzungen nicht ändern dürfen.
set -euo pipefail
if [ "$(id -u)" -eq 0 ]; then
	exec runuser -u brat -- "$0" "$@"
fi
cd "$(dirname "$0")/../.."
PORT=8741

if pm2 describe inklite-workshop >/dev/null 2>&1; then
	pm2 restart inklite-workshop >/dev/null
else
	pm2 start workshop/editor/server.py --name inklite-workshop --interpreter python3 --cwd "$PWD" -- --port "$PORT" >/dev/null
fi
pm2 save >/dev/null
sleep 1

python3 - "$PORT" <<'EOF'
import json, sys
cfg = json.load(open("workshop/editor/config.local.json"))
port = sys.argv[1]
print(f"Editor läuft auf 127.0.0.1:{port}  (Benutzer {cfg['user']}, Passwort {cfg['password']})")
print()
print("Ohne root erreichbar per SSH-Tunnel, auf deinem Rechner (PowerShell):")
print(f"  ssh -i $env:USERPROFILE\\.ssh\\id_ed25519 -N -L {port}:127.0.0.1:{port} root@5.75.161.48")
print(f"  dann im Browser: http://localhost:{port}/")
print()
print("Öffentlich (auch Handy), sobald nginx einmal neu geladen wurde:")
print("  https://5-75-161-48.sslip.io/inklite-workshop/")
EOF
