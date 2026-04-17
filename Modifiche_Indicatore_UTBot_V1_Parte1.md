# Modifiche Indicatore UTBot V1 — Parte 1

## File sorgente: `UTBotAdaptive-Ok-V1.mq5` (1525 righe, v2.01)
## File output: `UTBotAdaptive-Ok-V3.mq5` (copia modificata, v3.00)

**IMPORTANTE**: Creare una copia del file V1 e lavorare SOLO sulla copia.

---

## ORDINE DI IMPLEMENTAZIONE

1. Header e #property (plot/buffer count, nuovi plot)
2. Nuovi input parameters (FLAT detection + visual toggle)
3. Nuove variabili globali e buffer arrays
4. Preset MA per TF (g_eff_srcType)
5. OnInit: binding dei nuovi buffer + setup plot
6. ER finestrato (da V2)
7. Frecce multiple (3/2/1+■) + rimozione grigio
8. Candele: solo 3 colori (rimozione indice 3 grigio)
9. Flat detection + visualizzazione canale
10. Dashboard aggiornato
11. iCustom call update per HTF bias

---

## MODIFICA 1: Header e #property

### Riga 57: versione
```
VECCHIO: #property version   "2.01"
NUOVO:   #property version   "3.00"
```

### Righe 58-60: description
```
VECCHIO:
#property description "UT Bot Alerts — KAMA/HMA/JMA + anti-repainting + ER-colors"
#property description "v2.00: frecce ER-colorate, marker viola entrata, JMA adattiva, candela trigger gialla"
#property description "BUY/SELL su barre chiuse. Trigger bar = gialla. Entry marker = viola al close."

NUOVO:
#property description "UT Bot Alerts — KAMA/HMA/JMA + anti-repainting + frecce multi-ER"
#property description "v3.00: frecce 3/2/1+■ per ER, preset MA auto per TF, zona FLAT"
#property description "BUY/SELL su barre chiuse. Canale laterale blu. Entry marker viola."
```

### Righe 62-63: buffer e plot count
```
VECCHIO:
#property indicator_buffers 14
#property indicator_plots   5

NUOVO:
#property indicator_buffers 30
#property indicator_plots   13
```

### Righe 65-114: SOSTITUIRE INTERAMENTE la sezione plot con questa:

```mql5
//+------------------------------------------------------------------+
//| DEFINIZIONE DEI 13 PLOT (v3.00)                                  |
//+------------------------------------------------------------------+

// --- Plot 0: Trailing Stop Line ---
#property indicator_label1  "Trail Stop"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'38,166,154', C'239,83,80'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// --- Plot 1: Freccia BUY primaria (sempre visibile su segnale) ---
#property indicator_label2  "Buy1"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_color2  C'76,175,80', C'139,195,74', C'255,193,7', C'255,152,0'
#property indicator_width2  2

// --- Plot 2: Freccia BUY secondaria (ER >= 0.35) ---
#property indicator_label3  "Buy2"
#property indicator_type3   DRAW_COLOR_ARROW
#property indicator_color3  C'76,175,80', C'139,195,74'
#property indicator_width3  2

// --- Plot 3: Freccia BUY terziaria (ER >= 0.60) ---
#property indicator_label4  "Buy3"
#property indicator_type4   DRAW_COLOR_ARROW
#property indicator_color4  C'76,175,80'
#property indicator_width4  2

// --- Plot 4: Freccia SELL primaria (sempre visibile su segnale) ---
#property indicator_label5  "Sell1"
#property indicator_type5   DRAW_COLOR_ARROW
#property indicator_color5  C'239,83,80', C'255,138,101', C'255,193,7', C'255,152,0'
#property indicator_width5  2

// --- Plot 5: Freccia SELL secondaria (ER >= 0.35) ---
#property indicator_label6  "Sell2"
#property indicator_type6   DRAW_COLOR_ARROW
#property indicator_color6  C'239,83,80', C'255,138,101'
#property indicator_width6  2

// --- Plot 6: Freccia SELL terziaria (ER >= 0.60) ---
#property indicator_label7  "Sell3"
#property indicator_type7   DRAW_COLOR_ARROW
#property indicator_color7  C'239,83,80'
#property indicator_width7  2

// --- Plot 7: Caution marker ■ (ER < 0.15) ---
#property indicator_label8  "Caution"
#property indicator_type8   DRAW_COLOR_ARROW
#property indicator_color8  C'255,152,0', C'255,100,100'
#property indicator_width8  1

// --- Plot 8: Entry Level Line (viola dash) ---
#property indicator_label9  "Entry Level"
#property indicator_type9   DRAW_LINE
#property indicator_color9  C'148,0,211'
#property indicator_style9  STYLE_DASH
#property indicator_width9  1

// --- Plot 9: Flat Zone Fill (DRAW_FILLING tra Upper e Lower) ---
#property indicator_label10 "Flat Zone"
#property indicator_type10  DRAW_FILLING
#property indicator_color10 C'40,100,200', C'40,100,200'

// --- Plot 10: Flat Zone Upper Line (bianca tratteggiata) ---
#property indicator_label11 "Flat Upper"
#property indicator_type11  DRAW_LINE
#property indicator_color11 C'180,200,230'
#property indicator_style11 STYLE_DOT
#property indicator_width11 1

// --- Plot 11: Flat Zone Lower Line (bianca tratteggiata) ---
#property indicator_label12 "Flat Lower"
#property indicator_type12  DRAW_LINE
#property indicator_color12 C'180,200,230'
#property indicator_style12 STYLE_DOT
#property indicator_width12 1

// --- Plot 12: Candele colorate — 3 colori (NO grigio) ---
// Indice 0: teal   C'38,166,154'   candela bull
// Indice 1: coral  C'239,83,80'    candela bear
// Indice 2: giallo C'255,235,59'   candela TRIGGER
#property indicator_label13 "Candles"
#property indicator_type13  DRAW_COLOR_CANDLES
#property indicator_color13 C'38,166,154', C'239,83,80', C'255,235,59'
#property indicator_width13 1
```

---

## MODIFICA 2: Nuovi input parameters

### Dopo riga 195 (dopo InpBiasTF), INSERIRE:

```mql5
input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📐 RILEVAMENTO LATERALITÀ                               ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool            InpFlatDetect     = true;    // Attiva rilevamento zona FLAT
input double          InpFlatMinWidth   = 0.0;     // Min Channel Width pips (0=auto-preset)
input double          InpFlatERThresh   = 0.20;    // ER medio soglia per FLAT
input int             InpFlatERBars     = 8;       // Barre per media ER
input bool            InpShowFlatZone   = true;    // Mostra zona FLAT (canale blu)
```

### Dopo riga 203 (dopo InpShowArrows), aggiungere nella sezione COLORI E STILE:

**Nessuna modifica necessaria** — il toggle `InpShowFlatZone` è sufficiente.

---

## MODIFICA 3: Variabili globali e buffer arrays

### Sostituire la sezione buffer (righe 240-265) con:

```mql5
//+------------------------------------------------------------------+
//| BUFFER — 30 buffer totali, 13 plot (v3.00)                      |
//+------------------------------------------------------------------+
// Plot 0:  Buf 0-1   DRAW_COLOR_LINE    Trail stop + color
// Plot 1:  Buf 2-3   DRAW_COLOR_ARROW   Buy1 (primaria) + color
// Plot 2:  Buf 4-5   DRAW_COLOR_ARROW   Buy2 (secondaria) + color
// Plot 3:  Buf 6-7   DRAW_COLOR_ARROW   Buy3 (terziaria) + color
// Plot 4:  Buf 8-9   DRAW_COLOR_ARROW   Sell1 (primaria) + color
// Plot 5:  Buf 10-11 DRAW_COLOR_ARROW   Sell2 (secondaria) + color
// Plot 6:  Buf 12-13 DRAW_COLOR_ARROW   Sell3 (terziaria) + color
// Plot 7:  Buf 14-15 DRAW_COLOR_ARROW   Caution ■ + color
// Plot 8:  Buf 16    DRAW_LINE          Entry level (viola dash)
// Plot 9:  Buf 17-18 DRAW_FILLING       Flat zone fill (Upper+Lower)
// Plot 10: Buf 19    DRAW_LINE          Flat Upper line (bianca dot)
// Plot 11: Buf 20    DRAW_LINE          Flat Lower line (bianca dot)
// Plot 12: Buf 21-25 DRAW_COLOR_CANDLES OHLC + color
// ---     Buf 26    CALCULATIONS       ER
// ---     Buf 27    CALCULATIONS       State (+1/-1/0)
// ---     Buf 28    CALCULATIONS       FlatState (1=active, 0=flat)
// ---     Buf 29    CALCULATIONS       ChannelWidth (2*nLoss)
//
// EA extern: CopyBuffer(h, 2,..)  Buy1  | CopyBuffer(h, 8,..)  Sell1
//            CopyBuffer(h, 26,..) ER    | CopyBuffer(h, 27,..) State
//            CopyBuffer(h, 28,..) Flat  | CopyBuffer(h, 29,..) ChWidth

double B_Trail[];       // buffer 0
double B_TrailClr[];    // buffer 1
double B_Buy1[];        // buffer 2  — freccia BUY primaria
double B_Buy1Clr[];     // buffer 3
double B_Buy2[];        // buffer 4  — freccia BUY secondaria (ER≥0.35)
double B_Buy2Clr[];     // buffer 5
double B_Buy3[];        // buffer 6  — freccia BUY terziaria (ER≥0.60)
double B_Buy3Clr[];     // buffer 7
double B_Sell1[];       // buffer 8  — freccia SELL primaria
double B_Sell1Clr[];    // buffer 9
double B_Sell2[];       // buffer 10 — freccia SELL secondaria (ER≥0.35)
double B_Sell2Clr[];    // buffer 11
double B_Sell3[];       // buffer 12 — freccia SELL terziaria (ER≥0.60)
double B_Sell3Clr[];    // buffer 13
double B_Caution[];     // buffer 14 — quadratino ■ cautela (ER<0.15)
double B_CautionClr[];  // buffer 15
double B_EntryLine[];   // buffer 16
double B_FlatFillUp[];  // buffer 17 — DRAW_FILLING upper
double B_FlatFillDn[];  // buffer 18 — DRAW_FILLING lower
double B_FlatLineUp[];  // buffer 19 — Flat upper line
double B_FlatLineDn[];  // buffer 20 — Flat lower line
double B_CO[];          // buffer 21
double B_CH[];          // buffer 22
double B_CL[];          // buffer 23
double B_CC[];          // buffer 24
double B_CClr[];        // buffer 25
double B_ER[];          // buffer 26 (CALCULATIONS)
double B_State[];       // buffer 27 (CALCULATIONS)
double B_FlatState[];   // buffer 28 (CALCULATIONS) 1.0=active, 0.0=flat
double B_ChWidth[];     // buffer 29 (CALCULATIONS) channel width
```

### Nella sezione variabili interne (dopo riga 265), AGGIUNGERE:

```mql5
// --- Preset sorgente auto (v3.00) ---
ENUM_SRC_TYPE g_eff_srcType;    // SrcType effettivo (overridato da preset AUTO)

// --- Flat detection (v3.00) ---
double g_eff_flatMinWidth;       // MinWidth effettivo (auto-preset o manuale)
```

---

## MODIFICA 4: Preset MA per TF

### Nella funzione UTBotPresetsInit() (righe 368-461), modificare OGNI case per aggiungere `g_eff_srcType` e `g_eff_flatMinWidth`:

**NOTA**: In modalità AUTO, il preset sovrascrive anche il tipo di sorgente (`g_eff_srcType`). In modalità MANUAL, si usa `InpSrcType`.

```mql5
void UTBotPresetsInit()
  {
   ENUM_TF_PRESET_UT preset = InpTFPreset;

   if(preset == TF_PRESET_UT_AUTO)
     {
      switch(_Period)
        {
         case PERIOD_M1:  preset = TF_PRESET_UT_M1;  break;
         case PERIOD_M5:  preset = TF_PRESET_UT_M5;  break;
         case PERIOD_M15: preset = TF_PRESET_UT_M15; break;
         case PERIOD_M30: preset = TF_PRESET_UT_M30; break;
         case PERIOD_H1:  preset = TF_PRESET_UT_H1;  break;
         case PERIOD_H4:  preset = TF_PRESET_UT_H4;  break;
         default:         preset = TF_PRESET_UT_MANUAL; break;
        }
     }

   switch(preset)
     {
      case TF_PRESET_UT_M1:
         g_eff_keyValue    = 0.7;
         g_eff_atrPeriod   = 5;
         g_eff_srcType     = SRC_JMA;
         g_eff_kamaN       = 5;
         g_eff_kamaFast    = 2;
         g_eff_kamaSlow    = 20;
         g_eff_jmaPeriod   = 5;
         g_eff_jmaPhase    = 0;
         g_eff_flatMinWidth = 3.0;   // pips
         break;

      case TF_PRESET_UT_M5:
         g_eff_keyValue    = 1.0;
         g_eff_atrPeriod   = 7;
         g_eff_srcType     = SRC_KAMA;    // KAMA su M5
         g_eff_kamaN       = 8;
         g_eff_kamaFast    = 2;
         g_eff_kamaSlow    = 20;
         g_eff_jmaPeriod   = 8;
         g_eff_jmaPhase    = 0;
         g_eff_flatMinWidth = 5.0;
         break;

      case TF_PRESET_UT_M15:
         g_eff_keyValue    = 1.2;
         g_eff_atrPeriod   = 10;
         g_eff_srcType     = SRC_KAMA;    // KAMA su M15 (filtro naturale)
         g_eff_kamaN       = 10;
         g_eff_kamaFast    = 2;
         g_eff_kamaSlow    = 30;
         g_eff_jmaPeriod   = 14;
         g_eff_jmaPhase    = 0;
         g_eff_flatMinWidth = 8.0;
         break;

      case TF_PRESET_UT_M30:
         g_eff_keyValue    = 1.5;
         g_eff_atrPeriod   = 10;
         g_eff_srcType     = SRC_JMA;     // JMA su M30 (zero lag, TF già filtrato)
         g_eff_kamaN       = 10;
         g_eff_kamaFast    = 2;
         g_eff_kamaSlow    = 30;
         g_eff_jmaPeriod   = 18;
         g_eff_jmaPhase    = 50;
         g_eff_flatMinWidth = 12.0;
         break;

      case TF_PRESET_UT_H1:
         g_eff_keyValue    = 2.0;
         g_eff_atrPeriod   = 14;
         g_eff_srcType     = SRC_JMA;
         g_eff_kamaN       = 14;
         g_eff_kamaFast    = 2;
         g_eff_kamaSlow    = 35;
         g_eff_jmaPeriod   = 20;
         g_eff_jmaPhase    = 50;
         g_eff_flatMinWidth = 18.0;
         break;

      case TF_PRESET_UT_H4:
         g_eff_keyValue    = 2.5;
         g_eff_atrPeriod   = 14;
         g_eff_srcType     = SRC_JMA;
         g_eff_kamaN       = 14;
         g_eff_kamaFast    = 2;
         g_eff_kamaSlow    = 40;
         g_eff_jmaPeriod   = 28;
         g_eff_jmaPhase    = 75;
         g_eff_flatMinWidth = 25.0;
         break;

      default: // MANUAL
         g_eff_keyValue    = InpKeyValue;
         g_eff_atrPeriod   = InpATRPeriod;
         g_eff_srcType     = InpSrcType;  // utente decide
         g_eff_kamaN       = InpKAMA_N;
         g_eff_kamaFast    = InpKAMA_Fast;
         g_eff_kamaSlow    = InpKAMA_Slow;
         g_eff_jmaPeriod   = InpJMA_Period;
         g_eff_jmaPhase    = InpJMA_Phase;
         g_eff_flatMinWidth = (InpFlatMinWidth > 0.0) ? InpFlatMinWidth : 8.0;
         break;
     }

   // Override FlatMinWidth da input se l'utente l'ha specificato (> 0)
   if(InpFlatMinWidth > 0.0)
      g_eff_flatMinWidth = InpFlatMinWidth;
  }
```

**CRITICO**: Ovunque nel codice si usa `InpSrcType`, sostituire con `g_eff_srcType`. Questo include:
- Riga 516 (short name nel OnInit): `switch(InpSrcType)` → `switch(g_eff_srcType)`
- Riga 1108 (dashboard srcStr): `switch(InpSrcType)` → `switch(g_eff_srcType)`
- Riga 1313 (STEP 2 sorgente switch): `switch(InpSrcType)` → `switch(g_eff_srcType)`
- Riga 1418 (ER calc, vecchia condizione KAMA): rimossa dalla Modifica 6
- Riga 1386 (CopyBuffer HTF): indice buffer 13 → 27
- Riga 1372 (fullRecalc): B_BuyClr → B_Buy1Clr, B_SellClr → B_Sell1Clr
- Righe 1501-1502 (Alert): B_Buy → B_Buy1, B_Sell → B_Sell1

---

## MODIFICA 5: OnInit — Binding buffer e setup plot

### Sostituire il blocco di binding buffer (righe 472-508) con:

```mql5
   //--- Binding buffer v3.00 (30 buffer, 13 plot)
   SetIndexBuffer(0,  B_Trail,      INDICATOR_DATA);
   SetIndexBuffer(1,  B_TrailClr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,  B_Buy1,       INDICATOR_DATA);
   SetIndexBuffer(3,  B_Buy1Clr,    INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4,  B_Buy2,       INDICATOR_DATA);
   SetIndexBuffer(5,  B_Buy2Clr,    INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6,  B_Buy3,       INDICATOR_DATA);
   SetIndexBuffer(7,  B_Buy3Clr,    INDICATOR_COLOR_INDEX);
   SetIndexBuffer(8,  B_Sell1,      INDICATOR_DATA);
   SetIndexBuffer(9,  B_Sell1Clr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(10, B_Sell2,      INDICATOR_DATA);
   SetIndexBuffer(11, B_Sell2Clr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(12, B_Sell3,      INDICATOR_DATA);
   SetIndexBuffer(13, B_Sell3Clr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(14, B_Caution,    INDICATOR_DATA);
   SetIndexBuffer(15, B_CautionClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(16, B_EntryLine,  INDICATOR_DATA);
   SetIndexBuffer(17, B_FlatFillUp, INDICATOR_DATA);
   SetIndexBuffer(18, B_FlatFillDn, INDICATOR_DATA);
   SetIndexBuffer(19, B_FlatLineUp, INDICATOR_DATA);
   SetIndexBuffer(20, B_FlatLineDn, INDICATOR_DATA);
   SetIndexBuffer(21, B_CO,         INDICATOR_DATA);
   SetIndexBuffer(22, B_CH,         INDICATOR_DATA);
   SetIndexBuffer(23, B_CL,         INDICATOR_DATA);
   SetIndexBuffer(24, B_CC,         INDICATOR_DATA);
   SetIndexBuffer(25, B_CClr,       INDICATOR_COLOR_INDEX);
   SetIndexBuffer(26, B_ER,         INDICATOR_CALCULATIONS);
   SetIndexBuffer(27, B_State,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(28, B_FlatState,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(29, B_ChWidth,    INDICATOR_CALCULATIONS);

   //--- Codici freccia per ogni plot
   PlotIndexSetInteger(1, PLOT_ARROW, 233);   // Buy1  ▲
   PlotIndexSetInteger(2, PLOT_ARROW, 233);   // Buy2  ▲
   PlotIndexSetInteger(3, PLOT_ARROW, 233);   // Buy3  ▲
   PlotIndexSetInteger(4, PLOT_ARROW, 234);   // Sell1 ▼
   PlotIndexSetInteger(5, PLOT_ARROW, 234);   // Sell2 ▼
   PlotIndexSetInteger(6, PLOT_ARROW, 234);   // Sell3 ▼
   PlotIndexSetInteger(7, PLOT_ARROW, 158);   // Caution ■ (filled square)

   //--- Empty values per tutti i 13 plot
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, 0.0);          // Trail
   for(int p = 1; p <= 7; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE); // Frecce + Caution
   PlotIndexSetDouble(8,  PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Entry line
   PlotIndexSetDouble(9,  PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Flat fill
   PlotIndexSetDouble(10, PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Flat upper
   PlotIndexSetDouble(11, PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Flat lower
   PlotIndexSetDouble(12, PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Candles

   //--- Disabilita plot opzionali
   if(!InpColorBars)
      PlotIndexSetInteger(12, PLOT_DRAW_TYPE, DRAW_NONE);

   if(!InpShowArrows)
     {
      for(int p = 1; p <= 7; p++)
         PlotIndexSetInteger(p, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(8, PLOT_DRAW_TYPE, DRAW_NONE);  // Entry line
     }

   if(!InpShowTrailLine)
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

   // Toggle zona FLAT visiva
   if(!InpShowFlatZone || !InpFlatDetect)
     {
      PlotIndexSetInteger(9,  PLOT_DRAW_TYPE, DRAW_NONE);  // Flat fill
      PlotIndexSetInteger(10, PLOT_DRAW_TYPE, DRAW_NONE);  // Flat upper
      PlotIndexSetInteger(11, PLOT_DRAW_TYPE, DRAW_NONE);  // Flat lower
     }
```

### Short name (riga 516-533): aggiornare la sezione switch per usare `g_eff_srcType`:
```
switch(g_eff_srcType)  // era: switch(InpSrcType)
```

E aggiornare il nome:
```mql5
   IndicatorSetString(INDICATOR_SHORTNAME,
      "UTBot3[" + DoubleToString(g_eff_keyValue, 1) + "," +
      IntegerToString(g_eff_atrPeriod) + "," + srcStr + "]");
```

### Riga 1386 (CopyBuffer HTF State): CRITICO — aggiornare indice buffer
In V3, B_State si sposta dal buffer 13 al buffer 27.
```
VECCHIO (riga 1386): if(CopyBuffer(g_htfHandle, 13, 1, 1, tmp) == 1)
NUOVO:               if(CopyBuffer(g_htfHandle, 27, 1, 1, tmp) == 1)
```

### Riga 581 (iCustom per HTF): mantenere InpSrcType (NON g_eff_srcType)
Il parametro SrcType resta `InpSrcType` perché l'istanza child HTF farà il proprio
UTBotPresetsInit() e imposterà il suo g_eff_srcType basato sul TF child (es. H1).

Aggiungere i nuovi parametri della lateralità alla fine della chiamata iCustom.
La chiamata completa diventa:

```mql5
      g_htfHandle = iCustom(_Symbol, InpBiasTF, "UTBotAdaptive-Ok-V3",
                            InpTFPreset,      InpKeyValue,      InpATRPeriod,
                            InpSrcType,       InpHMAPeriod,
                            InpKAMA_N,        InpKAMA_Fast,     InpKAMA_Slow,
                            InpJMA_Period,    InpJMA_Phase,
                            false, PERIOD_H1,                   // bias OFF
                            false, 0.0, 0.20, 8, false,         // Flat OFF (child)
                            false, false,                        // ColorBars OFF, Arrows OFF
                            false, false,                        // Theme OFF, Grid OFF
                            InpThemeBG, InpThemeFG, InpThemeGrid,
                            InpThemeBullCandl, InpThemeBearCandl,
                            false, false,                        // Alert OFF
                            false, false);                       // Dashboard OFF, Trail OFF
```

**NOTA**: L'ordine dei parametri deve corrispondere ESATTAMENTE all'ordine degli input nella sezione in testa al file. Con i nuovi input FLAT, l'ordine diventa:
1. InpTFPreset, InpKeyValue, InpATRPeriod
2. InpSrcType, InpHMAPeriod
3. InpKAMA_N, InpKAMA_Fast, InpKAMA_Slow
4. InpJMA_Period, InpJMA_Phase
5. InpUseBias, InpBiasTF
6. **InpFlatDetect, InpFlatMinWidth, InpFlatERThresh, InpFlatERBars, InpShowFlatZone** (NUOVO)
7. InpColorBars, InpShowArrows
8. InpApplyTheme, InpShowGrid
9. InpThemeBG, InpThemeFG, InpThemeGrid, InpThemeBullCandl, InpThemeBearCandl
10. InpAlertPopup, InpAlertPush
11. InpShowDashboard, InpShowTrailLine

---

## MODIFICA 6: ER finestrato + Flat detection + init block + alert

### Righe 1368-1378: fullRecalc init block — aggiornare nomi buffer
Sostituire il blocco con:

```mql5
   if(fullRecalc || B_Trail[trail_start - 1] == 0.0)
     {
      B_Trail[trail_start - 1]      = g_src[trail_start - 1];
      B_TrailClr[trail_start - 1]   = 0;
      B_Buy1Clr[trail_start - 1]    = 0;
      B_Sell1Clr[trail_start - 1]   = 0;
      B_EntryLine[trail_start - 1]  = EMPTY_VALUE;
      B_ER[trail_start - 1]         = 0;
      B_State[trail_start - 1]      = 0;
      B_FlatState[trail_start - 1]  = 1.0;    // active by default
      B_ChWidth[trail_start - 1]    = 0;
      g_entryLevel = EMPTY_VALUE;
     }
```

### Sostituire righe 1414-1428 (sezione ER inline) con:

```mql5
      //--- Efficiency Ratio windowed (Kaufman, sempre su close[]) ---
      // v3.00: ER finestrato per TUTTE le sorgenti (non solo KAMA).
      double er_val = 0.0;
      int erWin = g_eff_kamaN;
      if(i >= erWin)
        {
         double d = MathAbs(close[i] - close[i - erWin]);
         double n = 0.0;
         for(int k = 1; k <= erWin; k++)
            n += MathAbs(close[i - k + 1] - close[i - k]);
         er_val = (n > 0.0) ? d / n : 0.0;
        }
      B_ER[i] = er_val;

      //--- Channel Width (per EA e flat detection) ---
      // nLoss è già calcolato sopra (riga 1397 originale, invariata)
      double chWidth = 2.0 * nLoss;
      B_ChWidth[i] = chWidth;

      //--- Flat Detection ---
      // Converte minWidth da pips a prezzo
      double minWidthPrice = g_eff_flatMinWidth * _Point * (((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0));
      // Media ER su ultime N barre
      double erAvg = er_val;
      if(InpFlatDetect && i >= InpFlatERBars)
        {
         double erSum = 0.0;
         for(int k = 0; k < InpFlatERBars; k++)
            erSum += B_ER[i - k];
         erAvg = erSum / InpFlatERBars;
        }

      bool isFlat = InpFlatDetect
                 && (chWidth < minWidthPrice)
                 && (erAvg < InpFlatERThresh);
      B_FlatState[i] = isFlat ? 0.0 : 1.0;
```

**NOTA**: La variabile `nLoss` resta alla riga 1397 (invariata). NON rimuoverla —
serve per il trailing stop alle righe 1400-1409. La sezione qui sopra la UTILIZZA
(per chWidth e flat detection), non la ricalcola.

---

## MODIFICA 7: Frecce multiple + rimozione grigio

### Sostituire righe 1430-1492 (erIdx + if/else anti-repainting + barra corrente) con:

```mql5
      //--- Flat zone visualization ---
      if(isFlat && InpShowFlatZone && InpFlatDetect)
        {
         // Calcola Upper/Lower del canale
         double flatUpper, flatLower;
         if(src > trail)
           { flatUpper = trail + chWidth; flatLower = trail; }
         else
           { flatUpper = trail; flatLower = trail - chWidth; }

         B_FlatFillUp[i] = flatUpper;
         B_FlatFillDn[i] = flatLower;
         B_FlatLineUp[i] = flatUpper;
         B_FlatLineDn[i] = flatLower;
        }
      else
        {
         B_FlatFillUp[i] = EMPTY_VALUE;
         B_FlatFillDn[i] = EMPTY_VALUE;
         B_FlatLineUp[i] = EMPTY_VALUE;
         B_FlatLineDn[i] = EMPTY_VALUE;
        }

      //--- ANTI-REPAINTING ---
      if(i < rates_total - 1)
        {
         //--- Segnali con filtro bias HTF + FLAT gate ---
         bool isBuy  = (src1 < t1) && (src > trail) && biasLong  && !isFlat;
         bool isSell = (src1 > t1) && (src < trail) && biasShort && !isFlat;

         //--- Frecce multiple per ER (3/2/1+■) ---
         // ER >= 0.60: 3 frecce (forte)
         // ER 0.35-0.59: 2 frecce (moderato)
         // ER 0.15-0.34: 1 freccia (debole)
         // ER < 0.15: 1 freccia + quadratino ■ (cautela)

         double buyBase  = low[i]  - g_atr[i] * 0.5;
         double sellBase = high[i] + g_atr[i] * 0.5;
         double arrowGap = g_atr[i] * 0.35;  // distanza tra frecce

         // --- BUY arrows ---
         if(isBuy)
           {
            // Buy1: sempre (primaria)
            B_Buy1[i] = buyBase;
            if(er_val >= 0.60)       B_Buy1Clr[i] = 0.0;  // verde pieno
            else if(er_val >= 0.35)  B_Buy1Clr[i] = 1.0;  // verde chiaro
            else if(er_val >= 0.15)  B_Buy1Clr[i] = 2.0;  // giallo
            else                     B_Buy1Clr[i] = 3.0;  // arancione

            // Buy2: solo se ER >= 0.35
            if(er_val >= 0.60)
              { B_Buy2[i] = buyBase - arrowGap; B_Buy2Clr[i] = 0.0; }
            else if(er_val >= 0.35)
              { B_Buy2[i] = buyBase - arrowGap; B_Buy2Clr[i] = 1.0; }
            else
              { B_Buy2[i] = EMPTY_VALUE; B_Buy2Clr[i] = 0.0; }

            // Buy3: solo se ER >= 0.60
            if(er_val >= 0.60)
              { B_Buy3[i] = buyBase - arrowGap * 2; B_Buy3Clr[i] = 0.0; }
            else
              { B_Buy3[i] = EMPTY_VALUE; B_Buy3Clr[i] = 0.0; }

            // Caution: solo se ER < 0.15
            if(er_val < 0.15)
              { B_Caution[i] = high[i] + g_atr[i] * 0.3; B_CautionClr[i] = 0.0; }
            else
              { B_Caution[i] = EMPTY_VALUE; B_CautionClr[i] = 0.0; }
           }
         else
           {
            B_Buy1[i] = EMPTY_VALUE; B_Buy1Clr[i] = 0.0;
            B_Buy2[i] = EMPTY_VALUE; B_Buy2Clr[i] = 0.0;
            B_Buy3[i] = EMPTY_VALUE; B_Buy3Clr[i] = 0.0;
           }

         // --- SELL arrows ---
         if(isSell)
           {
            B_Sell1[i] = sellBase;
            if(er_val >= 0.60)       B_Sell1Clr[i] = 0.0;  // rosso pieno
            else if(er_val >= 0.35)  B_Sell1Clr[i] = 1.0;  // arancione
            else if(er_val >= 0.15)  B_Sell1Clr[i] = 2.0;  // giallo
            else                     B_Sell1Clr[i] = 3.0;  // arancione scuro

            if(er_val >= 0.60)
              { B_Sell2[i] = sellBase + arrowGap; B_Sell2Clr[i] = 0.0; }
            else if(er_val >= 0.35)
              { B_Sell2[i] = sellBase + arrowGap; B_Sell2Clr[i] = 1.0; }
            else
              { B_Sell2[i] = EMPTY_VALUE; B_Sell2Clr[i] = 0.0; }

            if(er_val >= 0.60)
              { B_Sell3[i] = sellBase + arrowGap * 2; B_Sell3Clr[i] = 0.0; }
            else
              { B_Sell3[i] = EMPTY_VALUE; B_Sell3Clr[i] = 0.0; }

            if(er_val < 0.15)
              { B_Caution[i] = low[i] - g_atr[i] * 0.3; B_CautionClr[i] = 1.0; }
            else if(!isBuy) // evita sovrascrittura se sia Buy che Sell (impossibile, ma safety)
              { B_Caution[i] = EMPTY_VALUE; B_CautionClr[i] = 0.0; }
           }
         else
           {
            B_Sell1[i] = EMPTY_VALUE; B_Sell1Clr[i] = 0.0;
            B_Sell2[i] = EMPTY_VALUE; B_Sell2Clr[i] = 0.0;
            B_Sell3[i] = EMPTY_VALUE; B_Sell3Clr[i] = 0.0;
            if(!isBuy) // non sovrascrivere il Caution se è stato settato dal BUY
              { B_Caution[i] = EMPTY_VALUE; B_CautionClr[i] = 0.0; }
           }

         //--- Entry level line ---
         if(isBuy || isSell)
            g_entryLevel = close[i];
         B_EntryLine[i] = g_entryLevel;

         //--- Stato posizione (per EA) ---
         if(src1 < t1 && src > t1)
            B_State[i] = 1.0;
         else if(src1 > t1 && src < t1)
            B_State[i] = -1.0;
         else
            B_State[i] = B_State[i - 1];

         //--- Candele colorate: solo 3 colori (teal/coral/giallo) ---
         if(InpColorBars)
           {
            B_CO[i]   = open[i];
            B_CH[i]   = high[i];
            B_CL[i]   = low[i];
            B_CC[i]   = close[i];
            B_CClr[i] = (isBuy || isSell) ? 2.0 :
                         (src > trail) ? 0.0 : 1.0;
           }
        }
      else
        {
         //--- Barra corrente (aperta) ---
         B_Buy1[i] = EMPTY_VALUE;  B_Buy1Clr[i] = 0.0;
         B_Buy2[i] = EMPTY_VALUE;  B_Buy2Clr[i] = 0.0;
         B_Buy3[i] = EMPTY_VALUE;  B_Buy3Clr[i] = 0.0;
         B_Sell1[i] = EMPTY_VALUE; B_Sell1Clr[i] = 0.0;
         B_Sell2[i] = EMPTY_VALUE; B_Sell2Clr[i] = 0.0;
         B_Sell3[i] = EMPTY_VALUE; B_Sell3Clr[i] = 0.0;
         B_Caution[i] = EMPTY_VALUE; B_CautionClr[i] = 0.0;
         B_EntryLine[i] = g_entryLevel;
         B_State[i] = B_State[i - 1];

         if(InpColorBars)
           {
            B_CO[i]   = open[i];
            B_CH[i]   = high[i];
            B_CL[i]   = low[i];
            B_CC[i]   = close[i];
            B_CClr[i] = (src > trail) ? 0.0 : 1.0;
           }
        }
```

---

## MODIFICA 8: STEP 2 sorgente + Alert — aggiornare riferimenti buffer

### Riga 1313 (switch per la sorgente nel main loop):
```
VECCHIO: switch(InpSrcType)
NUOVO:   switch(g_eff_srcType)
```

### Righe 1501-1502: Alert — aggiornare nomi buffer
```
VECCHIO (riga 1501): bool alertBuy  = (B_Buy[last]  != EMPTY_VALUE);
NUOVO:               bool alertBuy  = (B_Buy1[last]  != EMPTY_VALUE);

VECCHIO (riga 1502): bool alertSell = (B_Sell[last] != EMPTY_VALUE);
NUOVO:               bool alertSell = (B_Sell1[last] != EMPTY_VALUE);
```

---

## MODIFICA 9: Dashboard aggiornato

### Nella funzione UpdateUTBDashboard(), riga 1055:
```
VECCHIO: UTBSetRow(row++, "UTBot v2.00 | " + _Symbol + " | " + EnumToString(_Period),
NUOVO:   UTBSetRow(row++, "UTBot v3.00 | " + _Symbol + " | " + EnumToString(_Period),
```

### Dopo la riga del Bias HTF (riga ~1149), AGGIUNGERE:

```mql5
   //--- FLAT STATUS ---
   if(InpFlatDetect)
     {
      int rt2 = g_dash_ratesTotal;
      if(rt2 >= 3)
        {
         double flatVal = B_FlatState[rt2 - 2];
         double cwVal   = B_ChWidth[rt2 - 2];
         double cwPips  = cwVal / (_Point * ((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0));

         if(flatVal < 0.5) // FLAT
           {
            UTBSetRow(row++, "Regime:  ⏸ FLAT — laterale", C'100,150,220');
            UTBSetRow(row++, "ChWidth: " + DoubleToString(cwPips, 1) + "p" +
                      " < min " + DoubleToString(g_eff_flatMinWidth, 1) + "p", C'100,150,220');
           }
         else
           {
            UTBSetRow(row++, "Regime:  ▶ ACTIVE — trending", C'50,220,120');
            UTBSetRow(row++, "ChWidth: " + DoubleToString(cwPips, 1) + "p", C'150,165,185');
           }
        }
     }
   else
      UTBSetRow(row++, "Flat:    OFF", C'80,90,110');
```

### Nella dashboard sezione sorgente (riga ~1108):
```
VECCHIO: switch(InpSrcType)
NUOVO:   switch(g_eff_srcType)
```

Aggiungere info su auto-preset:
```mql5
   if(InpTFPreset != TF_PRESET_UT_MANUAL && g_eff_srcType != InpSrcType)
      srcStr += " [auto]";
```

---

## MODIFICA 10: OnDeinit — cleanup

### Nella funzione OnDeinit (riga 690), nessuna modifica specifica necessaria. I buffer vengono deallocati automaticamente da MT5. Non ci sono oggetti OBJ_ da eliminare perché usiamo solo DRAW_FILLING (basato su buffer).

---

## VERIFICA FINALE — Checklist

- [ ] `#property indicator_buffers 30` e `indicator_plots 13`
- [ ] 30 buffer dichiarati e bindati con SetIndexBuffer
- [ ] 13 plot con #property corretti (type, color, style, width)
- [ ] `g_eff_srcType` usato al posto di `InpSrcType` in: riga 516, 1108, 1313
- [ ] `InpSrcType` mantenuto nella chiamata iCustom (NON g_eff_srcType)
- [ ] CopyBuffer HTF legge buffer **27** (non 13) per B_State
- [ ] ER windowed per tutte le sorgenti (nessun fallback proxy)
- [ ] `nLoss` resta alla riga 1397 (NON rimosso, NON duplicato)
- [ ] fullRecalc init block: B_Buy1Clr, B_Sell1Clr, B_FlatState, B_ChWidth
- [ ] Alert (righe 1501-1502): B_Buy1, B_Sell1
- [ ] Frecce: 3 BUY + 3 SELL + 1 Caution, nessun grigio
- [ ] Candele: solo 3 colori (teal/coral/giallo), nessun grigio
- [ ] Flat detection: `chWidth < minWidth && erAvg < threshold`
- [ ] Flat zone: DRAW_FILLING blu + 2 DRAW_LINE bianche dot
- [ ] `InpShowFlatZone` controlla visibilità dei 3 plot flat
- [ ] `InpFlatDetect` controlla la logica (se OFF, `isFlat` è sempre false)
- [ ] iCustom per HTF aggiornata con nuovi parametri nell'ordine corretto
- [ ] Dashboard con stato FLAT e ChannelWidth
- [ ] Compilazione senza warning
- [ ] Barra corrente: nessuna freccia, nessun flat fill, solo trail + candela

---

## BUFFER MAP PER EA EXTERN

```
CopyBuffer(handle, 2,  ...)  → Buy1 signal (EMPTY_VALUE = no signal)
CopyBuffer(handle, 8,  ...)  → Sell1 signal
CopyBuffer(handle, 26, ...)  → Efficiency Ratio 0.0-1.0
CopyBuffer(handle, 27, ...)  → State (+1.0 long, -1.0 short, 0.0 neutro)
CopyBuffer(handle, 28, ...)  → FlatState (1.0 = active/trading, 0.0 = flat)
CopyBuffer(handle, 29, ...)  → ChannelWidth (in prezzo, non pips)
```

---

*Fine Parte 1 — Modifiche indicatore UTBot V1 → V3*
