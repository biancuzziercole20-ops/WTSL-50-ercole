# S&P 500 · RSI Reversal H4

Il [sorgente](SP500_RSI_Reversal_H4.mq5) segue solo ingressi BUY. Valuta l’RSI(16) sulla chiusura H4 dopo una lettura sotto 30. La SMA a 25 periodi serve come riferimento visivo. Lo stop è sul minimo della candela di conferma e il take profit predefinito è 40 punti indice dal prezzo effettivo di ingresso.

Il volume predefinito è 0,01 lotti. Il codice gestisce una posizione alla volta e contiene condizioni specifiche per tornare ad armare il segnale durante un periodo prolungato di ipervenduto.
