//+------------------------------------------------------------------+
//|                                        adATRCalculator.mqh       |
//|           AcquaDulza EA v1.6.1 — ATR Calculator Module           |
//|                                                                  |
//|  ATR indicator for volatility monitoring                         |
//|  Unified cache system for dashboard + engine                     |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| GetATRPips — Get ATR in pips (from framework handle)            |
//|  Uses g_atrHandle, InpATR_Period, g_symbolPoint, g_symbolDigits  |
//|  Fallback: 10.0 pips if ATR not available                        |
//+------------------------------------------------------------------+
double GetATRPips()
{
   if(g_atrHandle == INVALID_HANDLE)
   {
      AdLogW(LOG_CAT_ATR, "GetATRPips: handle invalid — fallback 10.0");
      return 10.0;
   }

   int calculated = BarsCalculated(g_atrHandle);
   if(calculated < InpATR_Period + 1)
   {
      AdLogW(LOG_CAT_ATR, StringFormat("GetATRPips: insufficient bars (%d < %d) — fallback 10.0",
         calculated, InpATR_Period + 1));
      return 10.0;
   }

   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);

   if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) <= 0)
   {
      AdLogW(LOG_CAT_ATR, "GetATRPips: CopyBuffer failed — fallback 10.0");
      return 10.0;
   }

   return PointsToPips(atrBuffer[0]);
}

//+------------------------------------------------------------------+
//| CreateATRHandle — Create iATR indicator handle                  |
//+------------------------------------------------------------------+
bool CreateATRHandle()
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   g_atrHandle = iATR(_Symbol, InpATR_Timeframe, InpATR_Period);

   if(g_atrHandle == INVALID_HANDLE)
   {
      AdLogE(LOG_CAT_ATR, StringFormat("Failed to create ATR handle: error=%d", GetLastError()));
      return false;
   }

   AdLogI(LOG_CAT_ATR, StringFormat("ATR handle created: Period=%d TF=%s",
          InpATR_Period, EnumToString(InpATR_Timeframe)));
   return true;
}

//+------------------------------------------------------------------+
//| ReleaseATRHandle — Release ATR indicator handle                 |
//+------------------------------------------------------------------+
void ReleaseATRHandle()
{
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
      AdLogI(LOG_CAT_ATR, "ATR handle released");
   }
}

//+------------------------------------------------------------------+
//| WaitForATRData — Wait for ATR data availability                 |
//|  Tester: blocks with Sleep. Live: returns immediately.           |
//+------------------------------------------------------------------+
bool WaitForATRData(int maxWaitMs = 5000)
{
   if(g_atrHandle == INVALID_HANDLE) return false;

   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);

   int calculated = BarsCalculated(g_atrHandle);
   if(calculated >= InpATR_Period + 1)
   {
      if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) > 0 && atrBuffer[0] > 0)
         return true;
   }

   if(!MQLInfoInteger(MQL_TESTER)) return false;

   // Strategy Tester: wait with Sleep
   int waitCount = 0;
   int waitInterval = 100;
   while(waitCount * waitInterval < maxWaitMs)
   {
      calculated = BarsCalculated(g_atrHandle);
      if(calculated >= InpATR_Period + 1)
      {
         if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) > 0 && atrBuffer[0] > 0)
            return true;
      }
      Sleep(waitInterval);
      waitCount++;
   }
   return false;
}

//+------------------------------------------------------------------+
//| InitializeATR — Create handle + wait for data                   |
//+------------------------------------------------------------------+
bool InitializeATR()
{
   if(!CreateATRHandle()) return false;

   if(!WaitForATRData())
      AdLogW(LOG_CAT_ATR, "ATR data not immediately available — will be ready on next tick");

   // Update cache
   g_atrCache.valuePips = GetATRPips();
   g_atrCache.lastFullUpdate = TimeCurrent();
   g_atrCache.lastBarTime = iTime(_Symbol, InpATR_Timeframe, 0);
   g_atrCache.isValid = (g_atrCache.valuePips > 0);
   g_atrPips = g_atrCache.valuePips;

   AdLogI(LOG_CAT_ATR, StringFormat("g_atrPips synced: %.2f pips | valid=%s",
          g_atrPips, g_atrCache.isValid ? "YES" : "NO"));

   Log_InitComplete("ATR Calculator");
   return true;
}

//+------------------------------------------------------------------+
//| UpdateATR — Refresh ATR cache (call on new bar)                 |
//+------------------------------------------------------------------+
void UpdateATR()
{
   double newATR = GetATRPips();
   if(newATR > 0)
   {
      g_atrCache.valuePips     = newATR;
      g_atrPips                = newATR;
      g_atrCache.lastFullUpdate = TimeCurrent();
      g_atrCache.lastBarTime   = iTime(_Symbol, InpATR_Timeframe, 0);
      g_atrCache.isValid       = true;
   }
}


