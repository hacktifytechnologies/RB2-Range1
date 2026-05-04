#!/usr/bin/env bash
# ============================================================
# RNG-EXT-01 | M1-ext-customer-portal | setup.sh
# Deploys the BUNL Customer Self-Service Portal
# ============================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi

APP_DIR="/opt/bunl/customer-portal"
LOG_DIR="/var/log/bunl/customer-portal"
SVC_USER="bunl-csp"
SVC_NAME="bunl-customer-portal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  RNG-EXT-01 | M1 — BUNL Customer Self-Service Portal"
echo "  Operation VAJRA SHAKTI"
echo "============================================================"

# ── User & directories ────────────────────────────────────────
echo "[1/7] Creating service user and directories..."
id "${SVC_USER}" &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin "${SVC_USER}"
mkdir -p "${APP_DIR}" "${LOG_DIR}"

# ── Copy application ──────────────────────────────────────────
echo "[2/7] Deploying application files..."
cp -r "${SCRIPT_DIR}/app/"* "${APP_DIR}/"
chown -R "${SVC_USER}:${SVC_USER}" "${APP_DIR}" "${LOG_DIR}"
chmod 640 "${APP_DIR}/users.xml"
chmod 644 "${APP_DIR}/app.py"

# ── Python virtual environment ────────────────────────────────
echo "[3/7] Setting up Python virtual environment..."
python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --quiet --upgrade pip
"${APP_DIR}/venv/bin/pip" install --quiet -r "${APP_DIR}/requirements.txt"

# ── Systemd service ───────────────────────────────────────────
echo "[4/7] Creating systemd service..."
cat > "/etc/systemd/system/${SVC_NAME}.service" << UNIT
[Unit]
Description=BUNL Customer Self-Service Portal
After=network.target

[Service]
Type=simple
User=${SVC_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/gunicorn --bind 0.0.0.0:8080 --workers 2 --timeout 30 app:app
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SVC_NAME}
Environment="APP_SECRET=bunl-csp-2025-k9m3"

[Install]
WantedBy=multi-user.target
UNIT

# ── Firewall ──────────────────────────────────────────────────
echo "[5/7] Configuring firewall..."
ufw allow 8080/tcp comment "BUNL Customer Portal" 2>/dev/null || true

# ── Enable & start ────────────────────────────────────────────
echo "[6/7] Starting service..."
systemctl daemon-reload
systemctl enable "${SVC_NAME}" --quiet
systemctl restart "${SVC_NAME}"
sleep 3

# ── Validation ────────────────────────────────────────────────
echo "[7/7] Running validation checks..."
PASS=0; FAIL=0

check() {
    local desc="$1"; local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo "  [PASS] ${desc}"; ((PASS++))
    else
        echo "  [FAIL] ${desc}"; ((FAIL++))
    fi
}

check "Service is active" "systemctl is-active --quiet ${SVC_NAME}"
check "Port 8080 is listening" "ss -tlnp | grep -q ':8080'"
check "Health endpoint responds" "curl -sf http://127.0.0.1:8080/api/v1/health"
check "Login page returns 200" "curl -sf http://127.0.0.1:8080/login | grep -q 'Bharat Urja Nigam'"
check "users.xml exists and restricted" "test -f ${APP_DIR}/users.xml && ! test -r ${APP_DIR}/users.xml -a \$(stat -c '%a' ${APP_DIR}/users.xml) = '644'"
check "XPath vuln present" "curl -sf -X POST http://127.0.0.1:8080/login -d 'username=%27+or+%271%27%3D%271&password=x' | grep -q 'Dashboard\|Admin'"

echo ""
echo "  Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && echo "  [OK] M1 setup complete." || echo "  [WARN] Some checks failed — review above."
echo "============================================================"
