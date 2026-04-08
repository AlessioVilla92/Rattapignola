//+------------------------------------------------------------------+
//|                                          adHTFFilter.mqh         |
//|           AcquaDulza EA v1.6.1 — HTF Direction Filter            |
//|                                                                  |
//|  Donchian-based higher timeframe filter.                         |
//|  Blocks signals against HTF trend direction.                     |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| HTF Filter State                                                 |
//+------------------------------------------------------------------+
int g_htfDirection = 0;  // +1=bullish, -1=bearish, 0=neutral

//+------------------------------------------------------------------+
//| HTFGetDirection — Get HTF Donchian direction                    |
//|  Uses iHighest/iLowest on HTF timeframe                          |
//|  Returns: +1 (above midline=bullish), -1 (below=bearish), 0     |
//+------------------------------------------------------------------+
int HTFGetDirection()
{
   if(!UseHTFFilter) return 0;

   int totalBars = iBars(_Symbol, HTFTimeframe);
   if(totalBars < HTFPeriod + 2) return 0;

   // Compute HTF Donchian bands on bar[1]
   int highIdx = iHighest(_Symbol, HTFTimeframe, MODE_HIGH, HTFPeriod, 1);
   int lowIdx  = iLowest(_Symbol, HTFTimeframe, MODE_LOW, HTFPeriod, 1);

   if(highIdx < 0 || lowIdx < 0) return 0;

   double htfUpper = iHigh(_Symbol, HTFTimeframe, highIdx);
   double htfLower = iLow(_Symbol, HTFTimeframe, lowIdx);
   double htfMid   = (htfUpper + htfLower) / 2.0;

   double htfClose = iClose(_Symbol, HTFTimeframe, 1);

   if(htfClose > htfMid) return +1;  // Bullish
   if(htfClose < htfMid) return -1;  // Bearish
   return 0;
}

//+------------------------------------------------------------------+
//| HTFCheckSignal — Check if signal is compatible with HTF         |
//|  direction: +1=BUY, -1=SELL                                     |
//|  Returns: true if allowed                                        |
//+------------------------------------------------------------------+
bool HTFCheckSignal(int direction)
{
   if(!UseHTFFilter) return true;

   g_htfDirection = HTFGetDirection();

   // BUY allowed only if HTF bullish or neutral
   if(direction > 0 && g_htfDirection < 0)
   {
      AdLogI(LOG_CAT_FILTER, "HTF BLOCKED BUY — HTF bearish");
      return false;
   }

   // SELL allowed only if HTF bearish or neutral
   if(direction < 0 && g_htfDirection > 0)
   {
      AdLogI(LOG_CAT_FILTER, "HTF BLOCKED SELL — HTF bullish");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| HTFGetStatusString — For dashboard display                      |
//+------------------------------------------------------------------+
string HTFGetStatusString()
{
   if(!UseHTFFilter) return "OFF";
   g_htfDirection = HTFGetDirection();
   if(g_htfDirection > 0)  return "BULL";
   if(g_htfDirection < 0)  return "BEAR";
   return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| InitializeHTFFilter                                              |
//+------------------------------------------------------------------+
void InitializeHTFFilter()
{
   if(!UseHTFFilter)
   {
      Log_InitConfig("HTF Filter", "DISABLED");
      return;
   }

   g_htfDirection = HTFGetDirection();
   Log_InitConfig("HTF.Timeframe", EnumToString(HTFTimeframe));
   Log_InitConfig("HTF.Period", IntegerToString(HTFPeriod));
   Log_InitConfig("HTF.Direction", HTFGetStatusString());
   Log_InitComplete("HTF Filter");
}
