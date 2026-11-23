# WTSL-50-ercole
Expert Advisor MQL5 per MetaTrader 5: copia condizionata dei trade WT67 dal conto FTMO da 100.000 al conto da 50.000.

| File | Contenuto |
|---|---|
| `WT67ercole.mq5` | il bot del conto 100k: strategia WaveTrend che apre i trade (magic 670067) |
| `WTSL-50%ercole.mq5` | il collegamento: legge il WT67 sul 100k e copia sul 50k (magic 670050) |
| `tests/RISULTATI_TEST.md` | tabella atteso/osservato dell'ultima esecuzione dei test simulati |
| `tests/run_tests.sh` | compila il `.mq5` sul simulatore dell'API MT5 ed esegue i test |
| `tests/mt5_shim.h`, `tests/test_wtsl50.cpp`, `tests/test_wt67.inc` | simulatore dei due terminali e scenari di prova |
| `tests/wt_riferimento.py` | WaveTrend di riferimento con pandas |
| `tests/mutazioni.py` | rompe una regola alla volta e verifica che un test la rilevi |

## Origine della strategia

I file originali `WT67ercole.mq5` e `WT67_Collegamento_50k.mq5` non erano presenti nel repository
(né in altri repository accessibili). Entrambi i bot sono stati scritti dalla specifica.
`WT67ercole.mq5` in questo repository è quindi una **ricostruzione**: se usi il tuo WT67 originale,
WTSL-50%ercole funziona lo stesso purché le sue posizioni abbiano magic 670067 su XAUUSD e la chiusura
sull'incrocio opposto sia fatta dall'EA (`DEAL_REASON_EXPERT`).

## Il bot del 100k: WT67ercole.mq5

* **Segnale.** WaveTrend LazyBear 10/21/4 su XAUUSD M15, confermato solo su candele chiuse. Alla prima quotazione
  di una nuova candela confronta la candela appena chiusa con la precedente. Incrocio rialzista → BUY, ribassista → SELL.
* **Ordine.** A mercato, 1,00 lotto (`InpLotti`), con SL e TP a 10,00 di prezzo (`InpDistanzaSL`/`InpDistanzaTP`)
  dal prezzo eseguito: Ask per BUY, Bid per SELL. Se il broker esegue a un prezzo diverso, SL e TP vengono riallineati
  a 10,00 dall'ingresso reale. Se mancano, vengono ripristinati.
* **Regole.** Nuove aperture solo tra 15:30 inclusa e 17:30 esclusa (Europe/Rome, ora legale automatica), al massimo
  `InpMaxTradeGiorno` (4) per giorno italiano, una posizione alla volta, un solo trade per candela anche dopo un riavvio.
  L'ingresso deve avvenire entro `InpMaxRitardoSegnaleSec` (60 s) dall'apertura della candela: se l'EA parte più tardi,
  il segnale è scaduto.
* **Incrocio opposto.** Con una posizione aperta, la chiude subito (anche fuori orario) e, se le regole lo permettono,
  apre quella inversa nello stesso istante. È la sequenza che WTSL-50%ercole riconosce per chiudere la copia sul 50k.
* **Sicurezza.** Fuori dal Tester parte solo se il login è `InpConto100k`, quindi non può operare per errore sul 50k.
* **Strategy Tester.** Si può fare il backtest. Il Tester non conosce l'ora UTC, quindi `InpOraServerTester` indica il fuso
  del server: di default UTC+2, UTC+3 con l'ora legale USA, come sui server FTMO.

## Il collegamento 100k → 50k: WTSL-50%ercole.mq5

Lo stesso `.mq5` gira su **due terminali MT5 dello stesso utente Windows, sullo stesso PC o VPS**.
Il ruolo dipende dal login del conto:

* **Terminale 100k, login = `InpConto100k`: ruolo SORGENTE.** Non invia mai ordini. Ogni 100 ms
  (e a ogni tick) legge dal broker la posizione WT67 (magic `InpMagicWT67`, simbolo `InpSimbolo100k`):
  direzione, prezzo di esecuzione, SL, TP, `POSITION_IDENTIFIER`, `POSITION_PROFIT`, Bid/Ask correnti.
  Dallo storico ricava le chiusure delle ultime 48 ore con il motivo. Scrive tutto in
  `Common\Files\WTSL50ercole\canale_<login100k>.txt` (FILE_COMMON, scrittura su file temporaneo + rinomina).
* **Terminale 50k, login = `InpConto50k`: ruolo RICEVITORE.** Su ogni tick e ogni 100 ms rilegge il canale e apre la copia
  alla prima quotazione in cui valgono **tutte insieme** queste condizioni:
  1. il trade WT67 è aperto e il canale è aggiornato (dati con meno di 2 s, terminale 100k connesso);
  2. BUY: `ingresso − Bid100k ≥ 5,00`; SELL: `Ask100k − ingresso ≥ 5,00` (confronto in tick del simbolo, 4,99 non basta);
  3. `POSITION_PROFIT ≤ −500,00` (al centesimo: −499,99 non basta);
  4. ora italiana in [15:30:00, 17:30:00) e trade sorgente aperto nella stessa sessione dello stesso giorno italiano;
  5. meno di 4 aperture oggi, nessuna posizione del bot aperta, trade sorgente mai copiato;
  6. con l'Ask (BUY) o il Bid (SELL) reale del 50k, `OrderCalcProfit` su 0,50 lotti dà esattamente
     −250,00 allo SL e +750,00 al TP (al centesimo), con SL = SL_100k e TP = TP_100k.

  Subito prima dell'invio rilegge il canale e la quotazione del 50k e ripete tutti i controlli.
  Poi scrive su disco l'identificativo del trade sorgente e solo dopo invia `TRADE_ACTION_DEAL`
  da 0,50 lotti con SL, TP, `ORDER_FILLING_FOK`, magic `InpMagicRicevitore` e commento `WTSL50|<id>|B/S`.

### Gestione della copia aperta

* Se il 100k chiude per **incrocio opposto**, la copia viene chiusa anche fuori orario. L'incrocio opposto è riconosciuto
  quando la chiusura è fatta dall'EA (`DEAL_REASON_EXPERT`) e c'è una di queste due prove: il WT67 apre
  il trade inverso entro 120 s, oppure il WaveTrend 10/21/4 ricalcolato conferma l'incrocio opposto
  sulla M15 chiusa precedente.
* In ogni altro caso (SL, TP, chiusura manuale) la copia resta con i propri SL/TP al broker.
  `InpChiudiSuAltreChiusure=true` la chiude anche dopo una chiusura manuale o per altro motivo.
* Il nuovo trade inverso è un trade sorgente diverso: deve raggiungere la propria soglia, in sessione.
* Durante una disconnessione (di uno dei due terminali o del canale) non si aprono nuove copie
  e SL/TP restano quelli già inseriti al broker. Il bot non li modifica mai.

### Duplicati, riavvii, rifiuti

`Common\Files\WTSL50ercole\registro_<login50k>_da_<login100k>.txt` conserva ogni trade sorgente gestito:

| Stato | Significato | Si può copiare ancora? |
|---|---|---|
| INVIO | registrato prima dell'invio; dopo un riavvio diventa INCERTA | no |
| APERTA / CHIUSA | copia eseguita | no |
| INCERTA | timeout o esito non certo | no, mai reinviata |
| RIFIUTATA | rifiuto certo del broker, motivo registrato (livelli, FOK, margine...) | sì, dopo 5 s, al massimo 3 tentativi |

Se il registro viene perso, l'EA lo ricostruisce dallo storico del 50k grazie al commento delle copie.
Se il registro non è scrivibile, l'ordine non viene inviato. Ogni evento è anche in
`Common\Files\WTSL50ercole\eventi_<login>.log` e nella scheda Esperti.

## Installazione

1. Copiare `WT67ercole.mq5` in `MQL5\Experts\` del terminale 100k e `WTSL-50%ercole.mq5` in `MQL5\Experts\` di **entrambi** i terminali,
   poi compilarli con MetaEditor (F7).
   Da riga di comando: `metaeditor64.exe /compile:"MQL5\Experts\WTSL-50%ercole.mq5" /log`
   (in un file `.bat` scrivere `%%` al posto di `%`).
2. Terminale 100k: caricare WT67ercole sul grafico XAUUSD M15 con `InpConto100k` impostato e WTSL-50%ercole su un **altro**
   grafico (per esempio un secondo XAUUSD M15) con `InpConto100k` e `InpConto50k` impostati.
3. Terminale 50k (conto hedging, simbolo XAUUSD con Fill or Kill): caricarlo sul grafico XAUUSD con gli stessi due login
   e Algo Trading attivo.
4. Facoltativo: con `InpAutoTest=true` l'EA esegue solo 24 verifiche interne, tra cui `OrderCalcProfit` reale del broker
   sugli esempi −250/+750 e −260/+740, e non opera.

Parametri principali: `InpConto100k`, `InpConto50k`, `InpSimbolo100k`/`InpSimbolo50k` (XAUUSD),
`InpMagicWT67` (670067), `InpMagicRicevitore` (670050). Le regole della strategia (5,00 / −500 / 0,50 lotti /
−250 / +750 / 15:30–17:30 / 4 al giorno) sono costanti nel codice, non input.

Nel Tester strategie l'EA non opera, perché servono due terminali vivi. Lì funziona solo `InpAutoTest`.

## Test

```bash
tests/run_tests.sh          # 58 scenari simulati, tabella in tests/RISULTATI_TEST.md
python3 tests/mutazioni.py  # 41 mutazioni delle regole dei due bot, tutte devono essere rilevate
```

Il test E01 fa girare i tre EA insieme (WT67 e WTSL sorgente sul 100k, WTSL ricevitore sul 50k) su candele M15 sintetiche:
incrocio rialzista → WT67 BUY a 3000 → copia BUY 0,50 a 2995 → incrocio ribassista → WT67 chiude e vende, copia chiusa →
nuova copia SELL solo quando il nuovo trade raggiunge la sua soglia.

I test sono **simulati**: i sorgenti `.mq5` reali vengono compilati con g++ dentro un simulatore dell'API MT5
(due conti finti in USD, XAUUSD a 2 decimali, contratto da 100 once, cartella comune su disco).
Verificano la logica, non la sintassi MQL5. Non sostituiscono la compilazione in MetaEditor
né una prova su due terminali demo.

Limiti noti: commissioni, swap, slittamento e chiusure anticipate cambiano il risultato realizzato
(lo slittamento viene segnalato nel registro). Un tentativo con esito incerto conta tra le 4 aperture del giorno.
