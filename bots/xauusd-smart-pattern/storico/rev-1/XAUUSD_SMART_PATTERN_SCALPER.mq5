//+------------------------------------------------------------------+
//|                                XAUUSD_SMART_PATTERN_SCALPER.mq5  |
//|                                                                    |
//| Scalping EA su XAUUSD - Supporti/Resistenze come ZONE,             |
//| Struttura Multi-Timeframe, Anatomia delle candele, 5 pattern,      |
//| Scoring, Layer di sicurezza/validazione/execution.                 |
//|                                                                    |
//| ARCHITETTURA (separazione esplicita richiesta dalla specifica):    |
//|   ANALYSIS         -> S/R, MTF, Candele, Liquidita', Pattern       |
//|   SCORING          -> componenti + punteggio totale                |
//|   DECISION         -> PREMIUM / VALID / LOCAL SCALP / NO TRADE     |
//|   RISK VALIDATION  -> SL, TP, RR, limite 100 pip, spread, volume,  |
//|                       margine, restrizioni broker                  |
//|   EXECUTION        -> OrderCheck / OrderSend / retcode / verifica  |
//|   LOGGING          -> log completo e motivato di ogni decisione    |
//|                                                                    |
//| NOTE ONESTE SULLE IMPLEMENTAZIONI:                                 |
//| - GetBias() e' un motore di riferimento basato su EMA fast/slow.   |
//|   Non e' un'analisi di struttura HH/HL/LH/LL completa. E' usato    |
//|   SOLO per il bias D1/H4/H1 (contesto), MAI come sostituto delle   |
//|   condizioni strutturali dei pattern (impulso/pullback/reazione/   |
//|   continuazione, engulfing/trigger, liquidity grab), che sono      |
//|   verificate separatamente e in modo esplicito.                    |
//| - Se una condizione strutturale richiesta da un pattern non puo'   |
//|   essere verificata con i dati disponibili, il pattern NON viene   |
//|   dichiarato completo: nessuna condizione necessaria e' mai        |
//|   sostituita da un punteggio piu' alto altrove (vedi RunDecisionPipeline). |
//| - Nessuna martingala, nessun recovery dopo perdita, nessun         |
//|   aumento di lotto automatico, in nessun punto del codice.        |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Smart Pattern Scalper"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//====================================================================
// INPUT PARAMETERS
//====================================================================

input group "=== GENERALE ==="
input ulong   InpMagicNumber              = 999501;   // Magic Number dedicato
input bool    InpDebugMode                = true;     // Log dettagliato (nodi intermedi)
input bool    InpUseCloseBarsOnly         = true;      // Decisioni solo su candele M15 completamente chiuse

input group "=== FINESTRA ORARIA ITALIA (Europe/Rome) ==="
input int     InpBrokerGmtOffsetHoursWin  = 2;         // Offset server broker vs GMT in ora solare (winter)
input int     InpBrokerGmtOffsetHoursSum  = 3;         // Offset server broker vs GMT in ora legale (summer)
input bool    InpBrokerAppliesDST         = true;      // Il server broker cambia ora con il DST (come Europa)?
input int     InpTradingStartHour         = 7;         // Inizio finestra (ora Italia)
input int     InpTradingEndHour           = 12;        // Fine finestra (ora Italia)

input group "=== LIMITI OPERATIVI ==="
input double  InpLotSize                  = 0.10;      // Lotto fisso (NON martingala)
input int     InpMaxTradesPerDay          = 2;          // Massimo trade eseguiti/giorno italiano
input double  InpMaxSpreadPips            = 35.0;       // Spread massimo consentito (pip)
input int     InpMaxDeviationPoints       = 50;         // Deviation/slippage massima (points)
input double  InpMaxSLPips                = 100.0;      // SL massimo assoluto (pip)
input double  InpMaxTPPips                = 100.0;      // TP massimo assoluto (pip)
input double  InpMinRR                    = 1.20;       // R:R minimo richiesto
input double  InpStructSLBufferPips       = 3.0;        // Buffer oltre wick/struttura per lo SL
input double  InpFakeOutTpConservativeFactor = 0.70;    // Fattore conservativo TP per Fake Out (su MaxTPPips)
input double  InpLocalScalpRiskFactor     = 0.60;       // Fattore riduzione SL/TP per LOCAL SCALP

input group "=== ZONE S/R ==="
input int     InpZoneLookbackBarsH4       = 300;        // Barre H4 analizzate per le zone
input int     InpZoneLookbackBarsD1       = 300;        // Barre D1 analizzate per le zone
input int     InpFractalWing              = 2;           // Ampiezza fractal (barre a sx/dx)
input double  InpZoneClusterPips          = 25.0;        // Distanza max per raggruppare due fractal nella stessa zona
input double  InpMaxZoneDistancePips      = 15.0;        // Distanza massima ingresso-zona ("candela della strategia")
input int     InpZoneMinTouchesStrong     = 3;           // Tocchi minimi per considerare zona "forte"
input double  InpZoneStrongThreshold      = 60.0;        // Soglia di Strength (0-100) per considerare zona forte

input group "=== ANATOMIA CANDELE ==="
input double  InpDojiBodyRatio            = 0.10;        // BodyRatio massimo per Doji
input double  InpLongCandleMultiplier     = 1.8;         // Moltiplicatore su range medio per "candela lunga"
input int     InpAvgRangePeriod           = 20;          // Periodo range medio (proxy ATR)
input double  InpNoWickThreshold          = 0.08;        // Soglia wick "nulla" (Marubozu)
input double  InpCloseNearExtreme         = 0.90;        // Soglia chiusura vicina all'estremo
input double  InpRejectionWickRatio       = 0.50;        // Soglia wick di rigetto / wick fill

input group "=== PATTERN 3 - TREND FOLLOW (impulso/pullback) ==="
input int     InpImpulseBars              = 4;           // Barre M15 usate per misurare l'impulso
input double  InpImpulseMinMultiplier     = 1.5;         // Displacement minimo = AvgRange * questo fattore
input int     InpPullbackMaxBars          = 6;           // Barre massime per cercare il pullback
input int     InpContinuationMaxBars      = 4;           // Barre massime per confermare la continuazione

input group "=== PATTERN 4 - FAKE OUT / LIQUIDITY GRAB ==="
input bool    InpRequireGrabConfirmation  = true;        // Richiede candela di conferma dopo il grab

input group "=== SCORING (NON MODIFICARE SENZA MOTIVO) ==="
input double  InpScorePremium             = 85.0;
input double  InpScoreValid               = 65.0;
input double  InpScoreLocalScalp          = 75.0;        // Deve restare >= VALID
input int     InpScoreD1                  = 20;
input int     InpScoreH4                  = 15;
input int     InpScoreH1                  = 10;
input int     InpScoreZoneStrength        = 15;
input int     InpScoreLiquidityGrab       = 10;
input int     InpScorePatternComplete     = 15;
input int     InpScoreM15Confirm          = 10;
input int     InpScoreCandleQuality       = 5;
input int     InpScoreVolumePressure      = 5;

input group "=== MOTORE BIAS (riferimento, solo contesto MTF) ==="
input int     InpEmaFastPeriod            = 50;
input int     InpEmaSlowPeriod            = 200;

//====================================================================
// ENUM / STRUCT
//====================================================================
enum ENUM_BIAS { BIAS_BULL, BIAS_BEAR, BIAS_NEUTRAL };
enum ENUM_PATTERN_ID
  {
   PAT_NONE=0, PAT_BREAKOUT, PAT_IMPULSIVE, PAT_TRENDFOLLOW, PAT_FAKEOUT, PAT_BREAKTREND
  };
enum ENUM_SETUP_TYPE { SETUP_NONE_T, SETUP_PREMIUM, SETUP_VALID, SETUP_LOCAL };

struct SCandleInfo
  {
   double         open, high, low, close;
   double         body, upperWick, lowerWick, range;
   double         bodyRatio, upperWickRatio, lowerWickRatio, closePos, openPos;
   bool           bullish;
   datetime       time;
   bool           valid;
  };

struct SZone
  {
   double         upper;
   double         lower;
   double         strength;     // 0..100
   int            touches;
   ENUM_TIMEFRAMES tf;
   datetime       createdTime;
   datetime       lastEvent;
   bool           valid;
  };

// Risultato dettagliato del rilevamento Liquidity Grab (mai un semplice bool)
struct SGrabResult
  {
   bool           found;
   ENUM_BIAS      direction;
   double         violatedLevel;      // livello S/R violato
   double         priorExtreme;       // massimo/minimo rilevante precedente (= violatedLevel per zone)
   double         penetrationPrice;   // estremo raggiunto dalla wick di penetrazione
   double         closePrice;         // chiusura della candela di grab
   double         wickSizePips;       // dimensione della wick di penetrazione, in pip
   bool           cameBack;           // rientro nella zona (chiusura back-inside)
   bool           confirmed;          // conferma successiva coerente (se richiesta)
   string         detail;
  };

// Risultato dettagliato Pattern 5 - Break The Trend
struct SBreakTrendResult
  {
   bool           engulfingPresent;
   bool           engulfingValid;      // engulfing + arrivo su zona S/R contro-trend
   bool           triggerIdentified;
   double         triggerLevel;
   bool           triggerBroken;
   bool           tradeAuthorized;
   string         detail;
  };

// Risultato dettagliato Pattern 3 - Trend Follow
struct STrendFollowResult
  {
   bool           impulse;
   bool           pullback;
   bool           zoneReached;
   bool           reaction;
   bool           continuation;
   double         impulseDisplacementPrice; // usato per il TP (estensione del trend)
   string         detail;
  };

struct SPatternOutput
  {
   bool           found;
   ENUM_PATTERN_ID id;
   ENUM_BIAS      direction;
   double         entry;
   double         slRaw;
   bool           m15Confirm;
   bool           liquidityGrab;
   double         auxDisplacement;   // riuso: displacement impulso (Trend Follow) per il TP
   string         detail;
   string         debugFields;       // campi diagnostici per il log (Engulfing=, TriggerBreak=, Impulse=, ecc.)
  };

//====================================================================
// GLOBAL STATE
//====================================================================
string   g_executedSetupIDs[];         // SetupID gia' eseguiti (anti-duplicati)
int      g_tradesToday   = 0;
string   g_currentItalianDay = "";     // "YYYY.MM.DD" giorno italiano corrente
datetime g_lastBarTimeM15 = 0;

//====================================================================
// UTILITY: PIP / POINT
//====================================================================
double GetPipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(digits==3 || digits==5)
      return point*10.0;
   return point;
  }

double PriceToPips(double priceDelta)
  {
   double pip = GetPipSize();
   if(pip<=0.0) return 0.0;
   return priceDelta/pip; // con segno: chi chiama decide se usare MathAbs
  }

double PipsToPrice(double pips)
  {
   return pips*GetPipSize();
  }

//====================================================================
// UTILITY: TIMEZONE ITALIA (Europe/Rome, CET/CEST)
//====================================================================
bool IsEuDstActive(datetime utcTime)
  {
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);
   int year = dt.year;

   datetime marchLastSunday = 0;
   for(int d=31; d>=25; d--)
     {
      MqlDateTime t; t.year=year; t.mon=3; t.day=d; t.hour=1; t.min=0; t.sec=0;
      datetime cand = StructToTime(t);
      MqlDateTime chk; TimeToStruct(cand, chk);
      if(chk.day_of_week==0) { marchLastSunday = cand; break; }
     }
   datetime octLastSunday = 0;
   for(int d=31; d>=25; d--)
     {
      MqlDateTime t; t.year=year; t.mon=10; t.day=d; t.hour=1; t.min=0; t.sec=0;
      datetime cand = StructToTime(t);
      MqlDateTime chk; TimeToStruct(cand, chk);
      if(chk.day_of_week==0) { octLastSunday = cand; break; }
     }
   if(marchLastSunday==0 || octLastSunday==0)
      return false;

   return (utcTime>=marchLastSunday && utcTime<octLastSunday);
  }

datetime GetItalianTime()
  {
   datetime serverTime = TimeCurrent();
   int serverOffsetHours = InpBrokerGmtOffsetHoursWin;
   if(InpBrokerAppliesDST)
     {
      datetime approxUtc = serverTime - InpBrokerGmtOffsetHoursWin*3600;
      if(IsEuDstActive(approxUtc))
         serverOffsetHours = InpBrokerGmtOffsetHoursSum;
     }
   datetime utcTime = serverTime - serverOffsetHours*3600;

   int italyOffsetHours = 1; // CET
   if(IsEuDstActive(utcTime))
      italyOffsetHours = 2;  // CEST

   return utcTime + italyOffsetHours*3600;
  }

string ItalianDayKey(datetime italianTime)
  {
   MqlDateTime dt;
   TimeToStruct(italianTime, dt);
   return StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
  }

bool IsWithinTradingWindow(datetime italianTime)
  {
   MqlDateTime dt;
   TimeToStruct(italianTime, dt);
   int hour = dt.hour;
   return (hour>=InpTradingStartHour && hour<InpTradingEndHour);
  }

void ResetDailyCounterIfNeeded()
  {
   datetime itNow = GetItalianTime();
   string key = ItalianDayKey(itNow);
   if(key != g_currentItalianDay)
     {
      g_currentItalianDay = key;
      g_tradesToday = 0;
      ArrayResize(g_executedSetupIDs, 0);
      LogMsg(StringFormat("[DAILY RESET] Nuovo giorno italiano: %s", key));
     }
  }

//====================================================================
// LOGGING
//====================================================================
void LogMsg(string msg) { Print(msg); }
void LogDebug(string msg) { if(InpDebugMode) Print("[DEBUG] ", msg); }

void LogDecision(string outcome, string reason, string details)
  {
   Print(StringFormat("[DECISION] %s | Reason=%s | %s", outcome, reason, details));
  }

//====================================================================
// ANALYSIS: CANDLE ANATOMY
//====================================================================
SCandleInfo GetCandleInfo(ENUM_TIMEFRAMES tf, int shift)
  {
   SCandleInfo c;
   c.valid = false;
   if(shift<0) return c;                 // shift<0 = barra in formazione: mai usata (InpUseCloseBarsOnly)

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, shift, 1, rates);
   if(copied<1) return c;

   c.open  = rates[0].open;
   c.high  = rates[0].high;
   c.low   = rates[0].low;
   c.close = rates[0].close;
   c.time  = rates[0].time;
   c.range = c.high - c.low;
   if(c.range<=0.0) return c;

   c.body       = MathAbs(c.close - c.open);
   c.upperWick  = c.high - MathMax(c.open, c.close);
   c.lowerWick  = MathMin(c.open, c.close) - c.low;
   c.bodyRatio       = c.body / c.range;
   c.upperWickRatio  = c.upperWick / c.range;
   c.lowerWickRatio  = c.lowerWick / c.range;
   c.closePos   = (c.close - c.low) / c.range;
   c.openPos    = (c.open  - c.low) / c.range;
   c.bullish    = (c.close > c.open);
   c.valid      = true;
   return c;
  }

double GetAverageRange(ENUM_TIMEFRAMES tf, int shiftStart, int period)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, shiftStart, period, rates);
   if(copied<period) return 0.0;
   double sum=0.0;
   for(int i=0;i<copied;i++)
      sum += (rates[i].high - rates[i].low);
   return sum/copied;
  }

bool IsDoji(const SCandleInfo &c)
  {
   if(!c.valid) return false;
   return (c.bodyRatio <= InpDojiBodyRatio);
  }

bool IsLongCandle(ENUM_TIMEFRAMES tf, int shift, const SCandleInfo &c)
  {
   if(!c.valid) return false;
   double avg = GetAverageRange(tf, shift+1, InpAvgRangePeriod);
   if(avg<=0.0) return false;
   return (c.range > avg*InpLongCandleMultiplier);
  }

// Marubozu (candela senza wick finale)
bool IsBullMarubozuEnd(const SCandleInfo &c)
  {
   if(!c.valid || !c.bullish) return false;
   return (c.upperWickRatio<=InpNoWickThreshold && c.closePos>=InpCloseNearExtreme);
  }
bool IsBearMarubozuEnd(const SCandleInfo &c)
  {
   if(!c.valid || c.bullish) return false;
   return (c.lowerWickRatio<=InpNoWickThreshold && c.closePos<=(1.0-InpCloseNearExtreme));
  }

// Candela senza wick iniziale
bool IsBullNoWickStart(const SCandleInfo &c)
  {
   if(!c.valid || !c.bullish) return false;
   return (c.openPos<=InpNoWickThreshold && c.bodyRatio>=0.5);
  }
bool IsBearNoWickStart(const SCandleInfo &c)
  {
   if(!c.valid || c.bullish) return false;
   return (c.openPos>=(1.0-InpNoWickThreshold) && c.bodyRatio>=0.5);
  }

bool IsRejectionWickUp(const SCandleInfo &c)
  {
   if(!c.valid) return false;
   return (c.upperWickRatio >= InpRejectionWickRatio);
  }
bool IsRejectionWickDown(const SCandleInfo &c)
  {
   if(!c.valid) return false;
   return (c.lowerWickRatio >= InpRejectionWickRatio);
  }

// Engulfing: SOLO corpi (open/close), mai le wick
bool IsBullishEngulfing(const SCandleInfo &prev, const SCandleInfo &cur)
  {
   if(!prev.valid || !cur.valid) return false;
   if(prev.bullish) return false;
   if(!cur.bullish) return false;
   double prevBodyTop = MathMax(prev.open, prev.close);
   double prevBodyBot = MathMin(prev.open, prev.close);
   double curBodyTop  = MathMax(cur.open, cur.close);
   double curBodyBot  = MathMin(cur.open, cur.close);
   return (curBodyBot<=prevBodyBot && curBodyTop>=prevBodyTop);
  }
bool IsBearishEngulfing(const SCandleInfo &prev, const SCandleInfo &cur)
  {
   if(!prev.valid || !cur.valid) return false;
   if(!prev.bullish) return false;
   if(cur.bullish) return false;
   double prevBodyTop = MathMax(prev.open, prev.close);
   double prevBodyBot = MathMin(prev.open, prev.close);
   double curBodyTop  = MathMax(cur.open, cur.close);
   double curBodyBot  = MathMin(cur.open, cur.close);
   return (curBodyBot<=prevBodyBot && curBodyTop>=prevBodyTop);
  }

// Wick Fill: reazione a una wick precedente significativa, coerente con la direzione data
bool IsWickFill(ENUM_TIMEFRAMES tf, int shift, ENUM_BIAS direction)
  {
   SCandleInfo prev = GetCandleInfo(tf, shift+1);
   SCandleInfo cur  = GetCandleInfo(tf, shift);
   if(!prev.valid || !cur.valid) return false;

   if(direction==BIAS_BULL)
     {
      if(prev.lowerWickRatio < InpRejectionWickRatio) return false;
      double wickBodyLevel = MathMin(prev.open, prev.close);
      return (cur.close > wickBodyLevel && cur.bullish);
     }
   if(direction==BIAS_BEAR)
     {
      if(prev.upperWickRatio < InpRejectionWickRatio) return false;
      double wickBodyLevel = MathMax(prev.open, prev.close);
      return (cur.close < wickBodyLevel && !cur.bullish);
     }
   return false;
  }

//====================================================================
// ANALYSIS: ZONE S/R (fractal + clustering) - solo shift>=1, no look-ahead
//====================================================================
bool IsFractalHigh(ENUM_TIMEFRAMES tf, int shift, int wing)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int total = wing*2+1;
   if(CopyRates(_Symbol, tf, shift-wing, total, r)<total) return false;
   double centerHigh = r[wing].high;
   for(int i=0;i<total;i++)
     {
      if(i==wing) continue;
      if(r[i].high >= centerHigh) return false;
     }
   return true;
  }
bool IsFractalLow(ENUM_TIMEFRAMES tf, int shift, int wing)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int total = wing*2+1;
   if(CopyRates(_Symbol, tf, shift-wing, total, r)<total) return false;
   double centerLow = r[wing].low;
   for(int i=0;i<total;i++)
     {
      if(i==wing) continue;
      if(r[i].low <= centerLow) return false;
     }
   return true;
  }

int BuildZones(ENUM_TIMEFRAMES tf, int lookback, SZone &zones[])
  {
   ArrayResize(zones, 0);
   double clusterDist = PipsToPrice(InpZoneClusterPips);
   int wing = InpFractalWing;
   int shiftMin = wing+1;

   double levels[]; ArrayResize(levels, 0);
   datetime times[]; ArrayResize(times, 0);

   for(int s=shiftMin; s<lookback; s++)
     {
      if(IsFractalHigh(tf, s, wing))
        {
         MqlRates r[]; ArraySetAsSeries(r, true);
         if(CopyRates(_Symbol, tf, s, 1, r)==1)
           {
            int n=ArraySize(levels);
            ArrayResize(levels, n+1); ArrayResize(times, n+1);
            levels[n]=r[0].high; times[n]=r[0].time;
           }
        }
      if(IsFractalLow(tf, s, wing))
        {
         MqlRates r[]; ArraySetAsSeries(r, true);
         if(CopyRates(_Symbol, tf, s, 1, r)==1)
           {
            int n=ArraySize(levels);
            ArrayResize(levels, n+1); ArrayResize(times, n+1);
            levels[n]=r[0].low; times[n]=r[0].time;
           }
        }
     }

   int nLevels = ArraySize(levels);
   bool used[]; ArrayResize(used, nLevels); ArrayInitialize(used, false);

   for(int i=0;i<nLevels;i++)
     {
      if(used[i]) continue;
      int count=1;
      double minL=levels[i], maxL=levels[i];
      datetime oldest=times[i], newest=times[i];
      used[i]=true;
      for(int j=i+1;j<nLevels;j++)
        {
         if(used[j]) continue;
         if(MathAbs(levels[j]-levels[i])<=clusterDist)
           {
            used[j]=true; count++;
            if(levels[j]<minL) minL=levels[j];
            if(levels[j]>maxL) maxL=levels[j];
            if(times[j]<oldest) oldest=times[j];
            if(times[j]>newest) newest=times[j];
           }
        }
      SZone z;
      z.upper = maxL;
      z.lower = minL;
      if(z.upper==z.lower)
        {
         double pad = PipsToPrice(2.0);
         z.upper += pad/2.0; z.lower -= pad/2.0;
        }
      z.touches = count;
      z.tf = tf;
      z.createdTime = oldest;
      z.lastEvent = newest;
      // Forza: funzione di eta' e NUMERO DI TOCCHI REALI. Una zona con un solo tocco
      // resta debole per definizione (nessun bonus "forte" automatico).
      double ageBars = (double)((TimeCurrent()-oldest)/PeriodSeconds(tf));
      double ageScore = MathMin(ageBars/50.0, 1.0)*30.0;      // max 30 punti da eta'
      double touchScore = MathMin((double)count/(double)InpZoneMinTouchesStrong, 1.0)*70.0; // max 70 da tocchi
      z.strength = MathMin(ageScore+touchScore, 100.0);
      if(count<2) z.strength = MathMin(z.strength, 30.0); // un solo tocco -> forza tetto basso
      z.valid = true;

      int zn=ArraySize(zones);
      ArrayResize(zones, zn+1);
      zones[zn]=z;
     }
   return ArraySize(zones);
  }

bool FindNearestZone(const SZone &zones[], double price, SZone &outZone)
  {
   int n=ArraySize(zones);
   if(n==0) return false;
   double bestDist = -1;
   int bestIdx = -1;
   for(int i=0;i<n;i++)
     {
      double mid = (zones[i].upper+zones[i].lower)/2.0;
      double dist = MathAbs(price-mid);
      if(bestIdx==-1 || dist<bestDist) { bestDist=dist; bestIdx=i; }
     }
   if(bestIdx==-1) return false;
   outZone = zones[bestIdx];
   return true;
  }

int MergeZones(const SZone &a[], const SZone &b[], SZone &outMerged[])
  {
   int na=ArraySize(a), nb=ArraySize(b);
   ArrayResize(outMerged, na+nb);
   for(int i=0;i<na;i++) outMerged[i]=a[i];
   for(int i=0;i<nb;i++) outMerged[na+i]=b[i];
   return ArraySize(outMerged);
  }

// Prossima zona S/R oltre l'entry, nella direzione del trade, entro un limite pip e con un minimo pip
// (usato per il TP di Breakout, Break The Trend, Trend Follow-fallback, Fake Out)
bool FindNextZoneTarget(const SZone &zones[], double entry, ENUM_BIAS dir, double maxPips, double minPips, double &targetPrice)
  {
   int n=ArraySize(zones);
   bool found=false; double bestDistPips=0.0; double bestPrice=0.0;
   for(int i=0;i<n;i++)
     {
      double level = (dir==BIAS_BULL) ? zones[i].lower : zones[i].upper; // primo lato incontrato
      bool ahead = (dir==BIAS_BULL) ? (level > entry) : (level < entry);
      if(!ahead) continue;
      double distPips = MathAbs(PriceToPips(level-entry));
      if(distPips < minPips) continue;
      if(distPips > maxPips) continue;
      if(!found || distPips < bestDistPips) { found=true; bestDistPips=distPips; bestPrice=level; }
     }
   if(found) targetPrice=bestPrice;
   return found;
  }

//====================================================================
// ANALYSIS: BIAS MTF (riferimento EMA - SOLO contesto, mai sostituto di condizioni strutturali)
//====================================================================
ENUM_BIAS GetBias(ENUM_TIMEFRAMES tf)
  {
   int hFast = iMA(_Symbol, tf, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   int hSlow = iMA(_Symbol, tf, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE) return BIAS_NEUTRAL;

   double fastBuf[], slowBuf[];
   ArraySetAsSeries(fastBuf, true);
   ArraySetAsSeries(slowBuf, true);

   if(CopyBuffer(hFast, 0, 1, 3, fastBuf)<3 || CopyBuffer(hSlow, 0, 1, 3, slowBuf)<3)
      return BIAS_NEUTRAL;

   SCandleInfo c1 = GetCandleInfo(tf, 1);
   if(!c1.valid) return BIAS_NEUTRAL;

   bool fastRising  = (fastBuf[0] > fastBuf[2]);
   bool fastFalling = (fastBuf[0] < fastBuf[2]);

   if(c1.close > fastBuf[0] && fastBuf[0] > slowBuf[0] && fastRising)  return BIAS_BULL;
   if(c1.close < fastBuf[0] && fastBuf[0] < slowBuf[0] && fastFalling) return BIAS_BEAR;
   return BIAS_NEUTRAL;
  }

string BiasToString(ENUM_BIAS b)
  {
   if(b==BIAS_BULL) return "BULLISH";
   if(b==BIAS_BEAR) return "BEARISH";
   return "NEUTRAL";
  }

//====================================================================
// ANALYSIS: LIQUIDITY GRAB (dettagliato, distinto dal vero breakout)
//====================================================================
SGrabResult DetectLiquidityGrabDetailed(ENUM_TIMEFRAMES tf, const SZone &zone, ENUM_BIAS expectedReversalDir)
  {
   SGrabResult res;
   res.found=false; res.direction=expectedReversalDir; res.violatedLevel=0; res.priorExtreme=0;
   res.penetrationPrice=0; res.closePrice=0; res.wickSizePips=0; res.cameBack=false; res.confirmed=false;
   res.detail="";

   int lookback = 8;
   for(int s=1; s<=lookback; s++)
     {
      SCandleInfo c = GetCandleInfo(tf, s);
      if(!c.valid) continue;

      if(expectedReversalDir==BIAS_BULL)
        {
         double priorLow = zone.lower;                    // (1) massimo/minimo rilevante = bound della zona
         bool penetrated = (c.low < priorLow);             // (2) penetrazione/superamento
         if(!penetrated) continue;
         bool notMaintained = (c.close >= priorLow);        // (4) mancato mantenimento oltre il livello
         if(!notMaintained) continue;                       // se chiude stabile oltre -> vero breakout, non grab

         bool confirmed = true;
         if(InpRequireGrabConfirmation)
           {
            confirmed=false;
            for(int cs=s-1; cs>=MathMax(1,s-2); cs--)
              {
               SCandleInfo cc = GetCandleInfo(tf, cs);
               if(cc.valid && cc.bullish) { confirmed=true; break; }
              }
           }

         res.found=true; res.violatedLevel=priorLow; res.priorExtreme=priorLow;
         res.penetrationPrice=c.low; res.closePrice=c.close;
         res.wickSizePips=MathAbs(PriceToPips(priorLow-c.low));
         res.cameBack=true; res.confirmed=confirmed;
         res.detail=StringFormat("Grab BUY: livello=%.2f penetrazione_low=%.2f chiusura=%.2f wick=%.1fp conferma=%s",
                     priorLow, c.low, c.close, res.wickSizePips, confirmed?"YES":"NO");
         return res;
        }
      else if(expectedReversalDir==BIAS_BEAR)
        {
         double priorHigh = zone.upper;
         bool penetrated = (c.high > priorHigh);
         if(!penetrated) continue;
         bool notMaintained = (c.close <= priorHigh);
         if(!notMaintained) continue;

         bool confirmed = true;
         if(InpRequireGrabConfirmation)
           {
            confirmed=false;
            for(int cs=s-1; cs>=MathMax(1,s-2); cs--)
              {
               SCandleInfo cc = GetCandleInfo(tf, cs);
               if(cc.valid && !cc.bullish) { confirmed=true; break; }
              }
           }

         res.found=true; res.violatedLevel=priorHigh; res.priorExtreme=priorHigh;
         res.penetrationPrice=c.high; res.closePrice=c.close;
         res.wickSizePips=MathAbs(PriceToPips(c.high-priorHigh));
         res.cameBack=true; res.confirmed=confirmed;
         res.detail=StringFormat("Grab SELL: livello=%.2f penetrazione_high=%.2f chiusura=%.2f wick=%.1fp conferma=%s",
                     priorHigh, c.high, c.close, res.wickSizePips, confirmed?"YES":"NO");
         return res;
        }
     }
   res.detail = "Nessun liquidity grab rilevato (nessuna penetrazione con rientro nella finestra analizzata)";
   return res;
  }

//====================================================================
// PATTERN DETECTION
//====================================================================
void InitPatternOutput(SPatternOutput &p)
  {
   p.found=false; p.id=PAT_NONE; p.direction=BIAS_NEUTRAL;
   p.entry=0; p.slRaw=0; p.m15Confirm=false; p.liquidityGrab=false;
   p.auxDisplacement=0; p.detail=""; p.debugFields="";
  }

// ---- Pattern 1: BREAKOUT ----
bool DetectBreakout(const SZone &zone, SPatternOutput &out)
  {
   InitPatternOutput(out);
   SCandleInfo setupM15 = GetCandleInfo(PERIOD_M15, 1);
   if(!setupM15.valid) { out.debugFields="CandleData=NO"; return false; }

   double distUpperPips = PriceToPips(setupM15.close - zone.upper);
   double distLowerPips = PriceToPips(zone.lower - setupM15.close);

   if(setupM15.close > zone.upper && distUpperPips <= InpMaxZoneDistancePips)
     {
      out.found=true; out.id=PAT_BREAKOUT; out.direction=BIAS_BULL;
      out.entry = setupM15.close;
      out.slRaw = setupM15.low - PipsToPrice(InpStructSLBufferPips);
      out.m15Confirm = true;
      out.detail = "Breakout rialzista: chiusura sopra resistenza entro soglia zona";
      out.debugFields = StringFormat("CloseAboveZone=YES Dist=%.1fp", distUpperPips);
      return true;
     }
   if(setupM15.close < zone.lower && distLowerPips <= InpMaxZoneDistancePips)
     {
      out.found=true; out.id=PAT_BREAKOUT; out.direction=BIAS_BEAR;
      out.entry = setupM15.close;
      out.slRaw = setupM15.high + PipsToPrice(InpStructSLBufferPips);
      out.m15Confirm = true;
      out.detail = "Breakout ribassista: chiusura sotto supporto entro soglia zona";
      out.debugFields = StringFormat("CloseBelowZone=YES Dist=%.1fp", distLowerPips);
      return true;
     }
   out.debugFields = "BreakoutClose=NO";
   return false;
  }

// ---- Pattern 2: ENTRATA IMPULSIVA ----
bool DetectImpulsive(const SZone &zone, SPatternOutput &out)
  {
   InitPatternOutput(out);
   SCandleInfo m30 = GetCandleInfo(PERIOD_M30, 1);
   SCandleInfo m15 = GetCandleInfo(PERIOD_M15, 1);
   if(!m30.valid || !m15.valid) { out.debugFields="CandleData=NO"; return false; }

   double rangeSize = zone.upper - zone.lower;
   if(rangeSize<=0) { out.debugFields="RangeInvalid=YES"; return false; }
   double posInRange = (m30.close - zone.lower)/rangeSize;

   bool nearLow  = (posInRange <= 0.25);
   bool nearHigh = (posInRange >= 0.75);
   if(!nearLow && !nearHigh)
     {
      out.debugFields = StringFormat("PriceInRangePos=%.2f (centro range, no pattern)", posInRange);
      return false;
     }

   if(nearLow && IsBullMarubozuEnd(m30))
     {
      bool m15c = (m15.bullish && m15.bodyRatio>=0.4);
      out.found=m15c; out.id=PAT_IMPULSIVE; out.direction=BIAS_BULL;
      out.entry=m15.close;
      out.slRaw=zone.lower - PipsToPrice(InpStructSLBufferPips);
      out.m15Confirm=m15c;
      out.detail = "Reazione rialzista al limite basso del range (marubozu M30 + conferma M15)";
      out.debugFields = StringFormat("NearExtreme=LOW MarubozuM30=YES M15Confirm=%s", m15c?"YES":"NO");
      return m15c;
     }
   if(nearHigh && IsBearMarubozuEnd(m30))
     {
      bool m15c = (!m15.bullish && m15.bodyRatio>=0.4);
      out.found=m15c; out.id=PAT_IMPULSIVE; out.direction=BIAS_BEAR;
      out.entry=m15.close;
      out.slRaw=zone.upper + PipsToPrice(InpStructSLBufferPips);
      out.m15Confirm=m15c;
      out.detail = "Reazione ribassista al limite alto del range (marubozu M30 + conferma M15)";
      out.debugFields = StringFormat("NearExtreme=HIGH MarubozuM30=YES M15Confirm=%s", m15c?"YES":"NO");
      return m15c;
     }
   out.debugFields = "MarubozuM30=NO";
   return false;
  }

// ---- Pattern 3: TREND FOLLOW (impulso -> pullback -> zona -> reazione -> continuazione) ----
bool DetectTrendFollow(const SZone &zone, ENUM_BIAS higherBias, SPatternOutput &out, STrendFollowResult &dbg)
  {
   InitPatternOutput(out);
   dbg.impulse=false; dbg.pullback=false; dbg.zoneReached=false; dbg.reaction=false; dbg.continuation=false;
   dbg.impulseDisplacementPrice=0; dbg.detail="";

   if(higherBias==BIAS_NEUTRAL) { dbg.detail="Bias H1/H4 neutrale: nessun trend di riferimento"; return false; }

   double avgRange = GetAverageRange(PERIOD_M15, 1, InpAvgRangePeriod);
   if(avgRange<=0) { dbg.detail="Range medio M15 non disponibile"; return false; }

   int minShift = InpPullbackMaxBars+InpContinuationMaxBars+1;
   int maxLookback = InpImpulseBars + InpPullbackMaxBars + InpContinuationMaxBars + 6;

   int impulseEndShift = -1;
   double impulseDisplacement = 0.0;

   for(int startShift = maxLookback; startShift >= minShift+InpImpulseBars-1; startShift--)
     {
      int endShift = startShift - InpImpulseBars + 1;
      if(endShift < minShift) continue;
      SCandleInfo first = GetCandleInfo(PERIOD_M15, startShift);
      SCandleInfo last  = GetCandleInfo(PERIOD_M15, endShift);
      if(!first.valid || !last.valid) continue;
      double disp = last.close - first.open;
      if(higherBias==BIAS_BULL && disp > avgRange*InpImpulseMinMultiplier)
        { impulseEndShift = endShift; impulseDisplacement = disp; break; }
      if(higherBias==BIAS_BEAR && -disp > avgRange*InpImpulseMinMultiplier)
        { impulseEndShift = endShift; impulseDisplacement = disp; break; }
     }

   if(impulseEndShift==-1)
     { dbg.detail="Nessun impulso rilevato nella direzione del bias H1/H4"; return false; }
   dbg.impulse=true;
   dbg.impulseDisplacementPrice = impulseDisplacement;

   int pullbackExtremeShift = -1;
   double pullbackExtremePrice = 0.0;
   for(int s = impulseEndShift-1; s >= MathMax(1, impulseEndShift-InpPullbackMaxBars); s--)
     {
      SCandleInfo c = GetCandleInfo(PERIOD_M15, s);
      if(!c.valid) continue;
      if(higherBias==BIAS_BULL)
        { if(pullbackExtremeShift==-1 || c.low < pullbackExtremePrice) { pullbackExtremeShift=s; pullbackExtremePrice=c.low; } }
      else
        { if(pullbackExtremeShift==-1 || c.high > pullbackExtremePrice) { pullbackExtremeShift=s; pullbackExtremePrice=c.high; } }
     }
   if(pullbackExtremeShift==-1)
     { dbg.detail="Impulso rilevato ma nessun pullback identificabile"; return false; }
   dbg.pullback=true;

   double distToZonePips = (higherBias==BIAS_BULL) ? PriceToPips(pullbackExtremePrice - zone.lower)
                                                     : PriceToPips(zone.upper - pullbackExtremePrice);
   bool onZone = (MathAbs(distToZonePips) <= InpMaxZoneDistancePips) ||
                 (pullbackExtremePrice<=zone.upper && pullbackExtremePrice>=zone.lower);
   if(!onZone)
     { dbg.detail=StringFormat("Pullback non arriva sulla zona (distanza %.1f pips)", distToZonePips); return false; }
   dbg.zoneReached=true;

   SCandleInfo reactionCandle = GetCandleInfo(PERIOD_M15, pullbackExtremeShift);
   SCandleInfo reactionPrev   = GetCandleInfo(PERIOD_M15, pullbackExtremeShift+1);
   bool reactionOk=false;
   if(higherBias==BIAS_BULL)
      reactionOk = (reactionCandle.bullish && reactionCandle.closePos>=InpCloseNearExtreme) ||
                   IsBullishEngulfing(reactionPrev, reactionCandle) || IsRejectionWickDown(reactionCandle);
   else
      reactionOk = (!reactionCandle.bullish && reactionCandle.closePos<=(1.0-InpCloseNearExtreme)) ||
                   IsBearishEngulfing(reactionPrev, reactionCandle) || IsRejectionWickUp(reactionCandle);

   if(!reactionOk)
     { dbg.detail="Pullback sulla zona ma nessuna candela di reazione valida"; return false; }
   dbg.reaction=true;

   double continuationTrigger = (higherBias==BIAS_BULL) ? reactionCandle.high : reactionCandle.low;
   for(int s=pullbackExtremeShift-1; s>=MathMax(1,pullbackExtremeShift-InpContinuationMaxBars); s--)
     {
      SCandleInfo c = GetCandleInfo(PERIOD_M15, s);
      if(!c.valid) continue;
      if(higherBias==BIAS_BULL && c.close > continuationTrigger)
        {
         dbg.continuation=true;
         out.found=true; out.id=PAT_TRENDFOLLOW; out.direction=BIAS_BULL;
         out.entry=c.close;
         out.slRaw=pullbackExtremePrice - PipsToPrice(InpStructSLBufferPips);
         out.m15Confirm=true;
         out.auxDisplacement = MathAbs(impulseDisplacement);
         out.detail=StringFormat("Trend Follow BUY: impulso(%.1fp)+pullback su zona+reazione+continuazione a %.2f",
                     PriceToPips(impulseDisplacement), c.close);
         dbg.detail=out.detail;
         return true;
        }
      if(higherBias==BIAS_BEAR && c.close < continuationTrigger)
        {
         dbg.continuation=true;
         out.found=true; out.id=PAT_TRENDFOLLOW; out.direction=BIAS_BEAR;
         out.entry=c.close;
         out.slRaw=pullbackExtremePrice + PipsToPrice(InpStructSLBufferPips);
         out.m15Confirm=true;
         out.auxDisplacement = MathAbs(impulseDisplacement);
         out.detail=StringFormat("Trend Follow SELL: impulso(%.1fp)+pullback su zona+reazione+continuazione a %.2f",
                     MathAbs(PriceToPips(impulseDisplacement)), c.close);
         dbg.detail=out.detail;
         return true;
        }
     }
   dbg.detail="Reazione presente sulla zona ma continuazione non ancora confermata";
   return false;
  }

// ---- Pattern 4: FAKE OUT (richiede Liquidity Grab dettagliato + conferma M15 forte) ----
bool DetectFakeOut(const SZone &zone, SPatternOutput &out)
  {
   InitPatternOutput(out);
   SCandleInfo m30 = GetCandleInfo(PERIOD_M30, 1);
   SCandleInfo m15 = GetCandleInfo(PERIOD_M15, 1);
   SCandleInfo m15prev = GetCandleInfo(PERIOD_M15, 2);
   if(!m30.valid || !m15.valid) { out.debugFields="CandleData=NO"; return false; }

   SGrabResult grabBuy = DetectLiquidityGrabDetailed(PERIOD_M30, zone, BIAS_BULL);
   if(grabBuy.found && grabBuy.confirmed && (IsRejectionWickDown(m30) || IsBullMarubozuEnd(m30)))
     {
      bool m15Confirm = m15.bullish && (m15.closePos>=InpCloseNearExtreme || IsBullishEngulfing(m15prev, m15));
      out.debugFields = StringFormat("Grab=YES GrabConfirmed=YES WickPips=%.1f M15Confirm=%s", grabBuy.wickSizePips, m15Confirm?"YES":"NO");
      if(m15Confirm)
        {
         out.found=true; out.id=PAT_FAKEOUT; out.direction=BIAS_BULL;
         out.entry=m15.close;
         out.slRaw=MathMin(m30.low, m15.low) - PipsToPrice(InpStructSLBufferPips);
         out.liquidityGrab=true;
         out.m15Confirm=true;
         out.detail="Fake Out BUY: " + grabBuy.detail + "; conferma M15 forte presente";
         return true;
        }
      return false;
     }

   SGrabResult grabSell = DetectLiquidityGrabDetailed(PERIOD_M30, zone, BIAS_BEAR);
   if(grabSell.found && grabSell.confirmed && (IsRejectionWickUp(m30) || IsBearMarubozuEnd(m30)))
     {
      bool m15Confirm = !m15.bullish && (m15.closePos<=(1.0-InpCloseNearExtreme) || IsBearishEngulfing(m15prev, m15));
      out.debugFields = StringFormat("Grab=YES GrabConfirmed=YES WickPips=%.1f M15Confirm=%s", grabSell.wickSizePips, m15Confirm?"YES":"NO");
      if(m15Confirm)
        {
         out.found=true; out.id=PAT_FAKEOUT; out.direction=BIAS_BEAR;
         out.entry=m15.close;
         out.slRaw=MathMax(m30.high, m15.high) + PipsToPrice(InpStructSLBufferPips);
         out.liquidityGrab=true;
         out.m15Confirm=true;
         out.detail="Fake Out SELL: " + grabSell.detail + "; conferma M15 forte presente";
         return true;
        }
      return false;
     }

   out.debugFields = StringFormat("Grab=%s", (grabBuy.found||grabSell.found)?"YES(non_confermato)":"NO");
   return false;
  }

// ---- Pattern 5: BREAK THE TREND (engulfing valido + trigger identificato + rottura EFFETTIVA su barra chiusa) ----
bool DetectBreakTheTrend(const SZone &zone, ENUM_BIAS priorTrend, SPatternOutput &out, SBreakTrendResult &dbg)
  {
   InitPatternOutput(out);
   dbg.engulfingPresent=false; dbg.engulfingValid=false; dbg.triggerIdentified=false;
   dbg.triggerLevel=0; dbg.triggerBroken=false; dbg.tradeAuthorized=false; dbg.detail="";

   if(priorTrend==BIAS_NEUTRAL) { dbg.detail="Nessun trend precedente chiaro (H1/H4 neutrale)"; return false; }

   int lookback=12;
   for(int engShift=2; engShift<=lookback; engShift++)
     {
      SCandleInfo prev = GetCandleInfo(PERIOD_M15, engShift+1);
      SCandleInfo cur  = GetCandleInfo(PERIOD_M15, engShift);
      if(!prev.valid || !cur.valid) continue;

      bool isEngulf=false; bool bull=false;
      if(priorTrend==BIAS_BEAR) { isEngulf = IsBullishEngulfing(prev,cur); bull=true; }
      else                      { isEngulf = IsBearishEngulfing(prev,cur); bull=false; }
      if(!isEngulf) continue;

      dbg.engulfingPresent=true;

      bool onZone;
      double refPrice;
      if(bull)
        {
         refPrice = MathMin(prev.low, cur.low);
         double distPips = PriceToPips(refPrice - zone.lower);
         onZone = (MathAbs(distPips) <= InpMaxZoneDistancePips) || (refPrice<=zone.upper && refPrice>=zone.lower);
        }
      else
        {
         refPrice = MathMax(prev.high, cur.high);
         double distPips = PriceToPips(zone.upper - refPrice);
         onZone = (MathAbs(distPips) <= InpMaxZoneDistancePips) || (refPrice<=zone.upper && refPrice>=zone.lower);
        }

      if(!onZone) continue; // engulfing presente ma non su una zona S/R valida -> non "valido"

      dbg.engulfingValid=true;

      double triggerLevel = bull ? MathMax(prev.high,cur.high) : MathMin(prev.low,cur.low);
      dbg.triggerIdentified=true;
      dbg.triggerLevel=triggerLevel;

      // Rottura effettiva del trigger: SOLO su una candela M15 gia' CHIUSA e piu' recente dell'engulfing
      for(int s=engShift-1; s>=1; s--)
        {
         SCandleInfo brk = GetCandleInfo(PERIOD_M15, s);
         if(!brk.valid) continue;
         if(bull && brk.close > triggerLevel)
           {
            dbg.triggerBroken=true; dbg.tradeAuthorized=true;
            out.found=true; out.id=PAT_BREAKTREND; out.direction=BIAS_BULL;
            out.entry=brk.close;
            out.slRaw=MathMin(prev.low,cur.low)-PipsToPrice(InpStructSLBufferPips);
            out.m15Confirm=true;
            out.detail=StringFormat("Break The Trend BUY: engulfing valido su supporto, trigger %.2f rotto a chiusura %.2f", triggerLevel, brk.close);
            dbg.detail=out.detail;
            return true;
           }
         if(!bull && brk.close < triggerLevel)
           {
            dbg.triggerBroken=true; dbg.tradeAuthorized=true;
            out.found=true; out.id=PAT_BREAKTREND; out.direction=BIAS_BEAR;
            out.entry=brk.close;
            out.slRaw=MathMax(prev.high,cur.high)+PipsToPrice(InpStructSLBufferPips);
            out.m15Confirm=true;
            out.detail=StringFormat("Break The Trend SELL: engulfing valido su resistenza, trigger %.2f rotto a chiusura %.2f", triggerLevel, brk.close);
            dbg.detail=out.detail;
            return true;
           }
        }
      // Trigger identificato ma non rotto entro le barre disponibili: NO TRADE per questo pattern.
      // Non si autorizza il trade solo perche' l'engulfing e' presente (requisito necessario mancante).
      dbg.detail = StringFormat("Engulfing valido su zona, trigger %.2f identificato ma NON rotto: nessuna autorizzazione", triggerLevel);
      return false;
     }

   if(!dbg.engulfingPresent)
      dbg.detail="Nessun engulfing contro-trend rilevato nella finestra di analisi";
   else if(!dbg.engulfingValid)
      dbg.detail="Engulfing rilevato ma non in prossimita' di una zona S/R valida";
   return false;
  }

//====================================================================
// SCORING
//====================================================================
double ComputeScore(ENUM_BIAS d1, ENUM_BIAS h4, ENUM_BIAS h1, ENUM_BIAS setupDir,
                     const SZone &zone, bool liquidityGrab, bool patternComplete,
                     bool m15Confirm, bool candleQuality, bool volumePressure,
                     string &breakdown)
  {
   double score=0.0;
   breakdown="";

   if(d1==setupDir) { score+=InpScoreD1; breakdown+=StringFormat("D1(+%d) ", InpScoreD1); }
   if(h4==setupDir) { score+=InpScoreH4; breakdown+=StringFormat("H4(+%d) ", InpScoreH4); }
   if(h1==setupDir) { score+=InpScoreH1; breakdown+=StringFormat("H1(+%d) ", InpScoreH1); }

   bool zoneStrong = (zone.strength >= InpZoneStrongThreshold) || (zone.touches >= InpZoneMinTouchesStrong);
   if(zoneStrong) { score+=InpScoreZoneStrength; breakdown+=StringFormat("ZoneStrong(+%d) ", InpScoreZoneStrength); }

   if(liquidityGrab) { score+=InpScoreLiquidityGrab; breakdown+=StringFormat("LiquidityGrab(+%d) ", InpScoreLiquidityGrab); }
   if(patternComplete) { score+=InpScorePatternComplete; breakdown+=StringFormat("PatternComplete(+%d) ", InpScorePatternComplete); }
   if(m15Confirm) { score+=InpScoreM15Confirm; breakdown+=StringFormat("M15Confirm(+%d) ", InpScoreM15Confirm); }
   if(candleQuality) { score+=InpScoreCandleQuality; breakdown+=StringFormat("CandleQuality(+%d) ", InpScoreCandleQuality); }
   if(volumePressure) { score+=InpScoreVolumePressure; breakdown+=StringFormat("Volume(+%d) ", InpScoreVolumePressure); }

   return score;
  }

//====================================================================
// TP PER-PATTERN (mai un fallback generico automatico)
//====================================================================
bool ComputeTargetForPattern(ENUM_PATTERN_ID pid, ENUM_BIAS dir, double entry, const SZone &entryZone,
                              const SZone &allZones[], double impulseDisplacementPrice,
                              double maxTpPips, double minTpPips, double &tp, string &reason)
  {
   switch(pid)
     {
      case PAT_BREAKOUT:
      case PAT_BREAKTREND:
        {
         double cand;
         if(FindNextZoneTarget(allZones, entry, dir, maxTpPips, minTpPips, cand)) { tp=cand; return true; }
         reason = "nessuna zona S/R/liquidita' successiva compatibile entro il limite pip";
         return false;
        }

      case PAT_IMPULSIVE:
        {
         double cand = (dir==BIAS_BULL) ? entryZone.upper : entryZone.lower; // estremo opposto del range
         double distPips = MathAbs(PriceToPips(cand-entry));
         if(distPips<=maxTpPips && distPips>=minTpPips) { tp=cand; return true; }
         reason = "estremo opposto del range non compatibile col limite/RR pip";
         return false;
        }

      case PAT_TRENDFOLLOW:
        {
         double proj = (dir==BIAS_BULL) ? entry + MathAbs(impulseDisplacementPrice)
                                         : entry - MathAbs(impulseDisplacementPrice);
         double distPips = MathAbs(PriceToPips(proj-entry));
         if(distPips<=maxTpPips && distPips>=minTpPips) { tp=proj; return true; }
         // Fallback ESPLICITO e dichiarato: se l'estensione strutturale del trend non e' compatibile,
         // si cerca una zona S/R successiva entro il limite (non un multiplo di rischio generico).
         double cand;
         if(FindNextZoneTarget(allZones, entry, dir, maxTpPips, minTpPips, cand)) { tp=cand; return true; }
         reason = "estensione del trend non compatibile e nessuna zona alternativa entro il limite pip";
         return false;
        }

      case PAT_FAKEOUT:
        {
         double conservativeCap = maxTpPips * InpFakeOutTpConservativeFactor;
         double cand;
         if(FindNextZoneTarget(allZones, entry, dir, conservativeCap, minTpPips, cand)) { tp=cand; return true; }
         reason = "nessuna zona opposta compatibile entro il limite conservativo pip (Fake Out)";
         return false;
        }

      default:
         reason = "pattern non riconosciuto per il calcolo del TP";
         return false;
     }
  }

//====================================================================
// SETUP ID (anti-duplicati)
//====================================================================
string BuildSetupID(ENUM_PATTERN_ID pid, ENUM_BIAS dir, const SZone &zone, datetime setupBarTime)
  {
   return StringFormat("%s_%d_%d_%.2f_%.2f_%I64d",
                        _Symbol, (int)pid, (int)dir, zone.upper, zone.lower, (long)setupBarTime);
  }
bool IsSetupAlreadyExecuted(string setupID)
  {
   int n=ArraySize(g_executedSetupIDs);
   for(int i=0;i<n;i++) if(g_executedSetupIDs[i]==setupID) return true;
   return false;
  }
void MarkSetupExecuted(string setupID)
  {
   int n=ArraySize(g_executedSetupIDs);
   ArrayResize(g_executedSetupIDs, n+1);
   g_executedSetupIDs[n]=setupID;
  }

//====================================================================
// RISK VALIDATION: posizioni esistenti / volume / stop level / margine
//====================================================================
bool HasOpenPositionSameMagic()
  {
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      return true;
     }
   return false;
  }

bool ValidateVolume(double vol, double &validatedVol, string &reason)
  {
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(vol<minV || vol>maxV)
     { reason = StringFormat("volume %.2f fuori range broker [%.2f,%.2f]", vol, minV, maxV); return false; }

   double steps = (vol-minV)/stepV;
   double roundedSteps = MathRound(steps);
   if(MathAbs(steps-roundedSteps) > 0.0001)
     { reason = StringFormat("volume %.2f non allineato a VOLUME_STEP %.2f", vol, stepV); return false; }

   validatedVol = vol;
   return true;
  }

bool ValidateStopLevel(double entry, double sl, double tp, string &reason)
  {
   long stopLevelPoints   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist = MathMax(stopLevelPoints, freezeLevelPoints)*point;

   double slDist = MathAbs(entry-sl);
   double tpDist = MathAbs(entry-tp);

   if(minDist>0 && (slDist<minDist || tpDist<minDist))
     { reason = StringFormat("SL/TP sotto stop/freeze level broker (minimo %.5f)", minDist); return false; }
   return true;
  }

bool ValidateMargin(ENUM_ORDER_TYPE orderType, double volume, double price, string &reason)
  {
   double marginRequired=0.0;
   if(!OrderCalcMargin(orderType, _Symbol, volume, price, marginRequired))
     { reason = "errore calcolo margine (OrderCalcMargin)"; return false; }
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(marginRequired > freeMargin)
     { reason = StringFormat("margine insufficiente: richiesto %.2f, disponibile %.2f", marginRequired, freeMargin); return false; }
   return true;
  }

bool HasEnoughData(ENUM_TIMEFRAMES tf, int neededBars)
  {
   return (Bars(_Symbol, tf) >= neededBars);
  }

double GetCurrentSpreadPips()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return MathAbs(PriceToPips(ask-bid));
  }

//====================================================================
// NEW BAR (M15) - decisioni solo su barre chiuse
//====================================================================
bool IsNewM15Bar()
  {
   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, t)<1) return false;
   if(t[0]!=g_lastBarTimeM15) { g_lastBarTimeM15 = t[0]; return true; }
   return false;
  }

string PatternIdToString(ENUM_PATTERN_ID id)
  {
   switch(id)
     {
      case PAT_BREAKOUT:    return "BREAKOUT";
      case PAT_IMPULSIVE:   return "ENTRATA_IMPULSIVA";
      case PAT_TRENDFOLLOW: return "TREND_FOLLOW";
      case PAT_FAKEOUT:     return "FAKE_OUT";
      case PAT_BREAKTREND:  return "BREAK_THE_TREND";
      default: return "NONE";
     }
  }
string SetupTypeToString(ENUM_SETUP_TYPE t)
  {
   switch(t)
     {
      case SETUP_PREMIUM: return "PREMIUM";
      case SETUP_VALID:   return "VALID";
      case SETUP_LOCAL:   return "LOCAL_SCALP";
      default: return "NONE";
     }
  }

//====================================================================
// DECISION PIPELINE (ANALYSIS -> SCORING -> DECISION -> RISK -> EXECUTION -> LOG)
//====================================================================
void RunDecisionPipeline()
  {
   //--------------- FILTRI ASSOLUTI PRELIMINARI ---------------
   if(StringFind(_Symbol,"XAU")<0)
     { LogDecision("NO TRADE", "simbolo non valido per questa strategia", _Symbol); return; }

   datetime itNow = GetItalianTime();
   if(!IsWithinTradingWindow(itNow))
     { LogDecision("NO TRADE", "fuori finestra 07:00-12:00 Europe/Rome", TimeToString(itNow, TIME_MINUTES)); return; }

   if(g_tradesToday >= InpMaxTradesPerDay)
     { LogDecision("NO TRADE", StringFormat("limite giornaliero raggiunto (%d/%d)", g_tradesToday, InpMaxTradesPerDay), ""); return; }

   double spreadPips = GetCurrentSpreadPips();
   if(spreadPips > InpMaxSpreadPips)
     { LogDecision("NO TRADE", "spread eccessivo", StringFormat("%.1f > %.1f pips", spreadPips, InpMaxSpreadPips)); return; }

   if(!HasEnoughData(PERIOD_D1, 60) || !HasEnoughData(PERIOD_H4, 100) ||
      !HasEnoughData(PERIOD_H1, 100) || !HasEnoughData(PERIOD_M30, 100) ||
      !HasEnoughData(PERIOD_M15, InpAvgRangePeriod+50))
     { LogDecision("NO TRADE", "dati insufficienti su uno o piu' timeframe", ""); return; }

   if(HasOpenPositionSameMagic())
     { LogDecision("NO TRADE", "posizione EA gia' aperta sul simbolo (stesso Magic Number)", ""); return; }

   //--------------- ANALYSIS: ZONE ---------------
   SZone zonesH4[]; SZone zonesD1[]; SZone allZones[];
   BuildZones(PERIOD_H4, InpZoneLookbackBarsH4, zonesH4);
   BuildZones(PERIOD_D1, InpZoneLookbackBarsD1, zonesD1);
   MergeZones(zonesH4, zonesD1, allZones);

   if(ArraySize(zonesH4)==0)
     { LogDecision("NO TRADE", "nessuna zona S/R valida identificata su H4", ""); return; }

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   SZone zone;
   if(!FindNearestZone(zonesH4, currentPrice, zone))
     { LogDecision("NO TRADE", "nessuna zona di riferimento trovata vicino al prezzo", ""); return; }

   double zoneMid = (zone.upper+zone.lower)/2.0;
   double distZonePips = MathAbs(PriceToPips(currentPrice - zoneMid));
   if(distZonePips > InpMaxZoneDistancePips*4)
     { LogDecision("NO TRADE", StringFormat("distanza zona %.1f pips eccessiva anche per screening iniziale", distZonePips), ""); return; }

   //--------------- ANALYSIS: BIAS MTF ---------------
   ENUM_BIAS biasD1 = GetBias(PERIOD_D1);
   ENUM_BIAS biasH4 = GetBias(PERIOD_H4);
   ENUM_BIAS biasH1 = GetBias(PERIOD_H1);
   ENUM_BIAS higherBiasForTrend = (biasH1!=BIAS_NEUTRAL) ? biasH1 : ((biasH4!=BIAS_NEUTRAL) ? biasH4 : biasD1);

   LogDebug(StringFormat("Bias D1=%s H4=%s H1=%s | Zona [%.2f-%.2f] forza=%.1f tocchi=%d",
            BiasToString(biasD1), BiasToString(biasH4), BiasToString(biasH1),
            zone.lower, zone.upper, zone.strength, zone.touches));

   //--------------- ANALYSIS: PATTERN (valutati TUTTI, per diagnostica completa anche in NO TRADE) ---------------
   SPatternOutput pBreakTrend; SBreakTrendResult dbgBreakTrend;
   bool foundBreakTrend = DetectBreakTheTrend(zone, higherBiasForTrend, pBreakTrend, dbgBreakTrend);

   SPatternOutput pFake;
   bool foundFake = DetectFakeOut(zone, pFake);

   SPatternOutput pTrend; STrendFollowResult dbgTrend;
   bool foundTrend = DetectTrendFollow(zone, higherBiasForTrend, pTrend, dbgTrend);

   SPatternOutput pBreak;
   bool foundBreak = DetectBreakout(zone, pBreak);

   SPatternOutput pImp;
   bool foundImp = DetectImpulsive(zone, pImp);

   // Priorita': Break The Trend > Fake Out > Trend Follow > Breakout > Impulsiva
   SPatternOutput best; InitPatternOutput(best);
   string extraDebug = "";
   if(foundBreakTrend)      { best=pBreakTrend; extraDebug=StringFormat("Engulfing=%s TriggerIdentified=%s TriggerBreak=%s",
                                    dbgBreakTrend.engulfingValid?"YES":(dbgBreakTrend.engulfingPresent?"YES(non_valido)":"NO"),
                                    dbgBreakTrend.triggerIdentified?"YES":"NO", dbgBreakTrend.triggerBroken?"YES":"NO"); }
   else if(foundFake)       { best=pFake; extraDebug=pFake.debugFields; }
   else if(foundTrend)      { best=pTrend; extraDebug=StringFormat("Impulse=%s Pullback=%s Zone=%s Reaction=%s Continuation=%s",
                                    dbgTrend.impulse?"YES":"NO", dbgTrend.pullback?"YES":"NO", dbgTrend.zoneReached?"YES":"NO",
                                    dbgTrend.reaction?"YES":"NO", dbgTrend.continuation?"YES":"NO"); }
   else if(foundBreak)      { best=pBreak; extraDebug=pBreak.debugFields; }
   else if(foundImp)        { best=pImp; extraDebug=pImp.debugFields; }

   if(!best.found)
     {
      string diagnostics = StringFormat(
         "BreakTheTrend[Engulfing=%s Valid=%s TriggerBreak=%s: %s] | FakeOut[%s: %s] | TrendFollow[Impulse=%s Pullback=%s Zone=%s Reaction=%s Continuation=%s: %s] | Breakout[%s] | Impulsive[%s]",
         dbgBreakTrend.engulfingPresent?"YES":"NO", dbgBreakTrend.engulfingValid?"YES":"NO", dbgBreakTrend.triggerBroken?"YES":"NO", dbgBreakTrend.detail,
         pFake.debugFields, pFake.detail,
         dbgTrend.impulse?"YES":"NO", dbgTrend.pullback?"YES":"NO", dbgTrend.zoneReached?"YES":"NO", dbgTrend.reaction?"YES":"NO", dbgTrend.continuation?"YES":"NO", dbgTrend.detail,
         pBreak.debugFields, pImp.debugFields);
      LogDecision("NO TRADE", "nessun pattern completo (requisiti strutturali non soddisfatti)", diagnostics);
      return;
     }

   //--------------- Distance From Zone sull'entry effettivo ---------------
   double entryDistPips = MathAbs(PriceToPips(best.entry - zoneMid));
   if(entryDistPips > InpMaxZoneDistancePips)
     { LogDecision("NO TRADE", StringFormat("distanza zona %.1f pips > %.1f pips", entryDistPips, InpMaxZoneDistancePips), PatternIdToString(best.id)); return; }

   //--------------- Anatomia candela di setup: long candle -> non inseguire ---------------
   SCandleInfo setupCandle = GetCandleInfo(PERIOD_M15, 1);
   if(IsLongCandle(PERIOD_M15, 1, setupCandle))
     {
      double chaseDistPips = MathAbs(PriceToPips(best.entry - (best.direction==BIAS_BULL? setupCandle.low: setupCandle.high)));
      if(chaseDistPips > InpMaxZoneDistancePips)
        { LogDecision("NO TRADE", "candela troppo lunga: ingresso richiederebbe inseguire il prezzo", PatternIdToString(best.id)); return; }
     }

   //--------------- SCORING ---------------
   bool liquidityGrabForScore = best.liquidityGrab || DetectLiquidityGrabDetailed(PERIOD_H1, zone, best.direction).found;
   SCandleInfo prevM15forQuality = GetCandleInfo(PERIOD_M15, 2);
   bool candleQuality = (best.direction==BIAS_BULL && (IsBullMarubozuEnd(setupCandle) || IsBullNoWickStart(setupCandle))) ||
                         (best.direction==BIAS_BEAR && (IsBearMarubozuEnd(setupCandle) || IsBearNoWickStart(setupCandle))) ||
                         IsBullishEngulfing(prevM15forQuality, setupCandle) ||
                         IsBearishEngulfing(prevM15forQuality, setupCandle) ||
                         IsWickFill(PERIOD_M15, 1, best.direction);
   bool volumePressure = false; // tick volume non affidabile su molti broker CFD oro: disattivo di default

   //--------------- Doji: mai un segnale da solo, deve essere gestito secondo il contesto ---------------
   // (spec: Doji nel mezzo del range o su zona SENZA altre conferme forti -> nessun segnale sufficiente)
   bool candleIsDoji = IsDoji(setupCandle);
   if(candleIsDoji && !liquidityGrabForScore && !candleQuality)
     {
      LogDecision("NO TRADE", "Doji sulla candela di setup senza conferma indipendente (liquidity grab/engulfing/marubozu/wick fill)",
                  StringFormat("Pattern=%s BodyRatio=%.2f", PatternIdToString(best.id), setupCandle.bodyRatio));
      return;
     }

   string breakdown;
   double score = ComputeScore(biasD1, biasH4, biasH1, best.direction, zone,
                                liquidityGrabForScore, true, best.m15Confirm, candleQuality, volumePressure, breakdown);

   //--------------- DECISION: categoria setup ---------------
   bool mtfConfirmed = (biasD1==best.direction && biasH4==best.direction) ||
                        (biasH1==best.direction && biasH4==best.direction);

   ENUM_SETUP_TYPE setupType = SETUP_NONE_T;
   if(mtfConfirmed && score>=InpScorePremium)       setupType = SETUP_PREMIUM;
   else if(mtfConfirmed && score>=InpScoreValid)     setupType = SETUP_VALID;
   else if(!mtfConfirmed && zone.strength>=InpZoneStrongThreshold && (liquidityGrabForScore || candleQuality) &&
           best.m15Confirm && score>=InpScoreLocalScalp) setupType = SETUP_LOCAL;

   if(setupType==SETUP_NONE_T)
     {
      LogDecision("NO TRADE", StringFormat("score %.0f insufficiente per categoria valida (MTF confermato=%s)", score, mtfConfirmed?"si":"no"),
                  StringFormat("Pattern=%s %s | %s", PatternIdToString(best.id), extraDebug, breakdown));
      return;
     }

   //--------------- RISK VALIDATION: SL ---------------
   double entry = best.entry;
   double sl = best.slRaw;
   double slDistPips = MathAbs(PriceToPips(entry-sl));

   double maxSlPips = (setupType==SETUP_LOCAL) ? InpMaxSLPips*InpLocalScalpRiskFactor : InpMaxSLPips;
   double maxTpPips  = (setupType==SETUP_LOCAL) ? InpMaxTPPips*InpLocalScalpRiskFactor : InpMaxTPPips;

   if(slDistPips<=0)
     { LogDecision("NO TRADE", "SL strutturale non valido (distanza nulla o negativa)", PatternIdToString(best.id)); return; }
   if(slDistPips > maxSlPips)
     { LogDecision("NO TRADE", StringFormat("SL strutturale %.1f pips > limite %.1f pips, nessun setup alternativo con SL piu' vicino", slDistPips, maxSlPips), PatternIdToString(best.id)); return; }

   //--------------- RISK VALIDATION: TP specifico per pattern ---------------
   double minTpPipsForRR = slDistPips*InpMinRR;
   double tp; string tpReason;
   if(!ComputeTargetForPattern(best.id, best.direction, entry, zone, allZones, best.auxDisplacement,
                                maxTpPips, minTpPipsForRR, tp, tpReason))
     { LogDecision("NO TRADE", "TP: "+tpReason, PatternIdToString(best.id)); return; }

   double tpDistPips = MathAbs(PriceToPips(tp-entry));
   if(tpDistPips > maxTpPips)
     { LogDecision("NO TRADE", StringFormat("TP %.1f pips > limite %.1f pips, nessun target compatibile", tpDistPips, maxTpPips), PatternIdToString(best.id)); return; }

   //--------------- RISK VALIDATION: R:R ---------------
   double rr = tpDistPips / slDistPips;
   if(rr < InpMinRR)
     { LogDecision("NO TRADE", StringFormat("R:R %.2f < %.2f", rr, InpMinRR), PatternIdToString(best.id)); return; }

   //--------------- Anti-duplicati ---------------
   string setupID = BuildSetupID(best.id, best.direction, zone, setupCandle.time);
   if(IsSetupAlreadyExecuted(setupID))
     { LogDecision("NO TRADE", "segnale duplicato gia' eseguito su questo setup", setupID); return; }

   //--------------- RISK VALIDATION: broker (stop level, volume, margine) ---------------
   bool isBuy = (best.direction==BIAS_BULL);
   double execPrice = isBuy? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   string slReason;
   if(!ValidateStopLevel(execPrice, sl, tp, slReason))
     { LogDecision("NO TRADE", slReason, PatternIdToString(best.id)); return; }

   double validatedVol; string volReason;
   if(!ValidateVolume(InpLotSize, validatedVol, volReason))
     { LogDecision("NO TRADE", volReason, PatternIdToString(best.id)); return; }

   string marginReason;
   ENUM_ORDER_TYPE ordType = isBuy? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!ValidateMargin(ordType, validatedVol, execPrice, marginReason))
     { LogDecision("NO TRADE", marginReason, PatternIdToString(best.id)); return; }

   //--------------- EXECUTION ---------------
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxDeviationPoints);

   bool sent = isBuy ? trade.Buy(validatedVol, _Symbol, execPrice, sl, tp, "SmartPatternScalper")
                      : trade.Sell(validatedVol, _Symbol, execPrice, sl, tp, "SmartPatternScalper");

   uint retcode = trade.ResultRetcode();
   if(!sent || (retcode!=TRADE_RETCODE_DONE && retcode!=TRADE_RETCODE_PLACED))
     {
      LogMsg(StringFormat("[ORDER FAILED] retcode=%u desc=%s", retcode, trade.ResultRetcodeDescription()));
      LogDecision("NO TRADE", StringFormat("invio ordine fallito, retcode=%u", retcode), trade.ResultRetcodeDescription());
      return;
     }

   g_tradesToday++;
   MarkSetupExecuted(setupID);

   //--------------- LOGGING finale strutturato ---------------
   string patternName = PatternIdToString(best.id);
   string category = SetupTypeToString(setupType);

   string fullLog = StringFormat(
      "Time=%s Italy | Symbol=%s | Spread=%.1fp | TradesToday=%d/%d | Window=OK | D1=%s H4=%s H1=%s | Zone=[%.2f-%.2f] Strength=%.1f Touches=%d | DistZone=%.1fp | LiquidityGrab=%s | Pattern=%s | %s | Score=%.0f (%s) | Category=%s | Entry=%.2f | SL=%.2f(%.1fp) | TP=%.2f(%.1fp) | RR=1:%.2f | Decision=%s",
      TimeToString(itNow, TIME_DATE|TIME_MINUTES), _Symbol, spreadPips, g_tradesToday, InpMaxTradesPerDay,
      BiasToString(biasD1), BiasToString(biasH4), BiasToString(biasH1),
      zone.lower, zone.upper, zone.strength, zone.touches, entryDistPips,
      liquidityGrabForScore?"YES":"NO", patternName, extraDebug, score, breakdown, category,
      execPrice, sl, slDistPips, tp, tpDistPips, rr,
      isBuy?"BUY":"SELL");

   LogMsg("[TRADE EXECUTED] " + fullLog);
   LogDecision(isBuy?"BUY":"SELL", best.detail, fullLog);
  }

//====================================================================
// EXPERT EVENT HANDLERS
//====================================================================
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(StringFind(_Symbol, "XAU")<0)
      LogMsg("[WARNING] Il simbolo del chart non contiene 'XAU': verificare che l'EA sia applicato a XAUUSD.");

   if(!InpUseCloseBarsOnly)
      LogMsg("[WARNING] InpUseCloseBarsOnly=false non e' supportato da questa implementazione: "
             "tutte le decisioni continuano a essere prese esclusivamente su barre M15 chiuse (shift>=1), "
             "per evitare repainting e look-ahead bias. Nessuna logica intrabar aggiuntiva e' stata attivata.");

   g_currentItalianDay = ItalianDayKey(GetItalianTime());
   g_tradesToday = 0;
   ArrayResize(g_executedSetupIDs, 0);

   double pip = GetPipSize();
   LogMsg(StringFormat("[INIT] Digits=%d Point=%.5f PipSize=%.5f MaxSL=%.1fp MaxTP=%.1fp Lot=%.2f Magic=%I64u",
          (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS), SymbolInfoDouble(_Symbol, SYMBOL_POINT), pip,
          InpMaxSLPips, InpMaxTPPips, InpLotSize, InpMagicNumber));

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   LogMsg(StringFormat("[DEINIT] reason=%d", reason));
  }

void OnTick()
  {
   ResetDailyCounterIfNeeded();

   if(!IsNewM15Bar())
      return;

   RunDecisionPipeline();
  }
//+------------------------------------------------------------------+
