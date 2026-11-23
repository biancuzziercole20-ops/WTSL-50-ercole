"""
Identificazione testuale della carta a partire da titolo + descrizione
dell'annuncio (punto 3 e 15 della spec).

Approccio:
1. Estrazione del numero carta con regex (es. "199/165") — questo è il
   segnale più affidabile per distinguere carte con nomi simili
   (Charizard ex 199/165 vs Charizard 4/102).
2. Riconoscimento del nome Pokémon con fuzzy matching (difflib) per
   tollerare errori di battitura ("umbreon vmaxe" -> "Umbreon" + "VMAX").
3. Riconoscimento di set, tipo di carta, variante, lingua, grading,
   condizione e difetti tramite pattern/keyword matching.
4. Calcolo di un text_confidence 0-100 in base a quanti campi sono stati
   identificati con certezza.
"""
import re
import difflib
from typing import Optional

from backend.database.models import CardIdentification, GradingCompany
from backend.card_identifier.card_catalog import (
    KNOWN_POKEMON, KNOWN_SETS, CARD_TYPES, VARIANT_KEYWORDS,
    GRADING_PATTERNS, CONDITION_KEYWORDS, DEFECT_KEYWORDS, FAKE_SIGNAL_KEYWORDS,
)

CARD_NUMBER_RE = re.compile(r"\b([A-Za-z]{0,3}\d{1,4})\s*/\s*([A-Za-z]{0,3}\d{1,4})\b")
YEAR_RE = re.compile(r"\b(19[9]\d|20[0-3]\d)\b")


def _normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def _fuzzy_pokemon_match(token: str, cutoff: float = 0.72) -> Optional[str]:
    matches = difflib.get_close_matches(token.capitalize(), KNOWN_POKEMON, n=1, cutoff=cutoff)
    return matches[0] if matches else None


def _find_pokemon_name(text: str) -> Optional[str]:
    words = re.findall(r"[A-Za-zÀ-ÿ']+", text)
    # 1) match esatto (case-insensitive) prima
    lower_words = [w.lower() for w in words]
    for name in KNOWN_POKEMON:
        if name.lower() in lower_words:
            return name
    # 2) fuzzy match per tollerare refusi (es. "umbreonn", "pikacchu")
    for w in words:
        if len(w) < 4:
            continue
        m = _fuzzy_pokemon_match(w)
        if m:
            return m
    return None


def _find_set(text: str) -> Optional[str]:
    low = text.lower()
    for s in KNOWN_SETS:
        if s.lower() in low:
            return s
    return None


def _find_card_type(text: str) -> Optional[str]:
    low = text.lower()
    # Ordine: dal più specifico al più generico, per evitare che "V" matchi
    # dentro "VMAX" o "VSTAR" per primo.
    ordered = sorted(CARD_TYPES, key=len, reverse=True)
    for t in ordered:
        pattern = r"\b" + re.escape(t.lower()).replace(r"\ ", r"\s*") + r"\b"
        if re.search(pattern, low):
            return t
        # tollera errori tipo "vmaxe", "v max"
        if t.lower() == "vmax" and re.search(r"\bv\s*-?\s*max\w*\b", low):
            return "VMAX"
        if t.lower() == "vstar" and re.search(r"\bv\s*-?\s*star\w*\b", low):
            return "VSTAR"
    return None


def _find_variant(text: str) -> Optional[str]:
    low = text.lower()
    for v in VARIANT_KEYWORDS:
        if v in low:
            return v.title()
    return None


def _find_grading(text: str):
    for company, pattern in GRADING_PATTERNS.items():
        m = re.search(pattern, text, re.IGNORECASE)
        if m:
            return company, m.group(1)
    return GradingCompany.RAW.value, None


def _find_condition(text: str) -> Optional[str]:
    low = text.lower()
    for cond, keywords in CONDITION_KEYWORDS.items():
        for kw in keywords:
            if kw in low:
                return cond
    return None


def _find_defects(text: str):
    low = text.lower()
    return [kw for kw in DEFECT_KEYWORDS if kw in low]


def _find_language(text: str, listing_language: Optional[str]) -> Optional[str]:
    low = text.lower()
    if "japanese" in low or "giapponese" in low or re.search(r"[぀-ヿ一-鿿]", text):
        return "Japanese"
    if "english" in low or "inglese" in low:
        return "English"
    if "italian" in low or "italiano" in low:
        return "Italian"
    if "german" in low or "tedesco" in low:
        return "German"
    if "french" in low or "francese" in low:
        return "French"
    return listing_language


def _find_year(text: str) -> Optional[int]:
    m = YEAR_RE.search(text)
    return int(m.group(1)) if m else None


def identify_card_from_text(title: str, description: str, listing_language: Optional[str] = None) -> CardIdentification:
    text = _normalize(f"{title} {description}")

    ident = CardIdentification()
    ident.pokemon_name = _find_pokemon_name(text)
    ident.set_name = _find_set(text)

    m = CARD_NUMBER_RE.search(text)
    ident.card_number = f"{m.group(1)}/{m.group(2)}" if m else None

    ident.card_type = _find_card_type(text)
    ident.variant = _find_variant(text)
    ident.language = _find_language(text, listing_language)
    ident.year = _find_year(text)
    ident.condition = _find_condition(text)
    ident.defects = _find_defects(text)

    grading_company, grading_score = _find_grading(text)
    ident.grading_company = grading_company
    ident.grading_score = grading_score

    # card_name leggibile
    parts = [ident.pokemon_name, ident.card_type, ident.card_number]
    ident.card_name = " ".join([p for p in parts if p]) or title

    # Segnali di possibile falso/contraffazione -> annotati, il filtro
    # anti-frode vero e proprio è in deal_detector/anti_fraud_filter.py
    low = text.lower()
    for kw in FAKE_SIGNAL_KEYWORDS:
        if kw in low:
            ident.notes.append(f"Segnale sospetto nel testo: '{kw}'")

    # --- Confidence testuale ---
    score = 0.0
    if ident.pokemon_name:
        score += 35
    if ident.card_number:
        score += 25
    if ident.set_name:
        score += 20
    if ident.card_type:
        score += 10
    if ident.language:
        score += 5
    if ident.condition:
        score += 5
    ident.text_confidence = min(score, 100.0)
    ident.confidence = ident.text_confidence
    ident.uncertain = ident.confidence < 40 or ident.pokemon_name is None

    if ident.uncertain:
        ident.notes.append("Identificazione incerta")

    return ident
