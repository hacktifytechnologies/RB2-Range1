# Network Diagram — RNG-EXT-01 IT External Zone
## Operation VAJRA SHAKTI | 203.x.x.x/24 Public Network

```
[Public Internet / Attacker]
         │
         │ Port 8080 — Customer Self-Service Portal
         │ Port 4000 — Billing GraphQL API
         │ Port 5000 — Staff Authentication Portal
         │ Port 8000 — Meter Data Exchange API
         │ Port  80   — CDN Static File Server
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  RNG-EXT-01 | IT External Zone | 203.x.x.x/24                  │
│                                                                  │
│  M1  203.x.x.x:8080  BUNL Customer Self-Service Portal          │
│       ├── Vuln: XPath Injection (login form)                     │
│       ├── Exposes: Billing API key → M2                          │
│       └── Ancillary: 8443 9001 7080 4443 6080 2222              │
│                                                                  │
│  M2  203.x.x.x:4000  BUNL Billing GraphQL API                   │
│       ├── Vuln: Batch rate limit bypass → brute force            │
│       ├── Exposes: Staff portal credentials → M3                 │
│       └── Ancillary: 8081 9002 4001 7443 6090 11211             │
│                                                                  │
│  M3  203.x.x.x:5000  BUNL Staff Authentication Portal           │
│       ├── Vuln: Flask weak SECRET_KEY → cookie forge             │
│       ├── Exposes: Meter API key → M4                            │
│       └── Ancillary: 8082 4444 9003 7444 8444 389               │
│                                                                  │
│  M4  203.x.x.x:8000  BUNL Meter Data Exchange API               │
│       ├── Vuln: XXE → file:///opt/bunl/meter-api/config.ini      │
│       ├── Exposes: vs-corp-7g9h2j4k6n2m → RNG-CORP-01           │
│       └── Ancillary: 8083 5020 9004 7445 3000                   │
│                                                                  │
│  M5  203.x.x.x:80    BUNL CDN Static File Server (Nginx)         │
│       ├── Vuln: Nginx alias off-by-one → /assets../config.py     │
│       ├── Exposes: vs-corp-7g9h2j4k6n2m → RNG-CORP-01           │
│       └── Ancillary: 8085 4002 9005 7446 21                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
         │
         │ Pivot: vs-corp-7g9h2j4k6n2m
         │ Target: BUNL HR System DISHA — Corporate Zone M1
         ▼
   RNG-CORP-01 (203.x.x.x/24 Corporate Zone)
```

## Kill Chain

```
No credentials (Public)
    ↓ M1: XPath inject → admin session → gql-key-b2f4a8c3e9d1f7b5
    ↓ M2: Batch brute force → padmin:password → svcananya:BunlStaff@2025!
    ↓ M3: Flask-unsign → letmein → forge admin cookie → soap-9f3b2d1e7a8c4f6d
    ↓ M4: XXE → config.ini → vs-corp-7g9h2j4k6n2m
    → RNG-CORP-01 M1 (BUNL DISHA HR System)
```

## Ancillary Service Ports Summary

| Machine | Ports | Services |
|---|---|---|
| M1 | 8443 9001 7080 4443 6080 2222 | SCADA dashboard, Payment GW, Asset mgmt, IT desk, Outage API, SSH banner |
| M2 | 8081 9002 4001 7443 6090 11211 | Revenue analytics, Dispute portal, GQL explorer, Tariff console, Fraud API, Memcached |
| M3 | 8082 4444 9003 7444 8444 389 | DISHA HR, SSO OIDC, Access review, Audit logs, VPN portal, LDAP banner |
| M4 | 8083 5020 9004 7445 3000 | Meter provisioning, Modbus TCP, Data export, Calibration, Aggregator |
| M5 | 8085 4002 9005 7446 21 | File share, Asset registry, WAF mgmt, Cert mgmt, FTP banner |
