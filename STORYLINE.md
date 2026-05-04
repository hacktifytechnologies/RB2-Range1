# Storyline — RNG-EXT-01 IT External Zone
## Operation VAJRA SHAKTI | Bharat Urja Nigam Limited (BUNL)

---

## Setting

Bharat Urja Nigam Limited (BUNL) operates India's largest integrated energy utility — thermal plants in Singrauli (MP) and Bokaro (Jharkhand), hydro operations in Pandoh (HP), and a smart grid management platform across 8 states. Their customer-facing and operational IT infrastructure is spread across a public-facing network before the corporate and operational networks.

The External Zone (RNG-EXT-01) represents BUNL's publicly accessible internet-facing systems — the customer self-service portal, billing API, staff authentication, meter data exchange, and static CDN services.

---

## Threat Actor: APT-TARANG

APT-TARANG is a suspected state-sponsored threat group whose TTPs mirror those of RedEcho (attributed infrastructure targeting India's power grid in 2020-21) and Volt Typhoon (critical infrastructure pre-positioning). The group has been observed conducting long-duration reconnaissance against South Asian energy companies before executing targeted intrusions.

The operation codename "TARANG" was discovered embedded in the group's tooling — coincidentally matching BUNL's own smart-grid programme name, suggesting the group had conducted thorough OSINT on BUNL's internal terminology before the operation.

---

## Narrative

The VAJRA SHAKTI exercise begins with APT-TARANG having identified BUNL's public internet footprint through OSINT — customer portal URLs in public app stores, billing API references in developer forums, and static CDN URLs embedded in the BUNL mobile app JavaScript.

**M1 — Customer Portal (XPath Injection):** The attacker discovers the BUNL Customer Self-Service Portal and notes it runs a legacy XML-backend authentication system. A single quote in the login username field triggers an application error — revealing an XPath injection surface. By injecting XPath boolean logic, the attacker bypasses authentication and lands in the admin session, where the system configuration panel reveals the internal billing API key.

**M2 — Billing API (GraphQL Batch Brute Force):** Using the API key, the attacker accesses the GraphQL billing service. Introspection reveals a `staffLogin` mutation with a rate limit. The attacker discovers that GraphQL's native batch request format bypasses the rate limit entirely — 20 password attempts per HTTP request. The weak password `password` on the `padmin` account is cracked. The admin query `systemConfig` returns credentials for the staff authentication portal.

**M3 — Staff Portal (Flask Cookie Forgery):** The staff portal runs Flask with `SECRET_KEY = "letmein"`. After logging in with legitimate M2 credentials to obtain a session cookie, the attacker runs `flask-unsign` against rockyou and cracks the secret in under a second. A forged admin cookie grants access to the administration panel, which displays the Meter Data Exchange API key used by field engineers.

**M4 — Meter API (XXE):** The SOAP-based meter data exchange API processes XML submissions for meter readings. The lxml parser is configured to resolve external entities. The attacker submits a malicious XML payload with a DOCTYPE declaring a SYSTEM entity pointing to the application config file. The config file content is reflected in the API response, revealing database credentials and the corporate zone pivot token.

**M5 — CDN Server (Nginx Traversal):** Running independently and accessible from the internet, the CDN server has a single-character Nginx misconfiguration — a missing trailing slash on an alias directive. The request `/assets../config.py` traverses one directory level out of the assets folder and serves the Python configuration file, which also contains the corporate zone pivot token and CDN management credentials.

---

## Pivot Out

Both M4 (XXE) and M5 (Nginx traversal) provide the same corporate zone pivot token: `vs-corp-7g9h2j4k6n2m`. This token is used to authenticate against BUNL's Corporate Zone (RNG-CORP-01) — specifically the DISHA HR system at M1 of the corporate zone. The token represents an inter-zone service authentication credential used by the IT integration broker.

---

## Real-World Parallels

- **XPath Injection:** Used in the 2007 RSA authentication bypass affecting multiple financial institutions
- **GraphQL Batch Abuse:** Documented in HackerOne reports against Shopify, GitLab (2019-21)
- **Flask Weak Secret:** Common in misconfigured web apps; cracking method documented by PortSwigger
- **XXE in Energy Sector:** ICS/SCADA data exchange protocols frequently use XML — XXE documented in multiple ICS vendor advisories
- **Nginx Alias Traversal:** CVE-2013-2028 family; continues to appear in production deployments
