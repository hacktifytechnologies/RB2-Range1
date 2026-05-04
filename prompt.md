# Context Prompt — RNG-EXT-01 Complete
## For use when briefing another Claude to build RNG-CORP-01

---

## Operation Overview
**Name:** VAJRA SHAKTI  
**Theme:** Indian Energy Sector — Bharat Urja Nigam Limited (BUNL)  
**Threat Actor:** APT-TARANG (mirrors RedEcho/Volt Typhoon TTPs)  
**Total Ranges:** 4 (EXT-01 → CORP-01 → OPS-01 → CLD-01)

---

## RNG-EXT-01 — COMPLETED

**Zone:** IT External Zone | **Network:** 203.x.x.x/24 (Public)

**Machines built:**
- M1: BUNL Customer Self-Service Portal — XPath Injection → Auth Bypass (T1190)
- M2: BUNL Billing GraphQL API — Batch Rate Limit Bypass → Brute Force (T1110.003)
- M3: BUNL Staff Auth Portal — Flask Weak SECRET_KEY → Cookie Forge (T1606.001)
- M4: BUNL Meter Data Exchange API — XXE → Config File Read (T1005)
- M5: BUNL CDN Server — Nginx Alias Path Traversal (T1083)

**Exit credential from EXT-01:**
- Token: `vs-corp-7g9h2j4k6n2m`
- Description: "Corporate Zone M1 — BUNL HR System (DISHA)"
- Present in: M4 config.ini (via XXE) AND M5 config.py (via Nginx traversal)

---

## RNG-CORP-01 — TO BE BUILT

**Zone:** Corporate Zone | **Network:** 203.x.x.x/24 (separate /24 in same public range)  
**Entry point:** `vs-corp-7g9h2j4k6n2m` token → BUNL DISHA HR System (M1)

**Agreed challenges (approved pitch):**
- M1: Weak HS256 JWT Secret → Token Forgery (DISHA HR System) — T1606
- M2: Path Traversal in Energy Report Download API — T1083
- M3: LDAP Injection in Employee Directory Search — T1087
- M4: Sudo + Compiled PyInstaller Binary → Python Module Path Hijack (non-linpeas privesc) — T1574
- M5: SSRF via Gopher Protocol → Memcached → Admin Session Token → OPS-01 pivot — T1055

**Exit to OPS-01:** OPS DMZ session token or credential obtained from Memcached via Gopher SSRF on M5

**IMPORTANT DESIGN NOTES:**
1. The `vs-corp-7g9h2j4k6n2m` token must be the authentication mechanism for M1 DISHA — how it works is up to you (e.g. it could be an API key header, a query parameter for inter-zone service access, or a pre-shared token used in a "service account" login flow)
2. M4 privesc: The PyInstaller binary is sudo-allowed. It imports `bunl_metrics` from a writable directory. `strace` or reading the binary source reveals the path. linpeas shows the sudo rule but NOT the path hijack inside the binary
3. M5 Gopher SSRF: The internal Memcached is at 127.0.0.1:11211. Use `gopher://127.0.0.1:11211/_get%20corp:session:admin%0d%0a` format. The session key value should be the pivot token/credential for OPS-01
4. All web portals must be realistic BUNL corporate-themed (same style as EXT-01)
5. Each machine needs: deps.sh, setup.sh, app/ dir, solve_red.md, solve_blue.md, SITREP, INREP, RED-REPORT
6. Honeytraps: 5-6 unique per machine, themed to BUNL corporate IT (ERP, HR, reporting, directory, etc.)
7. TTPs: Use exact format from reference screenshot — description: >, inline command, sub_technique: "None" if N/A

---

## BUNL Named Characters (use consistently)
- CEO: Rajiv Subramaniam
- CISO: Priya Nair
- Plant Head (Singrauli): Arun Tiwari
- IT Operations Manager: Sonal Vaidya-Cananya (username: svcananya)
- Operations Manager: Rajesh Kumar Tiwari (username: rktiwari)
- Portal Admin: padmin
- CFO: Sunita Rao
- HR Manager: Kiran Joshi

## Internal Programme Names
- DISHA — HR System
- TARANG — Smart Grid Programme
- AGNI — Plant Operations System
- IS-2025-009 — API Key Rotation Policy document reference

## Tech Stack Constraints
- Ubuntu 22.04 LTS
- Python 3 / Flask / Gunicorn (no Node, no Java)
- SQLite for all databases
- All services run as dedicated system users
- Systemd service units for all challenge services

## File Structure (same as EXT-01)
```
RNG-CORP-01/
├── README.md, STORYLINE.md, NETWORK_DIAGRAM.md, .gitignore, github_push.sh, prompt.md
├── Honeytraps-CORP01/
│   ├── M[1-5]-corp-*.sh (ancillary services)
│   └── Honeytraps-R2-sol.md
├── TTPs/
│   └── TTP-CORP01-M[1-5].yaml
└── machines/
    └── M[1-5]-corp-*/
        ├── app/ (application source)
        ├── deps.sh, setup.sh
        ├── solve_red.md, solve_blue.md
        ├── SITREP-CORP01-M0X.md, INREP-CORP01-M0X.md
        └── RED-REPORT-CORP01-M0X.md
```
