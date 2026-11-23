# Pokémon Deal Scanner

Scanner modulare per marketplace Pokémon con notifiche Telegram.

## Regole implementate
- 15 piattaforme configurabili: Vinted, eBay, Cardmarket, Subito, Facebook Marketplace,
  Wallapop, Mercari, Depop, Etsy, TCGplayer, Carousell, OLX, Leboncoin,
  Kleinanzeigen, Gumtree.
- eBay: solo prezzo fisso.
- Controllo titolo + descrizione per individuare prezzi fittizi.
- "scambio/scambi" è ammesso.
- Prezzo reale necessario prima del confronto di mercato.
- Benchmark Cardmarket: carta/versione + lingua + condizione.
- Alert se valore Cardmarket >= prezzo reale * 1.95.
- Eccezione: prezzo reale 1 EUR -> valore Cardmarket minimo 10 EUR.
- Template Telegram fisso definito dall'utente.
- Priorità P1/P2/P3/P4 e rate limit configurabili.
- Deduplicazione 24h.

IMPORTANTE: i connector/scanner delle piattaforme richiedono una fonte dati/API/feed
effettivamente disponibile. Il progetto non finge di avere accesso a marketplace che
non hanno ancora credenziali/feed configurati.
