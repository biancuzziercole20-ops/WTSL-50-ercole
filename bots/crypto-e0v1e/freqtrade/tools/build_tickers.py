import json, sys, pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.comments import Comment
from openpyxl.utils import get_column_letter as L
from openpyxl.worksheet.datavalidation import DataValidation
sym = {x["code"]: x for x in json.load(open(sys.argv[1]))["data"]["symbols"] if "rypto" in x["assetClass"]}
runs = json.load(open(sys.argv[2])); OUT = sys.argv[3]
MAP = [("BTCUSD","BTC","Bitcoin"),("ETHUSD","ETH","Ethereum"),("BNBUSD","BNB","BNB"),("SOLUSD","SOL","Solana"),("XRPUSD","XRP","Ripple"),
       ("ADAUSD","ADA","Cardano"),("DOGEUSD","DOGE","Dogecoin"),("AVAUSD","AVAX","Avalanche"),("LNKUSD","LINK","Chainlink"),("DOTUSD","DOT","Polkadot"),
       ("LTCUSD","LTC","Litecoin"),("BCHUSD","BCH","Bitcoin Cash"),("UNIUSD","UNI","Uniswap"),("XLMUSD","XLM","Stellar"),("ETCUSD","ETC","Ethereum Classic"),
       ("ICPUSD","ICP","Internet Computer"),("BARUSD","HBAR","Hedera"),("VECUSD","VET","VeChain"),("AAVUSD","AAVE","AAVE"),("NERUSD","NEAR","NEAR Protocol")]
tr = {k: pd.DataFrame(runs[k]["trades"]) for k in ["D1_orig_1m_2022-24","D2_orig_1m_2025","D3_orig_1m_2026"]}
F="Arial"; H=Font(name=F,bold=True,color="FFFFFF"); HF=PatternFill("solid",fgColor="1F3864"); B=Font(name=F); BB=Font(name=F,bold=True)
BLUE=Font(name=F,color="0000FF"); YEL=PatternFill("solid",fgColor="FFFF00"); thin=Side(style="thin",color="BFBFBF"); BOX=Border(left=thin,right=thin,top=thin,bottom=thin)
wb=Workbook(); ws=wb.active; ws.title="Ticker MT5"
ws["A1"]="Ticker FTMO da caricare su MT5 con 86botERCOLE (grafico M5, file botinfo86.set)"; ws["A1"].font=Font(name=F,bold=True,size=14)
ws["A2"]="Saldo conto"; ws["B2"]=100000; ws["B2"].number_format='#,##0'
ws["A3"]="% del saldo per trade (InpStakePct)"; ws["B3"]=0.10; ws["B3"].number_format='0%'
ws["A4"]="Controvalore per trade"; ws["B4"]="=B2*B3"; ws["B4"].number_format='#,##0'
for c in ("B2","B3"): ws[c].font=BLUE; ws[c].fill=YEL
ws["B2"].comment=Comment("Fonte: conto FTMO-Demo 100.000 indicato dall'utente.","Claude"); ws["B3"].comment=Comment("Fonte: impostazione utente InpStakePct=10.","Claude")
ws["C2"]="Legenda: celle gialle da compilare (prezzo attuale e spunta), testo blu = dati importati, nero = formule."; ws["C2"].font=Font(name=F,italic=True)
hdr=["#","Simbolo MT5 (Ctrl+U)","Moneta","Coppia testata Binance","Contratto (1 lotto)","Decimali prezzo","Commissione FTMO","Leva","Swap long","Volume max per ordine (lotti)",
     "Trade 2022-24","Trade 2025","Trade gen-ott 2026","Win rate 2022-26","Prezzo attuale (da MT5)","Lotti per il controvalore","Margine stimato","Aggiunto in MT5"]
HR=6
for i,h in enumerate(hdr,1):
    c=ws.cell(HR,i,h); c.font=H; c.fill=HF; c.alignment=Alignment(horizontal="center",vertical="center",wrap_text=True); c.border=BOX
ws.row_dimensions[HR].height=45
for n,(code,base,name) in enumerate(MAP,1):
    r=HR+n; s=sym[code]; pair=f"{base}/USDT"
    cnt=[int((t.pair==pair).sum()) for t in tr.values()]
    allt=pd.concat([t[t.pair==pair] for t in tr.values()])
    vals=[n,code,name,pair,s["contractSize"],s["digits"],s["commission"]/100,s["leverageStandard"],f'{s["swapLong"]} ({s["swapType"]})',s["maxTradeVolume"],
          cnt[0],cnt[1],cnt[2],(allt.profit_abs>0).mean() if len(allt) else None,None,
          f'=IF(O{r}="","",ROUNDDOWN($B$4/(O{r}*E{r}),2))',f'=IF(O{r}="","",P{r}*O{r}*E{r}/H{r})',None]
    for j,v in enumerate(vals,1):
        c=ws.cell(r,j,v); c.border=BOX; c.font=BLUE if 5<=j<=14 else B
    ws.cell(r,2).font=BB; ws.cell(r,7).number_format='0.000%'; ws.cell(r,5).number_format='#,##0'; ws.cell(r,8).number_format='0.00'
    ws.cell(r,14).number_format='0.0%'; ws.cell(r,15).fill=YEL; ws.cell(r,18).fill=YEL; ws.cell(r,16).number_format='0.00'; ws.cell(r,17).number_format='#,##0'
last=HR+len(MAP)
dv=DataValidation(type="list",formula1='"Sì,No"',allow_blank=True); ws.add_data_validation(dv); dv.add(f"R{HR+1}:R{last}")
t=last+1; ws.cell(t,2,"Totale").font=BB
for col in "KLM": c=ws[f"{col}{t}"]; c.value=f"=SUM({col}{HR+1}:{col}{last})"; c.font=BB
ws[f"R{t}"]=f'=COUNTIF(R{HR+1}:R{last},"Sì")&" su "&COUNTA(B{HR+1}:B{last})'; ws[f"R{t}"].font=BB
ws.cell(HR,2).comment=Comment("Fonte: elenco ufficiale FTMO https://ftmo.com/wp-json/ftmo/symbols (dati della pagina https://ftmo.com/en/symbols/), letto il 22/11/2026.","Claude")
ws.cell(HR,7).comment=Comment("L'elenco FTMO riporta 0,065% (tipo 'percent'), il doppio dello 0,0325% per lato dell'articolo FTMO del 28/07/2025: probabilmente andata e ritorno. Verifica nel report del primo trade.","Claude")
ws.cell(HR,11).comment=Comment("Fonte: backtest freqtrade con dettaglio 1m sulle 33 coppie Freqle (strategia originale), eseguiti da Claude il 22/11/2026.","Claude")
ws.cell(HR,16).comment=Comment("Lotti = controvalore / (prezzo x contratto), arrotondati per difetto a 0,01. L'EA usa il passo lotto reale del server.","Claude")
notes=["Note:","Lotti e margine sono stime: compila il prezzo attuale letto da MT5. Il margine usa la leva standard FTMO.",
       "Sul server i nomi possono avere un suffisso: in Ctrl+U cerca la parte iniziale (es. SOL).",
       "Su tutti i grafici: timeframe M5, stesso InpMagic (20240501), Algo Trading attivo."]
for i,x in enumerate(notes): ws.cell(t+2+i,1,x).font=BB if i==0 else B
NA=[("TRX","TRON"),("POL","Polygon (ex MATIC)"),("ATOM","Cosmos"),("FIL","Filecoin"),("APT","Aptos"),("ARB","Arbitrum"),("OP","Optimism"),
    ("INJ","Injective"),("CRV","Curve DAO"),("SNX","Synthetix"),("COMP","Compound"),("SUI","Sui"),("SEI","Sei")]
s0=t+2+len(notes)+1
ws.cell(s0,1,"Coppie testate ma non presenti nell'elenco FTMO (in teoria non disponibili)").font=Font(name=F,bold=True,size=12,color="1F3864")
ws.cell(s0+1,1,"Se il tuo server ne mostra qualcuna in Ctrl+U, scrivi il nome trovato e trattala come gli altri ticker. Non ho dati FTMO su contratto, commissione e leva per queste.").font=Font(name=F,italic=True)
h2=["#","Da cercare in Ctrl+U","Moneta","Coppia testata Binance","Trade 2022-24","Trade 2025","Trade gen-ott 2026","Win rate 2022-26","Trovata sul server?","Nome trovato in MT5"]
HR2=s0+2
for i,h in enumerate(h2,1):
    c=ws.cell(HR2,i,h); c.font=H; c.fill=HF; c.alignment=Alignment(horizontal="center",vertical="center",wrap_text=True); c.border=BOX
ws.row_dimensions[HR2].height=45
for n,(base,name) in enumerate(NA,1):
    r=HR2+n; pair=f"{base}/USDT"; cnt=[int((tt.pair==pair).sum()) for tt in tr.values()]
    allt=pd.concat([tt[tt.pair==pair] for tt in tr.values()])
    vals=[n,base,name,pair,cnt[0],cnt[1],cnt[2],(allt.profit_abs>0).mean() if len(allt) else None,None,None]
    for j,v in enumerate(vals,1):
        c=ws.cell(r,j,v); c.border=BOX; c.font=BLUE if 5<=j<=8 else B
    ws.cell(r,2).font=BB; ws.cell(r,8).number_format='0.0%'; ws.cell(r,9).fill=YEL; ws.cell(r,10).fill=YEL
l2=HR2+len(NA); dv.add(f"I{HR2+1}:I{l2}")
t2=l2+1; ws.cell(t2,2,"Totale").font=BB
for col in "EFG": c=ws[f"{col}{t2}"]; c.value=f"=SUM({col}{HR2+1}:{col}{l2})"; c.font=BB
ws[f"I{t2}"]=f'=COUNTIF(I{HR2+1}:I{l2},"Sì")&" su "&COUNTA(B{HR2+1}:B{l2})'; ws[f"I{t2}"].font=BB
ws.cell(HR2,2).comment=Comment("Coppie delle 33 Freqle assenti dall'elenco ufficiale FTMO https://ftmo.com/wp-json/ftmo/symbols letto il 22/11/2026. Conteggi dai backtest con dettaglio 1m della strategia originale.","Claude")
for i,w in enumerate([4,22,18,18,12,10,12,7,18,12,10,10,12,11,14,12,12,11],1): ws.column_dimensions[L(i)].width=w
ws.freeze_panes="C7"

ws2=wb.create_sheet("Da non usare")
ws2["A1"]="Simboli FTMO da non caricare (mai testati)"; ws2["A1"].font=Font(name=F,bold=True,size=14)
for i,h in enumerate(["Simbolo / coppia","Moneta","Motivo"],1):
    c=ws2.cell(3,i,h); c.font=H; c.fill=HF; c.border=BOX
rows=[(c,sym[c]["name"].split(" vs ")[0],"Su FTMO ma non tra le 33 coppie testate") for c in ["ALGUSD","DASHUSD","GALUSD","GRTUSD","IMXUSD","MANUSD","NEOUSD","SANUSD","XMRUSD","XTZUSD"]]
for i,(a,b,c) in enumerate(rows):
    for j,v in enumerate((a,b,c),1): x=ws2.cell(4+i,j,v); x.font=B; x.border=BOX
for i,w in enumerate([18,22,48],1): ws2.column_dimensions[L(i)].width=w
wb.save(OUT); print("ok")
