"""Notifiche email via SMTP (punto 10 della spec, opzionale/configurabile)."""
import smtplib
import logging
from email.mime.text import MIMEText

logger = logging.getLogger("notifications.email")


def send_email_notification(smtp_host: str, smtp_port: int, smtp_user: str,
                             smtp_password: str, email_from: str, email_to: str,
                             subject: str, body: str) -> bool:
    if not all([smtp_host, smtp_user, smtp_password, email_from, email_to]):
        logger.warning("Email non configurata correttamente (parametri SMTP mancanti)")
        return False
    try:
        msg = MIMEText(body, "plain", "utf-8")
        msg["Subject"] = subject
        msg["From"] = email_from
        msg["To"] = email_to

        with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as server:
            server.starttls()
            server.login(smtp_user, smtp_password)
            server.sendmail(email_from, [email_to], msg.as_string())
        return True
    except Exception as e:
        logger.error(f"Errore invio email: {e}")
        return False


def format_deal_email(deal) -> str:
    listing = deal.listing
    ident = deal.identification
    mv = deal.market_value
    return (
        f"POKEMON DEAL TROVATO\n\n"
        f"Carta: {ident.card_name}\n"
        f"Set: {ident.set_name or 'N/D'}\n"
        f"Prezzo Vinted: {listing.price}€\n"
        f"Valore stimato: {mv.estimated_value}€\n"
        f"Sconto: {deal.discount_percentage}%\n"
        f"Deal Score: {deal.deal_score}/100\n"
        f"Confidence: {ident.confidence}%\n"
        f"Link annuncio: {listing.url}\n"
    )
