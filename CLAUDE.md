# Lavorare su questa raccolta

Il [catalogo](README.md) associa ciascuna strategia ai propri sorgenti. I parametri con nomi simili possono avere significati diversi tra due progetti. Per ricostruire il comportamento attuale leggi gli input e il ramo di codice che invia l’ordine. Le cartelle `strategie/` raccolgono requisiti e idee per lavori futuri.

## Primo incarico WTSL-50%ercole

1. Leggi il [prompt completo](bots/wt67-xauusd/Prompt_Claude_Code_WTSL_50_Ercole.txt), il [sorgente del 100k](bots/wt67-xauusd/WT67ercole.mq5) e il [collegamento 50k](bots/wt67-xauusd/WT67_Collegamento_50k.mq5).
2. Usa la cartella `bots/wt67-xauusd/` come radice di questo progetto. Il file richiesto nel prompt si chiama esattamente `WTSL-50%ercole.mq5`, incluso il segno percentuale.
3. Esegui `python3 bots/wt67-xauusd/test/run.py` dalla radice del repository per controllare la base di partenza. Il runner legge il sorgente del collegamento esistente. Per verificare un EA derivato, indirizza i test anche al nuovo sorgente.
4. Riporta separatamente i test di logica, la compilazione F7 in MetaEditor e la prova con due terminali demo. Indica quali hai effettivamente eseguito.

## Convenzioni delle strategie

- Distingui prezzo, punto indice, pip del progetto e `_Point` del simbolo. Per le soglie monetarie controlla valuta del conto, contratto, prezzo eseguibile e costi.
- Conserva la finestra e la gestione dell’ora legale specificate dal singolo EA. Un segnale su candela chiusa va calcolato con i dati disponibili a quella chiusura.
- Per un backtest registra versione del codice, simbolo del broker, periodo, modello di tick, costi e numero di operazioni. Un rapporto di copertura descrive i dati disponibili. Un risultato Freqtrade si riferisce al motore e al mercato usati in quella simulazione.
- Imposta login conto, token, chat ID e chiavi API soltanto nella configurazione locale. Gli esempi degli scanner contengono i nomi delle variabili da valorizzare.
