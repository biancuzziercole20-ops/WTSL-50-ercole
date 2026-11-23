# E0V1E "binance" – porting MetaTrader 5

Il sorgente MT5 recuperato si chiama [86botERCOLE.mq5](mt5/86botERCOLE.mq5). La [strategia Python di riferimento](reference/binance.py) proviene dal progetto [vaskosmihaylov/nfi-custom-strategies](https://github.com/vaskosmihaylov/nfi-custom-strategies). La licenza del progetto di origine è inclusa in [COPYING](COPYING).

La descrizione e i risultati sottostanti provengono dal progetto originale di porting alla revisione `f2a79a6313cdd75f10d316581501c44db21524a7`. Il [CSV BTC/ETH](reference/freqtrade_backtest_BTC_ETH_2022-2025.csv), la [cartella dei risultati](results/) e gli [strumenti Freqtrade](freqtrade/tools/) permettono di risalire al contesto di ogni prova. In questa raccolta gli esiti Freqtrade e MT5 vanno identificati con il motore che li ha prodotti.

- `reference/binance.py`: strategia freqtrade originale (vaskosmihaylov/nfi-custom-strategies, `user_data/strategies/e0v1e/binance.py`).
- `mt5/86botERCOLE.mq5`: Expert Advisor MQL5 equivalente.
- `reference/freqtrade_backtest_BTC_ETH_2022-2025.csv`: trade del backtest freqtrade 2026.10 ufficiale (dati Binance spot 5m, 01/2022–12/2025, fee 0,1%, stake 1000 USDT, wallet 2000, max 2 trade).

## Logica
Long only, 5m, una posizione per simbolo, ingresso a mercato all'apertura della candela successiva al segnale.

**Ingresso `ewo`**: RSI(4) < 50, close < EMA8 × 0,956, EWO(50,200) > −1,238, close < EMA16 × 0,986, RSI(14) < 30.
**Ingresso `buy_1`**: RSI(20) in calo, RSI(4) < 63, RSI(14) > 16, close < SMA15 × 0,932, CTI(20) < −0,8.

**Uscite** (nessun TP, stop fisso −99%):
- dopo 60 min: FastK(5) > 75 e profitto > −1% → stop a −0,1% dal prezzo;
- dopo 24 h: FastK > 75 e profitto > −5% → stop a −0,1%;
- tag `ewo` e profitto ≥ 5% → stop a −0,5%;
- profitto > 0 e FastK > 75 → stop a −0,1%;
- lo stop sale e non scende mai (trailing);
- `deadfish`: profitto < −5%, larghezza Bollinger < 0,05, close > banda media, volume medio 12 < volume medio 24 → chiusura.

## Installazione MT5
1. Copia `86botERCOLE.mq5` in `MQL5/Experts/`, apri in MetaEditor, Compila (F7).
2. Strategy Tester: simbolo crypto, timeframe M5, modello "Ogni tick basato su tick reali".
3. Il CSV dei trade viene scritto in `<Dati comuni>/Files/E0V1E_trades_<SIMBOLO>_<MAGIC>.csv`.

## Verifica
Gli indicatori dell'EA sono stati riprodotti in Python e confrontati con quelli calcolati dal codice originale su ~6000 candele BTC/ETH: errore ≤ 1e-13 (EWO ≤ 0,0005 assoluto per la finestra di 1000 barre) e segnali identici al 100%.

## Replica Freqle e varianti con stop (novembre 2026)
- Dati: 33 coppie Binance Spot (elenco Freqle), 5m e 1m da data.binance.vision, 3.692 file mensili con checksum verificato; dettaglio per coppia in `freqtrade/data_report.csv`.
- Configurazione: `freqtrade/config33.json` (1000 USDT, 100 per trade, 10 posizioni, fee 0,1%), `--enable-protections`.
- Replica 2022-2024 su 5m: 298 trade, 86,9% vincenti, +739 USDT, identica al report Freqle.
- Varianti: `freqtrade/strategies/binance_sl10.py` e `binance_sl15.py` (stop fisso sul broker a -10% / -15% dal prezzo d'ingresso).
- Scelta congelata sul 2025 prima del test 2026: `results/FREEZE_2025.txt`.
- Tutti i risultati: `results/E0V1E_risultati.xlsx` (Riepilogo, Trade Freqtrade, Parametri, Risultati MT5).

## Profilo MT5 FTMO
- `InpStakeMode = Rischio %`, `InpRiskPct = 0.25`, `InpMaxOpenRiskPct = 1.0`, `InpHardStopPct = 10` o `15`: lotti calcolati dalla distanza dello stop, commissione inclusa (`InpRiskFeePct = 0.0325`); se il lotto minimo supera il budget il trade viene saltato.
- `InpFeePct` serve solo per le soglie di profitto della strategia e non addebita nulla: le commissioni reali le applica il tester secondo il simbolo.
- All'avvio l'EA stampa nel Journal contratto, lotti, tick value, spread, swap e se il simbolo ha volume reale o solo tick volume.
- Il limite di rischio complessivo considera tutte le posizioni con lo stesso magic: in un test su un solo simbolo vale solo per quel simbolo.
