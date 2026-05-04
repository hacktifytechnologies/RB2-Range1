# Incident Notification Report (INREP)

**Cyber Exercise — Operation VAJRA SHAKTI**
**Version 1.0**

---

**Date:** 2025-11-15
**Time:** [Time of Incident]
**Report ID:** IN-EXT01-M03

---

## 1. Current Situation

**Description:** The BUNL Staff Authentication Portal (203.x.x.x:5000) has been compromised via a Flask Weak SECRET_KEY — Session Cookie Forgery vulnerability. The attack exploited the `Flask session cookie (role field)` parameter. Immediate investigation and containment are required.

**Threat Level:** High

**Areas of Concern:**
- Exploitation of `Flask session cookie (role field)` allowing unauthorised access to privileged functionality
- Potential credential exfiltration enabling lateral movement to connected systems
- Risk of cascading compromise across the BUNL IT External Zone

---

## 2. Threat Intelligence

**Sources:**
- Application access logs: `/var/log/bunl/`
- Systemd journal: `journalctl -u bunl-auth-portal --since today`

**Indicators of Compromise (IOCs):**
- Admin panel accessed but no admin login in access.log; forged session cookie presented with role=admin

**Log Entry Identified:**
```
[Paste relevant log line from access.log here]
e.g. 2025-11-15 09:42:11 WARNING <IOC details from log>
```

---

## 3. Vulnerability Identification

**Vulnerability:** Flask Weak SECRET_KEY — Session Cookie Forgery

**Affected Parameter:** `Flask session cookie (role field)`

**Description:** The BUNL Staff Authentication Portal processes the `Flask session cookie (role field)` without sufficient sanitisation or security controls, allowing an attacker to manipulate the application logic and access privileged data or functionality.

**Patch Status:** Ongoing — config change + service restart required

---

## 4. Security Operations

**Prevention Steps:**
- Generate cryptographically random SECRET_KEY using secrets.token_hex(32). Store in environment variable. Rotate immediately
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

This incident is part of the Operation VAJRA SHAKTI purple team cyber exercise targeting BUNL infrastructure. The exploitation of M03 provides the attacker with credentials or tokens necessary to progress to the next machine in the kill chain. Downstream services must be assessed immediately.

**Connected services at risk:**
- M4 ext-meter-api (API key exposed: soap-9f3b2d1e7a8c4f6d)

---

## 6. POC (Screenshots)
[Attach screenshots showing the exploit payload, server response, and log evidence]
