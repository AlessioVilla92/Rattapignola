//+------------------------------------------------------------------+
//|                                      adChannelOverlay.mqh        |
//|           AcquaDulza EA v1.8.0 — Channel Overlay                 |
//|                                                                  |
//|  Visualizzazione grafica del canale Donchian Predictive sul chart.|
//|  Disegna il canale DPC (bande + midline + MA) e il canale        |
//|  Hedge Smart entry (linee esterne dinamiche) come segmenti       |
//|  OBJ_TREND barra per barra, con fill trasparente CCanvas.        |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  ARCHITETTURA A DUE LIVELLI:                                     |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|  1. FULL REDRAW (DrawChannelOverlay) — solo su nuova barra:      |
//|     Calcola le bande Donchian per tutte le barre storiche        |
//|     (da bar[0] a bar[depth]) e disegna 6 tipi di segmento:      |
//|                                                                  |
//|     a) Upper band (U)  — blu solido, bordo superiore Donchian    |
//|     b) Lower band (L)  — blu solido, bordo inferiore Donchian    |
//|     c) Midline (M)     — colore dinamico per barra:              |
//|                           lime = bullish (midline sale)           |
//|                           red  = bearish (midline scende)         |
//|                           cyan = flat (midline stabile)           |
//|     d) MA filter (A)   — teal, linea media mobile inverted/class |
//|     e) HS Upper (HU)   — arancione tratteggiato, canale esterno  |
//|                           upper + (cw × HsTriggerPct)             |
//|                           Mostra dove entrerebbe BUY STOP HS     |
//|                           se fosse attiva una SELL Soup           |
//|     f) HS Lower (HL)   — arancione tratteggiato, canale esterno  |
//|                           lower - (cw × HsTriggerPct)             |
//|                           Mostra dove entrerebbe SELL STOP HS    |
//|                           se fosse attiva una BUY Soup            |
//|                                                                  |
//|     + Fill trasparente CCanvas tra upper e lower (alpha=40)      |
//|                                                                  |
//|  2. LIVE EDGE UPDATE (UpdateChannelLiveEdge) — ogni 500ms:       |
//|     Aggiorna SOLO il segmento index=0 (che collega bar[1] a      |
//|     bar[0]) per tutti i 6 tipi. Mantiene il bordo destro del     |
//|     canale sincronizzato con la candela in formazione.            |
//|     Costo: ~12 chiamate ObjectSet (vs ~15,000 del full redraw)   |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  OTTIMIZZAZIONI PERFORMANCE (v1.7.3):                            |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|  - DrawOverlayLine(): proprietà statiche (colore, stile,         |
//|    spessore) impostate SOLO alla prima creazione dell'oggetto.   |
//|    Dopo, aggiorna SOLO le 4 coordinate (time/price × 2 punti).  |
//|    Usata per: U, L, A, HU, HL (colore fisso)                    |
//|                                                                  |
//|  - DrawOverlayLineDynColor(): come sopra, ma aggiorna anche il   |
//|    colore ad ogni barra. Usata SOLO per la Midline (M) che       |
//|    cambia colore lime/red/cyan in base al trend.                 |
//|                                                                  |
//|  - IntegerToString() al posto di StringFormat() per i nomi       |
//|    dei segmenti nel loop tight (evita allocazione heap × 500)    |
//|                                                                  |
//|  - Flag bool drawHS pre-calcolato fuori dal loop (evita          |
//|    3 check booleani × 500 iterazioni)                            |
//|                                                                  |
//|  Risultato: ~15,000 API calls per redraw (era ~24,000 = -37%)   |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  NAMING CONVENTION OGGETTI CHART:                                |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|   Canale DPC (4 tipi × depth segmenti):                          |
//|   "AD_OVL_{i}_U"  — Upper band, segmento i                      |
//|   "AD_OVL_{i}_L"  — Lower band, segmento i                      |
//|   "AD_OVL_{i}_M"  — Midline, segmento i (colore dinamico)       |
//|   "AD_OVL_{i}_A"  — MA filter line, segmento i                  |
//|                                                                  |
//|   Canale HS entry (2 tipi × depth segmenti, se hedge attivo):    |
//|   "AD_OVL_{i}_HU" — HS entry channel upper, segmento i          |
//|   "AD_OVL_{i}_HL" — HS entry channel lower, segmento i          |
//|                                                                  |
//|   Canvas e TP:                                                   |
//|   "AD_OVL_CANVAS"  — CCanvas bitmap per il fill trasparente      |
//|   "AD_TP_LINE_{id}" — Linea orizzontale TP per ciclo             |
//|   "AD_TP_DOT_{id}"  — Punto cerchio TP per ciclo                 |
//|   "AD_TP_HIT_{id}"  — Stella quando TP viene raggiunto           |
//|   "AD_TP_STAR_{B|S}_{time}" — Asterisco giallo TP preview        |
//|   "AD_TRIG_VL_{t}"  — VLine trigger (disattivata, func presente) |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  CLEANUP:                                                        |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|  - CleanupOverlay(): ObjectsDeleteAll("AD_OVL_") cattura tutti   |
//|    i segmenti (U/L/M/A/HU/HL) + canvas. CCanvas.Destroy()       |
//|    libera la memoria bitmap. Chiamata da OnDeinit().             |
//|  - Depth change: loop elimina segmenti orfani (inclusi legacy    |
//|    H2U/H2L dal v1.5.0 Two-Tier hedge rimosso in v1.7.0)        |
//|  - HedgeDeinit(): pulisce legacy AD_HS_ZONE_* da v1.7.2         |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════════  |
//|  DIPENDENZE:                                                     |
//|  ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|   - Engine/adDPCBands.mqh: DPCComputeBands(), DPCGetMAValue(),   |
//|     DPCGetMidlineColor()                                         |
//|   - Config/adVisualTheme.mqh: AD_CHAN_* e AD_HS_CHAN_* defines    |
//|   - Config/adInputParameters.mqh: ShowChannelOverlay,            |
//|     OverlayDepth, ShowTPTargetLines, EnableHedge, HsEnabled,     |
//|     HsShowZones, HsTriggerPct                                    |
//|   - Canvas/Canvas.mqh: classe CCanvas per fill trasparente       |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

#include <Canvas/Canvas.mqh>

//+------------------------------------------------------------------+
//| VARIABILI GLOBALI OVERLAY                                        |
//+------------------------------------------------------------------+
CCanvas g_canvasFill;              // Oggetto CCanvas per il fill trasparente tra le bande
string  g_canvasName = "AD_OVL_CANVAS";  // Nome univoco dell'oggetto canvas sul chart
bool    g_canvasCreated = false;   // Flag: true dopo la prima creazione del canvas
uint    g_ovlLastRedrawMs = 0;     // Timestamp ultimo redraw canvas (throttle scroll a ~33 FPS)
int     g_ovlLastDepth   = 0;     // Profondita' effettiva dell'ultimo disegno (per cleanup segmenti)

// v1.7.3: Canale HS entry dinamico — sostituisce i 4 rettangoli statici (AD_HS_ZONE_*)
//          Le linee HU/HL seguono le bande DPC barra per barra come un Donchian esterno.
//          Geometria: upper + (cw × 30%) sopra, lower - (cw × 30%) sotto.
//          Il canale si allarga/stringe proporzionalmente al channel width (omotetia).
//          Controllato da: EnableHedge, HsEnabled, HsShowZones (input esistenti)
//          Colore/stile: AD_HS_CHAN_CLR/STYLE/WIDTH (definiti in adVisualTheme.mqh)

//+------------------------------------------------------------------+
//| IsNewBarOverlay — Rileva nuova barra per l'overlay               |
//|                                                                  |
//| SCOPO: Detection nuova barra INDIPENDENTE da IsNewBar() usata    |
//|        dalla trading logic. Evita interferenze: l'overlay si      |
//|        aggiorna su nuova barra anche quando EA e' in IDLE/PAUSED. |
//|                                                                  |
//| COME FUNZIONA:                                                   |
//|   - Usa una variabile static lastBar per ricordare l'ultima      |
//|     barra processata dall'overlay                                |
//|   - Confronta con iTime(0) della barra corrente                  |
//|   - Al primo tick di una nuova barra, ritorna true UNA SOLA VOLTA|
//|                                                                  |
//| CHIAMATA DA: OnTick() in AcquaDulza.mq5 — gate per full redraw  |
//| RITORNA: true se e' la prima volta che vede questa barra         |
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
//| DrawChannelOverlay — Disegno COMPLETO del canale storico         |
//|                                                                  |
//| SCOPO: Calcola le bande Donchian per tutte le barre da bar[0]    |
//|        a bar[depth] e disegna l'intero canale come segmenti      |
//|        OBJ_TREND collegati + fill trasparente CCanvas.           |
//|                                                                  |
//| QUANDO VIENE CHIAMATA:                                           |
//|   - OnInit(): disegno iniziale all'avvio EA                      |
//|   - OnTimer(): retry se i dati non erano pronti in OnInit        |
//|   - OnTick(): SOLO su nuova barra (gate IsNewBarOverlay)         |
//|                                                                  |
//| PIPELINE:                                                        |
//|   1. Valida parametri (depth, barre disponibili, dcLen)          |
//|   2. Cleanup segmenti stale se la depth e' diminuita             |
//|   3. Calcola bande DPC per ogni barra (loop bar[0]..bar[depth])  |
//|   4. Disegna 4 linee per ogni coppia di barre adiacenti:         |
//|      - Upper band (blu, AD_CHAN_UPPER_CLR)                       |
//|      - Lower band (blu, AD_CHAN_LOWER_CLR)                       |
//|      - Midline (lime/red/cyan in base al trend)                  |
//|      - MA filter (teal, solo se valore valido)                   |
//|   5. Disegna fill trasparente CCanvas tra upper e lower          |
//|                                                                  |
//| OGGETTI CREATI: ~depth*6 segmenti OBJ_TREND + 1 CCanvas bitmap  |
//|   (U, L, M, A per DPC + HU, HL per canale HS entry)            |
//| COSTO: ~15,000 chiamate API MQL5 con depth=500 e HS attivo     |
//|   (v1.7.3 OPT: colore/stile/spessore solo alla creazione)     |
//+------------------------------------------------------------------+

void DrawChannelOverlay()
{
   if(!ShowChannelOverlay) return;

   // Parametri: depth = quante barre disegnare, dcLen = periodo Donchian
   int depth = MathMax(1, OverlayDepth);
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   int dcLen = (g_dpc_dcLen > 0) ? g_dpc_dcLen : 20;

   // Serve almeno dcLen+5 barre per calcolare le bande
   if(totalBars < dcLen + 5)
   {
      AdLogW(LOG_CAT_UI, StringFormat("DrawChannelOverlay: insufficient bars (%d < %d)", totalBars, dcLen + 5));
      return;
   }
   depth = MathMin(depth, totalBars - 2);

   // Pulizia segmenti orfani: se la depth e' diminuita rispetto
   // all'ultimo disegno, elimina gli oggetti che non servono piu'
   // (es. cambio TF con meno barre, o riduzione OverlayDepth)
   if(g_ovlLastDepth > depth)
   {
      for(int i = depth; i < g_ovlLastDepth; i++)
      {
         string pfx = "AD_OVL_" + IntegerToString(i) + "_";
         ObjectDelete(0, pfx + "U");
         ObjectDelete(0, pfx + "L");
         ObjectDelete(0, pfx + "M");
         ObjectDelete(0, pfx + "A");
         ObjectDelete(0, pfx + "HU");
         ObjectDelete(0, pfx + "HL");
         ObjectDelete(0, pfx + "H2U");
         ObjectDelete(0, pfx + "H2L");
      }
   }
   g_ovlLastDepth = depth;

   // Array temporanei: Upper, Lower, Mid, MA, Time per ogni barra
   double arrU[], arrL[], arrM[], arrMA[];
   datetime arrT[];
   ArrayResize(arrU, depth + 1);
   ArrayResize(arrL, depth + 1);
   ArrayResize(arrM, depth + 1);
   ArrayResize(arrMA, depth + 1);
   ArrayResize(arrT, depth + 1);

   // STEP 1: Calcola bande Donchian per tutte le barre
   // barIdx=0 e' la barra corrente (live), barIdx=depth e' la piu' vecchia
   // DPCComputeBands usa iHighest/iLowest per trovare max/min nel lookback
   for(int i = 0; i <= depth && i < totalBars; i++)
   {
      int barIdx = i;  // bar[0] to bar[depth]
      arrT[i] = iTime(_Symbol, PERIOD_CURRENT, barIdx);
      DPCComputeBands(barIdx, dcLen, arrU[i], arrL[i], arrM[i]);
      arrMA[i] = DPCGetMAValue(barIdx);
   }

   // v1.7.3 OPT: Flag HS calcolato una volta fuori dal loop (evita 3 check × 500 iterazioni)
   bool drawHS = (EnableHedge && HsEnabled && HsShowZones);

   // STEP 2: Disegna segmenti OBJ_TREND tra barre adiacenti
   // Ogni segmento collega bar[i] (piu' recente) a bar[i+1] (piu' vecchia)
   // Il segmento i=0 e' il "live edge" che collega bar[0] a bar[1]
   for(int i = 0; i < depth && i < totalBars - 1; i++)
   {
      // Salta barre con dati invalidi (iHighest/iLowest ha fallito)
      if(arrU[i] <= 0 || arrL[i] <= 0) continue;

      datetime t1 = arrT[i];      // Tempo barra piu' recente (punto destro)
      datetime t2 = arrT[i + 1];  // Tempo barra piu' vecchia (punto sinistro)

      // v1.7.3 OPT: IntegerToString + concatenazione (evita StringFormat heap alloc × 500)
      string prefix = "AD_OVL_" + IntegerToString(i) + "_";

      // Banda superiore — colore blu, stile solido
      DrawOverlayLine(prefix + "U", t2, arrU[i + 1], t1, arrU[i],
                      AD_CHAN_UPPER_CLR, AD_CHAN_STYLE, AD_CHAN_WIDTH);

      // Banda inferiore — colore blu, stile solido
      DrawOverlayLine(prefix + "L", t2, arrL[i + 1], t1, arrL[i],
                      AD_CHAN_LOWER_CLR, AD_CHAN_STYLE, AD_CHAN_WIDTH);

      // Midline — colore dinamico per segmento (usa DrawOverlayLineDynColor):
      //   0 = bullish (lime): midline sale
      //   1 = bearish (red):  midline scende
      //   2 = flat (cyan):    midline stabile
      int midState = DPCGetMidlineColor(i);
      color midClr = AD_CHAN_MID_FLAT_CLR;
      if(midState == 0) midClr = AD_CHAN_MID_UP_CLR;
      else if(midState == 1) midClr = AD_CHAN_MID_DN_CLR;
      DrawOverlayLineDynColor(prefix + "M", t2, arrM[i + 1], t1, arrM[i],
                              midClr, AD_CHAN_MID_STYLE, AD_CHAN_WIDTH);

      // MA filter line — teal, spessore 2, solo se valore valido
      // Serve come filtro visivo: segnali validi solo se prezzo
      // e' sopra/sotto questa MA in base alla direzione
      if(arrMA[i] > 0 && arrMA[i + 1] > 0)
      {
         DrawOverlayLine(prefix + "A", t2, arrMA[i + 1], t1, arrMA[i],
                         AD_CHAN_MA_CLR, STYLE_SOLID, 2);
      }

      // ── v1.7.3: Hedge Smart entry channel (canale esterno dinamico) ──
      // Disegna 2 linee arancioni tratteggiate esterne al canale DPC.
      // Rappresentano i livelli a cui l'HS piazzerebbe un ordine STOP
      // se un segnale Soup fosse attivo su questa barra.
      //
      // Formula (identica a HsPlaceOrder in adHedgeManager.mqh):
      //   HU = upperBand + (channelWidth × HsTriggerPct)  → SELL Soup → BUY STOP HS
      //   HL = lowerBand - (channelWidth × HsTriggerPct)  → BUY Soup  → SELL STOP HS
      //
      // Le linee "respirano" col canale: quando cw si allarga,
      // il canale HS si espande proporzionalmente (offset = 30% di cw).
      // Controllato da input HsShowZones (stesso toggle dei vecchi rettangoli).
      if(drawHS)
      {
         double cw_i  = arrU[i] - arrL[i];
         double cw_i1 = arrU[i + 1] - arrL[i + 1];
         if(cw_i > 0 && cw_i1 > 0)
         {
            double hu_i  = arrU[i]     + cw_i  * HsTriggerPct;
            double hl_i  = arrL[i]     - cw_i  * HsTriggerPct;
            double hu_i1 = arrU[i + 1] + cw_i1 * HsTriggerPct;
            double hl_i1 = arrL[i + 1] - cw_i1 * HsTriggerPct;

            DrawOverlayLine(prefix + "HU", t2, hu_i1, t1, hu_i,
                            AD_HS_CHAN_CLR, AD_HS_CHAN_STYLE, AD_HS_CHAN_WIDTH);
            DrawOverlayLine(prefix + "HL", t2, hl_i1, t1, hl_i,
                            AD_HS_CHAN_CLR, AD_HS_CHAN_STYLE, AD_HS_CHAN_WIDTH);
         }
      }

   }

   // STEP 3: Disegna fill trasparente tra upper e lower band
   DrawBandFill(arrU, arrL, arrT, depth);

   // v1.7.3: HS entry channel disegnato inline nel loop STEP 2 (segmenti HU/HL)
}

//+------------------------------------------------------------------+
//| DrawBandFill — Fill trasparente tra le bande con CCanvas         |
//|                                                                  |
//| SCOPO: Crea un effetto di "area colorata" semi-trasparente tra   |
//|        la banda superiore e inferiore del canale Donchian.       |
//|        Usa la classe CCanvas di MQL5 per disegno bitmap.         |
//|                                                                  |
//| COME FUNZIONA:                                                   |
//|   1. Crea/ridimensiona un OBJ_BITMAP_LABEL che copre il chart    |
//|   2. Pulisce il canvas (completamente trasparente: alpha=0)      |
//|   3. Per ogni coppia di barre adiacenti, converte coordinate     |
//|      price/time in pixel X/Y con ChartTimePriceToXY()            |
//|   4. Disegna un quadrilatero riempito come 2 triangoli           |
//|   5. Il colore usa AD_CHAN_FILL_CLR con alpha AD_CHAN_FILL_ALPHA  |
//|                                                                  |
//| PROPRIETA' CANVAS:                                               |
//|   - OBJPROP_BACK=true: dietro le candele e i segmenti           |
//|   - OBJPROP_HIDDEN=true: nascosto dalla Lista Oggetti (Ctrl+B)  |
//|     (ma VISIBILE sul grafico — HIDDEN nasconde solo dalla lista) |
//|   - COLOR_FORMAT_ARGB_NORMALIZE: supporta alpha blending         |
//|                                                                  |
//| CHIAMATA DA: DrawChannelOverlay() alla fine del full redraw      |
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

   // Colore fill con trasparenza: ColorToARGB converte da BGR (MQL5) a ARGB
   // AD_CHAN_FILL_ALPHA=40 su 255 = ~16% opacita' (blu tenue)
   uint fillARGB = ColorToARGB(AD_CHAN_FILL_CLR, AD_CHAN_FILL_ALPHA);

   // Disegna un quadrilatero riempito tra ogni coppia di barre
   // Ogni quad e' scomposto in 2 triangoli per il rasterizzatore
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

      // Salta barre fuori dallo schermo (margine -200/+200 per scroll fluido)
      if(x1 < -200 || x1 > chartW + 200) continue;
      if(x2 < -200 || x2 > chartW + 200) continue;

      // Triangolo 1: angolo sup-sx, angolo sup-dx, angolo inf-sx
      g_canvasFill.FillTriangle(x1, y1U, x2, y2U, x1, y1L, fillARGB);
      // Triangolo 2: angolo sup-dx, angolo inf-dx, angolo inf-sx
      g_canvasFill.FillTriangle(x2, y2U, x2, y2L, x1, y1L, fillARGB);
   }

   // Aggiorna il bitmap senza forzare ChartRedraw (false)
   g_canvasFill.Update(false);
}

//+------------------------------------------------------------------+
//| RedrawOverlayFill — Ridisegna SOLO il canvas fill                |
//|                                                                  |
//| SCOPO: Quando l'utente scrolla, zooma o ridimensiona il chart,   |
//|        le coordinate pixel cambiano ma i prezzi no. Serve        |
//|        ridisegnare il canvas fill con le nuove coordinate pixel. |
//|        Le linee OBJ_TREND si spostano automaticamente (MT5 le    |
//|        gestisce), ma il canvas bitmap no.                        |
//|                                                                  |
//| THROTTLE: Max ~33 FPS (ogni 30ms) per evitare CPU eccessiva     |
//|           durante scroll rapido.                                 |
//|                                                                  |
//| CHIAMATA DA: OnChartEvent(CHARTEVENT_CHART_CHANGE) in           |
//|              AcquaDulza.mq5 — scroll, zoom, resize del chart    |
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
   int dcLen = (g_dpc_dcLen > 0) ? g_dpc_dcLen : 20;
   if(totalBars < dcLen + 5) return;
   depth = MathMin(depth, totalBars - 2);

   // Ricalcola solo upper/lower (non serve midline/MA per il fill)
   double arrU[], arrL[];
   datetime arrT[];
   ArrayResize(arrU, depth + 1);
   ArrayResize(arrL, depth + 1);
   ArrayResize(arrT, depth + 1);

   for(int i = 0; i <= depth && i < totalBars; i++)
   {
      int barIdx = i;
      arrT[i] = iTime(_Symbol, PERIOD_CURRENT, barIdx);
      double m;
      DPCComputeBands(barIdx, dcLen, arrU[i], arrL[i], m);
   }

   DrawBandFill(arrU, arrL, arrT, depth);
}

//+------------------------------------------------------------------+
//| UpdateChannelLiveEdge — Aggiorna SOLO il bordo live (bar[0])     |
//|                                                                  |
//| SCOPO: Funzione LEGGERA chiamata ogni 500ms per tenere           |
//|        aggiornato il segmento index=0 del canale, che collega    |
//|        bar[1] (confermata) a bar[0] (candela corrente in         |
//|        formazione). Aggiorna le coordinate del punto destro      |
//|        (bar[0]) di tutti i 6 segmenti:                           |
//|          U  = Upper band                                         |
//|          L  = Lower band                                         |
//|          M  = Midline (+ colore dinamico bull/bear/flat)         |
//|          A  = MA filter line                                     |
//|          HU = HS entry channel upper (se hedge attivo)           |
//|          HL = HS entry channel lower (se hedge attivo)           |
//|                                                                  |
//| PERCHE' SERVE:                                                   |
//|   Tra una barra e l'altra, il prezzo cambia ma la barra[0]      |
//|   e' ancora in formazione. Senza questo update, il bordo destro  |
//|   del canale resterebbe fermo fino alla prossima barra.          |
//|                                                                  |
//| COSTO: ~12 chiamate ObjectSet + 1 DPCComputeBands + 1 MA read   |
//|        (vs ~15,000 del full DrawChannelOverlay)                  |
//|                                                                  |
//| CONVENTION PUNTI OBJ_TREND:                                      |
//|   Punto 0 (OBJPROP_TIME/PRICE 0) = bar[1] (estremo sinistro)    |
//|   Punto 1 (OBJPROP_TIME/PRICE 1) = bar[0] (estremo destro)      |
//|   Aggiorniamo SOLO il punto 1 (bar[0]) qui.                     |
//|                                                                  |
//| CHIAMATA DA:                                                     |
//|   - OnTick() ogni 500ms (blocco dashboard throttle)              |
//|   - OnChartEvent(CHARTEVENT_CHART_CHANGE) su scroll/zoom        |
//+------------------------------------------------------------------+
void UpdateChannelLiveEdge()
{
   if(!ShowChannelOverlay) return;
   if(OverlayDepth <= 0) return;

   int dcLen = (g_dpc_dcLen > 0) ? g_dpc_dcLen : 20;
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars < dcLen + 5) return;

   // Calcola bande per bar[0] — costo minimo: 1x iHighest + 1x iLowest
   double upper0, lower0, mid0;
   DPCComputeBands(0, dcLen, upper0, lower0, mid0);
   if(upper0 <= 0 || lower0 <= 0 || mid0 <= 0) return;

   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   string prefix = "AD_OVL_0_";

   // Aggiorna banda superiore — solo il punto 1 (bar[0], estremo destro)
   string nameU = prefix + "U";
   if(ObjectFind(0, nameU) >= 0)
   {
      ObjectSetInteger(0, nameU, OBJPROP_TIME, 1, t0);
      ObjectSetDouble(0, nameU, OBJPROP_PRICE, 1, upper0);
   }

   // Aggiorna banda inferiore
   string nameL = prefix + "L";
   if(ObjectFind(0, nameL) >= 0)
   {
      ObjectSetInteger(0, nameL, OBJPROP_TIME, 1, t0);
      ObjectSetDouble(0, nameL, OBJPROP_PRICE, 1, lower0);
   }

   // Aggiorna midline + colore dinamico bull/bear/flat
   string nameM = prefix + "M";
   if(ObjectFind(0, nameM) >= 0)
   {
      ObjectSetInteger(0, nameM, OBJPROP_TIME, 1, t0);
      ObjectSetDouble(0, nameM, OBJPROP_PRICE, 1, mid0);
      // Colore midline: confronta mid[0] vs mid[2] per determinare trend
      int midState = DPCGetMidlineColor(0);
      color midClr = AD_CHAN_MID_FLAT_CLR;
      if(midState == 0) midClr = AD_CHAN_MID_UP_CLR;
      else if(midState == 1) midClr = AD_CHAN_MID_DN_CLR;
      ObjectSetInteger(0, nameM, OBJPROP_COLOR, midClr);
   }

   // Aggiorna MA filter line (solo se valore valido)
   double ma0 = DPCGetMAValue(0);
   if(ma0 > 0)
   {
      string nameA = prefix + "A";
      if(ObjectFind(0, nameA) >= 0)
      {
         ObjectSetInteger(0, nameA, OBJPROP_TIME, 1, t0);
         ObjectSetDouble(0, nameA, OBJPROP_PRICE, 1, ma0);
      }
   }

   // ── v1.7.3: HS entry channel — aggiorna live edge segmento 0 HU/HL ──
   // Stesso calcolo del full redraw: banda ± (cw × HsTriggerPct)
   // Aggiorna solo il punto destro (bar[0]) per seguire la barra in formazione
   if(EnableHedge && HsEnabled && HsShowZones)
   {
      double cw0 = upper0 - lower0;
      if(cw0 > 0)
      {
         double hu0 = upper0 + cw0 * HsTriggerPct;
         double hl0 = lower0 - cw0 * HsTriggerPct;

         string nameHU = prefix + "HU";
         if(ObjectFind(0, nameHU) >= 0)
         {
            ObjectSetInteger(0, nameHU, OBJPROP_TIME, 1, t0);
            ObjectSetDouble(0, nameHU, OBJPROP_PRICE, 1, hu0);
         }
         string nameHL = prefix + "HL";
         if(ObjectFind(0, nameHL) >= 0)
         {
            ObjectSetInteger(0, nameHL, OBJPROP_TIME, 1, t0);
            ObjectSetDouble(0, nameHL, OBJPROP_PRICE, 1, hl0);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DrawOverlayLine — Crea o aggiorna un segmento OBJ_TREND         |
//|                    (versione STATICA — colore fisso)              |
//|                                                                  |
//| SCOPO: Gestisce un singolo segmento di linea del canale.         |
//|        PRIMA CHIAMATA: crea l'oggetto con TUTTE le proprietà     |
//|          (coordinate + colore + stile + spessore + flags).       |
//|        CHIAMATE SUCCESSIVE: aggiorna SOLO le 4 coordinate        |
//|          (time/price × 2 punti). Colore/stile/spessore restano   |
//|          quelli impostati alla creazione.                        |
//|                                                                  |
//| USATA PER: U (upper), L (lower), A (MA filter),                 |
//|            HU (HS upper), HL (HS lower)                          |
//|            — tutti segmenti a colore fisso.                      |
//|                                                                  |
//| NON usare per la Midline (M) che cambia colore ogni barra       |
//|   → usare DrawOverlayLineDynColor() per quella.                  |
//|                                                                  |
//| PROPRIETA' SETTATE ALLA CREAZIONE:                               |
//|   - RAY_LEFT/RIGHT = false: segmento finito, non esteso         |
//|   - SELECTABLE = false: non selezionabile dall'utente            |
//|   - HIDDEN = true: nascosto dalla Lista Oggetti (Ctrl+B)        |
//|     NOTA: HIDDEN non rende l'oggetto invisibile sul grafico!     |
//|     Serve solo a non intasare la finestra Lista Oggetti.         |
//|   - BACK = true: disegnato dietro le candele                     |
//|   - ZORDER = 50: priorita' rendering sopra il canvas fill       |
//|   - COLOR, STYLE, WIDTH: impostati UNA SOLA VOLTA               |
//|                                                                  |
//| v1.7.3 OPT: Risparmio ~7,500 ObjectSet per redraw               |
//|   (5 tipi × 500 segmenti × 3 proprietà statiche skippate)       |
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
//| Come DrawOverlayLine(), ma aggiorna anche il COLORE ad ogni      |
//| chiamata (non solo le coordinate). Stile e spessore restano      |
//| statici (impostati solo alla creazione).                         |
//|                                                                  |
//| USATA SOLO PER: M (Midline) — cambia colore ogni barra:         |
//|   lime = bullish (midline sale rispetto a 2 barre fa)            |
//|   red  = bearish (midline scende)                                |
//|   cyan = flat (midline stabile entro 2×g_pipSize)                |
//|                                                                  |
//| Costo extra vs DrawOverlayLine: +1 ObjectSet (OBJPROP_COLOR)     |
//|   per segmento × 500 = +500 chiamate. Accettabile per 1 tipo.   |
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
//|                                                                  |
//| SCOPO: Quando viene aperto un ciclo di trading, disegna una      |
//|        linea orizzontale tratteggiata al livello del TP target.  |
//|        Colore lime per BUY, rosso per SELL.                      |
//|                                                                  |
//| CHIAMATA DA: OnTick() in AcquaDulza.mq5 quando un nuovo ciclo   |
//|              viene creato (riga ~429-430)                        |
//+------------------------------------------------------------------+
void DrawTPLine(int cycleID, double tpPrice, bool isBuy)
{
   if(!ShowTPTargetLines) return;

   string lineName = StringFormat("AD_TP_LINE_%d", cycleID);
   color tpClr = isBuy ? AD_TP_DOT_BUY : AD_TP_DOT_SELL;
   CreateHLine(lineName, tpPrice, tpClr, AD_TP_LINE_WIDTH, STYLE_DASH);
   ObjectSetString(0, lineName, OBJPROP_TOOLTIP,
       StringFormat("TP #%d %s @ %s", cycleID, isBuy ? "BUY" : "SELL",
                    DoubleToString(tpPrice, _Digits)));
}

//+------------------------------------------------------------------+
//| DrawTPDot — Cerchietto al livello del TP                         |
//|                                                                  |
//| SCOPO: Disegna un pallino (arrow code 159 = cerchio pieno)       |
//|        al prezzo TP sulla candela del segnale. Serve come        |
//|        indicatore visivo del target previsto.                    |
//|                                                                  |
//| PROPRIETA':                                                      |
//|   - BACK=false: disegnato SOPRA le candele (ben visibile)        |
//|   - HIDDEN=true: nascosto dalla Lista Oggetti                    |
//+------------------------------------------------------------------+
void DrawTPDot(int cycleID, double tpPrice, datetime signalTime, bool isBuy)
{
   if(!ShowTPTargetLines) return;

   string name = StringFormat("AD_TP_DOT_%d", cycleID);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, signalTime, tpPrice);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);  // Cerchio pieno
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? AD_TP_DOT_BUY : AD_TP_DOT_SELL);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);     // Davanti alle candele
}

//+------------------------------------------------------------------+
//| DrawTPAsterisk — Asterisco giallo al livello TP su ogni trigger  |
//|                                                                  |
//| SCOPO: Ogni volta che l'engine genera un segnale (trigger),      |
//|        disegna un asterisco giallo (★ arrow code 171) al prezzo  |
//|        TP previsto sulla candela del segnale. Visibile anche     |
//|        se l'ordine non viene piazzato (es. filtro attivo).       |
//|        Permette all'utente di vedere dove punta il TP di ogni    |
//|        segnale generato dall'engine.                             |
//|                                                                  |
//| CHIAMATA DA: AcquaDulza.mq5 OnTick() subito dopo DrawSignalMarkers |
//+------------------------------------------------------------------+
void DrawTPAsterisk(double tpPrice, datetime signalTime, bool isBuy)
{
   // Usa timestamp + direzione per nome univoco (un asterisco per segnale)
   string name = StringFormat("AD_TP_STAR_%s_%s",
      isBuy ? "B" : "S",
      TimeToString(signalTime, TIME_DATE|TIME_MINUTES));

   if(ObjectFind(0, name) >= 0) return;  // Già disegnato per questo segnale

   ObjectCreate(0, name, OBJ_ARROW, 0, signalTime, tpPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 171);  // Asterisco (★)
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow); // Giallo fisso
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);      // Davanti alle candele

   // Tooltip informativo: mostra direzione, prezzo TP e modalità
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
      StringFormat("TP Target %s @ %s [%s]",
         isBuy ? "BUY" : "SELL",
         DoubleToString(tpPrice, _Digits),
         EnumToString(TPMode)));
}

//+------------------------------------------------------------------+
//| DrawTPHitMarker — Stella quando il TP viene raggiunto            |
//|                                                                  |
//| SCOPO: Quando un ciclo raggiunge il TP target, disegna una       |
//|        stella gialla (arrow code 169) al prezzo/tempo dell'hit.  |
//|        Feedback visivo immediato per l'utente.                   |
//|                                                                  |
//| CHIAMATA DA: MonitorCycles() quando rileva TP hit                |
//+------------------------------------------------------------------+
void DrawTPHitMarker(int cycleID, double tpPrice, datetime hitTime)
{
   string name = StringFormat("AD_TP_HIT_%d", cycleID);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, hitTime, tpPrice);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 169);  // Stella
   ObjectSetInteger(0, name, OBJPROP_COLOR, AD_TP_HIT_CLR);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| RemoveTPLine — Rimuove linea TP + pallino alla chiusura ciclo    |
//|                                                                  |
//| SCOPO: Quando un ciclo di trading viene chiuso (TP hit, SL hit,  |
//|        o chiusura manuale), rimuove la linea orizzontale TP e    |
//|        il pallino associato per pulire il grafico.               |
//|                                                                  |
//| CHIAMATA DA: MonitorCycles() quando un ciclo si chiude           |
//+------------------------------------------------------------------+
void RemoveTPLine(int cycleID)
{
   string lineName = StringFormat("AD_TP_LINE_%d", cycleID);
   if(ObjectFind(0, lineName) >= 0) ObjectDelete(0, lineName);

   string dotName = StringFormat("AD_TP_DOT_%d", cycleID);
   if(ObjectFind(0, dotName) >= 0) ObjectDelete(0, dotName);
}

//+------------------------------------------------------------------+
//| CleanupOverlay — Rimuove TUTTI gli oggetti overlay + canvas      |
//|                                                                  |
//| SCOPO: Pulizia completa di tutti gli oggetti grafici creati da   |
//|        questo modulo. Chiamata in OnDeinit() quando l'EA viene   |
//|        rimosso o quando cambia timeframe.                        |
//|                                                                  |
//| OGGETTI RIMOSSI:                                                 |
//|   - "AD_OVL_*": tutti i segmenti canale + canvas                |
//|   - "AD_TP_*": linee e pallini TP                                |
//|   - "AD_TRIG_VL_*": VLine trigger                                |
//|   - CCanvas: distrutto esplicitamente per liberare memoria       |
//|                                                                  |
//| CHIAMATA DA: OnDeinit() in AcquaDulza.mq5                       |
//+------------------------------------------------------------------+
void CleanupOverlay()
{
   ObjectsDeleteAll(0, "AD_OVL_");     // Segmenti canale + canvas
   ObjectsDeleteAll(0, "AD_TP_");      // Linee e dot TP
   ObjectsDeleteAll(0, "AD_TRIG_VL_"); // VLine trigger
   if(g_canvasCreated)
   {
      g_canvasFill.Destroy();           // Libera memoria bitmap
      g_canvasCreated = false;
   }
   g_ovlLastDepth = 0;                 // Reset contatore profondita'
}
