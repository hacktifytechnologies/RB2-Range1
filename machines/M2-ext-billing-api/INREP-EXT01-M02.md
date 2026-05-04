# Incident Notification Report (INREP)

**Cyber Exercise — Operation VAJRA SHAKTI**
**Version 1.0**

---

**Date:** 2025-11-15
**Time:** [Time of Incident]
**Report ID:** IN-EXT01-M02

---

## 1. Current Situation

**Description:** The BUNL Billing GraphQL API (203.x.x.x:4000) has been compromised via a GraphQL Batch Rate Limit Bypass → Credential Brute Force vulnerability. The attack exploited the `POST /graphql body (batch array)` parameter. Immediate investigation and containment are required.

**Threat Level:** High

**Areas of Concern:**
- Exploitation of `POST /graphql body (batch array)` allowing unauthorised access to privileged functionality
- Potential credential exfiltration enabling lateral movement to connected systems
- Risk of cascading compromise across the BUNL IT External Zone

---

## 2. Threat Intelligence

**Sources:**
- Application access logs: `/var/log/bunl/`
- Systemd journal: `journalctl -u bunl-billing-api --since today`

**Indicators of Compromise (IOCs):**
- High volume of POST /graphql requests from single IP; all with staffLogin mutation; single IP sending arrays of 20+ operations

**Log Entry Identified:**
```
[Paste relevant log line from access.log here]
e.g. 2025-11-15 09:42:11 WARNING <IOC details from log>
```

---

## 3. Vulnerability Identification

**Vulnerability:** GraphQL Batch Rate Limit Bypass → Credential Brute Force

**Affected Parameter:** `POST /graphql body (batch array)`

**Description:** The BUNL Billing GraphQL API processes the `POST /graphql body (batch array)` without sufficient sanitisation or security controls, allowing an attacker to manipulate the application logic and access privileged data or functionality.

**Patch Status:** Ongoing — middleware fix required in Flask GraphQL endpoint

---

## 4. Security Operations

**Prevention Steps:**
- Count total operations across batch array. Apply per-IP limit to sum of all operations in a request. Implement exponential backoff after failures
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

This incident is part of the Operation VAJRA SHAKTI purple team cyber exercise targeting BUNL infrastructure. The exploitation of M02 provides the attacker with credentials or tokens necessary to progress to the next machine in the kill chain. Downstream services must be assessed immediately.

**Connected services at risk:**
- M3 ext-auth-portal (credentials exposed: svcananya:BunlStaff@2025!)

---

## 6. POC (Screenshots)
[Attach screenshots showing the exploit payload, server response, and log evidence]
