# Incident Notification Report (INREP)

**Cyber Exercise — Operation VAJRA SHAKTI**
**Version 1.0**

---

**Date:** 2025-11-15
**Time:** [Time of Incident]
**Report ID:** IN-EXT01-M01

---

## 1. Current Situation

**Description:** The BUNL Customer Self-Service Portal (203.x.x.x:8080) has been compromised via a XPath Injection vulnerability. The attack exploited the `username (login form)` parameter. Immediate investigation and containment are required.

**Threat Level:** High

**Areas of Concern:**
- Exploitation of `username (login form)` allowing unauthorised access to privileged functionality
- Potential credential exfiltration enabling lateral movement to connected systems
- Risk of cascading compromise across the BUNL IT External Zone

---

## 2. Threat Intelligence

**Sources:**
- Application access logs: `/var/log/bunl/`
- Systemd journal: `journalctl -u bunl-customer-portal --since today`

**Indicators of Compromise (IOCs):**
- Unexplained admin panel access from unknown IP; no admin login recorded in access.log

**Log Entry Identified:**
```
[Paste relevant log line from access.log here]
e.g. 2025-11-15 09:42:11 WARNING <IOC details from log>
```

---

## 3. Vulnerability Identification

**Vulnerability:** XPath Injection

**Affected Parameter:** `username (login form)`

**Description:** The BUNL Customer Self-Service Portal processes the `username (login form)` without sufficient sanitisation or security controls, allowing an attacker to manipulate the application logic and access privileged data or functionality.

**Patch Status:** Ongoing — code fix required in app.py login() function

---

## 4. Security Operations

**Prevention Steps:**
- Use lxml parameterised XPath (etree.XPath with variables). Add whitelist validation on username: allow only [a-zA-Z0-9._-]+ before query execution
- Implement centralised logging and SIEM alerting for this service
- Add WAF rules to detect and block the attack pattern
- Conduct security code review of all public-facing application endpoints
- Enforce principle of least privilege on all API credentials and sessions

**Immediate Actions:**
1. Block attacker source IP: `ufw insert 1 deny from <ATTACKER_IP>`
2. Rotate any credentials exposed by this compromise
3. Invalidate all active sessions on the affected service
4. Notify the security team and initiate the incident response procedure

---

## 5. Additional Notes

This incident is part of the Operation VAJRA SHAKTI purple team cyber exercise targeting BUNL infrastructure. The exploitation of M01 provides the attacker with credentials or tokens necessary to progress to the next machine in the kill chain. Downstream services must be assessed immediately.

**Connected services at risk:**
- M2 ext-billing-api (API key exposed: gql-key-b2f4a8c3e9d1f7b5)

---

## 6. POC (Screenshots)
[Attach screenshots showing the exploit payload, server response, and log evidence]
