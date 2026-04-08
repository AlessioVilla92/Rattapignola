//+------------------------------------------------------------------+
//| SqueezeMomentum_LB.mq5                                           |
//| Squeeze Momentum Indicator [LazyBear] — Porting MQL5            |
//| Con Opzione C: Peak Detector Persistente per half-peak exit      |
//| Ecosistema AcquaDulza — v1.00                                    |
//+------------------------------------------------------------------+
//|                                                                  |
//| ORIGINE: Pine Script "Squeeze Momentum Indicator [LazyBear]"     |
//| Autore originale: LazyBear (TradingView)                         |
//| Porting MQL5 + Opzione C: AcquaDulza ecosystem                   |
//|                                                                  |
//| PRINCIPIO OPERATIVO:                                             |
//| 1. Rileva la compressione di volatilita (BB dentro KC = sqzOn)   |
//| 2. Calcola il momentum via regressione lineare del delta         |
//|    (distanza del close dal midpoint del canale KC/Donchian)      |
//| 3. Opzione C: traccia il PEAK dell'istogramma in modo            |
//|    persistente e monotono (sale ma non scende mai nello swing)   |
//| 4. Genera B_ExitLong / B_ExitShort quando il valore scende       |
//|    sotto InpHalfPeakRatio * peak (default: 50% del picco)        |
//|                                                                  |
//| BUFFER ESPOSTI PER EA ESTERNI:                                   |
//|   Buffer 0: B_Val       — valore istogramma (linreg delta)       |
//|   Buffer 5: B_Peak      — peak persistente corrente              |
//|             (>0 = swing positivo, <0 = swing negativo/trough)    |
//|   Buffer 6: B_SqzState  — 1.0=sqzOn / 0.0=sqzOff / -1.0=noSqz  |
//|   Buffer 7: B_ExitLong  — 1.0 quando half-peak exit long attivo  |
//|   Buffer 8: B_ExitShort — 1.0 quando half-peak exit short attivo |
//|                                                                  |
//| BUFFER VISIVI (sub-window):                                      |
//|   Plot 0: Istogramma colorato (lime/green/red/maroon)            |
//|   Plot 1: Dot squeeze (nero=ON / grigio=OFF / blu=noSqz)         |
//|   Plot 2: Linea soglia half-peak (arancione tratteggiata)        |
//|                                                                  |
//| ANTI-REPAINTING:                                                 |
//|   B_ExitLong e B_ExitShort vengono scritti solo su barre         |
//|   confermate (i < rates_total - 1). Sulla barra corrente         |
//|   (aperta) i valori sono ereditati dalla barra precedente.       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright   "AcquaDulza ecosystem — porting da LazyBear Pine Script"
#property version     "1.00"
#property description "Squeeze Momentum [LazyBear] + Opzione C Peak Detector"
#property description "Buffer 0=val, 5=peak, 6=sqzState, 7=exitLong, 8=exitShort"
#property indicator_separate_window
#property indicator_buffers 9
#property indicator_plots   3

//--- Plot 0: Istogramma colorato — 4 colori (fedele al Pine originale)
//    Indice 0: lime   C'0,255,0'     val > 0 e crescente (positivo accelerante)
//    Indice 1: green  C'0,128,0'     val > 0 e decrescente (positivo frenante)
//    Indice 2: red    C'255,0,0'     val < 0 e decrescente (negativo accelerante)
//    Indice 3: maroon C'128,0,0'     val < 0 e crescente (negativo frenante)
#property indicator_label1  "SQZ Momentum"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  C'0,255,0', C'0,128,0', C'255,0,0', C'128,0,0'
#property indicator_width1  4

//--- Plot 1: Dot squeeze — cerchio sulla zero line
//    Indice 0: nero  C'30,30,30'    sqzOn  (BB dentro KC, alta compressione)
//    Indice 1: grigio C'150,150,150' sqzOff (BB fuori KC, compressione rilasciata)
//    Indice 2: blu   C'0,100,255'   noSqz  (ne ON ne OFF, stato intermedio)
#property indicator_label2  "Squeeze State"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_color2  C'30,30,30', C'150,150,150', C'0,100,255'
#property indicator_width2  2

//--- Plot 2: Linea soglia half-peak — arancione tratteggiata
//    Mostra il livello InpHalfPeakRatio * peak in tempo reale.
//    Quando l'istogramma tocca questa linea scatta l'exit signal.
//    EMPTY_VALUE quando non siamo in uno swing attivo.
#property indicator_label3  "Half-Peak Threshold"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'255,140,0'
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "╔═══════════════════════════════════════════════════════╗"
input group "║  SQUEEZE MOMENTUM [LazyBear]                        ║"
input group "╚═══════════════════════════════════════════════════════╝"

input int    InpBBLength    = 20;    // BB Length (lunghezza Bollinger Bands)
input double InpBBMult      = 2.0;   // BB MultFactor (moltiplicatore deviazione std)
input int    InpKCLength    = 20;    // KC Length (lunghezza Keltner Channel)
input double InpKCMult      = 1.5;   // KC MultFactor (moltiplicatore range KC)
input bool   InpUseTrueRange = true; // Usa True Range per KC (raccomandato)

input group "╔═══════════════════════════════════════════════════════╗"
input group "║  OPZIONE C — PEAK DETECTOR                          ║"
input group "╚═══════════════════════════════════════════════════════╝"

input double InpHalfPeakRatio = 0.50; // Soglia half-peak (0.50 = 50% del picco)
//                                    // Range ottimizzazione: 0.30 - 0.70, step 0.05
//                                    // XAUUSD M5: 0.40-0.55
//                                    // NAS100 M5: 0.35-0.45
//                                    // EURUSD M5: 0.25-0.35 (mercato + ranging)

input group "╔═══════════════════════════════════════════════════════╗"
input group "║  ALERT                                              ║"
input group "╚═══════════════════════════════════════════════════════╝"

input bool   InpAlertPopup  = false;  // Alert popup su half-peak exit
input bool   InpAlertPush   = false;  // Notifica push su half-peak exit

//+------------------------------------------------------------------+
//| DICHIARAZIONE BUFFER (9 buffer totali)                           |
//+------------------------------------------------------------------+
//--- Visivi (5 buffer per 3 plot)
double B_Val[];       // buffer 0: valore istogramma (linreg delta)
double B_ValClr[];    // buffer 1: indice colore istogramma (0-3)
double B_Dot[];       // buffer 2: dot squeeze (sempre 0.0)
double B_DotClr[];    // buffer 3: indice colore dot (0=nero/1=grigio/2=blu)
double B_HPLine[];    // buffer 4: linea soglia half-peak

//--- Calcolo (4 buffer — accessibili da EA via CopyBuffer)
double B_Peak[];      // buffer 5: peak corrente (>0 long / <0 short)
double B_SqzState[];  // buffer 6: stato squeeze (1.0/0.0/-1.0)
double B_ExitLong[];  // buffer 7: 1.0 = exit long attivo su barra chiusa
double B_ExitShort[]; // buffer 8: 1.0 = exit short attivo su barra chiusa

//+------------------------------------------------------------------+
//| VARIABILI GLOBALI                                                |
//+------------------------------------------------------------------+
int    g_warmup;           // Barre di warmup prima del primo calcolo valido
datetime g_lastAlert;      // Timestamp ultimo alert (deduplicazione)

//--- Stato Opzione C (persistente tra chiamate OnCalculate)
//    Vengono ripristinati da B_Peak e B_Val alla ripresa incrementale.
double g_peak_long    = 0.0;   // Peak corrente dello swing positivo
double g_trough_short = 0.0;   // Trough corrente dello swing negativo (valore assoluto)
bool   g_in_pos_swing = false; // Siamo in uno swing positivo?
bool   g_in_neg_swing = false; // Siamo in uno swing negativo?

//--- Array interno per il calcolo del delta (sorgente della linreg)
double g_delta[];

//+------------------------------------------------------------------+
//| LinRegValue — Regressione lineare su array custom               |
//+------------------------------------------------------------------+
// Equivalente esatto di Pine Script: linreg(src, len, 0)
// Ritorna il valore della retta di regressione al punto piu' recente
// (offset=0) fittata sugli ultimi len valori di src fino all'indice idx.
//
// Derivazione:
//   x = 0 (piu' recente) .. len-1 (piu' vecchio)
//   slope = (n*Σxy - Σx*Σy) / (n*Σxx - Σx*Σx)
//   intercept = (Σy - slope*Σx) / n
//   linreg al punto x=0: valore = intercept
//
double LinRegValue(const double &src[], int idx, int len)
  {
   if(idx < len - 1)
      return src[idx];  // Dati insufficienti: restituisce il valore grezzo

   double sum_x  = 0.0;
   double sum_y  = 0.0;
   double sum_xy = 0.0;
   double sum_xx = 0.0;
   double n      = (double)len;

   for(int k = 0; k < len; k++)
     {
      double x   = (double)k;   // k=0: piu' recente, k=len-1: piu' vecchio
      double y   = src[idx - k];
      sum_x  += x;
      sum_y  += y;
      sum_xy += x * y;
      sum_xx += x * x;
     }

   double denom = n * sum_xx - sum_x * sum_x;
   if(MathAbs(denom) < 1e-14)
      return sum_y / n;  // Caso degenere: tutti i valori identici

   double slope     = (n * sum_xy - sum_x * sum_y) / denom;
   double intercept = (sum_y - slope * sum_x) / n;

   return intercept;  // Valore alla posizione x=0 (barra corrente)
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Binding buffer → plot
   SetIndexBuffer(0, B_Val,      INDICATOR_DATA);
   SetIndexBuffer(1, B_ValClr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, B_Dot,      INDICATOR_DATA);
   SetIndexBuffer(3, B_DotClr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, B_HPLine,   INDICATOR_DATA);
   SetIndexBuffer(5, B_Peak,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, B_SqzState, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, B_ExitLong, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, B_ExitShort,INDICATOR_CALCULATIONS);

   //--- Codice freccia per il dot squeeze (cerchio pieno piccolo)
   PlotIndexSetInteger(1, PLOT_ARROW, 159);

   //--- Empty values
   //    B_Val (buffer 0): usa 0.0 come empty — NON settare PLOT_EMPTY_VALUE a 0
   //    altrimenti le barre a valore zero spariscono. Usiamo il default (EMPTY_VALUE).
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Warmup: massimo tra BB period e KC period + 1 per True Range + margine
   //    La linreg richiede lengthKC barre.
   //    Il True Range richiede close[i-1], quindi +1 barra.
   //    Margine di sicurezza: +5 barre.
   g_warmup = MathMax(InpBBLength, InpKCLength) + InpKCLength + 6;

   //--- Short name dinamico
   IndicatorSetString(INDICATOR_SHORTNAME,
      "SQZMOM_LB[" + IntegerToString(InpKCLength) + "," +
      DoubleToString(InpHalfPeakRatio, 2) + "]");

   //--- Reset stato Opzione C
   g_peak_long    = 0.0;
   g_trough_short = 0.0;
   g_in_pos_swing = false;
   g_in_neg_swing = false;
   g_lastAlert    = 0;

   Print("[SQZMOM v1.00] BB(", InpBBLength, ",", InpBBMult, ")",
         " KC(", InpKCLength, ",", InpKCMult, ",TR=", InpUseTrueRange, ")",
         " HalfPeak=", DoubleToString(InpHalfPeakRatio, 2),
         " Warmup=", g_warmup);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnCalculate — Calcolo principale                                 |
//+------------------------------------------------------------------+
// STEP 1: Calcolo BB (Bollinger Bands)
// STEP 2: Calcolo KC (Keltner Channel)
// STEP 3: Rilevamento stato squeeze (sqzOn / sqzOff / noSqz)
// STEP 4: Calcolo delta e linreg → B_Val
// STEP 5: Colorazione istogramma (4 colori LazyBear)
// STEP 6: Opzione C — Peak Detector persistente
// STEP 7: Segnali half-peak exit (anti-repainting su barre chiuse)
// STEP 8: Alert deduplicati
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < g_warmup + 2)
      return 0;

   //--- Ridimensiona array interno delta
   if(ArraySize(g_delta) != rates_total)
      ArrayResize(g_delta, rates_total, 0);

   bool fullRecalc = (prev_calculated < g_warmup + 2);
   int  start      = fullRecalc ? g_warmup : prev_calculated - 1;

   //--- Ripristino stato Opzione C in modalita' incrementale
   //    Legge il peak dallo stato salvato nella barra precedente.
   //    B_Peak[start-1] > 0 → eravamo in swing positivo → ripristina peak_long
   //    B_Peak[start-1] < 0 → eravamo in swing negativo → ripristina trough_short
   //    B_Peak[start-1] == 0 → nessuno swing attivo
   if(!fullRecalc && start > 0)
     {
      double prev_val  = B_Val[start - 1];
      double prev_peak = B_Peak[start - 1];

      if(prev_val > 0.0)
        {
         g_in_pos_swing = true;
         g_in_neg_swing = false;
         g_peak_long    = (prev_peak > 0.0) ? prev_peak : prev_val;
         g_trough_short = 0.0;
        }
      else if(prev_val < 0.0)
        {
         g_in_pos_swing = false;
         g_in_neg_swing = true;
         g_peak_long    = 0.0;
         g_trough_short = (prev_peak < 0.0) ? MathAbs(prev_peak) : MathAbs(prev_val);
        }
      else
        {
         g_in_pos_swing = false;
         g_in_neg_swing = false;
         g_peak_long    = 0.0;
         g_trough_short = 0.0;
        }
     }
   else if(fullRecalc)
     {
      //--- Reset completo stato Opzione C
      g_peak_long    = 0.0;
      g_trough_short = 0.0;
      g_in_pos_swing = false;
      g_in_neg_swing = false;
     }

   //--- Pre-fill g_delta per lookback linreg (solo su full recalc)
   //    Senza questo, LinRegValue alle prime barre dopo warmup legge
   //    g_delta[warmup-KCLength..warmup-1] = 0.0 (non calcolati).
   if(fullRecalc)
     {
      int delta_start = InpKCLength;  // primo indice con abbastanza dati
      for(int j = delta_start; j < start; j++)
        {
         double hi_max_j = high[j];
         double lo_min_j = low[j];
         double dc_sum_j = 0.0;
         for(int k = 0; k < InpKCLength; k++)
           {
            if(high[j - k] > hi_max_j) hi_max_j = high[j - k];
            if(low[j - k]  < lo_min_j) lo_min_j = low[j - k];
            dc_sum_j += close[j - k];
           }
         g_delta[j] = close[j] - ((hi_max_j + lo_min_j) / 2.0 + dc_sum_j / InpKCLength) / 2.0;
        }
     }

   //=== LOOP PRINCIPALE ===
   for(int i = start; i < rates_total; i++)
     {
      //--- Verifica che ci siano abbastanza barre precedenti per il TR
      if(i < 1)
        {
         B_Val[i]      = 0.0;
         B_ValClr[i]   = 3.0;
         B_Dot[i]      = EMPTY_VALUE;
         B_HPLine[i]   = EMPTY_VALUE;
         B_Peak[i]     = 0.0;
         B_SqzState[i] = -1.0;
         B_ExitLong[i] = 0.0;
         B_ExitShort[i]= 0.0;
         continue;
        }

      //=== STEP 1: Bollinger Bands ===
      //    basis = SMA(close, BBLength)
      //    dev   = BBMult * StdDev(close, BBLength)
      double bb_sum = 0.0;
      for(int k = 0; k < InpBBLength; k++)
         bb_sum += close[i - k];
      double bb_basis = bb_sum / InpBBLength;

      double bb_sq_sum = 0.0;
      for(int k = 0; k < InpBBLength; k++)
        {
         double diff = close[i - k] - bb_basis;
         bb_sq_sum += diff * diff;
        }
      double bb_dev    = InpBBMult * MathSqrt(bb_sq_sum / InpBBLength);
      double upperBB   = bb_basis + bb_dev;
      double lowerBB   = bb_basis - bb_dev;

      //=== STEP 2: Keltner Channel ===
      //    ma      = SMA(close, KCLength)
      //    rangema = SMA(TrueRange, KCLength)   se InpUseTrueRange
      //    rangema = SMA(High-Low, KCLength)    altrimenti
      double kc_sum = 0.0;
      for(int k = 0; k < InpKCLength; k++)
         kc_sum += close[i - k];
      double kc_ma = kc_sum / InpKCLength;

      double range_sum = 0.0;
      for(int k = 0; k < InpKCLength; k++)
        {
         double rng;
         if(InpUseTrueRange && (i - k) > 0)
            rng = MathMax(high[i - k], close[i - k - 1]) -
                  MathMin(low[i - k],  close[i - k - 1]);
         else
            rng = high[i - k] - low[i - k];
         range_sum += rng;
        }
      double rangema = range_sum / InpKCLength;

      double upperKC = kc_ma + rangema * InpKCMult;
      double lowerKC = kc_ma - rangema * InpKCMult;

      //=== STEP 3: Stato squeeze ===
      //    sqzOn  = BB completamente dentro KC (massima compressione)
      //    sqzOff = BB completamente fuori KC (compressione rilasciata)
      //    noSqz  = stato intermedio
      bool sqzOn  = (lowerBB > lowerKC) && (upperBB < upperKC);
      bool sqzOff = (lowerBB < lowerKC) && (upperBB > upperKC);
      bool noSqz  = !sqzOn && !sqzOff;

      B_SqzState[i] = sqzOn ? 1.0 : (sqzOff ? 0.0 : -1.0);

      //--- Dot squeeze (cerchio colorato sulla zero line)
      B_Dot[i]    = 0.0;  // Sempre sulla zero line
      B_DotClr[i] = noSqz ? 2.0 : (sqzOn ? 0.0 : 1.0);

      //=== STEP 4: Delta e linreg ===
      //    delta[i] = close[i] - midpoint[i]
      //    midpoint = avg(avg(highest(high,KCLength), lowest(low,KCLength)),
      //                   sma(close,KCLength))
      //    val = linreg(delta, KCLength, 0)
      double hi_max = high[i];
      double lo_min = low[i];
      double dc_sum = 0.0;
      for(int k = 0; k < InpKCLength; k++)
        {
         if(high[i - k] > hi_max) hi_max = high[i - k];
         if(low[i - k]  < lo_min) lo_min = low[i - k];
         dc_sum += close[i - k];
        }
      double dc_mid  = (hi_max + lo_min) / 2.0;
      double kc_sma  = dc_sum / InpKCLength;
      double midpoint = (dc_mid + kc_sma) / 2.0;

      g_delta[i] = close[i] - midpoint;

      //--- Linreg del delta su KCLength barre
      double val = (i >= InpKCLength - 1) ?
                   LinRegValue(g_delta, i, InpKCLength) :
                   g_delta[i];

      B_Val[i] = val;

      //=== STEP 5: Colorazione istogramma (fedele a LazyBear) ===
      //    val > 0 e crescente → lime  (indice 0)
      //    val > 0 e frenante  → green (indice 1)
      //    val < 0 e frenante  → red   (indice 2)
      //    val < 0 e crescente → maroon(indice 3)
      double val_prev = (i > 0) ? B_Val[i - 1] : 0.0;
      int bcolor;
      if(val > 0.0)
         bcolor = (val > val_prev) ? 0 : 1;   // lime o green
      else
         bcolor = (val < val_prev) ? 2 : 3;   // red o maroon
      B_ValClr[i] = (double)bcolor;

      //=== STEP 6: OPZIONE C — Peak Detector Persistente ===
      //
      //    REGOLA FONDAMENTALE: il peak puo' SOLO salire, mai scendere.
      //    Il reset avviene SOLO al zero-crossing (cambio di swing).
      //
      //    Zero-crossing POSITIVO (inizio swing long):
      //      val_prev <= 0 e val_curr > 0 → reset peak_long = val_curr
      //    Zero-crossing NEGATIVO (inizio swing short):
      //      val_prev >= 0 e val_curr < 0 → reset trough_short = |val_curr|
      //    Aggiornamento monotono (dentro lo swing attivo):
      //      peak_long  = max(peak_long, val_curr)   se val > 0
      //      trough_short = max(trough, |val_curr|)  se val < 0
      //
      if(val > 0.0 && val_prev <= 0.0)
        {
         //--- Inizio swing positivo
         g_peak_long    = val;
         g_in_pos_swing = true;
         g_in_neg_swing = false;
         g_trough_short = 0.0;
        }
      else if(val < 0.0 && val_prev >= 0.0)
        {
         //--- Inizio swing negativo
         g_trough_short = MathAbs(val);
         g_in_neg_swing = true;
         g_in_pos_swing = false;
         g_peak_long    = 0.0;
        }

      //--- Aggiornamento monotono (solo crescita, mai discesa)
      if(g_in_pos_swing && val > 0.0 && val > g_peak_long)
         g_peak_long = val;
      if(g_in_neg_swing && val < 0.0 && MathAbs(val) > g_trough_short)
         g_trough_short = MathAbs(val);

      //--- Salva peak nel buffer (per ripristino in modalita' incrementale)
      //    Convenzione: >0 = peak swing positivo, <0 = -trough swing negativo
      if(g_in_pos_swing)
         B_Peak[i] = g_peak_long;
      else if(g_in_neg_swing)
         B_Peak[i] = -g_trough_short;
      else
         B_Peak[i] = 0.0;

      //--- Linea soglia half-peak (visiva nel sub-window)
      //    Positivo: mostra peak * ratio  (linea orizzontale arancione)
      //    Negativo: mostra -trough * ratio (linea speculare sotto zero)
      //    Fuori swing: EMPTY_VALUE (linea non visualizzata)
      if(g_in_pos_swing && g_peak_long > 0.0)
         B_HPLine[i] = g_peak_long * InpHalfPeakRatio;
      else if(g_in_neg_swing && g_trough_short > 0.0)
         B_HPLine[i] = -g_trough_short * InpHalfPeakRatio;
      else
         B_HPLine[i] = EMPTY_VALUE;

      //=== STEP 7: Segnali exit half-peak (ANTI-REPAINTING) ===
      //    Scritti SOLO su barre CHIUSE (i < rates_total - 1).
      //    Sulla barra corrente (aperta): eredita dalla barra precedente.
      //
      //    CONDIZIONE EXIT LONG:
      //      - Siamo in swing positivo (in_pos_swing)
      //      - val e' ancora positivo (non ha ancora attraversato lo zero)
      //      - val < peak * ratio (ha perso almeno (1-ratio)% del picco)
      //      - peak > 0 (il peak e' stato stabilito)
      //
      //    CONDIZIONE EXIT SHORT:
      //      Speculare: swing negativo, |val| < trough * ratio
      //
      if(i < rates_total - 1)
        {
         bool condLong  = g_in_pos_swing
                       && val > 0.0
                       && g_peak_long > 0.0
                       && val < (g_peak_long * InpHalfPeakRatio);

         bool condShort = g_in_neg_swing
                       && val < 0.0
                       && g_trough_short > 0.0
                       && MathAbs(val) < (g_trough_short * InpHalfPeakRatio);

         B_ExitLong[i]  = condLong  ? 1.0 : 0.0;
         B_ExitShort[i] = condShort ? 1.0 : 0.0;
        }
      else
        {
         //--- Barra corrente (aperta): eredita dalla barra precedente
         B_ExitLong[i]  = (i > 0) ? B_ExitLong[i - 1]  : 0.0;
         B_ExitShort[i] = (i > 0) ? B_ExitShort[i - 1] : 0.0;
        }
     }  // fine loop

   //=== STEP 8: Alert deduplicati (solo su barre chiuse) ===
   if(prev_calculated > 0 && rates_total >= 2)
     {
      int last = rates_total - 2;  // Ultima barra CHIUSA

      if(time[last] != g_lastAlert)
        {
         bool newExitLong  = (B_ExitLong[last]  == 1.0 && last > 0 && B_ExitLong[last - 1]  == 0.0);
         bool newExitShort = (B_ExitShort[last] == 1.0 && last > 0 && B_ExitShort[last - 1] == 0.0);

         if(newExitLong || newExitShort)
           {
            string dir = newExitLong ? "EXIT LONG ▼" : "EXIT SHORT ▲";
            string msg = "SQZMOM Half-Peak — " + dir +
                         "  " + _Symbol +
                         " " + EnumToString((ENUM_TIMEFRAMES)Period()) +
                         " | Peak=" + DoubleToString(MathAbs(B_Peak[last]), 5) +
                         " | Val=" + DoubleToString(B_Val[last], 5);
            if(InpAlertPopup)
               Alert(msg);
            if(InpAlertPush)
               SendNotification(msg);
            g_lastAlert = time[last];
           }
        }
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
