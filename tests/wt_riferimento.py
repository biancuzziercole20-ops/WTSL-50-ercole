"""Riferimento indipendente del WaveTrend LazyBear 10/21/4 con pandas.

Legge il CSV scritto dal banco di prova (high, low, close e i valori wt1/wt2
calcolati dalla funzione WT_Calcola dell'EA) e stampa "OK ..." se valori e
incroci coincidono, altrimenti "KO ...".
"""
import sys

import pandas as pd


def main(percorso: str) -> int:
    df = pd.read_csv(percorso)
    ap = (df["high"] + df["low"] + df["close"]) / 3.0
    esa = ap.ewm(span=10, adjust=False).mean()
    d = (ap - esa).abs().ewm(span=10, adjust=False).mean()
    ci = ((ap - esa) / (0.015 * d)).where(d > 0, 0.0)
    wt1 = ci.ewm(span=21, adjust=False).mean()
    wt2 = wt1.rolling(4, min_periods=1).mean()
    scarto = max((wt1 - df["wt1"]).abs().max(), (wt2 - df["wt2"]).abs().max())

    def incroci(a, b):
        su = (a > b) & (a.shift(1) <= b.shift(1))
        giu = (a < b) & (a.shift(1) >= b.shift(1))
        return set(df.index[su]), set(df.index[giu])

    rif = incroci(wt1, wt2)
    ea = incroci(df["wt1"], df["wt2"])
    uguali = rif == ea
    esito = "OK" if scarto < 1e-9 and uguali else "KO"
    print(f"{esito} scarto massimo {scarto:.2e}, incroci rialzisti {len(rif[0])}, ribassisti {len(rif[1])}, "
          f"coincidono: {'si' if uguali else 'no'}")
    return 0 if esito == "OK" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
