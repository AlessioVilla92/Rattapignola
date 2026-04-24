# RattBiasTrend.mq5 — Istruzioni per Claude Code

**Data:** Aprile 2026  
**Progetto:** Ecosistema Rattapignola  
**Versione:** 1.00  
**Azione richiesta:** Creare il file `RattBiasTrend.mq5` nella cartella `Indicators` di MetaTrader 5.

---

## 1. Contesto e obiettivo

### Perché questo indicatore esiste

L'ecosistema Rattapignola utilizza `UTBotAdaptive` (attualmente v2.30 `UTBotAdaptiveLEVA2.mq5`) come engine di trigger su timeframe operativi (tipicamente M15). In fase di validazione è emerso che il core dell'UTBot con JMA e preset AUTO genera trigger direzionalmente corretti ma soffre di **microstorni in zona di consolidamento** che producono pattern distruttivi tipo:

1. Long aperto su trigger LONG UTBot
2. Micro-retracement genera trigger SHORT → long chiuso
3. Entra short che va in stop loss
4. Nuovo trigger LONG più alto dove si era chiusa la prima posizione

Il paradigma scelto per risolvere questo è: **non modificare il core UTBot** (che è già parametrizzato correttamente), ma aggiungere un **gate di bias direzionale calcolato su timeframe superiore** che filtri i trigger in ingresso:

- Bias HTF = LONG → l'EA accetta solo trigger LONG dell'UTBot (trigger SHORT ignorati, posizioni long esistenti protette da Chandelier Exit).
- Bias HTF = SHORT → l'EA accetta solo trigger SHORT.
- Bias HTF = NEUTRAL (warmup o stato indeterminato) → nessun trigger accettato.

`RattBiasTrend` è il primo indicatore **standalone** di questa famiglia. Viene sviluppato isolato per validare il paradigma HTF→LTF prima di integrarlo via `iCustom` in UTBot / EA. Non modifica UTBot né l'EA in questa fase.

### Scelte architetturali confermate con l'utente

1. **Due modalità engine** selezionabili via input, implementate nello stesso indicatore:
   - **`SUPERTREND_CLASSIC`** — prezzo base HL2, banda ATR ratchettata (formula Seban 2007).
   - **`MA_ATR_BAND`** — prezzo base MA selezionabile (EMA/SMA/SMMA/LWMA/HMA/KAMA), banda ATR ratchettata. **Questo è il default.**
2. **Timeframe di calcolo parametrizzato** tramite `InpBiasTF` (enum `ENUM_TIMEFRAMES`). Il calcolo avviene interamente sulle barre del TF scelto. Il risultato viene **proiettato sul chart corrente** (che può essere un TF inferiore) tramite `iBarShift` + copia di stato.
3. **Anti-repainting rigoroso**: la barra HTF corrente (non ancora chiusa) non determina mai lo stato del gate. Le barre LTF del chart che cadono nella HTF-in-formazione ereditano sempre lo stato dell'ultima HTF chiusa.
4. **Rendering overlay sul chart principale** (default) — linea colorata sovrapposta alle candele. Modalità subwindow opzionale.
5. **ATR = Wilder RMA** (coerente con il resto dell'ecosistema — `iATR()` built-in MT5 usa SMA e NON deve essere usato).
6. **Default parametrici confermati**:
   - `InpEngineMode = MA_ATR_BAND`
   - `InpBiasTF = PERIOD_H4`
   - `InpMAType = MA_KAMA`
   - `InpMAPeriod = 21` (KAMA Fast=2, Slow=30)
   - `InpATRPeriod = 10`
   - `InpATRMultiplier = 2.5`
   - `InpDrawMode = DRAW_OVERLAY_CHART`

### Cosa NON fa questa v1.00

- **Nessuna zona grigia/flat detection.** Lo stato è binario {+1, -1} + stato di warmup iniziale {0}. La detection di laterality è rimandata a v1.10.
- **Nessun VWAP mode.** Rimandato a v1.20.
- **Nessuna integrazione diretta con UTBot o EA.** L'indicatore espone buffer pubblici per futura lettura via `iCustom`, ma non scrive file, non apre ordini, non comunica con altri moduli.
- **Nessun alert/notifica.** I flip H4 sono tracciati nel buffer `B_Flip` per future statistiche; gli alert vengono aggiunti in v1.10.

---

## 2. File da creare

**Path:** `MQL5/Indicators/RattBiasTrend.mq5`  
**Azione:** Creare ex novo (file non esistente).

Nessun altro file del progetto viene toccato. L'indicatore è **100% standalone**.

---

## 3. Architettura tecnica dettagliata

### 3.1 Pipeline di calcolo (in ordine di esecuzione a ogni OnCalculate)

```
┌─────────────────────────────────────────────────────────────┐
│ STEP 1 — Determina quante barre HTF servono                 │
│   htfBarsNeeded = rates_total_HTF (o lookback ragionevole)  │
├─────────────────────────────────────────────────────────────┤
│ STEP 2 — Copia dati HTF in array interni                    │
│   CopyClose(_Symbol, InpBiasTF, 0, N, g_htf_close[])        │
│   CopyHigh (_Symbol, InpBiasTF, 0, N, g_htf_high[])         │
│   CopyLow  (_Symbol, InpBiasTF, 0, N, g_htf_low[])          │
│   CopyTime (_Symbol, InpBiasTF, 0, N, g_htf_time[])         │
│   (Tutti in modalità series: indice 0 = barra più recente)  │
├─────────────────────────────────────────────────────────────┤
│ STEP 3 — Calcolo MA su HTF (se MA_ATR_BAND)                 │
│   Riempie g_htf_ma[] — stesso indexing del close            │
├─────────────────────────────────────────────────────────────┤
│ STEP 4 — Calcolo ATR Wilder RMA su HTF                      │
│   Riempie g_htf_atr[] — stesso indexing                     │
├─────────────────────────────────────────────────────────────┤
│ STEP 5 — Bande grezze e ratchet su HTF                      │
│   basicUpper[i] = base[i] + mult*atr[i]                     │
│   basicLower[i] = base[i] - mult*atr[i]                     │
│   Applica ratchet e calcola finalUpper/finalLower/state     │
│   Itera da barra più vecchia a barra più recente            │
├─────────────────────────────────────────────────────────────┤
│ STEP 6 — Proiezione HTF → LTF (chart bars)                  │
│   Per ogni i da prev_calculated a rates_total-1:            │
│     htfShift = iBarShift(_Symbol, InpBiasTF, time[i], false)│
│     stateShift = htfShift + 1  // anti-repainting           │
│     B_State[i]     = g_htf_state[stateShift]                │
│     B_MainLine[i]  = g_htf_base[stateShift]                 │
│     B_Upper[i]     = g_htf_finalUpper[stateShift]           │
│     B_Lower[i]     = g_htf_finalLower[stateShift]           │
│     B_ColorIndex[i]= (state==+1)?0 : (state==-1)?1 : 2      │
│     B_Flip[i]      = (state[i] != state[i-1]) ? 1.0 : 0.0   │
├─────────────────────────────────────────────────────────────┤
│ STEP 7 — Aggiorna dashboard label                           │
│   Testo: "BIAS H4 [MA+ATR] KAMA(21) ATR(10×2.5) → LONG"     │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Regola anti-repainting (dettaglio)

La barra HTF all'indice 0 (più recente) è **in formazione**. Il suo stato può ancora cambiare prima della chiusura. Per evitare repainting visivo:

- Tutto il calcolo HTF viene fatto normalmente (anche sulla barra 0), **ma**:
- Al momento della proiezione su LTF, `stateShift = iBarShift(...) + 1`.
- Questo garantisce che un qualsiasi chart bar riceva lo stato di una barra HTF che **era già chiusa quando quel chart bar si è aperto**.
- Conseguenza: la linea colorata sul chart M15 non cambia mai in corso di formazione della barra H4. Cambia solo quando una nuova barra H4 si apre, riflettendo lo stato della H4 appena chiusa.

**Caso limite left-edge:** se `iBarShift` ritorna un valore tale che `stateShift` eccede `htfBarsComputed`, si scrive `EMPTY_VALUE` (warmup).

### 3.3 Supertrend ratchet (formula esatta)

```mql5
// Inizializzazione barra più vecchia (indice seriesCount-1 in indexing series, 
// oppure indice 0 in indexing as_timeseries=false)
state[oldest] = +1  // arbitrario, verrà sovrascritto appena il prezzo tocca una banda
finalUpper[oldest] = basicUpper[oldest]
finalLower[oldest] = basicLower[oldest]

// Iterazione dalla barra più vecchia alla più recente
for i from oldest-1 down to 0:  // (series indexing: 0 = newest)
    basicUpper[i] = base[i] + mult * atr[i]
    basicLower[i] = base[i] - mult * atr[i]
    
    // Ratchet upper: può scendere ma non salire, finche' close non la buca
    if (basicUpper[i] < finalUpper[i+1] || close[i+1] > finalUpper[i+1])
        finalUpper[i] = basicUpper[i]
    else
        finalUpper[i] = finalUpper[i+1]
    
    // Ratchet lower: può salire ma non scendere, finche' close non la buca
    if (basicLower[i] > finalLower[i+1] || close[i+1] < finalLower[i+1])
        finalLower[i] = basicLower[i]
    else
        finalLower[i] = finalLower[i+1]
    
    // State transition
    if (state[i+1] == +1 && close[i] < finalLower[i])
        state[i] = -1   // flip da long a short
    else if (state[i+1] == -1 && close[i] > finalUpper[i])
        state[i] = +1   // flip da short a long
    else
        state[i] = state[i+1]  // mantiene stato precedente
```

**NOTA IMPORTANTE:** in MQL5, se gli array HTF vengono usati in modalità series (`ArraySetAsSeries(arr, true)`), l'indice 0 è la barra più recente. L'iterazione del ratchet va da indice alto (passato) a indice basso (presente), quindi `for(int i = count-2; i >= 0; i--)` con lookback a `[i+1]` per i dati precedenti.

### 3.4 ATR Wilder RMA (formula esatta)

```mql5
// True Range
TR[i] = max( high[i] - low[i], 
             fabs(high[i] - close[i+1]),      // [i+1] = barra precedente in series
             fabs(low[i]  - close[i+1]) )

// Seed: SMA delle prime N TR
atr_seed_index = count - N - 1  (indice della seed bar in series indexing)
atr[atr_seed_index] = sum(TR[atr_seed_index .. count-2]) / N

// Ricorsione Wilder RMA
for i from atr_seed_index - 1 down to 0:
    atr[i] = (atr[i+1] * (N-1) + TR[i]) / N
```

La seed bar iniziale è l'SMA; dopo parte la RMA pura.

### 3.5 Calcolo MA (per modalità `MA_ATR_BAND`)

Implementare sei tipi:

| Tipo       | Implementazione                                            |
|------------|------------------------------------------------------------|
| `MA_EMA`   | `iMA` handle MT5, `MODE_EMA`, timeframe `InpBiasTF`        |
| `MA_SMA`   | `iMA` handle MT5, `MODE_SMA`, timeframe `InpBiasTF`        |
| `MA_SMMA`  | `iMA` handle MT5, `MODE_SMMA`, timeframe `InpBiasTF`       |
| `MA_LWMA`  | `iMA` handle MT5, `MODE_LWMA`, timeframe `InpBiasTF`       |
| `MA_HMA`   | Custom su close HTF: `HMA = LWMA(2·LWMA(n/2) - LWMA(n), √n)` |
| `MA_KAMA`  | Custom su close HTF: Kaufman Adaptive MA                   |

**KAMA formula esatta:**
```
// ER (Efficiency Ratio) su N periodi
change[i]   = |close[i] - close[i+N]|
volatility[i] = sum(|close[k] - close[k+1]|, k=i..i+N-1)
ER[i] = change[i] / volatility[i]  // evita div/0

// Smoothing Constant
fastSC = 2 / (InpKAMAFast + 1)    // default InpKAMAFast=2 → fastSC=2/3
slowSC = 2 / (InpKAMASlow + 1)    // default InpKAMASlow=30 → slowSC=2/31
SC[i] = (ER[i] * (fastSC - slowSC) + slowSC)^2

// Ricorsione (seed = close della seed bar)
kama[seed] = close[seed]
for i from seed-1 down to 0:   // series indexing: i decresce verso il presente
    kama[i] = kama[i+1] + SC[i] * (close[i] - kama[i+1])
```

**HMA formula esatta:**
```
step1[i] = 2 · LWMA(close, n/2)[i] - LWMA(close, n)[i]
hma[i]   = LWMA(step1, floor(√n))[i]
```

Per HMA si possono usare due handle `iMA MODE_LWMA` su due period diversi, poi calcolare lo step1 in array, poi un terzo LWMA (implementato inline su array, perché iMA non lavora su array custom).

### 3.6 Buffer layout

```
Buffer 0: B_MainLine     — valore della base (MA o HL2)  — plot principale
Buffer 1: B_Upper        — banda superiore finale (ratchet)
Buffer 2: B_Lower        — banda inferiore finale (ratchet)
Buffer 3: B_State        — 1.0 = long, -1.0 = short, 0.0 = warmup/neutral
Buffer 4: B_Flip         — 1.0 sulla candela LTF in cui HTF ha flippato, 0.0 altrove
Buffer 5: B_ColorIndex   — 0 = verde (long), 1 = rosso (short), 2 = grigio (warmup)

Totale: 6 buffer
```

### 3.7 Plot layout

```
Plot 0: B_MainLine — DRAW_COLOR_LINE, colore da B_ColorIndex
        Colori: {Verde, Rosso, Grigio}, width 3
Plot 1: B_Upper    — DRAW_LINE, grigio chiaro, STYLE_DOT, width 1
Plot 2: B_Lower    — DRAW_LINE, grigio chiaro, STYLE_DOT, width 1

Totale: 3 plot
```

**Rendering:**
- `indicator_chart_window` quando `InpDrawMode = DRAW_OVERLAY_CHART` (default).
- `indicator_separate_window` quando `InpDrawMode = DRAW_SUBWINDOW`.

Siccome `#property` è compile-time constant, l'indicatore si compila sempre come `indicator_chart_window`. Per supportare anche `SUBWINDOW` senza duplicare il file, in v1.00 implementiamo **solo `DRAW_OVERLAY_CHART`** come unica modalità effettiva. L'enum `InpDrawMode` è presente come placeholder per v1.10 ma al momento accetta solo `DRAW_OVERLAY_CHART`; altri valori producono un warning e fallback su overlay.

### 3.8 Dashboard label

Oggetto grafico `OBJ_LABEL` in alto a destra, testo aggiornato a ogni tick:

```
BIAS H4 [MA+ATR] KAMA(21) ATR(10×2.5) → LONG
```

Colore del testo uguale al colore corrente del bias (verde/rosso/grigio).

---

## 4. Codice completo da scrivere

Copia l'intero blocco seguente nel file `MQL5/Indicators/RattBiasTrend.mq5`:

```mql5
//+------------------------------------------------------------------+
//| RattBiasTrend.mq5                                                |
//| Ecosistema Rattapignola — Bias HTF direzionale v1.00             |
//|                                                                  |
//| Calcola un bias di trend (LONG/SHORT) su timeframe superiore     |
//| (configurabile) e lo proietta come overlay colorato sul chart    |
//| operativo. Supporta due engine:                                  |
//|   1. SUPERTREND_CLASSIC — HL2 + banda ATR ratchettata            |
//|   2. MA_ATR_BAND        — MA scelta + banda ATR ratchettata      |
//|                                                                  |
//| Timeframe di calcolo parametrizzato (InpBiasTF).                 |
//| Proiezione HTF->LTF via iBarShift + anti-repainting rigoroso:    |
//|   la barra HTF corrente (in formazione) non determina mai lo     |
//|   stato del gate. Le barre LTF ereditano sempre dallo stato      |
//|   dell'ultima barra HTF chiusa.                                  |
//|                                                                  |
//| ATR = Wilder RMA (NON iATR built-in, che usa SMA).               |
//|                                                                  |
//| BUFFER PUBBLICI (per iCustom futuro dell'EA):                    |
//|   Buffer 0: B_MainLine     — base (MA o HL2)                     |
//|   Buffer 1: B_Upper        — banda superiore finale              |
//|   Buffer 2: B_Lower        — banda inferiore finale              |
//|   Buffer 3: B_State        — 1.0 LONG / -1.0 SHORT / 0.0 WARMUP  |
//|   Buffer 4: B_Flip         — 1.0 sulla candela del flip HTF      |
//|   Buffer 5: B_ColorIndex   — 0 verde / 1 rosso / 2 grigio        |
//+------------------------------------------------------------------+
#property copyright   "Rattapignola ecosystem"
#property version     "1.00"
#property description "Bias HTF direzionale — Supertrend classico | MA+ATR"
#property description "Calcolo su TF configurabile, proiezione overlay sul chart"
#property description "Buffer 3 (B_State) = +1 LONG / -1 SHORT / 0 WARMUP"

#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   3

//--- Plot 0: linea principale colorata (bias)
#property indicator_label1  "Bias Line"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime, clrRed, clrGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- Plot 1: banda superiore
#property indicator_label2  "Upper Band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSilver
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Plot 2: banda inferiore
#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrSilver
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//+------------------------------------------------------------------+
//| Enum: modalità engine                                            |
//+------------------------------------------------------------------+
enum ENUM_BIAS_ENGINE
{
   ENGINE_SUPERTREND_CLASSIC = 0,   // Supertrend classico (HL2 + ATR)
   ENGINE_MA_ATR_BAND        = 1    // MA + banda ATR (default)
};

//+------------------------------------------------------------------+
//| Enum: tipo MA (attivo solo in ENGINE_MA_ATR_BAND)                |
//+------------------------------------------------------------------+
enum ENUM_BIAS_MATYPE
{
   BIAS_MA_EMA  = 0,
   BIAS_MA_SMA  = 1,
   BIAS_MA_SMMA = 2,
   BIAS_MA_LWMA = 3,
   BIAS_MA_HMA  = 4,
   BIAS_MA_KAMA = 5    // default
};

//+------------------------------------------------------------------+
//| Enum: smoothing ATR                                              |
//+------------------------------------------------------------------+
enum ENUM_BIAS_ATR_SMOOTH
{
   BIAS_ATR_WILDER_RMA = 0,  // default, coerente con ecosistema
   BIAS_ATR_SMA        = 1,
   BIAS_ATR_EMA        = 2
};

//+------------------------------------------------------------------+
//| Enum: rendering (v1.00 solo overlay effettivo)                   |
//+------------------------------------------------------------------+
enum ENUM_BIAS_DRAWMODE
{
   DRAW_OVERLAY_CHART = 0,   // default, unico supportato in v1.00
   DRAW_SUBWINDOW     = 1    // placeholder per v1.10
};

//+------------------------------------------------------------------+
//| INPUT                                                            |
//+------------------------------------------------------------------+
input group "=== Engine ==="
input ENUM_BIAS_ENGINE   InpEngineMode     = ENGINE_MA_ATR_BAND;  // Modalità engine

input group "=== Timeframe di calcolo ==="
input ENUM_TIMEFRAMES    InpBiasTF         = PERIOD_H4;           // TF di calcolo bias

input group "=== Parametri MA (solo MA_ATR_BAND) ==="
input ENUM_BIAS_MATYPE   InpMAType         = BIAS_MA_KAMA;        // Tipo MA
input int                InpMAPeriod       = 21;                  // Periodo MA
input int                InpKAMAFast       = 2;                   // KAMA Fast SC
input int                InpKAMASlow       = 30;                  // KAMA Slow SC

input group "=== Parametri ATR ==="
input int                InpATRPeriod      = 10;                  // Periodo ATR
input double             InpATRMultiplier  = 2.5;                 // Moltiplicatore banda
input ENUM_BIAS_ATR_SMOOTH InpATRSmoothing = BIAS_ATR_WILDER_RMA; // Smoothing ATR

input group "=== Rendering ==="
input ENUM_BIAS_DRAWMODE InpDrawMode       = DRAW_OVERLAY_CHART;  // Modalità disegno
input bool               InpShowBands      = true;                // Mostra bande ATR
input bool               InpShowDashboard  = true;                // Mostra label dashboard

input group "=== Warmup ==="
input int                InpWarmupExtraBars= 10;                  // Barre extra warmup HTF

//+------------------------------------------------------------------+
//| BUFFER                                                           |
//+------------------------------------------------------------------+
double B_MainLine  [];   // Buffer 0
double B_Upper     [];   // Buffer 1
double B_Lower     [];   // Buffer 2
double B_State     [];   // Buffer 3  (esposto per iCustom EA)
double B_Flip      [];   // Buffer 4
double B_ColorIndex[];   // Buffer 5  (color index per DRAW_COLOR_LINE)

//+------------------------------------------------------------------+
//| CACHE HTF (calcolata ogni OnCalculate, series indexing)          |
//| Indice 0 = barra HTF più recente (eventualmente in formazione)   |
//+------------------------------------------------------------------+
double    g_htf_close[];
double    g_htf_high [];
double    g_htf_low  [];
datetime  g_htf_time [];
double    g_htf_ma   [];   // MA su HTF (solo se ENGINE_MA_ATR_BAND)
double    g_htf_atr  [];   // ATR Wilder RMA su HTF
double    g_htf_base [];   // base = close-HL2 o MA (a seconda del mode)
double    g_htf_fUp  [];   // final upper ratchettato
double    g_htf_fLow [];   // final lower ratchettato
int       g_htf_state[];   // +1 / -1 / 0 (warmup)

int       g_htfBarsUsed = 0;  // quante barre HTF sono effettivamente calcolate

//--- Handle MA MT5 per EMA/SMA/SMMA/LWMA (iMA su HTF)
int       g_hMA_Standard = INVALID_HANDLE;

//--- Handle MA aux per HMA (due LWMA su periodi diversi)
int       g_hMA_HMA_Half = INVALID_HANDLE;
int       g_hMA_HMA_Full = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Nome oggetto dashboard                                           |
//+------------------------------------------------------------------+
const string DASH_LABEL_NAME = "RattBiasTrend_Dash";

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Mappa buffer
   SetIndexBuffer(0, B_MainLine,   INDICATOR_DATA);
   SetIndexBuffer(1, B_Upper,      INDICATOR_DATA);
   SetIndexBuffer(2, B_Lower,      INDICATOR_DATA);
   SetIndexBuffer(3, B_State,      INDICATOR_DATA);
   SetIndexBuffer(4, B_Flip,       INDICATOR_DATA);
   SetIndexBuffer(5, B_ColorIndex, INDICATOR_COLOR_INDEX);

   //--- EMPTY_VALUE per tutti i buffer visivi
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Nascondi bande se richiesto
   if(!InpShowBands)
   {
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
   }

   //--- Validazione TF: deve essere >= del chart corrente
   if((int)InpBiasTF < (int)Period() && InpBiasTF != PERIOD_CURRENT)
   {
      Print("[RattBiasTrend] WARN: InpBiasTF (", EnumToString(InpBiasTF),
            ") è inferiore al TF del chart (", EnumToString((ENUM_TIMEFRAMES)Period()),
            "). Il bias non ha senso su TF inferiori. L'indicatore funzionerà ma il paradigma è invertito.");
   }

   //--- Fallback DrawMode: in v1.00 solo overlay è supportato
   if(InpDrawMode != DRAW_OVERLAY_CHART)
   {
      Print("[RattBiasTrend] WARN: DRAW_SUBWINDOW non implementato in v1.00, fallback a DRAW_OVERLAY_CHART.");
   }

   //--- Crea handle MA standard se servono
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
   {
      if(!CreateMAHandles())
      {
         Print("[RattBiasTrend] ERROR: impossibile creare handle MA. Init fallito.");
         return INIT_FAILED;
      }
   }

   //--- Short name
   string shortName = BuildShortName();
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   //--- Dashboard
   if(InpShowDashboard)
      CreateDashboardLabel();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hMA_Standard != INVALID_HANDLE) { IndicatorRelease(g_hMA_Standard); g_hMA_Standard = INVALID_HANDLE; }
   if(g_hMA_HMA_Half != INVALID_HANDLE) { IndicatorRelease(g_hMA_HMA_Half); g_hMA_HMA_Half = INVALID_HANDLE; }
   if(g_hMA_HMA_Full != INVALID_HANDLE) { IndicatorRelease(g_hMA_HMA_Full); g_hMA_HMA_Full = INVALID_HANDLE; }

   if(ObjectFind(0, DASH_LABEL_NAME) >= 0)
      ObjectDelete(0, DASH_LABEL_NAME);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int        rates_total,
                const int        prev_calculated,
                const datetime  &time[],
                const double    &open[],
                const double    &high[],
                const double    &low[],
                const double    &close[],
                const long      &tick_volume[],
                const long      &volume[],
                const int       &spread[])
{
   //--- Working buffers non in series (coerente con chart bars)
   ArraySetAsSeries(B_MainLine,   false);
   ArraySetAsSeries(B_Upper,      false);
   ArraySetAsSeries(B_Lower,      false);
   ArraySetAsSeries(B_State,      false);
   ArraySetAsSeries(B_Flip,       false);
   ArraySetAsSeries(B_ColorIndex, false);
   ArraySetAsSeries(time,         false);

   //--- Barre HTF disponibili
   int htfBarsAvailable = Bars(_Symbol, InpBiasTF);
   int requiredWarmup = MathMax(InpMAPeriod, InpATRPeriod) + InpWarmupExtraBars + 5;
   if(htfBarsAvailable < requiredWarmup)
   {
      // Non abbastanza storia HTF — riempi tutto con warmup
      FillWarmup(rates_total);
      return rates_total;
   }

   //--- Step 1-2: copia dati HTF in cache
   // Usiamo series indexing interno: g_htf_*[0] = barra HTF più recente
   int htfBarsToUse = MathMin(htfBarsAvailable, 5000);  // cap per performance
   if(!RefreshHTFCache(htfBarsToUse))
   {
      FillWarmup(rates_total);
      return rates_total;
   }

   //--- Step 3: calcolo MA su HTF (se necessario)
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
   {
      if(!ComputeHTFMA())
      {
         FillWarmup(rates_total);
         return rates_total;
      }
   }

   //--- Step 4: calcolo ATR Wilder RMA su HTF
   if(!ComputeHTFATR())
   {
      FillWarmup(rates_total);
      return rates_total;
   }

   //--- Step 5: base, bande, ratchet, stato su HTF
   ComputeHTFState();

   //--- Step 6: proiezione HTF -> LTF chart bars
   ProjectHTFToChart(rates_total, prev_calculated, time);

   //--- Step 7: dashboard
   if(InpShowDashboard)
      UpdateDashboardLabel();

   return rates_total;
}

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+

//--- Crea gli handle iMA necessari in base a InpMAType
bool CreateMAHandles()
{
   ENUM_MA_METHOD m = MODE_EMA;
   bool needStandard = true;
   bool needHMA = false;

   switch(InpMAType)
   {
      case BIAS_MA_EMA:  m = MODE_EMA;  break;
      case BIAS_MA_SMA:  m = MODE_SMA;  break;
      case BIAS_MA_SMMA: m = MODE_SMMA; break;
      case BIAS_MA_LWMA: m = MODE_LWMA; break;
      case BIAS_MA_HMA:  needStandard = false; needHMA = true; break;
      case BIAS_MA_KAMA: needStandard = false; break;  // KAMA calcolata inline
      default: needStandard = false; break;
   }

   if(needStandard)
   {
      g_hMA_Standard = iMA(_Symbol, InpBiasTF, InpMAPeriod, 0, m, PRICE_CLOSE);
      if(g_hMA_Standard == INVALID_HANDLE)
      {
         Print("[RattBiasTrend] ERROR: iMA handle failed, err=", GetLastError());
         return false;
      }
   }

   if(needHMA)
   {
      int halfN = MathMax(1, InpMAPeriod / 2);
      g_hMA_HMA_Half = iMA(_Symbol, InpBiasTF, halfN,         0, MODE_LWMA, PRICE_CLOSE);
      g_hMA_HMA_Full = iMA(_Symbol, InpBiasTF, InpMAPeriod,   0, MODE_LWMA, PRICE_CLOSE);
      if(g_hMA_HMA_Half == INVALID_HANDLE || g_hMA_HMA_Full == INVALID_HANDLE)
      {
         Print("[RattBiasTrend] ERROR: HMA handles failed, err=", GetLastError());
         return false;
      }
   }

   return true;
}

//--- Refresh cache HTF (close/high/low/time in series indexing)
bool RefreshHTFCache(int barsToUse)
{
   ArrayResize(g_htf_close, barsToUse);
   ArrayResize(g_htf_high,  barsToUse);
   ArrayResize(g_htf_low,   barsToUse);
   ArrayResize(g_htf_time,  barsToUse);

   ArraySetAsSeries(g_htf_close, true);
   ArraySetAsSeries(g_htf_high,  true);
   ArraySetAsSeries(g_htf_low,   true);
   ArraySetAsSeries(g_htf_time,  true);

   int got = CopyClose(_Symbol, InpBiasTF, 0, barsToUse, g_htf_close);
   if(got <= 0) return false;
   if(CopyHigh(_Symbol, InpBiasTF, 0, barsToUse, g_htf_high) <= 0) return false;
   if(CopyLow (_Symbol, InpBiasTF, 0, barsToUse, g_htf_low)  <= 0) return false;
   if(CopyTime(_Symbol, InpBiasTF, 0, barsToUse, g_htf_time) <= 0) return false;

   g_htfBarsUsed = got;

   // Resize output arrays
   ArrayResize(g_htf_ma,    g_htfBarsUsed);
   ArrayResize(g_htf_atr,   g_htfBarsUsed);
   ArrayResize(g_htf_base,  g_htfBarsUsed);
   ArrayResize(g_htf_fUp,   g_htfBarsUsed);
   ArrayResize(g_htf_fLow,  g_htfBarsUsed);
   ArrayResize(g_htf_state, g_htfBarsUsed);

   ArraySetAsSeries(g_htf_ma,    true);
   ArraySetAsSeries(g_htf_atr,   true);
   ArraySetAsSeries(g_htf_base,  true);
   ArraySetAsSeries(g_htf_fUp,   true);
   ArraySetAsSeries(g_htf_fLow,  true);
   ArraySetAsSeries(g_htf_state, true);

   return true;
}

//--- Calcola MA HTF nel modo selezionato
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

      default:
         return false;
   }
}

//--- MA standard via iMA handle (EMA/SMA/SMMA/LWMA)
bool ComputeHTFMA_Standard()
{
   if(g_hMA_Standard == INVALID_HANDLE) return false;

   // Aspetta che l'handle sia pronto
   int copied = CopyBuffer(g_hMA_Standard, 0, 0, g_htfBarsUsed, g_htf_ma);
   if(copied <= 0) return false;

   ArraySetAsSeries(g_htf_ma, true);
   return true;
}

//--- HMA custom: LWMA(2*LWMA(n/2) - LWMA(n), floor(sqrt(n)))
bool ComputeHTFMA_HMA()
{
   if(g_hMA_HMA_Half == INVALID_HANDLE || g_hMA_HMA_Full == INVALID_HANDLE) return false;

   double lwmaHalf[], lwmaFull[];
   ArraySetAsSeries(lwmaHalf, true);
   ArraySetAsSeries(lwmaFull, true);
   ArrayResize(lwmaHalf, g_htfBarsUsed);
   ArrayResize(lwmaFull, g_htfBarsUsed);

   if(CopyBuffer(g_hMA_HMA_Half, 0, 0, g_htfBarsUsed, lwmaHalf) <= 0) return false;
   if(CopyBuffer(g_hMA_HMA_Full, 0, 0, g_htfBarsUsed, lwmaFull) <= 0) return false;

   // Step 1: raw = 2*lwmaHalf - lwmaFull
   double raw[];
   ArraySetAsSeries(raw, true);
   ArrayResize(raw, g_htfBarsUsed);
   for(int i = 0; i < g_htfBarsUsed; i++)
      raw[i] = 2.0 * lwmaHalf[i] - lwmaFull[i];

   // Step 2: LWMA di raw con period = floor(sqrt(n))
   int sqrtN = MathMax(1, (int)MathFloor(MathSqrt((double)InpMAPeriod)));
   for(int i = 0; i < g_htfBarsUsed; i++)
   {
      if(i + sqrtN > g_htfBarsUsed)
      {
         g_htf_ma[i] = EMPTY_VALUE;
         continue;
      }
      double num = 0.0, den = 0.0;
      for(int k = 0; k < sqrtN; k++)
      {
         double w = (double)(sqrtN - k);  // peso: la barra più recente (k=0) ha peso maggiore
         num += raw[i + k] * w;
         den += w;
      }
      g_htf_ma[i] = (den > 0.0) ? num / den : EMPTY_VALUE;
   }
   return true;
}

//--- KAMA custom su close HTF
bool ComputeHTFMA_KAMA()
{
   int N = InpMAPeriod;
   if(g_htfBarsUsed < N + 2) return false;

   double fastSC = 2.0 / ((double)InpKAMAFast + 1.0);
   double slowSC = 2.0 / ((double)InpKAMASlow + 1.0);

   // Seed: usa close della barra più vecchia utilizzabile (indice = g_htfBarsUsed - 1)
   // Iteriamo da più vecchia (indice alto) a più recente (indice 0)
   for(int i = g_htfBarsUsed - 1; i >= 0; i--)
   {
      if(i + N >= g_htfBarsUsed)
      {
         g_htf_ma[i] = g_htf_close[i];  // warmup — seed
         continue;
      }

      // Change e volatility
      double change = MathAbs(g_htf_close[i] - g_htf_close[i + N]);
      double vol    = 0.0;
      for(int k = 0; k < N; k++)
         vol += MathAbs(g_htf_close[i + k] - g_htf_close[i + k + 1]);

      double er = (vol > 0.0) ? change / vol : 0.0;
      double sc = MathPow(er * (fastSC - slowSC) + slowSC, 2.0);

      // Ricorsione: [i+1] è la barra precedente (più vecchia) in series indexing
      double prevK = g_htf_ma[i + 1];
      if(prevK == EMPTY_VALUE) prevK = g_htf_close[i + 1];

      g_htf_ma[i] = prevK + sc * (g_htf_close[i] - prevK);
   }
   return true;
}

//--- ATR Wilder RMA su HTF (o alternative SMA/EMA)
bool ComputeHTFATR()
{
   int N = InpATRPeriod;
   if(g_htfBarsUsed < N + 2) return false;

   // True Range in array temporaneo
   double tr[];
   ArraySetAsSeries(tr, true);
   ArrayResize(tr, g_htfBarsUsed);

   for(int i = 0; i < g_htfBarsUsed - 1; i++)
   {
      double h = g_htf_high[i];
      double l = g_htf_low[i];
      double cp = g_htf_close[i + 1];  // close della barra precedente (series: +1)
      double tr1 = h - l;
      double tr2 = MathAbs(h - cp);
      double tr3 = MathAbs(l - cp);
      tr[i] = MathMax(tr1, MathMax(tr2, tr3));
   }
   tr[g_htfBarsUsed - 1] = g_htf_high[g_htfBarsUsed - 1] - g_htf_low[g_htfBarsUsed - 1];

   switch(InpATRSmoothing)
   {
      case BIAS_ATR_WILDER_RMA:
      {
         // Seed: SMA delle prime N TR a partire dalla più vecchia
         int seedIdx = g_htfBarsUsed - N - 1;
         if(seedIdx < 0) return false;

         double sum = 0.0;
         for(int k = 0; k < N; k++) sum += tr[seedIdx + k];
         g_htf_atr[seedIdx] = sum / N;

         // Riempi warmup precedente con EMPTY_VALUE
         for(int i = g_htfBarsUsed - 1; i > seedIdx; i--)
            g_htf_atr[i] = EMPTY_VALUE;

         // Wilder RMA ricorsiva verso barre più recenti (indice decrescente)
         for(int i = seedIdx - 1; i >= 0; i--)
            g_htf_atr[i] = (g_htf_atr[i + 1] * (N - 1) + tr[i]) / N;

         break;
      }
      case BIAS_ATR_SMA:
      {
         for(int i = 0; i < g_htfBarsUsed; i++)
         {
            if(i + N > g_htfBarsUsed) { g_htf_atr[i] = EMPTY_VALUE; continue; }
            double s = 0.0;
            for(int k = 0; k < N; k++) s += tr[i + k];
            g_htf_atr[i] = s / N;
         }
         break;
      }
      case BIAS_ATR_EMA:
      {
         double alpha = 2.0 / (N + 1.0);
         int seedIdx = g_htfBarsUsed - N - 1;
         if(seedIdx < 0) return false;
         double sum = 0.0;
         for(int k = 0; k < N; k++) sum += tr[seedIdx + k];
         g_htf_atr[seedIdx] = sum / N;
         for(int i = g_htfBarsUsed - 1; i > seedIdx; i--)
            g_htf_atr[i] = EMPTY_VALUE;
         for(int i = seedIdx - 1; i >= 0; i--)
            g_htf_atr[i] = alpha * tr[i] + (1.0 - alpha) * g_htf_atr[i + 1];
         break;
      }
   }
   return true;
}

//--- Calcola base, bande, ratchet, stato su HTF
void ComputeHTFState()
{
   // Step A: base = MA (in MA mode) o HL2 (in Supertrend mode)
   for(int i = 0; i < g_htfBarsUsed; i++)
   {
      if(InpEngineMode == ENGINE_SUPERTREND_CLASSIC)
         g_htf_base[i] = (g_htf_high[i] + g_htf_low[i]) * 0.5;
      else
         g_htf_base[i] = g_htf_ma[i];
   }

   // Step B: inizializza stato sulla barra più vecchia
   int oldest = g_htfBarsUsed - 1;
   g_htf_state[oldest] = +1;
   if(g_htf_base[oldest] != EMPTY_VALUE && g_htf_atr[oldest] != EMPTY_VALUE)
   {
      g_htf_fUp [oldest] = g_htf_base[oldest] + InpATRMultiplier * g_htf_atr[oldest];
      g_htf_fLow[oldest] = g_htf_base[oldest] - InpATRMultiplier * g_htf_atr[oldest];
   }
   else
   {
      g_htf_fUp [oldest] = EMPTY_VALUE;
      g_htf_fLow[oldest] = EMPTY_VALUE;
      g_htf_state[oldest] = 0;
   }

   // Step C: iterazione da più vecchia (indice alto) a più recente (indice basso)
   for(int i = oldest - 1; i >= 0; i--)
   {
      double base = g_htf_base[i];
      double atr  = g_htf_atr [i];

      if(base == EMPTY_VALUE || atr == EMPTY_VALUE)
      {
         g_htf_fUp [i] = EMPTY_VALUE;
         g_htf_fLow[i] = EMPTY_VALUE;
         g_htf_state[i] = 0;
         continue;
      }

      double basicUp  = base + InpATRMultiplier * atr;
      double basicLow = base - InpATRMultiplier * atr;

      double prevUp  = g_htf_fUp [i + 1];
      double prevLow = g_htf_fLow[i + 1];
      double prevClose = g_htf_close[i + 1];

      // Se il precedente era in warmup, avvia qui
      if(prevUp == EMPTY_VALUE || prevLow == EMPTY_VALUE || g_htf_state[i + 1] == 0)
      {
         g_htf_fUp [i] = basicUp;
         g_htf_fLow[i] = basicLow;
         g_htf_state[i] = (g_htf_close[i] >= base) ? +1 : -1;
         continue;
      }

      // Ratchet
      double finalUp  = (basicUp  < prevUp  || prevClose > prevUp ) ? basicUp  : prevUp;
      double finalLow = (basicLow > prevLow || prevClose < prevLow) ? basicLow : prevLow;

      // State transition
      int prevState = g_htf_state[i + 1];
      int newState  = prevState;
      if(prevState == +1 && g_htf_close[i] < finalLow) newState = -1;
      else if(prevState == -1 && g_htf_close[i] > finalUp) newState = +1;

      g_htf_fUp [i] = finalUp;
      g_htf_fLow[i] = finalLow;
      g_htf_state[i] = newState;
   }
}

//--- Proietta stato HTF su chart bars (anti-repainting)
void ProjectHTFToChart(const int rates_total,
                       const int prev_calculated,
                       const datetime &time[])
{
   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   for(int i = start; i < rates_total; i++)
   {
      int htfShift = iBarShift(_Symbol, InpBiasTF, time[i], false);
      // Anti-repainting: usa sempre la barra HTF chiusa PRECEDENTE a quella che contiene time[i]
      int stateShift = htfShift + 1;

      if(htfShift < 0 || stateShift < 0 || stateShift >= g_htfBarsUsed)
      {
         // Left edge o no match: warmup
         B_MainLine  [i] = EMPTY_VALUE;
         B_Upper     [i] = EMPTY_VALUE;
         B_Lower     [i] = EMPTY_VALUE;
         B_State     [i] = 0.0;
         B_Flip      [i] = 0.0;
         B_ColorIndex[i] = 2.0;  // grigio
         continue;
      }

      double base = g_htf_base [stateShift];
      double fUp  = g_htf_fUp  [stateShift];
      double fLow = g_htf_fLow [stateShift];
      int    st   = g_htf_state[stateShift];

      if(base == EMPTY_VALUE || st == 0)
      {
         B_MainLine  [i] = EMPTY_VALUE;
         B_Upper     [i] = EMPTY_VALUE;
         B_Lower     [i] = EMPTY_VALUE;
         B_State     [i] = 0.0;
         B_Flip      [i] = 0.0;
         B_ColorIndex[i] = 2.0;
         continue;
      }

      B_MainLine[i] = base;
      B_Upper   [i] = (InpShowBands ? fUp  : EMPTY_VALUE);
      B_Lower   [i] = (InpShowBands ? fLow : EMPTY_VALUE);
      B_State   [i] = (double)st;
      B_ColorIndex[i] = (st == +1) ? 0.0 : (st == -1 ? 1.0 : 2.0);

      // Flip detection: state cambiato rispetto alla chart bar precedente
      if(i > 0 && B_State[i-1] != 0.0 && B_State[i] != B_State[i-1])
         B_Flip[i] = 1.0;
      else
         B_Flip[i] = 0.0;
   }
}

//--- Riempie tutti i buffer con warmup (0/EMPTY/grigio)
void FillWarmup(const int rates_total)
{
   for(int i = 0; i < rates_total; i++)
   {
      B_MainLine  [i] = EMPTY_VALUE;
      B_Upper     [i] = EMPTY_VALUE;
      B_Lower     [i] = EMPTY_VALUE;
      B_State     [i] = 0.0;
      B_Flip      [i] = 0.0;
      B_ColorIndex[i] = 2.0;
   }
}

//--- Short name
string BuildShortName()
{
   string engineStr = (InpEngineMode == ENGINE_SUPERTREND_CLASSIC) ? "ST" : "MA+ATR";
   string maStr = "";
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
   {
      string maType = "";
      switch(InpMAType)
      {
         case BIAS_MA_EMA:  maType = "EMA";  break;
         case BIAS_MA_SMA:  maType = "SMA";  break;
         case BIAS_MA_SMMA: maType = "SMMA"; break;
         case BIAS_MA_LWMA: maType = "LWMA"; break;
         case BIAS_MA_HMA:  maType = "HMA";  break;
         case BIAS_MA_KAMA: maType = "KAMA"; break;
      }
      maStr = " " + maType + "(" + IntegerToString(InpMAPeriod) + ")";
   }
   return StringFormat("RattBiasTrend [%s]%s ATR(%d×%.1f) @ %s",
                       engineStr, maStr, InpATRPeriod, InpATRMultiplier,
                       EnumToString(InpBiasTF));
}

//--- Dashboard label
void CreateDashboardLabel()
{
   if(ObjectFind(0, DASH_LABEL_NAME) < 0)
   {
      ObjectCreate(0, DASH_LABEL_NAME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_YDISTANCE, 25);
      ObjectSetString (0, DASH_LABEL_NAME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_BACK, false);
      ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_SELECTABLE, false);
   }
   UpdateDashboardLabel();
}

void UpdateDashboardLabel()
{
   int idx = 0;  // barra corrente in non-series indexing = ultimo chart bar
   int last = Bars(_Symbol, _Period) - 1;
   // Prendiamo lo stato del chart bar più recente (idx = last)
   // ma ricorda che B_State è non-series, quindi barra più recente = ultimo indice
   double st = 0.0;
   if(ArraySize(B_State) > 0) st = B_State[ArraySize(B_State) - 1];

   string stateStr = "WARMUP";
   color  clr = clrSilver;
   if(st > 0.5)      { stateStr = "LONG";  clr = clrLime; }
   else if(st < -0.5){ stateStr = "SHORT"; clr = clrRed;  }

   string maInfo = "";
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
   {
      string maType = "";
      switch(InpMAType)
      {
         case BIAS_MA_EMA:  maType = "EMA";  break;
         case BIAS_MA_SMA:  maType = "SMA";  break;
         case BIAS_MA_SMMA: maType = "SMMA"; break;
         case BIAS_MA_LWMA: maType = "LWMA"; break;
         case BIAS_MA_HMA:  maType = "HMA";  break;
         case BIAS_MA_KAMA: maType = "KAMA"; break;
      }
      maInfo = StringFormat("[MA+ATR] %s(%d) ", maType, InpMAPeriod);
   }
   else
   {
      maInfo = "[Supertrend] HL2 ";
   }

   string txt = StringFormat("BIAS %s %sATR(%d×%.1f) → %s",
                             EnumToString(InpBiasTF),
                             maInfo,
                             InpATRPeriod, InpATRMultiplier,
                             stateStr);

   ObjectSetString (0, DASH_LABEL_NAME, OBJPROP_TEXT,  txt);
   ObjectSetInteger(0, DASH_LABEL_NAME, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
```

---

## 5. Validazione e checklist di regressione

Dopo la compilazione pulita (zero errori, zero warning critici), effettuare le seguenti verifiche **in ordine**.

### 5.1 Check compilazione

- [ ] MetaEditor → Compile → 0 errori
- [ ] Warning accettabili: solo su variabili non usate o deprecation dell'API (nessun warning su struct/funzione critica)

### 5.2 Check 1 — Caricamento su chart vuoto

- [ ] Apri USDJPY M15, trascina `RattBiasTrend` con parametri default
- [ ] Appare una linea colorata sovrapposta alle candele M15
- [ ] Appare la label in alto a destra: `BIAS PERIOD_H4 [MA+ATR] KAMA(21) ATR(10×2.5) → LONG` (o SHORT a seconda dello stato H4 corrente)
- [ ] Colore linea = verde se label dice LONG, rosso se SHORT, grigio se WARMUP

### 5.3 Check 2 — Coerenza HTF→LTF

- [ ] Apri contemporaneamente due chart dello stesso simbolo: uno a H4 e uno a M15
- [ ] Applica `RattBiasTrend` con `InpBiasTF=PERIOD_H4` su entrambi
- [ ] Sul chart H4 la linea colorata cambia colore **solo** al closing della candela H4
- [ ] Sul chart M15 la linea cambia colore **solo** all'apertura della candela M15 che segue una chiusura H4 con flip
- [ ] In ogni istante, il colore sul chart M15 corrisponde al colore della candela H4 chiusa più recente

### 5.4 Check 3 — Anti-repainting

- [ ] Tester visuale MT5 (velocità bassa), periodo 10-20 aprile 2026, USDJPY M15
- [ ] Osserva una candela H4 in formazione: il prezzo deve poter oscillare all'interno della candela H4 senza che la linea sul chart M15 cambi colore
- [ ] La linea cambia colore SOLO quando la candela H4 si chiude (cioè quando nel tester passa al primo tick della nuova H4)
- [ ] Nessuna barra storica già processata cambia colore retroattivamente

### 5.5 Check 4 — Confronto modalità

- [ ] Stesso chart USDJPY M15
- [ ] Applica `RattBiasTrend` due volte con colori diversi (cambia Plot 0 color manualmente):
  - Istanza A: `InpEngineMode=ENGINE_SUPERTREND_CLASSIC`, `InpATRMultiplier=3.0`
  - Istanza B: `InpEngineMode=ENGINE_MA_ATR_BAND`, `InpMAType=BIAS_MA_KAMA`, `InpATRMultiplier=2.5`
- [ ] Entrambe devono plottare sensatamente, conta i flip H4 nel periodo 10-20 aprile
- [ ] Aspettativa: modalità MA+ATR produce meno flip del Supertrend classico (grazie al filtro MA)

### 5.6 Check 5 — Tipi MA selezionabili

Per ognuno dei tipi {EMA, SMA, SMMA, LWMA, HMA, KAMA} con `InpEngineMode=ENGINE_MA_ATR_BAND`:
- [ ] Cambia `InpMAType`, ricarica l'indicatore
- [ ] La short name si aggiorna con il nuovo tipo
- [ ] La linea viene plottata senza errori in log
- [ ] Lo stato long/short è coerente visivamente con la posizione del prezzo rispetto alla MA

### 5.7 Check 6 — Parametrizzazione TF

Per ogni TF in `{PERIOD_H1, PERIOD_H4, PERIOD_D1}`:
- [ ] Cambia `InpBiasTF`, ricarica
- [ ] Short name e label riflettono il nuovo TF
- [ ] La linea bias si aggiorna con granularità coerente (es. D1 = cambia colore ancora più raramente di H4)

### 5.8 Check 7 — Buffer esposizione via iCustom (smoke test)

Crea uno script di test temporaneo `TestReadBias.mq5`:

```mql5
void OnStart()
{
   int h = iCustom(_Symbol, _Period, "RattBiasTrend");
   if(h == INVALID_HANDLE) { Print("FAIL handle"); return; }
   Sleep(500);
   double st[1];
   ArraySetAsSeries(st, true);
   if(CopyBuffer(h, 3, 0, 1, st) > 0)
      Print("B_State = ", st[0]);
   else
      Print("CopyBuffer failed: ", GetLastError());
   IndicatorRelease(h);
}
```

- [ ] Esegui lo script sul chart con `RattBiasTrend` attivo
- [ ] L'output deve essere `B_State = 1.0`, `-1.0`, o `0.0` (coerente con label dashboard)

### 5.9 Check 8 — Log puliti

- [ ] Tab "Experts" di MT5: nessun `ERROR` relativo a `RattBiasTrend` durante 5 minuti di funzionamento continuo
- [ ] I soli `WARN` accettabili sono quelli previsti (TF inverso o DrawMode non implementato)

---

## 6. Note importanti per Claude Code

### 6.1 Coerenza con l'ecosistema

- **ATR algorithm:** in questo indicatore implementiamo Wilder RMA manualmente. NON usare `iATR()` built-in MT5 perché usa SMA (lo stesso bug di divergenza engine-indicator già risolto nel progetto).
- **Pattern HTF→LTF:** il metodo usato (`iBarShift` + `stateShift = htfShift + 1`) è lo stesso validato in UTBot V3.52 dopo il bug del "current HTF state applicato a tutte le barre storiche". NON sostituire con pattern più semplici tipo `CopyBuffer offset 0` che riprodurrebbe il bug.
- **Naming:** prefisso `B_` per i buffer e `g_htf_` per i cache interni segue la convenzione Rattapignola già in uso.

### 6.2 Verifiche da non saltare

- Prima di dichiarare "fatto", verificare che **tutti i 6 buffer siano mappati** con `SetIndexBuffer`.
- Verificare che **Plot 0 usi `DRAW_COLOR_LINE`** con 3 colori (verde, rosso, grigio) e che `INDICATOR_COLOR_INDEX` sia sul buffer 5.
- Verificare che la compilazione produca **zero errori** (warning permessi solo su variabili non usate).

### 6.3 Cosa NON fare

- Non aggiungere feature non richieste (flat detection, VWAP, alert, integrazioni UTBot). Sono esplicitamente rimandate a versioni future.
- Non modificare altri file del progetto. L'indicatore è standalone.
- Non implementare JMA in v1.00: non è nell'enum `ENUM_BIAS_MATYPE` di questa versione; verrà portato dal codice UTBot in v1.10.
- Non creare file accessori (.mqh separati). Tutto in un singolo `.mq5`.

### 6.4 Deliverable atteso

1. Il file `MQL5/Indicators/RattBiasTrend.mq5` creato ex novo con il codice sopra.
2. Compilazione pulita.
3. Conferma testuale di aver eseguito i check della sezione 5 (almeno Check 1, 2, 3, 8).

---

**Fine istruzioni.**
