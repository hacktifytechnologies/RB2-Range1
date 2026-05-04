#!/usr/bin/env bash
# ============================================================
# RNG-EXT-01 | M2-ext-billing-api | Ancillary Services
# BUNL Billing API — Secondary infrastructure services
# ============================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi

SVC_DIR="/opt/bunl/ancillary/m2"
LOG_DIR="/var/log/bunl/ancillary/m2"
mkdir -p "${SVC_DIR}" "${LOG_DIR}"

pip3 install flask --break-system-packages -q 2>/dev/null || true

# ── Service 1: Revenue Analytics Portal (port 8081) ──────────
cat > "${SVC_DIR}/revenue_analytics.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, session, redirect
import logging, time

app = Flask(__name__)
app.secret_key = "rev-portal-bunl-sk"
LOG_DIR = "/var/log/bunl/ancillary/m2"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

MONTHLY_DATA = [
    {"month": "Oct 2025", "revenue": 284132000, "consumers": 2412847, "units_billed": 1847392},
    {"month": "Sep 2025", "revenue": 271840000, "consumers": 2398012, "units_billed": 1793821},
    {"month": "Aug 2025", "revenue": 312490000, "consumers": 2401234, "units_billed": 2014782},
    {"month": "Jul 2025", "revenue": 329800000, "consumers": 2389012, "units_billed": 2134921},
]

LOGIN = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Revenue Analytics</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#0f172a;font-family:'Segoe UI',sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#1e293b;border:1px solid #334155;border-radius:12px;width:380px;overflow:hidden}
.bh{background:#0f172a;padding:1.5rem;text-align:center;border-bottom:1px solid #334155}
.bh h6{color:#38bdf8;font-weight:700;margin:0}.bh small{color:#64748b;font-size:.78rem}
.bb{padding:1.5rem}.form-control{background:#0f172a;border-color:#334155;color:#e2e8f0;font-size:.9rem}
.form-control:focus{background:#0f172a;color:#e2e8f0;border-color:#38bdf8;box-shadow:none}
.form-label{color:#94a3b8;font-size:.83rem}.btn-primary{background:#1d4ed8;border:none}</style></head><body>
<div class="box"><div class="bh"><h6>&#128200; Revenue Analytics Platform</h6><small>BUNL Finance & Operations</small></div>
<div class="bb">{% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.83rem">{{ error }}</div>{% endif %}
<form method="POST"><div class="mb-3"><label class="form-label">Analyst ID</label>
<input name="u" class="form-control" placeholder="e.g. finance.analyst01"></div>
<div class="mb-3"><label class="form-label">Password</label>
<input type="password" name="p" class="form-control"></div>
<button type="submit" class="btn btn-primary w-100">Access Dashboard</button></form>
</div></div></body></html>"""

DASH = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Revenue Analytics</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#0f172a;color:#e2e8f0;font-family:'Segoe UI',sans-serif}
.navbar{background:#0f172a;border-bottom:1px solid #1e293b}.card{background:#1e293b;border:1px solid #334155;border-radius:8px}
.card-header{background:#0f172a;color:#38bdf8;font-size:.88rem;font-weight:600;border-radius:8px 8px 0 0!important;border-bottom:1px solid #334155}
.stat{font-size:1.8rem;font-weight:700;color:#38bdf8}.stat-label{font-size:.78rem;color:#64748b}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#38bdf8;font-weight:700">&#128200; BUNL Revenue Analytics</span>
<a href="/logout" class="btn btn-sm btn-outline-secondary ms-auto">Logout</a></nav>
<div class="container-fluid p-3">
<div class="row g-3 mb-3">
{% for m in data %}
<div class="col-md-3"><div class="card p-3"><div class="stat">₹{{ (m.revenue/10000000)|round(1) }}Cr</div>
<div class="stat-label">{{ m.month }} Revenue</div>
<div style="font-size:.78rem;color:#64748b">{{ "{:,}".format(m.consumers) }} consumers</div></div></div>
{% endfor %}
</div>
<div class="card"><div class="card-header">Monthly Revenue Summary</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.83rem;color:#cbd5e1">
<thead style="background:#0f172a"><tr><th class="ps-3">Month</th><th>Revenue (₹)</th><th>Consumers</th><th>Units Billed (kWh)</th></tr></thead>
<tbody>{% for m in data %}<tr><td class="ps-3">{{ m.month }}</td>
<td>₹{{ "{:,.0f}".format(m.revenue) }}</td>
<td>{{ "{:,}".format(m.consumers) }}</td>
<td>{{ "{:,}".format(m.units_billed) }}</td></tr>{% endfor %}</tbody>
</table></div></div></div></body></html>"""

@app.route("/", methods=["GET","POST"])
def login():
    if "rev_auth" in session: return redirect("/dashboard")
    error = None
    if request.method == "POST":
        u,p = request.form.get("u",""), request.form.get("p","")
        logging.warning(f"REV_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        if p in ("revenue123","Bunl@Finance1","admin"):
            session["rev_auth"] = u; return redirect("/dashboard")
        error = "Invalid credentials."
    return render_template_string(LOGIN, error=error)

@app.route("/dashboard")
def dashboard():
    if "rev_auth" not in session: return redirect("/")
    return render_template_string(DASH, data=MONTHLY_DATA)

@app.route("/api/v1/revenue/monthly")
def rev_api():
    logging.warning(f"REV_API|ip={request.remote_addr}")
    return jsonify(MONTHLY_DATA)

@app.route("/logout")
def logout():
    session.clear(); return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081, debug=False)
PYEOF

# ── Service 2: Billing Dispute Portal (port 9002) ────────────
cat > "${SVC_DIR}/dispute_portal.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging, time, re

app = Flask(__name__)
LOG_DIR = "/var/log/bunl/ancillary/m2"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Billing Dispute Portal</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}
.header{background:#003d7a;color:#fff;padding:1rem 2rem}.brand{font-weight:700}
.card{border:none;box-shadow:0 2px 8px rgba(0,0,0,.1);border-radius:10px;max-width:600px;margin:2rem auto}
.card-header{background:#003d7a;color:#fff;font-weight:600;border-radius:10px 10px 0 0!important}
.btn-primary{background:#003d7a;border:none}</style></head><body>
<div class="header"><div class="brand">&#9889; BUNL Billing Dispute Portal</div></div>
<div class="card">
<div class="card-header">Raise a Bill Dispute</div>
<div class="card-body">
{% if submitted %}
<div class="alert alert-success">Dispute registered. Reference: <strong>DSP-{{ ref }}</strong>. You will be contacted within 5 working days.</div>
{% else %}
<form method="POST">
  <div class="mb-3"><label class="form-label fw-semibold">Consumer ID</label>
  <input name="consumer_id" class="form-control" placeholder="BUNL-CG-YYYY-NNNNN" required></div>
  <div class="mb-3"><label class="form-label fw-semibold">Bill Month</label>
  <select name="month" class="form-select"><option>October 2025</option><option>September 2025</option><option>August 2025</option></select></div>
  <div class="mb-3"><label class="form-label fw-semibold">Dispute Type</label>
  <select name="dtype" class="form-select"><option>Excess Units Billed</option><option>Wrong Tariff Applied</option><option>Meter Reading Error</option><option>Duplicate Bill</option></select></div>
  <div class="mb-3"><label class="form-label fw-semibold">Description</label>
  <textarea name="description" class="form-control" rows="3" placeholder="Describe the discrepancy..."></textarea></div>
  <button type="submit" class="btn btn-primary w-100">Submit Dispute</button>
</form>
{% endif %}
</div></div></body></html>"""

@app.route("/", methods=["GET","POST"])
def dispute():
    if request.method == "POST":
        data = {k:v for k,v in request.form.items()}
        logging.warning(f"DISPUTE|ip={request.remote_addr}|consumer={data.get('consumer_id','')}|type={data.get('dtype','')}")
        # SSTI test in description field — render_template_string with user input
        desc = data.get("description","")
        if "{{" in desc or "{%" in desc:
            logging.warning(f"SSTI_ATTEMPT|ip={request.remote_addr}|payload={desc[:100]}")
        import random
        return render_template_string(PAGE, submitted=True, ref=random.randint(100000,999999))
    return render_template_string(PAGE, submitted=False)

@app.route("/api/v1/disputes/<dispute_id>")
def dispute_status(dispute_id):
    logging.warning(f"DISPUTE_STATUS|ip={request.remote_addr}|id={dispute_id}")
    return jsonify({"dispute_id": dispute_id, "status": "Under Review", "eta": "5 working days"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9002, debug=False)
PYEOF

# ── Service 3: Staff GraphQL Explorer (port 4001) ────────────
cat > "${SVC_DIR}/graphql_explorer.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/bunl/ancillary/m2"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

EXPLORER_PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>BUNL Billing API — GraphQL Explorer</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>
body{font-family:'Segoe UI',sans-serif;background:#1e1e2e;color:#cdd6f4;margin:0}
.topbar{background:#181825;padding:10px 20px;display:flex;align-items:center;gap:12px;border-bottom:1px solid #313244}
.topbar .brand{color:#cba6f7;font-weight:700;font-size:1rem}
.topbar .version{background:#313244;color:#a6e3a1;padding:2px 10px;border-radius:10px;font-size:.75rem}
.main{display:grid;grid-template-columns:1fr 1fr;gap:0;height:calc(100vh - 48px)}
.pane{padding:1rem;border-right:1px solid #313244}
.pane-header{color:#89b4fa;font-size:.8rem;font-weight:600;margin-bottom:.5rem;text-transform:uppercase;letter-spacing:.5px}
textarea{width:100%;background:#181825;color:#cdd6f4;border:1px solid #313244;border-radius:6px;font-family:monospace;font-size:.85rem;resize:none;padding:.75rem;height:280px}
textarea:focus{outline:none;border-color:#cba6f7}
.btn-run{background:#cba6f7;color:#181825;border:none;border-radius:6px;padding:.4rem 1.2rem;font-weight:700;font-size:.85rem;cursor:pointer}
.result-box{background:#181825;border:1px solid #313244;border-radius:6px;padding:.75rem;height:280px;overflow:auto;font-family:monospace;font-size:.82rem;color:#a6e3a1}
.schema-section{margin-top:1rem}
.type-name{color:#cba6f7;font-weight:700;font-size:.85rem}
.field-name{color:#89b4fa;font-size:.82rem}
.field-type{color:#a6e3a1;font-size:.82rem}
</style></head><body>
<div class="topbar">
  <span class="brand">BUNL Billing API</span>
  <span class="version">GraphQL v2.1.4</span>
  <span style="color:#6c7086;font-size:.8rem;margin-left:auto">billing-api.bunl-internal.net:4000</span>
</div>
<div class="main">
  <div class="pane">
    <div class="pane-header">Query Editor</div>
    <textarea id="qry">{ __schema { queryType { name } mutationType { name } } }</textarea>
    <div class="d-flex gap-2 mt-2">
      <button class="btn-run" onclick="runQuery()">&#9654; Run Query</button>
      <select id="example" onchange="loadExample()" style="background:#313244;color:#cdd6f4;border:1px solid #45475a;border-radius:6px;padding:.3rem .8rem;font-size:.8rem">
        <option value="">Load example...</option>
        <option value="introspect">Full introspection</option>
        <option value="consumers">List consumers</option>
        <option value="login">Staff login mutation</option>
      </select>
    </div>
    <div class="pane-header mt-3">Variables (JSON)</div>
    <textarea id="vars" style="height:80px">{}</textarea>
  </div>
  <div class="pane" style="border-right:none">
    <div class="pane-header">Response</div>
    <div class="result-box" id="result">// Run a query to see results</div>
    <div class="schema-section">
      <div class="pane-header mt-2">Schema Reference</div>
      <div class="type-name">Query</div>
      <div class="ms-2"><span class="field-name">listConsumers</span><span class="field-type ms-2">(apiKey: String!): [Consumer]</span></div>
      <div class="ms-2"><span class="field-name">listStaffUsers</span><span class="field-type ms-2">(apiKey: String!): [StaffUser]</span></div>
      <div class="ms-2"><span class="field-name">systemConfig</span><span class="field-type ms-2">(token: String!): SystemConfig</span></div>
      <div class="type-name mt-2">Mutation</div>
      <div class="ms-2"><span class="field-name">staffLogin</span><span class="field-type ms-2">(username: String!, password: String!): StaffToken</span></div>
    </div>
  </div>
</div>
<script>
const EXAMPLES = {
  introspect: `{ __schema { types { name kind fields { name type { name kind } } } } }`,
  consumers: `query($k: String!) { listConsumers(apiKey: $k) { consumerId name division outstanding } }`,
  login: `mutation { staffLogin(username: "admin", password: "admin") { token role expiresIn } }`
};
function loadExample() {
  const k = document.getElementById('example').value;
  if (k && EXAMPLES[k]) document.getElementById('qry').value = EXAMPLES[k];
}
async function runQuery() {
  const q = document.getElementById('qry').value;
  const v = document.getElementById('vars').value;
  let vars = {};
  try { vars = JSON.parse(v); } catch(e) {}
  document.getElementById('result').textContent = 'Running...';
  try {
    const r = await fetch('http://' + window.location.hostname + ':4000/graphql', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({query: q, variables: vars})
    });
    const d = await r.json();
    document.getElementById('result').textContent = JSON.stringify(d, null, 2);
  } catch(e) {
    document.getElementById('result').textContent = 'Error: ' + e.message;
  }
}
</script>
</body></html>"""

@app.route("/")
def explorer():
    logging.warning(f"EXPLORER_ACCESS|ip={request.remote_addr}")
    return render_template_string(EXPLORER_PAGE)

@app.route("/api/health")
def health():
    return jsonify({"status": "ok", "service": "BUNL GraphQL Explorer"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4001, debug=False)
PYEOF

# ── Service 4: Tariff Management Console (port 7443) ─────────
cat > "${SVC_DIR}/tariff_console.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, session, redirect
import logging

app = Flask(__name__)
app.secret_key = "tariff-bunl-sk9x"
LOG_DIR = "/var/log/bunl/ancillary/m2"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

TARIFFS = [
    {"code":"LT-I","category":"Domestic","rate_per_unit":7.00,"fixed_charge":100,"desc":"Residential consumers up to 500 Units/Month"},
    {"code":"LT-II","category":"Commercial","rate_per_unit":9.50,"fixed_charge":250,"desc":"Commercial establishments"},
    {"code":"LT-IV","category":"Agriculture","rate_per_unit":3.50,"fixed_charge":50,"desc":"Agricultural pump sets"},
    {"code":"HT-I","category":"Industrial","rate_per_unit":6.80,"fixed_charge":500,"desc":"HT Industrial consumers > 100 kVA"},
]

LOGIN_PG = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Tariff Management</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:'Segoe UI',sans-serif}
.box{background:#fff;border-radius:10px;box-shadow:0 4px 20px rgba(0,0,0,.1);width:380px;overflow:hidden}
.bh{background:#1a3a5c;color:#fff;padding:1.5rem;text-align:center}.bh h6{font-weight:700;margin:0}
.bb{padding:1.5rem}.btn-primary{background:#1a3a5c;border:none}</style></head><body>
<div class="box"><div class="bh"><h6>&#128204; BUNL Tariff Management Console</h6><small style="color:#a8c4e0">Regulatory & Finance Division</small></div>
<div class="bb">{% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.83rem">{{ error }}</div>{% endif %}
<form method="POST"><div class="mb-3"><label style="font-size:.83rem;font-weight:600">Username</label>
<input name="u" class="form-control" placeholder="Regulatory staff ID"></div>
<div class="mb-3"><label style="font-size:.83rem;font-weight:600">Password</label>
<input type="password" name="p" class="form-control"></div>
<button type="submit" class="btn btn-primary w-100">Login</button></form>
</div></div></body></html>"""

DASH_PG = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Tariff Management</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}
.navbar{background:#1a3a5c}.card{border:none;box-shadow:0 1px 4px rgba(0,0,0,.08);border-radius:8px}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#128204; Tariff Management Console</span>
<a href="/logout" class="btn btn-sm btn-outline-light ms-auto">Logout</a></nav>
<div class="container py-3">
<div class="card"><div class="card-header" style="background:#1a3a5c;color:#fff;font-weight:600;border-radius:8px 8px 0 0">Current Tariff Schedule — Maharashtra SERC Approved</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
<thead style="background:#f8f9fa"><tr><th class="ps-3">Code</th><th>Category</th><th>Rate/Unit (₹)</th><th>Fixed Charge (₹/Month)</th><th>Description</th></tr></thead>
<tbody>{% for t in tariffs %}<tr><td class="ps-3"><code>{{ t.code }}</code></td><td>{{ t.category }}</td>
<td>{{ t.rate_per_unit }}</td><td>{{ t.fixed_charge }}</td><td style="font-size:.8rem;color:#6c757d">{{ t.desc }}</td></tr>{% endfor %}
</tbody></table></div></div></div></body></html>"""

@app.route("/", methods=["GET","POST"])
def login():
    if "tariff_auth" in session: return redirect("/dashboard")
    error = None
    if request.method == "POST":
        u,p = request.form.get("u",""), request.form.get("p","")
        logging.warning(f"TARIFF_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        if p in ("Tariff@2025","admin","Bunl@Reg1"):
            session["tariff_auth"]=u; return redirect("/dashboard")
        error = "Invalid credentials."
    return render_template_string(LOGIN_PG, error=error)

@app.route("/dashboard")
def dashboard():
    if "tariff_auth" not in session: return redirect("/")
    return render_template_string(DASH_PG, tariffs=TARIFFS)

@app.route("/api/v1/tariffs")
def tariff_api():
    logging.warning(f"TARIFF_API|ip={request.remote_addr}")
    return jsonify(TARIFFS)

@app.route("/logout")
def logout():
    session.clear(); return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7443, debug=False)
PYEOF

# ── Service 5: Fraud Detection API (port 6090) ───────────────
cat > "${SVC_DIR}/fraud_api.py" << 'PYEOF'
from flask import Flask, request, jsonify
import logging, time, random

app = Flask(__name__)
LOG_DIR = "/var/log/bunl/ancillary/m2"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

ALERTS = [
    {"alert_id": "FRD-2025-0891", "consumer_id": "BUNL-CG-2021-00512", "type": "ABNORMAL_USAGE", "score": 0.87, "flagged_at": "2025-11-14 22:10", "status": "Under Review"},
    {"alert_id": "FRD-2025-0887", "consumer_id": "BUNL-AG-2019-01147", "type": "METER_BYPASS", "score": 0.94, "flagged_at": "2025-11-13 11:30", "status": "Confirmed"},
]

@app.before_request
def log_req():
    auth = request.headers.get("Authorization","none")[:30]
    logging.warning(f"FRAUD_API|ip={request.remote_addr}|path={request.path}|auth={auth}")

@app.route("/api/v1/fraud/alerts")
def alerts():
    return jsonify({"alerts": ALERTS, "total": len(ALERTS), "generated": int(time.time())})

@app.route("/api/v1/fraud/score", methods=["POST"])
def score():
    data = request.get_json(silent=True) or {}
    consumer = data.get("consumer_id","")
    return jsonify({"consumer_id": consumer, "risk_score": round(random.uniform(0.1, 0.95), 2), "risk_level": random.choice(["LOW","MEDIUM","HIGH"]), "model_version": "v3.1.2"})

@app.route("/api/v1/health")
def health():
    return jsonify({"status": "ok", "service": "BUNL Fraud Detection API", "version": "3.1.2"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6090, debug=False)
PYEOF

# ── Service 6: TCP Memcached Banner (port 11211) ─────────────
cat > "${SVC_DIR}/memcached_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/bunl/ancillary/m2"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

STATS = (b"STAT pid 1842\r\nSTAT uptime 86400\r\nSTAT version 1.6.17\r\n"
         b"STAT curr_connections 4\r\nSTAT total_items 1247\r\n"
         b"STAT bytes 2048000\r\nSTAT limit_maxbytes 67108864\r\nEND\r\n")
FAKE_SESSION = b"VALUE bunl:session:admin 0 42\r\nadmin_session_token_placeholder_value\r\nEND\r\n"

def handle(conn, addr):
    logging.warning(f"MEMCACHED_PROBE|ip={addr[0]}:{addr[1]}|proto=TCP")
    try:
        data = conn.recv(512).decode(errors="ignore").strip()
        logging.warning(f"MEMCACHED_CMD|ip={addr[0]}|cmd={data[:80]}")
        if data.startswith("stats"):
            conn.sendall(STATS)
        elif "bunl:session:admin" in data:
            logging.warning(f"MEMCACHED_SESSION_READ|ip={addr[0]}|CRITICAL=SESSION_ENUM")
            conn.sendall(FAKE_SESSION)
        elif data.startswith("get") or data.startswith("gets"):
            conn.sendall(b"END\r\n")
        else:
            conn.sendall(b"ERROR\r\n")
    except Exception:
        pass
    finally:
        conn.close()

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 11211))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

declare -A SVCS=(
    ["bunl-svc-m2-revenue"]="${SVC_DIR}/revenue_analytics.py"
    ["bunl-svc-m2-dispute"]="${SVC_DIR}/dispute_portal.py"
    ["bunl-svc-m2-gqlexplorer"]="${SVC_DIR}/graphql_explorer.py"
    ["bunl-svc-m2-tariff"]="${SVC_DIR}/tariff_console.py"
    ["bunl-svc-m2-fraud"]="${SVC_DIR}/fraud_api.py"
    ["bunl-svc-m2-memcached"]="${SVC_DIR}/memcached_tcp.py"
)

for SVC in "${!SVCS[@]}"; do
    cat > "/etc/systemd/system/${SVC}.service" << UNIT
[Unit]
Description=BUNL Infrastructure Service — ${SVC}
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${SVCS[$SVC]}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SVC}
[Install]
WantedBy=multi-user.target
UNIT
done

systemctl daemon-reload
for SVC in "${!SVCS[@]}"; do
    systemctl enable "${SVC}" --quiet 2>/dev/null || true
    systemctl restart "${SVC}" 2>/dev/null || true
done

for PORT in 8081 9002 4001 7443 6090 11211; do
    ufw allow "${PORT}/tcp" comment "BUNL Ancillary M2" 2>/dev/null || true
done

echo "============================================================"
echo "  M2 Ancillary Services Active"
echo "  8081  — Revenue Analytics Portal (finance dashboard)"
echo "  9002  — Billing Dispute Portal (SSTI attempt logging)"
echo "  4001  — GraphQL Schema Explorer"
echo "  7443  — Tariff Management Console"
echo "  6090  — Fraud Detection REST API"
echo "  11211 — Memcached TCP (stats + fake session key)"
echo "  Logs → ${LOG_DIR}/services.log"
echo "============================================================"
