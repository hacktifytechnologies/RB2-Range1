#!/usr/bin/env bash
# ============================================================
# RNG-EXT-01 | M1-ext-customer-portal | Ancillary Services
# BUNL Customer Portal — Secondary infrastructure services
# ============================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi
command -v python3 >/dev/null || { echo "[!] python3 required." >&2; exit 1; }

SVC_DIR="/opt/bunl/ancillary/m1"
LOG_DIR="/var/log/bunl/ancillary/m1"
mkdir -p "${SVC_DIR}" "${LOG_DIR}"

# ── Service 1: Smart Metering Dashboard (port 8443) ──────────
cat > "${SVC_DIR}/smart_metering.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, session
import logging, os, random, time, re

app = Flask(__name__)
app.secret_key = "smdb-bunl-2025-k8"
LOG_DIR = "/var/log/bunl/ancillary/m1"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

PAGE = """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>BUNL Smart Metering Dashboard</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.2/css/all.min.css" rel="stylesheet">
<style>
body{font-family:'Segoe UI',sans-serif;background:#0a1628;color:#e2e8f0}
.navbar{background:#001d3d;border-bottom:1px solid #1a3a5c}
.brand{color:#f5a623;font-weight:700;font-size:1.05rem}
.card{background:#0f2744;border:1px solid #1a3a5c;border-radius:8px}
.card-header{background:#001d3d;color:#f5a623;font-size:.88rem;font-weight:600;border-radius:8px 8px 0 0!important;border-bottom:1px solid #1a3a5c}
.stat-val{font-size:2rem;font-weight:700;color:#38bdf8}
.stat-label{font-size:.78rem;color:#64748b;text-transform:uppercase;letter-spacing:.5px}
.live-dot{display:inline-block;width:8px;height:8px;background:#22c55e;border-radius:50%;animation:blink 1.2s infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.3}}
.login-box{background:#0f2744;border:1px solid #1a3a5c;border-radius:12px;max-width:400px;margin:60px auto;padding:2rem}
.login-box h5{color:#f5a623;font-weight:700;margin-bottom:1.2rem}
.form-control{background:#001d3d;border-color:#1a3a5c;color:#e2e8f0;font-size:.9rem}
.form-control:focus{background:#001d3d;color:#e2e8f0;border-color:#38bdf8;box-shadow:none}
.btn-primary{background:#1a56db;border:none}
.alert-danger{background:#2d1515;border-color:#7f1d1d;color:#fca5a5}
</style></head><body>
<nav class="navbar px-3 py-2"><span class="brand"><i class="fa fa-bolt me-2"></i>BUNL Smart Metering Dashboard</span>
<span class="ms-auto"><span class="live-dot me-2"></span><span style="font-size:.8rem;color:#94a3b8">LIVE</span></span></nav>

{% if not session.get('smdb_auth') %}
<div class="container">
<div class="login-box">
  <h5><i class="fa fa-satellite-dish me-2"></i>SCADA Access Portal</h5>
  <p style="font-size:.83rem;color:#64748b">Authorised BUNL Operations Personnel Only</p>
  {% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.85rem">{{ error }}</div>{% endif %}
  <form method="POST">
    <div class="mb-3"><label style="font-size:.83rem;color:#94a3b8">Operator ID</label>
    <input name="username" class="form-control mt-1" placeholder="e.g. ops.singrauli01"></div>
    <div class="mb-3"><label style="font-size:.83rem;color:#94a3b8">Access Code</label>
    <input type="password" name="password" class="form-control mt-1" placeholder="SCADA access code"></div>
    <button type="submit" class="btn btn-primary w-100 fw-bold">Authenticate</button>
  </form>
</div></div>
{% else %}
<div class="container-fluid py-3 px-4">
<div class="row g-3 mb-3">
  {% for label, val, unit in [('Grid Load', '1,847', 'MW'), ('Solar Feed-in', '324', 'MW'), ('Active Consumers', '2.4M', ''), ('Fault Incidents', '3', 'Active')] %}
  <div class="col-md-3"><div class="card p-3 text-center">
    <div class="stat-val">{{ val }}<span style="font-size:1rem;color:#64748b"> {{ unit }}</span></div>
    <div class="stat-label">{{ label }}</div>
  </div></div>
  {% endfor %}
</div>
<div class="card"><div class="card-header"><i class="fa fa-table me-2"></i>Substation Status — Maharashtra Region</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.83rem;color:#cbd5e1">
<thead style="background:#001d3d"><tr><th class="ps-3">Substation</th><th>Load (MVA)</th><th>Voltage (kV)</th><th>Status</th></tr></thead>
<tbody>
{% for s in substations %}
<tr><td class="ps-3">{{ s.name }}</td><td>{{ s.load }}</td><td>{{ s.voltage }}</td>
<td><span class="badge bg-{{ 'success' if s.status=='NORMAL' else 'warning' }}">{{ s.status }}</span></td></tr>
{% endfor %}
</tbody></table></div></div>
</div>
{% endif %}
</body></html>"""

SUBSTATIONS = [
    {"name": "Kalyan 220kV SS", "load": "312", "voltage": "218.4", "status": "NORMAL"},
    {"name": "Thane East 110kV SS", "load": "187", "voltage": "109.8", "status": "NORMAL"},
    {"name": "Dombivli 33kV SS", "load": "94", "voltage": "32.7", "status": "HIGH_LOAD"},
    {"name": "Badlapur 33kV SS", "load": "61", "voltage": "33.1", "status": "NORMAL"},
]

@app.route("/", methods=["GET", "POST"])
def index():
    error = None
    if request.method == "POST":
        u = request.form.get("username", "")
        p = request.form.get("password", "")
        logging.warning(f"AUTH_ATTEMPT|ip={request.remote_addr}|user={u}|pass={p}")
        # XSS reflected in error — basic exploitable vuln
        if "<script>" in u.lower() or "<script>" in p.lower():
            logging.warning(f"XSS_ATTEMPT|ip={request.remote_addr}|payload={u[:80]}")
        error = f"Authentication failed for operator: {u}. Access denied."
    return render_template_string(PAGE, error=error, substations=SUBSTATIONS)

@app.route("/api/v1/substations")
def substations_api():
    logging.warning(f"API_ACCESS|ip={request.remote_addr}|path=/api/v1/substations")
    return jsonify({"substations": SUBSTATIONS, "region": "Maharashtra", "timestamp": int(time.time())})

@app.route("/api/v1/meters/<meter_id>")
def meter_data(meter_id):
    logging.warning(f"API_ACCESS|ip={request.remote_addr}|meter_id={meter_id}")
    return jsonify({"meter_id": meter_id, "reading": random.randint(100, 9999), "unit": "kWh", "timestamp": int(time.time())})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8443, debug=False)
PYEOF

# ── Service 2: Bill Payment Gateway (port 9001) ──────────────
cat > "${SVC_DIR}/bill_payment.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging, re, time

app = Flask(__name__)
LOG_DIR = "/var/log/bunl/ancillary/m1"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

PAGE = """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>BUNL Bill Payment Gateway</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>
body{font-family:'Segoe UI',sans-serif;background:#f0f4f8;display:flex;flex-direction:column;min-height:100vh}
.header{background:linear-gradient(135deg,#003d7a,#005fa3);color:#fff;padding:1rem 2rem}
.brand{font-weight:700;font-size:1.1rem}.sub{color:#a8c4e0;font-size:.78rem}
.card{border:none;box-shadow:0 2px 8px rgba(0,0,0,.1);border-radius:10px;max-width:520px;margin:2rem auto}
.card-header{background:#003d7a;color:#fff;font-weight:600;border-radius:10px 10px 0 0!important}
.form-label{font-size:.84rem;font-weight:600;color:#495057}
.btn-pay{background:#f5a623;border:none;font-weight:700;padding:.6rem 2rem;border-radius:6px}
.btn-pay:hover{background:#d4901f}
.secure-badge{background:#e8f4fd;border:1px solid #b8d4eb;border-radius:6px;padding:.5rem 1rem;font-size:.78rem;color:#1a5276}
{% if paid %}.success-banner{background:#d4edda;border:1px solid #c3e6cb;border-radius:8px;padding:1.2rem;text-align:center;margin:2rem auto;max-width:520px;color:#155724}{% endif %}
</style></head><body>
<div class="header"><div class="brand"><span style="color:#f5a623">&#9889;</span> BUNL Online Bill Payment</div>
<div class="sub">Secure Payment Gateway — Consumer Services Division</div></div>
{% if paid %}
<div class="success-banner"><div style="font-size:1.5rem">&#10003;</div>
<div class="fw-bold mt-1">Payment Received</div>
<div style="font-size:.87rem">Transaction ID: TXN{{ txn_id }} | Amount: ₹{{ amount }}</div>
<div style="font-size:.82rem;color:#1e7e34">Your payment is being processed. Allow 24–48 hours for update.</div></div>
{% else %}
<div class="card">
<div class="card-header"><i class="fa fa-credit-card me-2" style="display:inline"></i>Pay Your Electricity Bill</div>
<div class="card-body">
<form method="POST">
  <div class="mb-3"><label class="form-label">Consumer ID / Account Number</label>
  <input name="consumer_id" class="form-control" placeholder="e.g. BUNL-CG-2023-00847" required></div>
  <div class="mb-3"><label class="form-label">Amount (₹)</label>
  <input name="amount" type="number" class="form-control" placeholder="e.g. 2184" required></div>
  <div class="mb-3"><label class="form-label">Payment Method</label>
  <select name="method" class="form-select">
    <option>Credit / Debit Card</option><option>UPI</option><option>Net Banking</option><option>NEFT/RTGS</option>
  </select></div>
  <div class="mb-3"><label class="form-label">Card Number (if applicable)</label>
  <input name="card_number" class="form-control" placeholder="XXXX XXXX XXXX XXXX" maxlength="19"></div>
  <div class="row mb-3"><div class="col-6">
    <label class="form-label">Expiry (MM/YY)</label>
    <input name="expiry" class="form-control" placeholder="MM/YY"></div>
  <div class="col-6"><label class="form-label">CVV</label><input name="cvv" type="password" class="form-control" maxlength="3"></div></div>
  <div class="secure-badge mb-3"><span style="color:#1a5276">&#128274;</span> Secured by BUNL Payment Gateway v3.1 | PCI DSS Compliant</div>
  <button type="submit" class="btn btn-pay w-100">Pay Now</button>
</form></div></div>
{% endif %}
</body></html>"""

@app.route("/", methods=["GET", "POST"])
def payment():
    if request.method == "POST":
        data = {k: v for k, v in request.form.items()}
        logging.warning(f"PAYMENT_ATTEMPT|ip={request.remote_addr}|consumer={data.get('consumer_id','')}|amount={data.get('amount','')}|card={data.get('card_number','')[:8]}****")
        # SQL injection attempt in consumer_id (logged, returns success regardless)
        if any(kw in data.get("consumer_id", "").lower() for kw in ["'", "select", "union", "--"]):
            logging.warning(f"SQLI_ATTEMPT|ip={request.remote_addr}|payload={data.get('consumer_id','')[:80]}")
        import random
        return render_template_string(PAGE, paid=True, txn_id=random.randint(100000000, 999999999), amount=data.get("amount", "0"))
    return render_template_string(PAGE, paid=False)

@app.route("/api/v1/verify-consumer")
def verify():
    consumer_id = request.args.get("id", "")
    logging.warning(f"CONSUMER_VERIFY|ip={request.remote_addr}|id={consumer_id}")
    return jsonify({"consumer_id": consumer_id, "name": "—", "outstanding": "N/A", "valid": True})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9001, debug=False)
PYEOF

# ── Service 3: Asset Management System (port 7080) ───────────
cat > "${SVC_DIR}/asset_mgmt.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, send_file
import logging, io, time

app = Flask(__name__)
LOG_DIR = "/var/log/bunl/ancillary/m1"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

ASSETS = [
    {"id": 1001, "tag": "TRF-MH-001", "type": "Transformer 220kV", "location": "Kalyan SS", "status": "Operational", "last_service": "2025-08-12"},
    {"id": 1002, "tag": "CB-MH-014", "type": "Circuit Breaker", "location": "Thane East SS", "status": "Maintenance", "last_service": "2025-10-01"},
    {"id": 1003, "tag": "MTR-MH-2847", "type": "Smart Meter", "location": "Dombivli Zone 3", "status": "Operational", "last_service": "2025-11-01"},
    {"id": 1004, "tag": "CAP-MH-007", "type": "Capacitor Bank", "location": "Badlapur SS", "status": "Operational", "last_service": "2025-09-20"},
    {"id": 1005, "tag": "DG-MH-003", "type": "Diesel Generator", "location": "Kalyan Control Room", "status": "Standby", "last_service": "2025-07-15"},
]

PAGE = """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>BUNL Asset Management</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>
body{font-family:'Segoe UI',sans-serif;background:#f0f4f8}
.navbar{background:#00509e;color:#fff}.brand{color:#fff;font-weight:700}
.card{border:none;box-shadow:0 1px 4px rgba(0,0,0,.08);border-radius:8px}
.card-header{background:#003d7a;color:#fff;font-weight:600;font-size:.88rem;border-radius:8px 8px 0 0!important}
.status-op{color:#155724;background:#d4edda;padding:2px 8px;border-radius:10px;font-size:.78rem}
.status-maint{color:#856404;background:#fff3cd;padding:2px 8px;border-radius:10px;font-size:.78rem}
.status-stby{color:#0c5460;background:#d1ecf1;padding:2px 8px;border-radius:10px;font-size:.78rem}
</style></head><body>
<nav class="navbar px-3 py-2"><span class="brand">&#9889; BUNL Asset Management System v4.1</span>
<span class="ms-auto text-white-50" style="font-size:.8rem">Infrastructure Division</span></nav>
<div class="container py-3">
  <div class="card mb-3">
    <div class="card-header"><i class="fa fa-search"></i> Asset Search</div>
    <div class="card-body">
      <form method="GET">
        <div class="row g-2">
          <div class="col-md-5"><input name="q" class="form-control" placeholder="Search by tag, type or location" value="{{ q }}"></div>
          <div class="col-md-3"><select name="status" class="form-select"><option>All</option><option>Operational</option><option>Maintenance</option><option>Standby</option></select></div>
          <div class="col-md-2"><button type="submit" class="btn btn-primary w-100">Search</button></div>
          <div class="col-md-2"><a href="/reports/download?file=monthly" class="btn btn-outline-secondary w-100">&#128196; Export</a></div>
        </div>
      </form>
    </div>
  </div>
  <div class="card"><div class="card-header">Asset Register</div>
  <div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
    <thead style="background:#f8f9fa"><tr><th class="ps-3">Asset ID</th><th>Tag</th><th>Type</th><th>Location</th><th>Status</th><th>Last Service</th></tr></thead>
    <tbody>
    {% for a in assets %}
    <tr><td class="ps-3"><a href="/api/assets/{{ a.id }}" style="color:#003d7a">#{{ a.id }}</a></td>
    <td><code>{{ a.tag }}</code></td><td>{{ a.type }}</td><td>{{ a.location }}</td>
    <td><span class="status-{{ 'op' if a.status=='Operational' else 'maint' if a.status=='Maintenance' else 'stby' }}">{{ a.status }}</span></td>
    <td>{{ a.last_service }}</td></tr>
    {% endfor %}
    </tbody>
  </table></div></div>
</div>
</body></html>"""

@app.route("/")
def index():
    q = request.args.get("q", "")
    logging.warning(f"ASSET_SEARCH|ip={request.remote_addr}|q={q}")
    filtered = [a for a in ASSETS if q.lower() in a["tag"].lower() or q.lower() in a["type"].lower() or q.lower() in a["location"].lower()] if q else ASSETS
    return render_template_string(PAGE, assets=filtered, q=q)

@app.route("/api/assets/<int:asset_id>")
def asset_detail(asset_id):
    # IDOR — all IDs accessible, no auth check
    logging.warning(f"ASSET_IDOR|ip={request.remote_addr}|id={asset_id}")
    for a in ASSETS:
        if a["id"] == asset_id:
            return jsonify(a)
    # Return plausible fake data for IDs outside list
    return jsonify({"id": asset_id, "tag": f"ASSET-{asset_id}", "type": "Infrastructure Component", "location": "Unknown", "status": "Decommissioned", "last_service": "N/A"})

@app.route("/reports/download")
def report_download():
    f = request.args.get("file", "monthly")
    logging.warning(f"REPORT_DOWNLOAD|ip={request.remote_addr}|file={f}")
    # Path traversal attempt logged, sandboxed
    if ".." in f or "/" in f:
        logging.warning(f"PATH_TRAVERSAL_ATTEMPT|ip={request.remote_addr}|file={f}")
        return "File not found.", 404
    content = f"BUNL Asset Management Report\nGenerated: {time.strftime('%Y-%m-%d')}\nFilter: {f}\n\nAsset Count: {len(ASSETS)}\nStatus: Operational: 3, Maintenance: 1, Standby: 1\n"
    return send_file(io.BytesIO(content.encode()), mimetype="text/plain", as_attachment=True, download_name=f"bunl-asset-report-{f}.txt")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7080, debug=False)
PYEOF

# ── Service 4: IT Service Desk (port 4443) ───────────────────
cat > "${SVC_DIR}/it_service_desk.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, session, redirect, url_for
import logging, time, random

app = Flask(__name__)
app.secret_key = "itdesk-bunl-sk"
LOG_DIR = "/var/log/bunl/ancillary/m1"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

TICKETS = [
    {"id": 5001, "title": "VPN access not working — Singrauli Plant", "priority": "High", "status": "Open", "submitted_by": "rktiwari", "created": "2025-11-14 09:30"},
    {"id": 5002, "title": "Email sync issue on mobile", "priority": "Low", "status": "Resolved", "submitted_by": "asingh", "created": "2025-11-13 14:10"},
    {"id": 5003, "title": "SAP login error — DISHA module", "priority": "Medium", "status": "In Progress", "submitted_by": "svcananya", "created": "2025-11-15 07:45"},
]

LOGIN_PAGE = """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>BUNL IT Service Desk</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#fff;border-radius:10px;box-shadow:0 4px 20px rgba(0,0,0,.1);width:380px;overflow:hidden}
.box-header{background:#003d7a;color:#fff;padding:1.5rem;text-align:center}
.box-header h6{font-weight:700;margin:0}.box-header small{color:#a8c4e0;font-size:.78rem}
.box-body{padding:1.5rem}.form-control{font-size:.9rem}
.btn-primary{background:#003d7a;border:none;font-weight:600}</style></head><body>
<div class="box">
<div class="box-header"><h6>&#128187; BUNL IT Service Desk</h6><small>Employee Support Portal</small></div>
<div class="box-body">
{% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.85rem">{{ error }}</div>{% endif %}
<form method="POST"><div class="mb-3"><label style="font-size:.83rem;font-weight:600">Employee ID</label>
<input name="username" class="form-control mt-1" placeholder="Your staff ID" required></div>
<div class="mb-3"><label style="font-size:.83rem;font-weight:600">Password</label>
<input type="password" name="password" class="form-control mt-1" required></div>
<button type="submit" class="btn btn-primary w-100">Sign In</button></form>
<div class="text-center mt-3" style="font-size:.78rem;color:#6c757d">Default credentials for new joiners: staff ID / <strong>Bunl@123!</strong></div>
</div></div></body></html>"""

DESK_PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>IT Service Desk</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{font-family:'Segoe UI',sans-serif;background:#f0f4f8}
.navbar{background:#003d7a}.brand{color:#fff;font-weight:700}
.card{border:none;box-shadow:0 1px 4px rgba(0,0,0,.08);border-radius:8px}</style></head><body>
<nav class="navbar px-3 py-2"><span class="brand">&#128187; BUNL IT Service Desk</span>
<a href="/logout" class="btn btn-sm btn-outline-light ms-auto">Logout</a></nav>
<div class="container py-3">
<div class="card mb-3"><div class="card-header" style="background:#003d7a;color:#fff;font-weight:600;border-radius:8px 8px 0 0">My Tickets</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
<thead style="background:#f8f9fa"><tr><th class="ps-3">ID</th><th>Title</th><th>Priority</th><th>Status</th><th>Created</th></tr></thead>
<tbody>{% for t in tickets %}<tr>
<td class="ps-3">#{{ t.id }}</td><td>{{ t.title }}</td>
<td><span class="badge bg-{{ 'danger' if t.priority=='High' else 'warning text-dark' if t.priority=='Medium' else 'secondary' }}">{{ t.priority }}</span></td>
<td>{{ t.status }}</td><td>{{ t.created }}</td>
</tr>{% endfor %}</tbody></table></div></div>
<a href="/new-ticket" class="btn btn-primary btn-sm">+ New Ticket</a>
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def login():
    if "itdesk_user" in session:
        return redirect("/dashboard")
    error = None
    if request.method == "POST":
        u = request.form.get("username", "")
        p = request.form.get("password", "")
        logging.warning(f"ITDESK_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        # Default creds work (admin/admin123 or anything/Bunl@123!)
        if p in ("Bunl@123!", "admin123", "admin") or (u == "admin" and p == "admin"):
            session["itdesk_user"] = u
            session["itdesk_role"] = "admin" if u == "admin" else "staff"
            return redirect("/dashboard")
        error = "Invalid credentials."
    return render_template_string(LOGIN_PAGE, error=error)

@app.route("/dashboard")
def dashboard():
    if "itdesk_user" not in session:
        return redirect("/")
    return render_template_string(DESK_PAGE, tickets=TICKETS)

@app.route("/new-ticket", methods=["GET", "POST"])
def new_ticket():
    if request.method == "POST":
        title = request.form.get("title", "")
        # Stored XSS — title rendered as HTML in admin view (sandboxed, no real cookies)
        logging.warning(f"TICKET_CREATED|ip={request.remote_addr}|title={title[:100]}")
        if "<" in title:
            logging.warning(f"STORED_XSS_ATTEMPT|ip={request.remote_addr}|payload={title[:100]}")
    return "<html><body><form method='POST'><input name='title' placeholder='Issue title'><textarea name='desc'></textarea><button type='submit'>Submit</button></form></body></html>"

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/")

@app.route("/api/v1/tickets")
def tickets_api():
    return jsonify(TICKETS)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4443, debug=False)
PYEOF

# ── Service 5: Outage Reporting API (port 6080) ──────────────
cat > "${SVC_DIR}/outage_api.py" << 'PYEOF'
from flask import Flask, request, jsonify
import logging, time, random

app = Flask(__name__)
LOG_DIR = "/var/log/bunl/ancillary/m1"
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

OUTAGES = [
    {"id": "OUT-2025-1142", "location": "Dombivli Zone 3", "cause": "Feeder fault", "start": "2025-11-15 06:20", "restoration_eta": "2025-11-15 10:00", "affected_consumers": 1240},
    {"id": "OUT-2025-1139", "location": "Thane West Zone 1", "cause": "Planned maintenance", "start": "2025-11-14 22:00", "restoration_eta": "2025-11-15 02:00", "affected_consumers": 540},
]

@app.before_request
def log_req():
    logging.warning(f"OUTAGE_API|ip={request.remote_addr}|method={request.method}|path={request.path}|auth={request.headers.get('X-API-KEY','none')[:20]}")

@app.route("/api/v1/outages")
def outages():
    return jsonify({"outages": OUTAGES, "total": len(OUTAGES), "timestamp": int(time.time())})

@app.route("/api/v1/outages/<outage_id>")
def outage_detail(outage_id):
    for o in OUTAGES:
        if o["id"] == outage_id:
            return jsonify(o)
    return jsonify({"error": "Outage not found"}), 404

@app.route("/api/v1/outages/report", methods=["POST"])
def report_outage():
    data = request.get_json(silent=True) or {}
    logging.warning(f"OUTAGE_REPORT|ip={request.remote_addr}|data={str(data)[:200]}")
    return jsonify({"status": "received", "ref_id": f"OUT-{int(time.time())}", "message": "Your outage report has been registered."})

@app.route("/api/v1/health")
def health():
    return jsonify({"status": "ok", "service": "BUNL Outage Reporting API", "version": "1.2.0"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6080, debug=False)
PYEOF

# ── Service 6: TCP SSH Banner (port 2222) ────────────────────
cat > "${SVC_DIR}/ssh_banner_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/bunl/ancillary/m1"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/services.log", level=logging.WARNING,
    format="%(asctime)s [SVC] %(message)s")

BANNER = b"SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.6\r\nBUNL-REMOTE-MONITORING-NODE-01\r\nUnauthorized access is prohibited and monitored.\r\n"

def handle(conn, addr):
    logging.warning(f"SSH_PROBE|ip={addr[0]}:{addr[1]}|proto=TCP")
    try:
        conn.sendall(BANNER)
        data = conn.recv(256)
        logging.warning(f"SSH_DATA|ip={addr[0]}|data={data[:80]!r}")
    except Exception:
        pass
    finally:
        conn.close()

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 2222))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

# ── pip install flask in system ───────────────────────────────
pip3 install flask --break-system-packages -q 2>/dev/null || true

# ── Systemd services ──────────────────────────────────────────
declare -A SERVICES=(
    ["bunl-svc-m1-smartmeter"]="${SVC_DIR}/smart_metering.py"
    ["bunl-svc-m1-payment"]="${SVC_DIR}/bill_payment.py"
    ["bunl-svc-m1-assetmgmt"]="${SVC_DIR}/asset_mgmt.py"
    ["bunl-svc-m1-itdesk"]="${SVC_DIR}/it_service_desk.py"
    ["bunl-svc-m1-outageapi"]="${SVC_DIR}/outage_api.py"
    ["bunl-svc-m1-sshbanner"]="${SVC_DIR}/ssh_banner_tcp.py"
)

for SVC in "${!SERVICES[@]}"; do
    cat > "/etc/systemd/system/${SVC}.service" << UNIT
[Unit]
Description=BUNL Infrastructure Service — ${SVC}
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${SERVICES[$SVC]}
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
for SVC in "${!SERVICES[@]}"; do
    systemctl enable "${SVC}" --quiet 2>/dev/null || true
    systemctl restart "${SVC}" 2>/dev/null || true
done

for PORT in 8443 9001 7080 4443 6080 2222; do
    ufw allow "${PORT}/tcp" comment "BUNL Ancillary M1" 2>/dev/null || true
done

echo "============================================================"
echo "  M1 Ancillary Services Active"
echo "  8443 — Smart Metering Dashboard (SCADA-style portal)"
echo "  9001 — Bill Payment Gateway (SQL injection logging)"
echo "  7080 — Asset Management System (IDOR in /api/assets/{id})"
echo "  4443 — IT Service Desk (default creds + stored XSS)"
echo "  6080 — Outage Reporting REST API"
echo "  2222 — Remote Monitoring Node (SSH banner)"
echo "  Logs → ${LOG_DIR}/services.log"
echo "============================================================"
