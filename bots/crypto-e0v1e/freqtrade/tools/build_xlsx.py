import json, sys, pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.comments import Comment
from openpyxl.utils import get_column_letter as L

AN, FT, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
runs = json.load(open(f"{AN}/runs.json"))
tick = json.load(open(f"{AN}/tickproxy.json"))
cmp_ = {k: json.load(open(f"{AN}/runs.json.{k}.cmp.json"))["summary"] for k in
        ["D1_sl10_1m_2022-24","D1_sl15_1m_2022-24","D2_sl10_1m_2025","D2_sl15_1m_2025","D3_sl10_1m_2026","D3_sl15_1m_2026","R1_sl10_5m_2022-24","R1_sl15_5m_2022-24"]}
datarep = pd.read_csv(f"{FT}/data_report.csv")

TESTS = [  # label, nome test, periodo, variante, dettaglio, volume, ruolo
 ("R0_replica_5m","Replica Freqle","2022-2024","Originale","5m","Reale Binance","Replica del report"),
 ("R1_sl10_5m_2022-24","SL10 5m 2022-24","2022-2024","SL 10%","5m","Reale Binance","Confronto senza dettaglio"),
 ("R1_sl15_5m_2022-24","SL15 5m 2022-24","2022-2024","SL 15%","5m","Reale Binance","Confronto senza dettaglio"),
 ("D1_orig_1m_2022-24","Originale 1m 2022-24","2022-2024","Originale","1m","Reale Binance","Periodo Freqle"),
 ("D1_sl10_1m_2022-24","SL10 1m 2022-24","2022-2024","SL 10%","1m","Reale Binance","Periodo Freqle"),
 ("D1_sl15_1m_2022-24","SL15 1m 2022-24","2022-2024","SL 15%","1m","Reale Binance","Periodo Freqle"),
 ("D2_orig_1m_2025","Originale 1m 2025","2025","Originale","1m","Reale Binance","Selezione"),
 ("D2_sl10_1m_2025","SL10 1m 2025","2025","SL 10%","1m","Reale Binance","Selezione"),
 ("D2_sl15_1m_2025","SL15 1m 2025","2025","SL 15%","1m","Reale Binance","Selezione"),
 ("D3_orig_1m_2026","Originale 1m 2026","gen-ott 2026","Originale","1m","Reale Binance","Fuori campione"),
 ("D3_sl10_1m_2026","SL10 1m 2026","gen-ott 2026","SL 10%","1m","Reale Binance","Fuori campione"),
 ("D3_sl15_1m_2026","SL15 1m 2026","gen-ott 2026","SL 15%","1m","Reale Binance","Fuori campione"),
 ("T1_orig_1m_2022-24_tickproxy","Originale 1m 2022-24 proxy tick","2022-2024","Originale","1m","N. transazioni (proxy tick)","Sensibilità volume"),
 ("T2_orig_1m_2025_tickproxy","Originale 1m 2025 proxy tick","2025","Originale","1m","N. transazioni (proxy tick)","Sensibilità volume"),
 ("T3_orig_1m_2026_tickproxy","Originale 1m 2026 proxy tick","gen-ott 2026","Originale","1m","N. transazioni (proxy tick)","Sensibilità volume"),
]
NAME = {t[0]: t[1] for t in TESTS}

F = "Arial"
H = Font(name=F, bold=True, color="FFFFFF"); HF = PatternFill("solid", fgColor="1F3864")
B = Font(name=F); BB = Font(name=F, bold=True); BLUE = Font(name=F, color="0000FF"); GREEN = Font(name=F, color="008000")
TITLE = Font(name=F, bold=True, size=14); SUB = Font(name=F, bold=True, size=11, color="1F3864")
YEL = PatternFill("solid", fgColor="FFFF00"); GREY = PatternFill("solid", fgColor="F2F2F2")
thin = Side(style="thin", color="BFBFBF"); BOX = Border(left=thin, right=thin, top=thin, bottom=thin)
PCT = '0.00%;-0.00%;"-"'; PCT1 = '0.0%;-0.0%;"-"'; USD = '#,##0.00;-#,##0.00;"-"'; INT = '#,##0;-#,##0;"-"'

def header(ws, row, cols, start=1):
    for i, c in enumerate(cols):
        x = ws.cell(row, start + i, c); x.font = H; x.fill = HF; x.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True); x.border = BOX

def font_all(ws):
    for row in ws.iter_rows():
        for c in row:
            if c.font is None or c.font.name != F:
                c.font = Font(name=F, bold=c.font.bold if c.font else False, color=c.font.color if c.font else None,
                              size=c.font.size if c.font else 11, italic=c.font.italic if c.font else False)

wb = Workbook()
wsR = wb.active; wsR.title = "Riepilogo"
wsT = wb.create_sheet("Trade Freqtrade"); wsP = wb.create_sheet("Parametri"); wsM = wb.create_sheet("Risultati MT5")

# ---------------- Trade Freqtrade ----------------
cols = ["Test","Periodo","Variante","Dettaglio","Volume deadfish","Coppia","Apertura (UTC)","Chiusura (UTC)",
        "Prezzo ingresso","Prezzo uscita","Stake (USDT)","Profitto netto %","Profitto netto (USDT)","Esito","Tag ingresso","Motivo uscita","Durata (min)"]
header(wsT, 1, cols)
r = 2
meta = {t[0]: t for t in TESTS}
for lab, *_ in TESTS:
    tr = sorted(runs[lab]["trades"], key=lambda x: x["open_date"])
    _, nm, per, var, det, vol, _ = meta[lab]
    for t in tr:
        od = pd.Timestamp(t["open_date"]).tz_convert(None).to_pydatetime(); cd = pd.Timestamp(t["close_date"]).tz_convert(None).to_pydatetime()
        vals = [nm, per, var, det, vol, t["pair"], od, cd, t["open_rate"], t["close_rate"], t["stake_amount"], t["profit_ratio"], t["profit_abs"],
                f'=IF(M{r}>0,"Vinto","Perso")', t["enter_tag"], t["exit_reason"], f"=(H{r}-G{r})*1440"]
        for i, v in enumerate(vals, 1):
            c = wsT.cell(r, i, v); c.font = B
        wsT.cell(r, 7).number_format = "yyyy-mm-dd hh:mm"; wsT.cell(r, 8).number_format = "yyyy-mm-dd hh:mm"
        for cc in (9, 10): wsT.cell(r, cc).number_format = "0.0000######"
        wsT.cell(r, 11).number_format = USD; wsT.cell(r, 12).number_format = PCT; wsT.cell(r, 13).number_format = USD; wsT.cell(r, 17).number_format = "0"
        r += 1
lastT = r - 1
wsT["A1"].comment = Comment("Fonte: backtest freqtrade 2026.10 eseguiti da Claude il 22/11/2026 su dati Binance Spot ufficiali (data.binance.vision, checksum SHA256 verificati). Profitto netto dopo fee 0,10% per lato. Una riga per trade.", "Claude")
wsT.freeze_panes = "A2"; wsT.auto_filter.ref = f"A1:Q{lastT}"
for i, w in enumerate([30,13,11,9,24,11,17,17,13,13,11,12,13,8,11,24,10], 1): wsT.column_dimensions[L(i)].width = w

# ---------------- Riepilogo ----------------
wsR["A1"] = "E0V1E binance: originale e varianti con stop sul broker"; wsR["A1"].font = TITLE
wsR["A2"] = "Nessuna configurazione resta sopra l'80% di trade vincenti fuori campione: 65,5% nel 2026 e 66,7% nel 2025, contro 85-87% nel periodo 2022-2024 di Freqle."
wsR["A2"].font = BB
wsR["A3"] = "Lo stop al 10% scatta anche su trade che la regola deadfish chiudeva tra -5% e -9%: la somma delle perdite peggiora. Lo stop al 15% non viene mai toccato nel 2025 e nel 2026."
wsR["A4"] = "Soglia win rate"; wsR["B4"] = 0.80; wsR["B4"].font = BLUE; wsR["B4"].fill = YEL; wsR["B4"].number_format = PCT1
wsR["B4"].comment = Comment("Fonte: obiettivo indicato dall'utente (>80% di trade chiusi in utile dopo i costi).", "Claude")
wsR["C4"] = "Legenda: testo blu = valore importato o da modificare; nero = formula sui trade; giallo = soglia modificabile."
wsR["C4"].font = Font(name=F, italic=True)

hdr = ["Test","Periodo","Variante","Dettaglio","Volume deadfish","Ruolo","Trade","Vincenti","Win rate netto","Perdita media %","Perdita peggiore %",
       "Perdita media (USDT)","Perdita peggiore (USDT)","Risultato medio netto %","Risultato medio netto (USDT)","Profitto totale (USDT)",
       "Max drawdown equity %","Peggior giornata (USDT)","Peggior giornata %","Δ perdita media vs originale (p.p.)","Δ perdita peggiore vs originale (p.p.)","Rispetta i criteri"]
HR = 6; header(wsR, HR, hdr); wsR.row_dimensions[HR].height = 45
T = "'Trade Freqtrade'"
rowof = {}
for i, (lab, nm, per, var, det, vol, role) in enumerate(TESTS):
    rr = HR + 1 + i; rowof[lab] = rr
    m = runs[lab]["metrics"]
    rng = lambda col: f"{T}!${col}$2:${col}${lastT}"
    crit = f'{rng("A")},$A{rr}'
    vals = [nm, per, var, det, vol, role,
            f"=COUNTIFS({crit})",
            f'=COUNTIFS({crit},{rng("M")},">0")',
            f"=IF(G{rr}=0,0,H{rr}/G{rr})",
            f'=IFERROR(AVERAGEIFS({rng("L")},{crit},{rng("M")},"<=0"),0)',
            f'=_xlfn.MINIFS({rng("L")},{crit})',
            f'=IFERROR(AVERAGEIFS({rng("M")},{crit},{rng("M")},"<=0"),0)',
            f'=_xlfn.MINIFS({rng("M")},{crit})',
            f'=IFERROR(AVERAGEIFS({rng("L")},{crit}),0)',
            f'=IFERROR(AVERAGEIFS({rng("M")},{crit}),0)',
            f'=SUMIFS({rng("M")},{crit})',
            m["max_equity_dd_pct"], m["worst_day_usdt"], f"=R{rr}/'Parametri'!$B$6",
            None, None,
            f'=IF(AND(I{rr}>=$B$4,N{rr}>0,OR(C{rr}="Originale",T{rr}>0)),"Sì","No")']
    for j, v in enumerate(vals, 1):
        c = wsR.cell(rr, j, v); c.font = B; c.border = BOX
    for j in (17, 18): wsR.cell(rr, j).font = BLUE
    for j, fmt in zip(range(7, 22), [INT, INT, PCT1, PCT, PCT, USD, USD, PCT, USD, USD, PCT, USD, PCT, '0.00;-0.00;"-"', '0.00;-0.00;"-"']):
        wsR.cell(rr, j).number_format = fmt
# delta vs originale dello stesso periodo/dettaglio
orig_for = {"R1_sl10_5m_2022-24":"R0_replica_5m","R1_sl15_5m_2022-24":"R0_replica_5m",
            "D1_sl10_1m_2022-24":"D1_orig_1m_2022-24","D1_sl15_1m_2022-24":"D1_orig_1m_2022-24",
            "D2_sl10_1m_2025":"D2_orig_1m_2025","D2_sl15_1m_2025":"D2_orig_1m_2025",
            "D3_sl10_1m_2026":"D3_orig_1m_2026","D3_sl15_1m_2026":"D3_orig_1m_2026",
            "T1_orig_1m_2022-24_tickproxy":"D1_orig_1m_2022-24","T2_orig_1m_2025_tickproxy":"D2_orig_1m_2025","T3_orig_1m_2026_tickproxy":"D3_orig_1m_2026"}
for lab, o in orig_for.items():
    rr, ro = rowof[lab], rowof[o]
    wsR.cell(rr, 20, f"=(J{rr}-J{ro})*100"); wsR.cell(rr, 21, f"=(K{rr}-K{ro})*100")
for lab in ("R0_replica_5m","D1_orig_1m_2022-24","D2_orig_1m_2025","D3_orig_1m_2026"):
    rr = rowof[lab]; wsR.cell(rr, 20, 0); wsR.cell(rr, 21, 0)
last = HR + len(TESTS)
wsR.cell(HR, 17).comment = Comment("Fonte: calcolato da Claude (script analyze.py) con equity mark-to-market ogni 5 minuti sulle chiusure 5m Binance, posizioni aperte incluse. Freqle riporta -3,67% sui soli trade chiusi.", "Claude")
wsR.cell(HR, 18).comment = Comment("Fonte: calcolato da Claude come somma dei profitti netti dei trade chiusi per giorno UTC (stessa definizione di Freqle: -1,80% nella replica).", "Claude")
wsR.cell(HR, 20).comment = Comment("Punti percentuali: positivo = perdita meno grave dell'originale dello stesso periodo e dettaglio.", "Claude")

# confronto con report Freqle
r0 = last + 2
wsR.cell(r0, 1, "Verifica replica Freqle (2022-2024, 5m)").font = SUB
header(wsR, r0 + 1, ["Metrica", "Report Freqle", "Replica", "Differenza"])
fr = [("Trade", 298, f"=G{rowof['R0_replica_5m']}", INT), ("Win rate netto", 0.869, f"=I{rowof['R0_replica_5m']}", PCT1),
      ("Risultato medio netto %", 0.0248, f"=N{rowof['R0_replica_5m']}", PCT), ("Profitto totale (USDT)", 739, f"=P{rowof['R0_replica_5m']}", USD),
      ("Perdita peggiore %", -0.1802, f"=K{rowof['R0_replica_5m']}", PCT), ("Peggior giornata %", -0.018, f"=S{rowof['R0_replica_5m']}", PCT)]
for i, (n, a, b, fmt) in enumerate(fr):
    rr = r0 + 2 + i
    wsR.cell(rr, 1, n).font = B; c = wsR.cell(rr, 2, a); c.font = BLUE; c.number_format = fmt
    c = wsR.cell(rr, 3, b); c.font = GREEN; c.number_format = fmt; c = wsR.cell(rr, 4, f"=C{rr}-B{rr}"); c.number_format = fmt
wsR.cell(r0 + 1, 2).comment = Comment("Fonte: Freqle, report binance check 79305, run del 2026-10-08, https://freqle.org/strategy/6a509820785852e6/check/79305/report", "Claude")

# stop: vincenti toccati e trade peggiori
r1 = r0 + 2 + len(fr) + 1
wsR.cell(r1, 1, "Effetto degli stop sui trade dell'originale (stessa coppia e stessa apertura)").font = SUB
h2 = ["Confronto","Trade abbinati","Vincenti originali","Vincenti chiusi dallo stop","Utile perso su quei vincenti (USDT)",
      "Perdenti originali chiusi dallo stop","10 peggiori: originale (USDT)","10 peggiori: con stop (USDT)","Riduzione perdita 10 peggiori (USDT)",
      "Tutti i perdenti: originale (USDT)","Tutti i perdenti: con stop (USDT)","Riduzione perdita perdenti (USDT)"]
header(wsR, r1 + 1, h2); wsR.row_dimensions[r1 + 1].height = 45
for i, k in enumerate(["R1_sl10_5m_2022-24","R1_sl15_5m_2022-24","D1_sl10_1m_2022-24","D1_sl15_1m_2022-24","D2_sl10_1m_2025","D2_sl15_1m_2025","D3_sl10_1m_2026","D3_sl15_1m_2026"]):
    s = cmp_[k]; rr = r1 + 2 + i
    vals = [NAME[k], s["matched"], s["orig_winners_matched"], s["orig_winners_hit_stop"], s["winners_lost_usdt"], s["orig_losers_hit_stop"],
            s["worst_orig_sum_usdt"], s["worst_var_sum_usdt"], f"=H{rr}-G{rr}", s["orig_losers_sum_usdt"], s["var_on_orig_losers_sum_usdt"], f"=K{rr}-J{rr}"]
    for j, v in enumerate(vals, 1):
        c = wsR.cell(rr, j, v); c.font = BLUE if j not in (1, 9, 12) else B; c.border = BOX
        c.number_format = INT if j in (2, 3, 4, 6) else USD
wsR.cell(r1 + 1, 1).comment = Comment("Fonte: calcolato da Claude (script compare.py) abbinando i trade per coppia e data di apertura. Valori positivi di riduzione = perdita minore con lo stop.", "Claude")

# tick proxy
r2 = r1 + 2 + 8 + 1
wsR.cell(r2, 1, "Deadfish con proxy del tick volume (numero di transazioni Binance al posto del volume)").font = SUB
header(wsR, r2 + 1, ["Periodo","Trade","Uscite cambiate","Uscite deadfish (volume reale)","Uscite deadfish (proxy)","Profitto volume reale (USDT)","Profitto proxy (USDT)","Differenza (USDT)"])
for i, (k, per) in enumerate([("T1_orig_1m_2022-24_tickproxy","2022-2024"),("T2_orig_1m_2025_tickproxy","2025"),("T3_orig_1m_2026_tickproxy","gen-ott 2026")]):
    rr = r2 + 2 + i
    if k in tick: s = tick[k]; ch, dr, dp = s["exits_changed"], s["deadfish_real"], s["deadfish_proxy"]
    else:
        o = pd.DataFrame(runs["D3_orig_1m_2026"]["trades"]); v = pd.DataFrame(runs[k]["trades"])
        ch = int(((o.close_date.values != v.close_date.values) | (o.exit_reason.values != v.exit_reason.values)).sum()) if len(o) == len(v) else None
        dr = int((o.exit_reason == "sell_stoploss_deadfish").sum()); dp = int((v.exit_reason == "sell_stoploss_deadfish").sum())
    base = {"T1_orig_1m_2022-24_tickproxy":"D1_orig_1m_2022-24","T2_orig_1m_2025_tickproxy":"D2_orig_1m_2025","T3_orig_1m_2026_tickproxy":"D3_orig_1m_2026"}[k]
    vals = [per, f"=G{rowof[k]}", ch, dr, dp, f"=P{rowof[base]}", f"=P{rowof[k]}", f"=G{rr}-F{rr}"]
    for j, v in enumerate(vals, 1):
        c = wsR.cell(rr, j, v); c.font = BLUE if j in (3, 4, 5) else B; c.border = BOX; c.number_format = USD if j >= 6 else INT
wsR.cell(r2 + 2 + 3, 1, "Nel 2022-2024 cambiano 3 uscite su 308: SEI -13,7% diventa -21,7%, ATOM -6,5% diventa -0,9%, COMP -5,3% diventa -5,1%. Il proxy non è il tick volume FTMO: va verificato sul server.").font = Font(name=F, italic=True)

# MT5 per profilo
r3 = r2 + 2 + 3 + 2
wsR.cell(r3, 1, "MT5 FTMO-Demo (si compila da solo dalla scheda Risultati MT5)").font = SUB
header(wsR, r3 + 1, ["Profilo","Trade","Vincenti","Win rate netto","Perdita media (valuta conto)","Perdita peggiore (valuta conto)","Risultato medio netto (valuta conto)","Profitto netto totale","Commissioni totali","Swap totali"])
M = "'Risultati MT5'"
for i, prof in enumerate(["Originale", "SL 10%", "SL 15%"]):
    rr = r3 + 2 + i; cr = f"{M}!$A$6:$A$5000,$A{rr}"
    mr = lambda col: f"{M}!${col}$6:${col}$5000"
    vals = [prof, f"=COUNTIFS({cr})", f'=COUNTIFS({cr},{mr("M")},">0")', f"=IF(B{rr}=0,0,C{rr}/B{rr})",
            f'=IFERROR(AVERAGEIFS({mr("M")},{cr},{mr("M")},"<=0"),0)', f'=IF(B{rr}=0,0,_xlfn.MINIFS({mr("M")},{cr}))',
            f'=IFERROR(AVERAGEIFS({mr("M")},{cr}),0)', f'=SUMIFS({mr("M")},{cr})', f'=SUMIFS({mr("K")},{cr})', f'=SUMIFS({mr("L")},{cr})']
    for j, v in enumerate(vals, 1):
        c = wsR.cell(rr, j, v); c.font = B; c.border = BOX; c.number_format = INT if j in (2, 3) else (PCT1 if j == 4 else USD)
wsR.freeze_panes = "B7"
for i, w in enumerate([34,13,11,10,24,22,9,10,11,12,12,12,12,13,13,13,13,13,12,14,14,11], 1): wsR.column_dimensions[L(i)].width = w

# ---------------- Parametri ----------------
wsP["A1"] = "Parametri dei test"; wsP["A1"].font = TITLE
header(wsP, 3, ["Parametro", "Valore", "Fonte / nota"])
P = [("Exchange e mercato","Binance Spot","Freqle FAQ, https://freqle.org/faq"),
     ("Coppie","33 (elenco sotto)","Freqle FAQ, https://freqle.org/faq"),
     ("Saldo iniziale (USDT)",1000,"Freqle base config: dry_run_wallet"),
     ("Stake per trade (USDT)",100,"Freqle base config: stake_amount"),
     ("Posizioni aperte max",10,"Freqle base config: max_open_trades"),
     ("Fee per lato",0.001,"Freqle: 0,1% per side, ingresso e uscita a mercato"),
     ("Timeframe segnali","5m","binance.py"),
     ("Dettaglio uscite","1m (--timeframe-detail 1m)","Richiesta utente"),
     ("Periodo Freqle","2022-01-01 / 2025-01-01","Freqle: --timerange 20220101-20250101"),
     ("Periodo selezione","2025-01-01 / 2026-01-01","Richiesta utente"),
     ("Periodo fuori campione","2026-01-01 / 2026-11-01","Richiesta utente; eseguito dopo il congelamento del 22/11/2026 19:13 UTC"),
     ("Protezioni","--enable-protections (la strategia non ne definisce)","Freqle sandbox command"),
     ("Versione freqtrade","2026.10","pip, eseguito da Claude"),
     ("Tick size prezzi","Stimata dai decimali dei prezzi 2026","Mercati Binance non scaricabili da qui; quantità con precisione 1e-8"),
     ("Variante SL 10%","stoploss = -0,10 fisso dal prezzo d'ingresso","binance_sl10.py"),
     ("Variante SL 15%","stoploss = -0,15 fisso dal prezzo d'ingresso","binance_sl15.py"),
     ("InpReplicateTagQuirk","Attivo","Richiesta utente"),
     ("InpHardStopPct originale","0 (disattivo)","Richiesta utente"),
     ("Profilo MT5: rischio per trade",0.0025,"Richiesta utente (0,25% equity)"),
     ("Profilo MT5: rischio aperto max",0.01,"Richiesta utente (1%)"),
     ("Profilo MT5: conto","FTMO-Demo 100.000","Richiesta utente"),
     ("Commissione FTMO crypto per lato",0.000325,"FTMO blog 28/07/2025, https://ftmo.com/it/blog/ftmo-migliora-il-trading-crypto-nuovi-strumenti-e-spread-piu-competitivi/ (da verificare sul server)")]
for i, (a, b, c) in enumerate(P):
    rr = 4 + i
    wsP.cell(rr, 1, a).font = B; x = wsP.cell(rr, 2, b); x.font = BLUE; wsP.cell(rr, 3, c).font = B
    if isinstance(b, float): x.number_format = '0.0000%' if b < 0.001 else '0.00%'
    if isinstance(b, int): x.number_format = '#,##0'
# B6 = saldo iniziale (usato nel Riepilogo)
assert wsP["A6"].value == "Saldo iniziale (USDT)"
rp = 4 + len(P) + 1
wsP.cell(rp, 1, "Parametri strategia (default di binance.py, uguali in tutte le varianti)").font = SUB
header(wsP, rp + 1, ["Parametro", "Valore", "Uso"])
SP = [("buy_rsi_fast",50,"ewo: RSI(4) <"),("buy_rsi",30,"ewo: RSI(14) <"),("buy_ewo",-1.238,"ewo: EWO(50,200) >"),("buy_ema_low",0.956,"ewo: close < EMA8 ×"),
      ("buy_ema_high",0.986,"ewo: close < EMA16 ×"),("buy_rsi_fast_32",63,"buy_1: RSI(4) <"),("buy_rsi_32",16,"buy_1: RSI(14) >"),("buy_sma15_32",0.932,"buy_1: close < SMA15 ×"),
      ("buy_cti_32",-0.8,"buy_1: CTI(20) <"),("sell_fastx",75,"stop -0,1% se FastK(5) >"),("sell_deadfish_bb_width",0.05,"deadfish: larghezza BB <"),
      ("sell_deadfish_profit",-0.05,"deadfish: profitto <"),("sell_deadfish_bb_factor",1.0,"deadfish: close > BB media ×"),("sell_deadfish_volume_factor",1.0,"deadfish: vol12 < vol24 ×"),
      ("stoploss originale",-0.99,"stop di base"),("minimal_roi",10,"1000%: nessun take profit")]
for i, (a, b, c) in enumerate(SP):
    rr = rp + 2 + i; wsP.cell(rr, 1, a).font = B; x = wsP.cell(rr, 2, b); x.font = BLUE; wsP.cell(rr, 3, c).font = B
rd = rp + 2 + len(SP) + 1
wsP.cell(rd, 1, "Dati Binance per coppia (5m e 1m da data.binance.vision, checksum SHA256 verificati su 3.692 file)").font = SUB
header(wsP, rd + 1, ["Coppia", "Prima candela 5m (UTC)", "Ultima candela 5m (UTC)", "Candele 5m mancanti", "Candele 1m mancanti", "Buchi oltre 1 ora", "Nota"])
d5 = datarep[datarep.tf == "5m"].set_index("pair"); d1 = datarep[datarep.tf == "1m"].set_index("pair")
for i, p in enumerate(d5.index):
    rr = rd + 2 + i
    first = d5.loc[p, "first"][:16]
    note = "" if first.startswith("2021-12") else f"Quotata dopo l'inizio del test: nessun dato prima del {first[:10]}"
    if p == "POL/USDT": note += " (prima era MATIC/USDT, non incluso come in Freqle)"
    vals = [p, first, d5.loc[p, "last"][:16], int(d5.loc[p, "missing_candles"]), int(d1.loc[p, "missing_candles"]),
            "" if pd.isna(d5.loc[p, "gaps_over_1h"]) else d5.loc[p, "gaps_over_1h"], note]
    for j, v in enumerate(vals, 1): c = wsP.cell(rr, j, v); c.font = BLUE if j in (2, 3, 4, 5, 6) else B
wsP.cell(rd + 1, 1).comment = Comment("Fonte: https://data.binance.vision (archivio ufficiale binance-public-data), file mensili 2021-12 / 2026-10, scaricati il 22/11/2026. Il buco del 24/03/2023 12:35-14:00 è un fermo di Binance.", "Claude")
for i, w in enumerate([34, 34, 22, 14, 14, 36, 60], 1): wsP.column_dimensions[L(i)].width = w

# ---------------- Risultati MT5 ----------------
wsM["A1"] = "Risultati MT5 FTMO-Demo"; wsM["A1"].font = TITLE
wsM["A2"] = "Incolla dalla riga 6 il contenuto di E0V1E_trades_<SIMBOLO>_<MAGIC>.csv (cartella Dati comuni\\Files) e scrivi nella colonna A il profilo: Originale, SL 10% o SL 15%."
wsM["A3"] = "Le celle gialle sono da compilare. La riga 5 è un esempio con valori inventati: cancellala prima di usare il riepilogo."
cm = ["Profilo","position_id","symbol","open_time","open_price","close_time","close_price","lots","profit_pct","profit_money","commission","swap","net_money","duration_min","enter_tag","exit_reason","Modello tester","Tick reali disponibili"]
header(wsM, 4, cm)
ex = ["Esempio", 123456, "SOLUSD", "2026.03.02 14:05:00", 142.35, "2026.03.02 14:40:00", 145.10, 7.0, 1.866, 19.25, -0.66, 0.0, 18.59, 35.0, "ewo", "trailing_stop_loss", "Ogni tick basato su tick reali", "Sì"]
for j, v in enumerate(ex, 1): c = wsM.cell(5, j, v); c.font = Font(name=F, italic=True, color="808080")
for rr in range(6, 206):
    for j in range(1, 19): wsM.cell(rr, j).fill = YEL
wsM.freeze_panes = "A5"
for i, w in enumerate([11,12,10,20,11,20,11,8,10,12,11,8,11,11,10,22,26,12], 1): wsM.column_dimensions[L(i)].width = w

for ws in (wsR, wsT, wsP, wsM): ws.sheet_view.showGridLines = True
wb.save(OUT); print("saved", OUT, "trade rows", lastT - 1)
