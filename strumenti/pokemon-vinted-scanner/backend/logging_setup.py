"""Configurazione logging globale (punto 21 della spec).

Gli errori (livello ERROR) sono chiaramente distinguibili dagli eventi
normali (INFO) grazie al formato con livello esplicito e, quando lo
stream supporta i colori, a colori differenti.
"""
import logging
import sys


class _ColorFormatter(logging.Formatter):
    COLORS = {
        "INFO": "\033[92m",     # verde
        "WARNING": "\033[93m",  # giallo
        "ERROR": "\033[91m",    # rosso
        "RESET": "\033[0m",
    }

    def format(self, record):
        color = self.COLORS.get(record.levelname, "")
        reset = self.COLORS["RESET"]
        base = super().format(record)
        if sys.stdout.isatty():
            return f"{color}{base}{reset}"
        return base


def setup_logging():
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_ColorFormatter("[%(asctime)s] %(levelname)s %(name)s: %(message)s", "%H:%M:%S"))
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.handlers = [handler]
