#include "mt5_mock.hpp"
namespace master {
#include "body.hpp"
}
namespace follower {
#include "body.hpp"
}
namespace extra {
#include "body.hpp"
}
const long A=1004001,B50=5004001, refid=9007199254740993L;
int checks=0;bool running=false;
void check(bool yes,const string&what){checks++;if(!yes)throw std::runtime_error(std::to_string(checks)+": "+what);std::cout<<"OK  "<<what<<"\n";}
long at(int y,int m,int d,int h,int min,int s=0){return StructToTime({y,m,d,h,min,s,0});}
void clockAt(long utc){utcNow=utc;}
void setQuote(long acct,double bid,double ask){use(acct);B().q={TimeTradeServer(),bid,ask};for(auto&v:B().pos){v.pl=(v.side==1?bid-v.entry:v.entry-ask)*B().contract*v.vol;}}
void age(ulong delta){ulong old=uptime;uptime+=delta;utcNow+=(uptime/1000-old/1000);for(auto&kv:brokers){kv.second.q.time=utcNow+kv.second.utcOffset;}}
void configure(){
 master::InpConto100k=A;master::InpConto50k=B50;follower::InpConto100k=A;follower::InpConto50k=B50;extra::InpConto100k=A;extra::InpConto50k=B50;
}
void finish(){if(running){use(B50);follower::OnDeinit(0);use(A);master::OnDeinit(0);running=false;}}
void fresh(){
 finish();files.clear();handles.clear();brokers.clear();selectedHistory.clear();configure();utcNow=at(2026,11,23,15,0);uptime=100000;
 brokers[A].utcOffset=7200;brokers[B50].utcOffset=-18000;brokers[B50].symbol="XAUUSD.pro";
 setQuote(A,2999.9,3000);setQuote(B50,2999.9,3000);
 use(A);if(master::OnInit()!=0)throw std::runtime_error("source init");
 use(B50);if(follower::OnInit()!=0)throw std::runtime_error("target init");
 running=true;
}
void sub(){use(B50);follower::OnTick();}
void cycle(){use(A);master::OnTick();sub();}
void original(int side,long id=refid){use(A);openPos(id,670067,side,3000,3000-side*10,3000+side*10,1,"WT67ercole New entry");}
void level(int side){if(side==1){setQuote(A,2994.80,2994.90);setQuote(B50,2994.9,2995);}else{setQuote(A,3005.1,3005.2);setQuote(B50,3005,3005.1);}}
void startTrade(int side){original(side);level(side);cycle();}
void localClose(){use(B50);closePos(B().pos.at(0).ticket);}
void closeSource(){use(A);closePos(B().pos.at(0).ticket);}
int main(){try{
 fresh(); auto&target=brokers[B50];
 check(target.attempts==0,"flat source does not send an order");
 use(B50);check(extra::OnInit()==INIT_FAILED,"exclusive 50k writer lock prevents a duplicate EA instance");
 use(99999);check(extra::OnInit()==INIT_PARAMETERS_INCORRECT,"unspecified third account cannot trade");
 original(1); setQuote(A,2995.01,2995.11);setQuote(B50,2994.9,2995);cycle();
 check(target.attempts==0,"BUY source move of 4.99 is insufficient despite ideal receiver Ask");
 setQuote(A,2995,2995.1);use(A);B().pos[0].pl=-499;age(510);cycle();
 check(target.attempts==0,"source monetary loss must also reach 500");
 setQuote(A,2995,2995.1);setQuote(B50,2995,2995.20);cycle();
 check(target.attempts==0,"BUY uses destination Ask, rejects spread causing -260/+740");
 setQuote(B50,2994.7,2994.8);sub();check(target.attempts==0,"a quote skipping beyond the requested monetary profile is skipped");
 setQuote(B50,2994.9,2995);sub();check(target.attempts==1&&target.pos.size()==1,"BUY enters on a subsequent eligible quote");
 auto pos=target.pos[0];check(pos.entry==2995&&pos.sl==2990&&pos.tp==3010&&pos.vol==.5&&pos.side==1,"BUY copies absolute prices with 0.50 lots");
 check(pos.tag=="WT67B-9007199254740993","source identifiers above 2^53 are never rounded");
 use(B50);double l,g;follower::Snapshot plan{};plan.side=1;plan.sl=pos.sl;plan.tp=pos.tp;
 check(follower::PlannedAmounts(plan,.5,2995,l,g)&&l==-250&&g==750,"gross BUY calculation matches -250/+750");
 localClose();use(B50);follower::OnDeinit(0);check(follower::OnInit()==0,"50k restarts and restores its records");age(1200);cycle();
 check(target.attempts==1,"closed copy is not opened twice after a restart");
 {
   auto receipt=follower::prefix+"_WT67B-"+IntegerToString(refid)+".used";files.erase(receipt);age(1100);cycle();
   check(target.attempts==1,"broker history also prevents a repeat when the local receipt is missing");
 }
 fresh();startTrade(-1);auto&s=brokers[B50];check(s.attempts==1&&s.pos.size()==1&&s.pos[0].side==-1,"SELL fires only in original direction");
 auto v=s.pos[0];check(v.entry==3005&&v.sl==3010&&v.tp==2990&&v.vol==.5,"SELL copies absolute source SL/TP with 0.50 lots");
 use(B50);plan.side=-1;plan.sl=v.sl;plan.tp=v.tp;check(follower::PlannedAmounts(plan,.5,3005,l,g)&&l==-250&&g==750,"gross SELL calculation matches -250/+750");
 use(A);B().pos[0].sl=3010.5;B().pos[0].tp=2989;age(1200);cycle();
 check(s.mods==1&&s.pos[0].sl==3010.5&&s.pos[0].tp==2989,"confirmed source protection levels are mirrored on an open trade");
 use(A);B().connected=false;age(3000);cycle();check(s.closes==0&&s.pos.size()==1,"source disconnection is not interpreted as an exit");
 use(A);B().connected=true;closeSource();brokers[A].history=false;age(1200);cycle();check(s.pos.size()==1,"flat snapshot alone cannot close a trade without exit confirmation");
 brokers[A].history=true;clockAt(at(2026,11,23,17,0));age(1200);cycle();check(s.closes==1&&s.pos.empty(),"source exit confirmed by its history closes the 50k even outside the entry window");
 fresh();original(1);level(1);use(A);master::OnTimer();age(2300);sub();check(brokers[B50].attempts==0,"stale source message prevents new entry");
 use(A);master::OnTimer();auto originalBytes=files.at(master::framePath);files[master::framePath].resize(6);
 sub();check(brokers[B50].attempts==0,"truncated records cannot be used to enter");
 files[master::framePath]=originalBytes;
 use(A);B().pos[0].pl=0;setQuote(A,3001,3001.1);cycle();check(brokers[B50].attempts==0,"recovery above the threshold cancels eligibility");
 fresh(); original(1);level(1);brokers[B50].contract=10;cycle();check(brokers[B50].attempts==0,"nonmatching contract size does not send a trade");
 brokers[B50].contract=100;brokers[B50].conversion=.92;sub();check(brokers[B50].attempts==0,"different account-currency valuation cannot silently change payoffs");
 brokers[B50].conversion=1;brokers[B50].stops=600;sub();check(brokers[B50].attempts==0,"broker minimum stop distance is honored");
 brokers[B50].stops=0;brokers[B50].volstep=.1;sub();check(brokers[B50].attempts==0,"invalid fixed lot volume grid halts entry");
 brokers[B50].volstep=.01;brokers[B50].calc=false;sub();check(brokers[B50].attempts==0,"missing broker valuation blocks entry");
 fresh();original(1);level(1);use(A);B().pos[0].magic=123456;cycle();check(brokers[B50].attempts==0,"foreign source magic does not produce a signal");
 use(A);B().pos[0].magic=670067;B().pos[0].reason=999;cycle();check(brokers[B50].attempts==0,"a manual source trade is ignored");
 fresh();original(1);level(1);brokers[B50].net=true;use(B50);openPos(700,1234,1,2989,2980,3020,1.0,"other");cycle();check(brokers[B50].attempts==0,"foreign netted position cannot be merged with a WT67 order");
 fresh();original(1);level(1);brokers[B50].net=true;brokers[B50].orders.push_back({750,777,"XAUUSD.pro"});cycle();check(brokers[B50].attempts==0,"foreign active netting order blocks an entry on that symbol");
 fresh();original(1);level(1);brokers[B50].allow=false;cycle();check(brokers[B50].attempts==0,"trading permissions enforced on destination only");
 fresh();original(1);level(1);brokers[A].allow=false;cycle();check(brokers[B50].attempts==1&&brokers[A].attempts==0,"read-only master supplies trades without issuing an order");
 fresh();original(1);level(1);brokers[B50].result=TRADE_RETCODE_TIMEOUT;cycle();age(2500);cycle();check(brokers[B50].attempts==1,"timeout does not duplicate a potentially accepted order");
 fresh();original(1);level(1);brokers[B50].result=TRADE_RETCODE_REQUOTE;cycle();brokers[B50].result=TRADE_RETCODE_DONE;age(1250);cycle();check(brokers[B50].attempts==2&&brokers[B50].pos.size()==1,"confirmed requote can retry after checking both feeds again");
 fresh();original(1);level(1);brokers[B50].result=TRADE_RETCODE_DONE_PARTIAL;cycle();localClose();age(1250);cycle();check(brokers[B50].attempts==1,"partial fill is managed once and never topped up as a fresh copy");
 fresh();original(1);level(1);brokers[B50].result=TRADE_RETCODE_PLACED;cycle();age(1250);cycle();check(brokers[B50].attempts==1&&brokers[B50].orders.size()==1,"an acknowledged working order is not duplicated");
 fresh();original(1);level(1);use(B50);for(int i=1;i<=4;i++)openPos(6000+i,670050,1,2995,2990,3010,.5,"previous");
 B().pos.clear();cycle();check(brokers[B50].attempts==0,"fifth distinct entry in the same Rome day is blocked");
 fresh();original(1);level(1);use(B50);openPos(6100,670050,1,2995,2990,3010,.2,"previous");
 auto piece=B().deals.back();for(int i=0;i<4;i++){piece.id=++idSeq;B().deals.push_back(piece);}B().pos.clear();
 cycle();check(brokers[B50].attempts==1,"partial deals for one order count as one daily opening");
 fresh();original(1);level(1);use(A);B().pos[0].opened-=86400;cycle();check(brokers[B50].attempts==0,"yesterday's surviving source trade cannot arm in a new session");
 fresh();original(1);level(1);setQuote(A,2989.9,2990);cycle();check(brokers[B50].attempts==0,"move through the original stop is not a new buying opportunity");
 fresh();original(-1);level(-1);setQuote(B50,3004.9,3005);cycle();check(brokers[B50].attempts==0,"SELL uses executable Bid, not Ask");
 fresh();original(1);level(1);closeSource();cycle();check(brokers[B50].attempts==0,"trade which closes before the follower can enter is skipped");
 fresh();startTrade(1);closeSource();original(-1,refid+1);level(-1);age(1200);cycle();
 check(brokers[B50].closes==1&&brokers[B50].pos.empty(),"reversal closes the first copy before opening another");
 age(1200);cycle();check(brokers[B50].attempts==2&&brokers[B50].pos[0].side==-1,"replacement trade waits for its own five-point adverse move");
 fresh();original(1);level(1);brokers[B50].fillFlags=2;cycle();check(brokers[B50].attempts==0,"IOC-only market cannot accidentally open a fractional position");
 brokers[B50].execution=SYMBOL_TRADE_EXECUTION_INSTANT;sub();check(brokers[B50].attempts==1,"instant execution supports full-volume orders even without advertised FOK flag");
 fresh();startTrade(1);brokers[B50].net=true;use(B50);auto mixed=B().deals.back();mixed.id=++idSeq;mixed.magic=55555;B().deals.push_back(mixed);
 closeSource();age(1400);cycle();check(brokers[B50].closes==0,"foreign entry into an existing net position is not closed by the copier");
 fresh();startTrade(1);brokers[B50].net=true;brokers[B50].orders.push_back({222,1234,"XAUUSD.pro"});
 closeSource();age(1400);cycle();check(brokers[B50].closes==1,"a foreign pending order does not prevent exiting an owned net position");
 fresh();startTrade(-1);use(B50);B().pos[0].tag="[dealer]";follower::OnDeinit(0);check(follower::OnInit()==0,"restart works after a broker changes the comment");
 closeSource();age(1400);cycle();check(brokers[B50].closes==1,"persisted binding recovers source exit when the broker changes the comment");
 fresh();original(1);level(1);use(A);B().q.time=TimeTradeServer()-40;cycle();check(brokers[B50].attempts==0,"a stale master quote is never refreshed by a timer heartbeat");
 fresh();original(1);level(1);use(B50);B().q.time=TimeTradeServer()-30;cycle();check(brokers[B50].attempts==0,"a stale follower quote cannot authorize an order");
 fresh();use(A);B().connected=false;age(1000);cycle();check(brokers[B50].attempts==0,"temporarily unavailable master never simulates an open");
 fresh();original(1);level(1);use(A);B().pos[0].sl=0;cycle();check(brokers[B50].attempts==0,"no entry without broker-side protection on the source");
 fresh();original(-1);level(-1);use(A);B().pos[0].tp=2990.005;cycle();check(brokers[B50].attempts==0,"an unrepresentable source target is not rounded onto a different stop grid");
 fresh();original(1);level(1);use(A);B().pos[0].pl=-500.1;B().q.bid=2995.01;B().q.ask=2995.11;cycle();check(brokers[B50].attempts==0,"a monetary loss alone does not replace the five-unit price condition");
 fresh();use(B50);follower::OnDeinit(0);B().connected=false;
 check(follower::OnInit()==0&&follower::roleLock==INVALID_HANDLE,"terminal can start before the 50k broker connects");
 B().connected=true;original(1);level(1);cycle();check(brokers[B50].attempts==1,"the link activates automatically after startup connectivity returns");
 fresh();use(A);master::OnDeinit(0);B().synced=false;
 check(master::OnInit()==0&&master::roleLock==INVALID_HANDLE,"100k observer waits for synchronized quotes on startup");
 B().synced=true;original(-1);level(-1);cycle();check(brokers[B50].attempts==1&&brokers[A].attempts==0,"read-only observer recovers automatically once symbol synchronizes");
 fresh();use(B50);follower::OnDeinit(0);B().tester=true;check(follower::OnInit()==INIT_FAILED,"a tester instance cannot access an active bridge");
 B().tester=false;B().symbol="BTCUSD";B().base="BTC";use(B50);check(follower::OnInit()==INIT_FAILED,"unrelated chart cannot be used to enter trades");
 auto winter=at(2026,11,23,14,30);auto summer=at(2026,7,23,13,30);
 check(follower::InTodaysWindow(winter,winter)&&!follower::InTodaysWindow(winter-1,winter),"15:30 Europe/Rome included and 15:29:59 excluded in winter");
 check(follower::InTodaysWindow(summer,summer+7199)&&!follower::InTodaysWindow(summer,summer+7200),"summer daylight saving applied and 17:30:00 excluded");
 check(follower::RomeOffset(at(2026,3,29,0,59,59))==3600&&follower::RomeOffset(at(2026,3,29,1,0))==7200,"Rome daylight saving starts at the EU transition instant");
 check(follower::RomeOffset(at(2026,10,25,0,59,59))==7200&&follower::RomeOffset(at(2026,10,25,1,0))==3600,"Rome daylight saving ends at the EU transition instant");
 finish();std::cout<<checks<<" checks passed\n";return 0;
 }catch(const std::exception&e){std::cerr<<"FAILED "<<e.what()<<"\n";return 1;}}
