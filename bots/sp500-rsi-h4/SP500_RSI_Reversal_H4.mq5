//+------------------------------------------------------------------+
//| S&P 500 RSI Reversal H4 - BUY ONLY                               |
//| MT5 Expert Advisor - MQL5                                        |
//| Entry: RSI(16) turns upward after an oversold reading (< 30).    |
//| Entry is evaluated only after a closed H4 candle.                |
//| SL: low of the H4 confirmation/reversal candle.                  |
//| TP: +40.0 index points from actual entry price.                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "S&P 500 RSI H4 reversal EA - BUY only"

#include <Trade/Trade.mqh>

CTrade trade;

//--- Inputs
input double InpLots                 = 0.01;       // Position volume (lots)
input int    InpRSIPeriod             = 16;         // RSI period
input double InpOversoldLevel         = 30.0;       // Oversold threshold
input int    InpRSISmoothingPeriod    = 25;         // SMA smoothing period (display/reference only)
input double InpTakeProfitIndexPoints = 40.0;       // TP distance in index-price points
input ulong  InpMagicNumber           = 16162530;   // EA magic number
input int    InpDeviationPoints       = 20;         // Max price deviation (broker points)
input bool   InpRequireH4Chart        = true;       // Refuse trading unless chart timeframe is H4

//--- Indicator and state
int      rsiHandle = INVALID_HANDLE;
datetime lastH4BarTime = 0;

// The state machine avoids repeated entries on every rising RSI candle.
// It requires a new downward turn below 30 before another reversal signal.
bool oversoldArmed = false;
bool waitForNewDipAfterSignal = false;

//+------------------------------------------------------------------+
//| Check whether this EA already has a position on this symbol      |
//+------------------------------------------------------------------+
bool HasEAPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         return true; // one position at a time for this EA/symbol
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check whether a new H4 candle has started                        |
//+------------------------------------------------------------------+
bool IsNewH4Bar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_H4, 0);
   if(currentBarTime == 0)
      return false;

   if(currentBarTime != lastH4BarTime)
   {
      lastH4BarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Validate volume against broker symbol settings                   |
//+------------------------------------------------------------------+
double NormalizeVolume(double requestedLots)
{
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      return 0.0;

   double volume = MathMax(minVol, MathMin(maxVol, requestedLots));
   volume = MathFloor(volume / step + 1e-8) * step;

   int volumeDigits = 0;
   double scaledStep = step;
   while(volumeDigits < 8 && MathAbs(scaledStep - MathRound(scaledStep)) > 1e-8)
   {
      scaledStep *= 10.0;
      volumeDigits++;
   }
   return NormalizeDouble(volume, volumeDigits);
}

//+------------------------------------------------------------------+
//| Open a BUY with SL at the confirmation candle low and TP +40     |
//+------------------------------------------------------------------+
bool OpenBuy(double signalCandleLow)
{
   if(HasEAPosition())
      return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0.0)
   {
      Print("BUY non eseguito: prezzo Ask non disponibile.");
      return false;
   }

   // The requested TP is 40.0 index-price units, not 40 broker ticks.
   double sl = NormalizeDouble(signalCandleLow, _Digits);
   double tp = NormalizeDouble(ask + InpTakeProfitIndexPoints, _Digits);

   if(sl <= 0.0 || sl >= ask)
   {
      Print("BUY non eseguito: minimo della candela non valido rispetto all'Ask. SL=",
            DoubleToString(sl, _Digits), " Ask=", DoubleToString(ask, _Digits));
      return false;
   }

   // Respect broker stop-distance constraints without silently moving the SL.
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = (double)stopsLevel * _Point;
   if(minDistance > 0.0 && (ask - sl < minDistance || tp - ask < minDistance))
   {
      Print("BUY non eseguito: SL/TP più vicini della distanza minima del broker. ",
            "SL lasciato esattamente sul minimo; nessun aggiustamento automatico.");
      return false;
   }

   double volume = NormalizeVolume(InpLots);
   if(volume <= 0.0)
   {
      Print("BUY non eseguito: volume non valido. Verificare InpLots e le specifiche del simbolo.");
      return false;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   bool sent = trade.Buy(volume, _Symbol, 0.0, sl, tp, "RSI H4 Reversal BUY");

   if(!sent)
   {
      Print("Errore apertura BUY. Retcode=", trade.ResultRetcode(),
            " - ", trade.ResultRetcodeDescription());
      return false;
   }

   Print("BUY inviato. Symbol=", _Symbol,
         " Volume=", DoubleToString(volume, 2),
         " SL=", DoubleToString(sl, _Digits),
         " TP=", DoubleToString(tp, _Digits),
         " TP distance=", DoubleToString(InpTakeProfitIndexPoints, 2), " index points");
   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRSIPeriod < 2 || InpOversoldLevel <= 0.0 || InpOversoldLevel >= 100.0 ||
      InpRSISmoothingPeriod < 1 || InpTakeProfitIndexPoints <= 0.0 || InpLots <= 0.0)
   {
      Print("Parametri non validi: controllare RSI, soglia, SMA, TP e lotto.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpRequireH4Chart && _Period != PERIOD_H4)
   {
      Print("EA non avviato: collegare l'EA a un grafico H4.");
      return INIT_FAILED;
   }

   rsiHandle = iRSI(_Symbol, PERIOD_H4, InpRSIPeriod, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Impossibile creare l'handle RSI. Errore=", GetLastError());
      return INIT_FAILED;
   }

   // Set the current bar time so the EA waits for the next H4 close.
   lastH4BarTime = iTime(_Symbol, PERIOD_H4, 0);

   // Start safely: require a fresh oversold/dip sequence after attaching/restarting.
   oversoldArmed = false;
   waitForNewDipAfterSignal = false;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("RSI H4 Reversal EA inizializzato su ", _Symbol,
         ". Solo BUY; RSI(", InpRSIPeriod, "), soglia ",
         DoubleToString(InpOversoldLevel, 1), ", TP +",
         DoubleToString(InpTakeProfitIndexPoints, 1), " punti indice.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   if(InpRequireH4Chart && _Period != PERIOD_H4)
      return;

   if(!IsNewH4Bar())
      return;

   // Use only closed candles: shift 1 = most recently closed H4 candle,
   // shift 2 = the closed candle immediately before it.
   double rsiValues[];
   ArraySetAsSeries(rsiValues, true);

   int needed = MathMax(InpRSIPeriod + InpRSISmoothingPeriod + 5, 10);
   if(BarsCalculated(rsiHandle) < needed)
   {
      Print("Dati RSI insufficienti: attesa di altre candele H4.");
      return;
   }

   if(CopyBuffer(rsiHandle, 0, 1, 3, rsiValues) != 3)
   {
      Print("CopyBuffer RSI non riuscito. Errore=", GetLastError());
      return;
   }

   // Array is set as series: logical index 0 is the newest copied value.
   // With start=1,count=3: [0]=shift 1, [1]=shift 2, [2]=shift 3.
   double rsiShift1 = rsiValues[0];
   double rsiShift2 = rsiValues[1];

   double lowShift1 = iLow(_Symbol, PERIOD_H4, 1);
   if(lowShift1 <= 0.0)
   {
      Print("Minimo della candela H4 non disponibile.");
      return;
   }

   bool rsiRising  = (rsiShift1 > rsiShift2);
   bool rsiFalling = (rsiShift1 < rsiShift2);
   bool below30    = (rsiShift1 < InpOversoldLevel);

   Print("Nuova H4 chiusa. RSI precedente=", DoubleToString(rsiShift2, 2),
         " RSI ultimo=", DoubleToString(rsiShift1, 2),
         " RSI rising=", (rsiRising ? "true" : "false"),
         " RSI<30=", (below30 ? "true" : "false"));

   // After a signal, require a new downward turn below 30 before re-arming.
   // This permits multiple entries during a prolonged oversold period, but
   // only on distinct reversals rather than on every rising candle.
   if(waitForNewDipAfterSignal)
   {
      if(below30 && rsiFalling)
      {
         oversoldArmed = true;
         waitForNewDipAfterSignal = false;
         Print("Nuovo minimo in ipervenduto rilevato: EA riarmato per una nuova inversione.");
      }
      return;
   }

   // Initial setup: RSI must have been observed below 30 on a closed candle.
   if(below30)
      oversoldArmed = true;

   if(!oversoldArmed)
      return;

   // The RSI may rise above 30 before confirmation; the oversold setup remains
   // valid until a reversal is detected, because the user's rule permits this.
   if(!rsiRising)
      return;

   // Consume this reversal signal exactly once, even if a position is already
   // open or the broker rejects the order. A fresh dip below 30 is required
   // before another reversal can trigger an entry.
   oversoldArmed = false;
   waitForNewDipAfterSignal = true;

   // One open position at a time for this EA and symbol.
   if(HasEAPosition())
   {
      Print("Segnale BUY rilevato ma esiste già una posizione EA aperta. ",
            "Il segnale è consumato; serve una nuova discesa sotto 30.");
      return;
   }

   // SL is exactly the low of the just-closed H4 candle confirming RSI rise.
   OpenBuy(lowShift1);
}
//+------------------------------------------------------------------+
