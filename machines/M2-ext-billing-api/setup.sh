#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi

APP_DIR="/opt/bunl/billing-api"
LOG_DIR="/var/log/bunl/billing-api"
SVC_USER="bunl-gql"
SVC_NAME="bunl-billing-api"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  RNG-EXT-01 | M2 — BUNL Billing GraphQL API"
echo "============================================================"

echo "[1/7] Creating service user and directories..."
id "${SVC_USER}" &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin "${SVC_USER}"
mkdir -p "${APP_DIR}" "${LOG_DIR}"

echo "[2/7] Deploying application files..."
cp -r "${SCRIPT_DIR}/app/"* "${APP_DIR}/"
chown -R "${SVC_USER}:${SVC_USER}" "${APP_DIR}" "${LOG_DIR}"
chmod 640 "${APP_DIR}/init_db.py"

echo "[3/7] Setting up Python venv..."
python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --quiet --upgrade pip
"${APP_DIR}/venv/bin/pip" install --quiet -r "${APP_DIR}/requirements.txt"

echo "[4/7] Initialising database..."
"${APP_DIR}/venv/bin/python3" "${APP_DIR}/init_db.py"
chown "${SVC_USER}:${SVC_USER}" "${APP_DIR}/billing.db"
chmod 640 "${APP_DIR}/billing.db"

echo "[5/7] Creating systemd service..."
cat > "/etc/systemd/system/${SVC_NAME}.service" << UNIT
[Unit]
Description=BUNL Billing GraphQL API
After=network.target

[Service]
Type=simple
User=${SVC_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/gunicorn --bind 0.0.0.0:4000 --workers 2 --timeout 30 app:app
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SVC_NAME}

[Install]
WantedBy=multi-user.target
UNIT

echo "[6/7] Starting service..."
systemctl daemon-reload
systemctl enable "${SVC_NAME}" --quiet
systemctl restart "${SVC_NAME}"
sleep 3

echo "[7/7] Validation..."
PASS=0; FAIL=0
check() { local d="$1"; local c="$2"; if eval "$c" &>/dev/null; then echo "  [PASS] $d"; ((PASS++)); else echo "  [FAIL] $d"; ((FAIL++)); fi; }

check "Service active" "systemctl is-active --quiet ${SVC_NAME}"
check "Port 4000 listening" "ss -tlnp | grep -q ':4000'"
check "Health endpoint" "curl -sf http://127.0.0.1:4000/api/v1/health | grep -q 'ok'"
check "GraphQL GET responds" "curl -sf http://127.0.0.1:4000/graphql | grep -q 'BUNL'"
check "Introspection works" "curl -sf -X POST http://127.0.0.1:4000/graphql -H 'Content-Type: application/json' -d '{\"query\":\"{__schema{queryType{name}}}\"}' | grep -q 'queryType'"
check "Batch array accepted" "curl -sf -X POST http://127.0.0.1:4000/graphql -H 'Content-Type: application/json' -d '[{\"query\":\"{__typename}\"}]' | grep -q 'Query'"

echo ""
echo "  Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && echo "  [OK] M2 setup complete." || echo "  [WARN] Some checks failed."
echo "============================================================"
