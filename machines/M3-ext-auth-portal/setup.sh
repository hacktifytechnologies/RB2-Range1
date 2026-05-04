#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi

APP_DIR="/opt/bunl/auth-portal"
LOG_DIR="/var/log/bunl/auth-portal"
SVC_USER="bunl-auth"
SVC_NAME="bunl-auth-portal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  RNG-EXT-01 | M3 — BUNL Staff Authentication Portal"
echo "============================================================"

id "${SVC_USER}" &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin "${SVC_USER}"
mkdir -p "${APP_DIR}" "${LOG_DIR}"

cp -r "${SCRIPT_DIR}/app/"* "${APP_DIR}/"
chown -R "${SVC_USER}:${SVC_USER}" "${APP_DIR}" "${LOG_DIR}"

python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --quiet --upgrade pip
"${APP_DIR}/venv/bin/pip" install --quiet -r "${APP_DIR}/requirements.txt"

"${APP_DIR}/venv/bin/python3" "${APP_DIR}/init_db.py"
chown "${SVC_USER}:${SVC_USER}" "${APP_DIR}/staff.db"
chmod 640 "${APP_DIR}/staff.db"

cat > "/etc/systemd/system/${SVC_NAME}.service" << UNIT
[Unit]
Description=BUNL Staff Authentication Portal
After=network.target
[Service]
Type=simple
User=${SVC_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 30 app:app
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SVC_NAME}
[Install]
WantedBy=multi-user.target
UNIT

ufw allow 5000/tcp comment "BUNL Auth Portal" 2>/dev/null || true
systemctl daemon-reload
systemctl enable "${SVC_NAME}" --quiet
systemctl restart "${SVC_NAME}"
sleep 3

PASS=0; FAIL=0
check() { if eval "$2" &>/dev/null; then echo "  [PASS] $1"; ((PASS++)); else echo "  [FAIL] $1"; ((FAIL++)); fi; }
check "Service active" "systemctl is-active --quiet ${SVC_NAME}"
check "Port 5000 listening" "ss -tlnp | grep -q ':5000'"
check "Login page loads" "curl -sf http://127.0.0.1:5000/login | grep -q 'BUNL Staff'"
check "Health endpoint" "curl -sf http://127.0.0.1:5000/api/v1/health | grep -q 'ok'"
check "Weak secret in app.py" "grep -q 'letmein' ${APP_DIR}/app.py"
check "Staff DB exists" "test -f ${APP_DIR}/staff.db"
check "Valid login works" "curl -sf -c /tmp/m3_test.txt -X POST http://127.0.0.1:5000/login -d 'username=svcananya&password=BunlStaff%402025%21' -L | grep -q 'Welcome'"

echo "  Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && echo "  [OK] M3 setup complete." || echo "  [WARN] Check above."
echo "============================================================"
