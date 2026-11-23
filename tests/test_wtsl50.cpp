// Banco di prova simulato per WTSL-50%ercole.mq5.
// Il sorgente .mq5 reale viene incluso dentro la struct EA (vedi run_tests.sh):
// ogni terminale ha la sua istanza, il suo conto finto e il suo broker finto,
// mentre la cartella Common\Files e l'orologio del PC sono condivisi.
#include "mt5_shim.h"

MockTerminal* g_term = nullptr;
long g_utc_ms = 0;
long g_uptime_ms = 0;
string g_common_dir;
bool g_verbose = false;
std::map<int, MockFile> g_files;
int g_next_handle = 1;
std::function<void(const string&)> g_hook_lettura;

struct EA {
#include "ea_body.inc"
};

struct WT67EA {
#include "wt67_body.inc"
};

namespace fs = std::filesystem;
static string g_base;
static const long L100 = 11000001;
static const long L50 = 22000002;
static const long MAGIC_WT67 = 670067;
static const long MAGIC_50K = 670050;

// ------------------------------------------------------------------ risultati
struct Riga { string id, nome, atteso, osservato; bool ok; };
static std::vector<Riga> g_righe;
static void Esito(const string& id, const string& nome, const string& atteso, const string& osservato, bool ok) {
  g_righe.push_back({id, nome, atteso, osservato, ok});
  std::cout << (ok ? "  OK   " : "  KO   ") << id << " " << nome << "\n        atteso:    " << atteso
            << "\n        osservato: " << osservato << "\n";
}
static string F2(double v) { char b[32]; snprintf(b, sizeof b, "%.2f", v); return b; }

static long UtcMs(int y, int mo, int d, int h, int mi, int s) {
  MqlDateTime t{y, mo, d, h, mi, s, 0, 0};
  return (long)StructToTime(t) * 1000L;
}

// ------------------------------------------------------------------ ambiente con due terminali
struct Env {
  MockTerminal T100, T50;
  EA* ea100 = nullptr;
  EA* ea50 = nullptr;
  string dir;
  int romeOff;
  Env(const string& name, int y = 2026, int mo = 7, int d = 15, int h = 15, int mi = 40, int s = 0, int romeOffH = 2) {
    dir = g_base + "/" + name;
    fs::remove_all(dir);
    fs::create_directories(dir + "/common");
    g_common_dir = dir + "/common";
    g_files.clear();
    romeOff = romeOffH;
    g_uptime_ms = 86400000L;
    g_utc_ms = UtcMs(y, mo, d, h, mi, s) - romeOffH * 3600000L;
    T100.name = "100k"; T100.login = L100; T100.next_ticket = 5000000;
    T50.name = "50k"; T50.login = L50; T50.next_ticket = 9000000;
    long srv = (romeOffH == 2) ? 3 : 2;   // server FTMO: UTC+3 d'estate, UTC+2 d'inverno
    T100.server_offset = T50.server_offset = srv * 3600;
    T100.bid = T50.bid = 2999.70; T100.ask = T50.ask = 3000.00;
    T100.tick_time_server = T50.tick_time_server = g_utc_ms / 1000 + srv * 3600;
  }
  ~Env() { delete ea100; delete ea50; delete wt; }
  // ---- bot WT67 sul terminale 100k e barre M15 sintetiche
  WT67EA* wt = nullptr;
  std::vector<MqlRates> serie;
  long t0 = 0;   // ora server di apertura della barra 0 della serie
  int StartWT() { wt = new WT67EA(); wt->InpConto100k = L100; g_term = &T100; return wt->OnInit(); }
  void RestartWT() { g_term = &T100; wt->OnDeinit(0); delete wt; wt = nullptr; StartWT(); }
  // La barra "idx" della serie apre alle romeH:romeM ora di Roma dello stesso giorno.
  void Serie(const std::vector<MqlRates>& s, int idx, int romeH, int romeM) {
    serie = s;
    long giorno = (g_utc_ms / 86400000L) * 86400L;
    long utc = giorno + (romeH - romeOff) * 3600L + romeM * 60L;
    t0 = utc + T100.server_offset - (long)idx * 900;
  }
  void VaiABarra(int j, int sec) {
    long target = (t0 + (long)j * 900 + sec - T100.server_offset) * 1000L;
    if (target > g_utc_ms) Adv(target - g_utc_ms);
    T100.m15.clear();
    for (int i = 0; i <= j; i++) { MqlRates r = serie[i]; r.time = t0 + (long)i * 900; T100.m15.push_back(r); }
  }
  void TickBarra(int j, int sec, double b100, double a100, double b50, double a50) { VaiABarra(j, sec); Q100(b100, a100); Q50(b50, a50); }
  int OpensWT() const { int n = 0; for (auto& r : T100.sent) if (r.action == TRADE_ACTION_DEAL && r.position == 0) n++; return n; }
  int ClosesWT() const { int n = 0; for (auto& r : T100.sent) if (r.action == TRADE_ACTION_DEAL && r.position != 0) n++; return n; }
  const MockPosition* PosWT() const { for (auto& p : T100.positions) if (p.magic == MAGIC_WT67) return &p; return nullptr; }
  EA* Make() { EA* e = new EA(); e->InpConto100k = L100; e->InpConto50k = L50; return e; }
  int Start100() { ea100 = Make(); g_term = &T100; return ea100->OnInit(); }
  int Start50() { ea50 = Make(); g_term = &T50; return ea50->OnInit(); }
  void Start() { Start100(); Start50(); }
  void Restart50() { g_term = &T50; ea50->OnDeinit(0); delete ea50; ea50 = nullptr; Start50(); }
  void Restart100() { g_term = &T100; ea100->OnDeinit(0); delete ea100; ea100 = nullptr; Start100(); }
  void Adv(long ms) { g_utc_ms += ms; g_uptime_ms += ms; }
  void SetRome(int h, int mi, int s) {   // stesso giorno, solo avanti
    long target = (g_utc_ms / 86400000L) * 86400000L + ((h - romeOff) * 3600L + mi * 60L + s) * 1000L;
    if (target > g_utc_ms) Adv(target - g_utc_ms);
  }
  void Q100(double bid, double ask) {
    T100.bid = bid; T100.ask = ask; T100.tick_time_server = g_utc_ms / 1000 + T100.server_offset;
    g_term = &T100; BrokerCheckStops(T100);
    if (wt) wt->OnTick();
    if (ea100) ea100->OnTick();
  }
  void Q50(double bid, double ask) {
    T50.bid = bid; T50.ask = ask; T50.tick_time_server = g_utc_ms / 1000 + T50.server_offset;
    g_term = &T50; BrokerCheckStops(T50);
    if (ea50) ea50->OnTick();
  }
  void Tick(double b100, double a100, double b50, double a50, long ms = 200) { Adv(ms); Q100(b100, a100); Q50(b50, a50); }
  void Timers(long ms = 100) { Adv(ms); g_term = &T100; if (ea100) ea100->OnTimer(); g_term = &T50; if (ea50) ea50->OnTimer(); }
  ulong WT67(int type, double price, double sl, double tp, double vol = 1.0) {
    return BrokerOpen(T100, type, price, sl, tp, vol, MAGIC_WT67, "WT67");
  }
  int Opens() const { int n = 0; for (auto& r : T50.sent) if (r.action == TRADE_ACTION_DEAL && r.position == 0) n++; return n; }
  int Closes() const { int n = 0; for (auto& r : T50.sent) if (r.action == TRADE_ACTION_DEAL && r.position != 0) n++; return n; }
  int Others() const { int n = 0; for (auto& r : T50.sent) if (r.action != TRADE_ACTION_DEAL) n++; return n; }
  int Copies() const { int n = 0; for (auto& p : T50.positions) if (p.magic == MAGIC_50K) n++; return n; }
  const MockPosition* Copy() const { for (auto& p : T50.positions) if (p.magic == MAGIC_50K) return &p; return nullptr; }
  const MqlTradeRequest* LastOpen() const { const MqlTradeRequest* r = nullptr; for (auto& x : T50.sent) if (x.action == TRADE_ACTION_DEAL && x.position == 0) r = &x; return r; }
  bool J50(const string& s) const { for (auto& l : T50.journal) if (l.find(s) != string::npos) return true; return false; }
  bool J100(const string& s) const { for (auto& l : T100.journal) if (l.find(s) != string::npos) return true; return false; }
  int RegStato(long id, int tipo) const { for (int i = 0; i < ea50->g_nRegistro; i++) if (ea50->g_registro[i].pos_id == id && ea50->g_registro[i].tipo == tipo) return ea50->g_registro[i].stato; return -1; }
};

static string DescriviOrdine(Env& e) {
  const MqlTradeRequest* r = e.LastOpen();
  if (!r) return "nessun ordine";
  g_term = &e.T50;
  double pSL = 0, pTP = 0;
  OrderCalcProfit(r->type, r->symbol, r->volume, r->price, r->sl, pSL);
  OrderCalcProfit(r->type, r->symbol, r->volume, r->price, r->tp, pTP);
  string s = string(r->type == ORDER_TYPE_BUY ? "BUY " : "SELL ") + F2(r->volume) + " @" + F2(r->price) + " SL " + F2(r->sl) + " TP " + F2(r->tp)
             + (r->type_filling == ORDER_FILLING_FOK ? " FOK" : " non-FOK") + " magic " + std::to_string(r->magic) + " '" + r->comment + "'"
             + ", lordo " + F2(pSL) + "/+" + F2(pTP);
  return s;
}
static bool OrdineCorretto(Env& e, int tipo, double prezzo, double sl, double tp, long srcId) {
  const MqlTradeRequest* r = e.LastOpen();
  if (!r) return false;
  g_term = &e.T50;
  double pSL = 0, pTP = 0;
  OrderCalcProfit(r->type, r->symbol, r->volume, r->price, r->sl, pSL);
  OrderCalcProfit(r->type, r->symbol, r->volume, r->price, r->tp, pTP);
  string comm = "WTSL50|" + std::to_string(srcId) + (tipo == 0 ? "|B" : "|S");
  const MockPosition* p = e.Copy();
  return r->type == (tipo == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL) && std::fabs(r->volume - 0.50) < 1e-9 && std::fabs(r->price - prezzo) < 1e-9
         && std::fabs(r->sl - sl) < 1e-9 && std::fabs(r->tp - tp) < 1e-9 && r->type_filling == ORDER_FILLING_FOK && (long)r->magic == MAGIC_50K
         && r->comment == comm && std::lround(pSL * 100) == -25000 && std::lround(pTP * 100) == 75000 && p && std::fabs(p->sl - sl) < 1e-9
         && std::fabs(p->tp - tp) < 1e-9;
}

// ------------------------------------------------------------------ WaveTrend di riferimento (implementazione indipendente)
static void RefWT(const std::vector<MqlRates>& b, size_t n, std::vector<double>& w1, std::vector<double>& w2) {
  std::vector<double> ap(n), esa(n), d(n), ci(n);
  w1.assign(n, 0); w2.assign(n, 0);
  double a1 = 2.0 / 11.0, a2 = 2.0 / 22.0;
  for (size_t i = 0; i < n; i++) {
    ap[i] = (b[i].high + b[i].low + b[i].close) / 3.0;
    esa[i] = i ? a1 * ap[i] + (1 - a1) * esa[i - 1] : ap[i];
    double dev = std::fabs(ap[i] - esa[i]);
    d[i] = i ? a1 * dev + (1 - a1) * d[i - 1] : dev;
    ci[i] = d[i] > 0 ? (ap[i] - esa[i]) / (0.015 * d[i]) : 0.0;
    w1[i] = i ? a2 * ci[i] + (1 - a2) * w1[i - 1] : ci[i];
    size_t k = std::min<size_t>(4, i + 1);
    double s = 0; for (size_t j = 0; j < k; j++) s += w1[i - j];
    w2[i] = s / k;
  }
}
static std::vector<MqlRates> SerieSintetica(size_t n) {
  std::vector<MqlRates> v(n);
  double prev = 3000;
  for (size_t i = 0; i < n; i++) {
    double c = 3000 + 9.0 * std::sin(i / 7.0) + 4.0 * std::sin(i / 2.3) + 0.03 * i;
    MqlRates r{};
    r.open = prev; r.close = c; r.high = std::max(prev, c) + 0.9 + 0.3 * std::sin(i * 1.7); r.low = std::min(prev, c) - 0.9 - 0.3 * std::cos(i * 1.3);
    v[i] = r; prev = c;
  }
  return v;
}
// Indice c (>= 100) con incrocio ribassista (dir=-1) o rialzista (+1) o assente (0) sulla barra c.
static int CercaBarra(const std::vector<MqlRates>& b, int dir) {
  std::vector<double> w1, w2;
  RefWT(b, b.size(), w1, w2);
  for (int c = (int)b.size() - 2; c >= 100; c--) {
    int d = 0;
    if (w1[c] > w2[c] && w1[c - 1] <= w2[c - 1]) d = 1;
    else if (w1[c] < w2[c] && w1[c - 1] >= w2[c - 1]) d = -1;
    if (d == dir) return c;
  }
  return -1;
}
// Carica sul 100k le barre 0..c+1 in modo che la barra c+1 sia quella in formazione adesso.
static void CaricaBarre(Env& e, const std::vector<MqlRates>& serie, int c) {
  long srv = g_utc_ms / 1000 + e.T100.server_offset;
  long cur = srv - srv % 900;
  e.T100.m15.clear();
  for (int i = 0; i <= c + 1; i++) { MqlRates r = serie[i]; r.time = cur - (long)(c + 1 - i) * 900; e.T100.m15.push_back(r); }
}

// ------------------------------------------------------------------ scenari comuni
// Trade WT67 BUY 1,00 a 3000 (SL 2990, TP 3010) aperto alle 15:40 e copia aperta a 2995.
static long ApriCopiaBuy(Env& e) {
  e.Start();
  e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
  long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
  e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
  e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
  return src;
}

#include "test_wt67.inc"

int main(int argc, char** argv) {
  g_base = argc > 1 ? argv[1] : "build/work";
  string report = argc > 2 ? argv[2] : "";
  string pyScript = argc > 3 ? argv[3] : "";
  g_verbose = getenv("WTSL_VERBOSE") != nullptr;
  fs::create_directories(g_base);
  std::cout << "WTSL-50%ercole - banco di prova simulato\n";

  // ---------------------------------------------------------------- T00 attesa del trade reale
  {
    Env e("T00_attesa_trade_reale");
    e.Start();
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("[NESSUN_TRADE_100K]");
    Esito("T00", "Incrocio confermato ma nessuna posizione WT67 sul 100k", "0 ordini, stato NESSUN_TRADE_100K",
          std::to_string(e.Opens()) + " ordini" + (e.J50("[NESSUN_TRADE_100K]") ? ", stato NESSUN_TRADE_100K" : ""), ok);
  }
  // ---------------------------------------------------------------- T01 BUY
  {
    Env e("T01_buy");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
    int prima = 0;
    for (double b = 2999.0; b > 2995.5; b -= 1.0) { e.Tick(b, b + 0.30, b - 0.30, b); prima += e.Opens(); }
    e.Tick(2995.50, 2995.80, 2994.70, 2995.00);        // 50k gia' a 2995 ma 100k solo a -450
    int conMeno450 = e.Opens();
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);        // tutte le condizioni
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = prima == 0 && conMeno450 == 0 && e.Opens() == 1 && e.Copies() == 1 && OrdineCorretto(e, 0, 2995.00, 2990.00, 3010.00, src);
    Esito("T01", "BUY: 100k compra a 3000 SL 2990 TP 3010, 50k compra a 2995",
          "1 ordine BUY 0.50 @2995.00 SL 2990.00 TP 3010.00 FOK, lordo -250.00/+750.00; nessun ordine con 100k a -450",
          std::to_string(e.Opens()) + " ordine/i: " + DescriviOrdine(e) + "; con 100k a -450: " + std::to_string(conMeno450) + " ordini", ok);
  }
  // ---------------------------------------------------------------- T02 SELL
  {
    Env e("T02_sell");
    e.Start();
    e.Tick(3000.00, 3000.30, 3000.00, 3000.30);
    long src = (long)e.WT67(1, 3000.00, 3010.00, 2990.00);
    for (double a = 3001.0; a < 3004.5; a += 1.0) e.Tick(a - 0.30, a, a, a + 0.30);
    e.Tick(3004.70, 3005.00, 3005.00, 3005.30);
    for (int i = 0; i < 20; i++) e.Tick(3004.70, 3005.00, 3005.00, 3005.30);
    bool ok = e.Opens() == 1 && e.Copies() == 1 && OrdineCorretto(e, 1, 3005.00, 3010.00, 2990.00, src);
    Esito("T02", "SELL: 100k vende a 3000 SL 3010 TP 2990, 50k vende a 3005",
          "1 ordine SELL 0.50 @3005.00 SL 3010.00 TP 2990.00 FOK, lordo -250.00/+750.00",
          std::to_string(e.Opens()) + " ordine/i: " + DescriviOrdine(e), ok);
  }
  // ---------------------------------------------------------------- T03 SPREAD
  {
    Env e("T03_spread");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 30; i++) e.Tick(2995.00, 2995.30, 2994.90, 2995.20);
    int conSpread = e.Opens();
    bool log260 = e.J50("stop -260.00") && e.J50("target 740.00");
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    for (int i = 0; i < 30; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    e.Tick(2995.00, 2995.30, 2994.90, 2995.20);
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = conSpread == 0 && log260 && e.Opens() == 1 && e.Copies() == 1 && OrdineCorretto(e, 0, 2995.00, 2990.00, 3010.00, src);
    Esito("T03", "SPREAD: 100k a -500 ma il 50k compra solo a 2995.20, poi torna a 2995.00",
          "0 ordini a 2995.20 (registrato stop -260.00 / target 740.00); poi una sola apertura a 2995.00",
          std::to_string(conSpread) + " ordini a 2995.20" + (log260 ? " (registrato -260.00/740.00)" : " (log importi mancante)")
              + "; dopo il ritorno: " + std::to_string(e.Opens()) + " apertura: " + DescriviOrdine(e), ok);
  }
  // ---------------------------------------------------------------- T04 movimento 4.99
  {
    Env e("T04_499_punti");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 20; i++) e.Tick(2995.01, 2995.31, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("movimento insufficiente");
    Esito("T04", "Movimento di soli 4.99 punti (Bid 2995.01, P/L -499) con 50k a 2995.00", "0 ordini",
          std::to_string(e.Opens()) + " ordini" + (e.J50("movimento insufficiente") ? ", motivo: movimento insufficiente" : ""), ok);
  }
  {
    Env e("T04b_499_punti_perdita_ok");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00, 1.20);   // 1,20 lotti: a 4,99 punti il P/L e' gia' -598,80
    for (int i = 0; i < 20; i++) e.Tick(2995.01, 2995.31, 2994.70, 2995.00);
    int a499 = e.Opens();
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = a499 == 0 && e.Opens() == 1;
    Esito("T04b", "4.99 punti con P/L gia' -598.80 (sorgente 1.20 lotti); controllo a 5.00 punti",
          "0 ordini a 4.99 punti; 1 ordine quando il movimento arriva a 5.00",
          std::to_string(a499) + " ordini a 4.99; " + std::to_string(e.Opens()) + " a 5.00", ok);
  }
  // ---------------------------------------------------------------- T05 perdita 499
  {
    Env e("T05_perdita_499");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.T100.positions[0].has_profit_override = true;
    e.T100.positions[0].profit_override = -499.00;
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    int a499 = e.Opens();
    e.T100.positions[0].profit_override = -499.99;
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    int a49999 = e.Opens();
    e.T100.positions[0].profit_override = -500.00;
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = a499 == 0 && a49999 == 0 && e.Opens() == 1 && e.J50("perdita insufficiente");
    Esito("T05", "Perdita di soli 499 (e 499.99) con movimento 5.00 e 50k a 2995.00",
          "0 ordini con -499.00 e -499.99; 1 ordine quando POSITION_PROFIT arriva a -500.00",
          std::to_string(a499) + " ordini a -499.00, " + std::to_string(a49999) + " a -499.99, " + std::to_string(e.Opens()) + " a -500.00", ok);
  }
  // ---------------------------------------------------------------- T06 sorgente gia' chiuso
  {
    Env e("T06_sorgente_chiuso");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    ulong t = e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.90, 2995.20);   // soglie 100k ok, 50k non ancora
    BrokerClose(e.T100, t, DEAL_REASON_EXPERT, 2995.00);
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("Attesa annullata");
    Esito("T06", "Trade sorgente chiuso prima che il 50k arrivi a 2995.00", "0 ordini, attesa annullata",
          std::to_string(e.Opens()) + " ordini" + (e.J50("Attesa annullata") ? ", 'Attesa annullata' registrato" : ""), ok);
  }
  // ---------------------------------------------------------------- T07 17:30 esatte e controlli di orario
  {
    Env e("T07_1730_esatte", 2026, 7, 15, 17, 20, 0);
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.SetRome(17, 29, 58);
    e.Tick(2995.00, 2995.30, 2994.90, 2995.20, 0);
    e.SetRome(17, 30, 0);
    e.Q100(2995.00, 2995.30);
    e.Q50(2994.70, 2995.00);                   // soglia raggiunta alle 17:30:00 esatte
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("fuori finestra");
    Esito("T07", "Soglie e prezzo 50k raggiunti alle 17:30:00 esatte (Europe/Rome, ora legale)", "0 ordini",
          std::to_string(e.Opens()) + " ordini" + (e.J50("fuori finestra") ? ", motivo: fuori finestra" : ""), ok);
  }
  {
    Env e("T07b_172959", 2026, 7, 15, 17, 20, 0);
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.SetRome(17, 29, 59);
    e.Q100(2995.00, 2995.30);
    e.Q50(2994.70, 2995.00);
    bool ok = e.Opens() == 1;
    Esito("T07b", "Controllo: stesse condizioni alle 17:29:59", "1 ordine", std::to_string(e.Opens()) + " ordine/i", ok);
  }
  {
    Env e("T07c_153000", 2026, 7, 15, 15, 29, 50);
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.SetRome(15, 30, 0);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.Q100(2995.00, 2995.30);
    e.Q50(2994.70, 2995.00);
    bool ok = e.Opens() == 1;
    Esito("T07c", "Trade e soglie alle 15:30:00 esatte (inizio incluso)", "1 ordine", std::to_string(e.Opens()) + " ordine/i", ok);
  }
  {
    Env e("T07d_sorgente_prima", 2026, 7, 15, 15, 29, 50);
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.SetRome(15, 29, 59);
    e.WT67(0, 3000.00, 2990.00, 3010.00);      // aperto un secondo prima della finestra
    e.SetRome(15, 35, 0);
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("fuori dalla sessione corrente");
    Esito("T07d", "Trade 100k aperto alle 15:29:59, soglie alle 15:35", "0 ordini (sessione diversa)",
          std::to_string(e.Opens()) + " ordini", ok);
  }
  {
    Env e("T07e_inverno", 2026, 1, 15, 16, 0, 0, 1);
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    int alle16 = e.Opens();
    Env f("T07f_inverno_1730", 2026, 1, 15, 17, 25, 0, 1);
    f.Start();
    f.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    f.WT67(0, 3000.00, 2990.00, 3010.00);
    f.SetRome(17, 30, 0);
    f.Q100(2995.00, 2995.30);
    f.Q50(2994.70, 2995.00);
    bool ok = alle16 == 1 && f.Opens() == 0;
    Esito("T07e", "Ora solare (gennaio, UTC+1): 16:00 dentro, 17:30:00 fuori", "1 ordine alle 16:00; 0 alle 17:30:00",
          std::to_string(alle16) + " alle 16:00; " + std::to_string(f.Opens()) + " alle 17:30:00", ok);
  }
  // ---------------------------------------------------------------- T08 riavvi
  {
    Env e("T08_riavvio_copia_aperta");
    ApriCopiaBuy(e);
    int prima = e.Opens();
    e.Restart50();
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    e.Restart100();
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = prima == 1 && e.Opens() == 1 && e.Copies() == 1;
    Esito("T08", "Riavvio di entrambi gli EA con la copia aperta e condizioni ancora valide", "nessuna seconda copia (1 ordine totale)",
          std::to_string(e.Opens()) + " ordini totali, " + std::to_string(e.Copies()) + " copie aperte", ok);
  }
  {
    Env e("T08b_riavvio_copia_chiusa");
    long src = ApriCopiaBuy(e);
    e.Tick(2990.10, 2990.40, 2989.90, 2990.20);   // SL della copia toccato sul 50k, 100k ancora aperto
    int copieDopoSL = e.Copies();
    e.Restart50();
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = copieDopoSL == 0 && e.Opens() == 1 && e.Copies() == 0 && e.RegStato(src, 0) == 5;
    Esito("T08b", "Copia chiusa dallo SL sul 50k, riavvio, trade 100k ancora aperto e di nuovo in soglia", "nessuna seconda copia",
          std::to_string(e.Opens()) + " ordini totali, registro: " + std::to_string(e.RegStato(src, 0)) + " (5 = CHIUSA)", ok);
  }
  {
    Env e("T08c_timeout");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.T50.forced.push_back({TRADE_RETCODE_TIMEOUT, false});
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    int primaRiavvio = e.Opens();
    e.Restart50();
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = primaRiavvio == 1 && e.Opens() == 1 && e.Copies() == 0 && e.RegStato(src, 0) == 3;
    Esito("T08c", "Timeout del broker senza esito certo, poi riavvio", "nessun reinvio (registro INCERTA)",
          std::to_string(e.Opens()) + " invii totali, registro " + std::to_string(e.RegStato(src, 0)) + " (3 = INCERTA)", ok);
  }
  {
    Env e("T08d_timeout_eseguito");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.T50.forced.push_back({TRADE_RETCODE_TIMEOUT, true});
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    e.Restart50();
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 1 && e.Copies() == 1 && e.RegStato(src, 0) == 2;
    Esito("T08d", "Timeout ma ordine eseguito dal server, poi riavvio", "1 sola copia, collegata al registro (APERTA)",
          std::to_string(e.Opens()) + " invii, " + std::to_string(e.Copies()) + " copie, registro " + std::to_string(e.RegStato(src, 0)), ok);
  }
  {
    Env e("T08e_registro_cancellato");
    long src = ApriCopiaBuy(e);
    e.Tick(2990.10, 2990.40, 2989.90, 2990.20);   // copia chiusa da SL
    e.Restart50();
    g_term = &e.T50;
    fs::remove(e.dir + "/common/WTSL50ercole/registro_" + std::to_string(L50) + "_da_" + std::to_string(L100) + ".txt");
    e.Restart50();
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 1 && e.RegStato(src, 0) == 5 && e.J50("Registro ricostruito dallo storico");
    Esito("T08e", "File del registro cancellato, riavvio, condizioni di nuovo valide", "nessuna seconda copia (registro ricostruito dallo storico)",
          std::to_string(e.Opens()) + " ordini totali" + (e.J50("Registro ricostruito") ? ", registro ricostruito" : ""), ok);
  }
  {
    Env e("T08f_riavvio_durante_invio");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    // simula un arresto tra la registrazione su disco e la risposta del broker
    string reg = e.dir + "/common/WTSL50ercole/registro_" + std::to_string(L50) + "_da_" + std::to_string(L100) + ".txt";
    { std::ofstream o(reg); o << "WTSL50REG 1\r\n" << src << ";0;1;" << (g_utc_ms / 1000) << ";20260715;1;0;0\r\nfine=1\r\n"; }
    e.Restart50();
    for (int i = 0; i < 20; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.RegStato(src, 0) == 3;
    Esito("T08f", "Riavvio con voce di registro rimasta 'INVIO'", "nessun invio (voce convertita in INCERTA)",
          std::to_string(e.Opens()) + " invii, registro " + std::to_string(e.RegStato(src, 0)), ok);
  }
  // ---------------------------------------------------------------- T09 inversione
  {
    Env e("T09_inversione_fuori_orario");
    long src = ApriCopiaBuy(e);
    e.SetRome(18, 10, 0);
    e.Tick(2992.70, 2993.00, 2992.70, 2993.00, 0);
    BrokerClose(e.T100, (ulong)src, DEAL_REASON_EXPERT, 2992.70);
    e.WT67(1, 2992.70, 3002.70, 2982.70);
    for (int i = 0; i < 10; i++) e.Tick(2992.70, 2993.00, 2992.70, 2993.00);
    int chiusure = e.Closes();
    for (int i = 0; i < 10; i++) e.Tick(2997.40, 2997.70, 2997.70, 2998.00);   // nuovo SELL in soglia ma alle 18:10
    bool ok = chiusure == 1 && e.Copies() == 0 && e.Opens() == 1 && e.J100("incrocio WaveTrend opposto confermato");
    Esito("T09", "Incrocio opposto alle 18:10 (fuori orario): WT67 chiude il BUY e apre SELL",
          "copia chiusa anche fuori orario; nuovo SELL non copiato (fuori finestra)",
          std::to_string(chiusure) + " chiusura, " + std::to_string(e.Copies()) + " copie aperte, " + std::to_string(e.Opens()) + " aperture totali", ok);
  }
  {
    Env e("T09b_inversione_in_sessione");
    ApriCopiaBuy(e);
    long src = (long)e.T100.positions[0].identifier;
    e.SetRome(16, 30, 0);
    e.Tick(2993.00, 2993.30, 2993.00, 2993.30, 0);
    BrokerClose(e.T100, (ulong)src, DEAL_REASON_EXPERT, 2993.00);
    long nuovo = (long)e.WT67(1, 2993.00, 3003.00, 2983.00);
    for (int i = 0; i < 10; i++) e.Tick(2993.00, 2993.30, 2993.00, 2993.30);
    int chiusure = e.Closes();
    int apertureDopoInversione = e.Opens();
    for (int i = 0; i < 10; i++) e.Tick(2997.69, 2997.99, 2998.00, 2998.30);   // 100k solo 4.99 sopra
    int a499 = e.Opens();
    e.Tick(2997.70, 2998.00, 2998.00, 2998.30);
    bool ok = chiusure == 1 && apertureDopoInversione == 1 && a499 == 1 && e.Opens() == 2 && OrdineCorretto(e, 1, 2998.00, 3003.00, 2983.00, nuovo);
    Esito("T09b", "Incrocio opposto alle 16:30: chiusura copia, il nuovo SELL deve raggiungere la sua soglia",
          "copia BUY chiusa; nessuna apertura finche' il SELL non e' a -5.00/-500; poi SELL 0.50 @2998.00 SL 3003.00 TP 2983.00",
          std::to_string(chiusure) + " chiusura; aperture: " + std::to_string(apertureDopoInversione) + " subito, " + std::to_string(a499)
              + " a 4.99, " + std::to_string(e.Opens()) + " in soglia: " + DescriviOrdine(e), ok);
  }
  {
    Env e("T09c_chiusura_ea_senza_incrocio");
    long src = ApriCopiaBuy(e);
    e.SetRome(16, 10, 0);
    e.Tick(2996.00, 2996.30, 2996.00, 2996.30, 0);
    BrokerClose(e.T100, (ulong)src, DEAL_REASON_EXPERT, 2996.00);   // nessuna riapertura, nessuna barra M15 disponibile
    for (int i = 0; i < 20; i++) e.Tick(2996.00, 2996.30, 2996.00, 2996.30);
    bool ok = e.Closes() == 0 && e.Copies() == 1;
    Esito("T09c", "100k chiuso dall'EA senza incrocio opposto confermato", "copia lasciata aperta con i suoi SL/TP",
          std::to_string(e.Closes()) + " chiusure, " + std::to_string(e.Copies()) + " copie aperte", ok);
  }
  {
    Env e("T09d_incrocio_wavetrend");
    long src = ApriCopiaBuy(e);
    std::vector<MqlRates> serie = SerieSintetica(320);
    int c = CercaBarra(serie, -1);
    e.SetRome(16, 20, 30);
    e.Tick(2996.00, 2996.30, 2996.00, 2996.30, 0);
    CaricaBarre(e, serie, c);
    BrokerClose(e.T100, (ulong)src, DEAL_REASON_EXPERT, 2996.00);   // chiusura senza riapertura
    for (int i = 0; i < 10; i++) e.Tick(2996.00, 2996.30, 2996.00, 2996.30);
    bool ok = c > 0 && e.Closes() == 1 && e.Copies() == 0;
    Esito("T09d", "100k chiuso dall'EA con incrocio WaveTrend ribassista sulla M15 chiusa precedente (senza riapertura)",
          "copia chiusa", "barra di incrocio " + std::to_string(c) + ", " + std::to_string(e.Closes()) + " chiusure, " + std::to_string(e.Copies()) + " copie aperte", ok);
  }
  {
    Env e("T09e_nessun_incrocio_wavetrend");
    long src = ApriCopiaBuy(e);
    std::vector<MqlRates> serie = SerieSintetica(320);
    int c = CercaBarra(serie, 0);
    e.SetRome(16, 20, 30);
    e.Tick(2996.00, 2996.30, 2996.00, 2996.30, 0);
    CaricaBarre(e, serie, c);
    BrokerClose(e.T100, (ulong)src, DEAL_REASON_EXPERT, 2996.00);
    for (int i = 0; i < 10; i++) e.Tick(2996.00, 2996.30, 2996.00, 2996.30);
    bool ok = c > 0 && e.Closes() == 0 && e.Copies() == 1;
    Esito("T09e", "100k chiuso dall'EA, barre M15 disponibili ma nessun incrocio sulla barra confermata", "copia lasciata aperta",
          "barra " + std::to_string(c) + ", " + std::to_string(e.Closes()) + " chiusure, " + std::to_string(e.Copies()) + " copie aperte", ok);
  }
  {
    Env e("T09f_sl_100k");
    long src = ApriCopiaBuy(e);
    BrokerClose(e.T100, (ulong)src, DEAL_REASON_SL, 2990.00);
    for (int i = 0; i < 10; i++) e.Tick(2990.00, 2990.30, 2990.10, 2990.40);
    bool aperta = e.Copies() == 1 && e.Closes() == 0;
    e.Tick(2989.90, 2990.20, 2989.90, 2990.20);   // lo SL della copia scatta al broker
    bool ok = aperta && e.Copies() == 0 && e.Closes() == 0 && e.Others() == 0;
    Esito("T09f", "100k chiuso da SL mentre il Bid del 50k e' 2990.10", "copia non toccata dal bot; si chiude col proprio SL al broker",
          string(aperta ? "copia ancora aperta, " : "copia chiusa dal bot, ") + std::to_string(e.Closes()) + " chiusure del bot, " + std::to_string(e.Others())
              + " modifiche SL/TP; dopo 2989.90: " + std::to_string(e.Copies()) + " copie", ok);
  }
  // ---------------------------------------------------------------- T10 limite giornaliero
  {
    Env e("T10_limite_4", 2026, 7, 15, 15, 31, 0);
    e.Start();
    int copie = 0;
    for (int k = 0; k < 5; k++) {
      e.Tick(2999.70, 3000.00, 2999.70, 3000.00, 1000);
      e.WT67(0, 3000.00, 2990.00, 3010.00);
      for (int i = 0; i < 5; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
      copie = e.Opens();
      e.Tick(2989.90, 2990.20, 2989.90, 2990.20);   // SL su entrambi i conti
      e.Tick(2989.90, 2990.20, 2989.90, 2990.20);
    }
    int oggi = e.Opens();
    bool limite = e.J50("[LIMITE_GIORNALIERO]");
    // giorno dopo
    e.Adv(86400000L);                             // stesso orario del giorno seguente
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00, 1000);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 5; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = oggi == 4 && limite && e.Opens() == 5;
    Esito("T10", "Cinque trade WT67 in soglia nella stessa sessione, poi il giorno dopo", "4 aperture, la quinta bloccata; il giorno dopo di nuovo ammessa",
          std::to_string(oggi) + " aperture oggi" + (limite ? " (LIMITE_GIORNALIERO)" : "") + ", totale dopo il giorno seguente " + std::to_string(e.Opens()), ok);
    (void)copie;
  }
  // ---------------------------------------------------------------- T11 una posizione alla volta
  {
    Env e("T11_una_alla_volta");
    long src = ApriCopiaBuy(e);
    BrokerClose(e.T100, (ulong)src, DEAL_REASON_CLIENT, 2995.00);
    e.Tick(2999.70, 3000.00, 2995.00, 2995.30);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 1 && e.Copies() == 1;
    Esito("T11", "Copia del trade A ancora aperta mentre un nuovo trade B del 100k va in soglia", "nessuna seconda posizione",
          std::to_string(e.Opens()) + " aperture, " + std::to_string(e.Copies()) + " copie aperte", ok);
  }
  // ---------------------------------------------------------------- T12 disconnessioni
  {
    Env e("T12_disconnessione_50k");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.T50.connected = false;
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    int disconnesso = (int)e.T50.sent.size();
    e.T50.connected = true;
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    e.T50.connected = false;
    const MockPosition* p = e.Copy();
    double sl = p ? p->sl : 0, tp = p ? p->tp : 0;
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    p = e.Copy();
    bool ok = disconnesso == 0 && e.Opens() == 1 && p && p->sl == sl && p->tp == tp && e.Others() == 0 && e.J50("[SOSPESO_50K]");
    Esito("T12", "Terminale 50k disconnesso con condizioni valide, poi riconnesso", "nessuna richiesta da disconnesso; 1 copia alla riconnessione; SL/TP intatti",
          std::to_string(disconnesso) + " richieste da disconnesso, " + std::to_string(e.Opens()) + " copie, SL/TP " + F2(sl) + "/" + F2(tp)
              + ", modifiche " + std::to_string(e.Others()), ok);
  }
  {
    Env e("T12b_100k_fermo");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.Tick(2995.00, 2995.30, 2994.90, 2995.20);   // 100k in soglia, 50k non ancora
    e.Adv(3000);                                  // il terminale 100k smette di aggiornare
    e.Q50(2994.70, 2995.00);
    int fermo = e.Opens();
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = fermo == 0 && e.Opens() == 1 && e.J50("non aggiornati");
    Esito("T12b", "Dati del 100k vecchi di 3 s (terminale 100k fermo)", "0 ordini finche' i dati non tornano freschi; poi 1",
          std::to_string(fermo) + " ordini con dati vecchi, " + std::to_string(e.Opens()) + " dopo l'aggiornamento", ok);
  }
  {
    Env e("T12c_100k_disconnesso");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.T100.connected = false;
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("terminale 100k disconnesso");
    Esito("T12c", "Terminale 100k disconnesso dal server", "0 ordini", std::to_string(e.Opens()) + " ordini", ok);
  }
  // ---------------------------------------------------------------- T13 rifiuti del broker
  {
    Env e("T13_rifiuto_fok");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.T50.forced.push_back({TRADE_RETCODE_REJECT, false});
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    int primo = e.Opens();
    bool regRif = e.RegStato(src, 0) == 4;
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00, 300);   // 3 s: in pausa
    int inPausa = e.Opens();
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00, 300);   // oltre 5 s
    bool ok = primo == 1 && regRif && inPausa == 1 && e.Opens() == 2 && e.Copies() == 1 && e.J50("RIFIUTATO") && e.J50("richiesta rifiutata");
    Esito("T13", "Il broker rifiuta l'esecuzione integrale (REJECT)", "rifiuto registrato col motivo, nessuna posizione; nuovo tentativo dopo 5 s; 1 sola copia",
          std::to_string(primo) + " invio rifiutato (registro " + (regRif ? "RIFIUTATA" : "?") + "), " + std::to_string(inPausa) + " in pausa, "
              + std::to_string(e.Opens()) + " invii totali, " + std::to_string(e.Copies()) + " copia", ok);
  }
  {
    Env e("T13b_livelli_rifiutati");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    long src = (long)e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 3; i++) e.T50.forced.push_back({TRADE_RETCODE_INVALID_STOPS, false});
    for (int i = 0; i < 60; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00, 500);
    bool ok = e.Opens() == 3 && e.Copies() == 0 && e.J50("livelli SL/TP rifiutati") && e.J50("tentativi esauriti") && e.RegStato(src, 0) == 4;
    Esito("T13b", "Il broker rifiuta SL/TP per tre volte", "motivo registrato, 3 tentativi poi stop; nessuna posizione",
          std::to_string(e.Opens()) + " invii, " + std::to_string(e.Copies()) + " copie" + (e.J50("tentativi esauriti") ? ", tentativi esauriti" : ""), ok);
  }
  {
    Env e("T13c_fok_non_ammesso");
    e.T50.filling = SYMBOL_FILLING_IOC;
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("Fill or Kill");
    Esito("T13c", "Simbolo del 50k senza modalita' Fill or Kill", "0 ordini, motivo registrato", std::to_string(e.Opens()) + " ordini", ok);
  }
  {
    Env e("T13d_slittamento");
    e.T50.slippage = 0.10;
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    const MockPosition* p = e.Copy();
    bool ok = e.Opens() == 1 && p && std::fabs(p->price_open - 2995.10) < 1e-9 && e.J50("slittamento") && e.J50("lordo allo stop -255.00");
    Esito("T13d", "Esecuzione con slittamento di +0.10 sul 50k", "1 copia, avviso registrato con i nuovi importi lordi (-255.00/+745.00)",
          std::to_string(e.Opens()) + " copia a " + (p ? F2(p->price_open) : "-") + (e.J50("slittamento") ? ", avviso registrato" : ""), ok);
  }
  // ---------------------------------------------------------------- T14 casi di sicurezza
  {
    Env e("T14_due_posizioni_wt67");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("[SORGENTE_AMBIGUA]");
    Esito("T14", "Due posizioni WT67 aperte sul 100k", "0 ordini (sorgente ambigua)", std::to_string(e.Opens()) + " ordini", ok);
  }
  {
    Env e("T14b_sorgente_senza_sl");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 0.0, 3010.00);
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("[SORGENTE_SENZA_LIVELLI]");
    Esito("T14b", "Trade 100k senza SL", "0 ordini", std::to_string(e.Opens()) + " ordini", ok);
  }
  {
    Env e("T14c_registro_non_scrivibile");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.T50.fail_file_writes = true;
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = e.Opens() == 0 && e.J50("ordine NON inviato");
    Esito("T14c", "Registro copie non scrivibile su disco", "0 ordini (senza registrazione preventiva non si invia)", std::to_string(e.Opens()) + " ordini", ok);
  }
  {
    Env e("T14d_100k_non_invia_ordini");
    long src = ApriCopiaBuy(e);
    for (int i = 0; i < 20; i++) e.Tick(2994.00, 2994.30, 2994.00, 2994.30);
    bool ok = e.T100.sent.empty() && src > 0;
    Esito("T14d", "Ruolo sorgente sul conto 100k", "nessuna richiesta OrderSend dal terminale 100k", std::to_string(e.T100.sent.size()) + " richieste", ok);
  }
  // ---------------------------------------------------------------- T15 autotest interno
  {
    Env e("T15_autotest");
    EA* a = e.Make();
    a->InpAutoTest = true;
    g_term = &e.T50;
    a->OnInit();
    bool ok = a->g_testKo == 0 && a->g_testOk > 20;
    Esito("T15", "Autotest interno dell'EA (InpAutoTest=true) su conto USD, contratto 100", "tutte le verifiche OK",
          std::to_string(a->g_testOk) + " OK, " + std::to_string(a->g_testKo) + " falliti", ok);
    delete a;
  }
  // ---------------------------------------------------------------- T16 WaveTrend contro riferimento
  {
    Env e("T16_wavetrend");
    EA* a = e.Make();
    std::vector<MqlRates> serie = SerieSintetica(320);
    for (size_t i = 0; i < serie.size(); i++) a->g_rates[i] = serie[i];
    a->WT_Calcola((int)serie.size());
    std::vector<double> w1, w2;
    RefWT(serie, serie.size(), w1, w2);
    double maxd = 0;
    string csv = g_base + "/wt_series.csv";
    std::ofstream o(csv);
    o << "i,high,low,close,wt1,wt2\n";
    for (size_t i = 0; i < serie.size(); i++) {
      maxd = std::max(maxd, std::max(std::fabs(w1[i] - a->g_wt1[i]), std::fabs(w2[i] - a->g_wt2[i])));
      char b[256]; snprintf(b, sizeof b, "%zu,%.10f,%.10f,%.10f,%.12f,%.12f\n", i, serie[i].high, serie[i].low, serie[i].close, a->g_wt1[i], a->g_wt2[i]);
      o << b;
    }
    o.close();
    string py = "non eseguito";
    bool pyOk = true;
    if (!pyScript.empty()) {
      string cmd = "python3 -I '" + pyScript + "' '" + csv + "'";
      FILE* p = popen(cmd.c_str(), "r");
      char b[512]; py.clear();
      while (p && fgets(b, sizeof b, p)) py += b;
      if (p) pclose(p);
      while (!py.empty() && (py.back() == '\n' || py.back() == '\r')) py.pop_back();
      pyOk = py.rfind("OK", 0) == 0;
    }
    bool ok = maxd < 1e-9 && pyOk;
    char b[64]; snprintf(b, sizeof b, "%.2e", maxd);
    Esito("T16", "WaveTrend 10/21/4 dell'EA contro due implementazioni indipendenti (C++ e pandas)", "stessi valori e stessi incroci",
          string("scarto massimo C++ ") + b + "; pandas: " + py, ok);
    delete a;
  }

  // ---------------------------------------------------------------- T17 verifica finale subito prima dell'invio
  {
    Env e("T17_verifica_finale_100k");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    ulong src = e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.Tick(2995.00, 2995.30, 2994.90, 2995.20);
    int letture = 0;
    g_hook_lettura = [&](const string& path) {
      if (path.find("canale_") == string::npos) return;
      if (++letture != 2) return;              // seconda lettura = verifica finale
      MockTerminal* prima = g_term;
      g_term = &e.T100;
      BrokerClose(e.T100, src, DEAL_REASON_EXPERT, 2995.00);
      e.ea100->OnTimer();                      // il 100k pubblica la chiusura
      g_term = prima;
    };
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    g_hook_lettura = nullptr;
    for (int i = 0; i < 10; i++) e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = letture >= 2 && e.Opens() == 0 && e.J50("Verifica finale");
    Esito("T17", "Il 100k chiude il trade tra il primo controllo e la verifica finale prima dell'invio", "0 ordini",
          std::to_string(e.Opens()) + " ordini" + (e.J50("Verifica finale") ? ", bloccato dalla verifica finale" : ""), ok);
  }
  {
    Env e("T17b_verifica_finale_50k");
    e.Start();
    e.Tick(2999.70, 3000.00, 2999.70, 3000.00);
    e.WT67(0, 3000.00, 2990.00, 3010.00);
    e.Tick(2995.00, 2995.30, 2994.90, 2995.20);
    int letture = 0;
    g_hook_lettura = [&](const string& path) {
      if (path.find("canale_") == string::npos) return;
      if (++letture == 2) { e.T50.bid = 2994.90; e.T50.ask = 2995.20; }   // lo spread si allarga in quell'istante
    };
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    g_hook_lettura = nullptr;
    int allargato = e.Opens();
    e.Tick(2995.00, 2995.30, 2994.70, 2995.00);
    bool ok = allargato == 0 && e.Opens() == 1;
    Esito("T17b", "L'Ask del 50k passa da 2995.00 a 2995.20 durante la verifica finale", "0 ordini in quell'istante; 1 al ritorno a 2995.00",
          std::to_string(allargato) + " ordini con spread allargato, " + std::to_string(e.Opens()) + " dopo", ok);
  }

  TestWT67();

  int ok = 0, ko = 0;
  for (auto& r : g_righe) (r.ok ? ok : ko)++;
  std::cout << "\nRisultato: " << ok << " OK, " << ko << " falliti\n";
  if (!report.empty()) {
    std::ofstream o(report);
    o << "# Risultati dei test simulati di WT67ercole.mq5 e WTSL-50%ercole.mq5\n\n";
    o << "Generato da `tests/run_tests.sh`. Prove **simulate**: il sorgente `.mq5` reale e' compilato con g++ su un simulatore "
         "dell'API MT5 (`tests/mt5_shim.h`) con due conti finti in USD, XAUUSD a 2 decimali e contratto da 100 once. "
         "Non sono prove su terminali MetaTrader 5.\n\n"
         "Serie T: WTSL-50%ercole (sorgente 100k e ricevitore 50k). Serie W: WT67ercole (strategia 100k) su candele M15 sintetiche. "
         "E01: i tre EA insieme, dall'incrocio WaveTrend alla copia sul 50k e alla chiusura sull'incrocio opposto.\n\n";
    o << "Esito complessivo: **" << ok << " OK, " << ko << " falliti**\n\n";
    o << "| ID | Prova | Risultato atteso | Risultato osservato | Esito |\n|---|---|---|---|---|\n";
    for (auto& r : g_righe) {
      auto esc = [](string s) { for (size_t p = 0; (p = s.find('|', p)) != string::npos; p += 2) s.replace(p, 1, "\\|"); return s; };
      o << "| " << r.id << " | " << esc(r.nome) << " | " << esc(r.atteso) << " | " << esc(r.osservato) << " | " << (r.ok ? "OK" : "**KO**") << " |\n";
    }
  }
  return ko == 0 ? 0 : 1;
}
