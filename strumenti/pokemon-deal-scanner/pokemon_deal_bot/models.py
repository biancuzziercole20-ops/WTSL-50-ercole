from dataclasses import dataclass
from typing import Optional

@dataclass
class Listing:
    platform: str
    url: str
    title: str
    description: str
    price: Optional[float]
    currency: str = "EUR"
    seller: str = "N/D"
    language: Optional[str] = None
    condition: Optional[str] = None

@dataclass
class CardMarketData:
    card_name: str
    value: float
    language: Optional[str]
    condition: Optional[str]
    rarity: Optional[str] = None
    demand: Optional[str] = None
    sales_data: Optional[str] = None
