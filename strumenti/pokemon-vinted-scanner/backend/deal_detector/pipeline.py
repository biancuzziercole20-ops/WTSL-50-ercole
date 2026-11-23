"""
Orchestratore della pipeline di analisi per un singolo annuncio:
identificazione testo -> identificazione immagine -> merge -> stima
mercato -> sconto -> deal score -> filtri soglie -> DealResult finale.
"""
from backend.database.models import Listing, CardIdentification, DealResult
from backend.card_identifier.parser import identify_card_from_text
from backend.image_analyzer.ocr_analyzer import analyze_images
from backend.market_data.market_estimator import estimate_market_value
from backend.market_data.price_provider_base import PriceProviderBase
from backend.deal_detector.discount_calculator import calculate_discount, classify_priority
from backend.deal_detector.deal_score import compute_deal_score


def _merge_identifications(text_ident: CardIdentification, image_ident: CardIdentification) -> CardIdentification:
    """Combina le due identificazioni preferendo il campo con confidence
    più alta per ciascun attributo, senza mai inventare dati mancanti."""
    merged = CardIdentification(**vars(text_ident))  # copia base testo

    use_image = image_ident.image_confidence > text_ident.text_confidence
    for field in ["pokemon_name", "card_name", "set_name", "card_number", "variant",
                  "card_type", "language", "year", "rarity", "condition"]:
        image_val = getattr(image_ident, field, None)
        text_val = getattr(text_ident, field, None)
        if use_image and image_val:
            setattr(merged, field, image_val)
        elif not text_val and image_val:
            setattr(merged, field, image_val)

    merged.defects = list(set((text_ident.defects or []) + (image_ident.defects or [])))
    merged.image_confidence = image_ident.image_confidence
    merged.text_confidence = text_ident.text_confidence
    merged.confidence = round((merged.text_confidence + merged.image_confidence) / 2, 1) \
        if merged.image_confidence else merged.text_confidence
    merged.uncertain = merged.confidence < 40 or merged.pokemon_name is None
    merged.notes = list(set((text_ident.notes or []) + (image_ident.notes or [])))
    if merged.uncertain and "Identificazione incerta" not in merged.notes:
        merged.notes.append("Identificazione incerta")
    return merged


def analyze_listing(
    listing: Listing,
    price_provider: PriceProviderBase,
    min_discount: float,
    min_market_value: float,
    max_listing_price: float,
    min_deal_score: float,
    demo_mode: bool = False,
) -> DealResult:
    text_ident = identify_card_from_text(listing.title, listing.description, listing.language)
    image_ident = analyze_images(
        listing.images, demo_mode=demo_mode, demo_hint_text=f"{listing.title} {listing.description}"
    )
    combined = _merge_identifications(text_ident, image_ident)

    market_value = estimate_market_value(combined, price_provider)
    discount = calculate_discount(market_value.estimated_value or 0.0, listing.price)

    result = compute_deal_score(listing, combined, image_ident, market_value, discount)
    result.priority = classify_priority(discount)

    # --- Filtri soglia (punto 6, 19 della spec) ---
    reasons = []
    is_opportunity = True

    if not market_value.data_available or not market_value.estimated_value:
        is_opportunity = False
        reasons.append("Valore di mercato non disponibile")
    if market_value.estimated_value and market_value.estimated_value < min_market_value:
        is_opportunity = False
        reasons.append(f"Valore di mercato sotto la soglia minima ({min_market_value}€)")
    if listing.price > max_listing_price:
        is_opportunity = False
        reasons.append(f"Prezzo annuncio sopra la soglia massima ({max_listing_price}€)")
    if discount < min_discount:
        is_opportunity = False
        reasons.append(f"Sconto {discount}% sotto la soglia minima ({min_discount}%)")
    if result.deal_score < min_deal_score:
        is_opportunity = False
        reasons.append(f"Deal Score {result.deal_score} sotto la soglia minima ({min_deal_score})")
    if combined.uncertain:
        is_opportunity = False
        reasons.append("Identificazione incerta: opportunità non confermata")

    result.is_opportunity = is_opportunity
    result.reasons = reasons
    return result
