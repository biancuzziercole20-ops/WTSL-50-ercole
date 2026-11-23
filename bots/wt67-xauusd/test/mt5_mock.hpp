#pragma once
#include <algorithm>
#include <cassert>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <initializer_list>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#include <sys/types.h>
using string = std::string;
using datetime = long;
#define input
const int INVALID_HANDLE=-1, INIT_SUCCEEDED=0, INIT_FAILED=1, INIT_PARAMETERS_INCORRECT=2;
enum {FILE_READ=1,FILE_WRITE=2,FILE_BIN=4,FILE_COMMON=8,FILE_SHARE_READ=16,FILE_REWRITE=32};
enum {
 ACCOUNT_CURRENCY, ACCOUNT_LOGIN, ACCOUNT_MARGIN_MODE, ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,
 ACCOUNT_TRADE_ALLOWED, ACCOUNT_TRADE_EXPERT, DEAL_COMMENT, DEAL_ENTRY, DEAL_ENTRY_IN,
 DEAL_ENTRY_INOUT, DEAL_ENTRY_OUT, DEAL_ENTRY_OUT_BY, DEAL_MAGIC, DEAL_ORDER, DEAL_SYMBOL, DEAL_TYPE,
 DEAL_TYPE_BUY, DEAL_TYPE_SELL, DEAL_VOLUME, MQL_TESTER, MQL_TRADE_ALLOWED, ORDER_FILLING_FOK,
 ORDER_FILLING_RETURN, ORDER_MAGIC, ORDER_SYMBOL, POSITION_COMMENT, POSITION_IDENTIFIER,
 POSITION_MAGIC, POSITION_PRICE_OPEN, POSITION_PROFIT, POSITION_REASON, POSITION_REASON_EXPERT,
 POSITION_SL, POSITION_SYMBOL, POSITION_TIME, POSITION_TP, POSITION_TYPE, POSITION_TYPE_BUY,
 POSITION_TYPE_SELL, SYMBOL_CURRENCY_BASE, SYMBOL_CURRENCY_PROFIT, SYMBOL_POINT, SYMBOL_TRADE_CONTRACT_SIZE,
 SYMBOL_TRADE_EXECUTION_EXCHANGE, SYMBOL_TRADE_EXECUTION_INSTANT, SYMBOL_TRADE_EXECUTION_REQUEST,
 SYMBOL_TRADE_EXEMODE, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_TICK_SIZE,
 SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_STEP, TERMINAL_COMMONDATA_PATH, TERMINAL_CONNECTED,
 TERMINAL_TRADE_ALLOWED, TRADE_RETCODE_CANCEL, TRADE_RETCODE_CLIENT_DISABLES_AT, TRADE_RETCODE_DONE,
 TRADE_RETCODE_DONE_PARTIAL, TRADE_RETCODE_INVALID, TRADE_RETCODE_INVALID_FILL, TRADE_RETCODE_INVALID_PRICE,
 TRADE_RETCODE_INVALID_STOPS, TRADE_RETCODE_INVALID_VOLUME, TRADE_RETCODE_MARKET_CLOSED, TRADE_RETCODE_NO_MONEY,
 TRADE_RETCODE_PLACED, TRADE_RETCODE_PRICE_CHANGED, TRADE_RETCODE_PRICE_OFF, TRADE_RETCODE_REJECT,
 TRADE_RETCODE_REQUOTE, TRADE_RETCODE_SERVER_DISABLES_AT, TRADE_RETCODE_TOO_MANY_REQUESTS,
 TRADE_RETCODE_TRADE_DISABLED, TRADE_RETCODE_TIMEOUT
};
const int SYMBOL_FILLING_FOK=1, SYMBOL_FILLING_MODE=1842;
enum ENUM_ORDER_TYPE {ORDER_TYPE_BUY=0,ORDER_TYPE_SELL=1};
struct MqlDateTime{int year=0,mon=0,day=0,hour=0,min=0,sec=0,day_of_week=0;};
struct MqlTick{datetime time=0; double bid=0,ask=0;};
datetime StructToTime(const MqlDateTime&d){std::tm t{}; t.tm_year=d.year-1900;t.tm_mon=d.mon-1;t.tm_mday=d.day;t.tm_hour=d.hour;t.tm_min=d.min;t.tm_sec=d.sec;return timegm(&t);}
void TimeToStruct(datetime n,MqlDateTime&d){std::tm t{};gmtime_r(&n,&t);d={t.tm_year+1900,t.tm_mon+1,t.tm_mday,t.tm_hour,t.tm_min,t.tm_sec,t.tm_wday};}
double MathAbs(double v){return std::abs(v);} double MathRound(double v){return std::round(v);}
template<class T> void ZeroMemory(T& v){v=T{};}
void StringToUpper(string&s){std::transform(s.begin(),s.end(),s.begin(),[](unsigned char c){return std::toupper(c);});}
int StringFind(const string&s,const string&t){auto k=s.find(t);return k==string::npos?-1:int(k);}
int StringLen(const string&s){return int(s.size());}
string StringSubstr(const string&s,int k){return s.substr(k);}
long StringToInteger(const string&s){try{return std::stol(s);}catch(...){return 0;}}
string IntegerToString(long n){return std::to_string(n);}
inline const char* carg(const string&s){return s.c_str();}
template<typename T> T carg(T t){return t;}
template<typename... T> string StringFormat(string f,const T&... a){for(size_t k=0;(k=f.find("I64",k))!=string::npos;){f.replace(k,3,"l");k++;} char b[2048];std::snprintf(b,sizeof(b),f.c_str(),carg(a)...);return b;}
template<typename... T> void Print(const T&...){} template<typename... T> void Comment(const T&...){}
template<typename... T> void PrintFormat(const string&f,const T&...a){(void)StringFormat(f,a...);}
bool EventSetMillisecondTimer(int){return true;} void EventKillTimer(){} int GetLastError(){return 0;}
struct FileH{string path;int flags;};
std::map<string,std::vector<unsigned char>> files; std::map<int,FileH> handles;int handleSeq=0;
int FileOpen(const string&p,int flag){
 for(auto&kv:handles)if(kv.second.path==p && ((flag & FILE_SHARE_READ)==0 || (kv.second.flags & FILE_SHARE_READ)==0))return INVALID_HANDLE;
 if((flag&FILE_WRITE)!=0){if((flag&FILE_READ)==0 || !files.count(p))files[p]={};}else if(!files.count(p))return INVALID_HANDLE;
 int id=++handleSeq;handles[id]={p,flag};return id;
}
void FileClose(int f){handles.erase(f);} void FileFlush(int){}
bool FileIsExist(const string&p,int){return files.count(p);}
bool FileDelete(const string&p,int){return files.erase(p);}
bool FileMove(const string&a,int,const string&b,int){if(!files.count(a))return false;for(auto& it:handles)if(it.second.path==b)return false;files[b]=std::move(files[a]);files.erase(a);return true;}
ulong FileSize(int f){return files.at(handles.at(f).path).size();}
template<typename T> uint FileWriteStruct(int f,const T& val){auto&v=files[handles.at(f).path];v.resize(sizeof(val));std::memcpy(v.data(),&val,sizeof(val));return uint(v.size());}
template<typename T> uint FileReadStruct(int f,T& val){auto&v=files.at(handles.at(f).path);if(v.size()!=sizeof(val))return 0;std::memcpy(&val,v.data(),sizeof(val));return uint(v.size());}
struct Pos{ulong ticket=0;long id=0;ulong magic=0;string symbol;int side=1;double entry=0,sl=0,tp=0,vol=0,pl=0;long opened=0;int reason=POSITION_REASON_EXPERT;string tag;};
struct Deal{ulong id=0,order=0;long pos=0;ulong magic=0;string symbol;long time=0;int side=1,entry=DEAL_ENTRY_IN;double vol=0;string tag;};
struct Ord{ulong id=0,magic=0;string symbol;};
struct Broker {
 string symbol="XAUUSD",base="XAU",ccy="USD",quoteCcy="USD";long utcOffset=7200;
 bool connected=true,synced=true,allow=true,net=false,history=true,calc=true,filling=true,tester=false;
 double contract=100,tickSize=.01,volstep=.01,conversion=1,slip=0;int stops=0,freeze=0,fillFlags=1,execution=99;
 uint result=TRADE_RETCODE_DONE; MqlTick q;std::vector<Pos> pos;std::vector<Deal> deals;std::vector<Ord> orders;
 int attempts=0,closes=0,mods=0;string status;
};
std::map<long,Broker> brokers;long login=0;string _Symbol;long utcNow=0;ulong uptime=0;ulong idSeq=10000;
std::vector<Deal> selectedHistory;int selectedPos=-1, selectedOrd=-1;void use(long l){login=l;_Symbol=brokers[l].symbol;selectedPos=-1;selectedOrd=-1;selectedHistory.clear();}
Broker& B(){return brokers.at(login);} long TimeGMT(){return utcNow;}long TimeTradeServer(){return utcNow+B().utcOffset;}ulong GetTickCount64(){return uptime;}
long AccountInfoInteger(int p){if(p==ACCOUNT_LOGIN)return login;if(p==ACCOUNT_MARGIN_MODE)return B().net?0:ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;return B().allow;}
string AccountInfoString(int){return B().ccy;}long TerminalInfoInteger(int p){return p==TERMINAL_CONNECTED?B().connected:B().allow;}long MQLInfoInteger(int p){return p==MQL_TESTER?B().tester:B().allow;}
string TerminalInfoString(int){return "MOCK/COMMON";}bool SymbolIsSynchronized(const string&){return B().synced;}
string SymbolInfoString(const string&,int p){return p==SYMBOL_CURRENCY_BASE?B().base:B().quoteCcy;}
double SymbolInfoDouble(const string&,int p){switch(p){case SYMBOL_TRADE_CONTRACT_SIZE:return B().contract;case SYMBOL_VOLUME_MIN:return .01;case SYMBOL_VOLUME_MAX:return 100;case SYMBOL_VOLUME_STEP:return B().volstep;case SYMBOL_TRADE_TICK_SIZE:return B().tickSize;case SYMBOL_POINT:return .01;}return 0;}
long SymbolInfoInteger(const string&,int p){if(p==SYMBOL_TRADE_EXEMODE)return B().execution;if(p==SYMBOL_FILLING_MODE)return B().fillFlags;return p==SYMBOL_TRADE_STOPS_LEVEL?B().stops:B().freeze;}
bool SymbolInfoTick(const string&,MqlTick&q){q=B().q;return q.time>0;}
bool OrderCalcProfit(ENUM_ORDER_TYPE t,const string&,double v,double a,double b,double&pl){if(!B().calc)return false;pl=std::round((t==ORDER_TYPE_BUY?1:-1)*v*B().contract*B().conversion*(b-a)*100)/100;return true;}
int PositionsTotal(){return int(B().pos.size());}
ulong PositionGetTicket(int i){if(i<0||i>=PositionsTotal())return 0;selectedPos=i;return B().pos[i].ticket;}
bool PositionSelectByTicket(ulong t){for(int i=0;i<PositionsTotal();i++)if(B().pos[i].ticket==t){selectedPos=i;return true;}return false;}
long PositionGetInteger(int p){auto&v=B().pos.at(selectedPos);switch(p){case POSITION_IDENTIFIER:return v.id;case POSITION_MAGIC:return v.magic;case POSITION_TIME:return v.opened;case POSITION_TYPE:return v.side==1?POSITION_TYPE_BUY:POSITION_TYPE_SELL;case POSITION_REASON:return v.reason;}throw std::runtime_error("getposint");}
double PositionGetDouble(int p){auto&v=B().pos.at(selectedPos);switch(p){case POSITION_PRICE_OPEN:return v.entry;case POSITION_PROFIT:return v.pl;case POSITION_SL:return v.sl;case POSITION_TP:return v.tp;}throw std::runtime_error("getposdbl");}
string PositionGetString(int p){auto&v=B().pos.at(selectedPos);return p==POSITION_SYMBOL?v.symbol:v.tag;}
int OrdersTotal(){return int(B().orders.size());}ulong OrderGetTicket(int i){selectedOrd=i;return B().orders.at(i).id;}
string OrderGetString(int){return B().orders.at(selectedOrd).symbol;}long OrderGetInteger(int){return B().orders.at(selectedOrd).magic;}
bool HistorySelect(datetime a,datetime z){selectedHistory.clear();if(!B().history)return false;for(auto&d:B().deals)if(d.time>=a&&d.time<=z)selectedHistory.push_back(d);return true;}
bool HistorySelectByPosition(long n){selectedHistory.clear();if(!B().history)return false;for(auto&d:B().deals)if(d.pos==n)selectedHistory.push_back(d);return true;}
int HistoryDealsTotal(){return int(selectedHistory.size());}ulong HistoryDealGetTicket(int i){return selectedHistory.at(i).id;}
Deal D(ulong t){for(auto&d:selectedHistory)if(d.id==t)return d;throw std::runtime_error("unknown deal");}
long HistoryDealGetInteger(ulong t,int k){auto d=D(t);switch(k){case DEAL_ENTRY:return d.entry;case DEAL_MAGIC:return d.magic;case DEAL_TYPE:return d.side==1?DEAL_TYPE_BUY:DEAL_TYPE_SELL;case DEAL_ORDER:return d.order;}throw std::runtime_error("getdealint");}
string HistoryDealGetString(ulong t,int k){auto d=D(t);return k==DEAL_SYMBOL?d.symbol:d.tag;}double HistoryDealGetDouble(ulong t,int){return D(t).vol;}
void openPos(long id,ulong magic,int side,double entry,double sl,double tp,double vol,string tag){
 auto ord=++idSeq;B().pos.push_back({ord,id,magic,_Symbol,side,entry,sl,tp,vol,0,TimeTradeServer(),POSITION_REASON_EXPERT,tag});
 B().deals.push_back({++idSeq,ord,id,magic,_Symbol,TimeTradeServer(),side,DEAL_ENTRY_IN,vol,tag});}
void closePos(ulong ticket){if(!PositionSelectByTicket(ticket))throw std::runtime_error("absent position");auto v=B().pos.at(selectedPos);B().deals.push_back({++idSeq,++idSeq,v.id,0,v.symbol,TimeTradeServer(),-v.side,DEAL_ENTRY_OUT,v.vol,"close"});B().pos.erase(B().pos.begin()+selectedPos);}
class CTrade {public: ulong magic=0,order=0;uint rc=0;double fill=0,volume=0;
 void SetExpertMagicNumber(ulong n){magic=n;}void SetAsyncMode(bool){}void SetDeviationInPoints(ulong){}void SetTypeFilling(int){}bool SetTypeFillingBySymbol(const string&){return B().filling;}
 bool PositionOpen(const string&,ENUM_ORDER_TYPE type,double v,double p,double sl,double tp,const string&tag){B().attempts++;rc=B().result;order=0;fill=0;volume=0;
 if(rc==TRADE_RETCODE_PLACED){order=++idSeq;B().orders.push_back({order,magic,_Symbol});return true;}
 if(rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL)return false;
 fill=p+B().slip;volume=rc==TRADE_RETCODE_DONE?v:v/2;openPos(++idSeq,magic,type==ORDER_TYPE_BUY?1:-1,fill,sl,tp,volume,tag);order=B().pos.back().ticket;return true;}
 bool PositionClose(ulong t){B().closes++;closePos(t);rc=TRADE_RETCODE_DONE;return true;}
 bool PositionModify(ulong t,double sl,double tp){if(!PositionSelectByTicket(t))return false;B().mods++;auto&v=B().pos.at(selectedPos);v.sl=sl;v.tp=tp;rc=TRADE_RETCODE_DONE;return true;}
 uint ResultRetcode()const{return rc;}string ResultRetcodeDescription()const{return std::to_string(rc);}double ResultVolume()const{return volume;}double ResultPrice()const{return fill;}ulong ResultOrder()const{return order;}
};
