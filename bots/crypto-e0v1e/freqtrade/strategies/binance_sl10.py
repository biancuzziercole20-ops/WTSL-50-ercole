# Variante: stesso codice di binance.py + stop fisso sul broker a -10% dal prezzo d'ingresso.
# Quando l'originale restituirebbe lo stoploss di base, qui si restituisce None:
# lo stop resta fermo a open_rate * (1 - 0.10) invece di diventare trailing.
from binance import binance

class binance_sl10(binance):
    stoploss = -0.10

    def custom_stoploss(self, pair, trade, current_time, current_rate, current_profit, **kwargs):
        sl = super().custom_stoploss(pair, trade, current_time, current_rate, current_profit, **kwargs)
        if sl == self.stoploss:
            return None
        return sl
