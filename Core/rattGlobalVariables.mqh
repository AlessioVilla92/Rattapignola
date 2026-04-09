//+------------------------------------------------------------------+
//|                                      rattGlobalVariables.mqh     |
//|           Rattapignola EA v1.6.1 — Global Variables              |
//|                                                                  |
//|  Stato macchina + array cicli + tracking + trade object          |
//|  NO variabili engine-specifiche (vivono in Engine/)              |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| TRADE OBJECT                                                     |
//+------------------------------------------------------------------+
CTrade g_trade;

//+------------------------------------------------------------------+
//| SYSTEM STATE                                                     |
//+------------------------------------------------------------------+
ENUM_SYSTEM_STATE g_systemState = STATE_INIT;
datetime g_systemStartTime = 0;

//+------------------------------------------------------------------+
//| BROKER SPECIFICATIONS                                            |
//+------------------------------------------------------------------+
int    g_symbolStopsLevel  = 0;
int    g_symbolFreezeLevel = 0;
double g_symbolMinLot      = 0;
double g_symbolMaxLot      = 0;
double g_symbolLotStep     = 0;
long   g_symbolSpreadPoints = 0;
double g_symbolPoint       = 0;
int    g_symbolDigits      = 0;

//+------------------------------------------------------------------+
//| INSTRUMENT CLASSIFICATION                                        |
//| Settati da InstrumentPresetsInit() in rattInstrumentConfig.mqh   |
//+------------------------------------------------------------------+
ENUM_INSTRUMENT_CLASS g_instrumentClass = INSTRUMENT_AUTO;
double g_pipSize           = 0.0001;  // Pip size in price (forex default)

//--- Effective parameters (auto-scaled per prodotto, override degli input) ---
double g_inst_maxSpread    = 3.0;     // MaxSpreadPips effettivo
int    g_inst_slippage     = 3;       // Slippage effettivo (in points)
double g_inst_stopOffset   = 2.5;     // StopOffsetPips effettivo
double g_inst_limitOffset  = 2.0;     // LimitOffsetPips effettivo
double g_inst_widthFactor  = 1.0;     // Fattore moltiplicativo per minWidth

//+------------------------------------------------------------------+
//| ATR CACHE                                                        |
//+------------------------------------------------------------------+
int    g_atrHandle = INVALID_HANDLE;
double g_atrPips   = 0;               // ATR in pips

struct ATRCacheData
{
   double   valuePips;
   datetime lastFullUpdate;
   datetime lastBarTime;
   bool     isValid;

   void Reset()
   {
      valuePips      = 0;
      lastFullUpdate = 0;
      lastBarTime    = 0;
      isValid        = false;
   }
};
ATRCacheData g_atrCache;

//+------------------------------------------------------------------+
//| ENGINE STATE — Framework side                                    |
//| (l'engine mantiene i propri handle internamente)                 |
//+------------------------------------------------------------------+
bool g_engineReady = false;
bool g_initialDrawDone = false;   // OnTimer retry: resettata in OnInit per ogni TF change

//+------------------------------------------------------------------+
//| PENDING EXPIRY — Framework variable set by engine                 |
//+------------------------------------------------------------------+
int g_pendingExpiry = 3;  // Barre prima che un pending scada (settato da engine in EngineInit)

//+------------------------------------------------------------------+
//| SQUEEZE MOMENTUM HANDLE                                           |
//+------------------------------------------------------------------+
int g_sqzHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| LAST ENGINE SIGNAL — Copia dell'ultimo segnale per il framework  |
//+------------------------------------------------------------------+
EngineSignal g_lastSignal;

//+------------------------------------------------------------------+
//| SIGNAL TRACKING                                                  |
//+------------------------------------------------------------------+
int      g_totalSignals     = 0;
int      g_buySignals       = 0;
int      g_sellSignals      = 0;
datetime g_lastSignalTime   = 0;

//+------------------------------------------------------------------+
//| CYCLE MANAGEMENT                                                 |
//+------------------------------------------------------------------+
CycleRecord g_cycles[];
int g_nextCycleID = 1;

//+------------------------------------------------------------------+
//| EQUITY TRACKING                                                  |
//+------------------------------------------------------------------+
double g_maxEquity          = 0;
double g_maxDrawdownPct     = 0;
double g_startingEquity     = 0;
double g_startingBalance    = 0;

//+------------------------------------------------------------------+
//| DAILY TRACKING                                                   |
//+------------------------------------------------------------------+
double   g_dailyRealizedProfit = 0;
int      g_dailyWins           = 0;
int      g_dailyLosses         = 0;
int      g_dailyCyclesCount    = 0;
datetime g_dailyCyclesDate     = 0;

//+------------------------------------------------------------------+
//| SESSION TRACKING                                                 |
//+------------------------------------------------------------------+
double   g_sessionRealizedProfit = 0;
int      g_sessionWins           = 0;
int      g_sessionLosses         = 0;

//+------------------------------------------------------------------+
//| FILTER COUNTERS                                                  |
//+------------------------------------------------------------------+
int g_totalExpiredOrders = 0;

//+------------------------------------------------------------------+
//| SIGNAL FEED (ultimi N eventi per dashboard side panel)           |
//+------------------------------------------------------------------+
#define MAX_FEED_ITEMS  5
string   g_feedLines[MAX_FEED_ITEMS];
color    g_feedColors[MAX_FEED_ITEMS];
int      g_feedCount = 0;

void AddFeedItem(string text, color clr)
{
   for(int i = MAX_FEED_ITEMS - 1; i > 0; i--)
   {
      g_feedLines[i]  = g_feedLines[i-1];
      g_feedColors[i] = g_feedColors[i-1];
   }
   g_feedLines[0]  = text;
   g_feedColors[0] = clr;
   if(g_feedCount < MAX_FEED_ITEMS) g_feedCount++;
}

//+------------------------------------------------------------------+
//| SIGNAL HISTORY (ultimi 3 segnali per dashboard Last Signals)    |
//+------------------------------------------------------------------+
struct SignalHistItem
{
   int      dir;       // +1/-1
   double   entry;
   double   tp;
   int      quality;   // PATTERN_TBS/PATTERN_TWS
   datetime time;
   string   status;    // "OPEN", "TP", "SL", "PEND"
};
SignalHistItem g_signalHist[3];
int g_signalHistCount = 0;

void AddSignalHistory(int dir, double entry, double tp, int quality, string status)
{
   for(int i = 2; i > 0; i--)
      g_signalHist[i] = g_signalHist[i-1];
   g_signalHist[0].dir     = dir;
   g_signalHist[0].entry   = entry;
   g_signalHist[0].tp      = tp;
   g_signalHist[0].quality = quality;
   g_signalHist[0].time    = TimeCurrent();
   g_signalHist[0].status  = status;
   if(g_signalHistCount < 3) g_signalHistCount++;
}

//+------------------------------------------------------------------+
//| CheckDailyReset — Reset daily counters on new day               |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   if(g_dailyCyclesDate > 0)
   {
      TimeToStruct(g_dailyCyclesDate, last);
      if(now.day != last.day || now.mon != last.mon)
      {
         AdLogI(LOG_CAT_SYSTEM, StringFormat(
            "DAILY RESET | Prev: W=%d L=%d PL=%.2f Cycles=%d | Date: %04d.%02d.%02d -> %04d.%02d.%02d",
            g_dailyWins, g_dailyLosses, g_dailyRealizedProfit, g_dailyCyclesCount,
            last.year, last.mon, last.day, now.year, now.mon, now.day));
         g_dailyCyclesCount    = 0;
         g_dailyRealizedProfit = 0;
         g_dailyWins           = 0;
         g_dailyLosses         = 0;
      }
   }
   g_dailyCyclesDate = TimeCurrent();
}
