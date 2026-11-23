"""Inizializzazione e connessione al database SQLite."""
import sqlite3
import os
import threading

_local = threading.local()

SCHEMA = """
CREATE TABLE IF NOT EXISTS listings (
    listing_id TEXT PRIMARY KEY,
    url TEXT NOT NULL,
    title TEXT,
    description TEXT,
    price REAL,
    currency TEXT,
    images TEXT,               -- JSON list
    seller TEXT,
    country TEXT,
    language TEXT,
    posted_at TEXT,
    first_seen_at TEXT,
    last_seen_at TEXT,

    pokemon_name TEXT,
    card_name TEXT,
    set_name TEXT,
    card_number TEXT,
    variant TEXT,
    card_type TEXT,
    card_language TEXT,
    year INTEGER,
    rarity TEXT,
    grading_company TEXT,
    grading_score TEXT,
    condition TEXT,
    defects TEXT,               -- JSON list
    text_confidence REAL,
    image_confidence REAL,
    confidence REAL,
    uncertain INTEGER,

    market_value REAL,
    market_basis TEXT,
    market_sample_size INTEGER,

    discount_percentage REAL,
    deal_score REAL,
    priority TEXT,
    is_opportunity INTEGER,
    fraud_flags TEXT,           -- JSON list

    status TEXT DEFAULT 'active',   -- active | gone | price_changed
    last_notified_price REAL,
    last_notified_at TEXT
);

CREATE TABLE IF NOT EXISTS price_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    listing_id TEXT,
    card_key TEXT,              -- chiave logica carta: nome|set|numero|lingua
    price REAL,
    market_value REAL,
    recorded_at TEXT,
    FOREIGN KEY (listing_id) REFERENCES listings(listing_id)
);

CREATE TABLE IF NOT EXISTS scan_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT,
    level TEXT,                 -- INFO | WARNING | ERROR
    message TEXT
);

CREATE TABLE IF NOT EXISTS settings_overrides (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS scan_stats (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    listings_analyzed INTEGER DEFAULT 0,
    opportunities_found INTEGER DEFAULT 0,
    last_check_at TEXT,
    next_check_at TEXT,
    current_interval INTEGER,
    scanner_status TEXT DEFAULT 'STOPPED'
);

CREATE INDEX IF NOT EXISTS idx_listings_card ON listings(pokemon_name, set_name, card_number);
"""


def get_connection(db_path: str) -> sqlite3.Connection:
    """Restituisce una connessione SQLite per-thread (necessario perché il
    backend gira su uno scheduler in background separato dal thread delle
    richieste HTTP)."""
    if not hasattr(_local, "conn") or getattr(_local, "db_path", None) != db_path:
        os.makedirs(os.path.dirname(os.path.abspath(db_path)) or ".", exist_ok=True)
        conn = sqlite3.connect(db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL;")
        _local.conn = conn
        _local.db_path = db_path
    return _local.conn


def init_db(db_path: str):
    conn = get_connection(db_path)
    conn.executescript(SCHEMA)
    conn.execute(
        "INSERT OR IGNORE INTO scan_stats (id, listings_analyzed, opportunities_found, current_interval, scanner_status) "
        "VALUES (1, 0, 0, 10, 'STOPPED')"
    )
    conn.commit()
    return conn
