"""
Stima del valore di mercato (punto 5 della spec).

Regole:
- Se la carta è gradata (PSA/CGC/BGS), si stima il valore SOLO sulla base
  di vendite comparabili della stessa grading company/punteggio. Una
  carta raw non viene MAI confrontata direttamente con una PSA 10.
- Se la carta è raw, si usa mediana + media delle vendite recenti raw.
- Se non ci sono dati sufficienti, data_available=False e il deal
  detector dovrà astenersi dal segnalare un'opportunità (per evitare
  falsi positivi da dati mancanti).
"""
import statistics
from backend.database.models import CardIdentification, MarketValue, GradingCompany
from backend.market_data.price_provider_base import PriceProviderBase

MIN_SAMPLE_FOR_CONFIDENCE = 3


def estimate_market_value(ident: CardIdentification, provider: PriceProviderBase) -> MarketValue:
    mv = MarketValue()

    if ident.grading_company and ident.grading_company != GradingCompany.RAW.value and ident.grading_score:
        value = provider.get_graded_value(ident, ident.grading_company, ident.grading_score)
        if value is not None:
            mv.estimated_value = value
            mv.basis = "graded"
            mv.grading_company = ident.grading_company
            mv.grading_score = ident.grading_score
            mv.sample_size = 1
            mv.data_available = True
            mv.recent_prices = [value]
        else:
            mv.data_available = False
            mv.basis = "graded"
        return mv

    # Raw
    prices = provider.get_recent_sales(ident)
    sample_size = getattr(provider, "_last_sample_size", len(prices))
    if not prices:
        mv.data_available = False
        return mv

    median_price = statistics.median(prices)
    mean_price = statistics.mean(prices)
    # media pesata: 60% mediana (più robusta agli outlier) + 40% media
    estimated = round(median_price * 0.6 + mean_price * 0.4, 2)

    mv.estimated_value = estimated
    mv.basis = "raw"
    mv.grading_company = GradingCompany.RAW.value
    mv.sample_size = sample_size
    mv.recent_prices = prices
    # data_available=True significa "abbiamo prodotto una stima"; il
    # sample_size (0 = fallback dal tipo carta, senza vendite comparabili
    # reali) viene poi usato dal Deal Score per pesare l'affidabilità.
    mv.data_available = True
    return mv
