# Piano di backtest (v0.1)

## 1. Domande a cui risponde

| # | Domanda | Fase |
|---|---|---|
| D0 | I dati del broker MT5 producono gli stessi livelli, le stesse barre H4 e lo stesso POC di TradingView? | 0 |
| D1 | Il software, con le sole informazioni disponibili al momento, riproduce gli ingressi annotati e scarta i setup che il trader ha scartato? | 2 |
| D2 | Il trader entra alla rottura, alla chiusura o sul retest? (ipotesi I-14) | 2 |
| D3 | **Sugli stessi ingressi**, l'uscita meccanica a stop o 2R rende più o meno delle uscite manuali annotate? | 3 |
| D4 | Le regole automatiche ([I-1], [I-6]…) hanno un vantaggio su tutto lo storico, fuori campione? | 4 |
| D5 | In demo, esecuzione e costi reali confermano il tester? | 5 |

Il **primo test** richiesto corrisponde alle Fasi 0–3. Le Fasi 4–5 vengono dopo e non servono a decidere
D3.

---

## 2. Regola d'oro: solo ciò che era visibile al momento

Ogni decisione simulata usa solo dati con timestamp ≤ istante della decisione. Controlli obbligatori:

| Fonte di look-ahead | Regola |
|---|---|
| Candela mensile | si usa solo una candela **chiusa** (§2.3 della specifica) |
| Scelta del riferimento | l'annotazione vale da `annotato_il_utc`, non da prima |
| Fixed Range annotato | la fine dell'intervallo viene **troncata** all'ultima barra chiusa prima della decisione, anche se il disegno del trader prosegue oltre |
| Swing / frattali | uno swing alla barra i esiste solo dalla chiusura di i + N |
| Ingresso alla chiusura (E2) | fill all'apertura della barra **successiva**, non al prezzo di chiusura |
| Stop e target dentro la stessa barra | con tick reali si usa l'ordine vero; con barre M1 si assume prima lo **stop**, e si conta quante volte succede |
| Uscita manuale | entra nel test primario solo se annotata **al momento** (`stato_annotazione = LIVE`) |
| Ricostruzioni a posteriori | i trade `RETRO` vanno solo nell'analisi secondaria, sempre separata |
| Universo dei simboli | la lista si fissa **prima** del test. AVGO non deve entrare perché "è salito" |

---

## 3. Fase 0 — Dati e riconciliazione TradingView ↔ MT5

**Dati**

- Dal broker MT5 di esecuzione: M1 (e tick reali dove ci sono) per ogni simbolo del periodo.
- Da TradingView: esportazione dei dati del grafico (H4 e mensile, stessi simboli e stesso feed del
  grafico, per esempio `NASDAQ:AVGO`, `OANDA:EURUSD`). Per le azioni va annotato se il grafico è
  aggiustato per i dividendi e se mostra l'extended hours.
- Fuso: tutte le annotazioni in UTC. L'orario del server MT5 si dichiara (GMT+2/+3 con l'ora legale USA o
  altro).

**Controlli e soglie proposte**

| Controllo | Metrica | Soglia |
|---|---|---|
| Livelli mensili | \|M_H, M_L broker − TV\| | ≤ 1 riga (24 tick) o ≤ 0,5% RM in ≥ 95% dei riferimenti |
| Allineamento H4 | % di barre con stessa apertura e chiusura | 100% dopo l'allineamento [I-4]; altrimenti si registra la differenza |
| Profilo | \|POC MT5 − POC TV\| sullo stesso intervallo | ≤ 2 righe in ≥ 80% dei casi |
| Volume | correlazione del volume per barra H4 TV ↔ MT5 | da registrare (atteso basso su FX e CFD) |
| Eventi societari | split e dividendi nel periodo | elencati; prezzi non aggiustati per i livelli |

Se il POC non supera la soglia, il filtro [I-7] si disattiva per quel simbolo nelle Fasi 2–3 e la scelta si
registra.

---

## 4. Fase 1 — Archivio delle annotazioni

Il formato sta in [`templates/annotazioni.csv`](../templates/annotazioni.csv). Ogni riga è un **trade**
oppure uno **scarto**, cioè un setup che il trader ha guardato e rifiutato. Gli scarti sono indispensabili
per misurare i falsi positivi: senza di loro D1 non è verificabile.

Campi chiave per il punto-nel-tempo:

- `stato_annotazione`: `LIVE` se scritta prima dell'ingresso (o dell'uscita, per i campi di uscita),
  `RETRO` se ricostruita dopo;
- `annotato_il_utc`: quando è stata scritta l'annotazione;
- `entry_modo_dichiarato`: `BREAK`, `CLOSE`, `RETEST` o `NON_SO`;
- `uscita_tipo`: `SL`, `TP` o `MANUALE`, con `uscita_motivo` (il pattern d'inversione visto);
- `screenshot`: un link per ogni decisione.

Campione minimo indicativo: 30 trade per gruppo (FX long, FX short, azioni e indici long). Sotto i 30 i
risultati sono **descrittivi** e non bastano per decidere.

---

## 5. Fase 2 — Fedeltà degli ingressi e scelta del timing

**Configurazione**: EA in `SEMI_AUTO` nel Tester, modello "Ogni tick basato su tick reali" (o "OHLC M1"
dove i tick mancano, dichiarandolo). Riferimento e intervallo del profilo vengono dalle annotazioni. Si fa
un passaggio per ciascun modo d'ingresso E1, E2, E3.

**Abbinamento**: un trigger del bot corrisponde a un trade annotato se sono sullo stesso simbolo e lato,
sullo stesso riferimento, e il trigger cade entro ±2 barre H4 dall'ingresso annotato.

**Metriche per modo**

| Metrica | Definizione |
|---|---|
| Richiamo | trade annotati con un trigger abbinato / trade annotati |
| Falsi positivi sugli scarti | scarti annotati su cui il bot entra / scarti annotati |
| Errore di prezzo | \|ingresso bot − ingresso annotato\| / R annotato (mediana, 80° percentile) |
| Errore di tempo | barre H4 di differenza (mediana) |
| Errore di stop | \|stop bot − stop annotato\| in tick → serve a calibrare il buffer [I-17] |
| Errore di target | target annotato − 2R esatto, in R [I-15] |

**Decisione su I-14**: si adotta il modo con l'errore di prezzo mediano minore, a condizione che sia ≤ 0,10R
con errore di tempo ≤ 1 barra in almeno il 70% dei trade. Se nessun modo soddisfa la condizione, oppure se
il modo cambia per classe di asset, il timing resta un'annotazione obbligatoria e si chiede al trader. Lo
stesso vale se le dichiarazioni `entry_modo_dichiarato` contraddicono i dati.

**Soglie di fedeltà proposte**: richiamo ≥ 80% e falsi positivi ≤ 20%. I trade non riprodotti si
classificano per causa: riferimento, livello di sweep, K, D_max, trigger, filtro EQ, filtro POC, dati.
Questa classificazione dice quale ipotesi rivedere.

---

## 6. Fase 3 — Uscite: stop/2R contro uscite manuali, sugli stessi ingressi

È il confronto richiesto per il primo test. **Gli ingressi sono fissi**: sono quelli annotati (orario,
prezzo e stop iniziale), non quelli del bot. Cambia solo la regola d'uscita, quindi la differenza misura
esclusivamente il valore delle uscite.

### 6.1 Bracci

| Braccio | Regola | Sorgente |
|---|---|---|
| **A – meccanico** | dall'ingresso annotato, esce al primo tra stop iniziale e `ingresso ± 2R`, con `R = |ingresso − stop|` annotati | simulato sui dati |
| **B – manuale** | uscita annotata (`uscita_tipo = MANUALE`) se `LIVE`; altrimenti l'esito reale del trade (SL o TP) | annotazioni |

Se il trader non ha chiuso a mano, B coincide con A **per costruzione** e ΔR = 0. Questi trade servono da
**controllo di coerenza**: se A non riproduce lo stesso esito (per esempio, TP sul grafico TV ma stop sui
dati del broker), la discrepanza si segnala come problema di dati, non di strategia.

### 6.2 Simulazione del braccio A

```
per ogni trade T (tipo = TRADE, stato_annotazione = LIVE), in ordine di ingresso:
    R0 = |T.entry − T.stop|
    TP = T.entry + lato × 2 × R0
    scorri tick (o M1) da T.entry_utc in avanti:
        long : stop se Bid ≤ T.stop  |  target se Bid ≥ TP
        short: stop se Ask ≥ T.stop  |  target se Ask ≤ TP
        gap oltre lo stop all'apertura → esecuzione al prezzo di apertura (slippage reale)
        stop e TP nella stessa M1 senza tick → stop (conservativo), contatore ambiguità++
    R_A = lato × (uscita − entry) / R0 − costi_R
```

La simulazione si fa con uno script esterno (Python o foglio di calcolo) su M1 e tick esportati, perché gli
ingressi sono fissi e non generati dall'EA. Come verifica incrociata si può usare l'EA in modalità replay
(apertura all'orario annotato), registrando lo scarto tra il prezzo annotato e il fill.

### 6.3 Costi, uguali nei due bracci

- **Spread** al momento dell'uscita.
- **Commissione** per lotto.
- **Swap** per notte (`SYMBOL_SWAP_LONG/SHORT`, giorno triplo): conta molto nello swing, e il braccio A, che
  tiene di più, ne paga di più.
- **Dividendi** sui CFD azionari long: aggiustamento a credito.

Tutti i costi si esprimono in R (`costo / rischio monetario del trade`).

### 6.4 Doppia base prezzi

Il confronto si esegue due volte: **con i prezzi TradingView**, cioè quello che il trader vedeva, e **con i
prezzi del broker MT5**, cioè quello che il bot eseguirebbe. Se le conclusioni divergono, prevale la
seconda per decidere sul bot e la differenza va riportata.

### 6.5 Metriche

Per braccio: numero di trade, R totale, R medio (aspettativa), R mediano, % vincenti, profit factor,
massimo drawdown in R sulla sequenza cronologica, durata media e costo medio di swap in R.

Appaiate:

| Metrica | Definizione |
|---|---|
| ΔR_i | R_B − R_A per trade |
| ΔR medio | con intervallo di confidenza bootstrap al 95% (10.000 ricampionamenti dei trade) |
| Segno | trade con ΔR > 0, = 0, < 0 |
| Test | Wilcoxon a ranghi con segno sui soli trade con uscita manuale, se n ≥ 10 |

Diagnosi delle uscite manuali, una riga per ciascuna:

| Campo | Significato |
|---|---|
| R all'uscita manuale | quanto ha incassato il trader |
| Esito di A | dove sarebbe finito lo stesso trade (TP o SL) e quando |
| Classe | **perdita evitata** (A finisce a stop), **profitto ceduto** (A finisce a 2R), **neutra** |
| MFE dopo l'uscita | massimo movimento favorevole prima che A chiuda |
| Motivo | pattern d'inversione annotato |

La tabella per motivo, cioè quali pattern d'inversione evitano perdite e quali tagliano profitti, è
l'input per decidere se e come automatizzare le uscite manuali nella v2.

### 6.6 Lettura del risultato

| Esito | Conclusione per la v1 |
|---|---|
| IC di ΔR medio tutto > 0 | le uscite manuali aggiungono valore: tenerle e formalizzare i motivi più efficaci |
| IC che contiene 0 | nessuna differenza dimostrabile: stop/2R è sufficiente per il bot; continuare ad annotare |
| IC tutto < 0 | le uscite manuali costano: nel bot uscita solo a stop/2R |
| n < 30 o < 10 uscite manuali | solo descrittivo: nessuna decisione, si estende il campione |

### 6.7 Analisi di sensibilità

- costi raddoppiati;
- regola d'ambiguità invertita (prima il TP) per misurarne il peso;
- target al 2R esatto contro target annotato (per esempio 1,986R su AVGO);
- inclusione dei trade `RETRO`, riportata a parte.

---

## 7. Fase 4 — Regole automatiche su tutto lo storico (dopo il primo test)

1. Si sostituiscono una alla volta le annotazioni con le regole automatiche: riferimento [I-1, I-2],
   intervallo [I-6], pattern [I-11]. Ogni volta si misura l'accordo con le annotazioni (precisione e
   richiamo) prima di guardare il rendimento.
2. Si esegue il backtest completo nello Strategy Tester con tick reali, separatamente per classe.
3. Divisione temporale: si ottimizza sul 70% più vecchio e si verifica sul 30% più recente. Poi si fa un
   walk-forward con finestre mobili.
4. La griglia dei parametri resta piccola (K, D_max, FrattaleN, ModoIngresso). Si sceglie una **regione
   stabile**, non il massimo puntuale.
5. Monte Carlo sull'ordine dei trade e sull'omissione casuale del 10% dei trade per stimare la
   distribuzione del drawdown.
6. Confronto con un riferimento ingenuo, a parità di rischio: stesso ingresso senza filtri volumi e zona.

Criteri proposti: aspettativa fuori campione > 0 dopo i costi, con almeno 30 trade per classe, e nessun
parametro il cui vicino cambi il segno del risultato.

---

## 8. Fase 5 — Forward test in demo

- Almeno 3 mesi o 20 trade, su un conto demo del broker scelto. Dove possibile si aggiunge un secondo broker
  per verificare la portabilità (nomi dei simboli, step di volume, orario server, volume reale o tick).
- Il registro dell'EA si confronta con quello del tester sugli stessi giorni: slippage, rifiuti, differenze
  di trigger.
- Le uscite manuali si registrano dal vivo (`DEAL_REASON`) e alimentano la Fase 3 con dati `LIVE`.

---

## 9. Riepilogo dei criteri di passaggio

| Fase | Passa se |
|---|---|
| 0 | livelli e POC entro le soglie di §3 per il simbolo |
| 2 | richiamo ≥ 80%, falsi positivi ≤ 20%, timing risolto o dichiarato come annotazione |
| 3 | nessuna soglia: il risultato decide la regola d'uscita del bot (§6.6) |
| 4 | aspettativa fuori campione > 0 dopo i costi, parametri stabili |
| 5 | esecuzione coerente col tester |

Le soglie sono proposte da concordare con il trader prima di vedere i risultati, non dopo.
