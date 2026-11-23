"""
Configurazione centrale dell'applicazione.

I valori di default vengono letti da variabili d'ambiente (file .env),
ma possono essere sovrascritti a runtime dalla dashboard (vedi
backend/database/repository.py::SettingsRepository), che li persiste
nel database SQLite. In questo modo l'utente può modificare i parametri
dalla UI senza toccare il codice, come richiesto.
"""
import os
from dataclasses import dataclass, asdict, field
from dotenv import load_dotenv

load_dotenv()


def _bool(name: str, default: bool) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


@dataclass
class Settings:
    # Modalità
    app_mode: str = os.getenv("APP_MODE", "demo")  # demo | manual_feed | vinted_api

    # Scansione
    scan_interval: int = int(os.getenv("SCAN_INTERVAL", "10"))
    min_scan_interval_enforced: int = 5  # limite di sicurezza minimo assoluto
    min_discount: float = float(os.getenv("MIN_DISCOUNT", "70"))
    min_market_value: float = float(os.getenv("MIN_MARKET_VALUE", "20"))
    max_listing_price: float = float(os.getenv("MAX_LISTING_PRICE", "500"))
    min_deal_score: float = float(os.getenv("MIN_DEAL_SCORE", "75"))

    # Mercato / categoria
    vinted_country: str = os.getenv("VINTED_COUNTRY", "IT")
    vinted_language: str = os.getenv("VINTED_LANGUAGE", "it")
    vinted_category: str = os.getenv("VINTED_CATEGORY", "pokemon")

    # Notifiche
    telegram_enabled: bool = _bool("TELEGRAM_ENABLED", False)
    telegram_bot_token: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
    telegram_chat_id: str = os.getenv("TELEGRAM_CHAT_ID", "")

    email_enabled: bool = _bool("EMAIL_ENABLED", False)
    smtp_host: str = os.getenv("SMTP_HOST", "")
    smtp_port: int = int(os.getenv("SMTP_PORT", "587"))
    smtp_user: str = os.getenv("SMTP_USER", "")
    smtp_password: str = os.getenv("SMTP_PASSWORD", "")
    email_from: str = os.getenv("EMAIL_FROM", "")
    email_to: str = os.getenv("EMAIL_TO", "")

    desktop_notification: bool = _bool("DESKTOP_NOTIFICATION", True)
    sound_notification: bool = _bool("SOUND_NOTIFICATION", True)

    # Database
    database_path: str = os.getenv("DATABASE_PATH", "./database/scanner.db")

    # Manual feed
    manual_feed_path: str = os.getenv("MANUAL_FEED_PATH", "./demo_data/manual_feed.json")

    def to_dict(self):
        return asdict(self)

    def apply_overrides(self, overrides: dict):
        """Applica un dizionario di override (es. dal database) sopra i default."""
        for k, v in overrides.items():
            if hasattr(self, k) and v is not None:
                setattr(self, k, v)
        self._enforce_safety_limits()

    def _enforce_safety_limits(self):
        # Punto 16: mai permettere un intervallo di scansione irrealisticamente
        # basso se il sistema ha rilevato limiti tecnici (vedi scan_orchestrator).
        if self.scan_interval < self.min_scan_interval_enforced:
            self.scan_interval = self.min_scan_interval_enforced


settings = Settings()
