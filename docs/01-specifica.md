# Specifica della strategia — Range mensile + reazione H4 (v0.1)

Questa specifica traduce in regole la strategia swing discrezionale descritta dal trader. Il mensile dice
**dove** cercare l'operazione, l'H4 dice **quando** prezzo e volumi giustificano l'ingresso. L'analisi
avviene su TradingView, mentre l'esecuzione è affidata a un Expert Advisor su MetaTrader 5 con qualsiasi
broker compatibile.

Documenti collegati:

- [02-casi-ricostruiti.md](02-casi-ricostruiti.md): long valido, short valido e ingresso da scartare, ricostruiti in ordine.
- [03-pseudocodice-mt5.md](03-pseudocodice-mt5.md): struttura dell'EA e pseudocodice.
- [04-piano-backtest.md](04-piano-backtest.md): piano di test, con il confronto tra uscite meccaniche e manuali.
- [`templates/`](../templates): formato delle annotazioni e della configurazione dei simboli.

---

## 0. Convenzioni

Ogni regola porta un'etichetta che dice da dove viene:

| Etichetta | Significato |
|---|---|
| **[R]** | Regola dichiarata dal trader. Il software la applica così com'è. |
| **[I-n]** | Ipotesi proposta in questa specifica per rendere la regola eseguibile. Va validata (vedi §10). |
| **[A]** | Decisione ancora discrezionale. Nella prima versione richiede un'annotazione sul grafico. |

Notazione:

| Simbolo | Definizione |
|---|---|
| `M_H`, `M_L` | Massimo e minimo della candela mensile di riferimento, ombre (spike) comprese **[R]** |
| `EQ` | Equilibrio = `(M_H + M_L) / 2` **[R]** |
| `RM` | Ampiezza del range mensile = `M_H − M_L` |
| `p(x)` | Posizione relativa di un prezzo nel range = `(x − M_L) / RM`. 0 = minimo, 0,5 = EQ, 1 = massimo |
| `R` | Distanza tra prezzo d'ingresso e stop iniziale **[R]** |
| barra chiusa | Barra la cui ora di chiusura è ≤ istante della decisione |

Principio generale: **ogni decisione di stato si prende sulla chiusura di una barra H4**. Solo
l'esecuzione degli ordini (stop, target, ingresso a rottura) avviene dentro la barra.

---

## 1. Architettura della strategia

```
 MENSILE (dove)                 H4 (quando)                        ESECUZIONE
 ─────────────                  ───────────                        ──────────
 candela di riferimento  ──►  sweep di M_L / M_H        ──►  ingresso (modo E1/E2/E3)
 M_H, M_L, EQ                 reazione o continuazione        stop = estremo del pattern
 zona sconto / premio         rottura di momentum             target = 2R
                              profilo volumi e POC            size dal rischio 0,25 / 0,5 %
```

---

## 2. Strato mensile

### 2.1 Candela di riferimento — **[A]**

Il trader sceglie una candela mensile che mostri forza dei compratori o dei venditori, valutando corpo e
ombre. Nella prima versione questa scelta **si annota** (file `annotazioni.csv`, campo `mese_rif`).

Il software calcola comunque, per ogni candela mensile chiusa, alcune metriche descrittive:

- corpo% = `|C − O| / RM`
- ombra superiore% = `(H − max(O,C)) / RM` e ombra inferiore% = `(min(O,C) − L) / RM`
- CLV (posizione della chiusura) = `(C − L) / RM`

**[I-1]** Si propone un classificatore candidato, che nella v1 lavora solo in ombra e serve a misurare
l'accordo con le scelte del trader. La candela è "forte rialzista" se corpo% ≥ 0,5 e CLV ≥ 0,7, oppure se
ombra inferiore% ≥ 0,5 e CLV ≥ 0,6. Il caso ribassista è speculare. Le soglie sono provvisorie.

### 2.2 Livelli — **[R]**

`M_H`, `M_L` ed `EQ` si calcolano sulla candela di riferimento **già chiusa**, spike comprese. Il software
li ricalcola sui dati del broker di esecuzione e li confronta con quelli annotati su TradingView (§2.6).

### 2.3 Disponibilità nel tempo — **[R]**

I livelli diventano utilizzabili dalla prima barra H4 che apre dopo la chiusura della candela mensile.
Non si usa mai la candela del mese in corso.

### 2.4 Validità per più mesi — **[A]** con regola di riserva **[I-2]**

Negli esempi i livelli restano validi per più mesi. Nella v1 il riferimento resta attivo finché il trader
non ne annota uno nuovo. Per la modalità automatica si propone che decada al primo evento tra i seguenti:

- una **chiusura mensile** fuori da `[M_L, M_H]`, cioè un'accettazione oltre il range (uno sweep dentro il mese non lo invalida);
- `N_max` mesi dalla chiusura della candela di riferimento (default 6).

Un trade già aperto non viene toccato quando il riferimento decade. Si bloccano solo i nuovi setup.

### 2.5 Zone e direzione

- Sotto `EQ` c'è la **zona sconto**, sopra `EQ` la **zona premio** **[R]**.
- La direzione non dipende dalla zona in sé, ma da **come reagisce il prezzo** quando la tocca (§3) **[R]**.
- **[I-3]** Filtro di zona: un long è ammesso solo se il prezzo d'ingresso è `< EQ`, uno short solo se è
  `> EQ`. Nell'esempio AVGO l'ingresso long è a p = 0,21, quindi sotto l'equilibrio come previsto. Il
  backtest proverà anche la variante senza filtro.

### 2.6 Coerenza dei dati tra TradingView e broker

I livelli usati per gli ordini vanno sempre ricalcolati sul feed del broker di esecuzione. La differenza
con TradingView si registra in righe del profilo (24 tick) e in % di `RM`. Sopra la tolleranza (proposta:
0,5% di `RM`) il setup viene segnalato e non eseguito automaticamente.

---

## 3. Strato H4: prezzo e volumi

### 3.1 Barre H4 allineate — **[I-4]**

La chiusura H4 osservata dal trader su TradingView può non coincidere con quella del broker.

- **Forex**: TradingView apre la sessione alle 17:00 di New York. Un broker con orario server "NY close"
  (GMT+2 d'inverno e GMT+3 d'estate, con l'ora legale USA) produce le stesse barre H4. Altri orari server no.
- **Azioni USA**: su TradingView le barre H4 della sessione regolare vanno dalle 09:30 alle 13:30 e dalle
  13:30 alle 16:00 ET. Un CFD su server GMT+3 le taglia invece alle 16:30–20:00 e alle 20:00–23:00 ora
  server, cioè alle 09:30–13:00 e alle 13:00–16:00 ET. La prima chiusura cade quindi **mezz'ora prima**.

Regola proposta: per ogni simbolo si sceglie in configurazione `allineamento_barre`. Con `BROKER` si usano
le barre native, con `TV_SESSIONE` l'EA ricostruisce le H4 dalle M1 partendo dall'ancora di sessione di
TradingView. La stessa scelta vale per la candela mensile.

### 3.2 Profilo volumi (equivalente del FRVP) — **[R]** + **[I-5]**

- L'altezza della riga è `24 × mintick di TradingView` **[R]**. Si salva come prezzo assoluto per simbolo,
  per esempio 0,24 per AVGO e 0,00024 per EURUSD a 5 decimali. Non si deriva da `SYMBOL_POINT` del broker,
  che può avere un numero di decimali diverso.
- **[I-5]** Il volume è quello reale (`real_volume`) se il broker lo fornisce, altrimenti si usa il tick
  volume. Il volume di ogni barra M1 si distribuisce in modo uniforme sulle righe tra il suo minimo e il suo
  massimo. La griglia è ancorata ai multipli dell'altezza riga.
- Il POC è la riga con più volume. A parità di volume si sceglie la riga più vicina al centro del range.
  Il prezzo del POC è il centro della riga.
- Il metodo di MT5 è un'approssimazione di quello di TradingView, e il volume CFD/FX del broker non è il
  volume di borsa che TradingView mostra per AVGO. La differenza di POC va **misurata** (piano di backtest,
  Fase 0) prima di usare il POC come filtro.

### 3.3 Intervalli del profilo — **[A]** in v1, **[I-6]** in automatico

Il trader sceglie a mano l'intervallo del Fixed Range. Nella v1 semi-automatica si annotano inizio e fine
(`frvp_da`, `frvp_a`), e la fine viene **sempre troncata** all'ultima barra chiusa prima della decisione.
In automatico si propongono due profili:

| Profilo | Inizio | Fine | Uso |
|---|---|---|---|
| **Contesto (PC)** | prima barra H4 dopo la chiusura della candela di riferimento | ultima barra H4 chiusa | dove si concentra il volume nel range |
| **Pattern (PP)** | barra di sweep | ultima barra H4 chiusa | accumulo/distribuzione intorno al livello spazzato |

**Migrazione del POC**: si confronta `POC_PC(t)` con `POC_PC(t − k)`, con k = 6 barre di default.

### 3.4 Swing H4

Gli swing sono frattali con `N = 2` barre per lato e confronto stretto. Uno swing alla barra *i* è
**noto solo dalla chiusura della barra i + N**, prima non si può usare.

### 3.5 Eventi del setup long (lo short è speculare, §3.6)

| # | Evento | Definizione | Etichetta |
|---|---|---|---|
| 1 | **Sweep** | una barra H4 ha minimo `< L*`. Il livello `L*` è `M_L` per default, oppure l'ultimo swing low confermato in zona sconto (variante) | [R] + [I-8] |
| 2 | **Rientro** | una chiusura H4 `≥ L*` entro `K` barre dall'inizio dello sweep (K per classe: azioni 6, FX e indici 12) | [I-9] |
| 2b | **Ricaduta** | dopo il rientro, una chiusura `< L*` riporta allo stato SWEPT: l'estremo resta, il contatore K riparte | [I-9] |
| 3 | **Scarto per continuazione** | prima del rientro l'estremo supera `L* − D_max × RM` (D_max = 0,15), oppure passano K barre senza rientro | [I-10] |
| 4 | **Rottura di momentum** | chiusura H4 sopra `T`, l'ultimo swing high confermato (cercato fino a 30 barre prima dello sweep). Variante accumulo: chiusura sopra il massimo di un box di ≥ 6 barre con ampiezza ≤ 1,5 × ATR(14) | [I-11] |
| 5 | **Filtro volumi** | alla rottura `POC_PC < EQ`, cioè il volume si è spostato nella parte bassa del range | [I-7] |
| 6 | **Filtro zona** | prezzo d'ingresso `< EQ` | [I-3] |
| 7 | **Estremo del pattern** | `P_low` = minimo dei minimi dallo sweep fino alla barra d'ingresso | [R] |

Il punto chiave da riprodurre è questo: **sulla barra dello sweep il caso valido e quello da scartare sono
identici**. Il software non prevede quale dei due si realizzerà. Attende la reazione (evento 2) oppure la
continuazione (evento 3). Il costo dell'attesa è un ingresso più alto: su AVGO l'ingresso è 26,39 sopra
`M_L`, cioè 0,69R.

### 3.6 Setup short (solo Forex)

Speculare al long. Il livello spazzato è `M_H` (oppure l'ultimo swing high in zona premio), il rientro è
una chiusura `≤ M_H`, la rottura è una chiusura sotto l'ultimo swing low confermato e il filtro di zona
richiede un ingresso `> EQ`.

- **Distribuzione sopra i massimi** **[I-12]**: nell'esempio short il prezzo resta qualche barra sopra i
  massimi e lì si forma volume. La regola di scarto (evento 3) quindi limita **tempo ed estensione**, non il
  numero di chiusure oltre il livello. In v1 si registra se `POC_PP > M_H` come segno di distribuzione,
  senza usarlo come filtro. `K` per lo short è un parametro separato, perché la distribuzione può durare più
  di uno sweep secco.
- **Stop = massimo del pattern + buffer** **[I-13]**: è l'ipotesi simmetrica da verificare sulle annotazioni short.
- **Secondo long all'EQ** **[A]**: se lo short arriva verso l'equilibrio e lì i compratori riprendono il
  controllo, può nascere un nuovo long. In v1 il software registra l'evento `EQ_TOCCATO` e non apre nulla.
  La regola va definita con il trader, perché il filtro [I-3] la escluderebbe.

---

## 4. Ingresso: timing — punto aperto, **[I-14]**

Sappiamo che il trader osserva le chiusure H4, ma non sappiamo se entra alla rottura, alla chiusura o sul
retest. L'EA implementa i tre modi su **lo stesso segnale**:

| Modo | Quando nasce l'ordine | Prezzo | Note |
|---|---|---|---|
| **E1 – Rottura** | dopo il rientro, appena `T` è noto | buy stop a `T` + spread (sell stop a `T` per lo short) | Fill dentro la barra. Se il prezzo è già oltre `T` quando l'ordine va piazzato, si converte in ordine a mercato (= E2) |
| **E2 – Chiusura** | alla chiusura H4 oltre `T` | a mercato, apertura della barra successiva | Usa solo informazione H4. Sui titoli c'è il rischio di gap |
| **E3 – Retest** | dopo la condizione E2 | buy limit a `T` per J = 6 barre | Si annulla se il prezzo raggiunge `T + 2R` prima del fill o se il limite scade |

**Ipotesi di lavoro [I-14]: il default è E2.** È l'unico modo che dipende solo dalle chiusure H4, che il
trader dichiara di osservare, e non risente delle differenze intrabar tra i feed. E1 ed E3 restano
varianti.

**Come si risolve il punto.** Per ogni ingresso annotato si calcolano i prezzi e gli orari che E1, E2 ed
E3 avrebbero prodotto, e si adotta il modo con l'errore mediano minore in R e in barre (soglie nel piano di
backtest, Fase 2). Sull'esempio sintetico del documento 02 lo stesso segnale dà ingressi a 326,40 (E1/E3)
e a 328,60 (E2). La scelta del modo cambia quindi R e il target di circa il 6%.

Valgono per tutti i modi: un solo trade per riferimento e per lato **[I-16]** (parametro, default 1) e
nessun ordine pendente prima del rientro. Nel caso da scartare, quindi, non c'è nulla da annullare.

---

## 5. Rischio e dimensione

- **Stop long** = `P_low − buffer` **[R]**. **Stop short** = `P_high + buffer` **[I-13]**. Il buffer è
  0 per default oppure lo spread corrente **[I-17]**: va verificato confrontando lo stop annotato con
  l'estremo reale della barra.
- **R** = `|prezzo di esecuzione − stop|`, calcolato sul **fill effettivo** (Ask per i buy, Bid per i sell).
- **Target** = esecuzione ± 2R esatti **[R]** + **[I-15]**. Su AVGO il target disegnato a 404,13 vale
  1,986R, mentre il 2R esatto è 404,67. La differenza di 0,014R si registra come tolleranza del disegno.
- **Rischio per trade**: 0,25% oppure 0,50% **[R]**, scelto a mano in v1 (input di default per classe e
  override per trade nel file annotazioni). La confluenza macro si registra in un campo dedicato.
- **Lotti** = `floor((base × rischio%) / perdita_per_lotto_allo_stop / volume_step) × volume_step`.
  - `perdita_per_lotto` viene da `OrderCalcProfit` più la commissione, così gestisce valute e contratti di qualsiasi broker.
  - Se i lotti risultano `< SYMBOL_VOLUME_MIN`, il trade **non si apre**: non si arrotonda mai per eccesso il rischio.
  - Il rischio effettivo si registra. Esempio AVGO al 0,25% su 100.000: 6,58 azioni teoriche diventano 6 con step 1, cioè un rischio dello 0,228%.
- La base di calcolo è balance o equity (input, default balance).

---

## 6. Uscita

- Stop e target stanno sul server dal momento del fill **[R]**. Non c'è breakeven né trailing, perché il
  metodo non li prevede.
- **Uscita manuale su pattern d'inversione** **[A]**: il trader chiude a mano. L'EA riconosce la chiusura
  manuale da `DEAL_REASON` (`CLIENT`, `MOBILE` o `WEB`, contro `SL`, `TP` ed `EXPERT`). La registra con
  orario e prezzo e lascia un campo `motivo` da compilare. Così le uscite manuali live entrano nel confronto
  del piano di backtest senza ricostruzioni a posteriori.

---

## 7. Mercati e direzioni

| Classe | Long | Short | v1 |
|---|---|---|---|
| Forex | sì | sì | operativo |
| Azioni | sì | **no** | operativo, solo long |
| Indici | sì | **no** | operativo, solo long |
| Materie prime | da precisare | da precisare | **SOLO_SEGNALI**: calcola e registra, nessun ordine **[A]** |
| Altro (cripto ecc.) | — | — | disabilitato |

La classe di ogni simbolo si dichiara esplicitamente in `simboli.csv`. I nomi cambiano da broker a broker
(`AVGO.US`, `#AVGO`, `US500`, `SPX500`…), quindi il software **non deduce** la classe dai metadati.
`SYMBOL_SECTOR` e `SYMBOL_PATH` servono solo come controllo di coerenza. Un simbolo senza riga di
configurazione non viene tradato.

Un segnale nella direzione vietata (per esempio uno short su AVGO) si registra come
`BLOCCATO_CLASSE`, così il backtest può misurarne la frequenza.

---

## 8. Chi decide cosa nella v1

| # | Decisione | v1 | Base | Per automatizzarla serve |
|---|---|---|---|---|
| 1 | Scelta della candela mensile di riferimento | **annotazione** | [A] | accordo con il classificatore [I-1] su ≥ 30 riferimenti annotati |
| 2 | Calcolo di M_H, M_L, EQ | software | [R] | — |
| 3 | Fine della validità del riferimento | **annotazione** (riserva [I-2]) | [A] | confronto tra le date annotate e [I-2] |
| 4 | Zona sconto/premio | software | [R] | — |
| 5 | Direzioni ammesse per classe | software (configurazione) | [R] | materie prime: regola dal trader |
| 6 | Intervallo del Fixed Range | **annotazione** (troncata alla decisione) | [A] | accordo POC annotato e POC [I-6] |
| 7 | Calcolo di profilo e POC | software | [I-5] | validazione TV↔MT5 (Fase 0) |
| 8 | "Il volume si sposta" | software | [I-7] | conferma sulle annotazioni |
| 9 | Rilevamento dello sweep | software | [R] + [I-8] | — |
| 10 | **Reazione o continuazione dopo la rottura del minimo** | software | [I-9], [I-10] | calibrazione di K e D_max su trade e scarti annotati |
| 11 | Tipo di pattern (rounding, accumulo, distribuzione) | **annotazione** come etichetta, software per il trigger | [A] + [I-11] | confronto tra etichette e trigger rilevati |
| 12 | Livello di trigger T | software | [I-11] | annotazione del livello usato dal trader |
| 13 | **Timing d'ingresso** | software con modo parametrico, default E2 | [I-14] | ingressi annotati con orario |
| 14 | Stop long | software | [R] + [I-17] | — |
| 15 | Stop short | software | [I-13] | trade short annotati |
| 16 | Target 2R | software | [R] + [I-15] | — |
| 17 | Rischio 0,25 / 0,5 % | **manuale** | [R] | regola sulla confluenza macro |
| 18 | Dimensione della posizione | software | — | — |
| 19 | Uscita manuale su inversione | **trader** (il software registra) | [A] | esito del confronto della Fase 3 |
| 20 | Secondo long all'EQ | **annotazione**, nessun ordine | [A] | regola dal trader |
| 21 | Short con 2R oltre EQ | software: resta 2R | domanda aperta | risposta del trader |
| 22 | Nuovo ingresso dopo uno stop sullo stesso riferimento | software: no | [I-16] | annotazioni |

---

## 9. Parametri

| Parametro | Default | Ipotesi |
|---|---|---|
| `RischioPct` | 0,25 (override 0,50) | [R] |
| `TargetR` | 2,0 | [R] |
| `ModoIngresso` | E2 | [I-14] |
| `FrattaleN` | 2 | [I-11] |
| `K_rientro` long/short | azioni 6 / FX 12 / indici 12 barre | [I-9] |
| `D_max` | 0,15 × RM | [I-10] |
| `Lookback_T` | 30 barre | [I-11] |
| `J_retest` | 6 barre | [I-14] |
| `Buffer_stop` | 0 o spread | [I-17] |
| `Filtro_EQ`, `Filtro_POC` | attivi | [I-3], [I-7] |
| `N_max_mesi` | 6 | [I-2] |
| `MaxTradePerRifLato` | 1 | [I-16] |

`D_max` = 0,15 separa i due scenari di AVGO, perché l'estremo valido è a 0,091 RM sotto `M_L`. Però è
calibrato su **un solo punto**: è un valore di partenza, non una stima.

---

## 10. Registro delle ipotesi

| ID | Ipotesi | Come si verifica |
|---|---|---|
| I-1 | Classificatore della candela di riferimento | accordo (precisione/richiamo) con i riferimenti annotati |
| I-2 | Il riferimento decade a una chiusura mensile fuori range o dopo 6 mesi | confronto con le date in cui il trader cambia riferimento |
| I-3 | Long solo sotto EQ, short solo sopra EQ | trade annotati fuori zona (se esistono, l'ipotesi cade) |
| I-4 | Allineamento delle barre a TradingView | % di barre H4 con stessa apertura e chiusura; trigger identici con le due basi |
| I-5 | Profilo M1 con distribuzione uniforme e volume tick come ripiego | distanza POC TV↔MT5 in righe sugli stessi intervalli |
| I-6 | Ancore automatiche dei profili | distanza tra POC automatico e POC annotato |
| I-7 | Filtro POC_PC < EQ (long) | quota di trade annotati che lo soddisfano |
| I-8 | Livello di sweep = estremo mensile | trade annotati su swing interni al range |
| I-9 | Rientro entro K barre con chiusura | distribuzione delle barre tra sweep e rientro nei trade annotati |
| I-10 | Scarto oltre D_max o dopo K barre | scarti annotati correttamente esclusi, trade validi non esclusi |
| I-11 | Momentum = chiusura oltre l'ultimo swing frattale | livello T contro livello annotato |
| I-12 | Distribuzione short = POC_PP oltre M_H | annotazioni short |
| I-13 | Stop short = massimo del pattern | stop short annotati |
| I-14 | Timing E2 di default, scelto tra E1/E2/E3 dai dati | errore mediano di prezzo e barra per modo |
| I-15 | Target 2R esatto | differenza tra target annotato e 2R |
| I-16 | Un trade per riferimento e lato | annotazioni con più ingressi sullo stesso riferimento |
| I-17 | Buffer dello stop | stop annotato contro estremo reale |

---

## 11. Domande aperte per il trader

1. Entri alla rottura del livello, alla chiusura H4 oltre il livello o sul retest? Cambia per asset?
2. Quale livello rompe il "momentum": l'ultimo massimo relativo, il bordo dell'accumulo o una trendline del rounding?
3. Su AVGO, 290,67 è esattamente il minimo del pattern o c'è un margine?
4. Il target a 404,13 è un 2R arrotondato nel disegno o c'è un motivo (un livello)?
5. Per lo short, se il 2R cade oltre l'equilibrio tieni il 2R o ti fermi all'EQ?
6. "Massimi precedenti" nello short significa il massimo mensile o gli ultimi massimi H4?
7. Quando smetti di usare una candela mensile come riferimento?
8. Come scegli inizio e fine del Fixed Range?
9. Dopo uno stop, rientri sullo stesso riferimento?
10. Che cosa decide 0,25% contro 0,5% (asset, confluenza macro, entrambi)?
11. Sulle materie prime operi in entrambe le direzioni?
12. Quali pattern d'inversione ti fanno chiudere prima del target?
