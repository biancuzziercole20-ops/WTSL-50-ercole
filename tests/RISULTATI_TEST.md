# Risultati dei test simulati di WT67ercole.mq5 e WTSL-50%ercole.mq5

Generato da `tests/run_tests.sh`. Prove **simulate**: il sorgente `.mq5` reale e' compilato con g++ su un simulatore dell'API MT5 (`tests/mt5_shim.h`) con due conti finti in USD, XAUUSD a 2 decimali e contratto da 100 once. Non sono prove su terminali MetaTrader 5.

Serie T: WTSL-50%ercole (sorgente 100k e ricevitore 50k). Serie W: WT67ercole (strategia 100k) su candele M15 sintetiche. E01: i tre EA insieme, dall'incrocio WaveTrend alla copia sul 50k e alla chiusura sull'incrocio opposto.

Esito complessivo: **58 OK, 0 falliti**

| ID | Prova | Risultato atteso | Risultato osservato | Esito |
|---|---|---|---|---|
| T00 | Incrocio confermato ma nessuna posizione WT67 sul 100k | 0 ordini, stato NESSUN_TRADE_100K | 0 ordini, stato NESSUN_TRADE_100K | OK |
| T01 | BUY: 100k compra a 3000 SL 2990 TP 3010, 50k compra a 2995 | 1 ordine BUY 0.50 @2995.00 SL 2990.00 TP 3010.00 FOK, lordo -250.00/+750.00; nessun ordine con 100k a -450 | 1 ordine/i: BUY 0.50 @2995.00 SL 2990.00 TP 3010.00 FOK magic 670050 'WTSL50\|5000000\|B', lordo -250.00/+750.00; con 100k a -450: 0 ordini | OK |
| T02 | SELL: 100k vende a 3000 SL 3010 TP 2990, 50k vende a 3005 | 1 ordine SELL 0.50 @3005.00 SL 3010.00 TP 2990.00 FOK, lordo -250.00/+750.00 | 1 ordine/i: SELL 0.50 @3005.00 SL 3010.00 TP 2990.00 FOK magic 670050 'WTSL50\|5000000\|S', lordo -250.00/+750.00 | OK |
| T03 | SPREAD: 100k a -500 ma il 50k compra solo a 2995.20, poi torna a 2995.00 | 0 ordini a 2995.20 (registrato stop -260.00 / target 740.00); poi una sola apertura a 2995.00 | 0 ordini a 2995.20 (registrato -260.00/740.00); dopo il ritorno: 1 apertura: BUY 0.50 @2995.00 SL 2990.00 TP 3010.00 FOK magic 670050 'WTSL50\|5000000\|B', lordo -250.00/+750.00 | OK |
| T04 | Movimento di soli 4.99 punti (Bid 2995.01, P/L -499) con 50k a 2995.00 | 0 ordini | 0 ordini, motivo: movimento insufficiente | OK |
| T04b | 4.99 punti con P/L gia' -598.80 (sorgente 1.20 lotti); controllo a 5.00 punti | 0 ordini a 4.99 punti; 1 ordine quando il movimento arriva a 5.00 | 0 ordini a 4.99; 1 a 5.00 | OK |
| T05 | Perdita di soli 499 (e 499.99) con movimento 5.00 e 50k a 2995.00 | 0 ordini con -499.00 e -499.99; 1 ordine quando POSITION_PROFIT arriva a -500.00 | 0 ordini a -499.00, 0 a -499.99, 1 a -500.00 | OK |
| T06 | Trade sorgente chiuso prima che il 50k arrivi a 2995.00 | 0 ordini, attesa annullata | 0 ordini, 'Attesa annullata' registrato | OK |
| T07 | Soglie e prezzo 50k raggiunti alle 17:30:00 esatte (Europe/Rome, ora legale) | 0 ordini | 0 ordini, motivo: fuori finestra | OK |
| T07b | Controllo: stesse condizioni alle 17:29:59 | 1 ordine | 1 ordine/i | OK |
| T07c | Trade e soglie alle 15:30:00 esatte (inizio incluso) | 1 ordine | 1 ordine/i | OK |
| T07d | Trade 100k aperto alle 15:29:59, soglie alle 15:35 | 0 ordini (sessione diversa) | 0 ordini | OK |
| T07e | Ora solare (gennaio, UTC+1): 16:00 dentro, 17:30:00 fuori | 1 ordine alle 16:00; 0 alle 17:30:00 | 1 alle 16:00; 0 alle 17:30:00 | OK |
| T08 | Riavvio di entrambi gli EA con la copia aperta e condizioni ancora valide | nessuna seconda copia (1 ordine totale) | 1 ordini totali, 1 copie aperte | OK |
| T08b | Copia chiusa dallo SL sul 50k, riavvio, trade 100k ancora aperto e di nuovo in soglia | nessuna seconda copia | 1 ordini totali, registro: 5 (5 = CHIUSA) | OK |
| T08c | Timeout del broker senza esito certo, poi riavvio | nessun reinvio (registro INCERTA) | 1 invii totali, registro 3 (3 = INCERTA) | OK |
| T08d | Timeout ma ordine eseguito dal server, poi riavvio | 1 sola copia, collegata al registro (APERTA) | 1 invii, 1 copie, registro 2 | OK |
| T08e | File del registro cancellato, riavvio, condizioni di nuovo valide | nessuna seconda copia (registro ricostruito dallo storico) | 1 ordini totali, registro ricostruito | OK |
| T08f | Riavvio con voce di registro rimasta 'INVIO' | nessun invio (voce convertita in INCERTA) | 0 invii, registro 3 | OK |
| T09 | Incrocio opposto alle 18:10 (fuori orario): WT67 chiude il BUY e apre SELL | copia chiusa anche fuori orario; nuovo SELL non copiato (fuori finestra) | 1 chiusura, 0 copie aperte, 1 aperture totali | OK |
| T09b | Incrocio opposto alle 16:30: chiusura copia, il nuovo SELL deve raggiungere la sua soglia | copia BUY chiusa; nessuna apertura finche' il SELL non e' a -5.00/-500; poi SELL 0.50 @2998.00 SL 3003.00 TP 2983.00 | 1 chiusura; aperture: 1 subito, 1 a 4.99, 2 in soglia: SELL 0.50 @2998.00 SL 3003.00 TP 2983.00 FOK magic 670050 'WTSL50\|5000003\|S', lordo -250.00/+750.00 | OK |
| T09c | 100k chiuso dall'EA senza incrocio opposto confermato | copia lasciata aperta con i suoi SL/TP | 0 chiusure, 1 copie aperte | OK |
| T09d | 100k chiuso dall'EA con incrocio WaveTrend ribassista sulla M15 chiusa precedente (senza riapertura) | copia chiusa | barra di incrocio 280, 1 chiusure, 0 copie aperte | OK |
| T09e | 100k chiuso dall'EA, barre M15 disponibili ma nessun incrocio sulla barra confermata | copia lasciata aperta | barra 318, 0 chiusure, 1 copie aperte | OK |
| T09f | 100k chiuso da SL mentre il Bid del 50k e' 2990.10 | copia non toccata dal bot; si chiude col proprio SL al broker | copia ancora aperta, 0 chiusure del bot, 0 modifiche SL/TP; dopo 2989.90: 0 copie | OK |
| T10 | Cinque trade WT67 in soglia nella stessa sessione, poi il giorno dopo | 4 aperture, la quinta bloccata; il giorno dopo di nuovo ammessa | 4 aperture oggi (LIMITE_GIORNALIERO), totale dopo il giorno seguente 5 | OK |
| T11 | Copia del trade A ancora aperta mentre un nuovo trade B del 100k va in soglia | nessuna seconda posizione | 1 aperture, 1 copie aperte | OK |
| T12 | Terminale 50k disconnesso con condizioni valide, poi riconnesso | nessuna richiesta da disconnesso; 1 copia alla riconnessione; SL/TP intatti | 0 richieste da disconnesso, 1 copie, SL/TP 2990.00/3010.00, modifiche 0 | OK |
| T12b | Dati del 100k vecchi di 3 s (terminale 100k fermo) | 0 ordini finche' i dati non tornano freschi; poi 1 | 0 ordini con dati vecchi, 1 dopo l'aggiornamento | OK |
| T12c | Terminale 100k disconnesso dal server | 0 ordini | 0 ordini | OK |
| T13 | Il broker rifiuta l'esecuzione integrale (REJECT) | rifiuto registrato col motivo, nessuna posizione; nuovo tentativo dopo 5 s; 1 sola copia | 1 invio rifiutato (registro RIFIUTATA), 1 in pausa, 2 invii totali, 1 copia | OK |
| T13b | Il broker rifiuta SL/TP per tre volte | motivo registrato, 3 tentativi poi stop; nessuna posizione | 3 invii, 0 copie, tentativi esauriti | OK |
| T13c | Simbolo del 50k senza modalita' Fill or Kill | 0 ordini, motivo registrato | 0 ordini | OK |
| T13d | Esecuzione con slittamento di +0.10 sul 50k | 1 copia, avviso registrato con i nuovi importi lordi (-255.00/+745.00) | 1 copia a 2995.10, avviso registrato | OK |
| T14 | Due posizioni WT67 aperte sul 100k | 0 ordini (sorgente ambigua) | 0 ordini | OK |
| T14b | Trade 100k senza SL | 0 ordini | 0 ordini | OK |
| T14c | Registro copie non scrivibile su disco | 0 ordini (senza registrazione preventiva non si invia) | 0 ordini | OK |
| T14d | Ruolo sorgente sul conto 100k | nessuna richiesta OrderSend dal terminale 100k | 0 richieste | OK |
| T15 | Autotest interno dell'EA (InpAutoTest=true) su conto USD, contratto 100 | tutte le verifiche OK | 24 OK, 0 falliti | OK |
| T16 | WaveTrend 10/21/4 dell'EA contro due implementazioni indipendenti (C++ e pandas) | stessi valori e stessi incroci | scarto massimo C++ 0.00e+00; pandas: OK scarto massimo 1.05e-10, incroci rialzisti 20, ribassisti 19, coincidono: si | OK |
| T17 | Il 100k chiude il trade tra il primo controllo e la verifica finale prima dell'invio | 0 ordini | 0 ordini, bloccato dalla verifica finale | OK |
| T17b | L'Ask del 50k passa da 2995.00 a 2995.20 durante la verifica finale | 0 ordini in quell'istante; 1 al ritorno a 2995.00 | 0 ordini con spread allargato, 1 dopo | OK |
| W01 | WT67: incrocio rialzista confermato sulla M15 chiusa delle 15:30, prima quotazione alle 15:45:01 | BUY 1.00 @3000.00 (Ask) SL 2990.00 TP 3010.00 magic 670067; nulla prima della chiusura della candela | 1 ordine: BUY 1.00 @3000.00 SL 2990.00 TP 3010.00 magic 670067; prima della chiusura: 0 | OK |
| W02 | WT67: incrocio ribassista confermato | SELL 1.00 @3000.00 (Bid) SL 3010.00 TP 2990.00 | 1 ordine: SELL 1.00 @3000.00 SL 3010.00 TP 2990.00 magic 670067 | OK |
| W03 | WT67: prima quotazione della candela alle 17:30:00 esatte e alle 15:30:00 | 0 ordini alle 17:30:00; 1 ordine alle 15:30:00 | 0 alle 17:30, 1 alle 15:30 | OK |
| W03c | WT67: ora solare (gennaio), ingresso alle 15:30:00 | 1 ordine | 1 ordine | OK |
| W04 | WT67: nessun incrocio sulla candela chiusa | 0 ordini | 0 ordini | OK |
| W04b | WT67: incrocio rialzista con un BUY gia' aperto | nessun ordine, una posizione alla volta | 0 aperture, 0 chiusure | OK |
| W05 | WT67: incrocio con gia' 4 trade nel giorno italiano (controllo con 3) | 0 ordini con 4; 1 ordine con 3 | 0 con 4, 1 con 3 | OK |
| W06 | WT67: riavvio entro la stessa candela dopo un trade gia' chiuso da SL | nessun secondo ordine sulla stessa candela | 1 ordini totali | OK |
| W07 | WT67: avviato 120 s dopo l'apertura della candela di segnale | 0 ordini (segnale scaduto, limite 60 s) | 0 ordini | OK |
| W08 | WT67: eseguito a 3000.20 invece di 3000.00 | SL/TP riallineati a 2990.20 / 3010.20 (10.00 dall'ingresso reale) | ingresso 3000.20, SL 2990.20, TP 3010.20 | OK |
| W09 | WT67: requote, nuovo tentativo dopo 2 s (e dopo 70 s) | riprova ed entra entro 60 s; dopo 60 s il segnale scade | 2 invii e posizione aperta; con 70 s: 1 invio, posizione assente | OK |
| W10 | WT67: BUY aperto, poi incrocio ribassista confermato in sessione | BUY chiuso dall'EA (DEAL_REASON_EXPERT) e SELL 1.00 @2993.00 SL 3003.00 TP 2983.00 nello stesso istante | 1 chiusura, 2 aperture, ultima: SELL 1.00 @2993.00 SL 3003.00 TP 2983.00 magic 670067 | OK |
| W10b | WT67: BUY delle 17:15, incrocio opposto dopo le 17:30 | BUY chiuso anche fuori orario, nessun SELL | 1 chiusura, 1 apertura, posizione nessuna | OK |
| W11 | WT67 nel Strategy Tester (TimeGMT = ora server, server UTC+3 d'estate) | finestra Europe/Rome rispettata: 1 ordine alle 15:45, 0 alle 17:30:00 | 1 alle 15:45, 0 alle 17:30 | OK |
| W12 | WT67 caricato per errore sul terminale del conto 50k | non parte (INIT_FAILED) | INIT_FAILED | OK |
| E01 | Catena completa con 3 EA: WT67 -> WTSL sorgente 100k -> WTSL ricevitore 50k | WT67 BUY @3000; copia BUY 0.50 @2995 a -5/-500; incrocio opposto: WT67 chiude e vende a 2993, copia chiusa; copia SELL @2998 solo alla nuova soglia | incroci sulle barre 100 e 106 (6 candele); WT67 BUY @3000 OK, copia BUY 0.50 @2995 OK, nessun duplicato OK, inversione: chiuse sorgente e copia OK, SELL non copiato a 4.99 OK, copia SELL 0.50 @2998 OK | OK |
