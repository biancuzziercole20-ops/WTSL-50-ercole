# Pseudocodice per l'Expert Advisor MT5 (v0.1)

Lo pseudocodice segue la sintassi MQL5 dove serve a fissare un'API (`CopyRates`, `OrderCalcProfit`,
`OnTradeTransaction`…). Il resto è descrittivo. Regole e ipotesi citate (`[R]`, `[I-n]`, `[A]`) sono quelle
di [01-specifica.md](01-specifica.md).

## 1. Struttura

```
WTSL50.mq5                 EA: un'istanza per grafico e simbolo
├── Config.mqh             lettura di simboli.csv e annotazioni.csv, validazione del simbolo
├── Bars.mqh               barre H4 e MN native o ricostruite da M1 (allineamento TV) [I-4]
├── Reference.mqh          candela mensile di riferimento, livelli, validità [R][A][I-2]
├── Profile.mqh            profilo volumi a righe fisse, POC [I-5][I-6]
├── Swings.mqh             frattali confermati [I-11]
├── Setup.mqh              macchina a stati per lato [I-8..I-11]
├── Execution.mqh          modi d'ingresso E1/E2/E3, size, ordini [I-14][R]
└── Journal.mqh            registro CSV di ogni decisione e di ogni deal
```

Modalità di esecuzione (`input RunMode`):

| Modo | Riferimento mensile | Intervallo profilo | Ordini |
|---|---|---|---|
| `SOLO_SEGNALI` | annotato o automatico | annotato o automatico | nessuno, solo registro |
| `SEMI_AUTO` (v1) | **annotato** | **annotato** (troncato) o automatico | sì |
| `AUTO` | classificatore [I-1] + [I-2] | automatico [I-6] | sì (solo dopo la Fase 4 del backtest) |

## 2. Input

```cpp
input ENUM_RUN_MODE   RunMode            = SEMI_AUTO;
input ENUM_ENTRY_MODE EntryMode          = ENTRY_CLOSE;  // ENTRY_BREAK | ENTRY_CLOSE | ENTRY_RETEST   [I-14]
input double          RiskPctDefault     = 0.25;         // 0.25 | 0.50, override per trade da annotazioni [R]
input bool            RiskOnEquity       = false;        // false = balance
input double          TargetR            = 2.0;          // [R]
input int             FractalN           = 2;            // [I-11]
input int             LookbackT          = 30;           // barre prima dello sweep in cui cercare T
input double          MaxSweepDepthRM    = 0.15;         // D_max [I-10]
input int             RetestExpiryBars   = 6;            // J [I-14]
input bool            UseEqFilter        = true;         // [I-3]
input bool            UsePocFilter       = true;         // [I-7]
input int             PocMigrationBars   = 6;            // k
input int             MaxTradesPerRefSide= 1;            // [I-16]
input int             RefMaxMonths       = 6;            // [I-2], solo in AUTO
input double          LevelTolerancePctRM= 0.5;          // tolleranza livelli TV↔broker [§2.6]
input int             ServerUtcWinter    = 2;            // nel tester TimeGMT() non è affidabile:
input int             ServerUtcSummer    = 3;            //   l'offset del server si dichiara
input string          SymbolsFile        = "wtsl\\simboli.csv";      // in Common\Files
input string          AnnotationsFile    = "wtsl\\annotazioni.csv";
input long            Magic              = 50050;
```

I parametri per classe (K di rientro, altezza riga, ancora di sessione, lati ammessi) vengono da
`simboli.csv` e non dagli input, così un'istanza su AVGO e una su EURUSD usano lo stesso file `.set`.

## 3. Tipi

```cpp
enum SetupState { IDLE, SWEPT, RECLAIMED, TRIGGERED, ORDER_PENDING, IN_TRADE, DONE, DISCARDED };

struct Reference {
   bool     valid;
   datetime monthOpen, monthClose;     // la candela è usabile solo se monthClose <= ora della decisione
   double   H, L, EQ, RM;
   string   source;                    // "ANNOTAZIONE" | "AUTO"
};

struct Setup {
   int        side;                    // +1 long, -1 short
   SetupState st;
   double     level;                   // L* (long) o H* (short)  [I-8]
   datetime   sweepTime;
   int        barsSinceSweep;
   double     extreme;                 // P_low (long) o P_high (short)
   double     T;                       // livello di trigger [I-11]
   datetime   tTime;
   ulong      orderTicket, positionTicket;
   int        pendingBarsLeft;
   int        tradesOnRef;
   string     lastReason;
};

struct Profile { double rowH; double base; double vol[]; int pocRow; double poc; double total; };
```

## 4. Ciclo principale

```cpp
int OnInit()
{
   cfg = LoadSymbolConfig(SymbolsFile, _Symbol);
   if(!cfg.found)                          return Fail("simbolo non configurato");   // nessun default silenzioso
   if(!ValidateSymbol(cfg))                return Fail("proprietà simbolo incoerenti");
   //   SYMBOL_TRADE_MODE, SYMBOL_VOLUME_MIN/STEP/MAX, SYMBOL_TRADE_TICK_SIZE,
   //   SYMBOL_FILLING_MODE -> trade.SetTypeFillingBySymbol(_Symbol)
   rowH = cfg.rowTicks * cfg.tvMinTick;                      // 24 × mintick TradingView [R]
   ann  = LoadAnnotations(AnnotationsFile, cfg.mt5Symbol);   // riferimenti, intervalli FRVP, rischio
   trade.SetExpertMagicNumber(Magic);
   setup[LONG]  = NewSetup(+1);
   setup[SHORT] = NewSetup(-1);
   RestoreStateFromPositionsAndOrders(Magic);                // riavvio senza duplicare ordini
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(Bars::IsNewH4(cfg.alignment, cfg.sessionAnchor))       // primo tick della nuova barra H4
      OnNewH4Bar(Bars::LastClosedH4());                      // barra con indice 1 = appena chiusa
   ManagePendingIntrabar();                                  // E3: annullamento se T±2R toccato
}
```

### 4.1 Elaborazione alla chiusura H4

```cpp
void OnNewH4Bar(const MqlRates &bar)
{
   datetime now = bar.time + PeriodSeconds(PERIOD_H4);       // istante della decisione = chiusura barra

   Reference ref = ActiveReference(now);
   if(!ref.valid) { ResetSetups("NESSUN_RIFERIMENTO"); return; }
   if(!LevelsConsistent(ref)) { Journal("SCARTO_DATI", ref); return; }   // §2.6

   Profile pc = BuildProfile(ContextFrom(ref), now, rowH);   // contesto [I-6] o intervallo annotato troncato
   Journal::Context(now, ref, pc);

   for(int s = 0; s < 2; s++)
   {
      Setup &x = setup[s];
      bool allowed = SideAllowed(cfg, x.side) && RunMode != SOLO_SEGNALI;
      Step(x, bar, ref, pc, now, allowed);
   }
}
```

### 4.2 Macchina a stati (scritta per il long, lo short è speculare con `sgn = −1`)

Per lo short si confrontano i prezzi moltiplicati per `x.side`: "minimo < livello" diventa
"massimo > livello" e così via. Nel codice reale conviene scrivere due funzioni esplicite, più leggibili.
Le funzioni dei §4.3 e §5 (`PassFilters`, `StopPrice`, ordini) usano già `x.side` e valgono per entrambi i lati.

```cpp
void Step(Setup &x, const MqlRates &b, const Reference &ref, const Profile &pc, datetime now, bool allowed)
{
   SetupState prev = x.st;
   x.level = SweepLevel(x, ref);                                   // M_L o swing in zona sconto [I-8]

   // 1. transizioni di prezzo
   switch(x.st)
   {
      case IN_TRADE: case DONE:                                    // DONE: limite di trade per riferimento raggiunto [I-16]
         return;
      case TRIGGERED:                                              // E2: ordine a mercato in volo, attende il fill
         return;
      case DISCARDED:                                              // nuovo ciclo solo dopo una chiusura dentro il range
         if(b.close >= x.level) x.st = IDLE;
         break;
      case IDLE:
         if(b.low < x.level)                                       // sweep [R]
         {  x.st = SWEPT; x.sweepTime = b.time; x.barsSinceSweep = 0; x.extreme = b.low;
            EvaluateSwept(x, b, ref); }                            // rientro possibile nella stessa barra
         break;
      case SWEPT:
         UpdateExtreme(x, b);                                      // extreme = min(extreme, low); barsSinceSweep++
         EvaluateSwept(x, b, ref);
         break;
      case RECLAIMED:
      case ORDER_PENDING:
         UpdateExtreme(x, b);
         if(b.close < x.level)                                     // ricaduta [I-9]: annulla un eventuale E1
         {  CancelPending(x, "RICADUTA"); x.st = SWEPT; x.barsSinceSweep = 0; }
         else if(x.st == ORDER_PENDING && EntryMode == ENTRY_RETEST && --x.pendingBarsLeft <= 0)
         {  CancelPending(x, "RETEST_SCADUTO"); Discard(x, "RETEST_SCADUTO"); }
         break;
   }

   // 2. trigger ed esecuzione
   bool canArm = (x.st == RECLAIMED) || (x.st == ORDER_PENDING && EntryMode == ENTRY_BREAK);
   if(canArm)
   {
      // ultimo swing high confermato (barra i con i + N <= barra appena chiusa) [I-11]
      x.T = Swings::LastConfirmedHigh(now, FractalN, x.sweepTime - LookbackT * PeriodSeconds(PERIOD_H4));
      if(x.T > 0)
      {
         if(EntryMode == ENTRY_BREAK)                                         // E1
            PlaceOrUpdateBreakOrder(x, ref, pc, allowed);
         else if(b.close > x.T)                                               // E2 / E3: chiusura oltre T
         {
            x.st = TRIGGERED;
            if(!allowed)                                        Block(x, "BLOCCATO_CLASSE");
            else if(PassFilters(x, ref, pc, EstimatedEntry(x)))
            {
               if(EntryMode == ENTRY_CLOSE) SendMarket(x, ref);               // apertura della barra corrente
               else                         PlaceRetestLimit(x, ref);         // E3
            }
         }
      }
   }

   if(x.st != prev) Journal::State(now, x, prev, ref, pc);
}

void EvaluateSwept(Setup &x, const MqlRates &b, const Reference &ref)
{
   if(x.level - x.extreme > MaxSweepDepthRM * ref.RM)  Discard(x, "SCARTO_CONTINUAZIONE");  // [I-10]
   else if(b.close >= x.level)                         x.st = RECLAIMED;                    // [I-9]
   else if(x.barsSinceSweep >= cfg.kReclaim[x.side])   Discard(x, "SCARTO_NO_RIENTRO");     // [I-10]
}
```

### 4.3 Filtri

```cpp
bool PassFilters(Setup &x, const Reference &ref, const Profile &pc, double entry)
{
   if(UseEqFilter  && x.side * (entry - ref.EQ) >= 0)   return Discard(x, "SCARTO_FILTRO_EQ");    // [I-3]
   if(UsePocFilter && x.side * (pc.poc - ref.EQ) >= 0)  return Discard(x, "SCARTO_FILTRO_POC");   // [I-7]
   double sl = StopPrice(x);
   if(x.side * (entry - sl) <= MinStopDistance())       return Discard(x, "SCARTO_STOP");         // STOPS_LEVEL
   Journal::PocMigration(pc, PocMigrationBars);                                                    // solo registro
   if(x.side < 0) Journal::Distribution(BuildProfile(x.sweepTime, Now(), rowH), x.level);          // [I-12]
   return true;
}
```

`Discard()` e `Block()` mettono lo stato a `DISCARDED`, registrano il motivo e restituiscono `false`.
Lo stato torna `IDLE` solo dopo una chiusura H4 di nuovo dentro il range, così serve un nuovo sweep per
aprire un nuovo ciclo. `CancelPending()` cancella l'ordine pendente, se esiste, e registra il motivo senza
cambiare lo stato. Dopo `SendMarket` lo stato resta `TRIGGERED` fino al fill (§6), oppure torna
`DISCARDED` se l'ordine viene rifiutato.

## 5. Ordini e dimensione

```cpp
double StopPrice(const Setup &x)
{
   double buf = (cfg.stopBuffer == BUFFER_SPREAD) ? CurrentSpread() : 0;   // [I-17]
   return x.extreme - x.side * buf;                                        // long: P_low − buf; short: P_high + buf
}

double CalcLots(int side, double entry, double sl, double riskPct)
{
   double base  = RiskOnEquity ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   double money = base * riskPct / 100.0;
   double pl;
   if(!OrderCalcProfit(side > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, entry, sl, pl)) return 0;
   double lossPerLot = -pl + cfg.commissionPerLot;           // pl è negativo; commissione andata e ritorno
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lots = MathFloor(money / lossPerLot / step) * step;
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return 0;      // SCARTO_SIZE: mai rischio per eccesso
   return MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
}

void SendMarket(Setup &x, const Reference &ref)                          // E2
{
   double entry = x.side > 0 ? Ask() : Bid();
   double sl    = StopPrice(x);
   double lots  = CalcLots(x.side, entry, sl, RiskFor(x));
   if(lots == 0) { Discard(x, "SCARTO_SIZE"); return; }
   double tpEst = entry + x.side * TargetR * MathAbs(entry - sl);        // corretto sul fill in OnTradeTransaction
   bool ok = x.side > 0 ? trade.Buy(lots, _Symbol, 0, sl, tpEst, Tag(x))
                        : trade.Sell(lots, _Symbol, 0, sl, tpEst, Tag(x));
   x.st = TRIGGERED;                                                      // attende il fill (§6)
   if(!ok) Discard(x, "ORDINE_RIFIUTATO");
}

void PlaceOrUpdateBreakOrder(Setup &x, const Reference &ref, const Profile &pc, bool allowed)   // E1
{
   double px = x.T + (x.side > 0 ? CurrentSpread() : 0);   // buy stop scatta sull'Ask: compensa lo spread
   if(x.side * (Current() - px) >= 0)                       // prezzo già oltre T
   {  if(PassFilters(x, ref, pc, Current()) && allowed) SendMarket(x, ref); return; }
   if(!PassFilters(x, ref, pc, px)) { CancelPending(x, x.lastReason); return; }
   if(!allowed) return Block(x, "BLOCCATO_CLASSE");
   double sl = StopPrice(x), lots = CalcLots(x.side, px, sl, RiskFor(x));
   if(lots == 0) { Discard(x, "SCARTO_SIZE"); return; }
   double tp = px + x.side * TargetR * MathAbs(px - sl);
   if(x.orderTicket == 0) x.orderTicket = PlaceStop(x.side, lots, px, sl, tp);
   else                   ModifyOrder(x.orderTicket, px, sl, tp, lots);   // cambio volume = cancella e ripiazza
   x.st = ORDER_PENDING;
}

void PlaceRetestLimit(Setup &x, const Reference &ref)                     // E3
{
   double px = x.T, sl = StopPrice(x), lots = CalcLots(x.side, px, sl, RiskFor(x));
   if(lots == 0) { Discard(x, "SCARTO_SIZE"); return; }
   x.orderTicket = PlaceLimit(x.side, lots, px, sl, px + x.side * TargetR * MathAbs(px - sl));
   x.pendingBarsLeft = RetestExpiryBars;
   x.st = ORDER_PENDING;
}

void ManagePendingIntrabar()                                              // E3 dentro la barra
{
   for each Setup x with st == ORDER_PENDING and EntryMode == ENTRY_RETEST:
      double r = MathAbs(x.T - StopPrice(x));
      if(x.side * (Current() - (x.T + x.side * TargetR * r)) >= 0) CancelPending(x, "RETEST_ANNULLATO_TARGET");
}
```

Nessun ordine viene piazzato prima di `RECLAIMED`. Nel caso da scartare non esiste quindi alcun ordine.

## 6. Fill, target esatto e uscite manuali

```cpp
void OnTradeTransaction(const MqlTradeTransaction &t, const MqlTradeRequest &rq, const MqlTradeResult &rs)
{
   if(t.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(t.deal)) return;
   if(HistoryDealGetInteger(t.deal, DEAL_MAGIC) != Magic) return;
   long   entry  = HistoryDealGetInteger(t.deal, DEAL_ENTRY);
   long   reason = HistoryDealGetInteger(t.deal, DEAL_REASON);
   double price  = HistoryDealGetDouble (t.deal, DEAL_PRICE);
   Setup &x = SetupByPosition(HistoryDealGetInteger(t.deal, DEAL_POSITION_ID));

   if(entry == DEAL_ENTRY_IN)
   {
      double sl = PositionSL(x), R = MathAbs(price - sl);                 // R sul fill effettivo [R]
      double tp = price + x.side * TargetR * R;                           // 2R esatto [I-15]
      trade.PositionModify(x.positionTicket, sl, NormalizePrice(tp));
      x.st = IN_TRADE; x.tradesOnRef++;
      Journal::Fill(x, price, sl, tp, R, Slippage(price));
   }
   else if(entry == DEAL_ENTRY_OUT)
   {
      string kind = (reason == DEAL_REASON_SL) ? "SL" : (reason == DEAL_REASON_TP) ? "TP"
                  : (reason == DEAL_REASON_CLIENT || reason == DEAL_REASON_MOBILE || reason == DEAL_REASON_WEB)
                    ? "MANUALE" : (reason == DEAL_REASON_SO) ? "STOP_OUT" : "ALTRO";
      Journal::Exit(x, price, kind, RealizedR(x, price), Swap(x), Commission(x));   // MANUALE: campo motivo vuoto
      x.st = (x.tradesOnRef < MaxTradesPerRefSide) ? IDLE : DONE;        // [I-16]; DONE si azzera al cambio di riferimento
   }
}
```

## 7. Riferimento mensile

```cpp
Reference ActiveReference(datetime now)
{
   Reference r;
   if(RunMode != AUTO)
   {
      Annotation a = ann.LatestReference(now);       // annotated_at <= now  (point-in-time)
      if(!a.found) return r;                         // valid = false
      r = LevelsFromMonth(a.month);                  // dai dati del broker, MN nativo o ricostruito [I-4]
      r.source = "ANNOTAZIONE";
      r.annotatedH = a.H; r.annotatedL = a.L;        // per il controllo §2.6
   }
   else
      r = AutoReference(now);                        // classificatore [I-1] + decadenza [I-2]
   r.valid = (r.monthClose <= now);                  // mai la candela del mese in corso [R]
   r.EQ = (r.H + r.L) / 2.0;  r.RM = r.H - r.L;      // [R]
   return r;
}
```

## 8. Profilo volumi

```cpp
Profile BuildProfile(datetime from, datetime to, double rowH)            // to = istante della decisione, escluso
{
   Profile p; p.rowH = rowH;
   MqlRates m1[];
   int n = CopyRates(_Symbol, PERIOD_M1, from, to - 60, m1);              // solo barre M1 già chiuse
   // se la storia M1 non basta: PERIOD_M5, e lo si scrive nel registro
   bool real = AnyPositive(m1, REAL_VOLUME);                              // [I-5]
   p.base = MathFloor(MinLow(m1) / rowH);
   for(int i = 0; i < n; i++)
   {
      double v  = real ? (double)m1[i].real_volume : (double)m1[i].tick_volume;
      int    r0 = (int)MathFloor(m1[i].low  / rowH) - (int)p.base;
      int    r1 = (int)MathFloor(m1[i].high / rowH) - (int)p.base;
      for(int r = r0; r <= r1; r++) p.vol[r] += v / (r1 - r0 + 1);       // distribuzione uniforme
      p.total += v;
   }
   p.pocRow = ArgMaxClosestToMiddle(p.vol);
   p.poc    = (p.base + p.pocRow + 0.5) * rowH;
   return p;
}
```

Il profilo di contesto si può aggiornare in modo incrementale, aggiungendo solo le M1 della nuova barra H4.
Il ricalcolo completo serve solo nei test di confronto con TradingView.

## 9. Barre H4 allineate a TradingView

```cpp
// cfg.alignment == BROKER       -> iTime/CopyRates(PERIOD_H4) nativi
// cfg.alignment == TV_SESSIONE  -> aggregazione delle M1:
//    ancora = cfg.sessionAnchor (FX: 17:00 America/New_York; azioni USA: 09:30 America/New_York)
//    barra k della sessione = [ancora + 4h·k, min(ancora + 4h·(k+1), fine sessione))
//    conversione ora server -> New York con ServerUtcWinter/Summer e le regole DST USA
// La candela mensile si ricostruisce allo stesso modo (prima sessione del mese -> ultima sessione).
```

## 10. Registro

Un file CSV per simbolo (`Common\Files\wtsl\journal_<simbolo>.csv`), una riga per evento. È la base di
tutto il piano di backtest.

```
utc;simbolo;lato;evento;stato_da;stato_a;motivo;M_H;M_L;EQ;POC_PC;POC_PP;livello;estremo;T;
close;prezzo;sl;tp;R;lotti;rischio_eff_pct;modo_ingresso;deal_reason;swap;commissione;R_realizzato
```

Eventi minimi: `SWEEP`, `RIENTRO`, `RICADUTA`, `TRIGGER`, `ORDINE`, `FILL`, `USCITA`, `SCARTO_*`,
`BLOCCATO_CLASSE`, `EQ_TOCCATO`, `SCARTO_DATI`.

## 11. Test unitari minimi

| Test | Input | Atteso |
|---|---|---|
| Livelli AVGO | H = 429,56, L = 302,28 | EQ = 365,92; RM = 127,28 |
| R e target AVGO | ingresso 328,67, stop 290,67 | R = 38,00; TP = 404,67; il target disegnato 404,13 = 1,986R |
| Caso 1 sintetico (doc 02) | 14 barre, E1/E2/E3 | ingressi 326,40 / 328,60 / 326,40 |
| Caso 2 sintetico | 14 barre FX, E2 | ingresso 1,11975, TP 1,11225 alla barra 14; E3 senza trade |
| Caso 3 sintetico | 10 barre | `DISCARDED` alla barra 9, nessun ordine |
| Frattale | swing alla barra i | non visibile prima della chiusura di i + N |
| Size | 0,25% di 100.000, R = 38, step 1 | 6 lotti; con step 0,01 → 6,57 |
| Lotto minimo | rischio < perdita di VOLUME_MIN | `SCARTO_SIZE`, nessun ordine |
| Classe | segnale short su azione | `BLOCCATO_CLASSE` |
| Uscita manuale | chiusura dal terminale | `deal_reason` = MANUALE nel registro |
