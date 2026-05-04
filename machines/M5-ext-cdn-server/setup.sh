#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi

APP_DIR="/opt/bunl/cdn-server"
LOG_DIR="/var/log/bunl/cdn-server"
SVC_NAME="nginx"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  RNG-EXT-01 | M5 — BUNL CDN Static File Server"
echo "============================================================"

mkdir -p "${APP_DIR}/assets" "${APP_DIR}/webroot" "${LOG_DIR}"

cp "${SCRIPT_DIR}/app/config.py" "${APP_DIR}/config.py"
cp "${SCRIPT_DIR}/app/webroot/index.html" "${APP_DIR}/webroot/index.html"
cp "${SCRIPT_DIR}/app/assets/"* "${APP_DIR}/assets/" 2>/dev/null || true

# Permissions: config.py readable only by root, simulating a misconfigured deployment
chown root:www-data "${APP_DIR}/config.py"
chmod 640 "${APP_DIR}/config.py"
chown -R www-data:www-data "${APP_DIR}/webroot" "${APP_DIR}/assets" "${LOG_DIR}"

# Deploy vulnerable Nginx config
cp "${SCRIPT_DIR}/app/nginx.conf" /etc/nginx/nginx.conf
nginx -t
systemctl enable nginx --quiet
systemctl restart nginx
sleep 2

ufw allow 80/tcp comment "BUNL CDN" 2>/dev/null || true

PASS=0; FAIL=0
check() { if eval "$2" &>/dev/null; then echo "  [PASS] $1"; ((PASS++)); else echo "  [FAIL] $1"; ((FAIL++)); fi; }
check "Nginx active" "systemctl is-active --quiet nginx"
check "Port 80 listening" "ss -tlnp | grep -q ':80'"
check "Landing page serves" "curl -sf http://127.0.0.1/ | grep -q 'BUNL CDN'"
check "Health endpoint" "curl -sf http://127.0.0.1/cdn-api/health | grep -q 'ok'"
check "Assets path works" "curl -sf http://127.0.0.1/assets/bunl-core.css | grep -q 'BUNL'"
check "Alias traversal works" "curl -sf 'http://127.0.0.1/assets../config.py' | grep -q 'CORP_PIVOT_TOKEN'"
check "config.py has pivot token" "grep -q 'vs-corp-7g9h2j4k6n2m' ${APP_DIR}/config.py"

echo "  Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && echo "  [OK] M5 setup complete." || echo "  [WARN] Check above."
echo "============================================================"
