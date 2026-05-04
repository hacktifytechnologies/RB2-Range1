# SITREP Report (SITREP)

**Cyber Exercise — Operation VAJRA SHAKTI**
**Version 1.0**

---

**Date:** 2025-11-15
**Time:** [Time of Detection]
**Incident ID:** SITREP-EXT01-M03

---

## 1. Incident Overview

**Description:**
- Flask Weak SECRET_KEY — Session Cookie Forgery detected on machine M3-ext-auth-portal (203.x.x.x:5000)
- Service affected: BUNL Staff Authentication Portal
- Attack vector: SECRET_KEY 'letmein' cracked by flask-unsign against rockyou wordlist; admin cookie forged
- Attacker successfully exploited the vulnerability; evidence found in /var/log/bunl/auth-portal/access.log

**Severity Level:** Critical

**Impact:** Admin session forged; Meter Data Exchange API key exposed (soap-9f3b2d1e7a8c4f6d)

**Affected System:** M3-ext-auth-portal — BUNL Staff Authentication Portal (Port 5000)

---

## 2. Incident Details

**Detection Method:**
Review of application logs in /var/log/bunl/auth-portal/access.log reveals unusual request patterns consistent with exploitation. Specific indicators include:

- **IOC:** Admin panel (/admin) accessed from session not matching any successful login in the access log

To detect:
```bash
grep -i "Admin" /var/log/bunl/auth-portal/access.log | tail -50
```

**Initial Detection Time:** [Timestamp when incident was first detected]

**Attack Vector:** Flask Weak SECRET_KEY — Session Cookie Forgery

---

## 3. Response Actions Taken

**Containment:**
- Isolate M3-ext-auth-portal from the external network segment
- Block attacker source IP at perimeter firewall using `ufw insert 1 deny from <IP>`
- Revoke any exposed credentials or API keys immediately
- Invalidate all active sessions on the affected service

**Eradication:**
- Patch the identified vulnerability (see Mitigation Recommendations)
- Rotate all credentials exposed during this incident
- Review logs for additional compromise indicators on connected systems

**Recovery:**
- Redeploy service from clean configuration after patching
- Re-enable external access only after patch verification
- Monitor access logs for 24 hours post-recovery for recurrence

**Lessons Learned:**
- Input validation must be enforced server-side for all user-supplied data
- Secrets and credentials must never be hardcoded or stored in plaintext config
- Rate limiting must be implemented at the operation level, not HTTP request level
- External entity resolution must be explicitly disabled in all XML parsers

---

## 4. Technical Analysis

**Evidence:**
- Access logs at /var/log/bunl/auth-portal/access.log
- Application configuration files (where applicable)
- Network connection records

**Indicators of Compromise (IOCs):**
- Admin panel (/admin) accessed from session not matching any successful login in the access log
- Unusual source IP with high request volume
- Unexpected admin panel or privileged API access

**Tactics, Techniques, and Procedures (TTPs):**

**MITRE ATT&CK: T1606.001**
Description: Flask Weak SECRET_KEY — Session Cookie Forgery used to gain unauthorised access to BUNL infrastructure services. The attacker exploited an application-layer vulnerability to access privileged configuration data and obtain credentials for lateral movement to the next zone.

**Mitigation Recommendations:**
- Apply secure coding fix for Flask Weak SECRET_KEY — Session Cookie Forgery
- Implement input validation and output encoding across all services
- Enable structured logging and SIEM alerting for anomalous patterns
- Conduct security code review of all public-facing applications
- Implement WAF rules to block common exploit signatures

---

## 5. Communication

**Internal Notification:**
- Security Team: Immediate notification to initiate incident response
- IT Operations: Coordinate containment and service restoration
- Executive Management: Timely notification with impact summary
- Legal & Compliance: Notification if data breach involves consumer PII

**External Notification:**
- CERT-In: Notification per mandatory reporting requirements if consumer data compromised
- Affected downstream services: Notify teams managing credentials exposed in this incident

**Updates:**
- Frequency: Every 2 hours until containment confirmed
- Channel: Incident response Slack channel + encrypted email to CISO (Priya Nair)

---

## 6. Additional Notes

This incident is part of the Operation VAJRA SHAKTI purple team exercise. The exploitation chain continues through connected systems — all downstream services must be assessed for impact.

---

## 7. Submission

**Prepared By:** [Blue Team Analyst Name]

## 8. POC (Screenshots)
[Attach screenshots of log evidence, attacker IP, and payload]
