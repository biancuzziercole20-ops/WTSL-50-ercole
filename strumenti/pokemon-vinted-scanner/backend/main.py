"""
Entry point del backend — API REST usata dalla dashboard React/Next.js.

Avvio:
    uvicorn backend.main:app --reload --port 8000

Vedi README.md per le istruzioni complete (Windows, avvio, configurazione
Telegram, modalità test/reale).
"""
import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional

from backend.logging_setup import setup_logging
from config.settings import settings
from backend.database.db import init_db
from backend.database.repository import ScanRepository
from backend.notifications.notification_manager import NotificationManager
from backend.scanner.demo_connector import DemoConnector
from backend.scanner.manual_feed_connector import ManualFeedConnector
from backend.scanner.vinted_connector_stub import VintedAPIConnector
from backend.scanner.scan_orchestrator import ScanOrchestrator
from backend.market_data.demo_price_provider import DemoPriceProvider

setup_logging()
logger = logging.getLogger("main")

app = FastAPI(title="Pokémon Vinted Deal Scanner API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------- #
# Wiring: connettore, price provider, database, notifiche, orchestratore
# ---------------------------------------------------------------------- #
conn = init_db(settings.database_path)
repo = ScanRepository(settings.database_path)

# applica eventuali override salvati in precedenza dalla dashboard
saved_overrides = repo.get_settings_overrides()
if saved_overrides:
    settings.apply_overrides(saved_overrides)


def _build_connector(app_mode: str):
    if app_mode == "demo":
        return DemoConnector(), True
    if app_mode == "manual_feed":
        return ManualFeedConnector(settings.manual_feed_path), False
    if app_mode == "vinted_api":
        return VintedAPIConnector(), False
    logger.warning(f"APP_MODE sconosciuto '{app_mode}', uso 'demo' come fallback sicuro")
    return DemoConnector(), True


connector, demo_mode = _build_connector(settings.app_mode)
price_provider = DemoPriceProvider(seed=42)  # in modalità reale, sostituire con un RealPriceProvider (vedi README)
notifier = NotificationManager(settings, repo)
orchestrator = ScanOrchestrator(connector, price_provider, repo, notifier, settings, demo_mode)


@app.on_event("startup")
def _on_startup():
    repo.log("INFO", f"Applicazione avviata in modalità '{settings.app_mode}' (demo_mode={demo_mode})")
    if settings.app_mode == "demo":
        orchestrator.start()


# ---------------------------------------------------------------------- #
# Schemas
# ---------------------------------------------------------------------- #
class ConfigUpdate(BaseModel):
    scan_interval: Optional[int] = None
    min_discount: Optional[float] = None
    min_market_value: Optional[float] = None
    max_listing_price: Optional[float] = None
    min_deal_score: Optional[float] = None
    telegram_enabled: Optional[bool] = None
    telegram_bot_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None
    email_enabled: Optional[bool] = None
    desktop_notification: Optional[bool] = None
    sound_notification: Optional[bool] = None


# ---------------------------------------------------------------------- #
# Endpoints
# ---------------------------------------------------------------------- #
@app.get("/api/status")
def get_status():
    stats = repo.get_stats()
    return {
        "app_mode": settings.app_mode,
        "demo_mode": demo_mode,
        "connector": connector.name,
        "scanner_status": stats.get("scanner_status", "STOPPED"),
        "listings_analyzed": stats.get("listings_analyzed", 0),
        "opportunities_found": stats.get("opportunities_found", 0),
        "last_check_at": stats.get("last_check_at"),
        "next_check_at": stats.get("next_check_at"),
        "current_interval": stats.get("current_interval"),
        "requested_interval": settings.scan_interval,
    }


@app.get("/api/opportunities")
def get_opportunities(limit: int = 200):
    return repo.get_opportunities(limit)


@app.get("/api/listings")
def get_listings(limit: int = 500):
    return repo.all_listings(limit)


@app.get("/api/history")
def get_history(pokemon_name: str, set_name: Optional[str] = None, card_number: Optional[str] = None):
    return repo.get_history_for_card(pokemon_name, set_name, card_number)


@app.get("/api/logs")
def get_logs(limit: int = 200):
    return repo.get_logs(limit)


@app.get("/api/config")
def get_config():
    return settings.to_dict()


@app.post("/api/config")
def update_config(update: ConfigUpdate):
    overrides = {k: v for k, v in update.dict().items() if v is not None}
    for k, v in overrides.items():
        repo.set_settings_override(k, v)
    settings.apply_overrides(overrides)
    repo.log("INFO", f"Configurazione aggiornata dalla dashboard: {overrides}")
    return settings.to_dict()


@app.post("/api/scan/start")
def start_scan():
    orchestrator.start()
    return {"status": "started"}


@app.post("/api/scan/stop")
def stop_scan():
    orchestrator.stop()
    return {"status": "stopped"}


@app.get("/api/health")
def health():
    return {"ok": True}
