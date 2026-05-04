#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi
apt-get update -qq
apt-get install -y --no-install-recommends python3 python3-pip python3-venv libxml2-dev libxslt1-dev net-tools curl
echo "[*] M4 deps installed."
