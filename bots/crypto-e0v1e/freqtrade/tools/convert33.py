import sys, os, glob, json, zipfile, io, pandas as pd, numpy as np
src, ft = sys.argv[1], sys.argv[2]
out_real = os.path.join(ft, "user_data/data/binance"); out_trd = os.path.join(ft, "user_data/data_trades/binance")
os.makedirs(out_real, exist_ok=True); os.makedirs(out_trd, exist_ok=True)
PAIRS = "BTC ETH BNB SOL XRP ADA DOGE TRX AVAX LINK DOT POL LTC BCH UNI XLM ATOM ETC FIL APT ICP HBAR VET ARB OP AAVE INJ CRV SNX COMP SUI NEAR SEI".split()
report, ticks = [], {}
for p in PAIRS:
    sym = p + "USDT"
    for tf, step in (("5m", "5min"), ("1m", "1min")):
        fs = sorted(glob.glob(f"{src}/{tf}/{sym}/*.zip"))
        if not fs:
            report.append(dict(pair=f"{p}/USDT", tf=tf, first=None, last=None, rows=0, missing_candles=None)); continue
        parts = []
        for f in fs:
            with zipfile.ZipFile(f) as z:
                raw = z.read(z.namelist()[0]).decode()
            df = pd.read_csv(io.StringIO(raw), header=None, usecols=[0,1,2,3,4,5,8], dtype={1:str,2:str,3:str,4:str})
            if not str(df.iloc[0,0]).isdigit(): df = df.iloc[1:]
            parts.append(df)
            if tf == "1m" and f >= f"{src}/{tf}/{sym}/{sym}-1m-2026-01.zip":
                for col in (1,2,3,4):
                    s = df[col].str.rstrip("0").str.split(".").str[1].fillna("").str.len().max()
                    ticks[p] = max(ticks.get(p, 0), int(s))
        df = pd.concat(parts, ignore_index=True)
        df.columns = ["ts","open","high","low","close","volume","trades"]
        df["ts"] = df["ts"].astype("int64"); df["ts"] = np.where(df["ts"] > 1e14, df["ts"] // 1000, df["ts"])
        df["date"] = pd.to_datetime(df["ts"], unit="ms", utc=True)
        for c in ("open","high","low","close","volume"): df[c] = df[c].astype(float)
        df = df.drop_duplicates("date").sort_values("date").reset_index(drop=True)
        full = pd.date_range(df.date.iloc[0], df.date.iloc[-1], freq=step)
        miss = len(full) - len(df)
        # periodi mancanti piu' lunghi di 1 ora
        d = df.date.diff(); big = df.loc[d > pd.Timedelta(hours=1), "date"]
        gaps = [f"{(t - d[i]).strftime('%Y-%m-%d %H:%M')}->{t.strftime('%Y-%m-%d %H:%M')}" for i, t in big.items()]
        report.append(dict(pair=f"{p}/USDT", tf=tf, first=str(df.date.iloc[0]), last=str(df.date.iloc[-1]), rows=len(df), missing_candles=int(miss), gaps_over_1h="; ".join(gaps)))
        cols = ["date","open","high","low","close","volume"]
        df[cols].to_feather(f"{out_real}/{p}_USDT-{tf}.feather")
        t = df[["date","open","high","low","close"]].copy(); t["volume"] = df["trades"].astype(float)
        t.to_feather(f"{out_trd}/{p}_USDT-{tf}.feather")
    print(p, "ok", flush=True)
pd.DataFrame(report).to_csv(os.path.join(ft, "data_report.csv"), index=False)
json.dump({p: 10**-d for p, d in ticks.items()}, open(os.path.join(ft, "ticks.json"), "w"), indent=1)
