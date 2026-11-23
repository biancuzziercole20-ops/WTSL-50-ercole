import sys, os, hashlib, urllib.request, concurrent.futures as cf
out = sys.argv[1]
PAIRS = "BTC ETH BNB SOL XRP ADA DOGE TRX AVAX LINK DOT POL LTC BCH UNI XLM ATOM ETC FIL APT ICP HBAR VET ARB OP AAVE INJ CRV SNX COMP SUI NEAR SEI".split()
months = [f"{y}-{m:02d}" for y in range(2021, 2027) for m in range(1, 13) if "2021-12" <= f"{y}-{m:02d}" <= "2026-10"]
B = "https://data.binance.vision/data/spot/monthly/klines"
def job(a):
    p, tf, mo = a; sym = p + "USDT"; fn = f"{sym}-{tf}-{mo}.zip"
    d = os.path.join(out, tf, sym); os.makedirs(d, exist_ok=True); fp = os.path.join(d, fn)
    url = f"{B}/{sym}/{tf}/{fn}"
    try:
        ck = urllib.request.urlopen(url + ".CHECKSUM", timeout=60).read().decode().split()[0]
    except Exception as e:
        return (p, tf, mo, "missing")
    for attempt in range(4):
        try:
            if not (os.path.exists(fp) and hashlib.sha256(open(fp,"rb").read()).hexdigest() == ck):
                data = urllib.request.urlopen(url, timeout=300).read(); open(fp, "wb").write(data)
            if hashlib.sha256(open(fp,"rb").read()).hexdigest() == ck: return (p, tf, mo, "ok")
        except Exception as e:
            err = str(e)
    return (p, tf, mo, "checksum_fail")
jobs = [(p, tf, mo) for tf in ("5m", "1m") for p in PAIRS for mo in months]
res = []
with cf.ThreadPoolExecutor(16) as ex:
    for r in ex.map(job, jobs): res.append(r)
with open(os.path.join(out, "download_log.csv"), "w") as f:
    f.write("pair,tf,month,status\n"); [f.write(",".join(r) + "\n") for r in res]
from collections import Counter
print(Counter(r[3] for r in res))
