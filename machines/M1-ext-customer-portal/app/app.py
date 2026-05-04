import os
import logging
from flask import Flask, request, session, redirect, url_for, render_template, flash
from lxml import etree
from functools import wraps
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get("APP_SECRET", "bunl-csp-2025-k9m3")

LOG_DIR = "/var/log/bunl/customer-portal"
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    filename=f"{LOG_DIR}/access.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

XML_DB = os.path.join(os.path.dirname(__file__), "users.xml")


def load_xml():
    parser = etree.XMLParser(resolve_entities=True, no_network=False)
    tree = etree.parse(XML_DB, parser)
    return tree.getroot()


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "username" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if session.get("role") != "admin":
            flash("Insufficient privileges.", "danger")
            return redirect(url_for("dashboard"))
        return f(*args, **kwargs)
    return decorated


@app.route("/", methods=["GET"])
def index():
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        ip = request.remote_addr

        logging.info(f"LOGIN_ATTEMPT|ip={ip}|user={username}")

        try:
            root = load_xml()
            # Vulnerable XPath — user input directly interpolated
            xpath_expr = f"//users/user[username/text()='{username}' and password/text()='{password}']"
            result = root.xpath(xpath_expr)
        except etree.XPathEvalError as e:
            logging.warning(f"XPATH_ERROR|ip={ip}|expr={xpath_expr}|error={e}")
            flash("An error occurred during authentication.", "danger")
            return render_template("login.html")

        if result:
            user_node = result[0]
            role_nodes = user_node.xpath("role/text()")
            uname_nodes = user_node.xpath("username/text()")
            session["username"] = uname_nodes[0] if uname_nodes else username
            session["role"] = role_nodes[0] if role_nodes else "customer"
            logging.info(f"LOGIN_SUCCESS|ip={ip}|user={session['username']}|role={session['role']}")
            if session["role"] == "admin":
                return redirect(url_for("admin_panel"))
            return redirect(url_for("dashboard"))
        else:
            logging.warning(f"LOGIN_FAILURE|ip={ip}|user={username}")
            flash("Invalid credentials. Please try again.", "danger")

    return render_template("login.html")


@app.route("/dashboard")
@login_required
def dashboard():
    account_data = {
        "name": "Prakash Mehta",
        "account_id": "BUNL-CG-2023-00847",
        "connection_type": "Domestic LT Supply",
        "sanctioned_load": "5 kW",
        "tariff": "LT-I (Domestic)",
        "discom": "BUNL Power Distribution Ltd.",
        "division": "Mumbai Urban – Zone 3",
    }
    bills = [
        {"month": "October 2025", "units": 312, "amount": "₹2,184", "status": "Paid", "due": "15 Nov 2025"},
        {"month": "September 2025", "units": 287, "amount": "₹2,009", "status": "Paid", "due": "15 Oct 2025"},
        {"month": "August 2025", "units": 345, "amount": "₹2,415", "status": "Paid", "due": "15 Sep 2025"},
        {"month": "July 2025", "units": 398, "amount": "₹2,786", "status": "Paid", "due": "15 Aug 2025"},
    ]
    return render_template("dashboard.html", account=account_data, bills=bills,
                           username=session.get("username"))


@app.route("/profile")
@login_required
def profile():
    return render_template("profile.html", username=session.get("username"))


@app.route("/new-connection")
@login_required
def new_connection():
    return render_template("new_connection.html", username=session.get("username"))


@app.route("/complaints")
@login_required
def complaints():
    return render_template("complaints.html", username=session.get("username"))


@app.route("/admin")
@login_required
@admin_required
def admin_panel():
    root = load_xml()
    users = []
    for u in root.xpath("//users/user"):
        users.append({
            "username": (u.xpath("username/text()") or [""])[0],
            "role": (u.xpath("role/text()") or [""])[0],
            "account_id": (u.xpath("account_id/text()") or [""])[0],
        })

    system_config = {
        "billing_api_endpoint": "http://billing-api.bunl-internal.net:4000/graphql",
        "billing_api_key": "gql-key-b2f4a8c3e9d1f7b5",
        "portal_version": "3.2.1",
        "environment": "production",
        "last_sync": "2025-11-15 04:00:00 IST",
        "db_host": "localhost",
        "cache_host": "cache-01.bunl-internal.net",
    }
    return render_template("admin.html", users=users, config=system_config,
                           username=session.get("username"))


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/api/v1/health")
def health():
    return {"status": "ok", "service": "BUNL Customer Self-Service Portal", "version": "3.2.1"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
