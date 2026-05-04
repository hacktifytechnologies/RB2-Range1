# Incident Notification Report (INREP)

**Cyber Exercise — Operation VAJRA SHAKTI**
**Version 1.0**

---

**Date:** 2025-11-15
**Time:** [Time of Incident]
**Report ID:** IN-EXT01-M05

---

## 1. Current Situation

**Description:** The BUNL CDN Static File Server (Nginx) (203.x.x.x:80) has been compromised via a Nginx Alias Path Traversal (Off-By-One) vulnerability. The attack exploited the `GET /assets../config.py (Nginx alias off-by-one)` parameter. Immediate investigation and containment are required.

**Threat Level:** High

**Areas of Concern:**
- Exploitation of `GET /assets../config.py (Nginx alias off-by-one)` allowing unauthorised access to privileged functionality
- Potential credential exfiltration enabling lateral movement to connected systems
- Risk of cascading compromise across the BUNL IT External Zone

---

## 2. Threat Intelligence

**Sources:**
- Application access logs: `/var/log/bunl/`
- Systemd journal: `journalctl -u bunl-cdn-server --since today`

**Indicators of Compromise (IOCs):**
- GET requests to /assets../ prefix in Nginx access log returning 200 with application/x-python content type

**Log Entry Identified:**
```
[Paste relevant log line from access.log here]
e.g. 2025-11-15 09:42:11 WARNING <IOC details from log>
```

---

## 3. Vulnerability Identification

**Vulnerability:** Nginx Alias Path Traversal (Off-By-One)

**Affected Parameter:** `GET /assets../config.py (Nginx alias off-by-one)`

**Description:** The BUNL CDN Static File Server (Nginx) processes the `GET /assets../config.py (Nginx alias off-by-one)` without sufficient sanitisation or security controls, allowing an attacker to manipulate the application logic and access privileged data or functionality.

**Patch Status:** Completed — single character change in nginx.conf

---

## 4. Security Operations

**Prevention Steps:**
- Add trailing slash: change 'location /assets' to 'location /assets/' in nginx.conf. Run nginx -t to verify. Reload nginx
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

This incident is part of the Operation VAJRA SHAKTI purple team cyber exercise targeting BUNL infrastructure. The exploitation of M05 provides the attacker with credentials or tokens necessary to progress to the next machine in the kill chain. Downstream services must be assessed immediately.

**Connected services at risk:**
- RNG-CORP-01 M1 (pivot token exposed: vs-corp-7g9h2j4k6n2m)

---

## 6. POC (Screenshots)
[Attach screenshots showing the exploit payload, server response, and log evidence]
