import sys, os, json
from freqtrade.exchange import exchange as exmod
TICKS = json.load(open(os.environ["FT_TICKS"]))
def fake_market(base, tick, quote="USDT"):
    return {"id": base+quote, "symbol": f"{base}/{quote}", "base": base, "quote": quote,
            "baseId": base, "quoteId": quote, "settle": None, "settleId": None, "active": True,
            "type": "spot", "spot": True, "margin": False, "swap": False, "future": False,
            "option": False, "contract": False, "linear": None, "inverse": None,
            "taker": 0.001, "maker": 0.001, "contractSize": None, "expiry": None, "strike": None,
            "precision": {"amount": 1e-8, "price": tick},
            "limits": {"amount": {"min": 1e-8, "max": 9e12}, "price": {"min": tick, "max": 1e9},
                       "cost": {"min": 5, "max": None}, "leverage": {"min": None, "max": None}},
            "info": {}}
MK = {f"{b}/USDT": fake_market(b, t) for b, t in TICKS.items()}
def reload_markets(self, force=False, *, load_leverage_tiers=True):
    self._api.set_markets(MK); self._api_async.set_markets(MK)
    self._markets = self._api.markets; self._last_markets_refresh = 1
exmod.Exchange.reload_markets = reload_markets
from freqtrade.main import main
sys.exit(main(sys.argv[1:]))
