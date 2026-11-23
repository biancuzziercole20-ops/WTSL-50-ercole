# WTSL-50-ercole
Expert Advisor MQL5 per MetaTrader 5

Strategia swing: la candela mensile di riferimento dice **dove** cercare l'operazione (minimo, massimo,
equilibrio al 50%). Il grafico H4 dice **quando** entrare, in base alla reazione di prezzo e volumi dopo lo
sweep di un estremo. Target a 2R, rischio 0,25% o 0,5% per trade.

## Documentazione (v0.1, nessun codice MQL5 ancora)

| File | Contenuto |
|---|---|
| [docs/01-specifica.md](docs/01-specifica.md) | regole, ipotesi da validare, decisioni del software contro annotazioni |
| [docs/02-casi-ricostruiti.md](docs/02-casi-ricostruiti.md) | long valido (AVGO), short valido (FX), ingresso da scartare, con casi di test |
| [docs/03-pseudocodice-mt5.md](docs/03-pseudocodice-mt5.md) | struttura dell'EA e pseudocodice |
| [docs/04-piano-backtest.md](docs/04-piano-backtest.md) | piano di backtest, con il confronto tra uscite stop/2R e manuali |
| [templates/](templates) | formato di `simboli.csv` e `annotazioni.csv` |
