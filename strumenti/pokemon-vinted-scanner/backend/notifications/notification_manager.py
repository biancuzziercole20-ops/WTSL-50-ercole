"""Coordina l'invio delle notifiche sui canali abilitati dalle impostazioni."""
import logging
from backend.notifications.telegram_notifier import send_telegram_message, format_deal_message
from backend.notifications.desktop_notifier import send_desktop_notification, play_notification_sound
from backend.notifications.email_notifier import send_email_notification, format_deal_email

logger = logging.getLogger("notifications.manager")


class NotificationManager:
    def __init__(self, settings, repo=None):
        self.settings = settings
        self.repo = repo  # per loggare l'esito nel database (punto 21)

    def _log(self, level, msg):
        if self.repo:
            self.repo.log(level, msg)
        logger.info(msg)

    def notify_deal(self, deal):
        card_name = deal.identification.card_name

        if self.settings.telegram_enabled:
            ok = send_telegram_message(
                self.settings.telegram_bot_token,
                self.settings.telegram_chat_id,
                format_deal_message(deal),
            )
            self._log("INFO" if ok else "ERROR",
                       f"Notifica Telegram {'inviata' if ok else 'FALLITA'} per {card_name}")

        if self.settings.desktop_notification:
            ok = send_desktop_notification(
                "🔥 Pokémon Deal trovato!",
                f"{card_name} — €{deal.listing.price} (sconto {deal.discount_percentage}%)",
            )
            self._log("INFO" if ok else "WARNING",
                       f"Notifica desktop {'inviata' if ok else 'non disponibile'} per {card_name}")

        if self.settings.sound_notification:
            play_notification_sound()

        if self.settings.email_enabled:
            ok = send_email_notification(
                self.settings.smtp_host, self.settings.smtp_port, self.settings.smtp_user,
                self.settings.smtp_password, self.settings.email_from, self.settings.email_to,
                subject=f"Pokémon Deal: {card_name}", body=format_deal_email(deal),
            )
            self._log("INFO" if ok else "ERROR",
                       f"Notifica email {'inviata' if ok else 'FALLITA'} per {card_name}")
