# Indicatori e avvisi da specificare

## Baricentro delle candele

L’idea è un indicatore TradingView/Pine che emetta segnali sugli incroci tra il prezzo di riferimento della candela e un baricentro dinamico nella sessione 15:30–17:30 di Roma. I candidati discussi sono il punto medio dell’intervallo massimo–minimo, il punto medio del corpo apertura–chiusura e la media OHLC. Una SMA a 10 barre e i timeframe M5/M15 sono ipotesi da confrontare. Prima di misurare i segnali occorre scegliere la coppia di serie da incrociare e la regola di conferma a candela chiusa.

## Avvisi sul Point of Control

Il progetto prevede di raccogliere un avviso dalla fonte scelta, verificare il POC con i parametri della strategia e mostrare il segnale. Servono ancora una fonte di dati accessibile, l’intervallo del profilo e il formato dell’avviso. Per rendere un test riproducibile, ogni segnale deve conservare simbolo, timeframe, data e ora, estremi del profilo e POC disponibili al momento. L’eventuale invio di un ordine è una fase successiva da specificare.
