//+------------------------------------------------------------------+
//|                                       rattSignalMarkers.mqh      |
//|           Rattapignola EA v1.0.0 — Signal Markers                |
//|                                                                  |
//|  Visualizzazione segnali UTBot sul chart — frecce, dot e labels. |
//|                                                                  |
//|  DUE MODALITA' DI DISEGNO:                                       |
//|                                                                  |
//|  1. REAL-TIME (DrawSignalMarkers) — segnali nuovi in tempo reale |
//|     Chiamata da OnTick() quando engine genera un nuovo segnale.  |
//|     Oggetti: RATT_SIG_*, RATT_DOT_*, RATT_LBL_*, RATT_TRIG_*    |
//|                                                                  |
//|  2. SCAN STORICO (ScanHistoricalSignals) — frecce passate        |
//|     Chiamata su ogni nuova barra (pre-gate, indipendente dallo   |
//|     stato EA). Replica la pipeline UTBot trailing stop per        |
//|     allineare frecce storiche ai trigger reali.                  |
//|     Oggetti: RATT_HSIG_*, RATT_HDOT_*, RATT_HLBL_*              |
//|                                                                  |
//|  COLORI FRECCE (4 livelli ER — UTBotAdaptive style):              |
//|     FORTE (ER>=0.60) / MOD (0.35-0.59) / DEB (0.15-0.34) / RANG |
//|                                                                  |
//|  ARROW PLACEMENT (offset verticale):                              |
//|     offset = ATR * RATT_ARROW_OFFSET (0.5)                       |
//|     BUY: sotto il low (lowPrice - offset)                        |
//|     SELL: sopra l'high (highPrice + offset)                      |
//|     Con ATR scaling l'offset e' proporzionale alla volatilita'.   |
//|                                                                  |
//|  Z-ORDER LAYERING:                                                |
//|     Signal arrows: Z=400 (sotto trigger)                          |
//|     Trigger arrows: Z=600 (sopra signal, cyan brillante)          |
//|     Entry dots: default Z (centro sulla banda)                    |
//|                                                                  |
//|  DIPENDENZE:                                                      |
//|     Config/rattVisualTheme.mqh: RATT_ARROW_*, RATT_ENTRY_*_CLR   |
//|     Engine/rattUTBotEngine.mqh: UTBot trailing stop logic         |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| GetSignalArrowColor — 4 livelli ER (UTBotAdaptive style)         |
//|   ER >= 0.60: FORTE | 0.35-0.59: MODERATO                       |
//|   0.15-0.34: DEBOLE | < 0.15: RANGING                           |
//+------------------------------------------------------------------+
color GetSignalArrowColor(bool isBuy, double er)
{
   int erIdx = (er >= 0.60) ? 0 : (er >= 0.35) ? 1 : (er >= 0.15) ? 2 : 3;
   if(isBuy)
   {
      if(erIdx == 0) return RATT_ARROW_BUY_0;
      if(erIdx == 1) return RATT_ARROW_BUY_1;
      if(erIdx == 2) return RATT_ARROW_BUY_2;
      return RATT_ARROW_BUY_3;
   }
   else
   {
      if(erIdx == 0) return RATT_ARROW_SELL_0;
      if(erIdx == 1) return RATT_ARROW_SELL_1;
      if(erIdx == 2) return RATT_ARROW_SELL_2;
      return RATT_ARROW_SELL_3;
   }
}

//+------------------------------------------------------------------+
//| DrawSignalArrow — ER-colored arrow with ATR offset               |
//|  arrowCode 233=up (BUY), 234=down (SELL)                         |
//|  Positioning: low - ATR*RATT_ARROW_OFFSET (BUY)                  |
//|               high + ATR*RATT_ARROW_OFFSET (SELL)                |
//|                                                                  |
//|  ── LEGENDA COLORI (4 livelli ER, Efficiency Ratio Kaufman) ──   |
//|  ER misura quanto direzionale e' il movimento (0=random/range,  |
//|  1=trend perfetto). Calcolato in UTBCalcER() (engine).           |
//|                                                                  |
//|    ER >= 0.60   BUY=verde scuro  SELL=rosso     FORTE            |
//|    ER 0.35-0.59 BUY=verde chiaro SELL=arancio   MODERATO         |
//|    ER 0.15-0.34 BUY=giallo       SELL=giallo    DEBOLE           |
//|    ER <  0.15   BUY=grigio       SELL=grigio    RANGING (chop)   |
//+------------------------------------------------------------------+
void DrawSignalArrow(const EngineSignal &sig)
{
   if(!ShowSignalArrows) return;
   if(sig.direction == 0 || !sig.isNewSignal) return;

   bool isBuy = (sig.direction > 0);
   double er = sig.extraValues[1];  // ER value
   string name = StringFormat("RATT_SIG_%s_%s",
                 isBuy ? "BUY" : "SELL",
                 TimeToString(sig.barTime, TIME_DATE|TIME_MINUTES));

   int arrowCode = isBuy ? 233 : 234;
   color clr = GetSignalArrowColor(isBuy, er);

   // Arrow placement: low - ATR*offset (BUY) / high + ATR*offset (SELL)
   double atrPips = (sig.extraValues[0] > 0) ? sig.extraValues[0] : 0;
   double atrPrice = PipsToPrice(atrPips);
   int barShift = iBarShift(_Symbol, PERIOD_CURRENT, sig.barTime);
   double price;
   if(isBuy)
      price = iLow(_Symbol, PERIOD_CURRENT, barShift) - atrPrice * RATT_ARROW_OFFSET;
   else
      price = iHigh(_Symbol, PERIOD_CURRENT, barShift) + atrPrice * RATT_ARROW_OFFSET;
   if(price <= 0) price = sig.entryPrice;

   ObjectCreate(0, name, OBJ_ARROW, 0, sig.barTime, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, RATT_ARROW_SIZE);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 400);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);

   string erLabel = (er >= 0.60) ? "FORTE" : (er >= 0.35) ? "MOD" : (er >= 0.15) ? "DEB" : "RANG";
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
       StringFormat("%s %s [ER=%.2f %s] | Entry: %s | TP: %s",
                    isBuy ? "BUY" : "SELL", erLabel, er, erLabel,
                    DoubleToString(sig.entryPrice, _Digits),
                    DoubleToString(sig.tpPrice, _Digits)));
}

//+------------------------------------------------------------------+
//| DrawSignalLabel — Text label "TRIGGER BUY [TBS]" at arrow pos    |
//+------------------------------------------------------------------+
void DrawSignalLabel(const EngineSignal &sig)
{
   if(!ShowSignalArrows) return;
   if(sig.direction == 0 || !sig.isNewSignal) return;

   bool isBuy = (sig.direction > 0);
   double er = sig.extraValues[1];
   string name = StringFormat("RATT_LBL_%s_%s",
                 isBuy ? "BUY" : "SELL",
                 TimeToString(sig.barTime, TIME_DATE|TIME_MINUTES));

   string erLabel = (er >= 0.60) ? "FORTE" : (er >= 0.35) ? "MOD" : (er >= 0.15) ? "DEB" : "RANG";
   string text = StringFormat("TRIGGER %s [%s]", isBuy ? "BUY" : "SELL", erLabel);
   color clr = GetSignalArrowColor(isBuy, er);

   // Place near arrow
   double atrPips = (sig.extraValues[0] > 0) ? sig.extraValues[0] : 0;
   double atrPrice = PipsToPrice(atrPips);
   int barShift = iBarShift(_Symbol, PERIOD_CURRENT, sig.barTime);
   double price;
   if(isBuy)
      price = iLow(_Symbol, PERIOD_CURRENT, barShift) - atrPrice * (RATT_ARROW_OFFSET + 0.3);
   else
      price = iHigh(_Symbol, PERIOD_CURRENT, barShift) + atrPrice * (RATT_ARROW_OFFSET + 0.3);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, sig.barTime, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DrawEntryDot — Circle marker at entry point                      |
//|  arrowCode 159 = filled circle                                   |
//+------------------------------------------------------------------+
void DrawEntryDot(const EngineSignal &sig)
{
   if(!ShowSignalArrows) return;
   if(sig.direction == 0 || !sig.isNewSignal) return;

   bool isBuy = (sig.direction > 0);
   double bandPrice = isBuy ? sig.lowerBand : sig.upperBand;
   if(bandPrice <= 0) return;

   string name = StringFormat("RATT_DOT_%s_%s",
                 isBuy ? "BUY" : "SELL",
                 TimeToString(sig.barTime, TIME_DATE|TIME_MINUTES));

   color clr = isBuy ? RATT_ENTRY_BUY_CLR : RATT_ENTRY_SELL_CLR;

   ObjectCreate(0, name, OBJ_ARROW, 0, sig.barTime, bandPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);

   ObjectSetString(0, name, OBJPROP_TOOLTIP,
       StringFormat("Entry dot %s | Band: %s",
                    isBuy ? "BUY" : "SELL",
                    DoubleToString(bandPrice, _Digits)));
}

//+------------------------------------------------------------------+
//| DrawTriggerArrow — Freccia cyan quando ordine piazzato            |
//|                                                                  |
//| Sovrapposta alla freccia segnale (Z=600 > Z=400) per indicare    |
//| che l'ordine e' stato effettivamente piazzato dal CycleManager.  |
//| Colore RATT_FIREFLY (cyan brillante), spessore 3 — risalta sopra |
//| le frecce Strong/Weak piu' piccole.                              |
//|                                                                  |
//| CHIAMATA DA: Rattapignola.mq5 OnTick() dopo CreateCycle()        |
//+------------------------------------------------------------------+
void DrawTriggerArrow(int cycleID, double price, datetime barTime, bool isBuy)
{
   if(!ShowSignalArrows) return;

   string name = StringFormat("RATT_TRIG_%s_%d_%s",
                 isBuy ? "BUY" : "SELL", cycleID,
                 TimeToString(barTime, TIME_DATE|TIME_MINUTES));

   int arrowCode = isBuy ? 233 : 234;

   ObjectCreate(0, name, OBJ_ARROW, 0, barTime, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, RATT_FIREFLY);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 600);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);

   ObjectSetString(0, name, OBJPROP_TOOLTIP,
       StringFormat("TRIGGER #%d %s @ %s",
                    cycleID, isBuy ? "BUY STOP" : "SELL STOP",
                    DoubleToString(price, _Digits)));
}

//+------------------------------------------------------------------+
//| DrawEntryLevel — Linea orizzontale tratteggiata viola            |
//|  al prezzo di entry (close del trigger bar). Si aggiorna ad      |
//|  ogni nuovo segnale. (UTBotAdaptive style)                       |
//+------------------------------------------------------------------+
string g_entryLevelName = "RATT_ENTRY_LEVEL";

void DrawEntryLevel(double price)
{
   if(ObjectFind(0, g_entryLevelName) >= 0)
      ObjectDelete(0, g_entryLevelName);

   ObjectCreate(0, g_entryLevelName, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, g_entryLevelName, OBJPROP_COLOR, RATT_ENTRY_LEVEL_CLR);
   ObjectSetInteger(0, g_entryLevelName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, g_entryLevelName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, g_entryLevelName, OBJPROP_BACK, true);
   ObjectSetInteger(0, g_entryLevelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, g_entryLevelName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DrawTriggerCandleHighlight — Rettangolo giallo su trigger bar    |
//|  Evidenzia la candela dove e' avvenuto il segnale UTBot.          |
//|  (UTBotAdaptive style)                                            |
//+------------------------------------------------------------------+
void DrawTriggerCandleHighlight(datetime barTime)
{
   int shift = iBarShift(_Symbol, PERIOD_CURRENT, barTime);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low  = iLow(_Symbol, PERIOD_CURRENT, shift);
   datetime t2 = barTime + PeriodSeconds();

   string name = "RATT_TRIG_CDL_" + TimeToString(barTime, TIME_DATE|TIME_MINUTES);
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_RECTANGLE, 0, barTime, high, t2, low);
   ObjectSetInteger(0, name, OBJPROP_COLOR, RATT_TRIGGER_CANDLE_CLR);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   // Foreground: deve restare sopra trail line e rettangoli trend candle.
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 400);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DrawSignalMarkers — Combined: arrow + dot + label + entry level  |
//|                      + trigger candle highlight                   |
//+------------------------------------------------------------------+
void DrawSignalMarkers(const EngineSignal &sig)
{
   DrawSignalArrow(sig);
   DrawEntryDot(sig);
   DrawSignalLabel(sig);

   if(sig.direction != 0 && sig.isNewSignal)
   {
      DrawEntryLevel(sig.entryPrice);
      DrawTriggerCandleHighlight(sig.barTime);
   }
}

//+------------------------------------------------------------------+
//| ScanHistoricalSignals — Scansione storica segnali UTBot          |
//|                         trailing stop                             |
//|                                                                  |
//| Calcola il trailing stop barra per barra usando la SORGENTE      |
//| ADATTIVA corretta (Close/KAMA/HMA/JMA) — identica all'engine.   |
//| Rileva crossover tra source e trail come segnali buy/sell.        |
//|                                                                  |
//| Per JMA: save/restore dello stato globale dell'engine per         |
//| evitare corruzione. UTBCalcJMA viene chiamata per ogni barra     |
//| dello scan, poi lo stato originale viene ripristinato.            |
//|                                                                  |
//| Risultato: le frecce nel grafico corrispondono ai segnali        |
//| UTBot trailing stop generati dall'engine.                        |
//+------------------------------------------------------------------+
void ScanHistoricalSignals()
{
   if(!ShowSignalArrows) return;

   int depth = MathMax(1, OverlayDepth);
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   int lookback = MathMax(g_utb_atrPeriod, 50) + 5;

   // Extra lookback per sorgente adattiva
   if(InpSrcType == UTB_SRC_HMA)
      lookback += g_utb_hmaPeriod * 2 + 10;
   else if(InpSrcType == UTB_SRC_KAMA)
      lookback += g_utb_kamaN + 5;

   if(totalBars < lookback) return;
   depth = MathMin(depth, totalBars - lookback);

   // Pulizia vecchi marker storici
   ObjectsDeleteAll(0, "RATT_HSIG_");
   ObjectsDeleteAll(0, "RATT_HDOT_");
   ObjectsDeleteAll(0, "RATT_HLBL_");
   ObjectsDeleteAll(0, "RATT_TRIG_CDL_");

   int bufSize = depth + lookback;

   // ATR buffer
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_utb_atrHandle, 0, 0, bufSize, atrBuf) < bufSize) return;

   // Close data
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, bufSize, closeBuf) < bufSize) return;

   // ================================================================
   // JMA: Save global state before scan
   // ================================================================
   bool   save_jma_init    = false;
   int    save_jma_histLen = 0;
   double save_jma_e0 = 0, save_jma_e1 = 0, save_jma_e2 = 0, save_jma_prev = 0;
   double save_uBand[], save_lBand[], save_volty[], save_vSum[];
   double save_e0_arr[], save_det0[], save_det1[], save_src_arr[];

   if(InpSrcType == UTB_SRC_JMA)
   {
      save_jma_init    = g_utb_jma_init;
      save_jma_histLen = g_utb_jma_histLen;
      save_jma_e0      = g_utb_jma_e0;
      save_jma_e1      = g_utb_jma_e1;
      save_jma_e2      = g_utb_jma_e2;
      save_jma_prev    = g_utb_jma_prev;

      ArrayCopy(save_uBand,   g_utb_jma_uBand);
      ArrayCopy(save_lBand,   g_utb_jma_lBand);
      ArrayCopy(save_volty,   g_utb_jma_volty);
      ArrayCopy(save_vSum,    g_utb_jma_vSum);
      ArrayCopy(save_e0_arr,  g_utb_jma_e0_arr);
      ArrayCopy(save_det0,    g_utb_jma_det0);
      ArrayCopy(save_det1,    g_utb_jma_det1);
      ArrayCopy(save_src_arr, g_utb_jma_src_arr);

      // Reset per scan pulito
      UTBResetJMAState();
   }

   // ================================================================
   // KAMA: stato locale (non tocca globali engine)
   // ================================================================
   double kama_prev = 0;
   bool   kama_init = false;
   double kama_fc = 2.0 / (g_utb_kamaFast + 1.0);
   double kama_sc = 2.0 / (g_utb_kamaSlow + 1.0);

   // State for trailing stop scan
   double trail = 0, src = 0, src_prev = 0;
   int signalCount = 0;
   double lastEntryPrice = 0;

   // Scan from oldest to newest (i decrescente in array as-series)
   for(int i = depth + lookback - 2; i >= 1; i--)
   {
      double atr = atrBuf[i];
      if(atr <= 0) continue;
      double nLoss = g_utb_keyValue * atr;

      // ===== Sorgente adattiva — identica all'engine =====
      double curSrc = closeBuf[i];

      switch(InpSrcType)
      {
         case UTB_SRC_CLOSE:
            curSrc = closeBuf[i];
            break;

         case UTB_SRC_KAMA:
         {
            if(!kama_init)
            {
               kama_prev = closeBuf[i];
               kama_init = true;
               curSrc = closeBuf[i];
            }
            else if((i + g_utb_kamaN) < bufSize)
            {
               double direction = MathAbs(closeBuf[i] - closeBuf[i + g_utb_kamaN]);
               double noise = 0;
               for(int k = 0; k < g_utb_kamaN; k++)
                  noise += MathAbs(closeBuf[i + k] - closeBuf[i + k + 1]);
               double er_k = (noise > 0) ? direction / noise : 0;
               double smooth = MathPow(er_k * (kama_fc - kama_sc) + kama_sc, 2.0);
               curSrc = kama_prev + smooth * (closeBuf[i] - kama_prev);
               kama_prev = curSrc;
            }
            else
            {
               curSrc = kama_prev;
            }
            break;
         }

         case UTB_SRC_HMA:
         {
            int period = g_utb_hmaPeriod;
            int half = MathMax(period / 2, 2);
            int sqn  = (int)MathRound(MathSqrt((double)period));
            int needed = i + period + sqn;

            if(needed < bufSize)
            {
               double tmp[];
               ArrayResize(tmp, sqn);
               for(int k = 0; k < sqn; k++)
               {
                  int barIdx = i + k;
                  double wmaHalf = WMAOnArray(closeBuf, barIdx, half, bufSize);
                  double wmaFull = WMAOnArray(closeBuf, barIdx, period, bufSize);
                  tmp[k] = 2.0 * wmaHalf - wmaFull;
               }
               double num = 0, den = 0;
               for(int k = 0; k < sqn; k++)
               {
                  double w = (double)(sqn - k);
                  num += w * tmp[k];
                  den += w;
               }
               curSrc = (den > 0) ? num / den : closeBuf[i];
            }
            break;
         }

         case UTB_SRC_JMA:
         {
            // UTBCalcJMA legge solo close[1] — mini array
            double jmaClose[3];
            jmaClose[0] = closeBuf[i];
            jmaClose[1] = closeBuf[i];
            jmaClose[2] = closeBuf[i];
            curSrc = UTBCalcJMA(jmaClose, 3);
            break;
         }
      }

      src_prev = src;
      src = curSrc;

      // Trailing stop (4 branches, Pine-faithful)
      double trail_prev = trail;
      if(trail_prev == 0)
      {
         trail = src - nLoss;
         continue;
      }

      if(src > trail_prev && src_prev > trail_prev)
         trail = MathMax(trail_prev, src - nLoss);
      else if(src < trail_prev && src_prev < trail_prev)
         trail = MathMin(trail_prev, src + nLoss);
      else if(src > trail_prev)
         trail = src - nLoss;
      else
         trail = src + nLoss;

      // Signal detection (crossover)
      bool isBuy  = (src_prev < trail_prev) && (src > trail);
      bool isSell = (src_prev > trail_prev) && (src < trail);

      if(!isBuy && !isSell) continue;

      // ER calculation — identica all'engine
      double er;
      if(InpSrcType == UTB_SRC_KAMA && (i + g_utb_kamaN) < bufSize)
      {
         double d = MathAbs(closeBuf[i] - closeBuf[i + g_utb_kamaN]);
         double n = 0;
         for(int k = 0; k < g_utb_kamaN; k++)
            n += MathAbs(closeBuf[i + k] - closeBuf[i + k + 1]);
         er = (n > 0) ? d / n : 0;
      }
      else
      {
         er = (atr > 0) ? MathMin(1.0, MathAbs(src - src_prev) / atr) : 0;
      }

      // Filter segnali deboli
      if(er < InpERWeak && !InpShowWeakSig) continue;

      datetime barTime = iTime(_Symbol, PERIOD_CURRENT, i);
      bool isBuyDir = isBuy;

      // Freccia con colore ER a 4 livelli
      string arrowName = "RATT_HSIG_" + IntegerToString(i);
      color arrowClr = GetSignalArrowColor(isBuyDir, er);
      double arrowPrice;
      int arrowCode;

      if(isBuyDir)
      {
         arrowPrice = iLow(_Symbol, PERIOD_CURRENT, i) - atr * RATT_ARROW_OFFSET;
         arrowCode = 233;
      }
      else
      {
         arrowPrice = iHigh(_Symbol, PERIOD_CURRENT, i) + atr * RATT_ARROW_OFFSET;
         arrowCode = 234;
      }

      ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, arrowPrice);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowClr);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, RATT_ARROW_SIZE);
      ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, isBuyDir ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, arrowName, OBJPROP_BACK, true);
      ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);

      // Trigger candle highlight (rettangolo giallo)
      DrawTriggerCandleHighlight(barTime);

      lastEntryPrice = closeBuf[i];
      signalCount++;
   }

   // Entry level per l'ultimo segnale trovato
   if(lastEntryPrice > 0)
      DrawEntryLevel(lastEntryPrice);

   // ================================================================
   // JMA: Restore global state after scan
   // ================================================================
   if(InpSrcType == UTB_SRC_JMA)
   {
      g_utb_jma_init    = save_jma_init;
      g_utb_jma_histLen = save_jma_histLen;
      g_utb_jma_e0      = save_jma_e0;
      g_utb_jma_e1      = save_jma_e1;
      g_utb_jma_e2      = save_jma_e2;
      g_utb_jma_prev    = save_jma_prev;

      ArrayCopy(g_utb_jma_uBand,   save_uBand);
      ArrayCopy(g_utb_jma_lBand,   save_lBand);
      ArrayCopy(g_utb_jma_volty,   save_volty);
      ArrayCopy(g_utb_jma_vSum,    save_vSum);
      ArrayCopy(g_utb_jma_e0_arr,  save_e0_arr);
      ArrayCopy(g_utb_jma_det0,    save_det0);
      ArrayCopy(g_utb_jma_det1,    save_det1);
      ArrayCopy(g_utb_jma_src_arr, save_src_arr);
   }

   AdLogI(LOG_CAT_UI, StringFormat("ScanHistoricalSignals: %d UTBot signals (%s source) over %d bars",
          signalCount, EnumToString(InpSrcType), depth));
}

//+------------------------------------------------------------------+
//| CleanupSignalMarkers — Rimuove tutti i marker segnale            |
//|                                                                  |
//| Cancella 7 famiglie di oggetti per prefisso:                     |
//|   RATT_SIG_  — frecce segnale real-time                          |
//|   RATT_DOT_  — entry dots real-time                              |
//|   RATT_LBL_  — labels testo real-time                            |
//|   RATT_TRIG_ — frecce trigger cyan (ordine piazzato)             |
//|   RATT_HSIG_ — frecce storiche (scan)                            |
//|   RATT_HDOT_ — entry dots storici                                |
//|   RATT_HLBL_ — labels testo storici                              |
//|                                                                  |
//| CHIAMATA DA: OnDeinit() in Rattapignola.mq5                     |
//+------------------------------------------------------------------+
void CleanupSignalMarkers()
{
   ObjectsDeleteAll(0, "RATT_SIG_");
   ObjectsDeleteAll(0, "RATT_DOT_");
   ObjectsDeleteAll(0, "RATT_LBL_");
   ObjectsDeleteAll(0, "RATT_TRIG_");
   ObjectsDeleteAll(0, "RATT_HSIG_");
   ObjectsDeleteAll(0, "RATT_HDOT_");
   ObjectsDeleteAll(0, "RATT_HLBL_");
   ObjectsDeleteAll(0, "RATT_TRIG_CDL_");
   ObjectDelete(0, "RATT_ENTRY_LEVEL");
}
