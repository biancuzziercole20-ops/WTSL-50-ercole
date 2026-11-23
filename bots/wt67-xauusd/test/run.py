"""Esegue i test del collegamento sul sorgente MQL5 incluso nel progetto."""
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    tests = Path(__file__).resolve().parent
    ea = tests.parent / "WT67_Collegamento_50k.mq5"
    source = ea.read_text(encoding="utf-8-sig")
    # Il mock fornisce CTrade. Le proprietà MT5 sono metadati per MetaEditor.
    lines = [
        line for line in source.splitlines(keepends=True)
        if not line.startswith("#property ")
        and line.strip() != r"#include <Trade\Trade.mqh>"
    ]
    with tempfile.TemporaryDirectory() as directory:
        build = Path(directory)
        (build / "body.hpp").write_text("".join(lines), encoding="utf-8")
        binary = build / "check"
        subprocess.run(
            [os.environ.get("CXX", "g++"), "-std=c++17", "-I", str(build),
             str(tests / "check.cpp"), "-o", str(binary)], check=True,
        )
        subprocess.run([str(binary)], check=True, cwd=build)


if __name__ == "__main__":
    main()
