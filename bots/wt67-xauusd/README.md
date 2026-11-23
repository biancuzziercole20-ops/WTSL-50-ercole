# WT67 XAUUSD · conti da 100k e 50k

| File | Ruolo |
|---|---|
| [WT67ercole.mq5](WT67ercole.mq5) | EA di riferimento sul 100k. Genera le posizioni WaveTrend M15 da cui parte il collegamento. |
| [WT67_Collegamento_50k.mq5](WT67_Collegamento_50k.mq5) | Lo stesso EA gira nei due terminali MT5 dello stesso utente Windows. Legge il conto attivo e usa la cartella comune per collegare le istanze. Sul 100k si applica a un secondo grafico. |
| [Prompt_Claude_Code_WTSL_50_Ercole.txt](Prompt_Claude_Code_WTSL_50_Ercole.txt) | Specifica per creare il nuovo `WTSL-50%ercole.mq5` a partire dai due sorgenti. |
| [Test del collegamento](test/) | Test BUY e SELL, soglie, prezzi, riavvii, ordini duplicati e cambio d’ora. |

Il collegamento segue una posizione già aperta dal bot 100k. Per comprare sul 50k, sul 100k il prezzo deve essere sceso di almeno **5,00 unità di quotazione** dall’ingresso. Per vendere, deve essere salito di almeno 5,00. In entrambi i casi il collegamento controlla anche una perdita aperta sul 100k di almeno **500** nella valuta di quel conto, pari allo 0,5% del capitale nominale di 100.000.

Sul 50k il volume è **0,50 lotti**. Il bot usa i **prezzi assoluti** di SL e TP del 100k e verifica il risultato lordo teorico al prezzo eseguibile sul 50k. Le soglie sono **−250 allo stop** e **+750 al target**. Spread, slippage, costi e chiusure anticipate possono modificare il risultato effettivo. Il collegamento consente una sola apertura accettata per posizione sorgente.

I test si lanciano su Linux con Python 3 e un compilatore C++17.

```sh
python3 bots/wt67-xauusd/test/run.py
```

Il programma usa un modello locale dei due terminali e delle quotazioni. Per accertare il comportamento di MT5 servono la compilazione del sorgente in MetaEditor e una prova nei due terminali demo.
