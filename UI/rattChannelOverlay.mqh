//+------------------------------------------------------------------+
//|                                      rattChannelOverlay.mqh      |
//|           Rattapignola EA v1.0.0 — Channel Overlay               |
//|                                                                  |
//|  Visualizzazione grafica del trailing stop UTBot sul chart.      |
//|  Disegna il trail stop (colore dinamico bull/bear) e la source   |
//|  line come segmenti OBJ_TREND barra per barra, con fill          |
//|  trasparente CCanvas.                                            |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  ARCHITETTURA A DUE LIVELLI:                                     |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|  1. FULL REDRAW (DrawChannelOverlay) — solo su nuova barra:      |
//|     Calcola il trailing stop UTBot per tutte le barre storiche   |
//|     (da bar[depth] a bar[0]) e disegna 2 tipi di segmento:      |
//|                                                                  |
//|     a) Trail stop (T) — colore dinamico per barra:               |
//|                           RATT_CHAN_TRAIL_BULL = price above trail|
//|                           RATT_CHAN_TRAIL_BEAR = price below trail|
//|     b) Source line (S) — RATT_CHAN_MID_CLR (yellow firefly)      |
//|                                                                  |
//|     + Fill trasparente CCanvas tra source e trail (alpha=40)     |
//|                                                                  |
//|  2. LIVE EDGE UPDATE (UpdateChannelLiveEdge) — ogni 500ms:       |
//|     Aggiorna SOLO il segmento index=0 (che collega bar[1] a      |
//|     bar[0]) per trail e source. Mantiene il bordo destro del     |
//|     canale sincronizzato con la candela in formazione.            |
//|     Costo: ~8 chiamate ObjectSet (vs full redraw)                |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  NAMING CONVENTION OGGETTI CHART:                                |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|   Trail stop + Source (2 tipi × depth segmenti):                 |
//|   "RATT_OVL_{i}_T"  — Trail stop, segmento i (colore dinamico)  |
//|   "RATT_OVL_{i}_S"  — Source line, segmento i                   |
//|                                                                  |
//|   Canvas e TP:                                                   |
//|   "RATT_OVL_CANVAS"  — CCanvas bitmap per il fill trasparente   |
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
//|    i segmenti (T/S) + canvas. CCanvas.Destroy()                  |
//|    libera la memoria bitmap. Chiamata da OnDeinit().             |
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
//|   - Canvas/Canvas.mqh: classe CCanvas per fill trasparente       |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

#include <Canvas/Canvas.mqh>

//+------------------------------------------------------------------+
//| VARIABILI GLOBALI OVERLAY                                        |
//+------------------------------------------------------------------+
CCanvas g_canvasFill;              // Oggetto CCanvas per il fill trasparente tra trail e source
string  g_canvasName = "RATT_OVL_CANVAS";  // Nome univoco dell'oggetto canvas sul chart
bool    g_canvasCreated = false;   // Flag: true dopo la prima creazione del canvas
uint    g_ovlLastRedrawMs = 0;     // Timestamp ultimo redraw canvas (throttle scroll a ~33 FPS)
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
   if(!ShowChannelOverlay) return;

   // Parametri: depth = quante barre disegnare, atrPeriod per lookback
   int depth = MathMax(1, OverlayDepth);
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   int atrPeriod = (g_utb_atrPeriod > 0) ? g_utb_atrPeriod : 14;
   int lookback = MathMax(atrPeriod, 50) + 5;

   // Serve almeno lookback barre per calcolare il trailing stop
   if(totalBars < lookback + 5)
   {
      AdLogW(LOG_CAT_UI, StringFormat("DrawChannelOverlay: insufficient bars (%d < %d)", totalBars, lookback + 5));
      return;
   }
   depth = MathMin(depth, totalBars - lookback);

   // Pulizia segmenti orfani: se la depth e' diminuita rispetto
   // all'ultimo disegno, elimina gli oggetti che non servono piu'
   if(g_ovlLastDepth > depth)
   {
      for(int i = depth; i < g_ovlLastDepth; i++)
      {
         string pfx = "RATT_OVL_" + IntegerToString(i) + "_";
         ObjectDelete(0, pfx + "T");
         ObjectDelete(0, pfx + "S");
      }
   }
   g_ovlLastDepth = depth;

   // Carica ATR buffer
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   int atrCopied = CopyBuffer(g_utb_atrHandle, 0, 0, depth + lookback, atrBuf);
   if(atrCopied < depth + lookback)
   {
      AdLogW(LOG_CAT_UI, StringFormat("DrawChannelOverlay: ATR copy failed (%d < %d)", atrCopied, depth + lookback));
      return;
   }

   // Carica Close buffer
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   int closeCopied = CopyClose(_Symbol, PERIOD_CURRENT, 0, depth + lookback, closeBuf);
   if(closeCopied < depth + lookback)
   {
      AdLogW(LOG_CAT_UI, StringFormat("DrawChannelOverlay: Close copy failed (%d < %d)", closeCopied, depth + lookback));
      return;
   }

   // Array temporanei: Trail, Source, Time per ogni barra visibile
   double arrTrail[], arrSrc[];
   datetime arrT[];
   ArrayResize(arrTrail, depth + 1);
   ArrayResize(arrSrc, depth + 1);
   ArrayResize(arrT, depth + 1);
   ArrayInitialize(arrTrail, 0);
   ArrayInitialize(arrSrc, 0);

   // STEP 1: Calcola trailing stop per tutte le barre (oldest to newest)
   // Dobbiamo scorrere dall'oldest al newest per mantenere lo stato del trail
   double trail = 0;
   double src = 0, src_prev = 0;

   // Prima calcolare il trail per le barre di warmup (non visualizzate)
   for(int i = depth + lookback - 2; i >= 0; i--)
   {
      double atr = atrBuf[i];
      if(atr <= 0) continue;
      double nLoss = g_utb_keyValue * atr;

      src_prev = src;
      src = closeBuf[i];

      if(trail == 0)
      {
         trail = src - nLoss;
         // Salva nei array se dentro il range visualizzabile
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

      // Salva nei array se dentro il range visualizzabile
      if(i <= depth)
      {
         arrTrail[i] = trail;
         arrSrc[i] = src;
         arrT[i] = iTime(_Symbol, PERIOD_CURRENT, i);
      }
   }

   // STEP 2: Disegna segmenti OBJ_TREND tra barre adiacenti
   for(int i = 0; i < depth; i++)
   {
      // Salta barre con dati invalidi
      if(arrTrail[i] <= 0 || arrTrail[i + 1] <= 0) continue;
      if(arrSrc[i] <= 0 || arrSrc[i + 1] <= 0) continue;

      datetime t1 = arrT[i];      // Tempo barra piu' recente (punto destro)
      datetime t2 = arrT[i + 1];  // Tempo barra piu' vecchia (punto sinistro)

      string prefix = "RATT_OVL_" + IntegerToString(i) + "_";

      // Trail stop — colore dinamico: bull se source sopra trail, bear se sotto
      bool isBull = (arrSrc[i] > arrTrail[i]);
      color trailClr = isBull ? RATT_CHAN_TRAIL_BULL : RATT_CHAN_TRAIL_BEAR;
      DrawOverlayLineDynColor(prefix + "T", t2, arrTrail[i + 1], t1, arrTrail[i],
                              trailClr, RATT_CHAN_STYLE, RATT_CHAN_WIDTH);

      // Source line — yellow firefly
      DrawOverlayLine(prefix + "S", t2, arrSrc[i + 1], t1, arrSrc[i],
                      RATT_CHAN_MID_CLR, STYLE_DOT, 1);
   }

   // STEP 3: Disegna fill trasparente tra source e trail
   DrawBandFill(arrSrc, arrTrail, arrT, depth);
}

//+------------------------------------------------------------------+
//| DrawBandFill — Fill trasparente tra source e trail con CCanvas   |
//+------------------------------------------------------------------+
void DrawBandFill(double &upper[], double &lower[], datetime &times[],
                  int count)
{
   // Dimensioni chart in pixel per il canvas
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(chartW < 10 || chartH < 10) return;

   // Se il chart e' stato ridimensionato, ridimensiona anche il canvas
   if(g_canvasCreated)
   {
      int oldW = (int)ObjectGetInteger(0, g_canvasName, OBJPROP_XSIZE);
      int oldH = (int)ObjectGetInteger(0, g_canvasName, OBJPROP_YSIZE);
      if(oldW != chartW || oldH != chartH)
         g_canvasFill.Resize(chartW, chartH);
   }

   // Prima creazione del canvas bitmap label
   if(!g_canvasCreated)
   {
      if(!g_canvasFill.CreateBitmapLabel(0, 0, g_canvasName, 0, 0, chartW, chartH, COLOR_FORMAT_ARGB_NORMALIZE))
      {
         AdLogE(LOG_CAT_UI, StringFormat("FAILED CreateBitmapLabel: %dx%d | error=%d", chartW, chartH, GetLastError()));
         return;
      }
      ObjectSetInteger(0, g_canvasName, OBJPROP_BACK, true);       // Dietro le candele
      ObjectSetInteger(0, g_canvasName, OBJPROP_SELECTABLE, false); // Non selezionabile
      ObjectSetInteger(0, g_canvasName, OBJPROP_HIDDEN, true);     // Nascosto da Lista Oggetti
      g_canvasCreated = true;
      AdLogI(LOG_CAT_UI, StringFormat("Overlay canvas created: %dx%d", chartW, chartH));
   }

   // Pulisci canvas — 0x00000000 = nero completamente trasparente (ARGB)
   g_canvasFill.Erase(0x00000000);

   // Colore fill con trasparenza
   uint fillARGB = ColorToARGB(RATT_CHAN_FILL_CLR, RATT_CHAN_FILL_ALPHA);

   // Disegna un quadrilatero riempito tra ogni coppia di barre
   for(int i = 0; i < count - 1; i++)
   {
      if(upper[i] <= 0 || lower[i] <= 0) continue;
      if(upper[i + 1] <= 0 || lower[i + 1] <= 0) continue;

      // Converti coordinate (time, price) -> (x, y) pixel
      int x1, y1U, y1L, x2, y2U, y2L;
      ChartTimePriceToXY(0, 0, times[i], upper[i], x1, y1U);
      ChartTimePriceToXY(0, 0, times[i], lower[i], x1, y1L);
      ChartTimePriceToXY(0, 0, times[i + 1], upper[i + 1], x2, y2U);
      ChartTimePriceToXY(0, 0, times[i + 1], lower[i + 1], x2, y2L);

      // Salta barre fuori dallo schermo
      if(x1 < -200 || x1 > chartW + 200) continue;
      if(x2 < -200 || x2 > chartW + 200) continue;

      g_canvasFill.FillTriangle(x1, y1U, x2, y2U, x1, y1L, fillARGB);
      g_canvasFill.FillTriangle(x2, y2U, x2, y2L, x1, y1L, fillARGB);
   }

   g_canvasFill.Update(false);
}

//+------------------------------------------------------------------+
//| RedrawOverlayFill — Ridisegna SOLO il canvas fill                |
//|                                                                  |
//| Quando l'utente scrolla, zooma o ridimensiona il chart,          |
//| le coordinate pixel cambiano ma i prezzi no. Serve               |
//| ridisegnare il canvas fill con le nuove coordinate pixel.        |
//|                                                                  |
//| THROTTLE: Max ~33 FPS (ogni 30ms) per evitare CPU eccessiva     |
//+------------------------------------------------------------------+
void RedrawOverlayFill()
{
   if(!ShowChannelOverlay || !g_canvasCreated) return;

   // Throttle: non ridisegnare piu' di ~33 volte al secondo
   uint now = GetTickCount();
   if(now - g_ovlLastRedrawMs < 30) return;
   g_ovlLastRedrawMs = now;

   int depth = MathMax(1, OverlayDepth);
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   int atrPeriod = (g_utb_atrPeriod > 0) ? g_utb_atrPeriod : 14;
   int lookback = MathMax(atrPeriod, 50) + 5;
   if(totalBars < lookback + 5) return;
   depth = MathMin(depth, totalBars - lookback);

   // Carica ATR e Close buffer per ricalcolo trail
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_utb_atrHandle, 0, 0, depth + lookback, atrBuf) < depth + lookback) return;

   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, depth + lookback, closeBuf) < depth + lookback) return;

   // Ricalcola trail e source
   double arrSrc[], arrTrail[];
   datetime arrT[];
   ArrayResize(arrSrc, depth + 1);
   ArrayResize(arrTrail, depth + 1);
   ArrayResize(arrT, depth + 1);
   ArrayInitialize(arrTrail, 0);
   ArrayInitialize(arrSrc, 0);

   double trail = 0;
   double src = 0, src_prev = 0;

   for(int i = depth + lookback - 2; i >= 0; i--)
   {
      double atr = atrBuf[i];
      if(atr <= 0) continue;
      double nLoss = g_utb_keyValue * atr;

      src_prev = src;
      src = closeBuf[i];

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

   DrawBandFill(arrSrc, arrTrail, arrT, depth);
}

//+------------------------------------------------------------------+
//| UpdateChannelLiveEdge — Aggiorna SOLO il bordo live (bar[0])     |
//|                                                                  |
//| Funzione LEGGERA chiamata ogni 500ms per tenere aggiornato       |
//| il segmento index=0 del canale, che collega bar[1] a bar[0].    |
//| Aggiorna le coordinate del punto destro (bar[0]) dei segmenti:  |
//|   T  = Trail stop (+ colore dinamico bull/bear)                  |
//|   S  = Source line                                               |
//+------------------------------------------------------------------+
void UpdateChannelLiveEdge()
{
   if(!ShowChannelOverlay) return;
   if(OverlayDepth <= 0) return;

   int atrPeriod = (g_utb_atrPeriod > 0) ? g_utb_atrPeriod : 14;
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars < atrPeriod + 5) return;

   // Calcola trail corrente per bar[0]
   // Usa i valori live dall'engine se disponibili
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_utb_atrHandle, 0, 0, 3, atrBuf) < 3) return;

   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, closeBuf) < 3) return;

   double src0 = closeBuf[0];
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   string prefix = "RATT_OVL_0_";

   // Aggiorna trail stop — solo il punto 1 (bar[0], estremo destro)
   string nameT = prefix + "T";
   if(ObjectFind(0, nameT) >= 0)
   {
      // Leggi il trail precedente dal punto 0 (bar[1]) dell'oggetto
      double trail1 = ObjectGetDouble(0, nameT, OBJPROP_PRICE, 0);
      if(trail1 > 0)
      {
         double atr0 = atrBuf[0];
         double nLoss = g_utb_keyValue * atr0;
         double src1 = closeBuf[1];
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

         // Colore dinamico: bull se source sopra trail
         bool isBull = (src0 > trail0);
         color trailClr = isBull ? RATT_CHAN_TRAIL_BULL : RATT_CHAN_TRAIL_BEAR;
         ObjectSetInteger(0, nameT, OBJPROP_COLOR, trailClr);
      }
   }

   // Aggiorna source line
   string nameS = prefix + "S";
   if(ObjectFind(0, nameS) >= 0)
   {
      ObjectSetInteger(0, nameS, OBJPROP_TIME, 1, t0);
      ObjectSetDouble(0, nameS, OBJPROP_PRICE, 1, src0);
   }
}

//+------------------------------------------------------------------+
//| DrawOverlayLine — Crea o aggiorna un segmento OBJ_TREND         |
//|                    (versione STATICA — colore fisso)              |
//+------------------------------------------------------------------+
void DrawOverlayLine(string name, datetime t1, double p1, datetime t2, double p2,
                     color clr, ENUM_LINE_STYLE style, int width)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 50);
      // Proprietà statiche: impostate solo alla creazione
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   }

   // Aggiorna SOLO le coordinate (cambiano ad ogni nuova barra)
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
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
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 50);
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
   ObjectsDeleteAll(0, "RATT_OVL_");     // Segmenti canale + canvas
   ObjectsDeleteAll(0, "RATT_TP_");      // Linee e dot TP
   ObjectsDeleteAll(0, "RATT_TRIG_VL_"); // VLine trigger
   if(g_canvasCreated)
   {
      g_canvasFill.Destroy();           // Libera memoria bitmap
      g_canvasCreated = false;
   }
   g_ovlLastDepth = 0;                 // Reset contatore profondita'
}
