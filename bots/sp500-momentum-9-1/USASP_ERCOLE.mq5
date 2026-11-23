//+------------------------------------------------------------------+
//|                                              USAS&P_ERCOLE.mq5   |
//+------------------------------------------------------------------+
//| STRATEGIA                                                        |
//|  Dopo la chiusura dell'ultima seduta USA di ogni mese:           |
//|  - universo = componenti effettivi dell'S&P 500 in quella data   |
//|    (storico composizione da file, anche nei test storici);       |
//|  - per ogni titolo rendimento di solo prezzo, finestra 9-1;      |
//|  - classifica dal rendimento più alto al più basso (relativa,    |
//|    vale anche con rendimenti negativi);                          |
//|  - prima selezione: primi 4 titoli, 25% ciascuno del capitale    |
//|    destinato alla strategia (controvalore della posizione);      |
//|  - mesi successivi: posseduti dal 1° all'8° posto incluso        |
//|    mantenuti, dal 9° in poi venduti; ogni posto libero va al     |
//|    titolo meglio classificato non ancora posseduto, fino a 4;    |
//|  - una sola procedura al mese; la vendita chiude una long.       |
//|                                                                  |
//| FINESTRA 9-1 (interpretazione confermata)                        |
//|  Lettura letterale di "ultimi nove mesi, escluso l'ultimo mese   |
//|  concluso". Con segnale al mese t (appena concluso):             |
//|     chiusura finale   = ultima seduta del mese t-1               |
//|     chiusura iniziale = ultima seduta del mese t-9               |
//|  Esempio: segnale di fine ottobre -> finale = fine settembre,    |
//|  iniziale = fine gennaio; rendimento =                           |
//|     100 * (chiusura settembre / chiusura gennaio - 1)            |
//|  cioè otto mesi effettivi di rendimento. Il mese t è escluso.    |
//|                                                                  |
//| FRAZIONAMENTI                                                    |
//|  La classifica misura la variazione del solo prezzo con chiusure |
//|  confrontabili. Modalità "dati broker": le chiusure si usano     |
//|  solo se nella finestra non compare alcun salto compatibile con  |
//|  uno split (verifica). Modalità "file split": si applicano solo  |
//|  rapporti verificati del file e solo se il salto corrispondente  |
//|  è effettivamente presente nei dati (altrimenti i dati sono già  |
//|  rettificati e non si rettifica due volte). Ogni salto sospetto  |
//|  non spiegato viene segnalato e il titolo non è classificabile   |
//|  finché non viene verificato: nessuna rettifica automatica.      |
//|                                                                  |
//| CASI PARTICOLARI (gestione provvisoria: segnala e chiedi)        |
//|  - Dati mancanti: indicati mese, titolo e prezzo mancante. Il    |
//|    ribilanciamento è sospeso come INDETERMINATO solo se i dati   |
//|    mancanti impediscono di stabilire chi entra o chi esce.       |
//|  - Parità: si procede se gli ordini restano identici; se la      |
//|    parità decide un acquisto o una vendita si segnala. Nessuna   |
//|    priorità alfabetica (l'ordine alfabetico serve solo a         |
//|    rendere stabile la stampa della classifica).                  |
//|  - Posseduto uscito dall'indice: la classifica contiene solo i   |
//|    componenti effettivi; la posizione è segnalata a parte perché |
//|    manca una regola per liquidarla.                              |
//|  - Titolo da comprare non negoziabile: resta al suo posto in     |
//|    classifica e l'ordine è segnalato come ineseguibile; passare  |
//|    al successivo richiede la scelta esplicita UNAV_SALTA.        |
//+------------------------------------------------------------------+
#property copyright   "Ercole"
#property version     "2.00"
#property description "S&P 500 momentum 9-1 (gennaio->settembre per segnale di ottobre): top 4, mantieni fino all'8° posto."

#include <Trade\Trade.mqh>

#define N_TARGET   4      // titoli in portafoglio
#define KEEP_MAX   8      // posseduti mantenuti fino a questo posto incluso
#define WIN_START  9      // chiusura iniziale = mese t-9
#define WIN_END    1      // chiusura finale   = mese t-1
#define EPS_RET    1e-9   // tolleranza per parità di rendimento (punti %)
#define COV_TOP    20     // posizioni memorizzate per mese nel rapporto di copertura

enum ENUM_RUN_MODE
  {
   MODE_TRADING   = 0, // Trading / backtest della strategia
   MODE_COPERTURA = 1  // Solo rapporto di copertura dati (nessun ordine)
  };
enum ENUM_WGT_MODE
  {
   WGT_DA_CONFERMARE    = 0, // DA CONFERMARE
   WGT_RESET_25         = 1, // (a) Riporta tutti e 4 al 25% a ogni ribilanciamento
   WGT_OSCILLA_PROCEEDS = 2, // (b) Pesi liberi: ricavato vendite diviso in parti uguali tra i nuovi
   WGT_OSCILLA_RESIDUO  = 3  // (c) Pesi liberi: (capitale - valore mantenuti) diviso tra i nuovi
  };
enum ENUM_CAP_MODE
  {
   CAP_DA_CONFERMARE = 0, // DA CONFERMARE
   CAP_EQUITY_PCT    = 1, // Percentuale dell'equity
   CAP_FISSO         = 2  // Importo fisso
  };
enum ENUM_EXE_MODE
  {
   EXE_DA_CONFERMARE      = 0, // DA CONFERMARE (nel tester: ipotesi prima apertura USA, dichiarata)
   EXE_PRIMA_APERTURA_USA = 1, // Prima apertura ordinaria USA successiva (09:30 New York)
   EXE_PERSONALIZZATA     = 2  // Giorno di borsa N del nuovo mese, ora server indicata
  };
enum ENUM_TZ_MODE { TZ_EU_DST = 0, TZ_US_DST = 1, TZ_FISSO = 2 };
enum ENUM_SPLIT_MODE
  {
   SPLIT_DATI_BROKER = 0, // Chiusure broker, verificate senza salti da split
   SPLIT_FILE        = 1  // Chiusure broker + rapporti di split verificati da file
  };
enum ENUM_POL_EXIT { EXIT_BLOCCA = 0, EXIT_VENDI = 1 };  // posseduto uscito dall'indice
enum ENUM_POL_UNAV { UNAV_BLOCCA = 0, UNAV_SALTA = 1 };  // titolo da comprare non negoziabile

input group "=== Modalità ==="
input ENUM_RUN_MODE InpRunMode = MODE_TRADING;   // Modalità di esecuzione
input datetime      InpCovFrom = D'1996.01.01';  // [Copertura] primo mese di segnale
input datetime      InpCovTo   = 0;              // [Copertura] ultimo mese (0 = ultimo concluso)

input group "=== Decisioni ancora aperte ==="
input ENUM_WGT_MODE InpWeights          = WGT_DA_CONFERMARE; // Pesi dopo il primo mese: (a), (b) o (c)
input ENUM_CAP_MODE InpCapMode          = CAP_DA_CONFERMARE; // Capitale destinato alla strategia
input double        InpCapPct           = 100.0;             // % dell'equity
input double        InpCapFixed         = 100000.0;          // Importo fisso (valuta del conto)
input ENUM_EXE_MODE InpExec             = EXE_DA_CONFERMARE; // Momento degli ordini
input int           InpCustomTradingDay = 1;                 // [Personalizzata] giorno di borsa del nuovo mese
input string        InpCustomServerTime = "17:00";           // [Personalizzata] ora server HH:MM

input group "=== Universo e simboli ==="
input string InpUniverseFile   = "sp500_constituents.csv"; // Storico composizione (data,"T1,T2,...")
input int    InpUniverseMaxAge = 45;                       // Giorni massimi oltre l'ultima riga del file
input string InpSymbolMapFile  = "sp500_symbol_map.csv";   // Mappa ticker;simbolo broker (opzionale)
input string InpSplitFile      = "sp500_splits.csv";       // Split verificati ticker;AAAA-MM-GG;rapporto
input bool   InpFilesCommon    = true;                     // File in Terminal\Common\Files
input string InpSymPrefix      = "";                       // Prefisso simboli broker
input string InpSymSuffix      = "";                       // Suffisso simboli broker (es. ".US")
input string InpDotReplace     = ".";                      // Sostituto del punto nei ticker (BRK.B)
input string InpCalendarSymbol = "";                       // Simbolo calendario borsa USA (vuoto = grafico)
input ENUM_SPLIT_MODE InpSplitMode = SPLIT_DATI_BROKER;    // Prezzi confrontabili
input double InpSplitGapPct    = 18.0;                     // Salto minimo % considerato possibile split

input group "=== Orari (server) ==="
input ENUM_TZ_MODE InpTzMode         = TZ_EU_DST; // Ora legale del server
input int          InpServerStdGMT   = 2;         // Offset GMT del server in ora solare
input string       InpUSOpenOverride = "";        // Apertura USA in ora server HH:MM (vuoto = calcolata)
input int          InpExecDelayMin   = 0;         // Minuti dopo l'apertura
input bool         InpAllowLateStart = false;     // Esegui anche se avviato dopo il giorno previsto

input group "=== Casi particolari (BLOCCA = sospendi e chiedi) ==="
input ENUM_POL_EXIT InpOnIndexExit   = EXIT_BLOCCA; // Posseduto uscito dall'indice
input ENUM_POL_UNAV InpOnUnavailable = UNAV_BLOCCA; // Titolo da comprare non negoziabile

input group "=== Esecuzione ==="
input ulong InpMagic           = 20261118; // Magic number
input int   InpSlippagePoints  = 50;       // Slippage massimo (punti)
input int   InpMaxOrderTries   = 20;       // Tentativi massimi per ordine
input int   InpRetrySeconds    = 30;       // Pausa tra tentativi (s, conto reale)
input int   InpDataWaitMinutes = 30;       // Attesa massima sincronizzazione dati (conto reale)
input bool  InpRunSelfTest     = true;     // Autotest della logica all'avvio

#define ACT_KEEP   0
#define ACT_ADJUST 1
#define ACT_SELL   2
#define ACT_BUY    3

//--- globali generali
CTrade   g_trade;
bool     g_tester = false;
string   g_cal = "";
bool     g_execHypothesis = false;    // orario non confermato: ipotesi di test dichiarata
datetime g_uDate[];
string   g_uLine[];
datetime g_uLast = 0, g_uFirst = 0;
string   g_mapT[], g_mapS[];
string   g_spT[];
datetime g_spD[];
double   g_spR[];
string   g_anom[];
bool     g_anomBlock = false;
//--- stato
string   g_heldT[], g_heldS[];
int      g_lastDone = -1, g_haltedPersist = -1, g_haltedRun = -1, g_lateNotified = -1;
int      g_dataWaitMonth = -1;
datetime g_dataWaitStart = 0;
//--- segnale del mese
int      g_sigMonth = -1;
string   g_sigHeldKey = "";
string   g_dKeep[], g_dSell[], g_dBuy[], g_dBuyS[];
bool     g_dFirst = false;
int      g_dEmpty = 0;
//--- piano
bool     g_planActive = false;
int      g_planMonth = -1, g_planPhase = 1;
double   g_planCap = 0, g_planFreed = 0;
int      g_planEmpty = 0;
bool     g_planFirst = false;
datetime g_planExec = 0;
string   g_pT[], g_pS[], g_pWhy[];
int      g_pAct[], g_pTries[];
double   g_pVal[], g_pVol[];
datetime g_lastExecTry = 0;
//--- statistiche backtest
int      g_haltCount = 0, g_firstHalt = -1, g_doneAfterHalt = 0, g_firstSig = -1, g_lastSig = -1;
string   g_haltList = "";
//--- copertura
bool     g_covDone = false, g_covPrepared = false;
datetime g_covStart = 0, g_covFromT = 0, g_covToT = 0;
string   g_cT[], g_cS[];
int      g_cState[], g_cOff[], g_cCnt[], g_cGOff[], g_cGCnt[];
int      g_mcM[];
double   g_mcC[];
datetime g_mcD[];
datetime g_gpD[];
double   g_gpR[];
int      g_calM[];
datetime g_calD[];
bool     g_mValid[];
string   g_mReason[], g_mTop[], g_mTopRet[], g_mMiss[], g_mUni[];
int      g_mN[], g_mOk[];
datetime g_mLs[];

//--- prototipi
string MapHeldSym(const string t);
void   CheckTries();
void   SaveState();
int    CountState(int st);

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
int      MonthId(datetime t)  { MqlDateTime s; TimeToStruct(t, s); return s.year * 12 + s.mon - 1; }
datetime MonthStart(int mid)  { MqlDateTime s; ZeroMemory(s); s.year = mid / 12; s.mon = mid % 12 + 1; s.day = 1; return StructToTime(s); }
string   MonthStr(int mid)    { return mid >= 0 ? StringFormat("%04d-%02d", mid / 12, mid % 12 + 1) : "-"; }
datetime DayStart(datetime t) { return t - (t % 86400); }
string   D2S(datetime t)      { return t > 0 ? TimeToString(t, TIME_DATE) : "-"; }
string   Trim(string s)       { StringTrimLeft(s); StringTrimRight(s); return s; }
int      FFlags()             { return InpFilesCommon ? FILE_COMMON : 0; }

int IndexOf(const string &a[], const string v)
  {
   for(int i = 0; i < ArraySize(a); i++)
      if(a[i] == v) return i;
   return -1;
  }
void PushS(string &a[], const string v)     { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
void PushI(int &a[], const int v)           { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
void PushD(double &a[], const double v)     { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
void PushT(datetime &a[], const datetime v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
void CopyS(string &dst[], const string &src[])
  {
   ArrayResize(dst, ArraySize(src));
   for(int i = 0; i < ArraySize(src); i++) dst[i] = src[i];
  }
string Join(const string &a[])
  {
   string s = "";
   for(int i = 0; i < ArraySize(a); i++) s += (i ? "," : "") + a[i];
   return s;
  }
void SortStrings(string &a[])
  {
   for(int i = 1; i < ArraySize(a); i++)
     {
      string k = a[i]; int j = i - 1;
      while(j >= 0 && StringCompare(a[j], k) > 0) { a[j + 1] = a[j]; j--; }
      a[j + 1] = k;
     }
  }
void InsertSorted(string &a[], const string v)
  {
   int lo = 0, hi = ArraySize(a);
   while(lo < hi)
     {
      int mid = (lo + hi) / 2;
      int c = StringCompare(a[mid], v);
      if(c == 0) return;
      if(c < 0) lo = mid + 1; else hi = mid;
     }
   int n = ArraySize(a);
   ArrayResize(a, n + 1, 256);
   for(int q = n; q > lo; q--) a[q] = a[q - 1];
   a[lo] = v;
  }
int BSearchStr(const string &a[], const string v)
  {
   int lo = 0, hi = ArraySize(a) - 1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      int c = StringCompare(a[mid], v);
      if(c == 0) return mid;
      if(c < 0) lo = mid + 1; else hi = mid - 1;
     }
   return -1;
  }
int BSearchInt(const int &a[], int off, int cnt, int v)
  {
   int lo = off, hi = off + cnt - 1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if(a[mid] == v) return mid;
      if(a[mid] < v) lo = mid + 1; else hi = mid - 1;
     }
   return -1;
  }
int SplitCsv(const string s, string &out[])
  {
   ArrayResize(out, 0);
   if(StringLen(s) == 0) return 0;
   return StringSplit(s, ',', out);
  }

string FileBase()  { return StringFormat("USASP_ERCOLE_%I64u", InpMagic); }
string StatePath() { return FileBase() + "_state.txt"; }
string PlanPath()  { return FileBase() + "_plan.txt"; }
string LogPath()   { return FileBase() + "_log.csv"; }
string AnomPath()  { return FileBase() + "_anomalie.txt"; }
string WinPath()   { return FileBase() + "_report.txt"; }

int ParseHM(string s)
  {
   string p[];
   if(StringSplit(Trim(s), ':', p) < 2) return -1;
   int h = (int)StringToInteger(p[0]), m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 3600 + m * 60;
  }

//+------------------------------------------------------------------+
//| Ora legale e apertura USA in ora server                          |
//+------------------------------------------------------------------+
int DaysInMonth(int y, int m) { return (int)((MonthStart(y * 12 + m) - MonthStart(y * 12 + m - 1)) / 86400); }

datetime NthSundayUTC(int year, int mon, int n, int hourUTC) // n = 0 -> ultima domenica
  {
   MqlDateTime s; ZeroMemory(s);
   s.year = year; s.mon = mon; s.day = 1;
   MqlDateTime f; TimeToStruct(StructToTime(s), f);
   int firstSun = 1 + ((7 - f.day_of_week) % 7);
   int day = firstSun;
   if(n > 0) day = firstSun + 7 * (n - 1);
   else { int dim = DaysInMonth(year, mon); while(day + 7 <= dim) day += 7; }
   s.day = day; s.hour = hourUTC;
   return StructToTime(s);
  }
bool IsUSDST(datetime utc)
  {
   MqlDateTime s; TimeToStruct(utc, s);
   datetime st, en;
   if(s.year >= 2007) { st = NthSundayUTC(s.year, 3, 2, 7); en = NthSundayUTC(s.year, 11, 1, 6); }
   else               { st = NthSundayUTC(s.year, 4, 1, 7); en = NthSundayUTC(s.year, 10, 0, 6); }
   return utc >= st && utc < en;
  }
bool IsEUDST(datetime utc)
  {
   MqlDateTime s; TimeToStruct(utc, s);
   return utc >= NthSundayUTC(s.year, 3, 0, 1) && utc < NthSundayUTC(s.year, 10, 0, 1);
  }
int ServerGMT(datetime utc)
  {
   if(InpTzMode == TZ_EU_DST) return InpServerStdGMT + (IsEUDST(utc) ? 1 : 0);
   if(InpTzMode == TZ_US_DST) return InpServerStdGMT + (IsUSDST(utc) ? 1 : 0);
   return InpServerStdGMT;
  }
int NYOpenServerSeconds(datetime day)
  {
   datetime approx = day + 15 * 3600;
   int ny = IsUSDST(approx) ? -4 : -5;
   return 9 * 3600 + 30 * 60 + (ServerGMT(approx) - ny) * 3600;
  }
datetime ExecTime(datetime day)
  {
   if(InpExec == EXE_PERSONALIZZATA) return day + MathMax(0, ParseHM(InpCustomServerTime));
   int hm = (StringLen(InpUSOpenOverride) > 0) ? ParseHM(InpUSOpenOverride) : NYOpenServerSeconds(day);
   return day + hm + InpExecDelayMin * 60;
  }
string ExecDescription()
  {
   if(InpExec == EXE_PERSONALIZZATA)
      return StringFormat("personalizzata: giorno di borsa %d del nuovo mese, ore %s server, primo prezzo negoziabile",
                          InpCustomTradingDay, InpCustomServerTime);
   return StringFormat("%sprima apertura ordinaria USA successiva al segnale (09:30 New York = %s server alla data corrente%s), "
                       "primo prezzo effettivamente negoziabile da quell'istante",
                       g_execHypothesis ? "IPOTESI DI TEST non confermata - " : "",
                       TimeToString(ExecTime(DayStart(TimeCurrent())), TIME_MINUTES),
                       InpExecDelayMin > 0 ? StringFormat(" + %d min", InpExecDelayMin) : "");
  }

//+------------------------------------------------------------------+
//| Calendario di borsa                                              |
//+------------------------------------------------------------------+
bool LastSession(int mid, datetime &d)
  {
   datetime t[];
   int n = CopyTime(g_cal, PERIOD_D1, MonthStart(mid), MonthStart(mid + 1) - 1, t);
   if(n <= 0) return false;
   d = DayStart(t[n - 1]);
   return true;
  }
int SessionsSoFar(datetime now, datetime &lastDay) // sedute del mese corrente fino a ora
  {
   datetime t[];
   int n = CopyTime(g_cal, PERIOD_D1, MonthStart(MonthId(now)), now, t);
   if(n <= 0) { lastDay = 0; return 0; }
   lastDay = DayStart(t[n - 1]);
   return n;
  }

//+------------------------------------------------------------------+
//| File di input                                                    |
//+------------------------------------------------------------------+
bool LoadUniverse()
  {
   ArrayResize(g_uDate, 0); ArrayResize(g_uLine, 0); g_uLast = 0; g_uFirst = 0;
   int h = FileOpen(InpUniverseFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FFlags());
   if(h == INVALID_HANDLE)
     {
      PrintFormat("ERRORE: file universo '%s' non trovato in %s (errore %d).", InpUniverseFile,
                  InpFilesCommon ? "Common\\Files" : "MQL5\\Files", GetLastError());
      return false;
     }
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      if(StringLen(line) < 12) continue;
      ushort c = StringGetCharacter(line, 0);
      if(c < '0' || c > '9') continue; // intestazione
      string ds = StringSubstr(line, 0, 10);
      StringReplace(ds, "-", "."); StringReplace(ds, "/", ".");
      datetime d = StringToTime(ds);
      if(d <= 0) continue;
      string rest = StringSubstr(line, 11);
      StringReplace(rest, "\"", ""); StringReplace(rest, ";", ",");
      int n = ArraySize(g_uDate);
      ArrayResize(g_uDate, n + 1, 4096); ArrayResize(g_uLine, n + 1, 4096);
      g_uDate[n] = d; g_uLine[n] = rest;
      if(d > g_uLast) g_uLast = d;
      if(g_uFirst == 0 || d < g_uFirst) g_uFirst = d;
     }
   FileClose(h);
   PrintFormat("Composizione S&P 500: %d istantanee dal %s al %s.", ArraySize(g_uDate), D2S(g_uFirst), D2S(g_uLast));
   return ArraySize(g_uDate) > 0;
  }
// componenti effettivi alla data d; false se il file non copre la data
bool Constituents(datetime d, string &out[], datetime &snap, bool dedupe = true)
  {
   ArrayResize(out, 0);
   if(d > g_uLast + InpUniverseMaxAge * 86400) return false;
   int best = -1;
   for(int i = 0; i < ArraySize(g_uDate); i++)
      if(g_uDate[i] <= d && (best < 0 || g_uDate[i] >= g_uDate[best])) best = i;
   if(best < 0) return false;
   snap = g_uDate[best];
   string p[];
   int n = StringSplit(g_uLine[best], ',', p);
   for(int i = 0; i < n; i++)
     {
      string t = Trim(p[i]);
      StringToUpper(t);
      if(StringLen(t) == 0) continue;
      if(dedupe && IndexOf(out, t) >= 0) continue;
      PushS(out, t);
     }
   return ArraySize(out) > 0;
  }
void LoadMap()
  {
   ArrayResize(g_mapT, 0); ArrayResize(g_mapS, 0);
   int h = FileOpen(InpSymbolMapFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FFlags());
   if(h == INVALID_HANDLE) { Print("Mappa simboli assente: uso prefisso/suffisso."); return; }
   while(!FileIsEnding(h))
     {
      string line = Trim(FileReadString(h));
      if(StringLen(line) == 0 || StringGetCharacter(line, 0) == '#') continue;
      StringReplace(line, ",", ";");
      string p[];
      if(StringSplit(line, ';', p) < 2) continue;
      string t = Trim(p[0]); StringToUpper(t);
      if(t == "TICKER") continue;
      PushS(g_mapT, t); PushS(g_mapS, Trim(p[1]));
     }
   FileClose(h);
   PrintFormat("Mappa simboli: %d voci.", ArraySize(g_mapT));
  }
void LoadSplits()
  {
   ArrayResize(g_spT, 0); ArrayResize(g_spD, 0); ArrayResize(g_spR, 0);
   int h = FileOpen(InpSplitFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FFlags());
   if(h == INVALID_HANDLE)
     {
      if(InpSplitMode == SPLIT_FILE) Print("ATTENZIONE: modalità SPLIT_FILE ma file split assente: nessuna rettifica disponibile.");
      return;
     }
   while(!FileIsEnding(h))
     {
      string line = Trim(FileReadString(h));
      if(StringLen(line) == 0 || StringGetCharacter(line, 0) == '#') continue;
      StringReplace(line, ",", ";");
      string p[];
      if(StringSplit(line, ';', p) < 3) continue;
      string ds = Trim(p[1]); StringReplace(ds, "-", ".");
      datetime d = StringToTime(ds);
      double r = StringToDouble(Trim(p[2]));
      if(d <= 0 || r <= 0) continue;
      string t = Trim(p[0]); StringToUpper(t);
      PushS(g_spT, t); PushT(g_spD, DayStart(d)); PushD(g_spR, r);
     }
   FileClose(h);
   PrintFormat("Split verificati: %d voci.", ArraySize(g_spT));
  }
string MapSymbol(const string ticker)
  {
   int k = IndexOf(g_mapT, ticker);
   if(k >= 0) return g_mapS[k];
   string t = ticker;
   if(InpDotReplace != ".") StringReplace(t, ".", InpDotReplace);
   return InpSymPrefix + t + InpSymSuffix;
  }
string TickerFromSymbol(const string sym)
  {
   int k = IndexOf(g_heldS, sym);
   if(k >= 0) return g_heldT[k];
   k = IndexOf(g_mapS, sym);
   if(k >= 0) return g_mapT[k];
   string t = sym;
   if(StringLen(InpSymPrefix) > 0 && StringFind(t, InpSymPrefix) == 0) t = StringSubstr(t, StringLen(InpSymPrefix));
   int ls = StringLen(InpSymSuffix);
   if(ls > 0 && StringLen(t) > ls && StringSubstr(t, StringLen(t) - ls) == InpSymSuffix) t = StringSubstr(t, 0, StringLen(t) - ls);
   if(InpDotReplace != "." && StringLen(InpDotReplace) > 0) StringReplace(t, InpDotReplace, ".");
   StringToUpper(t);
   return t;
  }
bool SymbolOk(const string sym)
  {
   bool custom = false;
   if(!SymbolExist(sym, custom)) return false;
   SymbolSelect(sym, true);
   return true;
  }

//+------------------------------------------------------------------+
//| Frazionamenti: verifica e rettifica                              |
//+------------------------------------------------------------------+
bool IsSplitLike(double g)
  {
   if(g <= 0 || MathAbs(g - 1.0) * 100.0 < InpSplitGapPct) return false;
   double ks[] = {1.25, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 15.0, 20.0, 25.0, 30.0, 50.0};
   for(int k = 0; k < ArraySize(ks); k++)
      if(MathAbs(g * ks[k] - 1.0) < 0.05 || MathAbs(g / ks[k] - 1.0) < 0.05) return true;
   return false;
  }
// gD/gR: salti simili a split (apertura / chiusura precedente).
// Restituisce false se nella finestra resta almeno un salto non verificato.
bool SplitAdjust(const string ticker, datetime d0, datetime d1, const datetime &gD[], const double &gR[],
                 double &factor, string &suspect, string &note)
  {
   factor = 1.0; suspect = ""; note = "";
   int ns = ArraySize(g_spT);
   bool used[];
   ArrayResize(used, ns);
   for(int k = 0; k < ns; k++) used[k] = false;
   for(int i = 0; i < ArraySize(gD); i++)
     {
      if(gD[i] <= d0 || gD[i] > d1) continue;
      bool matched = false;
      if(InpSplitMode == SPLIT_FILE)
         for(int k = 0; k < ns; k++)
            if(!used[k] && g_spT[k] == ticker && MathAbs((double)(g_spD[k] - gD[i])) <= 4 * 86400 &&
               MathAbs(gR[i] * g_spR[k] - 1.0) < 0.10)
              {
               factor *= g_spR[k]; used[k] = true; matched = true;
               note += StringFormat("split verificato %s rapporto %.4f applicato; ", D2S(g_spD[k]), g_spR[k]);
               break;
              }
      if(!matched)
         suspect += StringFormat("salto %+.1f%% il %s (rapporto %.4f) da verificare; ", (gR[i] - 1.0) * 100.0, D2S(gD[i]), gR[i]);
     }
   if(InpSplitMode == SPLIT_FILE)
      for(int k = 0; k < ns; k++)
         if(!used[k] && g_spT[k] == ticker && g_spD[k] > d0 && g_spD[k] <= d1)
            note += StringFormat("split %s (rapporto %.4f) già rettificato nei dati: nessuna rettifica; ", D2S(g_spD[k]), g_spR[k]);
   return StringLen(suspect) == 0;
  }

//+------------------------------------------------------------------+
//| Prezzi in modalità trading                                       |
//+------------------------------------------------------------------+
// 1 = ok, 0 = nessun dato, 2 = non aggiornato all'ultima seduta, -1 = non sincronizzato
int GetMonthClose(const string sym, int mid, datetime ref, double &c, datetime &d)
  {
   MqlRates r[];
   int n = CopyRates(sym, PERIOD_D1, MonthStart(mid), MonthStart(mid + 1) - 1, r);
   if(n < 0) return -1;
   if(n == 0) return 0;
   c = r[n - 1].close; d = DayStart(r[n - 1].time);
   if(c <= 0) return 0;
   if(d < ref) return 2;
   return 1;
  }
string CloseProblem(int code, const string which, int mid, datetime ref, datetime got)
  {
   if(code == 1) return "";
   if(code == 2) return StringFormat("chiusura %s di fine %s (seduta %s) non aggiornata: ultimo dato %s", which, MonthStr(mid), D2S(ref), D2S(got));
   if(code < 0)  return StringFormat("chiusura %s di fine %s (seduta %s) non sincronizzata", which, MonthStr(mid), D2S(ref));
   return StringFormat("chiusura %s di fine %s (seduta %s) mancante", which, MonthStr(mid), D2S(ref));
  }
string JoinProblems(const string a, const string b)
  {
   if(a == "") return b;
   if(b == "") return a;
   return a + "; " + b;
  }
// ritorna 1 classificabile, 0 non classificabile, -1 dati non sincronizzati
int EvalTicker(const string t, const string sym, int iniM, int finM, datetime lsIni, datetime lsFin,
               double &c0, datetime &d0, double &c1, datetime &d1, double &f, double &ret, string &st, string &desc)
  {
   c0 = 0; c1 = 0; d0 = 0; d1 = 0; f = 1.0; ret = 0; st = ""; desc = "";
   if(!SymbolOk(sym))
     {
      st = "SIMBOLO_ASSENTE";
      desc = StringFormat("simbolo broker '%s' assente: mancano chiusura iniziale (fine %s) e finale (fine %s)", sym, MonthStr(iniM), MonthStr(finM));
      return 0;
     }
   int a = GetMonthClose(sym, iniM, lsIni, c0, d0);
   int b = GetMonthClose(sym, finM, lsFin, c1, d1);
   if(!g_tester && (a < 0 || b < 0))
     {
      st = "NON_SINCRONIZZATO";
      desc = JoinProblems(CloseProblem(a, "iniziale", iniM, lsIni, d0), CloseProblem(b, "finale", finM, lsFin, d1));
      return -1;
     }
   if(a != 1 || b != 1)
     {
      st = "DATI_MANCANTI";
      desc = JoinProblems(CloseProblem(a, "iniziale", iniM, lsIni, d0), CloseProblem(b, "finale", finM, lsFin, d1));
      return 0;
     }
   MqlRates r[];
   datetime gD[]; double gR[];
   int n = CopyRates(sym, PERIOD_D1, d0, d1 + 86399, r);
   for(int i = 1; i < n; i++)
      if(r[i - 1].close > 0 && IsSplitLike(r[i].open / r[i - 1].close))
        { PushT(gD, DayStart(r[i].time)); PushD(gR, r[i].open / r[i - 1].close); }
   string susp = "", note = "";
   if(!SplitAdjust(t, d0, d1, gD, gR, f, susp, note))
     {
      st = "SPLIT_DA_VERIFICARE";
      desc = "chiusure non confrontabili finché il salto non è verificato: " + susp;
      return 0;
     }
   ret = 100.0 * (c1 / (c0 / f) - 1.0);
   st = "OK"; desc = note;
   return 1;
  }

//+------------------------------------------------------------------+
//| Valuta, contratto, volumi                                        |
//+------------------------------------------------------------------+
double FxToAccount(const string cur)
  {
   string acc = AccountInfoString(ACCOUNT_CURRENCY);
   if(cur == "" || cur == acc) return 1.0;
   string sfx[2]; sfx[0] = ""; sfx[1] = InpSymSuffix;
   for(int i = 0; i < 2; i++)
     {
      string s = cur + acc + sfx[i];
      if(SymbolOk(s)) { double b = SymbolInfoDouble(s, SYMBOL_BID); if(b > 0) return b; }
      s = acc + cur + sfx[i];
      if(SymbolOk(s)) { double a = SymbolInfoDouble(s, SYMBOL_ASK); if(a > 0) return 1.0 / a; }
     }
   return 0.0;
  }
double ValuePerLot(const string sym, double price) // controvalore di 1 lotto nella valuta del conto
  {
   double cs = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double fx = FxToAccount(SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT));
   if(cs > 0 && fx > 0) return price * cs * fx;
   double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tv > 0 && ts > 0) return price * tv / ts;
   return 0.0;
  }
int StepDigits(double step)
  {
   int d = 0;
   while(d < 8 && MathAbs(step - MathRound(step)) > 1e-9) { step *= 10.0; d++; }
   return d;
  }
double VolStep(const string sym)
  {
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   return step > 0 ? step : 1.0;
  }
double NormVolDown(const string sym, double v)
  {
   double step = VolStep(sym), mx = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   v = MathFloor(v / step + 1e-9) * step;
   if(mx > 0 && v > mx) v = mx;
   return NormalizeDouble(v, StepDigits(step));
  }
double VolumeForValue(const string sym, double value, double ask)
  {
   double vpl = ValuePerLot(sym, ask);
   if(ask <= 0 || vpl <= 0 || value <= 0) return 0.0;
   double v = NormVolDown(sym, value / vpl);
   if(v < SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN) - 1e-9) return 0.0;
   return v;
  }
double EAVolume(const string sym)
  {
   double v = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
      v += PositionGetDouble(POSITION_VOLUME);
     }
   return v;
  }
double PositionValue(const string sym) { return EAVolume(sym) * ValuePerLot(sym, SymbolInfoDouble(sym, SYMBOL_BID)); }
double StrategyCapital()
  {
   if(InpCapMode == CAP_FISSO) return InpCapFixed;
   return AccountInfoDouble(ACCOUNT_EQUITY) * InpCapPct / 100.0;
  }
bool Buyable(const string sym, string &why)
  {
   why = "";
   if(!SymbolOk(sym)) { why = "simbolo assente"; return false; }
   long mode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
   if(mode != SYMBOL_TRADE_MODE_FULL && mode != SYMBOL_TRADE_MODE_LONGONLY) { why = "acquisto disabilitato dal broker"; return false; }
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(ask <= 0) { why = "nessun prezzo ask"; return false; }
   double est = StrategyCapital() / N_TARGET;
   if(VolumeForValue(sym, est, ask) <= 0) { why = StringFormat("controvalore stimato %.2f sotto il volume minimo", est); return false; }
   return true;
  }
// primo prezzo effettivamente negoziabile dall'istante di esecuzione
bool FreshTick(const string sym, datetime notBefore, MqlTick &tk)
  {
   if(!SymbolInfoTick(sym, tk)) return false;
   if(tk.time < notBefore || tk.ask <= 0 || tk.bid <= 0) return false;
   return SymbolInfoInteger(sym, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_DISABLED;
  }

//+------------------------------------------------------------------+
//| Anomalie                                                         |
//+------------------------------------------------------------------+
void Anom(bool block, const string code, const string detail)
  {
   PushS(g_anom, StringFormat("[%s]%s %s", code, block ? " DA DECIDERE -" : " informazione -", detail));
   if(block) g_anomBlock = true;
  }
void ReportAnomalies(int sig)
  {
   if(ArraySize(g_anom) == 0) return;
   int h = FileOpen(AnomPath(), FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(h != INVALID_HANDLE) FileSeek(h, 0, SEEK_END);
   for(int i = 0; i < ArraySize(g_anom); i++)
     {
      string s = "Segnale " + MonthStr(sig) + " " + g_anom[i];
      Print(s);
      if(h != INVALID_HANDLE) FileWriteString(h, TimeToString(TimeCurrent()) + " " + s + "\r\n");
     }
   if(h != INVALID_HANDLE) FileClose(h);
   if(g_anomBlock)
     {
      string msg = StringFormat("USAS&P_ERCOLE: ribilanciamento %s SOSPESO (indeterminato o caso senza regola). "
                                "Dettagli in %s. Indica come trattarlo, poi riavvia l'EA.", MonthStr(sig), AnomPath());
      Print(msg);
      if(!g_tester) Alert(msg);
     }
  }
void MarkHalted(int sig)
  {
   g_haltedRun = sig; g_haltedPersist = sig; g_haltCount++;
   if(g_firstHalt < 0) g_firstHalt = sig;
   g_haltList += MonthStr(sig) + " ";
   SaveState();
  }

//+------------------------------------------------------------------+
//| Logica di selezione (pura, testabile)                            |
//| ranked: ticker ordinati dal migliore; posizione = indice + 1     |
//+------------------------------------------------------------------+
void DecideCore(const string &ranked[], const bool &buyable[], const string &held[], int nTarget,
                string &keep[], string &sell[], string &buy[], string &skipped[])
  {
   ArrayResize(keep, 0); ArrayResize(sell, 0); ArrayResize(buy, 0); ArrayResize(skipped, 0);
   for(int i = 0; i < ArraySize(held); i++)
     {
      int r = IndexOf(ranked, held[i]) + 1;
      if(r >= 1 && r <= KEEP_MAX) PushS(keep, held[i]);
      else                        PushS(sell, held[i]);
     }
   int slots = nTarget - ArraySize(keep);
   for(int i = 0; i < ArraySize(ranked) && slots > 0; i++)
     {
      if(IndexOf(held, ranked[i]) >= 0) continue; // posseduto (mantenuto o in vendita)
      if(!buyable[i]) { PushS(skipped, ranked[i]); continue; }
      PushS(buy, ranked[i]);
      slots--;
     }
  }
// Con M componenti non classificabili, la posizione vera di ogni titolo
// classificato può peggiorare fino a M posti. Gli ordini sono determinati
// solo se nessun mantenuto rischia di superare l'8° posto e non c'è nessun
// acquisto da decidere (un titolo senza dati potrebbe precedere i candidati).
bool Determinate(const string &ranked[], const string &keep[], const string &buy[], int M, string &why)
  {
   why = "";
   if(M <= 0) return true;
   for(int i = 0; i < ArraySize(keep); i++)
     {
      int r = IndexOf(ranked, keep[i]) + 1;
      if(r + M > KEEP_MAX)
         why += StringFormat("%s al %d° posto potrebbe scendere fino al %d° (mantenere o vendere?); ", keep[i], r, r + M);
     }
   if(ArraySize(buy) > 0)
      why += StringFormat("%d componenti non classificabili potrebbero precedere i candidati all'acquisto (%s): chi entra è incerto; ", M, Join(buy));
   return StringLen(why) == 0;
  }
// true se una parità decide un acquisto o una vendita
bool TieAffects(const double &ret[], const string &ranked[], const bool &buyable[],
                const string &held[], const string &buy[], string &detail)
  {
   int n = MathMin(ArraySize(ranked), ArraySize(ret));
   detail = "";
   if(n > KEEP_MAX && MathAbs(ret[KEEP_MAX - 1] - ret[KEEP_MAX]) < EPS_RET)
     {
      double rb = ret[KEEP_MAX - 1];
      for(int i = 0; i < n; i++)
         if(MathAbs(ret[i] - rb) < EPS_RET && IndexOf(held, ranked[i]) >= 0)
           {
            detail = StringFormat("parità a cavallo dell'8°/9° posto (%.6f%%) che coinvolge il posseduto %s: mantenere o vendere?", rb, ranked[i]);
            return true;
           }
     }
   int nb = ArraySize(buy);
   if(nb > 0)
     {
      int lb = IndexOf(ranked, buy[nb - 1]);
      for(int j = lb + 1; j < n; j++)
        {
         if(IndexOf(held, ranked[j]) >= 0 || !buyable[j]) continue;
         if(MathAbs(ret[j] - ret[lb]) < EPS_RET)
           {
            detail = StringFormat("parità tra %s (pos %d) e %s (pos %d), rendimento %.6f%%: quale acquistare?",
                                  ranked[lb], lb + 1, ranked[j], j + 1, ret[lb]);
            return true;
           }
         break;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Autotest                                                         |
//+------------------------------------------------------------------+
bool SameSet(string &a[], const string csv)
  {
   string e[];
   int n = SplitCsv(csv, e);
   if(n != ArraySize(a)) return false;
   for(int i = 0; i < n; i++) if(IndexOf(a, e[i]) < 0) return false;
   return true;
  }
bool RunCase(const string name, string &held[], bool &b[], const string expKeep, const string expSell,
             const string expBuy, const string expPort)
  {
   string ranked[20];
   for(int i = 0; i < 20; i++) ranked[i] = StringFormat("P%02d", i + 1);
   string k[], s[], bu[], sk[], port[];
   DecideCore(ranked, b, held, N_TARGET, k, s, bu, sk);
   for(int i = 0; i < ArraySize(k); i++)  PushS(port, k[i]);
   for(int i = 0; i < ArraySize(bu); i++) PushS(port, bu[i]);
   bool ok = SameSet(k, expKeep) && SameSet(s, expSell) && SameSet(bu, expBuy) && SameSet(port, expPort);
   SortStrings(port);
   PrintFormat("AUTOTEST %-48s %s  portafoglio=[%s]", name, ok ? "OK" : "FALLITO", Join(port));
   return ok;
  }
bool SelfTest()
  {
   bool all[20];
   ArrayInitialize(all, true);
   bool ok = true;
   string h1[] = {"P02", "P05", "P08", "P09"};
   ok = RunCase("Posseduti 2,5,8,9 -> esce il 9, entra il 1", h1, all, "P02,P05,P08", "P09", "P01", "P01,P02,P05,P08") && ok;
   string h0[];
   ok = RunCase("Prima selezione -> primi 4", h0, all, "", "", "P01,P02,P03,P04", "P01,P02,P03,P04") && ok;
   string h3[] = {"P03", "P06", "P07", "P08"};
   ok = RunCase("Tutti nei primi 8 -> nessun cambio", h3, all, "P03,P06,P07,P08", "", "", "P03,P06,P07,P08") && ok;
   string h4[] = {"P01", "P10", "P12", "P20"};
   ok = RunCase("Escono 10,12,20 -> entrano 2,3,4", h4, all, "P01", "P10,P12,P20", "P02,P03,P04", "P01,P02,P03,P04") && ok;
   bool b5[20];
   ArrayInitialize(b5, true);
   b5[0] = false;
   ok = RunCase("2,5,8,9 con 1° non negoziabile (solo con SALTA)", h1, b5, "P02,P05,P08", "P09", "P03", "P02,P03,P05,P08") && ok;
   //--- determinatezza con dati mancanti
   string rk[20];
   for(int i = 0; i < 20; i++) rk[i] = StringFormat("P%02d", i + 1);
   string kp1[] = {"P02", "P05", "P06", "P07"};
   string kp2[] = {"P02", "P05", "P08"};
   string b2[]  = {"P01"};
   string nob[];
   string why = "";
   bool d1 = Determinate(rk, kp1, nob, 1, why);   // 7°+1 = 8°: determinato
   bool d2 = Determinate(rk, kp2, b2, 1, why);    // acquisto da decidere: indeterminato
   bool d3 = Determinate(rk, kp2, b2, 0, why);    // nessun dato mancante: determinato
   bool okd = d1 && !d2 && d3;
   PrintFormat("AUTOTEST %-48s %s", "Determinatezza con dati mancanti", okd ? "OK" : "FALLITO");
   ok = ok && okd;
   //--- parità
   double rr[20];
   for(int i = 0; i < 20; i++) rr[i] = 100.0 - i;
   string hh[] = {"P02", "P05", "P08", "P11"};
   string bb[] = {"P01"};
   string td = "";
   rr[8] = rr[7];                                  // parità 8°/9° con P08 posseduto
   bool t1 = TieAffects(rr, rk, all, hh, bb, td);
   rr[8] = 92.0; rr[2] = rr[0];                    // parità tra P01 (comprato) e P03 (escluso)
   bool t2 = TieAffects(rr, rk, all, hh, bb, td);
   rr[2] = 98.0;                                   // nessuna parità
   bool t3 = TieAffects(rr, rk, all, hh, bb, td);
   bool okt = t1 && t2 && !t3;
   PrintFormat("AUTOTEST %-48s %s", "Parità che decide un ordine", okt ? "OK" : "FALLITO");
   ok = ok && okt;
   PrintFormat("AUTOTEST complessivo: %s", ok ? "SUPERATO" : "FALLITO");
   return ok;
  }

//+------------------------------------------------------------------+
//| Stato persistente                                                |
//+------------------------------------------------------------------+
void SaveState()
  {
   int h = FileOpen(StatePath(), FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(h == INVALID_HANDLE) { Print("ERRORE salvataggio stato ", GetLastError()); return; }
   FileWriteString(h, "lastDone=" + IntegerToString(g_lastDone) + "\r\n");
   FileWriteString(h, "halted=" + IntegerToString(g_haltedPersist) + "\r\n");
   for(int i = 0; i < ArraySize(g_heldT); i++) FileWriteString(h, "held=" + g_heldT[i] + ";" + g_heldS[i] + "\r\n");
   FileClose(h);
  }
void LoadState()
  {
   ArrayResize(g_heldT, 0); ArrayResize(g_heldS, 0);
   int h = FileOpen(StatePath(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FFlags());
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
     {
      string l = Trim(FileReadString(h));
      if(StringFind(l, "lastDone=") == 0) g_lastDone = (int)StringToInteger(StringSubstr(l, 9));
      else if(StringFind(l, "halted=") == 0) g_haltedPersist = (int)StringToInteger(StringSubstr(l, 7));
      else if(StringFind(l, "held=") == 0)
        {
         string p[];
         if(StringSplit(StringSubstr(l, 5), ';', p) >= 2) { PushS(g_heldT, p[0]); PushS(g_heldS, p[1]); }
        }
     }
   FileClose(h);
   PrintFormat("Stato: ultimo mese completato %s, titoli registrati %d.", MonthStr(g_lastDone), ArraySize(g_heldT));
  }

//+------------------------------------------------------------------+
//| Piano del mese (salvato prima di inviare ordini)                 |
//+------------------------------------------------------------------+
void ClearPlan()
  {
   ArrayResize(g_pT, 0); ArrayResize(g_pS, 0); ArrayResize(g_pWhy, 0);
   ArrayResize(g_pAct, 0); ArrayResize(g_pTries, 0); ArrayResize(g_pVal, 0); ArrayResize(g_pVol, 0);
  }
void AddPlan(const string t, const string s, int act, double val, double vol, const string why)
  {
   PushS(g_pT, t); PushS(g_pS, s); PushI(g_pAct, act); PushD(g_pVal, val); PushD(g_pVol, vol); PushS(g_pWhy, why); PushI(g_pTries, 0);
  }
void SavePlan(const string status)
  {
   int h = FileOpen(PlanPath(), FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(h == INVALID_HANDLE) { Print("ERRORE salvataggio piano ", GetLastError()); return; }
   FileWriteString(h, "month=" + IntegerToString(g_planMonth) + "\r\n");
   FileWriteString(h, "status=" + status + "\r\n");
   FileWriteString(h, "phase=" + IntegerToString(g_planPhase) + "\r\n");
   FileWriteString(h, "cap=" + DoubleToString(g_planCap, 2) + "\r\n");
   FileWriteString(h, "freed=" + DoubleToString(g_planFreed, 2) + "\r\n");
   FileWriteString(h, "empty=" + IntegerToString(g_planEmpty) + "\r\n");
   FileWriteString(h, "first=" + (g_planFirst ? "1" : "0") + "\r\n");
   FileWriteString(h, "exec=" + IntegerToString((long)g_planExec) + "\r\n");
   for(int i = 0; i < ArraySize(g_pT); i++)
     {
      string why = g_pWhy[i];
      StringReplace(why, ";", ",");
      FileWriteString(h, StringFormat("item=%s;%s;%d;%.4f;%.8f;%s\r\n", g_pT[i], g_pS[i], g_pAct[i], g_pVal[i], g_pVol[i], why));
     }
   FileClose(h);
  }
void LoadPlan()
  {
   ClearPlan(); g_planActive = false; g_planMonth = -1;
   int h = FileOpen(PlanPath(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FFlags());
   if(h == INVALID_HANDLE) return;
   string status = "";
   while(!FileIsEnding(h))
     {
      string l = Trim(FileReadString(h));
      if(StringFind(l, "month=") == 0)       g_planMonth = (int)StringToInteger(StringSubstr(l, 6));
      else if(StringFind(l, "status=") == 0) status = StringSubstr(l, 7);
      else if(StringFind(l, "phase=") == 0)  g_planPhase = (int)StringToInteger(StringSubstr(l, 6));
      else if(StringFind(l, "cap=") == 0)    g_planCap = StringToDouble(StringSubstr(l, 4));
      else if(StringFind(l, "freed=") == 0)  g_planFreed = StringToDouble(StringSubstr(l, 6));
      else if(StringFind(l, "empty=") == 0)  g_planEmpty = (int)StringToInteger(StringSubstr(l, 6));
      else if(StringFind(l, "first=") == 0)  g_planFirst = (StringSubstr(l, 6) == "1");
      else if(StringFind(l, "exec=") == 0)   g_planExec = (datetime)StringToInteger(StringSubstr(l, 5));
      else if(StringFind(l, "item=") == 0)
        {
         string p[];
         if(StringSplit(StringSubstr(l, 5), ';', p) >= 6)
            AddPlan(p[0], p[1], (int)StringToInteger(p[2]), StringToDouble(p[3]), StringToDouble(p[4]), p[5]);
        }
     }
   FileClose(h);
   int sig = MonthId(TimeCurrent()) - 1;
   if(status == "ACTIVE" && g_planMonth == sig)
     {
      g_planActive = true;
      PrintFormat("RICONCILIAZIONE: piano incompleto del segnale %s (fase %d, %d righe): riprendo inviando solo le differenze.",
                  MonthStr(g_planMonth), g_planPhase, ArraySize(g_pT));
     }
   else if(status == "ACTIVE")
     {
      PrintFormat("RICONCILIAZIONE: piano del segnale %s incompleto e superato dal nuovo mese: "
                  "le posizioni reali diventano il portafoglio di partenza.", MonthStr(g_planMonth));
      ClearPlan();
     }
  }

//+------------------------------------------------------------------+
//| Riconciliazione posizioni dell'EA                                |
//+------------------------------------------------------------------+
void ReconcileHeld(bool verbose)
  {
   string syms[];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
        { PrintFormat("ATTENZIONE: posizione short con magic EA su %s: la strategia è solo long, non gestita.", s); continue; }
      if(IndexOf(syms, s) < 0) PushS(syms, s);
     }
   string nt[], ns[];
   for(int i = 0; i < ArraySize(syms); i++) { PushS(nt, TickerFromSymbol(syms[i])); PushS(ns, syms[i]); }
   if(verbose)
     {
      for(int i = 0; i < ArraySize(g_heldS); i++)
         if(IndexOf(ns, g_heldS[i]) < 0)
            PrintFormat("RICONCILIAZIONE: %s (%s) nello stato ma senza posizione aperta: considerato non posseduto.", g_heldT[i], g_heldS[i]);
      for(int i = 0; i < ArraySize(ns); i++)
         if(IndexOf(g_heldS, ns[i]) < 0)
            PrintFormat("RICONCILIAZIONE: posizione EA su %s assente dallo stato: considerata posseduta (%s).", ns[i], nt[i]);
     }
   CopyS(g_heldT, nt);
   CopyS(g_heldS, ns);
  }
string HeldKey()
  {
   string a[];
   CopyS(a, g_heldT);
   SortStrings(a);
   return Join(a);
  }
int PendingEAOrders()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t > 0 && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic) n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
//| Registro mensile                                                 |
//+------------------------------------------------------------------+
void WriteLogRows(int sig, datetime lsSig, string &t[], string &s[], string &st[], datetime &d0[], double &c0[],
                  double &f[], datetime &d1[], double &c1[], double &ret[], int &rank[], bool &held[],
                  string &act[], string &why[], string &desc[])
  {
   int h = FileOpen(LogPath(), FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(h == INVALID_HANDLE) { Print("ERRORE apertura registro ", GetLastError()); return; }
   if(FileSize(h) == 0)
      FileWriteString(h, "MeseSegnale;UltimaSeduta;CalcolatoIl;Ticker;Simbolo;StatoDati;DataIniziale;ChiusuraIniziale;FattoreSplit;"
                         "DataFinale;ChiusuraFinale;RendimentoPct;Posizione;PossedutoPrima;Azione;Motivo;NoteDati\r\n");
   FileSeek(h, 0, SEEK_END);
   string now = TimeToString(TimeCurrent());
   for(int i = 0; i < ArraySize(t); i++)
     {
      string dsc = desc[i];
      StringReplace(dsc, ";", ",");
      FileWriteString(h, StringFormat("%s;%s;%s;%s;%s;%s;%s;%.6f;%.6f;%s;%.6f;%s;%s;%s;%s;%s;%s\r\n",
                                      MonthStr(sig), D2S(lsSig), now, t[i], s[i], st[i], D2S(d0[i]), c0[i], f[i],
                                      D2S(d1[i]), c1[i], rank[i] > 0 ? DoubleToString(ret[i], 4) : "-",
                                      rank[i] > 0 ? IntegerToString(rank[i]) : "-", held[i] ? "SI" : "NO",
                                      act[i], why[i], dsc));
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| SEGNALE: dopo la chiusura dell'ultima seduta del mese            |
//| ritorna -1 attendi dati, 0 sospeso, 1 decisioni pronte           |
//+------------------------------------------------------------------+
int BuildSignal(int sig)
  {
   ArrayResize(g_anom, 0); g_anomBlock = false;
   int finM = sig - WIN_END, iniM = sig - WIN_START;
   datetime lsSig = 0, lsFin = 0, lsIni = 0;
   if(!LastSession(sig, lsSig) || !LastSession(finM, lsFin) || !LastSession(iniM, lsIni))
     {
      Anom(true, "CALENDARIO", StringFormat("storico D1 di %s insufficiente per le sedute di fine %s / %s / %s",
                                            g_cal, MonthStr(iniM), MonthStr(finM), MonthStr(sig)));
      ReportAnomalies(sig); MarkHalted(sig); return 0;
     }
   string uni[];
   datetime snap = 0;
   if(!Constituents(lsSig, uni, snap))
     {
      Anom(true, "UNIVERSO", StringFormat("composizione S&P 500 non disponibile al %s (file fino al %s + %d giorni): aggiornare il file",
                                          D2S(lsSig), D2S(g_uLast), InpUniverseMaxAge));
      ReportAnomalies(sig); MarkHalted(sig); return 0;
     }
   ReconcileHeld(true);
   g_sigHeldKey = HeldKey();

   int n = ArraySize(uni);
   string uS[], uSt[], uAct[], uWhy[], uDesc[];
   datetime uD0[], uD1[];
   double uC0[], uC1[], uF[], uRet[];
   int uRank[];
   bool uHeld[];
   ArrayResize(uS, n); ArrayResize(uSt, n); ArrayResize(uAct, n); ArrayResize(uWhy, n); ArrayResize(uDesc, n);
   ArrayResize(uD0, n); ArrayResize(uD1, n); ArrayResize(uC0, n); ArrayResize(uC1, n);
   ArrayResize(uF, n); ArrayResize(uRet, n); ArrayResize(uRank, n); ArrayResize(uHeld, n);
   int notReady = 0, okCount = 0;
   for(int i = 0; i < n; i++)
     {
      uS[i] = MapSymbol(uni[i]); uRank[i] = 0; uHeld[i] = (IndexOf(g_heldT, uni[i]) >= 0); uAct[i] = "-"; uWhy[i] = "";
      double c0, c1, f, ret; datetime d0, d1; string st, desc;
      int e = EvalTicker(uni[i], uS[i], iniM, finM, lsIni, lsFin, c0, d0, c1, d1, f, ret, st, desc);
      uC0[i] = c0; uD0[i] = d0; uC1[i] = c1; uD1[i] = d1; uF[i] = f; uRet[i] = ret; uSt[i] = st; uDesc[i] = desc;
      if(e < 0) notReady++;
      if(e == 1) okCount++;
     }
   if(notReady > 0)
     {
      if(g_dataWaitMonth != sig) { g_dataWaitMonth = sig; g_dataWaitStart = TimeCurrent(); }
      if(TimeCurrent() - g_dataWaitStart < InpDataWaitMinutes * 60)
        { PrintFormat("Dati non ancora sincronizzati per %d simboli: riprovo.", notReady); return -1; }
     }
   int M = n - okCount;
   PrintFormat("Segnale %s calcolato il %s (ultima seduta %s, composizione del %s): %d/%d componenti classificabili. "
               "Rendimento = chiusura fine %s (%s) / chiusura fine %s (%s) - 1.",
               MonthStr(sig), TimeToString(TimeCurrent()), D2S(lsSig), D2S(snap), okCount, n,
               MonthStr(finM), D2S(lsFin), MonthStr(iniM), D2S(lsIni));

   //--- posseduti usciti dall'indice: segnalati a parte, fuori dalla classifica
   string exitHeld[];
   for(int i = 0; i < ArraySize(g_heldT); i++)
      if(IndexOf(uni, g_heldT[i]) < 0)
        {
         PushS(exitHeld, g_heldT[i]);
         string d = StringFormat("%s (%s) posseduto ma non più componente dell'S&P 500 al %s: manca una regola per liquidarlo",
                                 g_heldT[i], g_heldS[i], D2S(lsSig));
         if(InpOnIndexExit == EXIT_BLOCCA) Anom(true, "USCITA_INDICE", d);
         else                              Anom(false, "USCITA_INDICE", d + " -> venduto per scelta esplicita EXIT_VENDI");
        }
   //--- posseduti non classificabili
   for(int i = 0; i < n; i++)
      if(uHeld[i] && uSt[i] != "OK")
         Anom(true, "POSSEDUTO_NON_CLASSIFICABILE", StringFormat("%s posseduto, %s: impossibile stabilire se resta o esce", uni[i], uDesc[i]));

   //--- classifica dei soli componenti effettivi
   int idx[];
   for(int i = 0; i < n; i++) if(uSt[i] == "OK") PushI(idx, i);
   int m = ArraySize(idx);
   for(int i = 1; i < m; i++)
     {
      int k = idx[i], j = i - 1;
      while(j >= 0 && (uRet[idx[j]] < uRet[k] - EPS_RET ||
                       (MathAbs(uRet[idx[j]] - uRet[k]) < EPS_RET && StringCompare(uni[idx[j]], uni[k]) > 0)))
        { idx[j + 1] = idx[j]; j--; }
      idx[j + 1] = k;
     }
   string ranked[], rWhyNo[];
   double rRet[];
   bool rBuy[], rAll[];
   ArrayResize(ranked, m); ArrayResize(rRet, m); ArrayResize(rBuy, m); ArrayResize(rAll, m); ArrayResize(rWhyNo, m);
   for(int i = 0; i < m; i++)
     {
      ranked[i] = uni[idx[i]]; rRet[i] = uRet[idx[i]]; uRank[idx[i]] = i + 1;
      rAll[i] = true;
      string w = "";
      rBuy[i] = Buyable(uS[idx[i]], w);
      rWhyNo[i] = w;
     }
   string heldR[];
   for(int i = 0; i < ArraySize(g_heldT); i++)
      if(IndexOf(exitHeld, g_heldT[i]) < 0) PushS(heldR, g_heldT[i]);

   string keep[], sell[], buy[], skipped[];
   DecideCore(ranked, rAll, heldR, N_TARGET, keep, sell, buy, skipped);  // decisione secondo le regole
   //--- dati mancanti: sospende solo se rendono incerto chi entra o chi esce
   if(M > 0)
     {
      string missTxt = "";
      for(int i = 0; i < n; i++) if(uSt[i] != "OK") missTxt += StringFormat("%s[%s]: %s | ", uni[i], uS[i], uDesc[i]);
      string why = "";
      if(Determinate(ranked, keep, buy, M, why))
         Anom(false, "DATI_MANCANTI", StringFormat("%d componenti non classificabili, ordini comunque determinati: %s", M, missTxt));
      else
         Anom(true, "RIBILANCIAMENTO_INDETERMINATO", StringFormat("%s Titoli e prezzi mancanti (%d): %s", why, M, missTxt));
     }
   //--- parità
   string tieInfo = "";
   if(TieAffects(rRet, ranked, rAll, heldR, buy, tieInfo)) Anom(true, "PARITA", tieInfo);
   //--- titoli da acquistare non negoziabili: restano al loro posto in classifica
   bool anyUnav = false;
   for(int b = 0; b < ArraySize(buy); b++)
     {
      int ri = IndexOf(ranked, buy[b]);
      if(rBuy[ri]) continue;
      anyUnav = true;
      Anom(InpOnUnavailable == UNAV_BLOCCA, "ORDINE_INESEGUIBILE",
           StringFormat("acquisto di %s (%s, %d° posto) ineseguibile: %s%s", buy[b], uS[idx[ri]], ri + 1, rWhyNo[ri],
                        InpOnUnavailable == UNAV_BLOCCA ? "; passare al successivo richiede una scelta esplicita" : " -> si passa al successivo (UNAV_SALTA)"));
     }
   if(anyUnav && InpOnUnavailable == UNAV_SALTA) DecideCore(ranked, rBuy, heldR, N_TARGET, keep, sell, buy, skipped);
   if(InpOnIndexExit == EXIT_VENDI) for(int i = 0; i < ArraySize(exitHeld); i++) PushS(sell, exitHeld[i]);

   //--- motivi per il registro
   bool first = (ArraySize(g_heldT) == 0);
   for(int i = 0; i < n; i++)
     {
      string t = uni[i];
      if(IndexOf(keep, t) >= 0)         { uAct[i] = "MANTIENI"; uWhy[i] = StringFormat("posseduto, %d° posto <= %d°", uRank[i], KEEP_MAX); }
      else if(IndexOf(sell, t) >= 0)    { uAct[i] = "VENDI";    uWhy[i] = uRank[i] > 0 ? StringFormat("posseduto, %d° posto >= %d°", uRank[i], KEEP_MAX + 1) : "posseduto non classificabile"; }
      else if(IndexOf(buy, t) >= 0)     { uAct[i] = "ACQUISTA"; uWhy[i] = first ? StringFormat("prima selezione, %d° posto", uRank[i]) : StringFormat("posto libero: miglior titolo non posseduto, %d° posto", uRank[i]); }
      else if(IndexOf(skipped, t) >= 0) { uAct[i] = "SALTATO";  uWhy[i] = "non negoziabile (UNAV_SALTA)"; }
      else if(uSt[i] != "OK")           { uAct[i] = "-";        uWhy[i] = "non classificabile: " + uSt[i]; }
      else                              { uAct[i] = "-";        uWhy[i] = "non posseduto, nessun posto da riempire a questa posizione"; }
      if(g_anomBlock && uAct[i] != "-") uAct[i] = "SOSPESO(" + uAct[i] + ")";
     }
   WriteLogRows(sig, lsSig, uni, uS, uSt, uD0, uC0, uF, uD1, uC1, uRet, uRank, uHeld, uAct, uWhy, uDesc);
   for(int i = 0; i < ArraySize(exitHeld); i++)
      PrintFormat("Segnale %s: %s uscito dall'indice -> %s", MonthStr(sig), exitHeld[i], InpOnIndexExit == EXIT_VENDI ? "VENDI" : "DA DECIDERE");
   string top = "";
   for(int i = 0; i < MathMin(10, m); i++) top += StringFormat("%d.%s %.2f%%  ", i + 1, ranked[i], rRet[i]);
   Print("Classifica: ", top);
   ReportAnomalies(sig);
   if(g_anomBlock) { MarkHalted(sig); return 0; }

   CopyS(g_dKeep, keep);
   CopyS(g_dSell, sell);
   CopyS(g_dBuy, buy);
   ArrayResize(g_dBuyS, 0);
   for(int i = 0; i < ArraySize(buy); i++) PushS(g_dBuyS, uS[idx[IndexOf(ranked, buy[i])]]);
   g_dFirst = first;
   g_dEmpty = MathMax(0, N_TARGET - ArraySize(g_heldT));
   g_sigMonth = sig;
   return 1;
  }

//+------------------------------------------------------------------+
//| PIANO: creato all'istante di esecuzione                          |
//+------------------------------------------------------------------+
string MapHeldSym(const string t)
  {
   int k = IndexOf(g_heldT, t);
   return k >= 0 ? g_heldS[k] : MapSymbol(t);
  }
void BuildPlan(int sig, datetime execT)
  {
   ClearPlan();
   g_planMonth = sig; g_planPhase = 1; g_planFreed = 0; g_planExec = execT;
   g_planCap = StrategyCapital(); g_planEmpty = g_dEmpty; g_planFirst = g_dFirst;
   for(int i = 0; i < ArraySize(g_dSell); i++)
      AddPlan(g_dSell[i], MapHeldSym(g_dSell[i]), ACT_SELL, 0, 0, "vendita completa");
   for(int i = 0; i < ArraySize(g_dKeep); i++)
      AddPlan(g_dKeep[i], MapHeldSym(g_dKeep[i]), InpWeights == WGT_RESET_25 ? ACT_ADJUST : ACT_KEEP, -1, -1,
              InpWeights == WGT_RESET_25 ? "mantenuto, riportato al 25%" : "mantenuto, peso libero di oscillare");
   for(int i = 0; i < ArraySize(g_dBuy); i++)
      AddPlan(g_dBuy[i], g_dBuyS[i], ACT_BUY, -1, -1, g_planFirst ? "prima selezione, 25%" : "posto libero");
   PrintFormat("PIANO %s: capitale strategia %.2f %s; esecuzione %s.", MonthStr(sig), g_planCap,
               AccountInfoString(ACCOUNT_CURRENCY), ExecDescription());
   g_planActive = true;
   SavePlan("ACTIVE");
  }
void ComputePhase2Values()
  {
   int nb = 0;
   for(int i = 0; i < ArraySize(g_pT); i++) if(g_pAct[i] == ACT_BUY) nb++;
   double perBuy = g_planCap / N_TARGET;
   if(!g_planFirst && nb > 0)
     {
      if(InpWeights == WGT_OSCILLA_PROCEEDS) perBuy = (g_planFreed + g_planEmpty * g_planCap / N_TARGET) / nb;
      if(InpWeights == WGT_OSCILLA_RESIDUO)
        {
         double kv = 0;
         for(int i = 0; i < ArraySize(g_pT); i++) if(g_pAct[i] == ACT_KEEP) kv += PositionValue(g_pS[i]);
         perBuy = MathMax(0.0, g_planCap - kv) / nb;
        }
     }
   for(int i = 0; i < ArraySize(g_pT); i++)
     {
      if(g_pAct[i] == ACT_BUY)    { g_pVal[i] = perBuy; g_pWhy[i] += StringFormat(", controvalore %.2f", perBuy); }
      if(g_pAct[i] == ACT_ADJUST) { g_pVal[i] = g_planCap / N_TARGET; }
     }
   PrintFormat("PIANO %s fase 2: ricavato vendite %.2f, controvalore per nuovo titolo %.2f.", MonthStr(g_planMonth), g_planFreed, perBuy);
  }

//+------------------------------------------------------------------+
//| ESECUZIONE (idempotente: invia solo le differenze)               |
//+------------------------------------------------------------------+
bool ReduceVolume(const string sym, double vol, double &proceeds)
  {
   double left = vol;
   bool ok = true;
   g_trade.SetTypeFillingBySymbol(sym);
   for(int i = PositionsTotal() - 1; i >= 0 && left > 1e-9; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || PositionGetString(POSITION_SYMBOL) != sym || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
      double pv = PositionGetDouble(POSITION_VOLUME);
      double v = pv;
      bool r;
      if(pv <= left + 1e-9) r = g_trade.PositionClose(t, InpSlippagePoints);
      else
        {
         v = NormVolDown(sym, left);
         if(v <= 0) break;
         r = g_trade.PositionClosePartial(t, v, InpSlippagePoints);
        }
      if(r && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
        {
         left -= v;
         double px = g_trade.ResultPrice() > 0 ? g_trade.ResultPrice() : SymbolInfoDouble(sym, SYMBOL_BID);
         proceeds += v * ValuePerLot(sym, px);
        }
      else
        {
         ok = false;
         PrintFormat("Vendita %s non eseguita: %d %s", sym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
        }
     }
   return ok;
  }
bool IncreaseVolume(const string sym, double vol, const string cmt)
  {
   g_trade.SetTypeFillingBySymbol(sym);
   double v = NormVolDown(sym, vol);
   if(v < SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN) - 1e-9) return true;
   bool ok = g_trade.Buy(v, sym, 0.0, 0.0, 0.0, cmt);
   if(!ok || (g_trade.ResultRetcode() != TRADE_RETCODE_DONE && g_trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      PrintFormat("Acquisto %s non eseguito: %d %s", sym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }
   return true;
  }
bool ItemDone(int i)
  {
   double step = VolStep(g_pS[i]), cur = EAVolume(g_pS[i]);
   if(g_pAct[i] == ACT_KEEP) return true;
   if(g_pAct[i] == ACT_SELL) return cur < step * 0.5;
   if(g_pVol[i] < 0) return false;
   return MathAbs(g_pVol[i] - cur) < step * 0.5;
  }
void ExecutePlan()
  {
   if(!g_tester && TimeCurrent() - g_lastExecTry < InpRetrySeconds) return;
   g_lastExecTry = TimeCurrent();
   if(PendingEAOrders() > 0) { Print("RICONCILIAZIONE: ordini dell'EA ancora in attesa: nessun nuovo invio."); return; }
   string cmt = "ERC " + MonthStr(g_planMonth);
   MqlTick tk;
   //--- fase 1: vendite complete, al primo prezzo negoziabile
   if(g_planPhase == 1)
     {
      for(int i = 0; i < ArraySize(g_pT); i++)
        {
         if(g_pAct[i] != ACT_SELL || ItemDone(i)) continue;
         if(!FreshTick(g_pS[i], g_planExec, tk)) continue;
         g_pTries[i]++;
         ReduceVolume(g_pS[i], EAVolume(g_pS[i]), g_planFreed);
        }
      for(int i = 0; i < ArraySize(g_pT); i++)
         if(g_pAct[i] == ACT_SELL && !ItemDone(i)) { SavePlan("ACTIVE"); CheckTries(); return; }
      ComputePhase2Values();
      g_planPhase = 2;
      SavePlan("ACTIVE");
     }
   //--- fase 2: volumi fissati al primo prezzo negoziabile; prima le riduzioni, poi gli acquisti
   for(int i = 0; i < ArraySize(g_pT); i++)
     {
      if((g_pAct[i] != ACT_BUY && g_pAct[i] != ACT_ADJUST) || g_pVol[i] >= 0) continue;
      if(!FreshTick(g_pS[i], g_planExec, tk)) continue;
      double v = VolumeForValue(g_pS[i], g_pVal[i], tk.ask);
      if(v <= 0)
        {
         ArrayResize(g_anom, 0); g_anomBlock = false;
         Anom(true, "ORDINE_INESEGUIBILE", StringFormat("%s (%s): controvalore %.2f al prezzo %.4f sotto il volume minimo %.4f",
                                                        g_pT[i], g_pS[i], g_pVal[i], tk.ask, SymbolInfoDouble(g_pS[i], SYMBOL_VOLUME_MIN)));
         ReportAnomalies(g_planMonth);
         g_planActive = false;
         SavePlan("ACTIVE");
         MarkHalted(g_planMonth);
         return;
        }
      g_pVol[i] = v;
      g_pWhy[i] += StringFormat(", %.4f lotti, ask %.4f del %s", v, tk.ask, TimeToString(tk.time, TIME_DATE | TIME_SECONDS));
      SavePlan("ACTIVE");
     }
   bool pendingReduce = false;
   for(int i = 0; i < ArraySize(g_pT); i++)
     {
      if(g_pAct[i] != ACT_ADJUST || g_pVol[i] < 0 || ItemDone(i)) continue;
      double diff = g_pVol[i] - EAVolume(g_pS[i]);
      if(diff >= 0) continue;
      if(FreshTick(g_pS[i], g_planExec, tk))
        {
         g_pTries[i]++;
         double dummy = 0;
         ReduceVolume(g_pS[i], -diff, dummy);
        }
      if(!ItemDone(i)) pendingReduce = true;
     }
   if(!pendingReduce)
      for(int i = 0; i < ArraySize(g_pT); i++)
        {
         if((g_pAct[i] != ACT_BUY && g_pAct[i] != ACT_ADJUST) || g_pVol[i] < 0 || ItemDone(i)) continue;
         double diff = g_pVol[i] - EAVolume(g_pS[i]);
         if(diff <= 0 || !FreshTick(g_pS[i], g_planExec, tk)) continue;
         g_pTries[i]++;
         IncreaseVolume(g_pS[i], diff, cmt + (g_pAct[i] == ACT_BUY ? " BUY" : " ADJ"));
        }
   for(int i = 0; i < ArraySize(g_pT); i++)
      if(!ItemDone(i)) { SavePlan("ACTIVE"); CheckTries(); return; }
   //--- completato
   ArrayResize(g_heldT, 0); ArrayResize(g_heldS, 0);
   for(int i = 0; i < ArraySize(g_pT); i++)
      if(g_pAct[i] != ACT_SELL && EAVolume(g_pS[i]) > 0) { PushS(g_heldT, g_pT[i]); PushS(g_heldS, g_pS[i]); }
   for(int i = 0; i < ArraySize(g_pT); i++)
      PrintFormat("ESEGUITO %s: %s %s | %s", MonthStr(g_planMonth),
                  g_pAct[i] == ACT_BUY ? "ACQUISTA" : g_pAct[i] == ACT_SELL ? "VENDI" : g_pAct[i] == ACT_ADJUST ? "RIBILANCIA" : "MANTIENI",
                  g_pT[i], g_pWhy[i]);
   g_lastDone = g_planMonth; g_planActive = false;
   if(g_firstSig < 0) g_firstSig = g_planMonth;
   g_lastSig = g_planMonth;
   if(g_firstHalt >= 0) g_doneAfterHalt++;
   SavePlan("DONE"); SaveState();
   PrintFormat("Ribilanciamento %s completato. Portafoglio: %s", MonthStr(g_planMonth), Join(g_heldT));
  }
void CheckTries()
  {
   for(int i = 0; i < ArraySize(g_pT); i++)
      if(g_pTries[i] >= InpMaxOrderTries)
        {
         ArrayResize(g_anom, 0); g_anomBlock = false;
         Anom(true, "ORDINE_INESEGUIBILE", StringFormat("%s (%s): %d tentativi senza raggiungere il volume previsto (attuale %.4f)",
                                                        g_pT[i], g_pS[i], g_pTries[i], EAVolume(g_pS[i])));
         ReportAnomalies(g_planMonth);
         g_planActive = false;
         SavePlan("ACTIVE");      // al riavvio il piano viene ripreso senza duplicati
         MarkHalted(g_planMonth);
         return;
        }
  }

//+------------------------------------------------------------------+
//| Win rate: un ciclo per titolo dal primo acquisto all'uscita      |
//| completa; le vendite parziali fanno parte dello stesso ciclo.    |
//+------------------------------------------------------------------+
void WinRate(int &wins, int &closed, int &openCycles, double &net, double &comm, double &swp, double &fee, int &deals)
  {
   wins = 0; closed = 0; openCycles = 0; net = 0; comm = 0; swp = 0; fee = 0; deals = 0;
   if(!HistorySelect(0, TimeCurrent() + 86400)) return;
   string sy[];
   double vol[], pnl[];
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      long typ = HistoryDealGetInteger(d, DEAL_TYPE);
      if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL) continue;
      deals++;
      string s = HistoryDealGetString(d, DEAL_SYMBOL);
      int k = IndexOf(sy, s);
      if(k < 0) { PushS(sy, s); PushD(vol, 0); PushD(pnl, 0); k = ArraySize(sy) - 1; }
      double dc = HistoryDealGetDouble(d, DEAL_COMMISSION), dw = HistoryDealGetDouble(d, DEAL_SWAP), df = HistoryDealGetDouble(d, DEAL_FEE);
      comm += dc; swp += dw; fee += df;
      pnl[k] += HistoryDealGetDouble(d, DEAL_PROFIT) + dc + dw + df;
      double v = HistoryDealGetDouble(d, DEAL_VOLUME);
      vol[k] += (typ == DEAL_TYPE_BUY) ? v : -v;
      if(vol[k] <= 1e-8 && HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
        { closed++; if(pnl[k] > 0) wins++; net += pnl[k]; vol[k] = 0; pnl[k] = 0; }
     }
   for(int k = 0; k < ArraySize(sy); k++) if(vol[k] > 1e-8) openCycles++;
  }
double ReportWinRate(const string where)
  {
   int w, c, o, nd;
   double net, comm, swp, fee;
   WinRate(w, c, o, net, comm, swp, fee, nd);
   double wr = c > 0 ? 100.0 * w / c : 0.0;
   string s = StringFormat("[%s] USAS&P_ERCOLE\r\n"
                           "Ribilanciamenti eseguiti: segnali da %s a %s\r\n"
                           "Finestra: chiusura fine t-9 -> chiusura fine t-1 (8 mesi effettivi)\r\n"
                           "Esecuzione: %s\r\n"
                           "Pesi: %s | Capitale: %s\r\n"
                           "Costi registrati nei deal: commissioni %.2f, swap %.2f, fee %.2f (%d deal)\r\n"
                           "Cicli chiusi %d, vincenti %d, win rate %.2f%% (obiettivo >= 70%%: %s)\r\n"
                           "Profitto netto dei cicli chiusi %.2f. Cicli ancora aperti (esclusi dal win rate) %d.\r\n"
                           "Mesi sospesi %d: %s\r\n"
                           "Ribilanciamenti eseguiti dopo il primo mese sospeso (portafoglio dipendente da un mese indeterminato): %d\r\n",
                           where, MonthStr(g_firstSig), MonthStr(g_lastSig), ExecDescription(),
                           InpWeights == WGT_RESET_25 ? "(a) reset 25%" : InpWeights == WGT_OSCILLA_PROCEEDS ? "(b) ricavato ai nuovi" : "(c) residuo ai nuovi",
                           InpCapMode == CAP_FISSO ? StringFormat("fisso %.2f", InpCapFixed) : StringFormat("%.1f%% equity", InpCapPct),
                           comm, swp, fee, nd, c, w, wr, (c > 0 && wr >= 70.0) ? "RAGGIUNTO" : "NON raggiunto", net, o,
                           g_haltCount, g_haltList, g_doneAfterHalt);
   Print(s);
   int h = FileOpen(WinPath(), FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(h != INVALID_HANDLE) { FileWriteString(h, s); FileClose(h); }
   return wr;
  }

//+------------------------------------------------------------------+
//| RAPPORTO DI COPERTURA (prezzi broker + composizione storica)     |
//+------------------------------------------------------------------+
bool CalLast(int mid, datetime &d)
  {
   int k = BSearchInt(g_calM, 0, ArraySize(g_calM), mid);
   if(k < 0) return false;
   d = g_calD[k];
   return true;
  }
int CovSigFrom() { return MonthId(InpCovFrom); }
int CovSigTo()
  {
   int last = MonthId(TimeCurrent()) - 1;
   return (InpCovTo > 0) ? MathMin(MonthId(InpCovTo), last) : last;
  }
bool CovPrepare()
  {
   g_covFromT = MonthStart(CovSigFrom() - WIN_START - 1);
   g_covToT   = TimeCurrent();
   MqlRates r[];
   int n = CopyRates(g_cal, PERIOD_D1, g_covFromT, g_covToT, r);
   if(n <= 0) { Print("Copertura: storico D1 del simbolo calendario non disponibile, riprovo."); return false; }
   ArrayResize(g_calM, 0); ArrayResize(g_calD, 0);
   for(int i = 0; i < n; i++)
     {
      int mid = MonthId(r[i].time), last = ArraySize(g_calM) - 1;
      if(last >= 0 && g_calM[last] == mid) g_calD[last] = DayStart(r[i].time);
      else { PushI(g_calM, mid); PushT(g_calD, DayStart(r[i].time)); }
     }
   ArrayResize(g_cT, 0);
   datetime lim = MonthStart(CovSigTo() + 1);
   for(int i = 0; i < ArraySize(g_uDate); i++)
     {
      if(g_uDate[i] > lim) continue;
      string p[];
      int k = StringSplit(g_uLine[i], ',', p);
      for(int j = 0; j < k; j++)
        {
         string t = Trim(p[j]);
         StringToUpper(t);
         if(StringLen(t) > 0) InsertSorted(g_cT, t);
        }
     }
   int m = ArraySize(g_cT);
   ArrayResize(g_cS, m); ArrayResize(g_cState, m); ArrayResize(g_cOff, m); ArrayResize(g_cCnt, m);
   ArrayResize(g_cGOff, m); ArrayResize(g_cGCnt, m);
   for(int i = 0; i < m; i++) { g_cS[i] = MapSymbol(g_cT[i]); g_cState[i] = 0; g_cOff[i] = 0; g_cCnt[i] = 0; g_cGOff[i] = 0; g_cGCnt[i] = 0; }
   ArrayResize(g_mcM, 0); ArrayResize(g_mcC, 0); ArrayResize(g_mcD, 0); ArrayResize(g_gpD, 0); ArrayResize(g_gpR, 0);
   g_covStart = TimeLocal();
   PrintFormat("Copertura: %d ticker distinti nelle composizioni, segnali da %s a %s. Caricamento storici D1...",
               m, MonthStr(CovSigFrom()), MonthStr(CovSigTo()));
   g_covPrepared = true;
   return true;
  }
// stato: 0 da caricare, 1 ok, 2 simbolo assente, 3 non sincronizzato
void CovLoadTicker(int i)
  {
   string sym = g_cS[i];
   if(!SymbolOk(sym)) { g_cState[i] = 2; return; }
   if(!g_tester && !(bool)SeriesInfoInteger(sym, PERIOD_D1, SERIES_SYNCHRONIZED))
     {
      MqlRates tmp[];
      CopyRates(sym, PERIOD_D1, g_covFromT, g_covToT, tmp); // avvia lo scaricamento
      g_cState[i] = 3;
      return;
     }
   MqlRates r[];
   int n = CopyRates(sym, PERIOD_D1, g_covFromT, g_covToT, r);
   if(n < 0) { g_cState[i] = 3; return; }
   g_cOff[i] = ArraySize(g_mcM);
   g_cGOff[i] = ArraySize(g_gpD);
   for(int k = 0; k < n; k++)
     {
      int mid = MonthId(r[k].time), last = ArraySize(g_mcM) - 1;
      if(last >= g_cOff[i] && g_mcM[last] == mid) { g_mcC[last] = r[k].close; g_mcD[last] = DayStart(r[k].time); }
      else { PushI(g_mcM, mid); PushD(g_mcC, r[k].close); PushT(g_mcD, DayStart(r[k].time)); }
      if(k > 0 && r[k - 1].close > 0 && IsSplitLike(r[k].open / r[k - 1].close))
        { PushT(g_gpD, DayStart(r[k].time)); PushD(g_gpR, r[k].open / r[k - 1].close); }
     }
   g_cCnt[i] = ArraySize(g_mcM) - g_cOff[i];
   g_cGCnt[i] = ArraySize(g_gpD) - g_cGOff[i];
   g_cState[i] = 1;
  }
// true quando il caricamento è terminato
bool CovLoadStep(int maxPerCall)
  {
   int done = 0, pending = 0;
   bool timeout = (TimeLocal() - g_covStart) > InpDataWaitMinutes * 60;
   for(int i = 0; i < ArraySize(g_cT); i++)
     {
      if(g_cState[i] == 1 || g_cState[i] == 2) continue;
      if(g_cState[i] == 3 && (timeout || g_tester)) continue;
      if(done >= maxPerCall) { pending++; continue; }
      CovLoadTicker(i);
      done++;
      if(g_cState[i] == 3 && !g_tester) pending++;
     }
   if(!g_tester && done > 0) PrintFormat("Copertura: caricati/tentati %d ticker, in attesa %d.", done, pending);
   return pending == 0;
  }
// 1 ok, 0 assente, 2 non aggiornata, 3 storico non disponibile
int CovClose(int ti, int mid, datetime ref, double &c, datetime &d)
  {
   c = 0; d = 0;
   if(g_cState[ti] != 1) return 3;
   int k = BSearchInt(g_mcM, g_cOff[ti], g_cCnt[ti], mid);
   if(k < 0) return 0;
   c = g_mcC[k]; d = g_mcD[k];
   if(c <= 0) return 0;
   return d < ref ? 2 : 1;
  }
bool HasTok(const string csv, const string t) { return StringFind(csv, "," + t + ",") >= 0; }

void CovEvalMonths(int hDet)
  {
   int s0 = CovSigFrom(), s1 = CovSigTo(), nm = MathMax(0, s1 - s0 + 1);
   ArrayResize(g_mValid, nm); ArrayResize(g_mReason, nm); ArrayResize(g_mTop, nm); ArrayResize(g_mTopRet, nm);
   ArrayResize(g_mMiss, nm); ArrayResize(g_mUni, nm); ArrayResize(g_mN, nm); ArrayResize(g_mOk, nm); ArrayResize(g_mLs, nm);
   for(int k = 0; k < nm; k++)
     {
      int sig = s0 + k, finM = sig - WIN_END, iniM = sig - WIN_START;
      g_mValid[k] = false; g_mReason[k] = ""; g_mTop[k] = ""; g_mTopRet[k] = ""; g_mMiss[k] = ","; g_mUni[k] = ",";
      g_mN[k] = 0; g_mOk[k] = 0; g_mLs[k] = 0;
      datetime lsSig = 0, lsFin = 0, lsIni = 0;
      if(!CalLast(sig, lsSig) || !CalLast(finM, lsFin) || !CalLast(iniM, lsIni))
        { g_mReason[k] = "calendario: sedute mancanti nello storico del simbolo " + g_cal; continue; }
      g_mLs[k] = lsSig;
      string uni[];
      datetime snap = 0;
      if(!Constituents(lsSig, uni, snap, false)) { g_mReason[k] = "composizione S&P 500 non disponibile in questa data"; continue; }
      int n = ArraySize(uni);
      g_mN[k] = n;
      string topT[];
      double topR[];
      for(int i = 0; i < n; i++)
        {
         g_mUni[k] += uni[i] + ",";
         int ti = BSearchStr(g_cT, uni[i]);
         string prob = "";
         double c0 = 0, c1 = 0;
         datetime d0 = 0, d1 = 0;
         if(ti < 0) prob = "ticker non caricato";
         else if(g_cState[ti] == 2) prob = StringFormat("simbolo broker '%s' assente: mancano chiusura iniziale (fine %s) e finale (fine %s)", g_cS[ti], MonthStr(iniM), MonthStr(finM));
         else if(g_cState[ti] != 1) prob = StringFormat("storico di '%s' non disponibile o non sincronizzato", g_cS[ti]);
         else
           {
            int a = CovClose(ti, iniM, lsIni, c0, d0), b = CovClose(ti, finM, lsFin, c1, d1);
            if(a != 1 || b != 1)
               prob = JoinProblems(CloseProblem(a, "iniziale", iniM, lsIni, d0), CloseProblem(b, "finale", finM, lsFin, d1));
            else
              {
               datetime gD[];
               double gR[];
               for(int g = g_cGOff[ti]; g < g_cGOff[ti] + g_cGCnt[ti]; g++) { PushT(gD, g_gpD[g]); PushD(gR, g_gpR[g]); }
               double f = 1.0;
               string susp = "", note = "";
               if(!SplitAdjust(uni[i], d0, d1, gD, gR, f, susp, note)) prob = "split da verificare: " + susp;
               else
                 {
                  double ret = 100.0 * (c1 / (c0 / f) - 1.0);
                  g_mOk[k]++;
                  //--- primi COV_TOP (rendimento decrescente; ticker solo per stabilità di stampa)
                  int sz = ArraySize(topT), pos = sz;
                  while(pos > 0 && (topR[pos - 1] < ret - EPS_RET || (MathAbs(topR[pos - 1] - ret) < EPS_RET && StringCompare(topT[pos - 1], uni[i]) > 0))) pos--;
                  if(pos < COV_TOP)
                    {
                     ArrayResize(topT, sz + 1); ArrayResize(topR, sz + 1);
                     for(int q = sz; q > pos; q--) { topT[q] = topT[q - 1]; topR[q] = topR[q - 1]; }
                     topT[pos] = uni[i]; topR[pos] = ret;
                     if(ArraySize(topT) > COV_TOP) { ArrayResize(topT, COV_TOP); ArrayResize(topR, COV_TOP); }
                    }
                 }
              }
           }
         if(StringLen(prob) > 0)
           {
            g_mMiss[k] += uni[i] + ",";
            StringReplace(prob, ";", ",");
            if(hDet != INVALID_HANDLE)
               FileWriteString(hDet, StringFormat("%s;%s;%s;%s\r\n", MonthStr(sig), uni[i], ti >= 0 ? g_cS[ti] : MapSymbol(uni[i]), prob));
           }
        }
      g_mTop[k] = Join(topT);
      string rs = "";
      for(int q = 0; q < ArraySize(topR); q++) rs += (q ? "," : "") + DoubleToString(topR[q], 10);
      g_mTopRet[k] = rs;
      g_mValid[k] = true;
     }
  }
// un passo della simulazione (solo classifica, senza importi); true se determinato
bool CovSimStep(int k, string &held[], string &reason)
  {
   reason = "";
   if(!g_mValid[k]) { reason = g_mReason[k]; ArrayResize(held, 0); return false; }
   string top[], rsS[];
   SplitCsv(g_mTop[k], top);
   int nr = SplitCsv(g_mTopRet[k], rsS);
   double rr[];
   ArrayResize(rr, nr);
   for(int i = 0; i < nr; i++) rr[i] = StringToDouble(rsS[i]);
   bool all[];
   ArrayResize(all, ArraySize(top));
   for(int i = 0; i < ArraySize(top); i++) all[i] = true;
   bool det = true;
   string heldR[], forced[];
   for(int i = 0; i < ArraySize(held); i++)
     {
      if(!HasTok(g_mUni[k], held[i])) { det = false; reason += held[i] + " posseduto uscito dall'indice (regola mancante); "; continue; }
      if(HasTok(g_mMiss[k], held[i])) { det = false; reason += held[i] + " posseduto non classificabile; "; PushS(forced, held[i]); continue; }
      PushS(heldR, held[i]);
     }
   string keep[], sell[], buy[], sk[];
   DecideCore(top, all, heldR, N_TARGET - ArraySize(forced), keep, sell, buy, sk);
   string why = "";
   if(!Determinate(top, keep, buy, g_mN[k] - g_mOk[k] - ArraySize(forced), why)) { det = false; reason += why; }
   string td = "";
   if(TieAffects(rr, top, all, heldR, buy, td)) { det = false; reason += td + "; "; }
   ArrayResize(held, 0);
   for(int i = 0; i < ArraySize(keep); i++)   PushS(held, keep[i]);
   for(int i = 0; i < ArraySize(forced); i++) PushS(held, forced[i]);
   for(int i = 0; i < ArraySize(buy); i++)    PushS(held, buy[i]);
   return det;
  }
int CountState(int st)
  {
   int c = 0;
   for(int i = 0; i < ArraySize(g_cState); i++) if(g_cState[i] == st) c++;
   return c;
  }
void CovCompute()
  {
   int s0 = CovSigFrom(), s1 = CovSigTo(), nm = MathMax(0, s1 - s0 + 1);
   string pM = FileBase() + "_copertura_mesi.csv", pD = FileBase() + "_copertura_mancanti.csv", pS = FileBase() + "_copertura_sintesi.txt";
   int hD = FileOpen(pD, FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(hD != INVALID_HANDLE) FileWriteString(hD, "MeseSegnale;Ticker;Simbolo;PrezzoMancanteOProblema\r\n");
   CovEvalMonths(hD);
   if(hD != INVALID_HANDLE) FileClose(hD);
   //--- percorso simulato dal primo mese valido
   int hM = FileOpen(pM, FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(hM != INVALID_HANDLE)
      FileWriteString(hM, "MeseSegnale;UltimaSeduta;Componenti;Classificabili;NonClassificabili;Copertura;EsitoPercorso;Motivo;PortafoglioSimulato\r\n");
   string held[];
   bool started = false, contaminated = false;
   int firstIndet = -1;
   for(int k = 0; k < nm; k++)
     {
      string esito = "NON_VALIDO", reason = "";
      if(started || g_mValid[k])
        {
         started = true;
         bool det = CovSimStep(k, held, reason);
         if(!det && firstIndet < 0) firstIndet = k;
         if(!det) esito = contaminated ? "INDETERMINATO+DIPENDENTE" : "INDETERMINATO";
         else     esito = contaminated ? "DIPENDENTE" : "DETERMINATO";
         if(!det) contaminated = true;
        }
      if(!g_mValid[k] && reason == "") reason = g_mReason[k];
      StringReplace(reason, ";", ",");
      string cov = (g_mValid[k] && g_mOk[k] == g_mN[k]) ? "COMPLETA" : (g_mValid[k] ? "INCOMPLETA" : "-");
      if(hM != INVALID_HANDLE)
         FileWriteString(hM, StringFormat("%s;%s;%d;%d;%d;%s;%s;%s;%s\r\n", MonthStr(s0 + k), D2S(g_mLs[k]), g_mN[k], g_mOk[k],
                                          g_mN[k] - g_mOk[k], cov, esito, reason, Join(held)));
     }
   if(hM != INVALID_HANDLE) FileClose(hM);
   //--- per ogni mese di partenza: quanti mesi consecutivi restano determinati
   int bestS = -1, bestLen = 0;
   for(int s = 0; s < nm; s++)
     {
      if(!g_mValid[s]) continue;
      string h[];
      string r = "";
      int len = 0;
      for(int k = s; k < nm; k++) { if(!CovSimStep(k, h, r)) break; len++; }
      if(len > bestLen) { bestLen = len; bestS = s; }
     }
   //--- intervalli di copertura completa
   string ranges = "";
   int runStart = -1, nComplete = 0, nValid = 0;
   for(int k = 0; k <= nm; k++)
     {
      bool comp = (k < nm && g_mValid[k] && g_mOk[k] == g_mN[k]);
      if(k < nm && g_mValid[k]) nValid++;
      if(comp) { nComplete++; if(runStart < 0) runStart = k; }
      else if(runStart >= 0) { ranges += MonthStr(s0 + runStart) + (k - 1 > runStart ? ".." + MonthStr(s0 + k - 1) : "") + " "; runStart = -1; }
     }
   string s = StringFormat("RAPPORTO DI COPERTURA USAS&P_ERCOLE (finestra 9-1: chiusura fine t-9 -> chiusura fine t-1)\r\n"
                           "Composizione nel file: dal %s al %s (considerata valida fino a +%d giorni)\r\n"
                           "Calendario (%s): storico D1 dal %s\r\n"
                           "Mesi di segnale analizzati: %s .. %s (%d), con composizione e calendario: %d\r\n"
                           "Mesi con copertura prezzi COMPLETA: %d -> %s\r\n"
                           "Primo mese indeterminato partendo dal primo mese valido: %s\r\n"
                           "Periodo più lungo senza mesi indeterminati (partenza a portafoglio vuoto): %s .. %s (%d mesi di segnale)\r\n"
                           "Ticker con storico: %d; simboli assenti: %d; storico non disponibile: %d\r\n"
                           "Dettagli: %s (esito per mese) e %s (titolo e prezzo mancante)\r\n"
                           "Nota: la negoziabilità storica non è verificabile qui; un salto da split non verificato rende il titolo non classificabile.\r\n",
                           D2S(g_uFirst), D2S(g_uLast), InpUniverseMaxAge, g_cal, ArraySize(g_calD) > 0 ? D2S(g_calD[0]) : "-",
                           MonthStr(s0), MonthStr(s1), nm, nValid, nComplete, ranges == "" ? "nessuno" : ranges,
                           firstIndet >= 0 ? MonthStr(s0 + firstIndet) : "nessuno",
                           bestS >= 0 ? MonthStr(s0 + bestS) : "-", bestS >= 0 ? MonthStr(s0 + bestS + bestLen - 1) : "-", bestLen,
                           CountState(1), CountState(2), CountState(3), pM, pD);
   Print(s);
   int hS = FileOpen(pS, FILE_WRITE | FILE_TXT | FILE_ANSI | FFlags());
   if(hS != INVALID_HANDLE) { FileWriteString(hS, s); FileClose(hS); }
   g_covDone = true;
  }
void CoverageTick()
  {
   if(g_covDone) return;
   if(!g_covPrepared && !CovPrepare()) return;
   if(CovLoadStep(g_tester ? 100000 : 60)) CovCompute();
  }

//+------------------------------------------------------------------+
//| Ciclo principale                                                 |
//+------------------------------------------------------------------+
void Process()
  {
   if(InpRunMode == MODE_COPERTURA) { if(!g_tester) CoverageTick(); return; }
   if(g_planActive) { ExecutePlan(); return; }
   datetime now = TimeCurrent();
   int sig = MonthId(now) - 1;            // mese appena concluso
   if(g_lastDone >= sig || g_haltedRun == sig) return;
   int targetDay = (InpExec == EXE_PERSONALIZZATA) ? MathMax(1, InpCustomTradingDay) : 1;
   datetime lastDay = 0;
   int n = SessionsSoFar(now, lastDay);
   bool todayIsSession = (n > 0 && lastDay == DayStart(now));
   bool late = (n > targetDay) || (n == targetDay && !todayIsSession);
   if(late && !InpAllowLateStart && g_haltedPersist != sig)
     {
      if(g_lateNotified != sig)
        {
         PrintFormat("Momento di esecuzione del segnale %s già passato: attendo la prossima fine mese.", MonthStr(sig));
         g_lateNotified = sig;
        }
      return;
     }
   //--- segnale: appena dopo la chiusura dell'ultima seduta del mese
   if(g_sigMonth != sig)
     {
      if(BuildSignal(sig) != 1) return;
     }
   //--- ordini: momento di esecuzione
   if(!todayIsSession) return;
   if(!late && n != targetDay) return;
   datetime et = ExecTime(DayStart(now));
   if(now < et) return;
   ReconcileHeld(false);
   if(HeldKey() != g_sigHeldKey)
     {
      Print("RICONCILIAZIONE: posizioni cambiate tra segnale ed esecuzione: ricalcolo il segnale.");
      g_sigMonth = -1;
      if(BuildSignal(sig) != 1) return;
     }
   BuildPlan(sig, et);
   ExecutePlan();
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_tester = (bool)MQLInfoInteger(MQL_TESTER);
   if(InpRunSelfTest && !SelfTest()) return INIT_FAILED;
   g_cal = (StringLen(InpCalendarSymbol) > 0) ? InpCalendarSymbol : _Symbol;
   if(!SymbolOk(g_cal)) { Print("Simbolo calendario non trovato: ", g_cal); return INIT_PARAMETERS_INCORRECT; }
   if(!LoadUniverse()) return INIT_FAILED;
   LoadMap();
   LoadSplits();
   if(InpRunMode == MODE_COPERTURA)
     {
      Print("Modalità COPERTURA: nessun ordine verrà inviato.");
      if(!g_tester) EventSetTimer(5);
      return INIT_SUCCEEDED;
     }
   if(InpWeights == WGT_DA_CONFERMARE || InpCapMode == CAP_DA_CONFERMARE)
     {
      Print("DA SCEGLIERE prima di operare: InpWeights = (a) reset 25%, (b) ricavato vendite ai nuovi, (c) residuo ai nuovi; "
            "InpCapMode = percentuale dell'equity o importo fisso.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpExec == EXE_DA_CONFERMARE)
     {
      if(!g_tester)
        {
         Print("DA CONFERMARE: momento degli ordini (InpExec). Fuori dal tester l'EA non opera finché non è impostato.");
         return INIT_PARAMETERS_INCORRECT;
        }
      g_execHypothesis = true;
      Print("Tester: orario ordini non confermato -> IPOTESI prima apertura ordinaria USA (09:30 New York), dichiarata nel report.");
     }
   if(InpExec == EXE_PERSONALIZZATA && ParseHM(InpCustomServerTime) < 0) { Print("Ora personalizzata non valida."); return INIT_PARAMETERS_INCORRECT; }
   if(StringLen(InpUSOpenOverride) > 0 && ParseHM(InpUSOpenOverride) < 0) { Print("Ora apertura USA non valida."); return INIT_PARAMETERS_INCORRECT; }
   if(g_tester)
     {
      FileDelete(StatePath(), FFlags()); FileDelete(PlanPath(), FFlags());
      FileDelete(LogPath(), FFlags());   FileDelete(AnomPath(), FFlags());
     }
   LoadState();
   LoadPlan();
   ReconcileHeld(true);
   if(PendingEAOrders() > 0) PrintFormat("RICONCILIAZIONE: %d ordini pendenti dell'EA presenti: nessun invio finché restano.", PendingEAOrders());
   string uni[];
   datetime snap = 0;
   if(Constituents(TimeCurrent(), uni, snap))
     {
      int ok = 0;
      string miss = "";
      for(int i = 0; i < ArraySize(uni); i++) { if(SymbolOk(MapSymbol(uni[i]))) ok++; else miss += uni[i] + " "; }
      PrintFormat("Copertura simboli composizione del %s: %d/%d associati al broker.%s", D2S(snap), ok, ArraySize(uni),
                  ok < ArraySize(uni) ? " Mancanti: " + miss : "");
     }
   else
      PrintFormat("ATTENZIONE: il file di composizione termina il %s: per i segnali oltre %d giorni va aggiornato.", D2S(g_uLast), InpUniverseMaxAge);
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetAsyncMode(false);
   Print("Esecuzione: ", ExecDescription());
   EventSetTimer(MathMax(5, InpRetrySeconds));
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpRunMode == MODE_TRADING) ReportWinRate("OnDeinit");
  }
void OnTick()  { Process(); }
void OnTimer() { Process(); }
double OnTester()
  {
   if(InpRunMode == MODE_COPERTURA)
     {
      // nel tester il rapporto si calcola a fine test, con lo storico fino alla data finale
      if(CovPrepare()) { while(!CovLoadStep(100000)) {} CovCompute(); }
      return 0.0;
     }
   return ReportWinRate("Strategy Tester");
  }
//+------------------------------------------------------------------+
