#!/usr/bin/env python3
import sqlite3, hashlib, os
DB_PATH = os.path.join(os.path.dirname(__file__), "staff.db")

def hash_password(pw): return hashlib.sha256(pw.encode()).hexdigest()

def init():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.executescript("""
    CREATE TABLE IF NOT EXISTS staff (
        id INTEGER PRIMARY KEY,
        username TEXT UNIQUE,
        password_hash TEXT,
        full_name TEXT,
        department TEXT,
        role TEXT,
        active INTEGER DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS notices (
        id INTEGER PRIMARY KEY,
        title TEXT,
        body TEXT,
        posted_by TEXT,
        posted_at TEXT
    );
    """)
    staff = [
        ("svcananya", hash_password("BunlStaff@2025!"), "Sonal Vaidya-Cananya", "IT Operations", "staff"),
        ("rktiwari", hash_password("Mgr@Bunl#Ops7"), "Rajesh Kumar Tiwari", "Operations", "staff"),
        ("padmin", hash_password("password"), "Portal Administrator", "IT Administration", "admin"),
    ]
    for s in staff:
        c.execute("INSERT OR IGNORE INTO staff (username,password_hash,full_name,department,role) VALUES (?,?,?,?,?)", s)
    notices = [
        ("Scheduled Maintenance — 16 Nov", "The billing integration API will be unavailable from 02:00–04:00 IST for routine maintenance. Please plan accordingly.", "padmin", "2025-11-15 10:00:00"),
        ("IS-2025-009 — API Key Rotation Reminder", "Staff are reminded to rotate integration API keys as per IS-2025-009 policy. Refer to Admin Panel for current keys.", "padmin", "2025-11-12 09:00:00"),
        ("Meter Data Exchange Upgrade", "The SOAP-based meter data exchange API has been upgraded to v2. Staff in metering divisions should refer to the admin panel for updated endpoint details.", "padmin", "2025-11-08 14:00:00"),
    ]
    for n in notices:
        c.execute("INSERT OR IGNORE INTO notices (title,body,posted_by,posted_at) VALUES (?,?,?,?)", n)
    conn.commit(); conn.close()
    os.chmod(DB_PATH, 0o640)
    print("[OK] Staff DB initialized.")

if __name__ == "__main__": init()
