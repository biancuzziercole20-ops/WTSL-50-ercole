//+------------------------------------------------------------------+
//|                                              WT67NDX100_100k.mq5 |
//|        Expert Advisor WaveTrend M15 - CFD Nasdaq 100 - FTMO/MT5  |
//|        Versione 100k: identica a WT67NDX100, lotto 1.00          |
//+------------------------------------------------------------------+
//| COSA FA                                                          |
//|  - Calcola internamente il WaveTrend (formula LazyBear) sulle    |
//|    sole candele M15 COMPLETATE: wt1 = linea, wt2 = puntini       |
//|    (media semplice di wt1).                                      |
//|  - BUY  quando wt1 incrocia wt2 dal basso verso l'alto.          |
//|  - SELL quando wt1 incrocia wt2 dall'alto verso il basso.        |
//|  - Ingressi solo per candele che chiudono nella finestra         |
//|    italiana (default 15:30-17:30 Europe/Rome).                   |
//|  - SL e TP fissi a 30 punti indice dal prezzo di apertura.       |
//|  - Massimo 3 operazioni al giorno (calendario italiano),         |
//|    ricostruite dallo storico del conto dopo ogni riavvio.        |
//|  - Reversal: segnale opposto -> chiusura verificata -> eventuale |
//|    apertura opposta (se finestra e limite lo consentono).        |
//|                                                                  |
//| ORARI                                                            |
//|  L'ora UTC viene ricavata dall'ora del server FTMO tramite la    |
//|  regola di offset impostata negli input (default GMT+2, +1 ora   |
//|  durante l'ora legale USA). Da UTC si ricavano ora italiana e    |
//|  ora di New York con le regole UE e USA calcolate in codice.     |
//|  Dal vivo la regola viene confrontata con TimeGMT(): se non      |
//|  coincide, le nuove aperture vengono bloccate (default).         |
//|                                                                  |
//| Tutte le scelte non ancora confermate dall'utente sono input     |
//| modificabili: vedi la documentazione allegata.                   |
//|                                                                  |
//| Nessuna DLL, nessuna libreria esterna: solo la libreria          |
//| standard di MetaTrader 5 (Trade\Trade.mqh).                      |
//+------------------------------------------------------------------+
#property copyright   "WT67NDX100_100k"
#property version     "1.00"
#property description "WT67NDX100_100k - WaveTrend M15 - CFD Nasdaq 100 - FTMO / MetaTrader 5"
#property description "Ingressi in finestra oraria italiana, SL/TP fissi, max operazioni giornaliere, reversal."

#include <Trade\Trade.mqh>

#define ZONE_ROME    0
#define ZONE_NY      1
#define ZONE_SERVER  2
#define BAR_SEC      900          // durata candela M15 in secondi
#define RECONNECT_WAIT_SEC 5      // attesa dopo riconnessione prima di nuove aperture

//+------------------------------------------------------------------+
//| Enumerazioni degli input                                         |
//+------------------------------------------------------------------+
enum ENUM_WT_CROSS
  {
   WT_CROSS_STANDARD = 0, // Standard: precedente <= puntini, attuale > puntini
   WT_CROSS_STRICT   = 1  // Rigoroso: l'ultimo stato non uguale deve essere opposto
  };

enum ENUM_SLTP_MODE
  {
   SLTP_WITH_ORDER       = 0, // SL/TP inviati con l'ordine (nessuna correzione)
   SLTP_ORDER_THEN_ALIGN = 1  // SL/TP con l'ordine + una sola correzione sul prezzo eseguito
  };

enum ENUM_WINDOW_MODE
  {
   WINDOW_ROME_FIXED = 0, // Finestra fissa in ora italiana
   WINDOW_FOLLOW_NY  = 1  // Finestra spostata con l'apertura di New York
  };

enum ENUM_SERVER_DST
  {
   SRV_DST_US   = 0, // Ora legale server con regola USA (FTMO)
   SRV_DST_EU   = 1, // Ora legale server con regola UE
   SRV_DST_NONE = 2  // Server senza ora legale (offset fisso)
  };

enum ENUM_TIME_CHECK
  {
   TIMECHECK_BLOCK = 0, // Incoerenza orari: blocca nuove aperture + avviso
   TIMECHECK_WARN  = 1, // Incoerenza orari: solo avviso
   TIMECHECK_OFF   = 2  // Nessun controllo
  };

//+------------------------------------------------------------------+
//| Input                                                            |
//+------------------------------------------------------------------+
input group "=== Simbolo e identificazione ==="
input string InpExpectedSymbol = "";        // Simbolo atteso (vuoto = simbolo del grafico)
input ulong  InpMagic          = 670101;    // Magic Number
input string InpCommentPrefix  = "WT67";    // Prefisso del commento ordini

input group "=== WaveTrend ==="
input int           InpChannelLen = 10;           // Channel Length (n1)
input int           InpAverageLen = 21;           // Average Length (n2)
input int           InpSignalLen  = 4;            // Lunghezza SMA della linea a puntini (wt2)
input int           InpWarmupBars = 1000;         // Candele M15 completate usate nel calcolo
input ENUM_WT_CROSS InpCrossMode  = WT_CROSS_STANDARD; // Definizione di incrocio
input double        InpEqualEps   = 0.00000001;   // Tolleranza di uguaglianza wt1/wt2

input group "=== Orari (ora italiana Europe/Rome) ==="
input ENUM_WINDOW_MODE InpWindowMode = WINDOW_ROME_FIXED; // Modalita' finestra
input string InpPreAnalysis      = "15:28"; // Inizio analisi (controlli, nessun ordine)
input string InpEntryStart       = "15:30"; // Prima chiusura candela valida per aprire
input string InpEntryEnd         = "17:30"; // Ultima chiusura candela valida per aprire
input string InpProcessEnd       = "17:32"; // Limite assoluto per eseguire un ingresso
input int    InpMaxEntryDelaySec = 120;     // Ritardo max tra chiusura candela ed esecuzione (sec)
input int    InpBarCloseGraceSec = 3;       // Attesa dopo la fine teorica della candela senza tick (sec)

input group "=== Reversal e chiusure ==="
input bool InpCloseOnOppositeOutsideWindow = true;  // Chiudi su segnale opposto anche fuori finestra
input bool InpReverseOpenOutsideWindow     = false; // Riapertura opposta consentita fuori finestra
input bool InpCloseOnMissedOpposite        = true;  // Dopo inattivita': chiudi se e' stato perso un segnale opposto

input group "=== Limite giornaliero ==="
input int InpMaxTradesPerDay = 3; // Operazioni massime per giorno (calendario italiano)

input group "=== Stop Loss / Take Profit ==="
input double         InpSLDistance = 30.0; // Distanza SL in punti indice (unita' di prezzo)
input double         InpTPDistance = 30.0; // Distanza TP in punti indice (unita' di prezzo)
input ENUM_SLTP_MODE InpSLTPMode   = SLTP_ORDER_THEN_ALIGN; // Gestione SL/TP rispetto allo slippage

input group "=== Lotto ==="
input double InpLots = 1.00; // Lotti per operazione (mai modificati dall'EA)

input group "=== Esecuzione ordini ==="
input int   InpMaxRetries           = 3;    // Tentativi massimi per errore temporaneo
input int   InpRetryDelayMs         = 1000; // Pausa tra i tentativi (ms)
input int   InpPendingCloseRetrySec = 10;   // Intervallo tra nuovi tentativi di chiusura fallita (sec)
input ulong InpDeviationPoints      = 500;  // Deviazione max in point (solo esecuzione Instant)

input group "=== Fusi orari ==="
input int             InpServerStdOffsetMin = 120;        // Offset server in ora solare (minuti da UTC)
input ENUM_SERVER_DST InpServerDST          = SRV_DST_US; // Regola ora legale del server
input int             InpRomeStdOffsetMin   = 60;         // Offset Italia in ora solare (minuti)
input bool            InpRomeUseDST         = true;       // Italia usa l'ora legale
input string          InpRomeDSTOverride    = "";         // Override UE: "AAAA.MM.GG HH:MI-AAAA.MM.GG HH:MI;..." (UTC)
input int             InpNYStdOffsetMin     = -300;       // Offset New York in ora solare (minuti)
input bool            InpNYUseDST           = true;       // New York usa l'ora legale
input string          InpNYDSTOverride      = "";         // Override USA: stesso formato (UTC)
input ENUM_TIME_CHECK InpTimeCheck          = TIMECHECK_BLOCK; // Controllo dal vivo regola server vs TimeGMT()
input int             InpTimeCheckTolSec    = 120;        // Tolleranza del controllo (sec)

input group "=== Log e notifiche ==="
input bool InpLogEveryBar = false; // Log di ogni candela anche fuori finestra
input bool InpCsvLog      = true;  // Log anche su file CSV (MQL5\Files)
input bool InpAlertPopup  = false; // Avvisi con finestra popup
input bool InpPushNotify  = false; // Avvisi con notifica push (MetaQuotes ID)
input bool InpEmailNotify = false; // Avvisi via email (impostazioni MT5)

//+------------------------------------------------------------------+
//| Strutture e variabili globali                                    |
//+------------------------------------------------------------------+
struct DstOverride
  {
   int      year;
   datetime startUtc;
   datetime endUtc;
  };

CTrade      g_trade;
string      g_sym          = "";
bool        g_isTester     = false;
bool        g_useGv        = true;   // variabili globali persistenti (solo dal vivo)
bool        g_netting      = false;
int         g_digits       = 0;
double      g_point        = 0.0;
double      g_tickSize     = 0.0;
double      g_volMin       = 0.0;
double      g_volMax       = 0.0;
double      g_volStep      = 0.0;
int         g_preMin       = -1;
int         g_startMin     = -1;
int         g_endMin       = -1;
int         g_procEndMin   = -1;
int         g_normalDiffMin = 360;   // differenza normale Roma-NY in minuti
int         g_validStart   = 0;      // primo indice valido di wt2
int         g_minBars      = 0;
string      g_gvPrefix     = "";
string      g_csvName      = "";
DstOverride g_romeOv[];
DstOverride g_nyOv[];

datetime    g_lastProcessedBarOpen = 0;  // apertura (ora server) dell'ultima candela elaborata
datetime    g_lastSeenFormingBar   = 0;
bool        g_firstBarCheck        = true;
int         g_dayKey               = 0;
bool        g_preflightDone        = false;
bool        g_busy                 = false;
bool        g_clockOk              = true;
bool        g_clockChecked         = false;
datetime    g_lastClockCheck       = 0;
bool        g_wasConnected         = true;
datetime    g_reconnectUtc         = 0;
bool        g_blockStops           = false;
bool        g_blockAnomaly         = false;
string      g_blockAnomalyText     = "";
datetime    g_lastDataErrLog       = 0;

// chiusura in attesa (chiusura fallita da ritentare)
ulong       g_pendCloseTicket      = 0;
int         g_pendRevDir           = 0;
datetime    g_pendRevBarCloseUtc   = 0;
bool        g_pendAllowReopen      = false;
datetime    g_pendNextTryUtc       = 0;
datetime    g_pendLastLogUtc       = 0;

// controllo repainting
datetime    g_prevBarOpen = 0;
double      g_prevWt1     = 0.0;
double      g_prevWt2     = 0.0;

// statistiche (utili soprattutto nel backtest)
int         g_statSignals        = 0;
int         g_statEntries        = 0;
int         g_statRevCloses      = 0;
int         g_statRevEntries     = 0;
int         g_statBlockedLimit   = 0;
int         g_statBlockedWindow  = 0;
int         g_statBlockedOther   = 0;
int         g_statDeadline       = 0;
int         g_statSameDir        = 0;
int         g_statDupBlocked     = 0;
int         g_statDupEntries     = 0;
int         g_statMissedCloses   = 0;
int         g_statRepaint        = 0;
int         g_statTodayEntries   = 0;
int         g_statMaxDay         = 0;
datetime    g_lastEntrySignalUtc = 0;

//+------------------------------------------------------------------+
//| Utilita' stringhe                                                |
//+------------------------------------------------------------------+
string I2S(const long v)               { return IntegerToString(v); }
string D2S(const double v,const int d) { return DoubleToString(v,d); }
string PStr(const double p)            { return DoubleToString(p,g_digits); }
string Fmt(const datetime t)           { return TimeToString(t,TIME_DATE|TIME_SECONDS); }
string HHMM(const datetime t)          { return TimeToString(t,TIME_MINUTES); }
string YesNo(const bool b)             { return b ? "si" : "no"; }

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

//+------------------------------------------------------------------+
//| Calendario e fusi orari (tutto calcolato in codice, senza rete)  |
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
// all'ultima domenica di ottobre 01:00 UTC
bool RuleEU(const datetime utc)
  {
   int y=YearOf(utc);
   datetime a=(datetime)((long)LastSunday(y,3)+3600);
   datetime b=(datetime)((long)LastSunday(y,10)+3600);
   return (utc>=a && utc<b);
  }

// Regola USA: dalla seconda domenica di marzo alle 02:00 locali (ora solare)
// alla prima domenica di novembre alle 02:00 locali (ora legale)
bool RuleUS(const datetime utc)
  {
   int  y=YearOf(utc);
   long stdOff=(long)InpNYStdOffsetMin*60;
   datetime a=(datetime)((long)NthSunday(y,3,2)+7200-stdOff);
   datetime b=(datetime)((long)NthSunday(y,11,1)+7200-(stdOff+3600));
   return (utc>=a && utc<b);
  }

int FindOverride(const DstOverride &arr[],const int y)
  {
   for(int i=0;i<ArraySize(arr);i++)
      if(arr[i].year==y) return i;
   return -1;
  }

bool RomeDst(const datetime utc)
  {
   if(!InpRomeUseDST) return false;
   int i=FindOverride(g_romeOv,YearOf(utc));
   if(i>=0) return (utc>=g_romeOv[i].startUtc && utc<g_romeOv[i].endUtc);
   return RuleEU(utc);
  }

bool NYDst(const datetime utc)
  {
   if(!InpNYUseDST) return false;
   int i=FindOverride(g_nyOv,YearOf(utc));
   if(i>=0) return (utc>=g_nyOv[i].startUtc && utc<g_nyOv[i].endUtc);
   return RuleUS(utc);
  }

bool ZoneIsDst(const int zone,const datetime utc)
  {
   if(zone==ZONE_ROME) return RomeDst(utc);
   if(zone==ZONE_NY)   return NYDst(utc);
   if(InpServerDST==SRV_DST_US) return NYDst(utc);
   if(InpServerDST==SRV_DST_EU) return RomeDst(utc);
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

// ora corrente del server (TimeTradeServer funziona anche senza tick)
datetime ServerNow()
  {
   datetime t=TimeTradeServer();
   datetime c=TimeCurrent();
   if(t<c) t=c;
   return t;
  }

datetime NowUtc() { return ServerToUtc(ServerNow()); }

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

datetime DayStart(const datetime local) { return (datetime)(((long)local/86400)*86400); }

// spostamento della finestra (solo modalita' "segui New York")
int WindowShiftMin(const datetime utc)
  {
   if(InpWindowMode!=WINDOW_FOLLOW_NY) return 0;
   int diff=(ZoneOffSec(ZONE_ROME,utc)-ZoneOffSec(ZONE_NY,utc))/60;
   return diff-g_normalDiffMin;
  }

// la candela che chiude in closeUtc puo' generare un ingresso ordinario?
bool IsInEntryWindow(const datetime closeUtc)
  {
   int m=RomeMinuteOfDay(closeUtc);
   int sh=WindowShiftMin(closeUtc);
   return (m>=g_startMin+sh && m<=g_endMin+sh);
  }

// fascia di elaborazione/log (default 15:28-17:32)
bool IsInProcessWindow(const datetime utc)
  {
   int m=RomeMinuteOfDay(utc);
   int sh=WindowShiftMin(utc);
   return (m>=g_preMin+sh && m<=g_procEndMin+sh);
  }

// limite di esecuzione di un ingresso generato dalla candela chiusa in closeUtc
datetime EntryDeadlineUtc(const datetime closeUtc,const bool inWindow)
  {
   datetime d=(datetime)((long)closeUtc+InpMaxEntryDelaySec);
   if(inWindow)
     {
      int sh=WindowShiftMin(closeUtc);
      datetime dayStart=DayStart(UtcToZone(ZONE_ROME,closeUtc));
      datetime endLocal=(datetime)((long)dayStart+(long)(g_procEndMin+sh)*60);
      datetime endUtc=ZoneToUtc(ZONE_ROME,endLocal);
      if(endUtc<d) d=endUtc;
     }
   return d;
  }

bool ParseOverrides(const string src,DstOverride &arr[],const string label)
  {
   ArrayResize(arr,0);
   string s=Trim(src);
   if(s=="") return true;
   string parts[];
   int n=StringSplit(s,';',parts);
   for(int i=0;i<n;i++)
     {
      string p=Trim(parts[i]);
      if(p=="") continue;
      string se[];
      if(StringSplit(p,'-',se)!=2)
        {
         Print("[WT67NDX100_100k] Override ",label," non valido: '",p,"' (formato AAAA.MM.GG HH:MI-AAAA.MM.GG HH:MI)");
         return false;
        }
      datetime a=StringToTime(Trim(se[0]));
      datetime b=StringToTime(Trim(se[1]));
      if(a==0 || b==0 || b<=a || YearOf(a)!=YearOf(b))
        {
         Print("[WT67NDX100_100k] Override ",label," non valido: '",p,"'");
         return false;
        }
      int k=ArraySize(arr);
      ArrayResize(arr,k+1);
      arr[k].year=YearOf(a);
      arr[k].startUtc=a;
      arr[k].endUtc=b;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Log e notifiche                                                  |
//+------------------------------------------------------------------+
void AppendCsv(const string line)
  {
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
   PrintFormat("[WT67NDX100_100k] %s | Roma %s | %s",ev,Fmt(rome),msg);
   if(InpCsvLog)
     {
      string clean=msg;
      StringReplace(clean,";",",");
      AppendCsv(Fmt(utc)+";"+Fmt(rome)+";"+Fmt(UtcToZone(ZONE_NY,utc))+";"+Fmt(srv)+";"+ev+";"+clean);
     }
  }

void Notify(const string msg)
  {
   Log("AVVISO",msg);
   if(g_isTester) return;
   string t="WT67NDX100_100k "+g_sym+": "+msg;
   if(InpAlertPopup)  Alert(t);
   if(InpPushNotify)  SendNotification(StringSubstr(t,0,255));
   if(InpEmailNotify) SendMail("WT67NDX100_100k - avviso",t);
  }

void LogTimeDiagnostics(const string tag)
  {
   datetime srv=ServerNow();
   datetime utc=ServerToUtc(srv);
   datetime rome=UtcToZone(ZONE_ROME,utc);
   datetime ny=UtcToZone(ZONE_NY,utc);
   int offR=ZoneOffSec(ZONE_ROME,utc);
   int offN=ZoneOffSec(ZONE_NY,utc);
   int offS=ZoneOffSec(ZONE_SERVER,utc);
   int diffMin=(offR-offN)/60;

   Log(tag,"UTC "+Fmt(utc)+
       " | Roma "+Fmt(rome)+" ("+OffStr(offR)+", ora legale "+YesNo(ZoneIsDst(ZONE_ROME,utc))+")"+
       " | New York "+Fmt(ny)+" ("+OffStr(offN)+", ora legale "+YesNo(ZoneIsDst(ZONE_NY,utc))+")"+
       " | Server "+Fmt(srv)+" ("+OffStr(offS)+", ora legale "+YesNo(ZoneIsDst(ZONE_SERVER,utc))+")"+
       " | differenza Roma-New York "+MinToHHMM(diffMin)+" ore");

   // apertura ufficiale Nasdaq 09:30 ET del giorno corrente di New York
   datetime nyOpenLocal=(datetime)((long)DayStart(ny)+9*3600+30*60);
   datetime nyOpenUtc=ZoneToUtc(ZONE_NY,nyOpenLocal);
   datetime nyOpenRome=UtcToZone(ZONE_ROME,nyOpenUtc);
   int sh=WindowShiftMin(utc);
   string msg="Apertura Nasdaq 09:30 ET = "+HHMM(nyOpenRome)+" ora italiana"+
              " | finestra ingressi oggi "+MinToHHMM(g_startMin+sh)+"-"+MinToHHMM(g_endMin+sh)+" Roma"+
              " (= "+MinToHHMM(g_startMin+sh-diffMin)+"-"+MinToHHMM(g_endMin+sh-diffMin)+" New York)";
   if(diffMin!=g_normalDiffMin)
      msg+=" | ATTENZIONE: settimana di sfasamento ora legale Europa/USA";
   Log(tag,msg);

   if(!g_isTester)
     {
      datetime gmt=TimeGMT();
      long measured=(long)TimeTradeServer()-(long)gmt;
      Log(tag,"Controllo dal vivo: TimeGMT "+Fmt(gmt)+" | TimeLocal "+Fmt(TimeLocal())+
          " | offset server misurato "+I2S(measured/60)+" min, previsto dalla regola "+I2S(offS/60)+" min");
     }
   else
      Log(tag,"Tester: UTC ricostruito dall'ora del server con la regola impostata (nel tester TimeGMT coincide con l'ora del server)");
  }

//+------------------------------------------------------------------+
//| WaveTrend                                                        |
//+------------------------------------------------------------------+
// EMA con inizializzazione a media semplice; src valido da startIdx,
// dst valido da startIdx+len-1 (prima: EMPTY_VALUE)
void EMAFrom(const double &src[],const int cnt,const int startIdx,const int len,double &dst[])
  {
   ArrayResize(dst,cnt);
   ArrayInitialize(dst,EMPTY_VALUE);
   int s=startIdx+len-1;
   if(s>=cnt) return;
   double sum=0.0;
   for(int i=startIdx;i<=s;i++) sum+=src[i];
   dst[s]=sum/len;
   double a=2.0/(len+1.0);
   for(int i=s+1;i<cnt;i++) dst[i]=a*src[i]+(1.0-a)*dst[i-1];
  }

// r[0..cnt-1] in ordine cronologico, solo candele completate
void ComputeWT(const MqlRates &r[],const int cnt,double &wt1[],double &wt2[])
  {
   int n1=InpChannelLen, n2=InpAverageLen, sg=InpSignalLen;
   double ap[],esa[],dev[],dd[],ci[];
   ArrayResize(ap,cnt);
   ArrayResize(dev,cnt);
   ArrayResize(ci,cnt);
   for(int i=0;i<cnt;i++) ap[i]=(r[i].high+r[i].low+r[i].close)/3.0;   // HLC3

   EMAFrom(ap,cnt,0,n1,esa);                       // esa = EMA(ap,n1)
   int s1=n1-1;
   for(int i=0;i<cnt;i++) dev[i]=(i>=s1) ? MathAbs(ap[i]-esa[i]) : 0.0;
   EMAFrom(dev,cnt,s1,n1,dd);                      // d = EMA(|ap-esa|,n1)
   int s2=s1+n1-1;
   for(int i=0;i<cnt;i++)
     {
      if(i<s2) { ci[i]=0.0; continue; }
      double den=0.015*dd[i];
      ci[i]=(den!=0.0) ? (ap[i]-esa[i])/den : 0.0; // ci = (ap-esa)/(0.015*d)
     }
   EMAFrom(ci,cnt,s2,n2,wt1);                      // wt1 = EMA(ci,n2)
   int s3=s2+n2-1;
   ArrayResize(wt2,cnt);
   ArrayInitialize(wt2,EMPTY_VALUE);
   int s4=s3+sg-1;
   for(int i=s4;i<cnt;i++)                         // wt2 = SMA(wt1,sg)
     {
      double sum=0.0;
      for(int j=i-sg+1;j<=i;j++) sum+=wt1[j];
      wt2[i]=sum/sg;
     }
  }

// +1 = BUY, -1 = SELL, 0 = nessun incrocio sulla candela k (k-1 = precedente)
int DetectCross(const double &wt1[],const double &wt2[],const int k)
  {
   if(k-1<g_validStart) return 0;
   double eps=InpEqualEps;
   double dc=wt1[k]-wt2[k];
   double dp=wt1[k-1]-wt2[k-1];
   if(InpCrossMode==WT_CROSS_STANDARD)
     {
      if(dp<=eps  && dc>eps)  return 1;
      if(dp>=-eps && dc<-eps) return -1;
      return 0;
     }
   // modalita' rigorosa: cerca l'ultimo stato non uguale prima di k
   if(dc>eps || dc<-eps)
     {
      for(int j=k-1;j>=g_validStart;j--)
        {
         double dj=wt1[j]-wt2[j];
         if(dj>eps || dj<-eps)
           {
            if(dc>eps  && dj<-eps) return 1;
            if(dc<-eps && dj>eps)  return -1;
            return 0;
           }
        }
     }
   return 0;
  }

// confronta i valori ricalcolati della candela precedente con quelli memorizzati
void CheckRepaint(const MqlRates &r[],const int k,const double &wt1[],const double &wt2[])
  {
   if(g_prevBarOpen>0)
     {
      for(int j=k;j>=0 && j>=k-10;j--)
        {
         if(r[j].time!=g_prevBarOpen) continue;
         double e1=MathAbs(wt1[j]-g_prevWt1);
         double e2=MathAbs(wt2[j]-g_prevWt2);
         if(e1>0.000001 || e2>0.000001)
           {
            g_statRepaint++;
            Log("REPAINT","ATTENZIONE: ricalcolando la candela "+Fmt(r[j].time)+" (server) i valori sono cambiati: wt1 "+
                D2S(g_prevWt1,6)+" -> "+D2S(wt1[j],6)+", wt2 "+D2S(g_prevWt2,6)+" -> "+D2S(wt2[j],6)+
                " (dati storici corretti dal broker o tick arrivati in ritardo)");
           }
         break;
        }
     }
   g_prevBarOpen=r[k].time;
   g_prevWt1=wt1[k];
   g_prevWt2=wt2[k];
  }

//+------------------------------------------------------------------+
//| Prezzi, posizioni, ordini                                        |
//+------------------------------------------------------------------+
double NormalizePrice(double p)
  {
   if(g_tickSize>0.0) p=MathRound(p/g_tickSize)*g_tickSize;
   return NormalizeDouble(p,g_digits);
  }

int PosDir(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return 0;
   return ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? 1 : -1;
  }

int GetEAPositions(ulong &tickets[])
  {
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      int n=ArraySize(tickets);
      ArrayResize(tickets,n+1);
      tickets[n]=t;
     }
   return ArraySize(tickets);
  }

int CountEAPositions() { ulong t[]; return GetEAPositions(t); }

datetime EarliestEAPositionOpen()
  {
   ulong t[];
   int n=GetEAPositions(t);
   datetime best=0;
   for(int i=0;i<n;i++)
     {
      if(!PositionSelectByTicket(t[i])) continue;
      datetime o=(datetime)PositionGetInteger(POSITION_TIME);
      if(best==0 || o<best) best=o;
     }
   return best;
  }

string EAPositionText()
  {
   ulong t[];
   int n=GetEAPositions(t);
   if(n==0) return "nessuna";
   string s="";
   for(int i=0;i<n;i++)
     {
      if(!PositionSelectByTicket(t[i])) continue;
      if(s!="") s+=", ";
      s+=(PosDir(t[i])>0 ? "BUY" : "SELL")+" #"+I2S((long)t[i])+" "+D2S(PositionGetDouble(POSITION_VOLUME),2)+" lotti @ "+
         PStr(PositionGetDouble(POSITION_PRICE_OPEN));
     }
   return s;
  }

bool IsMarketOrderType(const long type) { return (type==ORDER_TYPE_BUY || type==ORDER_TYPE_SELL); }

bool HasInFlightOrder()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong o=OrderGetTicket(i);
      if(o==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=g_sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(IsMarketOrderType(OrderGetInteger(ORDER_TYPE))) return true;
     }
   return false;
  }

bool HasPendingEAOrders()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong o=OrderGetTicket(i);
      if(o==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=g_sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(!IsMarketOrderType(OrderGetInteger(ORDER_TYPE))) return true;
     }
   return false;
  }

// conto netting: una posizione di altri (manuale o altro EA) sullo stesso
// simbolo si fonderebbe con quella dell'EA
bool ForeignPositionNetting()
  {
   if(!g_netting) return false;
   if(!PositionSelect(g_sym)) return false;
   return ((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic);
  }

bool IsRetryable(const uint rc)
  {
   switch(rc)
     {
      case 0:
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_LOCKED:
      case TRADE_RETCODE_ERROR:
      case TRADE_RETCODE_REJECT:
         return true;
     }
   return false;
  }

void LogResult(const string ctx,const uint rc,const int err)
  {
   Log(ctx,"risposta server: "+I2S(rc)+" "+g_trade.ResultRetcodeDescription()+
       " | deal "+I2S((long)g_trade.ResultDeal())+" | ordine "+I2S((long)g_trade.ResultOrder())+
       " | volume "+D2S(g_trade.ResultVolume(),2)+" | prezzo "+PStr(g_trade.ResultPrice())+
       " | commento server '"+g_trade.ResultComment()+"' | errore terminale "+I2S(err));
  }

bool WaitPositionGone(const ulong ticket,const int ms)
  {
   int waited=0;
   while(PositionSelectByTicket(ticket))
     {
      if(waited>=ms) return false;
      Sleep(100);
      waited+=100;
     }
   return true;
  }

bool WaitForEAPosition(ulong &ticket,const int ms)
  {
   int waited=0;
   while(true)
     {
      ulong t[];
      if(GetEAPositions(t)>0) { ticket=t[0]; return true; }
      if(waited>=ms) return false;
      Sleep(100);
      waited+=100;
     }
   return false;
  }

void VerifyClosedInHistory(const long posId)
  {
   if(posId<=0) return;
   for(int w=0;w<=20;w++)
     {
      if(HistorySelectByPosition(posId))
        {
         for(int i=HistoryDealsTotal()-1;i>=0;i--)
           {
            ulong d=HistoryDealGetTicket(i);
            if(d==0) continue;
            long e=HistoryDealGetInteger(d,DEAL_ENTRY);
            if(e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY)
              {
               Log("CHIUSURA","confermata nello storico: deal #"+I2S((long)d)+" prezzo "+PStr(HistoryDealGetDouble(d,DEAL_PRICE))+
                   " profitto "+D2S(HistoryDealGetDouble(d,DEAL_PROFIT),2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+
                   " motivo "+EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(d,DEAL_REASON)));
               return;
              }
           }
        }
      Sleep(100);
     }
   Log("CHIUSURA","ATTENZIONE: la posizione non e' piu' aperta ma il deal di uscita non e' ancora visibile nello storico");
  }

bool StopsDistanceOk(const int dir,const MqlTick &tk,const double sl,const double tp,string &why)
  {
   double minD=(double)SymbolInfoInteger(g_sym,SYMBOL_TRADE_STOPS_LEVEL)*g_point;
   if(dir>0)
     {
      if(sl>=tk.bid || tp<=tk.bid)
        { why="prezzo/spread incompatibile con SL/TP (bid "+PStr(tk.bid)+", SL "+PStr(sl)+", TP "+PStr(tp)+")"; return false; }
      if(tk.bid-sl<minD || tp-tk.bid<minD)
        { why="distanza minima del broker "+PStr(minD)+" non rispettata"; return false; }
     }
   else
     {
      if(sl<=tk.ask || tp>=tk.ask)
        { why="prezzo/spread incompatibile con SL/TP (ask "+PStr(tk.ask)+", SL "+PStr(sl)+", TP "+PStr(tp)+")"; return false; }
      if(sl-tk.ask<minD || tk.ask-tp<minD)
        { why="distanza minima del broker "+PStr(minD)+" non rispettata"; return false; }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Contatore giornaliero (storico del conto + copia persistente)     |
//+------------------------------------------------------------------+
string GvName(const string key) { return g_gvPrefix+key; }

double GvGet(const string key,const double def)
  {
   string n=GvName(key);
   if(GlobalVariableCheck(n)) return GlobalVariableGet(n);
   return def;
  }

void GvSet(const string key,const double v) { GlobalVariableSet(GvName(key),v); }

// conta le posizioni dell'EA APERTE nel giorno italiano dayKey
// (una posizione eseguita in piu' deal conta una sola volta)
int CountTradesRomeDay(const int dayKey)
  {
   datetime nowSrv=ServerNow();
   if(!HistorySelect((datetime)((long)nowSrv-4*86400),(datetime)((long)nowSrv+86400))) return -1;
   ulong ids[];
   int n=0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=g_sym) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
      datetime t=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      if(RomeDayKey(ServerToUtc(t))!=dayKey) continue;
      ulong pid=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
      bool seen=false;
      for(int j=0;j<n;j++) if(ids[j]==pid) { seen=true; break; }
      if(!seen) { ArrayResize(ids,n+1); ids[n]=pid; n++; }
     }
   return n;
  }

int GetDayCount(const int dayKey)
  {
   int h=CountTradesRomeDay(dayKey);
   if(h<0) return -1;
   if(!g_useGv) return h;
   int g=(int)GvGet("cnt_"+I2S(dayKey),0.0);
   return (g>h) ? g : h;
  }

// gia' eseguito un ordine con lo stesso commento (stessa candela di segnale)?
bool SignalAlreadyExecuted(const string cmt)
  {
   datetime now=ServerNow();
   if(!HistorySelect((datetime)((long)now-2*86400),(datetime)((long)now+3600))) return false;
   for(int i=HistoryOrdersTotal()-1;i>=0;i--)
     {
      ulong o=HistoryOrderGetTicket(i);
      if(o==0) continue;
      if(HistoryOrderGetString(o,ORDER_SYMBOL)!=g_sym) continue;
      if((ulong)HistoryOrderGetInteger(o,ORDER_MAGIC)!=InpMagic) continue;
      if(StringFind(HistoryOrderGetString(o,ORDER_COMMENT),cmt)!=0) continue;
      long st=HistoryOrderGetInteger(o,ORDER_STATE);
      if(st==ORDER_STATE_FILLED || st==ORDER_STATE_PARTIAL) return true;
     }
   return false;
  }

void SaveLastProcessed(const datetime barOpenSrv)
  {
   g_lastProcessedBarOpen=barOpenSrv;
   if(g_useGv) GvSet("lastbar",(double)(long)barOpenSrv);
  }

string BuildComment(const int dir,const datetime closeUtc)
  {
   MqlDateTime s;
   TimeToStruct(UtcToZone(ZONE_ROME,closeUtc),s);
   string c=StringFormat("%s %s %04d%02d%02d %02d%02d",InpCommentPrefix,(dir>0 ? "B" : "S"),s.year,s.mon,s.day,s.hour,s.min);
   return StringSubstr(c,0,31);
  }

//+------------------------------------------------------------------+
//| Controlli prima di un'apertura                                    |
//+------------------------------------------------------------------+
bool CanOpenBasic(string &why)
  {
   if(!g_isTester)
     {
      if(TerminalInfoInteger(TERMINAL_CONNECTED)==0) { why="terminale non connesso al server"; return false; }
      if(g_reconnectUtc>0 && (long)NowUtc()-(long)g_reconnectUtc<RECONNECT_WAIT_SEC) { why="riconnessione appena avvenuta"; return false; }
      if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)==0) { why="trading automatico disattivato nel terminale"; return false; }
     }
   if(MQLInfoInteger(MQL_TRADE_ALLOWED)==0)          { why="trading non consentito nelle impostazioni dell'EA"; return false; }
   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)==0)  { why="trading non consentito sul conto"; return false; }
   if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)==0)   { why="trading automatico non consentito dal server"; return false; }
   long tm=SymbolInfoInteger(g_sym,SYMBOL_TRADE_MODE);
   if(tm!=SYMBOL_TRADE_MODE_FULL) { why="simbolo non negoziabile in entrambe le direzioni ("+EnumToString((ENUM_SYMBOL_TRADE_MODE)tm)+")"; return false; }
   if(!g_clockOk && InpTimeCheck==TIMECHECK_BLOCK) { why="incoerenza tra ora del server e regola di fuso orario"; return false; }
   if(g_blockStops)   { why="distanza minima degli stop del broker incompatibile con SL/TP"; return false; }
   if(g_blockAnomaly) { why=g_blockAnomalyText; return false; }
   if(HasPendingEAOrders())     { why="presenti ordini pendenti con il Magic dell'EA"; return false; }
   if(ForeignPositionNetting()) { why="conto netting con una posizione non dell'EA sullo stesso simbolo"; return false; }
   return true;
  }

//+------------------------------------------------------------------+
//| SL/TP esatti rispetto al prezzo di apertura effettivo             |
//+------------------------------------------------------------------+
void EnsureStops(const ulong ticket,const bool align,const string ctx)
  {
   if(!PositionSelectByTicket(ticket)) return;
   int    dir=PosDir(ticket);
   double op=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double esl=NormalizePrice(dir>0 ? op-InpSLDistance : op+InpSLDistance);
   double etp=NormalizePrice(dir>0 ? op+InpTPDistance : op-InpTPDistance);
   double half=g_tickSize*0.5;
   bool needSL=(sl==0.0) || (align && MathAbs(sl-esl)>half);
   bool needTP=(tp==0.0) || (align && MathAbs(tp-etp)>half);
   if(!needSL && !needTP)
     {
      Log("LIVELLI",ctx+": SL "+PStr(sl)+" TP "+PStr(tp)+" | distanza dal prezzo di apertura "+PStr(op)+
          ": SL "+PStr(MathAbs(op-sl))+", TP "+PStr(MathAbs(tp-op)));
      return;
     }
   double nsl=needSL ? esl : sl;
   double ntp=needTP ? etp : tp;
   MqlTick tk;
   if(!SymbolInfoTick(g_sym,tk)) { Notify(ctx+": prezzo non disponibile, SL/TP non verificati"); return; }

   // se il prezzo ha gia' superato il livello previsto la posizione non deve restare aperta
   bool beyond=(dir>0) ? (tk.bid<=nsl || tk.bid>=ntp) : (tk.ask>=nsl || tk.ask<=ntp);
   if(beyond)
     {
      Notify(ctx+": il prezzo ha gia' superato il livello SL/TP previsto: la posizione viene chiusa");
      bool mc=false;
      ClosePositionConfirmed(ticket,"livello SL/TP gia' superato",mc,true);
      return;
     }
   string why;
   if(!StopsDistanceOk(dir,tk,nsl,ntp,why))
     {
      Notify(ctx+": impossibile impostare SL/TP esatti ("+why+"); livelli attuali mantenuti: SL "+PStr(sl)+" TP "+PStr(tp));
      return;
     }
   for(int a=1;a<=InpMaxRetries;a++)
     {
      ResetLastError();
      g_trade.PositionModify(ticket,nsl,ntp);
      uint rc=g_trade.ResultRetcode();
      if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_NO_CHANGES)
        {
         Log("LIVELLI",ctx+": impostati SL "+PStr(nsl)+" TP "+PStr(ntp)+" = esattamente "+D2S(InpSLDistance,2)+"/"+
             D2S(InpTPDistance,2)+" punti dal prezzo di apertura "+PStr(op));
         return;
        }
      LogResult("LIVELLI",rc,GetLastError());
      if(!IsRetryable(rc)) break;
      Sleep(InpRetryDelayMs);
     }
   Notify(ctx+": modifica SL/TP non riuscita; livelli attuali SL "+PStr(sl)+" TP "+PStr(tp));
  }

//+------------------------------------------------------------------+
//| Chiusura con verifica effettiva                                   |
//+------------------------------------------------------------------+
bool ClosePositionConfirmed(const ulong ticket,const string reason,bool &marketClosed,const bool verbose)
  {
   marketClosed=false;
   long posId=0;
   if(PositionSelectByTicket(ticket)) posId=PositionGetInteger(POSITION_IDENTIFIER);
   for(int a=1;a<=InpMaxRetries;a++)
     {
      if(!PositionSelectByTicket(ticket))
        {
         if(verbose) Log("CHIUSURA","posizione #"+I2S((long)ticket)+" gia' chiusa (SL/TP o altro)");
         VerifyClosedInHistory(posId);
         return true;
        }
      if(verbose)
        {
         MqlTick tk;
         SymbolInfoTick(g_sym,tk);
         Log("CHIUSURA","chiusura "+(PosDir(ticket)>0 ? "BUY" : "SELL")+" #"+I2S((long)ticket)+" motivo: "+reason+
             " | tentativo "+I2S(a)+" | bid "+PStr(tk.bid)+" ask "+PStr(tk.ask));
        }
      ResetLastError();
      g_trade.PositionClose(ticket,InpDeviationPoints);
      uint rc=g_trade.ResultRetcode();
      if(verbose) LogResult("CHIUSURA",rc,GetLastError());
      if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED)
        {
         if(WaitPositionGone(ticket,5000))
           {
            VerifyClosedInHistory(posId);
            return true;
           }
         continue;   // chiusura parziale: chiude il resto al tentativo successivo
        }
      if(rc==TRADE_RETCODE_MARKET_CLOSED) { marketClosed=true; return false; }
      if(!IsRetryable(rc)) return false;
      Sleep(InpRetryDelayMs);
     }
   return !PositionSelectByTicket(ticket);
  }

void SetPendingClose(const ulong ticket,const int revDir,const datetime barCloseUtc,const bool allowReopen,const bool marketClosed)
  {
   g_pendCloseTicket=ticket;
   g_pendRevDir=revDir;
   g_pendRevBarCloseUtc=barCloseUtc;
   g_pendAllowReopen=allowReopen;
   g_pendNextTryUtc=(datetime)((long)NowUtc()+(marketClosed ? 60 : InpPendingCloseRetrySec));
   g_pendLastLogUtc=NowUtc();
  }

//+------------------------------------------------------------------+
//| Apertura                                                         |
//+------------------------------------------------------------------+
void OnEntryConfirmed(const ulong ticket,const int dir,const double reqPrice,const bool isReversal,const datetime closeUtc)
  {
   if(!PositionSelectByTicket(ticket)) return;
   double op=PositionGetDouble(POSITION_PRICE_OPEN);
   double vol=PositionGetDouble(POSITION_VOLUME);
   double slip=(dir>0) ? (op-reqPrice) : (reqPrice-op);
   g_statEntries++;
   if(isReversal) g_statRevEntries++;
   g_statTodayEntries++;
   if(g_statTodayEntries>g_statMaxDay) g_statMaxDay=g_statTodayEntries;
   if(g_lastEntrySignalUtc==closeUtc) g_statDupEntries++;
   g_lastEntrySignalUtc=closeUtc;

   Log("INGRESSO","ESEGUITO "+(dir>0 ? "BUY" : "SELL")+(isReversal ? " (reversal)" : "")+" #"+I2S((long)ticket)+
       " | prezzo effettivo "+PStr(op)+" | prezzo richiesto "+PStr(reqPrice)+" | slippage "+PStr(slip)+
       " | volume "+D2S(vol,2)+" | SL "+PStr(PositionGetDouble(POSITION_SL))+" TP "+PStr(PositionGetDouble(POSITION_TP)));
   if(vol<InpLots-g_volStep*0.5)
      Notify("esecuzione parziale: "+D2S(vol,2)+" lotti su "+D2S(InpLots,2)+" (la parte eseguita viene mantenuta, conta come 1 operazione)");

   EnsureStops(ticket,(InpSLTPMode==SLTP_ORDER_THEN_ALIGN),"ingresso");

   int dk=RomeDayKey(NowUtc());
   int h=CountTradesRomeDay(dk);
   if(g_useGv)
     {
      double g=GvGet("cnt_"+I2S(dk),0.0);
      double v=MathMax((double)h,g+1.0);
      GvSet("cnt_"+I2S(dk),v);
     }
   Log("CONTATORE","operazioni di oggi: "+I2S(GetDayCount(dk))+"/"+I2S(InpMaxTradesPerDay));
  }

bool OpenPosition(const int dir,const datetime closeUtc,const datetime deadlineUtc,const bool isReversal)
  {
   string cmt=BuildComment(dir,closeUtc);
   string side=(dir>0) ? "BUY" : "SELL";
   for(int a=1;a<=InpMaxRetries;a++)
     {
      if(NowUtc()>deadlineUtc)
        {
         Log("INGRESSO",side+" annullato: superato il limite di esecuzione "+HHMM(UtcToZone(ZONE_ROME,deadlineUtc))+" Roma");
         g_statDeadline++;
         return false;
        }
      if(CountEAPositions()>0) { Log("INGRESSO",side+" annullato: esiste gia' una posizione dell'EA"); return false; }
      if(HasInFlightOrder())   { Log("INGRESSO",side+": ordine precedente ancora in elaborazione, attendo"); Sleep(InpRetryDelayMs); continue; }
      if(SignalAlreadyExecuted(cmt))
        {
         Log("INGRESSO","segnale gia' eseguito (commento '"+cmt+"'): nessun ordine duplicato");
         g_statDupBlocked++;
         return false;
        }
      MqlTick tk;
      if(!SymbolInfoTick(g_sym,tk) || tk.ask<=0.0 || tk.bid<=0.0)
        {
         Log("INGRESSO",side+": prezzo non disponibile, tentativo "+I2S(a));
         Sleep(InpRetryDelayMs);
         continue;
        }
      double price=(dir>0) ? tk.ask : tk.bid;
      double sl=NormalizePrice(dir>0 ? price-InpSLDistance : price+InpSLDistance);
      double tp=NormalizePrice(dir>0 ? price+InpTPDistance : price-InpTPDistance);
      string why;
      if(!StopsDistanceOk(dir,tk,sl,tp,why))
        {
         Notify("ingresso "+side+" NON eseguito: "+why);
         return false;
        }
      ENUM_ORDER_TYPE ot=(dir>0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double margin=0.0;
      if(OrderCalcMargin(ot,g_sym,InpLots,price,margin) && margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
        {
         Notify("ingresso "+side+" NON eseguito: margine richiesto "+D2S(margin,2)+" > margine libero "+
                D2S(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2));
         return false;
        }
      Log("INGRESSO","invio "+side+(isReversal ? " (reversal)" : "")+" tentativo "+I2S(a)+" | lotti "+D2S(InpLots,2)+
          " | bid "+PStr(tk.bid)+" ask "+PStr(tk.ask)+" spread "+PStr(tk.ask-tk.bid)+
          " | SL "+PStr(sl)+" TP "+PStr(tp)+" | commento '"+cmt+"'");
      ResetLastError();
      if(dir>0) g_trade.Buy(InpLots,g_sym,price,sl,tp,cmt);
      else      g_trade.Sell(InpLots,g_sym,price,sl,tp,cmt);
      uint rc=g_trade.ResultRetcode();
      LogResult("INGRESSO",rc,GetLastError());
      if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED)
        {
         ulong pt=0;
         if(WaitForEAPosition(pt,5000))
           {
            OnEntryConfirmed(pt,dir,price,isReversal,closeUtc);
            return true;
           }
         g_blockAnomaly=true;
         g_blockAnomalyText="esito di un ingresso incerto (ordine accettato, posizione non trovata): verificare il conto";
         Notify("ordine "+side+" accettato ma posizione non trovata: nuove aperture bloccate fino a domani o al riavvio dell'EA");
         return false;
        }
      if(!IsRetryable(rc))
        {
         Notify("ingresso "+side+" rifiutato dal server: "+g_trade.ResultRetcodeDescription());
         return false;
        }
      Sleep(InpRetryDelayMs);
     }
   Notify("ingresso "+side+" non eseguito dopo "+I2S(InpMaxRetries)+" tentativi");
   return false;
  }

bool TryEntry(const int sig,const datetime closeUtc,const bool isReversal)
  {
   string side=(sig>0) ? "BUY" : "SELL";
   bool inWin=IsInEntryWindow(closeUtc);
   if(!inWin && !(isReversal && InpReverseOpenOutsideWindow))
     {
      Log("INGRESSO",side+" non aperto: candela fuori dalla finestra ingressi"+(isReversal ? " (reversal: eseguita solo la chiusura)" : ""));
      g_statBlockedWindow++;
      return false;
     }
   datetime deadline=EntryDeadlineUtc(closeUtc,inWin);
   if(NowUtc()>deadline)
     {
      Log("INGRESSO",side+" non aperto: superato il limite di esecuzione "+HHMM(UtcToZone(ZONE_ROME,deadline))+" Roma");
      g_statDeadline++;
      return false;
     }
   string why;
   if(!CanOpenBasic(why))
     {
      Log("INGRESSO",side+" non aperto: "+why);
      g_statBlockedOther++;
      return false;
     }
   int c=GetDayCount(RomeDayKey(NowUtc()));
   if(c<0)
     {
      Notify(side+" non aperto: storico del conto non disponibile per il conteggio giornaliero");
      g_statBlockedOther++;
      return false;
     }
   if(c>=InpMaxTradesPerDay)
     {
      Log("LIMITE",side+" non aperto: raggiunte "+I2S(c)+"/"+I2S(InpMaxTradesPerDay)+" operazioni oggi"+
          (isReversal ? " (reversal: eseguita solo la chiusura)" : ""));
      g_statBlockedLimit++;
      return false;
     }
   return OpenPosition(sig,closeUtc,deadline,isReversal);
  }

//+------------------------------------------------------------------+
//| Gestione di un segnale su una candela appena chiusa               |
//+------------------------------------------------------------------+
void HandleSignal(const int sig,const datetime closeUtc)
  {
   string side=(sig>0) ? "BUY" : "SELL";
   bool inWin=IsInEntryWindow(closeUtc);
   ulong t[];
   int n=GetEAPositions(t);
   bool reversal=false;
   int  sameDir=0;
   int  keptOpposite=0;
   for(int i=0;i<n;i++)
     {
      int pdir=PosDir(t[i]);
      if(pdir==0) continue;
      if(pdir==sig) { sameDir++; continue; }
      if(!inWin && !InpCloseOnOppositeOutsideWindow)
        {
         Log("REVERSAL","segnale "+side+" fuori finestra: chiusura fuori finestra disattivata, posizione mantenuta");
         keptOpposite++;
         continue;
        }
      reversal=true;
      bool mc=false;
      if(ClosePositionConfirmed(t[i],"segnale "+side+" opposto",mc,true))
         g_statRevCloses++;
      else
        {
         SetPendingClose(t[i],sig,closeUtc,true,mc);
         Notify("chiusura per segnale opposto NON riuscita"+(mc ? " (mercato chiuso)" : "")+
                ": nuovi tentativi ogni "+I2S(mc ? 60 : InpPendingCloseRetrySec)+" s, nessuna nuova apertura finche' non e' confermata");
         return;
        }
     }
   if(sameDir>0)
     {
      Log("SEGNALE",side+" nella stessa direzione della posizione aperta: ignorato");
      g_statSameDir++;
      return;
     }
   if(keptOpposite>0) return;
   if(CountEAPositions()>0)
     {
      Log("REVERSAL","dopo la chiusura risulta ancora una posizione dell'EA: nessuna nuova apertura");
      return;
     }
   TryEntry(sig,closeUtc,reversal);
  }

// chiusure su segnali opposti avvenuti mentre l'EA non era attivo
// (nessun ingresso in ritardo)
void HandleMissedBars(const MqlRates &r[],const double &wt1[],const double &wt2[],const int from,const int to)
  {
   int found=0;
   for(int j=from;j<=to;j++)
     {
      if(j-1<g_validStart) continue;
      int sig=DetectCross(wt1,wt2,j);
      if(sig==0) continue;
      found++;
      datetime closeSrv=(datetime)((long)r[j].time+BAR_SEC);
      datetime closeUtc=ServerToUtc(closeSrv);
      Log("SEGNALE PERSO",(sig>0 ? "BUY" : "SELL")+" alla chiusura "+Fmt(UtcToZone(ZONE_ROME,closeUtc))+
          " Roma: EA non attivo in quel momento, nessun ingresso in ritardo");
      if(!InpCloseOnMissedOpposite) continue;
      ulong t[];
      int n=GetEAPositions(t);
      for(int i=0;i<n;i++)
        {
         if(!PositionSelectByTicket(t[i])) continue;
         datetime po=(datetime)PositionGetInteger(POSITION_TIME);
         if((long)closeSrv<=(long)po) continue;          // segnale precedente all'apertura
         if(PosDir(t[i])==sig) continue;
         if(!IsInEntryWindow(closeUtc) && !InpCloseOnOppositeOutsideWindow) continue;
         bool mc=false;
         if(ClosePositionConfirmed(t[i],"segnale opposto perso durante l'inattivita'",mc,true))
            g_statMissedCloses++;
         else
           {
            SetPendingClose(t[i],0,0,false,mc);
            Notify("chiusura per segnale opposto perso NON riuscita: nuovi tentativi automatici");
           }
        }
     }
   Log("RECUPERO",I2S(to-from+1)+" candele M15 elaborate dopo inattivita'/riconnessione, segnali trovati: "+I2S(found));
   SaveLastProcessed(r[to].time);
  }

void ProcessFreshBar(const MqlRates &r[],const double &wt1[],const double &wt2[],const int k)
  {
   datetime closeSrv=(datetime)((long)r[k].time+BAR_SEC);
   datetime closeUtc=ServerToUtc(closeSrv);
   int sig=DetectCross(wt1,wt2,k);
   SaveLastProcessed(r[k].time);
   if(sig!=0) g_statSignals++;

   bool inProc=IsInProcessWindow(closeUtc);
   if(inProc || sig!=0 || InpLogEveryBar)
     {
      string gap="";
      if(k>0 && (long)r[k].time-(long)r[k-1].time!=BAR_SEC)
         gap=" | NOTA: candela precedente distante "+I2S(((long)r[k].time-(long)r[k-1].time)/60)+" min (buco dati o pausa mercato)";
      int c=GetDayCount(RomeDayKey(closeUtc));
      Log("CANDELA","chiusa "+HHMM(UtcToZone(ZONE_ROME,closeUtc))+" Roma ("+Fmt(closeSrv)+" server)"+
          " | O "+PStr(r[k].open)+" H "+PStr(r[k].high)+" L "+PStr(r[k].low)+" C "+PStr(r[k].close)+
          " | prec wt1 "+D2S(wt1[k-1],4)+" wt2 "+D2S(wt2[k-1],4)+
          " | wt1 "+D2S(wt1[k],4)+" wt2 "+D2S(wt2[k],4)+
          " | segnale "+(sig>0 ? "BUY" : (sig<0 ? "SELL" : "nessuno"))+
          " | finestra ingressi "+YesNo(IsInEntryWindow(closeUtc))+
          " | posizione EA "+EAPositionText()+
          " | operazioni oggi "+I2S(c)+"/"+I2S(InpMaxTradesPerDay)+gap);
     }
   if(sig==0) return;
   HandleSignal(sig,closeUtc);
  }

//+------------------------------------------------------------------+
//| Rilevamento delle candele M15 completate                          |
//+------------------------------------------------------------------+
void CheckNewBars(const datetime nowSrv,const datetime nowUtc)
  {
   datetime lastBar=(datetime)SeriesInfoInteger(g_sym,PERIOD_M15,SERIES_LASTBAR_DATE);
   if(lastBar<=0) return;

   if(g_firstBarCheck)
     {
      g_firstBarCheck=false;
      if(g_lastProcessedBarOpen>(datetime)((long)lastBar+BAR_SEC))
        {
         Log("STATO","memoria dell'ultima candela elaborata incoerente con i dati: azzerata");
         g_lastProcessedBarOpen=0;
        }
     }

   bool lastDone=((long)lastBar+BAR_SEC+InpBarCloseGraceSec<=(long)nowSrv);
   if(lastDone) { if(lastBar<=g_lastProcessedBarOpen) return; }
   else         { if(lastBar==g_lastSeenFormingBar) return; }

   MqlRates r[];
   ArraySetAsSeries(r,false);
   int got=CopyRates(g_sym,PERIOD_M15,0,InpWarmupBars+1,r);
   if(got<=0)
     {
      if((long)nowUtc-(long)g_lastDataErrLog>=300)
        {
         Log("DATI","lettura candele M15 non riuscita, errore "+I2S(GetLastError()));
         g_lastDataErrLog=nowUtc;
        }
      return;
     }
   int last=got-1;
   int k=((long)r[last].time+BAR_SEC+InpBarCloseGraceSec<=(long)nowSrv) ? last : last-1;
   if(!lastDone) g_lastSeenFormingBar=lastBar;
   if(k<0) return;
   if(r[k].time<=g_lastProcessedBarOpen) return;

   int cnt=k+1;
   if(cnt<g_minBars)
     {
      if((long)nowUtc-(long)g_lastDataErrLog>=3600)
        {
         Log("DATI","storico M15 insufficiente: "+I2S(cnt)+" candele completate, servono "+I2S(g_minBars)+
             ". Nessun segnale valutato finche' lo storico non e' sufficiente.");
         g_lastDataErrLog=nowUtc;
        }
      SaveLastProcessed(r[k].time);
      return;
     }

   double wt1[],wt2[];
   ComputeWT(r,cnt,wt1,wt2);
   CheckRepaint(r,k,wt1,wt2);

   // candele successive all'ultima elaborata
   int first=k;
   if(g_lastProcessedBarOpen>0)
     {
      while(first-1>=0 && r[first-1].time>g_lastProcessedBarOpen) first--;
     }
   else
     {
      // nessuna memoria: se c'e' una posizione dell'EA controlla dalla sua apertura
      datetime po=EarliestEAPositionOpen();
      if(po>0)
         while(first-1>=0 && (long)r[first-1].time+BAR_SEC>(long)po) first--;
     }
   if(first<g_validStart+1) first=g_validStart+1;

   datetime kCloseUtc=ServerToUtc((datetime)((long)r[k].time+BAR_SEC));
   bool kFresh=((long)nowUtc<=(long)kCloseUtc+InpMaxEntryDelaySec);
   int lastMissed=kFresh ? k-1 : k;

   if(lastMissed>=first)
      HandleMissedBars(r,wt1,wt2,first,lastMissed);
   if(kFresh)
      ProcessFreshBar(r,wt1,wt2,k);
   else
      SaveLastProcessed(r[k].time);
  }

//+------------------------------------------------------------------+
//| Controlli periodici                                               |
//+------------------------------------------------------------------+
void CheckConnection(const datetime nowUtc)
  {
   if(g_isTester) return;
   bool c=(TerminalInfoInteger(TERMINAL_CONNECTED)!=0);
   if(c==g_wasConnected) return;
   g_wasConnected=c;
   if(c)
     {
      g_reconnectUtc=nowUtc;
      Log("CONNESSIONE","connessione al server ripristinata");
     }
   else
      Notify("connessione al server persa");
  }

void CheckClock()
  {
   if(g_isTester || InpTimeCheck==TIMECHECK_OFF) { g_clockOk=true; return; }
   datetime gmt=TimeGMT();
   if(g_clockChecked && (long)gmt-(long)g_lastClockCheck<60) return;
   g_lastClockCheck=gmt;
   long measured=(long)TimeTradeServer()-(long)gmt;
   long expected=ZoneOffSec(ZONE_SERVER,gmt);
   long diff=measured-expected;
   bool ok=(MathAbs((double)diff)<=InpTimeCheckTolSec);
   if(!g_clockChecked || ok!=g_clockOk)
     {
      if(ok)
         Log("ORARIO","controllo orario superato: offset server misurato "+I2S(measured/60)+" min = previsto "+I2S(expected/60)+" min");
      else
         Notify("INCOERENZA ORARIO: offset server misurato "+I2S(measured/60)+" min, previsto dalla regola "+I2S(expected/60)+
                " min (differenza "+I2S(diff)+" s). Verificare l'orologio del VPS e le regole di fuso orario."+
                (InpTimeCheck==TIMECHECK_BLOCK ? " Nuove aperture BLOCCATE." : ""));
     }
   g_clockOk=ok;
   g_clockChecked=true;
  }

void OnNewRomeDay(const int key)
  {
   g_dayKey=key;
   g_preflightDone=false;
   g_statTodayEntries=0;
   if(g_blockAnomaly && StringFind(g_blockAnomalyText,"esito di un ingresso incerto")==0)
     {
      g_blockAnomaly=false;
      g_blockAnomalyText="";
     }
   Log("GIORNO","nuovo giorno di calendario italiano "+I2S(key));
  }

void MaybePreflight(const datetime nowUtc)
  {
   if(g_preflightDone) return;
   if(!IsInProcessWindow(nowUtc)) return;
   g_preflightDone=true;
   LogTimeDiagnostics("PRE-ANALISI");
   MqlTick tk;
   SymbolInfoTick(g_sym,tk);
   long stops=SymbolInfoInteger(g_sym,SYMBOL_TRADE_STOPS_LEVEL);
   g_blockStops=((double)stops*g_point>=MathMin(InpSLDistance,InpTPDistance));
   string why;
   bool ok=CanOpenBasic(why);
   int c=GetDayCount(RomeDayKey(nowUtc));
   Log("PRE-ANALISI","bid "+PStr(tk.bid)+" ask "+PStr(tk.ask)+" spread "+PStr(tk.ask-tk.bid)+
       " | stops level "+I2S(stops)+" point | posizione EA "+EAPositionText()+
       " | operazioni oggi "+I2S(c)+"/"+I2S(InpMaxTradesPerDay)+
       " | aperture possibili: "+(ok ? "si" : "no ("+why+")"));
  }

void HandlePendingClose(const datetime nowUtc)
  {
   if(g_pendCloseTicket==0) return;
   bool done=false;
   if(!PositionSelectByTicket(g_pendCloseTicket))
     {
      Log("CHIUSURA","la posizione in attesa di chiusura non e' piu' aperta (SL/TP o chiusura esterna)");
      done=true;
     }
   else
     {
      if(nowUtc<g_pendNextTryUtc) return;
      bool verbose=((long)nowUtc-(long)g_pendLastLogUtc>=3600);
      bool mc=false;
      if(ClosePositionConfirmed(g_pendCloseTicket,"nuovo tentativo di chiusura in attesa",mc,verbose))
        {
         Log("CHIUSURA","chiusura in attesa completata");
         g_statRevCloses++;
         done=true;
        }
      else
        {
         g_pendNextTryUtc=(datetime)((long)nowUtc+(mc ? 60 : InpPendingCloseRetrySec));
         if(verbose)
           {
            g_pendLastLogUtc=nowUtc;
            Notify("chiusura ancora non riuscita"+(mc ? " (mercato chiuso)" : "")+", continuo a ritentare");
           }
        }
     }
   if(!done) return;
   int  dir=g_pendRevDir;
   datetime bc=g_pendRevBarCloseUtc;
   bool reopen=g_pendAllowReopen;
   g_pendCloseTicket=0;
   g_pendRevDir=0;
   g_pendRevBarCloseUtc=0;
   g_pendAllowReopen=false;
   if(reopen && dir!=0 && CountEAPositions()==0)
      TryEntry(dir,bc,true);   // rispetta comunque finestra, limite e scadenza
  }

//+------------------------------------------------------------------+
//| Ciclo principale (chiamato da OnTick e OnTimer)                   |
//+------------------------------------------------------------------+
void Process()
  {
   if(g_busy) return;
   g_busy=true;
   datetime nowSrv=ServerNow();
   datetime nowUtc=ServerToUtc(nowSrv);
   int dk=RomeDayKey(nowUtc);
   if(dk!=g_dayKey) OnNewRomeDay(dk);
   CheckConnection(nowUtc);
   CheckClock();
   MaybePreflight(nowUtc);
   HandlePendingClose(nowUtc);
   CheckNewBars(nowSrv,nowUtc);
   g_busy=false;
  }

//+------------------------------------------------------------------+
//| Validazioni iniziali                                             |
//+------------------------------------------------------------------+
bool InitFail(const string msg)
  {
   Print("[WT67NDX100_100k] AVVIO NON RIUSCITO: ",msg);
   Alert("WT67NDX100_100k - avvio non riuscito: ",msg);
   return false;
  }

bool ValidateInputs()
  {
   if(InpChannelLen<1 || InpAverageLen<1 || InpSignalLen<1) return InitFail("lunghezze WaveTrend non valide");
   g_validStart=2*(InpChannelLen-1)+(InpAverageLen-1)+(InpSignalLen-1);
   if(InpWarmupBars<g_validStart+200) return InitFail("InpWarmupBars deve essere almeno "+I2S(g_validStart+200));
   g_minBars=InpWarmupBars;
   if(InpEqualEps<0.0) return InitFail("tolleranza di uguaglianza negativa");

   g_preMin=ParseHHMM(InpPreAnalysis);
   g_startMin=ParseHHMM(InpEntryStart);
   g_endMin=ParseHHMM(InpEntryEnd);
   g_procEndMin=ParseHHMM(InpProcessEnd);
   if(g_preMin<0 || g_startMin<0 || g_endMin<0 || g_procEndMin<0) return InitFail("orari non validi (formato HH:MM)");
   if(!(g_preMin<=g_startMin && g_startMin<=g_endMin && g_endMin<=g_procEndMin))
      return InitFail("orari non in sequenza: inizio analisi <= inizio ingressi <= fine ingressi <= fine elaborazione");
   if(InpMaxEntryDelaySec<1)   return InitFail("ritardo massimo di ingresso non valido");
   if(InpBarCloseGraceSec<0)   return InitFail("attesa di chiusura candela non valida");
   if(InpMaxTradesPerDay<0)    return InitFail("limite giornaliero non valido");
   if(InpSLDistance<=0.0 || InpTPDistance<=0.0) return InitFail("distanze SL/TP non valide");
   if(InpMaxRetries<1 || InpRetryDelayMs<0 || InpPendingCloseRetrySec<1) return InitFail("parametri di esecuzione non validi");
   if(InpTimeCheckTolSec<0) return InitFail("tolleranza controllo orario non valida");
   if(StringLen(InpCommentPrefix)>12) return InitFail("prefisso commento troppo lungo (max 12 caratteri)");
   g_normalDiffMin=InpRomeStdOffsetMin-InpNYStdOffsetMin;
   if(!ParseOverrides(InpRomeDSTOverride,g_romeOv,"Italia")) return InitFail("override ora legale Italia non valido");
   if(!ParseOverrides(InpNYDSTOverride,g_nyOv,"New York"))   return InitFail("override ora legale New York non valido");
   return true;
  }

bool ReadSymbolSpecs()
  {
   if(!SymbolSelect(g_sym,true)) return InitFail("simbolo "+g_sym+" non disponibile");
   g_digits  =(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   g_point   =SymbolInfoDouble(g_sym,SYMBOL_POINT);
   g_tickSize=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_SIZE);
   g_volMin  =SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   g_volMax  =SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   g_volStep =SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   if(g_point<=0.0 || g_tickSize<=0.0 || g_volStep<=0.0)
      return InitFail("specifiche del simbolo non ancora disponibili (point/tick size/volume step = 0): riprovare dopo la sincronizzazione");

   long   mm=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_netting=(mm==ACCOUNT_MARGIN_MODE_RETAIL_NETTING || mm==ACCOUNT_MARGIN_MODE_EXCHANGE);
   double tickValue=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_VALUE);
   double contract =SymbolInfoDouble(g_sym,SYMBOL_TRADE_CONTRACT_SIZE);
   long   stops    =SymbolInfoInteger(g_sym,SYMBOL_TRADE_STOPS_LEVEL);
   long   freeze   =SymbolInfoInteger(g_sym,SYMBOL_TRADE_FREEZE_LEVEL);
   long   fill     =SymbolInfoInteger(g_sym,SYMBOL_FILLING_MODE);

   Log("SIMBOLO",g_sym+" | "+SymbolInfoString(g_sym,SYMBOL_DESCRIPTION)+
       " | cifre "+I2S(g_digits)+" | point "+D2S(g_point,g_digits)+" | tick size "+D2S(g_tickSize,g_digits)+
       " | tick value "+D2S(tickValue,6)+" "+AccountInfoString(ACCOUNT_CURRENCY)+
       " | dimensione contratto "+D2S(contract,4)+
       " | volume min "+D2S(g_volMin,2)+" max "+D2S(g_volMax,2)+" step "+D2S(g_volStep,2)+
       " | stops level "+I2S(stops)+" point | freeze level "+I2S(freeze)+" point"+
       " | esecuzione "+EnumToString((ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(g_sym,SYMBOL_TRADE_EXEMODE))+
       " | calcolo "+EnumToString((ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(g_sym,SYMBOL_TRADE_CALC_MODE))+
       " | filling "+I2S(fill)+
       " | valuta profitto "+SymbolInfoString(g_sym,SYMBOL_CURRENCY_PROFIT));
   Log("CONTO","login "+I2S(AccountInfoInteger(ACCOUNT_LOGIN))+" | server "+AccountInfoString(ACCOUNT_SERVER)+
       " | valuta "+AccountInfoString(ACCOUNT_CURRENCY)+" | saldo "+D2S(AccountInfoDouble(ACCOUNT_BALANCE),2)+
       " | leva 1:"+I2S(AccountInfoInteger(ACCOUNT_LEVERAGE))+
       " | modalita' "+(g_netting ? "NETTING" : "HEDGING")+" ("+EnumToString((ENUM_ACCOUNT_MARGIN_MODE)mm)+")");

   // lotto: mai arrotondato dall'EA
   if(InpLots<g_volMin-1e-9 || InpLots>g_volMax+1e-9)
      return InitFail("lotto "+D2S(InpLots,2)+" fuori dai limiti del simbolo ("+D2S(g_volMin,2)+" - "+D2S(g_volMax,2)+")");
   double steps=InpLots/g_volStep;
   if(MathAbs(steps-MathRound(steps))>1e-6)
      return InitFail("lotto "+D2S(InpLots,2)+" non multiplo del volume step "+D2S(g_volStep,2));
   double lim=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_LIMIT);
   if(lim>0.0 && InpLots>lim+1e-9) return InitFail("lotto superiore al limite di volume del simbolo");

   // SL/TP: unita' di prezzo e multipli del tick
   double qs=InpSLDistance/g_tickSize, qt=InpTPDistance/g_tickSize;
   if(MathAbs(qs-MathRound(qs))>1e-6 || MathAbs(qt-MathRound(qt))>1e-6)
      Log("AVVISO","le distanze SL/TP non sono multipli del tick size: i livelli verranno arrotondati al tick");
   Log("LIVELLI","SL "+D2S(InpSLDistance,2)+" punti indice = "+D2S(InpSLDistance/g_point,0)+" point MT5 | TP "+
       D2S(InpTPDistance,2)+" punti indice = "+D2S(InpTPDistance/g_point,0)+" point MT5");
   g_blockStops=((double)stops*g_point>=MathMin(InpSLDistance,InpTPDistance));
   if(g_blockStops)
      Notify("stops level del broker ("+I2S(stops)+" point) incompatibile con SL/TP di "+D2S(InpSLDistance,2)+" punti: aperture bloccate");

   // stima del rischio in valuta del conto
   MqlTick tk;
   if(SymbolInfoTick(g_sym,tk) && tk.ask>0.0)
     {
      double loss=0.0, prof=0.0;
      if(OrderCalcProfit(ORDER_TYPE_BUY,g_sym,InpLots,tk.ask,tk.ask-InpSLDistance,loss) &&
         OrderCalcProfit(ORDER_TYPE_BUY,g_sym,InpLots,tk.ask,tk.ask+InpTPDistance,prof))
         Log("RISCHIO","con "+D2S(InpLots,2)+" lotti: perdita a SL circa "+D2S(loss,2)+" | profitto a TP circa "+D2S(prof,2)+
             " "+AccountInfoString(ACCOUNT_CURRENCY)+" (spread e commissioni esclusi)");
     }

   // modalita' di riempimento
   ENUM_ORDER_TYPE_FILLING f=ORDER_FILLING_RETURN;
   if((fill&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)      f=ORDER_FILLING_FOK;
   else if((fill&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) f=ORDER_FILLING_IOC;
   g_trade.SetTypeFilling(f);
   Log("ESECUZIONE","modalita' di riempimento usata: "+EnumToString(f));
   return true;
  }

//+------------------------------------------------------------------+
//| Eventi                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_isTester=(MQLInfoInteger(MQL_TESTER)!=0);
   g_useGv=!g_isTester;
   g_sym=_Symbol;

   if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;
   if(InpExpectedSymbol!="" && InpExpectedSymbol!=_Symbol)
     {
      InitFail("l'EA e' sul grafico "+_Symbol+" ma il simbolo atteso e' "+InpExpectedSymbol);
      return INIT_PARAMETERS_INCORRECT;
     }

   g_csvName="WT67NDX100_100k_"+I2S(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+g_sym+(g_isTester ? "_tester" : "")+".csv";
   g_gvPrefix="WT67_100k_"+I2S(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+g_sym+"_"+I2S((long)InpMagic)+"_";

   Log("AVVIO","WT67NDX100_100k v1.00 | simbolo "+g_sym+" | magic "+I2S((long)InpMagic)+
       " | WaveTrend n1="+I2S(InpChannelLen)+" n2="+I2S(InpAverageLen)+" segnale="+I2S(InpSignalLen)+" HLC3"+
       " | finestra "+InpEntryStart+"-"+InpEntryEnd+" Roma (analisi da "+InpPreAnalysis+", esecuzione entro "+InpProcessEnd+")"+
       " | max "+I2S(InpMaxTradesPerDay)+" operazioni/giorno | SL "+D2S(InpSLDistance,2)+" TP "+D2S(InpTPDistance,2)+
       " | lotti "+D2S(InpLots,2)+(g_isTester ? " | STRATEGY TESTER" : ""));
   if(_Period!=PERIOD_M15)
      Log("AVVISO","il grafico non e' M15: l'EA calcola comunque i segnali solo sulle candele M15");

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetAsyncMode(false);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   if(!ReadSymbolSpecs()) return INIT_FAILED;

   if(g_useGv)
     {
      g_lastProcessedBarOpen=(datetime)(long)GvGet("lastbar",0.0);
      if(g_lastProcessedBarOpen>0)
         Log("STATO","ultima candela elaborata prima del riavvio: "+Fmt(g_lastProcessedBarOpen)+" (server)");
     }

   if(HasPendingEAOrders())
     {
      g_blockAnomaly=true;
      g_blockAnomalyText="presenti ordini pendenti con il Magic dell'EA (l'EA non ne crea)";
      Notify(g_blockAnomalyText+": nuove aperture bloccate");
     }
   ulong t[];
   int n=GetEAPositions(t);
   if(n>1)
     {
      g_blockAnomaly=true;
      g_blockAnomalyText="piu' di una posizione dell'EA aperta";
      Notify(g_blockAnomalyText+": nuove aperture bloccate, le chiusure su segnale restano attive");
     }
   if(n>0) Log("STATO","posizioni dell'EA gia' aperte: "+EAPositionText());
   for(int i=0;i<n;i++)
      EnsureStops(t[i],(InpSLTPMode==SLTP_ORDER_THEN_ALIGN),"verifica all'avvio");
   if(ForeignPositionNetting())
      Notify("conto netting: posizione non dell'EA sullo stesso simbolo, nuove aperture bloccate finche' presente");

   datetime nowUtc=NowUtc();
   g_dayKey=RomeDayKey(nowUtc);
   int c=GetDayCount(g_dayKey);
   Log("CONTATORE","operazioni dell'EA gia' eseguite oggi (storico + memoria): "+I2S(c)+"/"+I2S(InpMaxTradesPerDay));
   g_statTodayEntries=(c>0) ? c : 0;
   LogTimeDiagnostics("AVVIO");

   if(!EventSetTimer(1))
     {
      InitFail("impossibile avviare il timer");
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Log("RIEPILOGO","segnali "+I2S(g_statSignals)+" | ingressi "+I2S(g_statEntries)+" (di cui reversal "+I2S(g_statRevEntries)+")"+
       " | chiusure per segnale opposto "+I2S(g_statRevCloses)+" | chiusure per segnale perso "+I2S(g_statMissedCloses)+
       " | bloccati: limite giornaliero "+I2S(g_statBlockedLimit)+", fuori finestra "+I2S(g_statBlockedWindow)+
       ", scadenza "+I2S(g_statDeadline)+", altri controlli "+I2S(g_statBlockedOther)+
       " | segnali stessa direzione ignorati "+I2S(g_statSameDir));
   Log("VERIFICA","massimo ingressi in un giorno "+I2S(g_statMaxDay)+" (limite "+I2S(InpMaxTradesPerDay)+")"+
       " | ingressi duplicati sulla stessa candela "+I2S(g_statDupEntries)+" | duplicati evitati "+I2S(g_statDupBlocked)+
       " | ricalcoli diversi (repainting) "+I2S(g_statRepaint)+" | motivo uscita "+I2S(reason));
  }

void OnTick()  { Process(); }
void OnTimer() { Process(); }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.symbol!=g_sym) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   string e=(entry==DEAL_ENTRY_IN) ? "APERTURA" : ((entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) ? "CHIUSURA" : "ALTRO");
   Log("DEAL",e+" deal #"+I2S((long)trans.deal)+" posizione #"+I2S(HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID))+
       " | "+EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal,DEAL_TYPE))+
       " | volume "+D2S(HistoryDealGetDouble(trans.deal,DEAL_VOLUME),2)+
       " | prezzo "+PStr(HistoryDealGetDouble(trans.deal,DEAL_PRICE))+
       " | profitto "+D2S(HistoryDealGetDouble(trans.deal,DEAL_PROFIT),2)+
       " | commissione "+D2S(HistoryDealGetDouble(trans.deal,DEAL_COMMISSION),2)+
       " | swap "+D2S(HistoryDealGetDouble(trans.deal,DEAL_SWAP),2)+
       " | motivo "+EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON)));
  }
//+------------------------------------------------------------------+
