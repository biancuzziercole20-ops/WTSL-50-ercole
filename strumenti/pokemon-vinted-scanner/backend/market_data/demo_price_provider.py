"""
Provider di prezzi per la modalità DEMO/TEST.

Usa la tabella locale reference_prices.json e introduce una piccola
variazione casuale per simulare vendite recenti multiple (necessario per
poter calcolare media/mediana come richiesto al punto 5 della spec).
"""
import json
import os
import random
from typing import List, Optional

from backend.market_data.price_provider_base import PriceProviderBase
from backend.database.models import CardIdentification

_REF_PATH = os.path.join(os.path.dirname(__file__), "reference_prices.json")

with open(_REF_PATH, "r", encoding="utf-8") as f:
    _REFERENCE = json.load(f)


def _card_key_candidates(ident: CardIdentification) -> List[str]:
    """Genera più chiavi candidate perché la tabella di riferimento a volte
    include il tipo carta nel nome (es. 'umbreon vmax') e a volte no (es.
    carte base 'charizard'). Si prova prima la forma più specifica."""
    if not ident.pokemon_name:
        return []
    set_part = (ident.set_name or "").lower()
    num_part = (ident.card_number or "").lower()
    name = ident.pokemon_name.lower()
    candidates = []
    if ident.card_type:
        candidates.append(f"{name} {ident.card_type.lower()}|{set_part}|{num_part}")
    candidates.append(f"{name}|{set_part}|{num_part}")
    return candidates


class DemoPriceProvider(PriceProviderBase):
    def __init__(self, seed: Optional[int] = None):
        self._rng = random.Random(seed)

    def _lookup_base(self, ident: CardIdentification):
        for key in _card_key_candidates(ident):
            if key in _REFERENCE["cards"]:
                return _REFERENCE["cards"][key]
        return None

    def get_recent_sales(self, ident: CardIdentification) -> List[float]:
        entry = self._lookup_base(ident)
        if entry:
            base = entry["raw"]
            sample_size = 6
        else:
            # fallback: nessun dato esatto -> stima grezza dal tipo carta,
            # con sample_size=0 per segnalare che non sono dati reali.
            multiplier = _REFERENCE["type_multipliers_fallback"].get(
                ident.card_type or "standard", 5.0
            )
            base = multiplier
            sample_size = 0

        prices = [
            round(base * self._rng.uniform(0.85, 1.15), 2) for _ in range(max(sample_size, 3))
        ]
        # tag sull'oggetto per far sapere al market_estimator che è fallback
        self._last_sample_size = sample_size
        return prices

    def get_graded_value(self, ident: CardIdentification, company: str, score: str) -> Optional[float]:
        entry = self._lookup_base(ident)
        if not entry:
            return None
        key = f"{company}{score}".replace(".", "")
        graded = entry.get("graded", {})
        # prova match diretto (es. "PSA10"), altrimenti None
        return graded.get(key)
