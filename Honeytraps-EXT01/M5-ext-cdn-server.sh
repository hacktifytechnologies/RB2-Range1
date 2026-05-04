#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Run as root." >&2; exit 1; fi
SVC_DIR="/opt/bunl/ancillary/m5"
LOG_DIR="/var/log/bunl/ancillary/m5"
mkdir -p "${SVC_DIR}" "${LOG_DIR}"
pip3 install flask --break-system-packages -q 2>/dev/null || true

# Service 1: Internal File Share (port 8085) — path traversal exploitable
cat > "${SVC_DIR}/file_share.py" << 'PYEOF'
from flask import Flask,request,render_template_string,send_file,jsonify,abort
import logging,os,io
app=Flask(__name__)
LOG_DIR="/var/log/bunl/ancillary/m5"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
SHARE_ROOT="/opt/bunl/cdn-server/share"
os.makedirs(SHARE_ROOT,exist_ok=True)
# Seed some files
for fn,ct in [("policy-IS-2025-009.txt","API Key Rotation Policy\nAll integration keys must be rotated quarterly.\nContact: infra@bunl-internal.net"),
              ("network-topology-v3.txt","BUNL Internal Network Topology v3\nFor internal use only.\nClassification: RESTRICTED"),
              ("readme.txt","BUNL Internal File Share\nAuthorised access only.")]:
    with open(os.path.join(SHARE_ROOT,fn),"w") as f: f.write(ct)

PAGE="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Internal File Share</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}.navbar{background:#5d4037}
.card{border:none;box-shadow:0 1px 4px rgba(0,0,0,.08);border-radius:8px}
.file-row{padding:.5rem 1rem;border-bottom:1px solid #f0f4f8;font-size:.87rem;display:flex;align-items:center;gap:.5rem}
.file-row:hover{background:#f8f9fa}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#128193; BUNL Internal File Share</span></nav>
<div class="container py-3">
<div class="card"><div class="card-header" style="background:#5d4037;color:#fff;font-weight:600;border-radius:8px 8px 0 0">Shared Files — /internal</div>
<div class="card-body p-0">
{% for f in files %}
<div class="file-row">&#128196; <a href="/files/download?path={{ f }}" style="color:#5d4037">{{ f }}</a></div>
{% endfor %}
</div></div>
<div class="mt-3 card"><div class="card-header" style="background:#5d4037;color:#fff;font-weight:600;border-radius:8px 8px 0 0">File Viewer</div>
<div class="card-body">
<form method="GET" class="d-flex gap-2">
<input name="view" class="form-control" placeholder="Enter filename to view..." value="{{ view }}">
<button type="submit" class="btn px-3" style="background:#5d4037;color:#fff">View</button>
</form>
{% if content %}<pre class="mt-3 p-3" style="background:#f8f9fa;border-radius:6px;font-size:.82rem">{{ content }}</pre>{% endif %}
</div></div></div></body></html>"""

@app.route("/")
def index():
    view=request.args.get("view","")
    content=None
    files=[f for f in os.listdir(SHARE_ROOT) if os.path.isfile(os.path.join(SHARE_ROOT,f))]
    if view:
        logging.warning(f"FILESHARE_VIEW|ip={request.remote_addr}|file={view}")
        # Sandboxed path traversal — logs attempt, returns sanitised content
        safe_name=os.path.basename(view)
        fpath=os.path.join(SHARE_ROOT,safe_name)
        if os.path.exists(fpath):
            with open(fpath) as f: content=f.read()
        else:
            content="File not found."
    return render_template_string(PAGE,files=files,view=view,content=content)

@app.route("/files/download")
def download():
    path=request.args.get("path","")
    logging.warning(f"FILESHARE_DL|ip={request.remote_addr}|path={path}")
    safe=os.path.basename(path)
    fpath=os.path.join(SHARE_ROOT,safe)
    if os.path.exists(fpath): return send_file(fpath,as_attachment=True)
    abort(404)

@app.route("/api/v1/health")
def health(): return jsonify({"status":"ok","service":"BUNL Internal File Share"})
if __name__=="__main__": app.run(host="0.0.0.0",port=8085,debug=False)
PYEOF

# Service 2: Static Asset Registry (port 4002) — open directory
cat > "${SVC_DIR}/asset_registry.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify
import logging,time
app=Flask(__name__)
LOG_DIR="/var/log/bunl/ancillary/m5"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
REGISTRY=[
    {"name":"bunl-core.css","size":"48 KB","version":"2.1.0","url":"/assets/bunl-core.css","updated":"2025-10-01"},
    {"name":"bunl-portal.js","size":"124 KB","version":"2.1.0","url":"/assets/bunl-portal.js","updated":"2025-10-01"},
    {"name":"bunl-logo.svg","size":"8 KB","version":"1.0","url":"/assets/bunl-logo.svg","updated":"2025-08-01"},
    {"name":"report-templates.zip","size":"2.3 MB","version":"3.0","url":"/assets/report-templates.zip","updated":"2025-09-15"},
]
PAGE="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL Asset Registry</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}.navbar{background:#0277bd}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#128230; BUNL Static Asset Registry</span></nav>
<div class="container py-3">
<div class="card border-0 shadow-sm rounded-3">
<div class="card-header" style="background:#0277bd;color:#fff;font-weight:600;border-radius:.5rem .5rem 0 0">Registered CDN Assets</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
<thead style="background:#f8f9fa"><tr><th class="ps-3">Filename</th><th>Size</th><th>Version</th><th>URL</th><th>Updated</th></tr></thead>
<tbody>{% for a in assets %}<tr><td class="ps-3">{{ a.name }}</td><td>{{ a.size }}</td><td>{{ a.version }}</td>
<td><a href="{{ a.url }}" style="color:#0277bd;font-size:.8rem"><code>{{ a.url }}</code></a></td><td>{{ a.updated }}</td></tr>{% endfor %}</tbody>
</table></div></div></div></body></html>"""

@app.before_request
def log_r(): logging.warning(f"ASSET_REG|ip={request.remote_addr}|path={request.path}")

@app.route("/")
def index(): return render_template_string(PAGE,assets=REGISTRY)

@app.route("/api/v1/assets")
def assets_api(): return jsonify(REGISTRY)
if __name__=="__main__": app.run(host="0.0.0.0",port=4002,debug=False)
PYEOF

# Service 3: Web Application Firewall Management (port 9005)
cat > "${SVC_DIR}/waf_mgmt.py" << 'PYEOF'
from flask import Flask,request,render_template_string,jsonify,session,redirect
import logging,time
app=Flask(__name__); app.secret_key="waf-mgmt-bunl"
LOG_DIR="/var/log/bunl/ancillary/m5"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
RULES=[
    {"id":"WAF-001","pattern":"UNION SELECT","category":"SQLi","action":"Block","hits":142,"active":True},
    {"id":"WAF-002","pattern":"<script>","category":"XSS","action":"Block","hits":87,"active":True},
    {"id":"WAF-003","pattern":"../","category":"PathTraversal","action":"Log","hits":34,"active":True},
    {"id":"WAF-004","pattern":"xxe","category":"XXE","action":"Block","hits":12,"active":True},
]
LOGIN="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>BUNL WAF Management</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:'Segoe UI',sans-serif}
.box{background:#fff;border-radius:10px;box-shadow:0 4px 20px rgba(0,0,0,.1);width:360px;overflow:hidden}
.bh{background:#b71c1c;color:#fff;padding:1.5rem;text-align:center}.bh h6{font-weight:700;margin:0}
.bb{padding:1.5rem}.btn-danger{background:#b71c1c;border:none}</style></head><body>
<div class="box"><div class="bh"><h6>&#128737; WAF Management Console</h6><small style="color:#ef9a9a">BUNL Network Security</small></div>
<div class="bb">{% if err %}<div class="alert alert-danger py-2 mb-3" style="font-size:.83rem">{{ err }}</div>{% endif %}
<form method="POST"><div class="mb-3"><input name="u" class="form-control" placeholder="Admin username"></div>
<div class="mb-3"><input type="password" name="p" class="form-control" placeholder="Password"></div>
<button type="submit" class="btn btn-danger w-100 fw-bold">Login</button></form></div></div></body></html>"""
DASH="""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>WAF Management</title>
<link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.2/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#f0f4f8;font-family:'Segoe UI',sans-serif}.navbar{background:#b71c1c}</style></head><body>
<nav class="navbar px-3 py-2"><span style="color:#fff;font-weight:700">&#128737; WAF Management Console</span>
<a href="/logout" class="btn btn-sm btn-outline-light ms-auto">Logout</a></nav>
<div class="container py-3"><div class="card border-0 shadow-sm rounded-3">
<div class="card-header" style="background:#b71c1c;color:#fff;font-weight:600;border-radius:.5rem .5rem 0 0">Active WAF Rules</div>
<div class="card-body p-0"><table class="table table-sm mb-0" style="font-size:.85rem">
<thead style="background:#f8f9fa"><tr><th class="ps-3">Rule ID</th><th>Pattern</th><th>Category</th><th>Action</th><th>Hits</th><th>Status</th></tr></thead>
<tbody>{% for r in rules %}<tr><td class="ps-3"><code>{{ r.id }}</code></td><td><code>{{ r.pattern }}</code></td>
<td>{{ r.category }}</td><td><span class="badge bg-{{ 'danger' if r.action=='Block' else 'warning text-dark' }}">{{ r.action }}</span></td>
<td>{{ r.hits }}</td><td><span class="badge bg-{{ 'success' if r.active else 'secondary' }}">{{ 'Active' if r.active else 'Disabled' }}</span></td>
</tr>{% endfor %}</tbody></table></div></div></div></body></html>"""

@app.route("/",methods=["GET","POST"])
def login():
    if "waf_auth" in session: return redirect("/dashboard")
    err=None
    if request.method=="POST":
        u,p=request.form.get("u",""),request.form.get("p","")
        logging.warning(f"WAF_LOGIN|ip={request.remote_addr}|user={u}|pass={p}")
        if p in ("Waf@Bunl2025","admin","netsec123"): session["waf_auth"]=u; return redirect("/dashboard")
        err="Invalid credentials."
    return render_template_string(LOGIN,err=err)

@app.route("/dashboard")
def dashboard():
    if "waf_auth" not in session: return redirect("/")
    return render_template_string(DASH,rules=RULES)

@app.route("/api/v1/rules")
def rules_api():
    logging.warning(f"WAF_RULES_API|ip={request.remote_addr}")
    return jsonify(RULES)

@app.route("/logout")
def logout(): session.clear(); return redirect("/")
if __name__=="__main__": app.run(host="0.0.0.0",port=9005,debug=False)
PYEOF

# Service 4: Certificate Management (port 7446) — info disclosure
cat > "${SVC_DIR}/cert_mgmt.py" << 'PYEOF'
from flask import Flask,request,jsonify,render_template_string
import logging,time
app=Flask(__name__)
LOG_DIR="/var/log/bunl/ancillary/m5"
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
CERTS=[
    {"cn":"*.bunl-internal.net","issuer":"BUNL Internal CA","valid_from":"2025-01-01","valid_to":"2026-01-01","sha256":"ab:cd:ef:12:34:56","status":"valid"},
    {"cn":"cdn-server.bunl-internal.net","issuer":"BUNL Internal CA","valid_from":"2025-03-01","valid_to":"2026-03-01","sha256":"12:34:56:ab:cd:ef","status":"valid"},
    {"cn":"sso.bunl-internal.net","issuer":"BUNL Internal CA","valid_from":"2025-06-01","valid_to":"2026-06-01","sha256":"fe:dc:ba:98:76:54","status":"valid"},
]
@app.before_request
def log_r(): logging.warning(f"CERT_MGMT|ip={request.remote_addr}|path={request.path}")

@app.route("/api/v1/certificates")
def certs(): return jsonify(CERTS)

@app.route("/api/v1/certificates/export")
def export():
    logging.warning(f"CERT_EXPORT|ip={request.remote_addr}|CRITICAL=CERT_ENUM")
    return jsonify({"certs": CERTS, "ca_info": {"cn": "BUNL Internal CA", "org": "Bharat Urja Nigam Limited"}})

@app.route("/")
def index():
    return render_template_string("""<html><body style="font-family:sans-serif;background:#f0f4f8;padding:2rem">
<h5 style="color:#003d7a">BUNL Certificate Management API</h5>
<p style="color:#495057">GET <code>/api/v1/certificates</code> — List all certificates</p>
<p style="color:#495057">GET <code>/api/v1/certificates/export</code> — Export certificate inventory</p>
</body></html>""")
if __name__=="__main__": app.run(host="0.0.0.0",port=7446,debug=False)
PYEOF

# Service 5: TCP FTP Banner (port 21)
cat > "${SVC_DIR}/ftp_tcp.py" << 'PYEOF'
import socket,threading,logging,os
LOG_DIR="/var/log/bunl/ancillary/m5"
os.makedirs(LOG_DIR,exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/services.log",level=logging.WARNING,format="%(asctime)s [SVC] %(message)s")
BANNER=b"220 BUNL CDN FTP Server (vsftpd 3.0.5) Ready\r\n"
def handle(conn,addr):
    logging.warning(f"FTP_PROBE|ip={addr[0]}:{addr[1]}|proto=TCP")
    try:
        conn.sendall(BANNER)
        data=conn.recv(256).decode(errors="ignore").strip()
        logging.warning(f"FTP_CMD|ip={addr[0]}|cmd={data[:60]}")
        if data.upper().startswith("USER"):
            conn.sendall(b"331 Please specify the password.\r\n")
            pwd=conn.recv(128).decode(errors="ignore").strip()
            logging.warning(f"FTP_AUTH|ip={addr[0]}|cmd={pwd[:60]}")
            conn.sendall(b"530 Login incorrect.\r\n")
        else:
            conn.sendall(b"530 Please login with USER and PASS.\r\n")
    except Exception: pass
    finally: conn.close()
def serve():
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    s.bind(("0.0.0.0",21)); s.listen(10)
    while True:
        conn,addr=s.accept()
        threading.Thread(target=handle,args=(conn,addr),daemon=True).start()
if __name__=="__main__": serve()
PYEOF

declare -A SVCS=(
    ["bunl-svc-m5-fileshare"]="${SVC_DIR}/file_share.py"
    ["bunl-svc-m5-assetreg"]="${SVC_DIR}/asset_registry.py"
    ["bunl-svc-m5-wafmgmt"]="${SVC_DIR}/waf_mgmt.py"
    ["bunl-svc-m5-certmgmt"]="${SVC_DIR}/cert_mgmt.py"
    ["bunl-svc-m5-ftp"]="${SVC_DIR}/ftp_tcp.py"
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
for PORT in 8085 4002 9005 7446 21; do ufw allow "${PORT}/tcp" comment "BUNL Ancillary M5" 2>/dev/null || true; done
echo "M5 ancillary services started"
