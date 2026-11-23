"""
Deal Score 0-100 (punto 7 della spec).

Combina:
- sconto rispetto al mercato (peso maggiore)
- confidence dell'identificazione (testo + immagine)
- qualità/disponibilità immagini
- affidabilità dell'annuncio (penalità anti-frode)
- corrispondenza titolo/immagine (quando entrambe le identificazioni sono disponibili)
- disponibilità di dati di mercato reali (sample_size)
"""
from backend.database.models import DealResult, CardIdentification, MarketValue, Listing
from backend.deal_detector.anti_fraud_filter import evaluate_fraud_risk


def _title_image_agreement(text_ident: CardIdentification, image_ident: CardIdentification) -> float:
    """Ritorna 0-100: quanto le due identificazioni (testo vs immagine)
    concordano sul nome pokemon e sul numero carta. Se una delle due manca,
    ritorna un valore neutro (50) perché non c'è disaccordo da penalizzare,
    ma nemmeno conferma incrociata."""
    if not image_ident or image_ident.image_confidence == 0:
        return 50.0
    if not text_ident.pokemon_name or not image_ident.pokemon_name:
        return 50.0
    name_match = text_ident.pokemon_name.lower() == image_ident.pokemon_name.lower()
    number_match = (
        text_ident.card_number == image_ident.card_number
        if text_ident.card_number and image_ident.card_number
        else True
    )
    if name_match and number_match:
        return 100.0
    if name_match and not number_match:
        return 40.0
    return 0.0


def compute_deal_score(
    listing: Listing,
    combined_ident: CardIdentification,
    image_ident: CardIdentification,
    market_value: MarketValue,
    discount_percentage: float,
) -> DealResult:
    fraud_flags, fraud_penalty = evaluate_fraud_risk(listing, combined_ident)

    # 1) componente sconto (0-100, saturato oltre il 90%)
    discount_component = max(0.0, min(discount_percentage, 90.0)) / 90.0 * 100

    # 2) componente confidence identificazione (media testo/immagine)
    confidences = [c for c in [combined_ident.text_confidence, combined_ident.image_confidence] if c > 0]
    confidence_component = sum(confidences) / len(confidences) if confidences else 0.0

    # 3) qualità/disponibilità immagini
    image_quality_component = 100.0 if listing.images else 20.0

    # 4) corrispondenza titolo/immagine
    agreement_component = _title_image_agreement(combined_ident, image_ident)

    # 5) disponibilità dati di mercato reali
    market_data_component = 100.0 if market_value.sample_size and market_value.sample_size > 0 else 40.0
    if not market_value.data_available:
        market_data_component = 0.0

    # Media pesata
    weights = {
        "discount": 0.35,
        "confidence": 0.20,
        "images": 0.10,
        "agreement": 0.15,
        "market_data": 0.20,
    }
    raw_score = (
        discount_component * weights["discount"]
        + confidence_component * weights["confidence"]
        + image_quality_component * weights["images"]
        + agreement_component * weights["agreement"]
        + market_data_component * weights["market_data"]
    )

    final_score = max(0.0, min(100.0, raw_score - fraud_penalty))

    result = DealResult(
        listing=listing,
        identification=combined_ident,
        market_value=market_value,
        discount_percentage=discount_percentage,
        deal_score=round(final_score, 1),
        fraud_flags=fraud_flags,
    )
    return result
