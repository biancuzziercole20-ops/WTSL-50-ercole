"""Notifiche desktop e suono (punto 10 della spec).

Usa `plyer` per le notifiche desktop cross-platform (Windows/macOS/Linux).
Se plyer o il backend nativo non sono disponibili (es. ambiente server
senza display), la funzione fallisce silenziosamente loggando un warning,
senza interrompere il resto della pipeline.
"""
import logging
import os
import sys

logger = logging.getLogger("notifications.desktop")


def send_desktop_notification(title: str, message: str) -> bool:
    try:
        from plyer import notification
        notification.notify(title=title, message=message, timeout=10)
        return True
    except Exception as e:
        logger.warning(f"Notifica desktop non disponibile: {e}")
        return False


def play_notification_sound() -> bool:
    """Riproduce un suono di sistema. Su Windows usa winsound (built-in),
    su macOS/Linux prova aplay/afplay se disponibili; altrimenti stampa un
    BEL ASCII come fallback minimo."""
    try:
        if sys.platform.startswith("win"):
            import winsound
            winsound.MessageBeep()
            return True
        elif sys.platform == "darwin":
            os.system("afplay /System/Library/Sounds/Glass.aiff")
            return True
        else:
            # Linux: prova un suono di sistema comune, altrimenti fallback
            candidates = [
                "/usr/share/sounds/freedesktop/stereo/complete.oga",
                "/usr/share/sounds/alsa/Front_Center.wav",
            ]
            for c in candidates:
                if os.path.exists(c):
                    os.system(f"paplay {c} 2>/dev/null || aplay {c} 2>/dev/null")
                    return True
            print("\a")  # fallback: bell ASCII
            return True
    except Exception as e:
        logger.warning(f"Suono notifica non disponibile: {e}")
        return False
