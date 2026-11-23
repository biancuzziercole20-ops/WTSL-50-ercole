// Scenari simulati del bot WT67ercole.mq5 (conto 100k) e della catena completa
// WT67 -> WTSL-50%ercole sorgente -> WTSL-50%ercole ricevitore. Incluso da test_wtsl50.cpp.

// Barra c con incrocio rialzista seguito dal primo incrocio ribassista entro "gap" barre.
static bool CercaCoppia(const std::vector<MqlRates>& b, int gapMax, int& c1, int& c2) {
  std::vector<double> w1, w2;
  RefWT(b, b.size(), w1, w2);
  int ultimoSu = -1;
  for (int c = 100; c < (int)b.size() - 2; c++) {
    bool su = w1[c] > w2[c] && w1[c - 1] <= w2[c - 1];
    bool giu = w1[c] < w2[c] && w1[c - 1] >= w2[c - 1];
    if (su) ultimoSu = c;
    if (giu && ultimoSu > 0) {
      if (c - ultimoSu <= gapMax && c - ultimoSu >= 2) { c1 = ultimoSu; c2 = c; return true; }
      ultimoSu = -1;
    }
  }
  return false;
}

static string DescriviWT(Env& e) {
  const MqlTradeRequest* r = nullptr;
  for (auto& x : e.T100.sent) if (x.action == TRADE_ACTION_DEAL && x.position == 0) r = &x;
  if (!r) return "nessun ordine";
  return string(r->type == ORDER_TYPE_BUY ? "BUY " : "SELL ") + F2(r->volume) + " @" + F2(r->price) + " SL " + F2(r->sl) + " TP " + F2(r->tp)
         + " magic " + std::to_string(r->magic);
}
static bool OrdineWT(Env& e, int tipo, double prezzo, double sl, double tp) {
  const MqlTradeRequest* r = nullptr;
  for (auto& x : e.T100.sent) if (x.action == TRADE_ACTION_DEAL && x.position == 0) r = &x;
  return r && r->type == (tipo == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL) && std::fabs(r->volume - 1.0) < 1e-9 && std::fabs(r->price - prezzo) < 1e-9
         && std::fabs(r->sl - sl) < 1e-9 && std::fabs(r->tp - tp) < 1e-9 && (long)r->magic == MAGIC_WT67;
}

static void TestWT67() {
  std::vector<MqlRates> serie = SerieSintetica(320);
  int cSu = CercaBarra(serie, 1), cGiu = CercaBarra(serie, -1), cNo = CercaBarra(serie, 0);

  // ---------------------------------------------------------------- W01 BUY
  {
    Env e("W01_wt67_buy", 2026, 7, 15, 14, 0, 0);
    e.Serie(serie, cSu + 1, 15, 45);
    e.VaiABarra(cSu, 300);
    int init = e.StartWT();
    e.Q100(2999.70, 3000.00);
    int primaDellaChiusura = e.OpensWT();
    e.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    for (int i = 0; i < 5; i++) { e.Adv(1000); e.Q100(2999.70, 3000.00); }
    const MockPosition* p = e.PosWT();
    bool ok = init == 0 && primaDellaChiusura == 0 && e.OpensWT() == 1 && OrdineWT(e, 0, 3000.00, 2990.00, 3010.00) && p && p->sl == 2990.00 && p->tp == 3010.00;
    Esito("W01", "WT67: incrocio rialzista confermato sulla M15 chiusa delle 15:30, prima quotazione alle 15:45:01",
          "BUY 1.00 @3000.00 (Ask) SL 2990.00 TP 3010.00 magic 670067; nulla prima della chiusura della candela",
          std::to_string(e.OpensWT()) + " ordine: " + DescriviWT(e) + "; prima della chiusura: " + std::to_string(primaDellaChiusura), ok);
  }
  // ---------------------------------------------------------------- W02 SELL
  {
    Env e("W02_wt67_sell", 2026, 7, 15, 14, 0, 0);
    e.Serie(serie, cGiu + 1, 16, 0);
    e.VaiABarra(cGiu, 300);
    e.StartWT();
    e.Q100(3000.00, 3000.30);
    e.TickBarra(cGiu + 1, 1, 3000.00, 3000.30, 0, 0);
    bool ok = e.OpensWT() == 1 && OrdineWT(e, 1, 3000.00, 3010.00, 2990.00);
    Esito("W02", "WT67: incrocio ribassista confermato", "SELL 1.00 @3000.00 (Bid) SL 3010.00 TP 2990.00",
          std::to_string(e.OpensWT()) + " ordine: " + DescriviWT(e), ok);
  }
  // ---------------------------------------------------------------- W03 orari
  {
    Env e("W03_wt67_1730", 2026, 7, 15, 16, 0, 0);
    e.Serie(serie, cSu + 1, 17, 30);
    e.VaiABarra(cSu, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.TickBarra(cSu + 1, 0, 2999.70, 3000.00, 0, 0);
    Env f("W03b_wt67_1530", 2026, 7, 15, 14, 0, 0);
    f.Serie(serie, cSu + 1, 15, 30);
    f.VaiABarra(cSu, 300);
    f.StartWT();
    f.Q100(2999.70, 3000.00);
    f.TickBarra(cSu + 1, 0, 2999.70, 3000.00, 0, 0);
    bool ok = e.OpensWT() == 0 && e.J100("fuori dalla finestra") && f.OpensWT() == 1;
    Esito("W03", "WT67: prima quotazione della candela alle 17:30:00 esatte e alle 15:30:00", "0 ordini alle 17:30:00; 1 ordine alle 15:30:00",
          std::to_string(e.OpensWT()) + " alle 17:30, " + std::to_string(f.OpensWT()) + " alle 15:30", ok);
  }
  {
    Env e("W03c_wt67_inverno", 2026, 1, 15, 14, 0, 0, 1);
    e.Serie(serie, cSu + 1, 15, 30);
    e.VaiABarra(cSu, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.TickBarra(cSu + 1, 0, 2999.70, 3000.00, 0, 0);
    bool ok = e.OpensWT() == 1;
    Esito("W03c", "WT67: ora solare (gennaio), ingresso alle 15:30:00", "1 ordine", std::to_string(e.OpensWT()) + " ordine", ok);
  }
  // ---------------------------------------------------------------- W04 nessun incrocio / stessa direzione
  {
    Env e("W04_wt67_nessun_incrocio", 2026, 7, 15, 14, 0, 0);
    e.Serie(serie, cNo + 1, 16, 0);
    e.VaiABarra(cNo, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.TickBarra(cNo + 1, 1, 2999.70, 3000.00, 0, 0);
    bool ok = e.OpensWT() == 0;
    Esito("W04", "WT67: nessun incrocio sulla candela chiusa", "0 ordini", std::to_string(e.OpensWT()) + " ordini", ok);
  }
  {
    Env e("W04b_wt67_stessa_direzione", 2026, 7, 15, 14, 0, 0);
    e.Serie(serie, cSu + 1, 16, 0);
    e.VaiABarra(cSu, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    BrokerOpen(e.T100, 0, 3000.00, 2990.00, 3010.00, 1.0, MAGIC_WT67, "WT67");
    e.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    bool ok = e.OpensWT() == 0 && e.ClosesWT() == 0 && e.J100("stessa direzione");
    Esito("W04b", "WT67: incrocio rialzista con un BUY gia' aperto", "nessun ordine, una posizione alla volta",
          std::to_string(e.OpensWT()) + " aperture, " + std::to_string(e.ClosesWT()) + " chiusure", ok);
  }
  // ---------------------------------------------------------------- W05 limite giornaliero
  {
    Env e("W05_wt67_limite", 2026, 7, 15, 14, 0, 0);
    for (int k = 0; k < 4; k++) { ulong t = BrokerOpen(e.T100, 0, 3000.0, 2990.0, 3010.0, 1.0, MAGIC_WT67, "WT67"); e.Adv(60000); BrokerClose(e.T100, t, DEAL_REASON_SL, 2990.0); }
    e.Serie(serie, cSu + 1, 16, 0);
    e.VaiABarra(cSu, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    Env f("W05b_wt67_tre_oggi", 2026, 7, 15, 14, 0, 0);
    for (int k = 0; k < 3; k++) { ulong t = BrokerOpen(f.T100, 0, 3000.0, 2990.0, 3010.0, 1.0, MAGIC_WT67, "WT67"); f.Adv(60000); BrokerClose(f.T100, t, DEAL_REASON_SL, 2990.0); }
    f.Serie(serie, cSu + 1, 16, 0);
    f.VaiABarra(cSu, 300);
    f.StartWT();
    f.Q100(2999.70, 3000.00);
    f.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    bool ok = e.OpensWT() == 0 && e.J100("gia' 4 trade oggi") && f.OpensWT() == 1;
    Esito("W05", "WT67: incrocio con gia' 4 trade nel giorno italiano (controllo con 3)", "0 ordini con 4; 1 ordine con 3",
          std::to_string(e.OpensWT()) + " con 4, " + std::to_string(f.OpensWT()) + " con 3", ok);
  }
  // ---------------------------------------------------------------- W06 riavvio sulla stessa candela
  {
    Env e("W06_wt67_riavvio", 2026, 7, 15, 14, 0, 0);
    e.Serie(serie, cSu + 1, 16, 0);
    e.VaiABarra(cSu, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    e.TickBarra(cSu + 1, 5, 2989.90, 2990.20, 0, 0);    // SL toccato: nessuna posizione aperta
    e.RestartWT();
    e.TickBarra(cSu + 1, 10, 2999.70, 3000.00, 0, 0);
    bool ok = e.OpensWT() == 1 && e.PosWT() == nullptr && e.J100("gia' stato aperto un trade");
    Esito("W06", "WT67: riavvio entro la stessa candela dopo un trade gia' chiuso da SL", "nessun secondo ordine sulla stessa candela",
          std::to_string(e.OpensWT()) + " ordini totali", ok);
  }
  // ---------------------------------------------------------------- W07 avvio a candela inoltrata
  {
    Env e("W07_wt67_ritardo", 2026, 7, 15, 14, 0, 0);
    e.Serie(serie, cSu + 1, 16, 0);
    e.VaiABarra(cSu + 1, 120);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    bool ok = e.OpensWT() == 0 && e.J100("scaduto");
    Esito("W07", "WT67: avviato 120 s dopo l'apertura della candela di segnale", "0 ordini (segnale scaduto, limite 60 s)",
          std::to_string(e.OpensWT()) + " ordini", ok);
  }
  // ---------------------------------------------------------------- W08 slittamento
  {
    Env e("W08_wt67_slittamento", 2026, 7, 15, 14, 0, 0);
    e.T100.slippage = 0.20;
    e.Serie(serie, cSu + 1, 16, 0);
    e.VaiABarra(cSu, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    const MockPosition* p = e.PosWT();
    bool ok = p && std::fabs(p->price_open - 3000.20) < 1e-9 && std::fabs(p->sl - 2990.20) < 1e-9 && std::fabs(p->tp - 3010.20) < 1e-9;
    Esito("W08", "WT67: eseguito a 3000.20 invece di 3000.00", "SL/TP riallineati a 2990.20 / 3010.20 (10.00 dall'ingresso reale)",
          p ? ("ingresso " + F2(p->price_open) + ", SL " + F2(p->sl) + ", TP " + F2(p->tp)) : "nessuna posizione", ok);
  }
  // ---------------------------------------------------------------- W09 rifiuto e nuovo tentativo
  {
    Env e("W09_wt67_rifiuto", 2026, 7, 15, 14, 0, 0);
    e.Serie(serie, cSu + 1, 16, 0);
    e.VaiABarra(cSu, 300);
    e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.T100.forced.push_back({TRADE_RETCODE_REQUOTE, false});
    e.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    e.TickBarra(cSu + 1, 3, 2999.70, 3000.00, 0, 0);
    Env f("W09b_wt67_rifiuto_scaduto", 2026, 7, 15, 14, 0, 0);
    f.Serie(serie, cSu + 1, 16, 0);
    f.VaiABarra(cSu, 300);
    f.StartWT();
    f.Q100(2999.70, 3000.00);
    f.T100.forced.push_back({TRADE_RETCODE_REQUOTE, false});
    f.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    f.TickBarra(cSu + 1, 70, 2999.70, 3000.00, 0, 0);
    bool ok = e.OpensWT() == 2 && e.PosWT() && f.OpensWT() == 1 && !f.PosWT() && e.J100("requote");
    Esito("W09", "WT67: requote, nuovo tentativo dopo 2 s (e dopo 70 s)", "riprova ed entra entro 60 s; dopo 60 s il segnale scade",
          std::to_string(e.OpensWT()) + " invii e posizione " + (e.PosWT() ? "aperta" : "assente") + "; con 70 s: " + std::to_string(f.OpensWT())
              + " invio, posizione " + (f.PosWT() ? "aperta" : "assente"), ok);
  }
  // ---------------------------------------------------------------- W10 inversione e chiusura fuori orario
  int c1 = -1, c2 = -1;
  bool coppia = CercaCoppia(serie, 6, c1, c2);
  {
    Env e("W10_wt67_inversione", 2026, 7, 15, 14, 0, 0);
    if (coppia) {
      e.Serie(serie, c1 + 1, 15, 45);
      e.VaiABarra(c1, 300);
      e.StartWT();
      e.Q100(2999.70, 3000.00);
      e.TickBarra(c1 + 1, 1, 2999.70, 3000.00, 0, 0);
      for (int j = c1 + 2; j <= c2; j++) e.TickBarra(j, 1, 2996.00, 2996.30, 0, 0);
      e.TickBarra(c2 + 1, 1, 2993.00, 2993.30, 0, 0);
    }
    const MockPosition* p = e.PosWT();
    bool chiusoEA = false;
    for (auto& d : e.T100.deals) if (d.entry == DEAL_ENTRY_OUT && d.reason == DEAL_REASON_EXPERT) chiusoEA = true;
    bool ok = coppia && e.OpensWT() == 2 && e.ClosesWT() == 1 && chiusoEA && p && p->type == 1 && std::fabs(p->sl - 3003.00) < 1e-9 && std::fabs(p->tp - 2983.00) < 1e-9;
    Esito("W10", "WT67: BUY aperto, poi incrocio ribassista confermato in sessione",
          "BUY chiuso dall'EA (DEAL_REASON_EXPERT) e SELL 1.00 @2993.00 SL 3003.00 TP 2983.00 nello stesso istante",
          coppia ? (std::to_string(e.ClosesWT()) + " chiusura, " + std::to_string(e.OpensWT()) + " aperture, ultima: " + DescriviWT(e)) : "coppia di incroci non trovata", ok);
  }
  {
    Env e("W10b_wt67_inversione_fuori_orario", 2026, 7, 15, 14, 0, 0);
    if (coppia) {
      e.Serie(serie, c1 + 1, 17, 15);
      e.VaiABarra(c1, 300);
      e.StartWT();
      e.Q100(2999.70, 3000.00);
      e.TickBarra(c1 + 1, 1, 2999.70, 3000.00, 0, 0);
      for (int j = c1 + 2; j <= c2; j++) e.TickBarra(j, 1, 2996.00, 2996.30, 0, 0);
      e.TickBarra(c2 + 1, 1, 2993.00, 2993.30, 0, 0);
    }
    bool ok = coppia && e.OpensWT() == 1 && e.ClosesWT() == 1 && e.PosWT() == nullptr;
    Esito("W10b", "WT67: BUY delle 17:15, incrocio opposto dopo le 17:30", "BUY chiuso anche fuori orario, nessun SELL",
          std::to_string(e.ClosesWT()) + " chiusura, " + std::to_string(e.OpensWT()) + " apertura, posizione " + (e.PosWT() ? "aperta" : "nessuna"), ok);
  }
  // ---------------------------------------------------------------- W11 Strategy Tester
  {
    Env e("W11_wt67_tester", 2026, 7, 15, 14, 0, 0);
    e.T100.tester = true;
    e.Serie(serie, cSu + 1, 15, 45);
    e.VaiABarra(cSu, 300);
    int init = e.StartWT();
    e.Q100(2999.70, 3000.00);
    e.TickBarra(cSu + 1, 1, 2999.70, 3000.00, 0, 0);
    Env f("W11b_wt67_tester_1730", 2026, 7, 15, 14, 0, 0);
    f.T100.tester = true;
    f.Serie(serie, cSu + 1, 17, 30);
    f.VaiABarra(cSu, 300);
    f.StartWT();
    f.Q100(2999.70, 3000.00);
    f.TickBarra(cSu + 1, 0, 2999.70, 3000.00, 0, 0);
    bool ok = init == 0 && e.OpensWT() == 1 && f.OpensWT() == 0;
    Esito("W11", "WT67 nel Strategy Tester (TimeGMT = ora server, server UTC+3 d'estate)", "finestra Europe/Rome rispettata: 1 ordine alle 15:45, 0 alle 17:30:00",
          std::to_string(e.OpensWT()) + " alle 15:45, " + std::to_string(f.OpensWT()) + " alle 17:30", ok);
  }
  // ---------------------------------------------------------------- W12 protezione login
  {
    Env e("W12_wt67_login", 2026, 7, 15, 14, 0, 0);
    WT67EA* w = new WT67EA();
    w->InpConto100k = L100;
    g_term = &e.T50;
    int init = w->OnInit();
    delete w;
    bool ok = init == INIT_FAILED;
    Esito("W12", "WT67 caricato per errore sul terminale del conto 50k", "non parte (INIT_FAILED)",
          init == INIT_FAILED ? "INIT_FAILED" : ("codice " + std::to_string(init)), ok);
  }
  // ---------------------------------------------------------------- E01 catena completa
  {
    Env e("E01_catena_completa", 2026, 7, 15, 14, 0, 0);
    bool fasi[6] = {false, false, false, false, false, false};
    string dett;
    if (coppia) {
      e.Serie(serie, c1 + 1, 15, 45);
      e.VaiABarra(c1, 300);
      e.StartWT();
      e.Start();
      e.Q100(2999.70, 3000.00); e.Q50(2999.70, 3000.00);
      e.TickBarra(c1 + 1, 1, 2999.70, 3000.00, 2999.70, 3000.00);
      fasi[0] = e.OpensWT() == 1 && OrdineWT(e, 0, 3000.00, 2990.00, 3010.00) && e.Opens() == 0;
      e.TickBarra(c1 + 1, 60, 2997.00, 2997.30, 2996.70, 2997.00);
      e.TickBarra(c1 + 1, 90, 2995.00, 2995.30, 2994.70, 2995.00);
      fasi[1] = e.Opens() == 1 && OrdineCorretto(e, 0, 2995.00, 2990.00, 3010.00, e.PosWT() ? e.PosWT()->identifier : 0);
      for (int j = c1 + 2; j <= c2; j++) e.TickBarra(j, 1, 2995.00, 2995.30, 2994.70, 2995.00);
      fasi[2] = e.Opens() == 1 && e.OpensWT() == 1;
      e.TickBarra(c2 + 1, 1, 2993.00, 2993.30, 2993.00, 2993.30);
      for (int i = 0; i < 5; i++) { e.Adv(200); e.Q100(2993.00, 2993.30); e.Q50(2993.00, 2993.30); }
      const MockPosition* src = e.PosWT();
      fasi[3] = e.ClosesWT() == 1 && src && src->type == 1 && e.Closes() == 1 && e.Copies() == 0;
      for (int i = 0; i < 5; i++) { e.Adv(200); e.Q100(2997.69, 2997.99); e.Q50(2998.00, 2998.30); }
      fasi[4] = e.Opens() == 1;
      e.Adv(200); e.Q100(2997.70, 2998.00); e.Q50(2998.00, 2998.30);
      fasi[5] = e.Opens() == 2 && src && OrdineCorretto(e, 1, 2998.00, 3003.00, 2983.00, src->identifier);
      char b[96]; snprintf(b, sizeof b, "incroci sulle barre %d e %d (%d candele); ", c1, c2, c2 - c1); dett = b;
    }
    const char* nomi[6] = {"WT67 BUY @3000", "copia BUY 0.50 @2995", "nessun duplicato", "inversione: chiuse sorgente e copia",
                           "SELL non copiato a 4.99", "copia SELL 0.50 @2998"};
    bool ok = coppia;
    for (int i = 0; i < 6; i++) { ok = ok && fasi[i]; dett += string(nomi[i]) + (fasi[i] ? " OK" : " KO") + (i < 5 ? ", " : ""); }
    Esito("E01", "Catena completa con 3 EA: WT67 -> WTSL sorgente 100k -> WTSL ricevitore 50k",
          "WT67 BUY @3000; copia BUY 0.50 @2995 a -5/-500; incrocio opposto: WT67 chiude e vende a 2993, copia chiusa; copia SELL @2998 solo alla nuova soglia",
          dett, ok);
  }
}
