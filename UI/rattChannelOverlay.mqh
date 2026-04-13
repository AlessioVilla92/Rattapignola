//+------------------------------------------------------------------+
//|                                      rattChannelOverlay.mqh      |
//|           Rattapignola EA v1.3.0 — Trend Candles + Trail + TP    |
//|                                                                  |
//|  Rendering grafico diretto dall'EA:                              |
//|   - Candele colorate per trend (body OBJ_RECTANGLE + wick        |
//|     OBJ_TREND) — teal bull, coral bear, giallo trigger           |
//|   - Trail line (OBJ_TREND segmenti, colore dinamico bull/bear)   |
//|   - Frecce storiche ER-colored (OBJ_ARROW)                      |
//|   - Entry level (OBJ_HLINE dashed viola)                         |
//|   - TP markers per ciclo trading                                 |
//|                                                                  |
//|  Calcoli identici all'indicatore UTBotAdaptive.mq5:              |
//|   - ATR Wilder (RMA, non SMA) per nLoss                         |
//|   - Sorgente adattiva (Close/KAMA/HMA/JMA)                      |
//|   - Trail stop 4-branch ratchet                                  |
//|   - ER classification a 4 livelli                                |
//|                                                                  |
//|  NAMING CONVENTION:                                              |
//|   RATT_TCOL_B_{i}  — body candela (OBJ_RECTANGLE)               |
//|   RATT_TCOL_W_{i}  — wick candela (OBJ_TREND)                   |
//|   RATT_OVL_{i}_T   — trail stop segmento                        |
//|   RATT_HSIG_{i}    — freccia storica                             |
//|   RATT_TRIG_CDL_{t} — trigger candle highlight (giallo)          |
//|   RATT_ENTRY_LEVEL — entry level HLINE                           |
//|   RATT_TP_*        — TP markers                                  |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

int g_ovlLastDepth = 0;

//+------------------------------------------------------------------+
//| IsNewBarOverlay — Rileva nuova barra (gate per pipeline OnTick)  |
//+------------------------------------------------------------------+
bool IsNewBarOverlay()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur == lastBar) return false;
   lastBar = cur;
   return true;
}

//+------------------------------------------------------------------+
//| GetSignalArrowColor — 4 livelli ER (UTBotAdaptive style)         |
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
//| DrawChannelOverlay — Disegno completo: candele trend + trail +   |
//|                      frecce storiche + entry level               |
//|                                                                  |
//| Pipeline identica all'indicatore UTBotAdaptive.mq5 OnCalculate: |
//| 1. ATR Wilder (SMA seed + RMA smoothing)                        |
//| 2. Sorgente adattiva (Close/KAMA/HMA/JMA)                       |
//| 3. Trail stop 4-branch                                          |
//| 4. Candle coloring: src>trail=teal, src<trail=coral, xover=giallo|
//| 5. Trail line segmenti teal/coral                                |
//| 6. Frecce BUY/SELL ER-colored                                    |
//| 7. Entry level dashed viola                                      |
//+------------------------------------------------------------------+
void DrawChannelOverlay()
{
   if(!ShowChannelOverlay && !ColorCandlesByTrend) return;

   int depth = MathMax(1, OverlayDepth);
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   int atrPeriod = (g_utb_atrPeriod > 0) ? g_utb_atrPeriod : 14;
   int lookback = MathMax(atrPeriod, 50) + 5;

   if(InpSrcType == UTB_SRC_HMA)
      lookback += g_utb_hmaPeriod * 2 + 10;
   else if(InpSrcType == UTB_SRC_KAMA)
      lookback += g_utb_kamaN + 5;

   if(totalBars < lookback + 5) return;
   depth = MathMin(depth, totalBars - lookback);

   // Cleanup segmenti orfani se depth diminuita
   if(g_ovlLastDepth > depth)
   {
      for(int i = depth; i < g_ovlLastDepth; i++)
      {
         string pfx = "RATT_OVL_" + IntegerToString(i) + "_";
         string nm = pfx + "T";
         if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
         string nb = "RATT_TCOL_B_" + IntegerToString(i);
         if(ObjectFind(0, nb) >= 0) ObjectDelete(0, nb);
         string nw = "RATT_TCOL_W_" + IntegerToString(i);
         if(ObjectFind(0, nw) >= 0) ObjectDelete(0, nw);
      }
   }
   g_ovlLastDepth = depth;

   int bufSize = depth + lookback;

   // Carica OHLC + ATR data
   double highBuf[], lowBuf[], openBuf[], closeBuf[];
   ArraySetAsSeries(highBuf, true);
   ArraySetAsSeries(lowBuf, true);
   ArraySetAsSeries(openBuf, true);
   ArraySetAsSeries(closeBuf, true);

   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, bufSize, highBuf) < bufSize) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, bufSize, lowBuf) < bufSize) return;
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, bufSize, openBuf) < bufSize) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, bufSize, closeBuf) < bufSize) return;

   // ================================================================
   // JMA: Save global state before scan (avoid corruption)
   // ================================================================
   bool   save_jma_init = false;
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
      UTBResetJMAState();
   }

   // KAMA local state
   double kama_prev = 0;
   bool   kama_init = false;
   double kama_fc = 2.0 / (g_utb_kamaFast + 1.0);
   double kama_sc = 2.0 / (g_utb_kamaSlow + 1.0);

   // ATR Wilder locale per scan storico
   double atr_w = 0;
   bool   atr_seeded = false;
   int    atr_count = 0;
   double tr_sum = 0;

   // Arrays per risultati visibili
   double arrTrail[], arrSrc[];
   datetime arrT[];
   ArrayResize(arrTrail, depth + 1);
   ArrayResize(arrSrc, depth + 1);
   ArrayResize(arrT, depth + 1);
   ArrayInitialize(arrTrail, 0);
   ArrayInitialize(arrSrc, 0);

   double trail = 0, src = 0, src_prev = 0;

   // Pulizia vecchi marker storici
   ObjectsDeleteAll(0, "RATT_HSIG_");
   ObjectsDeleteAll(0, "RATT_TRIG_CDL_");

   int signalCount = 0;
   double lastEntryPrice = 0;

   // SCAN: oldest to newest (i decrescente in array as-series)
   for(int i = bufSize - 2; i >= 0; i--)
   {
      // ATR Wilder (identica all'indicatore: SMA seed + RMA smoothing)
      if(i + 1 < bufSize)
      {
         double tr = MathMax(highBuf[i], closeBuf[i + 1]) - MathMin(lowBuf[i], closeBuf[i + 1]);
         if(!atr_seeded)
         {
            tr_sum += tr;
            atr_count++;
            if(atr_count >= atrPeriod)
            {
               atr_w = tr_sum / atrPeriod;
               atr_seeded = true;
            }
            else
               continue;
         }
         else
         {
            atr_w = (atr_w * (atrPeriod - 1) + tr) / atrPeriod;
         }
      }

      if(atr_w <= 0) continue;
      double nLoss = g_utb_keyValue * atr_w;

      // Sorgente adattiva
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
               curSrc = kama_prev;
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

      if(trail == 0)
      {
         trail = src - nLoss;
         if(i <= depth)
         {
            arrTrail[i] = trail;
            arrSrc[i] = src;
            arrT[i] = iTime(_Symbol, PERIOD_CURRENT, i);
         }
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

      if(i <= depth)
      {
         arrTrail[i] = trail;
         arrSrc[i] = src;
         arrT[i] = iTime(_Symbol, PERIOD_CURRENT, i);
      }

      // Signal detection + frecce storiche (solo per barre nel range visibile)
      if(i <= depth && i >= 1 && ShowSignalArrows)
      {
         bool isBuy  = (src_prev < trail_prev) && (src > trail);
         bool isSell = (src_prev > trail_prev) && (src < trail);

         if(isBuy || isSell)
         {
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
               er = (atr_w > 0) ? MathMin(1.0, MathAbs(src - src_prev) / atr_w) : 0;

            if(er >= InpERWeak || InpShowWeakSig)
            {
               datetime barTime = iTime(_Symbol, PERIOD_CURRENT, i);
               string arrowName = "RATT_HSIG_" + IntegerToString(i);
               color arrowClr = GetSignalArrowColor(isBuy, er);
               double arrowPrice;
               int arrowCode;

               if(isBuy)
               {
                  arrowPrice = lowBuf[i] - atr_w * RATT_ARROW_OFFSET;
                  arrowCode = 233;
               }
               else
               {
                  arrowPrice = highBuf[i] + atr_w * RATT_ARROW_OFFSET;
                  arrowCode = 234;
               }

               ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, arrowPrice);
               ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
               ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowClr);
               ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, RATT_ARROW_SIZE);
               ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
               ObjectSetInteger(0, arrowName, OBJPROP_BACK, false);
               ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);

               // Trigger candle highlight (giallo)
               datetime t2 = barTime + PeriodSeconds();
               string trigName = "RATT_TRIG_CDL_" + TimeToString(barTime, TIME_DATE|TIME_MINUTES);
               if(ObjectFind(0, trigName) < 0)
               {
                  ObjectCreate(0, trigName, OBJ_RECTANGLE, 0, barTime, highBuf[i], t2, lowBuf[i]);
                  ObjectSetInteger(0, trigName, OBJPROP_COLOR, RATT_TRIGGER_CANDLE_CLR);
                  ObjectSetInteger(0, trigName, OBJPROP_FILL, true);
                  ObjectSetInteger(0, trigName, OBJPROP_BACK, false);
                  ObjectSetInteger(0, trigName, OBJPROP_SELECTABLE, false);
                  ObjectSetInteger(0, trigName, OBJPROP_HIDDEN, true);
               }

               lastEntryPrice = closeBuf[i];
               signalCount++;
            }
         }
      }
   }

   // JMA: Restore global state
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

   // DISEGNO: candele colorate per trend + trail line
   int perSec = PeriodSeconds();

   for(int i = 0; i < depth; i++)
   {
      if(arrTrail[i] <= 0 || arrSrc[i] <= 0) continue;
      datetime t1 = arrT[i];
      if(t1 == 0) continue;

      bool isBull = (arrSrc[i] > arrTrail[i]);

      // === CANDELE COLORATE PER TREND ===
      if(ColorCandlesByTrend && i >= 1)
      {
         color candleClr = isBull ? RATT_CANDLE_BULL : RATT_CANDLE_BEAR;

         // Body: OBJ_RECTANGLE da Open a Close
         string bodyName = "RATT_TCOL_B_" + IntegerToString(i);
         double bodyTop = MathMax(openBuf[i], closeBuf[i]);
         double bodyBot = MathMin(openBuf[i], closeBuf[i]);
         if(bodyTop == bodyBot) bodyTop = bodyBot + _Point;
         datetime t2 = t1 + perSec;

         if(ObjectFind(0, bodyName) < 0)
         {
            ObjectCreate(0, bodyName, OBJ_RECTANGLE, 0, t1, bodyTop, t2, bodyBot);
            ObjectSetInteger(0, bodyName, OBJPROP_FILL, true);
            ObjectSetInteger(0, bodyName, OBJPROP_BACK, false);
            ObjectSetInteger(0, bodyName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, bodyName, OBJPROP_HIDDEN, true);
         }
         ObjectSetInteger(0, bodyName, OBJPROP_TIME, 0, t1);
         ObjectSetDouble(0, bodyName, OBJPROP_PRICE, 0, bodyTop);
         ObjectSetInteger(0, bodyName, OBJPROP_TIME, 1, t2);
         ObjectSetDouble(0, bodyName, OBJPROP_PRICE, 1, bodyBot);
         ObjectSetInteger(0, bodyName, OBJPROP_COLOR, candleClr);

         // Wick: OBJ_TREND da High a Low (linea verticale sottile)
         string wickName = "RATT_TCOL_W_" + IntegerToString(i);
         datetime tMid = t1 + perSec / 2;

         if(ObjectFind(0, wickName) < 0)
         {
            ObjectCreate(0, wickName, OBJ_TREND, 0, tMid, highBuf[i], tMid, lowBuf[i]);
            ObjectSetInteger(0, wickName, OBJPROP_RAY_LEFT, false);
            ObjectSetInteger(0, wickName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, wickName, OBJPROP_BACK, false);
            ObjectSetInteger(0, wickName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, wickName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, wickName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, wickName, OBJPROP_WIDTH, 1);
         }
         ObjectSetInteger(0, wickName, OBJPROP_TIME, 0, tMid);
         ObjectSetDouble(0, wickName, OBJPROP_PRICE, 0, highBuf[i]);
         ObjectSetInteger(0, wickName, OBJPROP_TIME, 1, tMid);
         ObjectSetDouble(0, wickName, OBJPROP_PRICE, 1, lowBuf[i]);
         ObjectSetInteger(0, wickName, OBJPROP_COLOR, candleClr);
      }

      // === TRAIL LINE ===
      if(ShowChannelOverlay && i < depth - 1 && arrTrail[i + 1] > 0)
      {
         datetime t2trail = arrT[i + 1];
         if(t2trail == 0) continue;

         string trailName = "RATT_OVL_" + IntegerToString(i) + "_T";
         color trailClr = isBull ? RATT_CHAN_TRAIL_BULL : RATT_CHAN_TRAIL_BEAR;

         if(ObjectFind(0, trailName) < 0)
         {
            ObjectCreate(0, trailName, OBJ_TREND, 0, t2trail, arrTrail[i + 1], t1, arrTrail[i]);
            ObjectSetInteger(0, trailName, OBJPROP_RAY_LEFT, false);
            ObjectSetInteger(0, trailName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, trailName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, trailName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, trailName, OBJPROP_BACK, false);
            ObjectSetInteger(0, trailName, OBJPROP_STYLE, RATT_CHAN_STYLE);
            ObjectSetInteger(0, trailName, OBJPROP_WIDTH, RATT_CHAN_WIDTH);
         }
         ObjectSetInteger(0, trailName, OBJPROP_TIME, 0, t2trail);
         ObjectSetDouble(0, trailName, OBJPROP_PRICE, 0, arrTrail[i + 1]);
         ObjectSetInteger(0, trailName, OBJPROP_TIME, 1, t1);
         ObjectSetDouble(0, trailName, OBJPROP_PRICE, 1, arrTrail[i]);
         ObjectSetInteger(0, trailName, OBJPROP_COLOR, trailClr);
      }
   }

   // Entry level per l'ultimo segnale trovato
   if(lastEntryPrice > 0)
   {
      string elName = "RATT_ENTRY_LEVEL";
      if(ObjectFind(0, elName) >= 0) ObjectDelete(0, elName);
      ObjectCreate(0, elName, OBJ_HLINE, 0, 0, lastEntryPrice);
      ObjectSetInteger(0, elName, OBJPROP_COLOR, RATT_ENTRY_LEVEL_CLR);
      ObjectSetInteger(0, elName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, elName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, elName, OBJPROP_BACK, true);
      ObjectSetInteger(0, elName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, elName, OBJPROP_HIDDEN, true);
   }

   AdLogI(LOG_CAT_UI, StringFormat("DrawChannelOverlay: %d signals over %d bars (ATR Wilder)", signalCount, depth));
}

//+------------------------------------------------------------------+
//| UpdateChannelLiveEdge — Aggiorna bordo live bar[0] (leggero)     |
//+------------------------------------------------------------------+
void UpdateChannelLiveEdge()
{
   if(!ShowChannelOverlay && !ColorCandlesByTrend) return;
   if(OverlayDepth <= 0) return;

   double src0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   double src1 = (g_utb_lastSrc > 0) ? g_utb_lastSrc : iClose(_Symbol, PERIOD_CURRENT, 1);
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);

   // Aggiorna trail stop bar[0]
   string nameT = "RATT_OVL_0_T";
   if(ShowChannelOverlay && ObjectFind(0, nameT) >= 0)
   {
      double trail1 = ObjectGetDouble(0, nameT, OBJPROP_PRICE, 0);
      if(trail1 > 0 && g_utb_atrWilder > 0)
      {
         double nLoss = g_utb_keyValue * g_utb_atrWilder;
         double trail0;

         if(src0 > trail1 && src1 > trail1)
            trail0 = MathMax(trail1, src0 - nLoss);
         else if(src0 < trail1 && src1 < trail1)
            trail0 = MathMin(trail1, src0 + nLoss);
         else if(src0 > trail1)
            trail0 = src0 - nLoss;
         else
            trail0 = src0 + nLoss;

         ObjectSetInteger(0, nameT, OBJPROP_TIME, 1, t0);
         ObjectSetDouble(0, nameT, OBJPROP_PRICE, 1, trail0);

         bool isBull = (src0 > trail0);
         ObjectSetInteger(0, nameT, OBJPROP_COLOR, isBull ? RATT_CHAN_TRAIL_BULL : RATT_CHAN_TRAIL_BEAR);
      }
   }

   // Aggiorna candela bar[0]
   if(ColorCandlesByTrend)
   {
      double o0 = iOpen(_Symbol, PERIOD_CURRENT, 0);
      double h0 = iHigh(_Symbol, PERIOD_CURRENT, 0);
      double l0 = iLow(_Symbol, PERIOD_CURRENT, 0);
      double c0 = src0;

      bool isBull = (g_utb_lastSrc > g_utb_lastTrail);
      color candleClr = isBull ? RATT_CANDLE_BULL : RATT_CANDLE_BEAR;

      int perSec = PeriodSeconds();
      datetime t2 = t0 + perSec;
      datetime tMid = t0 + perSec / 2;

      string bodyName = "RATT_TCOL_B_0";
      double bodyTop = MathMax(o0, c0);
      double bodyBot = MathMin(o0, c0);
      if(bodyTop == bodyBot) bodyTop = bodyBot + _Point;

      if(ObjectFind(0, bodyName) < 0)
      {
         ObjectCreate(0, bodyName, OBJ_RECTANGLE, 0, t0, bodyTop, t2, bodyBot);
         ObjectSetInteger(0, bodyName, OBJPROP_FILL, true);
         ObjectSetInteger(0, bodyName, OBJPROP_BACK, false);
         ObjectSetInteger(0, bodyName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, bodyName, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, bodyName, OBJPROP_TIME, 0, t0);
      ObjectSetDouble(0, bodyName, OBJPROP_PRICE, 0, bodyTop);
      ObjectSetInteger(0, bodyName, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, bodyName, OBJPROP_PRICE, 1, bodyBot);
      ObjectSetInteger(0, bodyName, OBJPROP_COLOR, candleClr);

      string wickName = "RATT_TCOL_W_0";
      if(ObjectFind(0, wickName) < 0)
      {
         ObjectCreate(0, wickName, OBJ_TREND, 0, tMid, h0, tMid, l0);
         ObjectSetInteger(0, wickName, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, wickName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, wickName, OBJPROP_BACK, false);
         ObjectSetInteger(0, wickName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, wickName, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, wickName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, wickName, OBJPROP_WIDTH, 1);
      }
      ObjectSetInteger(0, wickName, OBJPROP_TIME, 0, tMid);
      ObjectSetDouble(0, wickName, OBJPROP_PRICE, 0, h0);
      ObjectSetInteger(0, wickName, OBJPROP_TIME, 1, tMid);
      ObjectSetDouble(0, wickName, OBJPROP_PRICE, 1, l0);
      ObjectSetInteger(0, wickName, OBJPROP_COLOR, candleClr);
   }
}

//+------------------------------------------------------------------+
//| DrawTPLine — Disegna linea orizzontale TP (Take Profit)          |
//+------------------------------------------------------------------+
void DrawTPLine(int cycleID, double tpPrice, bool isBuy)
{
   if(!ShowTPTargetLines) return;
   string lineName = StringFormat("RATT_TP_LINE_%d", cycleID);
   color tpClr = isBuy ? RATT_TP_DOT_BUY : RATT_TP_DOT_SELL;
   CreateHLine(lineName, tpPrice, tpClr, RATT_TP_LINE_WIDTH, STYLE_DASH);
   ObjectSetString(0, lineName, OBJPROP_TOOLTIP,
       StringFormat("TP #%d %s @ %s", cycleID, isBuy ? "BUY" : "SELL",
                    DoubleToString(tpPrice, _Digits)));
}

//+------------------------------------------------------------------+
//| DrawTPDot — Cerchietto al livello del TP                         |
//+------------------------------------------------------------------+
void DrawTPDot(int cycleID, double tpPrice, datetime signalTime, bool isBuy)
{
   if(!ShowTPTargetLines) return;
   string name = StringFormat("RATT_TP_DOT_%d", cycleID);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, signalTime, tpPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? RATT_TP_DOT_BUY : RATT_TP_DOT_SELL);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| DrawTPAsterisk — Asterisco giallo al livello TP su ogni trigger  |
//+------------------------------------------------------------------+
void DrawTPAsterisk(double tpPrice, datetime signalTime, bool isBuy)
{
   string name = StringFormat("RATT_TP_STAR_%s_%s",
      isBuy ? "B" : "S",
      TimeToString(signalTime, TIME_DATE|TIME_MINUTES));
   if(ObjectFind(0, name) >= 0) return;
   ObjectCreate(0, name, OBJ_ARROW, 0, signalTime, tpPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 171);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
      StringFormat("TP Target %s @ %s [%s]",
         isBuy ? "BUY" : "SELL",
         DoubleToString(tpPrice, _Digits),
         EnumToString(TPMode)));
}

//+------------------------------------------------------------------+
//| DrawTPHitMarker — Stella quando il TP viene raggiunto            |
//+------------------------------------------------------------------+
void DrawTPHitMarker(int cycleID, double tpPrice, datetime hitTime)
{
   string name = StringFormat("RATT_TP_HIT_%d", cycleID);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, hitTime, tpPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 169);
   ObjectSetInteger(0, name, OBJPROP_COLOR, RATT_TP_HIT_CLR);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| RemoveTPLine — Rimuove linea TP + pallino alla chiusura ciclo    |
//+------------------------------------------------------------------+
void RemoveTPLine(int cycleID)
{
   string lineName = StringFormat("RATT_TP_LINE_%d", cycleID);
   if(ObjectFind(0, lineName) >= 0) ObjectDelete(0, lineName);
   string dotName = StringFormat("RATT_TP_DOT_%d", cycleID);
   if(ObjectFind(0, dotName) >= 0) ObjectDelete(0, dotName);
}

//+------------------------------------------------------------------+
//| CleanupOverlay — Rimuove TUTTI gli oggetti overlay               |
//+------------------------------------------------------------------+
void CleanupOverlay()
{
   ObjectsDeleteAll(0, "RATT_OVL_");      // Trail segments
   ObjectsDeleteAll(0, "RATT_TCOL_");     // Trend candle body + wick
   ObjectsDeleteAll(0, "RATT_TP_");       // TP markers
   ObjectsDeleteAll(0, "RATT_TRIG_VL_");  // VLine trigger (legacy)
   ObjectsDeleteAll(0, "RATT_TRIG_CDL_"); // Trigger candle highlight
   ObjectsDeleteAll(0, "RATT_HSIG_");     // Historical arrows
   ObjectDelete(0, "RATT_ENTRY_LEVEL");   // Entry level HLINE
   g_ovlLastDepth = 0;
}
