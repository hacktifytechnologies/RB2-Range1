import os
import logging
from flask import Flask, request, session, redirect, url_for, render_template, flash, g
import sqlite3
import hashlib
from functools import wraps

app = Flask(__name__)
# Weak secret key — crackable with flask-unsign + rockyou wordlist
app.secret_key = "letmein"

LOG_DIR = "/var/log/bunl/auth-portal"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=f"{LOG_DIR}/access.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

DB_PATH = os.path.join(os.path.dirname(__file__), "staff.db")

METER_API_CONFIG = {
    "endpoint": "http://meter-api.bunl-internal.net:8000/api/meter/submit",
    "api_key": "soap-9f3b2d1e7a8c4f6d",
    "environment": "production",
    "discom": "BUNL Power Distribution Ltd.",
}

def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db

@app.teardown_appcontext
def close_db(e=None):
    db = g.pop("db", None)
    if db: db.close()

def hash_password(pw):
    return hashlib.sha256(pw.encode()).hexdigest()

def login_required(f):
    @wraps(f)
    def dec(*a, **kw):
        if "staff_user" not in session:
            return redirect(url_for("login"))
        return f(*a, **kw)
    return dec

def admin_required(f):
    @wraps(f)
    def dec(*a, **kw):
        if session.get("role") != "admin":
            flash("This section requires administrative privileges.", "danger")
            return redirect(url_for("dashboard"))
        return f(*a, **kw)
    return dec

@app.route("/")
def index():
    return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        ip = request.remote_addr
        db = get_db()
        ph = hash_password(password)
        row = db.execute(
            "SELECT username, role, full_name, department FROM staff WHERE username=? AND password_hash=? AND active=1",
            (username, ph)
        ).fetchone()
        logging.info(f"LOGIN|ip={ip}|user={username}|ok={row is not None}")
        if row:
            session["staff_user"] = row["username"]
            session["role"] = row["role"]
            session["full_name"] = row["full_name"]
            session["department"] = row["department"]
            return redirect(url_for("admin_panel") if row["role"] == "admin" else url_for("dashboard"))
        flash("Invalid credentials. Please contact IT Helpdesk if you need assistance.", "danger")
    return render_template("login.html")

@app.route("/dashboard")
@login_required
def dashboard():
    db = get_db()
    notices = db.execute("SELECT * FROM notices ORDER BY posted_at DESC LIMIT 5").fetchall()
    return render_template("dashboard.html", notices=notices)

@app.route("/admin")
@login_required
@admin_required
def admin_panel():
    db = get_db()
    staff_list = db.execute("SELECT username, full_name, department, role, active FROM staff").fetchall()
    return render_template("admin.html", staff_list=staff_list, meter_config=METER_API_CONFIG)

@app.route("/profile")
@login_required
def profile():
    return render_template("profile.html")

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/api/v1/health")
def health():
    return {"status": "ok", "service": "BUNL Staff Authentication Portal", "version": "1.8.2"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
