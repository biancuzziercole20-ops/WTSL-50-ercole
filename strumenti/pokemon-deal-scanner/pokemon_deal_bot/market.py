from .models import CardMarketData, Listing
from .config import Config

def qualifies(listing: Listing, market: CardMarketData, cfg: Config) -> bool:
    if not listing.price or listing.price <= 0:
        return False
    if market.value <= 0:
        return False

    # Il confronto deve essere sulla carta/versione, lingua e condizione già
    # risolte dal layer di matching Cardmarket.
    if listing.price == 1:
        return market.value >= cfg.one_euro_min_market_value
    return market.value >= listing.price * cfg.market_multiplier

def difference_percent(listing: Listing, market: CardMarketData) -> float:
    if listing.price <= 0:
        return 0.0
    return ((market.value - listing.price) / listing.price) * 100
