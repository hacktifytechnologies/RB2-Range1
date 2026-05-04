import os
import time
import json
import logging
import hashlib
import sqlite3
from functools import wraps
from flask import Flask, request, jsonify, g
import graphene

app = Flask(__name__)

LOG_DIR = "/var/log/bunl/billing-api"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=f"{LOG_DIR}/access.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

DB_PATH = os.path.join(os.path.dirname(__file__), "billing.db")

# Per-IP rate limit: 5 staffLogin mutations per minute
# NOTE: Applies per HTTP REQUEST — batch arrays count as one request
RATE_LIMIT_WINDOW = 60
RATE_LIMIT_MAX = 5
_rate_store = {}


def check_rate_limit(ip):
    now = time.time()
    if ip not in _rate_store:
        _rate_store[ip] = []
    _rate_store[ip] = [t for t in _rate_store[ip] if now - t < RATE_LIMIT_WINDOW]
    if len(_rate_store[ip]) >= RATE_LIMIT_MAX:
        return False
    _rate_store[ip].append(now)
    return True


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(e=None):
    db = g.pop("db", None)
    if db:
        db.close()


def hash_password(pw):
    return hashlib.sha256(pw.encode()).hexdigest()


# ── GraphQL Types ─────────────────────────────────────────────

class ConsumerType(graphene.ObjectType):
    consumer_id = graphene.String()
    name = graphene.String()
    division = graphene.String()
    tariff = graphene.String()
    outstanding = graphene.Float()


class StaffUserType(graphene.ObjectType):
    username = graphene.String()
    department = graphene.String()
    role = graphene.String()


class StaffTokenType(graphene.ObjectType):
    token = graphene.String()
    username = graphene.String()
    role = graphene.String()
    expires_in = graphene.Int()


class SystemConfigType(graphene.ObjectType):
    staff_portal_url = graphene.String()
    staff_portal_user = graphene.String()
    staff_portal_pass = graphene.String()
    environment = graphene.String()
    build_version = graphene.String()
    last_sync = graphene.String()


# ── Queries ───────────────────────────────────────────────────

class Query(graphene.ObjectType):
    list_consumers = graphene.List(ConsumerType, api_key=graphene.String(required=True))
    list_staff_users = graphene.List(StaffUserType, api_key=graphene.String(required=True))
    system_config = graphene.Field(SystemConfigType, token=graphene.String(required=True))

    def resolve_list_consumers(root, info, api_key):
        db = get_db()
        row = db.execute("SELECT id FROM api_keys WHERE key_value=? AND active=1", (api_key,)).fetchone()
        if not row:
            raise Exception("Invalid or expired API key.")
        consumers = db.execute("SELECT * FROM consumers").fetchall()
        return [ConsumerType(
            consumer_id=c["consumer_id"], name=c["name"],
            division=c["division"], tariff=c["tariff"],
            outstanding=c["outstanding"]
        ) for c in consumers]

    def resolve_list_staff_users(root, info, api_key):
        db = get_db()
        row = db.execute("SELECT id FROM api_keys WHERE key_value=? AND active=1", (api_key,)).fetchone()
        if not row:
            raise Exception("Invalid or expired API key.")
        staff = db.execute("SELECT username, department, role FROM staff WHERE active=1").fetchall()
        return [StaffUserType(username=s["username"], department=s["department"], role=s["role"]) for s in staff]

    def resolve_system_config(root, info, token):
        db = get_db()
        row = db.execute(
            "SELECT s.username, s.role FROM staff_sessions ss JOIN staff s ON ss.staff_id=s.id WHERE ss.token=? AND ss.expires_at > ?",
            (token, int(time.time()))
        ).fetchone()
        if not row:
            raise Exception("Authentication required.")
        if row["role"] not in ("admin", "ops_manager"):
            raise Exception("Insufficient privileges.")
        return SystemConfigType(
            staff_portal_url="http://auth-portal.bunl-internal.net:5000",
            staff_portal_user="svcananya",
            staff_portal_pass="BunlStaff@2025!",
            environment="production",
            build_version="2.1.4",
            last_sync="2025-11-15 04:00:00 IST"
        )


# ── Mutations ─────────────────────────────────────────────────

class StaffLogin(graphene.Mutation):
    class Arguments:
        username = graphene.String(required=True)
        password = graphene.String(required=True)

    Output = StaffTokenType

    def mutate(root, info, username, password):
        ip = request.remote_addr
        # Rate limit is checked per HTTP request in the view, not here.
        # Individual batch items each call mutate() but the request-level
        # rate check was already passed for the whole batch.
        db = get_db()
        ph = hash_password(password)
        row = db.execute(
            "SELECT id, username, role FROM staff WHERE username=? AND password_hash=? AND active=1",
            (username, ph)
        ).fetchone()
        logging.info(f"STAFF_LOGIN|ip={ip}|user={username}|success={row is not None}")
        if not row:
            raise Exception("Invalid credentials.")
        token = hashlib.sha256(f"{username}{time.time()}{os.urandom(8).hex()}".encode()).hexdigest()
        expires_at = int(time.time()) + 3600
        db.execute(
            "INSERT OR REPLACE INTO staff_sessions (staff_id, token, expires_at) VALUES (?,?,?)",
            (row["id"], token, expires_at)
        )
        db.commit()
        return StaffTokenType(token=token, username=row["username"], role=row["role"], expires_in=3600)


class Mutation(graphene.ObjectType):
    staff_login = StaffLogin.Field()


schema = graphene.Schema(query=Query, mutation=Mutation)


# ── GraphQL endpoint — supports batching ─────────────────────

@app.route("/graphql", methods=["POST", "GET"])
def graphql_endpoint():
    if request.method == "GET":
        return jsonify({
            "service": "BUNL Billing GraphQL API",
            "version": "2.1.4",
            "introspection": True,
            "endpoint": "/graphql"
        })

    try:
        body = request.get_json(force=True)
    except Exception:
        return jsonify({"errors": [{"message": "Invalid JSON"}]}), 400

    ip = request.remote_addr

    # Determine if this is a batch request
    is_batch = isinstance(body, list)
    operations = body if is_batch else [body]

    # Rate limit: applied once per HTTP request regardless of batch size
    has_mutation = any(
        "mutation" in (op.get("query", "") or "").lower()
        for op in operations
    )
    if has_mutation:
        if not check_rate_limit(ip):
            logging.warning(f"RATE_LIMIT_HIT|ip={ip}|batch_size={len(operations)}")
            return jsonify({"errors": [{"message": "Rate limit exceeded. Try again in 60 seconds."}]}), 429

    results = []
    for op in operations:
        query = op.get("query", "")
        variables = op.get("variables") or {}
        operation_name = op.get("operationName")
        try:
            result = schema.execute(query, variable_values=variables, operation_name=operation_name)
            data = {"data": result.data}
            if result.errors:
                data["errors"] = [{"message": str(e)} for e in result.errors]
            results.append(data)
        except Exception as e:
            results.append({"errors": [{"message": str(e)}]})

    logging.info(f"GRAPHQL|ip={ip}|batch={is_batch}|ops={len(operations)}")
    return jsonify(results if is_batch else results[0])


@app.route("/api/v1/health")
def health():
    return jsonify({"status": "ok", "service": "BUNL Billing GraphQL API", "version": "2.1.4"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4000, debug=False)
