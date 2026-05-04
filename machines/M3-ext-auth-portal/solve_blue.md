# Blue Team Solve Guide — M3
## RNG-EXT-01 | M3-ext-auth-portal | Detection & Response
**Vulnerability:** Flask Weak SECRET_KEY Cookie Forgery

---

## Detection

### Log Analysis
```bash
grep "LOGIN_SUCCESS" /var/log/bunl/auth-portal/access.log | awk -F"|" '{print $3}' | sort | uniq
```

### Access Log Review
```bash
# Review all access logs for anomalies
tail -500 /var/log/bunl/auth/access.log | grep -E "WARNING|ERROR"

# Check for source IPs with high request volume
awk '{print $3}' /var/log/bunl/auth/access.log | sort | uniq -c | sort -rn | head -10
```

### Network-Level Detection
```bash
# Check active connections to this service
ss -tnp | grep ESTABLISHED
# Check firewall logs
journalctl -u ufw | grep -i "block\|deny" | tail -20
```

---

## Containment

```bash
# 1. Block attacker IP at firewall immediately
ATTACKER_IP="<identified IP>"
ufw insert 1 deny from ${ATTACKER_IP} comment "VAJRA-SHAKTI incident block"

# 2. Restart service to clear any active sessions
systemctl restart bunl-auth

# 3. Force session invalidation (for session-based services)
# Change the application secret key and restart
```

---

## Remediation

Replace SECRET_KEY with cryptographically random 32-byte value: python3 -c '\''import secrets; print(secrets.token_hex(32))'\'' and store in environment variable, never in source code.

---

## Indicators of Compromise

- Unusual login patterns in access log (multiple rapid failures followed by success)
- Source IP not in known staff/consumer IP range
- Admin panel access from unexpected session
- Large response sizes on API endpoints (indicating data exfiltration)

---

## Blue Team Checklist

- [ ] Source IP identified and blocked
- [ ] Compromised session/token invalidated
- [ ] Credential rotation completed for any exposed secrets
- [ ] Patch deployed and verified
- [ ] Downstream services assessed for impact
- [ ] Incident timeline documented for INREP
