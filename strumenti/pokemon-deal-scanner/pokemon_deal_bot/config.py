from dataclasses import dataclass
import os

@dataclass(frozen=True)
class Config:
    telegram_token: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
    telegram_chat_id: str = os.getenv("TELEGRAM_CHAT_ID", "")
    poll_interval_seconds: int = int(os.getenv("POLL_INTERVAL_SECONDS", "60"))
    market_multiplier: float = float(os.getenv("MARKET_MULTIPLIER", "1.95"))
    one_euro_min_market_value: float = float(os.getenv("ONE_EURO_MIN_MARKET_VALUE", "10"))
    dedup_hours: int = int(os.getenv("DEDUP_HOURS", "24"))
    normal_max_notifications: int = int(os.getenv("NORMAL_MAX_NOTIFICATIONS", "5"))
    normal_window_seconds: int = int(os.getenv("NORMAL_WINDOW_SECONDS", "600"))

PLATFORMS = [
    "Vinted", "eBay", "Cardmarket", "Subito", "Facebook Marketplace",
    "Wallapop", "Mercari", "Depop", "Etsy", "TCGplayer", "Carousell",
    "OLX", "Leboncoin", "Kleinanzeigen", "Gumtree"
]
