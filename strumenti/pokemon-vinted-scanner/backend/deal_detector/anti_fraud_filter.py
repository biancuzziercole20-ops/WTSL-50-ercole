"""
Filtro anti-falsi-affari (punto 7 della spec).

Rileva segnali che suggeriscono che un prezzo estremamente basso non sia
un vero affare, restituendo una lista di "fraud_flags" testuali e una
penalità numerica da applicare al Deal Score.
"""
import re
from typing import List, Tuple

from backend.database.models import Listing, CardIdentification
from backend.card_identifier.card_catalog import FAKE_SIGNAL_KEYWORDS, DEFECT_KEYWORDS

BUNDLE_KEYWORDS = ["bundle", "lotto", "lot of", "set completo", "collezione", "insieme a"]
WRONG_ITEM_KEYWORDS = ["binder", "album", "porta carte", "sleeve", "solo scatola", "box vuota", "empty box"]


def evaluate_fraud_risk(listing: Listing, ident: CardIdentification) -> Tuple[List[str], float]:
    """Ritorna (flags, penalty_0_100) dove penalty è quanto sottrarre dal
    Deal Score complessivo."""
    flags: List[str] = []
    penalty = 0.0
    text = f"{listing.title} {listing.description}".lower()

    for kw in FAKE_SIGNAL_KEYWORDS:
        if kw in text:
            flags.append(f"Possibile carta non originale (parola chiave: '{kw}')")
            penalty += 40

    for kw in BUNDLE_KEYWORDS:
        if kw in text:
            flags.append("L'annuncio sembra riferirsi a un lotto/bundle, non alla singola carta")
            penalty += 25
            break

    for kw in WRONG_ITEM_KEYWORDS:
        if kw in text:
            flags.append("L'annuncio potrebbe riferirsi a un accessorio, non alla carta")
            penalty += 35
            break

    if ident.defects:
        flags.append(f"Difetti dichiarati/rilevati: {', '.join(ident.defects)}")
        penalty += 10 * len(ident.defects)

    if ident.condition == "damaged":
        flags.append("Condizione dichiarata: danneggiata")
        penalty += 20

    # titolo/immagine mismatch: se l'OCR immagine e il testo titolo
    # identificano pokemon diversi, è un forte segnale di annuncio ingannevole
    # (la verifica vera avviene in deal_score.py combinando le due identificazioni)

    if not listing.images:
        flags.append("Nessuna immagine disponibile per verificare la carta")
        penalty += 15

    if ident.pokemon_name is None:
        flags.append("Impossibile identificare con certezza la carta dal testo")
        penalty += 20

    return flags, min(penalty, 100.0)
