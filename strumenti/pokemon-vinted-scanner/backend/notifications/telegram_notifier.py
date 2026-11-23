"""Notifiche Telegram (punto 10 della spec)."""
import logging
import requests

logger = logging.getLogger("notifications.telegram")


def send_telegram_message(bot_token: str, chat_id: str, text: str) -> bool:
    if not bot_token or not chat_id:
        logger.warning("Telegram non configurato (bot_token/chat_id mancanti)")
        return False
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    try:
        resp = requests.post(url, json={
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": False,
        }, timeout=10)
        if resp.status_code == 200:
            return True
        logger.error(f"Errore invio Telegram: {resp.status_code} {resp.text}")
        return False
    except Exception as e:
        logger.error(f"Eccezione invio Telegram: {e}")
        return False


def format_deal_message(deal) -> str:
    listing = deal.listing
    ident = deal.identification
    mv = deal.market_value
    detected_time = (listing.detected_at or "")[11:19]
    return (
        "🔥 <b>POKÉMON DEAL TROVATO</b>\n\n"
        f"🃏 <b>Carta:</b>\n{ident.card_name}\n\n"
        f"📦 <b>Set:</b>\n{ident.set_name or 'N/D'}\n\n"
        f"💰 <b>Prezzo Vinted:</b>\n€{listing.price}\n\n"
        f"📊 <b>Valore stimato:</b>\n€{mv.estimated_value}\n\n"
        f"📉 <b>Sconto:</b>\n{deal.discount_percentage}%\n\n"
        f"⭐ <b>Deal Score:</b>\n{deal.deal_score}/100\n\n"
        f"🎯 <b>Confidence:</b>\n{ident.confidence}%\n\n"
        f"🔗 <b>Apri annuncio:</b>\n{listing.url}\n\n"
        f"⏱ <b>Rilevato:</b>\n{detected_time}"
    )
