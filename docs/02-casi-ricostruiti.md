# Casi ricostruiti: long valido, short valido, ingresso da scartare

I tre casi seguono la macchina a stati della specifica (§3.5–3.6) nell'ordine in cui il software prende le
decisioni. Per ognuno si distingue:

- **dato**: valore fornito dal trader;
- **calcolato**: derivato dai dati con le formule della specifica;
- **inferito**: ricostruito, ma da confermare sul grafico;
- **sintetico**: sequenza H4 inventata per provare la logica. **Non sono dati storici.**

Le sequenze sintetiche sono scritte come casi di test per l'EA, con i risultati attesi in fondo a ogni
caso. Parametri usati: `FrattaleN = 2`, `D_max = 0,15`, `K` azioni = 6, `K` FX = 12, buffer = 0, spread = 0.

---

## Caso 1 — Long valido (AVGO)

### 1.1 Ricostruzione con i dati forniti

| Passo | Stato | Valore | Fonte |
|---|---|---|---|
| 1. Riferimento mensile | candela chiusa | `M_L` = 302,28 · `M_H` = 429,56 | dato |
| | | `EQ` = 365,92 · `RM` = 127,28 | calcolato |
| 2. Volumi | contesto | il volume si sposta verso la parte bassa del range → `POC_PC < EQ` (filtro I-7) | osservazione del trader, da misurare |
| 3. Sweep | `IDLE → SWEPT` | una barra H4 ha minimo < 302,28: il prezzo prende liquidità sotto il minimo | dato |
| 4. Estremo del pattern | aggiornato a ogni barra | ≈ 290,67, cioè 11,61 sotto `M_L` = **0,091 RM** (< `D_max` 0,15 → nessuno scarto) | inferito dallo stop, con buffer 0 |
| 5. Reazione | `SWEPT → RECLAIMED` | chiusura H4 di nuovo ≥ 302,28 entro K barre: i compratori reagiscono | ipotesi I-9, da verificare sul grafico |
| 6. Rottura di momentum | `RECLAIMED → TRIGGER` | rounding o accumulo seguito dalla rottura | dato (pattern), livello non noto |
| 7. Filtri | — | ingresso 328,67 → p = **0,207 < 0,5**: entra mentre è ancora sotto il 50%, filtro I-3 rispettato | dato e calcolato |
| 8. Stop | — | 290,67 = minimo del pattern H4 | dato |
| 9. R | — | 328,67 − 290,67 = **38,00** | calcolato |
| 10. Target | — | disegnato 404,13 = **1,986R** (p = 0,800). Il bot usa 2R esatto = **404,67** (p = 0,804) | dato e calcolato |
| 11. Dimensione | conto 100.000 USD, 1 lotto = 1 azione | 0,50% → 500 / 38 = 13,16 → **13** (rischio 494, cioè 0,494%) · 0,25% → 6,58 → **6** (rischio 228, cioè 0,228%) | calcolato |

Osservazioni:

- Il target long **supera l'equilibrio** (365,92) e resta sotto `M_H`. Per il long, quindi, l'EQ non è un
  tetto. Per lo short la questione è aperta (domanda 5 della specifica).
- Con step di volume 1, lo 0,25% arrotondato per difetto diventa 0,228%. Se il broker ammette lotti
  frazionari (step 0,01), il rischio torna a 249,66.
- La modalità d'ingresso non si ricava dai numeri. Servono le barre H4 reali intorno all'ingresso per capire
  se 328,67 è il livello rotto (E1), l'apertura dopo la chiusura (E2) o un retest (E3).

### 1.2 Sequenza sintetica di test (livelli AVGO, barre inventate)

| Barra | Open | High | Low | Close | Evento atteso |
|---|---|---|---|---|---|
| 1 | 321,00 | 322,50 | 319,00 | 322,00 | |
| 2 | 322,00 | 324,00 | 318,00 | 319,50 | |
| 3 | 319,50 | **326,40** | 317,00 | 325,00 | swing high (confermato alla chiusura della barra 5) |
| 4 | 325,00 | 325,80 | 314,00 | 315,50 | |
| 5 | 315,50 | 317,00 | 306,00 | 307,00 | T = 326,40 disponibile |
| 6 | 307,00 | 308,50 | 296,00 | 299,00 | **SWEPT** (minimo < 302,28) |
| 7 | 299,00 | 301,50 | **290,67** | 300,50 | estremo = 290,67 (0,091 RM) |
| 8 | 300,50 | 309,00 | 299,50 | 308,00 | **RECLAIMED** (chiusura ≥ 302,28, 2 barre dopo lo sweep) · E1: buy stop a 326,40 |
| 9 | 308,00 | 316,00 | 306,50 | 314,50 | |
| 10 | 314,50 | 321,00 | 312,00 | 318,00 | |
| 11 | 318,00 | 320,00 | 313,50 | 316,00 | |
| 12 | 316,00 | 329,50 | 315,00 | 328,40 | E1: fill a 326,40 · **TRIGGER** (chiusura 328,40 > 326,40) |
| 13 | 328,60 | 334,00 | 325,50 | 332,00 | E2: fill all'apertura 328,60 · E3: limit 326,40 eseguito |
| 14 | 332,00 | 336,00 | 324,00 | 333,00 | |

Risultati attesi, a filtro POC considerato soddisfatto (input del test):

| Modo | Ingresso | Barra | Stop | R | Target 2R | Lotti al 0,5% su 100k |
|---|---|---|---|---|---|---|
| E1 rottura | 326,40 | 12 | 290,67 | 35,73 | 397,86 | 13 (rischio 464,49) |
| E2 chiusura | 328,60 | 13 | 290,67 | 37,93 | 404,46 | 13 (rischio 493,09) |
| E3 retest | 326,40 | 13 | 290,67 | 35,73 | 397,86 | 13 (rischio 464,49) |

Lo stesso segnale produce R diversi del 6% e target diversi di 6,6 punti: è il motivo per cui il timing va
risolto sui dati annotati (Fase 2 del piano di backtest). La sequenza è costruita a mano, quindi non dice
nulla su quale modo il trader abbia usato su AVGO.

---

## Caso 2 — Short valido (Forex, dati sintetici)

Il metodo ammette lo short solo sul Forex, per cui il caso usa una coppia FX con **livelli e barre
inventati**. Se l'esempio short del trader fosse su un'azione o un indice, il bot lo registrerebbe come
`BLOCCATO_CLASSE` senza aprire nulla.

### 2.1 Ricostruzione

| Passo | Stato | Valore |
|---|---|---|
| 1. Riferimento mensile | candela chiusa | `M_L` = 1,08000 · `M_H` = 1,12000 · `EQ` = 1,10000 · `RM` = 0,04000 |
| 2. Contesto | zona premio | il prezzo sale nella metà alta del range |
| 3. Sweep | `IDLE → SWEPT` (barra 4) | massimo 1,12150 > `M_H` |
| 4. Distribuzione sopra i massimi | barre 4–9 | il prezzo resta sopra 1,12000 per 6 barre, il massimo del pattern è 1,12350 (0,0875 RM, < `D_max`). Nella v1 si registra `POC_PP > M_H` (I-12) |
| 5. Swing low della distribuzione | barra 7 | 1,12040, confermato alla chiusura della barra 9 |
| 6. Rientro e rottura | `SWEPT → TRIGGER` (barra 10) | la chiusura a 1,11980 è sotto `M_H` **e** sotto lo swing low 1,12040 nella stessa barra |
| 7. Filtro zona | — | ingresso 1,11975 → p = 0,994 > 0,5 → ok |
| 8. Stop | — | massimo del pattern 1,12350 + buffer (I-13). Su un broker reale il buffer deve coprire lo spread, perché lo stop short scatta sull'Ask |
| 9. R | — | 1,12350 − 1,11975 = **0,00375** (37,5 pip) |
| 10. Target | — | 1,11975 − 0,00750 = **1,11225** (p = 0,806): **prima dell'EQ**, coerente con la "discesa verso l'equilibrio" |
| 11. Dimensione | conto 100.000 USD, 10 USD/pip/lotto | 0,50% → 1,333 → **1,33 lotti** (rischio 498,75) · 0,25% → 0,667 → **0,66 lotti** (rischio 247,50) |
| 12. Dopo | — | se il prezzo arriva verso 1,10000 e lì i compratori riprendono il controllo, il software registra `EQ_TOCCATO` per un possibile secondo long, **senza aprirlo** [A] |

### 2.2 Sequenza sintetica di test

| Barra | Open | High | Low | Close | Evento atteso |
|---|---|---|---|---|---|
| 1 | 1,11500 | 1,11700 | 1,11450 | 1,11650 | |
| 2 | 1,11650 | 1,11850 | 1,11600 | 1,11800 | |
| 3 | 1,11800 | 1,11950 | 1,11700 | 1,11920 | |
| 4 | 1,11920 | 1,12150 | 1,11880 | 1,12100 | **SWEPT** (massimo > 1,12000) |
| 5 | 1,12100 | 1,12300 | 1,12050 | 1,12200 | |
| 6 | 1,12200 | 1,12250 | 1,12080 | 1,12120 | |
| 7 | 1,12120 | 1,12200 | **1,12040** | 1,12150 | swing low |
| 8 | 1,12150 | **1,12350** | 1,12100 | 1,12250 | estremo del pattern |
| 9 | 1,12250 | 1,12300 | 1,12080 | 1,12180 | swing low confermato |
| 10 | 1,12180 | 1,12200 | 1,11950 | 1,11980 | **rientro + TRIGGER** nella stessa barra |
| 11 | 1,11975 | 1,12010 | 1,11800 | 1,11850 | E2: fill all'apertura 1,11975 |
| 12 | 1,11850 | 1,11900 | 1,11550 | 1,11600 | E3: limit a 1,12040 ancora non eseguito |
| 13 | 1,11600 | 1,11650 | 1,11300 | 1,11350 | E3: il prezzo raggiunge T − 2R = 1,11420 senza fill → **annullato** |
| 14 | 1,11350 | 1,11400 | 1,11150 | 1,11200 | **TP** 1,11225 (E1/E2) |

Risultati attesi:

| Modo | Ingresso | Stop | R | Target | Esito |
|---|---|---|---|---|---|
| E1 rottura | 1,11975 (convertito a mercato: il prezzo era già sotto T quando l'ordine andava piazzato) | 1,12350 | 0,00375 | 1,11225 | TP alla barra 14 |
| E2 chiusura | 1,11975 | 1,12350 | 0,00375 | 1,11225 | TP alla barra 14 |
| E3 retest | — | — | — | — | nessun trade: il retest non arriva |

Il caso mostra due comportamenti da codificare: rientro e rottura possono coincidere nella stessa barra, e
il modo retest perde i movimenti senza ritorno.

---

## Caso 3 — Ingresso da scartare (AVGO, scenario alternativo)

Riferimento identico al caso 1. Fino alla barra 6 inclusa la sequenza è **uguale** a quella del caso 1: al
momento dello sweep i due scenari non si distinguono.

### 3.1 Ricostruzione

| Passo | Stato | Valore |
|---|---|---|
| 1. Riferimento | come nel caso 1 | `M_L` = 302,28 · `EQ` = 365,92 · soglia di continuazione `M_L − 0,15 RM` = **283,19** |
| 2. Sweep | `IDLE → SWEPT` (barra 6) | minimo 296,00 |
| 3. Continuazione | resta `SWEPT` | le chiusure 293,00 → 289,00 → 283,00 restano sotto 302,28, nessun rientro |
| 4. Scarto | `SWEPT → DISCARDED` (barra 9) | minimo 281,50 < 283,19: l'estensione è 0,163 RM > `D_max`. Anche senza questa soglia, il setup sarebbe scartato dopo K = 6 barre senza rientro |
| 5. Ordini | nessuno | in nessun modo esiste un ordine pendente prima del rientro, quindi non c'è nulla da annullare |
| 6. Registro | evento `SCARTO_CONTINUAZIONE` | con estremo, barre trascorse, POC del pattern (se sotto `M_L` conferma l'accettazione) |

### 3.2 Sequenza sintetica di test

| Barra | Open | High | Low | Close | Evento atteso |
|---|---|---|---|---|---|
| 1–5 | come caso 1 | | | | T = 326,40 disponibile |
| 6 | 307,00 | 308,50 | 296,00 | 299,00 | **SWEPT** |
| 7 | 299,00 | 301,50 | 291,00 | 293,00 | |
| 8 | 293,00 | 297,00 | 287,50 | 289,00 | |
| 9 | 289,00 | 291,00 | 281,50 | 283,00 | **DISCARDED** (0,163 RM > 0,15) |
| 10 | 283,00 | 286,00 | 276,00 | 278,00 | nessuna azione |

### 3.3 Altri motivi di scarto da coprire con i test

| Motivo | Esempio | Stato / log |
|---|---|---|
| K barre senza rientro, estensione < D_max | il prezzo resta tra 295 e 301 per 6 barre | `SCARTO_NO_RIENTRO` |
| Ingresso oltre EQ | E2 con gap di apertura sopra 365,92 | `SCARTO_FILTRO_EQ` |
| Volume nella metà sbagliata | `POC_PC ≥ EQ` alla rottura | `SCARTO_FILTRO_POC` |
| Direzione vietata | short su AVGO | `BLOCCATO_CLASSE` |
| Lotto minimo oltre il rischio | stop molto largo su un conto piccolo | `SCARTO_SIZE` |
| Dati incoerenti | M_L del broker diverso da TradingView oltre la tolleranza | `SCARTO_DATI` |

---

## Nota: cosa manca per ricostruire AVGO al 100%

Per sostituire le parti "inferite" del caso 1 con dati verificati servono:

1. il mese della candela di riferimento;
2. le barre H4 (OHLCV) dallo sweep all'ingresso, esportate da TradingView con lo stesso feed e lo stesso fuso del grafico;
3. orario e prezzo dell'ingresso, il livello che il trader considerava rotto e il modo (rottura, chiusura o retest);
4. inizio e fine del Fixed Range usato, con il POC letto su TradingView;
5. l'esito: target, stop o chiusura manuale, con orario.

Con questi dati il caso 1 diventa il primo record del file annotazioni e il primo test di fedeltà (Fase 2).
