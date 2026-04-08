//+------------------------------------------------------------------+
//|                                          rattUTBotEngine.mqh     |
//|           Rattapignola EA v1.0.0 — UTBot Adaptive Engine         |
//|                                                                  |
//|  Implements the 3 contract functions from adEngineInterface.mqh: |
//|    EngineInit()      — Create handles, init state                |
//|    EngineDeinit()    — Release handles, cleanup                  |
//|    EngineCalculate() — Read bar[1], populate EngineSignal        |
//|                                                                  |
//|  UTBot Adaptive trailing stop engine:                            |
//|    - ATR-based trailing stop with 4-branch ratchet logic         |
//|    - Adaptive source: Close / HMA / KAMA / JMA                  |
//|    - Efficiency Ratio quality classification                     |
//|    - Anti-repaint: signals on bar[1] only                        |
//|    - TF auto-presets for optimal parameters                      |
//|                                                                  |
//|  Source: UTBotAdaptive.mq5 (QuantNomad v4 porting)               |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| UTBot Preset Struct                                              |
//+------------------------------------------------------------------+
struct UTBPreset
{
   double keyValue;
   int    atrPeriod;
   int    kamaN;
   int    kamaFast;
   int    kamaSlow;
   int    hmaPeriod;
   int    jmaPeriod;
   int    jmaPhase;
   int    pendingExpiry;
};

//+------------------------------------------------------------------+
//| UTBot Preset Table (from UTBotAdaptive.mq5 UTBotPresetsInit)     |
//|                                                                  |
//|  Index:  0=M1, 1=M5, 2=M15, 3=M30, 4=H1, 5=H4                  |
//|  Values extracted from UTBotAdaptive.mq5 lines 381-439           |
//+------------------------------------------------------------------+
const UTBPreset g_utb_presetTable[] =
{
//  key   ATR  kamaN  kF  kS   hma  jmaPer  jmaPh  expiry
   {0.7,   5,   5,   2,  20,  14,    5,      0,     3},    // M1  — ultra-scalping
   {1.0,   7,   8,   2,  20,  14,    8,      0,     5},    // M5  — scalping intraday
   {1.2,  10,  10,   2,  30,  14,   14,      0,     8},    // M15 — day trade (Kaufman default)
   {1.5,  10,  10,   2,  30,  14,   18,     50,     8},    // M30 — day trade / swing intraday
   {2.0,  14,  14,   2,  35,  14,   20,     50,    10},    // H1  — swing intraday
   {2.5,  14,  14,   2,  40,  14,   28,     75,    12}     // H4  — swing / position
};

//+------------------------------------------------------------------+
//| Engine Global Variables (prefixed g_utb_)                         |
//+------------------------------------------------------------------+

// Handle
int g_utb_atrHandle = INVALID_HANDLE;

// Effective parameters (after preset application)
double g_utb_keyValue  = 1.0;
int    g_utb_atrPeriod = 10;
int    g_utb_kamaN     = 10;
int    g_utb_kamaFast  = 2;
int    g_utb_kamaSlow  = 30;
int    g_utb_hmaPeriod = 14;
int    g_utb_jmaPeriod = 14;
int    g_utb_jmaPhase  = 0;

// State
double   g_utb_lastTrail   = 0;
double   g_utb_lastSrc     = 0;
datetime g_utb_lastBarTime = 0;

// JMA internal state (bar-by-bar persistent)
double g_utb_jma_e0   = 0;
double g_utb_jma_e1   = 0;
double g_utb_jma_e2   = 0;
double g_utb_jma_prev = 0;
bool   g_utb_jma_init = false;
double g_utb_jma_beta = 0;
double g_utb_jma_alpha = 0;

// JMA constants (pre-calculated in EngineInit)
double g_utb_jma_PR   = 0;
double g_utb_jma_len1 = 0;
double g_utb_jma_pow1 = 0;
double g_utb_jma_bet  = 0;

// JMA Jurik Bands + volatility state (persistent arrays for lookback)
double g_utb_jma_uBand[];
double g_utb_jma_lBand[];
double g_utb_jma_volty[];
double g_utb_jma_vSum[];
double g_utb_jma_e0_arr[];
double g_utb_jma_det0[];
double g_utb_jma_det1[];
double g_utb_jma_src_arr[];   // JMA output history
int    g_utb_jma_histLen = 0; // Current history length
int    g_utb_jma_histMax = 200; // Max history buffer

// KAMA state
double g_utb_kama_prev = 0;
bool   g_utb_kama_init = false;

//+------------------------------------------------------------------+
//| UTBApplyPreset — Map Period() to preset index                    |
//+------------------------------------------------------------------+
int UTBGetPresetIndex(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 0;
      case PERIOD_M5:  return 1;
      case PERIOD_M15: return 2;
      case PERIOD_M30: return 3;
      case PERIOD_H1:  return 4;
      case PERIOD_H4:  return 5;
      default:         return -1;  // No preset — use manual
   }
}

//+------------------------------------------------------------------+
//| UTBApplyPreset — Apply preset values to effective params         |
//+------------------------------------------------------------------+
void UTBApplyPreset(const UTBPreset &p)
{
   g_utb_keyValue  = p.keyValue;
   g_utb_atrPeriod = p.atrPeriod;
   g_utb_kamaN     = p.kamaN;
   g_utb_kamaFast  = p.kamaFast;
   g_utb_kamaSlow  = p.kamaSlow;
   g_utb_hmaPeriod = p.hmaPeriod;
   g_utb_jmaPeriod = p.jmaPeriod;
   g_utb_jmaPhase  = p.jmaPhase;
   g_pendingExpiry = p.pendingExpiry;
}

//+------------------------------------------------------------------+
//| UTBApplyManual — Use input values directly                       |
//+------------------------------------------------------------------+
void UTBApplyManual()
{
   g_utb_keyValue  = InpKeyValue;
   g_utb_atrPeriod = InpATRPeriod_UTB;
   g_utb_kamaN     = InpKAMA_N;
   g_utb_kamaFast  = InpKAMA_Fast;
   g_utb_kamaSlow  = InpKAMA_Slow;
   g_utb_hmaPeriod = InpHMAPeriod;
   g_utb_jmaPeriod = InpJMA_Period;
   g_utb_jmaPhase  = InpJMA_Phase;
   g_pendingExpiry = PendingExpiryBars;
}

//+------------------------------------------------------------------+
//| UTBInitJMAConstants — Pre-calculate JMA constants                |
//|                                                                  |
//| From UTBotAdaptive.mq5 lines 538-548:                            |
//|   halfLen = 0.5 * (period - 1)                                   |
//|   PR  = clamp(phase/100 + 1.5, 0.5, 2.5)                         |
//|   len1 = max(log2(sqrt(halfLen)) + 2, 0)                         |
//|   pow1 = max(len1 - 2, 0.5)                                      |
//|   len2 = sqrt(halfLen) * len1                                     |
//|   bet  = len2 / (len2 + 1)                                       |
//|   beta = 0.45*(period-1) / (0.45*(period-1) + 2)                 |
//+------------------------------------------------------------------+
void UTBInitJMAConstants()
{
   double halfLen = 0.5 * (g_utb_jmaPeriod - 1.0);

   // Phase ratio: clamp phase/100 + 1.5 to [0.5, 2.5]
   g_utb_jma_PR = (g_utb_jmaPhase < -100) ? 0.5 :
                  (g_utb_jmaPhase >  100) ? 2.5 :
                  g_utb_jmaPhase / 100.0 + 1.5;

   // Log-derived length parameter
   g_utb_jma_len1 = MathMax(MathLog(MathSqrt(halfLen)) / MathLog(2.0) + 2.0, 0.0);

   // Power exponent base
   g_utb_jma_pow1 = MathMax(g_utb_jma_len1 - 2.0, 0.5);

   // Band smoothing factor
   double len2 = MathSqrt(halfLen) * g_utb_jma_len1;
   g_utb_jma_bet = len2 / (len2 + 1.0);

   // IIR base factor
   g_utb_jma_beta = 0.45 * (g_utb_jmaPeriod - 1.0) / (0.45 * (g_utb_jmaPeriod - 1.0) + 2.0);
}

//+------------------------------------------------------------------+
//| UTBResetJMAState — Reset JMA persistent state                    |
//+------------------------------------------------------------------+
void UTBResetJMAState()
{
   g_utb_jma_e0   = 0;
   g_utb_jma_e1   = 0;
   g_utb_jma_e2   = 0;
   g_utb_jma_prev = 0;
   g_utb_jma_init = false;

   g_utb_jma_histLen = 0;
   ArrayResize(g_utb_jma_uBand, g_utb_jma_histMax);
   ArrayResize(g_utb_jma_lBand, g_utb_jma_histMax);
   ArrayResize(g_utb_jma_volty, g_utb_jma_histMax);
   ArrayResize(g_utb_jma_vSum,  g_utb_jma_histMax);
   ArrayResize(g_utb_jma_e0_arr, g_utb_jma_histMax);
   ArrayResize(g_utb_jma_det0,  g_utb_jma_histMax);
   ArrayResize(g_utb_jma_det1,  g_utb_jma_histMax);
   ArrayResize(g_utb_jma_src_arr, g_utb_jma_histMax);
   ArrayInitialize(g_utb_jma_uBand, 0);
   ArrayInitialize(g_utb_jma_lBand, 0);
   ArrayInitialize(g_utb_jma_volty, 0);
   ArrayInitialize(g_utb_jma_vSum,  0);
   ArrayInitialize(g_utb_jma_e0_arr, 0);
   ArrayInitialize(g_utb_jma_det0,  0);
   ArrayInitialize(g_utb_jma_det1,  0);
   ArrayInitialize(g_utb_jma_src_arr, 0);
}

//+------------------------------------------------------------------+
//| WMAOnArray — WMA at specific index on a price array              |
//| Building block for HMA. From UTBotAdaptive.mq5 lines 732-742    |
//|                                                                  |
//| price[]: array with index 0 = most recent (as-series)            |
//| idx: index into array (0 = newest)                               |
//| period: WMA lookback length                                      |
//+------------------------------------------------------------------+
double WMAOnArray(const double &price[], int idx, int period, int arraySize)
{
   double num = 0, den = 0;
   for(int k = 0; k < period && (idx + k) < arraySize; k++)
   {
      double w = (double)(period - k);
      num += w * price[idx + k];
      den += w;
   }
   return (den > 0.0) ? num / den : price[idx];
}

//+------------------------------------------------------------------+
//| UTBCalcHMA — Hull Moving Average on bar[1]                       |
//|                                                                  |
//| HMA = WMA(2*WMA(close, period/2) - WMA(close, period), sqrt(p)) |
//| From UTBotAdaptive.mq5 lines 748-766                             |
//|                                                                  |
//| close[]: as-series array (index 0 = current bar)                 |
//| Returns HMA value for bar[1]                                     |
//+------------------------------------------------------------------+
double UTBCalcHMA(const double &close[], int count)
{
   int period = g_utb_hmaPeriod;
   int half = MathMax(period / 2, 2);
   int sqn  = (int)MathRound(MathSqrt((double)period));

   // Need enough data: period + sqn bars from bar[1]
   int needed = 1 + period + sqn;
   if(count < needed) return close[1];

   // Build tmp[] array: tmp[i] = 2*WMA(half) - WMA(full)
   // We only need sqn values starting from bar[1]
   double tmp[];
   ArrayResize(tmp, sqn);

   for(int k = 0; k < sqn; k++)
   {
      int barIdx = 1 + k;  // bar[1], bar[2], ..., bar[sqn]
      double wmaHalf = WMAOnArray(close, barIdx, half, count);
      double wmaFull = WMAOnArray(close, barIdx, period, count);
      tmp[k] = 2.0 * wmaHalf - wmaFull;
   }

   // Final WMA on tmp[] with period = sqn
   double num = 0, den = 0;
   for(int k = 0; k < sqn; k++)
   {
      double w = (double)(sqn - k);
      num += w * tmp[k];
      den += w;
   }

   return (den > 0.0) ? num / den : close[1];
}

//+------------------------------------------------------------------+
//| UTBCalcKAMA — Kaufman Adaptive MA on bar[1]                      |
//|                                                                  |
//| ER = |P[i]-P[i-N]| / Sum|P[j]-P[j-1]|                          |
//| SC = (ER*(FastSC-SlowSC)+SlowSC)^2                              |
//| KAMA[i] = KAMA[i-1] + SC*(P[i]-KAMA[i-1])                       |
//| From UTBotAdaptive.mq5 lines 774-792                             |
//|                                                                  |
//| close[]: as-series array (0 = current bar)                       |
//| Returns KAMA value for bar[1]                                    |
//+------------------------------------------------------------------+
double UTBCalcKAMA(const double &close[], int count)
{
   int N = g_utb_kamaN;

   // Need at least N+1 bars from bar[1] (bar[1] through bar[1+N])
   if(count < N + 2) return close[1];

   // Initialize KAMA on first call
   if(!g_utb_kama_init)
   {
      g_utb_kama_prev = close[1];
      g_utb_kama_init = true;
   }

   double fc = 2.0 / (g_utb_kamaFast + 1.0);
   double sc = 2.0 / (g_utb_kamaSlow + 1.0);

   // ER on bar[1]: direction over N bars, noise = sum of abs changes
   // close[] is as-series: close[1] is latest closed, close[1+N] is N bars back
   double direction = MathAbs(close[1] - close[1 + N]);
   double noise = 0.0;
   for(int k = 0; k < N; k++)
      noise += MathAbs(close[1 + k] - close[1 + k + 1]);

   double er = (noise > 0.0) ? direction / noise : 0.0;
   double smooth = MathPow(er * (fc - sc) + sc, 2.0);

   // Update KAMA
   double kama = g_utb_kama_prev + smooth * (close[1] - g_utb_kama_prev);
   g_utb_kama_prev = kama;

   return kama;
}

//+------------------------------------------------------------------+
//| UTBCalcJMA — Jurik-style MA on bar[1] (full volatility model)    |
//|                                                                  |
//| Complete IIR 3-stage filter with Jurik Bands + dynamic volatility|
//| From UTBotAdaptive.mq5 lines 814-903                             |
//|                                                                  |
//| Architecture:                                                    |
//|   1. Jurik Bands (uBand/lBand) track price extremes              |
//|   2. volty = max excursion beyond bands                          |
//|   3. Running sum (10-bar window) + 65-bar average -> rVolty      |
//|   4. Dynamic alpha = beta^(rVolty^pow1)                          |
//|   5. IIR 3 stages: e0 -> det0 -> det1 -> JMA                    |
//|                                                                  |
//| close[]: as-series array (0 = current bar)                       |
//| Returns JMA value for bar[1]                                     |
//+------------------------------------------------------------------+
double UTBCalcJMA(const double &close[], int count)
{
   double p = close[1];  // Current price (bar[1])

   // Initialize on first call
   if(!g_utb_jma_init)
   {
      g_utb_jma_init = true;
      g_utb_jma_histLen = 1;

      g_utb_jma_src_arr[0] = p;
      g_utb_jma_e0_arr[0]  = p;
      g_utb_jma_det0[0]    = 0.0;
      g_utb_jma_det1[0]    = 0.0;
      g_utb_jma_uBand[0]   = p;
      g_utb_jma_lBand[0]   = p;
      g_utb_jma_volty[0]   = 0.0;
      g_utb_jma_vSum[0]    = 0.0;

      return p;
   }

   // Ensure history buffer is large enough
   int i = g_utb_jma_histLen;
   if(i >= g_utb_jma_histMax)
   {
      // Shift arrays: keep only last 100 entries
      int keep = 100;
      int shift = i - keep;

      for(int j = 0; j < keep; j++)
      {
         g_utb_jma_src_arr[j] = g_utb_jma_src_arr[j + shift];
         g_utb_jma_e0_arr[j]  = g_utb_jma_e0_arr[j + shift];
         g_utb_jma_det0[j]    = g_utb_jma_det0[j + shift];
         g_utb_jma_det1[j]    = g_utb_jma_det1[j + shift];
         g_utb_jma_uBand[j]   = g_utb_jma_uBand[j + shift];
         g_utb_jma_lBand[j]   = g_utb_jma_lBand[j + shift];
         g_utb_jma_volty[j]   = g_utb_jma_volty[j + shift];
         g_utb_jma_vSum[j]    = g_utb_jma_vSum[j + shift];
      }
      g_utb_jma_histLen = keep;
      i = keep;
   }

   int sumLen = 10;
   int avgLen = 65;

   //--- STEP 1: Jurik Bands + Instantaneous Volatility ---
   double del1 = p - g_utb_jma_uBand[i - 1];
   double del2 = p - g_utb_jma_lBand[i - 1];

   // volty = max excursion beyond bands (0 if equidistant)
   double absD1 = MathAbs(del1);
   double absD2 = MathAbs(del2);
   double volty = (absD1 != absD2) ? MathMax(absD1, absD2) : 0.0;
   g_utb_jma_volty[i] = volty;

   // Running sum sliding window (sumLen=10)
   int    oldIdx  = (i >= sumLen) ? (i - sumLen) : 0;
   double oldVolt = g_utb_jma_volty[oldIdx];
   g_utb_jma_vSum[i] = g_utb_jma_vSum[i - 1] + (volty - oldVolt) / (double)sumLen;

   // Average of vSum over avgLen=65 bars (SMA approximation)
   double avgVolty = 0.0;
   int    avgStart = (i >= avgLen) ? (i - avgLen + 1) : 0;
   int    avgCount = i - avgStart + 1;
   for(int j = avgStart; j <= i; j++)
      avgVolty += g_utb_jma_vSum[j];
   avgVolty = (avgCount > 0) ? avgVolty / (double)avgCount : 0.0;

   // Relative volatility (clamped)
   double dVolty = (avgVolty > 0.0) ? volty / avgVolty : 0.0;
   double maxRV  = MathPow(g_utb_jma_len1, 1.0 / g_utb_jma_pow1);
   double rVolty = MathMax(1.0, MathMin(maxRV, dVolty));

   // Dynamic power + band coefficient
   double pow2 = MathPow(rVolty, g_utb_jma_pow1);
   double Kv   = MathPow(g_utb_jma_bet, MathSqrt(pow2));

   // Update Jurik Bands
   g_utb_jma_uBand[i] = (del1 > 0) ? p : p - Kv * del1;
   g_utb_jma_lBand[i] = (del2 < 0) ? p : p - Kv * del2;

   //--- STEP 2: Dynamic alpha ---
   double alpha = MathPow(g_utb_jma_beta, pow2);
   double a2    = alpha * alpha;
   double b2    = (1.0 - alpha) * (1.0 - alpha);

   //--- STEP 3: IIR 3 stages ---
   // Stage 1: Adaptive EMA
   double e0 = (1.0 - alpha) * p + alpha * g_utb_jma_e0_arr[i - 1];
   g_utb_jma_e0_arr[i] = e0;

   // Stage 2: Kalman-like error correction
   double det0 = (p - e0) * (1.0 - g_utb_jma_beta) + g_utb_jma_beta * g_utb_jma_det0[i - 1];
   g_utb_jma_det0[i] = det0;
   double ma2 = e0 + g_utb_jma_PR * det0;

   // Stage 3: Final Jurik adaptive smoothing
   double det1 = (ma2 - g_utb_jma_src_arr[i - 1]) * b2 + a2 * g_utb_jma_det1[i - 1];
   g_utb_jma_det1[i] = det1;

   // Output JMA
   double jma = g_utb_jma_src_arr[i - 1] + det1;
   g_utb_jma_src_arr[i] = jma;

   g_utb_jma_histLen = i + 1;

   return jma;
}

//+------------------------------------------------------------------+
//| UTBCalcER — Efficiency Ratio for bar[1]                          |
//|                                                                  |
//| KAMA source: exact ER = |close[1]-close[1+N]| / sum|diffs|      |
//| Other sources: proxy ER = min(1.0, |src-src_prev| / atr)        |
//+------------------------------------------------------------------+
double UTBCalcER(const double &close[], int count, double src, double src_prev, double atr)
{
   if(InpSrcType == UTB_SRC_KAMA && count >= g_utb_kamaN + 2)
   {
      double d = MathAbs(close[1] - close[1 + g_utb_kamaN]);
      double n = 0.0;
      for(int k = 0; k < g_utb_kamaN; k++)
         n += MathAbs(close[1 + k] - close[1 + k + 1]);
      return (n > 0.0) ? d / n : 0.0;
   }
   else if(atr > 0.0)
   {
      return MathMin(1.0, MathAbs(src - src_prev) / atr);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| EngineInit — Contract function 1/3                               |
//|                                                                  |
//|  1. Apply TF preset or manual params                             |
//|  2. Create ATR handle                                            |
//|  3. Pre-calculate JMA constants (if JMA source)                  |
//|  4. Create SqueezeMomentum handle (if enabled)                   |
//|  5. Set pending expiry from preset                               |
//|  6. Reset state                                                  |
//+------------------------------------------------------------------+
bool EngineInit()
{
   //--- 1. Apply preset ---
   if(InpUTBPreset == UTB_TF_AUTO)
   {
      int idx = UTBGetPresetIndex((ENUM_TIMEFRAMES)Period());
      if(idx >= 0 && idx < ArraySize(g_utb_presetTable))
      {
         UTBApplyPreset(g_utb_presetTable[idx]);
         AdLogI(LOG_CAT_UTB, StringFormat("Auto-preset applied: TF=%s idx=%d Key=%.1f ATR=%d",
                EnumToString((ENUM_TIMEFRAMES)Period()), idx,
                g_utb_keyValue, g_utb_atrPeriod));
      }
      else
      {
         // Fallback to manual for unsupported TFs (D1, W1, etc.)
         UTBApplyManual();
         AdLogW(LOG_CAT_UTB, StringFormat("No preset for TF=%s — using manual params",
                EnumToString((ENUM_TIMEFRAMES)Period())));
      }
   }
   else  // UTB_TF_MANUAL
   {
      UTBApplyManual();
      AdLogI(LOG_CAT_UTB, "Manual mode — using input parameters directly");
   }

   //--- 2. Create ATR handle ---
   g_utb_atrHandle = iATR(_Symbol, PERIOD_CURRENT, g_utb_atrPeriod);
   if(g_utb_atrHandle == INVALID_HANDLE)
   {
      AdLogE(LOG_CAT_UTB, StringFormat("CRITICAL: Failed to create ATR handle (period=%d)", g_utb_atrPeriod));
      return false;
   }

   //--- 3. Pre-calculate JMA constants ---
   if(InpSrcType == UTB_SRC_JMA)
   {
      UTBInitJMAConstants();
      UTBResetJMAState();
      AdLogI(LOG_CAT_UTB, StringFormat("JMA constants: PR=%.3f len1=%.3f pow1=%.3f bet=%.4f beta=%.4f",
             g_utb_jma_PR, g_utb_jma_len1, g_utb_jma_pow1, g_utb_jma_bet, g_utb_jma_beta));
   }

   //--- 4. Create SqueezeMomentum handle (if enabled) ---
   if(InpUseSqzExit)
   {
      g_sqzHandle = iCustom(_Symbol, PERIOD_CURRENT, "SqueezeMomentum_LB",
                            InpSqzBBLength, InpSqzBBMult,
                            InpSqzKCLength, InpSqzKCMult,
                            InpSqzUseTR, InpSqzHalfPeakRatio,
                            false, false);
      if(g_sqzHandle == INVALID_HANDLE)
         AdLogW(LOG_CAT_UTB, "SqueezeMomentum handle creation failed — SQZ exit disabled");
      else
         AdLogI(LOG_CAT_UTB, "SqueezeMomentum handle created for exit mode");
   }

   //--- 5. Pending expiry already set by UTBApplyPreset/UTBApplyManual ---

   //--- 6. Reset state ---
   g_utb_lastTrail   = 0;
   g_utb_lastSrc     = 0;
   g_utb_lastBarTime = 0;
   g_utb_kama_prev   = 0;
   g_utb_kama_init   = false;
   g_lastSignal.Reset();

   //--- Log configuration ---
   string srcStr;
   switch(InpSrcType)
   {
      case UTB_SRC_CLOSE: srcStr = "Close";  break;
      case UTB_SRC_HMA:   srcStr = StringFormat("HMA(%d)", g_utb_hmaPeriod); break;
      case UTB_SRC_KAMA:  srcStr = StringFormat("KAMA(%d,%d,%d)", g_utb_kamaN, g_utb_kamaFast, g_utb_kamaSlow); break;
      case UTB_SRC_JMA:   srcStr = StringFormat("JMA(%d,%d)", g_utb_jmaPeriod, g_utb_jmaPhase); break;
      default:             srcStr = "?"; break;
   }

   AdLogI(LOG_CAT_UTB, StringFormat("UTBot Engine: Key=%.1f ATR=%d Src=%s",
          g_utb_keyValue, g_utb_atrPeriod, srcStr));
   AdLogI(LOG_CAT_UTB, StringFormat("ER Thresholds: Strong=%.2f Weak=%.2f ShowWeak=%s",
          InpERStrong, InpERWeak, InpShowWeakSig ? "YES" : "NO"));
   AdLogI(LOG_CAT_UTB, StringFormat("TP Mode=%s Value=%.1f Entry=%s PendExpiry=%d",
          EnumToString(TPMode), TPValue, EnumToString(EntryMode), g_pendingExpiry));

   Log_InitComplete("UTBot Engine");
   return true;
}

//+------------------------------------------------------------------+
//| EngineDeinit — Contract function 2/3                             |
//+------------------------------------------------------------------+
void EngineDeinit()
{
   //--- Release ATR handle ---
   if(g_utb_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_utb_atrHandle);
      g_utb_atrHandle = INVALID_HANDLE;
   }

   //--- Release SQZ handle ---
   if(g_sqzHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_sqzHandle);
      g_sqzHandle = INVALID_HANDLE;
   }

   //--- Reset state ---
   g_utb_lastTrail   = 0;
   g_utb_lastSrc     = 0;
   g_utb_lastBarTime = 0;
   g_utb_kama_prev   = 0;
   g_utb_kama_init   = false;

   if(InpSrcType == UTB_SRC_JMA)
      UTBResetJMAState();

   AdLogI(LOG_CAT_UTB, "UTBot Engine deinitialized");
}

//+------------------------------------------------------------------+
//| EngineCalculate — Contract function 3/3                          |
//|                                                                  |
//|  Pipeline (every new bar, bar[1] confirmed):                     |
//|    1. Get ATR from iATR handle                                   |
//|    2. Calculate adaptive source on bar[1]                        |
//|    3. Trailing stop (4 branches, Pine-faithful)                  |
//|    4. Signal detection (crossover)                               |
//|    5. Efficiency Ratio + quality classification                  |
//|    6. Anti-repaint guard                                         |
//|    7. Update state                                               |
//|    8. Populate EngineSignal                                      |
//|                                                                  |
//|  Returns: true if signal populated (direction != 0)              |
//+------------------------------------------------------------------+
bool EngineCalculate(EngineSignal &sig)
{
   sig.Reset();

   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars < g_utb_atrPeriod + 10) return false;

   // ================================================================
   // STEP 1: Get ATR from iATR handle (bar[1])
   // ================================================================
   double atrBuf[1];
   if(CopyBuffer(g_utb_atrHandle, 0, 1, 1, atrBuf) < 1)
   {
      AdLogD(LOG_CAT_UTB, "ATR data not ready");
      return false;
   }
   double atr   = atrBuf[0];
   double nLoss = g_utb_keyValue * atr;

   // ================================================================
   // STEP 2: Calculate Adaptive Source on bar[1]
   // ================================================================
   // Determine how many close values we need
   int closeLookback = 2;  // Minimum: bar[1] and bar[2]
   switch(InpSrcType)
   {
      case UTB_SRC_CLOSE: closeLookback = 3; break;
      case UTB_SRC_HMA:   closeLookback = g_utb_hmaPeriod * 2 + 10; break;
      case UTB_SRC_KAMA:  closeLookback = g_utb_kamaN + 5; break;
      case UTB_SRC_JMA:   closeLookback = 3; break;  // JMA is recursive, needs only current
   }

   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   int copied = CopyClose(_Symbol, PERIOD_CURRENT, 0, closeLookback, closeArr);
   if(copied < closeLookback)
   {
      AdLogD(LOG_CAT_UTB, StringFormat("Close data not ready: copied=%d needed=%d", copied, closeLookback));
      return false;
   }

   double src = 0;
   switch(InpSrcType)
   {
      case UTB_SRC_CLOSE:
         src = closeArr[1];
         break;

      case UTB_SRC_HMA:
         src = UTBCalcHMA(closeArr, copied);
         break;

      case UTB_SRC_KAMA:
         src = UTBCalcKAMA(closeArr, copied);
         break;

      case UTB_SRC_JMA:
         src = UTBCalcJMA(closeArr, copied);
         break;

      default:
         src = closeArr[1];
         break;
   }

   // ================================================================
   // STEP 3: Trailing Stop (4 branches, Pine-faithful)
   // From UTBotAdaptive.mq5 lines 1383-1392
   // ================================================================
   double trail;
   double src_prev   = g_utb_lastSrc;
   double trail_prev = g_utb_lastTrail;

   if(trail_prev == 0)
   {
      // Initial: no previous trail, seed with src - nLoss
      trail = src - nLoss;
   }
   else if(src > trail_prev && src_prev > trail_prev)
   {
      // Both current and previous above trail: ratchet up (uptrend)
      trail = MathMax(trail_prev, src - nLoss);
   }
   else if(src < trail_prev && src_prev < trail_prev)
   {
      // Both below trail: ratchet down (downtrend)
      trail = MathMin(trail_prev, src + nLoss);
   }
   else if(src > trail_prev)
   {
      // Crossover up: flip to uptrend
      trail = src - nLoss;
   }
   else
   {
      // Crossover down: flip to downtrend
      trail = src + nLoss;
   }

   // ================================================================
   // STEP 4: Signal Detection (crossover)
   // From UTBotAdaptive.mq5 lines 1422-1423
   // ================================================================
   bool isBuy  = (src_prev < trail_prev || src_prev == 0) && (src > trail) && trail_prev != 0;
   bool isSell = (src_prev > trail_prev || src_prev == 0) && (src < trail) && trail_prev != 0;

   // ================================================================
   // STEP 5: Efficiency Ratio + quality classification
   // ================================================================
   double er = UTBCalcER(closeArr, copied, src, src_prev, atr);

   // Quality classification
   int quality = PATTERN_NONE;
   if(er >= InpERStrong)
      quality = PATTERN_TBS;   // Strong signal
   else
      quality = PATTERN_TWS;   // Weak signal

   // Skip weak signals if ER below minimum and weak signals not shown
   if((isBuy || isSell) && er < InpERWeak && !InpShowWeakSig)
   {
      AdLogD(LOG_CAT_UTB, StringFormat("Signal skipped: ER=%.3f < ERWeak=%.3f (ShowWeak=false)", er, InpERWeak));
      isBuy  = false;
      isSell = false;
   }

   // ================================================================
   // STEP 6: Anti-repaint guard
   // Only emit signal once per bar
   // ================================================================
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   bool isNewBar = (barTime != g_utb_lastBarTime);

   if(!isNewBar)
   {
      // Same bar already processed — suppress signal but still update bands
      isBuy  = false;
      isSell = false;
   }

   // ================================================================
   // STEP 7: Update state
   // ================================================================
   g_utb_lastTrail   = trail;
   g_utb_lastSrc     = src;
   g_utb_lastBarTime = barTime;

   // ================================================================
   // STEP 8: Populate EngineSignal
   // ================================================================

   // --- Always populate (even without signal, for dashboard) ---
   sig.upperBand       = src + nLoss;
   sig.lowerBand       = src - nLoss;
   sig.midline         = src;
   sig.bandLevel       = trail;
   sig.channelWidthPip = PointsToPips(2.0 * nLoss);
   sig.isFlat          = (er < InpERWeak);
   sig.barTime         = barTime;

   // --- Extra values for dashboard ---
   sig.extraValues[0] = PointsToPips(atr);    sig.extraLabels[0] = "ATR";
   sig.extraValues[1] = er;                    sig.extraLabels[1] = "ER";
   sig.extraValues[2] = trail;                 sig.extraLabels[2] = "Trail";
   sig.extraValues[3] = g_utb_keyValue;        sig.extraLabels[3] = "Key";
   sig.extraValues[4] = src;                   sig.extraLabels[4] = "Source";
   sig.extraCount     = 5;

   // --- Filter states for dashboard ---
   sig.filterNames[0]  = "ER";
   sig.filterStates[0] = (er >= InpERStrong) ? 1 : (er >= InpERWeak ? 0 : -1);
   sig.filterNames[1]  = "Repaint";
   sig.filterStates[1] = 1;  // Always pass (we use bar[1])
   sig.filterCount     = 2;

   // --- No signal case ---
   if(!isBuy && !isSell)
   {
      return true;  // Data populated but no signal (direction=0)
   }

   // ================================================================
   // Signal detected — populate entry/TP
   // ================================================================
   sig.direction   = isBuy ? +1 : -1;
   sig.quality     = quality;
   sig.isNewSignal = true;
   sig.entryPrice  = iClose(_Symbol, PERIOD_CURRENT, 1);
   sig.slPrice     = 0;  // No SL

   // TP based on mode
   switch(TPMode)
   {
      case TP_SIGNAL_TO_SIGNAL:
      case TP_SQUEEZE_EXIT:
         sig.tpPrice = 0;  // No broker TP — managed by framework
         break;

      case TP_ATR_MULTIPLE:
         sig.tpPrice = sig.entryPrice + sig.direction * TPValue * atr;
         break;

      case TP_FIXED_PIPS:
         sig.tpPrice = sig.entryPrice + sig.direction * PipsToPrice(TPValue);
         break;
   }

   // Log signal
   string patternName = (quality == PATTERN_TBS) ? "TBS" : "TWS";
   AdLogI(LOG_CAT_UTB, StringFormat("=== NEW %s %s SIGNAL === Entry=%s TP=%s Trail=%s ER=%.3f Key=%.1f",
          sig.direction > 0 ? "BUY" : "SELL", patternName,
          FormatPrice(sig.entryPrice),
          sig.tpPrice > 0 ? FormatPrice(sig.tpPrice) : "S2S",
          FormatPrice(trail), er, g_utb_keyValue));

   return true;
}
