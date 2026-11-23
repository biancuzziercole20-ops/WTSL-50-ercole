# Pokémon Vinted Deal Scanner

Sistema per individuare annunci Vinted di carte Pokémon proposte a un prezzo
molto scontato rispetto al valore di mercato stimato. **Non acquista mai
automaticamente** — rileva, analizza e notifica soltanto.

Leggi prima `ARCHITECTURE.md` per capire cosa funziona davvero fin da
subito e cosa richiede una fonte dati Vinted autorizzata che ancora non
esiste in forma pubblica.

---

## 1. Struttura del progetto

```
pokemon-vinted-scanner/
├── ARCHITECTURE.md          # analisi architetturale (leggere per primo)
├── README.md                # questo file
├── requirements.txt
├── .env.example
├── pytest.ini
├── run_demo.py               # test rapido da terminale, senza server
├── config/
│   └── settings.py           # configurazione centrale (letta da .env + DB)
├── backend/
│   ├── main.py                # FastAPI: API REST per la dashboard
│   ├── scanner/                # connettori (demo / manual_feed / vinted_api stub) + orchestratore
│   ├── card_identifier/        # parsing testuale nome/set/numero/variante
│   ├── image_analyzer/         # OCR immagini (pytesseract)
│   ├── market_data/             # stima valore di mercato (provider pluggable)
│   ├── deal_detector/            # sconto, deal score, filtro anti-frode
│   ├── database/                  # SQLite: modelli, schema, repository
│   ├── notifications/              # Telegram, desktop, suono, email
│   └── demo_data/                   # dati simulati per la modalità test
├── frontend/                  # dashboard Next.js/React
│   ├── pages/                  # Live Scanner, Opportunità, Storico, Impostazioni
│   ├── components/
│   └── lib/api.js               # client REST verso il backend
├── database/                  # file scanner.db (creato al primo avvio)
└── tests/
    ├── unit/
    └── integration/
```

---

## 2. Installazione — Windows

1. Installa **Python 3.11+** da python.org (spunta "Add Python to PATH").
2. Installa **Node.js 18+ LTS** da nodejs.org.
3. Apri **PowerShell** nella cartella del progetto.
4. Crea ed attiva un ambiente virtuale Python:
   ```powershell
   py -m venv venv
   venv\Scripts\activate
   ```
5. Installa le dipendenze backend:
   ```powershell
   pip install -r requirements.txt
   ```
6. (Opzionale ma consigliato per l'OCR reale) Installa **Tesseract OCR** per
   Windows da https://github.com/UB-Mannheim/tesseract/wiki e assicurati che
   `tesseract.exe` sia nel PATH. Senza Tesseract, il modulo di analisi
   immagini funziona comunque, ma restituirà sempre "Identificazione
   incerta" per l'OCR (il parsing testuale continua a funzionare
   normalmente).
7. Copia il file di configurazione:
   ```powershell
   copy .env.example .env
   ```
8. Installa le dipendenze frontend:
   ```powershell
   cd frontend
   npm install
   copy .env.local.example .env.local
   cd ..
   ```

Su macOS/Linux i comandi sono equivalenti (`python3 -m venv venv`,
`source venv/bin/activate`, `cp` invece di `copy`).

---

## 3. Avvio del backend

```bash
# dalla cartella principale del progetto, con il venv attivato
uvicorn backend.main:app --reload --port 8000
```

Il backend si avvia in modalità **demo** di default (`APP_MODE=demo` in
`.env`) e avvia automaticamente lo scanner con dati simulati. L'API è
disponibile su `http://localhost:8000` (endpoint principali: `/api/status`,
`/api/opportunities`, `/api/history`, `/api/logs`, `/api/config`).

---

## 4. Avvio del frontend

In un secondo terminale:

```bash
cd frontend
npm run dev
```

Apri `http://localhost:3000` nel browser. La dashboard mostra:

- **Live Scanner** — stato, ultimo/prossimo controllo, contatori, opportunità recenti;
- **Opportunità** — tabella completa con link "APRI ANNUNCIO";
- **Storico Prezzi** — ricerca per nome carta;
- **Impostazioni** — modifica di tutti i parametri (soglie, notifiche) senza toccare il codice.

---

## 5. Eseguire in modalità TEST/DEMO (nessuna richiesta reale)

Due modi:

**A. Da terminale, senza web server** (verifica rapida di tutta la pipeline):
```bash
python run_demo.py
```
Stampa annunci analizzati, identificazione carte, valori di mercato,
sconti, Deal Score, log ed eventuali eventi di rate-limit simulato.

**B. Con dashboard completa**: avvia backend e frontend come sopra con
`APP_MODE=demo` (default). Lo scanner userà i 22 annunci simulati in
`backend/demo_data/generate_demo_listings.py`, che includono: veri affari,
falsi positivi (proxy/custom, bundle, oggetto sbagliato), carte comuni,
carte vintage costose, carte danneggiate e un annuncio che cambia prezzo/
compare nel tempo per testare la deduplica.

---

## 6. Eseguire i test automatici

```bash
pip install pytest   # incluso in requirements.txt
pytest
```

I test coprono: calcolo sconto (con l'esempio numerico della specifica),
classificazione priorità, identificazione carte (incluso il caso
"Charizard ex 199/165" vs "Charizard 4/102"), tolleranza a errori di
battitura, filtro anti-frode (proxy, bundle, carte danneggiate), Deal
Score, deduplica annunci (nessuna notifica ripetuta, notifica solo su
cambio prezzo significativo), e un test di integrazione end-to-end
dell'intera pipeline in modalità demo.

Sono stati eseguiti manualmente in questo ambiente di sviluppo (20/20
superati) prima della consegna.

---

## 7. Configurare Telegram

1. Scrivi a **@BotFather** su Telegram, invia `/newbot` e segui le
   istruzioni per ottenere un **bot token**.
2. Avvia una conversazione con il tuo nuovo bot (cerca il suo username e
   premi "Avvia").
3. Ottieni il tuo **chat_id**: visita
   `https://api.telegram.org/bot<IL_TUO_TOKEN>/getUpdates` dopo aver
   inviato un messaggio al bot, e leggi il campo `"chat":{"id": ...}`.
4. Inserisci `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHAT_ID` in `.env` (o dalla
   dashboard, pagina Impostazioni) e imposta `TELEGRAM_ENABLED=true`.

---

## 8. Passare dalla modalità DEMO alla modalità reale

**Importante**: leggi prima `ARCHITECTURE.md`. Riepilogo:

| Cosa | Stato |
|---|---|
| Identificazione testo, OCR, calcolo sconto, Deal Score, filtro anti-frode, database, notifiche | Funzionano già con dati reali, indipendentemente da Vinted |
| Acquisizione annunci da Vinted in tempo reale | **Richiede una fonte dati autorizzata** (vedi sotto) |
| Prezzi di mercato reali (invece della tabella demo) | **Richiede una API key** di un provider come PriceCharting/TCGplayer/Cardmarket |

Per attivare una fonte annunci reale e lecita, hai due opzioni:

**Opzione A — `manual_feed` (disponibile subito):**
1. Copia `backend/demo_data/manual_feed_example.json` in un nuovo file (es.
   `manual_feed.json`), e popolalo tu stesso con annunci che hai trovato
   navigando Vinted normalmente (copia-incolla titolo, prezzo, url,
   immagini). Nessuna automazione tocca Vinted.
2. Imposta in `.env`:
   ```
   APP_MODE=manual_feed
   MANUAL_FEED_PATH=./manual_feed.json
   ```
3. Riavvia il backend. Ogni volta che aggiorni il file, lo scanner userà i
   nuovi dati al ciclo successivo.

**Opzione B — `vinted_api` (richiede una fonte autorizzata futura):**
1. Se in futuro disponi di un accesso lecito (API ufficiale per sviluppatori,
   accordo di partnership, feed dati concesso in licenza), apri
   `backend/scanner/vinted_connector_stub.py` e implementa `fetch_listings()`
   usando quella fonte, rispettando i rate limit che essa stessa dichiara.
2. Imposta `APP_MODE=vinted_api` in `.env`.
3. Aggiorna `recommended_min_interval_seconds()` nello stesso file con il
   valore minimo imposto dalla fonte dati.

Per i **prezzi di mercato reali**, crea una nuova classe in
`backend/market_data/` che eredita da `PriceProviderBase`
(`backend/market_data/price_provider_base.py`) e implementa
`get_recent_sales()` / `get_graded_value()` usando la API del provider
scelto (richiede una tua chiave API). Sostituisci `DemoPriceProvider` con
la nuova classe in `backend/main.py` (variabile `price_provider`).

---

## 9. Note di qualità e verifica effettuate

- **Calcolo sconto**: verificato con l'esempio della specifica (mercato
  €200, prezzo €60 → 70%) e con casi limite (prezzo sopra al mercato →
  sconto negativo, correttamente scartato).
- **Deduplica**: un annuncio che resta online per più cicli non genera
  righe duplicate né notifiche ripetute; una nuova notifica parte solo su
  variazione di prezzo ≥5%, nuova identificazione o nuovo annuncio.
- **Database**: schema SQLite con `listings`, `price_history`, `scan_log`,
  `settings_overrides`, `scan_stats`; storico prezzi separato per
  permettere l'analisi nel tempo per singola carta.
- **Notifiche**: Telegram/email falliscono in modo esplicito e loggato se
  mal configurate (nessun errore silenzioso); desktop/suono degradano
  senza bloccare la pipeline se l'ambiente non li supporta.
- **Nessun acquisto automatico**: verificato anche con un test automatico
  che analizza staticamente il codice del deal detector per assicurarsi
  che non contenga logica di acquisto/pagamento.
- **Gestione rate limit**: `ScanOrchestrator` intercetta `RateLimitedError`/
  `BlockedError`, applica backoff esponenziale (fino a un tetto di 10
  minuti), logga l'evento e mostra lo stato "PAUSED_..." in dashboard;
  nessun tentativo di bypass.
- **Componenti non testabili con dati reali**: l'acquisizione automatica da
  Vinted e i prezzi di mercato reali (vedi tabella sopra) non possono
  essere verificati in questa consegna perché richiedono l'accesso lecito
  che l'utente dovrà procurarsi; il resto della pipeline è stato
  verificato end-to-end in modalità demo con esito positivo.
