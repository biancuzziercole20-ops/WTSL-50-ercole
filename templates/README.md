# Modelli di file

File CSV con separatore `;` e punto decimale. L'EA li legge da `Common\Files\wtsl\`. Nel Tester si possono
dichiarare anche con `#property tester_file`.

## `simboli.csv`

Una riga per simbolo del broker. Un simbolo senza riga non viene tradato. I nomi (`AVGO.US`, `EURUSD`) e la
commissione sono esempi e vanno adattati al broker.

| Campo | Valori | Note |
|---|---|---|
| `classe` | `FOREX`, `AZIONI`, `INDICI`, `MATERIE_PRIME` | dichiarata, non dedotta dal broker |
| `lati` | `LONG`, `SHORT`, `ENTRAMBI`, `NESSUNO` | azioni e indici: `LONG`; Forex: `ENTRAMBI` |
| `tv_mintick` | tick minimo **di TradingView** | `altezza_riga = righe_tick × tv_mintick` |
| `allineamento_barre` | `BROKER`, `TV_SESSIONE` | ipotesi I-4 |
| `ancora_sessione`, `fuso_sessione` | es. `17:00` / `America/New_York` | per ricostruire H4 e MN come TradingView |
| `k_rientro_long`, `k_rientro_short` | barre H4 | ipotesi I-9 |
| `buffer_stop` | `0` o `SPREAD` | ipotesi I-17 |
| `modo` | `OPERATIVO`, `SOLO_SEGNALI`, `DISABILITATO` | materie prime: `SOLO_SEGNALI` finché non si precisano |

## `annotazioni.csv`

Una riga per ogni **trade** o **scarto**, cioè un setup guardato e rifiutato. Orari in UTC. I campi vuoti
sono ammessi, ma un trade entra nel test primario solo se ha `stato_annotazione = LIVE` e orari di ingresso
e uscita.

| Campo | Valori |
|---|---|
| `tipo` | `TRADE`, `SCARTO`, `RIFERIMENTO` (solo cambio di candela mensile) |
| `stato_annotazione` | `LIVE` (scritta al momento), `RETRO` (ricostruita dopo), `DA_CONFERMARE` |
| `annotato_il_utc` | quando è stata scritta: è la data da cui il software può usarla |
| `mese_rif` | `AAAA-MM` della candela mensile di riferimento |
| `frvp_da_utc`, `frvp_a_utc`, `poc_tv` | intervallo del Fixed Range e POC letto su TradingView |
| `pattern` | `ROUNDING`, `ACCUMULO`, `DISTRIBUZIONE`, `ALTRO` |
| `livello_trigger` | il livello che il trader considerava rotto |
| `entry_modo_dichiarato` | `BREAK`, `CLOSE`, `RETEST`, `NON_SO` |
| `rischio_pct` | `0.25` o `0.50` |
| `confluenza_macro` | `S`, `N` |
| `uscita_tipo` | `SL`, `TP`, `MANUALE` |
| `uscita_motivo` | pattern d'inversione visto (per le uscite manuali) |

La riga `AVGO-001` contiene i soli dati forniti finora. Va completata con mese, orari, Fixed Range ed esito.
