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
//|  COLORI FRECCE:                                                   |
//|     TBS (Strong): lime/rosso brillante                           |
//|     TWS (Weak): verde/rosso scuro (attenuato)                    |
//|                                                                  |
//|  ARROW PLACEMENT (offset verticale):                              |
//|     offset = ATR * RATT_ARROW_OFFSET (0.15)                      |
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
//| GetSignalArrowColor — Strong bright / Weak muted                 |
//+------------------------------------------------------------------+
color GetSignalArrowColor(bool isBuy, int quality)
{
   if(quality >= PATTERN_TBS)
      return isBuy ? RATT_ARROW_STRONG_BUY : RATT_ARROW_STRONG_SELL;
   else
      return isBuy ? RATT_ARROW_WEAK_BUY : RATT_ARROW_WEAK_SELL;
}

//+------------------------------------------------------------------+
//| DrawSignalArrow — Strong/Weak arrow with ATR offset              |
//|  arrowCode 233=up (BUY), 234=down (SELL)                         |
//+------------------------------------------------------------------+
void DrawSignalArrow(const EngineSignal &sig)
{
   if(!ShowSignalArrows) return;
   if(sig.direction == 0 || !sig.isNewSignal) return;

   bool isBuy = (sig.direction > 0);
   string name = StringFormat("RATT_SIG_%s_%d_%s",
                 isBuy ? "BUY" : "SELL", sig.quality,
                 TimeToString(sig.barTime, TIME_DATE|TIME_MINUTES));

   int arrowCode = isBuy ? 233 : 234;
   color clr = GetSignalArrowColor(isBuy, sig.quality);

   // Arrow placement: with ATR offset
   double atr = (sig.extraValues[0] > 0) ? sig.extraValues[0] : 0;
   double offset = atr * RATT_ARROW_OFFSET;
   double bandPrice = isBuy ? sig.lowerBand : sig.upperBand;
   if(bandPrice <= 0) bandPrice = sig.entryPrice;
   double price = isBuy ? (bandPrice - offset) : (bandPrice + offset);
   if(price <= 0) price = bandPrice;

   ObjectCreate(0, name, OBJ_ARROW, 0, sig.barTime, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, RATT_ARROW_SIZE);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 400);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);

   string patternName = (sig.quality >= PATTERN_TBS) ? "TBS" : "TWS";
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
       StringFormat("%s %s | Entry: %s | SL: %s | TP: %s",
                    patternName, isBuy ? "BUY" : "SELL",
                    DoubleToString(sig.entryPrice, _Digits),
                    DoubleToString(sig.slPrice, _Digits),
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
   string name = StringFormat("RATT_LBL_%s_%s",
                 isBuy ? "BUY" : "SELL",
                 TimeToString(sig.barTime, TIME_DATE|TIME_MINUTES));

   string patternName = (sig.quality >= PATTERN_TBS) ? "TBS" : "TWS";
   string text = StringFormat("TRIGGER %s [%s]", isBuy ? "BUY" : "SELL", patternName);
   color clr = GetSignalArrowColor(isBuy, sig.quality);

   // Place near arrow
   double atr = (sig.extraValues[0] > 0) ? sig.extraValues[0] : 0;
   double offset = atr * (RATT_ARROW_OFFSET + 0.5);
   double bandPrice = isBuy ? sig.lowerBand : sig.upperBand;
   if(bandPrice <= 0) bandPrice = sig.entryPrice;
   double price = isBuy ? (bandPrice - offset) : (bandPrice + offset);

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
//| DrawSignalMarkers — Combined: arrow + dot + label               |
//+------------------------------------------------------------------+
void DrawSignalMarkers(const EngineSignal &sig)
{
   DrawSignalArrow(sig);
   DrawEntryDot(sig);
   DrawSignalLabel(sig);
}

//+------------------------------------------------------------------+
//| ScanHistoricalSignals — Scansione storica segnali UTBot          |
//|                         trailing stop                             |
//|                                                                  |
//| Riscritta per UTBot: calcola il trailing stop barra per barra    |
//| e rileva crossover tra source e trail come segnali buy/sell.     |
//| Usa g_utb_atrHandle e g_utb_keyValue per i parametri engine.     |
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
   if(totalBars < lookback) return;
   depth = MathMin(depth, totalBars - lookback);

   // Pulizia vecchi marker storici
   ObjectsDeleteAll(0, "RATT_HSIG_");
   ObjectsDeleteAll(0, "RATT_HDOT_");
   ObjectsDeleteAll(0, "RATT_HLBL_");

   // ATR buffer
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_utb_atrHandle, 0, 0, depth + lookback, atrBuf) < depth + lookback) return;

   // Close data
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, depth + lookback, closeBuf) < depth + lookback) return;

   // State for trailing stop scan
   double trail = 0, src = 0, src_prev = 0;
   int signalCount = 0;

   // Initialize source calculator state
   double kama_prev = 0;
   bool kama_init = false;
   double jma_e0=0, jma_e1=0, jma_e2=0, jma_prev=0;
   bool jma_init = false;

   // Scan from oldest to newest
   for(int i = depth + lookback - 2; i >= 1; i--)
   {
      double atr = atrBuf[i];
      if(atr <= 0) continue;
      double nLoss = g_utb_keyValue * atr;

      // Calculate source
      double curSrc = closeBuf[i];  // Default: close
      // For HMA/KAMA/JMA, simplified version using close for historical scan
      // (Full adaptive source would require extensive computation per bar)

      src_prev = src;
      src = curSrc;

      // Trailing stop
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

      // Signal detection
      bool isBuy  = (src_prev < trail_prev) && (src > trail);
      bool isSell = (src_prev > trail_prev) && (src < trail);

      if(!isBuy && !isSell) continue;

      // ER proxy
      double er = (atr > 0) ? MathMin(1.0, MathAbs(src - src_prev) / atr) : 0;
      int quality = (er >= InpERStrong) ? PATTERN_TBS : PATTERN_TWS;
      if(er < InpERWeak && !InpShowWeakSig) continue;

      datetime barTime = iTime(_Symbol, PERIOD_CURRENT, i);
      double entryPrice = closeBuf[i];
      bool isBuyDir = isBuy;

      // Draw arrow
      string arrowName = "RATT_HSIG_" + IntegerToString(i);
      double arrowPrice;
      int arrowCode;
      color arrowClr;

      if(isBuyDir)
      {
         arrowPrice = iLow(_Symbol, PERIOD_CURRENT, i) - atr * RATT_ARROW_OFFSET;
         arrowCode = 233;  // up arrow
         arrowClr = (quality == PATTERN_TBS) ? RATT_ARROW_STRONG_BUY : RATT_ARROW_WEAK_BUY;
      }
      else
      {
         arrowPrice = iHigh(_Symbol, PERIOD_CURRENT, i) + atr * RATT_ARROW_OFFSET;
         arrowCode = 234;  // down arrow
         arrowClr = (quality == PATTERN_TBS) ? RATT_ARROW_STRONG_SELL : RATT_ARROW_WEAK_SELL;
      }

      ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, arrowPrice);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowClr);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, RATT_ARROW_SIZE);
      ObjectSetInteger(0, arrowName, OBJPROP_BACK, true);
      ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);

      signalCount++;
   }

   AdLogI(LOG_CAT_UI, StringFormat("ScanHistoricalSignals: %d UTBot signals drawn over %d bars", signalCount, depth));
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
}
