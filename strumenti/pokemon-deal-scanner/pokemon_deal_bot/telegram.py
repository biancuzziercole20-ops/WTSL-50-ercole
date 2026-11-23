import requests
from .models import Listing, CardMarketData
from .market import difference_percent

TEMPLATE = '''🔥 POKÉMON DEAL TROVATO

🃏 Carta: {name}
⭐ Rarità: {rarity}
🌍 Lingua: {language}
📦 Condizione: {condition}

💰 Prezzo annuncio: €{price}
📊 Valore Cardmarket: €{value}
📈 Differenza: +{percent:.1f}%
💎 Valore potenziale: €{value}

🔥 Domanda: {demand}
🛒 Vendite/mercato: {sales}

🌐 Piattaforma: {platform}
👤 Venditore: {seller}

🔗 APRI ANNUNCIO
{url}'''

def format_message(listing, market):
    return TEMPLATE.format(
        name=market.card_name,
        rarity=market.rarity or "N/D",
        language=market.language or listing.language or "N/D",
        condition=market.condition or listing.condition or "N/D",
        price=f"{listing.price:.2f}",
        value=f"{market.value:.2f}",
        percent=difference_percent(listing, market),
        demand=market.demand or "N/D",
        sales=market.sales_data or "N/D",
        platform=listing.platform,
        seller=listing.seller or "N/D",
        url=listing.url,
    )

def send_telegram(token, chat_id, text):
    if not token or not chat_id:
        raise RuntimeError("TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID non configurati")
    r = requests.post(
        f"https://api.telegram.org/bot{token}/sendMessage",
        json={"chat_id": chat_id, "text": text, "disable_web_page_preview": False},
        timeout=20,
    )
    r.raise_for_status()
