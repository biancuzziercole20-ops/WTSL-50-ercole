#property strict
#property version   "1.00"
#property description "XAUUSD Smart Pattern Scalper - specification driven EA"

#include <Trade/Trade.mqh>

// ============================================================
// XAUUSD SMART PATTERN SCALPER
// Strategy -> Scoring -> Risk Validation -> Execution -> Logging
// No trade is forced when a required condition cannot be verified.
// ============================================================

// ---------- Core / execution ----------
input string InpAllowedSymbolContains      = "XAUUSD";
input double InpLotSize                    = 0.10;
input ulong  InpMagicNumber                = 1121001;
input int    InpMaxTradesPerDay            = 2;
input bool   InpUseCloseBarsOnly           = true;
input bool   InpDebugMode                  = false;
input int    InpMaxDeviationPoints         = 50;
input double InpMaxSpreadPips              = 35.0;

// ---------- Time ----------
input int    InpItalyStartHour             = 7;
input int    InpItalyStartMinute           = 0;
input int    InpItalyEndHour               = 12;
input int    InpItalyEndMinute             = 0;
input bool   InpAutoBrokerGMTOffset        = true;
input double InpBrokerGmtOffsetHours       = 2.0;
input double InpBrokerGmtOffsetHoursDST    = 3.0;

// ---------- Zone / S-R ----------
input int    InpSRLookbackD1               = 80;
input int    InpSRLookbackH4               = 120;
input int    InpSRLookbackH1               = 180;
input int    InpSwingStrength              = 2;
input int    InpMaxZoneDistancePips        = 15;
input double InpZoneWidthPips              = 8.0;
input int    InpMinStrongTouches           = 3;
input double InpMinStrongZoneStrength      = 65.0;

// ---------- Candle anatomy ----------
input double InpDojiBodyRatio              = 0.10;
input int    InpAverageRangePeriod         = 14;
input double InpLongCandleMultiplier       = 1.80;
input double InpNoWickThreshold            = 0.10;
input double InpCloseNearHigh              = 0.80;
input double InpCloseNearLow               = 0.20;
input double InpRejectionWickRatio         = 0.50;
input double InpStrongBodyRatio             = 0.60;

// ---------- Scoring ----------
input double InpScoreD1BiasWeight          = 20.0;
input double InpScoreH4Weight              = 15.0;
input double InpScoreH1Weight              = 10.0;
input double InpScoreSRWeight              = 15.0;
input double InpScoreLiquidityGrabWeight   = 10.0;
input double InpScorePatternWeight         = 15.0;
input double InpScoreM15Weight             = 10.0;
input double InpScoreCandleWeight          = 5.0;
input double InpScoreVolumeWeight          = 5.0;
input double InpScorePremium               = 85.0;
input double InpScoreValid                 = 65.0;
input double InpScoreLocalScalp            = 75.0;
input double InpMinRR                      = 1.20;
input double InpMaxDistancePips            = 100.0;

// ---------- Pattern detection ----------
input bool   InpAllowBreakout              = true;
input bool   InpAllowImpulsiveEntry        = true;
input bool   InpAllowTrendFollow           = true;
input bool   InpAllowFakeOut               = true;
input bool   InpAllowBreakTheTrend         = true;

// ---------- Indicator / context ----------
input int    InpATRPeriod                  = 14;
input int    InpTrendMAPeriod              = 20;
input ENUM_MA_METHOD InpTrendMAMethod      = MODE_EMA;
input ENUM_APPLIED_PRICE InpTrendMAPrice   = PRICE_CLOSE;

// ============================================================
// DATA STRUCTURES
// ============================================================

enum Direction
{
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = -1
};

enum PatternType
{
   PAT_NONE = 0,
   PAT_BREAKOUT,
   PAT_IMPULSIVE,
   PAT_TREND_FOLLOW,
   PAT_FAKEOUT,
   PAT_BREAK_TREND
};

enum BiasState
{
   BIAS_SELL = -1,
   BIAS_NEUTRAL = 0,
   BIAS_BUY = 1
};

enum DecisionCategory
{
   CAT_NONE = 0,
   CAT_PREMIUM,
   CAT_VALID,
   CAT_LOCAL_SCALP,
   CAT_NO_TRADE
};

struct CandleInfo
{
   double open, high, low, close;
   double body, upperWick, lowerWick, range;
   double bodyRatio, upperWickRatio, lowerWickRatio;
   double closePosition, openPosition;
   bool bullish, bearish, doji, longCandle;
   bool marubozuClose, noInitialWick, rejectionWick;
};

struct SRZone
{
   bool valid;
   double lower;
   double upper;
   double level;
   double strength;
   int touches;
   ENUM_TIMEFRAMES sourceTF;
   int ageBars;
   datetime sourceTime;
   datetime lastBreakoutOrRetest;
};

struct PatternResult
{
   PatternType pattern;
   Direction direction;
   bool complete;
   bool liquidityGrab;
   bool m15Strong;
   bool candleConfirmation;
   double entry;
   double structuralSL;
   double structuralTP;
   double trigger;
   string reason;
};

struct ScoreResult
{
   double d1, h4, h1, sr, grab, pattern, m15, candle, volume;
   double total;
   DecisionCategory category;
   bool superiorAligned;
   bool localAllowed;
};

struct DecisionResult
{
   bool trade;
   Direction direction;
   PatternType pattern;
   DecisionCategory category;
   string reason;
   string setupID;
   double entry;
   double sl;
   double tp;
   double rr;
   SRZone zone;
   ScoreResult score;
   CandleInfo candle;
   bool liquidityGrab;
};

// ============================================================
// GLOBALS
// ============================================================

CTrade trade;
datetime g_lastClosedBarM15 = 0;
string   g_lastSetupID = "";
string   g_consumedSetupIDs[256];
int      g_consumedCount = 0;
int      g_lastItalyDateKey = -1;
int      g_todayExecutedTrades = 0;

// ============================================================
// UTILITY
// ============================================================

string PatternName(PatternType p)
{
   switch(p)
   {
      case PAT_BREAKOUT:   return "BREAKOUT";
      case PAT_IMPULSIVE:  return "ENTRATA_IMPULSIVA";
      case PAT_TREND_FOLLOW:return "TREND_FOLLOW";
      case PAT_FAKEOUT:    return "FAKE_OUT";
      case PAT_BREAK_TREND:return "BREAK_THE_TREND";
   }
   return "NONE";
}

string DirectionName(Direction d)
{
   if(d == DIR_BUY) return "BUY";
   if(d == DIR_SELL) return "SELL";
   return "NONE";
}

string BiasName(BiasState b)
{
   if(b == BIAS_BUY) return "BUY";
   if(b == BIAS_SELL) return "SELL";
   return "NEUTRAL";
}

string CategoryName(DecisionCategory c)
{
   switch(c)
   {
      case CAT_PREMIUM:    return "PREMIUM";
      case CAT_VALID:      return "VALID";
      case CAT_LOCAL_SCALP:return "LOCAL SCALP";
      case CAT_NO_TRADE:   return "NO TRADE";
   }
   return "NONE";
}

void DebugLog(string msg)
{
   if(InpDebugMode) Print("[DEBUG] ", msg);
}

void LogDecision(const DecisionResult &d, string phase="DECISION")
{
   string zoneText = "none";
   if(d.zone.valid)
      zoneText = StringFormat("%.3f-%.3f lvl=%.3f str=%.1f touches=%d TF=%s",
                              d.zone.lower,d.zone.upper,d.zone.level,d.zone.strength,d.zone.touches,EnumToString(d.zone.sourceTF));

   PrintFormat("[%s] IT=%s | %s | spread=%.2f pips | today=%d/%d | window=%s | D1=%s H4=%s H1=%s M30=%s M15=%s | zone=%s | dist=%.2f | grab=%s | pattern=%s %s | candle=%s | score[D1 %.1f H4 %.1f H1 %.1f SR %.1f Grab %.1f Pat %.1f M15 %.1f Candle %.1f Vol %.1f]=%.1f | cat=%s | entry=%.3f SL=%.3f TP=%.3f RR=%.2f | %s",
               phase, TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS), _Symbol,
               CurrentSpreadPips(), g_todayExecutedTrades, InpMaxTradesPerDay,
               IsItalyTradingWindow() ? "OK":"NO",
               BiasName(GetBias(PERIOD_D1,1)), BiasName(GetBias(PERIOD_H4,1)), BiasName(GetBias(PERIOD_H1,1)),
               BiasName(GetBias(PERIOD_M30,1)), BiasName(GetBias(PERIOD_M15,1)),
               zoneText,
               d.zone.valid ? MathAbs(d.entry-d.zone.level)/GetPipSize() : -1.0,
               d.liquidityGrab ? "YES":"NO", PatternName(d.pattern), DirectionName(d.direction),
               d.candle.bullish ? "bullish" : d.candle.bearish ? "bearish" : "neutral",
               d.score.d1,d.score.h4,d.score.h1,d.score.sr,d.score.grab,d.score.pattern,d.score.m15,d.score.candle,d.score.volume,d.score.total,
               CategoryName(d.category), d.entry,d.sl,d.tp,d.rr,d.reason);
}

bool IsAllowedSymbol()
{
   return (StringFind(_Symbol, InpAllowedSymbolContains) >= 0);
}

double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(digits == 3 || digits == 5) return point * 10.0;
   return point * 10.0; // XAUUSD convention in this specification: 1 pip = 0.10 price units.
}

double NormalizePrice(double price)
{
   int digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(price,digits);
}

double CurrentSpreadPips()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return DBL_MAX;
   return (tick.ask-tick.bid)/GetPipSize();
}

// ============================================================
// ITALY TIME CONVERSION
// ============================================================

bool IsLeapYear(int y)
{
   return ((y%4==0 && y%100!=0) || (y%400==0));
}

int DaysInMonth(int y,int m)
{
   if(m==2) return IsLeapYear(y)?29:28;
   if(m==4 || m==6 || m==9 || m==11) return 30;
   return 31;
}

// Returns day-of-week: 0 Sunday ... 6 Saturday.
int DayOfWeekDate(int y,int m,int d)
{
   MqlDateTime dt={0};
   dt.year=y; dt.mon=m; dt.day=d; dt.hour=12;
   datetime t=StructToTime(dt);
   TimeToStruct(t,dt);
   return dt.day_of_week;
}

int LastSundayOfMonth(int y,int m)
{
   int last=DaysInMonth(y,m);
   int dow=DayOfWeekDate(y,m,last);
   return last-dow;
}

bool IsRomeDST(datetime utc)
{
   MqlDateTime x; TimeToStruct(utc,x);
   if(x.mon < 3 || x.mon > 10) return false;
   if(x.mon > 3 && x.mon < 10) return true;

   int lastSun = LastSundayOfMonth(x.year, x.mon);
   if(x.mon == 3)
   {
      if(x.day > lastSun) return true;
      if(x.day < lastSun) return false;
      return x.hour >= 1; // DST starts at 01:00 UTC.
   }
   // October
   if(x.day < lastSun) return true;
   if(x.day > lastSun) return false;
   return x.hour < 1; // DST ends at 01:00 UTC.
}

datetime ServerToUTC(datetime serverTime)
{
   if(!InpAutoBrokerGMTOffset)
   {
      double off = InpBrokerGmtOffsetHours;
      // The server offset input is interpreted as a fixed GMT offset.
      return serverTime - (int)MathRound(off*3600.0);
   }

   // In live terminal TimeGMT/TimeTradeServer share the same current instant.
   // Their difference is therefore the broker server's current GMT offset.
   datetime serverNow = TimeTradeServer();
   datetime gmtNow    = TimeGMT();
   long offsetSec = (long)(serverNow-gmtNow);
   return serverTime-offsetSec;
}

datetime ServerToItaly(datetime serverTime)
{
   datetime utc=ServerToUTC(serverTime);
   int off=IsRomeDST(utc)?7200:3600;
   return utc+off;
}

int ItalyDateKey(datetime serverTime)
{
   MqlDateTime x; TimeToStruct(ServerToItaly(serverTime),x);
   return x.year*10000+x.mon*100+x.day;
}

bool IsItalyTradingWindow()
{
   MqlDateTime x; TimeToStruct(ServerToItaly(TimeTradeServer()),x);
   int now=x.hour*60+x.min;
   int start=InpItalyStartHour*60+InpItalyStartMinute;
   int end=InpItalyEndHour*60+InpItalyEndMinute;
   return (now>=start && now<end);
}

// ============================================================
// HISTORY / DAILY LIMIT / SETUP IDS
// ============================================================

void RefreshDailyCounter()
{
   int key=ItalyDateKey(TimeTradeServer());
   if(key==g_lastItalyDateKey) return;
   g_lastItalyDateKey=key;
   g_todayExecutedTrades=0;

   datetime now=TimeTradeServer();
   datetime italyNow=ServerToItaly(now);
   MqlDateTime x; TimeToStruct(italyNow,x);
   x.hour=0; x.min=0; x.sec=0;
   datetime italyStart=StructToTime(x);

   // Convert midnight Italy back to server time using current offset approximation;
   // exact day boundary is refined by testing the resulting Italy date.
   datetime serverStart=italyStart-(IsRomeDST(italyStart-3600)?7200:3600);
   HistorySelect(serverStart,now+60);
   int deals=HistoryDealsTotal();
   for(int i=0;i<deals;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
         g_todayExecutedTrades++;
   }
}

bool SetupConsumed(string id)
{
   for(int i=0;i<g_consumedCount;i++) if(g_consumedSetupIDs[i]==id) return true;
   return false;
}

void MarkSetupConsumed(string id)
{
   if(id=="" || SetupConsumed(id)) return;
   if(g_consumedCount<256) g_consumedSetupIDs[g_consumedCount++]=id;
}

string MakeSetupID(PatternType p,Direction d,datetime t,double zoneLevel)
{
   long z=(long)MathRound(zoneLevel/GetPipSize());
   return StringFormat("%s|%s|%d|%I64d|%I64d",_Symbol,PatternName(p),(int)d,(long)t,z);
}

bool HasOpenEAPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      return true;
   }
   return false;
}

// ============================================================
// DATA / CANDLE FUNCTIONS
// ============================================================

bool LoadRates(ENUM_TIMEFRAMES tf,int count,MqlRates &rates[])
{
   ArraySetAsSeries(rates,true);
   ResetLastError();
   int copied=CopyRates(_Symbol,tf,0,count,rates);
   if(copied<count)
   {
      DebugLog(StringFormat("CopyRates %s requested=%d got=%d err=%d",EnumToString(tf),count,copied,GetLastError()));
      return false;
   }
   return true;
}

bool GetCandle(ENUM_TIMEFRAMES tf,int shift,CandleInfo &c)
{
   MqlRates r[];
   if(!LoadRates(tf,shift+2,r)) return false;
   MqlRates x=r[shift];
   c.open=x.open; c.high=x.high; c.low=x.low; c.close=x.close;
   c.body=MathAbs(c.close-c.open);
   c.upperWick=c.high-MathMax(c.open,c.close);
   c.lowerWick=MathMin(c.open,c.close)-c.low;
   c.range=c.high-c.low;
   if(c.range<=0) return false;
   c.bodyRatio=c.body/c.range;
   c.upperWickRatio=c.upperWick/c.range;
   c.lowerWickRatio=c.lowerWick/c.range;
   c.closePosition=(c.close-c.low)/c.range;
   c.openPosition=(c.open-c.low)/c.range;
   c.bullish=c.close>c.open;
   c.bearish=c.close<c.open;
   c.doji=c.bodyRatio<=InpDojiBodyRatio;

   double sum=0.0; int n=0;
   MqlRates avg[];
   int need=InpAverageRangePeriod+shift+2;
   if(LoadRates(tf,need,avg))
   {
      for(int i=shift+1;i<=shift+InpAverageRangePeriod;i++) { sum+=avg[i].high-avg[i].low; n++; }
   }
   double avgRange=(n>0?sum/n:0);
   c.longCandle=(avgRange>0 && c.range>avgRange*InpLongCandleMultiplier);
   c.marubozuClose = c.bullish ? (c.upperWickRatio<=InpNoWickThreshold && c.closePosition>=InpCloseNearHigh)
                                : c.bearish ? (c.lowerWickRatio<=InpNoWickThreshold && c.closePosition<=InpCloseNearLow) : false;
   c.noInitialWick = c.bullish ? (c.openPosition<=InpNoWickThreshold && c.bodyRatio>=InpStrongBodyRatio)
                                : c.bearish ? (c.openPosition>=(1.0-InpNoWickThreshold) && c.bodyRatio>=InpStrongBodyRatio) : false;
   c.rejectionWick=(c.upperWickRatio>=InpRejectionWickRatio || c.lowerWickRatio>=InpRejectionWickRatio);
   return true;
}

bool GetPreviousCandle(ENUM_TIMEFRAMES tf,int shift,CandleInfo &c)
{
   return GetCandle(tf,shift,c);
}

// ============================================================
// BIAS / TREND
// ============================================================

BiasState GetBias(ENUM_TIMEFRAMES tf,int shift)
{
   MqlRates r[];
   int need=InpTrendMAPeriod+shift+5;
   if(!LoadRates(tf,need,r)) return BIAS_NEUTRAL;

   int handle=iMA(_Symbol,tf,InpTrendMAPeriod,0,InpTrendMAMethod,InpTrendMAPrice);
   if(handle==INVALID_HANDLE) { DebugLog("iMA handle creation failed"); return BIAS_NEUTRAL; }
   double ma[];
   ArraySetAsSeries(ma,true);
   bool ok=(CopyBuffer(handle,0,0,shift+3,ma)>=shift+2);
   IndicatorRelease(handle);
   if(!ok) return BIAS_NEUTRAL;

   double close=r[shift].close;
   double prevMA=ma[shift+1];
   double curMA=ma[shift];
   if(close>curMA && curMA>prevMA) return BIAS_BUY;
   if(close<curMA && curMA<prevMA) return BIAS_SELL;
   return BIAS_NEUTRAL;
}

bool IsStrongM15(Direction d)
{
   BiasState b=GetBias(PERIOD_M15,1);
   CandleInfo c;
   if(!GetCandle(PERIOD_M15,1,c)) return false;
   if(d==DIR_BUY) return (b==BIAS_BUY && c.bullish && (c.bodyRatio>=InpStrongBodyRatio || c.marubozuClose || c.noInitialWick));
   if(d==DIR_SELL) return (b==BIAS_SELL && c.bearish && (c.bodyRatio>=InpStrongBodyRatio || c.marubozuClose || c.noInitialWick));
   return false;
}

// ============================================================
// S/R ZONES
// ============================================================

bool IsSwingHigh(const MqlRates &r[],int idx,int strength)
{
   for(int k=1;k<=strength;k++)
      if(r[idx].high<=r[idx-k].high || r[idx].high<=r[idx+k].high) return false;
   return true;
}

bool IsSwingLow(const MqlRates &r[],int idx,int strength)
{
   for(int k=1;k<=strength;k++)
      if(r[idx].low>=r[idx-k].low || r[idx].low>=r[idx+k].low) return false;
   return true;
}

void ScoreZoneTouches(const MqlRates &r[],int total,double level,double width,int &touches,datetime &lastEvent)
{
   touches=0; lastEvent=0;
   for(int i=1;i<total;i++)
   {
      bool touched=(r[i].high>=level-width && r[i].low<=level+width);
      if(touched) { touches++; if(lastEvent==0) lastEvent=r[i].time; }
   }
}

bool FindBestZone(Direction desired,SRZone &best)
{
   best.valid=false;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double width=InpZoneWidthPips*GetPipSize();
   ENUM_TIMEFRAMES tfs[3]={PERIOD_D1,PERIOD_H4,PERIOD_H1};
   int looks[3]={InpSRLookbackD1,InpSRLookbackH4,InpSRLookbackH1};
   double price=(desired==DIR_BUY ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID));
   double bestDist=DBL_MAX;

   for(int ti=0;ti<3;ti++)
   {
      MqlRates r[];
      int total=looks[ti]+InpSwingStrength*2+10;
      if(!LoadRates(tfs[ti],total,r)) continue;
      for(int i=InpSwingStrength+1;i<total-InpSwingStrength;i++)
      {
         double level=0;
         bool validSwing=false;
         if(desired==DIR_BUY) { validSwing=IsSwingLow(r,i,InpSwingStrength); if(validSwing) level=r[i].low; }
         else { validSwing=IsSwingHigh(r,i,InpSwingStrength); if(validSwing) level=r[i].high; }
         if(!validSwing) continue;

         int touches=0; datetime lastEvent=0;
         ScoreZoneTouches(r,total,level,width,touches,lastEvent);
         double strength=MathMin(100.0,10.0+touches*18.0);
         int age=i;
         double dist=MathAbs(price-level)/GetPipSize();
         if(dist>InpMaxZoneDistancePips*2.5) continue;

         // Prefer stronger zones, then closer zones, then higher timeframe.
         double rank=(strength*2.0)-dist*2.0+(ti==0?10:ti==1?5:0);
         double bestRank=best.valid ? (best.strength*2.0-bestDist*2.0+(best.sourceTF==PERIOD_D1?10:best.sourceTF==PERIOD_H4?5:0)) : -DBL_MAX;
         if(!best.valid || rank>bestRank)
         {
            best.valid=true;
            best.level=NormalizePrice(level);
            best.lower=NormalizePrice(level-width);
            best.upper=NormalizePrice(level+width);
            best.strength=strength;
            best.touches=touches;
            best.sourceTF=tfs[ti];
            best.ageBars=age;
            best.sourceTime=r[i].time;
            best.lastBreakoutOrRetest=lastEvent;
            bestDist=dist;
         }
      }
   }
   return best.valid;
}

// ============================================================
// LIQUIDITY GRAB / ENGULFING / PATTERNS
// ============================================================

bool DetectLiquidityGrab(ENUM_TIMEFRAMES tf,Direction d,int shift,SRZone zone)
{
   MqlRates r[];
   if(!LoadRates(tf,20,r)) return false;
   if(shift+3>=ArraySize(r)) return false;
   MqlRates c=r[shift];
   double level=zone.level;
   double width=InpZoneWidthPips*GetPipSize();
   if(d==DIR_BUY)
   {
      bool penetration=c.low < level-width*0.25;
      bool returnInside=c.close >= zone.lower && c.close <= zone.upper || c.close>level;
      return penetration && returnInside && c.close>c.low;
   }
   if(d==DIR_SELL)
   {
      bool penetration=c.high > level+width*0.25;
      bool returnInside=c.close <= zone.upper && c.close >= zone.lower || c.close<level;
      return penetration && returnInside && c.close<c.high;
   }
   return false;
}

bool BullishEngulfing(ENUM_TIMEFRAMES tf,int shift)
{
   CandleInfo cur,prev;
   if(!GetCandle(tf,shift,cur) || !GetCandle(tf,shift+1,prev)) return false;
   return prev.bearish && cur.bullish && cur.open<=prev.close && cur.close>=prev.open && cur.body>=prev.body*0.8;
}

bool BearishEngulfing(ENUM_TIMEFRAMES tf,int shift)
{
   CandleInfo cur,prev;
   if(!GetCandle(tf,shift,cur) || !GetCandle(tf,shift+1,prev)) return false;
   return prev.bullish && cur.bearish && cur.open>=prev.close && cur.close<=prev.open && cur.body>=prev.body*0.8;
}

bool PriceNearZone(double price,const SRZone &z)
{
   if(!z.valid) return false;
   return (MathAbs(price-z.level)/GetPipSize()<=InpMaxZoneDistancePips);
}

bool DetectBreakout(Direction d,const SRZone &z,PatternResult &p)
{
   if(!InpAllowBreakout || !z.valid) return false;
   CandleInfo c;
   if(!GetCandle(PERIOD_M15,1,c)) return false;
   if(c.longCandle && !PriceNearZone(c.close,z)) return false;
   bool ok=false;
   if(d==DIR_BUY) ok=c.bullish && c.close>z.upper && c.bodyRatio>=InpStrongBodyRatio;
   if(d==DIR_SELL) ok=c.bearish && c.close<z.lower && c.bodyRatio>=InpStrongBodyRatio;
   if(!ok) return false;
   p.pattern=PAT_BREAKOUT; p.direction=d; p.complete=true; p.candleConfirmation=true;
   p.entry=c.close;
   p.structuralSL=(d==DIR_BUY?c.low:z.upper);
   if(d==DIR_SELL) p.structuralSL=c.high;
   return true;
}

bool DetectImpulsive(Direction d,const SRZone &z,PatternResult &p)
{
   if(!InpAllowImpulsiveEntry || !z.valid) return false;
   MqlRates r[]; if(!LoadRates(PERIOD_M30,30,r)) return false;
   double hi=-DBL_MAX,lo=DBL_MAX;
   for(int i=1;i<21;i++){ hi=MathMax(hi,r[i].high); lo=MathMin(lo,r[i].low); }
   double range=hi-lo; if(range<=0) return false;
   double price=(d==DIR_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   double pos=(price-lo)/range;
   bool atExtreme=(d==DIR_BUY?pos<=0.20:pos>=0.80);
   if(!atExtreme) return false;
   CandleInfo c; if(!GetCandle(PERIOD_M30,1,c)) return false;
   bool reaction=(d==DIR_BUY ? c.bullish && c.lowerWickRatio>=0.20 : c.bearish && c.upperWickRatio>=0.20);
   if(!reaction || !IsStrongM15(d)) return false;
   p.pattern=PAT_IMPULSIVE; p.direction=d; p.complete=true; p.m15Strong=true; p.candleConfirmation=true;
   p.entry=(d==DIR_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   p.structuralSL=(d==DIR_BUY?MathMin(lo,z.lower):MathMax(hi,z.upper));
   p.structuralTP=(d==DIR_BUY?hi:lo);
   return true;
}

bool DetectTrendFollow(Direction d,const SRZone &z,PatternResult &p)
{
   if(!InpAllowTrendFollow || !z.valid) return false;
   BiasState b1=GetBias(PERIOD_H1,1), b4=GetBias(PERIOD_H4,1);
   if((d==DIR_BUY && !(b1==BIAS_BUY || b4==BIAS_BUY)) || (d==DIR_SELL && !(b1==BIAS_SELL || b4==BIAS_SELL))) return false;
   CandleInfo c1,c2,c3;
   if(!GetCandle(PERIOD_M15,1,c1) || !GetCandle(PERIOD_M15,2,c2) || !GetCandle(PERIOD_M15,3,c3)) return false;
   bool reaction=(d==DIR_BUY ? c1.bullish && PriceNearZone(c1.low,z) : c1.bearish && PriceNearZone(c1.high,z));
   bool continuation=(d==DIR_BUY ? c1.close>c2.close : c1.close<c2.close);
   if(!reaction || !continuation) return false;
   p.pattern=PAT_TREND_FOLLOW; p.direction=d; p.complete=true; p.candleConfirmation=true; p.m15Strong=IsStrongM15(d);
   p.entry=(d==DIR_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   p.structuralSL=(d==DIR_BUY?MathMin(c1.low,z.lower):MathMax(c1.high,z.upper));
   return true;
}

bool DetectFakeOut(Direction d,const SRZone &z,PatternResult &p)
{
   if(!InpAllowFakeOut || !z.valid) return false;
   if(!DetectLiquidityGrab(PERIOD_M30,d,1,z)) return false;
   CandleInfo c; if(!GetCandle(PERIOD_M30,1,c)) return false;
   bool reject=(d==DIR_BUY ? c.lowerWickRatio>=InpRejectionWickRatio && c.close>z.lower : c.upperWickRatio>=InpRejectionWickRatio && c.close<z.upper);
   if(!reject || !IsStrongM15(d)) return false;
   p.pattern=PAT_FAKEOUT; p.direction=d; p.complete=true; p.liquidityGrab=true; p.m15Strong=true; p.candleConfirmation=true;
   p.entry=(d==DIR_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   p.structuralSL=(d==DIR_BUY?c.low:c.high);
   return true;
}

bool DetectBreakTheTrend(Direction d,const SRZone &z,PatternResult &p)
{
   if(!InpAllowBreakTheTrend || !z.valid) return false;
   Direction counter=(d==DIR_BUY?DIR_SELL:DIR_BUY);
   BiasState h1=GetBias(PERIOD_H1,1);
   if((counter==DIR_SELL && h1!=BIAS_SELL) || (counter==DIR_BUY && h1!=BIAS_BUY)) return false;
   bool engulf=(d==DIR_BUY?BullishEngulfing(PERIOD_M15,1):BearishEngulfing(PERIOD_M15,1));
   if(!engulf) return false;
   MqlRates r[]; if(!LoadRates(PERIOD_M15,10,r)) return false;
   double trigger=(d==DIR_BUY?r[2].high:r[2].low);
   bool broken=(d==DIR_BUY?r[1].close>trigger:r[1].close<trigger);
   if(!broken || !IsStrongM15(d)) return false;
   p.pattern=PAT_BREAK_TREND; p.direction=d; p.complete=true; p.m15Strong=true; p.candleConfirmation=true; p.trigger=trigger;
   p.entry=(d==DIR_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   p.structuralSL=(d==DIR_BUY?MathMin(r[1].low,z.lower):MathMax(r[1].high,z.upper));
   return true;
}

bool SelectBestPattern(Direction d,const SRZone &z,PatternResult &best)
{
   PatternResult p;
   best.pattern=PAT_NONE; best.complete=false;
   int priorityBest=999;
   // Lower number = preferred quality/prioritization.
   if(DetectBreakTheTrend(d,z,p)) { best=p; priorityBest=1; }
   if(DetectFakeOut(d,z,p) && priorityBest>2) { best=p; priorityBest=2; }
   if(DetectBreakout(d,z,p) && priorityBest>3) { best=p; priorityBest=3; }
   if(DetectTrendFollow(d,z,p) && priorityBest>4) { best=p; priorityBest=4; }
   if(DetectImpulsive(d,z,p) && priorityBest>5) { best=p; priorityBest=5; }
   return best.complete;
}

// ============================================================
// SCORING
// ============================================================

ScoreResult CalculateScore(Direction d,const SRZone &z,const PatternResult &p)
{
   ScoreResult s={0};
   BiasState d1=GetBias(PERIOD_D1,1), h4=GetBias(PERIOD_H4,1), h1=GetBias(PERIOD_H1,1);
   BiasState m30=GetBias(PERIOD_M30,1), m15=GetBias(PERIOD_M15,1);
   bool d1ok=(d==DIR_BUY?d1==BIAS_BUY:d1==BIAS_SELL);
   bool h4ok=(d==DIR_BUY?h4==BIAS_BUY:h4==BIAS_SELL);
   bool h1ok=(d==DIR_BUY?h1==BIAS_BUY:h1==BIAS_SELL);
   bool m15ok=(d==DIR_BUY?m15==BIAS_BUY:m15==BIAS_SELL);
   s.d1=d1ok?InpScoreD1BiasWeight:0;
   s.h4=h4ok?InpScoreH4Weight:0;
   s.h1=h1ok?InpScoreH1Weight:0;
   s.sr=(z.valid?MathMin(InpScoreSRWeight,InpScoreSRWeight*(z.strength/100.0)):0);
   s.grab=p.liquidityGrab?InpScoreLiquidityGrabWeight:0;
   s.pattern=p.complete?InpScorePatternWeight:0;
   s.m15=m15ok?InpScoreM15Weight:0;

   CandleInfo c; GetCandle(PERIOD_M15,1,c);
   bool quality=(c.marubozuClose || c.noInitialWick || (d==DIR_BUY?BullishEngulfing(PERIOD_M15,1):BearishEngulfing(PERIOD_M15,1)));
   s.candle=(quality && z.valid && PriceNearZone(c.close,z))?InpScoreCandleWeight:0;

   MqlRates r[];
   if(LoadRates(PERIOD_M15,25,r))
   {
      double avg=0,cur=0;
      for(int i=2;i<22;i++) avg+=(double)r[i].tick_volume;
      avg/=20.0; cur=(double)r[1].tick_volume;
      if(avg>0 && cur>=avg*1.20) s.volume=InpScoreVolumeWeight;
   }
   s.total=s.d1+s.h4+s.h1+s.sr+s.grab+s.pattern+s.m15+s.candle+s.volume;
   s.superiorAligned=d1ok && h4ok && h1ok;
   bool validSuperior=(d1ok&&h4ok) || (h1ok && (m30==(BiasState)d || m15==(BiasState)d));
   if(s.total>=InpScorePremium && s.superiorAligned) s.category=CAT_PREMIUM;
   else if(s.total>=InpScoreValid && validSuperior) s.category=CAT_VALID;
   else if(s.total>=InpScoreLocalScalp && !s.superiorAligned && z.valid && (p.liquidityGrab || quality) && IsStrongM15(d))
   {
      s.category=CAT_LOCAL_SCALP; s.localAllowed=true;
   }
   else s.category=CAT_NO_TRADE;
   return s;
}

// ============================================================
// RISK / VALIDATION
// ============================================================

bool BuildSLTP(Direction d,const PatternResult &p,const SRZone &z,double entry,double &sl,double &tp,string &reason)
{
   double pip=GetPipSize();
   if(entry<=0) { reason="entry non valida"; return false; }
   sl=p.structuralSL;
   if(sl<=0)
   {
      sl=(d==DIR_BUY ? entry-20*pip : entry+20*pip);
   }
   // Keep structural SL on the correct side.
   if(d==DIR_BUY && sl>=entry) sl=entry-20*pip;
   if(d==DIR_SELL && sl<=entry) sl=entry+20*pip;

   // TP selection: nearest opposite side of the detected zone first; otherwise 1.8R.
   if(z.valid)
   {
      if(d==DIR_BUY) tp=z.upper>entry ? z.upper : entry+MathAbs(entry-sl)*1.8;
      else tp=z.lower<entry ? z.lower : entry-MathAbs(entry-sl)*1.8;
   }
   else tp=(d==DIR_BUY ? entry+MathAbs(entry-sl)*1.8 : entry-MathAbs(entry-sl)*1.8);

   if(d==DIR_BUY && tp<=entry) tp=entry+MathAbs(entry-sl)*1.8;
   if(d==DIR_SELL && tp>=entry) tp=entry-MathAbs(entry-sl)*1.8;
   sl=NormalizePrice(sl); tp=NormalizePrice(tp);

   double slPips=MathAbs(entry-sl)/pip;
   double tpPips=MathAbs(tp-entry)/pip;
   if(slPips>InpMaxDistancePips) { reason=StringFormat("SL %.2f pips > %.2f",slPips,InpMaxDistancePips); return false; }
   if(tpPips>InpMaxDistancePips) { reason=StringFormat("TP %.2f pips > %.2f",tpPips,InpMaxDistancePips); return false; }
   double risk=MathAbs(entry-sl), reward=MathAbs(tp-entry);
   if(risk<=0) { reason="SL nullo"; return false; }
   double rr=reward/risk;
   if(rr<InpMinRR) { reason=StringFormat("R:R %.2f < %.2f",rr,InpMinRR); return false; }
   return true;
}

bool ValidateStops(Direction d,double entry,double sl,double tp,string &reason)
{
   long stops=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minDist=MathMax(stops,freeze)*point;
   if(minDist<=0) return true;
   if(d==DIR_BUY)
   {
      if(entry-sl<minDist || tp-entry<minDist) { reason=StringFormat("SL/TP sotto stop/freeze level broker (%.1f points)",minDist/point); return false; }
   }
   else
   {
      if(sl-entry<minDist || entry-tp<minDist) { reason=StringFormat("SL/TP sotto stop/freeze level broker (%.1f points)",minDist/point); return false; }
   }
   return true;
}

bool ValidateVolume(double volume,string &reason)
{
   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(vmin<=0 || vmax<=0 || vstep<=0) { reason="parametri volume broker non disponibili"; return false; }
   if(volume<vmin || volume>vmax) { reason=StringFormat("volume %.2f fuori [%g,%g]",volume,vmin,vmax); return false; }
   double steps=(volume-vmin)/vstep;
   if(MathAbs(steps-MathRound(steps))>1e-8) { reason=StringFormat("volume %.2f non conforme a step %g",volume,vstep); return false; }
   return true;
}

bool ValidateMargin(Direction d,double volume,double entry,string &reason)
{
   double margin=0;
   ENUM_ORDER_TYPE type=(d==DIR_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   if(!OrderCalcMargin(type,_Symbol,volume,entry,margin)) { reason=StringFormat("OrderCalcMargin fallito err=%d",GetLastError()); return false; }
   double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin>free) { reason=StringFormat("margine insufficiente %.2f > free %.2f",margin,free); return false; }
   return true;
}

bool ValidateDataAvailability(string &reason)
{
   int counts[5]={InpSRLookbackD1+20,InpSRLookbackH4+20,InpSRLookbackH1+20,80,120};
   ENUM_TIMEFRAMES tfs[5]={PERIOD_D1,PERIOD_H4,PERIOD_H1,PERIOD_M30,PERIOD_M15};
   for(int i=0;i<5;i++)
   {
      MqlRates r[];
      if(!LoadRates(tfs[i],counts[i],r)) { reason=StringFormat("dati insufficienti/CopyRates %s",EnumToString(tfs[i])); return false; }
   }
   return true;
}

// ============================================================
// DECISION ENGINE
// ============================================================

DecisionResult MakeDecision()
{
   DecisionResult d={0};
   d.trade=false; d.direction=DIR_NONE; d.pattern=PAT_NONE; d.category=CAT_NO_TRADE; d.reason="";

   // [0a] Symbol
   if(!IsAllowedSymbol()) { d.reason="simbolo non valido"; return d; }
   // [0b] Time
   if(!IsItalyTradingWindow()) { d.reason="fuori finestra 07:00-12:00 Europe/Rome"; return d; }
   // [0c] Daily limit
   RefreshDailyCounter();
   if(g_todayExecutedTrades>=InpMaxTradesPerDay) { d.reason=StringFormat("limite giornaliero raggiunto (%d/%d)",g_todayExecutedTrades,InpMaxTradesPerDay); return d; }
   // [0d] Existing position / duplicates
   if(HasOpenEAPosition()) { d.reason="posizione EA già aperta sul simbolo"; return d; }
   // [0e] Spread
   double spread=CurrentSpreadPips();
   if(spread==DBL_MAX || spread>InpMaxSpreadPips) { d.reason=StringFormat("spread eccessivo %.2f > %.2f pips",spread,InpMaxSpreadPips); return d; }
   // [0f] Data
   string reason;
   if(!ValidateDataAvailability(reason)) { d.reason=reason; return d; }

   // Try both directions; choose only one best complete setup.
   PatternResult bestBuy={0},bestSell={0};
   SRZone zBuy={0},zSell={0};
   FindBestZone(DIR_BUY,zBuy); FindBestZone(DIR_SELL,zSell);
   bool buyOK=SelectBestPattern(DIR_BUY,zBuy,bestBuy);
   bool sellOK=SelectBestPattern(DIR_SELL,zSell,bestSell);
   if(!buyOK && !sellOK) { d.reason="nessun pattern completo"; return d; }

   // If both sides exist, select by score after building provisional scores.
   ScoreResult sb={0},ss={0};
   if(buyOK) sb=CalculateScore(DIR_BUY,zBuy,bestBuy);
   if(sellOK) ss=CalculateScore(DIR_SELL,zSell,bestSell);
   Direction chosen=DIR_NONE;
   if(buyOK && sellOK) chosen=(sb.total>=ss.total?DIR_BUY:DIR_SELL);
   else chosen=(buyOK?DIR_BUY:DIR_SELL);

   PatternResult p=(chosen==DIR_BUY?bestBuy:bestSell);
   SRZone z=(chosen==DIR_BUY?zBuy:zSell);
   ScoreResult s=(chosen==DIR_BUY?sb:ss);
   d.direction=chosen; d.pattern=p.pattern; d.zone=z; d.score=s; d.liquidityGrab=p.liquidityGrab;
   GetCandle(PERIOD_M15,1,d.candle);

   // [2] Distance from zone
   d.entry=(chosen==DIR_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   if(!z.valid) { d.reason="S/R zona non identificata"; return d; }
   double dist=MathAbs(d.entry-z.level)/GetPipSize();
   if(dist>InpMaxZoneDistancePips) { d.reason=StringFormat("distanza zona %.2f pips > %.2f",dist,(double)InpMaxZoneDistancePips); return d; }

   // Candle anatomy absolute gate: long candle cannot be chased.
   if(d.candle.longCandle && dist>InpMaxZoneDistancePips) { d.reason="long candle + ingresso esteso: no chasing"; return d; }
   if(d.candle.doji && !d.candle.rejectionWick && !p.liquidityGrab) { d.reason="doji senza conferma contestuale"; return d; }

   // Score/category
   if(s.category==CAT_NO_TRADE) { d.reason=StringFormat("score %.1f sotto soglia/categoria non valida",s.total); return d; }

   // [9-11] SL/TP/RR
   if(!BuildSLTP(chosen,p,z,d.entry,d.sl,d.tp,reason)) { d.reason=reason; return d; }
   d.rr=MathAbs(d.tp-d.entry)/MathAbs(d.entry-d.sl);

   // [12] Stop/freeze
   if(!ValidateStops(chosen,d.entry,d.sl,d.tp,reason)) { d.reason=reason; return d; }
   // [13] Volume
   if(!ValidateVolume(InpLotSize,reason)) { d.reason=reason; return d; }
   // [14] Margin
   if(!ValidateMargin(chosen,InpLotSize,d.entry,reason)) { d.reason=reason; return d; }
   // [16] Setup duplicate
   datetime setupTime=iTime(_Symbol,PERIOD_M15,1);
   d.setupID=MakeSetupID(p.pattern,chosen,setupTime,z.level);
   if(SetupConsumed(d.setupID)) { d.reason="segnale duplicato: SetupID già consumato"; return d; }

   d.trade=true;
   d.category=s.category;
   d.reason="SETUP VALIDATO: pronto per execution";
   return d;
}

// ============================================================
// EXECUTION
// ============================================================

bool ExecuteDecision(DecisionResult &d)
{
   if(!d.trade) return false;
   if(!IsItalyTradingWindow()) { d.trade=false; d.reason="finestra oraria chiusa prima dell'invio"; return false; }
   RefreshDailyCounter();
   if(g_todayExecutedTrades>=InpMaxTradesPerDay) { d.trade=false; d.reason="limite giornaliero raggiunto prima dell'invio"; return false; }
   double spread=CurrentSpreadPips();
   if(spread>InpMaxSpreadPips) { d.trade=false; d.reason="spread eccessivo prima dell'invio"; return false; }
   if(HasOpenEAPosition()) { d.trade=false; d.reason="posizione EA apparsa prima dell'invio"; return false; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) { d.trade=false; d.reason="SymbolInfoTick fallito"; return false; }
   double price=(d.direction==DIR_BUY?tick.ask:tick.bid);
   d.entry=NormalizePrice(price);

   string reason;
   if(!ValidateStops(d.direction,d.entry,d.sl,d.tp,reason)) { d.trade=false; d.reason=reason; return false; }
   if(!ValidateMargin(d.direction,InpLotSize,d.entry,reason)) { d.trade=false; d.reason=reason; return false; }

   MqlTradeRequest req={0};
   MqlTradeResult  res={0};
   MqlTradeCheckResult check={0};
   req.action=TRADE_ACTION_DEAL;
   req.symbol=_Symbol;
   req.magic=InpMagicNumber;
   req.volume=InpLotSize;
   req.type=(d.direction==DIR_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   req.price=d.entry;
   req.sl=d.sl;
   req.tp=d.tp;
   req.deviation=(ulong)InpMaxDeviationPoints;
   long fillingFlags=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((fillingFlags & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
      req.type_filling=ORDER_FILLING_FOK;
   else if((fillingFlags & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
      req.type_filling=ORDER_FILLING_IOC;
   else
      req.type_filling=ORDER_FILLING_RETURN;
   req.comment=StringFormat("SPS|%s|%s",PatternName(d.pattern),d.setupID);

   ResetLastError();
   if(!OrderCheck(req,check))
   {
      int err=GetLastError();
      d.trade=false;
      d.reason=StringFormat("OrderCheck fallito err=%d retcode=%u comment=%s",err,check.retcode,check.comment);
      Print("[EXECUTION] ",d.reason);
      return false;
   }
   if(check.retcode!=TRADE_RETCODE_DONE && check.retcode!=TRADE_RETCODE_PLACED && check.retcode!=TRADE_RETCODE_DONE_PARTIAL)
   {
      d.trade=false;
      d.reason=StringFormat("OrderCheck rifiutato retcode=%u comment=%s",check.retcode,check.comment);
      Print("[EXECUTION] ",d.reason);
      return false;
   }

   ZeroMemory(res);
   ResetLastError();
   bool sent=OrderSend(req,res);
   int err=GetLastError();
   if(!sent)
   {
      d.trade=false;
      d.reason=StringFormat("OrderSend fallito err=%d retcode=%u comment=%s",err,res.retcode,res.comment);
      Print("[EXECUTION] ",d.reason);
      return false;
   }
   if(res.retcode!=TRADE_RETCODE_DONE && res.retcode!=TRADE_RETCODE_PLACED && res.retcode!=TRADE_RETCODE_DONE_PARTIAL)
   {
      d.trade=false;
      d.reason=StringFormat("esecuzione rifiutata retcode=%u comment=%s",res.retcode,res.comment);
      Print("[EXECUTION] ",d.reason);
      return false;
   }

   // Successful real execution: consume setup. Daily counter is refreshed from history.
   MarkSetupConsumed(d.setupID);
   RefreshDailyCounter();
   PrintFormat("[EXECUTION OK] %s %s | order=%I64u deal=%I64u | entry=%.3f SL=%.3f TP=%.3f | SetupID=%s | today=%d/%d",
               DirectionName(d.direction),PatternName(d.pattern),res.order,res.deal,d.entry,d.sl,d.tp,d.setupID,g_todayExecutedTrades,InpMaxTradesPerDay);
   return true;
}

// ============================================================
// EVENTS
// ============================================================

int OnInit()
{
   if(!SymbolSelect(_Symbol,true))
   {
      Print("[INIT ERROR] SymbolSelect fallito err=",GetLastError());
      return INIT_FAILED;
   }

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double pip=GetPipSize();

   PrintFormat("[INIT] XAUUSD SMART PATTERN SCALPER | symbol=%s | Digits=%d Point=%.10f TickSize=%.10f TickValue=%.5f PipSize=%.10f | window Italy=%02d:%02d-%02d:%02d | max trades=%d | lot=%.2f | spread max=%.2f pips | deviation=%d | magic=%I64u",
               _Symbol,digits,point,tickSize,tickValue,pip,InpItalyStartHour,InpItalyStartMinute,InpItalyEndHour,InpItalyEndMinute,InpMaxTradesPerDay,InpLotSize,InpMaxSpreadPips,InpMaxDeviationPoints,InpMagicNumber);

   if(InpAutoBrokerGMTOffset)
      PrintFormat("[INIT] Broker GMT offset: AUTO (server=%s GMT=%s)",TimeToString(TimeTradeServer(),TIME_SECONDS),TimeToString(TimeGMT(),TIME_SECONDS));
   else
      PrintFormat("[INIT] Broker GMT offset: FIXED normal=%.1f DST=%.1f",InpBrokerGmtOffsetHours,InpBrokerGmtOffsetHoursDST);

   RefreshDailyCounter();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   RefreshDailyCounter();

   datetime closed=iTime(_Symbol,PERIOD_M15,1);
   if(InpUseCloseBarsOnly)
   {
      if(closed==0 || closed==g_lastClosedBarM15) return;
      g_lastClosedBarM15=closed;
   }

   DecisionResult d=MakeDecision();
   LogDecision(d,d.trade?"SETUP":"NO TRADE");
   if(d.trade)
   {
      bool ok=ExecuteDecision(d);
      if(!ok) LogDecision(d,"EXECUTION REJECTED");
      else LogDecision(d,"TRADE EXECUTED");
   }
}
