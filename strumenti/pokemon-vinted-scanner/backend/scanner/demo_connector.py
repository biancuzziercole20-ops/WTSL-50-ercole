"""Connettore DEMO: nessuna richiesta di rete, dati simulati (punto 20)."""
from typing import List
from backend.scanner.base_connector import ConnectorBase, RateLimitedError
from backend.database.models import Listing
from backend.demo_data.generate_demo_listings import generate_demo_listings


class DemoConnector(ConnectorBase):
    name = "demo"

    def __init__(self):
        self._cycle = 0

    def fetch_listings(self, query: dict) -> List[Listing]:
        # Ogni 7° ciclo simula un rate limit per dimostrare che
        # scan_orchestrator gestisce correttamente il backoff (punto 16),
        # anche in modalità demo, senza alcuna rete reale coinvolta.
        if self._cycle > 0 and self._cycle % 7 == 0:
            self._cycle += 1
            raise RateLimitedError("Simulazione demo di HTTP 429 per testare il backoff")

        listings = generate_demo_listings(self._cycle)
        self._cycle += 1
        return listings

    def supports_realtime(self) -> bool:
        return True

    def recommended_min_interval_seconds(self) -> int:
        return 10
