from backend.deal_detector.discount_calculator import calculate_discount, classify_priority


def test_discount_basic_example_from_spec():
    # Esempio dalla specifica: Market value = 200, Listing = 60 -> 70%
    assert calculate_discount(200, 60) == 70.0


def test_discount_example_2():
    assert calculate_discount(100, 30) == 70.0


def test_discount_no_market_value():
    assert calculate_discount(0, 30) == 0.0
    assert calculate_discount(None, 30) == 0.0


def test_discount_negative_when_overpriced():
    assert calculate_discount(100, 150) == -50.0


def test_classify_priority_thresholds():
    assert classify_priority(85) == "ECCELLENTE"
    assert classify_priority(80) == "ECCELLENTE"
    assert classify_priority(79.9) == "INTERESSANTE"
    assert classify_priority(70) == "INTERESSANTE"
    assert classify_priority(65) == "DA VERIFICARE"
    assert classify_priority(60) == "DA VERIFICARE"
    assert classify_priority(59.9) == "NORMALE"
    assert classify_priority(0) == "NORMALE"
