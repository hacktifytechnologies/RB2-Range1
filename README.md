# RNG-EXT-01 — IT External Zone
## Operation VAJRA SHAKTI | Bharat Urja Nigam Limited (BUNL)
**Purple Team Cyber Range — 5 Machines | Public Network | 203.x.x.x/24**

---

## Overview
RNG-EXT-01 is the Internet-facing entry zone of Operation VAJRA SHAKTI. It simulates BUNL's public-facing digital infrastructure — customer self-service, billing APIs, staff authentication, meter data exchange, and CDN hosting. The attacker enters from the public internet and exits with a Corporate Zone pivot token.

**Kill Chain:** Public Internet → EXT-01 → RNG-CORP-01

## Machines

| Machine | Port | Challenge | Technique |
|---|---|---|---|
| M1-ext-customer-portal | 8080 | XPath Injection → Auth Bypass | T1190 |
| M2-ext-billing-api | 4000 | GraphQL Batch Brute Force | T1110.003 |
| M3-ext-auth-portal | 5000 | Flask Weak SECRET_KEY → Cookie Forge | T1606.001 |
| M4-ext-meter-api | 8000 | XXE → Config File Read | T1005 |
| M5-ext-cdn-server | 80 | Nginx Alias Path Traversal | T1083 |

## Deployment

```bash
# On each machine VM:
sudo bash deps.sh    # Install OS dependencies
sudo bash setup.sh   # Configure and start the challenge service
sudo bash ../../Honeytraps-EXT01/MX-ext-<name>.sh  # Deploy ancillary services
```

## Pivot Out
Both M4 and M5 reveal `vs-corp-7g9h2j4k6n2m` → RNG-CORP-01 M1 (BUNL DISHA HR System)

## File Structure
```
RNG-EXT-01/
├── README.md / STORYLINE.md / NETWORK_DIAGRAM.md / .gitignore / github_push.sh
├── Honeytraps-EXT01/
│   ├── M1-ext-customer-portal.sh    M2-ext-billing-api.sh
│   ├── M3-ext-auth-portal.sh        M4-ext-meter-api.sh
│   ├── M5-ext-cdn-server.sh         Honeytraps-R1-sol.md
├── TTPs/
│   └── TTP-EXT01-M[1-5].yaml
└── machines/
    └── M[1-5]-ext-*/
        ├── app/ (application source)
        ├── deps.sh / setup.sh
        ├── solve_red.md / solve_blue.md
        ├── SITREP-EXT01-M0X.md / INREP-EXT01-M0X.md
        └── RED-REPORT-EXT01-M0X.md
```
