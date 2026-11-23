# XAUUSD SMART PATTERN SCALPER — SPECIFICA TECNICA COMPLETA

---

## 0. DEFINIZIONI MATEMATICHE DI BASE

### 0.1 Point / Tick / Pip su XAUUSD

Non vanno confusi. Il bot li deriva a runtime dal broker, non li assume fissi:

```
Digits          = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)      // spesso 2 o 3 su XAUUSD
Point           = SymbolInfoDouble(_Symbol, SYMBOL_POINT)        // incremento minimo di prezzo
TickSize        = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)
TickValue       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)
```

Definizione operativa di **1 pip** per XAUUSD in questo EA:

```
PipSize = (Digits == 3 || Digits == 5) ? Point * 10 : Point
```

Cioè: se il broker quota con un decimale "extra" (es. 3333.215 con Digits=3), il pip è 10 point; se quota a 2 decimali (3333.21, Digits=2), il pip coincide con 10 point comunque nella convenzione oro standard (1 pip = 0.10 USD di movimento). Questo valore va reso **verificabile a log all'avvio** (stampa Digits, Point, TickSize, PipSize calcolato) così è controllabile manualmente prima di autorizzare il trading live.

Tutte le distanze SL/TP nel codice sono calcolate in **prezzo assoluto**, poi convertite in pip solo per il controllo del limite di 100 e per il logging. Il limite dei 100 pip si traduce quindi in:

```
MaxDistancePrice = 100 * PipSize
```

### 0.2 Distanza dalla zona (DistanceFromZone)

```
DistanceFromZone (in pip) = |PrezzoIngressoProposto - LivelloZona| / PipSize
```

Confrontata con `InpMaxZoneDistancePips` (parametro configurabile, default es. 15 pip) per giudicare se una candela/ingresso è ancora "candela della strategia" o si è già allontanata troppo.

### 0.3 Soglie configurabili di anatomia candela

```
BodySize        = |Close - Open|
UpperWick       = High - MAX(Open, Close)
LowerWick       = MIN(Open, Close) - Low
TotalRange      = High - Low
BodyRatio       = BodySize / TotalRange
UpperWickRatio  = UpperWick / TotalRange
LowerWickRatio  = LowerWick / TotalRange
ClosePosition   = (Close - Low) / TotalRange     // 0 = chiude sul minimo, 1 = chiude sul massimo
OpenPosition    = (Open  - Low) / TotalRange
```

Tutte le soglie sotto ("wick nulla", "corpo grande", "candela lunga") sono espresse come input configurabili, mai hard-coded.

---

## 1. TABELLA DEI 5 PATTERN

| Campo | PATTERN 1 — BREAKOUT | PATTERN 2 — ENTRATA IMPULSIVA | PATTERN 3 — TREND FOLLOW | PATTERN 4 — FAKE OUT | PATTERN 5 — BREAK THE TREND |
|---|---|---|---|---|---|
| **Condizione 1** | Prezzo raggiunge zona S/R identificata | Prezzo vicino a un estremo del range (non centro) | Bias/trend definito su TF superiore | Movimento diretto verso zona opposta al trend corrente | Trend precedente chiaro (rialzista o ribassista) |
| **Condizione 2** | Candela rompe la zona (corpo, non solo wick) | Reazione visibile sul livello (S in basso, R in alto) | Impulso nella direzione del trend | Penetrazione/rottura temporanea della zona (liquidity grab) | Prezzo arriva su S/R in contro-tendenza |
| **Condizione 3** | Chiusura oltre la zona ma `DistanceFromZone` entro soglia | Candela/e di pressione (corpo forte, wick coerente) | Pullback verso zona/supporto-resistenza dinamica | Rientro del prezzo dentro la zona dopo il grab | Engulfing contro-trend valido (definizione §Engulfing) |
| **Condizione 4** | Nessuna estensione eccessiva (no long candle chase) | Conferma M15 nella direzione dell'estremo | Reazione di conferma sulla zona di pullback | Comparsa di conferma nella nuova direzione (rejection candle/engulfing) | Identificazione di un livello di trigger e sua rottura |
| **Conferma** | Candela successiva conferma o regole di ingresso diretto su chiusura/corpo | Candela di forza + eventuale conferma M15 | Struttura IMPULSO→PULLBACK→ZONA→REAZIONE→CONTINUAZIONE completa | Conferma M15 forte richiesta (probabilità più bassa) | Rottura effettiva del trigger, non solo avvicinamento |
| **Invalidazione** | Wick break senza chiusura del corpo oltre la zona; extended move | Prezzo nel centro del range | Pullback che rompe struttura (non torna sulla zona attesa) | Nessun rientro nella zona / nessuna conferma dopo il grab | Engulfing non valido (corpo non ingloba) o trigger non rotto |
| **Entry** | Sulla rottura di chiusura/corpo della candela di setup (mai sulla wick) | Al livello dell'estremo del range, dopo conferma | Sulla continuazione dopo reazione in zona | Alla chiusura della candela di setup (M30/H1 evidente + M15 già confermata) o su nuova conferma | Sulla rottura del trigger |
| **SL** | Sotto/sopra la wick o minimo/massimo strutturale del setup | Oltre l'estremo del range/zona di reazione | Oltre la zona di pullback | Oltre l'estremo del liquidity grab (wick profonda) | Sotto/sopra il minimo/massimo strutturale del setup |
| **TP** | Prossima zona di liquidità/S-R, max 100 pip | Verso l'estremo opposto del range, max 100 pip | Estensione del trend, max 100 pip | Verso zona opposta, max 100 pip, gestione conservativa | Prossima zona di R/S o liquidità, max 100 pip |
| **Timeframe** | M15/M30 (setup), H1/H4/D1 (contesto) | M30, H1 principali | Tutti i TF, pullback letto su M15/M30 | M30/H1 per il grab, M15 per la conferma | Individuazione trend su H1/H4, trigger su M15/M30 |
| **Scalp normale** | Se confermato da D1/H4/H1 coerenti | Se confermato da TF superiori | Se trend coerente su tutti i TF | Solo se conferme molto forti e coerenza TF | Se trend + engulfing + trigger tutti confermati da TF superiori |
| **Scalp locale** | Se TF superiori non confermano ma zona è forte + conferma M15 forte | Se TF superiori neutrali/misti ma reazione locale netta | Se pullback valido ma bias superiore debole/neutrale | Fake out è per natura più "locale": richiede sempre conferma extra | Se trend locale (H1) chiaro ma D1/H4 non allineati, con conferma M15 forte |
| **No trade** | Wick break senza chiusura oltre zona, o prezzo già troppo esteso | Prezzo nel centro range, o nessuna conferma M15 | Pullback assente o struttura incompleta | Nessun rientro nella zona, o conferma M15 assente/debole | Engulfing non valido, trigger non rotto, o setup contro TF superiori senza conferma locale forte |

---

## 2. TABELLA ANATOMIA DELLE CANDELE

| Tipo candela | Definizione matematica | Significato | Dove è valida | Dove NON è valida | Conferma richiesta | Effetto sullo score | Effetto sulla decisione |
|---|---|---|---|---|---|---|---|
| **Doji** | `BodyRatio <= InpDojiBodyRatio` (es. 0.10) | Indecisione | Su S/R dopo movimento diretto; dopo liquidity grab | Nel mezzo del range senza altro contesto | Sì, sempre: dipende da "dove/dopo cosa/con quale bias/con quale zona" | Nessun bonus da solo; può azzerare/ridurre score di altri segnali in conflitto | Mai BUY/SELL da solo. Su zona → possibile rejection da confermare. Nel mezzo range → contribuisce a NO TRADE |
| **Candela molto lunga (Long Candle)** | `TotalRange > AverageRange(N) * InpLongCandleMultiplier` (ATR o range medio su N candele) | Movimento eccessivamente esteso, rischio di inseguire il prezzo | Come informazione di contesto vicino a un livello | Come base per un ingresso diretto (chasing) | Non impiegabile da sola per ingresso; richiede attesa di struttura più pulita | Penalità se l'ingresso richiesto è oltre `InpMaxZoneDistancePips` | Se l'ingresso implica inseguire il prezzo → forza NO TRADE (o attesa) |
| **Candela senza wick finale (Marubozu di chiusura)** | BUY: rialzista + `UpperWickRatio <= InpNoWickThreshold` + `ClosePosition >= InpCloseNearHigh`. SELL: ribassista + `LowerWickRatio <= InpNoWickThreshold` + `ClosePosition <= InpCloseNearLow` | Forte pressione direzionale | Particolarmente su M30/H1, su livello importante | Come segnale isolato senza livello rilevante | Deve avvenire su zona rilevante per contare come conferma | Bonus "candela di qualità" solo se su zona | Mai sufficiente da sola; rafforza pattern 1/2/3 se allineata alla zona |
| **Candela senza wick iniziale** | BUY: `OpenPosition <= InpNoWickThreshold` + corpo rialzista forte (`BodyRatio` alto). SELL: `OpenPosition >= 1 - InpNoWickThreshold` + corpo ribassista forte | Pressione direzionale dall'apertura | Contestualizzata con zona/Bias/struttura/liquidità/pattern | Come segnale isolato | Sì, sempre in combinazione con altri elementi | Bonus minore, cumulativo con altri fattori | Mai da sola; supporto a pattern esistente |
| **Candela della strategia** | `DistanceFromZone <= InpMaxZoneDistancePips`; può chiudere fuori dal range ma resta in relazione diretta con la zona | Mantiene validità operativa rispetto alla zona | Sempre richiesta come pre-condizione per ingresso su qualunque pattern | Se `DistanceFromZone` supera la soglia | N/A (è una condizione di validità, non un segnale a sé) | Se non rispettata, il setup perde punteggio "S/R forte" | Se violata → penalizza fortemente fino a NO TRADE |
| **Bullish/Bearish Engulfing** | Bullish: precedente ribassista, attuale rialzista, `BodyOpenAttuale <= BodyCloseAttuale` che ingloba interamente `[Open;Close]` della precedente (solo corpi, non wick). Bearish: speculare | Cambio di pressione tra compratori/venditori | Particolarmente rilevante in Break The Trend, su zona S/R | Come pattern isolato lontano da zone | Sì: rottura di un trigger/livello dopo l'engulfing (per Pattern 5) | Bonus se completo + su zona | Componente necessaria (non sufficiente) di Pattern 5; rafforza altri pattern se presente |
| **Wick di rigetto (Rejection Wick)** | Wick lunga: `UpperWickRatio` o `LowerWickRatio >= InpRejectionWickRatio` (es. 0.5) | Possibile rifiuto del prezzo | Su S/R, coerente con direzione precedente e liquidità | Nel mezzo del range | Valutata insieme a chiusura e corpo, non da sola | Bonus se su zona + direzione coerente | Contribuisce a Fake Out / Break The Trend; da sola non genera trade |
| **Wick fill** | Prezzo successivo che rientra/reagisce rispetto a una wick precedente, in relazione a zona/liquidità/direzione | Reazione del mercato a un eccesso di prezzo precedente | Quando collegata a zona e direzione coerenti | Se applicata automaticamente a ogni wick senza contesto | Sì, relazione esplicita zona+direzione+liquidità | Bonus contestuale, non fisso | Supporto a Fake Out / Liquidity Grab, mai standalone |
| **Liquidity Grab** | Superamento temporaneo di un massimo/minimo rilevante + mancato mantenimento (chiusura che rientra nella zona) + wick di penetrazione | Cattura di liquidità oltre un livello prima dell'inversione/continuazione | M30/H1/H4 principalmente | Se il breakout si mantiene (chiusura stabile oltre il livello → è un vero breakout, non un grab) | Sì: candela successiva + struttura M15 | Bonus significativo (+10 nello scoring base) | Elemento chiave per Fake Out; rafforza anche Pattern 1 (distinzione da falso breakout) |

---

## 3. SCORING DEL SETUP

Sistema a punti (pesi configurabili via input, valori di default):

| Componente | Peso |
|---|---|
| D1 Bias coerente | +20 |
| H4 coerente | +15 |
| H1 coerente | +10 |
| Supporto/Resistenza forte (validata da reazioni storiche/toccate multiple) | +15 |
| Liquidity Grab presente | +10 |
| Pattern completo (tutte le condizioni verificate) | +15 |
| Conferma M15 | +10 |
| Candela di qualità (marubozu su zona, engulfing valido) | +5 |
| Volume/pressione (se disponibile tick volume) | +5 |
| **Totale massimo** | **105** (normalizzabile a 100) |

### Categorie di output

| Categoria | Soglia score (default, configurabile) | Condizione aggiuntiva |
|---|---|---|
| PREMIUM | `>= InpScorePremium` (es. 85) | D1+H4+H1 tutti coerenti |
| VALID | `>= InpScoreValid` (es. 65) | Almeno D1+H4 coerenti, o H1+M30+M15 fortemente coerenti |
| LOCAL SCALP | `>= InpScoreLocalScalp` (es. 75, **più alto** di VALID come richiesto) | TF superiori non coerenti MA zona forte + liquidity grab/engulfing + conferma M15 forte |
| NO TRADE | Sotto le soglie precedenti, o violazione di un requisito assoluto (SL/TP > 100 pip, prezzo troppo lontano dalla zona, R:R insufficiente) | — |

Nota: **LOCAL SCALP richiede uno score minimo più alto di VALID**, non più basso — coerente con la richiesta "richiesta di conferma locale più forte".

---

## 4. MATRICE DECISIONALE MULTI-TIMEFRAME (riepilogo operativo)

| Caso | D1 | H4 | H1 | M30 | M15 | Esito |
|---|---|---|---|---|---|---|
| A | BUY | BUY | BUY | Setup | Conferma | SETUP PREMIUM — gestione normale |
| B | BUY | BUY | NEUTRAL | Setup | Conferma | SETUP VALID |
| C | BUY | NEUTRAL | SELL | Pattern | Conferma forte | LOCAL SCALP (SL/TP più vicini, rischio ridotto, score minimo alto) |
| D | BUY | SELL | SELL | BUY | Debole | NO TRADE |
| E | Non conferma | Non conferma | Non conferma | Pattern completo | Conferma forte + zona forte + liquidity grab/engulfing + R:R valido | LOCAL SCALP possibile |

Principio: **timeframe superiori contrari ≠ NO TRADE automatico**. Significa: setup più rischioso → richiede più conferme + gestione più conservativa. NO TRADE scatta solo quando anche la conferma locale è debole o assente.

---

## 5. DECISION TREE ESTESO

```
START (ogni tick / ogni nuova barra chiusa, secondo InpUseCloseBarsOnly)
  │
  ▼
[0a] SIMBOLO CORRETTO (XAUUSD)?
     │
     NO ──────────────────────────────► NO TRADE — motivo: simbolo non valido
     │
    YES
     ▼
[0b] FINESTRA ORARIA 07:00–12:00 EUROPE/ROME (CET/CEST) RISPETTATA?
     │
     NO ──────────────────────────────► NO TRADE — motivo: fuori finestra 07:00-12:00
     │
    YES
     ▼
[0c] TRADE ESEGUITI OGGI (giornata italiana) < InpMaxTradesPerDay (2)?
     │
     NO ──────────────────────────────► NO TRADE — motivo: limite giornaliero raggiunto (2/2)
     │
    YES
     ▼
[0d] SETUP/SEGNALE GIÀ ESEGUITO IN QUESTO MOVIMENTO (stesso SetupID)?
     │
     YES ─────────────────────────────► NO TRADE — motivo: segnale duplicato già eseguito
     │
    NO
     ▼
[0e] SPREAD CORRENTE <= InpMaxSpreadPips?
     │
     NO ──────────────────────────────► NO TRADE — motivo: spread eccessivo
     │
    YES
     ▼
[0f] DATI STORICI SUFFICIENTI SU TUTTI I TF (D1/H4/H1/M30/M15)?
     │
     NO ──────────────────────────────► NO TRADE — motivo: dati insufficienti/errore CopyRates
     │
    YES
     ▼
[1] SUPPORT/RESISTANCE IDENTIFICATA E VALIDA? (zona con upper/lower bound, forza, tocchi)
     │
     NO ──────────────────────────────► NO TRADE
     │
    YES
     ▼
[2] DISTANCE FROM ZONE ENTRO SOGLIA? (candela della strategia)
     │
     NO ──────────────────────────────► NO TRADE
     │
    YES
     ▼
[3] BIAS D1 → CONFERMA H4 → CONFERMA H1 → CONTESTO M30 → CONFERMA M15
     │  (costruzione dello stato multi-timeframe, nessuna decisione qui)
     ▼
[4] LIQUIDITY GRAB O REAZIONE PRESENTE?
     │
     (informativo, alimenta score — non blocca da solo)
     ▼
[5] QUALE DEI 5 PATTERN È PRESENTE E COMPLETO?
     │
     ├── BREAKOUT
     ├── ENTRATA IMPULSIVA (solo se prezzo a un estremo, non centro range)
     ├── TREND FOLLOW (richiede IMPULSO→PULLBACK→ZONA→REAZIONE)
     ├── FAKE OUT (richiede liquidity grab + rientro + conferma forte)
     └── BREAK THE TREND (richiede engulfing valido + rottura trigger)
     │
     NESSUNO COMPLETO ─────────────────► NO TRADE
     │
    ALMENO UNO COMPLETO
     ▼
[6] ANATOMIA CANDELA DI SETUP CONFERMA? (Doji contestuale, long candle check,
    marubozu, wick di rigetto, engulfing — vedi tabella §2)
     │
     NO / CONTRADDICE ─────────────────► NO TRADE
     │
    YES
     ▼
[7] CALCOLO SCORE (vedi §3)
     │
     ▼
[8] MTF CONFIRMATION?
     │
     ├── YES (D1/H4/H1 coerenti, score >= soglia PREMIUM/VALID)
     │        └──► NORMAL SCALP (SL/TP strutturali, entro 100 pip)
     │
     └── NO  (TF superiori non coerenti)
              ▼
         LOCAL SCALP CHECK:
         zona forte + liquidity grab/engulfing + conferma M15 forte
         + score >= soglia LOCAL SCALP (più alta di VALID)?
              │
              ├── YES ──► LOCAL SCALP (SL/TP ravvicinati, rischio ridotto)
              │
              └── NO  ──► NO TRADE
     │
     ▼
[9] CALCOLO SL STRUTTURALE
     │
     SL IMPLICA DISTANZA > 100 PIP?
     │
     ├── YES → esiste setup alternativo con SL più vicino?
     │           ├── YES → ricalcola SL, torna al punto [9]
     │           └── NO  → NO TRADE
     │
    NO (SL <= 100 pip)
     ▼
[10] CALCOLO TP (zona/liquidità successiva)
     │
     TP IMPLICA DISTANZA > 100 PIP?
     │
     ├── YES → usa target compatibile <= 100 pip esistente?
     │           ├── YES → adegua TP, continua
     │           └── NO  → NO TRADE
     │
    NO (TP <= 100 pip)
     ▼
[11] R:R VALIDO? (>= InpMinRR, es. 1:1.2)
     │
     NO ──────────────────────────────► NO TRADE
     │
    YES
     ▼
[12] STOP LEVEL / FREEZE LEVEL DEL BROKER RISPETTATI?
     (SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL)
     │
     NO ──────────────────────────────► NO TRADE — motivo: SL/TP sotto stop/freeze level broker
     │
    YES
     ▼
[13] VOLUME (InpLotSize, default 0.10) VALIDO PER IL BROKER?
     (SYMBOL_VOLUME_MIN/MAX/STEP) — nessun arrotondamento verso l'alto, nessun aumento dopo perdita
     │
     NO ──────────────────────────────► NO TRADE — motivo: volume non valido per il broker
     │
    YES
     ▼
[14] MARGINE DISPONIBILE SUFFICIENTE? (OrderCalcMargin / AccountFreeMargin)
     │
     NO ──────────────────────────────► NO TRADE — motivo: margine insufficiente
     │
    YES
     ▼
[15] POSIZIONI ESISTENTI DELL'EA (stesso Magic Number) SUL SIMBOLO
     CREANO DUPLICAZIONE INVOLONTARIA?
     │
     YES ─────────────────────────────► NO TRADE — motivo: posizione EA già aperta sul setup
     │
    NO
     ▼
[16] PATTERN DUPLICATO SU STESSO MOVIMENTO?
     (se più pattern coincidono, seleziona solo il migliore per qualità/priorità;
      mai aprire BUY e SELL sullo stesso setup)
     │
     ▼
DECISIONE FINALE: BUY / SELL
     │
     ▼
[17] INVIO ORDINE (OrderSend) CON:
     - InpMagicNumber
     - InpMaxDeviationPoints (deviation configurabile)
     - SetupID univoco per il segnale (per impedire re-invio allo stesso segnale)
     │
     ▼
[18] VERIFICA ESECUZIONE REALE (retcode, risultato OrderSend/OrderCheck)
     │
     ├── FALLITA → LOG errore con codice e descrizione, nessun retry forzato
     │
     └── OK → incrementa contatore trade giornalieri, registra SetupID come eseguito
     │
     ▼
[19] LOG FINALE STRUTTURATO (vedi §7.16) — sempre, sia per esecuzione che per rifiuto
```

---

## 7. LAYER TECNICO DI SICUREZZA, VALIDAZIONE ED EXECUTION

**Questa sezione è un'aggiunta.** Non sostituisce, non riduce e non semplifica nulla di quanto definito nelle Sezioni 0–6: pattern, anatomia candele, scoring, matrice MTF e decision tree restano invariati. Le regole seguenti sono controlli **a monte e a valle** della logica di strategia — filtri assoluti, validazione d'ordine, robustezza dati, logging, backtest-safety.

### 7.1 Filtro assoluto di orario

- Nuove aperture consentite **esclusivamente tra 07:00 e 12:00 ora Italia**, timezone `Europe/Rome`, con gestione automatica CET/CEST.
- Poiché MQL5 lavora nativamente in ora del server/broker, l'EA deve convertire l'ora del server nell'ora italiana corrente (calcolo manuale dell'offset CET/CEST basato su regole UE di cambio ora, oppure input `InpBrokerGmtOffsetHours` + `InpBrokerGmtOffsetHoursDST` configurabili, verificati a runtime) prima di qualunque valutazione.
- Fuori dalla finestra → **NO TRADE**, verifica eseguita **prima** dell'invio ordine (nodo [0b] del decision tree).

### 7.2 Massimo 2 trade al giorno

- Limite assoluto: **2 trade eseguiti** per giornata italiana (`InpMaxTradesPerDay = 2`, configurabile ma di default 2).
- Il conteggio riguarda **ordini effettivamente eseguiti**, non segnali generati o rifiutati.
- Contatore azzerato a ogni nuovo giorno italiano (rilevato tramite la stessa conversione timezone di §7.1).
- Dopo il secondo trade eseguito → blocco totale nuove aperture fino al giorno successivo (nodo [0c]).
- Nessuna martingala, nessun aumento di lotto dopo una perdita — vale anche qui, non solo nella size di base.

### 7.3 Controllo duplicati

- Se più pattern descrivono lo stesso movimento/struttura, il sistema deve raggrupparli, confrontarli per qualità/priorità (vedi §"Regole di priorità" della specifica originale) e produrre **una sola decisione**.
- Mai BUY e SELL simultanei sullo stesso setup.
- Implementato tramite `SetupID` (vedi §7.13) confrontato contro segnali già processati nello stesso movimento (nodo [0d] e [16]).

### 7.4 Controllo delle candele chiuse

- Le decisioni operative si basano principalmente su **candele completamente chiuse** (`InpUseCloseBarsOnly`, default true).
- Una candela ancora in formazione non può dichiarare un pattern completato, salvo i casi in cui la specifica originale prevede esplicitamente esecuzione su rottura/price action intrabar (es. Pattern 1 — rottura di chiusura/corpo: la chiusura di riferimento è comunque quella della candela di setup già chiusa, non del tick corrente).
- Obiettivo: evitare segnali che cambiano continuamente durante la formazione della barra.
- Il log riporta sempre: timeframe, shift della candela analizzata, OHLC, pattern individuato, motivo di conferma/invalidazione (vedi §7.16).

### 7.5 Prevenzione del look-ahead bias

- Nessun calcolo (swing high/low, S/R, liquidity grab, engulfing, conferme M15, trend H1/H4/D1) può usare dati di barre **future** rispetto al momento della decisione.
- Ogni livello storico (zone S/R, swing) è costruito esclusivamente con barre `shift >= 1` (o comunque già chiuse) al momento del calcolo.
- Questo vincolo è strutturale: le funzioni di analisi ricevono sempre e solo l'indice della barra "corrente chiusa" come riferimento massimo, mai un indice successivo.
- Requisito esplicito di **backtest-friendliness** (vedi anche §7.21): nessun repainting.

### 7.6 Supporti e resistenze come zone

Ogni zona S/R è una struttura dati con almeno:

| Campo | Descrizione |
|---|---|
| `UpperBound` / `LowerBound` | Estremi della zona (non una singola linea) |
| `Strength` | Punteggio di forza (0–100), alimenta lo scoring §3 |
| `TouchCount` | Numero di reazioni/tocchi storici |
| `SourceTimeframe` | TF di origine (D1/H4/H1) |
| `AgeBars` / `AgeTime` | Età della zona |
| `LastBreakoutOrRetest` | Ultimo evento di rottura/retest, se presente |

- Una zona appena creata (pochi tocchi, età bassa) **non** è automaticamente forte: `Strength` parte basso e cresce con tocchi/retest confermati nel tempo, sempre senza look-ahead (§7.5).
- `Strength` entra nel componente "Supporto/Resistenza forte" dello scoring (§3).

### 7.7 Distance From Zone — implementazione centralizzata

```
GetPipSize()                       // funzione unica, richiamata ovunque
DistanceFromZone = MathAbs(entryPrice - zoneLevel) / GetPipSize()
```

- Verificata **prima** dell'ingresso (nodo [2] del decision tree).
- Se `DistanceFromZone > InpMaxZoneDistancePips` → **NO TRADE — motivo: distanza zona X pips > soglia Y pips**.
- Mai inseguire una candela già eccessivamente estesa (coerente con §"Candela molto lunga").

### 7.8 Filtro spread

- Input `InpMaxSpreadPips` (configurabile, non hard-coded).
- `CurrentSpreadPips = (Ask - Bid) / GetPipSize()`, calcolato subito prima della decisione finale.
- Se `CurrentSpreadPips > InpMaxSpreadPips` → **NO TRADE — motivo: spread eccessivo** (nodo [0e]).

### 7.9 Slippage / deviation

- Input `InpMaxDeviationPoints`, usato nella richiesta d'ordine (`MqlTradeRequest.deviation`).
- Se l'esecuzione non può rispettare la deviation configurata, l'ordine non va forzato: si registra il fallimento (§7.20) senza retry automatico a parametri diversi.

### 7.10 Controllo Stop Level del broker

*(numerazione interna coerente con nodo [12] del decision tree)*

- Verificare `SYMBOL_TRADE_STOPS_LEVEL` e `SYMBOL_TRADE_FREEZE_LEVEL` prima dell'invio.
- Se SL o TP calcolati non rispettano la distanza minima richiesta dal broker → **NO TRADE**, senza modificare arbitrariamente SL/TP per "far entrare" l'operazione a forza.

### 7.11 Validazione volume

- `InpLotSize` (default 0.10) verificato contro `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_MAX`, `SYMBOL_VOLUME_STEP`.
- Se 0.10 non è valido per il broker → **NO TRADE**. Nessun arrotondamento automatico verso un lotto diverso.

### 7.12 Controllo margine

- Margine disponibile verificato (es. tramite `OrderCalcMargin`) prima dell'invio.
- Se insufficiente → **NO TRADE**. Il lotto non viene mai ridotto automaticamente per "far entrare" il trade.

### 7.13 Un solo posizionamento per segnale

- Ogni setup/segnale riceve un `SetupID` univoco (es. hash di simbolo + timeframe + pattern + timestamp della barra di setup + zona).
- Una volta eseguito, quel `SetupID` è marcato come "consumato": il segnale che persiste sui tick successivi non genera un secondo ingresso.

### 7.14 Magic Number

- `InpMagicNumber` configurabile, applicato a ogni ordine dell'EA.
- Conteggio trade giornalieri, controllo posizioni esistenti e gestione duplicati filtrano sempre per questo Magic Number, distinguendo le operazioni dell'EA da quelle manuali o di altri EA.

### 7.15 Controllo posizioni esistenti

- Prima di aprire, l'EA scansiona le posizioni aperte filtrate per `Symbol + InpMagicNumber`.
- Impedisce duplicazioni involontarie sullo stesso simbolo/setup (nodo [15]).
- Non chiude, non modifica e non tocca in alcun modo posizioni manuali o di altri Magic Number.

### 7.16 Log diagnostico completo

Ogni valutazione (BUY, SELL, o NO TRADE) produce un log strutturato con almeno:

data/ora italiana · simbolo · spread · trade eseguiti oggi · finestra oraria OK/NO · bias D1/H4/H1 · status M30/M15 · zona S/R (bound, forza, tocchi) · distanza dalla zona · liquidity grab (sì/no + dettagli) · pattern individuato · anatomia candela rilevante · punteggio di ogni componente di scoring · score totale · categoria (PREMIUM/VALID/LOCAL SCALP/NO TRADE) · entry · SL · TP · R:R · motivo della decisione · eventuale motivo del rifiuto dell'ordine (stop level, volume, margine, spread, ecc.).

### 7.17 NO TRADE motivato

Ogni NO TRADE riporta un motivo esplicito e specifico, ad es.:

- `NO TRADE — motivo: score 61 < 65`
- `NO TRADE — motivo: fuori finestra 07:00-12:00`
- `NO TRADE — motivo: distanza zona 21.4 pips > 15 pips`
- `NO TRADE — motivo: R:R 0.94 < 1.20`
- `NO TRADE — motivo: nessun pattern completo`

Mai un semplice `"NO TRADE"` senza causa — implementato restituendo sempre, dalla funzione di decisione, una coppia `(esito, motivo)`.

### 7.18 Priorità dei filtri

Ordine di valutazione, ciascuno bloccante se fallisce (nessun tentativo di "forzare" un trade saltando un controllo):

1. Simbolo corretto
2. Giorno/orario italiano (07:00–12:00 Europe/Rome)
3. Massimo 2 trade giornalieri
4. Posizioni/setup duplicati
5. Spread
6. Disponibilità dati
7. S/R e zona
8. Distance From Zone
9. Analisi MTF
10. Pattern
11. Anatomia candele
12. Liquidity Grab
13. Score
14. Categoria setup
15. SL
16. TP
17. R:R
18. Stop/Freeze Level broker
19. Volume
20. Margine
21. Invio ordine
22. Verifica esecuzione
23. Log finale

Questo ordine è riflesso nei nodi `[0a]`…`[19]` del decision tree aggiornato in §5.

### 7.19 Robustezza dati

- Prima di calcolare pattern/indicatori, verificare che siano disponibili abbastanza barre storiche su **tutti** i timeframe utilizzati (D1/H4/H1/M30/M15).
- Dati insufficienti → **NO TRADE + log esplicativo** (nodo [0f]).
- Gestire esplicitamente eventuali errori di `CopyRates`/`CopyBuffer` (valore di ritorno negativo, array non riempito).

### 7.20 Error handling

Ogni fallimento di `OrderSend`, `OrderCheck`, `CopyRates`, `CopyBuffer`, creazione di indicator handle, selezione simbolo, modifica SL/TP viene:

- gestito esplicitamente (nessuna eccezione silenziosa);
- scritto nel log con codice errore (`GetLastError()` / retcode) e descrizione testuale;
- **mai interpretato come successo solo perché la funzione è stata chiamata** — il risultato reale (retcode di `MqlTradeResult`, esito di `OrderCheck`) è sempre verificato esplicitamente.

### 7.21 Backtest-friendly

- Nessun look-ahead bias (§7.5), nessun repainting, nessuna dipendenza non necessaria da informazioni future.
- Nessun segnale duplicato ad ogni tick (garantito da `SetupID`, §7.13, e da `InpUseCloseBarsOnly`, §7.4).
- Architettura del codice separata in moduli chiaramente distinti: **analisi → decisione → risk/validation → execution → logging**, così da poter testare/validare ciascuno strato indipendentemente nello Strategy Tester di MT5.

### 7.22 Debug mode

- Input `InpDebugMode` (bool).
- `TRUE` → log dettagliato di ogni passaggio del decision tree (inclusi i nodi intermedi valutati).
- `FALSE` → log essenziale, mantenendo comunque sempre la decisione finale (BUY/SELL/NO TRADE) e il motivo principale.

### 7.23 Sicurezza: nessun trade forzato

Principio guida, sovraordinato a tutto il layer tecnico:

**NO TRADE > TRADE NON SICURO.**

- Se una condizione fondamentale non può essere verificata con sufficiente certezza (dati mancanti, errore di calcolo, ambiguità), l'esito è **NO TRADE**.
- Nessun valore mancante viene inventato o stimato per "riempire" un calcolo.
- Nessuna condizione viene sostituita automaticamente con un'altra per far quadrare un setup.
- Nessuna soglia viene rilassata dinamicamente per trovare un'operazione.
- Nessuna martingala, nessun recovery/aumento di rischio dopo una perdita, in nessun punto del sistema.

---

## 8. NOTE DI IMPLEMENTAZIONE (per il passaggio successivo al codice)

- Tutti i moltiplicatori/soglie citati (`InpDojiBodyRatio`, `InpLongCandleMultiplier`, `InpNoWickThreshold`, `InpRejectionWickRatio`, `InpMaxZoneDistancePips`, `InpMinRR`, soglie di score) diventano **input EA**, non costanti nel codice.
- Il calcolo di S/R deve produrre zone (range di prezzo), non singole linee, per gestire correttamente `DistanceFromZone`.
- Va prevista una funzione centrale `GetPipSize()` chiamata da ogni punto che confronta distanze in pip, per evitare disallineamenti tra moduli.
- Nessuna martingala, nessun aumento di lotto automatico: il volume è sempre `InpLotSize`, validato contro `SYMBOL_VOLUME_MIN/MAX/STEP` prima di ogni invio ordine.
- Il log di decisione (sezione §"decisione finale esempio" del documento originale, estesa in §7.16) va implementato come funzione di stampa strutturata, richiamata sia per i trade eseguiti sia per i NO TRADE, per permettere verifica/backtest a posteriori.
- La conversione oraria Europe/Rome (CET/CEST) va isolata in una funzione dedicata (§7.1), testabile indipendentemente dal resto della logica.
- Il conteggio giornaliero dei trade (§7.2) e i `SetupID` consumati (§7.13) vanno mantenuti in variabili globali dell'EA persistenti per la sessione, resettate al cambio di giorno italiano.
- Architettura consigliata a moduli separati: `Analysis` (S/R, bias MTF, candele, pattern) → `Scoring` → `RiskValidation` (SL/TP/RR/stop level/volume/margine) → `Execution` (OrderSend + verifica) → `Logging`, così da rispettare sia §7.21 (backtest-friendly) sia la richiesta di non forzare mai un trade (§7.23).

---

Ho integrato tutte le specifiche tecniche aggiuntive (finestra oraria, limite giornaliero, controllo duplicati, candele chiuse, look-ahead bias, zone S/R strutturate, filtro spread/deviation/stop level/volume/margine, magic number, logging completo, priorità dei filtri, robustezza dati, error handling, backtest-friendliness, debug mode, principio "no trade forzato") come Sezione 7, senza toccare né semplificare nulla delle Sezioni 0–6 già presenti.

Fammi sapere se va bene così, o se vuoi aggiustare qualche default (es. `InpMaxSpreadPips`, `InpMaxDeviationPoints`, offset GMT del tuo broker) prima che io generi `XAUUSD_SMART_PATTERN_SCALPER.mq5`.
