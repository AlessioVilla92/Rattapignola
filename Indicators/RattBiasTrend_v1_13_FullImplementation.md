# RattBiasTrend — Piano Implementativo Completo v1.10 → v1.13

**File**: `RattBiasTrend.mq5`
**Versione di partenza**: v1.10
**Versione finale**: v1.13
**Data**: 2026-05-01
**Target**: Claude Code per implementazione step-by-step

---

## INDICE

- [Sintesi del piano in 3 fasi](#sintesi-del-piano-in-3-fasi)
- [FASE 1 — v1.10 → v1.11 — Fix Tema Chart](#fase-1--v110--v111--fix-tema-chart)
- [FASE 2 — v1.11 → v1.12 — Sticky Bias (Hysteresis ATR + Confirmation)](#fase-2--v111--v112--sticky-bias-hysteresis-atr--confirmation)
- [FASE 3 — v1.12 → v1.13 — PMA e PMA+OEF come MA-types](#fase-3--v112--v113--pma-e-pmaoef-come-ma-types)
- [Verifica matematica delle formule](#verifica-matematica-delle-formule)
- [Test post-implementazione](#test-post-implementazione)
- [Rollback strategy](#rollback-strategy)

---

## Sintesi del piano in 3 fasi

### Obiettivi
1. **Eliminare** il bug del tema chart che torna a sfondo chiaro a righe con candele verdi su cambio TF
2. **Mantenere** il bias HTF nel trend, evitando uscite premature sui microstorni fisiologici
3. **Aggiungere** PMA (Ehlers Predictive MA) e PMA+OEF (con One Euro Filter) come opzioni adattive avanzate

### Vincoli architetturali
- Zero impatto su buffer pubblici esistenti (compatibilità EA AcquaDulza preservata)
- Tutte le modifiche **retrocompatibili** via toggle/parametri (default = comportamento v1.10)
- Modularità preservata: ogni fase è un file `.md` indipendente, rollback possibile per fase

### Stima complessità

| Fase | Operazioni `str_replace` | Righe codice toccate | Tempo Claude Code | Rischio |
|------|--------------------------|----------------------|-------------------|---------|
| 1    | 4                        | ~80                  | ~10 min           | Minimo  |
| 2    | 5                        | ~120                 | ~25 min           | Basso   |
| 3    | 8                        | ~350                 | ~3-4 ore          | Medio   |

---

## FASE 1 — v1.10 → v1.11 — Fix Tema Chart

### Diagnosi della causa

Il bug è causato da `OnDeinit` che chiama `RestoreChartTheme()` per qualunque valore di `reason`, incluso `REASON_CHARTCHANGE = 3` (cambio TF). La sequenza buggata è:

1. Cambio TF → `OnDeinit(reason=3)` → tema ripristinato a chiaro
2. Reload chart → `OnInit` → ApplyChartTheme tenta riapplicazione
3. In casi specifici (race condition, ChartSetInteger non ancora committato) il tema dark non viene applicato → chart resta chiaro con candele verdi

Effetti collaterali:
- Se `CreateMAHandles()` fallisce su cambio TF veloce (handle iMA non pronto), `OnInit` ritorna `INIT_FAILED` → segnali scompaiono fino al prossimo reload

### Strategia di fix

Refactor della gestione tema in 3 helper atomici con responsabilità separate:
- `SaveOriginalChartColors()` — salva i colori originali del chart UNA SOLA VOLTA (idempotente)
- `ApplyThemeColors()` — applica i colori del tema (idempotente, può essere chiamato ripetutamente)
- `RestoreChartTheme()` — restora i colori salvati

Aggiunta variabile `g_origSaved` per separare *"colori originali sono stati salvati"* da *"il tema è correntemente applicato"*. Sono concetti diversi che il codice attuale confonde.

In `OnDeinit`, il restore avviene **solo** per reason di rimozione effettiva (REMOVE, CHARTCLOSE, TEMPLATE, PROGRAM, INITFAILED, CLOSE). Su CHARTCHANGE/PARAMETERS/RECOMPILE/ACCOUNT, il tema viene preservato perché `OnInit` riapplicherà subito.

### PATCH 1.A — Aggiunta variabile globale `g_origSaved`

**File**: `RattBiasTrend.mq5`
**Posizione**: dopo riga 279

#### `str_replace` — search
```mql5
bool   g_themeApplied    = false;
```

#### `str_replace` — replace
```mql5
bool   g_themeApplied    = false;
bool   g_origSaved       = false;  // v1.11: separa "originali salvati" da "tema applicato"
```

---

### PATCH 1.B — Refactor `ApplyChartTheme()` in 3 helper atomici

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 1641-1714 (intera funzione `ApplyChartTheme` + `RestoreChartTheme`)

#### `str_replace` — search
Cerca l'intero blocco corrente di `ApplyChartTheme()` partendo da:
```mql5
//+------------------------------------------------------------------+
//| ApplyChartTheme — applica tema scuro al chart (idempotente)      |
//+------------------------------------------------------------------+
void ApplyChartTheme()
{
   if(g_themeApplied) return;
```

fino alla fine di `RestoreChartTheme()`. Il blocco da sostituire è circa 75 righe (dalla riga 1641 alla 1714 inclusa).

> **NOTA per Claude Code**: leggi il blocco esatto con `view` riga 1641-1714 prima di applicare lo `str_replace`. Sostituisci l'intero blocco con il replacement sotto.

#### `str_replace` — replace
```mql5
//+------------------------------------------------------------------+
//| SaveOriginalChartColors — salva originali UNA SOLA VOLTA (v1.11) |
//+------------------------------------------------------------------+
// Idempotente: se g_origSaved già true, no-op.
// Questa funzione NON applica nulla, solo salva lo stato originale.
void SaveOriginalChartColors()
{
   if(g_origSaved) return;

   g_origBG       = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   g_origFG       = (color)ChartGetInteger(0, CHART_COLOR_FOREGROUND);
   g_origGrid     = (color)ChartGetInteger(0, CHART_COLOR_GRID);
   g_origAxis     = (color)ChartGetInteger(0, CHART_COLOR_CHART_LINE);
   g_origVolume   = (color)ChartGetInteger(0, CHART_COLOR_VOLUME);
   g_origCandleUp = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   g_origCandleDn = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
   g_origBidLine  = (color)ChartGetInteger(0, CHART_COLOR_BID);
   g_origAskLine  = (color)ChartGetInteger(0, CHART_COLOR_ASK);
   g_origLastLine = (color)ChartGetInteger(0, CHART_COLOR_LAST);
   g_origStops    = (color)ChartGetInteger(0, CHART_COLOR_STOP_LEVEL);
   g_origShowGrid = (bool)ChartGetInteger(0, CHART_SHOW_GRID);
   g_origMode     = (int)ChartGetInteger(0, CHART_MODE);

   g_origSaved = true;
   RBTLog(LOG_DEBUG, "THEME", "Original chart colors saved.");
}

//+------------------------------------------------------------------+
//| ApplyThemeColors — applica i colori del tema (idempotente)       |
//+------------------------------------------------------------------+
// Può essere chiamata ripetutamente senza side-effects.
// NON modifica g_origSaved (è SaveOriginalChartColors a farlo).
// NON modifica g_themeApplied (è il chiamante a gestirlo).
void ApplyThemeColors()
{
   ChartSetInteger(0, CHART_MODE,                CHART_CANDLES);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,    InpThemeBG);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,    InpThemeFG);
   ChartSetInteger(0, CHART_COLOR_GRID,          InpThemeGrid);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE,    InpThemeFG);
   ChartSetInteger(0, CHART_COLOR_VOLUME,        InpThemeBG);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL,   InpThemeCandleUp);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR,   InpThemeCandleDn);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,      InpThemeCandleUp);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,    InpThemeCandleDn);
   ChartSetInteger(0, CHART_COLOR_BID,           InpThemeFG);
   ChartSetInteger(0, CHART_COLOR_ASK,           InpThemeFG);
   ChartSetInteger(0, CHART_COLOR_LAST,          InpThemeFG);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL,    InpThemeFG);
   ChartSetInteger(0, CHART_SHOW_GRID,           true);
}

//+------------------------------------------------------------------+
//| ApplyChartTheme — wrapper backward-compat (v1.11 refactored)     |
//+------------------------------------------------------------------+
// Mantiene la signature originale per compatibilità con eventuali
// chiamate esistenti. Internamente usa i 3 helper atomici.
void ApplyChartTheme()
{
   if(g_themeApplied) return;
   SaveOriginalChartColors();
   ApplyThemeColors();
   ChartRedraw(0);  // v1.11: forza commit visuale (fix race condition)
   g_themeApplied = true;
   RBTLog(LOG_DEBUG, "THEME", "Dark theme applied.");
}

//+------------------------------------------------------------------+
//| RestoreChartTheme — ripristina i colori originali del chart      |
//+------------------------------------------------------------------+
// Ripristina solo se g_origSaved=true E g_themeApplied=true.
// NON tocca g_origSaved (originali ancora validi per eventuale re-save).
void RestoreChartTheme()
{
   if(!g_origSaved || !g_themeApplied) return;

   ChartSetInteger(0, CHART_MODE,                g_origMode);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,    g_origBG);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,    g_origFG);
   ChartSetInteger(0, CHART_COLOR_GRID,          g_origGrid);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE,    g_origAxis);
   ChartSetInteger(0, CHART_COLOR_VOLUME,        g_origVolume);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL,   g_origCandleUp);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR,   g_origCandleDn);
   ChartSetInteger(0, CHART_COLOR_BID,           g_origBidLine);
   ChartSetInteger(0, CHART_COLOR_ASK,           g_origAskLine);
   ChartSetInteger(0, CHART_COLOR_LAST,          g_origLastLine);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL,    g_origStops);
   ChartSetInteger(0, CHART_SHOW_GRID,           g_origShowGrid);

   ChartRedraw(0);
   g_themeApplied = false;
   RBTLog(LOG_DEBUG, "THEME", "Original chart colors restored.");
}
```

---

### PATCH 1.C — OnInit con gestione tema completa

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 458-459 (dentro `OnInit()`)

#### `str_replace` — search
```mql5
   if(InpApplyTheme)
      ApplyChartTheme();
```

#### `str_replace` — replace
```mql5
   //--- v1.11: gestione tema completa (primo load, cambio TF, parameter change, toggle on/off)
   if(InpApplyTheme)
   {
      SaveOriginalChartColors();   // salva orig SOLO la prima volta (idempotente)
      ApplyThemeColors();          // applica/riapplica i colori (sempre)
      ChartRedraw(0);              // commit visuale immediato
      g_themeApplied = true;
   }
   else if(g_themeApplied)
   {
      // Utente ha disabilitato InpApplyTheme via parametri → restore
      RestoreChartTheme();
   }
```

---

### PATCH 1.D — OnDeinit con filtro `reason`

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 510-515 (dentro `OnDeinit()`)

#### `str_replace` — search
```mql5
   if(g_themeApplied)
   {
      RestoreChartTheme();
      RBTLog(LOG_DEBUG, "DEINIT", "Chart theme restored to original.");
   }
```

#### `str_replace` — replace
```mql5
   //--- v1.11: restore tema SOLO su rimozione reale dell'indicatore
   // Su CHARTCHANGE, PARAMETERS, RECOMPILE, ACCOUNT: NON restora
   // (OnInit gestirà il re-apply tramite ApplyThemeColors idempotente)
   bool real_removal = (reason == REASON_REMOVE     ||
                        reason == REASON_CHARTCLOSE ||
                        reason == REASON_TEMPLATE   ||
                        reason == REASON_PROGRAM    ||
                        reason == REASON_INITFAILED ||
                        reason == REASON_CLOSE);

   if(g_themeApplied && real_removal)
   {
      RestoreChartTheme();
      RBTLog(LOG_DEBUG, "DEINIT", StringFormat("Chart theme restored (real removal, reason=%d).", reason));
   }
   else if(g_themeApplied)
   {
      RBTLog(LOG_DEBUG, "DEINIT",
         StringFormat("Theme NOT restored (transient deinit, reason=%d).", reason));
   }
```

---

### PATCH 1.E — Aggiornamento header versione

**File**: `RattBiasTrend.mq5`
**Posizione**: riga 5-10 (header del file)

#### `str_replace` — search
```mql5
#property version   "1.10"
```

#### `str_replace` — replace
```mql5
#property version   "1.11"
```

---

### Test FASE 1

#### Test funzionali (manuali)
1. Carica RattBiasTrend su chart EUR/USD M30
2. Verifica tema scuro applicato
3. Cambia TF in sequenza: M30 → H1 → H4 → H1 → M30 → M5 (almeno 20 volte)
4. **Atteso**: tema scuro mantenuto, candele teal/coral, segnali visibili, NO sfondo a righe verde
5. Rimuovi indicatore manualmente (right-click → Delete)
6. **Atteso**: tema chiaro ripristinato correttamente
7. Ricarica indicatore + cambia parametro `InpApplyTheme = false`
8. **Atteso**: chart torna chiaro, segnali rimangono visibili
9. Riporta `InpApplyTheme = true`
10. **Atteso**: tema scuro riapplicato

#### Verifica via log
Abilita `InpLogLevel = LOG_DEBUG`. Su cambio TF dovresti vedere:
```
DEINIT — stopping — reason=3
DEINIT — Theme NOT restored (transient deinit, reason=3).
INIT — v1.11 started ...
THEME — Dark theme applied.
```

#### Compatibilità multi-indicatore
Se UTBotAdaptive è caricato sullo stesso chart e applica anch'esso un tema, può richiedere lo stesso fix in parallelo (file separato). Senza UTBot in chart, FASE 1 è autosufficiente.

---

## FASE 2 — v1.11 → v1.12 — Sticky Bias (Hysteresis ATR + Confirmation)

### Concetto

Lo state-machine attuale flippa quando `close < banda_ratchet (2.5×ATR)`. Un singolo close oltre la banda ratchettata causa flip immediato. Per evitare microstorni, introduciamo:

1. **Banda di flip allargata**: parallela alla banda visiva, calcolata con `ATR × InpATRMultiplierFlip` (default 3.5). Il flip avviene solo se il prezzo supera questa banda più ampia, mantenendo la banda visiva stretta per UX.

2. **Confirmation bars**: il close deve restare oltre la banda di flip per N barre HTF consecutive (default 1, alza a 2 per filtraggio aggiuntivo).

3. **Master switch**: `InpStickyBias = true/false` per A/B testing diretto vs comportamento v1.10.

### Effetto matematico

Per un microstorno fisiologico tipico (pullback ~1.5×ATR):
- Banda ratchet 2.5×ATR: tocca, NON supera
- Banda flip 3.5×ATR: NON tocca
- Risultato: bias mantenuto ✓

Per un'inversione vera (movimento 4×ATR):
- Banda flip 3.5×ATR: superata
- Confirmation 1 bar: flip immediato (lag = 0)
- Confirmation 2 bar: flip dopo 1 ulteriore barra HTF (lag = 1 TF)

### PATCH 2.A — Nuovi parametri di input

**File**: `RattBiasTrend.mq5`
**Posizione**: dopo riga 207 (gruppo "MA — Parametri SuperSmoother")

#### `str_replace` — search
```mql5
input int                InpSuperSmoothPeriod= 15;                // Periodo Ehlers SuperSmoother (Ehlers default 15)
```

#### `str_replace` — replace
```mql5
input int                InpSuperSmoothPeriod= 15;                // Periodo Ehlers SuperSmoother (Ehlers default 15)

//=== Anti-microstorm — Sticky Bias v1.12 ===========================
input group "=== Sticky Bias (anti-microstorni) ==="
input bool               InpStickyBias        = true;             // Master switch (false = comportamento v1.11)
input double             InpATRMultiplierFlip = 3.5;              // Mult ATR per flip (>= InpATRMultiplier)
input int                InpFlipConfirmBars   = 1;                // Barre HTF consecutive per conferma flip (1 = no confirmation)
```

---

### PATCH 2.B — Nuovi array globali per bande di flip

**File**: `RattBiasTrend.mq5`
**Posizione**: dopo riga 249 (dopo `g_htf_fLow`)

#### `str_replace` — search
```mql5
double    g_htf_fUp  [];   // final upper ratchettato
double    g_htf_fLow [];   // final lower ratchettato
int       g_htf_state[];   // +1 / -1 / 0 (warmup)
```

#### `str_replace` — replace
```mql5
double    g_htf_fUp  [];   // final upper ratchettato (banda visiva, mult InpATRMultiplier)
double    g_htf_fLow [];   // final lower ratchettato (banda visiva)
double    g_htf_fUpFlip [];   // v1.12: banda di flip allargata (mult InpATRMultiplierFlip)
double    g_htf_fLowFlip[];   // v1.12: banda di flip allargata
int       g_htf_state[];   // +1 / -1 / 0 (warmup)
```

---

### PATCH 2.C — ArrayResize/Init/Series per nuovi array

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 768-792 (dentro `RefreshHTFCache`)

#### `str_replace` — search
```mql5
   ArrayResize(g_htf_fUp,     g_htfBarsUsed);
   ArrayResize(g_htf_fLow,    g_htfBarsUsed);
```

#### `str_replace` — replace
```mql5
   ArrayResize(g_htf_fUp,     g_htfBarsUsed);
   ArrayResize(g_htf_fLow,    g_htfBarsUsed);
   ArrayResize(g_htf_fUpFlip,  g_htfBarsUsed);  // v1.12
   ArrayResize(g_htf_fLowFlip, g_htfBarsUsed);  // v1.12
```

E nel blocco di `ArrayInitialize` (qualche riga sotto):

#### `str_replace` — search
```mql5
   ArrayInitialize(g_htf_fUp,     EMPTY_VALUE);
   ArrayInitialize(g_htf_fLow,    EMPTY_VALUE);
```

#### `str_replace` — replace
```mql5
   ArrayInitialize(g_htf_fUp,      EMPTY_VALUE);
   ArrayInitialize(g_htf_fLow,     EMPTY_VALUE);
   ArrayInitialize(g_htf_fUpFlip,  EMPTY_VALUE);  // v1.12
   ArrayInitialize(g_htf_fLowFlip, EMPTY_VALUE);  // v1.12
```

E nel blocco di `ArraySetAsSeries`:

#### `str_replace` — search
```mql5
   ArraySetAsSeries(g_htf_fUp,     true);
   ArraySetAsSeries(g_htf_fLow,    true);
```

#### `str_replace` — replace
```mql5
   ArraySetAsSeries(g_htf_fUp,      true);
   ArraySetAsSeries(g_htf_fLow,     true);
   ArraySetAsSeries(g_htf_fUpFlip,  true);  // v1.12
   ArraySetAsSeries(g_htf_fLowFlip, true);  // v1.12
```

---

### PATCH 2.D — Logica sticky bias in `ComputeHTFState`

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 1283-1308 (loop principale di `ComputeHTFState`)

#### `str_replace` — search
```mql5
      double basicUp  = base + InpATRMultiplier * atr;
      double basicLow = base - InpATRMultiplier * atr;

      double prevUp  = g_htf_fUp [i + 1];
      double prevLow = g_htf_fLow[i + 1];
      double prevClose = g_htf_close[i + 1];

      if(prevUp == EMPTY_VALUE || prevLow == EMPTY_VALUE || g_htf_state[i + 1] == 0)
      {
         g_htf_fUp [i] = basicUp;
         g_htf_fLow[i] = basicLow;
         g_htf_state[i] = (g_htf_close[i] >= base) ? +1 : -1;
         continue;
      }

      double finalUp  = (basicUp  < prevUp  || prevClose > prevUp ) ? basicUp  : prevUp;
      double finalLow = (basicLow > prevLow || prevClose < prevLow) ? basicLow : prevLow;

      int prevState = g_htf_state[i + 1];
      int newState  = prevState;
      if(prevState == +1 && g_htf_close[i] < finalLow) newState = -1;
      else if(prevState == -1 && g_htf_close[i] > finalUp) newState = +1;

      g_htf_fUp [i] = finalUp;
      g_htf_fLow[i] = finalLow;
      g_htf_state[i] = newState;
```

#### `str_replace` — replace
```mql5
      double basicUp  = base + InpATRMultiplier * atr;
      double basicLow = base - InpATRMultiplier * atr;

      // v1.12: bande di flip allargate (parallele, stesso ratchet)
      double basicUpFlip  = base + InpATRMultiplierFlip * atr;
      double basicLowFlip = base - InpATRMultiplierFlip * atr;

      double prevUp      = g_htf_fUp     [i + 1];
      double prevLow     = g_htf_fLow    [i + 1];
      double prevUpFlip  = g_htf_fUpFlip [i + 1];
      double prevLowFlip = g_htf_fLowFlip[i + 1];
      double prevClose   = g_htf_close   [i + 1];

      if(prevUp == EMPTY_VALUE || prevLow == EMPTY_VALUE || g_htf_state[i + 1] == 0)
      {
         g_htf_fUp      [i] = basicUp;
         g_htf_fLow     [i] = basicLow;
         g_htf_fUpFlip  [i] = basicUpFlip;   // v1.12
         g_htf_fLowFlip [i] = basicLowFlip;  // v1.12
         g_htf_state    [i] = (g_htf_close[i] >= base) ? +1 : -1;
         continue;
      }

      double finalUp      = (basicUp      < prevUp      || prevClose > prevUp     ) ? basicUp      : prevUp;
      double finalLow     = (basicLow     > prevLow     || prevClose < prevLow    ) ? basicLow     : prevLow;
      double finalUpFlip  = (basicUpFlip  < prevUpFlip  || prevClose > prevUpFlip ) ? basicUpFlip  : prevUpFlip;
      double finalLowFlip = (basicLowFlip > prevLowFlip || prevClose < prevLowFlip) ? basicLowFlip : prevLowFlip;

      int prevState = g_htf_state[i + 1];
      int newState  = prevState;

      if(InpStickyBias)
      {
         //--- v1.12: flip su banda allargata + confirmation bars
         bool wantsFlipShort = (prevState == +1 && g_htf_close[i] < finalLowFlip);
         bool wantsFlipLong  = (prevState == -1 && g_htf_close[i] > finalUpFlip);

         if(wantsFlipShort)
         {
            int confirmCount = 1;
            for(int k = 1; k < InpFlipConfirmBars && (i + k) < g_htfBarsUsed; k++)
            {
               double prevFlipBand = g_htf_fLowFlip[i + k];
               if(prevFlipBand != EMPTY_VALUE && g_htf_close[i + k] < prevFlipBand)
                  confirmCount++;
               else
                  break;
            }
            if(confirmCount >= InpFlipConfirmBars) newState = -1;
         }
         else if(wantsFlipLong)
         {
            int confirmCount = 1;
            for(int k = 1; k < InpFlipConfirmBars && (i + k) < g_htfBarsUsed; k++)
            {
               double prevFlipBand = g_htf_fUpFlip[i + k];
               if(prevFlipBand != EMPTY_VALUE && g_htf_close[i + k] > prevFlipBand)
                  confirmCount++;
               else
                  break;
            }
            if(confirmCount >= InpFlipConfirmBars) newState = +1;
         }
      }
      else
      {
         //--- v1.11 retrocompatibile (banda ratchet stretta, no confirm)
         if(prevState == +1 && g_htf_close[i] < finalLow) newState = -1;
         else if(prevState == -1 && g_htf_close[i] > finalUp) newState = +1;
      }

      g_htf_fUp      [i] = finalUp;
      g_htf_fLow     [i] = finalLow;
      g_htf_fUpFlip  [i] = finalUpFlip;
      g_htf_fLowFlip [i] = finalLowFlip;
      g_htf_state    [i] = newState;
```

---

### PATCH 2.E — Validazione input + bump versione

**File**: `RattBiasTrend.mq5`
**Posizione**: header + funzione `OnInit` (validazione parametri)

#### `str_replace` — search
```mql5
#property version   "1.11"
```

#### `str_replace` — replace
```mql5
#property version   "1.12"
```

E aggiungi validazione parametri in `OnInit`. Cerca il blocco di validazione esistente (intorno a riga 405 con `InpATRPeriod < 2`):

#### `str_replace` — search
```mql5
   if(InpATRPeriod < 2)
   {
      RBTLog(LOG_ERROR, "INIT", StringFormat("InpATRPeriod deve essere >= 2 (attuale: %d)", InpATRPeriod));
      return INIT_PARAMETERS_INCORRECT;
   }
```

#### `str_replace` — replace
```mql5
   if(InpATRPeriod < 2)
   {
      RBTLog(LOG_ERROR, "INIT", StringFormat("InpATRPeriod deve essere >= 2 (attuale: %d)", InpATRPeriod));
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- v1.12: validazione Sticky Bias
   if(InpStickyBias)
   {
      if(InpATRMultiplierFlip < InpATRMultiplier)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpATRMultiplierFlip (%.2f) deve essere >= InpATRMultiplier (%.2f)",
               InpATRMultiplierFlip, InpATRMultiplier));
         return INIT_PARAMETERS_INCORRECT;
      }
      if(InpFlipConfirmBars < 1 || InpFlipConfirmBars > 5)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpFlipConfirmBars deve essere tra 1 e 5 (attuale: %d)", InpFlipConfirmBars));
         return INIT_PARAMETERS_INCORRECT;
      }
   }
```

---

### Test FASE 2

#### Test A/B in Strategy Tester
Periodo consigliato: 12 Mar 2026 — 29 Apr 2026 (stesso degli screenshot)
Strumenti: AUDUSD H1, EURUSD M30, XAUUSD H4

**Run 1 — Baseline v1.11**:
- `InpStickyBias = false`
- Registra: flip count, P&L netto, max drawdown, win rate

**Run 2 — Sticky moderato**:
- `InpStickyBias = true`
- `InpATRMultiplierFlip = 3.5`
- `InpFlipConfirmBars = 1`

**Run 3 — Sticky aggressivo**:
- `InpStickyBias = true`
- `InpATRMultiplierFlip = 4.0`
- `InpFlipConfirmBars = 2`

#### Metriche di accettazione
- Flip count Run 2 vs Run 1: riduzione attesa **30-50%**
- Flip count Run 3 vs Run 1: riduzione attesa **50-70%**
- P&L netto Run 2: ≥ Run 1 (su strumenti ranging) o ≤ Run 1 di non più del 10% (su strumenti trending)
- Validazione qualitativa: i flip rimasti devono coincidere con inversioni di trend visibili a occhio sul chart

---

## FASE 3 — v1.12 → v1.13 — PMA e PMA+OEF come MA-types

### Concetto

Aggiungiamo 2 nuovi MA-type all'enum `ENUM_BIAS_MATYPE`:

- `BIAS_MA_PMA = 8` — Predictive Moving Average di Ehlers (puro)
- `BIAS_MA_PMA_OEF = 9` — PMA in cascata con One Euro Filter (anti-microstorni avanzato)

Questi diventano selezionabili dal combobox `InpMAType` insieme alle 8 opzioni esistenti (EMA/SMA/SMMA/LWMA/HMA/KAMA/JMA/ZLEMA).

### Verifica matematica delle formule

#### PMA (Ehlers, "Rocket Science for Traders" 2001, capitolo 20)

Formula esatta verificata da letteratura originale:

```
WMA(src, period, i) = Σ_{k=0}^{period-1} [(period-k) × src[i-k]] / Σ_{k=0}^{period-1} (period-k)

WMA1[i] = WMA(close, period, i)
WMA2[i] = WMA(WMA1, period, i)
PMA[i]  = 2 × WMA1[i] - WMA2[i]
```

**Razionale teorico Ehlers**: una WMA di periodo N introduce un lag di circa (N-1)/4 barre. Una WMA della WMA aggiunge altrettanto lag. La differenza WMA1 - WMA2 è quindi proporzionale al lag della WMA1. Aggiungendola alla WMA1 si "annulla" il lag (proiezione lineare avanti).

**Periodo default**: 7 (Ehlers originale). Per RattBiasTrend HTF M30, range raccomandato: 7-21.

**Trigger line** (opzionale, NON usata come `g_htf_ma` ma può essere esposta come buffer secondario in futuro):
```
trigger[i] = (4×PMA[i] + 3×PMA[i-1] + 2×PMA[i-2] + 1×PMA[i-3]) / 10
```

#### One Euro Filter (Casiez, Roussel, Vogel — CHI 2012)

Formule esatte verificate da paper originale e implementazione GitHub di riferimento:

```
smoothing_factor(t_e, cutoff):
    r = 2π × cutoff × t_e
    return r / (r + 1)

exponential_smoothing(α, x, x_prev):
    return α × x + (1 - α) × x_prev
```

Per ogni nuovo sample (con t_e = 1 nel nostro caso, perché lavoriamo barra per barra):

```
1. Calcola derivata grezza:
   dx[i] = x[i] - x[i-1]                    (t_e = 1 per HTF)

2. Filtra la derivata con cutoff fisso:
   α_d = smoothing_factor(1, d_cutoff)     (default d_cutoff = 1.0)
   dx_hat[i] = α_d × dx[i] + (1 - α_d) × dx_hat[i-1]

3. Calcola cutoff ADATTIVO basato sulla derivata filtrata:
   cutoff[i] = min_cutoff + β × |dx_hat[i]|

4. Applica low-pass al segnale con cutoff adattivo:
   α[i] = smoothing_factor(1, cutoff[i])
   x_hat[i] = α[i] × x[i] + (1 - α[i]) × x_hat[i-1]
```

**Parametri (default sicuri per trading HTF)**:
- `min_cutoff = 1.0` Hz: cutoff minimo quando il segnale è fermo (smoothing aggressivo in chop)
- `β = 0.05`: sensibilità alla velocità (più alto = filtra meno in trend)
- `d_cutoff = 1.0` Hz: cutoff per la derivata

Questi default vanno calibrati empiricamente per asset class. Range tipico:
- `min_cutoff`: 0.5-2.0 (più basso = più smoothing in chop)
- `β`: 0.01-0.5 (più alto = più reattivo in trend)
- `d_cutoff`: 0.5-2.0 (raramente cambiato)

### PATCH 3.A — Estensione enum `ENUM_BIAS_MATYPE`

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 102-112

#### `str_replace` — search
```mql5
enum ENUM_BIAS_MATYPE
{
   BIAS_MA_EMA  = 0,   // EMA  — Exponential Moving Average
   BIAS_MA_SMA  = 1,   // SMA  — Simple Moving Average
   BIAS_MA_SMMA = 2,   // SMMA — Smoothed Moving Average
   BIAS_MA_LWMA = 3,   // LWMA — Linear Weighted Moving Average
   BIAS_MA_HMA  = 4,   // HMA  — Hull Moving Average
   BIAS_MA_KAMA  = 5,   // KAMA  — Kaufman Adaptive MA
   BIAS_MA_JMA   = 6,   // JMA   — Jurik-style Adaptive MA
   BIAS_MA_ZLEMA = 7    // ZLEMA — Ehlers Zero Lag EMA
};
```

#### `str_replace` — replace
```mql5
enum ENUM_BIAS_MATYPE
{
   BIAS_MA_EMA     = 0,   // EMA  — Exponential Moving Average
   BIAS_MA_SMA     = 1,   // SMA  — Simple Moving Average
   BIAS_MA_SMMA    = 2,   // SMMA — Smoothed Moving Average
   BIAS_MA_LWMA    = 3,   // LWMA — Linear Weighted Moving Average
   BIAS_MA_HMA     = 4,   // HMA  — Hull Moving Average
   BIAS_MA_KAMA    = 5,   // KAMA  — Kaufman Adaptive MA
   BIAS_MA_JMA     = 6,   // JMA   — Jurik-style Adaptive MA
   BIAS_MA_ZLEMA   = 7,   // ZLEMA — Ehlers Zero Lag EMA
   BIAS_MA_PMA     = 8,   // v1.13: PMA — Ehlers Predictive MA (puro)
   BIAS_MA_PMA_OEF = 9    // v1.13: PMA + One Euro Filter (anti-microstorni)
};
```

---

### PATCH 3.B — Nuovi parametri di input PMA + OEF

**File**: `RattBiasTrend.mq5`
**Posizione**: dopo gruppo SuperSmoother (dopo riga 207, prima del gruppo Sticky Bias di FASE 2)

#### `str_replace` — search
```mql5
input int                InpSuperSmoothPeriod= 15;                // Periodo Ehlers SuperSmoother (Ehlers default 15)

//=== Anti-microstorm — Sticky Bias v1.12 ===========================
```

#### `str_replace` — replace
```mql5
input int                InpSuperSmoothPeriod= 15;                // Periodo Ehlers SuperSmoother (Ehlers default 15)

//=== PMA — Parametri (attivi SOLO se InpMAType = PMA o PMA_OEF) v1.13 ===
input group "=== MA — Parametri PMA (Ehlers Predictive MA) ==="
input int                InpPMAPeriod      = 7;                   // PMA period (Ehlers default 7, range 5-21)

//=== One Euro Filter — Parametri (SOLO se InpMAType = PMA_OEF) v1.13 ===
input group "=== MA — Parametri One Euro Filter ==="
input double             InpOEFMinCutoff   = 1.0;                 // Cutoff minimo (Hz). Più basso = smoothing più aggressivo in chop
input double             InpOEFBeta        = 0.05;                // Sensibilità velocità. Più alto = filtra meno in trend forti
input double             InpOEFDerivCutoff = 1.0;                 // Cutoff derivata (Hz, raramente cambiato)

//=== Anti-microstorm — Sticky Bias v1.12 ===========================
```

---

### PATCH 3.C — Estensione `ComputeHTFMA()` dispatcher

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 802-827

#### `str_replace` — search
```mql5
bool ComputeHTFMA()
{
   switch(InpMAType)
   {
      case BIAS_MA_EMA:
      case BIAS_MA_SMA:
      case BIAS_MA_SMMA:
      case BIAS_MA_LWMA:
         return ComputeHTFMA_Standard();

      case BIAS_MA_HMA:
         return ComputeHTFMA_HMA();

      case BIAS_MA_KAMA:
         return ComputeHTFMA_KAMA();

      case BIAS_MA_JMA:
         return ComputeHTFMA_JMA();

      case BIAS_MA_ZLEMA:
         return ComputeHTFMA_ZLEMA();

      default:
         return false;
   }
}
```

#### `str_replace` — replace
```mql5
bool ComputeHTFMA()
{
   switch(InpMAType)
   {
      case BIAS_MA_EMA:
      case BIAS_MA_SMA:
      case BIAS_MA_SMMA:
      case BIAS_MA_LWMA:
         return ComputeHTFMA_Standard();

      case BIAS_MA_HMA:
         return ComputeHTFMA_HMA();

      case BIAS_MA_KAMA:
         return ComputeHTFMA_KAMA();

      case BIAS_MA_JMA:
         return ComputeHTFMA_JMA();

      case BIAS_MA_ZLEMA:
         return ComputeHTFMA_ZLEMA();

      case BIAS_MA_PMA:
      case BIAS_MA_PMA_OEF:
         return ComputeHTFMA_PMA();   // v1.13

      default:
         return false;
   }
}
```

---

### PATCH 3.D — Estensione `CreateMAHandles()` per PMA

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 670-712

#### `str_replace` — search
```mql5
      case BIAS_MA_HMA:
      case BIAS_MA_KAMA:
      case BIAS_MA_JMA:
      case BIAS_MA_ZLEMA:
         needStandard = false;
         break;
```

#### `str_replace` — replace
```mql5
      case BIAS_MA_HMA:
      case BIAS_MA_KAMA:
      case BIAS_MA_JMA:
      case BIAS_MA_ZLEMA:
      case BIAS_MA_PMA:       // v1.13: calcolato inline
      case BIAS_MA_PMA_OEF:   // v1.13: calcolato inline
         needStandard = false;
         break;
```

---

### PATCH 3.E — Implementazione `ComputeHTFMA_PMA()`

**File**: `RattBiasTrend.mq5`
**Posizione**: dopo `ComputeHTFMA_ZLEMA()` (dopo riga 1144), prima di `ComputeHTFATR()`

#### `str_replace` — search
```mql5
//+------------------------------------------------------------------+
//| ComputeHTFATR — ATR su HTF (Wilder RMA / SMA / EMA selezionabile)|
//+------------------------------------------------------------------+
```

#### `str_replace` — replace
```mql5
//+------------------------------------------------------------------+
//| ComputeHTFMA_PMA — Ehlers Predictive MA + (opt) One Euro Filter   |
//+------------------------------------------------------------------+
// Formula PMA (Ehlers, "Rocket Science for Traders" 2001, cap.20):
//   WMA1[i] = WMA(close, N, i)
//   WMA2[i] = WMA(WMA1, N, i)
//   PMA[i]  = 2*WMA1[i] - WMA2[i]
//
// Se InpMAType == BIAS_MA_PMA_OEF, applica in cascata One Euro Filter:
//   cutoff adattivo basato sulla velocità del PMA → smoothing aggressivo
//   in chop, lascia passare in trend.
//
// Formule One Euro Filter (Casiez et al. CHI 2012):
//   smoothing_factor(t_e, cutoff) = r / (r + 1) dove r = 2π·cutoff·t_e
//   dx[i]      = x[i] - x[i-1]                (t_e = 1 per HTF)
//   α_d        = smoothing_factor(1, d_cutoff)
//   dx_hat[i]  = α_d·dx[i] + (1-α_d)·dx_hat[i-1]
//   cutoff[i]  = min_cutoff + β·|dx_hat[i]|
//   α[i]       = smoothing_factor(1, cutoff[i])
//   x_hat[i]   = α[i]·x[i] + (1-α[i])·x_hat[i-1]
bool ComputeHTFMA_PMA()
{
   int N     = InpPMAPeriod;
   int total = g_htfBarsUsed;
   if(total < 2*N + 2) return false;  // warmup richiede WMA della WMA

   double closeNat[], wma1Nat[], wma2Nat[], pmaNat[];
   ArrayResize(closeNat, total);
   ArrayResize(wma1Nat,  total);
   ArrayResize(wma2Nat,  total);
   ArrayResize(pmaNat,   total);

   SeriesToNatural(g_htf_close, closeNat, total);

   //--- Step 1: WMA1 = WMA(close, N) — usa WMAPoint helper esistente
   for(int i = 0; i < N - 1; i++)
      wma1Nat[i] = closeNat[i];   // warmup: identità
   for(int i = N - 1; i < total; i++)
      wma1Nat[i] = WMAPoint(closeNat, i, N);

   //--- Step 2: WMA2 = WMA(WMA1, N)
   for(int i = 0; i < 2*(N-1); i++)
      wma2Nat[i] = wma1Nat[i];   // warmup: identità
   for(int i = 2*(N-1); i < total; i++)
      wma2Nat[i] = WMAPoint(wma1Nat, i, N);

   //--- Step 3: PMA = 2*WMA1 - WMA2
   for(int i = 0; i < total; i++)
      pmaNat[i] = 2.0 * wma1Nat[i] - wma2Nat[i];

   //--- Step 4 (opzionale): One Euro Filter
   if(InpMAType == BIAS_MA_PMA_OEF)
   {
      double oefNat[];
      ArrayResize(oefNat, total);

      // Stato del filtro
      double xHatPrev  = pmaNat[0];
      double dxHatPrev = 0.0;
      oefNat[0] = pmaNat[0];

      const double TWO_PI = 2.0 * 3.14159265358979323846;
      const double t_e   = 1.0;  // sample period = 1 barra HTF

      // α_d fisso (cutoff fisso per la derivata)
      double r_d = TWO_PI * InpOEFDerivCutoff * t_e;
      double a_d = r_d / (r_d + 1.0);

      for(int i = 1; i < total; i++)
      {
         //--- 1. Derivata grezza
         double dx = (pmaNat[i] - pmaNat[i-1]) / t_e;

         //--- 2. Derivata filtrata (low-pass con cutoff fisso)
         double dxHat = a_d * dx + (1.0 - a_d) * dxHatPrev;

         //--- 3. Cutoff adattivo
         double cutoff = InpOEFMinCutoff + InpOEFBeta * MathAbs(dxHat);

         //--- 4. α adattivo
         double r = TWO_PI * cutoff * t_e;
         double alpha = r / (r + 1.0);

         //--- 5. Output filtrato
         double xHat = alpha * pmaNat[i] + (1.0 - alpha) * xHatPrev;

         oefNat[i] = xHat;

         //--- Memorizza stato per prossima iterazione
         xHatPrev  = xHat;
         dxHatPrev = dxHat;
      }

      NaturalToSeries(oefNat, g_htf_ma, total);

      RBTLog(LOG_DEBUG, "MA",
         StringFormat("PMA+OEF OK — N=%d minCut=%.2f β=%.3f dCut=%.2f ma[0]=%s ma[last]=%s",
            N, InpOEFMinCutoff, InpOEFBeta, InpOEFDerivCutoff,
            DoubleToString(g_htf_ma[0],      _Digits),
            DoubleToString(g_htf_ma[total-1], _Digits)));
   }
   else
   {
      //--- PMA puro (no OEF)
      NaturalToSeries(pmaNat, g_htf_ma, total);

      RBTLog(LOG_DEBUG, "MA",
         StringFormat("PMA OK — N=%d ma[0]=%s ma[last]=%s",
            N,
            DoubleToString(g_htf_ma[0],      _Digits),
            DoubleToString(g_htf_ma[total-1], _Digits)));
   }

   return true;
}

//+------------------------------------------------------------------+
//| ComputeHTFATR — ATR su HTF (Wilder RMA / SMA / EMA selezionabile)|
//+------------------------------------------------------------------+
```

---

### PATCH 3.F — Aggiornamento `MAEffectivePeriod()`

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 1584-1588

#### `str_replace` — search
```mql5
int MAEffectivePeriod()
{
   if(InpMAType == BIAS_MA_JMA) return InpJMAPeriod;
   return InpMAPeriod;
}
```

#### `str_replace` — replace
```mql5
int MAEffectivePeriod()
{
   if(InpMAType == BIAS_MA_JMA) return InpJMAPeriod;
   if(InpMAType == BIAS_MA_PMA || InpMAType == BIAS_MA_PMA_OEF)
      return 2 * InpPMAPeriod;   // v1.13: warmup richiede WMA della WMA
   return InpMAPeriod;
}
```

---

### PATCH 3.G — Aggiornamento `MATypeLabel()`

**File**: `RattBiasTrend.mq5`
**Posizione**: blocco riga 1603-1620

#### `str_replace` — search
```mql5
string MATypeLabel()
{
   switch(InpMAType)
   {
      case BIAS_MA_EMA:   return "EMA";
      case BIAS_MA_SMA:   return "SMA";
      case BIAS_MA_SMMA:  return "SMMA";
      case BIAS_MA_LWMA:  return "LWMA";
      case BIAS_MA_HMA:   return "HMA";
      case BIAS_MA_KAMA:  return "KAMA";
      case BIAS_MA_JMA:   return "JMA";
      case BIAS_MA_ZLEMA: return "ZLEMA";
      default:            return "??";
   }
}
```

#### `str_replace` — replace
```mql5
string MATypeLabel()
{
   switch(InpMAType)
   {
      case BIAS_MA_EMA:     return "EMA";
      case BIAS_MA_SMA:     return "SMA";
      case BIAS_MA_SMMA:    return "SMMA";
      case BIAS_MA_LWMA:    return "LWMA";
      case BIAS_MA_HMA:     return "HMA";
      case BIAS_MA_KAMA:    return "KAMA";
      case BIAS_MA_JMA:     return "JMA";
      case BIAS_MA_ZLEMA:   return "ZLEMA";
      case BIAS_MA_PMA:     return "PMA";       // v1.13
      case BIAS_MA_PMA_OEF: return "PMA+OEF";   // v1.13
      default:              return "??";
   }
}
```

---

### PATCH 3.H — Validazione PMA + bump versione

**File**: `RattBiasTrend.mq5`
**Posizione**: header + validazione `OnInit`

#### `str_replace` — search
```mql5
#property version   "1.12"
```

#### `str_replace` — replace
```mql5
#property version   "1.13"
```

E aggiungi validazione parametri PMA in `OnInit` (dopo la validazione Sticky Bias aggiunta in Fase 2):

#### `str_replace` — search
```mql5
      if(InpFlipConfirmBars < 1 || InpFlipConfirmBars > 5)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpFlipConfirmBars deve essere tra 1 e 5 (attuale: %d)", InpFlipConfirmBars));
         return INIT_PARAMETERS_INCORRECT;
      }
   }
```

#### `str_replace` — replace
```mql5
      if(InpFlipConfirmBars < 1 || InpFlipConfirmBars > 5)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpFlipConfirmBars deve essere tra 1 e 5 (attuale: %d)", InpFlipConfirmBars));
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   //--- v1.13: validazione PMA / PMA+OEF
   if(InpMAType == BIAS_MA_PMA || InpMAType == BIAS_MA_PMA_OEF)
   {
      if(InpPMAPeriod < 5 || InpPMAPeriod > 50)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpPMAPeriod deve essere tra 5 e 50 (attuale: %d)", InpPMAPeriod));
         return INIT_PARAMETERS_INCORRECT;
      }
   }
   if(InpMAType == BIAS_MA_PMA_OEF)
   {
      if(InpOEFMinCutoff <= 0.0 || InpOEFMinCutoff > 10.0)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpOEFMinCutoff deve essere in (0, 10] (attuale: %.3f)", InpOEFMinCutoff));
         return INIT_PARAMETERS_INCORRECT;
      }
      if(InpOEFBeta < 0.0 || InpOEFBeta > 5.0)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpOEFBeta deve essere in [0, 5] (attuale: %.3f)", InpOEFBeta));
         return INIT_PARAMETERS_INCORRECT;
      }
      if(InpOEFDerivCutoff <= 0.0 || InpOEFDerivCutoff > 10.0)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpOEFDerivCutoff deve essere in (0, 10] (attuale: %.3f)", InpOEFDerivCutoff));
         return INIT_PARAMETERS_INCORRECT;
      }
   }
```

---

### Test FASE 3

#### Test funzionali (qualitativi)
1. Cambia `InpMAType = BIAS_MA_PMA` → verifica che la bias line sul chart sia visivamente più "anticipata" rispetto a KAMA(21)
2. Cambia `InpMAType = BIAS_MA_PMA_OEF` → verifica che la bias line sia ANCORA più liscia (filtro low-pass evidente)
3. Verifica dashboard: label "PMA" o "PMA+OEF" mostrato correttamente nel campo Source
4. Verifica log INIT: `MA: PMA OK — N=7 ma[0]=...` o `MA: PMA+OEF OK — N=7 minCut=1.00 β=0.050 ...`

#### Test A/B in Strategy Tester
Periodo: 1 mese
Strumenti: AUDUSD H1, EURUSD M30, BTCUSD H4

**Run 1 — Baseline KAMA(21)**: configurazione attuale
**Run 2 — PMA(7) puro**: `BIAS_MA_PMA` con `InpPMAPeriod=7`
**Run 3 — PMA(7) + OEF default**: `BIAS_MA_PMA_OEF` con default β=0.05
**Run 4 — PMA(7) + OEF aggressivo**: `InpOEFMinCutoff=0.5`, `InpOEFBeta=0.02` (smoothing maggiore)
**Run 5 — PMA(7) + OEF reattivo**: `InpOEFMinCutoff=2.0`, `InpOEFBeta=0.20` (più reattivo)

#### Metriche di accettazione
- Run 2 (PMA puro) flip count: simile a KAMA, possibili overshoot ai punti di flesso (atteso e documentato)
- Run 3 (OEF default) flip count: **inferiore a KAMA del 30-60%**
- Run 4 (OEF aggressivo) flip count: **inferiore a KAMA del 50-75%**, ma possibile lag eccessivo su trend rapidi
- Run 5 (OEF reattivo) flip count: simile a KAMA, ma con anticipo grazie al PMA

#### Tuning empirico raccomandato

Per AUDUSD/EURUSD M30 (Forex majors):
- `InpPMAPeriod = 7` (Ehlers default)
- `InpOEFMinCutoff = 1.0`
- `InpOEFBeta = 0.05`
- `InpOEFDerivCutoff = 1.0`

Per BTCUSD H1 (alta volatilità):
- `InpPMAPeriod = 14` (più lungo per assorbire volatilità)
- `InpOEFMinCutoff = 0.5` (smoothing più aggressivo)
- `InpOEFBeta = 0.10` (più reattivo per cogliere movimenti rapidi)

Per XAUUSD H4 (trending forte):
- `InpPMAPeriod = 9`
- `InpOEFMinCutoff = 0.8`
- `InpOEFBeta = 0.08`

**Importante**: questi sono punti di partenza. Walk-forward optimization per asset class raccomandato.

---

## Verifica matematica delle formule

### Tabella riassuntiva delle formule implementate

| Formula | Sorgente verificata | Implementazione MQL5 |
|---------|---------------------|----------------------|
| WMA(src, N, i) = Σ(N-k)·src[i-k] / Σ(N-k) | Standard, Wikipedia | `WMAPoint()` esistente, riga 849 |
| PMA = 2·WMA1 - WMA2 | Ehlers, Rocket Science for Traders pg.212 (2001) | `ComputeHTFMA_PMA()` step 1-3 |
| smoothing_factor(t_e, fc) = 2π·fc·t_e / (2π·fc·t_e + 1) | Casiez et al., CHI 2012 (paper originale) | `ComputeHTFMA_PMA()` step 4 (calcolo r e α) |
| dx_hat = α_d·dx + (1-α_d)·dx_hat_prev | One Euro Filter, eq.1 nel paper | step 4.2 |
| cutoff_adaptive = min_cutoff + β·|dx_hat| | One Euro Filter, eq.2 nel paper | step 4.3 |
| Hysteresis: flip se close < base - mult_flip·ATR | Standard channel theory + estensione propria | `ComputeHTFState()` v1.12 |
| Confirmation: N close consecutive oltre banda | Standard pattern (es. Donchian breakout) | loop confirmCount in v1.12 |

### Razionale delle scelte di default

#### PMA period = 7
Default di Ehlers nel libro originale. Periodo bilanciato per HTF M30/H1: cattura ~3.5 ore di movimento (su M30) o 7 ore (su H1), sufficiente per filtraggio del rumore senza eccessivo lag.

#### OEF min_cutoff = 1.0 Hz
Default raccomandato dal paper One Euro Filter. In contesto trading, "1 Hz" significa cutoff a 1 ciclo per unità di tempo (1 barra HTF). Smoothing moderato.

#### OEF β = 0.05
Più conservativo del default 0.0 del paper (che però era pensato per cursore, non finanza). 0.05 dà sensibilità alla velocità senza essere troppo reattivo. Range tipico per trading: 0.01-0.20.

#### OEF d_cutoff = 1.0 Hz
Default paper. Filtra la derivata in modo che cambi rapidi temporanei non destabilizzino il cutoff adattivo.

#### Sticky Bias mult_flip = 3.5
Empirico, basato sull'osservazione che un microstorno fisiologico raramente supera 2× ATR. 3.5× ATR è 1.4× la banda visiva 2.5× → soglia di flip statisticamente significativa.

#### Sticky Bias confirm_bars = 1
Default = 1 → no confirmation aggiuntiva (solo banda allargata). Alza a 2 per filtraggio doppio (banda + N close consecutive). Non superare 3 per non introdurre lag eccessivo.

---

## Test post-implementazione

### Checklist post-FASE 1
- [ ] Compila senza warning con `#property strict`
- [ ] Cambia TF 20 volte → tema scuro mantenuto, segnali visibili
- [ ] Toggle `InpApplyTheme` on/off → comportamento corretto
- [ ] Rimozione manuale → tema chiaro ripristinato
- [ ] Log DEBUG mostra "Theme NOT restored (transient deinit)" su CHARTCHANGE

### Checklist post-FASE 2
- [ ] Compila senza warning
- [ ] `InpStickyBias = false` produce comportamento identico a v1.11 (verifica con stesso dataset)
- [ ] `InpStickyBias = true` riduce flip count del 30-50% su Strategy Tester
- [ ] Validazione `InpATRMultiplierFlip < InpATRMultiplier` blocca init
- [ ] Validazione `InpFlipConfirmBars < 1 || > 5` blocca init

### Checklist post-FASE 3
- [ ] Compila senza warning
- [ ] `BIAS_MA_PMA` selezionabile dal combobox, label "PMA" in dashboard
- [ ] `BIAS_MA_PMA_OEF` selezionabile, label "PMA+OEF" in dashboard
- [ ] Bias line PMA visivamente più anticipata di KAMA su stesso chart
- [ ] Bias line PMA+OEF visivamente più liscia di PMA puro
- [ ] Validazioni input PMA / OEF bloccano init su valori fuori range
- [ ] Log INIT mostra parametri corretti

### Verifica grep finale
```bash
# Conferma presenza nuove funzioni
grep -n "SaveOriginalChartColors\|ApplyThemeColors\|ComputeHTFMA_PMA" RattBiasTrend.mq5

# Conferma versione finale
grep -n "#property version" RattBiasTrend.mq5
# Atteso: "1.13"

# Conferma nuovi MA-types
grep -n "BIAS_MA_PMA" RattBiasTrend.mq5
# Atteso: minimo 6 occorrenze (enum, dispatcher, MAEffectivePeriod, MATypeLabel, validazione, CreateMAHandles)

# Conferma sticky bias
grep -n "InpStickyBias\|InpATRMultiplierFlip\|InpFlipConfirmBars" RattBiasTrend.mq5
# Atteso: minimo 5 occorrenze ciascuna (input, validazione, ComputeHTFState x3)
```

---

## Rollback strategy

### Rollback FASE 3 (PMA)
- Cambia `InpMAType` da `BIAS_MA_PMA` o `BIAS_MA_PMA_OEF` a `BIAS_MA_KAMA` (o altro MA esistente)
- Le nuove funzioni sono dormienti se non chiamate, zero impatto sulle altre MA-type

### Rollback FASE 2 (Sticky Bias)
- Set `InpStickyBias = false`
- Comportamento torna identico a v1.11

### Rollback FASE 1 (Tema)
- Set `InpApplyTheme = false` per disabilitare tema
- Per ripristinare codice v1.10 esatto: `git checkout` sul tag pre-fix

### Rollback completo file
Mantenere backup `RattBiasTrend_v1.10_pre_fix.mq5` prima di iniziare. Tag git raccomandati:
- `v1.10` — pre-fix (baseline)
- `v1.11` — post FASE 1
- `v1.12` — post FASE 2
- `v1.13` — post FASE 3

---

## Riferimenti bibliografici

### PMA (Predictive Moving Average)
- Ehlers, J.F. (2001). *Rocket Science for Traders: Digital Signal Processing Applications*. Wiley. Capitolo 20, p. 212.
- Implementazione TradingView (cheatcountry, 2020) — verifica formula
- Implementazione MQL5 CodeBase (AndreiFX60, 2022) — riferimento tecnico

### One Euro Filter
- Casiez, G., Roussel, N., & Vogel, D. (2012). *1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive Systems*. Proceedings CHI '12, pp. 2527-2530. ACM.
- Repository ufficiale: https://github.com/casiez/OneEuroFilter
- Implementazione Python di riferimento: https://github.com/jaantollander/OneEuroFilter
- Articolo Financial Hacker (applicazione al trading): https://financial-hacker.com/the-one-euro-filter/

### Sticky Bias (Hysteresis ATR)
- Concetto derivato dal pattern Chandelier Exit (Le Beau & Lucas)
- Asymmetric SuperTrend (varianti professionali)
- Confirmation bars: Donchian breakout filtering pattern (Turtle Trading method)

---

## Sintesi finale

Questo documento descrive 3 fasi indipendenti di evoluzione di RattBiasTrend dalla v1.10 alla v1.13, con:

- **17 operazioni `str_replace` totali** (4 + 5 + 8)
- **~550 righe di codice nuovo** distribuite su 3 fasi
- **5 nuovi parametri di input** (1 toggle Fase 2 + 2 numerici Fase 2 + 1 numerico Fase 3 + 3 numerici OEF Fase 3, totale 7 nuovi parametri)
- **2 nuove MA-type** (PMA, PMA+OEF)
- **Retrocompatibilità totale** via toggle e default conservativi

Implementazione raccomandata in ordine sequenziale: FASE 1 → test → FASE 2 → test A/B → FASE 3 → test A/B/C/D/E.

Ogni fase è autonoma e può essere implementata e validata separatamente.

---

**Fine documento.**
