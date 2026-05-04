#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi
SVC_DIR="/opt/bunl/ancillary/m4"
LOG_DIR="/var/log/bunl/ancillary/m4"
mkdir -p "${SVC_DIR}" "${LOG_DIR}"
pip3 install flask --break-system-packages -q 2>/dev/null || true

# Service 1: Meter Provisioning Console (port 8083) — default creds
cat > "${SVC_DIR}/meter_provisioning.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify,session,redirect
import logging,time
app=Flask(__name__); app.secret_key="mtr-prov-bunl"
LOG_DIR="/var/log/bunl/ancillary/m4"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
METERS=[
    {"id":"MTR-MH-001247","type":"3-Phase Smart","location":"Kalyan Industrial Zone","status":"Active","last_reading":"2025-11-15 06:00","tamper":False},
    {"id":"MTR-MH-002891","type":"1-Phase Smart","location":"Thane West Residential","status":"Active","last_reading":"2025-11-15 05:45","tamper":False},
    {"id":"MTR-MH-003412","type":"1-Phase Basic","location":"Dombivli Zone 3","status":"Inactive","last_reading":"2025-10-31 23:59","tamper":True},
]
LOGIN="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Meter Provisioning</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:'Segoe UI',sans-serif}
.box{background:#fff;border-radius:10px;box-shadow:0 4px 20px rgba(0,0,0,.1);width:380px;overflow:hidden}
.bh{background:#7b2d8b;color:#fff;padding:1.5rem;text-align:center}.bh h6{font-weight:700;margin:0}
.bb{padding:1.5rem}.btn-primary{background:#7b2d8b;border:none;font-weight:600}
.notice{background:#f3e5f5;border-radius:6px;padding:.5rem .8rem;font-size:.78rem;color:#4a148c;margin-top:.8rem}</style></head><body>
<div class="box"><div class="bh"><h6>&#128268; Meter Provisioning Console</h6><small style="color:#ce93d8">BUNL Smart Metering Division</small></div>
<div class="bb">{% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.83rem">{{ error }}</div>{% endif %}
<form method="POST"><div class="mb-3"><label style="font-size:.83rem;font-weight:600">Field Engineer ID</label>
<input name="u" class="form-control" placeholder="e.g. FE-001"></div>
<div class="mb-3"><label style="font-size:.83rem;font-weight:600">Password</label><input type="password" name="p" class="form-control"></div>
<button type="submit" class="btn btn-primary w-100">Login</button></form>
<div class="notice">Field engineers: default password is <strong>Meter@Field1</strong> — please change at first login.</div>
</div></div></body></html>"""
DASH="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Meter Provisioning</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}.navbar{background:#7b2d8b}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#128268; Meter Provisioning Console</span>
<a href="/logout" class="btn btn-sm btn-outline-light ms-auto">Logout</a></nav>
<div class="container py-3"><div class="card border-0 shadow-sm rounded-3">
<div class="card-header" style="background:#7b2d8b;color:#fff;font-weight:600;border-radius:.5rem .5rem 0 0">Active Meters</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
<thead style="background:#f8f9fa"><tr><th class="ps-3">Meter ID</th><th>Type</th><th>Location</th><th>Status</th><th>Last Reading</th><th>Tamper</th></tr></thead>
<tbody>{% for m in meters %}<tr><td class="ps-3"><code>{{ m.id }}</code></td><td>{{ m.type }}</td><td>{{ m.location }}</td>
<td><span class="badge bg-{{ 'success' if m.status=='Active' else 'secondary' }}">{{ m.status }}</span></td>
<td>{{ m.last_reading }}</td>
<td><span class="badge bg-{{ 'danger' if m.tamper else 'light text-dark' }}">{{ 'ALERT' if m.tamper else 'Clear' }}</span></td>
</tr>{% endfor %}</tbody></table></div></div></div></body></html>"""

@app.route("/",methods=["GET","POST"])
def login():
    if "mtr_auth" in session: return redirect("/dashboard")
    error=None
    if request.method=="POST":
        u,p=request.form.get("u",""),request.form.get("p","")
        logging.warning(f"MTR_PROV_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        if p in ("Meter@Field1","admin","field123"): session["mtr_auth"]=u; return redirect("/dashboard")
        error="Invalid credentials."
    return render_template_string(LOGIN,error=error)

@app.route("/dashboard")
def dashboard():
    if "mtr_auth" not in session: return redirect("/")
    return render_template_string(DASH,meters=METERS)

@app.route("/api/v1/meters")
def meters_api():
    logging.warning(f"MTR_API|ip={request.remote_addr}")
    return jsonify(METERS)

@app.route("/logout")
def logout(): session.clear(); return redirect("/")
if __name__=="__main__": app.run(host="0.0.0.0",port=8083,debug=False)
PYEOF

# Service 2: SCADA Gateway API (port 5020) — Modbus TCP banner
cat > "${SVC_DIR}/modbus_tcp.py" << 'PYEOF'
import socket,threading,logging,os,struct
LOG_DIR="/var/log/bunl/ancillary/m4"
os.makedirs(LOG_DIR,exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")

def handle(conn,addr):
    logging.warning(f"MODBUS_PROBE|ip={addr[0]}:{addr[1]}|proto=TCP")
    try:
        data=conn.recv(256)
        logging.warning(f"MODBUS_DATA|ip={addr[0]}|hex={data.hex()[:40]}")
        # Modbus TCP response: unit ID 1, function 1 (Read Coils), 1 byte data
        if len(data)>=6:
            tid=data[0:2]; pid=b'\x00\x00'; length=b'\x00\x04'
            resp=tid+pid+length+b'\x01\x01\x01\x01'
            conn.sendall(resp)
    except Exception: pass
    finally: conn.close()

def serve():
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    s.bind(("0.0.0.0",5020)); s.listen(10)
    while True:
        conn,addr=s.accept()
        threading.Thread(target=handle,args=(conn,addr),daemon=True).start()
if __name__=="__main__": serve()
PYEOF

# Service 3: Data Export API (port 9004) — SQLi
cat > "${SVC_DIR}/data_export.py" << 'PYEOF'
from flask import Flask,request,jsonify
import logging,sqlite3,os
app=Flask(__name__)
LOG_DIR="/var/log/bunl/ancillary/m4"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
DB=":memory:"
conn=sqlite3.connect(DB,check_same_thread=False)
conn.execute("CREATE TABLE readings(id INTEGER PRIMARY KEY,meter_id TEXT,units REAL,ts TEXT)")
conn.execute("INSERT INTO readings VALUES(1,'MTR-001',312.4,'2025-11-15 06:00')")
conn.execute("INSERT INTO readings VALUES(2,'MTR-002',187.1,'2025-11-15 05:45')")
conn.commit()

@app.route("/api/v1/readings")
def readings():
    meter=request.args.get("meter_id","")
    logging.warning(f"READING_QUERY|ip={request.remote_addr}|meter={meter}")
    try:
        # SQLi in meter_id param
        if any(kw in meter.lower() for kw in ["'","union","select","--"]):
            logging.warning(f"SQLI_ATTEMPT|ip={request.remote_addr}|payload={meter[:80]}")
        rows=conn.execute(f"SELECT * FROM readings WHERE meter_id='{meter}'").fetchall()
        return jsonify([{"id":r[0],"meter_id":r[1],"units":r[2],"ts":r[3]} for r in rows])
    except Exception as e:
        return jsonify({"error":str(e)}),500

@app.route("/api/v1/health")
def health(): return jsonify({"status":"ok","service":"BUNL Meter Data Export API"})
if __name__=="__main__": app.run(host="0.0.0.0",port=9004,debug=False)
PYEOF

# Service 4: Calibration Portal (port 7445)
cat > "${SVC_DIR}/calibration_portal.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify,session,redirect
import logging,random
app=Flask(__name__); app.secret_key="calib-bunl-sk"
LOG_DIR="/var/log/bunl/ancillary/m4"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
JOBS=[
    {"id":"CAL-2025-0041","meter":"MTR-MH-001247","tech":"Ramesh Kumar","status":"Completed","due":"2025-11-10"},
    {"id":"CAL-2025-0042","meter":"MTR-MH-002891","tech":"Sunita Desai","status":"Pending","due":"2025-11-20"},
    {"id":"CAL-2025-0043","meter":"MTR-MH-003412","tech":"Vikram Singh","status":"In Progress","due":"2025-11-18"},
]
PAGE="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Meter Calibration</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}
.navbar{background:#c0392b}.card{border:none;box-shadow:0 1px 4px rgba(0,0,0,.08);border-radius:8px}
</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#127959; Meter Calibration Portal</span></nav>
<div class="container py-3">
{% if not auth %}
<div style="max-width:380px;margin:2rem auto;background:#fff;border-radius:10px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,.1)">
<div style="background:#c0392b;color:#fff;padding:1.5rem;text-align:center"><h6 style="font-weight:700;margin:0">Calibration Management Portal</h6></div>
<div style="padding:1.5rem">{% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.83rem">{{ error }}</div>{% endif %}
<form method="POST"><div class="mb-3"><input name="u" class="form-control" placeholder="Technician ID"></div>
<div class="mb-3"><input type="password" name="p" class="form-control" placeholder="Password"></div>
<button type="submit" class="btn w-100 fw-bold" style="background:#c0392b;color:#fff;border:none">Login</button></form></div></div>
{% else %}
<div class="card"><div class="card-header" style="background:#c0392b;color:#fff;font-weight:600;border-radius:8px 8px 0 0">Calibration Job Queue</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
<thead style="background:#f8f9fa"><tr><th class="ps-3">Job ID</th><th>Meter</th><th>Technician</th><th>Status</th><th>Due Date</th></tr></thead>
<tbody>{% for j in jobs %}<tr><td class="ps-3"><code>{{ j.id }}</code></td><td>{{ j.meter }}</td>
<td>{{ j.tech }}</td><td><span class="badge bg-{{ 'success' if j.status=='Completed' else 'warning text-dark' if j.status=='Pending' else 'info' }}">{{ j.status }}</span></td>
<td>{{ j.due }}</td></tr>{% endfor %}</tbody></table></div></div>
{% endif %}
</div></body></html>"""

@app.route("/",methods=["GET","POST"])
def index():
    auth="calib_auth" in session; error=None
    if request.method=="POST":
        u,p=request.form.get("u",""),request.form.get("p","")
        logging.warning(f"CALIB_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        if p in ("Calib@Bunl1","tech123","admin"): session["calib_auth"]=u; auth=True
        else: error="Invalid credentials."
    return render_template_string(PAGE,auth=auth,jobs=JOBS,error=error)

@app.route("/api/v1/jobs")
def jobs(): return jsonify(JOBS)

@app.route("/logout")
def logout(): session.clear(); return redirect("/")
if __name__=="__main__": app.run(host="0.0.0.0",port=7445,debug=False)
PYEOF

# Service 5: Metering Data Aggregator Dashboard (port 3000)
cat > "${SVC_DIR}/aggregator_dash.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify
import logging,time,random
app=Flask(__name__)
LOG_DIR="/var/log/bunl/ancillary/m4"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")

@app.before_request
def log_r(): logging.warning(f"AGGR|ip={request.remote_addr}|path={request.path}")

@app.route("/")
def index():
    return render_template_string("""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Data Aggregator</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#0d1117;color:#e6edf3;font-family:'Segoe UI',sans-serif}
.navbar{background:#161b22;border-bottom:1px solid #30363d}.brand{color:#58a6ff;font-weight:700}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px}
.card-header{background:#0d1117;color:#58a6ff;font-weight:600;border-radius:8px 8px 0 0!important;border-bottom:1px solid #30363d}
.metric{font-size:2rem;font-weight:700;color:#3fb950}</style></head><body>
<nav class="navbar px-3 py-2"><span class="brand">&#128202; BUNL Metering Data Aggregator</span>
<span class="ms-auto" style="font-size:.8rem;color:#8b949e">v2.4.1 | Region: Maharashtra</span></nav>
<div class="container-fluid p-3">
<div class="row g-3 mb-3">
<div class="col-md-3"><div class="card p-3 text-center"><div class="metric">1,247</div><div style="font-size:.78rem;color:#8b949e">Active Meters Online</div></div></div>
<div class="col-md-3"><div class="card p-3 text-center"><div class="metric">2.4M</div><div style="font-size:.78rem;color:#8b949e">kWh Aggregated Today</div></div></div>
<div class="col-md-3"><div class="card p-3 text-center"><div class="metric" style="color:#f85149">3</div><div style="font-size:.78rem;color:#8b949e">Tamper Alerts</div></div></div>
<div class="col-md-3"><div class="card p-3 text-center"><div class="metric" style="color:#d29922">12</div><div style="font-size:.78rem;color:#8b949e">Offline Meters</div></div></div>
</div>
<div class="card"><div class="card-header">Recent Aggregation Log</div>
<div class="card-body" style="font-size:.82rem;font-family:monospace;color:#3fb950">
2025-11-15 09:00:01 [INFO] Aggregated 1247 readings — Zone: MH-West | Total: 2,412,847 kWh<br>
2025-11-15 08:45:01 [INFO] Aggregated 1241 readings — Zone: MH-East | Total: 1,891,234 kWh<br>
2025-11-15 08:30:01 [WARN] 3 tamper alerts detected — forwarding to fraud module<br>
2025-11-15 08:15:01 [INFO] DR push to billing API: 1247 records | Status: 200 OK<br>
</div></div></div></body></html>""")

@app.route("/api/v1/aggregate")
def aggregate():
    return jsonify({"region":"Maharashtra","active_meters":1247,"total_kwh":2412847,"alerts":3,"timestamp":int(time.time())})

@app.route("/api/v1/health")
def health(): return jsonify({"status":"ok","service":"BUNL Metering Data Aggregator","version":"2.4.1"})
if __name__=="__main__": app.run(host="0.0.0.0",port=3000,debug=False)
PYEOF

declare -A SVCS=(
    ["bunl-svc-m4-mtrprov"]="${SVC_DIR}/meter_provisioning.py"
    ["bunl-svc-m4-modbus"]="${SVC_DIR}/modbus_tcp.py"
    ["bunl-svc-m4-dataexport"]="${SVC_DIR}/data_export.py"
    ["bunl-svc-m4-calibration"]="${SVC_DIR}/calibration_portal.py"
    ["bunl-svc-m4-aggregator"]="${SVC_DIR}/aggregator_dash.py"
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
for SVC in "${!SVCS[@]}"; do systemctl enable "${SVC}" --quiet 2>/dev/null || true; systemctl restart "${SVC}" 2>/dev/null || true; done
for PORT in 8083 5020 9004 7445 3000; do ufw allow "${PORT}/tcp" comment "BUNL Ancillary M4" 2>/dev/null || true; done
echo "M4 ancillary services started"
