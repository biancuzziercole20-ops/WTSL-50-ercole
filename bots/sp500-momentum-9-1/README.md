# S&P 500 · Momentum mensile 9−1

[USASP_ERCOLE.mq5](USASP_ERCOLE.mq5) avvia il ribilanciamento da un solo grafico. A fine mese classifica i componenti dell’indice in base al rendimento tra la chiusura del mese t−9 e quella del mese t−1. Il mese del segnale resta escluso. Da portafoglio vuoto sceglie i primi quattro titoli. Nei mesi successivi può mantenere i titoli già detenuti entro l’ottavo posto.

| Risorsa | Uso |
|---|---|
| [Prompt originale](Prompt_Claude_Code_MT5.txt) | Decisioni progettuali, casi da verificare e metrica richiesta |
| [sp500_constituents.csv](dati/sp500_constituents.csv) | Fotografie storiche dal 2 gennaio 1996 al 18 agosto 2026, 2.720 date. Il nome corrisponde all’input `InpUniverseFile`. |
| [Preset solo copertura](preset/USASP_ERCOLE_SoloCopertura.set) | Analisi della disponibilità dei prezzi nel terminale |
| [Rapporti di novembre 2026](rapporti/) | Copertura per mese, prezzi mancanti, sintesi e rapporto con zero cicli chiusi |
| [Verifica di settembre 2026](verifica-settembre-2026/LEGGIMI.txt) | Istruzioni originali, preset, composizione aggiornata, split, classifica e fonti per riprodurre questo caso |

Nel terminale copia nella cartella comune `Terminal/Common/Files` i CSV richiesti dal preset scelto. Per settembre usa i due file di [Per_MT5](verifica-settembre-2026/Per_MT5/) e il [preset di settembre](verifica-settembre-2026/Settembre_2026.set). Con i rapporti archiviati si possono verificare la copertura e i mesi indeterminati. Con zero cicli chiusi il win rate storico resta indeterminato.

La composizione di base corrisponde al file **S&P 500 Historical Components & Changes (Updated).csv** del progetto [fja05680/sp500](https://github.com/fja05680/sp500). La [licenza MIT](dati/LICENSE.txt) accompagna i dati originali e la copia aggiornata per la verifica di settembre.
