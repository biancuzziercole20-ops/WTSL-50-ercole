"""
Catalogo di riferimento: nomi Pokémon noti, set, rarità, varianti.

NOTA: la lista di Pokémon qui sotto è un sottoinsieme di esempio (come da
spec, "NON limitarti a questi Pokémon"). Il parser (parser.py) funziona
anche su nomi non presenti in questa lista, usando pattern generici
(qualunque parola con iniziale maiuscola seguita da indicatori di rarità
come "ex", "GX", "V", numeri set, ecc.). La lista serve principalmente per
il fuzzy-matching degli errori di battitura più comuni.
"""

KNOWN_POKEMON = [
    "Charizard", "Pikachu", "Umbreon", "Gengar", "Mew", "Mewtwo", "Rayquaza",
    "Lugia", "Giratina", "Espeon", "Eevee", "Blastoise", "Venusaur",
    "Sylveon", "Glaceon", "Leafeon", "Vaporeon", "Jolteon", "Flareon",
    "Dragonite", "Gyarados", "Snorlax", "Lucario", "Garchomp", "Greninja",
    "Zacian", "Zamazenta", "Palkia", "Dialga", "Arceus", "Darkrai",
    "Tyranitar", "Salamence", "Metagross", "Kyogre", "Groudon", "Latias",
    "Latios", "Celebi", "Jirachi", "Deoxys", "Reshiram", "Zekrom", "Kyurem",
]

KNOWN_SETS = [
    "Base Set", "Jungle", "Fossil", "Team Rocket", "Gym Heroes", "Neo Genesis",
    "Neo Discovery", "Neo Revelation", "Neo Destiny", "Expedition", "Aquapolis",
    "Skyridge", "EX Ruby & Sapphire", "EX Team Magma vs Team Aqua",
    "Diamond & Pearl", "Platinum", "HeartGold & SoulSilver", "Black & White",
    "XY", "Sun & Moon", "Sword & Shield", "Scarlet & Violet",
    "Evolving Skies", "Brilliant Stars", "Astral Radiance", "Lost Origin",
    "Silver Tempest", "Crown Zenith", "Paldea Evolved", "Obsidian Flames",
    "Fusion Strike", "Chilling Reign", "Vivid Voltage", "Darkness Ablaze",
    "Rebel Clash", "Battle Styles",
    "Paradox Rift", "Paldean Fates", "Temporal Forces", "Twilight Masquerade",
    "151", "Celebrations", "Hidden Fates", "Shining Fates", "Champion's Path",
]

CARD_TYPES = [
    "EX", "GX", "V", "VMAX", "VSTAR", "Full Art", "Illustration Rare",
    "Special Illustration Rare", "Hyper Rare", "Gold", "Secret Rare",
    "Promo", "Vintage", "Japanese",
]

VARIANT_KEYWORDS = [
    "alt art", "alternate art", "1st edition", "prima edizione", "shadowless",
    "reverse holo", "holo", "non holo", "full art", "gold", "rainbow",
    "textured", "jumbo",
]

GRADING_PATTERNS = {
    "PSA": r"PSA\s*(10|9|8|7|6|5|4|3|2|1)",
    "CGC": r"CGC\s*(10|9\.5|9|8\.5|8|7\.5|7)",
    "BGS": r"BGS\s*(10|9\.5|9|8\.5|8|7\.5|7)",
}

CONDITION_KEYWORDS = {
    "mint": ["mint", "nm", "near mint", "come nuova"],
    "excellent": ["excellent", "eccellente", "ottime condizioni"],
    "good": ["good", "buone condizioni", "played", "giocata"],
    "damaged": ["damaged", "rovinata", "danneggiata", "piegata", "bent", "creased", "rovinato"],
}

DEFECT_KEYWORDS = [
    "piegata", "piegato", "bent", "crease", "creased", "graffio", "graffiata",
    "scratch", "macchia", "stained", "angoli rovinati", "corner wear",
    "whitening", "sbiancatura", "danneggiata", "danneggiato", "rovinata",
    "strappata", "torn", "scolorita", "faded",
]

FAKE_SIGNAL_KEYWORDS = [
    "proxy", "custom", "fanmade", "fan made", "replica", "copia", "riproduzione",
    "not original", "non originale", "bootleg", "orica",
]
