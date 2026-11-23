import os
import tempfile
from backend.database.db import init_db
from backend.database.repository import ScanRepository
from backend.database.models import Listing
from backend.deal_detector.pipeline import analyze_listing
from backend.market_data.demo_price_provider import DemoPriceProvider


def _make_repo():
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    tmp.close()
    init_db(tmp.name)
    return ScanRepository(tmp.name), tmp.name


def _listing(price):
    return Listing(
        listing_id="dup-1", url="https://example.test/dup-1",
        title="Charizard ex 199/165 Obsidian Flames NM", description="near mint",
        price=price, currency="EUR", images=["demo://img.jpg"], language="Italian",
    )


def test_same_listing_seen_multiple_times_is_not_duplicated():
    """Punto 11: se lo stesso annuncio rimane online, non deve creare
    righe duplicate né richiedere una nuova notifica ogni volta."""
    repo, path = _make_repo()
    provider = DemoPriceProvider(seed=1)
    try:
        results = []
        for _ in range(5):  # simula 5 cicli di scansione consecutivi
            deal = analyze_listing(_listing(13.0), provider, min_discount=70,
                                    min_market_value=20, max_listing_price=500,
                                    min_deal_score=75, demo_mode=True)
            kind = repo.upsert_deal(deal)
            should_notify = repo.should_notify("dup-1", 13.0, kind)
            if should_notify:
                repo.mark_notified("dup-1", 13.0)
            results.append((kind, should_notify))

        all_rows = repo.all_listings()
        assert len(all_rows) == 1, "l'annuncio duplicato non deve creare righe multiple"

        # solo la prima occorrenza ("new") deve generare una notifica
        assert results[0] == ("new", True)
        for kind, notified in results[1:]:
            assert kind == "unchanged"
            assert notified is False
    finally:
        os.unlink(path)


def test_price_change_triggers_new_notification():
    repo, path = _make_repo()
    provider = DemoPriceProvider(seed=1)
    try:
        deal1 = analyze_listing(_listing(13.0), provider, min_discount=70,
                                 min_market_value=20, max_listing_price=500,
                                 min_deal_score=75, demo_mode=True)
        kind1 = repo.upsert_deal(deal1)
        notify1 = repo.should_notify("dup-1", 13.0, kind1)
        if notify1:
            repo.mark_notified("dup-1", 13.0)

        # prezzo cambia significativamente (>=5%)
        deal2 = analyze_listing(_listing(9.0), provider, min_discount=70,
                                 min_market_value=20, max_listing_price=500,
                                 min_deal_score=75, demo_mode=True)
        kind2 = repo.upsert_deal(deal2)
        notify2 = repo.should_notify("dup-1", 9.0, kind2)

        assert kind1 == "new"
        assert kind2 == "price_changed"
        assert notify2 is True
        assert len(repo.all_listings()) == 1
    finally:
        os.unlink(path)
