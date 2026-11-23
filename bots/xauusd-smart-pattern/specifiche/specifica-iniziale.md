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
START
  │
  ▼
[1] SUPPORT/RESISTANCE IDENTIFICATA E VALIDA?
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
[12] VOLUME (0.10 default) VALIDO PER IL BROKER?
     (min/max/step) — nessun aumento automatico dopo perdita
     │
     NO ──────────────────────────────► NO TRADE (non forzare volume invalido)
     │
    YES
     ▼
[13] PATTERN DUPLICATO SU STESSO MOVIMENTO?
     (se più pattern coincidono, seleziona solo il migliore per qualità/priorità)
     │
     ▼
DECISIONE FINALE: BUY / SELL
(con log completo: TF status, zona, liquidity grab, candela, pattern,
 MTF confirmation, setup type, score, SL, TP, RR, motivazione)
```

---

## 6. NOTE DI IMPLEMENTAZIONE (per il passaggio successivo al codice)

- Tutti i moltiplicatori/soglie citati (`InpDojiBodyRatio`, `InpLongCandleMultiplier`, `InpNoWickThreshold`, `InpRejectionWickRatio`, `InpMaxZoneDistancePips`, `InpMinRR`, soglie di score) diventano **input EA**, non costanti nel codice.
- Il calcolo di S/R deve produrre zone (range di prezzo), non singole linee, per gestire correttamente `DistanceFromZone`.
- Va prevista una funzione centrale `GetPipSize()` chiamata da ogni punto che confronta distanze in pip, per evitare disallineamenti tra moduli.
- Nessuna martingala, nessun aumento di lotto automatico: il volume è sempre `InpLotSize`, validato contro `SYMBOL_VOLUME_MIN/MAX/STEP` prima di ogni invio ordine.
- Il log di decisione (sezione §"decisione finale esempio" del documento originale) va implementato come funzione di stampa strutturata, richiamata sia per i trade eseguiti sia per i NO TRADE, per permettere verifica/backtest a posteriori.

---

Fammi sapere se questa specifica rispecchia esattamente la tua strategia (in particolare le soglie di default nello scoring e i parametri di anatomia candela) oppure se vuoi modificare pesi, soglie o priorità dei pattern prima che io generi `XAUUSD_SMART_PATTERN_SCALPER.mq5`.
