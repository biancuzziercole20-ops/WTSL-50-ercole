"""Calcolo dello sconto (punto 6 della spec)."""


def calculate_discount(market_value: float, listing_price: float) -> float:
    """
    discount_percentage = ((market_value - listing_price) / market_value) * 100

    Ritorna 0 se market_value <= 0 (dato non valido) invece di sollevare
    un'eccezione: un'opportunità non può essere calcolata senza un valore
    di mercato valido, e verrà comunque scartata a valle nel deal_detector.
    """
    if not market_value or market_value <= 0:
        return 0.0
    discount = ((market_value - listing_price) / market_value) * 100
    return round(discount, 2)


def classify_priority(discount_percentage: float) -> str:
    """Punto 12 della spec."""
    if discount_percentage >= 80:
        return "ECCELLENTE"
    if discount_percentage >= 70:
        return "INTERESSANTE"
    if discount_percentage >= 60:
        return "DA VERIFICARE"
    return "NORMALE"
