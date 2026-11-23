"""
Interfaccia astratta per un connettore di annunci (punto 1 e 17 della spec).

Ogni connettore deve implementare fetch_listings() e restituire una lista
di oggetti Listing. Il resto della pipeline è totalmente agnostico
rispetto alla fonte dei dati.

Un connettore può segnalare limiti tecnici/contrattuali sollevando
RateLimitedError o BlockedError: lo scan_orchestrator li intercetta e
applica automaticamente la strategia di backoff (punto 16 della spec),
SENZA alcun tentativo di aggirare la protezione.
"""
from abc import ABC, abstractmethod
from typing import List
from backend.database.models import Listing


class RateLimitedError(Exception):
    """Sollevato quando la fonte dati segnala HTTP 429 / rate limit."""


class BlockedError(Exception):
    """Sollevato quando la fonte dati segnala CAPTCHA, ban temporaneo o
    accesso negato. Il programma NON deve mai tentare di aggirare questo
    stato: si ferma, registra l'evento e avvisa l'utente."""


class ConnectorBase(ABC):
    name = "base"

    @abstractmethod
    def fetch_listings(self, query: dict) -> List[Listing]:
        """
        query contiene: country, category, language, min_price, max_price,
        keywords (lista di termini di ricerca, es. nomi Pokémon).
        """
        raise NotImplementedError

    def supports_realtime(self) -> bool:
        """Se False, lo scan_orchestrator forza automaticamente un
        intervallo minimo più prudente (punto 1 della spec: 'se Vinted
        impone limiti ... usa una frequenza compatibile e mostralo')."""
        return True

    def recommended_min_interval_seconds(self) -> int:
        return 10
