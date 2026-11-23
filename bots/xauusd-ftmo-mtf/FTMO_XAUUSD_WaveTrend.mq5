//+------------------------------------------------------------------+
//| FTMO_XAUUSD_WaveTrend.mq5                                       |
//| EA MQL5 - FTMO Challenge / XAUUSD / Wave Trend + MTF            |
//| Basato sulle specifiche del PROMPT FINALE v2                    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "XAUUSD Wave Trend EA for MT5 / FTMO Challenge"
#property description "Native WT fallback + M30/H1/H4 confirmation"
#property description "TP/SL calculated from monetary targets"

#include <Trade/Trade.mqh>

CTrade trade;

//--- Symbol / execution
input string InpSymbol              = "XAUUSD";
input double InpLotSize             = 0.10;
input ulong  InpMagicNumber         = 26081301;

//--- Entry timeframe
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M15;

//--- Wave Trend
input string InpCustomWTName        = "WT_LB";
input int    InpWT_Channel          = 10;
input int    InpWT_Average          = 21;
input int    InpWT_MA               = 4;

//--- MTF confirmation
input bool   InpUseMTFConfirmation  = true;
input bool   InpConfirmM30          = true;
input bool   InpConfirmH1           = true;
input bool   InpConfirmH4           = true;

//--- Italian trading window
input int    InpStartHourItaly      = 15;
input int    InpStartMinuteItaly    = 30;
input int    InpEndHourItaly        = 17;
input int    InpEndMinuteItaly      = 30;

//--- Monetary TP / SL, in account deposit currency
input double InpTP_Money            = 100.0;
input double InpSL_Money            = 100.0;

//--- FTMO internal safety thresholds
input double InpMaxDailyLossPct     = 4.0;
input double InpMaxOverallLossPct   = 8.0;

//--- Globals
string   g_symbol = "";
datetime g_lastEntryBar = 0;
datetime g_lastRiskLogBar = 0;
int      g_serverDayKey = -1;
double   g_dayStartEquity = 0.0;
double   g_initialBalance = 0.0;
bool     g_overallKill = false;
bool     g_dailyKill = false;
string   g_balanceGV = "";
string   g_dayEquityGV = "";

//+------------------------------------------------------------------+
//| Utility                                                           |
//+------------------------------------------------------------------+
string TfToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      default:         return EnumToString(tf);
   }
}

int DigitsForSymbol()
{
   return (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, DigitsForSymbol());
}

bool IsTradeModeAllowed()
{
   long mode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   return (mode != SYMBOL_TRADE_MODE_DISABLED &&
           mode != SYMBOL_TRADE_MODE_CLOSEONLY);
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);

      if(sym == g_symbol && magic == InpMagicNumber)
         return true;
   }
   return false;
}

int ServerDayKey(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

datetime DayStartServer(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

bool IsLeapYear(int year)
{
   return ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0));
}

int DaysInMonth(int year, int month)
{
   if(month == 2) return IsLeapYear(year) ? 29 : 28;
   if(month == 4 || month == 6 || month == 9 || month == 11) return 30;
   return 31;
}

// Last Sunday of a month at 01:00 UTC, as required for EU DST.
datetime LastSundayUTC(int year, int month)
{
   MqlDateTime dt;
   dt.year = year;
   dt.mon  = month;
   dt.day  = DaysInMonth(year, month);
   dt.hour = 1;
   dt.min  = 0;
   dt.sec  = 0;

   datetime d = StructToTime(dt);
   MqlDateTime cur;
   TimeToStruct(d, cur);

   // MQL5 day_of_week: 0=Sunday
   d -= cur.day_of_week * 86400;
   return d;
}

bool ItalyDST(datetime gmt)
{
   MqlDateTime dt;
   TimeToStruct(gmt, dt);

   datetime start = LastSundayUTC(dt.year, 3);
   datetime stop  = LastSundayUTC(dt.year, 10);

   return (gmt >= start && gmt < stop);
}

datetime ServerToItaly(datetime serverTime)
{
   // Dynamic server -> GMT offset; never hardcoded.
   datetime nowServer = TimeCurrent();
   datetime nowGMT    = TimeGMT();
   int serverGMTOffset = (int)(nowServer - nowGMT);

   datetime gmt = serverTime - serverGMTOffset;
   int italyOffset = ItalyDST(gmt) ? 2*3600 : 1*3600;

   return gmt + italyOffset;
}

bool IsInsideItalianWindow(datetime serverTime)
{
   datetime italy = ServerToItaly(serverTime);
   MqlDateTime dt;
   TimeToStruct(italy, dt);

   int nowMin = dt.hour * 60 + dt.min;
   int startMin = InpStartHourItaly * 60 + InpStartMinuteItaly;
   int endMin   = InpEndHourItaly * 60 + InpEndMinuteItaly;

   return (nowMin >= startMin && nowMin <= endMin);
}

//+------------------------------------------------------------------+
//| Wave Trend native implementation                                 |
//+------------------------------------------------------------------+
double EMAAt(const double &src[], int count, int period, int index)
{
   if(count <= 0 || period <= 0 || index < 0 || index >= count)
      return EMPTY_VALUE;

   double alpha = 2.0 / (period + 1.0);
   double ema = src[0];

   for(int i=1; i<=index; ++i)
      ema = alpha * src[i] + (1.0-alpha) * ema;

   return ema;
}

bool CalculateNativeWT(ENUM_TIMEFRAMES tf, int shift,
                       double &wt1, double &wt2)
{
   wt1 = EMPTY_VALUE;
   wt2 = EMPTY_VALUE;

   int barsNeeded = MathMax(InpWT_Channel, InpWT_Average);
   barsNeeded = MathMax(barsNeeded, InpWT_MA) + 80;

   MqlRates rates[];
   int copied = CopyRates(g_symbol, tf, 0, barsNeeded, rates);
   if(copied < 40)
      return false;

   // CopyRates returns oldest -> newest in a normal dynamic array.
   double ap[], esa[], absdev[], de[], ci[], tci[], w2[];
   ArrayResize(ap, copied);
   ArrayResize(esa, copied);
   ArrayResize(absdev, copied);
   ArrayResize(de, copied);
   ArrayResize(ci, copied);
   ArrayResize(tci, copied);
   ArrayResize(w2, copied);

   for(int i=0; i<copied; ++i)
      ap[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0;

   double aChan = 2.0 / (InpWT_Channel + 1.0);
   double aAvg  = 2.0 / (InpWT_Average + 1.0);

   esa[0] = ap[0];
   absdev[0] = 0.0;
   de[0] = 0.0;
   ci[0] = 0.0;
   tci[0] = 0.0;

   for(int i=1; i<copied; ++i)
   {
      esa[i] = aChan * ap[i] + (1.0-aChan) * esa[i-1];
      absdev[i] = MathAbs(ap[i] - esa[i]);
      de[i] = aChan * absdev[i] + (1.0-aChan) * de[i-1];

      if(de[i] > 0.0)
         ci[i] = (ap[i] - esa[i]) / (0.015 * de[i]);
      else
         ci[i] = 0.0;

      tci[i] = aAvg * ci[i] + (1.0-aAvg) * tci[i-1];
   }

   // WT2 = SMA(WT1, InpWT_MA)
   for(int i=0; i<copied; ++i)
   {
      if(i + 1 < InpWT_MA)
      {
         w2[i] = EMPTY_VALUE;
         continue;
      }

      double sum = 0.0;
      for(int j=0; j<InpWT_MA; ++j)
         sum += tci[i-j];

      w2[i] = sum / InpWT_MA;
   }

   int target = copied - 1 - shift;
   if(target < InpWT_MA || target < 2)
      return false;

   wt1 = tci[target];
   wt2 = w2[target];

   return (wt1 != EMPTY_VALUE && wt2 != EMPTY_VALUE);
}

bool GetWTCustom(ENUM_TIMEFRAMES tf, int shift,
                 double &wt1, double &wt2)
{
   wt1 = EMPTY_VALUE;
   wt2 = EMPTY_VALUE;

   if(InpCustomWTName == "")
      return false;

   ResetLastError();
   int handle = iCustom(g_symbol, tf, InpCustomWTName);
   if(handle == INVALID_HANDLE)
      return false;

   double b1[1], b2[1];
   bool ok1 = (CopyBuffer(handle, 0, shift, 1, b1) == 1);
   bool ok2 = (CopyBuffer(handle, 1, shift, 1, b2) == 1);

   IndicatorRelease(handle);

   if(!ok1 || !ok2)
      return false;

   if(!MathIsValidNumber(b1[0]) || !MathIsValidNumber(b2[0]))
      return false;

   wt1 = b1[0];
   wt2 = b2[0];
   return true;
}

bool GetWT(ENUM_TIMEFRAMES tf, int shift,
           double &wt1, double &wt2, bool &usedCustom)
{
   usedCustom = false;

   if(GetWTCustom(tf, shift, wt1, wt2))
   {
      usedCustom = true;
      return true;
   }

   return CalculateNativeWT(tf, shift, wt1, wt2);
}

bool GetWTClosedPair(ENUM_TIMEFRAMES tf,
                     double &wt1Last, double &wt2Last,
                     double &wt1Prev, double &wt2Prev,
                     bool &usedCustom)
{
   bool c1=false, c2=false;

   if(!GetWT(tf, 1, wt1Last, wt2Last, c1))
      return false;
   if(!GetWT(tf, 2, wt1Prev, wt2Prev, c2))
      return false;

   usedCustom = (c1 && c2);
   return true;
}

//+------------------------------------------------------------------+
//| MTF confirmation                                                  |
//+------------------------------------------------------------------+
bool ConfirmTF(ENUM_TIMEFRAMES tf, bool isLong, string &details)
{
   double w1, w2, p1, p2;
   bool custom = false;

   if(!GetWTClosedPair(tf, w1, w2, p1, p2, custom))
   {
      details = TfToString(tf) + ": WT unavailable";
      return false;
   }

   bool aligned = isLong ? (w1 > w2) : (w1 < w2);

   details = StringFormat("%s WT1=%.5f WT2=%.5f bias=%s source=%s",
                          TfToString(tf), w1, w2,
                          aligned ? "OK" : "NO",
                          custom ? "iCustom" : "native");
   return aligned;
}

bool ConfirmAllMTF(bool isLong)
{
   if(!InpUseMTFConfirmation)
      return true;

   string d;

   if(InpConfirmM30)
   {
      bool ok = ConfirmTF(PERIOD_M30, isLong, d);
      Print("[MTF] ", d);
      if(!ok) return false;
   }

   if(InpConfirmH1)
   {
      bool ok = ConfirmTF(PERIOD_H1, isLong, d);
      Print("[MTF] ", d);
      if(!ok) return false;
   }

   if(InpConfirmH4)
   {
      bool ok = ConfirmTF(PERIOD_H4, isLong, d);
      Print("[MTF] ", d);
      if(!ok) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Risk management                                                   |
//+------------------------------------------------------------------+
void InitRiskState()
{
   datetime now = TimeCurrent();
   g_serverDayKey = ServerDayKey(now);
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_dayStartEquity <= 0.0)
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_BALANCE);

   if(g_dayEquityGV != "")
      GlobalVariableSet(g_dayEquityGV, g_dayStartEquity);

   if(g_balanceGV != "")
   {
      if(GlobalVariableCheck(g_balanceGV))
         g_initialBalance = GlobalVariableGet(g_balanceGV);
      else
      {
         g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         GlobalVariableSet(g_balanceGV, g_initialBalance);
      }
   }
   else
      g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   g_dailyKill = false;
   g_overallKill = false;
}

void UpdateDailyReferenceIfNeeded()
{
   int today = ServerDayKey(TimeCurrent());

   if(today != g_serverDayKey)
   {
      g_serverDayKey = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(g_dayStartEquity <= 0.0)
         g_dayStartEquity = AccountInfoDouble(ACCOUNT_BALANCE);

      g_dailyKill = false;

      if(g_dayEquityGV != "")
         GlobalVariableSet(g_dayEquityGV, g_dayStartEquity);

      PrintFormat("[RISK] Nuovo giorno server. Equity iniziale = %.2f",
                  g_dayStartEquity);
   }
}

bool RiskAllowsNewEntry()
{
   UpdateDailyReferenceIfNeeded();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = MathMax(0.0, g_dayStartEquity - equity);
   double overallLoss = MathMax(0.0, g_initialBalance - equity);

   double dailyLimit = g_dayStartEquity * InpMaxDailyLossPct / 100.0;
   double overallLimit = g_initialBalance * InpMaxOverallLossPct / 100.0;

   if(dailyLimit > 0.0 && dailyLoss >= dailyLimit)
   {
      if(!g_dailyKill)
      {
         PrintFormat("[RISK KILL] Daily loss %.2f >= %.2f (%.2f%%)",
                     dailyLoss, dailyLimit, InpMaxDailyLossPct);
      }
      g_dailyKill = true;
   }

   if(overallLimit > 0.0 && overallLoss >= overallLimit)
   {
      if(!g_overallKill)
      {
         PrintFormat("[RISK KILL] Overall loss %.2f >= %.2f (%.2f%%)",
                     overallLoss, overallLimit, InpMaxOverallLossPct);
      }
      g_overallKill = true;
   }

   if(TimeCurrent() != g_lastRiskLogBar)
   {
      datetime bar = iTime(g_symbol, InpEntryTF, 0);
      if(bar != g_lastRiskLogBar)
      {
         g_lastRiskLogBar = bar;
         double dailyPct = (g_dayStartEquity > 0.0)
                           ? 100.0 * dailyLoss / g_dayStartEquity : 0.0;
         double overallPct = (g_initialBalance > 0.0)
                             ? 100.0 * overallLoss / g_initialBalance : 0.0;

         PrintFormat("[RISK] Equity=%.2f DailyDD=%.2f (%.2f%%/%.2f%%) OverallDD=%.2f (%.2f%%/%.2f%%)",
                     equity,
                     dailyLoss, dailyPct, InpMaxDailyLossPct,
                     overallLoss, overallPct, InpMaxOverallLossPct);
      }
   }

   return (!g_dailyKill && !g_overallKill);
}

//+------------------------------------------------------------------+
//| Monetary TP/SL                                                    |
//+------------------------------------------------------------------+
bool MoneyToPriceDistance(double money, double lots, double &distance)
{
   distance = 0.0;

   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);

   if(money <= 0.0 || lots <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0)
      return false;

   // distance = (money / (tick_value * lots)) * tick_size
   distance = (money / (tickValue * lots)) * tickSize;
   return (distance > 0.0 && MathIsValidNumber(distance));
}

double MinimumStopDistance()
{
   long stopsLevel = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(point <= 0.0) return 0.0;
   return (double)stopsLevel * point;
}

void BuildStops(bool isLong, double entry, double &sl, double &tp)
{
   double slDist=0.0, tpDist=0.0;

   MoneyToPriceDistance(InpSL_Money, InpLotSize, slDist);
   MoneyToPriceDistance(InpTP_Money, InpLotSize, tpDist);

   double minDist = MinimumStopDistance();

   if(slDist < minDist)
   {
      PrintFormat("[STOPS] SL distance %.5f < broker minimum %.5f; extending.",
                  slDist, minDist);
      slDist = minDist;
   }

   if(tpDist < minDist)
   {
      PrintFormat("[STOPS] TP distance %.5f < broker minimum %.5f; extending.",
                  tpDist, minDist);
      tpDist = minDist;
   }

   if(isLong)
   {
      sl = NormalizePrice(entry - slDist);
      tp = NormalizePrice(entry + tpDist);
   }
   else
   {
      sl = NormalizePrice(entry + slDist);
      tp = NormalizePrice(entry - tpDist);
   }
}

//+------------------------------------------------------------------+
//| Signal                                                            |
//+------------------------------------------------------------------+
bool GetEntrySignal(bool &isLong, double &wt1, double &wt2)
{
   isLong = false;
   wt1 = wt2 = 0.0;

   double prevWT1, prevWT2;
   bool custom=false;

   if(!GetWTClosedPair(InpEntryTF, wt1, wt2, prevWT1, prevWT2, custom))
      return false;

   bool longSignal  = (prevWT1 <= prevWT2 && wt1 > wt2);
   bool shortSignal = (prevWT1 >= prevWT2 && wt1 < wt2);

   if(longSignal)
   {
      isLong = true;
      PrintFormat("[SIGNAL] LONG %s WT1=%.5f WT2=%.5f prevWT1=%.5f prevWT2=%.5f source=%s",
                  TfToString(InpEntryTF), wt1, wt2, prevWT1, prevWT2,
                  custom ? "iCustom" : "native");
      return true;
   }

   if(shortSignal)
   {
      isLong = false;
      PrintFormat("[SIGNAL] SHORT %s WT1=%.5f WT2=%.5f prevWT1=%.5f prevWT2=%.5f source=%s",
                  TfToString(InpEntryTF), wt1, wt2, prevWT1, prevWT2,
                  custom ? "iCustom" : "native");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Order opening                                                     |
//+------------------------------------------------------------------+
bool OpenTrade(bool isLong, double wt1, double wt2)
{
   if(!IsTradeModeAllowed())
   {
      Print("[ORDER] Mercato non tradabile per il simbolo.");
      return false;
   }

   if(HasOpenPosition())
   {
      Print("[ORDER] Esiste già una posizione per simbolo + magic.");
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double price = isLong ? SymbolInfoDouble(g_symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(g_symbol, SYMBOL_BID);

   if(price <= 0.0)
      return false;

   ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double margin = 0.0;
   if(!OrderCalcMargin(orderType, g_symbol, InpLotSize, price, margin))
   {
      PrintFormat("[ORDER] OrderCalcMargin fallito. err=%d", GetLastError());
      return false;
   }

   if(margin > freeMargin)
   {
      PrintFormat("[ORDER] Margine insufficiente. Required=%.2f Free=%.2f",
                  margin, freeMargin);
      return false;
   }

   double sl=0.0, tp=0.0;
   BuildStops(isLong, price, sl, tp);

   double slDist = MathAbs(price - sl);
   double tpDist = MathAbs(tp - price);

   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);

   PrintFormat("[ORDER] %s entry=%.5f SL=%.5f (dist %.5f) TP=%.5f (dist %.5f) WT1=%.5f WT2=%.5f tickValue=%.8f tickSize=%.8f",
               isLong ? "BUY" : "SELL", price, sl, slDist, tp, tpDist,
               wt1, wt2, tickValue, tickSize);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(g_symbol);
   trade.SetDeviationInPoints(50);

   bool ok;
   if(isLong)
      ok = trade.Buy(InpLotSize, g_symbol, 0.0, sl, tp, "WT MTF LONG");
   else
      ok = trade.Sell(InpLotSize, g_symbol, 0.0, sl, tp, "WT MTF SHORT");

   if(!ok)
   {
      PrintFormat("[ORDER ERROR] %s retcode=%u description=%s",
                  isLong ? "BUY" : "SELL",
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
      return false;
   }

   PrintFormat("[ORDER OK] %s ticket=%I64u price=%.5f SL=%.5f TP=%.5f",
               isLong ? "BUY" : "SELL",
               trade.ResultOrder(), price, sl, tp);

   return true;
}

//+------------------------------------------------------------------+
//| Logging / initialization                                          |
//+------------------------------------------------------------------+
void CheckTFWarnings()
{
   if(!InpUseMTFConfirmation)
      return;

   ENUM_TIMEFRAMES tf = InpEntryTF;

   if(InpConfirmM30 && PeriodSeconds(tf) >= PeriodSeconds(PERIOD_M30))
      Print("[MTF WARNING] M30 confirmation coincides with or is below/equal to entry TF; it may add no real filter.");

   if(InpConfirmH1 && PeriodSeconds(tf) >= PeriodSeconds(PERIOD_H1))
      Print("[MTF WARNING] H1 confirmation coincides with or is below/equal to entry TF; it may add no real filter.");

   if(InpConfirmH4 && PeriodSeconds(tf) >= PeriodSeconds(PERIOD_H4))
      Print("[MTF WARNING] H4 confirmation coincides with or is below/equal to entry TF; it may add no real filter.");
}

void PrintStartupInfo()
{
   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   string company  = AccountInfoString(ACCOUNT_COMPANY);

   Print("==============================================================");
   Print("FTMO XAUUSD WaveTrend EA - START");
   PrintFormat("Company: %s", company);
   PrintFormat("Account currency: %s", currency);
   PrintFormat("Symbol: %s | Entry TF: %s | Lots: %.2f | Magic: %I64u",
               g_symbol, TfToString(InpEntryTF), InpLotSize, InpMagicNumber);
   PrintFormat("WT parameters: Channel=%d Average=%d MA=%d",
               InpWT_Channel, InpWT_Average, InpWT_MA);
   PrintFormat("Custom WT: %s (fallback native if unavailable)", InpCustomWTName);
   PrintFormat("TP money=%.2f | SL money=%.2f | TickValue=%.8f | TickSize=%.8f",
               InpTP_Money, InpSL_Money, tickValue, tickSize);
   PrintFormat("Italy window: %02d:%02d - %02d:%02d",
               InpStartHourItaly, InpStartMinuteItaly,
               InpEndHourItaly, InpEndMinuteItaly);
   PrintFormat("Safety limits: Daily %.2f%% | Overall %.2f%%",
               InpMaxDailyLossPct, InpMaxOverallLossPct);

   string companyLower = company;
   StringToLower(companyLower);
   string currencyUpper = currency;
   StringToUpper(currencyUpper);

   if(StringFind(companyLower, "ftmo") < 0)
      PrintFormat("[WARNING] Account company '%s' does not contain 'ftmo'. EA will NOT be blocked.", company);

   if(currencyUpper != "EUR")
      PrintFormat("[WARNING] Account currency is %s, not EUR. Monetary TP/SL inputs are interpreted in DEPOSIT currency.", currency);

   Print("==============================================================");
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = InpSymbol;

   if(!SymbolSelect(g_symbol, true))
   {
      PrintFormat("[INIT ERROR] Cannot select symbol %s. Error=%d",
                  g_symbol, GetLastError());
      return INIT_FAILED;
   }

   if(InpLotSize <= 0.0)
   {
      Print("[INIT ERROR] Lot size must be > 0.");
      return INIT_FAILED;
   }

   if(InpWT_Channel <= 0 || InpWT_Average <= 0 || InpWT_MA <= 0)
   {
      Print("[INIT ERROR] Wave Trend periods must be > 0.");
      return INIT_FAILED;
   }

   g_balanceGV = StringFormat("FTMO_WT_INITIAL_BALANCE_%I64d_%I64u",
                              AccountInfoInteger(ACCOUNT_LOGIN),
                              InpMagicNumber);

   g_dayEquityGV = StringFormat("FTMO_WT_DAY_EQUITY_%I64d_%I64u",
                                AccountInfoInteger(ACCOUNT_LOGIN),
                                InpMagicNumber);

   InitRiskState();
   PrintStartupInfo();
   CheckTFWarnings();

   g_lastEntryBar = iTime(g_symbol, InpEntryTF, 0);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDailyReferenceIfNeeded();

   // Existing positions are managed natively by broker TP/SL.
   // No new entries outside the Italian trading window.
   if(!IsInsideItalianWindow(TimeCurrent()))
      return;

   if(!RiskAllowsNewEntry())
      return;

   if(HasOpenPosition())
      return;

   datetime currentBar = iTime(g_symbol, InpEntryTF, 0);
   if(currentBar <= 0)
      return;

   // Evaluate once per new entry-timeframe bar.
   if(currentBar == g_lastEntryBar)
      return;

   g_lastEntryBar = currentBar;

   bool isLong;
   double wt1, wt2;

   if(!GetEntrySignal(isLong, wt1, wt2))
      return;

   if(!ConfirmAllMTF(isLong))
   {
      PrintFormat("[SIGNAL REJECTED] MTF confirmation failed for %s.",
                  isLong ? "LONG" : "SHORT");
      return;
   }

   PrintFormat("[SIGNAL ACCEPTED] %s - all enabled MTF confirmations aligned.",
               isLong ? "LONG" : "SHORT");

   OpenTrade(isLong, wt1, wt2);
}

//+------------------------------------------------------------------+
//| Trade transaction logging                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   ulong magic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

   if(symbol != g_symbol || magic != InpMagicNumber)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      PrintFormat("[CLOSE] symbol=%s price=%.5f profit=%.2f reason=%s deal=%I64u",
                  symbol, price, profit,
                  EnumToString((ENUM_DEAL_REASON)reason),
                  trans.deal);
   }
   else if(entry == DEAL_ENTRY_IN)
   {
      PrintFormat("[OPEN DEAL] symbol=%s price=%.5f deal=%I64u",
                  symbol, price, trans.deal);
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("FTMO XAUUSD WaveTrend EA stopped. reason=%d", reason);
}
//+------------------------------------------------------------------+
