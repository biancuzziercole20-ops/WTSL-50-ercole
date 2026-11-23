# Bot e strategie di Ercole

Per lavorare su **WTSL-50%ercole**, apri la cartella [WT67 XAUUSD](bots/wt67-xauusd/). Contiene il bot del conto da 100k, il collegamento al 50k e il [prompt per Claude Code](bots/wt67-xauusd/Prompt_Claude_Code_WTSL_50_Ercole.txt).

## Bot di trading

| Progetto | Punto di partenza | Materiale disponibile |
|---|---|---|
| [WT67 XAUUSD · 100k e 50k](bots/wt67-xauusd/) | WaveTrend M15 sul 100k e ingresso differito da 0,50 lotti sul 50k | Due EA, specifica WTSL e test del collegamento |
| [Nasdaq 100 · WaveTrend M15](bots/nasdaq100-wavetrend/) | Incrocio su candela chiusa, SL e TP a 30 punti indice, massimo tre aperture al giorno | EA base da 0,10 lotti ed EA 100k da 1,00 lotto |
| [XAUUSD · FP Markets](bots/xauusd-fpmarkets/) | Segnale normale M5 e speciale M15, con priorità al segnale M15 | EA, regole di rischio e CSV della simulazione |
| [XAUUSD · WaveTrend 1121](bots/xauusd-wavetrend-1121/) | Reversal M15 con diverse implementazioni della finestra oraria | Tre revisioni MQL5, variante Telegram, riferimento Python e PDF |
| [XAUUSD · FTMO multi-timeframe](bots/xauusd-ftmo-mtf/) | Entrata M15 e conferme M30/H1/H4 | EA e prompt tecnico v2 |
| [XAUUSD · Smart Pattern Scalper](bots/xauusd-smart-pattern/) | Zone di supporto e resistenza, struttura multi-timeframe e punteggio dei pattern | Quattro revisioni MQL5 e due specifiche |
| [S&P 500 · RSI H4](bots/sp500-rsi-h4/) | Solo BUY quando l’RSI(16) riprende a salire dopo l’ipervenduto | EA con SL sul minimo della candela di conferma e TP a 40 punti indice |
| [S&P 500 · Momentum mensile 9−1](bots/sp500-momentum-9-1/) | Selezione di quattro azioni e mantenimento delle posizioni entro l’ottavo posto | EA, composizione storica, preset, rapporti di copertura e verifica di settembre 2026 |
| [Crypto · 86botERCOLE / E0V1E](bots/crypto-e0v1e/) | Strategia long-only M5 e porting MT5 | EA, strategia Freqtrade, varianti di stop, strumenti di backtest, risultati CSV ed Excel |

## Strategie da sviluppare

| Strategia | Documento |
|---|---|
| Swing mensile e Volume Profile H4 | [Specifica per Claude con esempi e parametri aperti](strategie/mensile-h4/Strategia_Mensile_H4_per_Claude.txt) |
| Setup short su rottura e retest della demand | [Sequenza H4, ingresso al 50% e filtro POC](strategie/retest-demand-h4/README.md) |
| Baricentro delle candele e avvisi POC | [Due idee distinte e decisioni da prendere](strategie/idee-indicatori.md) |

## Strumenti e guide

| Risorsa | Uso |
|---|---|
| [Scanner Pokémon multi-marketplace](strumenti/pokemon-deal-scanner/pokemon_deal_bot/) | Base Python con filtri, confronto prezzi e notifiche da collegare ai dati |
| [Scanner Pokémon Vinted](strumenti/pokemon-vinted-scanner/) | Applicazione con interfaccia web, feed manuale, dati dimostrativi e test |
| [Guide MetaTrader 5](guide/mt5/) | Guida rapida di installazione e manuale completo in PDF |
| [Istruzioni per Claude Code](CLAUDE.md) | Scelta del sorgente, comandi di verifica e unità da rispettare |
