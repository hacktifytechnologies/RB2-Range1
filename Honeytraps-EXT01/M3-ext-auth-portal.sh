#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi
SVC_DIR="/opt/bunl/ancillary/m3"
LOG_DIR="/var/log/bunl/ancillary/m3"
mkdir -p "${SVC_DIR}" "${LOG_DIR}"
pip3 install flask --break-system-packages -q 2>/dev/null || true

# Service 1: HR System DISHA Preview (port 8082) — SSTI in search
cat > "${SVC_DIR}/disha_hr.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify,session,redirect
import logging
app=Flask(__name__)
app.secret_key="disha-hr-bunl-sk"
LOG_DIR="/var/log/bunl/ancillary/m3"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
EMPLOYEES=[
    {"id":"EMP-1001","name":"Priya Nair","dept":"IT Security","designation":"CISO","location":"Mumbai HQ"},
    {"id":"EMP-1002","name":"Arun Tiwari","dept":"Operations","designation":"Plant Head","location":"Singrauli"},
    {"id":"EMP-1003","name":"Sunita Rao","dept":"Finance","designation":"CFO","location":"Mumbai HQ"},
    {"id":"EMP-1004","name":"Kiran Joshi","dept":"HR","designation":"HR Manager","location":"Pune"},
]
LOGIN="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>DISHA HR System</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f8f9fa;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:'Segoe UI',sans-serif}
.box{background:#fff;border-radius:10px;box-shadow:0 4px 20px rgba(0,0,0,.1);width:380px;overflow:hidden}
.bh{background:#2e7d32;color:#fff;padding:1.5rem;text-align:center}.bh h6{font-weight:700;margin:0}
.bb{padding:1.5rem}.btn-success{background:#2e7d32;border:none}</style></head><body>
<div class="box"><div class="bh"><h6>&#128101; DISHA — HR Management System</h6><small style="color:#a5d6a7">Bharat Urja Nigam Limited</small></div>
<div class="bb">{% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.83rem">{{ error }}</div>{% endif %}
<form method="POST"><div class="mb-3"><label style="font-size:.83rem;font-weight:600">Employee ID / Username</label>
<input name="u" class="form-control" placeholder="e.g. EMP-1001 or svcananya"></div>
<div class="mb-3"><label style="font-size:.83rem;font-weight:600">Password</label><input type="password" name="p" class="form-control"></div>
<button type="submit" class="btn btn-success w-100">Sign In</button></form></div></div></body></html>"""

DASH="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>DISHA HR</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}.navbar{background:#2e7d32}
.card{border:none;box-shadow:0 1px 4px rgba(0,0,0,.08);border-radius:8px}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#128101; DISHA HR System</span>
<a href="/logout" class="btn btn-sm btn-outline-light ms-auto">Logout</a></nav>
<div class="container py-3">
<form method="GET" class="mb-3 d-flex gap-2"><input name="q" class="form-control" placeholder="Search employees..." value="{{ q }}">
<button type="submit" class="btn btn-success px-3">Search</button></form>
{% if q %}<div class="alert alert-info py-2" style="font-size:.87rem">Search results for: <strong>{{ q }}</strong></div>{% endif %}
<div class="card"><div class="card-header" style="background:#2e7d32;color:#fff;font-weight:600;border-radius:8px 8px 0 0">Employee Directory</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
<thead style="background:#f8f9fa"><tr><th class="ps-3">Emp ID</th><th>Name</th><th>Department</th><th>Designation</th><th>Location</th></tr></thead>
<tbody>{% for e in employees %}<tr><td class="ps-3"><code>{{ e.id }}</code></td><td>{{ e.name }}</td>
<td>{{ e.dept }}</td><td>{{ e.designation }}</td><td>{{ e.location }}</td></tr>{% endfor %}</tbody>
</table></div></div></div></body></html>"""

@app.route("/",methods=["GET","POST"])
def login():
    if "disha_auth" in session: return redirect("/dashboard")
    error=None
    if request.method=="POST":
        u,p=request.form.get("u",""),request.form.get("p","")
        logging.warning(f"DISHA_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        if p in ("Hr@Bunl2025","admin","Disha@123"): session["disha_auth"]=u; return redirect("/dashboard")
        error="Invalid credentials."
    return render_template_string(LOGIN,error=error)

@app.route("/dashboard")
def dashboard():
    if "disha_auth" not in session: return redirect("/")
    q=request.args.get("q","")
    if q and ("{{" in q or "{%" in q):
        logging.warning(f"SSTI_ATTEMPT|ip={request.remote_addr}|payload={q[:100]}")
    filtered=[e for e in EMPLOYEES if q.lower() in e["name"].lower() or q.lower() in e["dept"].lower()] if q else EMPLOYEES
    return render_template_string(DASH,employees=filtered,q=q)

@app.route("/api/v1/employees")
def emp_api():
    logging.warning(f"EMP_API|ip={request.remote_addr}")
    return jsonify(EMPLOYEES)

@app.route("/logout")
def logout():
    session.clear(); return redirect("/")

if __name__=="__main__": app.run(host="0.0.0.0",port=8082,debug=False)
PYEOF

# Service 2: SSO Discovery Document (port 4444) — OIDC metadata
cat > "${SVC_DIR}/sso_discovery.py" << 'PYEOF'
from flask import Flask,request,jsonify,render_template_string
import logging
app=Flask(__name__)
LOG_DIR="/var/log/bunl/ancillary/m3"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")

@app.before_request
def log_r(): logging.warning(f"SSO|ip={request.remote_addr}|path={request.path}")

@app.route("/.well-known/openid-configuration")
def oidc_config():
    base="http://sso.bunl-internal.net:4444"
    return jsonify({"issuer":base,"authorization_endpoint":f"{base}/oauth/authorize",
        "token_endpoint":f"{base}/oauth/token","userinfo_endpoint":f"{base}/userinfo",
        "jwks_uri":f"{base}/.well-known/jwks.json","response_types_supported":["code","token","id_token"],
        "subject_types_supported":["public"],"id_token_signing_alg_values_supported":["RS256","HS256"],
        "scopes_supported":["openid","profile","email","bunl.staff","bunl.admin"]})

@app.route("/.well-known/jwks.json")
def jwks():
    # Fake RSA public key — the HS256/RS256 confusion is the real M3 challenge
    return jsonify({"keys":[{"kty":"RSA","use":"sig","n":"0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw","e":"AQAB","kid":"bunl-sso-2025","alg":"RS256"}]})

@app.route("/oauth/token",methods=["POST"])
def token():
    logging.warning(f"TOKEN_REQUEST|ip={request.remote_addr}|data={request.form.to_dict()}")
    return jsonify({"error":"invalid_client","error_description":"Client authentication failed"}),401

@app.route("/")
def index():
    return render_template_string("""<html><body style="font-family:sans-serif;background:#f0f4f8;padding:2rem">
<h4 style="color:#003d7a">BUNL SSO Identity Provider</h4>
<p style="color:#495057">OIDC discovery: <code>/.well-known/openid-configuration</code></p>
<p style="color:#495057">JWKS: <code>/.well-known/jwks.json</code></p>
</body></html>""")

if __name__=="__main__": app.run(host="0.0.0.0",port=4444,debug=False)
PYEOF

# Service 3: Access Review Portal (port 9003) — IDOR
cat > "${SVC_DIR}/access_review.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify,session,redirect
import logging
app=Flask(__name__)
app.secret_key="access-rev-bunl"
LOG_DIR="/var/log/bunl/ancillary/m3"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
REVIEWS=[
    {"id":1,"user":"svcananya","resource":"billing-api-admin","approved":True,"reviewer":"padmin","date":"2025-10-01"},
    {"id":2,"user":"rktiwari","resource":"ops-dashboard-read","approved":True,"reviewer":"padmin","date":"2025-10-01"},
    {"id":3,"user":"padmin","resource":"all-systems-admin","approved":True,"reviewer":"ciso","date":"2025-09-01"},
    {"id":4,"user":"vendor_ext01","resource":"meter-api-read","approved":False,"reviewer":"padmin","date":"2025-11-01"},
]

@app.route("/")
def login():
    return render_template_string("""<html><body style="font-family:sans-serif;background:#f0f4f8;display:flex;align-items:center;justify-content:center;min-height:100vh">
<div style="background:#fff;border-radius:10px;padding:2rem;width:360px;box-shadow:0 4px 20px rgba(0,0,0,.1)">
<h6 style="color:#003d7a;font-weight:700">&#128274; Access Review Portal</h6>
<form method="POST" action="/login">
<div class="mb-2"><input name="u" style="width:100%;padding:.5rem;border:1px solid #ced4da;border-radius:4px;font-size:.9rem;margin-top:.5rem" placeholder="Staff ID"></div>
<div class="mb-3"><input type="password" name="p" style="width:100%;padding:.5rem;border:1px solid #ced4da;border-radius:4px;font-size:.9rem;margin-top:.5rem" placeholder="Password"></div>
<button type="submit" style="width:100%;padding:.6rem;background:#003d7a;color:#fff;border:none;border-radius:4px;font-weight:700">Login</button>
</form></div></body></html>""")

@app.route("/login",methods=["POST"])
def do_login():
    u,p=request.form.get("u",""),request.form.get("p","")
    logging.warning(f"ACCESS_REVIEW_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
    session["ar_user"]=u; return redirect("/reviews")

@app.route("/reviews")
def reviews():
    if "ar_user" not in session: return redirect("/")
    return jsonify(REVIEWS)

@app.route("/reviews/<int:rid>")
def review_detail(rid):
    logging.warning(f"ACCESS_IDOR|ip={request.remote_addr}|id={rid}")
    for r in REVIEWS:
        if r["id"]==rid: return jsonify(r)
    return jsonify({"error":"not found"}),404

if __name__=="__main__": app.run(host="0.0.0.0",port=9003,debug=False)
PYEOF

# Service 4: Audit Log Viewer (port 7444) — path traversal
cat > "${SVC_DIR}/audit_log_viewer.py" << 'PYEOF'
from flask import Flask,request,render_template_string,send_file,jsonify
import logging,io,os
app=Flask(__name__)
LOG_DIR="/var/log/bunl/ancillary/m3"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
LOGS_DIR="/var/log/bunl"
SAMPLE=["2025-11-15 08:42:11 LOGIN_SUCCESS user=padmin ip=10.0.0.5",
        "2025-11-15 08:30:01 CONFIG_VIEW user=svcananya ip=10.0.0.8",
        "2025-11-14 22:01:44 SESSION_EXPIRED user=rktiwari",
        "2025-11-14 18:30:12 PASSWORD_CHANGED user=padmin"]

PAGE="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Audit Log Viewer</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}.navbar{background:#003d7a}
.card{border:none;box-shadow:0 1px 4px rgba(0,0,0,.08);border-radius:8px}
.log-line{font-family:monospace;font-size:.8rem;padding:2px 0;border-bottom:1px solid #f0f4f8;color:#2d3748}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#128196; BUNL Audit Log Viewer</span></nav>
<div class="container py-3">
<div class="card mb-3"><div class="card-header" style="background:#003d7a;color:#fff;font-weight:600;border-radius:8px 8px 0 0">
Log File Viewer</div>
<div class="card-body">
<form method="GET" class="d-flex gap-2 mb-3">
  <input name="file" class="form-control" placeholder="Log file (e.g. auth-portal/access.log)" value="{{ file }}">
  <button class="btn btn-primary px-3">View</button>
  <a href="/logs/download?file={{ file }}" class="btn btn-outline-secondary px-3">&#8595; Download</a>
</form>
{% if lines %}<div>{% for l in lines %}<div class="log-line">{{ l }}</div>{% endfor %}</div>{% endif %}
</div></div></div></body></html>"""

@app.route("/",methods=["GET"])
def viewer():
    f=request.args.get("file","")
    logging.warning(f"AUDIT_VIEW|ip={request.remote_addr}|file={f}")
    lines=SAMPLE
    if f and ".." in f:
        logging.warning(f"PATH_TRAVERSAL|ip={request.remote_addr}|file={f}")
    return render_template_string(PAGE,file=f,lines=lines)

@app.route("/logs/download")
def download():
    f=request.args.get("file","audit")
    logging.warning(f"AUDIT_DOWNLOAD|ip={request.remote_addr}|file={f}")
    if ".." in f or f.startswith("/"): return "Access denied.",403
    content="\n".join(SAMPLE)
    return send_file(io.BytesIO(content.encode()),mimetype="text/plain",as_attachment=True,download_name=f"{f}.log")

@app.route("/api/v1/health")
def health(): return jsonify({"status":"ok","service":"BUNL Audit Log Viewer"})

if __name__=="__main__": app.run(host="0.0.0.0",port=7444,debug=False)
PYEOF

# Service 5: VPN Client Portal (port 8444) — default creds
cat > "${SVC_DIR}/vpn_portal.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify,session,redirect
import logging
app=Flask(__name__)
app.secret_key="vpn-bunl-sk-x9"
LOG_DIR="/var/log/bunl/ancillary/m3"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")

PAGE="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL VPN Portal</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#1a1a2e;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:'Segoe UI',sans-serif}
.box{background:#16213e;border:1px solid #0f3460;border-radius:12px;width:400px;overflow:hidden}
.bh{background:#0f3460;padding:1.5rem;text-align:center}.bh h6{color:#e94560;font-weight:700;margin:0}
.bb{padding:1.5rem}.form-control{background:#1a1a2e;border-color:#0f3460;color:#e2e8f0}
.form-control:focus{background:#1a1a2e;color:#e2e8f0;border-color:#e94560;box-shadow:none}
.form-label{color:#94a3b8;font-size:.83rem}.btn-danger{background:#e94560;border:none}
.notice{background:#0f3460;border-radius:6px;padding:.6rem 1rem;color:#94a3b8;font-size:.78rem;margin-top:.8rem}
{% if logged_in %}.status-box{background:#0f3460;border-radius:8px;padding:1.5rem;color:#e2e8f0}{% endif %}</style></head><body>
<div class="box"><div class="bh"><h6>&#128274; BUNL Corporate VPN</h6><small style="color:#94a3b8">Remote Access Gateway — Authorised Users Only</small></div>
<div class="bb">
{% if not logged_in %}
{% if error %}<div class="alert alert-danger py-2 mb-3" style="font-size:.83rem">{{ error }}</div>{% endif %}
<form method="POST">
<div class="mb-3"><label class="form-label">Username</label><input name="u" class="form-control" placeholder="Staff username"></div>
<div class="mb-3"><label class="form-label">Password</label><input type="password" name="p" class="form-control"></div>
<button type="submit" class="btn btn-danger w-100 fw-bold">Connect</button></form>
<div class="notice">New employees: use your staff ID as username and <strong>Bunl@VPN1</strong> as password. Change after first login.</div>
{% else %}
<div class="status-box"><div style="color:#22c55e;font-weight:700;margin-bottom:.5rem">&#10003; VPN Connected</div>
<div style="font-size:.85rem">Assigned IP: 10.200.{{ range(10,200)|random }}.{{ range(2,254)|random }}</div>
<div style="font-size:.83rem;color:#94a3b8;margin-top:.3rem">Gateway: vpn-gw.bunl-internal.net | Protocol: OpenVPN</div>
<a href="/disconnect" class="btn btn-outline-danger btn-sm mt-2 w-100">Disconnect</a>
</div>{% endif %}
</div></div></body></html>"""

@app.route("/",methods=["GET","POST"])
def vpn():
    if "vpn_auth" in session: return render_template_string(PAGE,logged_in=True)
    error=None
    if request.method=="POST":
        u,p=request.form.get("u",""),request.form.get("p","")
        logging.warning(f"VPN_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        if p in ("Bunl@VPN1","vpn123","admin"): session["vpn_auth"]=u; return render_template_string(PAGE,logged_in=True)
        error="Authentication failed. Check credentials."
    return render_template_string(PAGE,logged_in=False,error=error)

@app.route("/disconnect")
def disconnect():
    session.clear(); return redirect("/")

@app.route("/api/v1/health")
def health(): return jsonify({"status":"ok","service":"BUNL VPN Gateway"})

if __name__=="__main__": app.run(host="0.0.0.0",port=8444,debug=False)
PYEOF

# Service 6: LDAP Banner TCP (port 389)
cat > "${SVC_DIR}/ldap_tcp.py" << 'PYEOF'
import socket,threading,logging,os
LOG_DIR="/var/log/bunl/ancillary/m3"
os.makedirs(LOG_DIR,exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
LDAP_ERR=(b"\x30\x0c\x02\x01\x01\x61\x07\x0a\x01\x31\x04\x00\x04\x00")

def handle(conn,addr):
    logging.warning(f"LDAP_PROBE|ip={addr[0]}:{addr[1]}|proto=TCP")
    try:
        data=conn.recv(512)
        logging.warning(f"LDAP_DATA|ip={addr[0]}|bytes={len(data)}|data={data[:40]!r}")
        conn.sendall(LDAP_ERR)
    except Exception: pass
    finally: conn.close()

def serve():
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    s.bind(("0.0.0.0",389)); s.listen(10)
    while True:
        conn,addr=s.accept()
        threading.Thread(target=handle,args=(conn,addr),daemon=True).start()

if __name__=="__main__": serve()
PYEOF

declare -A SVCS=(
    ["bunl-svc-m3-disha"]="${SVC_DIR}/disha_hr.py"
    ["bunl-svc-m3-sso"]="${SVC_DIR}/sso_discovery.py"
    ["bunl-svc-m3-accessrev"]="${SVC_DIR}/access_review.py"
    ["bunl-svc-m3-auditlog"]="${SVC_DIR}/audit_log_viewer.py"
    ["bunl-svc-m3-vpn"]="${SVC_DIR}/vpn_portal.py"
    ["bunl-svc-m3-ldap"]="${SVC_DIR}/ldap_tcp.py"
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
for PORT in 8082 4444 9003 7444 8444 389; do ufw allow "${PORT}/tcp" comment "BUNL Ancillary M3" 2>/dev/null || true; done
echo "M3 ancillary services started: 8082 9003 4444 7444 8444 389"
