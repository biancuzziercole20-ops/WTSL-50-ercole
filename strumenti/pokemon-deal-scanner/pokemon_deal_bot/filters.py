import re
from .models import Listing

# Questi pattern servono a riconoscere prezzi che il venditore dichiara non essere
# il vero prezzo della carta. "scambio/scambi" NON è qui: resta ammesso.
FAKE_PRICE_PATTERNS = [
    r"solo\s+per\s+la\s+spedizione",
    r"per\s+la\s+spedizione",
    r"spedisc(?:o|io)\s+(?:a|per)\s+\d+(?:[,.]\d+)?\s*€?",
    r"prezzo\s+(?:simbolico|indicativo)",
    r"prezzo\s+da\s+concordare",
    r"prezzo\s+da\s+definire",
    r"contatt(?:ami|atemi)\s+(?:per|x)\s+il\s+prezzo",
    r"scriv(?:imi|etemi)\s+(?:per|in)\s+(?:privato|mp|dm)",
    r"fate\s+un[' ]?offerta",
    r"accetto\s+offerte",
    r"prezzo\s+non\s+reale",
    r"prezzo\s+solo\s+per",
    r"solo\s+per\s+attirare",
    r"asta",
    r"non\s+è\s+il\s+prezzo",
    r"prezzo\s+da\s+concordare",
]

def has_fake_price_signal(listing: Listing) -> bool:
    text = f"{listing.title} {listing.description}".lower()
    return any(re.search(p, text, re.I) for p in FAKE_PRICE_PATTERNS)

def has_real_price(listing: Listing) -> bool:
    return listing.price is not None and listing.price >= 0 and not has_fake_price_signal(listing)
