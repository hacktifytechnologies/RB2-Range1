#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi

APP_DIR="/opt/bunl/meter-api"
LOG_DIR="/var/log/bunl/meter-api"
SVC_USER="bunl-meter"
SVC_NAME="bunl-meter-api"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  RNG-EXT-01 | M4 — BUNL Meter Data Exchange API"
echo "============================================================"

id "${SVC_USER}" &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin "${SVC_USER}"
mkdir -p "${APP_DIR}" "${LOG_DIR}"
cp -r "${SCRIPT_DIR}/app/"* "${APP_DIR}/"
chown -R "${SVC_USER}:${SVC_USER}" "${APP_DIR}" "${LOG_DIR}"
# config.ini is readable by service user only
chmod 640 "${APP_DIR}/config.ini"

python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --quiet --upgrade pip
"${APP_DIR}/venv/bin/pip" install --quiet -r "${APP_DIR}/requirements.txt"

cat > "/etc/systemd/system/${SVC_NAME}.service" << UNIT
[Unit]
Description=BUNL Meter Data Exchange API
After=network.target
[Service]
Type=simple
User=${SVC_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/gunicorn --bind 0.0.0.0:8000 --workers 2 --timeout 30 app:app
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SVC_NAME}
[Install]
WantedBy=multi-user.target
UNIT

ufw allow 8000/tcp comment "BUNL Meter API" 2>/dev/null || true
systemctl daemon-reload
systemctl enable "${SVC_NAME}" --quiet
systemctl restart "${SVC_NAME}"
sleep 3

PASS=0; FAIL=0
check() { if eval "$2" &>/dev/null; then echo "  [PASS] $1"; ((PASS++)); else echo "  [FAIL] $1"; ((FAIL++)); fi; }
check "Service active" "systemctl is-active --quiet ${SVC_NAME}"
check "Port 8000 listening" "ss -tlnp | grep -q ':8000'"
check "Health endpoint" "curl -sf http://127.0.0.1:8000/api/meter/health | grep -q 'ok'"
check "Auth required" "curl -sf http://127.0.0.1:8000/api/meter/schema | grep -q '401'"
check "Valid key accepted" "curl -sf -H 'X-API-KEY: soap-9f3b2d1e7a8c4f6d' http://127.0.0.1:8000/api/meter/schema | grep -q 'schema'"
check "config.ini restricted" "test \$(stat -c '%a' ${APP_DIR}/config.ini) = '640'"
XXE='<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/hostname">]><MeterDataSubmission><MeterId>&xxe;</MeterId><ReadingValue>100</ReadingValue></MeterDataSubmission>'
check "XXE vulnerable" "curl -sf -X POST http://127.0.0.1:8000/api/meter/submit -H 'X-API-KEY: soap-9f3b2d1e7a8c4f6d' -H 'Content-Type: application/xml' -d '$XXE' | grep -q '<MeterId>'"

echo "  Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && echo "  [OK] M4 setup complete." || echo "  [WARN] Check above."
echo "============================================================"
