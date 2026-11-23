//+------------------------------------------------------------------+
//|                                              86botERCOLE.mq5     |
//|  Porting MQL5 della strategia Freqtrade "binance" (famiglia      |
//|  E0V1E) - user_data/strategies/e0v1e/binance.py                  |
//|                                                                  |
//|  Solo LONG, timeframe 5 minuti, 1 posizione per simbolo.         |
//|  Ingressi: "ewo" e "buy_1" (vedi README).                        |
//|  Uscite : stop dinamico (custom_stoploss) + "deadfish"           |
//|           (custom_exit). Nessun take profit (ROI 1000%) e        |
//|           stoploss fisso -99% come nell'originale.               |
//|                                                                  |
//|  Gli indicatori sono ricalcolati internamente con le STESSE      |
//|  formule di TA-Lib / pandas_ta / qtpylib usate da freqtrade      |
//|  (RSI di Wilder seed SMA, EMA seed SMA, Bollinger con dev. std.  |
//|  campionaria ddof=1, CTI = correlazione di Pearson col tempo).   |
//+------------------------------------------------------------------+
#property copyright "Porting E0V1E binance.py"
#property version   "1.10"
#property description "86botERCOLE - strategia E0V1E 'binance' (long only, M5). Size predefinita: 10% del saldo per trade."

#include <Trade\Trade.mqh>

//--- modalita' di dimensionamento della posizione
enum ENUM_STAKE_MODE
  {
   STAKE_FIXED_LOTS  = 0, // Lotti fissi
   STAKE_MONEY       = 1, // Controvalore fisso (valuta del conto)
   STAKE_PCT_BALANCE = 2, // Controvalore = % del saldo
   STAKE_RISK_PCT    = 3  // Rischio % dell'equity sulla distanza dello stop (richiede InpHardStopPct > 0)
  };

//--- sorgente del volume per la regola "deadfish"
enum ENUM_VOL_SOURCE
  {
   VOL_TICK = 0, // Tick volume (forex/CFD)
   VOL_REAL = 1  // Volume reale (se il broker lo fornisce)
  };

//=== Generale ========================================================
input group "=== Generale ==="
input ENUM_TIMEFRAMES InpTimeframe     = PERIOD_M5;  // Timeframe strategia (originale: 5m)
input long            InpMagic         = 20240501;   // Magic number
input int             InpBarsCalc      = 1000;       // Barre usate per gli indicatori (min 300)
input ENUM_VOL_SOURCE InpVolumeSource  = VOL_TICK;   // Volume per regola deadfish
input double          InpFeePct        = 0.0325;     // Fee % per lato SOLO per le soglie di profitto (non addebitata). FTMO=0.0325, Binance=0.10
input int             InpMaxSpreadPts  = 0;          // Spread massimo in punti per entrare (0 = nessun filtro)

//=== Money management ================================================
input group "=== Dimensione posizione ==="
input ENUM_STAKE_MODE InpStakeMode     = STAKE_PCT_BALANCE; // Modalita' dimensionamento
input double          InpLots          = 0.01;       // Lotti (se Lotti fissi)
input double          InpStakeMoney    = 1000.0;     // Controvalore (se Controvalore fisso)
input double          InpStakePct      = 10.0;       // % del saldo per trade (100.000 -> 10.000 di controvalore)
input double          InpRiskPct       = 0.25;       // Rischio % equity per trade (se Rischio %)
input double          InpMaxOpenRiskPct= 1.0;        // Rischio % complessivo aperto max (tutte le posizioni con questo magic)
input int             InpMaxOpenTrades = 10;         // Posizioni aperte max (tutti i simboli, questo magic)
input double          InpRiskFeePct    = 0.0325;     // Commissione % per lato inclusa nel calcolo del rischio (FTMO crypto)

//=== Ingresso "ewo" ==================================================
input group "=== Ingresso EWO ==="
input bool   InpUseEwo        = true;    // Abilita ingresso 'ewo'
input int    buy_rsi_fast     = 50;      // buy_rsi_fast  (RSI4 <)
input int    buy_rsi          = 30;      // buy_rsi       (RSI14 <)
input double buy_ewo          = -1.238;  // buy_ewo       (EWO >)
input double buy_ema_low      = 0.956;   // buy_ema_low   (close < EMA8 * x)
input double buy_ema_high     = 0.986;   // buy_ema_high  (close < EMA16 * x)

//=== Ingresso "buy_1" ================================================
input group "=== Ingresso BUY_1 ==="
input bool   InpUseBuy1       = true;    // Abilita ingresso 'buy_1'
input int    buy_rsi_fast_32  = 63;      // buy_rsi_fast_32 (RSI4 <)
input int    buy_rsi_32       = 16;      // buy_rsi_32      (RSI14 >)
input double buy_sma15_32     = 0.932;   // buy_sma15_32    (close < SMA15 * x)
input double buy_cti_32       = -0.8;    // buy_cti_32      (CTI20 <)

//=== Uscite ==========================================================
input group "=== Uscite ==="
input int    sell_fastx                  = 75;    // sell_fastx (FastK > x)
input double sell_deadfish_bb_width      = 0.05;  // sell_deadfish_bb_width
input double sell_deadfish_profit        = -0.05; // sell_deadfish_profit
input double sell_deadfish_bb_factor     = 1.0;   // sell_deadfish_bb_factor
input double sell_deadfish_volume_factor = 1.0;   // sell_deadfish_volume_factor
input double InpStoplossRatio            = -0.99; // stoploss (originale -0.99 = -99%)
input bool   InpReplicateTagQuirk        = true;  // Replica comportamento originale tag 'ewobuy_1'
input double InpHardStopPct              = 0.0;   // SL reale sul broker in % (0 = disattivo, come originale)

//=== Report ==========================================================
input group "=== Report CSV ==="
input bool   InpWriteCsv      = true;    // Scrivi CSV dei trade (cartella Common\Files)
input string InpCsvSep        = ",";     // Separatore CSV

//--- costanti tag
#define TAG_EWO   1
#define TAG_BUY1  2

//--- valori dell'ultima candela CHIUSA (equivalente di dataframe.iloc[-1])
struct SCandle
  {
   datetime time;
   double   close;
   double   fastk;
   double   bb_mid;
   double   bb_width;
   double   vol_mean_12;
   double   vol_mean_24;
   bool     valid;
  };

CTrade   g_trade;
SCandle  g_last;
datetime g_lastBarTime  = 0;
datetime g_lastExitBar  = 0;     // "Auto lock" di freqtrade: niente nuovo ingresso nella candela dell'uscita
string   g_csvName      = "";

//+------------------------------------------------------------------+
//| Indicatori (array cronologici: indice 0 = barra piu' vecchia)    |
//+------------------------------------------------------------------+
// EMA stile TA-Lib: seed = SMA dei primi 'period' valori
void CalcEMA(const double &src[], int n, int period, double &out[])
  {
   ArrayResize(out, n);
   ArrayInitialize(out, EMPTY_VALUE);
   if(n < period) return;
   double sum = 0.0;
   for(int i = 0; i < period; i++) sum += src[i];
   double prev = sum / period;
   out[period - 1] = prev;
   double k = 2.0 / (period + 1.0);
   for(int i = period; i < n; i++)
     {
      prev = (src[i] - prev) * k + prev;
      out[i] = prev;
     }
  }

// RSI stile TA-Lib (Wilder, seed = media semplice delle prime 'period' variazioni)
void CalcRSI(const double &src[], int n, int period, double &out[])
  {
   ArrayResize(out, n);
   ArrayInitialize(out, EMPTY_VALUE);
   if(n <= period) return;
   double g = 0.0, l = 0.0;
   for(int i = 1; i <= period; i++)
     {
      double d = src[i] - src[i - 1];
      if(d > 0) g += d; else l -= d;
     }
   g /= period;
   l /= period;
   out[period] = (g + l != 0.0) ? 100.0 * g / (g + l) : 0.0;
   for(int i = period + 1; i < n; i++)
     {
      double d  = src[i] - src[i - 1];
      double gu = (d > 0) ?  d : 0.0;
      double ld = (d < 0) ? -d : 0.0;
      g = (g * (period - 1) + gu) / period;
      l = (l * (period - 1) + ld) / period;
      out[i] = (g + l != 0.0) ? 100.0 * g / (g + l) : 0.0;
     }
  }

double SMAat(const double &src[], int i, int period)
  {
   double s = 0.0;
   for(int k = i - period + 1; k <= i; k++) s += src[k];
   return s / period;
  }

// CTI (pandas_ta) = coefficiente r della regressione lineare, x = 1..length
double CTIat(const double &src[], int i, int length)
  {
   double x_sum  = 0.5 * length * (length + 1);
   double x2_sum = x_sum * (2 * length + 1) / 3.0;
   double divisor = length * x2_sum - x_sum * x_sum;
   double y_sum = 0.0, xy_sum = 0.0, y2_sum = 0.0;
   int start = i - length + 1;
   for(int k = 0; k < length; k++)
     {
      double y = src[start + k];
      y_sum  += y;
      xy_sum += (k + 1) * y;
      y2_sum += y * y;
     }
   double rn = length * xy_sum - x_sum * y_sum;
   double rd2 = divisor * (length * y2_sum - y_sum * y_sum);
   double rd = (rd2 > 0.0) ? MathSqrt(rd2) : 0.0;
   if(rd == 0.0) rd = DBL_EPSILON;
   return rn / rd;
  }

// FastK di STOCHF(5,3,0,3,0) di TA-Lib
double FastKat(const double &h[], const double &l[], const double &c[], int i, int period)
  {
   double hh = h[i], ll = l[i];
   for(int k = i - period + 1; k <= i; k++)
     {
      if(h[k] > hh) hh = h[k];
      if(l[k] < ll) ll = l[k];
     }
   double diff = hh - ll;
   return (diff != 0.0) ? (c[i] - ll) / diff * 100.0 : 0.0;
  }

//+------------------------------------------------------------------+
//| Calcolo segnali sull'ultima candela chiusa                       |
//| ritorna maschera tag (TAG_EWO | TAG_BUY1), 0 = nessun ingresso   |
//+------------------------------------------------------------------+
int ComputeCandle()
  {
   g_last.valid = false;
   int need = (InpBarsCalc < 300) ? 300 : InpBarsCalc;
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int n = CopyRates(_Symbol, InpTimeframe, 1, need, rates);   // dalla barra 1 (ultima chiusa)
   if(n < 260)
     {
      PrintFormat("Storico insufficiente: %d barre (servono almeno 260)", n);
      return 0;
     }

   double o[], h[], l[], c[], v[], tp[];
   ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n);
   ArrayResize(c, n); ArrayResize(v, n); ArrayResize(tp, n);
   for(int i = 0; i < n; i++)
     {
      o[i] = rates[i].open;  h[i] = rates[i].high;
      l[i] = rates[i].low;   c[i] = rates[i].close;
      v[i] = (InpVolumeSource == VOL_REAL) ? (double)rates[i].real_volume : (double)rates[i].tick_volume;
      tp[i] = (h[i] + l[i] + c[i]) / 3.0;
     }

   double ema8[], ema16[], ema50[], ema200[], rsi[], rsi4[], rsi20[];
   CalcEMA(c, n, 8, ema8);
   CalcEMA(c, n, 16, ema16);
   CalcEMA(c, n, 50, ema50);
   CalcEMA(c, n, 200, ema200);
   CalcRSI(c, n, 14, rsi);
   CalcRSI(c, n, 4, rsi4);
   CalcRSI(c, n, 20, rsi20);

   int i = n - 1;                      // ultima candela chiusa
   double sma15 = SMAat(c, i, 15);
   double cti   = CTIat(c, i, 20);
   double ewo   = (ema50[i] - ema200[i]) / l[i] * 100.0;
   double fastk = FastKat(h, l, c, i, 5);

   // Bollinger 20,2 su typical price, dev. std. campionaria (ddof=1) come qtpylib
   double mid = SMAat(tp, i, 20);
   double ss = 0.0;
   for(int k = i - 19; k <= i; k++) ss += (tp[k] - mid) * (tp[k] - mid);
   double sd = MathSqrt(ss / 19.0);
   double upper = mid + 2.0 * sd, lower = mid - 2.0 * sd;

   // medie volume rolling(12/24).mean().shift(1) -> escludono la candela corrente
   double vm12 = 0.0, vm24 = 0.0;
   for(int k = i - 12; k <= i - 1; k++) vm12 += v[k];
   for(int k = i - 24; k <= i - 1; k++) vm24 += v[k];
   vm12 /= 12.0; vm24 /= 24.0;

   g_last.time        = rates[i].time;
   g_last.close       = c[i];
   g_last.fastk       = fastk;
   g_last.bb_mid      = mid;
   g_last.bb_width    = (upper - lower) / mid;
   g_last.vol_mean_12 = vm12;
   g_last.vol_mean_24 = vm24;
   g_last.valid       = true;

   int tags = 0;
   bool is_ewo = (rsi4[i] < buy_rsi_fast) &&
                 (c[i] < ema8[i] * buy_ema_low) &&
                 (ewo > buy_ewo) &&
                 (c[i] < ema16[i] * buy_ema_high) &&
                 (rsi[i] < buy_rsi);
   bool is_b1 = (rsi20[i] < rsi20[i - 1]) &&
                (rsi4[i] < buy_rsi_fast_32) &&
                (rsi[i] > buy_rsi_32) &&
                (c[i] < sma15 * buy_sma15_32) &&
                (cti < buy_cti_32);
   if(InpUseEwo  && is_ewo) tags |= TAG_EWO;
   if(InpUseBuy1 && is_b1)  tags |= TAG_BUY1;
   return tags;
  }

//+------------------------------------------------------------------+
//| Utility posizione                                                |
//+------------------------------------------------------------------+
bool SelectMyPosition(ulong &ticket)
  {
   for(int k = PositionsTotal() - 1; k >= 0; k--)
     {
      ulong t = PositionGetTicket(k);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         ticket = t;
         return true;
        }
     }
   return false;
  }

string GVStop(ulong t) { return StringFormat("E0V1E_%I64d_stop_%I64u", InpMagic, t); }
string GVTag(ulong t)  { return StringFormat("E0V1E_%I64d_tag_%I64u",  InpMagic, t); }

string TagToString(int tags)
  {
   // freqtrade concatena i tag senza spazio: 'ewo' + 'buy_1' = 'ewobuy_1'
   string s = "";
   if((tags & TAG_EWO)  != 0) s += "ewo";
   if((tags & TAG_BUY1) != 0) s += "buy_1";
   return s;
  }

double NormalizeLots(double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = vmin;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) lots = 0.0;           // troppo piccolo: non apro
   if(lots > vmax) lots = vmax;
   return NormalizeDouble(lots, 8);
  }

// valore in valuta conto di una variazione di prezzo 'dist' per 1 lotto
double MoneyPerLot(string sym, double dist)
  {
   double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0) return 0.0;
   return dist * tv / ts;
  }

// rischio aperto (valuta conto) di tutte le posizioni con questo magic: distanza dallo SL reale + commissione di uscita
double OpenRiskMoney(int &count)
  {
   double risk = 0.0;
   count = 0;
   for(int k = PositionsTotal() - 1; k >= 0; k--)
     {
      ulong t = PositionGetTicket(k);
      if(t == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      count++;
      string sym = PositionGetString(POSITION_SYMBOL);
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl  = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0)            // senza SL il rischio e' l'intero controvalore
         risk += MoneyPerLot(sym, op) * vol;
      else if(sl < op)
         risk += MoneyPerLot(sym, op - sl) * vol + MoneyPerLot(sym, sl) * vol * InpRiskFeePct / 100.0;
     }
   return risk;
  }

double CalcLots(double price)
  {
   if(InpStakeMode == STAKE_FIXED_LOTS) return NormalizeLots(InpLots);
   if(InpStakeMode == STAKE_RISK_PCT)
     {
      if(InpHardStopPct <= 0)
        {
         Print("Rischio %: serve InpHardStopPct > 0 (distanza dello stop). Trade saltato.");
         return 0.0;
        }
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double budget = equity * InpRiskPct / 100.0;
      int n = 0;
      double free = equity * InpMaxOpenRiskPct / 100.0 - OpenRiskMoney(n);
      if(free < budget) budget = free;
      if(budget <= 0)
        {
         Print("Rischio complessivo aperto al limite: trade saltato.");
         return 0.0;
        }
      double slPrice = price * (1.0 - InpHardStopPct / 100.0);
      // perdita per lotto allo stop: distanza + commissioni d'ingresso e d'uscita
      double perLot = MoneyPerLot(_Symbol, price - slPrice) +
                      (MoneyPerLot(_Symbol, price) + MoneyPerLot(_Symbol, slPrice)) * InpRiskFeePct / 100.0;
      if(perLot <= 0) return 0.0;
      double lots = NormalizeLots(budget / perLot);   // arrotonda per difetto; 0 se sotto il lotto minimo
      if(lots <= 0)
         PrintFormat("Lotto minimo %.4f oltre il budget di rischio (%.2f): trade saltato.",
                     SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), budget);
      return lots;
     }
   double money = (InpStakeMode == STAKE_MONEY) ? InpStakeMoney
                  : AccountInfoDouble(ACCOUNT_BALANCE) * InpStakePct / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0 || price <= 0) return 0.0;
   double notionalPerLot = price * tickValue / tickSize;   // controvalore di 1 lotto in valuta conto
   return NormalizeLots(money / notionalPerLot);
  }

// profitto come freqtrade.calc_profit_ratio (long, commissioni incluse)
double ProfitRatio(double openRate, double rate)
  {
   double fee = InpFeePct / 100.0;
   double openVal  = openRate * (1.0 + fee);
   double closeVal = rate * (1.0 - fee);
   return closeVal / openVal - 1.0;
  }

//+------------------------------------------------------------------+
//| custom_stoploss dell'originale: ritorna lo stop relativo         |
//+------------------------------------------------------------------+
double CustomStoploss(long ageSec, double profit, int tags)
  {
   double fk = g_last.fastk;
   if(ageSec > 60 * 60)
      if(fk > sell_fastx && profit > -0.01) return -0.001;
   if(ageSec > 24 * 60 * 60)
      if(fk > sell_fastx && profit > -0.05) return -0.001;

   bool hasEwo;
   if(InpReplicateTagQuirk)
      hasEwo = (tags == TAG_EWO);           // originale: "ewo" in 'ewobuy_1'.split() -> False
   else
      hasEwo = ((tags & TAG_EWO) != 0);
   if(hasEwo && profit >= 0.05) return -0.005;

   if(profit > 0 && fk > sell_fastx) return -0.001;
   return InpStoplossRatio;
  }

bool IsDeadfish(double profit)
  {
   return (profit < sell_deadfish_profit) &&
          (g_last.bb_width < sell_deadfish_bb_width) &&
          (g_last.close > g_last.bb_mid * sell_deadfish_bb_factor) &&
          (g_last.vol_mean_12 < g_last.vol_mean_24 * sell_deadfish_volume_factor);
  }

double ReasonCode(string r)
  {
   if(r == "trailing_stop_loss")      return 1;
   if(r == "stop_loss")               return 2;
   if(r == "sell_stoploss_deadfish")  return 3;
   return 0;
  }

string ReasonName(double code)
  {
   int c = (int)code;
   if(c == 1) return "trailing_stop_loss";
   if(c == 2) return "stop_loss";
   if(c == 3) return "sell_stoploss_deadfish";
   return "";
  }

//+------------------------------------------------------------------+
//| Report CSV (ricostruito dallo storico deal)                      |
//+------------------------------------------------------------------+
void WriteCsv()
  {
   if(!HistorySelect(0, TimeCurrent() + 86400)) return;
   int h = FileOpen(g_csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("Impossibile scrivere %s (err %d)", g_csvName, GetLastError());
      return;
     }
   string s = InpCsvSep;
   FileWriteString(h, "position_id" + s + "symbol" + s + "open_time" + s + "open_price" + s + "close_time" + s +
                   "close_price" + s + "lots" + s + "profit_pct" + s + "profit_money" + s +
                   "commission" + s + "swap" + s + "net_money" + s + "duration_min" + s + "enter_tag" + s + "exit_reason\r\n");
   int total = HistoryDealsTotal();
   for(int k = 0; k < total; k++)
     {
      ulong d = HistoryDealGetTicket(k);
      if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      ulong pos = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      // cerca il deal di ingresso della stessa posizione
      double inPrice = 0, inComm = 0; datetime inTime = 0; string tag = "";
      for(int j = 0; j < total; j++)
        {
         ulong di = HistoryDealGetTicket(j);
         if((ulong)HistoryDealGetInteger(di, DEAL_POSITION_ID) == pos &&
            HistoryDealGetInteger(di, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            inPrice = HistoryDealGetDouble(di, DEAL_PRICE);
            inTime  = (datetime)HistoryDealGetInteger(di, DEAL_TIME);
            inComm  = HistoryDealGetDouble(di, DEAL_COMMISSION);
            tag     = HistoryDealGetString(di, DEAL_COMMENT);
            break;
           }
        }
      double outPrice = HistoryDealGetDouble(d, DEAL_PRICE);
      datetime outTime = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      double lots   = HistoryDealGetDouble(d, DEAL_VOLUME);
      double pm     = HistoryDealGetDouble(d, DEAL_PROFIT);
      double comm   = HistoryDealGetDouble(d, DEAL_COMMISSION) + inComm;
      double swp    = HistoryDealGetDouble(d, DEAL_SWAP);
      double pct    = (inPrice > 0) ? ProfitRatio(inPrice, outPrice) * 100.0 : 0.0;
      string gvr    = StringFormat("E0V1E_%I64d_reason_%I64u", InpMagic, pos);
      string reason = GlobalVariableCheck(gvr) ? ReasonName(GlobalVariableGet(gvr)) : "";
      if(reason == "")
        {
         long dr = HistoryDealGetInteger(d, DEAL_REASON);
         reason = (dr == DEAL_REASON_SL) ? "hard_stop" : (dr == DEAL_REASON_SO ? "stop_out" : "other");
        }
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      FileWriteString(h,
                      IntegerToString((long)pos) + s + _Symbol + s +
                      TimeToString(inTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS) + s + DoubleToString(inPrice, digits) + s +
                      TimeToString(outTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS) + s + DoubleToString(outPrice, digits) + s +
                      DoubleToString(lots, 4) + s + DoubleToString(pct, 3) + s + DoubleToString(pm, 2) + s +
                      DoubleToString(comm, 2) + s + DoubleToString(swp, 2) + s + DoubleToString(pm + comm + swp, 2) + s +
                      DoubleToString((outTime - inTime) / 60.0, 1) + s + tag + s + reason + "\r\n");
     }
   FileClose(h);
  }

void ClosePosition(ulong ticket, string reason)
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   // il commento dell'ordine di chiusura conserva la causa per il report
   if(g_trade.PositionClose(ticket, ULONG_MAX))
     {
      if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE || g_trade.ResultRetcode() == TRADE_RETCODE_PLACED)
        {
         GlobalVariableSet(StringFormat("E0V1E_%I64d_reason_%I64u", InpMagic, ticket), ReasonCode(reason));
         GlobalVariableDel(GVStop(ticket));
         GlobalVariableDel(GVTag(ticket));
         g_lastExitBar = iTime(_Symbol, InpTimeframe, 0);
         PrintFormat("CHIUSURA %s ticket=%I64u motivo=%s", _Symbol, ticket, reason);
         if(InpWriteCsv) WriteCsv();
        }
     }
   else
      PrintFormat("Errore chiusura ticket %I64u: %d %s", ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Gestione della posizione aperta (ad ogni tick)                   |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return;
   double openRate = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime openTm = (datetime)PositionGetInteger(POSITION_TIME);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0) return;

   // stop corrente (persistente: in freqtrade lo stop puo' solo salire)
   string gvs = GVStop(ticket);
   double initialStop = openRate * (1.0 + InpStoplossRatio);     // open * (1 - 0.99)
   if(!GlobalVariableCheck(gvs)) GlobalVariableSet(gvs, initialStop);
   double stop = GlobalVariableGet(gvs);

   int tags = 0;
   if(GlobalVariableCheck(GVTag(ticket))) tags = (int)GlobalVariableGet(GVTag(ticket));
   else
     {
      string cm = PositionGetString(POSITION_COMMENT);
      bool e = (StringFind(cm, "ewo") >= 0), b = (StringFind(cm, "buy_1") >= 0);
      tags = (e ? TAG_EWO : 0) | (b ? TAG_BUY1 : 0);
     }

   double profit = ProfitRatio(openRate, bid);
   long   ageSec = (long)(TimeCurrent() - openTm);

   // 1) aggiornamento stop (ft_stoploss_adjust) - solo se lo stop e' sotto il prezzo
   if(stop < bid && g_last.valid)
     {
      double sl = CustomStoploss(ageSec, profit, tags);
      double newStop = bid * (1.0 - MathAbs(sl));
      if(newStop > stop)
        {
         stop = newStop;
         GlobalVariableSet(gvs, stop);
        }
     }

   // 2) custom_exit "deadfish" (in freqtrade ha priorita' sullo stop trailing)
   if(g_last.valid && IsDeadfish(profit))
     {
      ClosePosition(ticket, "sell_stoploss_deadfish");
      return;
     }

   // 3) stop raggiunto
   if(stop >= bid)
     {
      bool trailing = (MathAbs(stop - initialStop) > _Point * 0.5);
      ClosePosition(ticket, trailing ? "trailing_stop_loss" : "stop_loss");
     }
  }

//+------------------------------------------------------------------+
//| Stampa nel log le specifiche del simbolo e verifica il volume    |
//+------------------------------------------------------------------+
void ReportSymbol()
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, InpTimeframe, 1, 2000, r);
   long realSum = 0, tickSum = 0;
   for(int i = 0; i < n; i++) { realSum += r[i].real_volume; tickSum += r[i].tick_volume; }
   PrintFormat("SIMBOLO %s | contratto=%.4f | lotto min=%.4f step=%.4f | tick size=%.10f tick value=%.6f | spread attuale=%d punti | swap long=%.4f short=%.4f (modo %d) | stops level=%d",
               _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
               SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG), SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_MODE), (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   PrintFormat("VOLUME %s su %d barre: reale=%I64d tick=%I64d -> %s", _Symbol, n, realSum, tickSum,
               realSum > 0 ? "volume reale DISPONIBILE" : "SOLO tick volume: deadfish usa un dato diverso da Binance");
   if(InpVolumeSource == VOL_REAL && realSum == 0)
      Print("ATTENZIONE: InpVolumeSource=reale ma il broker non lo fornisce. Usa VOL_TICK.");
   Print("Commissione: MQL5 non la espone; controlla la colonna Commissione nel report del tester dopo il primo trade.");
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBarsCalc < 300) Print("InpBarsCalc < 300: uso 300 barre (EMA200 richiede storico)");
   if(InpTimeframe != PERIOD_M5) Print("ATTENZIONE: la strategia originale e' tarata sul 5m.");
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(50);
   g_csvName = StringFormat("E0V1E_trades_%s_%I64d.csv", _Symbol, InpMagic);
   g_last.valid = false;
   ReportSymbol();
   ComputeCandle();                  // inizializza i valori della candela chiusa
   g_lastBarTime = iTime(_Symbol, InpTimeframe, 0);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(InpWriteCsv) WriteCsv();
   if(InpWriteCsv) PrintFormat("Report trade: <Dati comuni>\\Files\\%s", g_csvName);
  }

void OnTick()
  {
   datetime bar0 = iTime(_Symbol, InpTimeframe, 0);
   ulong ticket = 0;
   bool hasPos = SelectMyPosition(ticket);

   if(bar0 != 0 && bar0 != g_lastBarTime)
     {
      // nuova candela: ricalcola indicatori sulla candela appena chiusa
      g_lastBarTime = bar0;
      int tags = ComputeCandle();
      hasPos = SelectMyPosition(ticket);

      int openCount = 0;
      OpenRiskMoney(openCount);
      if(tags != 0 && !hasPos && g_lastExitBar != bar0 && openCount >= InpMaxOpenTrades)
         PrintFormat("Segnale %s ignorato: %d posizioni aperte (max %d)", TagToString(tags), openCount, InpMaxOpenTrades);
      if(tags != 0 && !hasPos && g_lastExitBar != bar0 && openCount < InpMaxOpenTrades)
        {
         bool spreadOk = true;
         if(InpMaxSpreadPts > 0)
            spreadOk = (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPts);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double lots = CalcLots(ask);
         if(spreadOk && lots > 0)
           {
            double sl = 0.0;
            if(InpHardStopPct > 0)
               sl = NormalizeDouble(ask * (1.0 - InpHardStopPct / 100.0), (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            string tag = TagToString(tags);
            if(g_trade.Buy(lots, _Symbol, 0.0, sl, 0.0, tag))
              {
               if(SelectMyPosition(ticket))
                 {
                  GlobalVariableSet(GVTag(ticket), tags);
                  PositionSelectByTicket(ticket);
                  GlobalVariableSet(GVStop(ticket), PositionGetDouble(POSITION_PRICE_OPEN) * (1.0 + InpStoplossRatio));
                  hasPos = true;
                 }
               {
                double notional = MoneyPerLot(_Symbol, ask) * lots;
                double bal = AccountInfoDouble(ACCOUNT_BALANCE);
                PrintFormat("INGRESSO %s tag=%s lotti=%.4f prezzo=%.5f controvalore=%.2f (%.2f%% del saldo %.2f)",
                            _Symbol, tag, lots, ask, notional, bal > 0 ? notional / bal * 100.0 : 0.0, bal);
               }
              }
            else
               PrintFormat("Errore ingresso: %d %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
           }
         else if(lots <= 0)
            Print("Ingresso saltato: lotto calcolato sotto il minimo del simbolo");
        }
     }

   if(hasPos) ManagePosition(ticket);
  }
//+------------------------------------------------------------------+
