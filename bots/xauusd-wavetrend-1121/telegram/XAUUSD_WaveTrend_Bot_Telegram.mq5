//+------------------------------------------------------------------+
//|                                    XAUUSD_WaveTrend_Bot.mq5       |
//|         Expert Advisor nativo MQL5 - conversione fedele del bot   |
//|         Python WaveTrend (LazyBear) Reversal Bot per XAUUSD       |
//+------------------------------------------------------------------+
//
// STRATEGIA (ESATTAMENTE come da specifica, nessun filtro aggiuntivo):
//
// - Simbolo: SOLO XAUUSD (InpSymbol), nessuna sostituzione automatica
// - Timeframe: M15, solo candele CHIUSE
// - Indicatore: WaveTrend Oscillator (LazyBear), CH_LEN=10, AVG_LEN=21,
//   WT_MA_LEN=4
// - Segnale: incrocio WT1/WT2 sulla candela M15 chiusa
//     BUY  -> WT1 prev <= WT2 prev  AND WT1 curr > WT2 curr
//     SELL -> WT1 prev >= WT2 prev  AND WT1 curr < WT2 curr
// - Finestra di apertura NUOVE operazioni: 15:30-17:30 ORARIO SERVER
// - SL/TP fissi: 100 pips (SL_PIPS/TP_PIPS), PIP_SIZE=0.1
// - Inversione automatica su incrocio contrario (ANCHE fuori dalla finestra)
// - 1 sola posizione del bot alla volta (MAGIC_NUMBER=991015), oppure
//   posizione virtuale simulata se PAPER_TRADING=true
// - Lotto fisso 0.10 (nessun money management dinamico)
// - PAPER_TRADING=true di default: simulazione completa (apertura, SL, TP,
//   inversione) senza alcun invio di ordini reali
// - All'avvio, la candela M15 gia' chiusa NON genera un segnale: viene
//   usata solo come riferimento, cosi' l'EA reagisce solo a candele nuove
//
// ORARIO SERVER - NESSUNA CONVERSIONE ARBITRARIA:
// A differenza della versione Python (dove la libreria MetaTrader5 espone i
// timestamp in UTC, obbligando a una conversione esplicita verso un
// timezone broker configurabile), in MQL5 nativo questo problema NON SI
// PONE: sia MqlRates.time (il timestamp di ogni candela) sia TimeCurrent()
// e TimeTradeServer() sono GIA' espressi nell'orario del trade server a cui
// il terminale e' connesso in questo momento. Non si assume Londra, Atene o
// un altro fuso: si usa direttamente l'orario che il server del broker
// comunica al terminale, qualunque esso sia, e lo si stampa nei log per
// verifica.
//
// NON aggiunti: M30, bande +-60, filtri discrezionali, ATR, RSI, MACD,
// trailing stop, break-even, martingala, grid, averaging, risk management
// percentuale. Gli unici controlli aggiunti sono di SICUREZZA/ROBUSTEZZA
// (validazione volume/pip/stops level, spread anomalo, verifica retcode),
// non modificano la strategia.
//+------------------------------------------------------------------+
#property copyright "Conversione MQL5 del bot Python WaveTrend XAUUSD"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//============================================================
// INPUT - PARAMETRI CONFIGURABILI (valori predefiniti = strategia originale)
//============================================================
input string InpSymbol           = "XAUUSD"; // Simbolo (ESCLUSIVAMENTE XAUUSD, nessuna sostituzione automatica)
input double InpLotSize          = 0.10;     // Lotto fisso
input int    InpSlPips           = 100;      // Stop Loss (pips)
input int    InpTpPips           = 100;      // Take Profit (pips)
input double InpPipSize          = 0.1;      // Dimensione di 1 pip in unita' di prezzo
input int    InpTradingStartHour = 15;       // Ora inizio finestra nuove aperture (ORARIO SERVER)
input int    InpTradingStartMin  = 30;       // Minuto inizio finestra nuove aperture (ORARIO SERVER)
input int    InpTradingEndHour   = 17;       // Ora fine finestra nuove aperture (ORARIO SERVER)
input int    InpTradingEndMin    = 30;       // Minuto fine finestra nuove aperture (ORARIO SERVER)
input int    InpChLen            = 10;       // WaveTrend - Channel Length
input int    InpAvgLen           = 21;       // WaveTrend - Average Length
input int    InpWtMaLen          = 4;        // WaveTrend - Signal (SMA) Length
input ulong  InpMagicNumber      = 991015;   // Magic Number
input int    InpDeviation        = 30;       // Deviazione massima (slippage) in punti
input double InpMaxSpreadPoints  = 0;        // Spread massimo consentito in punti (0 = controllo disattivato)
input int    InpRatesCount       = 300;      // Candele M15 da scaricare per il calcolo WaveTrend
input int    InpPollSeconds      = 5;        // Intervallo di polling (secondi) per rilevare nuove candele
input bool   InpPaperTrading     = true;     // PAPER_TRADING: se true, nessun ordine reale viene inviato
input bool   InpTelegramEnabled   = false;
input string InpTelegramToken     = "";
input long   InpTelegramChatId    = 0;
input int    InpTelegramTimeoutMs = 5000;      // Timeout WebRequest Telegram (ms)


//============================================================
// STRUTTURE DATI
//============================================================
struct VirtualPosition
  {
   bool     active;
   string   direction;   // "BUY" oppure "SELL"
   double   entry;
   double   sl;
   double   tp;
   double   volume;
   ulong    ticket;
   datetime openTime;
  };

struct BotPosition
  {
   bool     exists;
   string   direction;
   ulong    ticket;
   double   volume;
   double   entry;
   double   sl;
   double   tp;
  };

struct SignalResult
  {
   string   direction;   // "" = nessun segnale
   datetime candleTime;  // orario SERVER della candela chiusa che ha generato il segnale
   double   wt1v;
   double   wt2v;
  };

//============================================================
// STATO GLOBALE
//============================================================
CTrade           g_trade;
VirtualPosition  g_virtualPosition;
ulong            g_virtualTicketCounter = 100000;
datetime         g_lastProcessedTime    = 0;

//+------------------------------------------------------------------+
//| Validazione simbolo: nessuna sostituzione automatica              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Telegram - invio notifiche tramite Bot API                       |
//+------------------------------------------------------------------+
string TelegramUrlEncode(const string text)
  {
   string out = "";
   int len = StringLen(text);
   for(int i = 0; i < len; i++)
     {
      ushort c = StringGetCharacter(text, i);
      bool safe = ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
                   (c >= 'a' && c <= 'z') || c == '-' || c == '_' ||
                   c == '.' || c == '~');
      if(safe) out += ShortToString(c);
      else if(c == ' ') out += "%20";
      else if(c <= 255) out += StringFormat("%%%02X", (int)c);
      else out += "%3F";
     }
   return(out);
  }

bool SendTelegramMessage(const string message)
  {
   if(!InpTelegramEnabled) return(true);
   if(StringLen(InpTelegramToken) < 20 || InpTelegramToken == "INSERISCI_IL_TOKEN_DI_BOTFATHER")
     { Print("Telegram: token non configurato. Inserisci InpTelegramToken."); return(false); }
   string url = "https://api.telegram.org/bot" + InpTelegramToken +
                "/sendMessage?chat_id=" + (string)InpTelegramChatId +
                "&text=" + TelegramUrlEncode(message);
   char data[]; char result[]; string resultHeaders = "";
   ResetLastError();
   int status = WebRequest("GET", url, "", "", InpTelegramTimeoutMs, data, 0, result, resultHeaders);
   if(status == -1)
     { PrintFormat("Telegram WebRequest fallita. Errore=%d. Controlla gli URL consentiti in MT5.", GetLastError()); return(false); }
   if(status != 200)
     { PrintFormat("Telegram HTTP status=%d | risposta=%s", status, CharArrayToString(result)); return(false); }
   PrintFormat("Telegram: messaggio inviato (%s)", message);
   return(true);
  }

bool ValidateSymbol()
  {
   if(!(bool)SymbolInfoInteger(InpSymbol, SYMBOL_EXIST))
     {
      PrintFormat("Il simbolo '%s' non esiste su questo broker. Il bot NON tradera' un simbolo diverso "
                  "(es. %s.a, %s.pro, %sm). Correggi manualmente InpSymbol.",
                  InpSymbol, InpSymbol, InpSymbol, InpSymbol);
      return(false);
     }

   if(!(bool)SymbolInfoInteger(InpSymbol, SYMBOL_VISIBLE))
     {
      if(!SymbolSelect(InpSymbol, true))
        {
         PrintFormat("Impossibile rendere visibile il simbolo '%s'. Errore=%d", InpSymbol, GetLastError());
         return(false);
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Validazione LOT_SIZE contro volume_min/max/step del simbolo       |
//+------------------------------------------------------------------+
bool ValidateVolume()
  {
   double volMin  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
   if(volStep <= 0.0)
      volStep = 0.01;

   if(InpLotSize < volMin - 1e-9 || InpLotSize > volMax + 1e-9)
     {
      PrintFormat("LOT_SIZE=%.2f fuori dal range consentito dal broker per %s (volume_min=%.2f, volume_max=%.2f). "
                  "Correggi InpLotSize.", InpLotSize, InpSymbol, volMin, volMax);
      return(false);
     }

   double steps        = MathRound((InpLotSize - volMin) / volStep);
   double reconstructed = volMin + steps * volStep;
   if(MathAbs(reconstructed - InpLotSize) > 1e-6)
     {
      PrintFormat("LOT_SIZE=%.2f non e' un multiplo valido di volume_step=%.2f (volume_min=%.2f) per %s. "
                  "Correggi InpLotSize.", InpLotSize, volStep, volMin, InpSymbol);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Validazione PIP_SIZE contro la griglia 'point' del simbolo        |
//| (MT5 non espone un concetto universale di "pip": si verifica solo |
//| la coerenza interna della configurazione, non si modifica nulla)  |
//+------------------------------------------------------------------+
bool ValidatePipSize()
  {
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);

   if(InpPipSize <= 0.0)
     {
      Print("PIP_SIZE deve essere un valore positivo.");
      return(false);
     }

   if(point <= 0.0)
     {
      PrintFormat("Il simbolo %s riporta un 'point' non valido (%.8f).", InpSymbol, point);
      return(false);
     }

   double ratio = InpPipSize / point;
   if(MathAbs(ratio - MathRound(ratio)) > 1e-6)
     {
      PrintFormat("PIP_SIZE=%.8f non e' un multiplo del point (%.8f) di %s. Correggi manualmente PIP_SIZE.",
                  InpPipSize, point, InpSymbol);
      return(false);
     }

   double slDistance = InpSlPips * InpPipSize;
   double tpDistance = InpTpPips * InpPipSize;
   if(slDistance <= 0.0 || tpDistance <= 0.0)
     {
      Print("SL_PIPS/TP_PIPS combinati con PIP_SIZE producono una distanza di prezzo non valida.");
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Determina un filling mode compatibile con il simbolo              |
//| (non forza ciecamente ORDER_FILLING_FOK)                          |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
  {
   long filling = SymbolInfoInteger(InpSymbol, SYMBOL_FILLING_MODE);

   if((filling & SYMBOL_FILLING_FOK) != 0)
      return(ORDER_FILLING_FOK);
   if((filling & SYMBOL_FILLING_IOC) != 0)
      return(ORDER_FILLING_IOC);

   return(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| Log diagnostico completo all'avvio                                |
//+------------------------------------------------------------------+
void LogStartupDiagnostics()
  {
   double slDistance = InpSlPips * InpPipSize;
   double tpDistance = InpTpPips * InpPipSize;
   int    digits     = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);
   double point       = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);

   Print("==================== CONTROLLO DI AVVIO ====================");
   Print("EA = XAUUSD_WaveTrend_Bot");
   PrintFormat("SYMBOL = %s", InpSymbol);
   Print("TIMEFRAME = M15");
   PrintFormat("MAGIC_NUMBER = %I64u", InpMagicNumber);
   PrintFormat("LOT_SIZE = %.2f", InpLotSize);
   PrintFormat("SL_PIPS = %d -> distanza prezzo SL = %.5f", InpSlPips, slDistance);
   PrintFormat("TP_PIPS = %d -> distanza prezzo TP = %.5f", InpTpPips, tpDistance);
   PrintFormat("PIP_SIZE = %.8f", InpPipSize);
   PrintFormat("digits = %d | point = %.8f", digits, point);
   PrintFormat("Finestra nuove aperture = %02d:%02d - %02d:%02d (ORARIO SERVER, nessuna conversione di fuso)",
               InpTradingStartHour, InpTradingStartMin, InpTradingEndHour, InpTradingEndMin);
   PrintFormat("Orario server attuale (TimeTradeServer) = %s", TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   PrintFormat("Stato connessione terminale = %s", (bool)TerminalInfoInteger(TERMINAL_CONNECTED) ? "CONNESSO" : "NON CONNESSO");
   PrintFormat("Modalita' operativa = %s", InpPaperTrading ? "PAPER_TRADING (nessun ordine reale)" : "TRADING REALE");
   Print("==============================================================");
  }

//+------------------------------------------------------------------+
//| WaveTrend Oscillator - LazyBear                                   |
//|   ap  = (High+Low+Close)/3                                        |
//|   esa = EMA(ap, CH_LEN)                                           |
//|   d   = EMA(abs(ap-esa), CH_LEN)                                  |
//|   ci  = (ap-esa) / (0.015*d)                                      |
//|   wt1 = EMA(ci, AVG_LEN)                                          |
//|   wt2 = SMA(wt1, WT_MA_LEN)                                       |
//| rates[] deve essere in ordine cronologico ascendente               |
//| (ArraySetAsSeries(rates,false)): indice 0 = piu' vecchia candela   |
//+------------------------------------------------------------------+
bool ComputeWaveTrend(const MqlRates &rates[], int ratesTotal, double &wt1[], double &wt2[])
  {
   if(ratesTotal < InpAvgLen + InpWtMaLen + 3)
      return(false);

   double ap[], esa[], d[], ci[];
   ArrayResize(ap, ratesTotal);
   ArrayResize(esa, ratesTotal);
   ArrayResize(d, ratesTotal);
   ArrayResize(ci, ratesTotal);
   ArrayResize(wt1, ratesTotal);
   ArrayResize(wt2, ratesTotal);

   double alpha1 = 2.0 / (InpChLen + 1.0);
   double alpha2 = 2.0 / (InpAvgLen + 1.0);

   for(int i = 0; i < ratesTotal; i++)
      ap[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0;

   esa[0] = ap[0];
   for(int i = 1; i < ratesTotal; i++)
      esa[i] = esa[i - 1] + alpha1 * (ap[i] - esa[i - 1]);

   d[0] = MathAbs(ap[0] - esa[0]);
   for(int i = 1; i < ratesTotal; i++)
     {
      double absDiff = MathAbs(ap[i] - esa[i]);
      d[i] = d[i - 1] + alpha1 * (absDiff - d[i - 1]);
     }

   for(int i = 0; i < ratesTotal; i++)
     {
      double denom = 0.015 * d[i];
      ci[i] = (denom != 0.0) ? (ap[i] - esa[i]) / denom : 0.0;
     }

   wt1[0] = ci[0];
   for(int i = 1; i < ratesTotal; i++)
      wt1[i] = wt1[i - 1] + alpha2 * (ci[i] - wt1[i - 1]);

   for(int i = 0; i < ratesTotal; i++)
     {
      int start = i - InpWtMaLen + 1;
      if(start < 0)
         start = 0;
      double sum = 0.0;
      int    cnt = 0;
      for(int j = start; j <= i; j++)
        {
         sum += wt1[j];
         cnt++;
        }
      wt2[i] = sum / cnt;
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Rileva il segnale (crossover WT1/WT2) sull'ultima candela CHIUSA. |
//| rates[ratesTotal-1] = candela in formazione (MAI usata)           |
//| rates[ratesTotal-2] = ultima candela CHIUSA                       |
//| rates[ratesTotal-3] = candela chiusa precedente                   |
//+------------------------------------------------------------------+
SignalResult DetectSignal(const MqlRates &rates[], int ratesTotal, const double &wt1[], const double &wt2[])
  {
   SignalResult sig;
   sig.direction  = "";
   sig.candleTime = 0;
   sig.wt1v       = 0.0;
   sig.wt2v       = 0.0;

   if(ratesTotal < InpAvgLen + InpWtMaLen + 3)
      return(sig);

   int closedIdx = ratesTotal - 2;
   int prevIdx   = ratesTotal - 3;

   sig.candleTime = rates[closedIdx].time;
   sig.wt1v       = wt1[closedIdx];
   sig.wt2v       = wt2[closedIdx];

   bool bullish = (wt1[prevIdx] <= wt2[prevIdx]) && (wt1[closedIdx] > wt2[closedIdx]);
   bool bearish = (wt1[prevIdx] >= wt2[prevIdx]) && (wt1[closedIdx] < wt2[closedIdx]);

   if(bullish)
      sig.direction = "BUY";
   else
      if(bearish)
         sig.direction = "SELL";

   return(sig);
  }

//+------------------------------------------------------------------+
//| Finestra 15:30-17:30 ORARIO SERVER.                                |
//| candleTime e' gia' espresso in orario server (MqlRates.time):     |
//| nessuna conversione di fuso e' necessaria ne' viene applicata.     |
//+------------------------------------------------------------------+
bool IsWithinTradingWindow(datetime candleTime)
  {
   MqlDateTime dt;
   TimeToStruct(candleTime, dt);

   int minutesOfDay = dt.hour * 60 + dt.min;
   int startMinutes = InpTradingStartHour * 60 + InpTradingStartMin;
   int endMinutes   = InpTradingEndHour * 60 + InpTradingEndMin;

   bool inside = (minutesOfDay >= startMinutes && minutesOfDay <= endMinutes);

   PrintFormat("Controllo sessione | candela (server) = %s | finestra %02d:%02d-%02d:%02d -> %s",
               TimeToString(candleTime, TIME_DATE | TIME_MINUTES),
               InpTradingStartHour, InpTradingStartMin, InpTradingEndHour, InpTradingEndMin,
               inside ? "DENTRO" : "FUORI");

   return(inside);
  }

//+------------------------------------------------------------------+
//| Ritorna la posizione attualmente aperta dal bot, in modo unificato|
//| (reale su MT5 tramite MAGIC_NUMBER, oppure virtuale in paper mode)|
//+------------------------------------------------------------------+
BotPosition GetCurrentPosition()
  {
   BotPosition pos;
   pos.exists    = false;
   pos.direction = "";
   pos.ticket    = 0;
   pos.volume    = 0.0;
   pos.entry     = 0.0;
   pos.sl        = 0.0;
   pos.tp        = 0.0;

   if(InpPaperTrading)
     {
      if(!g_virtualPosition.active)
         return(pos);

      pos.exists    = true;
      pos.direction = g_virtualPosition.direction;
      pos.ticket    = (ulong)g_virtualPosition.ticket;
      pos.volume    = g_virtualPosition.volume;
      pos.entry     = g_virtualPosition.entry;
      pos.sl        = g_virtualPosition.sl;
      pos.tp        = g_virtualPosition.tp;
      return(pos);
     }

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      string symbolOfPos = PositionGetString(POSITION_SYMBOL);
      ulong  magicOfPos  = (ulong)PositionGetInteger(POSITION_MAGIC);

      if(symbolOfPos == InpSymbol && magicOfPos == InpMagicNumber)
        {
         long type = PositionGetInteger(POSITION_TYPE);
         pos.exists    = true;
         pos.direction = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         pos.ticket    = ticket;
         pos.volume    = PositionGetDouble(POSITION_VOLUME);
         pos.entry     = PositionGetDouble(POSITION_PRICE_OPEN);
         pos.sl        = PositionGetDouble(POSITION_SL);
         pos.tp        = PositionGetDouble(POSITION_TP);
         return(pos);
        }
     }

   return(pos);
  }

//+------------------------------------------------------------------+
//| Calcolo SL/TP fissi a partire da PIP_SIZE/SL_PIPS/TP_PIPS          |
//+------------------------------------------------------------------+
void CalcSlTp(string direction, double entryPrice, double &sl, double &tp)
  {
   double offset   = InpSlPips * InpPipSize;
   double tpOffset = InpTpPips * InpPipSize;

   if(direction == "BUY")
     {
      sl = entryPrice - offset;
      tp = entryPrice + tpOffset;
     }
   else
     {
      sl = entryPrice + offset;
      tp = entryPrice - tpOffset;
     }

   int digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
  }

//+------------------------------------------------------------------+
//| Verifica stops level / freeze level del broker                    |
//+------------------------------------------------------------------+
bool CheckStopsLevel(double entryPrice, double sl, double tp)
  {
   double point       = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   long   stopsLevel  = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLevel = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long   minLevel    = (stopsLevel > freezeLevel) ? stopsLevel : freezeLevel;
   double minDistance = minLevel * point;

   if(minDistance <= 0.0)
      return(true);

   if(MathAbs(entryPrice - sl) < minDistance || MathAbs(entryPrice - tp) < minDistance)
     {
      PrintFormat("Distanza SL/TP inferiore al livello minimo richiesto dal broker "
                  "(stops/freeze level=%d punti=%.5f). Ordine annullato.", (int)minLevel, minDistance);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Apre una nuova posizione (reale o virtuale) con SL/TP fissi       |
//+------------------------------------------------------------------+
bool OpenNewPosition(string direction, string comment)
  {
   long tradeMode = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
     {
      PrintFormat("Trading disabilitato per %s in questo momento (SYMBOL_TRADE_MODE_DISABLED). Apertura annullata.",
                  InpSymbol);
      return(false);
     }

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
     {
      PrintFormat("Impossibile leggere il tick per %s. Errore=%d", InpSymbol, GetLastError());
      return(false);
     }

   double entryPrice = (direction == "BUY") ? tick.ask : tick.bid;

   if(InpMaxSpreadPoints > 0.0)
     {
      double point        = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
      double spreadPoints = (point > 0.0) ? (tick.ask - tick.bid) / point : 0.0;
      if(spreadPoints > InpMaxSpreadPoints)
        {
         PrintFormat("Spread anomalo (%.1f punti > massimo consentito %.1f). Apertura annullata per sicurezza.",
                     spreadPoints, InpMaxSpreadPoints);
         return(false);
        }
     }

   double sl, tp;
   CalcSlTp(direction, entryPrice, sl, tp);

   if(!CheckStopsLevel(entryPrice, sl, tp))
      return(false);

   PrintFormat("Entry = %.5f", entryPrice);
   PrintFormat("SL = %.5f", sl);
   PrintFormat("TP = %.5f", tp);

   if(InpPaperTrading)
     {
      g_virtualTicketCounter++;
      g_virtualPosition.active    = true;
      g_virtualPosition.direction = direction;
      g_virtualPosition.entry     = entryPrice;
      g_virtualPosition.sl        = sl;
      g_virtualPosition.tp        = tp;
      g_virtualPosition.volume    = InpLotSize;
      g_virtualPosition.ticket    = g_virtualTicketCounter;
      g_virtualPosition.openTime  = TimeTradeServer();

      PrintFormat("[PAPER_TRADING] Apertura %s %.2f | ticket virtuale=%I64u | %s",
                  direction, InpLotSize, g_virtualPosition.ticket, comment);
      SendTelegramMessage("APERTURA " + direction + " | " + InpSymbol +
                          " | Entry=" + DoubleToString(entryPrice, 2) +
                          " | SL=" + DoubleToString(sl, 2) +
                          " | TP=" + DoubleToString(tp, 2) +
                          " | Lotto=" + DoubleToString(InpLotSize, 2) + " | PAPER");
      return(true);
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFilling(GetFillingMode());

   bool sent;
   if(direction == "BUY")
      sent = g_trade.Buy(InpLotSize, InpSymbol, entryPrice, sl, tp, comment);
   else
      sent = g_trade.Sell(InpLotSize, InpSymbol, entryPrice, sl, tp, comment);

   if(!sent)
     {
      PrintFormat("ORDINE FALLITO - Retcode=%d (%s)", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return(false);
     }

   uint retcode = g_trade.ResultRetcode();
   if(retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED && retcode != TRADE_RETCODE_DONE_PARTIAL)
     {
      PrintFormat("ORDINE FALLITO - Retcode=%d (%s)", retcode, g_trade.ResultRetcodeDescription());
      return(false);
     }

   PrintFormat("Apertura %s %.2f | Entry=%.5f | SL=%.5f | TP=%.5f | ticket=%I64u | Magic=%I64u",
               direction, InpLotSize, entryPrice, sl, tp, g_trade.ResultOrder(), InpMagicNumber);
   SendTelegramMessage("APERTURA " + direction + " | " + InpSymbol +
                       " | Entry=" + DoubleToString(entryPrice, 2) +
                       " | SL=" + DoubleToString(sl, 2) +
                       " | TP=" + DoubleToString(tp, 2) +
                       " | Lotto=" + DoubleToString(InpLotSize, 2) + " | REALE");
   return(true);
  }

//+------------------------------------------------------------------+
//| Chiude la posizione corrente (reale o virtuale)                   |
//+------------------------------------------------------------------+
bool CloseCurrentPosition(const BotPosition &pos, string comment)
  {
   if(InpPaperTrading)
     {
      PrintFormat("[PAPER_TRADING] Chiusura %s ticket virtuale=%I64u (%s)", pos.direction, pos.ticket, comment);
      g_virtualPosition.active = false;
      SendTelegramMessage("CHIUSURA " + pos.direction + " | " + InpSymbol +
                          " | Entry=" + DoubleToString(pos.entry, 2) +
                          " | Motivo=" + comment + " | PAPER");
      return(true);
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFilling(GetFillingMode());

   bool ok = g_trade.PositionClose(pos.ticket, (ulong)InpDeviation);

   if(!ok)
     {
      PrintFormat("CHIUSURA FALLITA - Retcode=%d (%s)", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return(false);
     }

   uint retcode = g_trade.ResultRetcode();
   if(retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_DONE_PARTIAL)
     {
      PrintFormat("CHIUSURA FALLITA - Retcode=%d (%s)", retcode, g_trade.ResultRetcodeDescription());
      return(false);
     }

   PrintFormat("Posizione ticket=%I64u chiusa (%s)", pos.ticket, comment);
   return(true);
  }

//+------------------------------------------------------------------+
//| In PAPER_TRADING il broker non gestisce SL/TP da solo: l'EA lo    |
//| simula confrontando il prezzo corrente con i livelli della        |
//| posizione virtuale, indipendentemente dalla fascia oraria.        |
//+------------------------------------------------------------------+
void CheckVirtualPositionSlTp()
  {
   if(!InpPaperTrading || !g_virtualPosition.active)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return;

   bool   hitTp = false;
   bool   hitSl = false;
   double currentPrice = 0.0;

   if(g_virtualPosition.direction == "BUY")
     {
      currentPrice = tick.bid;
      hitTp = (currentPrice >= g_virtualPosition.tp);
      hitSl = (currentPrice <= g_virtualPosition.sl);
     }
   else
     {
      currentPrice = tick.ask;
      hitTp = (currentPrice <= g_virtualPosition.tp);
      hitSl = (currentPrice >= g_virtualPosition.sl);
     }

   if(hitTp)
     {
      PrintFormat("[PAPER_TRADING] TP raggiunto - Chiusura %s ticket virtuale=%I64u a prezzo=%.5f",
                  g_virtualPosition.direction, g_virtualPosition.ticket, currentPrice);
      SendTelegramMessage("TP RAGGIUNTO | " + g_virtualPosition.direction + " | " + InpSymbol +
                          " | Prezzo=" + DoubleToString(currentPrice, 2) + " | PAPER");
      g_virtualPosition.active = false;
     }
   else
      if(hitSl)
        {
         PrintFormat("[PAPER_TRADING] SL raggiunto - Chiusura %s ticket virtuale=%I64u a prezzo=%.5f",
                     g_virtualPosition.direction, g_virtualPosition.ticket, currentPrice);
         SendTelegramMessage("SL RAGGIUNTO | " + g_virtualPosition.direction + " | " + InpSymbol +
                             " | Prezzo=" + DoubleToString(currentPrice, 2) + " | PAPER");
         g_virtualPosition.active = false;
        }
  }

//+------------------------------------------------------------------+
//| Gestisce un segnale rilevato: reversal se posizione contraria     |
//| esistente (ANCHE fuori dalla finestra oraria), altrimenti nuova   |
//| apertura solo se dentro la finestra 15:30-17:30 server.           |
//+------------------------------------------------------------------+
void HandleSignal(const SignalResult &sig)
  {
   if(sig.direction == "")
      return;

   PrintFormat("WT1 = %.4f", sig.wt1v);
   PrintFormat("WT2 = %.4f", sig.wt2v);
   PrintFormat("Segnale %s", sig.direction);

   BotPosition pos = GetCurrentPosition();

   if(pos.exists)
     {
      if(pos.direction == sig.direction)
        {
         PrintFormat("Posizione %s gia' aperta. Nessuna nuova entrata sullo stesso incrocio.", pos.direction);
         return;
        }

      // Incrocio contrario -> chiudi e inverti immediatamente.
      // Avviene ANCHE fuori dalla fascia oraria 15:30-17:30 server: la
      // gestione di una posizione gia' aperta (SL, TP, inversione) prosegue
      // sempre, indipendentemente dalla finestra di ingresso.
      Print("INCROCIO CONTRARIO");
      PrintFormat("Chiusura %s", pos.direction);

      string previousDirection = pos.direction;
      bool closedOk = CloseCurrentPosition(pos, "Reversal close");

      if(!closedOk)
        {
         Print("Chiusura posizione fallita: inversione ANNULLATA per sicurezza. "
               "Non viene aperta nessuna nuova posizione senza prima aver chiuso quella esistente.");
         return;
        }

      BotPosition verify = GetCurrentPosition();
      if(verify.exists)
        {
         Print("Verifica post-chiusura fallita: risulta ancora una posizione aperta. Apertura annullata.");
         return;
        }

      if(previousDirection == "BUY")
         Print("REVERSAL BUY -> SELL");
      else
         Print("REVERSAL SELL -> BUY");

      OpenNewPosition(sig.direction, "Reversal open");
      return;
     }

   // Nessuna posizione del bot aperta: apri una nuova entrata SOLO se la
   // candela che ha generato il segnale rientra nella fascia 15:30-17:30
   // ORARIO SERVER.
   if(!IsWithinTradingWindow(sig.candleTime))
     {
      PrintFormat("Segnale %s ricevuto ma la candela e' fuori dalla fascia oraria operativa %02d:%02d-%02d:%02d "
                  "(server). Nessuna apertura.", sig.direction,
                  InpTradingStartHour, InpTradingStartMin, InpTradingEndHour, InpTradingEndMin);
      return;
     }

   PrintFormat("Apertura %s %.2f", sig.direction, InpLotSize);
   OpenNewPosition(sig.direction, "New entry");
  }

//+------------------------------------------------------------------+
//| Ciclo principale: scarica le candele, calcola il WaveTrend,       |
//| rileva una nuova candela M15 chiusa ed eventualmente processa un  |
//| segnale. Idempotente: se richiamato piu' volte sulla stessa       |
//| candela non genera doppie esecuzioni (guardia g_lastProcessedTime)|
//+------------------------------------------------------------------+
void ProcessCycle()
  {
   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      Print("Terminale non connesso al server. In attesa di riconnessione...");
      return;
     }

   CheckVirtualPositionSlTp();

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(InpSymbol, PERIOD_M15, 0, InpRatesCount, rates);

   if(copied <= 0)
     {
      PrintFormat("Impossibile scaricare le candele M15 per %s. Errore=%d", InpSymbol, GetLastError());
      return;
     }

   if(copied < 2)
      return;

   double wt1[], wt2[];
   if(!ComputeWaveTrend(rates, copied, wt1, wt2))
      return; // storico insufficiente per calcolare CH_LEN/AVG_LEN/WT_MA_LEN

   datetime closedTime = rates[copied - 2].time;

   if(g_lastProcessedTime == 0)
     {
      // Difesa aggiuntiva: non dovrebbe accadere perche' OnInit lo imposta
      // sempre, ma se succede non generiamo un segnale "ritardato".
      g_lastProcessedTime = closedTime;
      return;
     }

   if(closedTime != g_lastProcessedTime)
     {
      PrintFormat("Nuova candela M15 chiusa: %s (server)", TimeToString(closedTime, TIME_DATE | TIME_MINUTES));
      SignalResult sig = DetectSignal(rates, copied, wt1, wt2);
      HandleSignal(sig);
      g_lastProcessedTime = closedTime;
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateSymbol())
      return(INIT_FAILED);

   if(!ValidateVolume())
      return(INIT_FAILED);

   if(!ValidatePipSize())
      return(INIT_FAILED);

   g_virtualPosition.active    = false;
   g_virtualPosition.direction = "";
   g_virtualPosition.entry     = 0.0;
   g_virtualPosition.sl        = 0.0;
   g_virtualPosition.tp        = 0.0;
   g_virtualPosition.volume    = 0.0;
   g_virtualPosition.ticket    = 0;
   g_virtualTicketCounter      = 100000;

   LogStartupDiagnostics();

   // Inizializzazione dell'ultima candela chiusa SENZA valutare un segnale:
   // evita che all'avvio, a meta' sessione, venga eseguito un ingresso
   // "ritardato" basato su una candela gia' passata. L'EA reagira' solo a
   // partire dalla PROSSIMA candela M15 che si chiudera'.
   MqlRates initRates[];
   ArraySetAsSeries(initRates, false);
   int copied = CopyRates(InpSymbol, PERIOD_M15, 0, InpRatesCount, initRates);

   g_lastProcessedTime = 0;
   if(copied >= 2)
     {
      g_lastProcessedTime = initRates[copied - 2].time;
      PrintFormat("Ultima candela M15 chiusa all'avvio: %s (server) - usata solo come riferimento, "
                  "nessun segnale valutato.", TimeToString(g_lastProcessedTime, TIME_DATE | TIME_MINUTES));
     }
   else
     {
      PrintFormat("Dati M15 insufficienti all'avvio per %s (copiate %d candele). L'EA rilevera' la prima "
                  "candela utile durante l'esecuzione.", InpSymbol, copied);
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviation);

   EventSetTimer(InpPollSeconds);

   Print("BOT AVVIATO");
   SendTelegramMessage("BOT AVVIATO | " + InpSymbol + " M15 | Modalita=" + (InpPaperTrading ? "PAPER" : "REALE"));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   PrintFormat("BOT ARRESTATO (reason=%d)", reason);
   SendTelegramMessage("BOT ARRESTATO | reason=" + IntegerToString(reason));
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//| Mantiene la simulazione SL/TP del paper trading reattiva ad ogni  |
//| tick; la rilevazione di nuove candele e la logica di segnale      |
//| restano nel polling temporizzato (OnTimer), come nel bot Python.  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Notifica chiusure REALI rilevate tramite transazione             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(InpPaperTrading) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(symbol != InpSymbol || (ulong)magic != InpMagicNumber || entry != DEAL_ENTRY_OUT) return;
   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   string reasonText = "CHIUSURA";
   if(reason == DEAL_REASON_TP) reasonText = "TP RAGGIUNTO";
   else if(reason == DEAL_REASON_SL) reasonText = "SL RAGGIUNTO";
   else if(reason == DEAL_REASON_EXPERT) reasonText = "CHIUSURA EA";
   SendTelegramMessage(reasonText + " | " + symbol +
                       " | Prezzo=" + DoubleToString(price, 2) +
                       " | Profit=" + DoubleToString(profit, 2) + " | REALE");
  }

void OnTick()
  {
   CheckVirtualPositionSlTp();
  }

//+------------------------------------------------------------------+
//| Timer function - polling periodico (default ogni 5 secondi)       |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ProcessCycle();
  }
//+------------------------------------------------------------------+
