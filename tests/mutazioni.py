"""Prova a mutazioni: rompe di proposito una regola dell'EA alla volta e
verifica che almeno un test simulato fallisca. Uso: python3 tests/mutazioni.py
"""
import pathlib
import re
import subprocess
import sys

RADICE = pathlib.Path(__file__).resolve().parent.parent
SORGENTI = {"WTSL": RADICE / "WTSL-50%ercole.mq5", "WT67": RADICE / "WT67ercole.mq5"}
CORPI = {"WTSL": "ea_body.inc", "WT67": "wt67_body.inc"}
BUILD = RADICE / "tests" / "build"

MUTAZIONI = [
    # ---- WTSL-50%ercole.mq5 (ricevitore 50k e sorgente 100k)
    ("17:30 inclusa invece che esclusa", "s < WTSL_SESSIONE_FINE_SEC", "s <= WTSL_SESSIONE_FINE_SEC"),
    ("15:30 esclusa invece che inclusa", "s >= WTSL_SESSIONE_INIZIO_SEC", "s > WTSL_SESSIONE_INIZIO_SEC"),
    ("soglia movimento 4,99", "bool okMovimento = (distanzaTick >= sogliaTick);", "bool okMovimento = (distanzaTick >= sogliaTick - 1);"),
    ("soglia perdita -499", "bool okPerdita = (Centesimi(profitto) <= -Centesimi(WTSL_SOGLIA_PERDITA_100K));",
     "bool okPerdita = (Centesimi(profitto) <= -Centesimi(WTSL_SOGLIA_PERDITA_100K) + 100);"),
    ("importi 50k non verificati", "   return (okSL && okTP);\n", "   return true;\n"),
    ("BUY al Bid invece che all'Ask", "      prezzo = tick.ask;\n", "      prezzo = tick.bid;\n"),
    ("niente Fill or Kill", "   req.type_filling = ORDER_FILLING_FOK;\n   req.type_time", "   req.type_filling = ORDER_FILLING_IOC;\n   req.type_time"),
    ("SL non incluso nella richiesta", "   req.sl = p.sl;\n", "   req.sl = 0.0;\n"),
    ("registro copie ignorato", "if(GiaCopiato(s.pos_id, s.pos_tipo, codice, motivo))", "if(false && GiaCopiato(s.pos_id, s.pos_tipo, codice, motivo))"),
    ("timeout trattato come rifiuto", "   g_registro[k].stato = REG_INCERTA;\n   SalvaRegistro();\n   LogEvento(\"Esito NON certo",
     "   g_registro[k].stato = REG_RIFIUTATA;\n   SalvaRegistro();\n   LogEvento(\"Esito NON certo"),
    ("INVIO non convertito al riavvio", "         g_registro[k].stato = REG_INCERTA;   // riavvio", "         g_registro[k].stato = REG_RIFIUTATA;   // riavvio"),
    ("storico 50k non consultato", "         if(!ChiaveDaCommento(HistoryDealGetString(deal, DEAL_COMMENT), id, tipo))\n            continue;\n         int k = CercaVoce(id, tipo);\n         long pos50",
     "         if(true)\n            continue;\n         int k = CercaVoce(id, tipo);\n         long pos50"),
    ("stessa sessione non verificata", "if(!StessaSessione((datetime)s.pos_apertura_utc, oraUtc, motivo))", "if(false && !StessaSessione((datetime)s.pos_apertura_utc, oraUtc, motivo))"),
    ("limite giornaliero 5", "if(aperture >= WTSL_MAX_APERTURE_GIORNO)", "if(aperture > WTSL_MAX_APERTURE_GIORNO)"),
    ("nessuna chiusura su incrocio opposto", "bool chiudi = (g_snap.chiusure[i].opposto == 1);", "bool chiudi = false;"),
    ("chiusura su qualsiasi chiusura del 100k", "bool chiudi = (g_snap.chiusure[i].opposto == 1);", "bool chiudi = true;"),
    ("incrocio WaveTrend nel verso sbagliato", "if(tipoChiuso == 0 && direzione == -1)", "if(tipoChiuso == 0 && direzione == 1)"),
    ("riapertura opposta non considerata", "         return 1;\n     }\n   int c = CercaCacheWT", "         return 0;\n     }\n   int c = CercaCacheWT"),
    ("dati 100k vecchi accettati", "eta > InpMaxEtaDatiMs ||", "eta > 1000000 ||"),
    ("100k disconnesso accettato", "   if(s.connesso != 1)\n", "   if(false)\n"),
    ("50k disconnesso non controllato", "   if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)\n     {\n      motivo = \"terminale 50k",
     "   if(false)\n     {\n      motivo = \"terminale 50k"),
    ("ora legale ignorata", "      return 7200;\n", "      return 3600;\n"),
    ("pausa tra tentativi ignorata", "if((long)TimeGMT() - g_registro[k].utc < InpPausaTentativiSec)", "if(false)"),
    ("verifica finale saltata", "   if(!CondizioniIngresso(f, TimeGMT(), OraMs(), p2, codice, motivo))", "   p2 = p1;\n   if(false)"),
    ("registro non scritto prima dell'invio", "   if(!SalvaRegistro())\n     {\n      g_registro[k].stato = REG_RIFIUTATA;",
     "   if(false)\n     {\n      g_registro[k].stato = REG_RIFIUTATA;"),
    ("piu' posizioni WT67 accettate", "   if(s.n_posizioni > 1)\n", "   if(s.n_posizioni > 2)\n"),
]
MUTAZIONI = [("WTSL",) + m for m in MUTAZIONI] + [
    # ---- WT67ercole.mq5 (strategia 100k)
    ("WT67", "BUY sull'incrocio ribassista", "      direzione = 1;\n   else\n      if(g_wt1[k] < g_wt2[k]", "      direzione = -1;\n   else\n      if(g_wt1[k] < g_wt2[k]"),
    ("WT67", "segnale sulla candela in formazione", "CopyRates(InpSimbolo, PERIOD_M15, 1, WT67_BARRE, g_rates)", "CopyRates(InpSimbolo, PERIOD_M15, 0, WT67_BARRE, g_rates)"),
    ("WT67", "SL a 9,99", "      sl = NormalizzaPrezzo(ingresso - InpDistanzaSL);", "      sl = NormalizzaPrezzo(ingresso - InpDistanzaSL + 0.01);"),
    ("WT67", "BUY al Bid", "      prezzo = tick.ask;\n", "      prezzo = tick.bid;\n"),
    ("WT67", "17:30 inclusa", "s < WT67_SESSIONE_FINE_SEC", "s <= WT67_SESSIONE_FINE_SEC"),
    ("WT67", "ora legale ignorata", "      return 7200;\n", "      return 3600;\n"),
    ("WT67", "limite giornaliero ignorato", "if(oggi >= InpMaxTradeGiorno)", "if(oggi > InpMaxTradeGiorno)"),
    ("WT67", "nessun controllo della candela gia' usata", "if(GlobalVariableCheck(g_nomeGV) && (long)GlobalVariableGet(g_nomeGV) == (long)barra)", "if(false)"),
    ("WT67", "segnale mai scaduto", "if(ritardo > InpMaxRitardoSegnaleSec)", "if(false)"),
    ("WT67", "nessuna chiusura sull'incrocio opposto", "            g_daChiudere = ticket;", "            g_daChiudere = 0;"),
    ("WT67", "nessun riallineamento dopo slittamento", "      if(!mancano && !(appenaAperta && spostati))", "      if(!mancano)"),
    ("WT67", "nessun nuovo tentativo dopo requote", "      Ritenta();\n      return false;\n     }\n   GlobalVariableSet", "      return true;\n     }\n   GlobalVariableSet"),
    ("WT67", "orario del Tester come UTC", "      if(OraLegaleUSA(TimeTradeServer()))\n         return 3 * 3600;\n      return 2 * 3600;", "      return 0;"),
    ("WT67", "login non verificato", "      if(login != InpConto100k)", "      if(false)"),
    ("WT67", "piu' posizioni alla volta", "   if(n > 0)\n     {\n      if((tipo == 0 && dir > 0)", "   if(n > 5)\n     {\n      if((tipo == 0 && dir > 0)"),
]


def corpo(testo: str) -> str:
    righe = []
    for riga in testo.splitlines(keepends=True):
        if riga.startswith("#property") or riga.startswith("input group"):
            continue
        righe.append(re.sub(r"^input ", "", riga))
    return "".join(righe)


def esegui(testi: dict) -> tuple[bool, str]:
    BUILD.mkdir(parents=True, exist_ok=True)
    for chiave, testo in testi.items():
        (BUILD / CORPI[chiave]).write_text(corpo(testo))
    exe = BUILD / "test_mutante"
    c = subprocess.run(["g++", "-std=c++17", "-O0", "-I", str(RADICE / "tests"), "-I", str(BUILD), "-o", str(exe),
                        str(RADICE / "tests" / "test_wtsl50.cpp")], capture_output=True, text=True)
    if c.returncode != 0:
        return False, "non compila: " + c.stderr[:300]
    r = subprocess.run([str(exe), str(BUILD / "work_mutante")], capture_output=True, text=True)
    falliti = re.findall(r"^  KO   (\S+)", r.stdout, re.M)
    return r.returncode != 0, ", ".join(falliti)


def main() -> int:
    originali = {k: v.read_text() for k, v in SORGENTI.items()}
    vivi = 0
    for file, nome, vecchio, nuovo in MUTAZIONI:
        testo = originali[file]
        if testo.count(vecchio) != 1:
            print(f"?? [{file}] {nome}: testo da mutare trovato {testo.count(vecchio)} volte")
            vivi += 1
            continue
        mutati = dict(originali)
        mutati[file] = testo.replace(vecchio, nuovo)
        presa, falliti = esegui(mutati)
        print(f"{'presa ' if presa else 'VIVA  '} [{file}] {nome}: {falliti if presa else 'nessun test fallito'}")
        vivi += 0 if presa else 1
    esegui(originali)
    print(f"\n{len(MUTAZIONI) - vivi}/{len(MUTAZIONI)} mutazioni rilevate dai test")
    return 1 if vivi else 0


if __name__ == "__main__":
    sys.exit(main())
