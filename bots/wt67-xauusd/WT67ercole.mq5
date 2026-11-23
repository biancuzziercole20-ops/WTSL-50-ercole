//+------------------------------------------------------------------+
//|                                              WT67ercole.mq5
//|   Expert Advisor MQL5 - WaveTrend (LazyBear) Reversal su XAUUSD   |
//+------------------------------------------------------------------+
//
// STRATEGIA:
// - Simbolo: SOLO XAUUSD (InpSymbol), nessuna sostituzione automatica
// - Timeframe: M15, solo candele CHIUSE
// - Indicatore: WaveTrend (LazyBear), CH_LEN=10, AVG_LEN=21, WT_MA_LEN=4
// - Segnale: incrocio WT1/WT2 sulla candela M15 appena chiusa
//     BUY  -> WT1 prev <= WT2 prev  AND WT1 curr > WT2 curr
//     SELL -> WT1 prev >= WT2 prev  AND WT1 curr < WT2 curr
// - Lotto fisso 1.00 (conto da 100k). SL e TP a 10.00 di prezzo dall'ingresso
//   (100 pips x 0.1): con XAUUSD (contratto 100 oz) ogni operazione
//   chiusa a SL o TP perde o guadagna circa 1000 USD (1% di 100k).
// - Sessione NUOVE aperture: dalle 15:30:00 alle 17:29:59 ORA ITALIANA.
//   Servono entrambe: la candela M15 del segnale chiude dentro la sessione
//   E l'ora italiana nel momento dell'ordine e' dentro la sessione.
//   La candela 15:15-15:30 (chiusa alle 15:30) e' la prima che puo' aprire,
//   la 17:00-17:15 l'ultima. Alle 17:30 la sessione e' finita.
// - Inversione su incrocio contrario: la posizione aperta viene chiusa e
//   ne viene aperta una opposta. La riapertura e' una nuova operazione:
//   rispetta la finestra (InpReversalRespectsWindow) e il limite giornaliero.
// - Massimo InpMaxTradesPerDay (default 4) aperture per giorno italiano.
//   Il conteggio e' persistente: un riavvio dell'EA non lo azzera.
// - 1 sola posizione del bot alla volta (Magic Number).
// - PAPER_TRADING=true: simulazione senza ordini reali.
// - All'avvio la candela gia' chiusa NON genera segnali.
//
// ORA ITALIANA: orario server -> UTC con la regola del fuso del server
// (InpServerTzRule, FTMO = UTC+2/UTC+3 con ora legale USA) -> Italia con la
// regola UE (CET UTC+1 / CEST UTC+2). Dal vivo il risultato deve coincidere con
// l'orologio del PC; se la conversione non e' affidabile le nuove aperture
// vengono bloccate e il motivo compare nel log. Il contatore giornaliero
// riparte a mezzanotte italiana.
//+------------------------------------------------------------------+
#property copyright "WT67ercole"
#property version   "1.20"
#property strict

#define BOT_NAME      "WT67ercole"
#define BOT_GV_PREFIX "WT67"

#include <Trade\Trade.mqh>

// Fuso orario del server del broker (serve a ricavare l'UTC dall'orario server)
enum ENUM_SERVER_TZ_RULE
  {
   SERVER_TZ_NY_CLOSE = 0, // UTC+2 / UTC+3 con ora legale USA (FTMO)
   SERVER_TZ_EET_EU   = 1, // UTC+2 / UTC+3 con ora legale europea
   SERVER_TZ_FIXED    = 2, // Offset fisso da UTC (InpServerFixedUtcOffsetMin)
   SERVER_TZ_NONE     = 3  // Nessuna regola: solo orologio del PC (non funziona nel tester)
  };

//============================================================
// INPUT - PARAMETRI CONFIGURABILI (valori predefiniti = strategia originale)
//============================================================
input string InpSymbol           = "XAUUSD"; // Simbolo (ESCLUSIVAMENTE XAUUSD, nessuna sostituzione automatica)
input double InpLotSize          = 1.00;     // Lotto fisso (1.00 su conto 100k)
input int    InpSlPips           = 100;      // Stop Loss (pips): 100 x 0.1 = 10.00 di prezzo (~1000 USD con 1.00)
input int    InpTpPips           = 100;      // Take Profit (pips): 100 x 0.1 = 10.00 di prezzo (~1000 USD con 1.00)
input double InpPipSize          = 0.1;      // Dimensione di 1 pip in unita' di prezzo
input int    InpTradingStartHour = 15;       // Ora inizio sessione (ORA ITALIANA, compresa)
input int    InpTradingStartMin  = 30;       // Minuto inizio sessione (ORA ITALIANA, compreso)
input int    InpTradingEndHour   = 17;       // Ora fine sessione (ORA ITALIANA, esclusa: ultima apertura 17:29:59)
input int    InpTradingEndMin    = 30;       // Minuto fine sessione (ORA ITALIANA, escluso)
input int    InpChLen            = 10;       // WaveTrend - Channel Length
input int    InpAvgLen           = 21;       // WaveTrend - Average Length
input int    InpWtMaLen          = 4;        // WaveTrend - Signal (SMA) Length
input ulong  InpMagicNumber      = 670067;   // Magic Number
input int    InpDeviation        = 30;       // Deviazione massima (slippage) in punti
input double InpMaxSpreadPoints  = 0;        // Spread massimo consentito in punti (0 = controllo disattivato)
input int    InpRatesCount       = 300;      // Candele M15 da scaricare per il calcolo WaveTrend
input int    InpPollSeconds      = 5;        // Intervallo di polling (secondi) per rilevare nuove candele
input bool   InpPaperTrading     = false;    // PAPER_TRADING: se true, nessun ordine reale viene inviato
input bool   InpReversalRespectsWindow = true; // Reversal: la riapertura rispetta la sessione italiana (15:30:00-17:29:59)
input int    InpMaxTradesPerDay  = 4;        // Massimo operazioni (aperture) per giorno italiano
input ENUM_SERVER_TZ_RULE InpServerTzRule = SERVER_TZ_NY_CLOSE; // Fuso del server (FTMO: UTC+2/+3 ora legale USA)
input int    InpServerFixedUtcOffsetMin = 120; // Solo con offset fisso: minuti del server rispetto a UTC
input bool   InpCheckPcClock     = true;     // Dal vivo: l'ora calcolata deve coincidere con l'orologio del PC (ora italiana)

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
   PrintFormat("EA = %s", BOT_NAME);
   PrintFormat("SYMBOL = %s", InpSymbol);
   Print("TIMEFRAME = M15");
   PrintFormat("MAGIC_NUMBER = %I64u", InpMagicNumber);
   PrintFormat("LOT_SIZE = %.2f", InpLotSize);
   PrintFormat("SL_PIPS = %d -> distanza prezzo SL = %.5f", InpSlPips, slDistance);
   PrintFormat("TP_PIPS = %d -> distanza prezzo TP = %.5f", InpTpPips, tpDistance);
   PrintFormat("PIP_SIZE = %.8f", InpPipSize);
   PrintFormat("digits = %d | point = %.8f", digits, point);
   PrintFormat("Sessione nuove aperture = %s ORA ITALIANA (candela M15 chiusa e ora dell'ordine dentro la sessione)",
               WindowText());
   PrintFormat("Contract size %s = %.2f", InpSymbol, SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_CONTRACT_SIZE));
   double refPrice  = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double plAtTp    = 0.0;
   double plAtSl    = 0.0;
   if(refPrice > 0.0
      && OrderCalcProfit(ORDER_TYPE_BUY, InpSymbol, InpLotSize, refPrice, refPrice + tpDistance, plAtTp)
      && OrderCalcProfit(ORDER_TYPE_BUY, InpSymbol, InpLotSize, refPrice, refPrice - slDistance, plAtSl))
      PrintFormat("Risultato per operazione con %.2f lotti: TP = %+.2f %s | SL = %+.2f %s",
                  InpLotSize, plAtTp, AccountInfoString(ACCOUNT_CURRENCY), plAtSl, AccountInfoString(ACCOUNT_CURRENCY));
   PrintFormat("Limite operazioni giornaliere = %d | gia' aperte oggi (Italia) = %d",
               InpMaxTradesPerDay, CountTodayOpenings());
   int    startRuleOff  = 0;
   string startRuleName = "";
   RuleServerUtcOffset(TimeTradeServer(), startRuleOff, startRuleName);
   PrintFormat("Regola fuso server = %s | controllo con orologio PC = %s | Strategy Tester = %s",
               startRuleName, InpCheckPcClock ? "SI" : "NO",
               ((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION)) ? "SI" : "NO");
   PrintFormat("Orologio PC (TimeLocal) = %s | UTC di Windows (TimeGMT) = %s (solo informativi)",
               TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS), TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS));
   LogItalyClock("AVVIO");
   PrintFormat("Reversal rispetta la finestra oraria = %s", InpReversalRespectsWindow ? "SI" : "NO");
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
//| ORA ITALIANA                                                      |
//|                                                                   |
//| Fonte principale: orario del SERVER + regola del fuso del server  |
//| (InpServerTzRule). FTMO: UTC+2, UTC+3 durante l'ora legale USA.    |
//|   server -> UTC  : si toglie l'offset del server per quella data   |
//|   UTC -> Italia  : +1h (CET) oppure +2h (CEST) con la regola UE    |
//| Dal vivo il risultato viene confrontato con l'orologio del PC     |
//| (TimeLocal, deve mostrare l'ora italiana). Se non coincidono, o   |
//| se la conversione non e' possibile, le nuove aperture sono        |
//| BLOCCATE e il motivo viene scritto nel log.                       |
//| Nello Strategy Tester TimeGMT() e TimeLocal() coincidono con      |
//| l'orario del server simulato: l'unica fonte valida e' la regola   |
//| del server; senza regola il tester non apre nuove posizioni.      |
//+------------------------------------------------------------------+
#define SEC_QUARTER 900

struct ItalyClockInfo
  {
   bool     valid;
   datetime serverNow;
   datetime italyNow;
   int      serverMinusItalySec;   // orario server - ora italiana, adesso
   int      serverMinusUtcSec;     // orario server - UTC, adesso
   bool     italyDst;              // true = ora legale italiana (CEST, UTC+2)
   string   source;
   string   error;
  };

int g_lastClockState = -1;         // -1 sconosciuto, 0 conversione non valida, 1 valida

int RoundToQuarter(long seconds)
  {
   return((int)(MathRound((double)seconds / SEC_QUARTER) * SEC_QUARTER));
  }

//+------------------------------------------------------------------+
//| true se l'anno indicato e' bisestile (serve per il 29 febbraio    |
//| nel calcolo dell'ultima domenica di marzo/ottobre)                |
//+------------------------------------------------------------------+
bool IsLeapYear(int year)
  {
   return((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0));
  }

//+------------------------------------------------------------------+
//| Istante UTC (ore 'hourUtc') dell'ultima domenica di un dato mese/ |
//| anno. L'ora legale UE cambia alle 01:00 UTC dell'ultima domenica  |
//| di marzo (inizio) e di ottobre (fine).                            |
//+------------------------------------------------------------------+
datetime LastSundayOfMonthUtc(int year, int month, int hourUtc)
  {
   int daysInMonth[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
   int lastDay = daysInMonth[month - 1];
   if(month == 2 && IsLeapYear(year))
      lastDay = 29;

   MqlDateTime dt;
   dt.year = year;
   dt.mon  = month;
   dt.day  = lastDay;
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime lastDayTime = StructToTime(dt);

   TimeToStruct(lastDayTime, dt);          // popola dt.day_of_week (0=Domenica ... 6=Sabato)
   int sundayDay = lastDay - dt.day_of_week;

   dt.day  = sundayDay;
   dt.hour = hourUtc;
   dt.min  = 0;
   dt.sec  = 0;
   return(StructToTime(dt));
  }

//+------------------------------------------------------------------+
//| Istante UTC (ore 'hourUtc') della n-esima domenica (n = 1, 2, ...) |
//| di un dato mese/anno.                                             |
//+------------------------------------------------------------------+
datetime NthSundayOfMonthUtc(int year, int month, int n, int hourUtc)
  {
   MqlDateTime dt;
   dt.year = year;
   dt.mon  = month;
   dt.day  = 1;
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime firstDay = StructToTime(dt);

   TimeToStruct(firstDay, dt);             // popola dt.day_of_week (0=Domenica ... 6=Sabato)
   int firstSunday = 1 + (7 - dt.day_of_week) % 7;

   dt.day  = firstSunday + 7 * (n - 1);
   dt.hour = hourUtc;
   dt.min  = 0;
   dt.sec  = 0;
   return(StructToTime(dt));
  }

//+------------------------------------------------------------------+
//| true se l'istante UTC cade nell'ora legale italiana (CEST, UTC+2):|
//| dalle 01:00 UTC dell'ultima domenica di marzo alle 01:00 UTC      |
//| dell'ultima domenica di ottobre. Altrimenti CET, UTC+1.           |
//+------------------------------------------------------------------+
bool IsItalianDST(datetime utcTime)
  {
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);

   datetime dstStart = LastSundayOfMonthUtc(dt.year, 3, 1);
   datetime dstEnd   = LastSundayOfMonthUtc(dt.year, 10, 1);

   return(utcTime >= dstStart && utcTime < dstEnd);
  }

//+------------------------------------------------------------------+
//| true se l'istante UTC cade nell'ora legale USA (New York):        |
//| dalla 2a domenica di marzo 02:00 New York (07:00 UTC) alla 1a     |
//| domenica di novembre 02:00 New York (06:00 UTC).                  |
//+------------------------------------------------------------------+
bool IsUsDST(datetime utcTime)
  {
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);

   datetime dstStart = NthSundayOfMonthUtc(dt.year, 3, 2, 7);
   datetime dstEnd   = NthSundayOfMonthUtc(dt.year, 11, 1, 6);

   return(utcTime >= dstStart && utcTime < dstEnd);
  }

int ItalyUtcOffsetSec(datetime utcTime)
  {
   return(IsItalianDST(utcTime) ? 2 * 3600 : 1 * 3600);
  }

//+------------------------------------------------------------------+
//| Offset del server rispetto a UTC, per un orario SERVER, secondo   |
//| la regola scelta negli input. false = nessuna regola.             |
//| Per le regole UTC+2/+3 l'UTC si stima togliendo 2 ore: vicino al  |
//| cambio dell'ora (domenica mattina, mercato chiuso) la stima puo'  |
//| anticipare il cambio di al massimo un'ora.                        |
//+------------------------------------------------------------------+
bool RuleServerUtcOffset(datetime serverTime, int &offsetSec, string &ruleName)
  {
   offsetSec = 0;
   ruleName  = "nessuna regola";

   if(InpServerTzRule == SERVER_TZ_NY_CLOSE)
     {
      offsetSec = IsUsDST(serverTime - 2 * 3600) ? 3 * 3600 : 2 * 3600;
      ruleName  = "UTC+2/UTC+3 con ora legale USA";
      return(true);
     }
   if(InpServerTzRule == SERVER_TZ_EET_EU)
     {
      offsetSec = IsItalianDST(serverTime - 2 * 3600) ? 3 * 3600 : 2 * 3600;
      ruleName  = "UTC+2/UTC+3 con ora legale europea";
      return(true);
     }
   if(InpServerTzRule == SERVER_TZ_FIXED)
     {
      offsetSec = InpServerFixedUtcOffsetMin * 60;
      ruleName  = StringFormat("offset fisso UTC%+d min", InpServerFixedUtcOffsetMin);
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Calcola l'ora italiana ADESSO e verifica che sia affidabile.      |
//+------------------------------------------------------------------+
bool GetItalyClock(ItalyClockInfo &c)
  {
   c.valid               = false;
   c.serverNow           = TimeTradeServer();
   c.italyNow            = 0;
   c.serverMinusItalySec = 0;
   c.serverMinusUtcSec   = 0;
   c.italyDst            = false;
   c.source              = "";
   c.error               = "";

   if(c.serverNow <= 0)
     {
      c.error = "orario del server non disponibile";
      return(false);
     }

   bool   tester    = ((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION));
   int    ruleOff   = 0;
   string ruleName  = "";
   bool   hasRule   = RuleServerUtcOffset(c.serverNow, ruleOff, ruleName);
   int    ruleMinusItaly = 0;
   if(hasRule)
      ruleMinusItaly = ruleOff - ItalyUtcOffsetSec(c.serverNow - ruleOff);

   if(tester)
     {
      if(!hasRule)
        {
         c.error = "Strategy Tester senza regola del fuso del server (InpServerTzRule): nel tester non esiste "
                   "un orologio UTC reale, quindi l'ora italiana non e' calcolabile";
         return(false);
        }
      c.serverMinusUtcSec   = ruleOff;
      c.serverMinusItalySec = ruleMinusItaly;
      c.source              = "Strategy Tester, regola server " + ruleName + " (non verificabile con l'orologio del PC)";
     }
   else
     {
      int pcMinusItaly = RoundToQuarter((long)c.serverNow - (long)TimeLocal());
      if(hasRule)
        {
         if(InpCheckPcClock && pcMinusItaly != ruleMinusItaly)
           {
            c.error = StringFormat("la regola del server (%s) da' server-Italia %+d min, l'orologio del PC da' %+d min: "
                                   "controlla data, ora e fuso orario di Windows oppure la regola del server negli input",
                                   ruleName, ruleMinusItaly / 60, pcMinusItaly / 60);
            return(false);
           }
         c.serverMinusUtcSec   = ruleOff;
         c.serverMinusItalySec = ruleMinusItaly;
         c.source = InpCheckPcClock ? "regola server " + ruleName + ", confermata dall'orologio del PC"
                                    : "regola server " + ruleName + " (controllo orologio PC disattivato)";
        }
      else
        {
         // Nessuna regola del server: si usa il PC, ma solo se UTC di Windows e ora del PC sono coerenti.
         int pcMinusUtc = RoundToQuarter((long)c.serverNow - (long)TimeGMT());
         datetime utcNow = c.serverNow - pcMinusUtc;
         if(pcMinusUtc - pcMinusItaly != ItalyUtcOffsetSec(utcNow))
           {
            c.error = StringFormat("orologio del PC (%s) non coerente con l'ora UTC di Windows (%s): "
                                   "controlla il fuso orario di Windows (UTC+01:00 Roma, ora legale automatica)",
                                   TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
                                   TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS));
            return(false);
           }
         c.serverMinusUtcSec   = pcMinusUtc;
         c.serverMinusItalySec = pcMinusItaly;
         c.source              = "orologio del PC (nessuna regola del server)";
        }
     }

   if(c.serverMinusItalySec > 14 * 3600 || c.serverMinusItalySec < -14 * 3600)
     {
      c.error = StringFormat("differenza server-Italia non plausibile (%+d min)", c.serverMinusItalySec / 60);
      return(false);
     }

   c.italyNow = c.serverNow - c.serverMinusItalySec;
   c.italyDst = IsItalianDST(c.serverNow - c.serverMinusUtcSec);
   c.valid    = true;
   return(true);
  }

//+------------------------------------------------------------------+
//| Converte un orario SERVER (es. chiusura di una candela) in ora    |
//| italiana. false = conversione non disponibile o non affidabile.   |
//+------------------------------------------------------------------+
bool ServerToItaly(datetime serverTime, datetime &italyTime, string &err)
  {
   ItalyClockInfo c;
   italyTime = 0;
   if(!GetItalyClock(c))
     {
      err = c.error;
      return(false);
     }
   int    ruleOff  = 0;
   string ruleName = "";
   if(RuleServerUtcOffset(serverTime, ruleOff, ruleName))
     {
      datetime utc = serverTime - ruleOff;
      italyTime = utc + ItalyUtcOffsetSec(utc);
     }
   else
      italyTime = serverTime - c.serverMinusItalySec;
   err = "";
   return(true);
  }

// Solo per i log: 0 se la conversione non e' disponibile.
datetime ConvertServerTimeToItaly(datetime serverTime)
  {
   datetime it  = 0;
   string   err = "";
   if(!ServerToItaly(serverTime, it, err))
      return(0);
   return(it);
  }

// Ora italiana adesso, 0 se non disponibile.
datetime GetItalianTime()
  {
   ItalyClockInfo c;
   if(!GetItalyClock(c))
      return(0);
   return(c.italyNow);
  }

//+------------------------------------------------------------------+
//| Sessione italiana: dalle InpTradingStart (compreso) alle          |
//| InpTradingEnd (escluso). Default 15:30:00 - 17:29:59.              |
//+------------------------------------------------------------------+
bool IsItalianTradingSession(datetime italyTime)
  {
   if(italyTime <= 0)
      return(false);
   MqlDateTime dt;
   TimeToStruct(italyTime, dt);
   int secOfDay = dt.hour * 3600 + dt.min * 60 + dt.sec;
   int startSec = InpTradingStartHour * 3600 + InpTradingStartMin * 60;
   int endSec   = InpTradingEndHour * 3600 + InpTradingEndMin * 60;
   return(secOfDay >= startSec && secOfDay < endSec);
  }

string WindowText()
  {
   int endSec = InpTradingEndHour * 3600 + InpTradingEndMin * 60 - 1;
   return(StringFormat("%02d:%02d:00-%02d:%02d:%02d", InpTradingStartHour, InpTradingStartMin,
                       endSec / 3600, (endSec % 3600) / 60, endSec % 60));
  }

string TimeOrNA(datetime t, int flags)
  {
   if(t <= 0)
      return("N/D");
   return(TimeToString(t, flags));
  }

//+------------------------------------------------------------------+
//| Riga di diagnostica: ora server, ora italiana, data, DST, stato   |
//| della sessione ed eventuale errore di conversione.                |
//+------------------------------------------------------------------+
void LogItalyClock(string context)
  {
   ItalyClockInfo c;
   if(!GetItalyClock(c))
     {
      PrintFormat("[ORA] %s | Server time: %s | Italy time: N/D | Session allowed: NO | ERRORE conversione oraria: %s | Nuove aperture BLOCCATE",
                  context, TimeOrNA(c.serverNow, TIME_DATE | TIME_SECONDS), c.error);
      return;
     }
   PrintFormat("[ORA] %s | Server time: %s | Italy time: %s | Data Italia: %s | DST Italia: %s | Server-Italia: %+d min | Server-UTC: %+d min | Session %s allowed: %s | Fonte: %s",
               context,
               TimeToString(c.serverNow, TIME_DATE | TIME_SECONDS),
               TimeToString(c.italyNow, TIME_SECONDS),
               TimeToString(c.italyNow, TIME_DATE),
               c.italyDst ? "SI (CEST, UTC+2)" : "NO (CET, UTC+1)",
               c.serverMinusItalySec / 60, c.serverMinusUtcSec / 60,
               WindowText(),
               IsItalianTradingSession(c.italyNow) ? "YES" : "NO",
               c.source);
  }

// Scrive subito nel log quando la conversione diventa non valida o torna valida.
void CheckClockStateChange()
  {
   ItalyClockInfo c;
   int state = GetItalyClock(c) ? 1 : 0;
   if(state != g_lastClockState)
     {
      if(g_lastClockState != -1)
         LogItalyClock(state == 1 ? "CONVERSIONE ORARIA DI NUOVO VALIDA" : "CONVERSIONE ORARIA NON VALIDA");
      g_lastClockState = state;
     }
  }

//+------------------------------------------------------------------+
//| CONTROLLO DELLA SESSIONE per una nuova apertura. Consentita solo  |
//| se: la conversione oraria e' valida, la candela M15 del segnale   |
//| chiude dentro la sessione italiana E l'ora italiana attuale (il   |
//| momento in cui parte l'ordine) e' dentro la sessione.             |
//| candleCloseServer = orario SERVER di chiusura della candela.      |
//+------------------------------------------------------------------+
bool IsWithinItalianTradingWindow(datetime candleCloseServer)
  {
   ItalyClockInfo c;
   bool     clockOk     = GetItalyClock(c);
   datetime candleItaly = 0;
   string   err         = "";
   bool     candleOk    = clockOk && ServerToItaly(candleCloseServer, candleItaly, err);
   bool     candleIn    = candleOk && IsItalianTradingSession(candleItaly);
   bool     nowIn       = clockOk && IsItalianTradingSession(c.italyNow);
   bool     allowed     = clockOk && candleIn && nowIn;

   PrintFormat("CANDLE SERVER = %s | CANDLE ITALY = %s | NOW SERVER = %s | NOW ITALY = %s | WINDOW = %s | NEW ENTRY = %s",
               TimeOrNA(candleCloseServer, TIME_DATE | TIME_SECONDS),
               TimeOrNA(candleItaly, TIME_DATE | TIME_SECONDS),
               TimeOrNA(c.serverNow, TIME_DATE | TIME_SECONDS),
               TimeOrNA(clockOk ? c.italyNow : (datetime)0, TIME_DATE | TIME_SECONDS),
               WindowText(),
               allowed ? "ALLOWED" : "BLOCKED");
   if(!clockOk)
      PrintFormat("[ORA] ERRORE conversione oraria: %s. Nuove aperture BLOCCATE.", c.error);

   return(allowed);
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
//| PERSISTENZA della posizione virtuale (solo PAPER_TRADING) tramite |
//| Global Variables del terminale: sopravvivono a riavvio,           |
//| ricompilazione e cambio parametri dell'EA. Prima la posizione     |
//| virtuale viveva solo in memoria e OnInit la azzerava sempre: un   |
//| riavvio la "dimenticava" e il bot si credeva FLAT.                |
//+------------------------------------------------------------------+
string GvName(string field)
  {
   return(StringFormat("%s_%I64u_%s", BOT_GV_PREFIX, InpMagicNumber, field));
  }

string VPosGvName(string field)
  {
   return(GvName("VPOS_" + field));
  }

//+------------------------------------------------------------------+
//| LIMITE OPERAZIONI GIORNALIERE (giorno italiano).                  |
//| Il conteggio e' salvato in Global Variables (sopravvive ai        |
//| riavvii). In trading reale viene anche ricontato dallo storico    |
//| degli ingressi del bot e si usa il valore piu' alto dei due.      |
//+------------------------------------------------------------------+
// Giorno italiano (AAAAMMGG). 0 = ora italiana non disponibile.
int ItalianDayKey()
  {
   ItalyClockInfo c;
   if(!GetItalyClock(c))
      return(0);
   MqlDateTime dt;
   TimeToStruct(c.italyNow, dt);
   return(dt.year * 10000 + dt.mon * 100 + dt.day);
  }

// Orario SERVER della mezzanotte italiana di oggi. 0 = non disponibile.
datetime ItalianDayStartServerTime()
  {
   ItalyClockInfo c;
   if(!GetItalyClock(c))
      return(0);
   MqlDateTime dt;
   TimeToStruct(c.italyNow, dt);
   long secondsSinceMidnight = (long)dt.hour * 3600 + (long)dt.min * 60 + (long)dt.sec;
   return((datetime)((long)c.serverNow - secondsSinceMidnight));
  }

int GvTodayCount()
  {
   if(!GlobalVariableCheck(GvName("DAYKEY")) || !GlobalVariableCheck(GvName("DAYCOUNT")))
      return(0);
   int today = ItalianDayKey();
   if(today == 0)
      return(InpMaxTradesPerDay);  // giorno italiano non calcolabile: per sicurezza limite raggiunto
   if((int)GlobalVariableGet(GvName("DAYKEY")) != today)
      return(0);
   return((int)GlobalVariableGet(GvName("DAYCOUNT")));
  }

int HistoryTodayCount()
  {
   datetime fromTime = ItalianDayStartServerTime();
   if(fromTime <= 0)
      return(-1);
   if(!HistorySelect(fromTime, TimeTradeServer() + 86400))
      return(-1);

   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != InpSymbol)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      count++;
     }
   return(count);
  }

int CountTodayOpenings()
  {
   int count = GvTodayCount();
   if(!InpPaperTrading)
     {
      int fromHistory = HistoryTodayCount();
      if(fromHistory < 0)
         return(InpMaxTradesPerDay); // storico non leggibile: per sicurezza si considera il limite raggiunto
      if(fromHistory > count)
         count = fromHistory;
     }
   return(count);
  }

void RegisterTodayOpening()
  {
   if(ItalianDayKey() == 0)
     {
      Print("[ORA] ERRORE: giorno italiano non calcolabile, contatore giornaliero non aggiornato.");
      return;
     }
   int count = GvTodayCount() + 1;
   GlobalVariableSet(GvName("DAYKEY"),   (double)ItalianDayKey());
   GlobalVariableSet(GvName("DAYCOUNT"), (double)count);
   PrintFormat("Operazioni aperte oggi (Italia): %d/%d", count, InpMaxTradesPerDay);
  }

void SaveVirtualPositionState()
  {
   double dirCode = 0.0;
   if(g_virtualPosition.direction == "BUY")
      dirCode = 1.0;
   else
      if(g_virtualPosition.direction == "SELL")
         dirCode = -1.0;

   GlobalVariableSet(VPosGvName("ACTIVE"), g_virtualPosition.active ? 1.0 : 0.0);
   GlobalVariableSet(VPosGvName("DIR"),    dirCode);
   GlobalVariableSet(VPosGvName("ENTRY"),  g_virtualPosition.entry);
   GlobalVariableSet(VPosGvName("SL"),     g_virtualPosition.sl);
   GlobalVariableSet(VPosGvName("TP"),     g_virtualPosition.tp);
   GlobalVariableSet(VPosGvName("VOL"),    g_virtualPosition.volume);
   GlobalVariableSet(VPosGvName("TICKET"), (double)g_virtualPosition.ticket);
   GlobalVariableSet(VPosGvName("OPENT"),  (double)g_virtualPosition.openTime);
  }

void LoadVirtualPositionState()
  {
   if(!GlobalVariableCheck(VPosGvName("ACTIVE")))
     {
      Print("[PAPER_TRADING] Nessuno stato salvato: nessuna posizione virtuale da ripristinare.");
      return;
     }

   if(GlobalVariableGet(VPosGvName("ACTIVE")) <= 0.5)
     {
      Print("[PAPER_TRADING] Stato salvato: nessuna posizione virtuale attiva.");
      return;
     }

   double dirCode = GlobalVariableGet(VPosGvName("DIR"));
   if(dirCode == 0.0)
     {
      Print("[PAPER_TRADING] Stato salvato non valido (direzione assente): ignorato.");
      return;
     }

   g_virtualPosition.active    = true;
   g_virtualPosition.direction = (dirCode > 0.0) ? "BUY" : "SELL";
   g_virtualPosition.entry     = GlobalVariableGet(VPosGvName("ENTRY"));
   g_virtualPosition.sl        = GlobalVariableGet(VPosGvName("SL"));
   g_virtualPosition.tp        = GlobalVariableGet(VPosGvName("TP"));
   g_virtualPosition.volume    = GlobalVariableGet(VPosGvName("VOL"));
   g_virtualPosition.ticket    = (ulong)GlobalVariableGet(VPosGvName("TICKET"));
   g_virtualPosition.openTime  = (datetime)GlobalVariableGet(VPosGvName("OPENT"));

   if(g_virtualPosition.ticket > g_virtualTicketCounter)
      g_virtualTicketCounter = g_virtualPosition.ticket;

   PrintFormat("[PAPER_TRADING] Posizione virtuale RIPRISTINATA dopo riavvio: %s ticket=%I64u entry=%.5f SL=%.5f TP=%.5f",
               g_virtualPosition.direction, g_virtualPosition.ticket, g_virtualPosition.entry,
               g_virtualPosition.sl, g_virtualPosition.tp);
  }

//+------------------------------------------------------------------+
//| Apre una nuova posizione (reale o virtuale) con SL/TP fissi.      |
//| CONTROLLO HARD: per "New entry" (sempre) e per "Reversal open"    |
//| (se InpReversalRespectsWindow=true) la finestra oraria viene      |
//| ricontrollata QUI, nel punto esatto dell'apertura, sull'ora       |
//| italiana della candela M15 che ha generato il segnale. Se il      |
//| controllo fallisce, nessun ordine (reale o virtuale) parte.       |
//+------------------------------------------------------------------+
bool OpenNewPosition(string direction, string comment, datetime signalCandleServerTime, bool requireTradingWindow)
  {
   ItalyClockInfo clockNow;
   if(!GetItalyClock(clockNow))
     {
      PrintFormat("[ORA] ERRORE conversione oraria: %s. Apertura %s BLOCCATA (%s).", clockNow.error, direction, comment);
      return(false);
     }

   bool mustCheckWindow = requireTradingWindow || (comment == "New entry");
   if(mustCheckWindow)
     {
      if(signalCandleServerTime <= 0)
        {
         PrintFormat("HARD CHECK: orario candela del segnale non valido. Apertura %s BLOCCATA (%s).", direction, comment);
         return(false);
        }
      if(!IsWithinItalianTradingWindow(signalCandleServerTime))
        {
         PrintFormat("HARD CHECK: fuori sessione %s ora italiana. Apertura %s BLOCCATA (%s).", WindowText(), direction, comment);
         return(false);
        }
     }

   int openedToday = CountTodayOpenings();
   if(openedToday >= InpMaxTradesPerDay)
     {
      PrintFormat("LIMITE GIORNALIERO raggiunto (%d/%d). Apertura %s BLOCCATA (%s).",
                  openedToday, InpMaxTradesPerDay, direction, comment);
      return(false);
     }

   string orderComment = StringFormat("%s %s", BOT_NAME, comment);

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
      SaveVirtualPositionState();

      PrintFormat("[PAPER_TRADING] Apertura %s %.2f | ticket virtuale=%I64u | %s",
                  direction, InpLotSize, g_virtualPosition.ticket, comment);
      RegisterTodayOpening();
      return(true);
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFilling(GetFillingMode());

   bool sent;
   if(direction == "BUY")
      sent = g_trade.Buy(InpLotSize, InpSymbol, entryPrice, sl, tp, orderComment);
   else
      sent = g_trade.Sell(InpLotSize, InpSymbol, entryPrice, sl, tp, orderComment);

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
   RegisterTodayOpening();
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
      SaveVirtualPositionState();
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
      g_virtualPosition.active = false;
      SaveVirtualPositionState();
     }
   else
      if(hitSl)
        {
         PrintFormat("[PAPER_TRADING] SL raggiunto - Chiusura %s ticket virtuale=%I64u a prezzo=%.5f",
                     g_virtualPosition.direction, g_virtualPosition.ticket, currentPrice);
         g_virtualPosition.active = false;
         SaveVirtualPositionState();
        }
  }

//+------------------------------------------------------------------+
//| Gestisce un segnale rilevato: reversal se posizione contraria     |
//| esistente (ANCHE fuori dalla finestra oraria), altrimenti nuova   |
//| apertura solo dentro la sessione 15:30:00-17:29:59 ORA ITALIANA.  |
//+------------------------------------------------------------------+
void HandleSignal(const SignalResult &sig)
  {
   if(sig.direction == "")
      return;

   // La finestra oraria si riferisce all'orario di CHIUSURA della candela
   // M15 del segnale (MqlRates.time e' l'orario di APERTURA): la candela
   // 15:15-15:30 chiude alle 15:30 e puo' quindi aprire alle 15:30.
   datetime candleCloseServer = sig.candleTime + PeriodSeconds(PERIOD_M15);

   PrintFormat("WT1 = %.4f", sig.wt1v);
   PrintFormat("WT2 = %.4f", sig.wt2v);
   PrintFormat("Segnale %s | candela M15 Italia %s -> %s", sig.direction,
               TimeOrNA(ConvertServerTimeToItaly(sig.candleTime), TIME_DATE | TIME_MINUTES),
               TimeOrNA(ConvertServerTimeToItaly(candleCloseServer), TIME_MINUTES));

   BotPosition pos = GetCurrentPosition();

   if(pos.exists)
     {
      if(pos.direction == sig.direction)
        {
         PrintFormat("Posizione %s gia' aperta. Nessuna nuova entrata sullo stesso incrocio.", pos.direction);
         return;
        }

      // Incrocio contrario -> chiudi la posizione aperta (sempre, anche
      // fuori finestra) e prova ad aprire quella opposta (soggetta a
      // finestra oraria e limite giornaliero, vedi OpenNewPosition).
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

      // La chiusura qui sopra avviene sempre. La RIAPERTURA in direzione
      // opposta e' una nuova operazione: OpenNewPosition verifica finestra
      // oraria (se InpReversalRespectsWindow=true) e limite giornaliero.
      bool reopened = OpenNewPosition(sig.direction, "Reversal open", candleCloseServer, InpReversalRespectsWindow);
      if(!reopened)
         Print("Reversal: posizione precedente chiusa, nuova posizione NON aperta. Il bot resta FLAT.");
      return;
     }

   // Nessuna posizione del bot aperta: apri una nuova entrata SOLO se la
   // candela del segnale chiude dentro la sessione italiana e l'ora
   // italiana attuale e' dentro la sessione (Europe/Rome, CET/CEST).
   if(!IsWithinItalianTradingWindow(candleCloseServer))
     {
      PrintFormat("Segnale %s ricevuto fuori dalla sessione %s (ora italiana) o con ora non verificabile. "
                  "Nessuna apertura.", sig.direction, WindowText());
      return;
     }

   PrintFormat("Apertura %s %.2f", sig.direction, InpLotSize);
   // Secondo controllo (HARD) dentro OpenNewPosition, sempre attivo per "New entry".
   OpenNewPosition(sig.direction, "New entry", candleCloseServer, true);
  }

//+------------------------------------------------------------------+
//| Ciclo principale: scarica le candele, calcola il WaveTrend,       |
//| rileva una nuova candela M15 chiusa ed eventualmente processa un  |
//| segnale. Idempotente: se richiamato piu' volte sulla stessa       |
//| candela non genera doppie esecuzioni (guardia g_lastProcessedTime)|
//+------------------------------------------------------------------+
void ProcessCycle()
  {
   CheckClockStateChange();

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
      PrintFormat("Nuova candela M15 chiusa: %s -> %s (server)", TimeToString(closedTime, TIME_DATE | TIME_MINUTES),
                  TimeToString(closedTime + PeriodSeconds(PERIOD_M15), TIME_MINUTES));
      LogItalyClock("NUOVA CANDELA M15");
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

   // Ripristina l'eventuale posizione virtuale salvata prima del riavvio,
   // cosi' una reinizializzazione non la "dimentica".
   if(InpPaperTrading)
      LoadVirtualPositionState();

   LogStartupDiagnostics();
   CheckClockStateChange();

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

   PrintFormat("BOT AVVIATO - %s", BOT_NAME);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   string reasonText = "SCONOSCIUTO";
   switch(reason)
     {
      case REASON_PROGRAM:     reasonText = "PROGRAM (ExpertRemove)";                    break;
      case REASON_REMOVE:      reasonText = "REMOVE (EA rimosso dal grafico)";           break;
      case REASON_RECOMPILE:   reasonText = "RECOMPILE (ricompilato in MetaEditor)";     break;
      case REASON_CHARTCHANGE: reasonText = "CHARTCHANGE (cambio simbolo/timeframe)";    break;
      case REASON_CHARTCLOSE:  reasonText = "CHARTCLOSE (grafico chiuso)";               break;
      case REASON_PARAMETERS:  reasonText = "PARAMETERS (parametri modificati)";         break;
      case REASON_ACCOUNT:     reasonText = "ACCOUNT (cambio conto/riconnessione)";      break;
      case REASON_TEMPLATE:    reasonText = "TEMPLATE (template applicato)";             break;
      case REASON_INITFAILED:  reasonText = "INITFAILED (OnInit fallito)";               break;
      case REASON_CLOSE:       reasonText = "CLOSE (terminale chiuso)";                  break;
     }
   PrintFormat("BOT ARRESTATO (reason=%d -> %s)", reason, reasonText);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//| Mantiene la simulazione SL/TP del paper trading reattiva ad ogni  |
//| tick; la rilevazione di nuove candele e la logica di segnale      |
//| restano nel polling temporizzato (OnTimer), come nel bot Python.  |
//+------------------------------------------------------------------+
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
