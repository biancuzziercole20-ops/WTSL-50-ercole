# XAUUSD · FP Markets M5/M15

Il [sorgente](WT_XAUUSD_FPM.mq5) rivaluta l’ingresso ad ogni nuova candela M5 durante la sessione italiana 15:30–17:30. Il segnale normale segue la direzione dell’ultimo incrocio M5 confermato. Un nuovo incrocio M15 sulla candela appena chiusa ha precedenza su quel medesimo ingresso.

| Impostazione di fabbrica | Normale M5 | Speciale M15 |
|---|---|---|
| Stop loss | 10 pip | 50 pip |
| Take profit | 15 pip | 70 pip |
| Valore di un pip del progetto | 0,10 di prezzo | 0,10 di prezzo |

Il sorgente prevede al massimo 24 aperture al giorno e un budget di rischio giornaliero del 4%. Calcola il volume dalla distanza dello stop e dal budget residuo. La chiusura a fine sessione è attiva per impostazione iniziale.

Il [CSV della simulazione](simulazione/operazioni_2026-03-02_2026-05-25.csv) contiene 1.440 operazioni dal 2 marzo al 25 maggio 2026. È una simulazione indipendente del progetto. Comprende orari, direzione, prezzi, commissioni e risultato netto per operazione. La pubblicazione conserva i dati archiviati.
