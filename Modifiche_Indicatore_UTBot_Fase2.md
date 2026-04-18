# Modifiche Indicatore UTBot V3.52 → V4.00 — Fase 2

## File sorgente: `UTBotAdaptive-Ok-V1.mq5` (2141 righe, v3.52)
## Versione target: v4.00

**5 nuovi buffer (30→35), 3 nuovi plot (13→16), 3 nuovi input.**

---

## COSA AGGIUNGE LA FASE 2

1. **Chandelier Exit Anchored** — overlay visivo (linea verde long, rossa short)
   con trailing ratchet, anchored dall'ultimo segnale UTBot, vol normalization.
   Buffer esposti per l'EA: l'EA legge i livelli e chiude quando toccati.

2. **BiasGate** — buffer CALC che tagga ogni segnale come con-bias (1.0)
   o contro-bias (0.0). L'EA decide: con-bias → apri trade; contro-bias → solo chiudi.

3. **BiasContra marker ◆** — marker visivo sulle frecce contro-bias per backtest.

4. **Pulsante dashboard CHAND** — toggle visivo Chandelier overlay.

---

## ELENCO MODIFICHE

1. Header (version, buffers, plots, nuovi #property plot)
2. Nuovi input (Chandelier)
3. Nuovi buffer arrays + variabili globali
4. OnInit: binding buffer + plot setup + init
5. OnCalculate: BiasGate tagging
6. OnCalculate: Chandelier Anchored overlay
7. Barra corrente: nuovi buffer
8. fullRecalc init block: nuovi buffer
9. Dashboard: pulsante CHAND
10. OnChartEvent: handler CHAND
11. iCustom call: nuovi parametri

---

## MODIFICA 1: Header

### Riga 132:
```
VECCHIO: #property version   "3.52"
NUOVO:   #property version   "4.00"
```

### Righe 137-138:
```
VECCHIO:
#property indicator_buffers 30
#property indicator_plots   13

NUOVO:
#property indicator_buffers 35
#property indicator_plots   16
```

### Dopo l'ultimo #property plot (dopo indicator_width13), AGGIUNGERE:

```mql5
// --- Plot 13: Chandelier Long (verde tratteggiata sotto prezzo) ---
#property indicator_label14 "Chand Long"
#property indicator_type14  DRAW_LINE
#property indicator_color14 C'50,200,120'
#property indicator_style14 STYLE_DASH
#property indicator_width14 1

// --- Plot 14: Chandelier Short (rossa tratteggiata sopra prezzo) ---
#property indicator_label15 "Chand Short"
#property indicator_type15  DRAW_LINE
#property indicator_color15 C'239,100,100'
#property indicator_style15 STYLE_DASH
#property indicator_width15 1

// --- Plot 15: Bias Contra marker ◆ (segnale contro-bias) ---
#property indicator_label16 "Bias Contra"
#property indicator_type16  DRAW_COLOR_ARROW
#property indicator_color16 C'100,100,180', C'180,100,100'
#property indicator_width16 1
```

---

## MODIFICA 2: Nuovi input

### Dopo riga 323 (InpShowFlatZone), INSERIRE nuovo gruppo:

```mql5
input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📏 CHANDELIER EXIT OVERLAY                              ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool            InpShowChandelier = false;     // Mostra Chandelier Exit (overlay)
input double          InpChandMult      = 2.5;       // Chandelier ATR multiplier
input bool            InpChandVolNorm   = true;      // Normalizzazione volatilità ATR
```

**NUOVO ORDINE INPUT COMPLETO** (per iCustom):
1. InpTFPreset, InpKeyValue, InpATRPeriod
2. InpSrcType, InpHMAPeriod
3. InpKAMA_N, InpKAMA_Fast, InpKAMA_Slow
4. InpJMA_Period, InpJMA_Phase
5. InpUseBias, InpBiasTF
6. InpFlatDetect, InpFlatMinWidth, InpFlatERThresh, InpFlatERBars, InpShowFlatZone
7. **InpShowChandelier, InpChandMult, InpChandVolNorm** (NUOVO)
8. InpColorBars, InpShowArrows
9. InpApplyTheme, InpShowGrid
10. InpThemeBG..InpThemeBearCandl
11. InpAlertPopup, InpAlertPush
12. InpShowDashboard, InpShowTrailLine

---

## MODIFICA 3: Nuovi buffer arrays + variabili globali

### Dopo B_ChWidth[] (attuale ultimo buffer array), AGGIUNGERE:

```mql5
double B_BiasGate[];     // buffer 30 (CALC) 1.0=con-bias, 0.0=contro-bias, EMPTY=no signal
double B_ChandLong[];    // buffer 31 (Plot 13) Chandelier trailing long
double B_ChandShort[];   // buffer 32 (Plot 14) Chandelier trailing short
double B_BiasContra[];   // buffer 33 (Plot 15) marker ◆ contro-bias
double B_BiasContraClr[];// buffer 34 (Plot 15 COLOR)
```

### Nella sezione variabili globali, AGGIUNGERE:

```mql5
// --- Chandelier state (v4.00) ---
double g_chandHH;                // Highest High dal segnale (anchor)
double g_chandLL;                // Lowest Low dal segnale (anchor)
double g_chandLastLong;          // ultimo valore Chandelier Long (ratchet up)
double g_chandLastShort;         // ultimo valore Chandelier Short (ratchet down)

// --- Dashboard vis toggle (v4.00) ---
bool   g_dash_vis_chand = true;  // Chandelier visibilità
```

---

## MODIFICA 4: OnInit — binding buffer + plot setup + init

### Dopo SetIndexBuffer(29, B_ChWidth, ...) (riga ~703), AGGIUNGERE:

```mql5
   SetIndexBuffer(30, B_BiasGate,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(31, B_ChandLong,     INDICATOR_DATA);
   SetIndexBuffer(32, B_ChandShort,    INDICATOR_DATA);
   SetIndexBuffer(33, B_BiasContra,    INDICATOR_DATA);
   SetIndexBuffer(34, B_BiasContraClr, INDICATOR_COLOR_INDEX);
```

### Dopo l'ultimo PlotIndexSetInteger per le frecce (PLOT_ARROW), AGGIUNGERE:

```mql5
   PlotIndexSetInteger(15, PLOT_ARROW, 169);  // BiasContra ◆ (diamond)
```

### Dopo l'ultimo PlotIndexSetDouble per EMPTY_VALUE, AGGIUNGERE:

```mql5
   PlotIndexSetDouble(13, PLOT_EMPTY_VALUE, EMPTY_VALUE);  // Chand Long
   PlotIndexSetDouble(14, PLOT_EMPTY_VALUE, EMPTY_VALUE);  // Chand Short
   PlotIndexSetDouble(15, PLOT_EMPTY_VALUE, EMPTY_VALUE);  // Bias Contra
```

### Dopo il blocco toggle FLAT zone, AGGIUNGERE:

```mql5
   // Toggle Chandelier overlay
   if(!InpShowChandelier)
     {
      PlotIndexSetInteger(13, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(14, PLOT_DRAW_TYPE, DRAW_NONE);
     }

   // Toggle Bias Contra markers (visibili solo se bias possibile)
   if(g_htfHandle == INVALID_HANDLE)
      PlotIndexSetInteger(15, PLOT_DRAW_TYPE, DRAW_NONE);
```

### Nella sezione init variabili (dopo g_flatRangeLow = 0), AGGIUNGERE:

```mql5
   g_chandHH         = 0;
   g_chandLL         = 0;
   g_chandLastLong   = 0;
   g_chandLastShort  = 999999;
   g_dash_vis_chand  = InpShowChandelier;
```

---

## MODIFICA 5: OnCalculate — BiasGate tagging

### DOPO le righe isBuy/isSell (riga ~1967-1968), INSERIRE:

```mql5
         // [v4.00] BiasGate: tagga il segnale come con-bias o contro-bias.
         // L'EA usa questo buffer per decidere:
         //   1.0 = con-bias → apri nuovo trade
         //   0.0 = contro-bias → solo chiudi posizione esistente, NON aprire opposto
         // Le frecce appaiono SEMPRE (isBuy/isSell NON cambiano).
         // Il BiasGate è solo informativo per l'EA.

         // Calcola crossover RAW (senza bias) per il tagging
         bool rawBuy  = (src1 < t1) && (src > trail) && !isFlat;
         bool rawSell = (src1 > t1) && (src < trail) && !isFlat;

         if(rawBuy)
            B_BiasGate[i] = biasLong ? 1.0 : 0.0;
         else if(rawSell)
            B_BiasGate[i] = biasShort ? 1.0 : 0.0;
         else
            B_BiasGate[i] = EMPTY_VALUE;

         // Bias Contra marker ◆: visibile su frecce contro-bias
         // (frecce che passano il crossover ma non il bias HTF)
         if(rawBuy && !biasLong && !isBuy)
           { B_BiasContra[i] = high[i] + g_atr[i] * 0.3; B_BiasContraClr[i] = 0.0; }
         else if(rawSell && !biasShort && !isSell)
           { B_BiasContra[i] = low[i] - g_atr[i] * 0.3; B_BiasContraClr[i] = 1.0; }
         else
           { B_BiasContra[i] = EMPTY_VALUE; B_BiasContraClr[i] = 0.0; }
```

**NOTA IMPORTANTE**: `rawBuy`/`rawSell` sono calcolati SENZA bias (solo crossover + !isFlat).
`isBuy`/`isSell` (riga 1967-1968) INCLUDONO il bias. Quando il bias blocca un segnale
(`rawBuy=true` ma `isBuy=false`), il BiasContra marker ◆ appare come avviso visivo,
e B_BiasGate[i]=0.0 dice all'EA di usare quel segnale solo per chiudere.

Quando il bias è OFF (g_biasEnabled=false), `biasLong=biasShort=true` sempre,
quindi `rawBuy==isBuy` e `rawSell==isSell`, nessun marker ◆ appare, BiasGate=1.0 sempre.

---

## MODIFICA 6: OnCalculate — Chandelier Anchored overlay

### DOPO il blocco flat zone visualization e PRIMA di `//--- ANTI-REPAINTING ---`, INSERIRE:

```mql5
      //--- Chandelier Exit Anchored (v4.00) ---
      // Trailing Chandelier dal segnale UTBot più recente.
      // HH/LL anchor: resettato ad ogni crossover trail.
      // Ratchet: Chandelier Long sale ma non scende; Short scende ma non sale.
      // Vol normalization: adjATR = mult * ATR * (avgATR / ATR) per stabilizzare.
      if(InpShowChandelier)
        {
         // Detect crossover trail per reset anchor
         bool chandReset = false;
         if(i > 0)
           {
            bool crossUp   = (g_src[i-1] < B_Trail[i-1]) && (src > trail);
            bool crossDown = (g_src[i-1] > B_Trail[i-1]) && (src < trail);
            if(crossUp || crossDown)
              {
               g_chandHH = high[i];
               g_chandLL = low[i];
               g_chandLastLong  = 0;
               g_chandLastShort = 999999;
               chandReset = true;
              }
           }
         if(!chandReset)
           {
            if(high[i] > g_chandHH) g_chandHH = high[i];
            if(low[i]  < g_chandLL) g_chandLL = low[i];
           }

         // ATR con volatility normalization
         double chandATR = g_atr[i];
         double adjATR;
         if(InpChandVolNorm && i >= 50)
           {
            double avgATR = 0;
            for(int k = 0; k < 50; k++)
               avgATR += g_atr[i - k];
            avgATR /= 50.0;
            double volFactor = (chandATR > 0) ? (avgATR / chandATR) : 1.0;
            adjATR = InpChandMult * chandATR * volFactor;
           }
         else
            adjATR = InpChandMult * chandATR;

         // Chandelier levels
         double chandLongVal  = g_chandHH - adjATR;
         double chandShortVal = g_chandLL + adjATR;

         // Ratchet: Long solo sale, Short solo scende
         if(src > trail) // regime LONG
           {
            if(g_chandLastLong > 0 && !chandReset)
               chandLongVal = MathMax(chandLongVal, g_chandLastLong);
            g_chandLastLong = chandLongVal;
            B_ChandLong[i]  = chandLongVal;
            B_ChandShort[i] = EMPTY_VALUE;
           }
         else // regime SHORT
           {
            if(g_chandLastShort < 999999 && !chandReset)
               chandShortVal = MathMin(chandShortVal, g_chandLastShort);
            g_chandLastShort = chandShortVal;
            B_ChandShort[i] = chandShortVal;
            B_ChandLong[i]  = EMPTY_VALUE;
           }
        }
      else
        {
         B_ChandLong[i]  = EMPTY_VALUE;
         B_ChandShort[i] = EMPTY_VALUE;
        }
```

**POSIZIONE**: Questo blocco va DOPO la flat zone visualization (fine riga ~1960)
e PRIMA di `//--- ANTI-REPAINTING ---` (riga ~1961). Il Chandelier usa `trail`,
`src`, `g_atr[i]` che sono già calcolati.

---

## MODIFICA 7: Barra corrente — nuovi buffer

### Nel blocco `else` della barra corrente (dopo B_State[i] = B_State[i-1], riga ~2095), AGGIUNGERE:

```mql5
         B_BiasGate[i]      = EMPTY_VALUE;
         B_BiasContra[i]    = EMPTY_VALUE;
         B_BiasContraClr[i] = 0.0;
         // Chandelier: carry-forward (non repaint — livelli confermati)
         if(InpShowChandelier)
           {
            B_ChandLong[i]  = (src > trail) ? g_chandLastLong  : EMPTY_VALUE;
            B_ChandShort[i] = (src < trail) ? g_chandLastShort : EMPTY_VALUE;
           }
         else
           {
            B_ChandLong[i]  = EMPTY_VALUE;
            B_ChandShort[i] = EMPTY_VALUE;
           }
```

---

## MODIFICA 8: fullRecalc init block

### Nel blocco `if(fullRecalc || B_Trail[trail_start-1] == 0.0)`, AGGIUNGERE:

```mql5
      B_BiasGate[trail_start - 1]     = EMPTY_VALUE;
      B_ChandLong[trail_start - 1]    = EMPTY_VALUE;
      B_ChandShort[trail_start - 1]   = EMPTY_VALUE;
      B_BiasContra[trail_start - 1]   = EMPTY_VALUE;
      B_BiasContraClr[trail_start - 1] = 0;
```

### Aggiungere reset Chandelier state:

```mql5
      g_chandHH         = 0;
      g_chandLL         = 0;
      g_chandLastLong   = 0;
      g_chandLastShort  = 999999;
```

---

## MODIFICA 9: Dashboard — pulsante CHAND

### Dopo il pulsante BIAS nella sezione VISUALS, AGGIUNGERE:

```mql5
   // [v4.00] Chandelier overlay toggle
   if(InpShowChandelier)
     {
      vst = g_dash_vis_chand ? "● ON" : "○ OFF";
      vcl = g_dash_vis_chand ? C'70,200,130' : C'50,70,120';
      UTBSetRow(row, "Chandelier         " + vst, vcl);
      UTBSetBtn("CHAND", g_dash_vis_chand, y_base + 6 + row * y_step);
      row++;
     }
```

### UTB_DASH_MAX_ROWS: aggiornare
```
VECCHIO: #define UTB_DASH_MAX_ROWS 28
NUOVO:   #define UTB_DASH_MAX_ROWS 30
```

### Button pool: da 6 a 7 pulsanti (riga 1260-1262)
```
VECCHIO (riga 1260-1262):
   //--- Button pool (6 toggle: TRAIL, ARROWS, ENTRY, CANDLES, FLAT, BIAS)
   string btnIds[6] = {"TRAIL", "ARROWS", "ENTRY", "CANDLES", "FLAT", "BIAS"};
   for(int i = 0; i < 6; i++)

NUOVO:
   //--- Button pool (7 toggle: TRAIL, ARROWS, ENTRY, CANDLES, FLAT, BIAS, CHAND)
   string btnIds[7] = {"TRAIL", "ARROWS", "ENTRY", "CANDLES", "FLAT", "BIAS", "CHAND"};
   for(int i = 0; i < 7; i++)
```

---

## MODIFICA 10: OnChartEvent — handler CHAND

### Dopo il handler BIAS (dopo `g_forceRecalcCounter++`), INSERIRE:

```mql5
   //--- [v4.00] CHAND: toggle visivo Plot 13-14 (Chandelier Long + Short)
   if(btn_id == "CHAND")
     {
      g_dash_vis_chand = !g_dash_vis_chand;
      PlotIndexSetInteger(13, PLOT_DRAW_TYPE,
                          g_dash_vis_chand ? DRAW_LINE : DRAW_NONE);
      PlotIndexSetInteger(14, PLOT_DRAW_TYPE,
                          g_dash_vis_chand ? DRAW_LINE : DRAW_NONE);
     }
```

---

## MODIFICA 11: iCustom call — nuovi parametri

### SOSTITUIRE la chiamata iCustom (righe ~805-817) con:

```mql5
      g_htfHandle = iCustom(_Symbol, g_eff_biasTF, "UTBotAdaptive-Ok-V1",
                            InpTFPreset,      InpKeyValue,      InpATRPeriod,
                            InpSrcType,       InpHMAPeriod,
                            InpKAMA_N,        InpKAMA_Fast,     InpKAMA_Slow,
                            InpJMA_Period,    InpJMA_Phase,
                            false, PERIOD_H1,                   // bias OFF (child)
                            false, 0.0, 0.20, 8, false,         // Flat OFF (child)
                            false, 2.5, true,                    // Chand OFF, defaults (child)
                            false, false,                        // ColorBars OFF, Arrows OFF
                            false, false,                        // Theme OFF, Grid OFF
                            InpThemeBG, InpThemeFG, InpThemeGrid,
                            InpThemeBullCandl, InpThemeBearCandl,
                            false, false,                        // Alert OFF
                            false, false);                       // Dashboard OFF, Trail OFF
```

---

## VERIFICA FINALE — Checklist

- [ ] `#property version "4.00"`, buffers 35, plots 16
- [ ] 3 nuovi #property plot (14: Chand Long, 15: Chand Short, 16: BiasContra)
- [ ] 3 nuovi input (InpShowChandelier, InpChandMult, InpChandVolNorm)
- [ ] 5 nuovi buffer arrays (B_BiasGate, B_ChandLong, B_ChandShort, B_BiasContra, B_BiasContraClr)
- [ ] 5 SetIndexBuffer (30-34)
- [ ] PlotIndexSetInteger(15, PLOT_ARROW, 169) per diamond ◆
- [ ] PlotIndexSetDouble empty per plot 13, 14, 15
- [ ] Toggle Chandelier e BiasContra in OnInit
- [ ] Init variabili: g_chandHH/LL/LastLong/LastShort, g_dash_vis_chand
- [ ] BiasGate: rawBuy/rawSell senza bias → tagging 1.0/0.0 → marker ◆ su contro-bias
- [ ] Chandelier: anchored da crossover, ratchet MathMax/MathMin, vol normalization
- [ ] Chandelier reset su crossover trail (chandReset flag)
- [ ] Barra corrente: 5 nuovi buffer a EMPTY_VALUE, Chandelier carry-forward
- [ ] fullRecalc init: 5 nuovi buffer + reset Chandelier state
- [ ] Dashboard: pulsante CHAND con toggle plot 13-14
- [ ] OnChartEvent: handler CHAND
- [ ] iCustom: 3 nuovi parametri (false, 2.5, true per child)
- [ ] Button pool: da 6 a 7 (riga 1260-1262: btnIds[7], for < 7)
- [ ] UTB_DASH_MAX_ROWS → 30

---

## NOTA ARCHITETTURALE: BiasGate e segnali contro-bias

I segnali contro-bias (rawBuy=true ma isBuy=false perché il bias HTF li blocca) hanno:
- Buy1[i] = EMPTY_VALUE (nessuna freccia)
- BiasGate[i] = 0.0 (contro-bias)
- BiasContra[i] = prezzo marker ◆ (visivo)

L'EA leggendo Buy1 NON vede segnali contro-bias. Questo è il comportamento CORRETTO
per EXIT_CHANDELIER e EXIT_HYBRID: il Chandelier gestisce l'uscita indipendentemente.
Se in futuro servisse all'EA di rilevare crossover contro-bias per chiusura attiva,
si aggiungerà un buffer B_RawState separato.

---

## BUFFER MAP PER EA EXTERN (v4.00)

```
CopyBuffer(handle, 2,  ...)  → Buy1 signal (EMPTY_VALUE = no signal)
CopyBuffer(handle, 8,  ...)  → Sell1 signal
CopyBuffer(handle, 26, ...)  → ER (0.0-1.0)
CopyBuffer(handle, 27, ...)  → State (+1.0 long, -1.0 short, 0.0 neutro)
CopyBuffer(handle, 28, ...)  → FlatState (1.0 = active, 0.0 = flat)
CopyBuffer(handle, 29, ...)  → ChannelWidth (in prezzo)
CopyBuffer(handle, 30, ...)  → BiasGate (1.0=con-bias → apri, 0.0=contro-bias → solo close)
CopyBuffer(handle, 31, ...)  → ChandLong (trailing long level, EMPTY se regime SHORT)
CopyBuffer(handle, 32, ...)  → ChandShort (trailing short level, EMPTY se regime LONG)
```

### Logica EA con i nuovi buffer:

```
// Ingresso:
Se Buy1 signal E FlatState=1.0:
    Se BiasGate=1.0 → APRI BUY
    Se BiasGate=0.0 → SOLO CLOSE SHORT (se aperto), NON aprire BUY

// Uscita con Chandelier (ExitMode = EXIT_CHANDELIER):
Se posizione LONG aperta:
    Se Bid <= ChandLong → CLOSE LONG (nessun SELL automatico)
Se posizione SHORT aperta:
    Se Ask >= ChandShort → CLOSE SHORT (nessun BUY automatico)

// Lateralità:
Se FlatState=0.0 → non aprire nuovi trade, Chandelier protegge i trade aperti
```

---

*Fine Fase 2 — Modifiche indicatore UTBot V3.52 → V4.00*
