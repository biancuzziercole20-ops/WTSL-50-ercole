"""
Connettore basato su un file di dati che l'utente popola con mezzi leciti:
- copia manuale di annunci trovati navigando Vinted normalmente;
- un'estensione browser personale, usata dall'utente stesso, non
  automatizzata da questo programma;
- un futuro export/feed fornito legittimamente da Vinted o da terzi.

Il file (JSON) deve contenere una lista di oggetti con gli stessi campi
del modello Listing. Vedi demo_data/manual_feed_example.json per un
esempio di formato.

Questo connettore NON effettua alcuna richiesta di rete verso Vinted: si
limita a leggere il file locale indicato in MANUAL_FEED_PATH.
"""
import json
import os
from typing import List
from datetime import datetime, timezone

from backend.scanner.base_connector import ConnectorBase
from backend.database.models import Listing


class ManualFeedConnector(ConnectorBase):
    name = "manual_feed"

    def __init__(self, feed_path: str):
        self.feed_path = feed_path

    def fetch_listings(self, query: dict) -> List[Listing]:
        if not os.path.exists(self.feed_path):
            return []
        with open(self.feed_path, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                return []

        listings = []
        for item in data:
            listings.append(Listing(
                listing_id=item.get("listing_id") or item.get("url", ""),
                url=item.get("url", ""),
                title=item.get("title", ""),
                description=item.get("description", ""),
                price=float(item.get("price", 0)),
                currency=item.get("currency", "EUR"),
                images=item.get("images", []),
                seller=item.get("seller"),
                country=item.get("country"),
                language=item.get("language"),
                posted_at=item.get("posted_at"),
                detected_at=datetime.now(timezone.utc).isoformat(),
                raw_source=item,
            ))
        return listings

    def supports_realtime(self) -> bool:
        return False

    def recommended_min_interval_seconds(self) -> int:
        return 30
