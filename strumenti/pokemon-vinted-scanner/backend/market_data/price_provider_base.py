"""
Interfaccia astratta per una fonte di prezzi di mercato.

Per collegare una fonte reale (PriceCharting, TCGplayer, Cardmarket, ecc.)
basta creare una nuova classe che eredita da PriceProviderBase e
implementa get_recent_sales(). Vedi README.md, sezione "Passare alla
modalità reale", per la procedura completa.
"""
from abc import ABC, abstractmethod
from typing import List, Optional
from backend.database.models import CardIdentification


class PriceProviderBase(ABC):
    @abstractmethod
    def get_recent_sales(self, ident: CardIdentification) -> List[float]:
        """Ritorna una lista di prezzi di vendite recenti (raw, stessa
        lingua/condizione quando possibile) per la carta identificata.
        Lista vuota se non ci sono dati disponibili."""
        raise NotImplementedError

    @abstractmethod
    def get_graded_value(self, ident: CardIdentification, company: str, score: str) -> Optional[float]:
        """Ritorna il valore stimato per una carta gradata da una specifica
        società/punteggio (es. PSA 10). None se non disponibile."""
        raise NotImplementedError
