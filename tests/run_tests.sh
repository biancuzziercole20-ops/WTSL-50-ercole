#!/usr/bin/env bash
# Compila WTSL-50%ercole.mq5 sul simulatore dell'API MT5 ed esegue i test.
# Uso: tests/run_tests.sh   (WTSL_VERBOSE=1 per vedere il registro degli EA)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tests/build
# Il sorgente MQL5 diventa il corpo di una struct C++: si tolgono solo le
# righe #property e "input group" e la parola chiave "input".
sed -e '/^#property/d' -e '/^input group/d' -e 's/^input //' 'WTSL-50%ercole.mq5' > tests/build/ea_body.inc
g++ -std=c++17 -O0 -g -Wall -Wextra -Wno-unused-parameter -I tests -I tests/build \
    -o tests/build/test_wtsl50 tests/test_wtsl50.cpp 2> tests/build/compilazione.log || { cat tests/build/compilazione.log; exit 1; }
if [ -s tests/build/compilazione.log ]; then echo "Avvisi del compilatore:"; cat tests/build/compilazione.log; fi
rm -rf tests/build/work
tests/build/test_wtsl50 tests/build/work tests/RISULTATI_TEST.md tests/wt_riferimento.py
