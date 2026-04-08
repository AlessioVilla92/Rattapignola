//+------------------------------------------------------------------+
//|                                         adDPCFilters.mqh         |
//|           AcquaDulza EA v1.7.1 — DPC Quality Filters             |
//|                                                                  |
//|  Filtri qualita' segnale DPC (Donchian Predictive Channel).      |
//|  Ogni filtro implementa un aspetto della strategia Turtle Soup:  |
//|                                                                  |
//|  1. FLATNESS:   banda deve essere "piatta" (no breakout vero)    |
//|  2. TREND CTX:  no segnali contro-trend macro (midline slope)    |
//|  3. LEVEL AGE:  banda ferma da N barre (livello "maturo")        |
//|  4. WIDTH:      canale min N pips (no squeeze troppo stretto)    |
//|  5. MA FILTER:  conferma da media mobile (classic o inverted)    |
//|  6. CLASSIFY:   TBS vs TWS (qualita' penetrazione banda)        |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| CheckBandFlatness_Sell — Block SELL if upper band expanded up    |
//|                                                                  |
//| LOGICA TURTLE SOUP: La strategia Soup cerca FALSE breakout.      |
//| Se la banda superiore si e' espansa verso l'alto, potrebbe       |
//| essere un breakout VERO (prezzo in forte rialzo), non un         |
//| falso breakout -> blocca SELL.                                   |
//|                                                                  |
//| Confronta la banda corrente con le ultime N barre (flatLookback).|
//| Se upper[0] > upper[k] + tolerance -> banda espansa -> BLOCK.   |
//+------------------------------------------------------------------+
bool DPCCheckFlatness_Sell(int barShift, double atr)
{
   double flatTolerance = g_dpc_flatTol * atr;
   int flatLookback = (int)MathMax(1, MathMin(10, g_dpc_flatLook));

   double uC, lC, mC;
   DPCComputeBands(barShift, g_dpc_dcLen, uC, lC, mC);

   for(int k = 1; k <= flatLookback; k++)
   {
      double uK, lK, mK;
      DPCComputeBands(barShift + k, g_dpc_dcLen, uK, lK, mK);

      if(uC > uK + flatTolerance)
      {
         AdLogD(LOG_CAT_FILTER, StringFormat(
            "DIAG Flatness SELL BLOCK: upper[0]=%.5f > upper[%d]=%.5f + tol=%.5f (ATR*%.2f)",
            uC, k, uK, flatTolerance, g_dpc_flatTol));
         return false;  // Upper expanded -> block SELL
      }
   }

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG Flatness SELL PASS: upper=%.5f stable over %d bars | tol=%.5f",
      uC, flatLookback, flatTolerance));
   return true;
}

//+------------------------------------------------------------------+
//| CheckBandFlatness_Buy — Block BUY if lower band expanded down   |
//|                                                                  |
//| Specchio di Sell: se la banda inferiore scende, potrebbe essere  |
//| un breakout ribassista VERO -> blocca BUY.                      |
//+------------------------------------------------------------------+
bool DPCCheckFlatness_Buy(int barShift, double atr)
{
   double flatTolerance = g_dpc_flatTol * atr;
   int flatLookback = (int)MathMax(1, MathMin(10, g_dpc_flatLook));

   double uC, lC, mC;
   DPCComputeBands(barShift, g_dpc_dcLen, uC, lC, mC);

   for(int k = 1; k <= flatLookback; k++)
   {
      double uK, lK, mK;
      DPCComputeBands(barShift + k, g_dpc_dcLen, uK, lK, mK);

      if(lC < lK - flatTolerance)
      {
         AdLogD(LOG_CAT_FILTER, StringFormat(
            "DIAG Flatness BUY BLOCK: lower[0]=%.5f < lower[%d]=%.5f - tol=%.5f (ATR*%.2f)",
            lC, k, lK, flatTolerance, g_dpc_flatTol));
         return false;  // Lower expanded down -> block BUY
      }
   }

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG Flatness BUY PASS: lower=%.5f stable over %d bars | tol=%.5f",
      lC, flatLookback, flatTolerance));
   return true;
}

//+------------------------------------------------------------------+
//| CheckTrendContext_Sell — Block SELL if macro uptrend              |
//|                                                                  |
//| LOGICA: Confronta la midline corrente con quella di dcLen barre  |
//| fa. Se la midline e' salita di piu' di trendThreshold (ATR *     |
//| TrendContextMult), il mercato e' in uptrend macro -> pericoloso  |
//| vendere contro-trend.                                            |
//|                                                                  |
//| La midline e' il centro del canale Donchian: se sale, il mercato |
//| sta facendo higher highs E higher lows -> trend rialzista.       |
//+------------------------------------------------------------------+
bool DPCCheckTrendContext_Sell(int barShift, double atr)
{
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if((barShift + g_dpc_dcLen) >= totalBars) return true;

   double trendThreshold = InpTrendContextMult * atr;

   double uNow, lNow, mNow;
   double uThen, lThen, mThen;
   DPCComputeBands(barShift, g_dpc_dcLen, uNow, lNow, mNow);
   DPCComputeBands(barShift + g_dpc_dcLen, g_dpc_dcLen, uThen, lThen, mThen);

   double midDelta = mNow - mThen;
   if(midDelta > trendThreshold)
   {
      AdLogD(LOG_CAT_FILTER, StringFormat(
         "DIAG TrendCtx SELL BLOCK: mNow=%.5f mThen=%.5f | delta=%.5f > threshold=%.5f (ATR*%.2f)",
         mNow, mThen, midDelta, trendThreshold, InpTrendContextMult));
      return false;  // Midline rose -> macro uptrend -> block SELL
   }

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG TrendCtx SELL PASS: midDelta=%.5f <= threshold=%.5f",
      midDelta, trendThreshold));
   return true;
}

//+------------------------------------------------------------------+
//| CheckTrendContext_Buy — Block BUY if macro downtrend             |
//|                                                                  |
//| Specchio di Sell: se la midline e' scesa, il mercato e' in       |
//| downtrend macro -> pericoloso comprare contro-trend.             |
//+------------------------------------------------------------------+
bool DPCCheckTrendContext_Buy(int barShift, double atr)
{
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if((barShift + g_dpc_dcLen) >= totalBars) return true;

   double trendThreshold = InpTrendContextMult * atr;

   double uNow, lNow, mNow;
   double uThen, lThen, mThen;
   DPCComputeBands(barShift, g_dpc_dcLen, uNow, lNow, mNow);
   DPCComputeBands(barShift + g_dpc_dcLen, g_dpc_dcLen, uThen, lThen, mThen);

   double midDelta = mThen - mNow;
   if(midDelta > trendThreshold)
   {
      AdLogD(LOG_CAT_FILTER, StringFormat(
         "DIAG TrendCtx BUY BLOCK: mThen=%.5f mNow=%.5f | delta=%.5f > threshold=%.5f (ATR*%.2f)",
         mThen, mNow, midDelta, trendThreshold, InpTrendContextMult));
      return false;  // Midline fell -> macro downtrend -> block BUY
   }

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG TrendCtx BUY PASS: midDelta=%.5f <= threshold=%.5f",
      midDelta, trendThreshold));
   return true;
}

//+------------------------------------------------------------------+
//| CheckLevelAge_Sell — Require upper band flat for N bars          |
//|                                                                  |
//| LOGICA TURTLE SOUP: Un livello "maturo" (rimasto fermo N barre)  |
//| e' un livello di resistenza significativo. I false breakout      |
//| sono piu' probabili su livelli maturi, perche' il mercato li ha  |
//| "testati" e li riconosce.                                       |
//|                                                                  |
//| Tolleranza: crypto usa g_pipSize (BTCUSD=$2), altri _Point.     |
//| Questo previene il bug v1.2.0 dove _Point=$0.02 per BTC era     |
//| troppo stretto e LevelAge non passava mai.                      |
//+------------------------------------------------------------------+
bool DPCCheckLevelAge_Sell(int barShift)
{
   int minAge = (int)MathMax(1, MathMin(10, g_dpc_minLevelAge));
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);

   double uC, lC, mC;
   DPCComputeBands(barShift, g_dpc_dcLen, uC, lC, mC);

   // Tolleranza: crypto usa g_pipSize (es. $2 per BTCUSD/$2 per ETH), altri strumenti usano _Point
   bool isCrypto = (g_instrumentClass == INSTRUMENT_CRYPTO || g_instrumentClass == INSTRUMENT_CRYPTO_ALT);
   double levelTol = isCrypto ? (2 * g_pipSize) : (2 * _Point);

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG LevelAge SELL: bar=%d | upper=%.2f | tolerance=%.5f (%s) | minAge=%d",
      barShift, uC, levelTol,
      isCrypto ? "crypto/pipSize" : "point",
      minAge));

   int flatBars = 0;
   double firstDelta = -1;
   for(int k = 1; k < g_dpc_dcLen && (barShift + k) < totalBars; k++)
   {
      double uK, lK, mK;
      DPCComputeBands(barShift + k, g_dpc_dcLen, uK, lK, mK);

      if(k == 1) firstDelta = MathAbs(uK - uC);

      if(MathAbs(uK - uC) <= levelTol)
         flatBars++;
      else
         break;
   }

   if(flatBars < minAge)
      AdLogD(LOG_CAT_FILTER, StringFormat(
         "DIAG LevelAge SELL BLOCKED: flatBars=%d < minAge=%d | firstDelta=%.5f vs tol=%.5f",
         flatBars, minAge, firstDelta, levelTol));
   else
      AdLogD(LOG_CAT_FILTER, StringFormat(
         "DIAG LevelAge SELL PASS: flatBars=%d >= minAge=%d",
         flatBars, minAge));

   return (flatBars >= minAge);
}

//+------------------------------------------------------------------+
//| CheckLevelAge_Buy — Require lower band flat for N bars           |
//|                                                                  |
//| Specchio di Sell: verifica che la banda inferiore sia "matura"   |
//| (ferma da almeno minAge barre). Stesso bug-fix tolleranza.       |
//+------------------------------------------------------------------+
bool DPCCheckLevelAge_Buy(int barShift)
{
   int minAge = (int)MathMax(1, MathMin(10, g_dpc_minLevelAge));
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);

   double uC, lC, mC;
   DPCComputeBands(barShift, g_dpc_dcLen, uC, lC, mC);

   // Tolleranza: crypto usa g_pipSize (es. $2 per BTCUSD/$2 per ETH), altri strumenti usano _Point
   bool isCrypto = (g_instrumentClass == INSTRUMENT_CRYPTO || g_instrumentClass == INSTRUMENT_CRYPTO_ALT);
   double levelTol = isCrypto ? (2 * g_pipSize) : (2 * _Point);

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG LevelAge BUY: bar=%d | lower=%.2f | tolerance=%.5f (%s) | minAge=%d",
      barShift, lC, levelTol,
      isCrypto ? "crypto/pipSize" : "point",
      minAge));

   int flatBars = 0;
   double firstDelta = -1;
   for(int k = 1; k < g_dpc_dcLen && (barShift + k) < totalBars; k++)
   {
      double uK, lK, mK;
      DPCComputeBands(barShift + k, g_dpc_dcLen, uK, lK, mK);

      if(k == 1) firstDelta = MathAbs(lK - lC);

      if(MathAbs(lK - lC) <= levelTol)
         flatBars++;
      else
         break;
   }

   if(flatBars < minAge)
      AdLogD(LOG_CAT_FILTER, StringFormat(
         "DIAG LevelAge BUY BLOCKED: flatBars=%d < minAge=%d | firstDelta=%.5f vs tol=%.5f",
         flatBars, minAge, firstDelta, levelTol));
   else
      AdLogD(LOG_CAT_FILTER, StringFormat(
         "DIAG LevelAge BUY PASS: flatBars=%d >= minAge=%d",
         flatBars, minAge));

   return (flatBars >= minAge);
}

//+------------------------------------------------------------------+
//| CheckChannelWidth — Min channel width in pips                    |
//|                                                                  |
//| LOGICA: Canale troppo stretto = squeeze/consolidazione.          |
//| I segnali in squeeze hanno basso R:R perche' TP e SL sono       |
//| troppo vicini. minWidth viene scalato per strumento via          |
//| g_inst_widthFactor (es. crypto x7, gold x5).                    |
//+------------------------------------------------------------------+
bool DPCCheckChannelWidth(double upper, double lower)
{
   double widthPips = PointsToPips(upper - lower);
   bool pass = (widthPips >= g_dpc_minWidth);

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG ChannelWidth: width=%.1fp vs min=%.1fp | result=%s",
      widthPips, g_dpc_minWidth, pass ? "PASS" : "BLOCK"));

   return pass;
}

//+------------------------------------------------------------------+
//| CheckMAFilter — MA direction filter                              |
//| Aligned with DPC indicator v7.19 (lines 3509-3520)               |
//|                                                                  |
//| CLASSIC:  trend-following — SELL se close < MA, BUY se close > MA|
//|           Filtra segnali CONTRO la MA: tradizionale              |
//|                                                                  |
//| INVERTED: mean-reversion Soup — SELL se close > MA (overextended)|
//|           BUY se close < MA (oversold) — DEFAULT in DPC          |
//|           La logica Soup cerca reversal: il prezzo deve essere   |
//|           "esteso" oltre la MA per un falso breakout plausibile  |
//+------------------------------------------------------------------+
bool DPCCheckMAFilter(double close1, double ma1, int direction)
{
   if(InpMAFilterMode == MA_FILTER_DISABLED) return true;
   if(ma1 <= 0) return true;

   bool pass = true;
   string mode = "DISABLED";

   if(InpMAFilterMode == MA_FILTER_CLASSIC)
   {
      mode = "CLASSIC";
      // Trend-following: SELL sotto MA, BUY sopra MA
      if(direction > 0)  pass = (close1 > ma1);  // BUY only above MA
      if(direction < 0)  pass = (close1 < ma1);  // SELL only below MA
   }
   else if(InpMAFilterMode == MA_FILTER_INVERTED)
   {
      mode = "INVERTED";
      // Mean-reversion Soup: SELL quando overextended SOPRA MA, BUY quando SOTTO MA
      if(direction > 0)  pass = (close1 < ma1);  // BUY when below MA (oversold)
      if(direction < 0)  pass = (close1 > ma1);  // SELL when above MA (overextended)
   }

   AdLogD(LOG_CAT_FILTER, StringFormat(
      "DIAG MAFilter %s [%s]: close=%.5f | ma=%.5f | result=%s",
      mode, direction > 0 ? "BUY" : "SELL",
      close1, ma1, pass ? "PASS" : "BLOCK"));

   return pass;
}

//+------------------------------------------------------------------+
//| ClassifySignal — TBS vs TWS pattern                              |
//| Aligned with DPC indicator v7.19 (lines 3636-3642, 3769-3775)   |
//|                                                                  |
//| TBS (Through Band Signal): il CORPO della candela penetra la    |
//| banda -> segnale di qualita' alta (quality=3).                   |
//| - BUY: min(open,close) < lower -> corpo sfonda sotto            |
//| - SELL: max(open,close) > upper -> corpo sfonda sopra           |
//|                                                                  |
//| TWS (Touch/Wick Signal): solo lo STOPPINO penetra la banda      |
//| -> segnale di qualita' bassa (quality=1).                        |
//| - Il corpo e' rimasto dentro il canale                           |
//|                                                                  |
//| TBS e' preferito per Turtle Soup perche' indica un tentativo     |
//| di breakout piu' aggressivo (e quindi piu' probabile reversal).  |
//+------------------------------------------------------------------+
int DPCClassifySignal(int direction, double open1, double close1, double upper, double lower)
{
   if(direction > 0) // BUY — lower band touched
   {
      // TBS: body LOW (min of open/close) breaks below lower band
      if(MathMin(open1, close1) < lower) return PATTERN_TBS;
      // TWS: only wick broke (low <= lower but body stayed inside)
      return PATTERN_TWS;
   }
   else if(direction < 0) // SELL — upper band touched
   {
      // TBS: body HIGH (max of open/close) breaks above upper band
      if(MathMax(open1, close1) > upper) return PATTERN_TBS;
      // TWS: only wick broke (high >= upper but body stayed inside)
      return PATTERN_TWS;
   }
   return PATTERN_NONE;
}
