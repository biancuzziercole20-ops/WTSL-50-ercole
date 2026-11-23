"""
Repository: incapsula tutte le query SQL.

Contiene la logica di deduplica (punto 11 della spec):
- un annuncio già visto viene aggiornato, non duplicato;
- una nuova notifica viene inviata solo se: annuncio nuovo, prezzo cambiato
  significativamente (>=5%), stato/disponibilità cambiati, o informazioni
  importanti cambiate (carta identificata diversa, ecc).
"""
import json
from datetime import datetime, timezone
from typing import Optional, List
from backend.database.db import get_connection
from backend.database.models import DealResult

PRICE_CHANGE_THRESHOLD = 0.05  # 5%


def _now():
    return datetime.now(timezone.utc).isoformat()


def _card_key(ident) -> str:
    return "|".join([
        (ident.pokemon_name or "?").lower(),
        (ident.set_name or "?").lower(),
        (ident.card_number or "?").lower(),
        (ident.language or "?").lower(),
    ])


class ScanRepository:
    def __init__(self, db_path: str):
        self.db_path = db_path

    @property
    def conn(self):
        return get_connection(self.db_path)

    # ---------------------------------------------------------------- #
    # Listings / dedup
    # ---------------------------------------------------------------- #
    def upsert_deal(self, deal: DealResult) -> str:
        """
        Inserisce o aggiorna un annuncio. Restituisce una delle stringhe:
        'new', 'price_changed', 'unchanged', 'info_changed'
        — usata dal notification manager per decidere se notificare.
        """
        listing = deal.listing
        ident = deal.identification
        row = self.conn.execute(
            "SELECT * FROM listings WHERE listing_id=?", (listing.listing_id,)
        ).fetchone()

        now = _now()
        result_kind = "new"

        if row is None:
            self.conn.execute(
                """INSERT INTO listings (
                    listing_id, url, title, description, price, currency, images,
                    seller, country, language, posted_at, first_seen_at, last_seen_at,
                    pokemon_name, card_name, set_name, card_number, variant, card_type,
                    card_language, year, rarity, grading_company, grading_score,
                    condition, defects, text_confidence, image_confidence, confidence,
                    uncertain, market_value, market_basis, market_sample_size,
                    discount_percentage, deal_score, priority, is_opportunity,
                    fraud_flags, status, last_notified_price, last_notified_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    listing.listing_id, listing.url, listing.title, listing.description,
                    listing.price, listing.currency, json.dumps(listing.images),
                    listing.seller, listing.country, listing.language, listing.posted_at,
                    now, now,
                    ident.pokemon_name, ident.card_name, ident.set_name, ident.card_number,
                    ident.variant, ident.card_type, ident.language, ident.year, ident.rarity,
                    ident.grading_company, ident.grading_score, ident.condition,
                    json.dumps(ident.defects), ident.text_confidence, ident.image_confidence,
                    ident.confidence, int(ident.uncertain),
                    deal.market_value.estimated_value, deal.market_value.basis,
                    deal.market_value.sample_size,
                    deal.discount_percentage, deal.deal_score, deal.priority,
                    int(deal.is_opportunity), json.dumps(deal.fraud_flags),
                    "active", None, None,
                ),
            )
            result_kind = "new"
        else:
            old_price = row["price"]
            old_ident_key = (row["pokemon_name"], row["set_name"], row["card_number"])
            new_ident_key = (ident.pokemon_name, ident.set_name, ident.card_number)

            price_changed = old_price and abs(listing.price - old_price) / max(old_price, 1e-6) >= PRICE_CHANGE_THRESHOLD
            info_changed = old_ident_key != new_ident_key

            self.conn.execute(
                """UPDATE listings SET price=?, last_seen_at=?, status='active',
                   market_value=?, discount_percentage=?, deal_score=?, priority=?,
                   is_opportunity=?, fraud_flags=?, pokemon_name=?, set_name=?, card_number=?
                   WHERE listing_id=?""",
                (
                    listing.price, now, deal.market_value.estimated_value,
                    deal.discount_percentage, deal.deal_score, deal.priority,
                    int(deal.is_opportunity), json.dumps(deal.fraud_flags),
                    ident.pokemon_name, ident.set_name, ident.card_number,
                    listing.listing_id,
                ),
            )
            if price_changed:
                result_kind = "price_changed"
            elif info_changed:
                result_kind = "info_changed"
            else:
                result_kind = "unchanged"

        # storico prezzi per la carta (indipendentemente dal dedup dell'annuncio)
        self.conn.execute(
            "INSERT INTO price_history (listing_id, card_key, price, market_value, recorded_at) VALUES (?,?,?,?,?)",
            (listing.listing_id, _card_key(ident), listing.price, deal.market_value.estimated_value, now),
        )
        self.conn.commit()
        return result_kind

    def mark_notified(self, listing_id: str, price: float):
        self.conn.execute(
            "UPDATE listings SET last_notified_price=?, last_notified_at=? WHERE listing_id=?",
            (price, _now(), listing_id),
        )
        self.conn.commit()

    def should_notify(self, listing_id: str, price: float, result_kind: str) -> bool:
        """Regola anti-spam: notifica solo su new/price_changed/info_changed,
        e mai più di una volta per lo stesso identico prezzo."""
        if result_kind == "unchanged":
            return False
        row = self.conn.execute(
            "SELECT last_notified_price FROM listings WHERE listing_id=?", (listing_id,)
        ).fetchone()
        if row is None:
            return True
        if row["last_notified_price"] is not None and abs(row["last_notified_price"] - price) < 1e-6:
            return False
        return True

    def get_opportunities(self, limit: int = 200) -> List[dict]:
        rows = self.conn.execute(
            "SELECT * FROM listings WHERE is_opportunity=1 AND status='active' "
            "ORDER BY deal_score DESC, discount_percentage DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]

    def get_history_for_card(self, pokemon_name: str, set_name: Optional[str] = None,
                              card_number: Optional[str] = None) -> List[dict]:
        q = "SELECT * FROM price_history WHERE card_key LIKE ? ORDER BY recorded_at DESC LIMIT 100"
        key_prefix = f"{pokemon_name.lower()}%"
        rows = self.conn.execute(q, (key_prefix,)).fetchall()
        return [dict(r) for r in rows]

    def all_listings(self, limit=500):
        rows = self.conn.execute(
            "SELECT * FROM listings ORDER BY last_seen_at DESC LIMIT ?", (limit,)
        ).fetchall()
        return [dict(r) for r in rows]

    # ---------------------------------------------------------------- #
    # Stats / stato scanner
    # ---------------------------------------------------------------- #
    def increment_analyzed(self, n: int = 1):
        self.conn.execute(
            "UPDATE scan_stats SET listings_analyzed = listings_analyzed + ? WHERE id=1", (n,)
        )
        self.conn.commit()

    def increment_opportunities(self, n: int = 1):
        self.conn.execute(
            "UPDATE scan_stats SET opportunities_found = opportunities_found + ? WHERE id=1", (n,)
        )
        self.conn.commit()

    def update_scan_timing(self, last_check, next_check, interval, status):
        self.conn.execute(
            "UPDATE scan_stats SET last_check_at=?, next_check_at=?, current_interval=?, scanner_status=? WHERE id=1",
            (last_check, next_check, interval, status),
        )
        self.conn.commit()

    def get_stats(self) -> dict:
        row = self.conn.execute("SELECT * FROM scan_stats WHERE id=1").fetchone()
        return dict(row) if row else {}

    # ---------------------------------------------------------------- #
    # Log
    # ---------------------------------------------------------------- #
    def log(self, level: str, message: str):
        self.conn.execute(
            "INSERT INTO scan_log (timestamp, level, message) VALUES (?,?,?)",
            (_now(), level, message),
        )
        self.conn.commit()

    def get_logs(self, limit: int = 200) -> List[dict]:
        rows = self.conn.execute(
            "SELECT * FROM scan_log ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return [dict(r) for r in rows]

    # ---------------------------------------------------------------- #
    # Settings override (per modifica da dashboard)
    # ---------------------------------------------------------------- #
    def get_settings_overrides(self) -> dict:
        rows = self.conn.execute("SELECT key, value FROM settings_overrides").fetchall()
        out = {}
        for r in rows:
            try:
                out[r["key"]] = json.loads(r["value"])
            except (json.JSONDecodeError, TypeError):
                out[r["key"]] = r["value"]
        return out

    def set_settings_override(self, key: str, value):
        self.conn.execute(
            "INSERT INTO settings_overrides (key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, json.dumps(value)),
        )
        self.conn.commit()
