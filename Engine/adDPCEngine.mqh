//+------------------------------------------------------------------+
//|                                          adDPCEngine.mqh         |
//|           AcquaDulza EA v1.6.1 — DPC Engine Orchestrator         |
//|                                                                  |
//|  Implements the 3 contract functions from adEngineInterface.mqh: |
//|    EngineInit()      — Create handles, init state                |
//|    EngineDeinit()    — Release handles, cleanup                  |
//|    EngineCalculate() — Read bar[1], populate EngineSignal         |
//|                                                                  |
//|  Calls sub-modules:                                              |
//|    adDPCPresets  — TF auto-preset                                |
//|    adDPCBands    — Band calculation, ATR, MA                     |
//|    adDPCFilters  — Quality filters                               |
//|    adDPCCooldown — SmartCooldown state machine                   |
//|    adDPCLTFEntry — LTF entry confirmation                        |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| DPC Engine State Variables                                       |
//+------------------------------------------------------------------+
datetime g_dpcLastProcessedBuyBar  = 0;
datetime g_dpcLastProcessedSellBar = 0;
int      g_dpcTimeBlockStartMin    = 0;
int      g_dpcTimeBlockEndMin      = 0;

//+------------------------------------------------------------------+
//| EngineInit — Contract function 1/3                               |
//|  1. Apply TF auto-preset                                        |
//|  2. Create indicator handles (ATR, MA)                           |
//|  3. Parse time filter                                            |
//|  4. Reset cooldown + LTF state                                   |
//|  5. Validate initial bands on bar[1]                             |
//+------------------------------------------------------------------+
bool EngineInit()
{
   // 1. Apply TF preset (sets g_dpc_dcLen, g_dpc_maLen, etc.)
   DPCPresetsInit();

   // v1.6.1: Avviso loop LTF su M1
   if(Period() == PERIOD_M1 && InpUseLTFEntry)
      AdLogW(LOG_CAT_DPC, "AVVISO: InpUseLTFEntry=true su M1 — disabilitare (LTF mapping M1→M1 = loop)");

   // 2. Create handles
   if(!DPCCreateHandles())
   {
      AdLogE(LOG_CAT_DPC, "CRITICAL: Failed to create DPC handles!");
      return false;
   }

   // 3. Parse time filter
   if(InpUseTimeFilter)
   {
      g_dpcTimeBlockStartMin = ParseTimeToMinutes(InpTimeBlockStart);
      g_dpcTimeBlockEndMin   = ParseTimeToMinutes(InpTimeBlockEnd);

      AdLogI(LOG_CAT_DPC, StringFormat("Time Filter: %02d:%02d - %02d:%02d (server)",
               g_dpcTimeBlockStartMin / 60, g_dpcTimeBlockStartMin % 60,
               g_dpcTimeBlockEndMin / 60, g_dpcTimeBlockEndMin % 60));
   }

   // 4. Reset state
   DPCResetCooldown();
   DPCResetLTF();
   g_dpcLastProcessedBuyBar  = 0;
   g_dpcLastProcessedSellBar = 0;
   g_lastSignal.Reset();

   // 5. Validate first read
   double testU, testL, testM;
   DPCComputeBands(1, g_dpc_dcLen, testU, testL, testM);

   if(testU > 0 && testL > 0 && testM > 0)
   {
      AdLogI(LOG_CAT_DPC, StringFormat("DPC ENGINE READY — Upper:%s | Lower:%s | Mid:%s | Width:%.1fp",
              DoubleToString(testU, _Digits), DoubleToString(testL, _Digits),
              DoubleToString(testM, _Digits), PointsToPips(testU - testL)));
   }
   else
   {
      AdLogW(LOG_CAT_DPC, "Engine handles ready but data not yet available (normal on first load)");
   }

   // Log configuration
   AdLogI(LOG_CAT_DPC, StringFormat("Params: Period=%d MAType=%s MALen=%d MinLevelAge=%d",
            g_dpc_dcLen, EnumToString(InpMAType), g_dpc_maLen, g_dpc_minLevelAge));
   AdLogI(LOG_CAT_DPC, StringFormat("SmartCooldown=%s MidTouch=%s SameDir=%d OppDir=%d",
            InpUseSmartCooldown ? "ON" : "OFF", InpRequireMidTouch ? "YES" : "NO",
            g_dpc_nSame, g_dpc_nOpp));
   AdLogI(LOG_CAT_DPC, StringFormat("Filters: Flatness=%s Trend=%s LevelAge=%s Width=%s Time=%s",
            InpUseBandFlatness ? "ON" : "OFF", InpUseTrendContext ? "ON" : "OFF",
            g_dpc_useLevelAge ? "ON" : "OFF", InpUseWidthFilter ? "ON" : "OFF",
            InpUseTimeFilter ? "ON" : "OFF"));
   AdLogI(LOG_CAT_DPC, StringFormat("LTF Entry=%s (OnlyTBS=%s) | TriggerMode=%s",
            g_dpc_useLTFEntry ? "ON" : "OFF", g_dpc_ltfOnlyTBS ? "YES" : "NO",
            EnumToString(InpTriggerMode)));

   Log_InitComplete("DPC Engine");
   return true;
}

//+------------------------------------------------------------------+
//| EngineDeinit — Contract function 2/3                             |
//+------------------------------------------------------------------+
void EngineDeinit()
{
   DPCReleaseHandles();
   DPCResetCooldown();
   DPCResetLTF();
   AdLogI(LOG_CAT_DPC, "DPC Engine deinitialized");
}

//+------------------------------------------------------------------+
//| EngineCalculate — Contract function 3/3                          |
//|                                                                  |
//|  Pipeline (every new bar, bar[1] confirmed):                     |
//|    1. Compute Donchian bands                                     |
//|    2. Compute ATR + EMA ATR                                      |
//|    3. Compute MA                                                 |
//|    4. Check midline touch (SmartCooldown state)                  |
//|    5. Signal detection: bearBase/bullBase                        |
//|    6. Quality filters (6 filters)                                |
//|    7. SmartCooldown check                                        |
//|    8. Classify signal (TBS/TWS)                                  |
//|    9. Entry/SL/TP price calculation                              |
//|   10. Populate EngineSignal                                      |
//|   11. LTF entry (if enabled)                                     |
//|   12. Anti-repaint guard                                         |
//|                                                                  |
//|  Returns: true if signal populated (direction != 0)              |
//+------------------------------------------------------------------+
bool EngineCalculate(EngineSignal &sig)
{
   sig.Reset();

   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars < g_dpc_dcLen + 5) return false;

   // === 1. COMPUTE DONCHIAN BANDS for bar[1] ===
   double upper1, lower1, mid1;
   DPCComputeBands(1, g_dpc_dcLen, upper1, lower1, mid1);

   if(upper1 <= 0 || lower1 <= 0 || mid1 <= 0) return false;

   // === 2. ATR + EMA ATR ===
   double atr1 = DPCGetATR(1);
   if(atr1 > 0)
      DPCUpdateEmaATR(atr1);

   // === 3. MA ===
   double ma1 = (InpMAFilterMode != MA_FILTER_DISABLED) ? DPCGetMAValue(1) : 0;

   // === Populate band data in signal (always, for dashboard) ===
   sig.upperBand      = upper1;
   sig.lowerBand      = lower1;
   sig.midline        = mid1;
   sig.channelWidthPip = PointsToPips(upper1 - lower1);
   sig.barTime        = iTime(_Symbol, PERIOD_CURRENT, 1);

   // === Populate extra values for dashboard ===
   sig.extraCount = 4;
   sig.extraLabels[0] = "ATR";        sig.extraValues[0] = atr1;
   sig.extraLabels[1] = "EMA ATR";    sig.extraValues[1] = g_dpcEmaATR;
   sig.extraLabels[2] = "MA";         sig.extraValues[2] = ma1;
   sig.extraLabels[3] = "Mid Color";  sig.extraValues[3] = (double)DPCGetMidlineColor(1);

   if(g_dpc_useLTFEntry)
   {
      sig.extraLabels[4] = "LTF";
      sig.extraValues[4] = g_ltfWindowOpen ? 1.0 : 0.0;
   }

   // === Engine config values for dashboard (engine-specific) ===
   sig.extraLabels[5] = "Period";     sig.extraValues[5] = (double)g_dpc_dcLen;
   sig.extraLabels[6] = "MA Len";    sig.extraValues[6] = (double)g_dpc_maLen;
   sig.extraLabels[7] = "MinWidth";  sig.extraValues[7] = g_dpc_minWidth;
   sig.extraLabels[8] = "CD Same";   sig.extraValues[8] = (double)g_dpc_nSame;
   sig.extraLabels[9] = "CD Opp";    sig.extraValues[9] = (double)g_dpc_nOpp;
   sig.extraCount = 10;

   // === 4. CHECK MIDLINE TOUCH (SmartCooldown) ===
   int currentBarIdx = totalBars - 2;  // bar[1] index
   DPCCheckMidlineTouch(1, currentBarIdx, mid1);

   // === 5. SIGNAL DETECTION on bar[1] ===
   double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1   = iLow(_Symbol, PERIOD_CURRENT, 1);
   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   // BAR_CLOSE: Turtle Soup rejection — touch band + close inside channel
   // Aligned with DPC indicator v7.19 Section 5 (lines 3123-3124)
   bool bearBase = (high1 >= upper1) && (close1 < upper1);   // Wick/body touches upper, closes INSIDE → SELL
   bool bullBase = (low1  <= lower1) && (close1 > lower1);   // Wick/body touches lower, closes INSIDE → BUY

   // Anti-ambiguity: both bands touched simultaneously
   if(bearBase && bullBase)
   {
      bearBase = false;
      bullBase = false;
   }

   // ── DIAG: Contatore barre senza segnale base (throttled) ──
   static int noBaseCount = 0;
   if(!bearBase && !bullBase)
   {
      noBaseCount++;
      if(noBaseCount % 20 == 1)
         AdLogI(LOG_CAT_ENGINE, StringFormat(
            "DIAG: %d barre senza segnale base | H=%.2f U=%.2f L=%.2f C=%.2f | W=%.1fp",
            noBaseCount, high1, upper1, lower1, close1, sig.channelWidthPip));
   }
   else
      noBaseCount = 0;

   // ── DIAG: Salva stato base PRE-filtri per diagnostica ──
   bool origBear = bearBase;
   bool origBull = bullBase;
   string rejectedBy = "";   // Accumula nomi filtri che bloccano

   // ── DIAG: Log quando un segnale base viene rilevato ──
   if(bearBase || bullBase)
   {
      AdLogD(LOG_CAT_ENGINE, StringFormat("DIAG BASE SIGNAL DETECTED: %s | Bar[1]=%s | H=%s L=%s O=%s C=%s | Upper=%s Lower=%s Mid=%s",
             bearBase ? "SELL(bear)" : "BUY(bull)",
             TimeToString(iTime(_Symbol, PERIOD_CURRENT, 1), TIME_DATE|TIME_MINUTES),
             DoubleToString(high1, _Digits), DoubleToString(low1, _Digits),
             DoubleToString(open1, _Digits), DoubleToString(close1, _Digits),
             DoubleToString(upper1, _Digits), DoubleToString(lower1, _Digits),
             DoubleToString(mid1, _Digits)));
   }

   // === 6. QUALITY FILTERS ===

   // Register filter states for dashboard
   sig.filterCount = 0;

   // --- Filter 1: Band Flatness ---
   bool flatPass_sell = true, flatPass_buy = true;
   if(InpUseBandFlatness && atr1 > 0)
   {
      if(bearBase) flatPass_sell = DPCCheckFlatness_Sell(1, atr1);
      if(bullBase) flatPass_buy  = DPCCheckFlatness_Buy(1, atr1);
      if(bearBase && !flatPass_sell)
      {
         bearBase = false;
         rejectedBy += "Flatness(SELL) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: Flatness — SELL bloccato (banda upper si espande, tol=%.4f*ATR)", g_dpc_flatTol));
      }
      if(bullBase && !flatPass_buy)
      {
         bullBase = false;
         rejectedBy += "Flatness(BUY) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: Flatness — BUY bloccato (banda lower si espande, tol=%.4f*ATR)", g_dpc_flatTol));
      }
   }
   sig.filterNames[sig.filterCount]  = "Flat";
   sig.filterStates[sig.filterCount] = InpUseBandFlatness ? ((flatPass_sell || flatPass_buy) ? 1 : -1) : 0;
   sig.filterCount++;

   // --- Filter 2: Trend Context ---
   bool trendPass_sell = true, trendPass_buy = true;
   if(InpUseTrendContext && atr1 > 0)
   {
      if(bearBase) trendPass_sell = DPCCheckTrendContext_Sell(1, atr1);
      if(bullBase) trendPass_buy  = DPCCheckTrendContext_Buy(1, atr1);
      if(bearBase && !trendPass_sell)
      {
         bearBase = false;
         rejectedBy += "TrendCtx(SELL) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: TrendContext — SELL bloccato (macro uptrend, soglia=%.1f*ATR)", InpTrendContextMult));
      }
      if(bullBase && !trendPass_buy)
      {
         bullBase = false;
         rejectedBy += "TrendCtx(BUY) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: TrendContext — BUY bloccato (macro downtrend, soglia=%.1f*ATR)", InpTrendContextMult));
      }
   }
   sig.filterNames[sig.filterCount]  = "Trend";
   sig.filterStates[sig.filterCount] = InpUseTrendContext ? ((trendPass_sell || trendPass_buy) ? 1 : -1) : 0;
   sig.filterCount++;

   // --- Filter 3: Level Age ---
   bool agePass_sell = true, agePass_buy = true;
   if(g_dpc_useLevelAge)
   {
      if(bearBase) agePass_sell = DPCCheckLevelAge_Sell(1);
      if(bullBase) agePass_buy  = DPCCheckLevelAge_Buy(1);
      if(bearBase && !agePass_sell)
      {
         bearBase = false;
         rejectedBy += "LevelAge(SELL) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: LevelAge — SELL bloccato (upper band non flat per min %d barre)", g_dpc_minLevelAge));
      }
      if(bullBase && !agePass_buy)
      {
         bullBase = false;
         rejectedBy += "LevelAge(BUY) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: LevelAge — BUY bloccato (lower band non flat per min %d barre)", g_dpc_minLevelAge));
      }
   }
   sig.filterNames[sig.filterCount]  = "Age";
   sig.filterStates[sig.filterCount] = g_dpc_useLevelAge ? ((agePass_sell || agePass_buy) ? 1 : -1) : 0;
   sig.filterCount++;

   // --- Filter 4: Channel Width ---
   bool widthPass = true;
   if(InpUseWidthFilter)
   {
      widthPass = DPCCheckChannelWidth(upper1, lower1);
      if(!widthPass)
      {
         if(bearBase) rejectedBy += "Width(SELL) ";
         if(bullBase) rejectedBy += "Width(BUY) ";
         bearBase = false;
         bullBase = false;
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: Width — canale troppo stretto (%.1fp < min %.1fp)",
                PointsToPips(upper1 - lower1), g_dpc_minWidth));
      }
   }
   sig.filterNames[sig.filterCount]  = "Width";
   sig.filterStates[sig.filterCount] = InpUseWidthFilter ? (widthPass ? 1 : -1) : 0;
   sig.filterCount++;

   // --- Filter 5: Time Filter ---
   bool timePass = true;
   if(InpUseTimeFilter)
   {
      timePass = !IsInBlockedTime(g_dpcTimeBlockStartMin, g_dpcTimeBlockEndMin);
      if(!timePass)
      {
         if(bearBase) rejectedBy += "Time(SELL) ";
         if(bullBase) rejectedBy += "Time(BUY) ";
         bearBase = false;
         bullBase = false;
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: TimeFilter — orario bloccato (%s-%s)",
                InpTimeBlockStart, InpTimeBlockEnd));
      }
   }
   sig.filterNames[sig.filterCount]  = "Time";
   sig.filterStates[sig.filterCount] = InpUseTimeFilter ? (timePass ? 1 : -1) : 0;
   sig.filterCount++;

   // --- Filter 6: MA Filter ---
   bool maPass_sell = true, maPass_buy = true;
   if(InpMAFilterMode != MA_FILTER_DISABLED && ma1 > 0)
   {
      if(bearBase) maPass_sell = DPCCheckMAFilter(close1, ma1, -1);
      if(bullBase) maPass_buy  = DPCCheckMAFilter(close1, ma1, +1);
      if(bearBase && !maPass_sell)
      {
         bearBase = false;
         rejectedBy += "MA(SELL) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: MA — SELL bloccato (close=%s, MA=%s, mode=%s)",
                DoubleToString(close1, _Digits), DoubleToString(ma1, _Digits), EnumToString(InpMAFilterMode)));
      }
      if(bullBase && !maPass_buy)
      {
         bullBase = false;
         rejectedBy += "MA(BUY) ";
         AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: MA — BUY bloccato (close=%s, MA=%s, mode=%s)",
                DoubleToString(close1, _Digits), DoubleToString(ma1, _Digits), EnumToString(InpMAFilterMode)));
      }
   }
   sig.filterNames[sig.filterCount]  = "MA";
   sig.filterStates[sig.filterCount] = (InpMAFilterMode != MA_FILTER_DISABLED) ? ((bearBase || bullBase) ? 1 : -1) : 0;
   sig.filterCount++;

   // === 7. SMARTCOOLDOWN (filter 7/7: signal frequency) ===
   bool bearCooldownOK = DPCCheckSmartCooldown_Sell(currentBarIdx);
   bool bullCooldownOK = DPCCheckSmartCooldown_Buy(currentBarIdx);

   bool bearCond = bearBase && bearCooldownOK;
   bool bullCond = bullBase && bullCooldownOK;

   // ── DIAG: Log se SmartCooldown blocca un segnale che ha passato tutti i filtri ──
   if(bearBase && !bearCooldownOK)
   {
      rejectedBy += "Cooldown(SELL) ";
      AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: SmartCooldown — SELL bloccato (lastDir=%d, barsSince=%d, midTouch=%s, waitingMid=%s)",
             g_dpcLastDirection_cd, currentBarIdx - g_dpcLastSignalBarIdx,
             g_dpcMidlineTouched_cd ? "YES" : "NO", g_dpcWaitingForMidTouch ? "YES" : "NO"));
   }
   if(bullBase && !bullCooldownOK)
   {
      rejectedBy += "Cooldown(BUY) ";
      AdLogD(LOG_CAT_FILTER, StringFormat("DIAG FILTRO BLOCCA: SmartCooldown — BUY bloccato (lastDir=%d, barsSince=%d, midTouch=%s, waitingMid=%s)",
             g_dpcLastDirection_cd, currentBarIdx - g_dpcLastSignalBarIdx,
             g_dpcMidlineTouched_cd ? "YES" : "NO", g_dpcWaitingForMidTouch ? "YES" : "NO"));
   }

   sig.filterNames[sig.filterCount]  = "CD";
   sig.filterStates[sig.filterCount] = InpUseSmartCooldown ?
      ((bearCond || bullCond) ? 1 : ((bearBase || bullBase) ? -1 : 0)) : 0;
   sig.filterCount++;

   // === Determine regime ===
   sig.isFlat = widthPass && (InpUseBandFlatness ? (flatPass_sell || flatPass_buy) : true);

   // === No signal ===
   if(!bearCond && !bullCond)
   {
      // ── DIAG: Log riepilogo reiezione se c'era un segnale base ──
      if(origBear || origBull)
      {
         AdLogD(LOG_CAT_ENGINE, StringFormat("DIAG SIGNAL REJECTED: %s base=%s | BLOCCATO DA: %s| Bar=%s",
                origBear ? "SELL" : "BUY",
                origBear ? StringFormat("H(%s)>=U(%s) C(%s)<U", DoubleToString(high1, _Digits), DoubleToString(upper1, _Digits), DoubleToString(close1, _Digits))
                         : StringFormat("L(%s)<=L(%s) C(%s)>L", DoubleToString(low1, _Digits), DoubleToString(lower1, _Digits), DoubleToString(close1, _Digits)),
                rejectedBy,
                TimeToString(iTime(_Symbol, PERIOD_CURRENT, 1), TIME_DATE|TIME_MINUTES)));
      }

      // Check LTF window if still open
      if(g_dpc_useLTFEntry && g_ltfWindowOpen)
         sig.ltfConfirm = DPCLTFCheckConfirmation();
      return true;  // Return true (data populated) but direction=0
   }

   // ── DIAG: Log segnale che ha SUPERATO tutti i filtri ──
   AdLogD(LOG_CAT_ENGINE, StringFormat("DIAG SIGNAL PASSED ALL FILTERS: %s | Bar=%s | Filtri superati: Flat=%s Trend=%s Age=%s Width=%s Time=%s MA=%s CD=%s",
          bullCond ? "BUY" : "SELL",
          TimeToString(iTime(_Symbol, PERIOD_CURRENT, 1), TIME_DATE|TIME_MINUTES),
          flatPass_sell || flatPass_buy ? "OK" : "SKIP",
          trendPass_sell || trendPass_buy ? "OK" : "SKIP",
          agePass_sell || agePass_buy ? "OK" : "SKIP",
          widthPass ? "OK" : "SKIP",
          timePass ? "OK" : "SKIP",
          maPass_sell || maPass_buy ? "OK" : "SKIP",
          (bullCond || bearCond) ? "OK" : "SKIP"));

   // === 8. CLASSIFY SIGNAL (TBS/TWS) ===
   int direction = bullCond ? +1 : -1;
   int quality   = DPCClassifySignal(direction, open1, close1, upper1, lower1);

   // Skip TWS signals if disabled
   if(!InpShowTWSSignals && quality == PATTERN_TWS)
   {
      AdLogD(LOG_CAT_ENGINE, StringFormat("DIAG SIGNAL DROPPED: %s TWS scartato (InpShowTWSSignals=false) | Bar=%s",
             direction > 0 ? "BUY" : "SELL",
             TimeToString(iTime(_Symbol, PERIOD_CURRENT, 1), TIME_DATE|TIME_MINUTES)));
      return true;  // Data populated but no signal emitted
   }

   // === 9. ANTI-REPAINT GUARD ===
   datetime bar1Time = iTime(_Symbol, PERIOD_CURRENT, 1);
   bool isNew = false;

   if(direction == -1 && bar1Time != g_dpcLastProcessedSellBar)
   {
      isNew = true;
      g_dpcLastProcessedSellBar = bar1Time;
   }
   else if(direction == +1 && bar1Time != g_dpcLastProcessedBuyBar)
   {
      isNew = true;
      g_dpcLastProcessedBuyBar = bar1Time;
   }

   if(!isNew)
   {
      AdLogD(LOG_CAT_ENGINE, StringFormat("DIAG ANTI-REPAINT: %s duplicato bloccato (bar gia' processata: %s)",
             direction > 0 ? "BUY" : "SELL",
             TimeToString(bar1Time, TIME_DATE|TIME_MINUTES)));
      return true;  // Duplicate blocked
   }

   // === Update cooldown after anti-repaint confirmation ===
   DPCUpdateCooldownState(direction, currentBarIdx);

   // === 10. POPULATE SIGNAL ===
   sig.direction   = direction;
   sig.quality     = quality;
   sig.isNewSignal = true;

   // Band level (the band that was touched)
   sig.bandLevel = (direction > 0) ? lower1 : upper1;

   // Entry price (band +/- offset, scalato per classe strumento)
   double triggerOffset = PipsToPrice(g_inst_stopOffset);
   if(direction > 0)
      sig.entryPrice = lower1 + triggerOffset;   // BUY STOP above lower band
   else
      sig.entryPrice = upper1 - triggerOffset;   // SELL STOP below upper band

   // [MOD] SL RIMOSSO — Il calcolo dello Stop Loss e' stato completamente disattivato.
   // Prima qui c'era il blocco SL_BAND_OPPOSITE / SL_ATR_MULTIPLE / SL_FIXED_PIPS
   // che conteneva un bug critico: piazzava lo SL dalla parte sbagliata
   // (sopra l'entry per BUY, sotto l'entry per SELL), causando il rifiuto
   // di TUTTI gli ordini pendenti da parte del broker (errore INVALID_STOPS).
   // Ora sig.slPrice resta a 0 (dal Reset()), gli ordini vengono piazzati senza SL.
   sig.slPrice = 0;

   // TP price (depends on TPMode)
   // Tutti i valori di banda (upper1, lower1, mid1) sono congelati al momento del segnale.
   // Per BUY (entry ≈ lower band): banda opposta = upper, per SELL: banda opposta = lower.
   if(TPMode == TP_MIDLINE)
   {
      // TP alla midline del canale Donchian — strategia mean reversion classica
      sig.tpPrice = mid1;
   }
   else if(TPMode == TP_OPPOSITE_BAND)
   {
      // TP alla banda opposta del canale — target full-range
      // BUY: entry vicino a lower → TP = upper band (massimo del canale)
      // SELL: entry vicino a upper → TP = lower band (minimo del canale)
      if(direction > 0)
         sig.tpPrice = upper1;
      else
         sig.tpPrice = lower1;
   }
   else if(TPMode == TP_150_PERCENT)
   {
      // TP a metà strada tra midline e banda opposta — 150% della distanza entry→midline
      // BUY: TP = (midline + upper) / 2 → oltre la midline ma non fino alla banda
      // SELL: TP = (midline + lower) / 2 → oltre la midline ma non fino alla banda
      if(direction > 0)
         sig.tpPrice = (mid1 + upper1) * 0.5;
      else
         sig.tpPrice = (mid1 + lower1) * 0.5;
   }
   else if(TPMode == TP_ATR_MULTIPLE && atr1 > 0)
   {
      // TP basato su ATR — distanza dal prezzo di entry proporzionale alla volatilità
      double tpDist = TPValue * atr1;
      if(direction > 0)
         sig.tpPrice = sig.entryPrice + tpDist;
      else
         sig.tpPrice = sig.entryPrice - tpDist;
   }
   else if(TPMode == TP_FIXED_PIPS)
   {
      // TP a distanza fissa in pip — indipendente dalla volatilità o dalla larghezza canale
      double tpDist = PipsToPrice(TPValue);
      if(direction > 0)
         sig.tpPrice = sig.entryPrice + tpDist;
      else
         sig.tpPrice = sig.entryPrice - tpDist;
   }

   // === 11. LTF ENTRY ===
   sig.ltfConfirm = 0;
   if(g_dpc_useLTFEntry && DPCLTFShouldFilter(quality))
   {
      // Open LTF window for this signal
      DPCLTFOpenWindow(direction, sig.bandLevel, iTime(_Symbol, PERIOD_CURRENT, 0));
   }

   // === LOG ===
   string patternName = (quality == PATTERN_TBS) ? "TBS" : ((quality == PATTERN_TWS) ? "TWS" : "???");
   AdLogI(LOG_CAT_DPC, StringFormat("=== NEW %s %s SIGNAL === Entry=%s SL=%s TP=%s Width=%.1fp",
          direction > 0 ? "BUY" : "SELL", patternName,
          DoubleToString(sig.entryPrice, _Digits),
          DoubleToString(sig.slPrice, _Digits),
          DoubleToString(sig.tpPrice, _Digits),
          sig.channelWidthPip));

   return true;
}
