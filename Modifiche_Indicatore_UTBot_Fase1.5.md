# Modifiche Indicatore UTBot V3.01 → V3.50 — Fase 1.5

## File sorgente: `UTBotAdaptive-Ok-V1.mq5` (1943 righe, v3.01)
## Versione target: v3.50

**Nessun nuovo buffer. Nessun nuovo plot. Nessun nuovo input.**
Solo fix logici, miglioramento HTF, pulsanti dashboard.

---

## ELENCO MODIFICHE

1. Versione header
2. Nuove variabili globali
3. OnInit: handle HTF sempre creato + init variabili
4. Preset FlatMinWidth rivisti
5. OnCalculate: force-recalc counter
6. OnCalculate: HTF bias per-bar (fullRecalc)
7. OnCalculate: bias per-bar dentro il loop
8. OnCalculate: fix zona FLAT Donchian orizzontale
9. Dashboard: righe BIAS e FLAT + 2 pulsanti
10. OnChartEvent: handler BIAS e FLAT
11. UTB_DASH_MAX_ROWS aggiornato

---

## MODIFICA 1: Versione header

### Riga 95:
```
VECCHIO: #property version   "3.01"
NUOVO:   #property version   "3.50"
```

Buffer e plot INVARIATI: `indicator_buffers 30`, `indicator_plots 13`.

---

## MODIFICA 2: Nuove variabili globali

### Dopo riga 457 (g_dash_vis_candles), INSERIRE:

```mql5
bool   g_dash_vis_flatzone = true;   // Flat zone visibilità (toggle dashboard)
bool   g_dash_vis_bias     = true;   // Bias HTF attivo (toggle logico dashboard)
```

### Dopo riga 461 (g_dash_ratesTotal), INSERIRE:

```mql5
// --- HTF Bias runtime toggle (v3.50) ---
bool   g_biasEnabled;                // runtime toggle (init da InpUseBias)
int    g_forceRecalcCounter = 0;     // incrementato da OnChartEvent per forzare fullRecalc

// --- Flat zone Donchian (v3.50) ---
double g_flatRangeHigh;              // HH dall'inizio della flat zone
double g_flatRangeLow;               // LL dall'inizio della flat zone
bool   g_wasFlatPrev;                // isFlat della barra precedente
```

---

## MODIFICA 3: OnInit — handle HTF + init variabili

### Riga 742: rimuovere InpUseBias dalla condizione di creazione handle
Il handle HTF viene SEMPRE creato (se TF diverso), indipendentemente da InpUseBias.
Così il toggle dashboard BIAS funziona anche se InpUseBias era false all'avvio.

```
VECCHIO (riga 742): if(InpUseBias && _Period != InpBiasTF)
NUOVO:              if(_Period != InpBiasTF)
```

### Dopo riga 847 (g_dash_vis_candles = InpColorBars), INSERIRE:

```mql5
   // [v3.50] Init stato runtime
   g_biasEnabled     = InpUseBias;
   g_dash_vis_bias   = InpUseBias;
   g_dash_vis_flatzone = InpShowFlatZone;
   g_wasFlatPrev     = false;
   g_flatRangeHigh   = 0;
   g_flatRangeLow    = 0;
```

---

## MODIFICA 4: Preset FlatMinWidth rivisti

### Modificare i valori g_eff_flatMinWidth in UTBotPresetsInit():

```
Riga 526 (M1):   g_eff_flatMinWidth = 3.0 → 2.0
Riga 538 (M5):   g_eff_flatMinWidth = 5.0 → 3.5
Riga 550 (M15):  g_eff_flatMinWidth = 8.0 → 6.0
Riga 562 (M30):  g_eff_flatMinWidth = 12.0 → 10.0
Riga 574 (H1):   g_eff_flatMinWidth = 18.0 → 15.0
Riga 586 (H4):   g_eff_flatMinWidth = 25.0 → 20.0
```

---

## MODIFICA 5: OnCalculate — Force-recalc counter

### Dopo riga 1556 (`int start = fullRecalc ? 1 : prev_calculated - 1;`), INSERIRE:

```mql5
   // [v3.50] Force fullRecalc quando dashboard toggle BIAS cambia stato.
   // g_forceRecalcCounter viene incrementato in OnChartEvent.
   // Al prossimo tick, il contatore diverso da s_lastRecalcCheck forza fullRecalc.
   static int s_lastRecalcCheck = 0;
   if(g_forceRecalcCounter != s_lastRecalcCheck)
     {
      s_lastRecalcCheck = g_forceRecalcCounter;
      fullRecalc = true;
      start = 1;
     }
```

---

## MODIFICA 6: HTF bias per-bar durante fullRecalc

### SOSTITUIRE righe 1662-1675 (intero blocco bias HTF) con:

```mql5
   //--- HTF Bias — per-bar durante fullRecalc, singolo altrimenti ---
   // [v3.50] Durante fullRecalc, il bias va letto barra per barra dall'istanza
   // HTF per avere il backtest visivo corretto. In v3.01 il bias era letto
   // UNA volta prima del loop → tutte le barre storiche usavano il bias ODIERNO,
   // falsando le frecce storiche. Ora si copia l'intero B_State array dall'HTF
   // e si usa iBarShift per mappare ogni barra LTF alla corrispondente HTF.

   // Copia intera serie B_State dall'HTF (una volta sola, efficiente)
   double htfStateArr[];
   int htfCopied = 0;
   bool htfAvailable = g_biasEnabled && g_htfHandle != INVALID_HANDLE;
   if(htfAvailable)
     {
      int htfBars = iBars(_Symbol, InpBiasTF);
      if(htfBars > 0)
        {
         ArraySetAsSeries(htfStateArr, true);
         htfCopied = CopyBuffer(g_htfHandle, 27, 0, htfBars, htfStateArr);
        }
     }

   // Per il path incrementale: bias corrente (barra chiusa HTF)
   double htfStateCurrent = 0.0;
   if(htfAvailable && htfCopied > 1)
      htfStateCurrent = htfStateArr[1]; // offset=1, barra chiusa HTF corrente

   g_lastHtfState = htfStateCurrent;   // per dashboard

   // Default biasLong/biasShort per path incrementale
   // Verranno sovrascritti barra-per-barra nel loop durante fullRecalc
   bool biasLong  = !g_biasEnabled || (htfStateCurrent > 0.5);
   bool biasShort = !g_biasEnabled || (htfStateCurrent < -0.5);
```

---

## MODIFICA 7: Dentro il loop — bias per-bar

### DOPO riga 1696 (`B_TrailClr[i] = (src > trail) ? 0.0 : 1.0;`),
### PRIMA della sezione ER (riga 1698 `// [v3.00] Efficiency Ratio`), INSERIRE:

```mql5
      // [v3.50] Per-bar HTF bias durante fullRecalc
      // Sovrascrivi biasLong/biasShort con lo stato HTF al momento della barra i.
      // iBarShift converte il tempo LTF nell'indice HTF. +1 = barra chiusa.
      // htfStateArr è in modalità series (indice 0 = barra più recente).
      if(fullRecalc && htfAvailable && htfCopied > 0)
        {
         int htfShift = iBarShift(_Symbol, InpBiasTF, time[i]);
         int htfIdx = htfShift + 1; // +1 = barra chiusa HTF (anti-repainting)
         double htfBarState = 0.0;
         if(htfIdx >= 0 && htfIdx < htfCopied)
            htfBarState = htfStateArr[htfIdx];
         biasLong  = !g_biasEnabled || (htfBarState > 0.5);
         biasShort = !g_biasEnabled || (htfBarState < -0.5);
        }
```

**NOTA**: Le righe 1774-1775 (isBuy/isSell con biasLong/biasShort) restano INVARIATE.
Il bias continua a bloccare i segnali contro-bias (come V3.01). La differenza è
che il blocco è ora CORRETTO storicamente (per-bar) e attivabile/disattivabile dal dashboard.

---

## MODIFICA 8: Fix zona FLAT Donchian orizzontale

### SOSTITUIRE righe 1745-1766 (intero blocco flat zone visualization) con:

```mql5
      //--- Flat zone visualization — Donchian orizzontale (v3.50) ---
      // [v3.50] Il canale usa HH/LL persistenti dall'inizio della lateralità.
      // Le bande sono ORIZZONTALI (si espandono solo se prezzo fa nuovo HH/LL).
      // Alla fine della lateralità scompaiono istantaneamente (EMPTY_VALUE).
      if(isFlat && InpShowFlatZone && InpFlatDetect)
        {
         if(!g_wasFlatPrev)   // inizio nuova zona flat
           {
            g_flatRangeHigh = high[i];
            g_flatRangeLow  = low[i];
           }
         else                 // flat continua — espandi range
           {
            if(high[i] > g_flatRangeHigh) g_flatRangeHigh = high[i];
            if(low[i]  < g_flatRangeLow)  g_flatRangeLow  = low[i];
           }

         B_FlatFillUp[i] = g_flatRangeHigh;
         B_FlatFillDn[i] = g_flatRangeLow;
         B_FlatLineUp[i] = g_flatRangeHigh;
         B_FlatLineDn[i] = g_flatRangeLow;
        }
      else
        {
         B_FlatFillUp[i] = EMPTY_VALUE;
         B_FlatFillDn[i] = EMPTY_VALUE;
         B_FlatLineUp[i] = EMPTY_VALUE;
         B_FlatLineDn[i] = EMPTY_VALUE;
        }
      g_wasFlatPrev = isFlat;
```

---

## MODIFICA 9: Dashboard — righe BIAS e FLAT + pulsanti

### Riga 459: aggiornare max rows
```
VECCHIO: #define UTB_DASH_MAX_ROWS 24
NUOVO:   #define UTB_DASH_MAX_ROWS 28
```

### Nella sezione Bias HTF del dashboard (righe 1373-1383), SOSTITUIRE con:

```mql5
   // [v3.50] Bias HTF — usa g_biasEnabled (runtime toggle)
   if(g_biasEnabled && g_htfHandle != INVALID_HANDLE)
     {
      string htfDir = (g_lastHtfState > 0.5)  ? "LONG ▲" :
                      (g_lastHtfState < -0.5) ? "SHORT ▼" : "NEUTRO";
      color  htfClr = (g_lastHtfState > 0.5)  ? C'50,220,120' :
                      (g_lastHtfState < -0.5) ? C'239,83,80'  : C'150,165,185';
      UTBSetRow(row++, "Bias HTF: " + EnumToString(InpBiasTF) + " " + htfDir, htfClr);
     }
   else if(g_htfHandle != INVALID_HANDLE)
      UTBSetRow(row++, "Bias HTF: OFF (toggle)", C'80,90,110');
   else
      UTBSetRow(row++, "Bias HTF: N/A (stesso TF)", C'60,60,80');
```

### Dopo il pulsante CANDLES (riga 1447, dopo `row++;`),
### INSERIRE PRIMA di `//--- Hide unused rows` (riga 1449):

```mql5
   // [v3.50] Flat Zone toggle (visivo: mostra/nasconde canale blu)
   vst = g_dash_vis_flatzone ? "● ON" : "○ OFF";
   vcl = g_dash_vis_flatzone ? C'70,200,130' : C'50,70,120';
   UTBSetRow(row, "Flat Zone          " + vst, vcl);
   UTBSetBtn("FLAT", g_dash_vis_flatzone, y_base + 6 + row * y_step);
   row++;

   // [v3.50] Bias HTF toggle (LOGICO: attiva/disattiva bias + forza recalc)
   if(g_htfHandle != INVALID_HANDLE)
     {
      vst = g_dash_vis_bias ? "● ON" : "○ OFF";
      vcl = g_dash_vis_bias ? C'70,200,130' : C'50,70,120';
      UTBSetRow(row, "Bias HTF           " + vst, vcl);
      UTBSetBtn("BIAS", g_dash_vis_bias, y_base + 6 + row * y_step);
      row++;
     }
```

---

## MODIFICA 10: OnChartEvent — handler BIAS e FLAT

### Dopo il handler CANDLES (riga ~1522), INSERIRE prima di `UpdateUTBDashboard(true);` (riga 1524):

```mql5
   //--- [v3.50] FLAT: toggle visivo Plot 9-11 (fill + upper + lower)
   if(btn_id == "FLAT")
     {
      g_dash_vis_flatzone = !g_dash_vis_flatzone;
      PlotIndexSetInteger(9,  PLOT_DRAW_TYPE,
                          g_dash_vis_flatzone ? DRAW_FILLING : DRAW_NONE);
      PlotIndexSetInteger(10, PLOT_DRAW_TYPE,
                          g_dash_vis_flatzone ? DRAW_LINE : DRAW_NONE);
      PlotIndexSetInteger(11, PLOT_DRAW_TYPE,
                          g_dash_vis_flatzone ? DRAW_LINE : DRAW_NONE);
     }

   //--- [v3.50] BIAS: toggle LOGICO + force recalc
   // Cambia g_biasEnabled → tutte le frecce storiche vengono ricalcolate
   // al prossimo OnCalculate con il nuovo stato del bias.
   if(btn_id == "BIAS")
     {
      g_dash_vis_bias = !g_dash_vis_bias;
      g_biasEnabled = g_dash_vis_bias;
      g_forceRecalcCounter++;  // forza fullRecalc al prossimo tick
     }
```

---

## VERIFICA FINALE — Checklist

- [ ] `#property version "3.50"` — buffer 30, plot 13 INVARIATI
- [ ] 7 nuove variabili globali dichiarate
- [ ] OnInit: `if(_Period != InpBiasTF)` (rimosso InpUseBias dalla condizione)
- [ ] OnInit: 7 variabili inizializzate dopo g_dash_vis_candles
- [ ] FlatMinWidth: 6 preset aggiornati (M1:2.0 M5:3.5 M15:6.0 M30:10.0 H1:15.0 H4:20.0)
- [ ] Force-recalc: dichiarato, incrementato in BIAS handler, rilevato in OnCalculate
- [ ] HTF per-bar: htfStateArr copiato prima loop, iBarShift dentro loop in fullRecalc
- [ ] g_biasEnabled al posto di InpUseBias in bias read e dashboard
- [ ] Flat Donchian: HH/LL persistenti, g_wasFlatPrev, bande orizzontali
- [ ] Dashboard: 2 nuovi pulsanti (FLAT visivo, BIAS logico)
- [ ] OnChartEvent: 2 nuovi handler
- [ ] UTB_DASH_MAX_ROWS 24 → 28
- [ ] Nessun nuovo buffer, nessun nuovo plot, nessun nuovo input
- [ ] iCustom call INVARIATA
- [ ] Righe 1774-1775 (isBuy/isSell) INVARIATE

---

*Fine Fase 1.5 — Modifiche indicatore UTBot V3.01 → V3.50*
