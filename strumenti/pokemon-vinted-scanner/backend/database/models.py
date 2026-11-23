"""Modelli dati (dataclass) condivisi da tutta la pipeline."""
from dataclasses import dataclass, field
from typing import Optional, List
from enum import Enum


class CardType(str, Enum):
    STANDARD = "standard"
    EX = "EX"
    GX = "GX"
    V = "V"
    VMAX = "VMAX"
    VSTAR = "VSTAR"
    FULL_ART = "Full Art"
    ILLUSTRATION_RARE = "Illustration Rare"
    SPECIAL_ILLUSTRATION_RARE = "Special Illustration Rare"
    HYPER_RARE = "Hyper Rare"
    GOLD = "Gold"
    SECRET_RARE = "Secret Rare"
    PROMO = "Promo"
    VINTAGE = "Vintage"


class GradingCompany(str, Enum):
    RAW = "RAW"
    PSA = "PSA"
    CGC = "CGC"
    BGS = "BGS"
    OTHER = "OTHER"


@dataclass
class Listing:
    """Annuncio grezzo così come restituito da un connettore (qualsiasi fonte)."""
    listing_id: str          # identificatore univoco dell'annuncio (dedup)
    url: str
    title: str
    description: str
    price: float
    currency: str
    images: List[str] = field(default_factory=list)
    seller: Optional[str] = None
    country: Optional[str] = None
    language: Optional[str] = None
    posted_at: Optional[str] = None
    detected_at: Optional[str] = None
    raw_source: Optional[dict] = None  # payload originale, per debug/audit


@dataclass
class CardIdentification:
    """Esito dell'identificazione testuale + OCR di una carta."""
    pokemon_name: Optional[str] = None
    card_name: Optional[str] = None
    set_name: Optional[str] = None
    card_number: Optional[str] = None
    variant: Optional[str] = None      # es. "Alt Art", "1st Edition"
    card_type: Optional[str] = None    # CardType
    language: Optional[str] = None
    year: Optional[int] = None
    rarity: Optional[str] = None
    grading_company: str = GradingCompany.RAW.value
    grading_score: Optional[str] = None  # es. "10", "9"
    condition: Optional[str] = None
    defects: List[str] = field(default_factory=list)
    text_confidence: float = 0.0   # 0-100, da parsing testo
    image_confidence: float = 0.0  # 0-100, da OCR immagini
    confidence: float = 0.0        # combinata
    uncertain: bool = True
    notes: List[str] = field(default_factory=list)


@dataclass
class MarketValue:
    estimated_value: Optional[float] = None
    basis: str = "unknown"          # "raw" | "graded"
    grading_company: str = GradingCompany.RAW.value
    grading_score: Optional[str] = None
    sample_size: int = 0
    recent_prices: List[float] = field(default_factory=list)
    data_available: bool = False


@dataclass
class DealResult:
    listing: Listing
    identification: CardIdentification
    market_value: MarketValue
    discount_percentage: float = 0.0
    deal_score: float = 0.0
    priority: str = "NORMALE"       # ECCELLENTE | INTERESSANTE | DA VERIFICARE | NORMALE
    is_opportunity: bool = False
    fraud_flags: List[str] = field(default_factory=list)
    reasons: List[str] = field(default_factory=list)
