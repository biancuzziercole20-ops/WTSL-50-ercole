"""
Generatore di annunci simulati per la MODALITÀ TEST/DEMO (punto 20 della
spec). Nessuna richiesta di rete reale viene effettuata.

Fornisce almeno 20 annunci Pokémon simulati che coprono tutti i casi
richiesti: veri affari, falsi positivi, carte comuni, carte costose,
carte danneggiate, annunci duplicati (stesso ID che ricompare, con e
senza variazione di prezzo, per testare la deduplica).

generate_demo_listings(cycle) viene chiamata ad ogni ciclo di scansione
simulato: la maggior parte degli annunci resta identica (per testare che
NON vengano rinotificati, punto 11), mentre alcuni cambiano nel tempo per
testare price_changed / nuovo annuncio.
"""
from typing import List
from datetime import datetime, timezone
from backend.database.models import Listing

PLACEHOLDER_IMG = "demo://placeholder-card-image.jpg"


def _base_listings() -> List[dict]:
    return [
        # --- VERI AFFARI (sconto reale, alta confidence) ---
        {
            "listing_id": "demo-001", "title": "Charizard ex 199/165 Obsidian Flames NM",
            "description": "Carta Charizard ex in ottime condizioni, mai giocata, near mint.",
            "price": 13.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },
        {
            "listing_id": "demo-002", "title": "Umbreon VMAX 215/203 Evolving Skies alt art",
            "description": "Umbreon VMAX alt art, condizioni eccellenti, no piegature.",
            "price": 78.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },
        {
            "listing_id": "demo-003", "title": "Rayquaza VMAX 218/203 Evolving Skies",
            "description": "Rayquaza VMAX in buone condizioni.",
            "price": 25.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },
        {
            "listing_id": "demo-004", "title": "Lugia Silver Tempest 186/195",
            "description": "Lugia, condizioni mint, mai toccata.",
            "price": 12.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },
        {
            "listing_id": "demo-005", "title": "Sylveon VMAX 203/203 Evolving Skies alt art PSA 9",
            "description": "Sylveon VMAX gradata PSA 9, certificato incluso.",
            "price": 220.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },

        # --- CARTE COSTOSE (vintage, alto valore) ---
        {
            "listing_id": "demo-006", "title": "Charizard Base Set 4/102 1999 PSA 9",
            "description": "Charizard originale Base Set 1999, gradata PSA 9, certificato ufficiale.",
            "price": 3800.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },
        {
            "listing_id": "demo-007", "title": "Blastoise Base Set 2/102 vintage",
            "description": "Blastoise vintage Base Set, raw, condizioni buone.",
            "price": 140.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },
        {
            "listing_id": "demo-008", "title": "Venusaur Base Set 15/102 vintage played",
            "description": "Venusaur vintage, giocata, qualche segno di usura.",
            "price": 120.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },

        # --- CARTE COMUNI (basso valore, sconto insufficiente) ---
        {
            "listing_id": "demo-009", "title": "Pikachu Celebrations 5/25",
            "description": "Pikachu Celebrations, condizioni buone.",
            "price": 15.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },
        {
            "listing_id": "demo-010", "title": "Eevee Celebrations 8/25",
            "description": "Eevee comune, nessun difetto visibile.",
            "price": 10.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },
        {
            "listing_id": "demo-011", "title": "Zacian V Sword & Shield 138/202",
            "description": "Zacian V, condizioni normali, leggero segno su un angolo.",
            "price": 13.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },

        # --- CARTE DANNEGGIATE (deal score basso nonostante sconto alto) ---
        {
            "listing_id": "demo-012", "title": "Giratina VSTAR 131/196 Lost Origin danneggiata",
            "description": "Giratina VSTAR con carta piegata e angoli rovinati, whitening evidente.",
            "price": 8.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },
        {
            "listing_id": "demo-013", "title": "Espeon VMAX 203/172 Brilliant Stars rovinata",
            "description": "Espeon VMAX danneggiata, piegatura centrale, macchia visibile.",
            "price": 9.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },

        # --- FALSI POSITIVI: proxy/custom/non originale ---
        {
            "listing_id": "demo-014", "title": "Charizard ex 199/165 custom proxy alta qualità",
            "description": "Riproduzione custom stile Obsidian Flames, non originale, ottima per giocare.",
            "price": 3.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },

        # --- FALSI POSITIVI: bundle/lotto ---
        {
            "listing_id": "demo-015", "title": "Lotto 50 carte Pokemon comuni incluso Mewtwo",
            "description": "Bundle di 50 carte comuni, incluse alcune EX, prezzo per tutto il lotto.",
            "price": 20.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },

        # --- FALSI POSITIVI: prezzo riferito ad altro oggetto ---
        {
            "listing_id": "demo-016", "title": "Album porta carte Pokemon Charizard cover",
            "description": "Solo il binder con immagine di Charizard in copertina, nessuna carta inclusa.",
            "price": 6.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },

        # --- FALSI POSITIVI: nessuna immagine, identificazione incerta ---
        {
            "listing_id": "demo-017", "title": "Carta pokemon rara vendo urgente",
            "description": "Vendo carta pokemon, guardate voi che carta è, sconosco il valore.",
            "price": 5.0, "images": [], "language": None,
        },

        # --- Altri veri affari per varietà ---
        {
            "listing_id": "demo-018", "title": "Gengar Fusion Strike 271/264 alt art",
            "description": "Gengar alt art, condizioni ottime, near mint.",
            "price": 18.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },
        {
            "listing_id": "demo-019", "title": "Mew 151 151/165 illustration rare",
            "description": "Mew illustration rare, mint condition.",
            "price": 11.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },
        {
            "listing_id": "demo-020", "title": "Arceus VSTAR 123/172 Brilliant Stars",
            "description": "Arceus VSTAR, condizioni eccellenti.",
            "price": 19.0, "images": [PLACEHOLDER_IMG], "language": "English",
        },
        {
            "listing_id": "demo-021", "title": "Dragonite VSTAR Silver Tempest 104/195",
            "description": "Dragonite VSTAR, mai giocata.",
            "price": 9.0, "images": [PLACEHOLDER_IMG], "language": "Italian",
        },
    ]


def generate_demo_listings(cycle: int = 0) -> List[Listing]:
    data = _base_listings()

    # Simulazione di variazione prezzo nel tempo per testare price_changed:
    # ogni 3 cicli il prezzo di demo-003 scende ulteriormente.
    if cycle > 0 and cycle % 3 == 0:
        for item in data:
            if item["listing_id"] == "demo-003":
                item["price"] = round(item["price"] * 0.85, 2)

    # Simulazione di un nuovo annuncio che compare dopo qualche ciclo.
    if cycle >= 2:
        data.append({
            "listing_id": "demo-022", "title": "Mewtwo Shining Fates SV49/SV94 shiny vault",
            "description": "Mewtwo shiny vault, condizioni mint, nuovo annuncio.",
            "price": 7.0, "images": [PLACEHOLDER_IMG], "language": "English",
        })

    now = datetime.now(timezone.utc).isoformat()
    listings = []
    for item in data:
        listings.append(Listing(
            listing_id=item["listing_id"],
            url=f"https://www.vinted.it/items/demo-{item['listing_id']}",
            title=item["title"],
            description=item["description"],
            price=item["price"],
            currency="EUR",
            images=item["images"],
            seller="demo_seller",
            country="IT",
            language=item.get("language"),
            posted_at=now,
            detected_at=now,
            raw_source=item,
        ))
    return listings
