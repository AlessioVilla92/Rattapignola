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
   ENUM_UTB_SRC_TYPE autoSrcType;   // [v2.13] sorgente auto se InpAutoSrcByTF=true
};

//+------------------------------------------------------------------+
//| UTBot Preset Table (from UTBotAdaptive.mq5 UTBotPresetsInit)     |
//|                                                                  |
//|  Index:  0=M1, 1=M5, 2=M15, 3=M30, 4=H1, 5=H4                  |
//|  autoSrcType allineato a UTBotAdaptive-DA IMPLEMENTARE v2.13     |
//+------------------------------------------------------------------+
const UTBPreset g_utb_presetTable[] =
{
//  key   ATR  kamaN  kF  kS   hma  jmaPer  jmaPh  expiry  autoSrc
   {0.7,   5,   5,   2,  20,  14,    5,      0,     3,    UTB_SRC_JMA},   // M1  — ultra-scalping
   {1.0,   7,   8,   2,  20,  14,    8,      0,     5,    UTB_SRC_KAMA},  // M5  — scalping intraday
   {1.2,  10,  10,   2,  30,  14,   14,      0,     8,    UTB_SRC_KAMA},  // M15 — day trade (Kaufman)
   {1.5,  10,  10,   2,  30,  14,   18,     50,     8,    UTB_SRC_JMA},   // M30 — day trade / swing
   {2.0,  14,  14,   2,  35,  14,   20,     50,    10,    UTB_SRC_JMA},   // H1  — swing intraday
   {2.5,  14,  14,   2,  40,  14,   28,     75,    12,    UTB_SRC_JMA}    // H4  — swing / position
};

//+------------------------------------------------------------------+
//| Engine Global Variables (prefixed g_utb_)                         |
//+------------------------------------------------------------------+

// ATR Wilder calcolato manualmente (vedi UTBCalcATRWilder/UTBWarmupATRWilder)
// — non usiamo iATR() handle: il calcolo manuale e' identico a UTBotAdaptive
//   indicatore (RMA seed + Wilder smoothing) e fedele al trail Pine.

// Effective parameters (after preset application)
double g_utb_keyValue  = 1.0;
int    g_utb_atrPeriod = 10;
int    g_utb_kamaN     = 10;
int    g_utb_kamaFast  = 2;
int    g_utb_kamaSlow  = 30;
int    g_utb_hmaPeriod = 14;
int    g_utb_jmaPeriod = 14;
int    g_utb_jmaPhase  = 0;
ENUM_UTB_SRC_TYPE g_utb_srcEffective = UTB_SRC_JMA;  // [v2.13] sorgente effettiva (auto-TF override)

// State
double   g_utb_lastTrail   = 0;
double   g_utb_lastSrc     = 0;
datetime g_utb_lastBarTime = 0;
double   g_utb_state       = 0.0;   // [v2.13] +1=LONG, -1=SHORT, 0=NEUTRO (carry-forward)
double   g_utb_entryLevel  = 0.0;   // [v2.13] livello entry carry-forward (close trigger)

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

// ATR Wilder (manual, matches UTBotAdaptive.mq5 line 1283 exactly)
double g_utb_atrWilder = 0.0;
bool   g_utb_atrInit   = false;

//+------------------------------------------------------------------+
//| UTBGetPresetIndex — Map Period() to preset index                 |
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
//| UTBResolvePresetEnum — Resolve InpUTBPreset to preset table idx  |
//|                                                                  |
//| AUTO   → UTBGetPresetIndex(Period())                              |
//| M1..H4 → 0..5                                                     |
//| MANUAL → -1                                                       |
//+------------------------------------------------------------------+
int UTBResolvePresetEnum(ENUM_UTB_TF_PRESET preset)
{
   switch(preset)
   {
      case UTB_TF_AUTO:   return UTBGetPresetIndex((ENUM_TIMEFRAMES)Period());
      case UTB_TF_M1:     return 0;
      case UTB_TF_M5:     return 1;
      case UTB_TF_M15:    return 2;
      case UTB_TF_M30:    return 3;
      case UTB_TF_H1:     return 4;
      case UTB_TF_H4:     return 5;
      case UTB_TF_MANUAL: return -1;
      default:            return -1;
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
   g_utb_srcEffective = InpAutoSrcByTF ? p.autoSrcType : InpSrcType;
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
   g_utb_srcEffective = InpSrcType;
}

//+------------------------------------------------------------------+
//| UTBApplyKamaPreset — Override KAMA params from KamaPreset enum   |
//|                                                                  |
//| Allineato a UTBotAdaptive-DA IMPLEMENTARE v2.13 righe 663-714.   |
//| AUTO     → presetIdx M1/M5: STANDARD (10,2,30); M15+: MIDDLE     |
//| STANDARD → (10, 2, 30)  Kaufman classico reattivo                |
//| MIDDLE   → (14, 4, 50)  anti-microstorno (raccomandato M15)      |
//| SLOW     → (20, 6, 80)  swing filter H1/H4                       |
//| MANUAL   → no-op (mantiene valori da UTBApplyPreset/Manual)      |
//|                                                                  |
//| presetIdx: indice tabella TF (0=M1..5=H4, -1=manual TF).         |
//+------------------------------------------------------------------+
void UTBApplyKamaPreset(int presetIdx)
{
   ENUM_KAMA_PRESET sel = InpKamaPreset;

   if(sel == KAMA_PRESET_AUTO)
   {
      // M1/M5 → STANDARD; M15+ → MIDDLE
      if(presetIdx >= 0 && presetIdx <= 1) sel = KAMA_PRESET_STANDARD;
      else                                  sel = KAMA_PRESET_MIDDLE;
   }

   switch(sel)
   {
      case KAMA_PRESET_STANDARD:
         g_utb_kamaN    = 10;
         g_utb_kamaFast = 2;
         g_utb_kamaSlow = 30;
         break;
      case KAMA_PRESET_MIDDLE:
         g_utb_kamaN    = 14;
         g_utb_kamaFast = 4;
         g_utb_kamaSlow = 50;
         break;
      case KAMA_PRESET_SLOW:
         g_utb_kamaN    = 20;
         g_utb_kamaFast = 6;
         g_utb_kamaSlow = 80;
         break;
      case KAMA_PRESET_MANUAL:
      default:
         // No-op
         break;
   }
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
   // Guard difensivo: previene out-of-bounds se idx e' al limite del buffer
   // (regressioni future con buffer sotto-dimensionati). In condizioni
   // normali l'engine alloca sempre buffer abbastanza grandi.
   if(idx < 0 || idx >= arraySize) return 0.0;
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

   // sumLen = 10: finestra sliding per la volatilita' istantanea (Jurik standard).
   //   Misura l'escursione del prezzo oltre le bande su 10 barre recenti.
   //   Piu' corta = reattiva, piu' lunga = smooth. 10 e' il default Jurik.
   // avgLen = 65: finestra per normalizzare la volatilita' cumulata (vSum).
   //   Converte vSum in relative volatility [0..1] confrontando con la media
   //   su 65 barre. Valore standard Jurik per stabilita' dell'alpha dinamico.
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
//| [v2.13] Modalita' uniforme (InpERKaufmanUniform=true):           |
//|   ER Kaufman autentico su close[] finestra g_utb_kamaN per       |
//|   TUTTE le sorgenti — scala 0..1 coerente cross-source.          |
//|                                                                  |
//| Modalita' legacy (InpERKaufmanUniform=false):                    |
//|   KAMA source  → ER Kaufman autentico                            |
//|   Other source → proxy min(1, |src-src_prev|/atr)                |
//|                                                                  |
//| Allineato a UTBotAdaptive-DA IMPLEMENTARE v2.13 righe 1657-1683. |
//+------------------------------------------------------------------+
double UTBCalcER(const double &close[], int count, double src, double src_prev, double atr)
{
   bool useKaufman = InpERKaufmanUniform || (g_utb_srcEffective == UTB_SRC_KAMA);

   if(useKaufman && count >= g_utb_kamaN + 2)
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
//| UTBCalcATRWilder — ATR Wilder manuale per bar[1]                 |
//|                                                                  |
//| Formula identica a UTBotAdaptive.mq5 riga 1280-1283:             |
//|   ATR[i] = (ATR[i-1] * (period-1) + TR) / period                |
//| Mantiene stato in g_utb_atrWilder (persistente tra tick).        |
//+------------------------------------------------------------------+
double UTBCalcATRWilder()
{
   int period = g_utb_atrPeriod;

   if(!g_utb_atrInit)
   {
      double highBuf[], lowBuf[], closeBuf[];
      ArraySetAsSeries(highBuf, true);
      ArraySetAsSeries(lowBuf, true);
      ArraySetAsSeries(closeBuf, true);

      int needed = period + 2;
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, needed, highBuf) < needed) return 0;
      if(CopyLow(_Symbol, PERIOD_CURRENT, 1, needed, lowBuf) < needed) return 0;
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, needed, closeBuf) < needed) return 0;

      double sum = 0;
      for(int k = 0; k < period; k++)
      {
         int idx = period - k;
         double trueHigh = MathMax(highBuf[idx], closeBuf[idx + 1]);
         double trueLow  = MathMin(lowBuf[idx], closeBuf[idx + 1]);
         sum += (trueHigh - trueLow);
      }
      g_utb_atrWilder = sum / period;
      g_utb_atrInit = true;
   }

   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double tr = MathMax(h1, c2) - MathMin(l1, c2);

   g_utb_atrWilder = (g_utb_atrWilder * (period - 1) + tr) / period;
   return g_utb_atrWilder;
}

//+------------------------------------------------------------------+
//| UTBWarmupATRWilder — Scalda ATR Wilder su N barre storiche       |
//|                                                                  |
//| 1. SMA dei primi `period` True Range come seed                   |
//| 2. Wilder's smoothing per tutte le barre successive              |
//+------------------------------------------------------------------+
void UTBWarmupATRWilder(int bars = 500)
{
   int period = g_utb_atrPeriod;
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(bars > totalBars - period - 2) bars = totalBars - period - 2;
   if(bars < period + 1) return;

   double highBuf[], lowBuf[], closeBuf[];
   ArraySetAsSeries(highBuf, false);
   ArraySetAsSeries(lowBuf, false);
   ArraySetAsSeries(closeBuf, false);

   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, bars, highBuf) < bars) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, bars, lowBuf) < bars) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, bars, closeBuf) < bars) return;

   double sum = 0;
   for(int k = 1; k <= period; k++)
   {
      double tr_k = MathMax(highBuf[k], closeBuf[k - 1]) - MathMin(lowBuf[k], closeBuf[k - 1]);
      sum += tr_k;
   }
   g_utb_atrWilder = sum / period;

   for(int i = period + 1; i < bars; i++)
   {
      double tr_i = MathMax(highBuf[i], closeBuf[i - 1]) - MathMin(lowBuf[i], closeBuf[i - 1]);
      g_utb_atrWilder = (g_utb_atrWilder * (period - 1) + tr_i) / period;
   }

   g_utb_atrInit = true;
   AdLogI(LOG_CAT_UTB, StringFormat("ATR Wilder warmup: %d bars | ATR=%.5f (%.2f pip)",
          bars, g_utb_atrWilder, PointsToPips(g_utb_atrWilder)));
}

//+------------------------------------------------------------------+
//| UTBWarmupEngine — Scalda JMA + ATR Wilder + Trail su storia      |
//|                                                                  |
//| Processa `bars` barre storiche in ordine cronologico, calcolando |
//| sorgente adattiva e trailing stop per allineare lo stato engine   |
//| con quello che l'indicatore avrebbe calcolato sulla stessa storia.|
//| Al termine, g_utb_lastTrail e g_utb_lastSrc contengono i valori  |
//| corretti — niente piu' "trail=0 guess bullish".                  |
//+------------------------------------------------------------------+
void UTBWarmupEngine(int bars = 500)
{
   if(bars < 50) bars = 50;
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars < bars + 5) bars = totalBars - 5;
   if(bars < 50) return;

   double closes[];
   ArraySetAsSeries(closes, false);
   int copied = CopyClose(_Symbol, PERIOD_CURRENT, 1, bars, closes);
   if(copied < 50) return;
   bars = copied;

   // tmp[] e' un buffer fisso passato a UTBCalcJMA che legge solo tmp[1].
   // ArraySetAsSeries non e' applicabile (e non serve) su array statici.
   double tmp[3];
   tmp[0] = 0; tmp[2] = 0;

   double trail = 0, src = 0, src_prev = 0;
   double state = 0.0;
   double entry = 0.0;

   for(int i = 0; i < bars; i++)
   {
      double close_i = closes[i];
      tmp[1] = close_i;

      double curSrc = close_i;
      switch(g_utb_srcEffective)
      {
         case UTB_SRC_CLOSE:
            curSrc = close_i;
            break;
         case UTB_SRC_JMA:
            curSrc = UTBCalcJMA(tmp, 3);
            break;
         case UTB_SRC_KAMA:
         {
            if(!g_utb_kama_init)
            {
               g_utb_kama_prev = close_i;
               g_utb_kama_init = true;
               curSrc = close_i;
            }
            else
            {
               double fc = 2.0 / (g_utb_kamaFast + 1.0);
               double sc = 2.0 / (g_utb_kamaSlow + 1.0);
               double er_k = (g_utb_atrWilder > 0)
                  ? MathMin(1.0, MathAbs(close_i - g_utb_kama_prev) / g_utb_atrWilder)
                  : 0.0;
               double smooth = MathPow(er_k * (fc - sc) + sc, 2.0);
               curSrc = g_utb_kama_prev + smooth * (close_i - g_utb_kama_prev);
               g_utb_kama_prev = curSrc;
            }
            break;
         }
         case UTB_SRC_HMA:
            curSrc = close_i;
            break;
      }

      src_prev = src;
      src = curSrc;

      double nLoss = g_utb_keyValue * g_utb_atrWilder;
      if(nLoss <= 0) continue;

      if(trail == 0)
      {
         trail = src - nLoss;
         continue;
      }

      double trail_prev = trail;
      if(src > trail_prev && src_prev > trail_prev)
         trail = MathMax(trail_prev, src - nLoss);
      else if(src < trail_prev && src_prev < trail_prev)
         trail = MathMin(trail_prev, src + nLoss);
      else if(src > trail_prev)
         trail = src - nLoss;
      else
         trail = src + nLoss;

      // [v2.13] Track state + entryLevel during warmup
      bool wIsBuy  = (src_prev < trail_prev) && (src > trail);
      bool wIsSell = (src_prev > trail_prev) && (src < trail);
      if(wIsBuy)       { state = +1.0; entry = close_i; }
      else if(wIsSell) { state = -1.0; entry = close_i; }
   }

   g_utb_lastTrail   = trail;
   g_utb_lastSrc     = src;
   g_utb_state       = state;
   g_utb_entryLevel  = entry;

   AdLogI(LOG_CAT_UTB, StringFormat("WarmupEngine: %d bars | Trail=%.5f | Src=%.5f | State=%s | Entry=%.5f",
          bars, trail, src,
          (state > 0 ? "LONG" : (state < 0 ? "SHORT" : "NEUTRO")),
          entry));
}

//+------------------------------------------------------------------+
//| EngineInit — Contract function 1/3                               |
//|                                                                  |
//|  1. Apply TF preset or manual params                             |
//|  2. Create ATR handle (kept for legacy/future use)               |
//|  3. Pre-calculate JMA constants (if JMA source)                  |
//|  4. Warmup ATR Wilder + Engine (trail + source)                  |
//|  5. Create SqueezeMomentum handle (if enabled)                   |
//|  6. Reset barTime only (trail/src set by warmup)                 |
//+------------------------------------------------------------------+
bool EngineInit()
{
   //--- 1. Apply preset ---
   int presetIdx = UTBResolvePresetEnum(InpUTBPreset);
   if(presetIdx >= 0 && presetIdx < ArraySize(g_utb_presetTable))
   {
      UTBApplyPreset(g_utb_presetTable[presetIdx]);
      AdLogI(LOG_CAT_UTB, StringFormat("Preset applied: %s idx=%d Key=%.1f ATR=%d",
             EnumToString(InpUTBPreset), presetIdx,
             g_utb_keyValue, g_utb_atrPeriod));
   }
   else if(InpUTBPreset == UTB_TF_MANUAL)
   {
      UTBApplyManual();
      AdLogI(LOG_CAT_UTB, "Manual mode — using input parameters directly");
   }
   else
   {
      // AUTO con TF non supportato (D1, W1, etc.)
      UTBApplyManual();
      AdLogW(LOG_CAT_UTB, StringFormat("No preset for TF=%s — using manual params",
             EnumToString((ENUM_TIMEFRAMES)Period())));
   }

   //--- 1b. Apply KAMA preset (override after TF preset) ---
   UTBApplyKamaPreset(presetIdx);

   //--- 2. ATR Wilder: nessun handle iATR (calcolo manuale fedele all'indicatore) ---

   //--- 3. Pre-calculate JMA constants (use effective source) ---
   if(g_utb_srcEffective == UTB_SRC_JMA)
   {
      UTBInitJMAConstants();
      UTBResetJMAState();
      AdLogI(LOG_CAT_UTB, StringFormat("JMA constants: PR=%.3f len1=%.3f pow1=%.3f bet=%.4f beta=%.4f",
             g_utb_jma_PR, g_utb_jma_len1, g_utb_jma_pow1, g_utb_jma_bet, g_utb_jma_beta));
   }

   //--- 3b. Warmup ATR Wilder (identico all'indicatore riga 1283) ---
   UTBWarmupATRWilder(500);

   //--- 3c. Warmup engine completo: sorgente + trail + state ---
   // Scalda 500 barre storiche calcolando JMA/KAMA/HMA + ATR + trail
   // contemporaneamente. Al termine g_utb_lastTrail/lastSrc/state/entryLevel
   // contengono i valori storici corretti — niente piu' "trail=0 guess bullish".
   UTBWarmupEngine(500);

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
   // NON azzerare g_utb_lastTrail/g_utb_lastSrc — il warmup li ha settati
   // ai valori storici corretti. Azzerandoli qui si causerebbe il BUG 2
   // (trail=0 → engine indovina il lato bull → divergenza dall'indicatore).
   // NON azzerare g_utb_kama_prev/init — il warmup engine li ha scaldati.
   g_utb_lastBarTime = 0;
   g_lastSignal.Reset();

   //--- Log configuration ---
   string srcStr;
   switch(g_utb_srcEffective)
   {
      case UTB_SRC_CLOSE: srcStr = "Close";  break;
      case UTB_SRC_HMA:   srcStr = StringFormat("HMA(%d)", g_utb_hmaPeriod); break;
      case UTB_SRC_KAMA:  srcStr = StringFormat("KAMA(%d,%d,%d)", g_utb_kamaN, g_utb_kamaFast, g_utb_kamaSlow); break;
      case UTB_SRC_JMA:   srcStr = StringFormat("JMA(%d,%d)", g_utb_jmaPeriod, g_utb_jmaPhase); break;
      default:             srcStr = "?"; break;
   }

   AdLogI(LOG_CAT_UTB, StringFormat("UTBot v2.13 | TFPreset=%s | KAMAPreset=%s | Src=%s | Key=%.1f | ATR=%d | AutoSrcByTF=%s | ERUniform=%s",
          EnumToString(InpUTBPreset), EnumToString(InpKamaPreset), srcStr,
          g_utb_keyValue, g_utb_atrPeriod,
          InpAutoSrcByTF ? "YES" : "NO",
          InpERKaufmanUniform ? "YES" : "NO"));
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
   //--- ATR Wilder: nessun handle da rilasciare (calcolo manuale) ---

   //--- Release SQZ handle ---
   if(g_sqzHandle != INVALID_HANDLE)
   {
      if(!IndicatorRelease(g_sqzHandle))
         AdLogW(LOG_CAT_UTB, StringFormat("SQZ IndicatorRelease failed (err=%d)", GetLastError()));
      g_sqzHandle = INVALID_HANDLE;
   }

   //--- Reset state ---
   g_utb_lastTrail   = 0;
   g_utb_lastSrc     = 0;
   g_utb_lastBarTime = 0;
   g_utb_state       = 0.0;
   g_utb_entryLevel  = 0.0;
   g_utb_kama_prev   = 0;
   g_utb_kama_init   = false;
   g_utb_atrWilder   = 0;
   g_utb_atrInit     = false;

   if(g_utb_srcEffective == UTB_SRC_JMA)
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
   // STEP 1: ATR Wilder per bar[1] (identico a UTBotAdaptive.mq5 riga 1283)
   // ================================================================
   double atr = UTBCalcATRWilder();
   if(atr <= 0)
   {
      AdLogD(LOG_CAT_UTB, "ATR Wilder not ready");
      return false;
   }
   double nLoss = g_utb_keyValue * atr;

   // ================================================================
   // STEP 2: Calculate Adaptive Source on bar[1]
   // [v2.13] usa g_utb_srcEffective (auto-TF override)
   // ================================================================
   // Determine how many close values we need
   int closeLookback = 2;  // Minimum: bar[1] and bar[2]
   switch(g_utb_srcEffective)
   {
      case UTB_SRC_CLOSE: closeLookback = 3; break;
      case UTB_SRC_HMA:   closeLookback = g_utb_hmaPeriod * 2 + 10; break;
      case UTB_SRC_KAMA:  closeLookback = g_utb_kamaN + 5; break;
      case UTB_SRC_JMA:   closeLookback = 3; break;  // JMA is recursive, needs only current
   }
   // [v2.13] ER Kaufman uniforme richiede almeno kamaN+2 close per qualunque sorgente
   if(InpERKaufmanUniform)
      closeLookback = MathMax(closeLookback, g_utb_kamaN + 2);

   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   int copied = CopyClose(_Symbol, PERIOD_CURRENT, 0, closeLookback, closeArr);
   if(copied < closeLookback)
   {
      AdLogD(LOG_CAT_UTB, StringFormat("Close data not ready: copied=%d needed=%d", copied, closeLookback));
      return false;
   }

   double src = 0;
   switch(g_utb_srcEffective)
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
   // [v2.13] formula allineata a UTBotAdaptive-DA IMPLEMENTARE righe 1696-1697.
   // Fallback src_prev==0 rimosso: warmup engine garantisce src_prev valido.
   // ================================================================
   bool isBuy  = (trail_prev != 0) && (src_prev < trail_prev) && (src > trail);
   bool isSell = (trail_prev != 0) && (src_prev > trail_prev) && (src < trail);

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
   // STEP 7: Update state (trail + src + bar time + state badge + entryLevel)
   // [v2.13] state e entryLevel carry-forward per dashboard e UI.
   // ================================================================
   g_utb_lastTrail   = trail;
   g_utb_lastSrc     = src;
   g_utb_lastBarTime = barTime;

   // [v2.13] State badge + entryLevel carry-forward (allineato a B_State + B_EntryLine indicatore)
   if(isBuy)
   {
      g_utb_state      = +1.0;
      g_utb_entryLevel = iClose(_Symbol, PERIOD_CURRENT, 1);
   }
   else if(isSell)
   {
      g_utb_state      = -1.0;
      g_utb_entryLevel = iClose(_Symbol, PERIOD_CURRENT, 1);
   }
   // else: state e entryLevel rimangono ai valori precedenti (carry-forward)

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
   sig.extraValues[0] = PointsToPips(atr);              sig.extraLabels[0] = "ATR";
   sig.extraValues[1] = er;                              sig.extraLabels[1] = "ER";
   sig.extraValues[2] = trail;                           sig.extraLabels[2] = "Trail";
   sig.extraValues[3] = g_utb_keyValue;                  sig.extraLabels[3] = "Key";
   sig.extraValues[4] = src;                             sig.extraLabels[4] = "Source";
   sig.extraValues[5] = g_utb_state;                     sig.extraLabels[5] = "State";
   sig.extraValues[6] = g_utb_entryLevel;                sig.extraLabels[6] = "EntryLvl";
   sig.extraValues[7] = (double)g_utb_srcEffective;      sig.extraLabels[7] = "SrcEff";
   sig.extraCount     = 8;

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
