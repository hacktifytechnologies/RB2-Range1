#!/usr/bin/env bash
# ============================================================
# RNG-EXT-01 | M1-ext-customer-portal | deps.sh
# Installs OS-level dependencies for the BUNL Customer
# Self-Service Portal. Run once before setup.sh.
# ============================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi

echo "[*] Updating package index..."
apt-get update -qq

echo "[*] Installing runtime dependencies..."
apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    libxml2-dev libxslt1-dev \
    net-tools curl wget ufw

echo "[*] Verifying Python version..."
python3 --version

echo "[*] M1 deps installed successfully."
