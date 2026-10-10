# db.py
import sqlite3
from config import Config

SCHEMA = """
CREATE TABLE IF NOT EXISTS campaigns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    message TEXT NOT NULL,
    is_flash INTEGER DEFAULT 1,
    provider TEXT NOT NULL,
    provider_mode TEXT DEFAULT '',
    status TEXT DEFAULT 'pending',
    total INTEGER DEFAULT 0,
    sent INTEGER DEFAULT 0,
    failed INTEGER DEFAULT 0,
    pending INTEGER DEFAULT 0,
    schedule_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    started_at TEXT,
    finished_at TEXT
);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id INTEGER NOT NULL,
    phone TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    provider_msg_id TEXT,
    error TEXT,
    retries INTEGER DEFAULT 0,
    sent_at TEXT,
    FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_msg_campaign_status ON messages(campaign_id, status);
CREATE INDEX IF NOT EXISTS idx_campaign_status ON campaigns(status);
"""

def get_db():
    conn = sqlite3.connect(Config.DATABASE, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn

def init_db():
    conn = get_db()
    conn.executescript(SCHEMA)
    conn.commit()
    conn.close()
