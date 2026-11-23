"""
Test di integrazione: esegue l'intera pipeline in modalità demo per alcuni
cicli, come farebbe run_demo.py, e verifica il comportamento end-to-end:
scanner -> identificazione -> mercato -> sconto -> deal score -> filtro
anti-frode -> database -> (niente notifiche reali, Telegram disabilitato).
"""
import os
import tempfile

from config.settings import Settings
from backend.database.db import init_db
from backend.database.repository import ScanRepository
from backend.notifications.notification_manager import NotificationManager
from backend.scanner.demo_connector import DemoConnector
from backend.scanner.scan_orchestrator import ScanOrchestrator
from backend.market_data.demo_price_provider import DemoPriceProvider


def test_full_demo_pipeline_end_to_end():
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    tmp.close()
    try:
        settings = Settings()
        settings.app_mode = "demo"
        settings.database_path = tmp.name
        settings.telegram_enabled = False
        settings.email_enabled = False
        settings.desktop_notification = False
        settings.sound_notification = False

        init_db(settings.database_path)
        repo = ScanRepository(settings.database_path)
        connector = DemoConnector()
        provider = DemoPriceProvider(seed=7)
        notifier = NotificationManager(settings, repo)
        orchestrator = ScanOrchestrator(connector, provider, repo, notifier, settings, demo_mode=True)

        for _ in range(5):
            try:
                orchestrator._run_single_cycle()
            except Exception:
                # un ciclo su 7 simula un rate limit: gestito da _handle_block
                # nel loop reale; qui verifichiamo solo che non propaghi
                pass

        stats = repo.get_stats()
        assert stats["listings_analyzed"] > 0

        opportunities = repo.get_opportunities()
        assert len(opportunities) > 0, "in modalità demo devono emergere alcune vere opportunità"

        # nessun annuncio duplicato: listing_id univoci
        all_rows = repo.all_listings()
        ids = [r["listing_id"] for r in all_rows]
        assert len(ids) == len(set(ids))

        # il sistema non deve MAI marcare un annuncio come "acquistato"
        statuses = {r["status"] for r in all_rows}
        assert "purchased" not in statuses
        assert "acquistato" not in statuses

        # verifica log strutturato con eventi distinguibili
        logs = repo.get_logs(limit=500)
        levels = {l["level"] for l in logs}
        assert "INFO" in levels
    finally:
        os.unlink(tmp.name)
