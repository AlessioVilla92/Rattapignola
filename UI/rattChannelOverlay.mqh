//+------------------------------------------------------------------+
//|                                      rattChannelOverlay.mqh      |
//|           Rattapignola EA v1.0.0 — Channel Overlay               |
//|                                                                  |
//|  Visualizzazione grafica del trailing stop UTBot sul chart.      |
//|  Disegna il trail stop come linea singola teal/coral              |
//|  (colore dinamico bull/bear) segmento per segmento.              |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  ARCHITETTURA A DUE LIVELLI:                                     |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|  1. FULL REDRAW (DrawChannelOverlay) — solo su nuova barra:      |
//|     Calcola il trailing stop UTBot per tutte le barre storiche   |
//|     (da bar[depth] a bar[0]) e disegna il trail con colore       |
//|     dinamico bull/bear per ogni segmento.                        |
//|                                                                  |
//|  2. LIVE EDGE UPDATE (UpdateChannelLiveEdge) — ogni 500ms:       |
//|     Aggiorna SOLO il segmento index=0 (che collega bar[1] a      |
//|     bar[0]) per il trail. Mantiene il bordo destro sincronizzato |
//|     con la candela in formazione.                                |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  NAMING CONVENTION OGGETTI CHART:                                |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|   Trail stop (depth segmenti):                                   |
//|   "RATT_OVL_{i}_T"  — Trail stop, segmento i (colore dinamico)  |
//|                                                                  |
//|   TP:                                                            |
//|   "RATT_TP_LINE_{id}" — Linea orizzontale TP per ciclo          |
//|   "RATT_TP_DOT_{id}"  — Punto cerchio TP per ciclo              |
//|   "RATT_TP_HIT_{id}"  — Stella quando TP viene raggiunto        |
//|   "RATT_TP_STAR_{B|S}_{time}" — Asterisco giallo TP preview     |
//|   "RATT_TRIG_VL_{t}"  — VLine trigger                           |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  CLEANUP:                                                        |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|  - CleanupOverlay(): ObjectsDeleteAll("RATT_OVL_") cattura tutti |
//|    i segmenti trail. Chiamata da OnDeinit().                     |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  DIPENDENZE:                                                     |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|   - Engine/rattUTBotEngine.mqh: g_utb_atrHandle, g_utb_keyValue, |
//|     g_utb_atrPeriod                                              |
//|   - Config/rattVisualTheme.mqh: RATT_CHAN_* defines              |
//|   - Config/rattInputParameters.mqh: ShowChannelOverlay,          |
//|     OverlayDepth, ShowTPTargetLines, EnableHedge, HsEnabled,     |
//|     HsShowZones, HsTriggerPct                                    |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| VARIABILI GLOBALI OVERLAY                                        |
//+------------------------------------------------------------------+
int     g_ovlLastDepth   = 0;     // Profondita' effettiva dell'ultimo disegno (per cleanup segmenti)

//+------------------------------------------------------------------+
//| IsNewBarOverlay — Rileva nuova barra per l'overlay               |
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
//| DrawChannelOverlay — Disegno COMPLETO del trailing stop UTBot    |
//|                                                                  |
//| SCOPO: Calcola il trailing stop UTBot per tutte le barre da      |
//|        bar[depth] a bar[0] e disegna la trail line (colore       |
//|        dinamico bull/bear) e la source line.                     |
//|                                                                  |
//| QUANDO VIENE CHIAMATA:                                           |
//|   - OnInit(): disegno iniziale all'avvio EA                      |
//|   - OnTimer(): retry se i dati non erano pronti in OnInit        |
//|   - OnTick(): SOLO su nuova barra (gate IsNewBarOverlay)         |
//|                                                                  |
//| PIPELINE:                                                        |
//|   1. Valida parametri (depth, barre disponibili, atrPeriod)     |
//|   2. Cleanup segmenti stale se la depth e' diminuita             |
//|   3. Carica ATR e Close buffer per calcolo trailing stop         |
//|   4. Calcola trail stop barra per barra (oldest to newest)       |
//|   5. Disegna 2 linee per ogni coppia di barre adiacenti:         |
//|      - Trail stop (colore dinamico bull/bear)                    |
//|      - Source line (yellow firefly)                               |
//|   6. Disegna fill trasparente CCanvas tra source e trail         |
//+------------------------------------------------------------------+

void DrawChannelOverlay()
{
   if(!ShowChannelOverlay && !ColorCandlesByTrend) return;

   // Parametri: depth = quante barre disegnare, atrPeriod per lookback
   int depth = MathMax(1, OverlayDepth);
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   int atrPeriod = (g_utb_atrPeriod > 0) ? g_utb_atrPeriod : 14;
   int lookback = MathMax(atrPeriod, 50) + 5;

   // Extra lookback per sorgente adattiva (come ScanHistoricalSignals)
   if(InpSrcType == UTB_SRC_HMA)
      lookback += g_utb_hmaPeriod * 2 + 10;
   else if(InpSrcType == UTB_SRC_KAMA)
      lookback += g_utb_kamaN + 5;

   // Serve almeno lookback barre per calcolare il trailing stop
   if(totalBars < lookback + 5)
   {
      AdLogW(LOG_CAT_UI, StringFormat("DrawChannelOverlay: insufficient bars (%d < %d)", totalBars, lookback + 5));
      return;
   }
   depth = MathMin(depth, totalBars - lookback);

   // Pulizia segmenti orfani: se la depth e' diminuita rispetto
   // all'ultimo disegno, elimina gli oggetti che non servono piu'.
   // Guard ObjectFind per evitare error 4202 nei log Experts su
   // oggetti gia' assenti (es. dopo cleanup parziale o cambio chart).
   if(g_ovlLastDepth > depth)
   {
      for(int i = depth; i < g_ovlLastDepth; i++)
      {
         string pfx = "RATT_OVL_" + IntegerToString(i) + "_";
         string nm  = pfx + "T";
         if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
      }
   }
   g_ovlLastDepth = depth;

   int bufSize = depth + lookback;

   // Carica ATR buffer
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   int atrCopied = CopyBuffer(g_utb_atrHandle, 0, 0, bufSize, atrBuf);
   if(atrCopied < bufSize)
   {
      AdLogW(LOG_CAT_UI, StringFormat("DrawChannelOverlay: ATR copy failed (%d < %d)", atrCopied, bufSize));
      return;
   }

   // Carica Close buffer
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   int closeCopied = CopyClose(_Symbol, PERIOD_CURRENT, 0, bufSize, closeBuf);
   if(closeCopied < bufSize)
   {
      AdLogW(LOG_CAT_UI, StringFormat("DrawChannelOverlay: Close copy failed (%d < %d)", closeCopied, bufSize));
      return;
   }

   // ================================================================
   // JMA: Save global state before scan (avoid corruption)
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

      UTBResetJMAState();
   }

   // ================================================================
   // KAMA: stato locale (non tocca globali engine)
   // ================================================================
   double kama_prev = 0;
   bool   kama_init = false;
   double kama_fc = 2.0 / (g_utb_kamaFast + 1.0);
   double kama_sc = 2.0 / (g_utb_kamaSlow + 1.0);

   // Array temporanei: Trail, Source, Time per ogni barra visibile
   double arrTrail[], arrSrc[];
   datetime arrT[];
   ArrayResize(arrTrail, depth + 1);
   ArrayResize(arrSrc, depth + 1);
   ArrayResize(arrT, depth + 1);
   ArrayInitialize(arrTrail, 0);
   ArrayInitialize(arrSrc, 0);

   // STEP 1: Calcola trailing stop per tutte le barre (oldest to newest)
   // Usa la SORGENTE ADATTIVA (Close/KAMA/HMA/JMA) identica all'engine
   double trail = 0;
   double src = 0, src_prev = 0;

   for(int i = bufSize - 2; i >= 0; i--)
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
   }

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

   // STEP 2: Le candele colorate per trend sono disegnate dall'indicatore
   // UTBotAdaptive embedded come resource (vedi Rattapignola.mq5 #resource +
   // iCustom in OnInit). L'EA non disegna piu' rettangoli RATT_TCOL_.

   // STEP 3: Disegna segmenti trail (OBJ_TREND) — sopra le candele dell'indicatore
   if(ShowChannelOverlay)
   {
      for(int i = 0; i < depth; i++)
      {
         if(arrTrail[i] <= 0 || arrTrail[i + 1] <= 0) continue;
         if(arrSrc[i] <= 0 || arrSrc[i + 1] <= 0) continue;

         datetime t1 = arrT[i];
         datetime t2 = arrT[i + 1];

         string prefix = "RATT_OVL_" + IntegerToString(i) + "_";

         bool isBull = (arrSrc[i] > arrTrail[i]);
         color trailClr = isBull ? RATT_CHAN_TRAIL_BULL : RATT_CHAN_TRAIL_BEAR;
         DrawOverlayLineDynColor(prefix + "T", t2, arrTrail[i + 1], t1, arrTrail[i],
                                 trailClr, RATT_CHAN_STYLE, RATT_CHAN_WIDTH);

         // When trend rectangles are foreground (BACK=false), trail must also be
         // foreground so it renders on top of filled rectangles
         if(ColorCandlesByTrend)
            ObjectSetInteger(0, prefix + "T", OBJPROP_BACK, false);
      }
   }
}

//+------------------------------------------------------------------+
//| UpdateChannelLiveEdge — Aggiorna SOLO il bordo live (bar[0])     |
//|                                                                  |
//| Funzione LEGGERA chiamata ogni 500ms per tenere aggiornato       |
//| il segmento index=0 del canale, che collega bar[1] a bar[0].    |
//| Aggiorna le coordinate del punto destro (bar[0]) del trail stop  |
//| con colore dinamico bull/bear (teal/coral).                      |
//+------------------------------------------------------------------+
void UpdateChannelLiveEdge()
{
   if(!ShowChannelOverlay && !ColorCandlesByTrend) return;
   if(OverlayDepth <= 0) return;

   int atrPeriod = (g_utb_atrPeriod > 0) ? g_utb_atrPeriod : 14;
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars < atrPeriod + 5) return;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_utb_atrHandle, 0, 0, 3, atrBuf) < 3) return;

   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, closeBuf) < 3) return;

   // Bar[0]: close live (approssimazione — engine non ha ancora calcolato)
   // Bar[1]: sorgente adattiva confermata dall'engine
   double src0 = closeBuf[0];
   double src1 = (g_utb_lastSrc > 0) ? g_utb_lastSrc : closeBuf[1];
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);

   // Aggiorna trail stop — solo il punto 1 (bar[0], estremo destro)
   string nameT = "RATT_OVL_0_T";
   bool isBull = false;

   if(ShowChannelOverlay && ObjectFind(0, nameT) >= 0)
   {
      double trail1 = ObjectGetDouble(0, nameT, OBJPROP_PRICE, 0);
      if(trail1 > 0)
      {
         double atr0 = atrBuf[0];
         double nLoss = g_utb_keyValue * atr0;
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

         isBull = (src0 > trail0);
         color trailClr = isBull ? RATT_CHAN_TRAIL_BULL : RATT_CHAN_TRAIL_BEAR;
         ObjectSetInteger(0, nameT, OBJPROP_COLOR, trailClr);

         // Trail foreground when trend rects are foreground (correct layering)
         if(ColorCandlesByTrend)
            ObjectSetInteger(0, nameT, OBJPROP_BACK, false);
      }
   }

   // Live candle coloring (bar[0]) gestito dall'indicatore UTBotAdaptive
   // embedded — vedi Rattapignola.mq5 OnInit.
}

//+------------------------------------------------------------------+
//| DrawOverlayLineDynColor — Segmento con colore DINAMICO           |
//|                                                                  |
//| Usata per il Trail stop che cambia colore ogni barra:            |
//|   bull color = price above trail (bullish)                       |
//|   bear color = price below trail (bearish)                       |
//+------------------------------------------------------------------+
void DrawOverlayLineDynColor(string name, datetime t1, double p1, datetime t2, double p2,
                             color clr, ENUM_LINE_STYLE style, int width)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      // Con ColorCandlesByTrend i rettangoli trend hanno BACK=false, quindi
      // il trail deve passare in foreground per restare visibile sopra di essi.
      bool trailFront = ColorCandlesByTrend;
      ObjectSetInteger(0, name, OBJPROP_BACK, trailFront ? false : true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, trailFront ? 350 : 50);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   }

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);  // Colore aggiornato ogni barra
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

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);  // Cerchio pieno
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? RATT_TP_DOT_BUY : RATT_TP_DOT_SELL);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);     // Davanti alle candele
}

//+------------------------------------------------------------------+
//| DrawTPAsterisk — Asterisco giallo al livello TP su ogni trigger  |
//+------------------------------------------------------------------+
void DrawTPAsterisk(double tpPrice, datetime signalTime, bool isBuy)
{
   string name = StringFormat("RATT_TP_STAR_%s_%s",
      isBuy ? "B" : "S",
      TimeToString(signalTime, TIME_DATE|TIME_MINUTES));

   if(ObjectFind(0, name) >= 0) return;  // Già disegnato per questo segnale

   ObjectCreate(0, name, OBJ_ARROW, 0, signalTime, tpPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 171);  // Asterisco
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow); // Giallo fisso
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

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 169);  // Stella
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
//| CleanupOverlay — Rimuove TUTTI gli oggetti overlay + canvas      |
//+------------------------------------------------------------------+
void CleanupOverlay()
{
   ObjectsDeleteAll(0, "RATT_OVL_");     // Segmenti trail
   ObjectsDeleteAll(0, "RATT_TP_");      // Linee e dot TP
   ObjectsDeleteAll(0, "RATT_TRIG_VL_"); // VLine trigger
   ObjectsDeleteAll(0, "RATT_TCOL_");    // Candele colorate (legacy v1.2 — pulizia migrazione)
   g_ovlLastDepth = 0;
}
