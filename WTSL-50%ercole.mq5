//+------------------------------------------------------------------+
//|                                               WTSL-50%ercole.mq5 |
//|     Copia condizionata dei trade WT67 (conto 100k) sul conto 50k |
//+------------------------------------------------------------------+
//
// FUNZIONAMENTO IN BREVE
// Lo stesso file va caricato su DUE terminali MT5 dello stesso utente
// Windows, sullo stesso PC o VPS. Il ruolo dipende dal login del conto:
//
//  - terminale del conto 100k (login = InpConto100k): ruolo SORGENTE.
//    Non invia MAI ordini. Legge dal broker la posizione aperta dal WT67
//    (magic InpMagicWT67, simbolo InpSimbolo100k) e pubblica ogni 100 ms
//    nella cartella FILE_COMMON: direzione, prezzo di esecuzione, SL, TP,
//    identificativo, Bid/Ask correnti, POSITION_PROFIT e le chiusure recenti
//    con il motivo letto dallo storico (SL, TP, EA, manuale...).
//
//  - terminale del conto 50k (login = InpConto50k): ruolo RICEVITORE.
//    Apre al massimo una copia da 0,50 lotti per ogni trade sorgente quando,
//    nello stesso istante: il trade WT67 e' aperto, il 100k e' almeno 5,00
//    di prezzo in perdita, POSITION_PROFIT <= -500, e con il prezzo reale
//    del 50k OrderCalcProfit restituisce esattamente -250 allo stop e +750
//    al target (precisione al centesimo). SL e TP sono gli stessi prezzi
//    assoluti del 100k. Finestra 15:30 inclusa - 17:30 esclusa Europe/Rome,
//    massimo 4 aperture per giorno italiano, una posizione alla volta.
//
// Il WT67 originale (WaveTrend LazyBear 10/21/4 su M15 chiuse, 1,00 lotto,
// SL/TP a 10,00) continua a girare per conto suo sul terminale 100k. Questo
// EA ricalcola il WaveTrend solo per riconoscere le chiusure del 100k dovute
// all'incrocio opposto, che fanno chiudere anche la copia sul 50k.
//
// Il file e' scritto in ASCII puro: niente caratteri accentati.
//+------------------------------------------------------------------+
#property copyright   "ercole"
#property version     "1.00"
#property description "WTSL-50%ercole: copia i trade WT67 del conto 100k sul conto 50k (0,50 lotti, -250/+750 lordi)."
#property description "Caricare lo stesso EA su entrambi i terminali: il ruolo dipende dal login (InpConto100k / InpConto50k)."

//--- parametri
input group "Conti (login MT5)"
input long   InpConto100k            = 0;          // Login del conto 100k (sorgente WT67)
input long   InpConto50k             = 0;          // Login del conto 50k (ricevitore)

input group "Simboli e magic number"
input string InpSimbolo100k          = "XAUUSD";   // Simbolo del WT67 sul 100k
input string InpSimbolo50k           = "XAUUSD";   // Simbolo delle copie sul 50k
input long   InpMagicWT67            = 670067;     // Magic number del WT67 (100k)
input long   InpMagicRicevitore      = 670050;     // Magic number delle copie (50k)

input group "Collegamento tra i terminali (FILE_COMMON)"
input string InpCartellaComune       = "WTSL50ercole"; // Sottocartella di Common\Files
input int    InpTimerMs              = 100;        // Ciclo del timer (ms)
input int    InpMaxEtaDatiMs         = 2000;       // Eta' massima dei dati 100k per aprire (ms)
input int    InpMaxEtaQuotazioneSec  = 30;         // Eta' massima dell'ultima quotazione 100k (s)

input group "Esecuzione sul 50k"
input int    InpDeviazionePunti      = 0;          // Deviazione massima (punti, solo esecuzione instant/request)
input int    InpMaxTentativi         = 3;          // Tentativi dopo rifiuti certi del broker
input int    InpPausaTentativiSec    = 5;          // Pausa minima tra due tentativi (s)
input bool   InpChiudiSuAltreChiusure = false;     // Chiudi la copia anche se il 100k chiude a mano/per altro motivo

input group "Diagnostica"
input bool   InpAutoTest             = false;      // Esegue solo l'autotest e non opera
input bool   InpLogDettagliato       = false;      // Registra ogni variazione dello stato di attesa

//--- regole fisse della strategia (non modificabili da input)
#define WTSL_VERSIONE_CANALE         1
#define WTSL_SOGLIA_MOVIMENTO        5.00     // unita' di prezzo XAUUSD (3000 -> 2995)
#define WTSL_SOGLIA_PERDITA_100K     500.00   // valuta del conto 100k (0,5% di 100.000)
#define WTSL_LOTTI_50K               0.50
#define WTSL_RISCHIO_50K             250.00   // -0,5% di 50.000
#define WTSL_TARGET_50K              750.00   // +1,5% di 50.000
#define WTSL_SESSIONE_INIZIO_SEC     55800    // 15:30:00 Europe/Rome (inclusa)
#define WTSL_SESSIONE_FINE_SEC       63000    // 17:30:00 Europe/Rome (esclusa)
#define WTSL_MAX_APERTURE_GIORNO     4
#define WTSL_WT_CANALE               10       // WaveTrend LazyBear: channel length
#define WTSL_WT_MEDIA                21       // WaveTrend LazyBear: average length
#define WTSL_WT_SEGNALE              4        // WaveTrend LazyBear: SMA di wt1
#define WTSL_WT_BARRE                400
#define WTSL_FINESTRA_INVERSIONE_SEC 120
#define WTSL_MAX_CHIUSURE            16
#define WTSL_MAX_APERTURE_STORICO    64
#define WTSL_MAX_CACHE_WT            32
#define WTSL_MAX_REGISTRO            256
#define WTSL_PREFISSO_COMMENTO       "WTSL50|"
#define WTSL_FILE_INTESTAZIONE       "WTSL50 1"
#define WTSL_REG_INTESTAZIONE        "WTSL50REG 1"

//--- stati del registro copie (persistente su disco)
#define REG_INVIO       1   // richiesta in preparazione/inviata, esito non ancora noto
#define REG_APERTA      2   // copia aperta confermata dal broker
#define REG_INCERTA     3   // esito non certo (timeout, connessione): mai reinviare
#define REG_RIFIUTATA   4   // rifiuto certo del broker: nessuna posizione aperta
#define REG_CHIUSA      5   // copia aperta e poi chiusa

//--- motivo di chiusura del trade sorgente
#define MOT_SCONOSCIUTO 0
#define MOT_SL          1
#define MOT_TP          2
#define MOT_EXPERT      3
#define MOT_MANUALE     4
#define MOT_STOPOUT     5
#define MOT_ALTRO       6

enum ENUM_WTSL_RUOLO
  {
   RUOLO_NESSUNO        = 0,
   RUOLO_SORGENTE_100K  = 1,
   RUOLO_RICEVITORE_50K = 2
  };

struct ChiusuraSorgente
  {
   long              pos_id;
   int               tipo;          // 0 = BUY, 1 = SELL (posizione chiusa)
   int               motivo;        // MOT_*
   int               opposto;       // 1 = chiusa per incrocio WaveTrend opposto
   long              chiusura_utc;
  };

struct SnapshotSorgente
  {
   int               valido;
   long              seq;
   long              tick_ms;       // GetTickCount64() del PC al momento della scrittura
   long              gmt;           // TimeGMT() al momento della scrittura
   long              login;
   int               connesso;
   int               digits;
   double            point;
   long              quota_eta_sec;
   double            bid;
   double            ask;
   int               n_posizioni;
   int               pos_aperta;
   long              pos_id;
   long              pos_ticket;
   int               pos_tipo;
   double            pos_volume;
   double            pos_prezzo;
   double            pos_sl;
   double            pos_tp;
   double            pos_profitto;
   long              pos_apertura_utc;
   int               n_chiusure;
   ChiusuraSorgente  chiusure[WTSL_MAX_CHIUSURE];
  };

struct VoceRegistro
  {
   long              pos_id;        // POSITION_IDENTIFIER del trade sorgente 100k
   int               tipo;          // 0 = BUY, 1 = SELL
   int               stato;         // REG_*
   long              utc;           // ultimo aggiornamento
   long              data_roma;     // aaaammgg del giorno italiano dell'apertura
   int               tentativi;
   long              ticket50;      // POSITION_IDENTIFIER della copia sul 50k
   int               retcode;
  };

struct PianoOrdine
  {
   long              pos_id;
   int               tipo;
   double            prezzo;
   double            sl;
   double            tp;
   double            profitto_sl;
   double            profitto_tp;
  };

struct CacheWT
  {
   long              pos_id;
   int               tipo;
   int               direzione;     // +1 incrocio rialzista, -1 ribassista, 0 nessuno
  };

//--- stato globale
ENUM_WTSL_RUOLO  g_ruolo = RUOLO_NESSUNO;
bool             g_soloTest = false;
string           g_fileCanale = "";
string           g_fileRegistro = "";
string           g_fileEventi = "";
string           g_ultimoGrafico = "";
string           g_ultimoCodiceStato = "";
string           g_ultimoMessaggioStato = "";
long             g_ultimoLogStatoMs = 0;
bool             g_statoDaRegistrare = false;

//--- ruolo sorgente
long             g_seq = 0;
ChiusuraSorgente g_chiusure[WTSL_MAX_CHIUSURE];
int              g_nChiusure = 0;
long             g_apId[WTSL_MAX_APERTURE_STORICO];
int              g_apTipo[WTSL_MAX_APERTURE_STORICO];
long             g_apTempo[WTSL_MAX_APERTURE_STORICO];
int              g_nAp = 0;
CacheWT          g_cacheWT[WTSL_MAX_CACHE_WT];
int              g_nCacheWT = 0;
long             g_firmaPosizioni = -1;
long             g_ultimaRicostruzioneMs = 0;
int              g_erroriScrittura = 0;
MqlRates         g_rates[WTSL_WT_BARRE];
double           g_wt1[WTSL_WT_BARRE];
double           g_wt2[WTSL_WT_BARRE];

//--- ruolo ricevitore
SnapshotSorgente g_snap;
bool             g_haSnap = false;
VoceRegistro     g_registro[WTSL_MAX_REGISTRO];
int              g_nRegistro = 0;
bool             g_fokDisponibile = false;
bool             g_contoHedging = false;
long             g_attesaId = 0;
int              g_attesaTipo = -1;
long             g_ultimaScansioneMs = 0;
long             g_ultimoTentativoChiusuraMs = 0;
long             g_copiaSenzaChiaveLog = 0;

//+------------------------------------------------------------------+
//| Utilita' generali                                                |
//+------------------------------------------------------------------+
long OraMs()
  {
   return (long)GetTickCount64();
  }

long Centesimi(const double valore)
  {
   return (long)MathRound(valore * 100.0);
  }

string TipoTesto(const int tipo)
  {
   if(tipo == 0)
      return "BUY";
   return "SELL";
  }

string Soldi(const double valore)
  {
   return DoubleToString(valore, 2);
  }

string MotivoTesto(const int motivo)
  {
   if(motivo == MOT_SL)
      return "stop loss";
   if(motivo == MOT_TP)
      return "take profit";
   if(motivo == MOT_EXPERT)
      return "chiusura da EA";
   if(motivo == MOT_MANUALE)
      return "chiusura manuale";
   if(motivo == MOT_STOPOUT)
      return "stop out";
   if(motivo == MOT_ALTRO)
      return "altro";
   return "sconosciuto";
  }

string StatoRegistroTesto(const int stato)
  {
   if(stato == REG_INVIO)
      return "INVIO";
   if(stato == REG_APERTA)
      return "APERTA";
   if(stato == REG_INCERTA)
      return "INCERTA";
   if(stato == REG_RIFIUTATA)
      return "RIFIUTATA";
   if(stato == REG_CHIUSA)
      return "CHIUSA";
   return "?";
  }

// Campo numero "indice" (da 0) di un testo separato da "sep".
string Campo(const string testo, const int indice, const string sep)
  {
   int inizio = 0;
   for(int i = 0; i < indice; i++)
     {
      int p = StringFind(testo, sep, inizio);
      if(p < 0)
         return "";
      inizio = p + StringLen(sep);
     }
   int fine = StringFind(testo, sep, inizio);
   if(fine < 0)
      return StringSubstr(testo, inizio);
   return StringSubstr(testo, inizio, fine - inizio);
  }

bool DividiChiaveValore(const string riga, string &chiave, string &valore)
  {
   int p = StringFind(riga, "=");
   if(p <= 0)
      return false;
   chiave = StringSubstr(riga, 0, p);
   valore = StringSubstr(riga, p + 1);
   return true;
  }

string Pulisci(const string testo)
  {
   string t = testo;
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
  }

string CommentoCopia(const long pos_id, const int tipo)
  {
   string lato = "S";
   if(tipo == 0)
      lato = "B";
   return WTSL_PREFISSO_COMMENTO + IntegerToString(pos_id) + "|" + lato;
  }

bool ChiaveDaCommento(const string commento, long &pos_id, int &tipo)
  {
   pos_id = 0;
   tipo = -1;
   if(StringFind(commento, WTSL_PREFISSO_COMMENTO) != 0)
      return false;
   string resto = StringSubstr(commento, StringLen(WTSL_PREFISSO_COMMENTO));
   long id = StringToInteger(Campo(resto, 0, "|"));
   string lato = Campo(resto, 1, "|");
   if(id <= 0)
      return false;
   if(lato == "B")
      tipo = 0;
   else
      if(lato == "S")
         tipo = 1;
      else
         return false;
   pos_id = id;
   return true;
  }

//+------------------------------------------------------------------+
//| Ora Europe/Rome con ora legale automatica (regola UE)            |
//| CEST dall'ultima domenica di marzo 01:00 UTC all'ultima domenica |
//| di ottobre 01:00 UTC; altrimenti CET (UTC+1).                    |
//+------------------------------------------------------------------+
datetime Utc(const int anno, const int mese, const int giorno, const int ora, const int minuti, const int secondi)
  {
   MqlDateTime t;
   ZeroMemory(t);
   t.year = anno;
   t.mon = mese;
   t.day = giorno;
   t.hour = ora;
   t.min = minuti;
   t.sec = secondi;
   return StructToTime(t);
  }

datetime UltimaDomenicaUTC(const int anno, const int mese)
  {
   datetime giorno31 = Utc(anno, mese, 31, 0, 0, 0); // marzo e ottobre hanno 31 giorni
   MqlDateTime k;
   TimeToStruct(giorno31, k);
   return (datetime)((long)giorno31 - (long)k.day_of_week * 86400);
  }

int OffsetRomaSec(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(utc, d);
   long inizio = (long)UltimaDomenicaUTC(d.year, 3) + 3600;
   long fine = (long)UltimaDomenicaUTC(d.year, 10) + 3600;
   long u = (long)utc;
   if(u >= inizio && u < fine)
      return 7200;
   return 3600;
  }

datetime UtcARoma(const datetime utc)
  {
   return (datetime)((long)utc + OffsetRomaSec(utc));
  }

long DataRoma(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(UtcARoma(utc), d);
   return (long)d.year * 10000 + (long)d.mon * 100 + (long)d.day;
  }

int SecondiGiornoRoma(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(UtcARoma(utc), d);
   return d.hour * 3600 + d.min * 60 + d.sec;
  }

bool InSessione(const datetime utc)
  {
   int s = SecondiGiornoRoma(utc);
   return (s >= WTSL_SESSIONE_INIZIO_SEC && s < WTSL_SESSIONE_FINE_SEC);
  }

string OraRoma(const datetime utc)
  {
   return TimeToString(UtcARoma(utc), TIME_DATE | TIME_SECONDS);
  }

// Differenza tra ora del server di trading e UTC, arrotondata al quarto d'ora.
long OffsetServerSec()
  {
   long d = (long)TimeTradeServer() - (long)TimeGMT();
   return (long)MathRound((double)d / 900.0) * 900;
  }

//+------------------------------------------------------------------+
//| Regole pure (usate dal ricevitore e dall'autotest)               |
//+------------------------------------------------------------------+
// Soglie del conto 100k: movimento contrario >= 5,00 di prezzo
// (Bid per BUY, Ask per SELL) E POSITION_PROFIT <= -500,00.
bool Soglie100kRaggiunte(const int tipo, const double prezzoIngresso, const double bid, const double ask,
                         const double profitto, const double point, string &motivo)
  {
   double pt = point;
   if(pt <= 0.0)
      pt = 0.01;
   double riferimento = ask;
   double distanza = riferimento - prezzoIngresso;
   string nomePrezzo = "Ask";
   if(tipo == 0)
     {
      riferimento = bid;
      distanza = prezzoIngresso - bid;
      nomePrezzo = "Bid";
     }
   long distanzaTick = (long)MathRound(distanza / pt);
   long sogliaTick = (long)MathRound(WTSL_SOGLIA_MOVIMENTO / pt);
   bool okMovimento = (distanzaTick >= sogliaTick);
   bool okPerdita = (Centesimi(profitto) <= -Centesimi(WTSL_SOGLIA_PERDITA_100K));
   motivo = "100k " + TipoTesto(tipo) + ": " + nomePrezzo + " " + DoubleToString(riferimento, 5)
            + " contro ingresso " + DoubleToString(prezzoIngresso, 5)
            + ", movimento " + DoubleToString((double)distanzaTick * pt, 3) + " (minimo " + DoubleToString(WTSL_SOGLIA_MOVIMENTO, 2) + ")"
            + ", P/L " + Soldi(profitto) + " (massimo -" + Soldi(WTSL_SOGLIA_PERDITA_100K) + ")";
   if(!okMovimento)
      motivo = motivo + " -> movimento insufficiente";
   if(!okPerdita)
      motivo = motivo + " -> perdita insufficiente";
   return (okMovimento && okPerdita);
  }

// Importi lordi su 0,50 lotti: stop esattamente -250,00 e target esattamente +750,00.
bool Importi50kEsatti(const double profittoSL, const double profittoTP, string &motivo)
  {
   bool okSL = (Centesimi(profittoSL) == -Centesimi(WTSL_RISCHIO_50K));
   bool okTP = (Centesimi(profittoTP) == Centesimi(WTSL_TARGET_50K));
   motivo = "50k " + DoubleToString(WTSL_LOTTI_50K, 2) + " lotti: stop " + Soldi(profittoSL)
            + " (richiesto -" + Soldi(WTSL_RISCHIO_50K) + "), target " + Soldi(profittoTP)
            + " (richiesto +" + Soldi(WTSL_TARGET_50K) + ")";
   if(!okSL || !okTP)
      motivo = motivo + " -> importi diversi, attendo il prezzo utile";
   return (okSL && okTP);
  }

// Trade sorgente aperto in sessione e copia nello stesso giorno italiano e nella stessa sessione.
bool StessaSessione(const datetime aperturaUtc, const datetime oraUtc, string &motivo)
  {
   if(!InSessione(oraUtc))
     {
      motivo = "fuori finestra 15:30-17:30 Europe/Rome (ora " + OraRoma(oraUtc) + ")";
      return false;
     }
   if(!InSessione(aperturaUtc) || DataRoma(aperturaUtc) != DataRoma(oraUtc))
     {
      motivo = "trade 100k aperto alle " + OraRoma(aperturaUtc) + ", fuori dalla sessione corrente (" + OraRoma(oraUtc) + ")";
      return false;
     }
   motivo = "sessione valida";
   return true;
  }

//+------------------------------------------------------------------+
//| Registro eventi su disco (FILE_COMMON) e stato a video           |
//+------------------------------------------------------------------+
void LogEvento(const string testo)
  {
   string riga = OraRoma(TimeGMT()) + " Roma | " + testo;
   Print(riga);
   if(g_fileEventi == "")
      return;
   int h = FileOpen(g_fileEventi, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, riga + "\r\n");
   FileClose(h);
  }

void AggiornaGrafico(const string testo)
  {
   if(testo == g_ultimoGrafico)
      return;
   g_ultimoGrafico = testo;
   Comment(testo);
  }

// Stato di attesa: registrato quando cambia, al massimo una riga al secondo
// (vicino alle soglie lo stato puo' alternarsi a ogni tick), e comunque ogni minuto.
void Stato(const string codice, const string messaggio)
  {
   long ora = OraMs();
   bool cambiato = (codice != g_ultimoCodiceStato);
   bool dettaglio = (InpLogDettagliato && messaggio != g_ultimoMessaggioStato);
   if(cambiato || dettaglio)
      g_statoDaRegistrare = true;
   if((g_statoDaRegistrare && ora - g_ultimoLogStatoMs >= 1000) || ora - g_ultimoLogStatoMs >= 60000)
     {
      LogEvento("[" + codice + "] " + messaggio);
      g_ultimoLogStatoMs = ora;
      g_statoDaRegistrare = false;
     }
   g_ultimoCodiceStato = codice;
   g_ultimoMessaggioStato = messaggio;
   string ruolo = "RICEVITORE 50k";
   if(g_ruolo == RUOLO_SORGENTE_100K)
      ruolo = "SORGENTE 100k";
   AggiornaGrafico("WTSL-50%ercole - " + ruolo + "\n[" + codice + "]\n" + messaggio);
  }

string DescrizioneRetcode(const uint rc)
  {
   if(rc == TRADE_RETCODE_REQUOTE)
      return "requote";
   if(rc == TRADE_RETCODE_REJECT)
      return "richiesta rifiutata";
   if(rc == TRADE_RETCODE_CANCEL)
      return "richiesta annullata";
   if(rc == TRADE_RETCODE_PLACED)
      return "ordine piazzato";
   if(rc == TRADE_RETCODE_DONE)
      return "eseguito";
   if(rc == TRADE_RETCODE_DONE_PARTIAL)
      return "eseguito parzialmente";
   if(rc == TRADE_RETCODE_ERROR)
      return "errore di elaborazione";
   if(rc == TRADE_RETCODE_TIMEOUT)
      return "timeout";
   if(rc == TRADE_RETCODE_INVALID)
      return "richiesta non valida";
   if(rc == TRADE_RETCODE_INVALID_VOLUME)
      return "volume non valido";
   if(rc == TRADE_RETCODE_INVALID_PRICE)
      return "prezzo non valido";
   if(rc == TRADE_RETCODE_INVALID_STOPS)
      return "livelli SL/TP rifiutati";
   if(rc == TRADE_RETCODE_TRADE_DISABLED)
      return "trading disabilitato";
   if(rc == TRADE_RETCODE_MARKET_CLOSED)
      return "mercato chiuso";
   if(rc == TRADE_RETCODE_NO_MONEY)
      return "margine insufficiente";
   if(rc == TRADE_RETCODE_PRICE_CHANGED)
      return "prezzo cambiato";
   if(rc == TRADE_RETCODE_PRICE_OFF)
      return "nessuna quotazione";
   if(rc == TRADE_RETCODE_TOO_MANY_REQUESTS)
      return "troppe richieste";
   if(rc == TRADE_RETCODE_CONNECTION)
      return "nessuna connessione col server";
   if(rc == TRADE_RETCODE_INVALID_FILL)
      return "esecuzione Fill or Kill non ammessa";
   if(rc == TRADE_RETCODE_LIMIT_POSITIONS)
      return "limite posizioni";
   if(rc == TRADE_RETCODE_LIMIT_VOLUME)
      return "limite volume";
   return "codice " + IntegerToString((long)rc);
  }

// Rifiuti per cui e' certo che nessuna posizione sia stata aperta.
bool RifiutoCerto(const uint rc)
  {
   if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_REJECT || rc == TRADE_RETCODE_CANCEL
      || rc == TRADE_RETCODE_INVALID || rc == TRADE_RETCODE_INVALID_VOLUME || rc == TRADE_RETCODE_INVALID_PRICE
      || rc == TRADE_RETCODE_INVALID_STOPS || rc == TRADE_RETCODE_TRADE_DISABLED || rc == TRADE_RETCODE_MARKET_CLOSED
      || rc == TRADE_RETCODE_NO_MONEY || rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_PRICE_OFF
      || rc == TRADE_RETCODE_TOO_MANY_REQUESTS || rc == TRADE_RETCODE_INVALID_FILL
      || rc == TRADE_RETCODE_LIMIT_POSITIONS || rc == TRADE_RETCODE_LIMIT_VOLUME)
      return true;
   return false;
  }

//+------------------------------------------------------------------+
//| WaveTrend LazyBear (n1=10, n2=21, segnale SMA 4)                 |
//| ap = hlc3; esa = ema(ap,n1); d = ema(|ap-esa|,n1)                |
//| ci = (ap-esa)/(0.015*d); wt1 = ema(ci,n2); wt2 = sma(wt1,4)      |
//+------------------------------------------------------------------+
void WT_Calcola(const int n)
  {
   double a1 = 2.0 / (WTSL_WT_CANALE + 1.0);
   double a2 = 2.0 / (WTSL_WT_MEDIA + 1.0);
   double esa = 0.0;
   double d = 0.0;
   double tci = 0.0;
   for(int i = 0; i < n; i++)
     {
      double ap = (g_rates[i].high + g_rates[i].low + g_rates[i].close) / 3.0;
      if(i == 0)
         esa = ap;
      else
         esa = a1 * ap + (1.0 - a1) * esa;
      double dev = MathAbs(ap - esa);
      if(i == 0)
         d = dev;
      else
         d = a1 * dev + (1.0 - a1) * d;
      double ci = 0.0;
      if(d > 0.0)
         ci = (ap - esa) / (0.015 * d);
      if(i == 0)
         tci = ci;
      else
         tci = a2 * ci + (1.0 - a2) * tci;
      g_wt1[i] = tci;
      int k = WTSL_WT_SEGNALE;
      if(i + 1 < k)
         k = i + 1;
      double somma = 0.0;
      for(int j = 0; j < k; j++)
         somma += g_wt1[i - j];
      g_wt2[i] = somma / k;
     }
  }

// Direzione dell'incrocio wt1/wt2 confermato sulla candela M15 chiusa che inizia a "barraConfermata" (ora server).
bool WT_IncrocioSuBarra(const string simbolo, const datetime barraConfermata, int &direzione)
  {
   direzione = 0;
   int shift = iBarShift(simbolo, PERIOD_M15, barraConfermata, true);
   if(shift < 0)
      return false;
   int copiate = CopyRates(simbolo, PERIOD_M15, shift, WTSL_WT_BARRE, g_rates);
   if(copiate < 60)
      return false;
   if(g_rates[copiate - 1].time != barraConfermata)
      return false;
   WT_Calcola(copiate);
   int k = copiate - 1;
   if(g_wt1[k] > g_wt2[k] && g_wt1[k - 1] <= g_wt2[k - 1])
      direzione = 1;
   else
      if(g_wt1[k] < g_wt2[k] && g_wt1[k - 1] >= g_wt2[k - 1])
         direzione = -1;
   return true;
  }

//+------------------------------------------------------------------+
//| RUOLO SORGENTE (terminale 100k): sola lettura, nessun ordine     |
//+------------------------------------------------------------------+
int MotivoDaReason(const long reason)
  {
   if(reason == DEAL_REASON_SL)
      return MOT_SL;
   if(reason == DEAL_REASON_TP)
      return MOT_TP;
   if(reason == DEAL_REASON_EXPERT)
      return MOT_EXPERT;
   if(reason == DEAL_REASON_CLIENT || reason == DEAL_REASON_MOBILE || reason == DEAL_REASON_WEB)
      return MOT_MANUALE;
   if(reason == DEAL_REASON_SO)
      return MOT_STOPOUT;
   return MOT_ALTRO;
  }

bool PosizioneWT67Aperta(const long pos_id, const int tipo)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_IDENTIFIER) != pos_id)
         continue;
      if((int)PositionGetInteger(POSITION_TYPE) == tipo)
         return true;
     }
   return false;
  }

int CercaCacheWT(const long pos_id, const int tipo)
  {
   for(int i = 0; i < g_nCacheWT; i++)
      if(g_cacheWT[i].pos_id == pos_id && g_cacheWT[i].tipo == tipo)
         return i;
   return -1;
  }

void SalvaCacheWT(const long pos_id, const int tipo, const int direzione)
  {
   if(g_nCacheWT >= WTSL_MAX_CACHE_WT)
     {
      for(int i = 1; i < g_nCacheWT; i++)
         g_cacheWT[i - 1] = g_cacheWT[i];
      g_nCacheWT--;
     }
   g_cacheWT[g_nCacheWT].pos_id = pos_id;
   g_cacheWT[g_nCacheWT].tipo = tipo;
   g_cacheWT[g_nCacheWT].direzione = direzione;
   g_nCacheWT++;
  }

// 1 se la chiusura da EA del WT67 e' dovuta all'incrocio opposto:
// a) il WT67 ha aperto la posizione opposta entro 120 s dalla chiusura, oppure
// b) il WaveTrend 10/21/4 conferma l'incrocio opposto sulla M15 chiusa precedente.
int ClassificaOpposto(const long pos_id, const int tipoChiuso, const int motivo, const long chiusuraServer)
  {
   if(motivo != MOT_EXPERT)
      return 0;
   for(int j = 0; j < g_nAp; j++)
     {
      if(g_apTipo[j] == tipoChiuso)
         continue;
      if(g_apTempo[j] >= chiusuraServer - 5 && g_apTempo[j] <= chiusuraServer + WTSL_FINESTRA_INVERSIONE_SEC)
         return 1;
     }
   int c = CercaCacheWT(pos_id, tipoChiuso);
   int direzione = 0;
   if(c >= 0)
      direzione = g_cacheWT[c].direzione;
   else
     {
      long barraChiusura = chiusuraServer - (chiusuraServer % 900);
      datetime barraConfermata = (datetime)(barraChiusura - 900);
      if(!WT_IncrocioSuBarra(InpSimbolo100k, barraConfermata, direzione))
         return 0;                    // dati non disponibili: si riprova al giro successivo
      SalvaCacheWT(pos_id, tipoChiuso, direzione);
     }
   if(tipoChiuso == 0 && direzione == -1)
      return 1;
   if(tipoChiuso == 1 && direzione == 1)
      return 1;
   return 0;
  }

// Ricostruisce dallo storico del broker (ultime 48 ore) le chiusure dei trade WT67.
void RicostruisciChiusure()
  {
   long oraServer = (long)TimeTradeServer();
   long offset = OffsetServerSec();
   if(!HistorySelect((datetime)(oraServer - 2 * 86400), (datetime)(oraServer + 86400)))
      return;
   int totale = HistoryDealsTotal();
   g_nAp = 0;
   for(int i = 0; i < totale; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != InpSimbolo100k)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicWT67)
         continue;
      if(g_nAp >= WTSL_MAX_APERTURE_STORICO)
        {
         for(int k = 1; k < g_nAp; k++)
           {
            g_apId[k - 1] = g_apId[k];
            g_apTipo[k - 1] = g_apTipo[k];
            g_apTempo[k - 1] = g_apTempo[k];
           }
         g_nAp--;
        }
      g_apId[g_nAp] = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      g_apTipo[g_nAp] = 1;
      if(HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY)
         g_apTipo[g_nAp] = 0;
      g_apTempo[g_nAp] = HistoryDealGetInteger(deal, DEAL_TIME);
      g_nAp++;
     }
   ChiusuraSorgente nuove[WTSL_MAX_CHIUSURE];
   int n = 0;
   for(int i = 0; i < totale; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != InpSimbolo100k)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
         continue;
      long pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      bool delWT67 = false;
      for(int j = 0; j < g_nAp; j++)
         if(g_apId[j] == pid)
            delWT67 = true;
      if(!delWT67)
         continue;
      int tipoChiuso = 1;
      if(HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_SELL)
         tipoChiuso = 0;
      if(PosizioneWT67Aperta(pid, tipoChiuso))
         continue;                    // chiusura parziale: la posizione e' ancora aperta
      long tempoServer = HistoryDealGetInteger(deal, DEAL_TIME);
      int motivo = MotivoDaReason(HistoryDealGetInteger(deal, DEAL_REASON));
      int posto = -1;
      for(int j = 0; j < n; j++)
         if(nuove[j].pos_id == pid && nuove[j].tipo == tipoChiuso)
            posto = j;
      if(posto < 0)
        {
         if(n >= WTSL_MAX_CHIUSURE)
           {
            for(int k = 1; k < n; k++)
               nuove[k - 1] = nuove[k];
            n--;
           }
         posto = n;
         n++;
        }
      nuove[posto].pos_id = pid;
      nuove[posto].tipo = tipoChiuso;
      nuove[posto].motivo = motivo;
      nuove[posto].chiusura_utc = tempoServer - offset;
      nuove[posto].opposto = ClassificaOpposto(pid, tipoChiuso, motivo, tempoServer);
     }
   for(int i = 0; i < n; i++)
     {
      bool nota = false;
      for(int j = 0; j < g_nChiusure; j++)
         if(g_chiusure[j].pos_id == nuove[i].pos_id && g_chiusure[j].tipo == nuove[i].tipo
            && g_chiusure[j].opposto == nuove[i].opposto)
            nota = true;
      if(!nota)
         LogEvento("Trade WT67 100k #" + IntegerToString(nuove[i].pos_id) + " " + TipoTesto(nuove[i].tipo)
                   + " chiuso: " + MotivoTesto(nuove[i].motivo)
                   + (nuove[i].opposto == 1 ? " (incrocio WaveTrend opposto confermato)" : ""));
     }
   for(int i = 0; i < n; i++)
      g_chiusure[i] = nuove[i];
   g_nChiusure = n;
  }

string SnapshotATesto(const SnapshotSorgente &s)
  {
   string t = WTSL_FILE_INTESTAZIONE;
   t += "\r\n";
   t += "seq=" + IntegerToString(s.seq) + "\r\n";
   t += "tick_ms=" + IntegerToString(s.tick_ms) + "\r\n";
   t += "gmt=" + IntegerToString(s.gmt) + "\r\n";
   t += "login=" + IntegerToString(s.login) + "\r\n";
   t += "simbolo=" + InpSimbolo100k + "\r\n";
   t += "magic=" + IntegerToString(InpMagicWT67) + "\r\n";
   t += "connesso=" + IntegerToString(s.connesso) + "\r\n";
   t += "digits=" + IntegerToString(s.digits) + "\r\n";
   t += "point=" + DoubleToString(s.point, 8) + "\r\n";
   t += "quota_eta_sec=" + IntegerToString(s.quota_eta_sec) + "\r\n";
   t += "bid=" + DoubleToString(s.bid, 8) + "\r\n";
   t += "ask=" + DoubleToString(s.ask, 8) + "\r\n";
   t += "n_posizioni=" + IntegerToString(s.n_posizioni) + "\r\n";
   t += "pos_aperta=" + IntegerToString(s.pos_aperta) + "\r\n";
   t += "pos_id=" + IntegerToString(s.pos_id) + "\r\n";
   t += "pos_ticket=" + IntegerToString(s.pos_ticket) + "\r\n";
   t += "pos_tipo=" + IntegerToString(s.pos_tipo) + "\r\n";
   t += "pos_volume=" + DoubleToString(s.pos_volume, 8) + "\r\n";
   t += "pos_prezzo=" + DoubleToString(s.pos_prezzo, 8) + "\r\n";
   t += "pos_sl=" + DoubleToString(s.pos_sl, 8) + "\r\n";
   t += "pos_tp=" + DoubleToString(s.pos_tp, 8) + "\r\n";
   t += "pos_profitto=" + DoubleToString(s.pos_profitto, 8) + "\r\n";
   t += "pos_apertura_utc=" + IntegerToString(s.pos_apertura_utc) + "\r\n";
   for(int i = 0; i < s.n_chiusure; i++)
      t += "chiusura=" + IntegerToString(s.chiusure[i].pos_id) + ";" + IntegerToString(s.chiusure[i].tipo) + ";"
           + IntegerToString(s.chiusure[i].motivo) + ";" + IntegerToString(s.chiusure[i].opposto) + ";"
           + IntegerToString(s.chiusure[i].chiusura_utc) + "\r\n";
   t += "fine=" + IntegerToString(s.seq) + "\r\n";
   return t;
  }

bool ScriviCanale(const SnapshotSorgente &s)
  {
   string tmp = g_fileCanale + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      g_erroriScrittura++;
      if(g_erroriScrittura % 100 == 1)
         LogEvento("Impossibile scrivere il canale (errore " + IntegerToString(GetLastError()) + ")");
      return false;
     }
   FileWriteString(h, SnapshotATesto(s));
   FileClose(h);
   if(!FileMove(tmp, FILE_COMMON, g_fileCanale, FILE_COMMON | FILE_REWRITE))
     {
      g_erroriScrittura++;
      if(g_erroriScrittura % 100 == 1)
         LogEvento("Impossibile aggiornare il canale (errore " + IntegerToString(GetLastError()) + "), riprovo");
      return false;
     }
   return true;
  }

void Sorgente_Ciclo()
  {
   SnapshotSorgente s;
   ZeroMemory(s);
   g_seq++;
   s.valido = 1;
   s.seq = g_seq;
   s.tick_ms = OraMs();
   s.gmt = (long)TimeGMT();
   s.login = AccountInfoInteger(ACCOUNT_LOGIN);
   s.connesso = 0;
   if(TerminalInfoInteger(TERMINAL_CONNECTED) != 0)
      s.connesso = 1;
   s.digits = (int)SymbolInfoInteger(InpSimbolo100k, SYMBOL_DIGITS);
   s.point = SymbolInfoDouble(InpSimbolo100k, SYMBOL_POINT);
   s.quota_eta_sec = 999999;
   MqlTick tick;
   if(SymbolInfoTick(InpSimbolo100k, tick))
     {
      s.bid = tick.bid;
      s.ask = tick.ask;
      s.quota_eta_sec = (long)TimeTradeServer() - (long)tick.time;
     }
   long offset = OffsetServerSec();
   long firma = 0;
   long aperturaPiuRecente = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSimbolo100k)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicWT67)
         continue;
      s.n_posizioni++;
      long id = PositionGetInteger(POSITION_IDENTIFIER);
      int tipo = (int)PositionGetInteger(POSITION_TYPE);
      firma += id * 2 + tipo;
      long apertura = PositionGetInteger(POSITION_TIME);
      if(apertura > aperturaPiuRecente)
        {
         aperturaPiuRecente = apertura;
         s.pos_aperta = 1;
         s.pos_id = id;
         s.pos_ticket = (long)ticket;
         s.pos_tipo = tipo;
         s.pos_volume = PositionGetDouble(POSITION_VOLUME);
         s.pos_prezzo = PositionGetDouble(POSITION_PRICE_OPEN);
         s.pos_sl = PositionGetDouble(POSITION_SL);
         s.pos_tp = PositionGetDouble(POSITION_TP);
         s.pos_profitto = PositionGetDouble(POSITION_PROFIT);
         s.pos_apertura_utc = apertura - offset;
        }
     }
   long ora = OraMs();
   if(firma != g_firmaPosizioni || ora - g_ultimaRicostruzioneMs >= 1000)
     {
      if(firma != g_firmaPosizioni && s.pos_aperta == 1)
         LogEvento("Trade WT67 100k osservato: #" + IntegerToString(s.pos_id) + " " + TipoTesto(s.pos_tipo) + " "
                   + DoubleToString(s.pos_volume, 2) + " lotti a " + DoubleToString(s.pos_prezzo, s.digits)
                   + " SL " + DoubleToString(s.pos_sl, s.digits) + " TP " + DoubleToString(s.pos_tp, s.digits));
      g_firmaPosizioni = firma;
      RicostruisciChiusure();
      g_ultimaRicostruzioneMs = ora;
     }
   s.n_chiusure = g_nChiusure;
   for(int i = 0; i < g_nChiusure; i++)
      s.chiusure[i] = g_chiusure[i];
   ScriviCanale(s);
   string stato = "nessun trade WT67 aperto";
   if(s.pos_aperta == 1)
      stato = "#" + IntegerToString(s.pos_id) + " " + TipoTesto(s.pos_tipo) + " a " + DoubleToString(s.pos_prezzo, s.digits)
              + " P/L " + Soldi(s.pos_profitto);
   AggiornaGrafico("WTSL-50%ercole - SORGENTE 100k (nessun ordine inviato da questo EA)\n" + stato
                   + "\nconnesso=" + IntegerToString(s.connesso) + " seq=" + IntegerToString(s.seq));
  }

//+------------------------------------------------------------------+
//| RUOLO RICEVITORE (terminale 50k)                                 |
//+------------------------------------------------------------------+
bool LeggiCanale(SnapshotSorgente &s)
  {
   ZeroMemory(s);
   if(!FileIsExist(g_fileCanale, FILE_COMMON))
      return false;
   int h = FileOpen(g_fileCanale, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return false;
   string intestazione = Pulisci(FileReadString(h));
   if(intestazione != WTSL_FILE_INTESTAZIONE)
     {
      FileClose(h);
      return false;
     }
   long fine = -1;
   bool okSimbolo = false;
   bool okMagic = false;
   int nc = 0;
   while(!FileIsEnding(h))
     {
      string riga = Pulisci(FileReadString(h));
      string k = "";
      string v = "";
      if(!DividiChiaveValore(riga, k, v))
         continue;
      if(k == "seq")            { s.seq = StringToInteger(v); continue; }
      if(k == "tick_ms")        { s.tick_ms = StringToInteger(v); continue; }
      if(k == "gmt")            { s.gmt = StringToInteger(v); continue; }
      if(k == "login")          { s.login = StringToInteger(v); continue; }
      if(k == "simbolo")        { okSimbolo = (v == InpSimbolo100k); continue; }
      if(k == "magic")          { okMagic = (StringToInteger(v) == InpMagicWT67); continue; }
      if(k == "connesso")       { s.connesso = (int)StringToInteger(v); continue; }
      if(k == "digits")         { s.digits = (int)StringToInteger(v); continue; }
      if(k == "point")          { s.point = StringToDouble(v); continue; }
      if(k == "quota_eta_sec")  { s.quota_eta_sec = StringToInteger(v); continue; }
      if(k == "bid")            { s.bid = StringToDouble(v); continue; }
      if(k == "ask")            { s.ask = StringToDouble(v); continue; }
      if(k == "n_posizioni")    { s.n_posizioni = (int)StringToInteger(v); continue; }
      if(k == "pos_aperta")     { s.pos_aperta = (int)StringToInteger(v); continue; }
      if(k == "pos_id")         { s.pos_id = StringToInteger(v); continue; }
      if(k == "pos_ticket")     { s.pos_ticket = StringToInteger(v); continue; }
      if(k == "pos_tipo")       { s.pos_tipo = (int)StringToInteger(v); continue; }
      if(k == "pos_volume")     { s.pos_volume = StringToDouble(v); continue; }
      if(k == "pos_prezzo")     { s.pos_prezzo = StringToDouble(v); continue; }
      if(k == "pos_sl")         { s.pos_sl = StringToDouble(v); continue; }
      if(k == "pos_tp")         { s.pos_tp = StringToDouble(v); continue; }
      if(k == "pos_profitto")   { s.pos_profitto = StringToDouble(v); continue; }
      if(k == "pos_apertura_utc") { s.pos_apertura_utc = StringToInteger(v); continue; }
      if(k == "fine")           { fine = StringToInteger(v); continue; }
      if(k == "chiusura" && nc < WTSL_MAX_CHIUSURE)
        {
         s.chiusure[nc].pos_id = StringToInteger(Campo(v, 0, ";"));
         s.chiusure[nc].tipo = (int)StringToInteger(Campo(v, 1, ";"));
         s.chiusure[nc].motivo = (int)StringToInteger(Campo(v, 2, ";"));
         s.chiusure[nc].opposto = (int)StringToInteger(Campo(v, 3, ";"));
         s.chiusure[nc].chiusura_utc = StringToInteger(Campo(v, 4, ";"));
         nc++;
        }
     }
   FileClose(h);
   s.n_chiusure = nc;
   if(s.seq <= 0 || fine != s.seq)
      return false;                   // file letto a meta' scrittura: si usa il precedente
   if(!okSimbolo || !okMagic || s.login != InpConto100k)
      return false;
   s.valido = 1;
   return true;
  }

bool CanaleAffidabile(const SnapshotSorgente &s, const long oraMs, string &motivo)
  {
   if(s.valido != 1)
     {
      motivo = "nessun dato valido dal terminale 100k";
      return false;
     }
   long eta = oraMs - s.tick_ms;
   long etaGmt = (long)TimeGMT() - s.gmt;
   if(eta < -1000 || eta > InpMaxEtaDatiMs || etaGmt < -2 || etaGmt > InpMaxEtaDatiMs / 1000 + 2)
     {
      motivo = "dati del 100k non aggiornati (eta' " + IntegerToString(eta) + " ms): terminale 100k fermo o EA sorgente assente";
      return false;
     }
   if(s.connesso != 1)
     {
      motivo = "terminale 100k disconnesso dal server";
      return false;
     }
   if(s.quota_eta_sec > InpMaxEtaQuotazioneSec)
     {
      motivo = "ultima quotazione del 100k vecchia di " + IntegerToString(s.quota_eta_sec) + " s";
      return false;
     }
   motivo = "canale 100k aggiornato";
   return true;
  }

bool Conto50kOperativo(string &motivo)
  {
   if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
     {
      motivo = "terminale 50k disconnesso: nuove aperture sospese, SL/TP restano al broker";
      return false;
     }
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0 || MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
     {
      motivo = "Algo Trading disattivato sul terminale 50k";
      return false;
     }
   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0 || AccountInfoInteger(ACCOUNT_TRADE_EXPERT) == 0)
     {
      motivo = "il conto 50k non consente il trading automatico";
      return false;
     }
   if(SymbolInfoInteger(InpSimbolo50k, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
     {
      motivo = "simbolo " + InpSimbolo50k + " non negoziabile in entrambe le direzioni";
      return false;
     }
   if(!g_fokDisponibile)
     {
      motivo = "il broker non ammette Fill or Kill su " + InpSimbolo50k;
      return false;
     }
   if(!g_contoHedging)
     {
      motivo = "il conto 50k non e' in modalita' hedging";
      return false;
     }
   motivo = "conto 50k operativo";
   return true;
  }

//--- registro persistente delle copie
int CercaVoce(const long pos_id, const int tipo)
  {
   for(int i = 0; i < g_nRegistro; i++)
      if(g_registro[i].pos_id == pos_id && g_registro[i].tipo == tipo)
         return i;
   return -1;
  }

int CercaVocePerTicket(const long ticket50)
  {
   if(ticket50 <= 0)
      return -1;
   for(int i = 0; i < g_nRegistro; i++)
      if(g_registro[i].ticket50 == ticket50)
         return i;
   return -1;
  }

int NuovaVoce(const long pos_id, const int tipo)
  {
   if(g_nRegistro >= WTSL_MAX_REGISTRO)
     {
      int via = 0;
      for(int i = 0; i < g_nRegistro; i++)
         if(g_registro[i].utc < g_registro[via].utc)
            via = i;
      for(int i = via + 1; i < g_nRegistro; i++)
         g_registro[i - 1] = g_registro[i];
      g_nRegistro--;
     }
   int k = g_nRegistro;
   ZeroMemory(g_registro[k]);
   g_registro[k].pos_id = pos_id;
   g_registro[k].tipo = tipo;
   g_registro[k].utc = (long)TimeGMT();
   g_registro[k].data_roma = DataRoma(TimeGMT());
   g_nRegistro++;
   return k;
  }

bool SalvaRegistro()
  {
   string testo = WTSL_REG_INTESTAZIONE;
   testo += "\r\n";
   for(int i = 0; i < g_nRegistro; i++)
      testo += IntegerToString(g_registro[i].pos_id) + ";" + IntegerToString(g_registro[i].tipo) + ";"
               + IntegerToString(g_registro[i].stato) + ";" + IntegerToString(g_registro[i].utc) + ";"
               + IntegerToString(g_registro[i].data_roma) + ";" + IntegerToString(g_registro[i].tentativi) + ";"
               + IntegerToString(g_registro[i].ticket50) + ";" + IntegerToString(g_registro[i].retcode) + "\r\n";
   testo += "fine=" + IntegerToString(g_nRegistro) + "\r\n";
   string tmp = g_fileRegistro + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      LogEvento("ERRORE: impossibile scrivere il registro copie (errore " + IntegerToString(GetLastError()) + ")");
      return false;
     }
   FileWriteString(h, testo);
   FileFlush(h);
   FileClose(h);
   if(!FileMove(tmp, FILE_COMMON, g_fileRegistro, FILE_COMMON | FILE_REWRITE))
     {
      LogEvento("ERRORE: impossibile aggiornare il registro copie (errore " + IntegerToString(GetLastError()) + ")");
      return false;
     }
   return true;
  }

bool CaricaRegistro()
  {
   g_nRegistro = 0;
   if(!FileIsExist(g_fileRegistro, FILE_COMMON))
      return true;
   int h = FileOpen(g_fileRegistro, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
     {
      LogEvento("ERRORE: registro copie presente ma non leggibile (errore " + IntegerToString(GetLastError()) + ")");
      return false;
     }
   string intestazione = Pulisci(FileReadString(h));
   if(intestazione != WTSL_REG_INTESTAZIONE)
     {
      FileClose(h);
      LogEvento("ERRORE: registro copie con intestazione inattesa");
      return false;
     }
   bool convertite = false;
   while(!FileIsEnding(h) && g_nRegistro < WTSL_MAX_REGISTRO)
     {
      string riga = Pulisci(FileReadString(h));
      if(riga == "" || StringFind(riga, "fine=") == 0)
         continue;
      long id = StringToInteger(Campo(riga, 0, ";"));
      if(id <= 0)
         continue;
      int k = g_nRegistro;
      ZeroMemory(g_registro[k]);
      g_registro[k].pos_id = id;
      g_registro[k].tipo = (int)StringToInteger(Campo(riga, 1, ";"));
      g_registro[k].stato = (int)StringToInteger(Campo(riga, 2, ";"));
      g_registro[k].utc = StringToInteger(Campo(riga, 3, ";"));
      g_registro[k].data_roma = StringToInteger(Campo(riga, 4, ";"));
      g_registro[k].tentativi = (int)StringToInteger(Campo(riga, 5, ";"));
      g_registro[k].ticket50 = StringToInteger(Campo(riga, 6, ";"));
      g_registro[k].retcode = (int)StringToInteger(Campo(riga, 7, ";"));
      if(g_registro[k].stato == REG_INVIO)
        {
         g_registro[k].stato = REG_INCERTA;   // riavvio durante un invio: mai reinviare
         convertite = true;
        }
      g_nRegistro++;
     }
   FileClose(h);
   LogEvento("Registro copie caricato: " + IntegerToString(g_nRegistro) + " voci");
   if(convertite)
     {
      LogEvento("Invio interrotto da un riavvio: la voce resta bloccata come INCERTA");
      SalvaRegistro();
     }
   return true;
  }

// Allinea il registro con posizioni e storico del broker (protezione se il file viene perso).
void SincronizzaRegistroDaStorico()
  {
   bool cambiato = false;
   long offset = OffsetServerSec();
   long oraServer = (long)TimeTradeServer();
   if(HistorySelect((datetime)(oraServer - 10 * 86400), (datetime)(oraServer + 86400)))
     {
      int totale = HistoryDealsTotal();
      for(int i = 0; i < totale; i++)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0)
            continue;
         if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicRicevitore)
            continue;
         if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         long id = 0;
         int tipo = -1;
         if(!ChiaveDaCommento(HistoryDealGetString(deal, DEAL_COMMENT), id, tipo))
            continue;
         int k = CercaVoce(id, tipo);
         long pos50 = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(k < 0)
           {
            k = NuovaVoce(id, tipo);
            g_registro[k].stato = REG_CHIUSA;
            g_registro[k].utc = HistoryDealGetInteger(deal, DEAL_TIME) - offset;
            g_registro[k].data_roma = DataRoma((datetime)g_registro[k].utc);
            g_registro[k].ticket50 = pos50;
            cambiato = true;
            LogEvento("Registro ricostruito dallo storico: trade 100k #" + IntegerToString(id) + " gia' copiato");
           }
         else
            if(g_registro[k].stato == REG_INVIO || g_registro[k].stato == REG_INCERTA || g_registro[k].stato == REG_RIFIUTATA)
              {
               g_registro[k].stato = REG_CHIUSA;
               g_registro[k].ticket50 = pos50;
               cambiato = true;
              }
        }
     }
   // posizioni aperte dal bot
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicRicevitore)
         continue;
      long id = 0;
      int tipo = -1;
      if(!ChiaveDaCommento(PositionGetString(POSITION_COMMENT), id, tipo))
         continue;
      int k = CercaVoce(id, tipo);
      if(k < 0)
        {
         k = NuovaVoce(id, tipo);
         g_registro[k].utc = PositionGetInteger(POSITION_TIME) - offset;
         g_registro[k].data_roma = DataRoma((datetime)g_registro[k].utc);
        }
      if(g_registro[k].stato != REG_APERTA)
        {
         g_registro[k].stato = REG_APERTA;
         g_registro[k].ticket50 = PositionGetInteger(POSITION_IDENTIFIER);
         cambiato = true;
        }
     }
   // copie registrate come aperte ma non piu' presenti
   for(int i = 0; i < g_nRegistro; i++)
     {
      if(g_registro[i].stato != REG_APERTA)
         continue;
      bool presente = false;
      for(int j = PositionsTotal() - 1; j >= 0; j--)
        {
         ulong ticket = PositionGetTicket(j);
         if(ticket == 0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicRicevitore
            && PositionGetInteger(POSITION_IDENTIFIER) == g_registro[i].ticket50)
            presente = true;
        }
      if(!presente)
        {
         g_registro[i].stato = REG_CHIUSA;
         cambiato = true;
         LogEvento("Copia del trade 100k #" + IntegerToString(g_registro[i].pos_id) + " risulta chiusa sul 50k");
        }
     }
   if(cambiato)
      SalvaRegistro();
  }

// Vero se per questo trade sorgente non si deve piu' aprire nulla.
bool GiaCopiato(const long pos_id, const int tipo, string &codice, string &motivo)
  {
   int k = CercaVoce(pos_id, tipo);
   if(k < 0)
      return false;
   int st = g_registro[k].stato;
   codice = "GIA_COPIATO";
   if(st == REG_RIFIUTATA)
     {
      if(g_registro[k].tentativi >= InpMaxTentativi)
        {
         codice = "TENTATIVI_ESAURITI";
         motivo = "trade 100k #" + IntegerToString(pos_id) + ": tentativi esauriti ("
                  + IntegerToString(g_registro[k].tentativi) + "), ultimo rifiuto: " + DescrizioneRetcode((uint)g_registro[k].retcode);
         return true;
        }
      if((long)TimeGMT() - g_registro[k].utc < InpPausaTentativiSec)
        {
         codice = "PAUSA_DOPO_RIFIUTO";
         motivo = "trade 100k #" + IntegerToString(pos_id) + ": pausa dopo il rifiuto del broker";
         return true;
        }
      return false;
     }
   motivo = "trade 100k #" + IntegerToString(pos_id) + " gia' gestito (registro: " + StatoRegistroTesto(st) + ")";
   return true;
  }

int ApertureOggi(const datetime oraUtc)
  {
   long oggi = DataRoma(oraUtc);
   int nRegistro = 0;
   for(int i = 0; i < g_nRegistro; i++)
     {
      int st = g_registro[i].stato;
      if(st == REG_RIFIUTATA)
         continue;
      if(g_registro[i].data_roma == oggi)
         nRegistro++;
     }
   int nDeal = 0;
   long offset = OffsetServerSec();
   long oraServer = (long)TimeTradeServer();
   if(HistorySelect((datetime)(oraServer - 2 * 86400), (datetime)(oraServer + 86400)))
     {
      int totale = HistoryDealsTotal();
      for(int i = 0; i < totale; i++)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0)
            continue;
         if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicRicevitore)
            continue;
         if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         long utc = HistoryDealGetInteger(deal, DEAL_TIME) - offset;
         if(DataRoma((datetime)utc) == oggi)
            nDeal++;
        }
     }
   if(nDeal > nRegistro)
      return nDeal;
   return nRegistro;
  }

// Posizioni del bot aperte sul 50k (qualsiasi simbolo). Restituisce il numero e i dati dell'ultima.
int CopieAperte(long &ticket, long &identificativo, long &sorgenteId, int &sorgenteTipo)
  {
   int n = 0;
   ticket = 0;
   identificativo = 0;
   sorgenteId = 0;
   sorgenteTipo = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicRicevitore)
         continue;
      n++;
      ticket = (long)t;
      identificativo = PositionGetInteger(POSITION_IDENTIFIER);
      long id = 0;
      int tipo = -1;
      if(ChiaveDaCommento(PositionGetString(POSITION_COMMENT), id, tipo))
        {
         sorgenteId = id;
         sorgenteTipo = tipo;
        }
      else
        {
         int k = CercaVocePerTicket(identificativo);
         if(k >= 0)
           {
            sorgenteId = g_registro[k].pos_id;
            sorgenteTipo = g_registro[k].tipo;
           }
        }
     }
   return n;
  }

bool VolumeValido(const string simbolo, const double volume, string &motivo)
  {
   double vmin = SymbolInfoDouble(simbolo, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(simbolo, SYMBOL_VOLUME_MAX);
   double passo = SymbolInfoDouble(simbolo, SYMBOL_VOLUME_STEP);
   if(volume < vmin - 1e-9 || volume > vmax + 1e-9)
     {
      motivo = "volume " + DoubleToString(volume, 2) + " fuori dai limiti del broker (" + DoubleToString(vmin, 2) + "-" + DoubleToString(vmax, 2) + ")";
      return false;
     }
   if(passo > 0.0)
     {
      double passi = volume / passo;
      if(MathAbs(passi - MathRound(passi)) > 1e-6)
        {
         motivo = "volume " + DoubleToString(volume, 2) + " non multiplo del passo " + DoubleToString(passo, 2);
         return false;
        }
     }
   return true;
  }

// Prepara la richiesta sul 50k con il prezzo realmente disponibile (Ask per BUY, Bid per SELL).
bool Prepara50k(const int tipo, const double sl100, const double tp100, PianoOrdine &p, string &codice, string &motivo)
  {
   MqlTick tick;
   if(!SymbolInfoTick(InpSimbolo50k, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
     {
      codice = "ATTESA_QUOTAZIONE_50K";
      motivo = "nessuna quotazione disponibile su " + InpSimbolo50k;
      return false;
     }
   int dg = (int)SymbolInfoInteger(InpSimbolo50k, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(InpSimbolo50k, SYMBOL_POINT);
   double sl = NormalizeDouble(sl100, dg);
   double tp = NormalizeDouble(tp100, dg);
   if(MathAbs(sl - sl100) > pt * 0.01 || MathAbs(tp - tp100) > pt * 0.01)
     {
      codice = "LIVELLI_NON_COPIABILI";
      motivo = "SL/TP del 100k non rappresentabili con " + IntegerToString(dg) + " decimali sul 50k";
      return false;
     }
   double prezzo = tick.bid;
   ENUM_ORDER_TYPE tipoOrdine = ORDER_TYPE_SELL;
   if(tipo == 0)
     {
      prezzo = tick.ask;
      tipoOrdine = ORDER_TYPE_BUY;
     }
   double livelloStop = (double)SymbolInfoInteger(InpSimbolo50k, SYMBOL_TRADE_STOPS_LEVEL) * pt;
   bool latiOk = true;
   if(tipo == 0)
      latiOk = (sl < tick.bid && sl <= tick.bid - livelloStop && tp > tick.bid && tp >= tick.bid + livelloStop);
   else
      latiOk = (sl > tick.ask && sl >= tick.ask + livelloStop && tp < tick.ask && tp <= tick.ask - livelloStop);
   if(!latiOk)
     {
      codice = "ATTESA_LIVELLI_50K";
      motivo = "SL " + DoubleToString(sl, dg) + " / TP " + DoubleToString(tp, dg) + " non validi rispetto a Bid "
               + DoubleToString(tick.bid, dg) + " / Ask " + DoubleToString(tick.ask, dg) + " del 50k";
      return false;
     }
   string m = "";
   if(!VolumeValido(InpSimbolo50k, WTSL_LOTTI_50K, m))
     {
      codice = "VOLUME_NON_AMMESSO";
      motivo = m;
      return false;
     }
   double profSL = 0.0;
   double profTP = 0.0;
   if(!OrderCalcProfit(tipoOrdine, InpSimbolo50k, WTSL_LOTTI_50K, prezzo, sl, profSL)
      || !OrderCalcProfit(tipoOrdine, InpSimbolo50k, WTSL_LOTTI_50K, prezzo, tp, profTP))
     {
      codice = "ATTESA_CALCOLO_50K";
      motivo = "OrderCalcProfit non disponibile (errore " + IntegerToString(GetLastError()) + ")";
      return false;
     }
   if(!Importi50kEsatti(profSL, profTP, m))
     {
      codice = "ATTESA_PREZZO_50K";
      motivo = TipoTesto(tipo) + " a " + DoubleToString(prezzo, dg) + ": " + m;
      return false;
     }
   p.tipo = tipo;
   p.prezzo = prezzo;
   p.sl = sl;
   p.tp = tp;
   p.profitto_sl = profSL;
   p.profitto_tp = profTP;
   motivo = TipoTesto(tipo) + " " + DoubleToString(WTSL_LOTTI_50K, 2) + " a " + DoubleToString(prezzo, dg) + " SL " + DoubleToString(sl, dg)
            + " TP " + DoubleToString(tp, dg) + ": " + m;
   return true;
  }

// Tutte le condizioni di ingresso valutate sullo stesso snapshot del 100k e sulla quotazione attuale del 50k.
bool CondizioniIngresso(const SnapshotSorgente &s, const datetime oraUtc, const long oraMs, PianoOrdine &p,
                        string &codice, string &motivo)
  {
   ZeroMemory(p);
   if(!CanaleAffidabile(s, oraMs, motivo))
     {
      codice = "SOSPESO_100K";
      return false;
     }
   if(!Conto50kOperativo(motivo))
     {
      codice = "SOSPESO_50K";
      return false;
     }
   if(s.n_posizioni > 1)
     {
      codice = "SORGENTE_AMBIGUA";
      motivo = IntegerToString(s.n_posizioni) + " posizioni WT67 aperte sul 100k: nessuna copia";
      return false;
     }
   if(s.pos_aperta != 1)
     {
      codice = "NESSUN_TRADE_100K";
      motivo = "nessun trade WT67 aperto sul 100k";
      return false;
     }
   if(GiaCopiato(s.pos_id, s.pos_tipo, codice, motivo))
      return false;
   if(s.pos_sl <= 0.0 || s.pos_tp <= 0.0)
     {
      codice = "SORGENTE_SENZA_LIVELLI";
      motivo = "il trade 100k #" + IntegerToString(s.pos_id) + " non ha SL e TP entrambi impostati";
      return false;
     }
   if(!StessaSessione((datetime)s.pos_apertura_utc, oraUtc, motivo))
     {
      codice = "FUORI_SESSIONE";
      return false;
     }
   int aperture = ApertureOggi(oraUtc);
   if(aperture >= WTSL_MAX_APERTURE_GIORNO)
     {
      codice = "LIMITE_GIORNALIERO";
      motivo = "gia' " + IntegerToString(aperture) + " aperture oggi (massimo " + IntegerToString(WTSL_MAX_APERTURE_GIORNO) + ")";
      return false;
     }
   long t1 = 0;
   long t2 = 0;
   long t3 = 0;
   int t4 = 0;
   if(CopieAperte(t1, t2, t3, t4) > 0)
     {
      codice = "COPIA_GIA_APERTA";
      motivo = "una posizione del bot e' gia' aperta sul 50k";
      return false;
     }
   g_attesaId = s.pos_id;
   g_attesaTipo = s.pos_tipo;
   if(!Soglie100kRaggiunte(s.pos_tipo, s.pos_prezzo, s.bid, s.ask, s.pos_profitto, s.point, motivo))
     {
      codice = "ATTESA_SOGLIE_100K";
      return false;
     }
   string m100 = motivo;
   if(!Prepara50k(s.pos_tipo, s.pos_sl, s.pos_tp, p, codice, motivo))
     {
      motivo = motivo + " | " + m100;
      return false;
     }
   p.pos_id = s.pos_id;
   codice = "PRONTO";
   motivo = motivo + " | " + m100;
   return true;
  }

void CompilaRichiesta(const PianoOrdine &p, MqlTradeRequest &req)
  {
   ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = InpSimbolo50k;
   req.volume = WTSL_LOTTI_50K;
   req.type = ORDER_TYPE_SELL;
   if(p.tipo == 0)
      req.type = ORDER_TYPE_BUY;
   req.price = p.prezzo;
   req.sl = p.sl;
   req.tp = p.tp;
   req.deviation = (ulong)InpDeviazionePunti;
   req.type_filling = ORDER_FILLING_FOK;
   req.type_time = ORDER_TIME_GTC;
   req.magic = (ulong)InpMagicRicevitore;
   req.comment = CommentoCopia(p.pos_id, p.tipo);
  }

void VerificaCopiaAperta(const PianoOrdine &p, const MqlTradeResult &res)
  {
   int dg = (int)SymbolInfoInteger(InpSimbolo50k, SYMBOL_DIGITS);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicRicevitore)
         continue;
      long id = 0;
      int tipo = -1;
      if(!ChiaveDaCommento(PositionGetString(POSITION_COMMENT), id, tipo) || id != p.pos_id || tipo != p.tipo)
         continue;
      double prezzo = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_ORDER_TYPE tipoOrdine = ORDER_TYPE_SELL;
      if(p.tipo == 0)
         tipoOrdine = ORDER_TYPE_BUY;
      double pSL = 0.0;
      double pTP = 0.0;
      OrderCalcProfit(tipoOrdine, InpSimbolo50k, volume, prezzo, p.sl, pSL);
      OrderCalcProfit(tipoOrdine, InpSimbolo50k, volume, prezzo, p.tp, pTP);
      LogEvento("Copia aperta sul 50k: " + TipoTesto(p.tipo) + " " + DoubleToString(volume, 2) + " lotti a " + DoubleToString(prezzo, dg)
                + " SL " + DoubleToString(sl, dg) + " TP " + DoubleToString(tp, dg)
                + " | lordo allo stop " + Soldi(pSL) + ", al target " + Soldi(pTP));
      if(MathAbs(prezzo - p.prezzo) > SymbolInfoDouble(InpSimbolo50k, SYMBOL_POINT) * 0.5)
         LogEvento("ATTENZIONE: eseguito a " + DoubleToString(prezzo, dg) + " invece di " + DoubleToString(p.prezzo, dg)
                   + " (slittamento): gli importi lordi realizzabili cambiano");
      if(MathAbs(volume - WTSL_LOTTI_50K) > 1e-8)
         LogEvento("ATTENZIONE: volume eseguito " + DoubleToString(volume, 2) + " diverso da " + DoubleToString(WTSL_LOTTI_50K, 2));
      if(MathAbs(sl - p.sl) > 1e-8 || MathAbs(tp - p.tp) > 1e-8)
        {
         LogEvento("ATTENZIONE: SL/TP non presenti sulla posizione, li imposto ora");
         MqlTradeRequest mod;
         MqlTradeResult esito;
         ZeroMemory(mod);
         ZeroMemory(esito);
         mod.action = TRADE_ACTION_SLTP;
         mod.symbol = InpSimbolo50k;
         mod.position = ticket;
         mod.sl = p.sl;
         mod.tp = p.tp;
         mod.magic = (ulong)InpMagicRicevitore;
         if(!OrderSend(mod, esito) || esito.retcode != TRADE_RETCODE_DONE)
            LogEvento("ERRORE: impostazione SL/TP rifiutata: " + DescrizioneRetcode(esito.retcode) + " " + esito.comment);
        }
      return;
     }
   LogEvento("Esito " + DescrizioneRetcode(res.retcode) + " ma la posizione non e' ancora visibile: la cerco nei cicli successivi");
  }

void InviaCopia(const PianoOrdine &p)
  {
   MqlTradeRequest req;
   MqlTradeResult res;
   MqlTradeCheckResult chk;
   CompilaRichiesta(p, req);
   ZeroMemory(res);
   ZeroMemory(chk);
   if(!OrderCheck(req, chk))
     {
      Stato("ATTESA_VERIFICA_ORDINE", "OrderCheck: " + DescrizioneRetcode(chk.retcode) + " " + chk.comment);
      return;
     }
   // registrazione su disco PRIMA dell'invio: dopo un riavvio o un timeout non si apre una seconda copia
   int k = CercaVoce(p.pos_id, p.tipo);
   if(k < 0)
      k = NuovaVoce(p.pos_id, p.tipo);
   g_registro[k].stato = REG_INVIO;
   g_registro[k].utc = (long)TimeGMT();
   g_registro[k].data_roma = DataRoma(TimeGMT());
   g_registro[k].tentativi++;
   if(!SalvaRegistro())
     {
      g_registro[k].stato = REG_RIFIUTATA;
      g_registro[k].tentativi--;
      LogEvento("ERRORE: registro copie non scrivibile, ordine NON inviato per il trade 100k #" + IntegerToString(p.pos_id));
      Stato("ERRORE_REGISTRO", "registro copie non scrivibile: ordine NON inviato");
      return;
     }
   int dg = (int)SymbolInfoInteger(InpSimbolo50k, SYMBOL_DIGITS);
   LogEvento("Invio " + TipoTesto(p.tipo) + " " + DoubleToString(WTSL_LOTTI_50K, 2) + " " + InpSimbolo50k + " a "
             + DoubleToString(p.prezzo, dg) + " SL " + DoubleToString(p.sl, dg) + " TP " + DoubleToString(p.tp, dg)
             + " (FOK) per il trade 100k #" + IntegerToString(p.pos_id) + ", tentativo " + IntegerToString(g_registro[k].tentativi)
             + ", lordo previsto " + Soldi(p.profitto_sl) + " / +" + Soldi(p.profitto_tp));
   ResetLastError();
   bool inviato = OrderSend(req, res);
   uint rc = res.retcode;
   g_registro[k].retcode = (int)rc;
   g_registro[k].utc = (long)TimeGMT();
   if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL)
     {
      g_registro[k].stato = REG_APERTA;
      g_registro[k].ticket50 = (long)res.order;
      SalvaRegistro();
      LogEvento("Ordine eseguito: deal " + IntegerToString((long)res.deal) + ", ordine " + IntegerToString((long)res.order)
                + ", prezzo " + DoubleToString(res.price, dg) + ", volume " + DoubleToString(res.volume, 2));
      VerificaCopiaAperta(p, res);
      g_attesaId = 0;
      g_attesaTipo = -1;
      return;
     }
   if(RifiutoCerto(rc) || (!inviato && rc == 0))
     {
      g_registro[k].stato = REG_RIFIUTATA;
      SalvaRegistro();
      LogEvento("Ordine RIFIUTATO dal broker: " + DescrizioneRetcode(rc) + " (retcode " + IntegerToString((long)rc)
                + ", errore " + IntegerToString(GetLastError()) + ", '" + res.comment + "'). Nessuna posizione aperta; tentativi "
                + IntegerToString(g_registro[k].tentativi) + "/" + IntegerToString(InpMaxTentativi));
      return;
     }
   g_registro[k].stato = REG_INCERTA;
   SalvaRegistro();
   LogEvento("Esito NON certo: " + DescrizioneRetcode(rc) + " (retcode " + IntegerToString((long)rc) + ", '" + res.comment
             + "'). Il trade 100k #" + IntegerToString(p.pos_id) + " non verra' piu' copiato per evitare duplicati");
  }

bool ChiudiCopia(const long ticket, const string motivo)
  {
   if(!PositionSelectByTicket((ulong)ticket))
      return false;
   if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
     {
      Stato("CHIUSURA_IN_ATTESA", "terminale 50k disconnesso: chiusura rimandata (" + motivo + ")");
      return false;
     }
   long ora = OraMs();
   if(ora - g_ultimoTentativoChiusuraMs < 1000)
      return false;
   g_ultimoTentativoChiusuraMs = ora;
   string simbolo = PositionGetString(POSITION_SYMBOL);
   MqlTick tick;
   if(!SymbolInfoTick(simbolo, tick))
      return false;
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = simbolo;
   req.position = (ulong)ticket;
   req.volume = PositionGetDouble(POSITION_VOLUME);
   req.magic = (ulong)InpMagicRicevitore;
   req.deviation = (ulong)InpDeviazionePunti;
   req.comment = "WTSL50 chiusura";
   if((int)PositionGetInteger(POSITION_TYPE) == 0)
     {
      req.type = ORDER_TYPE_SELL;
      req.price = tick.bid;
     }
   else
     {
      req.type = ORDER_TYPE_BUY;
      req.price = tick.ask;
     }
   long riempimento = SymbolInfoInteger(simbolo, SYMBOL_FILLING_MODE);
   req.type_filling = ORDER_FILLING_IOC;
   if((riempimento & SYMBOL_FILLING_FOK) != 0)
      req.type_filling = ORDER_FILLING_FOK;
   bool ok = OrderSend(req, res);
   if(ok && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL))
     {
      LogEvento("Copia #" + IntegerToString(ticket) + " chiusa: " + motivo + " (prezzo " + DoubleToString(res.price, 5) + ")");
      return true;
     }
   LogEvento("Chiusura della copia #" + IntegerToString(ticket) + " non riuscita: " + DescrizioneRetcode(res.retcode)
             + " '" + res.comment + "'. Riprovo; SL/TP restano al broker");
   return false;
  }

void GestisciCopiaAperta(const long ticket, const long sorgenteId, const int sorgenteTipo)
  {
   if(sorgenteId <= 0)
     {
      if(OraMs() - g_copiaSenzaChiaveLog > 60000)
        {
         LogEvento("Posizione #" + IntegerToString(ticket) + " con magic del bot ma senza trade sorgente riconoscibile: resta con i suoi SL/TP");
         g_copiaSenzaChiaveLog = OraMs();
        }
      Stato("COPIA_APERTA", "posizione #" + IntegerToString(ticket) + " aperta (sorgente sconosciuta)");
      return;
     }
   if(g_haSnap)
     {
      for(int i = 0; i < g_snap.n_chiusure; i++)
        {
         if(g_snap.chiusure[i].pos_id != sorgenteId || g_snap.chiusure[i].tipo != sorgenteTipo)
            continue;
         int motivo = g_snap.chiusure[i].motivo;
         bool chiudi = (g_snap.chiusure[i].opposto == 1);
         string perche = "il 100k ha chiuso il trade #" + IntegerToString(sorgenteId) + " per incrocio WaveTrend opposto";
         if(!chiudi && InpChiudiSuAltreChiusure && motivo != MOT_SL && motivo != MOT_TP)
           {
            chiudi = true;
            perche = "il 100k ha chiuso il trade #" + IntegerToString(sorgenteId) + " (" + MotivoTesto(motivo) + ")";
           }
         if(chiudi)
           {
            Stato("CHIUSURA_COPIA", perche);
            if(ChiudiCopia(ticket, perche))
               SincronizzaRegistroDaStorico();
            return;
           }
         Stato("COPIA_APERTA", "trade 100k #" + IntegerToString(sorgenteId) + " chiuso (" + MotivoTesto(motivo)
               + "): la copia #" + IntegerToString(ticket) + " resta con i suoi SL/TP al broker");
         return;
        }
     }
   Stato("COPIA_APERTA", "copia #" + IntegerToString(ticket) + " del trade 100k #" + IntegerToString(sorgenteId) + " aperta, SL/TP al broker");
  }

void Ricevitore_Ciclo()
  {
   long oraMs = OraMs();
   SnapshotSorgente s;
   if(LeggiCanale(s))
     {
      g_snap = s;
      g_haSnap = true;
     }
   if(g_ultimaScansioneMs == 0 || oraMs - g_ultimaScansioneMs >= 30000)
     {
      SincronizzaRegistroDaStorico();
      g_ultimaScansioneMs = oraMs;
     }
   long ticket = 0;
   long identificativo = 0;
   long sorgenteId = 0;
   int sorgenteTipo = -1;
   int n = CopieAperte(ticket, identificativo, sorgenteId, sorgenteTipo);
   if(n > 1)
      Stato("ALLARME_PIU_COPIE", IntegerToString(n) + " posizioni con magic " + IntegerToString(InpMagicRicevitore) + " aperte: nessuna nuova apertura");
   if(n > 0)
     {
      if(sorgenteId > 0)
        {
         int k = CercaVoce(sorgenteId, sorgenteTipo);
         if(k < 0 || g_registro[k].stato != REG_APERTA)
            SincronizzaRegistroDaStorico();
        }
      GestisciCopiaAperta(ticket, sorgenteId, sorgenteTipo);
      return;
     }
   // attesa annullata se il trade sorgente atteso non e' piu' aperto
   if(g_attesaId != 0 && g_haSnap && g_snap.valido == 1)
     {
      if(g_snap.pos_aperta != 1 || g_snap.pos_id != g_attesaId || g_snap.pos_tipo != g_attesaTipo)
        {
         LogEvento("Attesa annullata: il trade 100k #" + IntegerToString(g_attesaId) + " " + TipoTesto(g_attesaTipo)
                   + " e' stato chiuso prima dell'ingresso sul 50k");
         g_attesaId = 0;
         g_attesaTipo = -1;
        }
     }
   string codice = "";
   string motivo = "";
   PianoOrdine p1;
   if(!g_haSnap)
     {
      Stato("ATTESA_CANALE", "nessun dato dal terminale 100k (file " + g_fileCanale + " in Common\\Files)");
      return;
     }
   if(!CondizioniIngresso(g_snap, TimeGMT(), oraMs, p1, codice, motivo))
     {
      if(g_attesaId != 0 && (codice == "FUORI_SESSIONE" || codice == "LIMITE_GIORNALIERO"))
        {
         LogEvento("Attesa terminata per il trade 100k #" + IntegerToString(g_attesaId) + ": " + motivo);
         g_attesaId = 0;
         g_attesaTipo = -1;
        }
      Stato(codice, motivo);
      return;
     }
   // verifica finale di entrambi i conti subito prima dell'invio
   SnapshotSorgente f;
   if(!LeggiCanale(f))
     {
      Stato("VERIFICA_FINALE", "rilettura del canale 100k non riuscita: riprovo al prossimo tick");
      return;
     }
   g_snap = f;
   PianoOrdine p2;
   if(!CondizioniIngresso(f, TimeGMT(), OraMs(), p2, codice, motivo))
     {
      LogEvento("Verifica finale prima dell'invio non superata, ordine non inviato: [" + codice + "] " + motivo);
      Stato(codice, "verifica finale: " + motivo);
      return;
     }
   if(p2.pos_id != p1.pos_id || p2.tipo != p1.tipo)
     {
      Stato("VERIFICA_FINALE", "il trade 100k e' cambiato durante la verifica");
      return;
     }
   InviaCopia(p2);
  }

//+------------------------------------------------------------------+
//| Autotest (InpAutoTest=true): regole pure + OrderCalcProfit reale |
//+------------------------------------------------------------------+
int g_testOk = 0;
int g_testKo = 0;

void Verifica(const string nome, const bool atteso, const bool osservato, const string dettaglio)
  {
   string esito = "FALLITO";
   if(atteso == osservato)
     {
      esito = "OK";
      g_testOk++;
     }
   else
      g_testKo++;
   Print("AUTOTEST | ", nome, " | atteso ", (atteso ? "SI" : "NO"), " | osservato ", (osservato ? "SI" : "NO"), " | ", esito, " | ", dettaglio);
  }

void VerificaImporti(const string nome, const ENUM_ORDER_TYPE tipo, const double prezzo, const double sl, const double tp, const bool atteso)
  {
   double pSL = 0.0;
   double pTP = 0.0;
   string m = "";
   bool calcolato = OrderCalcProfit(tipo, InpSimbolo50k, WTSL_LOTTI_50K, prezzo, sl, pSL)
                    && OrderCalcProfit(tipo, InpSimbolo50k, WTSL_LOTTI_50K, prezzo, tp, pTP);
   bool ok = calcolato && Importi50kEsatti(pSL, pTP, m);
   Verifica(nome, atteso, ok, m);
  }

void EseguiAutoTest()
  {
   g_testOk = 0;
   g_testKo = 0;
   string m = "";
   Verifica("BUY 100k: Bid 2995,00 e P/L -500", true, Soglie100kRaggiunte(0, 3000.0, 2995.00, 2995.30, -500.00, 0.01, m), m);
   Verifica("SELL 100k: Ask 3005,00 e P/L -500", true, Soglie100kRaggiunte(1, 3000.0, 3004.70, 3005.00, -500.00, 0.01, m), m);
   Verifica("4,99 punti (P/L -499)", false, Soglie100kRaggiunte(0, 3000.0, 2995.01, 2995.31, -499.00, 0.01, m), m);
   Verifica("4,99 punti con P/L -598,80", false, Soglie100kRaggiunte(0, 3000.0, 2995.01, 2995.31, -598.80, 0.01, m), m);
   Verifica("5,00 punti con P/L -499,00", false, Soglie100kRaggiunte(0, 3000.0, 2995.00, 2995.30, -499.00, 0.01, m), m);
   Verifica("5,00 punti con P/L -499,99", false, Soglie100kRaggiunte(0, 3000.0, 2995.00, 2995.30, -499.99, 0.01, m), m);
   Verifica("3 decimali: 4,999 punti", false, Soglie100kRaggiunte(0, 3000.0, 2995.001, 2995.3, -500.00, 0.001, m), m);
   Verifica("Importi -250/+750", true, Importi50kEsatti(-250.0, 750.0, m), m);
   Verifica("Importi -260/+740", false, Importi50kEsatti(-260.0, 740.0, m), m);
   Verifica("Importi -250,01/+750", false, Importi50kEsatti(-250.01, 750.0, m), m);
   Verifica("Sessione 15:30:00 (estate)", true, InSessione(Utc(2026, 7, 15, 13, 30, 0)), OraRoma(Utc(2026, 7, 15, 13, 30, 0)));
   Verifica("Sessione 15:29:59 (estate)", false, InSessione(Utc(2026, 7, 15, 13, 29, 59)), OraRoma(Utc(2026, 7, 15, 13, 29, 59)));
   Verifica("Sessione 17:29:59 (estate)", true, InSessione(Utc(2026, 7, 15, 15, 29, 59)), OraRoma(Utc(2026, 7, 15, 15, 29, 59)));
   Verifica("Sessione 17:30:00 (estate)", false, InSessione(Utc(2026, 7, 15, 15, 30, 0)), OraRoma(Utc(2026, 7, 15, 15, 30, 0)));
   Verifica("Sessione 15:30:00 (inverno)", true, InSessione(Utc(2026, 1, 15, 14, 30, 0)), OraRoma(Utc(2026, 1, 15, 14, 30, 0)));
   Verifica("Sessione 17:30:00 (inverno)", false, InSessione(Utc(2026, 1, 15, 16, 30, 0)), OraRoma(Utc(2026, 1, 15, 16, 30, 0)));
   Verifica("Ora legale 29/03/2026 00:59:59 UTC = +1", true, OffsetRomaSec(Utc(2026, 3, 29, 0, 59, 59)) == 3600, "");
   Verifica("Ora legale 29/03/2026 01:00:00 UTC = +2", true, OffsetRomaSec(Utc(2026, 3, 29, 1, 0, 0)) == 7200, "");
   Verifica("Ora solare 25/10/2026 00:59:59 UTC = +2", true, OffsetRomaSec(Utc(2026, 10, 25, 0, 59, 59)) == 7200, "");
   Verifica("Ora solare 25/10/2026 01:00:00 UTC = +1", true, OffsetRomaSec(Utc(2026, 10, 25, 1, 0, 0)) == 3600, "");
   long id = 0;
   int tipo = -1;
   bool chiave = ChiaveDaCommento(CommentoCopia(123456789, 1), id, tipo) && id == 123456789 && tipo == 1;
   Verifica("Commento copia reversibile", true, chiave, CommentoCopia(123456789, 1));
   // OrderCalcProfit reale del broker (esempi validi per conto in USD e contratto da 100 once)
   Print("AUTOTEST | valuta conto ", AccountInfoString(ACCOUNT_CURRENCY), ", contratto ", DoubleToString(SymbolInfoDouble(InpSimbolo50k, SYMBOL_TRADE_CONTRACT_SIZE), 2));
   VerificaImporti("Broker: BUY 0,50 a 2995 SL 2990 TP 3010", ORDER_TYPE_BUY, 2995.00, 2990.00, 3010.00, true);
   VerificaImporti("Broker: SELL 0,50 a 3005 SL 3010 TP 2990", ORDER_TYPE_SELL, 3005.00, 3010.00, 2990.00, true);
   VerificaImporti("Broker: BUY 0,50 a 2995,20 (spread)", ORDER_TYPE_BUY, 2995.20, 2990.00, 3010.00, false);
   Print("AUTOTEST | completato: ", IntegerToString(g_testOk), " OK, ", IntegerToString(g_testKo), " falliti");
   Comment("WTSL-50%ercole AUTOTEST: " + IntegerToString(g_testOk) + " OK, " + IntegerToString(g_testKo) + " falliti (vedi scheda Esperti)");
  }

//+------------------------------------------------------------------+
//| Eventi                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpAutoTest)
     {
      g_soloTest = true;
      EseguiAutoTest();
      return INIT_SUCCEEDED;
     }
   if(MQLInfoInteger(MQL_TESTER) != 0)
     {
      Print("WTSL-50%ercole richiede due terminali reali collegati: nel tester usare solo InpAutoTest=true");
      return INIT_FAILED;
     }
   if(InpConto100k <= 0 || InpConto50k <= 0 || InpConto100k == InpConto50k)
     {
      Print("Impostare InpConto100k e InpConto50k con i due login MT5 (diversi tra loro)");
      return INIT_PARAMETERS_INCORRECT;
     }
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(login == InpConto100k)
      g_ruolo = RUOLO_SORGENTE_100K;
   else
      if(login == InpConto50k)
         g_ruolo = RUOLO_RICEVITORE_50K;
      else
        {
         Print("Il login ", IntegerToString(login), " non corrisponde ne' a InpConto100k ne' a InpConto50k");
         return INIT_FAILED;
        }
   FolderCreate(InpCartellaComune, FILE_COMMON);
   g_fileCanale = InpCartellaComune + "\\canale_" + IntegerToString(InpConto100k) + ".txt";
   g_fileRegistro = InpCartellaComune + "\\registro_" + IntegerToString(InpConto50k) + "_da_" + IntegerToString(InpConto100k) + ".txt";
   g_fileEventi = InpCartellaComune + "\\eventi_" + IntegerToString(login) + ".log";
   if(g_ruolo == RUOLO_SORGENTE_100K)
     {
      if(!SymbolSelect(InpSimbolo100k, true))
        {
         Print("Simbolo ", InpSimbolo100k, " non disponibile sul conto 100k");
         return INIT_FAILED;
        }
      LogEvento("Avvio ruolo SORGENTE sul conto 100k " + IntegerToString(login) + ": pubblico il trade WT67 (magic "
                + IntegerToString(InpMagicWT67) + ") su " + TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + g_fileCanale
                + ". Questo EA non invia ordini sul 100k.");
      RicostruisciChiusure();
     }
   else
     {
      if(!SymbolSelect(InpSimbolo50k, true))
        {
         Print("Simbolo ", InpSimbolo50k, " non disponibile sul conto 50k");
         return INIT_FAILED;
        }
      long riempimento = SymbolInfoInteger(InpSimbolo50k, SYMBOL_FILLING_MODE);
      g_fokDisponibile = ((riempimento & SYMBOL_FILLING_FOK) != 0);
      g_contoHedging = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      LogEvento("Avvio ruolo RICEVITORE sul conto 50k " + IntegerToString(login) + " (" + AccountInfoString(ACCOUNT_CURRENCY)
                + "), magic " + IntegerToString(InpMagicRicevitore) + ", canale " + g_fileCanale
                + ", FOK " + (g_fokDisponibile ? "ammesso" : "NON ammesso") + ", hedging " + (g_contoHedging ? "si" : "NO"));
      if(!CaricaRegistro())
        {
         Print("Registro copie illeggibile: per sicurezza l'EA non parte. Controllare ", g_fileRegistro);
         return INIT_FAILED;
        }
      SincronizzaRegistroDaStorico();
      g_ultimaScansioneMs = OraMs();
     }
   int periodo = InpTimerMs;
   if(periodo < 50)
      periodo = 50;
   EventSetMillisecondTimer(periodo);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

void Ciclo()
  {
   if(g_soloTest)
      return;
   if(g_ruolo == RUOLO_SORGENTE_100K)
      Sorgente_Ciclo();
   else
      if(g_ruolo == RUOLO_RICEVITORE_50K)
         Ricevitore_Ciclo();
  }

void OnTick()
  {
   Ciclo();
  }

void OnTimer()
  {
   Ciclo();
  }
//+------------------------------------------------------------------+
