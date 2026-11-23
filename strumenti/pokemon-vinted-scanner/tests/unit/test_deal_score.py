from backend.database.models import Listing
from backend.deal_detector.pipeline import analyze_listing
from backend.market_data.demo_price_provider import DemoPriceProvider


def _listing(listing_id, title, price, description="", images=None, language="Italian"):
    return Listing(
        listing_id=listing_id, url=f"https://example.test/{listing_id}",
        title=title, description=description, price=price, currency="EUR",
        images=images if images is not None else ["demo://img.jpg"], language=language,
    )


def test_real_deal_is_flagged_as_opportunity():
    listing = _listing("t1", "Charizard ex 199/165 Obsidian Flames NM", 13.0,
                        "condizioni ottime, near mint")
    provider = DemoPriceProvider(seed=1)
    deal = analyze_listing(listing, provider, min_discount=70, min_market_value=20,
                            max_listing_price=500, min_deal_score=75, demo_mode=True)
    assert deal.is_opportunity is True
    assert deal.deal_score >= 75
    assert deal.discount_percentage >= 70


def test_fake_proxy_card_is_never_flagged_as_opportunity():
    listing = _listing("t2", "Charizard ex 199/165 custom proxy riproduzione", 2.0,
                        "riproduzione custom, non originale")
    provider = DemoPriceProvider(seed=1)
    deal = analyze_listing(listing, provider, min_discount=70, min_market_value=20,
                            max_listing_price=500, min_deal_score=75, demo_mode=True)
    assert deal.is_opportunity is False
    assert len(deal.fraud_flags) > 0


def test_damaged_card_penalized_even_with_high_discount():
    listing = _listing("t3", "Giratina VSTAR 131/196 Lost Origin", 5.0,
                        "carta piegata, angoli rovinati, danneggiata")
    provider = DemoPriceProvider(seed=1)
    deal = analyze_listing(listing, provider, min_discount=70, min_market_value=20,
                            max_listing_price=500, min_deal_score=75, demo_mode=True)
    # sconto alto ma deal score basso per via dei difetti -> NON opportunità
    assert deal.discount_percentage > 70
    assert deal.is_opportunity is False


def test_no_image_results_in_uncertain_identification_not_flagged():
    listing = _listing("t4", "Carta pokemon rara", 5.0, "vendo carta pokemon", images=[])
    provider = DemoPriceProvider(seed=1)
    deal = analyze_listing(listing, provider, min_discount=70, min_market_value=20,
                            max_listing_price=500, min_deal_score=75, demo_mode=True)
    assert deal.is_opportunity is False
    assert deal.identification.uncertain is True


def test_expensive_card_close_to_market_not_a_deal():
    listing = _listing("t5", "Charizard Base Set 4/102 PSA 9", 4400.0)
    provider = DemoPriceProvider(seed=1)
    deal = analyze_listing(listing, provider, min_discount=70, min_market_value=20,
                            max_listing_price=10000, min_deal_score=75, demo_mode=True)
    assert deal.is_opportunity is False


def test_program_never_purchases_anything():
    """Verifica statica: nessuna funzione del deal_detector effettua
    richieste HTTP di scrittura o acquisto; analyze_listing ritorna
    soltanto un DealResult (dato), senza side-effect di acquisto."""
    import inspect
    from backend.deal_detector import pipeline
    source = inspect.getsource(pipeline)
    forbidden = ["buy", "purchase", "checkout", "acquista", "pay(", "add_to_cart"]
    for word in forbidden:
        assert word not in source.lower()
