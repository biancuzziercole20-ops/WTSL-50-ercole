#!/usr/bin/env python3
"""
Script di verifica rapida in modalità DEMO, senza avviare il server web.

Esegue alcuni cicli di scansione simulata e stampa a console:
- annunci analizzati
- carte identificate
- valore di mercato, sconto, deal score
- opportunità rilevate
- eventi di rate-limit simulato e backoff
- log strutturato

Uso:
    python run_demo.py
"""
import time
import logging

from backend.logging_setup import setup_logging
from config.settings import settings
from backend.database.db import init_db
from backend.database.repository import ScanRepository
from backend.notifications.notification_manager import NotificationManager
from backend.scanner.demo_connector import DemoConnector
from backend.scanner.scan_orchestrator import ScanOrchestrator
from backend.market_data.demo_price_provider import DemoPriceProvider

setup_logging()
logger = logging.getLogger("run_demo")

settings.app_mode = "demo"
settings.database_path = "./database/demo_run.db"

repo = ScanRepository(settings.database_path)
init_db(settings.database_path)

connector = DemoConnector()
price_provider = DemoPriceProvider(seed=1)
notifier = NotificationManager(settings, repo)
orchestrator = ScanOrchestrator(connector, price_provider, repo, notifier, settings, demo_mode=True)

print("=" * 70)
print("POKÉMON VINTED DEAL SCANNER — MODALITÀ DEMO")
print("Nessuna richiesta di rete reale verrà effettuata.")
print("=" * 70)

CYCLES = 8
orchestrator._current_interval = 1  # accelera il demo per il test manuale

for i in range(CYCLES):
    print(f"\n--- Ciclo di scansione {i + 1}/{CYCLES} ---")
    try:
        orchestrator._run_single_cycle()
    except Exception as e:
        orchestrator._handle_block(
            "RATE_LIMIT" if "429" in str(e) or "rate limit" in str(e).lower() else "BLOCKED", str(e)
        )
    time.sleep(0.2)

print("\n" + "=" * 70)
print("RIEPILOGO")
print("=" * 70)
stats = repo.get_stats()
print(f"Annunci analizzati: {stats['listings_analyzed']}")
print(f"Opportunità trovate: {stats['opportunities_found']}")

print("\nTop opportunità rilevate:")
for opp in repo.get_opportunities(limit=10):
    print(
        f"  {opp['pokemon_name']} {opp['card_number'] or ''} | "
        f"Prezzo: €{opp['price']} | Mercato: €{opp['market_value']} | "
        f"Sconto: {opp['discount_percentage']}% | Score: {opp['deal_score']} | "
        f"Priorità: {opp['priority']}"
    )

print("\nUltimi log:")
for log in reversed(repo.get_logs(limit=15)):
    print(f"  [{log['timestamp'][11:19]}] {log['level']}: {log['message']}")

print("\nDatabase demo salvato in:", settings.database_path)
