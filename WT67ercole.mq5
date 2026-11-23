//+------------------------------------------------------------------+
//|                                                  WT67ercole.mq5  |
//|        Strategia WaveTrend LazyBear 10/21/4 per il conto da 100k |
//+------------------------------------------------------------------+
//
// REGOLE
//  - Simbolo XAUUSD, candele M15. Il segnale si conferma solo su candele
//    CHIUSE: alla prima quotazione di una nuova candela si confronta la
//    candela appena chiusa (barra 1) con quella precedente (barra 2).
//      incrocio rialzista  wt1 > wt2 e prima wt1 <= wt2  -> BUY
//      incrocio ribassista wt1 < wt2 e prima wt1 >= wt2  -> SELL
//  - WaveTrend LazyBear: ap = hlc3, esa = ema(ap,10), d = ema(|ap-esa|,10),
//    ci = (ap-esa)/(0,015*d), wt1 = ema(ci,21), wt2 = sma(wt1,4).
//  - Ordine a mercato da InpLotti (1,00) con SL e TP a 10,00 unita' di prezzo
//    dal prezzo di ingresso effettivo (Ask per BUY, Bid per SELL). Se il
//    broker esegue a un prezzo diverso, SL e TP vengono riallineati.
//  - Nuove aperture solo tra 15:30 inclusa e 17:30 esclusa, ora Europe/Rome
//    con ora legale automatica; massimo InpMaxTradeGiorno al giorno italiano;
//    una sola posizione alla volta (magic InpMagic).
//  - Incrocio opposto con posizione aperta: la posizione viene chiusa (anche
//    fuori orario) e, se le regole lo permettono, si apre quella inversa
//    nello stesso istante. WTSL-50%ercole riconosce questa sequenza e chiude
//    anche la copia sul conto 50k.
//
// Il file e' in ASCII puro: niente caratteri accentati.
//+------------------------------------------------------------------+
#property copyright   "ercole"
#property version     "1.00"
#property description "WT67ercole: WaveTrend LazyBear 10/21/4 su M15 chiuse, XAUUSD, conto 100k."
#property description "1,00 lotto, SL e TP a 10,00, finestra 15:30-17:30 Europe/Rome, chiusura e inversione sull'incrocio opposto."

enum ENUM_WT67_ORA_TESTER
  {
   ORA_TESTER_NY_CLOSE = 0,   // UTC+2, UTC+3 con l'ora legale USA (server FTMO)
   ORA_TESTER_FISSA    = 1    // Differenza fissa da InpOreServerTester
  };

//--- parametri
input group "Conto e simbolo"
input long   InpConto100k            = 0;          // Login del conto 100k (obbligatorio fuori dal Tester)
input string InpSimbolo              = "XAUUSD";   // Simbolo
input long   InpMagic                = 670067;     // Magic number (letto da WTSL-50%ercole)

input group "Ordini"
input double InpLotti                = 1.00;       // Lotti per trade
input double InpDistanzaSL           = 10.00;      // Distanza SL dall'ingresso (unita' di prezzo)
input double InpDistanzaTP           = 10.00;      // Distanza TP dall'ingresso (unita' di prezzo)
input int    InpDeviazionePunti      = 30;         // Deviazione massima (punti, solo esecuzione instant/request)
input string InpCommento             = "WT67";     // Commento degli ordini

input group "Regole operative"
input bool   InpSoloInSessione       = true;       // Nuove aperture solo 15:30-17:30 Europe/Rome
input int    InpMaxTradeGiorno       = 4;          // Aperture massime per giorno italiano (0 = nessun limite)
input int    InpMaxRitardoSegnaleSec = 60;         // Secondi dall'apertura della candela entro cui entrare
input bool   InpChiudiSuIncrocioOpposto = true;    // Chiudi la posizione sull'incrocio opposto

input group "Strategy Tester"
input ENUM_WT67_ORA_TESTER InpOraServerTester = ORA_TESTER_NY_CLOSE; // Fuso del server nel Tester
input int    InpOreServerTester      = 2;          // Ore server - UTC se il fuso e' fisso

//--- regole fisse
#define WT67_CANALE              10
#define WT67_MEDIA               21
#define WT67_SEGNALE             4
#define WT67_BARRE               400
#define WT67_SESSIONE_INIZIO_SEC 55800   // 15:30:00 Europe/Rome (inclusa)
#define WT67_SESSIONE_FINE_SEC   63000   // 17:30:00 Europe/Rome (esclusa)

//--- stato
bool      g_tester = false;
bool      g_attivo = false;
string    g_nomeGV = "";
datetime  g_barraSegnale = 0;
int       g_dirSegnale = 0;
bool      g_aperturaFatta = true;
ulong     g_daChiudere = 0;
ulong     g_ultimoChiuso = 0;
long      g_prossimoTentativoMs = 0;
long      g_ultimaVerificaLivelliMs = 0;
long      g_riallineaId = 0;
long      g_riallineaScadenzaMs = 0;
string    g_ultimoGrafico = "";
MqlRates  g_rates[WT67_BARRE];
double    g_wt1[WT67_BARRE];
double    g_wt2[WT67_BARRE];

//+------------------------------------------------------------------+
//| Utilita'                                                         |
//+------------------------------------------------------------------+
long OraMs()
  {
   return (long)GetTickCount64();
  }

string Lato(const int dir)
  {
   if(dir > 0)
      return "BUY";
   return "SELL";
  }

int Cifre()
  {
   return (int)SymbolInfoInteger(InpSimbolo, SYMBOL_DIGITS);
  }

string Px(const double prezzo)
  {
   return DoubleToString(prezzo, Cifre());
  }

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

// n-esima domenica del mese (n >= 1), alle 00:00
datetime DomenicaDelMese(const int anno, const int mese, const int n)
  {
   datetime primo = Utc(anno, mese, 1, 0, 0, 0);
   MqlDateTime d;
   TimeToStruct(primo, d);
   int primaDomenica = 1 + (7 - d.day_of_week) % 7;
   return Utc(anno, mese, primaDomenica + 7 * (n - 1), 0, 0, 0);
  }

datetime UltimaDomenica(const int anno, const int mese)
  {
   datetime giorno31 = Utc(anno, mese, 31, 0, 0, 0);   // marzo e ottobre
   MqlDateTime d;
   TimeToStruct(giorno31, d);
   return (datetime)((long)giorno31 - (long)d.day_of_week * 86400);
  }

// Ora legale europea: dall'ultima domenica di marzo 01:00 UTC all'ultima domenica di ottobre 01:00 UTC.
int OffsetRomaSec(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(utc, d);
   long inizio = (long)UltimaDomenica(d.year, 3) + 3600;
   long fine = (long)UltimaDomenica(d.year, 10) + 3600;
   if((long)utc >= inizio && (long)utc < fine)
      return 7200;
   return 3600;
  }

// Ora legale USA (per i server allineati alla chiusura di New York): seconda domenica di marzo - prima di novembre.
bool OraLegaleUSA(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   long inizio = (long)DomenicaDelMese(d.year, 3, 2) + 7 * 3600;
   long fine = (long)DomenicaDelMese(d.year, 11, 1) + 6 * 3600;
   return ((long)t >= inizio && (long)t < fine);
  }

// Differenza tra ora del server e UTC, in secondi.
long OffsetServerSec()
  {
   if(g_tester)
     {
      if(InpOraServerTester == ORA_TESTER_FISSA)
         return (long)InpOreServerTester * 3600;
      if(OraLegaleUSA(TimeTradeServer()))
         return 3 * 3600;
      return 2 * 3600;
     }
   long d = (long)TimeTradeServer() - (long)TimeGMT();
   return (long)MathRound((double)d / 900.0) * 900;
  }

datetime UtcOra()
  {
   return (datetime)((long)TimeTradeServer() - OffsetServerSec());
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

bool InSessione(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(UtcARoma(utc), d);
   int s = d.hour * 3600 + d.min * 60 + d.sec;
   return (s >= WT67_SESSIONE_INIZIO_SEC && s < WT67_SESSIONE_FINE_SEC);
  }

string OraRoma(const datetime utc)
  {
   return TimeToString(UtcARoma(utc), TIME_DATE | TIME_SECONDS);
  }

void Log(const string testo)
  {
   Print(OraRoma(UtcOra()), " Roma | ", testo);
  }

void AggiornaGrafico(const string testo)
  {
   string t = "WT67ercole - " + InpSimbolo + " M15, magic " + IntegerToString(InpMagic) + "\n" + testo;
   if(t == g_ultimoGrafico)
      return;
   g_ultimoGrafico = t;
   Comment(t);
  }

void Ritenta()
  {
   g_prossimoTentativoMs = OraMs() + 1000;
  }

bool PuoiTentare()
  {
   if(g_tester)
      return true;
   if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
     {
      AggiornaGrafico("terminale disconnesso: in attesa");
      return false;
     }
   return (OraMs() >= g_prossimoTentativoMs);
  }

string DescrizioneRetcode(const uint rc)
  {
   if(rc == TRADE_RETCODE_DONE)
      return "eseguito";
   if(rc == TRADE_RETCODE_DONE_PARTIAL)
      return "eseguito parzialmente";
   if(rc == TRADE_RETCODE_REQUOTE)
      return "requote";
   if(rc == TRADE_RETCODE_REJECT)
      return "richiesta rifiutata";
   if(rc == TRADE_RETCODE_INVALID_STOPS)
      return "livelli SL/TP rifiutati";
   if(rc == TRADE_RETCODE_INVALID_VOLUME)
      return "volume non valido";
   if(rc == TRADE_RETCODE_NO_MONEY)
      return "margine insufficiente";
   if(rc == TRADE_RETCODE_MARKET_CLOSED)
      return "mercato chiuso";
   if(rc == TRADE_RETCODE_PRICE_CHANGED)
      return "prezzo cambiato";
   if(rc == TRADE_RETCODE_PRICE_OFF)
      return "nessuna quotazione";
   if(rc == TRADE_RETCODE_INVALID_FILL)
      return "modalita' di esecuzione non ammessa";
   if(rc == TRADE_RETCODE_TIMEOUT)
      return "timeout";
   if(rc == TRADE_RETCODE_CONNECTION)
      return "nessuna connessione col server";
   return "codice " + IntegerToString((long)rc);
  }

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

ENUM_ORDER_TYPE_FILLING Riempimento()
  {
   long modi = SymbolInfoInteger(InpSimbolo, SYMBOL_FILLING_MODE);
   if((modi & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   if((modi & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

double NormalizzaPrezzo(const double prezzo)
  {
   double passo = SymbolInfoDouble(InpSimbolo, SYMBOL_TRADE_TICK_SIZE);
   double p = prezzo;
   if(passo > 0.0)
      p = MathRound(p / passo) * passo;
   return NormalizeDouble(p, Cifre());
  }

bool VolumeValido(const double volume)
  {
   double vmin = SymbolInfoDouble(InpSimbolo, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(InpSimbolo, SYMBOL_VOLUME_MAX);
   double passo = SymbolInfoDouble(InpSimbolo, SYMBOL_VOLUME_STEP);
   if(volume < vmin - 1e-9 || volume > vmax + 1e-9)
      return false;
   if(passo > 0.0 && MathAbs(volume / passo - MathRound(volume / passo)) > 1e-6)
      return false;
   return true;
  }

// SL/TP validi rispetto ai prezzi correnti e al livello minimo di stop del broker.
bool LivelliValidi(const bool buy, const double sl, const double tp, const MqlTick &tick)
  {
   double livello = (double)SymbolInfoInteger(InpSimbolo, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(InpSimbolo, SYMBOL_POINT);
   if(buy)
      return (sl < tick.bid && sl <= tick.bid - livello && tp > tick.bid && tp >= tick.bid + livello);
   return (sl > tick.ask && sl >= tick.ask + livello && tp < tick.ask && tp <= tick.ask - livello);
  }

//+------------------------------------------------------------------+
//| WaveTrend LazyBear 10/21/4                                       |
//+------------------------------------------------------------------+
void WT_Calcola(const int n)
  {
   double a1 = 2.0 / (WT67_CANALE + 1.0);
   double a2 = 2.0 / (WT67_MEDIA + 1.0);
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
      int k = WT67_SEGNALE;
      if(i + 1 < k)
         k = i + 1;
      double somma = 0.0;
      for(int j = 0; j < k; j++)
         somma += g_wt1[i - j];
      g_wt2[i] = somma / k;
     }
  }

// Incrocio confermato sull'ultima M15 chiusa (barra 1 contro barra 2): +1 BUY, -1 SELL, 0 nessuno.
bool IncrocioUltimaChiusa(int &direzione)
  {
   direzione = 0;
   int copiate = CopyRates(InpSimbolo, PERIOD_M15, 1, WT67_BARRE, g_rates);
   if(copiate < 60)
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
//| Posizioni e ordini                                               |
//+------------------------------------------------------------------+
// Posizioni del bot sul simbolo, esclusa quella appena chiusa che il terminale puo' ancora mostrare.
int PosizioniBot(ulong &ticket, int &tipo)
  {
   int n = 0;
   ticket = 0;
   tipo = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || t == g_ultimoChiuso)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSimbolo || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      n++;
      ticket = t;
      tipo = (int)PositionGetInteger(POSITION_TYPE);
     }
   return n;
  }

int TradeOggi()
  {
   long oggi = DataRoma(UtcOra());
   long offset = OffsetServerSec();
   long server = (long)TimeTradeServer();
   int n = 0;
   if(!HistorySelect((datetime)(server - 2 * 86400), (datetime)(server + 86400)))
      return 0;
   int totale = HistoryDealsTotal();
   for(int i = 0; i < totale; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic || HistoryDealGetString(deal, DEAL_SYMBOL) != InpSimbolo)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      if(DataRoma((datetime)(HistoryDealGetInteger(deal, DEAL_TIME) - offset)) == oggi)
         n++;
     }
   return n;
  }

bool ImpostaLivelli(const ulong ticket, const double sl, const double tp)
  {
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_SLTP;
   req.symbol = InpSimbolo;
   req.position = ticket;
   req.sl = sl;
   req.tp = tp;
   req.magic = (ulong)InpMagic;
   if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
      return true;
   Log("Impostazione SL/TP non riuscita: " + DescrizioneRetcode(res.retcode) + " '" + res.comment + "'");
   return false;
  }

// SL e TP esattamente a InpDistanzaSL / InpDistanzaTP dal prezzo di ingresso effettivo.
void LivelliDaIngresso(const int tipo, const double ingresso, double &sl, double &tp)
  {
   if(tipo == 0)
     {
      sl = NormalizzaPrezzo(ingresso - InpDistanzaSL);
      tp = NormalizzaPrezzo(ingresso + InpDistanzaTP);
     }
   else
     {
      sl = NormalizzaPrezzo(ingresso + InpDistanzaSL);
      tp = NormalizzaPrezzo(ingresso - InpDistanzaTP);
     }
  }

// Ripristina SL/TP se mancano (controllo ogni 5 s) e, subito dopo un'apertura,
// li riallinea a 10,00 dal prezzo realmente eseguito.
void VerificaLivelli()
  {
   bool urgente = (g_riallineaId != 0);
   if(urgente && OraMs() > g_riallineaScadenzaMs)
     {
      g_riallineaId = 0;
      urgente = false;
     }
   if(!urgente && !g_tester && OraMs() - g_ultimaVerificaLivelliMs < 5000)
      return;
   g_ultimaVerificaLivelliMs = OraMs();
   MqlTick tick;
   if(!SymbolInfoTick(InpSimbolo, tick))
      return;
   double mezzoTick = SymbolInfoDouble(InpSimbolo, SYMBOL_POINT) * 0.5;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || t == g_ultimoChiuso)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSimbolo || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      int tipo = (int)PositionGetInteger(POSITION_TYPE);
      double ingresso = PositionGetDouble(POSITION_PRICE_OPEN);
      double slAttuale = PositionGetDouble(POSITION_SL);
      double tpAttuale = PositionGetDouble(POSITION_TP);
      double sl = 0.0;
      double tp = 0.0;
      LivelliDaIngresso(tipo, ingresso, sl, tp);
      bool mancano = (slAttuale <= 0.0 || tpAttuale <= 0.0);
      bool spostati = (MathAbs(slAttuale - sl) > mezzoTick || MathAbs(tpAttuale - tp) > mezzoTick);
      bool appenaAperta = (urgente && PositionGetInteger(POSITION_IDENTIFIER) == g_riallineaId);
      if(appenaAperta)
         g_riallineaId = 0;
      if(!mancano && !(appenaAperta && spostati))
         continue;
      if(!LivelliValidi(tipo == 0, sl, tp, tick))
        {
         Log("SL " + Px(sl) + " / TP " + Px(tp) + " non piu' validi rispetto al prezzo attuale: livelli lasciati invariati");
         continue;
        }
      if(ImpostaLivelli(t, sl, tp))
         Log("SL/TP della posizione #" + IntegerToString((long)t) + " impostati a " + Px(sl) + " / " + Px(tp)
             + " (ingresso " + Px(ingresso) + ")");
     }
  }

bool ChiudiPosizione(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return true;
   MqlTick tick;
   if(!SymbolInfoTick(InpSimbolo, tick))
     {
      Ritenta();
      return false;
     }
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = InpSimbolo;
   req.position = ticket;
   req.volume = PositionGetDouble(POSITION_VOLUME);
   req.magic = (ulong)InpMagic;
   req.deviation = (ulong)InpDeviazionePunti;
   req.type_filling = Riempimento();
   req.comment = InpCommento + " incrocio opposto";
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
   bool ok = OrderSend(req, res);
   if(ok && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL))
     {
      g_ultimoChiuso = ticket;
      Log("Posizione #" + IntegerToString((long)ticket) + " chiusa per incrocio opposto a " + Px(res.price));
      return true;
     }
   Log("Chiusura della posizione #" + IntegerToString((long)ticket) + " non riuscita: " + DescrizioneRetcode(res.retcode)
       + " '" + res.comment + "'. Riprovo.");
   Ritenta();
   return false;
  }

// Restituisce true quando il segnale non richiede altri tentativi.
bool InviaApertura(const int dir, const datetime barra)
  {
   MqlTick tick;
   if(!SymbolInfoTick(InpSimbolo, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
     {
      Ritenta();
      return false;
     }
   bool buy = (dir > 0);
   int tipo = 1;
   double prezzo = tick.bid;
   if(buy)
     {
      tipo = 0;
      prezzo = tick.ask;
     }
   double sl = 0.0;
   double tp = 0.0;
   LivelliDaIngresso(tipo, prezzo, sl, tp);
   if(!LivelliValidi(buy, sl, tp, tick))
     {
      Log("SL " + Px(sl) + " / TP " + Px(tp) + " sotto il livello minimo del broker: riprovo");
      Ritenta();
      return false;
     }
   MqlTradeRequest req;
   MqlTradeResult res;
   MqlTradeCheckResult chk;
   ZeroMemory(req);
   ZeroMemory(res);
   ZeroMemory(chk);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = InpSimbolo;
   req.volume = InpLotti;
   req.type = ORDER_TYPE_SELL;
   if(buy)
      req.type = ORDER_TYPE_BUY;
   req.price = prezzo;
   req.sl = sl;
   req.tp = tp;
   req.deviation = (ulong)InpDeviazionePunti;
   req.type_filling = Riempimento();
   req.type_time = ORDER_TIME_GTC;
   req.magic = (ulong)InpMagic;
   req.comment = InpCommento;
   if(!OrderCheck(req, chk))
     {
      Log("OrderCheck non superato: " + DescrizioneRetcode(chk.retcode) + " '" + chk.comment + "'");
      Ritenta();
      return false;
     }
   Log("Invio " + Lato(dir) + " " + DoubleToString(InpLotti, 2) + " " + InpSimbolo + " a " + Px(prezzo) + " SL " + Px(sl) + " TP " + Px(tp));
   bool ok = OrderSend(req, res);
   uint rc = res.retcode;
   if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL)
     {
      GlobalVariableSet(g_nomeGV, (double)barra);
      Log("Aperto " + Lato(dir) + " ordine " + IntegerToString((long)res.order) + " a " + Px(res.price)
          + ", volume " + DoubleToString(res.volume, 2));
      g_riallineaId = (long)res.order;          // in hedging l'identificativo della posizione = ticket dell'ordine
      g_riallineaScadenzaMs = OraMs() + 30000;
      VerificaLivelli();
      return true;
     }
   if(RifiutoCerto(rc) || (!ok && rc == 0))
     {
      Log("Apertura rifiutata: " + DescrizioneRetcode(rc) + " '" + res.comment + "'. Riprovo entro "
          + IntegerToString(InpMaxRitardoSegnaleSec) + " s dall'apertura della candela");
      Ritenta();
      return false;
     }
   GlobalVariableSet(g_nomeGV, (double)barra);   // esito incerto: mai un secondo invio sulla stessa candela
   Log("Esito incerto dell'apertura: " + DescrizioneRetcode(rc) + " '" + res.comment + "'. Nessun nuovo invio su questa candela");
   return true;
  }

// Restituisce true quando l'apertura e' fatta o non e' ammessa dalle regole.
bool TentaApertura(const int dir, const datetime barra)
  {
   ulong ticket = 0;
   int tipo = -1;
   int n = PosizioniBot(ticket, tipo);
   if(n > 0)
     {
      if((tipo == 0 && dir > 0) || (tipo == 1 && dir < 0))
         Log("Incrocio " + Lato(dir) + ": posizione gia' aperta nella stessa direzione, nessun nuovo ordine");
      else
         Log("Incrocio " + Lato(dir) + ": posizione opposta ancora aperta, nessun nuovo ordine");
      return true;
     }
   if(GlobalVariableCheck(g_nomeGV) && (long)GlobalVariableGet(g_nomeGV) == (long)barra)
     {
      Log("Incrocio " + Lato(dir) + ": su questa candela e' gia' stato aperto un trade");
      return true;
     }
   datetime ora = UtcOra();
   if(InpSoloInSessione && !InSessione(ora))
     {
      Log("Incrocio " + Lato(dir) + " fuori dalla finestra 15:30-17:30 Europe/Rome (" + OraRoma(ora) + "): nessuna apertura");
      return true;
     }
   if(InpMaxTradeGiorno > 0)
     {
      int oggi = TradeOggi();
      if(oggi >= InpMaxTradeGiorno)
        {
         Log("Incrocio " + Lato(dir) + ": gia' " + IntegerToString(oggi) + " trade oggi (massimo " + IntegerToString(InpMaxTradeGiorno) + ")");
         return true;
        }
     }
   return InviaApertura(dir, barra);
  }

void Ciclo()
  {
   if(!g_attivo)
      return;
   VerificaLivelli();
   datetime barra0 = iTime(InpSimbolo, PERIOD_M15, 0);
   if(barra0 <= 0)
      return;
   if(barra0 != g_barraSegnale)
     {
      int dir = 0;
      if(!IncrocioUltimaChiusa(dir))
        {
         AggiornaGrafico("in attesa delle candele M15");
         return;
        }
      g_barraSegnale = barra0;
      g_dirSegnale = dir;
      g_aperturaFatta = (dir == 0);
      g_ultimoChiuso = 0;
      if(dir != 0)
        {
         string verso = "ribassista";
         if(dir > 0)
            verso = "rialzista";
         Log("Incrocio WaveTrend " + verso + " confermato sulla M15 chiusa delle "
             + TimeToString((datetime)((long)barra0 - 900), TIME_DATE | TIME_MINUTES) + " (ora server): segnale " + Lato(dir));
         ulong ticket = 0;
         int tipo = -1;
         if(InpChiudiSuIncrocioOpposto && PosizioniBot(ticket, tipo) > 0
            && ((tipo == 0 && dir < 0) || (tipo == 1 && dir > 0)))
            g_daChiudere = ticket;
        }
     }
   // la chiusura sull'incrocio opposto non scade e vale anche fuori orario
   if(g_daChiudere != 0)
     {
      if(!PositionSelectByTicket(g_daChiudere))
         g_daChiudere = 0;
      else
        {
         if(!PuoiTentare())
            return;
         if(!ChiudiPosizione(g_daChiudere))
            return;
         g_daChiudere = 0;
        }
     }
   if(g_aperturaFatta)
     {
      AggiornaGrafico("in attesa del prossimo incrocio confermato (ultimo controllo: candela delle "
                      + TimeToString(barra0, TIME_DATE | TIME_MINUTES) + " server)");
      return;
     }
   long ritardo = (long)TimeCurrent() - (long)barra0;
   if(ritardo > InpMaxRitardoSegnaleSec)
     {
      Log("Segnale " + Lato(g_dirSegnale) + " scaduto: la candela e' iniziata da " + IntegerToString(ritardo) + " s");
      g_aperturaFatta = true;
      return;
     }
   if(!PuoiTentare())
      return;
   g_aperturaFatta = TentaApertura(g_dirSegnale, barra0);
  }

//+------------------------------------------------------------------+
//| Eventi                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tester = (MQLInfoInteger(MQL_TESTER) != 0);
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(!g_tester)
     {
      if(InpConto100k <= 0)
        {
         Print("Impostare InpConto100k con il login del conto 100k: protegge dal caricamento per errore su un altro conto");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(login != InpConto100k)
        {
         Print("Login ", IntegerToString(login), " diverso da InpConto100k (", IntegerToString(InpConto100k), "): WT67ercole non parte");
         return INIT_FAILED;
        }
     }
   if(!SymbolSelect(InpSimbolo, true))
     {
      Print("Simbolo ", InpSimbolo, " non disponibile");
      return INIT_FAILED;
     }
   if(!VolumeValido(InpLotti))
     {
      Print("Volume ", DoubleToString(InpLotti, 2), " non ammesso dal broker su ", InpSimbolo);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpDistanzaSL <= 0.0 || InpDistanzaTP <= 0.0)
     {
      Print("Le distanze di SL e TP devono essere positive");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_nomeGV = "WT67ercole_" + IntegerToString(login) + "_" + IntegerToString(InpMagic) + "_ultima_apertura";
   g_barraSegnale = 0;
   g_aperturaFatta = true;
   g_daChiudere = 0;
   g_ultimoChiuso = 0;
   g_attivo = true;
   EventSetTimer(1);
   Log("WT67ercole avviato su " + InpSimbolo + " M15: " + DoubleToString(InpLotti, 2) + " lotti, SL " + DoubleToString(InpDistanzaSL, 2)
       + ", TP " + DoubleToString(InpDistanzaTP, 2) + ", magic " + IntegerToString(InpMagic)
       + (InpSoloInSessione ? ", aperture 15:30-17:30 Europe/Rome" : ", aperture a qualsiasi ora")
       + ", massimo " + IntegerToString(InpMaxTradeGiorno) + " al giorno");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
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
