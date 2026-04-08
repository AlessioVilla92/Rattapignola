//+------------------------------------------------------------------+
//|                                           adDPCBands.mqh         |
//|           AcquaDulza EA v1.6.1 — DPC Band Calculation            |
//|                                                                  |
//|  Calcolo Donchian bands + EMA ATR. Math puro.                    |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| DPC Engine internal handles                                      |
//+------------------------------------------------------------------+
int    g_dpcMAHandle      = INVALID_HANDLE;
int    g_dpcHMAHalfHandle = INVALID_HANDLE;
int    g_dpcHMAFullHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| DPC Engine internal state                                        |
//+------------------------------------------------------------------+
double g_dpcEmaATR = 0;

//+------------------------------------------------------------------+
//| ComputeDonchianBands — Upper/Lower/Mid via iHighest/iLowest      |
//+------------------------------------------------------------------+
void DPCComputeBands(int barShift, int lookback, double &upper, double &lower, double &mid)
{
   int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, barShift);
   int lowestBar  = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, barShift);

   if(highestBar < 0 || lowestBar < 0)
   {
      AdLogW(LOG_CAT_DPC, StringFormat("ComputeBands failed: iHighest=%d iLowest=%d (bar=%d lookback=%d)",
         highestBar, lowestBar, barShift, lookback));
      upper = 0;
      lower = 0;
      mid   = 0;
      return;
   }

   upper = iHigh(_Symbol, PERIOD_CURRENT, highestBar);
   lower = iLow(_Symbol, PERIOD_CURRENT, lowestBar);
   mid   = (upper + lower) * 0.5;
}

//+------------------------------------------------------------------+
//| DPCGetATR — Read ATR from internal handle                        |
//+------------------------------------------------------------------+
double DPCGetATR(int barShift)
{
   if(g_atrHandle == INVALID_HANDLE)
   {
      AdLogW(LOG_CAT_DPC, "DPCGetATR: ATR handle invalid");
      return 0;
   }

   double atrBuf[];
   ArrayResize(atrBuf, 1);
   ArraySetAsSeries(atrBuf, true);

   if(CopyBuffer(g_atrHandle, 0, barShift, 1, atrBuf) < 1)
   {
      AdLogW(LOG_CAT_DPC, StringFormat("DPCGetATR: CopyBuffer failed (bar=%d)", barShift));
      return 0;
   }
   return atrBuf[0];
}

//+------------------------------------------------------------------+
//| DPCUpdateEmaATR — Exponential moving average of ATR(14)          |
//| EMA(200) for smooth volatility reference                         |
//+------------------------------------------------------------------+
void DPCUpdateEmaATR(double atr)
{
   if(atr <= 0) return;

   double alpha = 2.0 / (200.0 + 1.0);
   if(g_dpcEmaATR > 0)
      g_dpcEmaATR = alpha * atr + (1.0 - alpha) * g_dpcEmaATR;
   else
      g_dpcEmaATR = atr;
}

//+------------------------------------------------------------------+
//| ManualWMA — Weighted Moving Average (for HMA calculation)        |
//+------------------------------------------------------------------+
double DPCManualWMA(const double &src[], int startIdx, int period)
{
   if(period < 1) return 0;

   double weightSum = 0;
   double valueSum  = 0;
   int available = ArraySize(src);

   for(int k = 0; k < period && (startIdx + k) < available; k++)
   {
      double weight = (double)(period - k);
      valueSum  += src[startIdx + k] * weight;
      weightSum += weight;
   }

   return (weightSum > 0) ? valueSum / weightSum : 0;
}

//+------------------------------------------------------------------+
//| DPCGetMAValue — MA filter value (SMA/EMA/WMA/HMA)               |
//+------------------------------------------------------------------+
double DPCGetMAValue(int barShift)
{
   if(InpMAType == DPC_MA_HMA)
   {
      int sqrtLen = (int)MathFloor(MathSqrt((double)g_dpc_maLen));
      if(sqrtLen < 1) sqrtLen = 1;
      int neededBars = sqrtLen + 2;

      static double halfBuf[], fullBuf[], interBuf[];
      static int s_lastNeeded = 0;
      if(neededBars != s_lastNeeded)
      {
         ArrayResize(halfBuf, neededBars);
         ArrayResize(fullBuf, neededBars);
         ArrayResize(interBuf, neededBars);
         s_lastNeeded = neededBars;
      }
      ArraySetAsSeries(halfBuf, true);
      ArraySetAsSeries(fullBuf, true);

      int copiedHalf = CopyBuffer(g_dpcHMAHalfHandle, 0, barShift, neededBars, halfBuf);
      int copiedFull = CopyBuffer(g_dpcHMAFullHandle, 0, barShift, neededBars, fullBuf);

      if(copiedHalf < neededBars || copiedFull < neededBars)
      {
         AdLogW(LOG_CAT_DPC, StringFormat("DPCGetMAValue HMA: CopyBuffer insufficient (half=%d full=%d need=%d)",
            copiedHalf, copiedFull, neededBars));
         return 0;
      }
      for(int k = 0; k < neededBars; k++)
         interBuf[k] = 2.0 * halfBuf[k] - fullBuf[k];

      return DPCManualWMA(interBuf, 0, sqrtLen);
   }
   else
   {
      if(g_dpcMAHandle == INVALID_HANDLE)
      {
         AdLogW(LOG_CAT_DPC, "DPCGetMAValue: MA handle invalid");
         return 0;
      }

      double maBuf[];
      ArrayResize(maBuf, 1);
      ArraySetAsSeries(maBuf, true);

      if(CopyBuffer(g_dpcMAHandle, 0, barShift, 1, maBuf) < 1)
      {
         AdLogW(LOG_CAT_DPC, StringFormat("DPCGetMAValue: CopyBuffer failed (bar=%d)", barShift));
         return 0;
      }
      return maBuf[0];
   }
}

//+------------------------------------------------------------------+
//| DPCGetMidlineColor — Midline trend direction                     |
//| 0=bullish (lime), 1=bearish (red), 2=flat (cyan)                 |
//+------------------------------------------------------------------+
int DPCGetMidlineColor(int barShift)
{
   double u1, l1, m1;
   double u3, l3, m3;
   DPCComputeBands(barShift, g_dpc_dcLen, u1, l1, m1);
   DPCComputeBands(barShift + 2, g_dpc_dcLen, u3, l3, m3);

   double threshold = g_pipSize * 2;
   if(m1 - m3 > threshold) return 0;  // bullish
   if(m3 - m1 > threshold) return 1;  // bearish
   return 2;                           // flat
}

//+------------------------------------------------------------------+
//| DPCCreateHandles — Create indicator handles                      |
//+------------------------------------------------------------------+
bool DPCCreateHandles()
{
   // ATR: uses framework g_atrHandle (created by InitializeATR in adATRCalculator.mqh)
   // No duplicate handle needed — DPCGetATR() reads from g_atrHandle directly.

   // MA handle(s)
   if(InpMAType == DPC_MA_HMA)
   {
      int halfLen = (int)MathFloor(g_dpc_maLen / 2.0);
      if(halfLen < 1) halfLen = 1;
      g_dpcHMAHalfHandle = iMA(_Symbol, PERIOD_CURRENT, halfLen, 0, MODE_LWMA, PRICE_CLOSE);
      g_dpcHMAFullHandle = iMA(_Symbol, PERIOD_CURRENT, g_dpc_maLen, 0, MODE_LWMA, PRICE_CLOSE);

      if(g_dpcHMAHalfHandle == INVALID_HANDLE || g_dpcHMAFullHandle == INVALID_HANDLE)
      {
         AdLogE(LOG_CAT_ENGINE, "Failed to create HMA handles!");
         return false;
      }
   }
   else
   {
      ENUM_MA_METHOD maMethod = MODE_SMA;
      if(InpMAType == DPC_MA_EMA) maMethod = MODE_EMA;
      else if(InpMAType == DPC_MA_WMA) maMethod = MODE_LWMA;

      g_dpcMAHandle = iMA(_Symbol, PERIOD_CURRENT, g_dpc_maLen, 0, maMethod, PRICE_CLOSE);
      if(g_dpcMAHandle == INVALID_HANDLE)
      {
         AdLogE(LOG_CAT_ENGINE, StringFormat("Failed to create iMA handle (type=%s, period=%d)!",
            EnumToString(InpMAType), g_dpc_maLen));
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| DPCReleaseHandles — Release all indicator handles                |
//+------------------------------------------------------------------+
void DPCReleaseHandles()
{
   if(g_dpcMAHandle != INVALID_HANDLE)      { IndicatorRelease(g_dpcMAHandle);      g_dpcMAHandle = INVALID_HANDLE; }
   if(g_dpcHMAHalfHandle != INVALID_HANDLE) { IndicatorRelease(g_dpcHMAHalfHandle); g_dpcHMAHalfHandle = INVALID_HANDLE; }
   if(g_dpcHMAFullHandle != INVALID_HANDLE) { IndicatorRelease(g_dpcHMAFullHandle); g_dpcHMAFullHandle = INVALID_HANDLE; }
   AdLogI(LOG_CAT_ENGINE, "DPC indicator handles released");
}
