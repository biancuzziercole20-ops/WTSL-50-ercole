from dotenv import load_dotenv
load_dotenv()

from .config import Config
from .filters import has_real_price
from .market import qualifies
from .priority import RateLimiter
from .dedup import Deduplicator

def process_listing(listing, market, priority, cfg, telegram_send):
    if not has_real_price(listing):
        return False
    if not qualifies(listing, market, cfg):
        return False
    key = f"{listing.platform}|{listing.url}"
    # dedup and priority logic are wired here by the runner.
    return True

def main():
    cfg = Config()
    print("Pokémon Deal Scanner pronto.")
    print("Piattaforme configurate:", ", ".join(__import__('pokemon_deal_bot.config', fromlist=['PLATFORMS']).PLATFORMS))
    print("Configurare i connector reali/API prima dell'avvio live.")

if __name__ == "__main__":
    main()
