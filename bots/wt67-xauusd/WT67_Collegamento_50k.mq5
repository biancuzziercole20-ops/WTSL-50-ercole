// Collegamento locale per WT67ercole.mq5 v1.20 (XAUUSD, WaveTrend M15).
// Installare questo stesso EA in due terminali MT5 dello stesso utente Windows.
// Compilare con F7. In entrambe le istanze impostare gli stessi due login.
// Sul 100k usare un secondo grafico dell'oro: il WT67 originale genera i trade.
// Se il WT67 gira altrove basta una sessione locale in lettura sul suo conto.
// Sul 50k usare il grafico dell'oro del proprio broker e abilitare Algo Trading.
// Sul grafico e nella scheda Experts e' indicato lo stato del collegamento.
//
// Il 100k pubblica solo posizioni MT5 effettive del magic WT67. La copia
// richiede contemporaneamente -5.00 di quotazione e almeno -500 di P/L aperto
// sul 100k nominale. Sul 50k l'Ask BUY / Bid SELL deve rendere possibili
// -250/+750 lordi ai prezzi SL/TP del 100k. Un salto di prezzo fa attendere
// un ritorno al livello finche' le condizioni sono valide. Nessun pendente.
// Una sola richiesta accettata per trade sorgente. Orari Europe/Rome.
// In apertura si richiede l'intero volume (Fill or Kill). Commissioni, swap,
// slippage e uscite anticipate possono cambiare gli importi effettivi.
// Le cifre sono espresse nelle rispettive valute dei conti.
#property strict
#property version "1.00"
#property description "WT67 | Collegamento locale 100k - 50k su XAUUSD"
#include <Trade\Trade.mqh>

input long  InpConto100k = 0;
input long  InpConto50k  = 0;
input ulong InpMagic100k = 670067;
input ulong InpMagic50k  = 670050;

const double LOTS_50K = 0.50;
const double ADVERSE_MOVE = 5.00;
const double LOSS_100K = 100000.0 * 0.005;
const double STOP_50K = 250.0;
const double TARGET_50K = 750.0;
const double MONEY_EPS = 0.0050001; // arrotondamento a un centesimo
const int MAX_DAILY_ENTRIES = 4;
const int WIRE_VERSION = 670501;
enum SourceState { SOURCE_UNAVAILABLE = 0, SOURCE_FLAT = 1, SOURCE_OPEN = 2 };

struct Binding
  {
   long id;                        // POSITION_IDENTIFIER del 100k, mai convertito in double
   int side;                       // 1 BUY, -1 SELL
  };

struct Snapshot
  {
   int version;
   long sourceLogin, targetLogin;
   ulong sourceMagic;
   datetime sentUtc, openedUtc;
   ulong sentMs;                   // uptime di Windows, comune ai due processi
   int state, side;
   long id;
   double entry, mark, floating, sl, tp;
   long closedId;                  // chiusura del trade copiato confermata dallo storico del 100k
   int closedSide;
  };

CTrade trade;
string prefix, framePath, bindPath, roleText, lastStatus;
bool isSource = false;
int roleLock = INVALID_HANDLE;
Snapshot lastSent;
Binding confirmedClose;
ulong lastCloseCheck = 0, nextRequest = 0, nextActivation = 0;

void Status(const string message)
  {
   if(message == lastStatus) return;
   lastStatus = message;
   Comment("WT67 | ", roleText, "\n", message);
  }

bool IsGoldUsd()
  {
   string name = _Symbol;
   StringToUpper(name);
   return SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT) == "USD"
          && (SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE) == "XAU"
              || StringFind(name, "XAUUSD") >= 0);
  }

// Ultima domenica di marzo/ottobre alle 01:00 UTC, come nel WT67 allegato.
datetime LastSundayUtc(const int year, const int month)
  {
   MqlDateTime d = {};
   d.year = year; d.mon = month; d.day = 31; d.hour = 1;
   datetime last = StructToTime(d);
   TimeToStruct(last, d);
   return last - d.day_of_week * 86400;
  }
int RomeOffset(const datetime utc)
  {
   MqlDateTime d = {};
   TimeToStruct(utc, d);
   return utc >= LastSundayUtc(d.year, 3) && utc < LastSundayUtc(d.year, 10) ? 7200 : 3600;
  }
bool InTodaysWindow(const datetime openedUtc, const datetime nowUtc)
  {
   if(openedUtc <= 0 || openedUtc > nowUtc + 1) return false;
   long nowRome = (long)nowUtc + RomeOffset(nowUtc);
   long openRome = (long)openedUtc + RomeOffset(openedUtc);
   long start = nowRome - nowRome % 86400 + 15 * 3600 + 30 * 60;
   long end = start + 2 * 3600;
   return openRome >= start && openRome < end && nowRome >= start && nowRome < end;
  }
long ServerOffset(const datetime server, const datetime utc)
  {
   return (long)MathRound((double)(server - utc) / 900.0) * 900;
  }
bool FreshTick(MqlTick &q)
  {
   if(!SymbolInfoTick(_Symbol, q) || q.time <= 0 || q.bid <= 0 || q.ask < q.bid) return false;
   long age = (long)TimeTradeServer() - (long)q.time;
   return age >= -1 && age <= 4;
  }
bool ReadyTerminal()
  {
   return TerminalInfoInteger(TERMINAL_CONNECTED) && SymbolIsSynchronized(_Symbol);
  }
bool CanTrade()
  {
   return AccountInfoInteger(ACCOUNT_LOGIN) == InpConto50k && ReadyTerminal()
          && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT)
          && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
  }
bool IsBuy(const int side) { return side == 1; }
string SideText(const int side) { return IsBuy(side) ? "BUY" : "SELL"; }
string Tag(const long id, const int side)
  {
   return (IsBuy(side) ? "WT67B-" : "WT67S-") + IntegerToString(id);
  }
bool SameTrade(const Binding &b, const Snapshot &s)
  {
   return s.state == SOURCE_OPEN && b.id == s.id && b.side == s.side;
  }
bool Triggered(const Snapshot &s)
  {
   if(s.state != SOURCE_OPEN || (s.side != 1 && s.side != -1) || s.id <= 0
      || s.entry <= 0 || s.mark <= 0 || s.tp <= 0 || s.sl <= 0) return false;
   if(s.side * (s.mark - s.sl) <= 0 || s.side * (s.tp - s.mark) <= 0) return false;
   return s.side * (s.entry - s.mark) + 1e-8 >= ADVERSE_MOVE
          && s.floating <= -LOSS_100K + MONEY_EPS;
  }

bool ReadBinding(Binding &b)
  {
   int f = FileOpen(bindPath, FILE_COMMON | FILE_BIN | FILE_READ | FILE_SHARE_READ);
   if(f == INVALID_HANDLE) return false;
   bool ok = FileSize(f) == sizeof(b) && FileReadStruct(f, b) == sizeof(b);
   FileClose(f);
   return ok && b.id > 0 && (b.side == 1 || b.side == -1);
  }
bool SaveBinding(const Binding &b)
  {
   string tmp = bindPath + ".new";
   int f = FileOpen(tmp, FILE_COMMON | FILE_BIN | FILE_WRITE);
   if(f == INVALID_HANDLE) return false;
   bool ok = FileWriteStruct(f, b) == sizeof(b);
   FileFlush(f);
   FileClose(f);
   return ok && FileMove(tmp, FILE_COMMON, bindPath, FILE_COMMON | FILE_REWRITE);
  }
bool Publish(Snapshot &s)
  {
   s.version = WIRE_VERSION; s.sourceLogin = InpConto100k; s.targetLogin = InpConto50k;
   s.sourceMagic = InpMagic100k; s.sentUtc = TimeGMT(); s.sentMs = GetTickCount64();
   string tmp = framePath + ".new";
   int f = FileOpen(tmp, FILE_COMMON | FILE_BIN | FILE_WRITE);
   if(f == INVALID_HANDLE) return false;
   bool ok = FileWriteStruct(f, s) == sizeof(s);
   FileClose(f);
   if(!ok || !FileMove(tmp, FILE_COMMON, framePath, FILE_COMMON | FILE_REWRITE)) return false;
   lastSent = s;
   return true;
  }
bool ReadSnapshot(Snapshot &s)
  {
   int f = FileOpen(framePath, FILE_COMMON | FILE_BIN | FILE_READ | FILE_SHARE_READ);
   if(f == INVALID_HANDLE) return false;
   bool ok = FileSize(f) == sizeof(s) && FileReadStruct(f, s) == sizeof(s);
   FileClose(f);
   ulong now = GetTickCount64();
   long age = (long)TimeGMT() - (long)s.sentUtc;
   return ok && s.version == WIRE_VERSION && s.sourceLogin == InpConto100k
          && s.targetLogin == InpConto50k && s.sourceMagic == InpMagic100k
          && age >= 0 && age <= 3 && now >= s.sentMs && now - s.sentMs <= 2000
          && (s.state == SOURCE_FLAT || s.state == SOURCE_OPEN);
  }

// Un terminale scollegato o uno storico incompleto non equivalgono a una chiusura.
bool ClosedInHistory(const Binding &b)
  {
   if(!HistorySelectByPosition(b.id)) return false;
   double net = 0;
   bool ownEntry = false, exitSeen = false;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) return false;
      long type = HistoryDealGetInteger(d, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      int side = type == DEAL_TYPE_BUY ? 1 : -1;
      net += side * HistoryDealGetDouble(d, DEAL_VOLUME);
      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      if((entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT) && side == b.side
         && (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) == InpMagic100k) ownEntry = true;
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT) exitSeen = true;
     }
   return ownEntry && exitSeen && net * b.side <= 1e-8;
  }
void CheckSourceClose(Snapshot &s)
  {
   ulong now = GetTickCount64();
   if(lastCloseCheck == 0 || now - lastCloseCheck >= 400)
     {
      lastCloseCheck = now;
      Binding b = {};
      if(ReadBinding(b) && !SameTrade(b, s)
         && (b.id != confirmedClose.id || b.side != confirmedClose.side) && ClosedInHistory(b))
         confirmedClose = b;
     }
   s.closedId = confirmedClose.id; s.closedSide = confirmedClose.side;
  }
void SourceSnapshot(Snapshot &s)
  {
   MqlTick q;
   if(!ReadyTerminal() || !FreshTick(q)) return;
   s.state = SOURCE_FLAT;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) { s.state = SOURCE_UNAVAILABLE; return; }
      if(PositionGetString(POSITION_SYMBOL) != _Symbol
         || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic100k
         || PositionGetInteger(POSITION_REASON) != POSITION_REASON_EXPERT) continue;
      if(s.state == SOURCE_OPEN) { s.state = SOURCE_UNAVAILABLE; return; }
      s.state = SOURCE_OPEN;
      s.id = PositionGetInteger(POSITION_IDENTIFIER);
      s.side = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      s.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      s.mark = IsBuy(s.side) ? q.bid : q.ask;
      s.floating = PositionGetDouble(POSITION_PROFIT);
      s.sl = PositionGetDouble(POSITION_SL); s.tp = PositionGetDouble(POSITION_TP);
      s.openedUtc = (datetime)(PositionGetInteger(POSITION_TIME) - ServerOffset(TimeTradeServer(), TimeGMT()));
     }
   CheckSourceClose(s);
  }
void SourceCycle()
  {
   Snapshot s = {};
   SourceSnapshot(s);
   bool changed = s.state != lastSent.state || s.id != lastSent.id || s.side != lastSent.side
                  || s.entry != lastSent.entry || s.sl != lastSent.sl || s.tp != lastSent.tp
                  || s.closedId != lastSent.closedId || s.closedSide != lastSent.closedSide
                  || Triggered(s) != Triggered(lastSent);
   if(!changed && lastSent.version == WIRE_VERSION && GetTickCount64() - lastSent.sentMs < 500) return;
   if(!Publish(s)) { Status("Scrittura del collegamento in attesa."); return; }
   if(s.state == SOURCE_UNAVAILABLE) Status("In attesa di dati coerenti dal 100k.");
   else if(s.state == SOURCE_FLAT) Status("In ascolto. Nessuna posizione WT67 aperta.");
   else Status(StringFormat("WT67 %s #%I64d | P/L %.2f | soglia %s",
                            SideText(s.side), s.id, s.floating, Triggered(s) ? "raggiunta" : "in attesa"));
  }

bool OnGrid(const double price, const double step)
  {
   return step > 0 && MathAbs(price - MathRound(price / step) * step) <= step * 1e-6;
  }
bool VolumeSupported()
  {
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return vmin > 0 && LOTS_50K >= vmin - 1e-9 && LOTS_50K <= vmax + 1e-9
          && OnGrid(LOTS_50K - vmin, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
  }
bool StopsUsable(const Snapshot &s, const MqlTick &q, const bool modification)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(s.sl <= 0 || s.tp <= 0 || !OnGrid(s.sl, tickSize) || !OnGrid(s.tp, tickSize)) return false;
   long points = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(modification)
     {
      long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      if(freeze > points) points = freeze;
     }
   double minDist = points * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double exitQuote = IsBuy(s.side) ? q.bid : q.ask;
   double toSl = s.side * (exitQuote - s.sl), toTp = s.side * (s.tp - exitQuote);
   return toSl > 0 && toTp > 0 && toSl + 1e-8 >= minDist && toTp + 1e-8 >= minDist;
  }
bool PlannedAmounts(const Snapshot &s, const double volume, const double price, double &loss, double &gain)
  {
   ENUM_ORDER_TYPE type = IsBuy(s.side) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   return OrderCalcProfit(type, _Symbol, volume, price, s.sl, loss)
          && OrderCalcProfit(type, _Symbol, volume, price, s.tp, gain);
  }
bool EntryQuote(const Snapshot &s, double &price, string &reason)
  {
   if(!Triggered(s)) { reason = "In attesa di -5,00 e di -500 sul trade WT67 del 100k."; return false; }
   if(!InTodaysWindow(s.openedUtc, TimeGMT())) { reason = "Fuori sessione o trade di una sessione precedente."; return false; }
   MqlTick q;
   if(!FreshTick(q)) { reason = "In attesa di una quotazione aggiornata del 50k."; return false; }
   if(!StopsUsable(s, q, false)) { reason = "SL/TP del 100k non eseguibili sul 50k a questo prezzo."; return false; }
   price = IsBuy(s.side) ? q.ask : q.bid;
   double loss, gain;
   if(!PlannedAmounts(s, LOTS_50K, price, loss, gain)) { reason = "Valore del contratto non disponibile."; return false; }
   if(MathAbs(loss + STOP_50K) > MONEY_EPS || MathAbs(gain - TARGET_50K) > MONEY_EPS)
     {
      reason = StringFormat("Soglia 100k raggiunta. Al prezzo 50k %.3f: SL %.2f / TP %.2f. Attesa -250/+750.",
                            price, loss, gain);
      return false;
     }
   return true;
  }

// Controllo anche sullo storico del broker, per riavvii e trasferimenti
// di terminale. Esecuzioni parziali dello stesso ordine contano una volta.
bool HistoryAllowsEntry(const string tag, string &reason)
  {
   datetime utc = TimeGMT(), server = TimeTradeServer();
   long rome = (long)utc + RomeOffset(utc);
   long midnight = rome - rome % 86400;
   datetime from = (datetime)(midnight - RomeOffset((datetime)(midnight - 7200)) + ServerOffset(server, utc));
   if(!HistorySelect(from, server + 60)) { reason = "Storico del 50k non ancora disponibile."; return false; }
   ulong counted[4] = {};
   int n = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) { reason = "Storico del 50k in aggiornamento."; return false; }
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic50k || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      if(HistoryDealGetString(d, DEAL_COMMENT) == tag) { reason = "Trade del 100k gia' copiato."; return false; }
      ulong order = (ulong)HistoryDealGetInteger(d, DEAL_ORDER);
      bool seen = false;
      for(int j = 0; j < n; j++) if(counted[j] == order) seen = true;
      if(!seen) counted[n++] = order;
      if(n >= MAX_DAILY_ENTRIES) { reason = "Raggiunte 4 aperture oggi (ora italiana)."; return false; }
     }
   return true;
  }
bool IsNetting() { return AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; }
bool BusyOrder(const bool netting)
  {
   for(int i = OrdersTotal() - 1; i >= 0; --i)
     {
      if(OrderGetTicket(i) == 0) return true;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && (netting || (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic50k)) return true;
     }
   return false;
  }
bool InspectExposure(const bool netting, ulong &ownTicket, string &reason)
  {
   ownTicket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) { reason = "Posizioni del 50k in aggiornamento."; return false; }
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic50k)
        {
         if(ownTicket != 0) { reason = "Piu' posizioni sul magic 50k. Verificare che sia dedicato."; return false; }
         ownTicket = ticket;
        }
      else if(netting) { reason = "Posizione netting di altra origine sul simbolo del 50k."; return false; }
     }
   if(BusyOrder(netting && ownTicket == 0)) { reason = "Ordine gia' presente sul simbolo. Attesa esito."; return false; }
   return true;
  }
bool SelectFilling(const bool wholeEntry)
  {
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   long allowed = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(mode == SYMBOL_TRADE_EXECUTION_REQUEST || mode == SYMBOL_TRADE_EXECUTION_INSTANT || (allowed & SYMBOL_FILLING_FOK) != 0)
     { trade.SetTypeFilling(ORDER_FILLING_FOK); return true; }
   if(wholeEntry) return false;
   if(trade.SetTypeFillingBySymbol(_Symbol)) return true;
   if(mode == SYMBOL_TRADE_EXECUTION_EXCHANGE) { trade.SetTypeFilling(ORDER_FILLING_RETURN); return true; }
   return false;
  }
bool PositiveReply(const uint code)
  {
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_PLACED;
  }
bool DefiniteRejection(const uint code)
  {
   switch(code)
     {
      case TRADE_RETCODE_REQUOTE: case TRADE_RETCODE_REJECT: case TRADE_RETCODE_CANCEL:
      case TRADE_RETCODE_INVALID: case TRADE_RETCODE_INVALID_VOLUME: case TRADE_RETCODE_INVALID_PRICE:
      case TRADE_RETCODE_INVALID_STOPS: case TRADE_RETCODE_TRADE_DISABLED: case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_NO_MONEY: case TRADE_RETCODE_PRICE_CHANGED: case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_TOO_MANY_REQUESTS: case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_CLIENT_DISABLES_AT: case TRADE_RETCODE_SERVER_DISABLES_AT: return true;
     }
   return false;
  }
// La ricevuta viene chiusa e scritta su disco PRIMA dell'ordine: nessun
// secondo invio dopo riavvio, timeout o fill seguito subito da uno stop.
bool Reserve(const string receipt, const Binding &b)
  {
   if(FileIsExist(receipt, FILE_COMMON) || !SaveBinding(b)) return false;
   int f = FileOpen(receipt, FILE_COMMON | FILE_BIN | FILE_WRITE);
   if(f == INVALID_HANDLE) return false;
   bool ok = FileWriteStruct(f, b) == sizeof(b);
   FileFlush(f);
   FileClose(f);
   if(!ok) FileDelete(receipt, FILE_COMMON);
   return ok;
  }
void TryOpen(const Snapshot &s)
  {
   string why;
   double price = 0;
   if(!EntryQuote(s, price, why)) { Status(why); return; }
   if(!VolumeSupported()) { Status("Il broker non ammette il volume esatto di 0,50 lotti."); return; }
   if(!SelectFilling(true)) { Status("Il broker non supporta l'esecuzione integrale di 0,50 lotti con Fill or Kill."); return; }
   string tag = Tag(s.id, s.side), receipt = prefix + "_" + tag + ".used";
   if(FileIsExist(receipt, FILE_COMMON)) { Status("Trade gia' inviato per questa posizione del 100k."); return; }
   if(!HistoryAllowsEntry(tag, why)) { Status(why); return; }
   Binding b = {}; b.id = s.id; b.side = s.side;
   if(!Reserve(receipt, b)) { Status("Registro ordini occupato o non disponibile."); return; }
   // Lo storico e il disco possono impiegare tempo. Rilegge entrambi i feed.
   Snapshot fresh = {};
   ulong existing = 0;
   if(!InspectExposure(IsNetting(), existing, why) || existing != 0
      || !ReadSnapshot(fresh) || !SameTrade(b, fresh) || !CanTrade() || !EntryQuote(fresh, price, why))
     { FileDelete(receipt, FILE_COMMON); Status("Condizioni cambiate prima dell'invio. In attesa."); return; }
   trade.SetDeviationInPoints(0);
   ENUM_ORDER_TYPE type = IsBuy(b.side) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   bool sent = trade.PositionOpen(_Symbol, type, LOTS_50K, price, fresh.sl, fresh.tp, tag);
   uint code = trade.ResultRetcode();
   nextRequest = GetTickCount64() + 1000;
   PrintFormat("50k %s | richiesta %.2f a %.5f, SL %.5f, TP %.5f | inviata=%d, retcode=%u (%s), ordine=%I64u",
               tag, LOTS_50K, price, fresh.sl, fresh.tp, (int)sent, code, trade.ResultRetcodeDescription(), trade.ResultOrder());
   if(!PositiveReply(code))
     {
      if(DefiniteRejection(code)) FileDelete(receipt, FILE_COMMON);
      else Print("Esito incerto. Ricevuta conservata per evitare un doppio ingresso sullo stesso trade.");
      return;
     }
   double fill = trade.ResultPrice(), volume = trade.ResultVolume(), loss, gain;
   if(fill > 0 && volume > 0 && PlannedAmounts(fresh, volume, fill, loss, gain))
      PrintFormat("Esecuzione comunicata: %.2f lotti a %.5f; SL %.2f / TP %.2f %s lordi.",
                  volume, fill, loss, gain, AccountInfoString(ACCOUNT_CURRENCY));
  }

bool NetPositionIsOurs(const long localId)
  {
   if(!HistorySelectByPosition(localId)) return false;
   bool found = false;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) return false;
      long e = HistoryDealGetInteger(d, DEAL_ENTRY), t = HistoryDealGetInteger(d, DEAL_TYPE);
      if((t != DEAL_TYPE_BUY && t != DEAL_TYPE_SELL) || (e != DEAL_ENTRY_IN && e != DEAL_ENTRY_INOUT)) continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic50k) return false;
      found = true;
     }
   return found;
  }
bool PositionBinding(const string comment, const int side, Binding &b)
  {
   // Alcuni broker cambiano il commento della posizione: il legame salvato
   // prima dell'ordine resta valido poiche' la copia possiede una posizione per volta.
   Binding saved = {};
   bool have = ReadBinding(saved);
   string head = IsBuy(side) ? "WT67B-" : "WT67S-";
   if(StringFind(comment, head) == 0)
     {
      long id = StringToInteger(StringSubstr(comment, StringLen(head)));
      if(id > 0)
        {
         b.id = id; b.side = side;
         if(have && saved.id == id && saved.side == side) return true;
         return SaveBinding(b);
        }
     }
   if(!have || saved.side != side) return false;
   b = saved;
   return true;
  }
void ManagePosition(const ulong ticket, const Snapshot &s, const bool netting)
  {
   if(!PositionSelectByTicket(ticket)) return;
   long localId = PositionGetInteger(POSITION_IDENTIFIER);
   int side = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   Binding b = {};
   if(!PositionBinding(PositionGetString(POSITION_COMMENT), side, b)) { Status("Associazione al trade del 100k da verificare."); return; }
   bool close = s.closedId == b.id && s.closedSide == b.side && !SameTrade(b, s);
   bool modify = SameTrade(b, s) && (MathAbs(s.sl - sl) > 1e-8 || MathAbs(s.tp - tp) > 1e-8);
   if(!close && !modify)
     { Status(SameTrade(b, s) ? "Posizione collegata, SL e TP sul broker." : "Posizione aperta. Attesa conferma di chiusura dal 100k."); return; }
   if(!CanTrade() || !SelectFilling(false)) { Status("Verificare il permesso Algo Trading e l'esecuzione sul 50k."); return; }
   if(netting && !NetPositionIsOurs(localId)) { Status("Posizione netting condivisa o storico non pronto."); return; }
   MqlTick q;
   if(!FreshTick(q) || (!close && !StopsUsable(s, q, true))) { Status("In attesa di quotazione o livelli validi."); return; }
   trade.SetDeviationInPoints(30); // impostazione di chiusura del WT67
   bool sent;
   if(close) sent = trade.PositionClose(ticket);
   else      sent = trade.PositionModify(ticket, s.sl, s.tp);
   nextRequest = GetTickCount64() + 1000;
   PrintFormat("50k #%I64u %s: inviata=%d, retcode=%u (%s).", ticket, close ? "chiusura su uscita 100k" : "aggiornamento SL/TP",
               (int)sent, trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }
void FollowerCycle()
  {
   if(!ReadyTerminal()) { Status("50k in attesa della connessione al broker."); return; }
   Snapshot s = {};
   if(!ReadSnapshot(s)) { Status("Attesa del 100k e di dati recenti. Gli SL/TP gia' inseriti restano al broker."); return; }
   if(GetTickCount64() < nextRequest) return;
   bool netting = IsNetting();
   ulong ticket = 0;
   string why;
   if(!InspectExposure(netting, ticket, why)) { Status(why); return; }
   if(ticket != 0) { ManagePosition(ticket, s, netting); return; }
   if(s.state == SOURCE_FLAT) { Status("Collegato. In attesa di un trade WT67 sul 100k."); return; }
   if(!CanTrade()) { Status("Collegato. Per operare il 50k richiede Algo Trading e accesso operativo."); return; }
   TryOpen(s);
  }
int ActivateRole()
  {
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(login != InpConto100k && login != InpConto50k)
     { Print("Il login attivo non corrisponde a nessuno dei due conti configurati."); return INIT_PARAMETERS_INCORRECT; }
   if(!IsGoldUsd()) { Print("Applicare l'EA al grafico dell'oro quotato in USD del conto (XAUUSD)."); return INIT_FAILED; }
   isSource = login == InpConto100k;
   roleText = isSource ? "100k, lettura" : "50k, ricezione";
   prefix = StringFormat("WT67_Link\\%I64d_%I64d_%I64u_%I64u", InpConto100k, InpConto50k, InpMagic100k, InpMagic50k);
   framePath = prefix + ".frame"; bindPath = prefix + ".binding";
   string lockName = isSource ? prefix + ".sender.lock" : StringFormat("WT67_Link\\recv_%I64d_%I64u.lock", InpConto50k, InpMagic50k);
   roleLock = FileOpen(lockName, FILE_COMMON | FILE_BIN | FILE_READ | FILE_WRITE);
   if(roleLock == INVALID_HANDLE) { Print("Ruolo gia' in uso o cartella condivisa non accessibile. Errore ", GetLastError()); return INIT_FAILED; }
   trade.SetExpertMagicNumber(InpMagic50k);
   trade.SetAsyncMode(false);
   PrintFormat("WT67 | %s | %s | valuta %s | contratto %.2f | cartella comune %s", roleText, _Symbol,
               AccountInfoString(ACCOUNT_CURRENCY), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               TerminalInfoString(TERMINAL_COMMONDATA_PATH));
   return INIT_SUCCEEDED;
  }
bool ReadyToActivate()
  {
   return AccountInfoInteger(ACCOUNT_LOGIN) > 0 && ReadyTerminal() && SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT) != "";
  }
void Run()
  {
   if(roleLock == INVALID_HANDLE)
     {
      if(!ReadyToActivate() || GetTickCount64() < nextActivation) return;
      nextActivation = GetTickCount64() + 5000;
      if(ActivateRole() != INIT_SUCCEEDED) { Status("Controllare il login, il grafico e la scheda Experts."); return; }
     }
   if(AccountInfoInteger(ACCOUNT_LOGIN) != (isSource ? InpConto100k : InpConto50k)) return;
   if(isSource) SourceCycle(); else FollowerCycle();
  }
int OnInit()
  {
   if(MQLInfoInteger(MQL_TESTER)) { Print("Il collegamento richiede due terminali MT5. Usare conti demo per la prova integrata."); return INIT_FAILED; }
   if(InpConto100k <= 0 || InpConto50k <= 0 || InpConto100k == InpConto50k)
     { Print("Inserire in entrambi i terminali i due numeri conto distinti, negli stessi campi."); return INIT_PARAMETERS_INCORRECT; }
   if(InpMagic100k == 0 || InpMagic50k == 0 || InpMagic100k == InpMagic50k)
     { Print("Occorrono magic distinti e dedicati. Usare sul 100k il magic del WT67."); return INIT_PARAMETERS_INCORRECT; }
   ZeroMemory(lastSent); ZeroMemory(confirmedClose);
   lastCloseCheck = 0; nextRequest = 0; nextActivation = 0; lastStatus = "";
   if(!EventSetMillisecondTimer(200)) { Print("Timer non disponibile. Errore ", GetLastError()); return INIT_FAILED; }
   if(!ReadyToActivate())
     { roleText = "avvio"; Status("In attesa della connessione MT5 e delle specifiche del simbolo."); return INIT_SUCCEEDED; }
   int result = ActivateRole();
   if(result != INIT_SUCCEEDED) return result;
   Run();
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(roleLock != INVALID_HANDLE)
     {
      if(isSource) { Snapshot s = {}; Publish(s); }
      FileClose(roleLock); roleLock = INVALID_HANDLE;
     }
   Comment("");
  }
void OnTick()  { Run(); }
void OnTimer() { Run(); }
