// Simulatore minimo dell'API MQL5 usata da WTSL-50%ercole.mq5.
// Permette di compilare il sorgente .mq5 reale con g++ (dentro una struct,
// una istanza per terminale) e di pilotarlo con due conti finti 100k e 50k
// che condividono una cartella "Common\Files" su disco.
// NON sostituisce MetaEditor: verifica la logica, non la sintassi MQL5.
#pragma once
#include <string>
#include <vector>
#include <deque>
#include <map>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <cstring>
#include <sstream>
#include <fstream>
#include <iostream>
#include <filesystem>
#include <algorithm>
#include <functional>

using std::string;
typedef long datetime;
typedef unsigned long ulong;
typedef unsigned int uint;
typedef unsigned short ushort;
typedef unsigned char uchar;

// ------------------------------------------------------------------ costanti
#define INIT_SUCCEEDED 0
#define INIT_FAILED 1
#define INIT_PARAMETERS_INCORRECT 2
#define INVALID_HANDLE (-1)
#define FILE_READ 1
#define FILE_WRITE 2
#define FILE_BIN 4
#define FILE_CSV 8
#define FILE_TXT 16
#define FILE_ANSI 32
#define FILE_UNICODE 64
#define FILE_SHARE_READ 128
#define FILE_SHARE_WRITE 256
#define FILE_REWRITE 512
#define FILE_COMMON 4096
#define TIME_DATE 1
#define TIME_MINUTES 2
#define TIME_SECONDS 4
#define SYMBOL_FILLING_FOK 1
#define SYMBOL_FILLING_IOC 2

#define TRADE_RETCODE_REQUOTE 10004
#define TRADE_RETCODE_REJECT 10006
#define TRADE_RETCODE_CANCEL 10007
#define TRADE_RETCODE_PLACED 10008
#define TRADE_RETCODE_DONE 10009
#define TRADE_RETCODE_DONE_PARTIAL 10010
#define TRADE_RETCODE_ERROR 10011
#define TRADE_RETCODE_TIMEOUT 10012
#define TRADE_RETCODE_INVALID 10013
#define TRADE_RETCODE_INVALID_VOLUME 10014
#define TRADE_RETCODE_INVALID_PRICE 10015
#define TRADE_RETCODE_INVALID_STOPS 10016
#define TRADE_RETCODE_TRADE_DISABLED 10017
#define TRADE_RETCODE_MARKET_CLOSED 10018
#define TRADE_RETCODE_NO_MONEY 10019
#define TRADE_RETCODE_PRICE_CHANGED 10020
#define TRADE_RETCODE_PRICE_OFF 10021
#define TRADE_RETCODE_TOO_MANY_REQUESTS 10024
#define TRADE_RETCODE_INVALID_FILL 10030
#define TRADE_RETCODE_CONNECTION 10031
#define TRADE_RETCODE_LIMIT_VOLUME 10034
#define TRADE_RETCODE_LIMIT_POSITIONS 10040

enum ENUM_TIMEFRAMES { PERIOD_CURRENT = 0, PERIOD_M15 = 15 };
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY = 0, ORDER_TYPE_SELL = 1 };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK = 0, ORDER_FILLING_IOC = 1, ORDER_FILLING_RETURN = 2 };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC = 0 };
enum ENUM_TRADE_REQUEST_ACTIONS { TRADE_ACTION_DEAL = 1, TRADE_ACTION_PENDING = 5, TRADE_ACTION_SLTP = 6 };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
enum ENUM_DEAL_TYPE { DEAL_TYPE_BUY = 0, DEAL_TYPE_SELL = 1 };
enum ENUM_DEAL_ENTRY { DEAL_ENTRY_IN = 0, DEAL_ENTRY_OUT = 1, DEAL_ENTRY_INOUT = 2, DEAL_ENTRY_OUT_BY = 3 };
enum ENUM_DEAL_REASON { DEAL_REASON_CLIENT = 0, DEAL_REASON_MOBILE = 1, DEAL_REASON_WEB = 2, DEAL_REASON_EXPERT = 3,
                        DEAL_REASON_SL = 4, DEAL_REASON_TP = 5, DEAL_REASON_SO = 6 };
enum ENUM_POSITION_PROPERTY_INTEGER { POSITION_TICKET, POSITION_TIME, POSITION_TIME_MSC, POSITION_TYPE, POSITION_MAGIC, POSITION_IDENTIFIER };
enum ENUM_POSITION_PROPERTY_DOUBLE { POSITION_VOLUME, POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP, POSITION_PROFIT };
enum ENUM_POSITION_PROPERTY_STRING { POSITION_SYMBOL, POSITION_COMMENT };
enum ENUM_DEAL_PROPERTY_INTEGER { DEAL_TICKET, DEAL_TIME, DEAL_TYPE, DEAL_ENTRY, DEAL_MAGIC, DEAL_REASON, DEAL_POSITION_ID };
enum ENUM_DEAL_PROPERTY_DOUBLE { DEAL_VOLUME, DEAL_PRICE, DEAL_PROFIT };
enum ENUM_DEAL_PROPERTY_STRING { DEAL_SYMBOL, DEAL_COMMENT };
enum ENUM_ACCOUNT_INFO_INTEGER { ACCOUNT_LOGIN, ACCOUNT_TRADE_ALLOWED, ACCOUNT_TRADE_EXPERT, ACCOUNT_MARGIN_MODE };
enum ENUM_ACCOUNT_INFO_STRING { ACCOUNT_CURRENCY };
enum ENUM_ACCOUNT_MARGIN_MODE { ACCOUNT_MARGIN_MODE_RETAIL_NETTING = 0, ACCOUNT_MARGIN_MODE_EXCHANGE = 1, ACCOUNT_MARGIN_MODE_RETAIL_HEDGING = 2 };
enum ENUM_TERMINAL_INFO_INTEGER { TERMINAL_CONNECTED, TERMINAL_TRADE_ALLOWED };
enum ENUM_TERMINAL_INFO_STRING { TERMINAL_COMMONDATA_PATH };
enum ENUM_MQL_INFO_INTEGER { MQL_TESTER, MQL_TRADE_ALLOWED };
enum ENUM_SYMBOL_INFO_INTEGER { SYMBOL_DIGITS, SYMBOL_TRADE_MODE, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_FILLING_MODE };
enum ENUM_SYMBOL_INFO_DOUBLE { SYMBOL_POINT, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_STEP, SYMBOL_TRADE_CONTRACT_SIZE, SYMBOL_TRADE_TICK_SIZE };
enum ENUM_SYMBOL_TRADE_MODE { SYMBOL_TRADE_MODE_DISABLED = 0, SYMBOL_TRADE_MODE_FULL = 4 };

struct MqlDateTime { int year, mon, day, hour, min, sec, day_of_week, day_of_year; };
struct MqlTick { datetime time; double bid, ask, last; ulong volume; long time_msc; uint flags; double volume_real; };
struct MqlRates { datetime time; double open, high, low, close; long tick_volume; int spread; long real_volume; };
struct MqlTradeRequest {
  ENUM_TRADE_REQUEST_ACTIONS action; ulong magic; ulong order; string symbol; double volume, price, stoplimit, sl, tp;
  ulong deviation; ENUM_ORDER_TYPE type; ENUM_ORDER_TYPE_FILLING type_filling; ENUM_ORDER_TYPE_TIME type_time;
  datetime expiration; string comment; ulong position; ulong position_by;
};
struct MqlTradeResult { uint retcode; ulong deal, order; double volume, price, bid, ask; string comment; uint request_id; int retcode_external; };
struct MqlTradeCheckResult { uint retcode; double balance, equity, profit, margin, margin_free, margin_level; string comment; };

// ------------------------------------------------------------------ mondo simulato
struct MockPosition {
  ulong ticket; long identifier; int type; double volume, price_open, sl, tp; long magic;
  string symbol, comment; long time_server; bool has_profit_override; double profit_override;
};
struct MockDeal {
  ulong ticket; long position_id; int type; int entry; int reason; long magic; string symbol, comment;
  double price, volume; long time_server;
};
struct ForcedResult { uint retcode; bool executes; };

struct MockTerminal {
  string name;
  long login = 0;
  string currency = "USD";
  bool connected = true;
  bool algo_allowed = true;
  bool hedging = true;
  bool fail_file_writes = false;
  bool tester = false;           // Strategy Tester: TimeGMT() = ora del server
  std::map<string, double> gv;   // variabili globali del terminale
  string symbol = "XAUUSD";
  double bid = 0, ask = 0;
  long tick_time_server = 0;
  int digits = 2;
  double point = 0.01;
  double contract = 100.0;
  double vmin = 0.01, vmax = 100.0, vstep = 0.01;
  int filling = SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC;
  int stops_level = 0;
  double slippage = 0.0;         // differenza applicata al prezzo di esecuzione
  long server_offset = 3 * 3600; // ora server = UTC + offset
  std::vector<MockPosition> positions;
  std::vector<MockDeal> deals;
  std::deque<ForcedResult> forced;
  std::vector<MqlTradeRequest> sent;   // tutte le richieste OrderSend
  int selected = -1;
  std::vector<int> hist_sel;
  std::vector<MqlRates> m15;
  std::vector<string> journal;
  string comment;
  ulong next_ticket = 1000;
};

extern MockTerminal* g_term;
extern long g_utc_ms;      // orologio UTC del PC (ms)
extern long g_uptime_ms;   // GetTickCount64 del PC (ms)
extern string g_common_dir;
extern bool g_verbose;

// ------------------------------------------------------------------ tempo
inline long GetTickCount64() { return g_uptime_ms; }
inline datetime TimeTradeServer() { return g_utc_ms / 1000 + g_term->server_offset; }
inline datetime TimeGMT() { return g_term && g_term->tester ? TimeTradeServer() : g_utc_ms / 1000; }
inline datetime TimeCurrent() { return g_term->tick_time_server ? g_term->tick_time_server : TimeTradeServer(); }
inline datetime TimeLocal() { return TimeGMT() + 3600; }
inline bool TimeToStruct(datetime t, MqlDateTime& d) {
  time_t tt = (time_t)t; struct tm r; gmtime_r(&tt, &r);
  d.year = r.tm_year + 1900; d.mon = r.tm_mon + 1; d.day = r.tm_mday; d.hour = r.tm_hour; d.min = r.tm_min; d.sec = r.tm_sec;
  d.day_of_week = r.tm_wday; d.day_of_year = r.tm_yday; return true;
}
inline datetime StructToTime(MqlDateTime& d) {
  struct tm r; memset(&r, 0, sizeof r);
  r.tm_year = d.year - 1900; r.tm_mon = d.mon - 1; r.tm_mday = d.day; r.tm_hour = d.hour; r.tm_min = d.min; r.tm_sec = d.sec;
  return (datetime)timegm(&r);
}
inline string TimeToString(datetime t, int mode = TIME_DATE | TIME_MINUTES) {
  MqlDateTime d; TimeToStruct(t, d); char b[64]; string s;
  if (mode & TIME_DATE) { snprintf(b, sizeof b, "%04d.%02d.%02d", d.year, d.mon, d.day); s += b; }
  if (mode & (TIME_MINUTES | TIME_SECONDS)) {
    if (!s.empty()) s += " ";
    if (mode & TIME_SECONDS) snprintf(b, sizeof b, "%02d:%02d:%02d", d.hour, d.min, d.sec);
    else snprintf(b, sizeof b, "%02d:%02d", d.hour, d.min);
    s += b;
  }
  return s;
}

// ------------------------------------------------------------------ matematica e stringhe
inline double MathRound(double v) { return std::round(v); }
template <class T> T MathAbs(T v) { return v < 0 ? -v : v; }
template <class A, class B> auto MathMax(A a, B b) -> decltype(a + b) { return a > b ? a : b; }
template <class A, class B> auto MathMin(A a, B b) -> decltype(a + b) { return a < b ? a : b; }
inline double MathFloor(double v) { return std::floor(v); }
inline double NormalizeDouble(double v, int digits) { double p = std::pow(10.0, digits); return std::round(v * p) / p; }
inline int StringLen(const string& s) { return (int)s.size(); }
inline int StringFind(const string& s, const string& m, int start = 0) {
  if (start < 0 || start > (int)s.size()) return -1;
  size_t p = s.find(m, (size_t)start); return p == string::npos ? -1 : (int)p;
}
inline string StringSubstr(const string& s, int start, int len = -1) {
  if (start < 0 || start >= (int)s.size()) return "";
  return len < 0 ? s.substr(start) : s.substr(start, len);
}
inline long StringToInteger(const string& s) { return std::strtol(s.c_str(), nullptr, 10); }
inline double StringToDouble(const string& s) { return std::strtod(s.c_str(), nullptr); }
inline string IntegerToString(long v, int = 0, ushort = ' ') { return std::to_string(v); }
inline string DoubleToString(double v, int digits = 8) { char b[64]; snprintf(b, sizeof b, "%.*f", digits, v); return b; }
inline int StringTrimLeft(string& s) { size_t n = 0; while (n < s.size() && (s[n] == ' ' || s[n] == '\t' || s[n] == '\r' || s[n] == '\n')) n++; s.erase(0, n); return (int)n; }
inline int StringTrimRight(string& s) { size_t n = 0; while (!s.empty() && (s.back() == ' ' || s.back() == '\t' || s.back() == '\r' || s.back() == '\n')) { s.pop_back(); n++; } return (int)n; }
template <class T> void ZeroMemory(T& x) { x = T(); }

inline void PrintTo(std::ostringstream&) {}
template <class T, class... R> void PrintTo(std::ostringstream& o, const T& v, const R&... r) { o << v; PrintTo(o, r...); }
template <class... A> void Print(const A&... a) {
  std::ostringstream o; PrintTo(o, a...);
  g_term->journal.push_back(o.str());
  if (g_verbose) std::cout << "    [" << g_term->name << "] " << o.str() << "\n";
}
inline void Comment(const string& s) { g_term->comment = s; }
inline int GetLastError() { return 0; }
inline void ResetLastError() {}
inline bool EventSetMillisecondTimer(int) { return true; }
inline bool EventSetTimer(int) { return true; }
inline void EventKillTimer() {}

// ------------------------------------------------------------------ terminale e conto
inline long AccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER p) {
  switch (p) {
    case ACCOUNT_LOGIN: return g_term->login;
    case ACCOUNT_TRADE_ALLOWED: return 1;
    case ACCOUNT_TRADE_EXPERT: return 1;
    case ACCOUNT_MARGIN_MODE: return g_term->hedging ? ACCOUNT_MARGIN_MODE_RETAIL_HEDGING : ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
  }
  return 0;
}
inline string AccountInfoString(ENUM_ACCOUNT_INFO_STRING) { return g_term->currency; }
inline long TerminalInfoInteger(ENUM_TERMINAL_INFO_INTEGER p) {
  if (p == TERMINAL_CONNECTED) return g_term->connected ? 1 : 0;
  return g_term->algo_allowed ? 1 : 0;
}
inline string TerminalInfoString(ENUM_TERMINAL_INFO_STRING) { return g_common_dir; }
inline long MQLInfoInteger(ENUM_MQL_INFO_INTEGER p) { return p == MQL_TRADE_ALLOWED ? 1 : (g_term->tester ? 1 : 0); }
inline bool SymbolSelect(const string& s, bool) { return s == g_term->symbol; }
inline long SymbolInfoInteger(const string& s, ENUM_SYMBOL_INFO_INTEGER p) {
  if (s != g_term->symbol) return 0;
  switch (p) {
    case SYMBOL_DIGITS: return g_term->digits;
    case SYMBOL_TRADE_MODE: return SYMBOL_TRADE_MODE_FULL;
    case SYMBOL_TRADE_STOPS_LEVEL: return g_term->stops_level;
    case SYMBOL_FILLING_MODE: return g_term->filling;
  }
  return 0;
}
inline double SymbolInfoDouble(const string& s, ENUM_SYMBOL_INFO_DOUBLE p) {
  if (s != g_term->symbol) return 0;
  switch (p) {
    case SYMBOL_POINT: return g_term->point;
    case SYMBOL_VOLUME_MIN: return g_term->vmin;
    case SYMBOL_VOLUME_MAX: return g_term->vmax;
    case SYMBOL_VOLUME_STEP: return g_term->vstep;
    case SYMBOL_TRADE_CONTRACT_SIZE: return g_term->contract;
    case SYMBOL_TRADE_TICK_SIZE: return g_term->point;
  }
  return 0;
}
inline bool SymbolInfoTick(const string& s, MqlTick& t) {
  if (s != g_term->symbol || g_term->bid <= 0) return false;
  t = MqlTick(); t.bid = g_term->bid; t.ask = g_term->ask; t.time = g_term->tick_time_server; t.time_msc = t.time * 1000; return true;
}

// ------------------------------------------------------------------ posizioni
inline double MockProfit(const MockPosition& p) {
  if (p.has_profit_override) return p.profit_override;
  if (p.type == 0) return (g_term->bid - p.price_open) * g_term->contract * p.volume;
  return (p.price_open - g_term->ask) * g_term->contract * p.volume;
}
inline int PositionsTotal() { return (int)g_term->positions.size(); }
inline ulong PositionGetTicket(int i) {
  if (i < 0 || i >= (int)g_term->positions.size()) return 0;
  g_term->selected = i; return g_term->positions[i].ticket;
}
inline bool PositionSelectByTicket(ulong t) {
  for (size_t i = 0; i < g_term->positions.size(); i++) if (g_term->positions[i].ticket == t) { g_term->selected = (int)i; return true; }
  return false;
}
inline const MockPosition& SelPos() { return g_term->positions.at(g_term->selected); }
inline long PositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER p) {
  const MockPosition& x = SelPos();
  switch (p) {
    case POSITION_TICKET: return (long)x.ticket;
    case POSITION_TIME: return x.time_server;
    case POSITION_TIME_MSC: return x.time_server * 1000;
    case POSITION_TYPE: return x.type;
    case POSITION_MAGIC: return x.magic;
    case POSITION_IDENTIFIER: return x.identifier;
  }
  return 0;
}
inline double PositionGetDouble(ENUM_POSITION_PROPERTY_DOUBLE p) {
  const MockPosition& x = SelPos();
  switch (p) {
    case POSITION_VOLUME: return x.volume;
    case POSITION_PRICE_OPEN: return x.price_open;
    case POSITION_SL: return x.sl;
    case POSITION_TP: return x.tp;
    case POSITION_PROFIT: return MockProfit(x);
  }
  return 0;
}
inline string PositionGetString(ENUM_POSITION_PROPERTY_STRING p) {
  const MockPosition& x = SelPos();
  return p == POSITION_SYMBOL ? x.symbol : x.comment;
}

// ------------------------------------------------------------------ storico
inline bool HistorySelect(datetime from, datetime to) {
  g_term->hist_sel.clear();
  for (size_t i = 0; i < g_term->deals.size(); i++)
    if (g_term->deals[i].time_server >= from && g_term->deals[i].time_server <= to) g_term->hist_sel.push_back((int)i);
  return true;
}
inline int HistoryDealsTotal() { return (int)g_term->hist_sel.size(); }
inline ulong HistoryDealGetTicket(int i) {
  if (i < 0 || i >= (int)g_term->hist_sel.size()) return 0;
  return g_term->deals[g_term->hist_sel[i]].ticket;
}
inline const MockDeal* FindDeal(ulong t) {
  for (auto& d : g_term->deals) if (d.ticket == t) return &d;
  return nullptr;
}
inline long HistoryDealGetInteger(ulong t, ENUM_DEAL_PROPERTY_INTEGER p) {
  const MockDeal* d = FindDeal(t); if (!d) return 0;
  switch (p) {
    case DEAL_TICKET: return (long)d->ticket;
    case DEAL_TIME: return d->time_server;
    case DEAL_TYPE: return d->type;
    case DEAL_ENTRY: return d->entry;
    case DEAL_MAGIC: return d->magic;
    case DEAL_REASON: return d->reason;
    case DEAL_POSITION_ID: return d->position_id;
  }
  return 0;
}
inline double HistoryDealGetDouble(ulong t, ENUM_DEAL_PROPERTY_DOUBLE p) {
  const MockDeal* d = FindDeal(t); if (!d) return 0;
  return p == DEAL_PRICE ? d->price : p == DEAL_VOLUME ? d->volume : 0.0;
}
inline string HistoryDealGetString(ulong t, ENUM_DEAL_PROPERTY_STRING p) {
  const MockDeal* d = FindDeal(t); if (!d) return "";
  return p == DEAL_SYMBOL ? d->symbol : d->comment;
}

// ------------------------------------------------------------------ operazioni del broker (usate anche dai test)
inline long ServerNow() { return TimeGMT() + g_term->server_offset; }
inline ulong BrokerOpen(MockTerminal& T, int type, double price, double sl, double tp, double vol, long magic, const string& comment) {
  MockPosition p{}; p.ticket = T.next_ticket++; p.identifier = (long)p.ticket; p.type = type; p.volume = vol; p.price_open = price;
  p.sl = sl; p.tp = tp; p.magic = magic; p.symbol = T.symbol; p.comment = comment; p.time_server = TimeGMT() + T.server_offset;
  T.positions.push_back(p);
  MockDeal d{}; d.ticket = T.next_ticket++; d.position_id = p.identifier; d.type = type; d.entry = DEAL_ENTRY_IN; d.reason = DEAL_REASON_EXPERT;
  d.magic = magic; d.symbol = T.symbol; d.comment = comment; d.price = price; d.volume = vol; d.time_server = p.time_server;
  T.deals.push_back(d);
  return p.ticket;
}
inline bool BrokerClose(MockTerminal& T, ulong ticket, int reason, double price, long magic_override = -1) {
  for (size_t i = 0; i < T.positions.size(); i++) {
    if (T.positions[i].ticket != ticket) continue;
    MockPosition p = T.positions[i];
    MockDeal d{}; d.ticket = T.next_ticket++; d.position_id = p.identifier; d.type = p.type == 0 ? DEAL_TYPE_SELL : DEAL_TYPE_BUY;
    d.entry = DEAL_ENTRY_OUT; d.reason = reason; d.magic = magic_override >= 0 ? magic_override : p.magic; d.symbol = p.symbol;
    d.comment = reason == DEAL_REASON_SL ? "[sl]" : reason == DEAL_REASON_TP ? "[tp]" : "";
    d.price = price; d.volume = p.volume; d.time_server = TimeGMT() + T.server_offset;
    T.deals.push_back(d);
    T.positions.erase(T.positions.begin() + i);
    return true;
  }
  return false;
}
// Il server chiude le posizioni che toccano SL o TP (BUY su Bid, SELL su Ask).
inline void BrokerCheckStops(MockTerminal& T) {
  for (size_t i = 0; i < T.positions.size();) {
    MockPosition p = T.positions[i];
    int reason = -1; double px = 0;
    if (p.type == 0) {
      if (p.sl > 0 && T.bid <= p.sl) { reason = DEAL_REASON_SL; px = T.bid; }
      else if (p.tp > 0 && T.bid >= p.tp) { reason = DEAL_REASON_TP; px = T.bid; }
    } else {
      if (p.sl > 0 && T.ask >= p.sl) { reason = DEAL_REASON_SL; px = T.ask; }
      else if (p.tp > 0 && T.ask <= p.tp) { reason = DEAL_REASON_TP; px = T.ask; }
    }
    if (reason >= 0) BrokerClose(T, p.ticket, reason, px); else i++;
  }
}

inline bool OrderCalcProfit(ENUM_ORDER_TYPE type, const string& s, double vol, double open, double close, double& profit) {
  if (s != g_term->symbol) return false;
  profit = (type == ORDER_TYPE_BUY ? (close - open) : (open - close)) * g_term->contract * vol;
  return true;
}
inline bool StopsValid(const MqlTradeRequest& r) {
  double lvl = g_term->stops_level * g_term->point;
  if (r.type == ORDER_TYPE_BUY) return (r.sl == 0 || r.sl <= g_term->bid - lvl) && (r.tp == 0 || r.tp >= g_term->bid + lvl) && (r.sl < g_term->bid) && (r.tp == 0 || r.tp > g_term->bid);
  return (r.sl == 0 || r.sl >= g_term->ask + lvl) && (r.tp == 0 || r.tp <= g_term->ask - lvl) && (r.sl == 0 || r.sl > g_term->ask) && (r.tp < g_term->ask);
}
inline bool OrderCheck(const MqlTradeRequest& r, MqlTradeCheckResult& c) {
  c = MqlTradeCheckResult();
  if (!g_term->connected) { c.retcode = TRADE_RETCODE_CONNECTION; c.comment = "no connection"; return false; }
  if (r.action == TRADE_ACTION_DEAL && r.position == 0) {
    if (r.volume < g_term->vmin || r.volume > g_term->vmax) { c.retcode = TRADE_RETCODE_INVALID_VOLUME; return false; }
    if (!StopsValid(r)) { c.retcode = TRADE_RETCODE_INVALID_STOPS; c.comment = "Invalid stops"; return false; }
  }
  c.retcode = 0; c.comment = "Done"; return true;
}
inline bool OrderSend(MqlTradeRequest& r, MqlTradeResult& res) {
  res = MqlTradeResult();
  g_term->sent.push_back(r);
  if (!g_term->connected) { res.retcode = TRADE_RETCODE_CONNECTION; res.comment = "No connection"; return false; }
  bool execute = true; uint forced = 0;
  if (!g_term->forced.empty()) { ForcedResult f = g_term->forced.front(); g_term->forced.pop_front(); forced = f.retcode; execute = f.executes; }
  if (r.action == TRADE_ACTION_DEAL && r.position == 0) {
    if (!forced) {
      if (r.type_filling == ORDER_FILLING_FOK && !(g_term->filling & SYMBOL_FILLING_FOK)) { res.retcode = TRADE_RETCODE_INVALID_FILL; res.comment = "Unsupported filling mode"; return false; }
      if (!StopsValid(r)) { res.retcode = TRADE_RETCODE_INVALID_STOPS; res.comment = "Invalid stops"; return false; }
    }
    if (execute) {
      int type = r.type == ORDER_TYPE_BUY ? 0 : 1;
      double px = (type == 0 ? g_term->ask : g_term->bid) + g_term->slippage;
      ulong t = BrokerOpen(*g_term, type, px, r.sl, r.tp, r.volume, (long)r.magic, r.comment);
      res.order = t; res.deal = t + 1; res.price = px; res.volume = r.volume;
    }
    res.retcode = forced ? forced : TRADE_RETCODE_DONE;
    res.comment = forced ? "forced" : "Request executed";
    return res.retcode == TRADE_RETCODE_DONE;
  }
  if (r.action == TRADE_ACTION_DEAL && r.position != 0) {
    if (forced && !execute) { res.retcode = forced; return false; }
    double px = r.type == ORDER_TYPE_SELL ? g_term->bid : g_term->ask;
    if (!BrokerClose(*g_term, r.position, DEAL_REASON_EXPERT, px)) { res.retcode = TRADE_RETCODE_INVALID; return false; }
    res.retcode = TRADE_RETCODE_DONE; res.price = px; res.volume = r.volume; return true;
  }
  if (r.action == TRADE_ACTION_SLTP) {
    for (auto& p : g_term->positions) if (p.ticket == r.position) { p.sl = r.sl; p.tp = r.tp; res.retcode = TRADE_RETCODE_DONE; return true; }
    res.retcode = TRADE_RETCODE_INVALID; return false;
  }
  res.retcode = TRADE_RETCODE_INVALID; return false;
}

// ------------------------------------------------------------------ variabili globali del terminale
inline datetime GlobalVariableSet(const string& n, double v) { g_term->gv[n] = v; return TimeCurrent(); }
inline double GlobalVariableGet(const string& n) { auto it = g_term->gv.find(n); return it == g_term->gv.end() ? 0.0 : it->second; }
inline bool GlobalVariableCheck(const string& n) { return g_term->gv.count(n) > 0; }
inline bool GlobalVariableDel(const string& n) { return g_term->gv.erase(n) > 0; }

// ------------------------------------------------------------------ barre M15
inline datetime iTime(const string& s, ENUM_TIMEFRAMES, int shift) {
  if (s != g_term->symbol) return 0;
  int n = (int)g_term->m15.size();
  if (shift < 0 || shift >= n) return 0;
  return g_term->m15[n - 1 - shift].time;
}
inline int iBarShift(const string& s, ENUM_TIMEFRAMES, datetime t, bool exact = false) {
  if (s != g_term->symbol) return -1;
  int n = (int)g_term->m15.size();
  for (int i = n - 1; i >= 0; i--) {
    if (g_term->m15[i].time == t) return n - 1 - i;
    if (!exact && g_term->m15[i].time < t) return n - 1 - i;
  }
  return -1;
}
template <size_t N> int CopyRates(const string& s, ENUM_TIMEFRAMES, int start, int count, MqlRates (&arr)[N]) {
  if (s != g_term->symbol) return -1;
  int n = (int)g_term->m15.size();
  int last = n - 1 - start;
  if (last < 0) return -1;
  int first = std::max(0, last - std::min(count, (int)N) + 1);
  int k = 0;
  for (int i = first; i <= last; i++) arr[k++] = g_term->m15[i];
  return k;
}

// ------------------------------------------------------------------ file (Common\Files = g_common_dir)
struct MockFile { string path; int flags; std::vector<string> lines; size_t pos; string out; bool seek_end; };
extern std::map<int, MockFile> g_files;
extern int g_next_handle;
// Richiamata quando un file viene aperto in sola lettura: i test la usano per
// cambiare lo stato del mondo tra due letture dello stesso ciclo.
extern std::function<void(const string&)> g_hook_lettura;
inline string ResolvePath(const string& name, int flags) {
  string n = name; std::replace(n.begin(), n.end(), '\\', '/');
  string base = (flags & FILE_COMMON) ? g_common_dir : g_common_dir + "/../local_" + std::to_string(g_term->login);
  return base + "/" + n;
}
inline std::vector<string> SplitLines(const string& c) {
  std::vector<string> v; string cur;
  for (char ch : c) { if (ch == '\n') { if (!cur.empty() && cur.back() == '\r') cur.pop_back(); v.push_back(cur); cur.clear(); } else cur += ch; }
  if (!cur.empty()) v.push_back(cur);
  return v;
}
inline int FileOpen(const string& name, int flags, short = '\t', uint = 0) {
  string path = ResolvePath(name, flags);
  bool rd = flags & FILE_READ, wr = flags & FILE_WRITE;
  if (rd && !wr && g_hook_lettura) g_hook_lettura(path);
  if (wr && g_term->fail_file_writes) return INVALID_HANDLE;
  MockFile f{path, flags, {}, 0, "", false};
  if (rd) {
    std::ifstream in(path, std::ios::binary);
    if (!in) { if (!wr) return INVALID_HANDLE; }
    else { std::stringstream ss; ss << in.rdbuf(); f.lines = SplitLines(ss.str()); }
  }
  if (wr) std::filesystem::create_directories(std::filesystem::path(path).parent_path());
  int h = g_next_handle++; g_files[h] = f; return h;
}
inline string FileReadString(int h, int = -1) { MockFile& f = g_files.at(h); return f.pos < f.lines.size() ? f.lines[f.pos++] : ""; }
inline bool FileIsEnding(int h) { MockFile& f = g_files.at(h); return f.pos >= f.lines.size(); }
inline uint FileWriteString(int h, const string& s, int = -1) { g_files.at(h).out += s; return (uint)s.size(); }
inline bool FileSeek(int h, long, int origin) { if (origin == SEEK_END) g_files.at(h).seek_end = true; return true; }
inline void FileFlush(int) {}
inline void FileClose(int h) {
  auto it = g_files.find(h); if (it == g_files.end()) return;
  MockFile& f = it->second;
  if (f.flags & FILE_WRITE) {
    if ((f.flags & FILE_READ) && f.seek_end) { std::ofstream o(f.path, std::ios::binary | std::ios::app); o << f.out; }
    else { std::ofstream o(f.path, std::ios::binary | std::ios::trunc); o << f.out; }
  }
  g_files.erase(it);
}
inline bool FileIsExist(const string& name, int common = 0) { return std::filesystem::exists(ResolvePath(name, common)); }
inline bool FileDelete(const string& name, int common = 0) { return std::filesystem::remove(ResolvePath(name, common)); }
inline bool FolderCreate(const string& name, int common = 0) { std::filesystem::create_directories(ResolvePath(name, common)); return true; }
inline bool FileMove(const string& src, int common, const string& dst, int mode) {
  string a = ResolvePath(src, common), b = ResolvePath(dst, mode);
  if (g_term->fail_file_writes) return false;
  if (std::filesystem::exists(b) && !(mode & FILE_REWRITE)) return false;
  std::error_code ec; std::filesystem::rename(a, b, ec); return !ec;
}
