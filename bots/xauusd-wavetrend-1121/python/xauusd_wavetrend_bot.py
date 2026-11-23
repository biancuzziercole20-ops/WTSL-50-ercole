"""
================================================================================
 XAUUSD WAVE TREND SESSION BOT - MetaTrader 5 / Python
================================================================================
Strategia:
  - Asset: SOLO XAUUSD
  - TF esecuzione: M15
  - Indicatore: WaveTrend (LazyBear)
  - Sessione operativa: 15:30–17:30 (server time)
  - Reversal su cross opposto M15
  - SL/TP: 100 pips
  - PIP_SIZE: 0.1
  - LOT_SIZE: 0.10
  - PAPER_TRADING: True
================================================================================
"""

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

# =============================================================================
# CONFIG
# =============================================================================

SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M15
RATES_COUNT = 300

BROKER_TIMEZONE = "Europe/Athens"

TRADING_START_HOUR = 15
TRADING_START_MIN = 30
TRADING_END_HOUR = 17
TRADING_END_MIN = 30

CH_LEN = 10
AVG_LEN = 21
WT_MA_LEN = 4

PIP_SIZE = 0.1
SL_PIPS = 100
TP_PIPS = 100
LOT_SIZE = 0.10

MAGIC_NUMBER = 991015

PAPER_TRADING = True

# =============================================================================
# TIMEZONE
# =============================================================================

def to_broker_server_time(candle_time_epoch):
    dt_utc = datetime.fromtimestamp(candle_time_epoch, tz=timezone.utc)
    return dt_utc.astimezone(ZoneInfo(BROKER_TIMEZONE))

def is_within_trading_window(candle_time_epoch):
    broker_time = to_broker_server_time(candle_time_epoch)
    current_minutes = broker_time.hour * 60 + broker_time.minute

    start_minutes = TRADING_START_HOUR * 60 + TRADING_START_MIN
    end_minutes = TRADING_END_HOUR * 60 + TRADING_END_MIN

    return start_minutes <= current_minutes <= end_minutes

# =============================================================================
# WAVETREND
# =============================================================================

def calculate_wavetrend(df):
    ap = (df["high"] + df["low"] + df["close"]) / 3.0

    esa = ap.ewm(span=CH_LEN, adjust=False).mean()
    d = (ap - esa).abs().ewm(span=CH_LEN, adjust=False).mean()

    ci = (ap - esa) / (0.015 * d.replace(0, np.nan))

    wt1 = ci.ewm(span=AVG_LEN, adjust=False).mean()
    wt2 = wt1.rolling(WT_MA_LEN).mean()

    df["wt1"] = wt1
    df["wt2"] = wt2

    return df
# =============================================================================
# MT5 DATA
# =============================================================================

def get_rates():
    rates = mt5.copy_rates_from_pos(
        SYMBOL,
        TIMEFRAME,
        0,
        RATES_COUNT
    )

    if rates is None or len(rates) == 0:
        return None

    df = pd.DataFrame(rates)

    df["time_epoch"] = df["time"].astype("int64")

    df["time"] = pd.to_datetime(
        df["time"],
        unit="s"
    )

    return df

# =============================================================================
# SYMBOL / STOPS
# =============================================================================

def validate_symbol():
    info = mt5.symbol_info(SYMBOL)

    if info is None:
        print(f"[ERROR] Symbol {SYMBOL} non trovato.")
        return False

    if not info.visible:
        if not mt5.symbol_select(SYMBOL, True):
            print(f"[ERROR] Impossibile selezionare {SYMBOL}.")
            return False

    return True

def validate_pip_size():
    info = mt5.symbol_info(SYMBOL)

    if info is None:
        return False

    point = info.point

    if PIP_SIZE <= 0:
        print("[ERROR] PIP_SIZE deve essere > 0.")
        return False

    ratio = PIP_SIZE / point

    if abs(ratio - round(ratio)) > 1e-9:
        print(
            f"[ERROR] PIP_SIZE={PIP_SIZE} non è multiplo "
            f"del point={point}."
        )
        return False

    return True

def check_stops_level():
    info = mt5.symbol_info(SYMBOL)

    if info is None:
        return False

    stops_level = info.trade_stops_level
    point = info.point

    minimum_distance = stops_level * point
    configured_distance = SL_PIPS * PIP_SIZE

    if configured_distance < minimum_distance:
        print(
            f"[ERROR] SL/TP troppo vicini. "
            f"Minimo broker={minimum_distance}, "
            f"configurato={configured_distance}"
        )
        return False

    return True

# =============================================================================
# SIGNALS
# =============================================================================

def get_signal(df):
    if len(df) < max(CH_LEN, AVG_LEN, WT_MA_LEN) + 5:
        return None

    prev = df.iloc[-3]
    last = df.iloc[-2]

    bullish_cross = (
        prev["wt1"] <= prev["wt2"]
        and last["wt1"] > last["wt2"]
    )

    bearish_cross = (
        prev["wt1"] >= prev["wt2"]
        and last["wt1"] < last["wt2"]
    )

    if bullish_cross:
        return "BUY"

    if bearish_cross:
        return "SELL"

    return None

# =============================================================================
# POSITION HELPERS
# =============================================================================

def get_bot_position():
    positions = mt5.positions_get(symbol=SYMBOL)

    if positions is None:
        return None

    for position in positions:
        if position.magic == MAGIC_NUMBER:
            return position

    return None

def close_position(position):
    tick = mt5.symbol_info_tick(SYMBOL)

    if tick is None:
        return False

    if position.type == mt5.POSITION_TYPE_BUY:
        order_type = mt5.ORDER_TYPE_SELL
        price = tick.bid
    else:
        order_type = mt5.ORDER_TYPE_BUY
        price = tick.ask

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": SYMBOL,
        "volume": position.volume,
        "type": order_type,
        "position": position.ticket,
        "price": price,
        "deviation": 20,
        "magic": MAGIC_NUMBER,
        "comment": "WT_REVERSAL_CLOSE"
    }

    if PAPER_TRADING:
        print(
            f"[PAPER] CLOSE "
            f"{'BUY' if position.type == mt5.POSITION_TYPE_BUY else 'SELL'}"
        )
        return True

    result = mt5.order_send(request)

    if result is None:
        print("[ERROR] order_send() restituisce None.")
        return False

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(
            f"[ERROR] Chiusura fallita: "
            f"{result.retcode} - {result.comment}"
        )
        return False

    return True
def open_position(direction):
    tick = mt5.symbol_info_tick(SYMBOL)
    if tick is None:
        return False

    if direction == "BUY":
        order_type = mt5.ORDER_TYPE_BUY
        price = tick.ask
        sl = price - SL_PIPS * PIP_SIZE
        tp = price + TP_PIPS * PIP_SIZE

    else:
        order_type = mt5.ORDER_TYPE_SELL
        price = tick.bid
        sl = price + SL_PIPS * PIP_SIZE
        tp = price - TP_PIPS * PIP_SIZE

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": SYMBOL,
        "volume": LOT_SIZE,
        "type": order_type,
        "price": price,
        "sl": sl,
        "tp": tp,
        "deviation": 20,
        "magic": MAGIC_NUMBER,
        "comment": "WT_XAUUSD"
    }

    if PAPER_TRADING:
        print(
            f"[PAPER] OPEN {direction} "
            f"price={price} SL={sl} TP={tp}"
        )
        return True

    result = mt5.order_send(request)

    if result is None:
        print("[ERROR] order_send() restituisce None.")
        return False

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(
            f"[ERROR] Apertura fallita: "
            f"{result.retcode} - {result.comment}"
        )
        return False

    print(
        f"[TRADE] {direction} aperto "
        f"order={result.order}"
    )

    return True

# =============================================================================
# MAIN
# =============================================================================

def main():

    print("=" * 80)
    print("XAUUSD WAVETREND BOT")
    print("=" * 80)

    if not mt5.initialize():
        print("[ERROR] MT5 initialize fallito.")
        return

    print("[OK] MT5 connesso.")

    account = mt5.account_info()

    if account is not None:
        print(
            f"[ACCOUNT] login={account.login} "
            f"server={account.server}"
        )

    print(
        f"[TIMEZONE] UTC -> {BROKER_TIMEZONE}"
    )

    if not validate_symbol():
        mt5.shutdown()
        return

    if not validate_pip_size():
        mt5.shutdown()
        return

    if not check_stops_level():
        mt5.shutdown()
        return

    print(
        f"[CONFIG] SYMBOL={SYMBOL} "
        f"TF=M15 "
        f"WINDOW={TRADING_START_HOUR:02d}:{TRADING_START_MIN:02d}-"
        f"{TRADING_END_HOUR:02d}:{TRADING_END_MIN:02d} "
        f"SL={SL_PIPS} pips "
        f"TP={TP_PIPS} pips "
        f"LOT={LOT_SIZE} "
        f"PAPER={PAPER_TRADING}"
    )

    last_processed_candle = None

    try:

        while True:

            df = get_rates()

            if df is None:
                time.sleep(5)
                continue

            df = calculate_wavetrend(df)

            closed_candle = df.iloc[-2]

            candle_time_epoch = int(
                closed_candle["time_epoch"]
            )

            if candle_time_epoch == last_processed_candle:
                time.sleep(2)
                continue

            last_processed_candle = candle_time_epoch

            broker_time = to_broker_server_time(
                candle_time_epoch
            )

            signal = get_signal(df)

            print(
                f"[CANDLE] {broker_time} "
                f"WT1={closed_candle['wt1']:.4f} "
                f"WT2={closed_candle['wt2']:.4f} "
                f"SIGNAL={signal}"
            )

            position = get_bot_position()

            # -------------------------------------------------------------
            # REVERSAL
            # -------------------------------------------------------------

            if position is not None:

                current_direction = (
                    "BUY"
                    if position.type == mt5.POSITION_TYPE_BUY
                    else "SELL"
                )

                if signal is not None and signal != current_direction:

                    print(
                        f"[REVERSAL] {current_direction} -> {signal}"
                    )

                    if close_position(position):
                        open_position(signal)

                continue

            # -------------------------------------------------------------
            # ENTRY
            # -------------------------------------------------------------

            if signal is None:
                continue

            if not is_within_trading_window(
                candle_time_epoch
            ):
                print(
                    "[INFO] Segnale fuori finestra operativa."
                )
                continue

            print(
                f"[ENTRY] Segnale {signal} "
                f"nella finestra operativa."
            )

            open_position(signal)

    except KeyboardInterrupt:

        print("\n[STOP] Bot fermato manualmente.")

    finally:

        mt5.shutdown()
        print("[MT5] Connessione chiusa.")

if __name__ == "__main__":
    main()
