"""
Orchestratore dello scanner (punti 1, 16, 21 della spec).

Gira in un thread separato, esegue un ciclo di scansione ogni
`scan_interval` secondi, e implementa:
- backoff automatico su rate limit/blocco (mai bypass);
- logging strutturato con distinzione INFO/WARNING/ERROR;
- aggiornamento delle statistiche live per la dashboard;
- invio delle opportunità rilevate al notification manager.
"""
import threading
import time
import logging
from datetime import datetime, timedelta, timezone

from backend.scanner.base_connector import ConnectorBase, RateLimitedError, BlockedError
from backend.market_data.price_provider_base import PriceProviderBase
from backend.deal_detector.pipeline import analyze_listing
from backend.database.repository import ScanRepository
from backend.notifications.notification_manager import NotificationManager

logger = logging.getLogger("scanner")


class ScanOrchestrator:
    def __init__(self, connector: ConnectorBase, price_provider: PriceProviderBase,
                 repository: ScanRepository, notifier: NotificationManager, settings, demo_mode: bool):
        self.connector = connector
        self.price_provider = price_provider
        self.repo = repository
        self.notifier = notifier
        self.settings = settings
        self.demo_mode = demo_mode

        self._thread = None
        self._stop_event = threading.Event()
        self._running = False

        self._current_interval = max(settings.scan_interval, connector.recommended_min_interval_seconds())
        self._consecutive_blocks = 0

    # ------------------------------------------------------------------ #
    def start(self):
        if self._running:
            return
        self._stop_event.clear()
        self._running = True
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()
        self.repo.log("INFO", "Scanner started")
        self.repo.update_scan_timing(
            datetime.now(timezone.utc).isoformat(), None, self._current_interval, "SCANNING"
        )

    def stop(self):
        self._stop_event.set()
        self._running = False
        self.repo.log("INFO", "Scanner stopped")
        self.repo.update_scan_timing(
            datetime.now(timezone.utc).isoformat(), None, self._current_interval, "STOPPED"
        )

    def is_running(self) -> bool:
        return self._running

    # ------------------------------------------------------------------ #
    def _run_loop(self):
        # Se il connettore dichiara di non supportare tempo reale, o se
        # l'intervallo configurato è sotto il minimo raccomandato, adegua
        # automaticamente la frequenza e lo rende visibile (punto 1 spec).
        recommended = self.connector.recommended_min_interval_seconds()
        if self._current_interval < recommended:
            self._current_interval = recommended
            self.repo.log(
                "WARNING",
                f"Intervallo richiesto troppo aggressivo per il connettore "
                f"'{self.connector.name}'. Uso automaticamente {recommended}s.",
            )

        while not self._stop_event.is_set():
            try:
                self._run_single_cycle()
                self._consecutive_blocks = 0
            except RateLimitedError as e:
                self._handle_block("RATE_LIMIT", str(e))
            except BlockedError as e:
                self._handle_block("BLOCKED", str(e))
            except Exception as e:  # errore imprevisto: non deve far crashare il loop
                self.repo.log("ERROR", f"Errore imprevisto nel ciclo di scansione: {e}")
                logger.exception(e)

            next_check = datetime.now(timezone.utc) + timedelta(seconds=self._current_interval)
            self.repo.update_scan_timing(
                datetime.now(timezone.utc).isoformat(),
                next_check.isoformat(),
                self._current_interval,
                "SCANNING" if self._running else "STOPPED",
            )
            self._stop_event.wait(self._current_interval)

    def _handle_block(self, kind: str, message: str):
        """Punto 16: interrompe, registra, aumenta l'intervallo, avvisa,
        riprende solo quando appropriato. Nessun tentativo di elusione."""
        self._consecutive_blocks += 1
        self.repo.log("WARNING", f"[{kind}] {message}")

        # backoff esponenziale, con tetto massimo di 10 minuti
        self._current_interval = min(self._current_interval * 2, 600)
        self.repo.update_scan_timing(
            datetime.now(timezone.utc).isoformat(),
            (datetime.now(timezone.utc) + timedelta(seconds=self._current_interval)).isoformat(),
            self._current_interval,
            "PAUSED_RATE_LIMIT" if kind == "RATE_LIMIT" else "PAUSED_BLOCKED",
        )
        self.repo.log(
            "WARNING",
            f"Intervallo di scansione aumentato automaticamente a {self._current_interval}s "
            f"per rispettare i limiti della piattaforma.",
        )

    def _run_single_cycle(self):
        query = {
            "country": self.settings.vinted_country,
            "category": self.settings.vinted_category,
            "language": self.settings.vinted_language,
            "min_price": 0,
            "max_price": self.settings.max_listing_price,
        }
        listings = self.connector.fetch_listings(query)
        self.repo.log("INFO", f"{len(listings)} annunci trovati")

        for listing in listings:
            try:
                deal = analyze_listing(
                    listing,
                    self.price_provider,
                    min_discount=self.settings.min_discount,
                    min_market_value=self.settings.min_market_value,
                    max_listing_price=self.settings.max_listing_price,
                    min_deal_score=self.settings.min_deal_score,
                    demo_mode=self.demo_mode,
                )
            except Exception as e:
                self.repo.log("ERROR", f"Errore analizzando annuncio {listing.listing_id}: {e}")
                continue

            self.repo.increment_analyzed(1)

            if deal.identification.pokemon_name:
                self.repo.log("INFO", f"Carta identificata: {deal.identification.card_name}")
                if deal.market_value.estimated_value:
                    self.repo.log("INFO", f"Valore mercato: {deal.market_value.estimated_value}€")
                self.repo.log("INFO", f"Prezzo annuncio: {listing.price}€")
                self.repo.log("INFO", f"Sconto: {deal.discount_percentage}%")
                self.repo.log("INFO", f"Deal Score: {deal.deal_score}")

            result_kind = self.repo.upsert_deal(deal)

            if deal.is_opportunity:
                self.repo.increment_opportunities(1)
                if self.repo.should_notify(listing.listing_id, listing.price, result_kind):
                    self.notifier.notify_deal(deal)
                    self.repo.mark_notified(listing.listing_id, listing.price)
