from backend.card_identifier.parser import identify_card_from_text


def test_distinguishes_same_pokemon_different_numbers():
    """Punto 3 della spec: 'Charizard ex 199/165' non deve essere confuso
    con 'Charizard 4/102'."""
    a = identify_card_from_text("Charizard ex 199/165 Obsidian Flames", "")
    b = identify_card_from_text("Charizard 4/102 Base Set", "")
    assert a.card_number == "199/165"
    assert b.card_number == "4/102"
    assert a.card_number != b.card_number
    assert a.pokemon_name == b.pokemon_name == "Charizard"
    assert a.card_type == "EX"


def test_typo_tolerance_recognizes_vmax_variants():
    """Punto 15: tollerare errori di battitura comuni."""
    variants = [
        "umbreon vmax alt art",
        "umbreon vmax",
        "umbreon vmax 215",
        "umbreon v max",
    ]
    for text in variants:
        ident = identify_card_from_text(text, "")
        assert ident.pokemon_name == "Umbreon", f"fallito per: {text}"
        assert ident.card_type == "VMAX", f"fallito per: {text}"


def test_fuzzy_pokemon_name_typo():
    ident = identify_card_from_text("Pikacchu rara scintillante", "")
    assert ident.pokemon_name == "Pikachu"


def test_uncertain_when_no_pokemon_found():
    ident = identify_card_from_text("oggetto misterioso da collezione", "")
    assert ident.uncertain is True
    assert ident.pokemon_name is None


def test_grading_detection():
    ident = identify_card_from_text("Charizard 4/102 Base Set PSA 9", "")
    assert ident.grading_company == "PSA"
    assert ident.grading_score == "9"


def test_defect_and_condition_detection():
    ident = identify_card_from_text(
        "Giratina VSTAR", "carta piegata con angoli rovinati, danneggiata"
    )
    assert ident.condition == "damaged"
    assert len(ident.defects) > 0
