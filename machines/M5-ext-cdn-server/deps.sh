#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi
apt-get update -qq
apt-get install -y --no-install-recommends nginx net-tools curl
echo "[*] M5 deps installed."
