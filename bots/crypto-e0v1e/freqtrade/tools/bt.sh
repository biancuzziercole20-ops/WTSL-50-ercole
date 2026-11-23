#!/bin/bash
# uso: bt.sh <label> <strategy> <timerange> <detail:none|1m> <datadir: data|data_trades>
S=${S:-$(cd $(dirname $0)/../.. && pwd)/work}
label=$1; strat=$2; tr=$3; det=$4; dd=$5
out=$S/ft/results/$label; mkdir -p $out
args=(backtesting -c config33.json -s $strat --timerange $tr --enable-protections --export trades --cache none --backtest-directory $out --datadir user_data/$dd/binance)
[ "$det" = "1m" ] && args+=(--timeframe-detail 1m)
cd $S/ft && FT_TICKS=$S/ft/ticks.json $S/ftenv/bin/python $S/tools/run_ft33.py "${args[@]}" > $out/log.txt 2>&1
z=$(ls -t $out/*.zip 2>/dev/null | head -1); [ -n "$z" ] && echo "$label" > "${z%.zip}.label"
echo "$label exit=$? $(grep -E 'TOTAL' $out/log.txt | tail -1 | tr -s ' ' | cut -c1-160)"
