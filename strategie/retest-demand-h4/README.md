# H4 · Setup short sul retest della demand

Il setup parte dalla zona di demand individuata sul grafico con la candela arancione. Per trasformare il modello visivo in un EA occorre definire con prezzi e volumi come identificare la candela e i limiti superiore e inferiore della zona.

1. Attendi che una candela ribassista rompa la demand e chiuda con il corpo sotto la zona. La sola ombra sotto il livello lascia il setup in attesa.
2. Calcola il prezzo a metà della demand rotta. Il livello di ingresso previsto è il 50% della zona, raggiunto durante il retest dal basso.
3. Nel caso descritto il POC dei volumi si trovava sopra l’ingresso al momento della decisione. Un POC sotto l’ingresso esclude lo short. Per il backtest registra il POC disponibile su quella candela, anche se il profilo cambia in seguito.
4. La conferma H4 descritta prende i massimi del ritracciamento e chiude con il corpo dentro il corpo della candela precedente. Sul grafico viene associata alla candela arancione con il puntino azzurro.
5. L’ordine previsto è un sell limit al 50%. Lo stop è poco sopra l’intera demand secondo la descrizione operativa. Il materiale illustrativo usa anche il massimo che invalida il retest e indica una zona di liquidità o supporto per il target.

Prima di implementare l’EA vanno fissati il margine dello stop, gli estremi esatti del profilo volumi e il momento in cui inserire l’ordine. La conferma H4 e il tocco del 50% possono avvenire in ordine diverso. Registrare un ingresso sul primo tocco usando una conferma arrivata più tardi introdurrebbe dati futuri nel test.
