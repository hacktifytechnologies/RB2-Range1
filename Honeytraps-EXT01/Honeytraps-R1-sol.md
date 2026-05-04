# Honeytrap Solution Guide — RNG-EXT-01 IT External Zone
## Operation VAJRA SHAKTI | Bharat Urja Nigam Limited (BUNL)
All ancillary services log hits to `/var/log/bunl/ancillary/mX/services.log`

---

## M1 — Customer Portal Ancillary Services

### Port 8443 — Smart Metering Dashboard
**Theme:** SCADA-style operator portal  
**Basic Vuln:** Reflected XSS in the login error message — username input is rendered back unsanitised in `"Authentication failed for operator: {u}"` via `render_template_string`. Payload: `<script>alert(1)</script>` in username field triggers XSS in the error banner.  
**Detection trigger:** Any username containing `<script>` logs `XSS_ATTEMPT` — blue team alert.

### Port 9001 — Bill Payment Gateway
**Theme:** Online electricity bill payment  
**Basic Vuln:** Login credentials (including card data) captured verbatim in service log. SQL injection in `consumer_id` field is logged but the response always returns success — a red herring to waste time. No actual database exists.  
**Detection trigger:** Payment submissions containing `'`, `SELECT`, `UNION` log `SQLI_ATTEMPT`.

### Port 7080 — Asset Management System
**Theme:** BUNL infrastructure asset register  
**Basic Vuln:** IDOR in `/api/assets/<id>` — any integer ID returns asset data with no authentication or ownership check. Also, the `/reports/download?file=` parameter attempts path traversal (blocked by `os.path.basename` sanitisation) but logs the attempt.  
**Detection trigger:** Requests to `/api/assets/` IDs outside normal range log `ASSET_IDOR`.

### Port 4443 — IT Service Desk
**Theme:** Internal employee helpdesk  
**Basic Vuln:** Default credentials (`Bunl@123!`) are displayed on the login page as a "new joiner hint". Also accepts `admin/admin123` and `admin/admin`. Stored XSS in ticket title field is logged (`STORED_XSS_ATTEMPT`) but not rendered back in the sandboxed environment.  
**Detection trigger:** Any login using default creds logs `ITDESK_LOGIN` with matching password.

### Port 6080 — Outage Reporting API
**Theme:** REST API for field outage reporting  
**Basic Vuln:** No authentication on any endpoint. `POST /api/v1/outages/report` accepts arbitrary JSON and logs the payload. All API calls are logged with source IP.  
**Detection trigger:** All requests logged under `OUTAGE_API`.

### Port 2222 — Remote Monitoring Node (SSH banner)
**Theme:** SSH remote access for monitoring node  
**Basic Vuln:** Responds to TCP with a real SSH banner, logs any data sent back. Brute force attempts land here instead of the real SSH port.  
**Detection trigger:** Any TCP connect logs `SSH_PROBE`.

---

## M2 — Billing API Ancillary Services

### Port 8081 — Revenue Analytics Portal
**Theme:** Finance/operations revenue dashboard  
**Basic Vuln:** Default credentials accepted (`revenue123`, `Bunl@Finance1`, `admin`). Login credentials logged. API `/api/v1/revenue/monthly` is open without auth.  
**Detection trigger:** `REV_LOGIN` log entry with any successful or failed attempt.

### Port 9002 — Billing Dispute Portal
**Theme:** Consumer billing dispute submission  
**Basic Vuln:** Description field rendered via `render_template_string` — SSTI possible. Payload `{{ 7*7 }}` in description renders to `49` in the success message. Logged as `SSTI_ATTEMPT`.  
**Detection trigger:** `SSTI_ATTEMPT` log entry — high confidence indicator.

### Port 4001 — GraphQL Schema Explorer
**Theme:** Internal developer GraphQL IDE  
**Basic Vuln:** Exposes full schema reference and proxies queries to the real GraphQL API on port 4000. Reveals field names, argument types, and mutation signatures. Any access logged as `EXPLORER_ACCESS`.  
**Detection trigger:** Access to port 4001 from non-dev IP range.

### Port 7443 — Tariff Management Console
**Theme:** Regulatory tariff schedule management  
**Basic Vuln:** Default credentials (`Tariff@2025`, `admin`, `Bunl@Reg1`). Exposes tariff schedule via unauthenticated `/api/v1/tariffs`.  
**Detection trigger:** `TARIFF_LOGIN` log with password match.

### Port 6090 — Fraud Detection API
**Theme:** Internal fraud scoring REST service  
**Basic Vuln:** All endpoints unauthenticated. `/api/v1/fraud/alerts` exposes internal consumer IDs flagged for fraud. `/api/v1/fraud/score` accepts any `consumer_id` and returns a random score.  
**Detection trigger:** All requests logged under `FRAUD_API`.

### Port 11211 — Memcached TCP
**Theme:** Caching layer  
**Basic Vuln:** Responds to `stats` command with realistic Memcached statistics. Responds to `get bunl:session:admin` with a fake session token value (logged as `MEMCACHED_SESSION_READ`). This is the actual SSRF pivot target in M5 of the next range.  
**Detection trigger:** Any TCP connect logs `MEMCACHED_PROBE`; key-specific gets log `MEMCACHED_CMD`.

---

## M3 — Staff Auth Portal Ancillary Services

### Port 8082 — DISHA HR System
**Theme:** Employee directory (HR module)  
**Basic Vuln:** Search parameter `q` fed directly into `render_template_string` for display — SSTI via search. Payload: `?q={{ config }}` after login exposes Flask config. Logged as `SSTI_ATTEMPT`.  
**Detection trigger:** `SSTI_ATTEMPT` in search query.

### Port 4444 — SSO Discovery / OIDC Endpoint
**Theme:** BUNL identity provider (fake OIDC)  
**Basic Vuln:** JWKS endpoint exposes a fake RSA public key — realistic enough to confuse attackers attempting RS256→HS256 token confusion against it. Token endpoint returns `invalid_client`. All access logged.  
**Detection trigger:** Access to `/.well-known/openid-configuration` or `/oauth/token` logged as `SSO`.

### Port 9003 — Access Review Portal
**Theme:** Quarterly access review tool  
**Basic Vuln:** IDOR on `/reviews/<id>` — any integer ID returns access review data with no session check after initial login. Login accepts any password.  
**Detection trigger:** `ACCESS_IDOR` log entry for IDs outside expected range.

### Port 7444 — Audit Log Viewer
**Theme:** Internal audit log browser  
**Basic Vuln:** File viewer attempts path traversal via `view` param — blocked by `os.path.basename` but attempt is logged. Download endpoint also logs traversal attempts.  
**Detection trigger:** `PATH_TRAVERSAL` log entry.

### Port 8444 — VPN Client Portal
**Theme:** Corporate VPN remote access  
**Basic Vuln:** Default credentials prominently displayed ("new employees: use `Bunl@VPN1`"). Also accepts `vpn123` and `admin`. Credentials logged.  
**Detection trigger:** `VPN_LOGIN` with password match to default creds.

### Port 389 — LDAP TCP Banner
**Theme:** Active Directory LDAP  
**Basic Vuln:** Responds to raw LDAP bind with an `invalidCredentials` response. Logs all probe data including bind DN bytes attempted. Useful for detecting LDAP password spray.  
**Detection trigger:** Any TCP connect logs `LDAP_PROBE`; data received logs `LDAP_DATA`.

---

## M4 — Meter API Ancillary Services

### Port 8083 — Meter Provisioning Console
**Theme:** Field engineer meter provisioning  
**Basic Vuln:** Default credentials (`Meter@Field1`) displayed on login page. Credentials logged.  
**Detection trigger:** `MTR_PROV_LOGIN` with matching password.

### Port 5020 — Modbus TCP
**Theme:** SCADA Modbus protocol gateway  
**Basic Vuln:** Responds to Modbus TCP frames with a valid Read Coils response (FC01). Any protocol probe logged. No authentication in standard Modbus.  
**Detection trigger:** `MODBUS_PROBE` and `MODBUS_DATA` log entries.

### Port 9004 — Meter Data Export API
**Theme:** REST endpoint for meter reading export  
**Basic Vuln:** SQL injection in `meter_id` parameter — `meter_id=MTR' OR '1'='1` returns all rows. `SQLI_ATTEMPT` logged when injection keywords detected.  
**Detection trigger:** `SQLI_ATTEMPT` log entry.

### Port 7445 — Meter Calibration Portal
**Theme:** Meter calibration job management  
**Basic Vuln:** Default credentials (`Calib@Bunl1`, `tech123`, `admin`). Login credentials logged.  
**Detection trigger:** `CALIB_LOGIN` with password match.

### Port 3000 — Metering Data Aggregator Dashboard
**Theme:** Operations aggregation dashboard  
**Basic Vuln:** Completely unauthenticated. All requests logged. Realistic SCADA-style data returned from API.  
**Detection trigger:** Access from non-internal IP.

---

## M5 — CDN Server Ancillary Services

### Port 8085 — Internal File Share
**Theme:** BUNL internal document share  
**Basic Vuln:** File viewer endpoint logs all access. `view` parameter path traversal sandboxed by `os.path.basename`. Files seeded include policy documents referencing IS-2025-009 (the API key rotation policy from M1 admin panel).  
**Detection trigger:** `FILESHARE_VIEW` and `FILESHARE_DL` logged for all access.

### Port 4002 — Static Asset Registry
**Theme:** CDN asset inventory  
**Basic Vuln:** Completely unauthenticated. Exposes full list of CDN asset URLs. All access logged.  
**Detection trigger:** Access from non-CDN IP.

### Port 9005 — WAF Management Console
**Theme:** Network security WAF rule manager  
**Basic Vuln:** Default credentials (`Waf@Bunl2025`, `admin`, `netsec123`). Unauthenticated API on `/api/v1/rules` exposes all WAF rules including patterns being blocked. Login credentials logged.  
**Detection trigger:** `WAF_LOGIN` with password match; `WAF_RULES_API` from unexpected IP.

### Port 7446 — Certificate Management API
**Theme:** Internal TLS certificate inventory  
**Basic Vuln:** Completely unauthenticated. `/api/v1/certificates/export` returns full cert inventory including CA information. Logged as `CERT_EXPORT` with `CRITICAL=CERT_ENUM`.  
**Detection trigger:** `CERT_EXPORT` access logged.

### Port 21 — FTP TCP Banner
**Theme:** File transfer server  
**Basic Vuln:** Responds to `USER`/`PASS` commands. Logs username and password attempted before returning 530 error. Useful for detecting credential stuffing.  
**Detection trigger:** `FTP_AUTH` log with captured credentials.
