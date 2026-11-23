//+------------------------------------------------------------------+
//|                                               WT_XAUUSD_FPM.mq5  |
//|   WaveTrend M5 + speciale WT M15 - XAUUSD - FP Markets / MT5     |
//+------------------------------------------------------------------+
//| STRATEGIA (default = specifica confermata il 03/11/2026)         |
//|  - Sessione 15:30-17:30 ORA ITALIANA (Europe/Rome).              |
//|  - Ad ogni nuova candela M5 della sessione (24 al giorno):       |
//|     * se la candela M15 appena chiusa ha un incrocio WT1/WT2     |
//|       -> operazione SPECIALE WT M15 (SL 50 pip, TP 70 pip)       |
//|          nella direzione dell'incrocio (priorita' su M5);        |
//|     * altrimenti -> operazione NORMALE M5 (SL 10, TP 15) nella   |
//|       direzione dell'ultimo incrocio WT1/WT2 confermato su M5.   |
//|  - Massimo 1 apertura per candela M5, 24 aperture al giorno.     |
//|  - Livelli +60/-60 solo informativi (nessun filtro).             |
//|  - Chiusura di tutte le posizioni dell'EA alle 17:30 italiane.   |
//|                                                                  |
//| RISCHIO                                                          |
//|  - Capitale di riferimento = balance alla mezzanotte italiana.   |
//|  - Budget giornaliero = capitale x 4%; nominale = budget / 24.   |
//|  - Residuo = budget + P/L netto realizzato (mai sopra il budget).|
//|  - Size = min(nominale, residuo) / perdita allo SL di 1 lotto    |
//|    (OrderCalcProfit, gia' convertita nella valuta del conto).    |
//|  - Blocco fino al giorno dopo se il P/L netto tocca -budget.     |
//|                                                                  |
//| ORARI                                                            |
//|  Ora server -> UTC con la regola del server (FP Markets: GMT+2,  |
//|  GMT+3 durante l'ora legale USA) -> Roma e New York con le       |
//|  regole UE e USA calcolate nel codice. Nessun offset fisso,      |
//|  nessun orologio del VPS come riferimento. Dal vivo la regola    |
//|  viene confrontata con TimeGMT(): se non coincide, nuove         |
//|  aperture bloccate (default).                                    |
//|                                                                  |
//| Nessuna DLL. Solo libreria standard MT5: Trade\Trade.mqh e       |
//| Generic\HashMap.mqh.                                             |
//+------------------------------------------------------------------+
#property copyright   "WT XAUUSD FPM"
#property version     "1.00"
#property description "WaveTrend M5 + speciale WT M15 su XAUUSD (FP Markets)."
#property description "Sessione 15:30-17:30 ora italiana, rischio giornaliero 4%, size automatica."

#include <Trade\Trade.mqh>
#include <Generic\HashMap.mqh>

#define EA_NAME      "WT XAUUSD FPM"
#define EA_VERSION   "1.00"
#define ZONE_ROME    0
#define ZONE_NY      1
#define ZONE_SERVER  2
#define M5_SEC       300
#define M15_SEC      900
#define KIND_NORMAL  1
#define KIND_SPECIAL 2
#define WT_MIN_BARS  300
#define RECONNECT_WAIT_SEC 5
#define PANEL_PREFIX "WTX_PNL_"
#define PANEL_LINES  23

// motivi per cui una candela della sessione non apre (statistiche)
#define SK_NOSIGNAL   0
#define SK_DIRECTION  1
#define SK_SPREAD     2
#define SK_MAXTRADES  3
#define SK_DAILYLIMIT 4
#define SK_SIZE       5
#define SK_MARGIN     6
#define SK_DATA       7
#define SK_CLOCK      8
#define SK_TRADEOFF   9
#define SK_STOPS      10
#define SK_SEND       11
#define SK_UNCERTAIN  12
#define SK_DUP        13
#define SK_CALC       14
#define SK_LATE       15
#define SK_N          16

//+------------------------------------------------------------------+
//| Enumerazioni degli input                                         |
//+------------------------------------------------------------------+
enum ENUM_SERVER_DST
  {
   SRV_DST_US   = 0, // Ora legale del server con regola USA (FP Markets)
   SRV_DST_EU   = 1, // Ora legale del server con regola UE
   SRV_DST_NONE = 2  // Server senza ora legale
  };

enum ENUM_TIME_CHECK
  {
   TIMECHECK_BLOCK = 0, // Incoerenza orari: blocca le nuove aperture
   TIMECHECK_WARN  = 1, // Incoerenza orari: solo avviso
   TIMECHECK_OFF   = 2  // Nessun controllo
  };

//+------------------------------------------------------------------+
//| Input                                                            |
//+------------------------------------------------------------------+
input group "=== Identificazione ==="
input string InpSymbolPrefix  = "XAUUSD";   // Simbolo atteso (il nome del grafico deve iniziare cosi')
input ulong  InpMagic         = 20261103;   // Magic Number
input string InpCommentPrefix = "WTX";      // Prefisso commento ordini (1-10 caratteri)

input group "=== Rischio ==="
input double InpDailyRiskPct    = 4.0;      // Rischio giornaliero massimo (% del capitale di inizio giornata)
input int    InpMaxTradesPerDay = 24;       // Numero massimo di aperture al giorno

input group "=== Sessione (ora italiana) ==="
input string InpSessionStart      = "15:30"; // Inizio sessione (ora italiana)
input string InpSessionEnd        = "17:30"; // Fine sessione (ora italiana)
input bool   InpCloseAtSessionEnd = true;    // Chiudi tutte le posizioni dell'EA a fine sessione
input int    InpEntryWindowSec    = 60;      // Secondi dall'apertura della candela entro cui aprire

input group "=== Pip, Stop Loss e Take Profit ==="
input double InpPipSize       = 0.10;  // Convenzione: 1 pip = USD di movimento prezzo XAUUSD
input double InpNormalSLPips  = 10;    // Stop Loss normale M5 (pip)
input double InpNormalTPPips  = 15;    // Take Profit normale M5 (pip)
input double InpM15SLPips     = 50;    // Stop Loss speciale WT M15 (pip)
input double InpM15TPPips     = 70;    // Take Profit speciale WT M15 (pip)
input bool   InpRealignSLTP   = true;  // Riallinea SL/TP sul prezzo effettivamente eseguito

input group "=== WaveTrend (LazyBear) ==="
input int    InpWTChannelLen = 10;    // Channel Length (n1)
input int    InpWTAverageLen = 21;    // Average Length (n2)
input int    InpWTSignalLen  = 4;     // Signal Smoothing (WT2 = SMA di WT1)
input double InpWTOverbought = 60;    // Ipercomprato (solo informativo)
input double InpWTOversold   = -60;   // Ipervenduto (solo informativo)
input int    InpWTBars       = 1000;  // Candele chiuse usate nel calcolo (minimo 300)

input group "=== Filtri e abilitazioni ==="
input double InpMaxSpreadPips = 3.0;  // Spread massimo in pip (0 = nessun limite)
input bool   InpAllowBuy      = true; // Abilita operazioni BUY
input bool   InpAllowSell     = true; // Abilita operazioni SELL
input bool   InpEnableM15     = true; // Abilita la strategia speciale WT M15

input group "=== Esecuzione ==="
input int    InpMaxSendAttempts  = 3;   // Tentativi di invio per candela (solo errori temporanei)
input ulong  InpDeviationPoints  = 30;  // Deviazione massima in point (solo esecuzione Instant)
input double InpCalcTolerancePct = 5.0; // Tolleranza OrderCalcProfit vs tick value (%)

input group "=== Fusi orari ==="
input int             InpServerStdOffsetMin = 120;        // Offset del server in ora solare (minuti da UTC)
input ENUM_SERVER_DST InpServerDST          = SRV_DST_US; // Regola ora legale del server
input int             InpRomeStdOffsetMin   = 60;         // Offset Italia in ora solare (minuti da UTC)
input bool            InpRomeUseDST         = true;       // Italia usa l'ora legale (regola UE)
input int             InpNYStdOffsetMin     = -300;       // Offset New York in ora solare (minuti da UTC)
input bool            InpNYUseDST           = true;       // New York usa l'ora legale (regola USA)
input ENUM_TIME_CHECK InpTimeCheck          = TIMECHECK_BLOCK; // Controllo dal vivo: regola server vs TimeGMT()
input int             InpTimeCheckTolSec    = 120;        // Tolleranza del controllo orario (secondi)

input group "=== Pannello e log ==="
input bool InpShowPanel    = true; // Mostra il pannello sul grafico
input bool InpCsvLog       = true; // Copia dei log su file CSV (MQL5\Files)
input int  InpDiagEveryMin = 60;   // Diagnostica oraria nel log ogni N minuti (0 = solo eventi; ignorato nel tester)

//+------------------------------------------------------------------+
//| Variabili globali                                                |
//+------------------------------------------------------------------+
CTrade   g_trade;
string   g_sym          = "";
string   g_accCur       = "";
bool     g_isTester     = false;
bool     g_isOptim      = false;
bool     g_panelOn      = false;
bool     g_busy         = false;

// specifiche del simbolo
int      g_digits    = 0;
double   g_point     = 0.0;
double   g_tickSize  = 0.0;
double   g_tickValue = 0.0;
double   g_contract  = 0.0;
double   g_volMin    = 0.0;
double   g_volMax    = 0.0;
double   g_volStep   = 0.0;
double   g_volLimit  = 0.0;
int      g_volDigits = 2;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;

// sessione in minuti dalla mezzanotte italiana
int      g_startMin = -1;
int      g_endMin   = -1;
int      g_normalDiffMin = 360; // differenza Roma-New York in ora solare

// cache delle date di cambio ora (UTC)
int      g_euYear = 0;  datetime g_euA = 0;  datetime g_euB = 0;
int      g_usYear = 0;  datetime g_usA = 0;  datetime g_usB = 0;

// orologio e connessione
bool     g_clockOk        = true;
bool     g_clockChecked   = false;
datetime g_lastClockCheck = 0;
bool     g_wasConnected   = true;
datetime g_reconnectLocal = 0;

// giornata italiana
int      g_dayKey       = 0;
datetime g_dayStartSrv  = 0;
bool     g_statsDirty   = true;
bool     g_statsOk      = false;
datetime g_lastRecalc   = 0;
double   g_refCapital   = 0.0;
double   g_budget       = 0.0;
double   g_nominalRisk  = 0.0;
double   g_netPL        = 0.0;
double   g_realizedLoss = 0.0;
int      g_closedTrades = 0;
int      g_entries      = 0;
int      g_entriesN     = 0;
int      g_entriesS     = 0;
bool     g_limitHit     = false;
bool     g_limitLogged  = false;
string   g_tags[];

// candela M5 in elaborazione
datetime g_candle        = 0;
bool     g_candleDone    = true;
string   g_candleMsg     = "";
int      g_candleReason  = -1;
int      g_sendAttempts  = 0;
bool     g_signalLogged  = false;

// posizioni
ulong    g_realign[];
int      g_realignTries[];
datetime g_nextCloseTry     = 0;
datetime g_lastProtectCheck = 0;

// cache WaveTrend per pannello
datetime g_pnlM5Bar  = 0;
datetime g_pnlM15Bar = 0;
double   g_pM5w1 = EMPTY_VALUE, g_pM5w2 = EMPTY_VALUE;
double   g_pM15w1 = EMPTY_VALUE, g_pM15w2 = EMPTY_VALUE;
int      g_pM5Dir = 0;
datetime g_pM5CrossClose = 0;
int      g_pM15Cross = 0;
datetime g_lastPanel = 0;

// diagnostica
datetime g_lastDiagUtc = 0;
int      g_preDiagDay  = 0;
string   g_gvLastBar   = "";
string   g_csvName     = "";

// statistiche (soprattutto per il tester)
int      g_skip[SK_N];
int      g_statCandles      = 0;
int      g_statEntriesN     = 0;
int      g_statEntriesS     = 0;
int      g_statSessionClose = 0;
int      g_statLimitDays    = 0;
int      g_statMismatchCand = 0;
int      g_statRealign      = 0;

//+------------------------------------------------------------------+
//| Utilita' stringhe                                                |
//+------------------------------------------------------------------+
string I2S(const long v)               { return IntegerToString(v); }
string D2S(const double v,const int d) { return DoubleToString(v,d); }
string PStr(const double p)            { return DoubleToString(p,g_digits); }
string Fmt(const datetime t)           { return TimeToString(t,TIME_DATE|TIME_SECONDS); }
string HHMM(const datetime t)          { return TimeToString(t,TIME_MINUTES); }
string YesNo(const bool b)             { return b ? "si" : "no"; }
string Money(const double v)           { return DoubleToString(v,2)+" "+g_accCur; }
string LotStr(const double v)          { return DoubleToString(v,g_volDigits); }
string DirStr(const int d)             { return d>0 ? "BUY" : (d<0 ? "SELL" : "-"); }
string KindStr(const int k)            { return k==KIND_SPECIAL ? "SPECIALE WT M15" : "NORMALE M5"; }
string WTStr(const double v)           { return v==EMPTY_VALUE ? "n/d" : DoubleToString(v,2); }

string DTShort(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t,s);
   return StringFormat("%02d.%02d %02d:%02d:%02d",s.day,s.mon,s.hour,s.min,s.sec);
  }

string MinToHHMM(int m)
  {
   while(m<0) m+=1440;
   m%=1440;
   return StringFormat("%02d:%02d",m/60,m%60);
  }

string Trim(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
  }

string OffStr(const int sec)
  {
   int m=sec/60;
   string sg=(m<0) ? "-" : "+";
   if(m<0) m=-m;
   return StringFormat("UTC%s%02d:%02d",sg,m/60,m%60);
  }

int ParseHHMM(const string s)
  {
   string p[];
   if(StringSplit(Trim(s),':',p)!=2) return -1;
   int h=(int)StringToInteger(Trim(p[0]));
   int m=(int)StringToInteger(Trim(p[1]));
   if(h<0 || h>23 || m<0 || m>59) return -1;
   return h*60+m;
  }

string RetcodeStr(const uint rc)
  {
   switch(rc)
     {
      case TRADE_RETCODE_REQUOTE:           return "requote";
      case TRADE_RETCODE_REJECT:            return "rifiutato";
      case TRADE_RETCODE_CANCEL:            return "annullato";
      case TRADE_RETCODE_PLACED:            return "piazzato";
      case TRADE_RETCODE_DONE:              return "eseguito";
      case TRADE_RETCODE_DONE_PARTIAL:      return "eseguito parzialmente";
      case TRADE_RETCODE_ERROR:             return "errore";
      case TRADE_RETCODE_TIMEOUT:           return "timeout";
      case TRADE_RETCODE_INVALID:           return "richiesta non valida";
      case TRADE_RETCODE_INVALID_VOLUME:    return "volume non valido";
      case TRADE_RETCODE_INVALID_PRICE:     return "prezzo non valido";
      case TRADE_RETCODE_INVALID_STOPS:     return "stop non validi";
      case TRADE_RETCODE_TRADE_DISABLED:    return "trading disabilitato";
      case TRADE_RETCODE_MARKET_CLOSED:     return "mercato chiuso";
      case TRADE_RETCODE_NO_MONEY:          return "fondi insufficienti";
      case TRADE_RETCODE_PRICE_CHANGED:     return "prezzo cambiato";
      case TRADE_RETCODE_PRICE_OFF:         return "nessuna quotazione";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "troppe richieste";
      case TRADE_RETCODE_LOCKED:            return "richiesta bloccata";
      case TRADE_RETCODE_FROZEN:            return "ordine/posizione congelati";
      case TRADE_RETCODE_INVALID_FILL:      return "tipo di riempimento non valido";
      case TRADE_RETCODE_CONNECTION:        return "nessuna connessione";
      case TRADE_RETCODE_LIMIT_VOLUME:      return "limite di volume";
      case TRADE_RETCODE_LIMIT_POSITIONS:   return "limite di posizioni";
     }
   return "codice "+I2S(rc);
  }

bool IsTransientRetcode(const uint rc)
  {
   return (rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_PRICE_CHANGED || rc==TRADE_RETCODE_PRICE_OFF ||
           rc==TRADE_RETCODE_TOO_MANY_REQUESTS || rc==TRADE_RETCODE_LOCKED);
  }

//+------------------------------------------------------------------+
//| CALENDARIO E FUSI ORARI (tutto calcolato in codice)              |
//+------------------------------------------------------------------+
datetime MakeDT(const int y,const int mo,const int d,const int h,const int mi)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year=y; s.mon=mo; s.day=d; s.hour=h; s.min=mi; s.sec=0;
   return StructToTime(s);
  }

int DowOf(const datetime t)  { MqlDateTime s; TimeToStruct(t,s); return s.day_of_week; } // 0 = domenica
int YearOf(const datetime t) { MqlDateTime s; TimeToStruct(t,s); return s.year; }

// n-esima domenica del mese (00:00)
datetime NthSunday(const int y,const int mo,const int n)
  {
   datetime first=MakeDT(y,mo,1,0,0);
   int dow=DowOf(first);
   int day=1+((7-dow)%7)+7*(n-1);
   return MakeDT(y,mo,day,0,0);
  }

// ultima domenica del mese (00:00)
datetime LastSunday(const int y,const int mo)
  {
   int ny=(mo==12) ? y+1 : y;
   int nm=(mo==12) ? 1 : mo+1;
   datetime last=(datetime)((long)MakeDT(ny,nm,1,0,0)-86400);
   return (datetime)((long)last-(long)DowOf(last)*86400);
  }

// Regola UE: ora legale dall'ultima domenica di marzo 01:00 UTC
// all'ultima domenica di ottobre 01:00 UTC (stessa ora UTC in tutta la UE)
void EUBounds(const int y,datetime &a,datetime &b)
  {
   if(g_euYear!=y)
     {
      g_euYear=y;
      g_euA=(datetime)((long)LastSunday(y,3)+3600);
      g_euB=(datetime)((long)LastSunday(y,10)+3600);
     }
   a=g_euA; b=g_euB;
  }

// Regola USA: dalla seconda domenica di marzo alle 02:00 locali (ora solare)
// alla prima domenica di novembre alle 02:00 locali (ora legale)
void USBounds(const int y,datetime &a,datetime &b)
  {
   if(g_usYear!=y)
     {
      g_usYear=y;
      long std=(long)InpNYStdOffsetMin*60;
      g_usA=(datetime)((long)NthSunday(y,3,2)+7200-std);
      g_usB=(datetime)((long)NthSunday(y,11,1)+7200-(std+3600));
     }
   a=g_usA; b=g_usB;
  }

bool RuleEU(const datetime utc)
  {
   datetime a,b;
   EUBounds(YearOf(utc),a,b);
   return (utc>=a && utc<b);
  }

bool RuleUS(const datetime utc)
  {
   datetime a,b;
   USBounds(YearOf(utc),a,b);
   return (utc>=a && utc<b);
  }

bool ZoneIsDst(const int zone,const datetime utc)
  {
   if(zone==ZONE_ROME) return InpRomeUseDST && RuleEU(utc);
   if(zone==ZONE_NY)   return InpNYUseDST && RuleUS(utc);
   if(InpServerDST==SRV_DST_US) return RuleUS(utc);
   if(InpServerDST==SRV_DST_EU) return RuleEU(utc);
   return false;
  }

int ZoneStdOffSec(const int zone)
  {
   if(zone==ZONE_ROME) return InpRomeStdOffsetMin*60;
   if(zone==ZONE_NY)   return InpNYStdOffsetMin*60;
   return InpServerStdOffsetMin*60;
  }

int ZoneOffSec(const int zone,const datetime utc)
  {
   return ZoneStdOffSec(zone)+(ZoneIsDst(zone,utc) ? 3600 : 0);
  }

datetime UtcToZone(const int zone,const datetime utc)
  {
   return (datetime)((long)utc+ZoneOffSec(zone,utc));
  }

// da ora locale di una zona a UTC (nell'ora ripetuta di ottobre/novembre
// viene scelta la prima occorrenza, cioe' quella in ora legale)
datetime ZoneToUtc(const int zone,const datetime local)
  {
   long s=ZoneStdOffSec(zone);
   datetime b=(datetime)((long)local-s-3600);
   if(ZoneIsDst(zone,b)) return b;
   return (datetime)((long)local-s);
  }

datetime ServerToUtc(const datetime srv) { return ZoneToUtc(ZONE_SERVER,srv); }

// ora corrente del server (TimeTradeServer avanza anche senza tick)
datetime ServerNow()
  {
   datetime t=TimeTradeServer();
   datetime c=TimeCurrent();
   if(t<c) t=c;
   return t;
  }

datetime DayStart(const datetime local) { return (datetime)(((long)local/86400)*86400); }

int RomeDayKey(const datetime utc)
  {
   MqlDateTime s;
   TimeToStruct(UtcToZone(ZONE_ROME,utc),s);
   return s.year*10000+s.mon*100+s.day;
  }

int RomeMinuteOfDay(const datetime utc)
  {
   MqlDateTime s;
   TimeToStruct(UtcToZone(ZONE_ROME,utc),s);
   return s.hour*60+s.min;
  }

// inizio (ora server) del giorno italiano che contiene utc
datetime RomeDayStartServer(const datetime utc)
  {
   datetime startLocal=DayStart(UtcToZone(ZONE_ROME,utc));
   return UtcToZone(ZONE_SERVER,ZoneToUtc(ZONE_ROME,startLocal));
  }

bool InSessionMin(const int m) { return (m>=g_startMin && m<g_endMin); }

string RomeZoneName(const datetime utc) { return ZoneIsDst(ZONE_ROME,utc) ? "CEST" : "CET"; }
string NYZoneName(const datetime utc)   { return ZoneIsDst(ZONE_NY,utc) ? "EDT" : "EST"; }

int RomeNYDiffMin(const datetime utc)
  {
   return (ZoneOffSec(ZONE_ROME,utc)-ZoneOffSec(ZONE_NY,utc))/60;
  }

// "AAAAMMGG HHMM" della candela in ora italiana: chiave anti-duplicato
string CandleCore(const datetime candleSrv)
  {
   MqlDateTime s;
   TimeToStruct(UtcToZone(ZONE_ROME,ServerToUtc(candleSrv)),s);
   return StringFormat("%04d%02d%02d %02d%02d",s.year,s.mon,s.day,s.hour,s.min);
  }

string MakeTag(const int kind,const string core)
  {
   return InpCommentPrefix+(kind==KIND_SPECIAL ? " S " : " N ")+core;
  }

int KindFromComment(const string c)
  {
   if(StringFind(c,InpCommentPrefix+" S ")==0) return KIND_SPECIAL;
   if(StringFind(c,InpCommentPrefix+" N ")==0) return KIND_NORMAL;
   return 0;
  }

//+------------------------------------------------------------------+
//| Log e notifiche                                                  |
//+------------------------------------------------------------------+
void AppendCsv(const string line)
  {
   if(g_csvName=="") return;
   int h=FileOpen(g_csvName,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0) FileWriteString(h,"UTC;Roma;NewYork;Server;Evento;Dettagli\r\n");
   FileSeek(h,0,SEEK_END);
   FileWriteString(h,line+"\r\n");
   FileClose(h);
  }

void Log(const string ev,const string msg)
  {
   datetime srv=ServerNow();
   datetime utc=ServerToUtc(srv);
   datetime rome=UtcToZone(ZONE_ROME,utc);
   PrintFormat("[WTX] %s | Roma %s | %s",ev,Fmt(rome),msg);
   if(InpCsvLog && !g_isOptim)
     {
      string clean=msg;
      StringReplace(clean,";",",");
      AppendCsv(Fmt(utc)+";"+Fmt(rome)+";"+Fmt(UtcToZone(ZONE_NY,utc))+";"+Fmt(srv)+";"+ev+";"+clean);
     }
  }

void Notify(const string msg)
  {
   Log("AVVISO",msg);
   if(!g_isTester) Alert(EA_NAME+" "+g_sym+": "+msg);
  }

//+------------------------------------------------------------------+
//| DIAGNOSTICA ORARIA: UTC, Italia, New York, server                |
//+------------------------------------------------------------------+
void LogTimeDiagnostics(const string tag)
  {
   datetime srv=ServerNow();
   datetime utc=ServerToUtc(srv);
   datetime rome=UtcToZone(ZONE_ROME,utc);
   datetime ny=UtcToZone(ZONE_NY,utc);
   int offR=ZoneOffSec(ZONE_ROME,utc);
   int offN=ZoneOffSec(ZONE_NY,utc);
   int offS=ZoneOffSec(ZONE_SERVER,utc);
   int diff=RomeNYDiffMin(utc);

   Log(tag,"UTC "+Fmt(utc)+
       " | Italia "+Fmt(rome)+" ("+RomeZoneName(utc)+" "+OffStr(offR)+")"+
       " | New York "+Fmt(ny)+" ("+NYZoneName(utc)+" "+OffStr(offN)+")"+
       " | Server "+Fmt(srv)+" ("+OffStr(offS)+", ora legale server "+YesNo(ZoneIsDst(ZONE_SERVER,utc))+")"+
       " | Italia-New York "+MinToHHMM(diff));

   datetime d0=DayStart(rome);
   datetime sUtc=ZoneToUtc(ZONE_ROME,(datetime)((long)d0+(long)g_startMin*60));
   datetime eUtc=ZoneToUtc(ZONE_ROME,(datetime)((long)d0+(long)g_endMin*60));
   string msg="Sessione oggi "+MinToHHMM(g_startMin)+"-"+MinToHHMM(g_endMin)+" Italia"+
              " = "+HHMM(UtcToZone(ZONE_SERVER,sUtc))+"-"+HHMM(UtcToZone(ZONE_SERVER,eUtc))+" server"+
              " = "+HHMM(sUtc)+"-"+HHMM(eUtc)+" UTC"+
              " = "+HHMM(UtcToZone(ZONE_NY,sUtc))+"-"+HHMM(UtcToZone(ZONE_NY,eUtc))+" New York";
   if(diff!=g_normalDiffMin)
      msg+=" | SETTIMANA DI SFASAMENTO ora legale Europa/USA (Italia-New York "+MinToHHMM(diff)+" invece di "+MinToHHMM(g_normalDiffMin)+")";
   Log(tag,msg);

   if(!g_isTester)
     {
      datetime gmt=TimeGMT();
      long measured=(long)TimeTradeServer()-(long)gmt;
      Log(tag,"Controllo dal vivo: TimeGMT (orologio VPS) "+Fmt(gmt)+" | offset server misurato "+I2S(measured/60)+
          " min, previsto dalla regola "+I2S(offS/60)+" min | esito "+(g_clockChecked ? (g_clockOk ? "OK" : "INCOERENTE") : "non ancora verificato"));
     }
   else
      Log(tag,"Tester: UTC ricostruito dall'ora del server con la regola impostata (nel tester TimeGMT coincide con l'ora del server)");
  }

// date di cambio ora dell'anno e settimane di sfasamento
void LogDstCalendar(const int y)
  {
   datetime ea,eb,ua,ub;
   EUBounds(y,ea,eb);
   USBounds(y,ua,ub);
   string s="Anno "+I2S(y)+": ";
   s+= InpRomeUseDST ? "Italia ora legale dal "+Fmt(UtcToZone(ZONE_ROME,ea))+" al "+Fmt(UtcToZone(ZONE_ROME,eb))+" (ora italiana)" : "Italia senza ora legale";
   s+= InpNYUseDST ? " | New York ora legale dal "+Fmt(UtcToZone(ZONE_NY,ua))+" al "+Fmt(UtcToZone(ZONE_NY,ub))+" (ora di New York)" : " | New York senza ora legale";
   Log("CALENDARIO",s);
   if(InpRomeUseDST && InpNYUseDST)
     {
      string m="Settimane di sfasamento "+I2S(y)+":";
      if(ua<ea) m+=" "+TimeToString(UtcToZone(ZONE_ROME,ua),TIME_DATE)+" - "+TimeToString(UtcToZone(ZONE_ROME,(datetime)((long)ea-1)),TIME_DATE);
      if(ub>eb) m+=" | "+TimeToString(UtcToZone(ZONE_ROME,eb),TIME_DATE)+" - "+TimeToString(UtcToZone(ZONE_ROME,(datetime)((long)ub-1)),TIME_DATE);
      m+=" (la sessione resta "+MinToHHMM(g_startMin)+"-"+MinToHHMM(g_endMin)+" italiane)";
      Log("CALENDARIO",m);
     }
  }

//+------------------------------------------------------------------+
//| Orologio e connessione                                           |
//+------------------------------------------------------------------+
void CheckClock()
  {
   if(g_isTester || InpTimeCheck==TIMECHECK_OFF) { g_clockOk=true; g_clockChecked=true; return; }
   datetime gmt=TimeGMT();
   if(g_clockChecked && (long)gmt-(long)g_lastClockCheck<60) return;
   g_lastClockCheck=gmt;
   datetime srvNow=TimeTradeServer();
   if(srvNow<=0 || gmt<=0)
     {
      if(g_clockOk || !g_clockChecked) Notify("ora del server o UTC non disponibili: nuove aperture bloccate");
      g_clockOk=false; g_clockChecked=true;
      return;
     }
   long measured=(long)srvNow-(long)gmt;
   long expected=ZoneOffSec(ZONE_SERVER,gmt);
   long diff=measured-expected;
   bool ok=(MathAbs((double)diff)<=InpTimeCheckTolSec);
   if(!g_clockChecked || ok!=g_clockOk)
     {
      if(ok)
         Log("ORARIO","controllo superato: offset server misurato "+I2S(measured/60)+" min = previsto "+I2S(expected/60)+" min");
      else
         Notify("INCOERENZA ORARIO: offset server misurato "+I2S(measured/60)+" min, previsto "+I2S(expected/60)+
                " min (differenza "+I2S(diff)+" s). Verificare orologio del VPS e regole dei fusi."+
                (InpTimeCheck==TIMECHECK_BLOCK ? " Nuove aperture BLOCCATE." : ""));
     }
   g_clockOk=ok;
   g_clockChecked=true;
  }

bool ClockUsable()
  {
   if(ServerNow()<=0) return false;
   if(g_isTester) return true;
   if(InpTimeCheck!=TIMECHECK_BLOCK) return true;
   return (g_clockChecked && g_clockOk);
  }

void CheckConnection()
  {
   if(g_isTester) return;
   bool c=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(c==g_wasConnected) return;
   g_wasConnected=c;
   if(c)
     {
      g_reconnectLocal=TimeLocal();
      g_statsDirty=true;
      g_lastProtectCheck=0;
      Log("CONNESSIONE","connessione ripristinata: ricontrollo storico e posizioni; nuove aperture dopo "+I2S(RECONNECT_WAIT_SEC)+" s");
     }
   else
      Notify("connessione al server persa: nessuna nuova apertura finche' non torna");
  }

bool ConnectionUsable()
  {
   if(g_isTester) return true;
   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   if(g_reconnectLocal>0 && (long)TimeLocal()-(long)g_reconnectLocal<RECONNECT_WAIT_SEC) return false;
   return true;
  }

// permessi di trading (terminale, EA, conto, simbolo)
bool TradingAllowed(const int dir,string &why)
  {
   if(!g_isTester)
     {
      if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { why="Algo Trading disattivato nel terminale"; return false; }
      if(!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED))           { why="trading non consentito nelle proprieta' dell'EA"; return false; }
      if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))   { why="trading non consentito sul conto"; return false; }
      if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT))    { why="trading automatico non consentito dal server"; return false; }
     }
   long mode=SymbolInfoInteger(g_sym,SYMBOL_TRADE_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED)  { why="trading disabilitato sul simbolo"; return false; }
   if(mode==SYMBOL_TRADE_MODE_CLOSEONLY) { why="simbolo in sola chiusura"; return false; }
   if(dir>0 && mode==SYMBOL_TRADE_MODE_SHORTONLY) { why="simbolo solo SELL"; return false; }
   if(dir<0 && mode==SYMBOL_TRADE_MODE_LONGONLY)  { why="simbolo solo BUY"; return false; }
   return true;
  }

//+------------------------------------------------------------------+
//| Prezzi, pip e volumi                                             |
//+------------------------------------------------------------------+
double NormPrice(const double p)
  {
   if(g_tickSize<=0.0) return NormalizeDouble(p,g_digits);
   return NormalizeDouble(MathRound(p/g_tickSize)*g_tickSize,g_digits);
  }

// pip -> distanza di prezzo, arrotondata a multipli del tick size
double PipsToPrice(const double pips)
  {
   double d=pips*InpPipSize;
   if(g_tickSize>0.0) d=MathRound(d/g_tickSize)*g_tickSize;
   return d;
  }

double SLDist(const int kind) { return PipsToPrice(kind==KIND_SPECIAL ? InpM15SLPips : InpNormalSLPips); }
double TPDist(const int kind) { return PipsToPrice(kind==KIND_SPECIAL ? InpM15TPPips : InpNormalTPPips); }

int StepDigits(const double step)
  {
   int d=0;
   double s=step;
   while(d<8 && MathAbs(s-MathRound(s))>1e-9) { s*=10.0; d++; }
   return d;
  }

// 1 = ok, 0 = calcolo non affidabile (riprovare), -1 = size sotto il minimo / rischio nullo
int CalcLots(const int dir,const double slDist,const double risk,const MqlTick &tk,
             double &lots,double &lossLot,string &why)
  {
   lots=0.0; lossLot=0.0;
   if(risk<=0.0) { why="rischio disponibile nullo"; return -1; }
   double price=(dir>0) ? tk.ask : tk.bid;
   if(price<=0.0) { why="prezzo non disponibile"; return 0; }
   double sl=NormPrice(dir>0 ? price-slDist : price+slDist);
   double p=0.0;
   ResetLastError();
   if(!OrderCalcProfit(dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,g_sym,1.0,price,sl,p))
     { why="OrderCalcProfit fallito (errore "+I2S(GetLastError())+")"; return 0; }
   lossLot=-p;
   if(lossLot<=0.0) { why="perdita allo SL non positiva ("+D2S(p,2)+")"; return 0; }
   // controllo incrociato con il valore monetario del tick
   double tv=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv<=0.0) tv=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_VALUE);
   if(tv>0.0 && g_tickSize>0.0)
     {
      double est=MathAbs(price-sl)/g_tickSize*tv;
      if(est>0.0 && MathAbs(lossLot-est)/est*100.0>InpCalcTolerancePct)
        { why="OrderCalcProfit "+D2S(lossLot,2)+" incoerente con la stima da tick value "+D2S(est,2); return 0; }
     }
   double raw=risk/lossLot;
   double l=MathFloor(raw/g_volStep+1e-9)*g_volStep;
   l=NormalizeDouble(l,g_volDigits);
   if(l>g_volMax) l=NormalizeDouble(MathFloor(g_volMax/g_volStep+1e-9)*g_volStep,g_volDigits);
   if(l<g_volMin-1e-12)
     { why="size calcolata "+D2S(raw,4)+" lotti, sotto il minimo "+LotStr(g_volMin); return -1; }
   lots=l;
   return 1;
  }

double ResidualBudget()
  {
   if(g_limitHit) return 0.0;
   return MathMin(g_budget,g_budget+g_netPL);
  }

//+------------------------------------------------------------------+
//| Posizioni dell'EA                                                |
//+------------------------------------------------------------------+
bool SelectedIsMine()
  {
   return (PositionGetString(POSITION_SYMBOL)==g_sym &&
           (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic);
  }

int CollectMyPositions(ulong &tickets[])
  {
   ArrayResize(tickets,0);
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(!SelectedIsMine()) continue;
      ArrayResize(tickets,n+1);
      tickets[n]=t;
      n++;
     }
   return n;
  }

double MyOpenVolume()
  {
   ulong t[];
   int n=CollectMyPositions(t);
   double v=0.0;
   for(int i=0;i<n;i++)
      if(PositionSelectByTicket(t[i])) v+=PositionGetDouble(POSITION_VOLUME);
   return v;
  }

// rischio ancora impegnato: perdita se tutte le posizioni aperte toccano lo SL
double OpenRiskMoney(int &cnt,int &noSL)
  {
   ulong t[];
   cnt=CollectMyPositions(t);
   noSL=0;
   double risk=0.0;
   for(int i=0;i<cnt;i++)
     {
      if(!PositionSelectByTicket(t[i])) continue;
      double sl=PositionGetDouble(POSITION_SL);
      if(sl<=0.0) { noSL++; continue; }
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double p=0.0;
      if(OrderCalcProfit(pt==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,g_sym,
                         PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),sl,p))
         if(p<0.0) risk+=-p;
     }
   return risk;
  }

bool CoreUsed(const string core)
  {
   for(int i=0;i<ArraySize(g_tags);i++)
      if(StringFind(g_tags[i],core)>=0) return true;
   ulong t[];
   int n=CollectMyPositions(t);
   for(int k=0;k<n;k++)
     {
      if(!PositionSelectByTicket(t[k])) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(KindFromComment(c)!=0 && StringFind(c,core)>=0) return true;
     }
   return false;
  }

void AddTag(const string tag)
  {
   int n=ArraySize(g_tags);
   ArrayResize(g_tags,n+1);
   g_tags[n]=tag;
  }

//+------------------------------------------------------------------+
//| Persistenza: ultima candela M5 elaborata                         |
//+------------------------------------------------------------------+
datetime GVLastBar()
  {
   if(!GlobalVariableCheck(g_gvLastBar)) return 0;
   return (datetime)(long)GlobalVariableGet(g_gvLastBar);
  }

void SetGVLastBar(const datetime candle)
  {
   if(GVLastBar()>=candle) return;
   GlobalVariableSet(g_gvLastBar,(double)(long)candle);
   if(!g_isTester) GlobalVariablesFlush();
  }

//+------------------------------------------------------------------+
//| STATISTICHE DEL GIORNO ITALIANO (ricostruite dallo storico)      |
//| Persistenti per costruzione: un riavvio le ricalcola identiche.  |
//+------------------------------------------------------------------+
double DealResult(const ulong t)
  {
   return HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_COMMISSION)+
          HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_FEE);
  }

void RecalcDay()
  {
   datetime nowSrv=ServerNow();
   g_lastRecalc=nowSrv;
   g_statsDirty=false;
   if(g_dayStartSrv<=0) { g_statsOk=false; return; }
   if(!HistorySelect(g_dayStartSrv,(datetime)((long)nowSrv+86400)))
     {
      if(g_statsOk) Log("STORICO","HistorySelect fallito: nuove aperture sospese");
      g_statsOk=false;
      return;
     }
   int total=HistoryDealsTotal();
   double sumAll=0.0;
   ulong eaT[];
   long  eaMsc[];
   int   nEa=0;
   for(int i=0;i<total;i++)
     {
      ulong t=HistoryDealGetTicket(i);
      if(t==0) continue;
      ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(t,DEAL_TYPE);
      if(dt!=DEAL_TYPE_CREDIT) sumAll+=DealResult(t);
      if(HistoryDealGetString(t,DEAL_SYMBOL)==g_sym && (ulong)HistoryDealGetInteger(t,DEAL_MAGIC)==InpMagic)
        {
         ArrayResize(eaT,nEa+1);
         ArrayResize(eaMsc,nEa+1);
         eaT[nEa]=t;
         eaMsc[nEa]=HistoryDealGetInteger(t,DEAL_TIME_MSC);
         nEa++;
        }
     }
   // ordine cronologico dei deal dell'EA
   for(int a=1;a<nEa;a++)
     {
      ulong tt=eaT[a]; long mm=eaMsc[a]; int b=a-1;
      while(b>=0 && eaMsc[b]>mm) { eaT[b+1]=eaT[b]; eaMsc[b+1]=eaMsc[b]; b--; }
      eaT[b+1]=tt; eaMsc[b+1]=mm;
     }
   // capitale di riferimento = balance alla mezzanotte italiana
   g_refCapital=AccountInfoDouble(ACCOUNT_BALANCE)-sumAll;
   g_budget=g_refCapital*InpDailyRiskPct/100.0;
   g_nominalRisk=g_budget/InpMaxTradesPerDay;

   g_netPL=0.0; g_realizedLoss=0.0; g_closedTrades=0;
   g_entries=0; g_entriesN=0; g_entriesS=0;
   ArrayResize(g_tags,0);
   bool hit=false;
   long   pId[];
   double pSum[];
   bool   pIn[];
   bool   pOut[];
   int    np=0;
   for(int k=0;k<nEa;k++)
     {
      ulong t=eaT[k];
      double r=DealResult(t);
      g_netPL+=r;
      if(g_budget>0.0 && g_netPL<=-g_budget+1e-9) hit=true;
      long pid=HistoryDealGetInteger(t,DEAL_POSITION_ID);
      int idx=-1;
      for(int j=0;j<np;j++) if(pId[j]==pid) { idx=j; break; }
      if(idx<0)
        {
         ArrayResize(pId,np+1); ArrayResize(pSum,np+1); ArrayResize(pIn,np+1); ArrayResize(pOut,np+1);
         pId[np]=pid; pSum[np]=0.0; pIn[np]=false; pOut[np]=false;
         idx=np; np++;
        }
      pSum[idx]+=r;
      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY);
      if(en==DEAL_ENTRY_IN)
        {
         if(!pIn[idx])
           {
            pIn[idx]=true;
            string c=HistoryDealGetString(t,DEAL_COMMENT);
            g_entries++;
            if(KindFromComment(c)==KIND_SPECIAL) g_entriesS++; else g_entriesN++;
            AddTag(c);
           }
        }
      else if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY || en==DEAL_ENTRY_INOUT)
         pOut[idx]=true;
     }
   for(int j=0;j<np;j++)
      if(pOut[j])
        {
         g_closedTrades++;
         if(pSum[j]<0.0) g_realizedLoss+=pSum[j];
        }
   g_limitHit=hit;
   g_statsOk=true;
   if(g_limitHit && !g_limitLogged)
     {
      g_limitLogged=true;
      g_statLimitDays++;
      Notify("LIMITE GIORNALIERO RAGGIUNTO: P/L netto "+Money(g_netPL)+" su budget "+Money(g_budget)+
             ". Nuove aperture bloccate fino alla mezzanotte italiana.");
     }
  }

void LogDayStatus(const string tag)
  {
   Log(tag,"capitale inizio giorno "+Money(g_refCapital)+" | budget "+D2S(InpDailyRiskPct,2)+"% = "+Money(g_budget)+
       " | rischio nominale per operazione "+Money(g_nominalRisk)+" | P/L netto realizzato "+Money(g_netPL)+
       " | perdite realizzate "+Money(g_realizedLoss)+" | residuo "+Money(ResidualBudget())+
       " | aperture "+I2S(g_entries)+"/"+I2S(InpMaxTradesPerDay)+" (normali "+I2S(g_entriesN)+", M15 "+I2S(g_entriesS)+")"+
       " | limite raggiunto "+YesNo(g_limitHit));
  }

void OnNewRomeDay(const int key,const datetime nowUtc)
  {
   if(g_dayKey!=0)
      LogDayStatus("RIEPILOGO GIORNO "+I2S(g_dayKey));
   g_dayKey=key;
   g_dayStartSrv=RomeDayStartServer(nowUtc);
   g_limitLogged=false;
   g_limitHit=false;
   RecalcDay();
   Log("GIORNO","nuovo giorno italiano "+I2S(key)+" (inizio = "+Fmt(g_dayStartSrv)+" ora server): contatori azzerati");
   LogTimeDiagnostics("GIORNO");
   LogDayStatus("STATO");
  }

//+------------------------------------------------------------------+
//| WAVETREND (LazyBear) calcolato internamente                      |
//|  ap  = hlc3                                                      |
//|  esa = ema(ap, n1)                                               |
//|  d   = ema(abs(ap - esa), n1)                                    |
//|  ci  = (ap - esa) / (0.015 * d)                                  |
//|  wt1 = ema(ci, n2)                                               |
//|  wt2 = sma(wt1, 4)                                               |
//| EMA come in Pine: alpha = 2/(n+1), primo valore = sorgente.      |
//| Con d = 0 (solo alla prima candela) ci non e' definito: wt1 e'   |
//| vuoto e l'EMA riparte dal primo ci valido, come in Pine.         |
//| Calcolato SOLO su candele chiuse.                                |
//+------------------------------------------------------------------+
void CalcWT(const MqlRates &r[],const int n,double &w1[],double &w2[])
  {
   ArrayResize(w1,n);
   ArrayResize(w2,n);
   double a1=2.0/(InpWTChannelLen+1.0);
   double a2=2.0/(InpWTAverageLen+1.0);
   double esa=0.0, d=0.0, tci=0.0;
   bool esaOk=false, dOk=false, tciOk=false;
   for(int i=0;i<n;i++)
     {
      double ap=(r[i].high+r[i].low+r[i].close)/3.0;
      esa=esaOk ? a1*ap+(1.0-a1)*esa : ap;
      esaOk=true;
      double dev=MathAbs(ap-esa);
      d=dOk ? a1*dev+(1.0-a1)*d : dev;
      dOk=true;
      if(d>0.0)
        {
         double ci=(ap-esa)/(0.015*d);
         tci=tciOk ? a2*ci+(1.0-a2)*tci : ci;
         tciOk=true;
         w1[i]=tci;
        }
      else
        {
         tciOk=false;
         w1[i]=EMPTY_VALUE;
        }
      w2[i]=EMPTY_VALUE;
      if(i>=InpWTSignalLen-1)
        {
         double s=0.0;
         bool ok=true;
         for(int k=i-InpWTSignalLen+1;k<=i;k++)
           {
            if(w1[k]==EMPTY_VALUE) { ok=false; break; }
            s+=w1[k];
           }
         if(ok) w2[i]=s/InpWTSignalLen;
        }
     }
  }

// +1 incrocio rialzista, -1 ribassista, 0 nessuno, sulla candela k (rispetto a k-1)
int CrossAt(const double &w1[],const double &w2[],const int k)
  {
   if(k<1) return 0;
   if(w1[k]==EMPTY_VALUE || w2[k]==EMPTY_VALUE || w1[k-1]==EMPTY_VALUE || w2[k-1]==EMPTY_VALUE) return 0;
   if(w1[k-1]<=w2[k-1] && w1[k]>w2[k]) return 1;
   if(w1[k-1]>=w2[k-1] && w1[k]<w2[k]) return -1;
   return 0;
  }

// direzione dell'ultimo incrocio confermato fino alla candela last; kOut = candela dell'incrocio
int LastCross(const double &w1[],const double &w2[],const int last,int &kOut)
  {
   kOut=-1;
   for(int k=last;k>=1;k--)
     {
      int c=CrossAt(w1,w2,k);
      if(c!=0) { kOut=k; return c; }
     }
   return 0;
  }

// WaveTrend sulle candele chiuse di tf, verificando che la candela appena
// chiusa sia quella immediatamente precedente a "candle" (ora server).
// 1 = ok, 0 = dati non pronti/non affidabili
int ComputeWT(const ENUM_TIMEFRAMES tf,const datetime candle,const int sec,
              MqlRates &r[],double &w1[],double &w2[],string &why)
  {
   string tfs=(tf==PERIOD_M15) ? "M15" : "M5";
   if(!(bool)SeriesInfoInteger(g_sym,tf,SERIES_SYNCHRONIZED)) { why="storico "+tfs+" non sincronizzato"; return 0; }
   MqlRates b0[];
   if(CopyRates(g_sym,tf,0,1,b0)!=1 || b0[0].time!=candle) { why="candela "+tfs+" corrente non ancora aggiornata"; return 0; }
   int got=CopyRates(g_sym,tf,1,InpWTBars,r);
   if(got<WT_MIN_BARS) { why="storico "+tfs+" insufficiente ("+I2S(got)+" candele, minimo "+I2S(WT_MIN_BARS)+")"; return 0; }
   if(r[got-1].time!=(datetime)((long)candle-sec))
     { why="buco nei dati "+tfs+": ultima candela chiusa "+Fmt(r[got-1].time)+" invece di "+Fmt((datetime)((long)candle-sec)); return 0; }
   CalcWT(r,got,w1,w2);
   if(w1[got-1]==EMPTY_VALUE || w2[got-1]==EMPTY_VALUE || w1[got-2]==EMPTY_VALUE || w2[got-2]==EMPTY_VALUE)
     { why="WaveTrend "+tfs+" non calcolabile"; return 0; }
   return 1;
  }

string RomeHHMMofSrv(const datetime srv) { return HHMM(UtcToZone(ZONE_ROME,ServerToUtc(srv))); }

// 1 = segnale, 0 = dati non pronti (riprovare), -1 = nessun segnale
int DetermineSignal(const datetime candle,int &dir,int &kind,string &txt)
  {
   dir=0; kind=0; txt="";
   string m15Info="";
   bool m15slot=(((long)candle%M15_SEC)==0);
   if(InpEnableM15 && m15slot)
     {
      MqlRates q[]; double v1[],v2[]; string why="";
      if(ComputeWT(PERIOD_M15,candle,M15_SEC,q,v1,v2,why)<=0)
        { txt=why+" (con la priorita' M15 non si ripiega su M5)"; return 0; }
      int n=ArraySize(v1);
      int c=CrossAt(v1,v2,n-1);
      g_pM15w1=v1[n-1]; g_pM15w2=v2[n-1]; g_pM15Cross=c; g_pnlM15Bar=q[n-1].time;
      if(c!=0)
        {
         dir=c; kind=KIND_SPECIAL;
         txt="incrocio WT M15 "+(c>0 ? "rialzista" : "ribassista")+" alla chiusura delle "+RomeHHMMofSrv(candle)+
             " | M15 wt1 "+WTStr(v1[n-2])+"->"+WTStr(v1[n-1])+", wt2 "+WTStr(v2[n-2])+"->"+WTStr(v2[n-1]);
         return 1;
        }
      m15Info=" | M15: nessun incrocio (wt1 "+WTStr(v1[n-1])+", wt2 "+WTStr(v2[n-1])+")";
     }
   MqlRates r[]; double w1[],w2[]; string why5="";
   if(ComputeWT(PERIOD_M5,candle,M5_SEC,r,w1,w2,why5)<=0) { txt=why5; return 0; }
   int n5=ArraySize(w1);
   int k=-1;
   int d=LastCross(w1,w2,n5-1,k);
   g_pM5w1=w1[n5-1]; g_pM5w2=w2[n5-1]; g_pM5Dir=d; g_pnlM5Bar=r[n5-1].time;
   g_pM5CrossClose=(k>=0) ? (datetime)((long)r[k].time+M5_SEC) : 0;
   if(d==0) { txt="nessun incrocio WT M5 nelle ultime "+I2S(n5)+" candele"+m15Info; return -1; }
   dir=d; kind=KIND_NORMAL;
   txt="ultimo incrocio WT M5 "+(d>0 ? "rialzista" : "ribassista")+" confermato alle "+RomeHHMMofSrv(g_pM5CrossClose)+
       " ("+I2S(n5-1-k)+" candele fa) | M5 wt1 "+WTStr(w1[n5-1])+", wt2 "+WTStr(w2[n5-1])+m15Info;
   return 1;
  }

//+------------------------------------------------------------------+
//| Invio ordine                                                     |
//| 1 = eseguito, 0 = errore temporaneo, -1 = definitivo,            |
//| -2 = esito incerto (nessun nuovo invio: rischio di duplicato)    |
//+------------------------------------------------------------------+
int SendEntry(const int dir,const int kind,const double lots,const string tag,string &msg,int &reason)
  {
   reason=SK_SEND;
   MqlTick tk;
   if(!SymbolInfoTick(g_sym,tk)) { msg="quotazione non disponibile"; return 0; }
   double price=(dir>0) ? tk.ask : tk.bid;
   double slD=SLDist(kind), tpD=TPDist(kind);
   double sl=NormPrice(dir>0 ? price-slD : price+slD);
   double tp=NormPrice(dir>0 ? price+tpD : price-tpD);

   MqlTradeRequest rq;
   MqlTradeCheckResult cr;
   MqlTradeResult rs;
   ZeroMemory(rq); ZeroMemory(cr); ZeroMemory(rs);
   rq.action      =TRADE_ACTION_DEAL;
   rq.symbol      =g_sym;
   rq.volume      =lots;
   rq.type        =(dir>0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   rq.price       =NormPrice(price);
   rq.sl          =sl;
   rq.tp          =tp;
   rq.deviation   =InpDeviationPoints;
   rq.magic       =InpMagic;
   rq.comment     =tag;
   rq.type_filling=g_filling;
   rq.type_time   =ORDER_TIME_GTC;

   if(!OrderCheck(rq,cr))
     {
      msg="OrderCheck: "+RetcodeStr(cr.retcode)+" "+cr.comment+" (margine libero dopo "+D2S(cr.margin_free,2)+")";
      if(cr.retcode==TRADE_RETCODE_NO_MONEY) { reason=SK_MARGIN; return 0; }
      return IsTransientRetcode(cr.retcode) ? 0 : -1;
     }
   ResetLastError();
   bool ok=OrderSend(rq,rs);
   int err=GetLastError();
   msg="OrderSend "+(ok ? "inviato" : "fallito")+" | "+RetcodeStr(rs.retcode)+" ("+I2S(rs.retcode)+")"+
       " | richiesto "+DirStr(dir)+" "+LotStr(lots)+" a "+PStr(rq.price)+" SL "+PStr(sl)+" TP "+PStr(tp)+
       " | eseguito "+LotStr(rs.volume)+" a "+PStr(rs.price)+
       (rs.price>0.0 ? " (slippage "+D2S((dir>0 ? rs.price-rq.price : rq.price-rs.price)/InpPipSize,1)+" pip)" : "")+
       " | deal #"+I2S((long)rs.deal)+" ordine #"+I2S((long)rs.order)+" | server: "+rs.comment+
       (ok ? "" : " | errore "+I2S(err));
   if(rs.retcode==TRADE_RETCODE_DONE || rs.retcode==TRADE_RETCODE_DONE_PARTIAL || rs.retcode==TRADE_RETCODE_PLACED)
      return 1;
   if(rs.retcode==TRADE_RETCODE_TIMEOUT || rs.retcode==TRADE_RETCODE_CONNECTION || (!ok && rs.retcode==0))
     { reason=SK_UNCERTAIN; return -2; }
   if(rs.retcode==TRADE_RETCODE_NO_MONEY) { reason=SK_MARGIN; return 0; }
   if(IsTransientRetcode(rs.retcode)) return 0;
   return -1;
  }

//+------------------------------------------------------------------+
//| Gestione della candela M5 corrente                               |
//+------------------------------------------------------------------+
void FinalizeCandle(const int reason,const string msg)
  {
   g_candleDone=true;
   if(reason>=0 && reason<SK_N) g_skip[reason]++;
   SetGVLastBar(g_candle);
   Log("CANDELA",RomeHHMMofSrv(g_candle)+" nessuna apertura: "+msg);
  }

void Transient(const int reason,const string msg)
  {
   g_candleReason=reason;
   if(msg!=g_candleMsg)
     {
      g_candleMsg=msg;
      Log("ATTESA",RomeHHMMofSrv(g_candle)+": "+msg+" (nuovo tentativo entro "+I2S(InpEntryWindowSec)+" s dall'apertura della candela)");
     }
  }

void ProcessEntry(const datetime nowSrv)
  {
   datetime candle=(datetime)(((long)nowSrv/M5_SEC)*M5_SEC);
   if(candle!=g_candle)
     {
      if(!g_candleDone && g_candle>0)
         FinalizeCandle(g_candleReason>=0 ? g_candleReason : SK_DATA,"candela terminata: "+g_candleMsg);
      g_candle=candle;
      g_candleDone=false;
      g_candleMsg="";
      g_candleReason=-1;
      g_sendAttempts=0;
      g_signalLogged=false;
      datetime cUtc=ServerToUtc(candle);
      if(!InSessionMin(RomeMinuteOfDay(cUtc))) { g_candleDone=true; return; }
      g_statCandles++;
      if(RomeNYDiffMin(cUtc)!=g_normalDiffMin) g_statMismatchCand++;
      if(GVLastBar()>=candle)
        {
         g_candleDone=true;
         Log("CANDELA",RomeHHMMofSrv(candle)+" gia' elaborata prima del riavvio: nessuna nuova valutazione");
         return;
        }
      if((long)nowSrv-(long)candle>InpEntryWindowSec)
        {
         FinalizeCandle(SK_LATE,"candela iniziata da "+I2S((long)nowSrv-(long)candle)+" s (avvio o riconnessione oltre la finestra di "+I2S(InpEntryWindowSec)+" s)");
         return;
        }
     }
   if(g_candleDone) return;

   if((long)nowSrv-(long)candle>InpEntryWindowSec)
     {
      FinalizeCandle(g_candleReason>=0 ? g_candleReason : SK_DATA,"finestra di "+I2S(InpEntryWindowSec)+" s scaduta: "+g_candleMsg);
      return;
     }

   // la nuova candela M5 deve esistere (primo tick ricevuto)
   MqlRates b0[];
   if(CopyRates(g_sym,PERIOD_M5,0,1,b0)!=1 || b0[0].time!=candle) { Transient(SK_DATA,"attesa della prima quotazione della candela"); return; }

   // stato del giorno
   if(g_statsDirty || !g_statsOk) RecalcDay();
   if(!g_statsOk) { Transient(SK_DATA,"storico del conto non disponibile"); return; }
   if(g_limitHit) { FinalizeCandle(SK_DAILYLIMIT,"limite giornaliero "+D2S(InpDailyRiskPct,2)+"% raggiunto (P/L netto "+Money(g_netPL)+")"); return; }
   if(g_entries>=InpMaxTradesPerDay) { FinalizeCandle(SK_MAXTRADES,"raggiunte "+I2S(g_entries)+" aperture su "+I2S(InpMaxTradesPerDay)); return; }

   // orario e connessione affidabili
   if(!ClockUsable())      { Transient(SK_CLOCK,"orario non determinabile con sicurezza"); return; }
   if(!ConnectionUsable()) { Transient(SK_TRADEOFF,"terminale non connesso o appena riconnesso"); return; }

   // protezione da duplicati (storico, posizioni aperte, variabile globale)
   string core=CandleCore(candle);
   if(CoreUsed(core)) { FinalizeCandle(SK_DUP,"operazione gia' presente per la candela "+core); return; }

   // segnale (M15 prioritario)
   int dir=0, kind=0;
   string sig="";
   int rs=DetermineSignal(candle,dir,kind,sig);
   if(rs==0) { Transient(SK_DATA,sig); return; }
   if(rs<0)  { FinalizeCandle(SK_NOSIGNAL,sig); return; }
   if(!g_signalLogged)
     {
      g_signalLogged=true;
      Log("SEGNALE",RomeHHMMofSrv(candle)+" "+KindStr(kind)+" "+DirStr(dir)+" | "+sig);
     }
   if((dir>0 && !InpAllowBuy) || (dir<0 && !InpAllowSell))
     {
      FinalizeCandle(SK_DIRECTION,"operazioni "+DirStr(dir)+" disabilitate"+(kind==KIND_SPECIAL ? " (il segnale M15 sostituisce quello M5: nessuna apertura)" : ""));
      return;
     }
   string why="";
   if(!TradingAllowed(dir,why)) { Transient(SK_TRADEOFF,why); return; }

   // spread
   MqlTick tk;
   if(!SymbolInfoTick(g_sym,tk) || tk.ask<=0.0 || tk.bid<=0.0) { Transient(SK_DATA,"quotazione non disponibile"); return; }
   double spread=tk.ask-tk.bid;
   if(InpMaxSpreadPips>0.0 && spread>InpMaxSpreadPips*InpPipSize+1e-9)
     { Transient(SK_SPREAD,"spread "+D2S(spread/InpPipSize,1)+" pip oltre il massimo "+D2S(InpMaxSpreadPips,1)); return; }

   // distanza minima del broker (mai allargare SL/TP)
   double slD=SLDist(kind), tpD=TPDist(kind);
   double minD=(double)SymbolInfoInteger(g_sym,SYMBOL_TRADE_STOPS_LEVEL)*g_point;
   if(minD>0.0 && (slD-spread<minD || tpD+spread<minD))
     { FinalizeCandle(SK_STOPS,"SL/TP piu' vicini della distanza minima del broker ("+D2S(minD,g_digits)+")"); return; }

   // size
   double residual=ResidualBudget();
   double risk=MathMin(g_nominalRisk,residual);
   double lots=0.0, lossLot=0.0;
   int cl=CalcLots(dir,slD,risk,tk,lots,lossLot,why);
   if(cl==0) { Transient(SK_CALC,"calcolo della size non affidabile: "+why); return; }
   if(cl<0)  { FinalizeCandle(SK_SIZE,why+" (rischio disponibile "+Money(risk)+")"); return; }
   if(g_volLimit>0.0 && MyOpenVolume()+lots>g_volLimit+1e-9)
     { FinalizeCandle(SK_SIZE,"volume totale oltre il limite del simbolo "+LotStr(g_volLimit)); return; }

   // margine
   double price=(dir>0) ? tk.ask : tk.bid;
   double margin=0.0;
   if(!OrderCalcMargin(dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,g_sym,lots,price,margin))
     { Transient(SK_CALC,"OrderCalcMargin fallito (errore "+I2S(GetLastError())+")"); return; }
   double freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin>freeM)
     { Transient(SK_MARGIN,"margine richiesto "+Money(margin)+" oltre il margine libero "+Money(freeM)+" (la size non viene ridotta)"); return; }

   // invio
   g_sendAttempts++;
   string tag=MakeTag(kind,core);
   Log("INVIO",RomeHHMMofSrv(candle)+" "+KindStr(kind)+" "+DirStr(dir)+" "+LotStr(lots)+" lotti | rischio "+Money(lots*lossLot)+
       " (nominale "+Money(g_nominalRisk)+", residuo "+Money(residual)+") | perdita allo SL per 1 lotto "+Money(lossLot)+
       " | SL "+D2S(slD,2)+" USD, TP "+D2S(tpD,2)+" USD | spread "+D2S(spread/InpPipSize,1)+" pip | margine "+Money(margin)+
       " | tentativo "+I2S(g_sendAttempts)+"/"+I2S(InpMaxSendAttempts)+" | commento "+tag);
   string msg="";
   int reason=SK_SEND;
   int res=SendEntry(dir,kind,lots,tag,msg,reason);
   Log("ESITO",msg);
   if(res==1)
     {
      AddTag(tag);
      g_entries++;
      if(kind==KIND_SPECIAL) { g_entriesS++; g_statEntriesS++; } else { g_entriesN++; g_statEntriesN++; }
      g_statsDirty=true;
      g_candleDone=true;
      SetGVLastBar(candle);
      return;
     }
   if(res==-2)
     {
      AddTag(tag);
      FinalizeCandle(SK_UNCERTAIN,"esito dell'invio incerto: nessun nuovo invio su questa candela per evitare duplicati. Verificare le posizioni.");
      Notify("esito incerto dell'ordine "+tag+": controllare manualmente le posizioni");
      return;
     }
   if(res==0 && g_sendAttempts<InpMaxSendAttempts) { Transient(reason,msg); return; }
   FinalizeCandle(reason,msg);
  }

//+------------------------------------------------------------------+
//| SL/TP: riallineamento e posizioni senza protezione               |
//+------------------------------------------------------------------+
bool ApplyLevels(const ulong ticket,const bool realign)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   int kind=KindFromComment(PositionGetString(POSITION_COMMENT));
   if(kind==0) kind=KIND_NORMAL;
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL=PositionGetDouble(POSITION_SL);
   double curTP=PositionGetDouble(POSITION_TP);
   double vol=PositionGetDouble(POSITION_VOLUME);
   double slD=SLDist(kind), tpD=TPDist(kind);
   double sl=NormPrice(pt==POSITION_TYPE_BUY ? open-slD : open+slD);
   double tp=NormPrice(pt==POSITION_TYPE_BUY ? open+tpD : open-tpD);
   if(!realign)
     {
      // solo i livelli mancanti
      if(curSL>0.0) sl=curSL;
      if(curTP>0.0) tp=curTP;
     }
   bool slOk=(curSL>0.0 && MathAbs(curSL-sl)<g_tickSize*0.5);
   bool tpOk=(curTP>0.0 && MathAbs(curTP-tp)<g_tickSize*0.5);
   if(slOk && tpOk) return true;

   MqlTick tk;
   if(!SymbolInfoTick(g_sym,tk)) return false;
   double lim=MathMax((double)SymbolInfoInteger(g_sym,SYMBOL_TRADE_STOPS_LEVEL),
                      (double)SymbolInfoInteger(g_sym,SYMBOL_TRADE_FREEZE_LEVEL))*g_point;
   double ref=(pt==POSITION_TYPE_BUY) ? tk.bid : tk.ask;
   bool valid=(pt==POSITION_TYPE_BUY) ? (sl<ref-lim && tp>ref+lim) : (sl>ref+lim && tp<ref-lim);
   if(!valid)
     {
      if(realign)
        {
         Log("LIVELLI","posizione #"+I2S((long)ticket)+": riallineamento a SL "+PStr(sl)+" TP "+PStr(tp)+
             " non applicabile al prezzo "+PStr(ref)+": restano i livelli inviati con l'ordine");
         return false;
        }
      bool slMissingAndBeyond=(curSL<=0.0) && ((pt==POSITION_TYPE_BUY) ? (ref<=sl) : (ref>=sl));
      if(slMissingAndBeyond)
        {
         Notify("posizione #"+I2S((long)ticket)+" senza SL e gia' oltre il livello previsto "+PStr(sl)+": chiusura immediata");
         if(g_trade.PositionClose(ticket))
            Log("CHIUSURA","#"+I2S((long)ticket)+" chiusa per mancanza di SL: "+RetcodeStr(g_trade.ResultRetcode()));
         return false;
        }
      Log("LIVELLI","ATTENZIONE posizione #"+I2S((long)ticket)+" senza SL/TP completi e livelli non applicabili ora: nuovo tentativo tra 10 s");
      return false;
     }
   if(!g_trade.PositionModify(ticket,sl,tp))
     {
      Log("LIVELLI","#"+I2S((long)ticket)+" modifica SL/TP fallita: "+RetcodeStr(g_trade.ResultRetcode())+" "+g_trade.ResultComment());
      return false;
     }
   uint rc=g_trade.ResultRetcode();
   Log("LIVELLI","#"+I2S((long)ticket)+" "+(realign ? "riallineata" : "protezione impostata")+" | apertura "+PStr(open)+
       " volume "+LotStr(vol)+" | SL "+PStr(curSL)+" -> "+PStr(sl)+" | TP "+PStr(curTP)+" -> "+PStr(tp)+" | "+RetcodeStr(rc));
   if(rc==TRADE_RETCODE_DONE && realign) g_statRealign++;
   return (rc==TRADE_RETCODE_DONE);
  }

void QueueRealign(const ulong ticket)
  {
   for(int i=0;i<ArraySize(g_realign);i++) if(g_realign[i]==ticket) return;
   int n=ArraySize(g_realign);
   ArrayResize(g_realign,n+1);
   ArrayResize(g_realignTries,n+1);
   g_realign[n]=ticket;
   g_realignTries[n]=0;
  }

void RemoveRealign(const int i)
  {
   int n=ArraySize(g_realign);
   for(int k=i;k<n-1;k++) { g_realign[k]=g_realign[k+1]; g_realignTries[k]=g_realignTries[k+1]; }
   ArrayResize(g_realign,n-1);
   ArrayResize(g_realignTries,n-1);
  }

void ManageProtection(const datetime nowSrv)
  {
   for(int i=ArraySize(g_realign)-1;i>=0;i--)
     {
      ulong t=g_realign[i];
      if(!PositionSelectByTicket(t))
        {
         g_realignTries[i]++;
         if(g_realignTries[i]>=5) RemoveRealign(i);
         continue;
        }
      ApplyLevels(t,true);
      RemoveRealign(i);
     }
   if((long)nowSrv-(long)g_lastProtectCheck<10) return;
   g_lastProtectCheck=nowSrv;
   ulong tk[];
   int n=CollectMyPositions(tk);
   for(int k=0;k<n;k++)
     {
      if(!PositionSelectByTicket(tk[k])) continue;
      if(PositionGetDouble(POSITION_SL)<=0.0 || PositionGetDouble(POSITION_TP)<=0.0)
         ApplyLevels(tk[k],false);
     }
  }

//+------------------------------------------------------------------+
//| Chiusura di fine sessione (17:30 italiane)                       |
//+------------------------------------------------------------------+
void ManageSessionClose(const datetime nowSrv,const datetime nowUtc)
  {
   if(!InpCloseAtSessionEnd) return;
   if(InSessionMin(RomeMinuteOfDay(nowUtc))) return;
   if(nowSrv<g_nextCloseTry) return;
   ulong tk[];
   int n=CollectMyPositions(tk);
   if(n==0) return;
   g_nextCloseTry=(datetime)((long)nowSrv+5);
   for(int k=0;k<n;k++)
     {
      if(!PositionSelectByTicket(tk[k])) continue;
      double pl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      string c=PositionGetString(POSITION_COMMENT);
      bool ok=g_trade.PositionClose(tk[k]);
      uint rc=g_trade.ResultRetcode();
      Log("CHIUSURA","fine sessione "+MinToHHMM(g_endMin)+" Italia | #"+I2S((long)tk[k])+" "+c+" | P/L flottante "+Money(pl)+
          " | "+(ok ? "inviata" : "fallita")+": "+RetcodeStr(rc)+" "+g_trade.ResultComment()+
          ((ok && rc==TRADE_RETCODE_DONE) ? "" : " | nuovo tentativo tra 5 s"));
      if(ok && rc==TRADE_RETCODE_DONE) g_statSessionClose++;
     }
   g_statsDirty=true;
  }

//+------------------------------------------------------------------+
//| PANNELLO                                                         |
//+------------------------------------------------------------------+
void PanelCreate()
  {
   if(!g_panelOn) return;
   string bg=PANEL_PREFIX+"BG";
   ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,5);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,470);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,PANEL_LINES*15+12);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'20,24,32');
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   for(int i=0;i<PANEL_LINES;i++)
     {
      string n=PANEL_PREFIX+I2S(i);
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,12);
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,26+i*15);
      ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,n,OBJPROP_COLOR,clrGainsboro);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
      ObjectSetString(0,n,OBJPROP_TEXT," ");
     }
   ChartRedraw();
  }

void PanelSet(const int i,string txt,const color c)
  {
   if(StringLen(txt)>62) txt=StringSubstr(txt,0,62);
   if(txt=="") txt=" ";
   string n=PANEL_PREFIX+I2S(i);
   ObjectSetString(0,n,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
  }

// WaveTrend per il pannello (solo informativo, ricalcolato a ogni nuova candela)
void PanelRefreshWT()
  {
   MqlRates r[]; double w1[],w2[];
   datetime t0[];
   if(CopyTime(g_sym,PERIOD_M5,1,1,t0)==1 && t0[0]!=g_pnlM5Bar)
     {
      int got=CopyRates(g_sym,PERIOD_M5,1,InpWTBars,r);
      if(got>=WT_MIN_BARS)
        {
         CalcWT(r,got,w1,w2);
         int k=-1;
         g_pM5Dir=LastCross(w1,w2,got-1,k);
         g_pM5w1=w1[got-1]; g_pM5w2=w2[got-1];
         g_pM5CrossClose=(k>=0) ? (datetime)((long)r[k].time+M5_SEC) : 0;
         g_pnlM5Bar=r[got-1].time;
        }
     }
   if(CopyTime(g_sym,PERIOD_M15,1,1,t0)==1 && t0[0]!=g_pnlM15Bar)
     {
      int got=CopyRates(g_sym,PERIOD_M15,1,InpWTBars,r);
      if(got>=WT_MIN_BARS)
        {
         CalcWT(r,got,w1,w2);
         g_pM15Cross=CrossAt(w1,w2,got-1);
         g_pM15w1=w1[got-1]; g_pM15w2=w2[got-1];
         g_pnlM15Bar=r[got-1].time;
        }
     }
  }

string ZoneLabel(const double w1)
  {
   if(w1==EMPTY_VALUE) return "";
   if(w1>=InpWTOverbought) return "ipercomprato";
   if(w1<=InpWTOversold)   return "ipervenduto";
   return "zona neutra";
  }

void UpdatePanel(const datetime nowSrv,const datetime nowUtc)
  {
   if(!g_panelOn) return;
   if(nowSrv==g_lastPanel) return;
   g_lastPanel=nowSrv;
   PanelRefreshWT();

   datetime rome=UtcToZone(ZONE_ROME,nowUtc);
   datetime ny=UtcToZone(ZONE_NY,nowUtc);
   bool inSes=InSessionMin(RomeMinuteOfDay(nowUtc));
   MqlTick tk;
   bool hasTick=SymbolInfoTick(g_sym,tk);
   double spread=hasTick ? (tk.ask-tk.bid) : 0.0;

   // stato del trading
   string state="ATTIVO", reason="";
   color sc=clrLime;
   string why="";
   if(!ClockUsable())                       { state="BLOCCATO"; reason="orario non determinabile"; }
   else if(!ConnectionUsable())             { state="BLOCCATO"; reason="terminale non connesso"; }
   else if(!TradingAllowed(0,why))          { state="BLOCCATO"; reason=why; }
   else if(!g_statsOk)                      { state="BLOCCATO"; reason="storico non disponibile"; }
   else if(g_limitHit)                      { state="BLOCCATO"; reason="limite giornaliero raggiunto"; }
   else if(g_entries>=InpMaxTradesPerDay)   { state="BLOCCATO"; reason="aperture massime raggiunte"; }
   else if(!inSes)                          { state="FUORI SESSIONE"; reason=""; }
   if(state=="BLOCCATO") sc=clrTomato;
   if(state=="FUORI SESSIONE") sc=clrGold;

   // size teoriche correnti
   double risk=MathMin(g_nominalRisk,ResidualBudget());
   string szN="n/d", szS="n/d";
   if(hasTick)
     {
      double l=0.0, ll=0.0; string ww="";
      if(CalcLots(1,SLDist(KIND_NORMAL),risk,tk,l,ll,ww)==1)  szN=LotStr(l);
      if(CalcLots(1,SLDist(KIND_SPECIAL),risk,tk,l,ll,ww)==1) szS=LotStr(l);
     }
   int openCnt=0, noSL=0;
   double openRisk=OpenRiskMoney(openCnt,noSL);

   datetime d0=DayStart(rome);
   datetime sUtc=ZoneToUtc(ZONE_ROME,(datetime)((long)d0+(long)g_startMin*60));
   datetime eUtc=ZoneToUtc(ZONE_ROME,(datetime)((long)d0+(long)g_endMin*60));
   bool mism=(RomeNYDiffMin(nowUtc)!=g_normalDiffMin);

   int i=0;
   color w=clrGainsboro;
   PanelSet(i++,EA_NAME+" v"+EA_VERSION+" | "+g_sym+" | Magic "+I2S((long)InpMagic),clrWhite);
   PanelSet(i++,"Ora italiana : "+DTShort(rome)+" ("+RomeZoneName(nowUtc)+")",w);
   PanelSet(i++,"Ora New York : "+DTShort(ny)+" ("+NYZoneName(nowUtc)+")",w);
   PanelSet(i++,"Ora server   : "+DTShort(nowSrv)+" ("+OffStr(ZoneOffSec(ZONE_SERVER,nowUtc))+")",w);
   PanelSet(i++,"Ora UTC      : "+DTShort(nowUtc)+" | orologio "+(ClockUsable() ? "OK" : "NON AFFIDABILE"),ClockUsable() ? w : clrTomato);
   PanelSet(i++,"Sessione "+MinToHHMM(g_startMin)+"-"+MinToHHMM(g_endMin)+" Italia = "+HHMM(UtcToZone(ZONE_SERVER,sUtc))+"-"+HHMM(UtcToZone(ZONE_SERVER,eUtc))+" server"+(mism ? " (sfas.)" : ""),w);
   PanelSet(i++,"Stato sessione: "+(inSes ? "APERTA" : "CHIUSA"),inSes ? clrLime : clrGold);
   PanelSet(i++,"Operazioni oggi: "+I2S(g_entries)+" / "+I2S(InpMaxTradesPerDay)+"  (normali "+I2S(g_entriesN)+", M15 "+I2S(g_entriesS)+")",w);
   PanelSet(i++,"Capitale inizio giorno: "+Money(g_refCapital),w);
   PanelSet(i++,"Balance: "+D2S(AccountInfoDouble(ACCOUNT_BALANCE),2)+"  Equity: "+Money(AccountInfoDouble(ACCOUNT_EQUITY)),w);
   PanelSet(i++,"Rischio giornaliero max: "+Money(g_budget)+" ("+D2S(InpDailyRiskPct,2)+"%)",w);
   PanelSet(i++,"Rischio nominale per operazione: "+Money(g_nominalRisk),w);
   PanelSet(i++,"P/L netto realizzato oggi: "+Money(g_netPL),g_netPL<0.0 ? clrSalmon : w);
   PanelSet(i++,"Perdite realizzate: "+Money(g_realizedLoss),g_realizedLoss<0.0 ? clrSalmon : w);
   PanelSet(i++,"Budget residuo: "+Money(ResidualBudget()),w);
   PanelSet(i++,"Rischio aperto: "+I2S(openCnt)+" pos, "+Money(openRisk)+" allo SL"+(noSL>0 ? " ("+I2S(noSL)+" senza SL!)" : ""),noSL>0 ? clrTomato : w);
   PanelSet(i++,"Size normale: "+szN+" lotti | Size M15: "+szS+" lotti",w);
   PanelSet(i++,"Spread: "+D2S(spread/InpPipSize,1)+" pip (max "+(InpMaxSpreadPips>0.0 ? D2S(InpMaxSpreadPips,1) : "nessuno")+")",
            (InpMaxSpreadPips>0.0 && spread>InpMaxSpreadPips*InpPipSize) ? clrTomato : w);
   PanelSet(i++,"WT M5 : wt1 "+WTStr(g_pM5w1)+" wt2 "+WTStr(g_pM5w2)+" "+ZoneLabel(g_pM5w1),w);
   PanelSet(i++,"        ultimo incrocio "+DirStr(g_pM5Dir)+(g_pM5CrossClose>0 ? " alle "+RomeHHMMofSrv(g_pM5CrossClose) : ""),w);
   PanelSet(i++,"WT M15: wt1 "+WTStr(g_pM15w1)+" wt2 "+WTStr(g_pM15w2)+" "+ZoneLabel(g_pM15w1)+
                (g_pM15Cross!=0 ? " | incrocio "+DirStr(g_pM15Cross) : ""),w);
   PanelSet(i++,"STATO TRADING: "+state,sc);
   PanelSet(i++,reason,sc);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| VERIFICA DELLO STORICO (a fine test o alla rimozione)            |
//+------------------------------------------------------------------+
void VerifyHistory()
  {
   datetime to=(datetime)((long)ServerNow()+86400);
   if(!HistorySelect(0,to)) { Log("VERIFICA","storico non disponibile"); return; }
   CHashMap<long,int> posIdx;
   CHashMap<int,int>  dayIdx;
   CHashMap<long,int> candleSeen;
   int    pKind[]; int pDay[]; double pPL[]; int np=0;
   int    dKey[];  int dCnt[]; double dPL[]; int nd=0;
   int nIn=0, nN=0, nS=0, dup=0, outWin=0, m15Bad=0, noSLTP=0, late=0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong t=HistoryDealGetTicket(i);
      if(t==0) continue;
      if(HistoryDealGetString(t,DEAL_SYMBOL)!=g_sym || (ulong)HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic) continue;
      long pos=HistoryDealGetInteger(t,DEAL_POSITION_ID);
      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY);
      datetime tm=(datetime)HistoryDealGetInteger(t,DEAL_TIME);
      datetime utc=ServerToUtc(tm);
      int dk=RomeDayKey(utc);
      double res=DealResult(t);
      int di=-1;
      if(!dayIdx.TryGetValue(dk,di))
        {
         di=nd; nd++;
         ArrayResize(dKey,nd); ArrayResize(dCnt,nd); ArrayResize(dPL,nd);
         dKey[di]=dk; dCnt[di]=0; dPL[di]=0.0;
         dayIdx.Add(dk,di);
        }
      dPL[di]+=res;
      int pi=-1;
      bool known=posIdx.TryGetValue(pos,pi);
      if(en==DEAL_ENTRY_IN)
        {
         if(known) { pPL[pi]+=res; continue; } // fill parziale della stessa posizione
         pi=np; np++;
         ArrayResize(pKind,np); ArrayResize(pDay,np); ArrayResize(pPL,np);
         string c=HistoryDealGetString(t,DEAL_COMMENT);
         int kind=KindFromComment(c);
         if(kind==0) kind=KIND_NORMAL;
         pKind[pi]=kind; pDay[pi]=dk; pPL[pi]=res;
         posIdx.Add(pos,pi);
         nIn++;
         if(kind==KIND_SPECIAL) nS++; else nN++;
         dCnt[di]++;
         long cs=((long)tm/M5_SEC)*M5_SEC;
         int dummy=0;
         if(candleSeen.TryGetValue(cs,dummy)) dup++; else candleSeen.Add(cs,1);
         int cm=RomeMinuteOfDay(ServerToUtc((datetime)cs));
         if(!InSessionMin(cm) || (long)tm-cs>InpEntryWindowSec+5) outWin++;
         if(kind==KIND_SPECIAL && (cs%M15_SEC)!=0) m15Bad++;
         ulong ord=(ulong)HistoryDealGetInteger(t,DEAL_ORDER);
         if(HistoryOrderGetDouble(ord,ORDER_SL)<=0.0 || HistoryOrderGetDouble(ord,ORDER_TP)<=0.0) noSLTP++;
        }
      else
        {
         if(known) pPL[pi]+=res;
         if((en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY) && known && InpCloseAtSessionEnd)
           {
            int m=RomeMinuteOfDay(utc);
            if(dk!=pDay[pi] || m>=g_endMin+2) late++;
           }
        }
     }
   int maxDay=0, worstDayKey=0; double worstDay=0.0;
   for(int j=0;j<nd;j++)
     {
      if(dCnt[j]>maxDay) maxDay=dCnt[j];
      if(dPL[j]<worstDay) { worstDay=dPL[j]; worstDayKey=dKey[j]; }
     }
   double plN=0.0, plS=0.0; int winN=0, winS=0, lossN=0, lossS=0;
   for(int k=0;k<np;k++)
     {
      if(pKind[k]==KIND_SPECIAL) { plS+=pPL[k]; if(pPL[k]>0.0) winS++; else lossS++; }
      else                       { plN+=pPL[k]; if(pPL[k]>0.0) winN++; else lossN++; }
     }
   Log("VERIFICA","aperture "+I2S(nIn)+" (normali "+I2S(nN)+", M15 "+I2S(nS)+") in "+I2S(nd)+" giorni | massimo in un giorno "+I2S(maxDay)+
       " (limite "+I2S(InpMaxTradesPerDay)+") | candele con piu' aperture "+I2S(dup)+" | aperture fuori sessione/finestra "+I2S(outWin)+
       " | M15 fuori dagli slot :00/:15/:30/:45 "+I2S(m15Bad)+" | ordini senza SL o TP "+I2S(noSLTP)+" | chiusure dopo fine sessione "+I2S(late));
   Log("VERIFICA","P/L netto normali "+Money(plN)+" ("+I2S(winN)+" vinte / "+I2S(lossN)+" perse) | M15 "+Money(plS)+
       " ("+I2S(winS)+" / "+I2S(lossS)+") | giorno peggiore "+I2S(worstDayKey)+" "+Money(worstDay));
   string ok=(maxDay<=InpMaxTradesPerDay && dup==0 && outWin==0 && m15Bad==0 && noSLTP==0 && late==0) ? "SUPERATA" : "NON SUPERATA";
   Log("VERIFICA","esito controlli automatici: "+ok);
  }

void LogRunStats()
  {
   Log("STATISTICHE","candele di sessione valutate "+I2S(g_statCandles)+" | aperture normali "+I2S(g_statEntriesN)+
       " | aperture M15 "+I2S(g_statEntriesS)+" | chiusure fine sessione "+I2S(g_statSessionClose)+
       " | giorni con limite 4% "+I2S(g_statLimitDays)+" | candele in settimane di sfasamento "+I2S(g_statMismatchCand)+
       " | riallineamenti SL/TP "+I2S(g_statRealign));
   Log("STATISTICHE","candele senza apertura -> nessun segnale "+I2S(g_skip[SK_NOSIGNAL])+", direzione disabilitata "+I2S(g_skip[SK_DIRECTION])+
       ", spread "+I2S(g_skip[SK_SPREAD])+", max operazioni "+I2S(g_skip[SK_MAXTRADES])+", limite giornaliero "+I2S(g_skip[SK_DAILYLIMIT])+
       ", size "+I2S(g_skip[SK_SIZE])+", margine "+I2S(g_skip[SK_MARGIN])+", dati "+I2S(g_skip[SK_DATA])+", orario "+I2S(g_skip[SK_CLOCK])+
       ", trading non consentito "+I2S(g_skip[SK_TRADEOFF])+", distanza stop "+I2S(g_skip[SK_STOPS])+", invio "+I2S(g_skip[SK_SEND])+
       ", esito incerto "+I2S(g_skip[SK_UNCERTAIN])+", duplicato evitato "+I2S(g_skip[SK_DUP])+", calcolo "+I2S(g_skip[SK_CALC])+
       ", avvio tardivo "+I2S(g_skip[SK_LATE]));
  }

//+------------------------------------------------------------------+
//| Ciclo principale                                                 |
//+------------------------------------------------------------------+
void Process()
  {
   if(g_busy) return;
   g_busy=true;
   datetime nowSrv=ServerNow();
   if(nowSrv>0)
     {
      datetime nowUtc=ServerToUtc(nowSrv);
      CheckConnection();
      CheckClock();
      int key=RomeDayKey(nowUtc);
      if(key!=g_dayKey) OnNewRomeDay(key,nowUtc);
      if(g_statsDirty || (long)nowSrv-(long)g_lastRecalc>=30) RecalcDay();

      int m=RomeMinuteOfDay(nowUtc);
      if(g_preDiagDay!=g_dayKey && m>=g_startMin-5 && m<g_startMin)
        {
         g_preDiagDay=g_dayKey;
         LogTimeDiagnostics("PRE-SESSIONE");
         LogDayStatus("PRE-SESSIONE");
        }
      if(!g_isTester && InpDiagEveryMin>0 && (long)nowUtc-(long)g_lastDiagUtc>=(long)InpDiagEveryMin*60)
        {
         g_lastDiagUtc=nowUtc;
         LogTimeDiagnostics("DIAGNOSTICA");
        }
      ManageSessionClose(nowSrv,nowUtc);
      ManageProtection(nowSrv);
      ProcessEntry(nowSrv);
      UpdatePanel(nowSrv,nowUtc);
     }
   g_busy=false;
  }

//+------------------------------------------------------------------+
//| Inizializzazione                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_sym=_Symbol;
   g_isTester=(bool)MQLInfoInteger(MQL_TESTER);
   g_isOptim=(bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_panelOn=InpShowPanel && !g_isOptim && (!g_isTester || (bool)MQLInfoInteger(MQL_VISUAL_MODE));
   g_accCur=AccountInfoString(ACCOUNT_CURRENCY);
   ArrayInitialize(g_skip,0);

   // --- input
   g_startMin=ParseHHMM(InpSessionStart);
   g_endMin=ParseHHMM(InpSessionEnd);
   string bad="";
   if(g_startMin<0 || g_endMin<0 || g_startMin>=g_endMin) bad="orari di sessione non validi (HH:MM, inizio prima della fine)";
   else if(InpDailyRiskPct<=0.0 || InpDailyRiskPct>100.0) bad="rischio giornaliero fuori da 0-100%";
   else if(InpMaxTradesPerDay<1 || InpMaxTradesPerDay>288) bad="numero massimo di operazioni fuori da 1-288";
   else if(InpPipSize<=0.0) bad="convenzione pip non valida";
   else if(InpNormalSLPips<=0.0 || InpNormalTPPips<=0.0 || InpM15SLPips<=0.0 || InpM15TPPips<=0.0) bad="SL/TP devono essere positivi";
   else if(InpWTChannelLen<1 || InpWTAverageLen<1 || InpWTSignalLen<1) bad="parametri WaveTrend non validi";
   else if(InpWTBars<WT_MIN_BARS) bad="InpWTBars deve essere almeno "+I2S(WT_MIN_BARS);
   else if(InpEntryWindowSec<1 || InpEntryWindowSec>=M5_SEC) bad="finestra di ingresso fuori da 1-299 secondi";
   else if(StringLen(InpCommentPrefix)<1 || StringLen(InpCommentPrefix)>10 || StringFind(InpCommentPrefix," ")>=0) bad="prefisso commento: 1-10 caratteri senza spazi";
   else if(InpMaxSendAttempts<1) bad="tentativi di invio almeno 1";
   if(bad!="")
     {
      Print("[WTX] PARAMETRI NON VALIDI: ",bad);
      return INIT_PARAMETERS_INCORRECT;
     }
   g_normalDiffMin=(InpRomeStdOffsetMin-InpNYStdOffsetMin);

   // --- file e variabili persistenti
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   g_gvLastBar="WTX_"+I2S(login)+"_"+I2S((long)InpMagic)+"_"+g_sym+"_LASTBAR"+(g_isTester ? "_T" : "");
   if(g_isTester && GlobalVariableCheck(g_gvLastBar)) GlobalVariableDel(g_gvLastBar);
   g_csvName=(InpCsvLog && !g_isOptim) ? "WTX_"+I2S(login)+"_"+g_sym+(g_isTester ? "_tester" : "")+".csv" : "";

   // --- simbolo
   if(InpSymbolPrefix!="" && StringFind(g_sym,InpSymbolPrefix)!=0)
     {
      Print("[WTX] SIMBOLO NON PREVISTO: il grafico e' ",g_sym,", atteso ",InpSymbolPrefix,"...");
      if(!g_isTester) Alert(EA_NAME,": aprire l'EA su un grafico ",InpSymbolPrefix);
      return INIT_FAILED;
     }
   if(!SymbolSelect(g_sym,true)) { Print("[WTX] impossibile selezionare ",g_sym); return INIT_FAILED; }
   g_digits   =(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   g_point    =SymbolInfoDouble(g_sym,SYMBOL_POINT);
   g_tickSize =SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_SIZE);
   g_tickValue=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_VALUE);
   g_contract =SymbolInfoDouble(g_sym,SYMBOL_TRADE_CONTRACT_SIZE);
   g_volMin   =SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   g_volMax   =SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   g_volStep  =SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   g_volLimit =SymbolInfoDouble(g_sym,SYMBOL_VOLUME_LIMIT);
   if(g_point<=0.0 || g_tickSize<=0.0 || g_contract<=0.0 || g_volMin<=0.0 || g_volMax<=0.0 || g_volStep<=0.0)
     {
      Print("[WTX] specifiche del simbolo non valide: point ",g_point," tick ",g_tickSize," contratto ",g_contract,
            " volumi ",g_volMin,"/",g_volMax,"/",g_volStep);
      return INIT_FAILED;
     }
   g_volDigits=StepDigits(g_volStep);
   string base=SymbolInfoString(g_sym,SYMBOL_CURRENCY_BASE);
   string prof=SymbolInfoString(g_sym,SYMBOL_CURRENCY_PROFIT);
   string marg=SymbolInfoString(g_sym,SYMBOL_CURRENCY_MARGIN);
   if(prof!="USD")
     {
      Print("[WTX] valuta di profitto del simbolo ",prof,": la convenzione pip in USD non e' applicabile");
      return INIT_FAILED;
     }
   if(InpPipSize<g_tickSize-1e-12)
     {
      Print("[WTX] 1 pip (",InpPipSize,") e' piu' piccolo del tick size (",g_tickSize,")");
      return INIT_FAILED;
     }
   int fm=(int)SymbolInfoInteger(g_sym,SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)      g_filling=ORDER_FILLING_FOK;
   else if((fm & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) g_filling=ORDER_FILLING_IOC;
   else                                                   g_filling=ORDER_FILLING_RETURN;

   // --- conto: servono posizioni multiple indipendenti -> hedging
   ENUM_ACCOUNT_MARGIN_MODE mm=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("[WTX] CONTO NON HEDGING: la strategia richiede posizioni multiple indipendenti con SL/TP propri");
      if(!g_isTester) Alert(EA_NAME,": serve un conto MT5 di tipo hedging");
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFilling(g_filling);
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   // --- log di avvio
   Log("AVVIO",EA_NAME+" v"+EA_VERSION+" su "+g_sym+(g_isTester ? " (STRATEGY TESTER)" : "")+" | grafico "+EnumToString((ENUM_TIMEFRAMES)_Period)+
       " | Magic "+I2S((long)InpMagic)+" | sessione "+MinToHHMM(g_startMin)+"-"+MinToHHMM(g_endMin)+" Italia | max "+I2S(InpMaxTradesPerDay)+
       " aperture | rischio "+D2S(InpDailyRiskPct,2)+"% | spread max "+D2S(InpMaxSpreadPips,1)+" pip | BUY "+YesNo(InpAllowBuy)+
       " SELL "+YesNo(InpAllowSell)+" M15 "+YesNo(InpEnableM15)+" | chiusura fine sessione "+YesNo(InpCloseAtSessionEnd));
   if(_Period!=PERIOD_M5) Log("AVVISO","il grafico non e' M5: l'EA usa comunque M5 e M15 internamente");
   Log("SIMBOLO",g_sym+" | digits "+I2S(g_digits)+" | point "+D2S(g_point,8)+" | tick size "+D2S(g_tickSize,8)+
       " | tick value "+D2S(g_tickValue,6)+" "+g_accCur+" | contratto "+D2S(g_contract,2)+" | lotto min "+LotStr(g_volMin)+
       " max "+LotStr(g_volMax)+" step "+D2S(g_volStep,4)+" | limite volume "+D2S(g_volLimit,2)+
       " | stops level "+I2S(SymbolInfoInteger(g_sym,SYMBOL_TRADE_STOPS_LEVEL))+" | freeze level "+I2S(SymbolInfoInteger(g_sym,SYMBOL_TRADE_FREEZE_LEVEL))+
       " | valute base/profitto/margine "+base+"/"+prof+"/"+marg+" | riempimento "+EnumToString(g_filling)+
       " | esecuzione "+EnumToString((ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(g_sym,SYMBOL_TRADE_EXEMODE)));
   Log("PIP","1 pip = "+D2S(InpPipSize,4)+" USD di prezzo = "+D2S(InpPipSize/g_point,1)+" point = "+D2S(InpPipSize/g_tickSize,1)+
       " tick | SL normale "+D2S(SLDist(KIND_NORMAL),2)+" USD, TP "+D2S(TPDist(KIND_NORMAL),2)+" USD | SL M15 "+D2S(SLDist(KIND_SPECIAL),2)+
       " USD, TP "+D2S(TPDist(KIND_SPECIAL),2)+" USD");
   if(MathAbs(SLDist(KIND_NORMAL)-InpNormalSLPips*InpPipSize)>1e-9 || MathAbs(SLDist(KIND_SPECIAL)-InpM15SLPips*InpPipSize)>1e-9)
      Log("AVVISO","le distanze in pip sono state arrotondate al tick size del simbolo");
   Log("CONTO","login "+I2S(login)+" | server "+AccountInfoString(ACCOUNT_SERVER)+" | societa' "+AccountInfoString(ACCOUNT_COMPANY)+
       " | valuta "+g_accCur+" | balance "+D2S(AccountInfoDouble(ACCOUNT_BALANCE),2)+" | equity "+D2S(AccountInfoDouble(ACCOUNT_EQUITY),2)+
       " | leva 1:"+I2S(AccountInfoInteger(ACCOUNT_LEVERAGE))+" | hedging");

   datetime nowSrv=ServerNow();
   datetime nowUtc=ServerToUtc(nowSrv);
   LogDstCalendar(YearOf(nowUtc));
   LogDstCalendar(YearOf(nowUtc)+1);
   CheckClock();
   OnNewRomeDay(RomeDayKey(nowUtc),nowUtc);

   // size di riferimento con i prezzi attuali (verifica della conversione valutaria)
   MqlTick tk;
   if(SymbolInfoTick(g_sym,tk) && tk.ask>0.0)
     {
      double l=0.0, ll=0.0; string w="";
      int r1=CalcLots(1,SLDist(KIND_NORMAL),g_nominalRisk,tk,l,ll,w);
      string s1=(r1==1) ? LotStr(l)+" lotti (perdita allo SL per 1 lotto "+Money(ll)+")" : "n/d: "+w;
      double usdLoss=SLDist(KIND_NORMAL)*g_contract;
      string conv=(r1==1 && ll>0.0) ? " | cambio implicito "+g_accCur+"/USD "+D2S(usdLoss/ll,5) : "";
      double l2=0.0, ll2=0.0; string w2="";
      int r2=CalcLots(1,SLDist(KIND_SPECIAL),g_nominalRisk,tk,l2,ll2,w2);
      string s2=(r2==1) ? LotStr(l2)+" lotti (perdita allo SL per 1 lotto "+Money(ll2)+")" : "n/d: "+w2;
      Log("RISCHIO","rischio nominale "+Money(g_nominalRisk)+" | size normale M5 "+s1+" | size speciale M15 "+s2+conv);
     }

   // posizioni gia' aperte (riavvio)
   ulong t[];
   int n=CollectMyPositions(t);
   for(int i=0;i<n;i++)
     {
      if(!PositionSelectByTicket(t[i])) continue;
      Log("RIAVVIO","posizione dell'EA trovata #"+I2S((long)t[i])+" "+PositionGetString(POSITION_COMMENT)+
          " "+(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? "BUY" : "SELL")+" "+LotStr(PositionGetDouble(POSITION_VOLUME))+
          " a "+PStr(PositionGetDouble(POSITION_PRICE_OPEN))+" SL "+PStr(PositionGetDouble(POSITION_SL))+" TP "+PStr(PositionGetDouble(POSITION_TP)));
     }
   g_lastProtectCheck=0;

   // la candela in corso all'avvio viene valutata solo se entro la finestra di ingresso
   g_candle=0;
   g_candleDone=true;

   PanelCreate();
   EventSetTimer(1);
   Process();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_dayKey!=0) LogDayStatus("STATO FINALE");
   LogRunStats();
   VerifyHistory();
   ObjectsDeleteAll(0,PANEL_PREFIX);
   ChartRedraw();
   Log("ARRESTO","EA rimosso (motivo "+I2S(reason)+")");
  }

void OnTick()  { Process(); }
void OnTimer() { Process(); }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   g_statsDirty=true;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=g_sym) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;
   ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   ENUM_DEAL_REASON rs=(ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON);
   string why=EnumToString(rs);
   if(rs==DEAL_REASON_SL) why="stop loss";
   else if(rs==DEAL_REASON_TP) why="take profit";
   else if(rs==DEAL_REASON_EXPERT) why="EA";
   else if(rs==DEAL_REASON_SO) why="stop out";
   Log("DEAL","#"+I2S((long)trans.deal)+" posizione #"+I2S(HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID))+
       " "+(en==DEAL_ENTRY_IN ? "APERTURA" : "CHIUSURA")+" "+
       ((ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal,DEAL_TYPE)==DEAL_TYPE_BUY ? "BUY" : "SELL")+" "+
       LotStr(HistoryDealGetDouble(trans.deal,DEAL_VOLUME))+" a "+PStr(HistoryDealGetDouble(trans.deal,DEAL_PRICE))+
       " | profitto "+D2S(HistoryDealGetDouble(trans.deal,DEAL_PROFIT),2)+" commissione "+D2S(HistoryDealGetDouble(trans.deal,DEAL_COMMISSION),2)+
       " swap "+D2S(HistoryDealGetDouble(trans.deal,DEAL_SWAP),2)+" fee "+D2S(HistoryDealGetDouble(trans.deal,DEAL_FEE),2)+" "+g_accCur+
       " | motivo "+why+" | "+HistoryDealGetString(trans.deal,DEAL_COMMENT));
   if(en==DEAL_ENTRY_IN && InpRealignSLTP)
      QueueRealign((ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID));
  }
//+------------------------------------------------------------------+
