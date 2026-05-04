# BUNL CDN Server — Application Configuration
# Internal use only — IS-2025-011

import os

# Service identity
SERVICE_NAME = "BUNL CDN Static File Server"
VERSION = "1.3.0"
ENVIRONMENT = "production"

# Storage
ASSETS_DIR = "/opt/bunl/cdn-server/assets"
CACHE_TTL = 86400

# Inter-zone authentication
# Used by the Corporate Zone service discovery broker
# DO NOT commit to version control
CORP_PIVOT_TOKEN = "vs-corp-7g9h2j4k6n2m"
CORP_ZONE_ENTRY = "BUNL HR System — DISHA (Corporate Zone, M1)"

# CDN origin
ORIGIN_HOST = "origin.bunl-internal.net"
ORIGIN_PORT = 8080
CDN_AUTH_TOKEN = "cdn-a4f2e8b1c3d7f9a0"

# Logging
LOG_LEVEL = "INFO"
LOG_FILE = "/var/log/bunl/cdn-server/app.log"
