//+------------------------------------------------------------------+
//|                                              adHelpers.mqh       |
//|           AcquaDulza EA v1.6.1 — Helper Functions                |
//|                                                                  |
//|  Utility: price conversion, logging, formatting, account info    |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| PRICE CONVERSION — Universale multi-prodotto                     |
//|                                                                  |
//| Usa g_pipSize (settato da InstrumentPresetsInit) per definire     |
//| cosa è "1 pip" per ogni classe di strumento:                      |
//|   Forex 5d: g_pipSize=0.0001  | Crypto: g_pipSize=1.0            |
//|   Gold:     g_pipSize=0.10    | Indici: g_pipSize=1.0             |
//|                                                                  |
//| Tutte le funzioni pip dell'EA passano da qui — choke point unico.|
//+------------------------------------------------------------------+

//--- Converte una distanza prezzo in pip
double PointsToPips(double points)
{
   if(g_pipSize <= 0) return 0;
   return points / g_pipSize;
}

//--- Converte pip in delta prezzo (per SL/TP/offset)
double PipsToPrice(double pips)
{
   return pips * g_pipSize;
}

//+------------------------------------------------------------------+
//| IsNewBar — Detects new bar on current timeframe                  |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetSpreadPips — Current spread in pips                           |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return 1.0;
   return PointsToPips(ask - bid);
}

//+------------------------------------------------------------------+
//| FORMAT FUNCTIONS                                                 |
//+------------------------------------------------------------------+

string FormatPrice(double price)
{
   return DoubleToString(price, g_symbolDigits);
}

string FormatMoney(double amount)
{
   if(amount >= 0)
      return "$" + DoubleToString(amount, 2);
   else
      return "-$" + DoubleToString(MathAbs(amount), 2);
}

string FormatPercent(double percent)
{
   return DoubleToString(percent, 2) + "%";
}

//+------------------------------------------------------------------+
//| LOGGING SYSTEM — Simplified (3 levels: INFO/WARN/ERROR)          |
//+------------------------------------------------------------------+

// Log Categories
#define LOG_CAT_INIT      "[INIT]"
#define LOG_CAT_ORDER     "[ORDER]"
#define LOG_CAT_POSITION  "[POSITION]"
#define LOG_CAT_SESSION   "[SESSION]"
#define LOG_CAT_SYSTEM    "[SYSTEM]"
#define LOG_CAT_RECOVERY  "[RECOVERY]"
#define LOG_CAT_ENGINE    "[ENGINE]"
#define LOG_CAT_HEDGE     "[HEDGE]"
#define LOG_CAT_DPC       "[DPC]"
#define LOG_CAT_PERSIST   "[PERSIST]"
#define LOG_CAT_UI        "[UI]"
#define LOG_CAT_FILTER    "[FILTER]"
#define LOG_CAT_ATR       "[ATR]"
#define LOG_CAT_BROKER    "[BROKER]"
#define LOG_CAT_RISK      "[RISK]"
#define LOG_CAT_CYCLE     "[CYCLE]"
#define LOG_CAT_VIRTUAL   "[VIRTUAL]"
#define LOG_CAT_TRIGGER   "[TRIGGER]"
#define LOG_CAT_HTF       "[HTF]"

string LogLevelToString(ENUM_LOG_LEVEL level)
{
   switch(level)
   {
      case LOG_DEBUG:   return "DEBUG";
      case LOG_INFO:    return "INFO ";
      case LOG_WARNING: return "WARN ";
      case LOG_ERROR:   return "ERROR";
   }
   return "?????";
}

//+------------------------------------------------------------------+
//| AdLog — Central logging function                                 |
//+------------------------------------------------------------------+
void AdLog(ENUM_LOG_LEVEL level, string category, string message)
{
   if(level < MinLogLevel) return;

   PrintFormat("%s [%s] %s %s",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
      LogLevelToString(level), category, message);

   if(LogToCSVFile)
      LogToCSV(level, category, message);
}

void AdLogD(string cat, string msg) { AdLog(LOG_DEBUG,   cat, msg); }
void AdLogI(string cat, string msg) { AdLog(LOG_INFO,    cat, msg); }
void AdLogW(string cat, string msg) { AdLog(LOG_WARNING, cat, msg); }
void AdLogE(string cat, string msg) { AdLog(LOG_ERROR,   cat, msg); }

//+------------------------------------------------------------------+
//| LogToCSV — Write log entry to CSV file                           |
//+------------------------------------------------------------------+
void LogToCSV(ENUM_LOG_LEVEL level, string category, string message)
{
   string filename = "AcquaDulza_" + _Symbol + "_" +
                     TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   int handle = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_WRITE, ',');
   if(handle == INVALID_HANDLE) return;

   if(FileSize(handle) == 0)
      FileWrite(handle, "Time", "Level", "Category", "Message", "Bid");

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
      LogLevelToString(level), category, message,
      DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits));
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| STRUCTURED LOG WRAPPERS                                          |
//+------------------------------------------------------------------+

void Log_OrderCancelled(ulong ticket, string reason)
{
   AdLog(LOG_INFO, LOG_CAT_ORDER,
      StringFormat("CANCELLED ticket=%d reason=%s", ticket, reason));
}

void Log_PositionClosed(ulong ticket, string reason, double profit, double closePrice)
{
   AdLog(LOG_INFO, LOG_CAT_POSITION,
      StringFormat("CLOSED ticket=%d reason=%s profit=%.2f price=%s",
         ticket, reason, profit, DoubleToString(closePrice, _Digits)));
}

void Log_SystemError(string component, int code, string message)
{
   AdLog(LOG_ERROR, LOG_CAT_SYSTEM,
      StringFormat("component=%s code=%d message=%s", component, code, message));
}

void Log_InitConfig(string key, string value)
{
   AdLog(LOG_INFO, LOG_CAT_INIT, StringFormat("CONFIG %s=%s", key, value));
}

void Log_InitComplete(string component)
{
   AdLog(LOG_INFO, LOG_CAT_INIT, StringFormat("COMPLETE component=%s", component));
}

//+------------------------------------------------------------------+
//| REPORT FORMATTING                                                |
//+------------------------------------------------------------------+

void Log_Separator()
{
   AdLog(LOG_INFO, LOG_CAT_SYSTEM,
      "------------------------------------------------------------------------");
}

void Log_Header(string title)
{
   AdLog(LOG_INFO, LOG_CAT_SYSTEM,
      "========================================================================");
   AdLog(LOG_INFO, LOG_CAT_SYSTEM, StringFormat("  %s", title));
   AdLog(LOG_INFO, LOG_CAT_SYSTEM,
      "========================================================================");
}

void Log_SubHeader(string title)
{
   AdLog(LOG_INFO, LOG_CAT_SYSTEM,
      "------------------------------------------------------------------------");
   AdLog(LOG_INFO, LOG_CAT_SYSTEM, StringFormat("  %s", title));
   AdLog(LOG_INFO, LOG_CAT_SYSTEM,
      "------------------------------------------------------------------------");
}

void Log_KeyValue(string key, string value)
{
   AdLog(LOG_INFO, LOG_CAT_SYSTEM,
      StringFormat("  %-30s %s", key + ":", value));
}

void Log_KeyValueNum(string key, double value, int decimals = 2)
{
   AdLog(LOG_INFO, LOG_CAT_SYSTEM,
      StringFormat("  %-30s %.*f", key + ":", decimals, value));
}

//+------------------------------------------------------------------+
//| ACCOUNT FUNCTIONS                                                |
//+------------------------------------------------------------------+

double GetEquity()       { return AccountInfoDouble(ACCOUNT_EQUITY); }
double GetBalance()      { return AccountInfoDouble(ACCOUNT_BALANCE); }
double GetFreeMargin()   { return AccountInfoDouble(ACCOUNT_MARGIN_FREE); }

double GetMarginLevel()
{
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin <= 0) return 0;
   return (AccountInfoDouble(ACCOUNT_EQUITY) / margin) * 100.0;
}

//+------------------------------------------------------------------+
//| CHART OBJECT HELPERS                                             |
//+------------------------------------------------------------------+

void CreateHLine(string name, double price, color clr, int width = 1, ENUM_LINE_STYLE style = STYLE_SOLID)
{
   if(ObjectFind(0, name) >= 0)
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      return;
   }
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| CountActiveCycles — Count non-idle cycles                        |
//| (forward declaration — implemented in adCycleManager.mqh)        |
//+------------------------------------------------------------------+
int CountActiveCycles();
