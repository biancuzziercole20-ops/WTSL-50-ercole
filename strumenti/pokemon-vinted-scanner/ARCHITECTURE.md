# Architettura — Pokémon Vinted Deal Scanner

## Analisi preliminare: cosa può funzionare davvero e cosa no

Prima di scrivere una riga di codice applicativo, ecco la valutazione onesta richiesta.

### 1. Accesso diretto e automatico a Vinted — NON disponibile in modo pienamente affidabile

Vinted **non pubblica un'API pubblica di terze parti** per la ricerca annunci su larga scala, e il sito è protetto da sistemi anti-bot (rate limiting aggressivo, fingerprinting, blocchi IP/account). Uno scraping automatico a intervalli di 10 secondi:

- violerebbe quasi certamente i Termini di Servizio di Vinted;
- verrebbe rapidamente rilevato e bloccato (captcha, HTTP 429, ban IP/account).

Per esplicita richiesta, questo programma **non implementa alcuna tecnica di elusione** (bypass captcha, fingerprint falsi, account multipli, bypass rate limit). Di conseguenza:

**→ Il modulo di accesso reale a Vinted è sostituito da un connettore ad architettura plug-in (`VintedConnectorBase`), con tre implementazioni:**

| Connettore | Stato | Note |
|---|---|---|
| `DemoConnector` | ✅ Funzionante al 100% | Genera annunci simulati per test completo di tutta la pipeline |
| `ManualFeedConnector` | ✅ Funzionante | Legge annunci da un file JSON/CSV che l'utente popola con dati raccolti manualmente o tramite un metodo di export consentito (es. salvataggio manuale, estensione browser personale, futura API ufficiale) |
| `VintedAPIConnector` | ⚠️ Placeholder documentato, disattivato di default | Punto di innesto per una **fonte dati autorizzata** (API ufficiale Vinted se/quando disponibile per sviluppatori, un feed RSS/partner, o un servizio di terze parti con licenza). Non contiene codice di scraping: solleva `NotImplementedError` con istruzioni su come collegare una fonte lecita. |

Il resto della pipeline (identificazione, stima valore, scoring, filtri, notifiche, database) è **agnostico rispetto alla fonte**: qualunque connettore fornisca annunci nel formato standard `Listing`, tutto il resto funziona identicamente.

### 2. Stima del valore di mercato — parzialmente disponibile senza chiavi API

Non esiste una fonte gratuita e no-ToS-violation per prezzi Pokémon in tempo reale. Sono disponibili (a pagamento/con registrazione):

- **PriceCharting API** (a pagamento, dati storici PSA/raw)
- **TCGplayer API** (richiede approvazione partner)
- **Cardmarket API** (richiede app token, mercato EU)

**→ Soluzione adottata:** un'astrazione `PriceProviderBase` con:
- `DemoPriceProvider` (✅ funzionante): tabella di riferimento locale (`reference_prices.json`) con prezzi raw/graded/PSA10/PSA9/PSA8 simulati ma realistici, usata in modalità test.
- Punto di innesto per collegare in futuro un provider reale (`RealPriceProviderStub`), documentato nel README, richiede una API key dell'utente.

### 3. Componenti che funzionano già in modo completo e reale (indipendentemente da Vinted)

- Parsing/identificazione testuale della carta (nome, set, numero, variante, lingua) — regex + fuzzy matching, **funziona su qualunque testo reale**.
- OCR/analisi immagini — usa `pytesseract` (Tesseract OCR) se installato, altrimenti dichiara "Identificazione incerta" senza inventare dati.
- Calcolo sconto, Deal Score, filtro anti-falsi-affari — matematica pura, **funziona sempre**.
- Database SQLite, storico prezzi, deduplica annunci — **funziona sempre**.
- Notifiche Telegram/desktop/suono/email — **funzionano davvero** con le credenziali dell'utente.
- Gestione rate-limit/backoff/circuit breaker — **funziona sempre**, testata anche in demo tramite simulazione di HTTP 429.

### Flusso dati

```
[Connector: Demo | ManualFeed | VintedAPI(stub)]
        │  Listing grezzo (titolo, prezzo, immagini, url, ...)
        ▼
[card_identifier] → nome, set, numero, variante, lingua, confidence testuale
        │
        ▼
[image_analyzer] → OCR su immagini (se disponibili) → arricchisce/conferma identificazione, confidence immagine
        │
        ▼
[market_data] → stima valore (raw/graded, PSA10/9/8) da PriceProvider
        │
        ▼
[deal_detector] → discount %, anti-fraud filter, Deal Score 0-100
        │
        ▼
[database] → upsert con dedup su ID annuncio, storico prezzi
        │
        ▼
[notifications] → Telegram / desktop / suono / email (solo se nuova opportunità o cambiamento rilevante)
        │
        ▼
[frontend dashboard] → polling REST API → tabella opportunità, live status, storico
```

Questa architettura è descritta in dettaglio anche in `README.md`, insieme alle istruzioni per passare dalla modalità DEMO a una modalità reale quando l'utente disporrà di una fonte dati/API consentita.
