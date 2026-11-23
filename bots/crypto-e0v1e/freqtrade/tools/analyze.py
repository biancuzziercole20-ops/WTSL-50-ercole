"""Legge i risultati freqtrade (zip) e calcola le metriche richieste.
uso: analyze.py <results_dir> <datadir> <out_json>"""
import sys, os, glob, json, zipfile, pandas as pd, numpy as np
res_dir, datadir, out = sys.argv[1:4]
WALLET = 1000.0

def load_run(zp):
    with zipfile.ZipFile(zp) as z:
        n = [x for x in z.namelist() if x.endswith(".json") and not x.endswith("_config.json")][0]
        d = json.loads(z.read(n))
    strat = list(d["strategy"].keys())[0]
    return strat, d["strategy"][strat]

_px = {}
def closes(pair):
    if pair not in _px:
        df = pd.read_feather(f"{datadir}/{pair.replace('/','_')}-5m.feather")
        _px[pair] = df.set_index("date")["close"]
    return _px[pair]

def metrics(sr, start, end):
    t = pd.DataFrame(sr["trades"])
    if t.empty: return {"trades": 0}
    t["open_date"] = pd.to_datetime(t["open_date"], utc=True); t["close_date"] = pd.to_datetime(t["close_date"], utc=True)
    win = t.profit_abs > 0; los = ~win
    # equity mark-to-market ogni 5 minuti
    grid = pd.date_range(pd.Timestamp(start, tz="UTC"), pd.Timestamp(end, tz="UTC"), freq="5min")
    eq = pd.Series(WALLET, index=grid)
    for _, r in t.iterrows():
        fee_o, fee_c = r.fee_open, r.fee_close
        cost = r.amount * r.open_rate * (1 + fee_o)
        px = closes(r.pair).loc[r.open_date:r.close_date - pd.Timedelta("1ns")]
        unreal = (r.amount * px * (1 - fee_c) - cost).reindex(grid.intersection(px.index))
        eq.loc[unreal.index] += unreal.values
        eq.loc[eq.index >= r.close_date] += r.profit_abs
    peak = eq.cummax(); dd = (eq / peak - 1)
    daily = t.groupby(t.close_date.dt.date).profit_abs.sum()
    return {
        "trades": int(len(t)), "wins": int(win.sum()), "losses": int(los.sum()),
        "win_rate": float(win.mean()),
        "avg_loss_pct": float(t.loc[los, "profit_ratio"].mean()) if los.any() else 0.0,
        "avg_loss_usdt": float(t.loc[los, "profit_abs"].mean()) if los.any() else 0.0,
        "worst_trade_pct": float(t.profit_ratio.min()), "worst_trade_usdt": float(t.profit_abs.min()),
        "avg_trade_pct": float(t.profit_ratio.mean()), "avg_trade_usdt": float(t.profit_abs.mean()),
        "total_profit_usdt": float(t.profit_abs.sum()), "total_profit_pct": float(t.profit_abs.sum() / WALLET),
        "max_equity_dd_pct": float(dd.min()), "max_equity_dd_usdt": float((eq - peak).min()),
        "worst_day_usdt": float(daily.min()), "worst_day_pct": float(daily.min() / WALLET),
        "avg_duration_min": float(((t.close_date - t.open_date).dt.total_seconds() / 60).mean()),
        "exit_reasons": t.exit_reason.value_counts().to_dict(),
        "pairs_traded": int(t.pair.nunique()),
    }

runs = {}
for zp in sorted(glob.glob(f"{res_dir}/*/*.zip")):
    label = open(zp.replace(".zip", ".label")).read().strip() if os.path.exists(zp.replace(".zip", ".label")) else os.path.basename(zp)
    strat, sr = load_run(zp)
    start, end = sr["backtest_start"], sr["backtest_end"]
    m = metrics(sr, start, end); m.update(label=label, strategy=strat, start=start, end=end)
    runs[label] = {"metrics": m, "trades": sr["trades"]}
json.dump(runs, open(out, "w"), default=str)
for k, v in runs.items():
    m = v["metrics"]; print(k, {x: (round(y, 4) if isinstance(y, float) else y) for x, y in m.items() if x not in ("exit_reasons",)})
