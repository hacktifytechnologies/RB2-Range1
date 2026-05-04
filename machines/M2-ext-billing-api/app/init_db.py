#!/usr/bin/env python3
"""Initialize the BUNL Billing API SQLite database."""
import sqlite3
import hashlib
import os

DB_PATH = os.path.join(os.path.dirname(__file__), "billing.db")


def hash_password(pw):
    return hashlib.sha256(pw.encode()).hexdigest()


def init():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.executescript("""
    CREATE TABLE IF NOT EXISTS api_keys (
        id INTEGER PRIMARY KEY,
        key_value TEXT UNIQUE NOT NULL,
        label TEXT,
        active INTEGER DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS consumers (
        id INTEGER PRIMARY KEY,
        consumer_id TEXT,
        name TEXT,
        division TEXT,
        tariff TEXT,
        outstanding REAL
    );

    CREATE TABLE IF NOT EXISTS staff (
        id INTEGER PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        department TEXT,
        role TEXT,
        active INTEGER DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS staff_sessions (
        staff_id INTEGER,
        token TEXT PRIMARY KEY,
        expires_at INTEGER
    );
    """)

    # API keys — M1 admin panel reveals this key
    c.execute("INSERT OR IGNORE INTO api_keys (key_value, label) VALUES (?, ?)",
              ("gql-key-b2f4a8c3e9d1f7b5", "Customer Portal Integration — IS-2025-009"))
    c.execute("INSERT OR IGNORE INTO api_keys (key_value, label, active) VALUES (?, ?, ?)",
              ("gql-key-deprecated-2024", "Legacy portal key (deactivated)", 0))

    # Consumers
    consumers = [
        ("BUNL-CG-2023-00847", "Prakash Mehta", "Mumbai Urban Zone 3", "LT-I Domestic", 2184.00),
        ("BUNL-CG-2022-01293", "Anita Singh", "Pune West Zone 1", "LT-II Commercial", 8720.50),
        ("BUNL-CG-2021-00512", "Rajesh Tiwari", "Nagpur Zone 2", "LT-I Domestic", 0.00),
        ("BUNL-AG-2020-00128", "Suresh Patil", "Nashik Rural", "LT-IV Agriculture", 4100.00),
    ]
    for con in consumers:
        c.execute("INSERT OR IGNORE INTO consumers (consumer_id,name,division,tariff,outstanding) VALUES (?,?,?,?,?)", con)

    # Staff accounts — padmin:password is the one batchbruted
    staff = [
        ("svcananya", hash_password("BunlStaff@2025!"), "IT Operations", "ops_manager"),
        ("rktiwari", hash_password("Mgr@Bunl#Ops7"), "Billing Operations", "billing_admin"),
        ("padmin", hash_password("password"), "IT Administration", "admin"),
    ]
    for s in staff:
        c.execute("INSERT OR IGNORE INTO staff (username,password_hash,department,role) VALUES (?,?,?,?)", s)

    conn.commit()
    conn.close()
    print("[OK] Database initialized.")
    os.chmod(DB_PATH, 0o640)


if __name__ == "__main__":
    init()
