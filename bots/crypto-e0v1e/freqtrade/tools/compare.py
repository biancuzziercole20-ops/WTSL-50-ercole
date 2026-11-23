"""Confronto trade per trade originale vs variante (stessa coppia e stessa apertura).
uso: compare.py runs.json <label_orig> <label_var> [n_peggiori]"""
import sys, json, pandas as pd
runs = json.load(open(sys.argv[1])); a, b = sys.argv[2], sys.argv[3]; N = int(sys.argv[4]) if len(sys.argv) > 4 else 10
def df(l):
    t = pd.DataFrame(runs[l]["trades"]); t["key"] = t.pair + "|" + t.open_date.astype(str); return t.set_index("key")
o, v = df(a), df(b)
common = o.index.intersection(v.index)
oc, vc = o.loc[common], v.loc[common]
win_o = oc.profit_abs > 0
hit = vc.exit_reason.isin(["stop_loss", "stoploss_on_exchange"])
res = {
  "orig": a, "variant": b, "orig_trades": len(o), "variant_trades": len(v), "matched": len(common),
  "only_in_orig": len(o.index.difference(v.index)), "only_in_variant": len(v.index.difference(o.index)),
  "orig_winners_hit_stop": int((win_o & hit).sum()),
  "orig_winners_matched": int(win_o.sum()),
  "orig_losers_hit_stop": int((~win_o & hit).sum()),
}
worst = oc.sort_values("profit_ratio").head(N)
w = pd.DataFrame({"pair": worst.pair, "open_date": worst.open_date, "orig_pct": worst.profit_ratio * 100,
                  "orig_usdt": worst.profit_abs, "orig_exit": worst.exit_reason,
                  "var_pct": vc.loc[worst.index, "profit_ratio"] * 100, "var_usdt": vc.loc[worst.index, "profit_abs"],
                  "var_exit": vc.loc[worst.index, "exit_reason"]})
res["worst_orig_sum_usdt"] = float(w.orig_usdt.sum()); res["worst_var_sum_usdt"] = float(w.var_usdt.sum())
res["worst_saving_usdt"] = res["worst_var_sum_usdt"] - res["worst_orig_sum_usdt"]
losers = oc[~win_o]
res["orig_losers_sum_usdt"] = float(losers.profit_abs.sum()); res["var_on_orig_losers_sum_usdt"] = float(vc.loc[losers.index, "profit_abs"].sum())
res["winners_lost_usdt"] = float((oc.loc[win_o & hit, "profit_abs"] - vc.loc[win_o & hit, "profit_abs"]).sum())
print(json.dumps(res, indent=1)); print(w.round(2).to_string())
json.dump({"summary": res, "worst": w.reset_index(drop=True).to_dict("records")}, open(f"{sys.argv[1]}.{b}.cmp.json", "w"), default=str)
