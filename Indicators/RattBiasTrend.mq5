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
//| STILE VISUALE — allineato UTBotAdaptive (dark navy + teal):      |
//|   - Tema chart scuro opzionale (InpApplyTheme), grid off default |
//|   - Colori candele teal/coral coerenti con bias line             |
//|   - Dashboard modern con card (STATO BIAS + CONFIGURAZIONE)      |
//|   - Font Segoe UI / Consolas, palette identica a UTBot           |
//|                                                                  |
//| BUFFER PUBBLICI (per iCustom dell'EA):                           |
//|   Buffer 0: B_MainLine         — base (MA o HL2)                 |
//|   Buffer 1: B_ColorIndex       — 0 teal / 1 coral / 2 dim        |
//|   Buffer 2: B_Upper            — banda superiore finale          |
//|   Buffer 3: B_Lower            — banda inferiore finale          |
//|   Buffer 4: B_FlipLong         — prezzo freccia ▲ o EMPTY_VALUE  |
//|   Buffer 5: B_FlipShort        — prezzo freccia ▼ o EMPTY_VALUE  |
//|   Buffer 6: B_State            — GATE: +1 LONG / -1 SHORT / 0    |
//|   Buffer 7: B_Flip             — 1.0 sulla candela del flip HTF  |
//|   Buffer 8: B_EfficiencyRatio  — v1.09: Kaufman ER raw (0..1)    |
//|   Buffer 9: B_SuperSmoother    — v1.09: Ehlers SS su HTF         |
//|                                                                  |
//| v1.09 NOTE: i buffer 8-9 sono "observability pack" — esposti per |
//| lettura EA e dashboard, ma IL GATE RESTA B_State (voto singolo). |
//| Il committee AND verrà eventualmente aggiunto in v1.10 dopo      |
//| calibrazione empirica delle soglie sui dati reali.               |
//+------------------------------------------------------------------+
#property copyright   "Rattapignola ecosystem"
#property version     "1.13"
#property description "Bias HTF direzionale — Supertrend classico | MA+ATR"
#property description "v1.13: PMA Ehlers + One Euro Filter (anti-microstorni avanzato)"
#property description "v1.12: Sticky Bias — bande flip allargate + confirmation bars"
#property description "v1.11: Fix tema chart su cambio TF (helper atomici idempotenti)"
#property description "v1.10: Observability Pack — Kaufman ER (buf 8) + Ehlers SS (buf 9)"
#property description "Calcolo su TF configurabile, proiezione overlay sul chart"
#property description "Stile UTBotAdaptive: tema scuro + dashboard modern"

#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   5

//--- Plot 0: linea principale colorata (bias)
//    Palette UTBot: teal C'38,166,154' (LONG) / coral C'239,83,80' (SHORT) / dim C'95,110,140' (warmup)
#property indicator_label1  "Bias Line"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'38,166,154', C'239,83,80', C'95,110,140'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- Plot 1: banda superiore (dim navy dotted)
#property indicator_label2  "Upper Band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'95,110,140'
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Plot 2: banda inferiore (dim navy dotted)
#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'95,110,140'
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- Plot 3: freccia flip LONG (▲ teal sotto al low della candela LTF di flip)
#property indicator_label4  "HTF Flip LONG"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  C'38,166,154'
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

//--- Plot 4: freccia flip SHORT (▼ coral sopra all'high della candela LTF di flip)
#property indicator_label5  "HTF Flip SHORT"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  C'239,83,80'
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

//+------------------------------------------------------------------+
//| Enum: modalità engine                                            |
//+------------------------------------------------------------------+
enum ENUM_BIAS_ENGINE
{
   ENGINE_SUPERTREND_CLASSIC = 0,   // Supertrend Classic (base = HL2)
   ENGINE_MA_ATR_BAND        = 1    // MA + ATR Band (base = MA selezionata)
};

//+------------------------------------------------------------------+
//| Enum: tipo MA (attivo solo in ENGINE_MA_ATR_BAND)                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Enum: smoothing ATR                                              |
//+------------------------------------------------------------------+
enum ENUM_BIAS_ATR_SMOOTH
{
   BIAS_ATR_WILDER_RMA = 0,   // Wilder RMA (default, coerente con ecosistema)
   BIAS_ATR_SMA        = 1,   // SMA (Simple Moving Average)
   BIAS_ATR_EMA        = 2    // EMA (Exponential Moving Average)
};

//+------------------------------------------------------------------+
//| Enum: rendering (v1.00 solo overlay effettivo)                   |
//+------------------------------------------------------------------+
enum ENUM_BIAS_DRAWMODE
{
   DRAW_OVERLAY_CHART = 0,   // Overlay sul chart (default, unico supportato v1.0x)
   DRAW_SUBWINDOW     = 1    // Subwindow separata (placeholder — non implementato)
};

//+------------------------------------------------------------------+
//| Enum: livello di logging                                         |
//+------------------------------------------------------------------+
// Ordine: OFF(0) < ERROR(1) < WARN(2) < INFO(3) < DEBUG(4)
// Un messaggio di livello L viene stampato solo se L <= InpLogLevel.
enum ENUM_LOG_LEVEL
{
   LOG_OFF   = 0,   // OFF   — nessun log (uso produzione silenziosa)
   LOG_ERROR = 1,   // ERROR — solo errori bloccanti
   LOG_WARN  = 2,   // WARN  — errori + warning (config sospette)
   LOG_INFO  = 3,   // INFO  — errori + warning + eventi chiave (init, MA/ATR OK, stats) [default]
   LOG_DEBUG = 4    // DEBUG — tutto, inclusi dump di stato ad ogni frame
};

//+------------------------------------------------------------------+
//| INPUT                                                            |
//+------------------------------------------------------------------+
input group "=== Engine ==="
input ENUM_BIAS_ENGINE   InpEngineMode     = ENGINE_MA_ATR_BAND;  // Modalità engine

input group "=== Timeframe di calcolo ==="
input ENUM_TIMEFRAMES    InpBiasTF         = PERIOD_M30;          // TF di calcolo bias

input group "=== MA — Tipo e periodo base (EMA/SMA/SMMA/LWMA/HMA/KAMA) ==="
input ENUM_BIAS_MATYPE   InpMAType         = BIAS_MA_HMA;         // Tipo MA
input int                InpMAPeriod       = 21;                  // Periodo MA (ignorato se JMA)

input group "=== MA — Parametri KAMA (attivi SOLO se InpMAType = KAMA) ==="
input int                InpKAMAFast       = 2;                   // KAMA Fast SC (default 2)
input int                InpKAMASlow       = 30;                  // KAMA Slow SC (default 30)

input group "=== MA — Parametri JMA (attivi SOLO se InpMAType = JMA) ==="
input int                InpJMAPeriod      = 14;                  // JMA Period (usato al posto di MAPeriod)
input int                InpJMAPhase       = 0;                   // JMA Phase (-100..+100, 0 = neutro)

input group "=== Parametri ATR ==="
input int                InpATRPeriod      = 10;                  // Periodo ATR
input double             InpATRMultiplier  = 2.5;                 // Moltiplicatore banda
input ENUM_BIAS_ATR_SMOOTH InpATRSmoothing = BIAS_ATR_WILDER_RMA; // Smoothing ATR

input group "=== Rendering ==="
input ENUM_BIAS_DRAWMODE InpDrawMode       = DRAW_OVERLAY_CHART;  // Modalità disegno
input bool               InpShowBands      = true;                // Mostra bande ATR
input bool               InpShowFlipArrows = true;                // Mostra frecce flip HTF
input bool               InpShowDashboard  = true;                // Mostra dashboard

input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🎭 TEMA CHART                                           ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool   InpApplyTheme     = true;             // Applica Tema Scuro
input bool   InpShowGrid       = false;            // Mostra Griglia

input group "    🎨 COLORI TEMA"
input color  InpThemeBG        = C'19,23,34';      // Sfondo Chart
input color  InpThemeFG        = C'131,137,150';   // Testo, Assi
input color  InpThemeGrid      = C'42,46,57';      // Griglia
input color  InpThemeBullCandl = C'38,166,154';    // Candela Rialzista
input color  InpThemeBearCandl = C'239,83,80';     // Candela Ribassista

input group "=== Warmup ==="
input int                InpWarmupExtraBars= 10;                  // Barre extra warmup HTF

input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🎯 OBSERVABILITY PACK v1.09 (ER + SuperSmoother)        ║"
input group "╚═══════════════════════════════════════════════════════════╝"
// NOTA v1.09: questi parametri pilotano SOLO il calcolo dei buffer
// B_EfficiencyRatio e B_SuperSmoother e il pannello dashboard "Voti
// Preview". Il gate (B_State) NON usa ancora questi segnali — resta
// il ratchet MA+ATR del voto 1. Serve per osservare empiricamente
// i due filtri su dati reali prima di introdurre l'AND committee (v1.10).
input int                InpERLength         = 21;                // Lunghezza Kaufman ER
input double             InpERThreshold      = 0.35;              // Soglia centrale VALID/CHOP
input double             InpERHysteresis     = 0.05;              // Dead-band (±) per isteresi
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
input group "=== Sticky Bias (anti-microstorni) ==="
input bool               InpStickyBias        = true;             // Master switch (false = comportamento v1.11)
input double             InpATRMultiplierFlip = 3.5;              // Mult ATR per flip (>= InpATRMultiplier)
input int                InpFlipConfirmBars   = 1;                // Barre HTF consecutive per conferma flip (1 = no confirmation)

input group "=== Debug / Logging ==="
input ENUM_LOG_LEVEL     InpLogLevel       = LOG_INFO;             // Livello log (OFF/ERROR/WARN/INFO/DEBUG)

//+------------------------------------------------------------------+
//| BUFFER                                                           |
//+------------------------------------------------------------------+
// NB: in MQL5 il buffer INDICATOR_COLOR_INDEX di un DRAW_COLOR_LINE deve stare
// SUBITO dopo il buffer dati del suo plot. Ordine corretto:
//   Buffer 0 B_MainLine    DATA         → Plot 0 (DRAW_COLOR_LINE)
//   Buffer 1 B_ColorIndex  COLOR_INDEX  → color index di Plot 0
//   Buffer 2 B_Upper       DATA         → Plot 1 (DRAW_LINE)
//   Buffer 3 B_Lower       DATA         → Plot 2 (DRAW_LINE)
//   Buffer 4 B_FlipLong    DATA         → Plot 3 (DRAW_ARROW ▲)
//   Buffer 5 B_FlipShort   DATA         → Plot 4 (DRAW_ARROW ▼)
//   Buffer 6 B_State       DATA         → per iCustom EA
//   Buffer 7 B_Flip        DATA         → per iCustom EA
double B_MainLine       [];   // Buffer 0
double B_ColorIndex     [];   // Buffer 1 (INDICATOR_COLOR_INDEX per Plot 0)
double B_Upper          [];   // Buffer 2
double B_Lower          [];   // Buffer 3
double B_FlipLong       [];   // Buffer 4
double B_FlipShort      [];   // Buffer 5
double B_State          [];   // Buffer 6 (GATE, esposto per iCustom EA)
double B_Flip           [];   // Buffer 7 (esposto per iCustom EA)
// --- v1.09 observability buffers (INDICATOR_CALCULATIONS, esposti iCustom) ---
double B_EfficiencyRatio[];   // Buffer 8 — Kaufman ER su HTF proiettato su LTF
double B_SuperSmoother  [];   // Buffer 9 — Ehlers SuperSmoother su HTF proiettato su LTF

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
double    g_htf_fUp  [];   // final upper ratchettato (banda visiva, mult InpATRMultiplier)
double    g_htf_fLow [];   // final lower ratchettato (banda visiva)
double    g_htf_fUpFlip [];   // v1.12: banda di flip allargata (mult InpATRMultiplierFlip)
double    g_htf_fLowFlip[];   // v1.12: banda di flip allargata
int       g_htf_state[];   // +1 / -1 / 0 (warmup)
// --- v1.09 observability HTF cache ---
double    g_htf_er     [];   // Kaufman ER per bar HTF [0..1] (EMPTY_VALUE in warmup)
int       g_htf_erState[];   // Stato isteresi ER: 1=VALID, 0=CHOP
double    g_htf_ss     [];   // Ehlers 2-pole SuperSmoother value per bar HTF

int       g_htfBarsUsed = 0;  // quante barre HTF sono effettivamente calcolate

//--- Handle MA MT5 per EMA/SMA/SMMA/LWMA (iMA su HTF)
//    HMA, KAMA, JMA non usano handle — sono calcolate inline.
int       g_hMA_Standard = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Chart theme — colori originali per ripristino OnDeinit           |
//+------------------------------------------------------------------+
color  g_origBG          = clrBlack;
color  g_origFG          = clrWhite;
color  g_origGrid        = clrGray;
color  g_origChartUp     = clrBlack;
color  g_origChartDown   = clrBlack;
color  g_origChartLine   = clrBlack;
color  g_origCandleBull  = clrWhite;
color  g_origCandleBear  = clrBlack;
color  g_origBid         = clrGray;
color  g_origAsk         = clrGray;
color  g_origVolume      = clrGray;
bool   g_origShowGrid    = true;
int    g_origShowVolumes = 0;
bool   g_origForeground  = true;
bool   g_themeApplied    = false;
bool   g_origSaved       = false;  // v1.11: separa "originali salvati" da "tema applicato"

//+------------------------------------------------------------------+
//| Diagnostica one-shot: stampa stato buffer alla prima calcolo OK  |
//+------------------------------------------------------------------+
bool   g_diagPrinted     = false;

//+------------------------------------------------------------------+
//| LOGGING — helper centralizzato                                   |
//+------------------------------------------------------------------+
// Tutti i Print del modulo passano da RBTLog() per poter filtrare
// per livello (InpLogLevel). Il prefisso esplicita il modulo chiamante
// per rendere i log cercabili/filtrabili nel tab Experts di MT5.
//
// Uso:
//   RBTLog(LOG_ERROR, "MA", "iMA handle failed");
//   RBTLog(LOG_INFO,  "HTF", "cache refreshed: " + ...);
//   RBTLog(LOG_DEBUG, "STATE", "flip at bar " + ...);
void RBTLog(ENUM_LOG_LEVEL level, string module, string msg)
{
   if((int)level > (int)InpLogLevel) return;
   string tag = "?";
   switch(level)
   {
      case LOG_ERROR: tag = "ERR"; break;
      case LOG_WARN:  tag = "WRN"; break;
      case LOG_INFO:  tag = "INF"; break;
      case LOG_DEBUG: tag = "DBG"; break;
      default: tag = "?"; break;
   }
   Print("[RattBiasTrend ", tag, "][", module, "] ", msg);
}

//+------------------------------------------------------------------+
//| Dashboard — prefisso e layout (px) — palette UTBot compatibile   |
//+------------------------------------------------------------------+
string RBT_DASH_PREFIX = "RBT_DASH_";

#define DASH_X            12
#define DASH_Y            22
#define DASH_W            320
#define DASH_HEADER_H     34
#define DASH_CARD_W       304

//--- Palette (dark navy + teal accent, identica a UTBot)
#define CLR_BORDER        C'38,166,154'      // teal accent outer border
#define CLR_BG            C'15,21,38'        // navy molto scuro
#define CLR_HDR_BG        C'38,166,154'      // teal header bar
#define CLR_HDR_TXT       C'255,255,255'     // bianco header
#define CLR_CARD_BG       C'24,32,55'        // grigio-blu card
#define CLR_CARD_BORDER   C'45,58,90'        // bordo card
#define CLR_SECTION       C'100,200,210'     // teal chiaro section label
#define CLR_TXT_PRIMARY   C'225,230,240'     // off-white dato principale
#define CLR_TXT_SECOND    C'150,165,190'     // medium gray testo standard
#define CLR_TXT_DIM       C'95,110,140'      // dim gray
#define CLR_STATE_LONG    C'38,166,154'      // teal LONG
#define CLR_STATE_SHORT   C'239,83,80'       // coral SHORT
#define CLR_STATE_NEUT    C'95,110,140'      // dim gray WARMUP

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Mappa buffer (vedi commento sopra le dichiarazioni: il color index
   //    deve stare immediatamente dopo il data buffer del DRAW_COLOR_LINE)
   SetIndexBuffer(0, B_MainLine,        INDICATOR_DATA);
   SetIndexBuffer(1, B_ColorIndex,      INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, B_Upper,           INDICATOR_DATA);
   SetIndexBuffer(3, B_Lower,           INDICATOR_DATA);
   SetIndexBuffer(4, B_FlipLong,        INDICATOR_DATA);
   SetIndexBuffer(5, B_FlipShort,       INDICATOR_DATA);
   SetIndexBuffer(6, B_State,           INDICATOR_DATA);
   SetIndexBuffer(7, B_Flip,            INDICATOR_DATA);
   // v1.09: observability buffers (non plottati, solo per iCustom / dashboard)
   SetIndexBuffer(8, B_EfficiencyRatio, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, B_SuperSmoother,   INDICATOR_CALCULATIONS);

   //--- EMPTY_VALUE per tutti i buffer visivi (Plot 0..4)
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Glyph frecce flip (Wingdings 233=▲ BUY, 234=▼ SELL)
   PlotIndexSetInteger(3, PLOT_ARROW, 233);
   PlotIndexSetInteger(4, PLOT_ARROW, 234);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 10);   // offset px sotto il low
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, -10);  // offset px sopra l'high

   //--- Nascondi bande se richiesto
   if(!InpShowBands)
   {
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
   }

   //--- Nascondi frecce flip se richiesto
   if(!InpShowFlipArrows)
   {
      PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
   }

   //--- Validazione TF: deve essere >= del chart corrente
   //    L'HTF bias è pensato per filtrare un LTF; invertire l'ordine snatura l'uso.
   if((int)InpBiasTF < (int)Period() && InpBiasTF != PERIOD_CURRENT)
   {
      RBTLog(LOG_WARN, "INIT", StringFormat(
         "InpBiasTF (%s) < TF chart (%s). L'indicatore funziona ma il paradigma HTF->LTF è invertito.",
         EnumToString(InpBiasTF), EnumToString((ENUM_TIMEFRAMES)Period())));
   }

   //--- Fallback DrawMode: in v1.0x solo overlay è supportato
   if(InpDrawMode != DRAW_OVERLAY_CHART)
   {
      RBTLog(LOG_WARN, "INIT", "DRAW_SUBWINDOW non implementato in v1.0x — fallback a DRAW_OVERLAY_CHART.");
   }

   //--- Validazione parametri numerici (prevenzione div/0 e buffer vuoti)
   if(InpMAPeriod < 2)
   {
      RBTLog(LOG_ERROR, "INIT", StringFormat("InpMAPeriod deve essere >= 2 (attuale: %d)", InpMAPeriod));
      return INIT_FAILED;
   }
   if(InpATRPeriod < 2)
   {
      RBTLog(LOG_ERROR, "INIT", StringFormat("InpATRPeriod deve essere >= 2 (attuale: %d)", InpATRPeriod));
      return INIT_FAILED;
   }

   //--- v1.12: validazione Sticky Bias
   if(InpStickyBias)
   {
      if(InpATRMultiplierFlip < InpATRMultiplier)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpATRMultiplierFlip (%.2f) deve essere >= InpATRMultiplier (%.2f)",
               InpATRMultiplierFlip, InpATRMultiplier));
         return INIT_FAILED;
      }
      if(InpFlipConfirmBars < 1 || InpFlipConfirmBars > 5)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpFlipConfirmBars deve essere tra 1 e 5 (attuale: %d)", InpFlipConfirmBars));
         return INIT_FAILED;
      }
   }

   //--- v1.13: validazione PMA / PMA+OEF
   if(InpMAType == BIAS_MA_PMA || InpMAType == BIAS_MA_PMA_OEF)
   {
      if(InpPMAPeriod < 5 || InpPMAPeriod > 50)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpPMAPeriod deve essere tra 5 e 50 (attuale: %d)", InpPMAPeriod));
         return INIT_FAILED;
      }
   }
   if(InpMAType == BIAS_MA_PMA_OEF)
   {
      if(InpOEFMinCutoff <= 0.0 || InpOEFMinCutoff > 10.0)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpOEFMinCutoff deve essere in (0, 10] (attuale: %.3f)", InpOEFMinCutoff));
         return INIT_FAILED;
      }
      if(InpOEFBeta < 0.0 || InpOEFBeta > 5.0)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpOEFBeta deve essere in [0, 5] (attuale: %.3f)", InpOEFBeta));
         return INIT_FAILED;
      }
      if(InpOEFDerivCutoff <= 0.0 || InpOEFDerivCutoff > 10.0)
      {
         RBTLog(LOG_ERROR, "INIT",
            StringFormat("InpOEFDerivCutoff deve essere in (0, 10] (attuale: %.3f)", InpOEFDerivCutoff));
         return INIT_FAILED;
      }
   }

   if(InpMAType == BIAS_MA_KAMA)
   {
      // KAMA: SC = 2/(F+1) → F o S <= 0 genera divisione per zero → NaN propagato
      if(InpKAMAFast < 1 || InpKAMASlow < 1)
      {
         RBTLog(LOG_ERROR, "INIT", StringFormat(
            "InpKAMAFast/Slow devono essere >= 1 (Fast=%d, Slow=%d). Rischio NaN.",
            InpKAMAFast, InpKAMASlow));
         return INIT_FAILED;
      }
      if(InpKAMAFast >= InpKAMASlow)
      {
         RBTLog(LOG_WARN, "INIT", StringFormat(
            "KAMAFast (%d) >= KAMASlow (%d) — dinamica adattiva invertita. Default raccomandati: 2 / 30.",
            InpKAMAFast, InpKAMASlow));
      }
   }
   if(InpMAType == BIAS_MA_JMA)
   {
      // JMA: phase fuori [-100, +100] viene clampato internamente a 0.5 o 2.5.
      if(InpJMAPeriod < 2)
      {
         RBTLog(LOG_ERROR, "INIT", StringFormat("InpJMAPeriod deve essere >= 2 (attuale: %d)", InpJMAPeriod));
         return INIT_FAILED;
      }
      if(InpJMAPhase < -100 || InpJMAPhase > 100)
      {
         RBTLog(LOG_WARN, "INIT", StringFormat(
            "InpJMAPhase (%d) fuori [-100, +100] — viene clampato a 0.5 o 2.5.", InpJMAPhase));
      }
   }

   //--- Crea handle MA standard se servono (solo EMA/SMA/SMMA/LWMA)
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
   {
      if(!CreateMAHandles())
      {
         RBTLog(LOG_ERROR, "INIT", "CreateMAHandles() fallita — indicatore non partirà.");
         return INIT_FAILED;
      }
   }

   //--- Short name
   string shortName = BuildShortName();
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

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

   //--- Stampa versione + config effettiva (sempre visibile se log >= INFO)
   //    Utile per confermare ricompilazione e per auditing backtest.
   RBTLog(LOG_INFO, "INIT", StringFormat(
      "v1.13 started — BiasTF=%s Engine=%s MAType=%s MAPeriod=%d (eff=%d) ATRPeriod=%d ATRMult=%.2f ATRSmooth=%s foreground=%s",
      EnumToString(InpBiasTF),
      (InpEngineMode == ENGINE_SUPERTREND_CLASSIC ? "Supertrend" : "MA+ATR"),
      EnumToString(InpMAType),
      InpMAPeriod, MAEffectivePeriod(),
      InpATRPeriod, InpATRMultiplier,
      EnumToString(InpATRSmoothing),
      ((bool)ChartGetInteger(0, CHART_FOREGROUND) ? "TRUE" : "FALSE")));

   if(InpMAType == BIAS_MA_KAMA)
      RBTLog(LOG_INFO, "INIT", StringFormat("KAMA params — Fast=%d Slow=%d (N=%d)",
         InpKAMAFast, InpKAMASlow, InpMAPeriod));
   if(InpMAType == BIAS_MA_JMA)
      RBTLog(LOG_INFO, "INIT", StringFormat("JMA params — Period=%d Phase=%d",
         InpJMAPeriod, InpJMAPhase));

   //--- v1.10 observability pack params
   RBTLog(LOG_INFO, "INIT", StringFormat(
      "Observability (v1.10) — ER(len=%d thr=%.2f±%.2f) | SS(period=%d) — gate NON coinvolto",
      InpERLength, InpERThreshold, InpERHysteresis, InpSuperSmoothPeriod));

   //--- Dashboard modern (card-based)
   if(InpShowDashboard)
      InitRBTDashboard();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RBTLog(LOG_INFO, "DEINIT", StringFormat("stopping — reason=%d", reason));

   if(g_hMA_Standard != INVALID_HANDLE)
   {
      IndicatorRelease(g_hMA_Standard);
      g_hMA_Standard = INVALID_HANDLE;
      RBTLog(LOG_DEBUG, "DEINIT", "iMA handle released.");
   }

   //--- Rimuovi oggetti dashboard (prefix scan)
   CleanupRBTDashboard();
   RBTLog(LOG_DEBUG, "DEINIT", "Dashboard objects removed.");

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
   ArraySetAsSeries(B_FlipLong,        false);
   ArraySetAsSeries(B_FlipShort,       false);
   ArraySetAsSeries(B_EfficiencyRatio, false);  // v1.10 fix: coerenza con gli altri buffer
   ArraySetAsSeries(B_SuperSmoother,   false);  // v1.10 fix: coerenza con gli altri buffer
   ArraySetAsSeries(time,              false);
   ArraySetAsSeries(high,              false);
   ArraySetAsSeries(low,               false);

   //--- Barre HTF disponibili
   // NOTA: gli early-return di warmup restituiscono 0 (non rates_total), così
   // quando i dati HTF arrivano, prev_calculated torna a 0 e ProjectHTFToChart
   // riparte dalla bar 0 riempiendo TUTTO lo storico. Restituire rates_total
   // bloccherebbe il prev_calculated a "tutto fatto" e il loop processerebbe
   // solo l'ultima bar.
   int htfBarsAvailable = Bars(_Symbol, InpBiasTF);
   // JMA ha warmup maggiore (sumLen=10 + avgLen=65). Per gli altri usa MA period.
   int maWarmup = (InpMAType == BIAS_MA_JMA) ? (InpJMAPeriod + 75) : InpMAPeriod;
   int requiredWarmup = MathMax(maWarmup, InpATRPeriod) + InpWarmupExtraBars + 5;
   if(htfBarsAvailable < requiredWarmup)
   {
      FillWarmup(rates_total);
      if(InpShowDashboard) UpdateRBTDashboard();
      return 0;
   }

   //--- Step 1-2: copia dati HTF in cache
   // Usiamo series indexing interno: g_htf_*[0] = barra HTF più recente
   int htfBarsToUse = MathMin(htfBarsAvailable, 5000);  // cap per performance
   if(!RefreshHTFCache(htfBarsToUse))
   {
      FillWarmup(rates_total);
      if(InpShowDashboard) UpdateRBTDashboard();
      return 0;
   }

   //--- Step 3: calcolo MA su HTF (se necessario)
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
   {
      if(!ComputeHTFMA())
      {
         FillWarmup(rates_total);
         if(InpShowDashboard) UpdateRBTDashboard();
         return 0;
      }
   }

   //--- Step 4: calcolo ATR Wilder RMA su HTF
   if(!ComputeHTFATR())
   {
      FillWarmup(rates_total);
      if(InpShowDashboard) UpdateRBTDashboard();
      return 0;
   }

   //--- Step 5: base, bande, ratchet, stato su HTF (Voto 1 = GATE)
   ComputeHTFState();

   //--- Step 5b v1.09: observability pack — calcolo ER e SuperSmoother
   //    Questi popolano i buffer 8/9 e sono esposti in dashboard, ma NON
   //    partecipano al gate (B_State resta il voto singolo v1.08).
   ComputeHTFEfficiencyRatio();
   ComputeHTFSuperSmoother();

   //--- Step 6: proiezione HTF -> LTF chart bars
   ProjectHTFToChart(rates_total, prev_calculated, time, high, low);

   //--- Step 7: dashboard
   if(InpShowDashboard)
      UpdateRBTDashboard();

   //--- Diagnostica one-shot: verifica che i buffer siano effettivamente popolati
   if(!g_diagPrinted && rates_total > 10)
   {
      int validCount = 0;
      int firstValid = -1, lastValid = -1;
      for(int k = 0; k < rates_total; k++)
      {
         if(B_State[k] != 0.0 && B_MainLine[k] != EMPTY_VALUE)
         {
            validCount++;
            if(firstValid < 0) firstValid = k;
            lastValid = k;
         }
      }
      // Conta anche quanti g_htf_ma[] sono validi e prendi alcuni sample
      int htfMaValid = 0;
      for(int m = 0; m < g_htfBarsUsed; m++)
         if(g_htf_ma[m] != EMPTY_VALUE && g_htf_ma[m] != 0.0) htfMaValid++;

      RBTLog(LOG_INFO, "DIAG", StringFormat(
         "htfBarsUsed=%d rates_total=%d validBars=%d firstValid=%d lastValid=%d ML[last]=%s State[last]=%s ColorIdx[last]=%s",
         g_htfBarsUsed, rates_total, validCount, firstValid, lastValid,
         (rates_total > 0 ? DoubleToString(B_MainLine[rates_total-1], _Digits) : "n/a"),
         (rates_total > 0 ? DoubleToString(B_State[rates_total-1], 0)         : "n/a"),
         (rates_total > 0 ? DoubleToString(B_ColorIndex[rates_total-1], 0)    : "n/a")));

      RBTLog(LOG_INFO, "DIAG-HTF", StringFormat(
         "htfMaValid=%d/%d htfMa[0]=%s htfMa[last]=%s htfAtr[0]=%s htfClose[0]=%s htfState[0]=%s",
         htfMaValid, g_htfBarsUsed,
         (g_htfBarsUsed > 0 ? DoubleToString(g_htf_ma[0], _Digits)              : "n/a"),
         (g_htfBarsUsed > 0 ? DoubleToString(g_htf_ma[g_htfBarsUsed-1], _Digits) : "n/a"),
         (g_htfBarsUsed > 0 ? DoubleToString(g_htf_atr[0], _Digits+1)           : "n/a"),
         (g_htfBarsUsed > 0 ? DoubleToString(g_htf_close[0], _Digits)           : "n/a"),
         (g_htfBarsUsed > 0 ? IntegerToString(g_htf_state[0])                   : "n/a")));

      // v1.09: sample ER e SS sulla bar più recente
      RBTLog(LOG_INFO, "DIAG-OBS", StringFormat(
         "ER[0]=%s state=%s | SS[0]=%s SS[1]=%s",
         (g_htfBarsUsed > 0 && g_htf_er[0] != EMPTY_VALUE ? DoubleToString(g_htf_er[0], 3) : "n/a"),
         (g_htfBarsUsed > 0 ? (g_htf_erState[0] == 1 ? "VALID" : "CHOP") : "n/a"),
         (g_htfBarsUsed > 0 ? DoubleToString(g_htf_ss[0], _Digits) : "n/a"),
         (g_htfBarsUsed > 1 ? DoubleToString(g_htf_ss[1], _Digits) : "n/a")));

      // Heuristic di salute: se validBars << rates_total c'è un bug (vedi fix v1.02)
      if(rates_total > 10 && validCount < rates_total / 2)
         RBTLog(LOG_WARN, "DIAG", StringFormat(
            "validBars (%d) << rates_total (%d) — plotting potrebbe essere incompleto.", validCount, rates_total));

      g_diagPrinted = true;
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| HELPERS — CALCOLO                                                |
//+------------------------------------------------------------------+

//--- Crea gli handle iMA necessari in base a InpMAType
//    Solo EMA/SMA/SMMA/LWMA usano handle iMA.
//    HMA, KAMA, JMA sono calcolate inline (formule UTBot verbatim).
bool CreateMAHandles()
{
   ENUM_MA_METHOD m = MODE_EMA;
   bool needStandard = true;

   switch(InpMAType)
   {
      case BIAS_MA_EMA:  m = MODE_EMA;  break;
      case BIAS_MA_SMA:  m = MODE_SMA;  break;
      case BIAS_MA_SMMA: m = MODE_SMMA; break;
      case BIAS_MA_LWMA: m = MODE_LWMA; break;
      case BIAS_MA_HMA:
      case BIAS_MA_KAMA:
      case BIAS_MA_JMA:
      case BIAS_MA_ZLEMA:
      case BIAS_MA_PMA:       // v1.13: calcolato inline
      case BIAS_MA_PMA_OEF:   // v1.13: calcolato inline
         needStandard = false;  // calcolate inline, nessun handle richiesto
         break;
      default: needStandard = false; break;
   }

   if(needStandard)
   {
      g_hMA_Standard = iMA(_Symbol, InpBiasTF, InpMAPeriod, 0, m, PRICE_CLOSE);
      if(g_hMA_Standard == INVALID_HANDLE)
      {
         RBTLog(LOG_ERROR, "MA-HANDLE",
            StringFormat("iMA(%s,%s,%d) handle FAILED, GetLastError=%d",
               _Symbol, EnumToString(InpBiasTF), InpMAPeriod, GetLastError()));
         return false;
      }
      RBTLog(LOG_DEBUG, "MA-HANDLE",
         StringFormat("iMA handle OK — MODE=%s period=%d TF=%s",
            EnumToString(m), InpMAPeriod, EnumToString(InpBiasTF)));
   }
   else
   {
      RBTLog(LOG_DEBUG, "MA-HANDLE",
         StringFormat("No iMA handle needed (MAType=%s uses inline computation).",
            EnumToString(InpMAType)));
   }

   return true;
}

//+------------------------------------------------------------------+
//| RefreshHTFCache — riempie la cache HTF dal broker                |
//+------------------------------------------------------------------+
// Legge fino a `barsToUse` barre HTF via CopyClose/High/Low/Time.
// Tutte in series indexing (0 = bar più recente).
// Inizializza DIFENSIVAMENTE gli array working (g_htf_ma/atr/base/fUp/fLow/state)
// a EMPTY_VALUE/0 per evitare che valori stantii vengano interpretati
// come validi dai calcoli successivi.
//
// Ritorna false se una qualsiasi Copy* fallisce (broker non ha ancora servito
// la storia HTF: normale sui primi tick dopo cambio TF/simbolo).
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
   if(got <= 0)
   {
      RBTLog(LOG_DEBUG, "HTF", StringFormat("CopyClose fallita, err=%d (history non ancora pronta)", GetLastError()));
      return false;
   }
   if(CopyHigh(_Symbol, InpBiasTF, 0, barsToUse, g_htf_high) <= 0)
   {
      RBTLog(LOG_DEBUG, "HTF", StringFormat("CopyHigh fallita, err=%d", GetLastError()));
      return false;
   }
   if(CopyLow (_Symbol, InpBiasTF, 0, barsToUse, g_htf_low)  <= 0)
   {
      RBTLog(LOG_DEBUG, "HTF", StringFormat("CopyLow fallita, err=%d", GetLastError()));
      return false;
   }
   if(CopyTime(_Symbol, InpBiasTF, 0, barsToUse, g_htf_time) <= 0)
   {
      RBTLog(LOG_DEBUG, "HTF", StringFormat("CopyTime fallita, err=%d", GetLastError()));
      return false;
   }

   g_htfBarsUsed = got;
   RBTLog(LOG_DEBUG, "HTF",
      StringFormat("cache refresh: %d HTF bars (richiesti %d) su TF=%s",
         got, barsToUse, EnumToString(InpBiasTF)));

   // Resize output arrays
   ArrayResize(g_htf_ma,      g_htfBarsUsed);
   ArrayResize(g_htf_atr,     g_htfBarsUsed);
   ArrayResize(g_htf_base,    g_htfBarsUsed);
   ArrayResize(g_htf_fUp,     g_htfBarsUsed);
   ArrayResize(g_htf_fLow,    g_htfBarsUsed);
   ArrayResize(g_htf_fUpFlip,  g_htfBarsUsed);  // v1.12
   ArrayResize(g_htf_fLowFlip, g_htfBarsUsed);  // v1.12
   ArrayResize(g_htf_state,   g_htfBarsUsed);
   ArrayResize(g_htf_er,      g_htfBarsUsed);
   ArrayResize(g_htf_erState, g_htfBarsUsed);
   ArrayResize(g_htf_ss,      g_htfBarsUsed);

   // Inizializzazione difensiva: così se un computer MA/ATR/ER/SS lascia buchi
   // (es. CopyBuffer parziale), i buchi sono EMPTY_VALUE e ComputeHTFState
   // li tratta correttamente come warmup invece di usare zeri casuali.
   ArrayInitialize(g_htf_ma,      EMPTY_VALUE);
   ArrayInitialize(g_htf_atr,     EMPTY_VALUE);
   ArrayInitialize(g_htf_base,    EMPTY_VALUE);
   ArrayInitialize(g_htf_fUp,      EMPTY_VALUE);
   ArrayInitialize(g_htf_fLow,     EMPTY_VALUE);
   ArrayInitialize(g_htf_fUpFlip,  EMPTY_VALUE);  // v1.12
   ArrayInitialize(g_htf_fLowFlip, EMPTY_VALUE);  // v1.12
   ArrayInitialize(g_htf_state,   0);
   ArrayInitialize(g_htf_er,      EMPTY_VALUE);
   ArrayInitialize(g_htf_erState, 0);
   ArrayInitialize(g_htf_ss,      EMPTY_VALUE);

   ArraySetAsSeries(g_htf_ma,      true);
   ArraySetAsSeries(g_htf_atr,     true);
   ArraySetAsSeries(g_htf_base,    true);
   ArraySetAsSeries(g_htf_fUp,      true);
   ArraySetAsSeries(g_htf_fLow,     true);
   ArraySetAsSeries(g_htf_fUpFlip,  true);  // v1.12
   ArraySetAsSeries(g_htf_fLowFlip, true);  // v1.12
   ArraySetAsSeries(g_htf_state,   true);
   ArraySetAsSeries(g_htf_er,      true);
   ArraySetAsSeries(g_htf_erState, true);
   ArraySetAsSeries(g_htf_ss,      true);

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

//+------------------------------------------------------------------+
//| Helper — copie natural <-> series per i calcoli MA               |
//+------------------------------------------------------------------+
// Internamente i calcoli KAMA/HMA/JMA sono IDENTICI all'UTBotAdaptive
// (natural indexing: idx 0 = oldest, last = newest). Convertiamo
// g_htf_close (series) in natural, calcoliamo, e riconvertiamo in series.
void SeriesToNatural(const double &src[], double &dst[], int count)
{
   for(int i = 0; i < count; i++)
      dst[i] = src[count - 1 - i];   // ribalta l'ordinamento
}

void NaturalToSeries(const double &src[], double &dst[], int count)
{
   for(int i = 0; i < count; i++)
      dst[i] = src[count - 1 - i];
}

//--- WMAPoint UTBot: weighted MA su src[i-(period-1)..i] con pesi lineari
//    (pesi decrescenti dalla bar più recente i alla più vecchia i-period+1)
double WMAPoint(const double &src[], int i, int period)
{
   double num = 0.0, den = 0.0;
   for(int k = 0; k < period; k++)
   {
      double w = (double)(period - k);
      num += w * src[i - k];
      den += w;
   }
   return (den > 0.0) ? num / den : src[i];
}

//+------------------------------------------------------------------+
//| ComputeHTFMA_Standard — EMA/SMA/SMMA/LWMA via iMA handle MT5     |
//+------------------------------------------------------------------+
// Il motore di calcolo è MT5 (iMA). Noi facciamo solo CopyBuffer della
// serie già pronta. Gestione difensiva del partial-copy: se l'handle
// non ha ancora tutto lo storico, marchiamo la coda come EMPTY_VALUE
// per evitare che ComputeHTFState la tratti come dato valido.
bool ComputeHTFMA_Standard()
{
   if(g_hMA_Standard == INVALID_HANDLE)
   {
      RBTLog(LOG_ERROR, "MA", "Standard called with INVALID_HANDLE");
      return false;
   }

   int copied = CopyBuffer(g_hMA_Standard, 0, 0, g_htfBarsUsed, g_htf_ma);
   if(copied <= 0)
   {
      RBTLog(LOG_DEBUG, "MA",
         StringFormat("Standard CopyBuffer fallito (err=%d) — handle async non ancora pronto",
            GetLastError()));
      return false;
   }

   ArraySetAsSeries(g_htf_ma, true);

   if(copied < g_htfBarsUsed)
   {
      RBTLog(LOG_DEBUG, "MA",
         StringFormat("Standard partial copy: %d/%d (resto marcato EMPTY_VALUE)",
            copied, g_htfBarsUsed));
      for(int i = copied; i < g_htfBarsUsed; i++)
         g_htf_ma[i] = EMPTY_VALUE;
   }

   RBTLog(LOG_DEBUG, "MA",
      StringFormat("Standard OK — copied=%d ma[0]=%s ma[last]=%s",
         copied,
         DoubleToString(g_htf_ma[0], _Digits),
         DoubleToString(g_htf_ma[g_htfBarsUsed-1], _Digits)));
   return true;
}

//+------------------------------------------------------------------+
//| ComputeHTFMA_HMA — Hull MA (formula UTBot verbatim, natural idx) |
//+------------------------------------------------------------------+
// HMA = WMA(2*WMA(close, period/2) - WMA(close, period), √period)
// Gli handle iMA non servono più: calcolo tutto inline su array natural.
bool ComputeHTFMA_HMA()
{
   int period = InpMAPeriod;
   int total  = g_htfBarsUsed;
   int half   = MathMax(period / 2, 2);
   int sqn    = (int)MathRound(MathSqrt((double)period));

   if(total < period + sqn) return false;

   // Array natural
   double closeNat[], tmpNat[], hmaNat[];
   ArrayResize(closeNat, total);
   ArrayResize(tmpNat,   total);
   ArrayResize(hmaNat,   total);
   ArrayInitialize(tmpNat, 0.0);
   ArrayInitialize(hmaNat, EMPTY_VALUE);

   SeriesToNatural(g_htf_close, closeNat, total);

   // Stage 1: tmp[i] = 2*WMA(half) - WMA(period)
   for(int i = period - 1; i < total; i++)
      tmpNat[i] = 2.0 * WMAPoint(closeNat, i, half) - WMAPoint(closeNat, i, period);

   // Stage 2: hma[i] = WMA(tmp, √period)
   int hma_start = period + sqn - 2;
   for(int i = hma_start; i < total; i++)
      hmaNat[i] = WMAPoint(tmpNat, i, sqn);

   // Bar warmup iniziali: seed con close (come UTBot)
   for(int i = 0; i < hma_start && i < total; i++)
      hmaNat[i] = closeNat[i];

   NaturalToSeries(hmaNat, g_htf_ma, total);
   RBTLog(LOG_DEBUG, "MA",
      StringFormat("HMA OK — period=%d half=%d sqn=%d ma[0]=%s ma[last]=%s",
         period, half, sqn,
         DoubleToString(g_htf_ma[0], _Digits),
         DoubleToString(g_htf_ma[total-1], _Digits)));
   return true;
}

//+------------------------------------------------------------------+
//| ComputeHTFMA_KAMA — Kaufman Adaptive MA (UTBot verbatim)         |
//+------------------------------------------------------------------+
// ER = |P[i]-P[i-N]| / Σ|P[j]-P[j-1]|
// SC = (ER*(FastSC-SlowSC)+SlowSC)^2
// KAMA[i] = KAMA[i-1] + SC*(P[i]-KAMA[i-1])
bool ComputeHTFMA_KAMA()
{
   int N     = InpMAPeriod;
   int total = g_htfBarsUsed;
   if(total < N + 2) return false;

   double closeNat[], kamaNat[];
   ArrayResize(closeNat, total);
   ArrayResize(kamaNat,  total);
   SeriesToNatural(g_htf_close, closeNat, total);

   double fc = 2.0 / ((double)InpKAMAFast + 1.0);
   double sc = 2.0 / ((double)InpKAMASlow + 1.0);

   // Seed i=0..N (N+1 bars, identico a UTBot)
   for(int i = 0; i <= N && i < total; i++)
      kamaNat[i] = closeNat[i];

   // Ricorsione da i=N+1 a total-1 (dal più vecchio al più recente)
   for(int i = N + 1; i < total; i++)
   {
      double direction = MathAbs(closeNat[i] - closeNat[i - N]);
      double noise     = 0.0;
      for(int k = 1; k <= N; k++)
         noise += MathAbs(closeNat[i - k + 1] - closeNat[i - k]);

      double er     = (noise > 0.0) ? direction / noise : 0.0;
      double smooth = MathPow(er * (fc - sc) + sc, 2.0);
      kamaNat[i]    = kamaNat[i - 1] + smooth * (closeNat[i] - kamaNat[i - 1]);
   }

   NaturalToSeries(kamaNat, g_htf_ma, total);
   RBTLog(LOG_DEBUG, "MA",
      StringFormat("KAMA OK — N=%d fast=%d slow=%d fc=%.3f sc=%.3f ma[0]=%s ma[last]=%s",
         N, InpKAMAFast, InpKAMASlow, fc, sc,
         DoubleToString(g_htf_ma[0], _Digits),
         DoubleToString(g_htf_ma[total-1], _Digits)));
   return true;
}

//+------------------------------------------------------------------+
//| ComputeHTFMA_JMA — Jurik-style Adaptive MA (UTBot verbatim)      |
//+------------------------------------------------------------------+
// Formula IIR 3-stage con Jurik Bands + volatilità dinamica.
// Fonte: Igor 2008 + mihakralj Python + pandas_ta. Match < 2% vs Jurik DLL.
bool ComputeHTFMA_JMA()
{
   int N     = InpJMAPeriod;
   int total = g_htfBarsUsed;
   int sumLen = 10;
   int avgLen = 65;
   if(total < avgLen + sumLen + 2) return false;

   // Pre-calc delle costanti JMA (identico a UTBotPresetsInit)
   double halfLen = 0.5 * ((double)N - 1.0);
   double phase   = (double)InpJMAPhase;
   double jma_PR   = (phase < -100) ? 0.5 : (phase > 100) ? 2.5 : phase / 100.0 + 1.5;
   double jma_len1 = MathMax(MathLog(MathSqrt(halfLen)) / MathLog(2.0) + 2.0, 0.0);
   double jma_pow1 = MathMax(jma_len1 - 2.0, 0.5);
   double len2     = MathSqrt(halfLen) * jma_len1;
   double jma_bet  = len2 / (len2 + 1.0);
   double jma_beta = 0.45 * ((double)N - 1.0) / (0.45 * ((double)N - 1.0) + 2.0);

   // Array natural + state arrays
   double closeNat[], jmaNat[];
   double e0[], det0[], det1[], uBand[], lBand[], volty[], vSum[];
   ArrayResize(closeNat, total); ArrayResize(jmaNat, total);
   ArrayResize(e0,       total); ArrayResize(det0,  total);
   ArrayResize(det1,     total); ArrayResize(uBand, total);
   ArrayResize(lBand,    total); ArrayResize(volty, total);
   ArrayResize(vSum,     total);
   SeriesToNatural(g_htf_close, closeNat, total);

   // Seed a natural idx 0
   jmaNat[0]   = closeNat[0];
   e0[0]       = closeNat[0];
   det0[0]     = 0.0;
   det1[0]     = 0.0;
   uBand[0]    = closeNat[0];
   lBand[0]    = closeNat[0];
   volty[0]    = 0.0;
   vSum[0]     = 0.0;

   for(int i = 1; i < total; i++)
   {
      double p = closeNat[i];

      //--- Stage 1: Jurik Bands + volatilità istantanea
      double del1  = p - uBand[i - 1];
      double del2  = p - lBand[i - 1];
      double absD1 = MathAbs(del1);
      double absD2 = MathAbs(del2);
      double vol   = (absD1 != absD2) ? MathMax(absD1, absD2) : 0.0;
      volty[i]     = vol;

      // Running sum sliding-window (sumLen=10)
      int    oldIdx  = (i >= sumLen) ? (i - sumLen) : 0;
      double oldVol  = volty[oldIdx];
      vSum[i]        = vSum[i - 1] + (vol - oldVol) / (double)sumLen;

      // Media vSum su avgLen=65 bar
      double avgVol  = 0.0;
      int    avgStart = (i >= avgLen) ? (i - avgLen + 1) : 0;
      int    avgCount = i - avgStart + 1;
      for(int j = avgStart; j <= i; j++)
         avgVol += vSum[j];
      avgVol = (avgCount > 0) ? avgVol / (double)avgCount : 0.0;

      double dVol   = (avgVol > 0.0) ? vol / avgVol : 0.0;
      double maxRV  = MathPow(jma_len1, 1.0 / jma_pow1);
      double rVolty = MathMax(1.0, MathMin(maxRV, dVol));

      double pow2 = MathPow(rVolty, jma_pow1);
      double Kv   = MathPow(jma_bet, MathSqrt(pow2));

      uBand[i] = (del1 > 0) ? p : p - Kv * del1;
      lBand[i] = (del2 < 0) ? p : p - Kv * del2;

      //--- Stage 2: dynamic alpha
      double alpha = MathPow(jma_beta, pow2);
      double a2    = alpha * alpha;
      double b2    = (1.0 - alpha) * (1.0 - alpha);

      //--- Stage 3: IIR 3 stadi
      double eNew = (1.0 - alpha) * p + alpha * e0[i - 1];
      e0[i]       = eNew;

      double d0 = (p - eNew) * (1.0 - jma_beta) + jma_beta * det0[i - 1];
      det0[i]   = d0;
      double ma2 = eNew + jma_PR * d0;

      double d1 = (ma2 - jmaNat[i - 1]) * b2 + a2 * det1[i - 1];
      det1[i]   = d1;

      jmaNat[i] = jmaNat[i - 1] + d1;
   }

   NaturalToSeries(jmaNat, g_htf_ma, total);
   RBTLog(LOG_DEBUG, "MA",
      StringFormat("JMA OK — period=%d phase=%d PR=%.3f beta=%.3f ma[0]=%s ma[last]=%s",
         N, InpJMAPhase, jma_PR, jma_beta,
         DoubleToString(g_htf_ma[0], _Digits),
         DoubleToString(g_htf_ma[total-1], _Digits)));
   return true;
}

//+------------------------------------------------------------------+
//| ComputeHTFMA_ZLEMA — Ehlers Zero Lag EMA (Ehlers & Way 2010)     |
//+------------------------------------------------------------------+
// K = 2/(N+1); lag = (N-1)/2
// ZLEMA[i] = K·(2·close[i] − close[i-lag]) + (1-K)·ZLEMA[i-1]
//
// Idea: invece di smussare close[i], smussa "close con pre-shift di lag"
// (cioè close[i] + (close[i] − close[i-lag])). La sottrazione del close
// più vecchio compensa il ritardo che l'EMA introdurrebbe.
// Fonte: https://www.mesasoftware.com/papers/ZeroLag.pdf
bool ComputeHTFMA_ZLEMA()
{
   int N     = InpMAPeriod;
   int total = g_htfBarsUsed;
   int lag   = (N - 1) / 2;
   if(total < N + lag + 2) return false;

   double closeNat[], zlemaNat[];
   ArrayResize(closeNat,  total);
   ArrayResize(zlemaNat,  total);
   SeriesToNatural(g_htf_close, closeNat, total);

   double K = 2.0 / ((double)N + 1.0);

   // Seed warmup: bars < lag con close stesso (non possiamo usare close[i-lag])
   for(int i = 0; i <= lag && i < total; i++)
      zlemaNat[i] = closeNat[i];

   // Ricorsione da i=lag+1: applica correzione lag-compensata
   for(int i = lag + 1; i < total; i++)
   {
      double adjClose = 2.0 * closeNat[i] - closeNat[i - lag];
      zlemaNat[i] = K * adjClose + (1.0 - K) * zlemaNat[i - 1];
   }

   NaturalToSeries(zlemaNat, g_htf_ma, total);
   RBTLog(LOG_DEBUG, "MA",
      StringFormat("ZLEMA OK — N=%d lag=%d K=%.3f ma[0]=%s ma[last]=%s",
         N, lag, K,
         DoubleToString(g_htf_ma[0], _Digits),
         DoubleToString(g_htf_ma[total-1], _Digits)));
   return true;
}

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
// TR[i] = max(high-low, |high-prevClose|, |low-prevClose|)
// Poi uno smoothing scelto via InpATRSmoothing:
//   - WILDER_RMA: ATR[i] = (ATR[i-1]*(N-1) + TR[i]) / N  [coerente UTBot]
//   - SMA:        media mobile semplice delle TR
//   - EMA:        α = 2/(N+1), reazione ~2× Wilder a parità di N
// Seed (bar più vecchie): SMA delle prime N TR, poi ricorsione.
// I bar warmup (indici più vecchi del seed) vengono marcati EMPTY_VALUE.
bool ComputeHTFATR()
{
   int N = InpATRPeriod;
   if(g_htfBarsUsed < N + 2)
   {
      RBTLog(LOG_DEBUG, "ATR",
         StringFormat("Storia insufficiente: %d bars (serve almeno N+2 = %d)", g_htfBarsUsed, N+2));
      return false;
   }

   double tr[];
   ArraySetAsSeries(tr, true);
   ArrayResize(tr, g_htfBarsUsed);

   for(int i = 0; i < g_htfBarsUsed - 1; i++)
   {
      double h = g_htf_high[i];
      double l = g_htf_low[i];
      double cp = g_htf_close[i + 1];
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
         int seedIdx = g_htfBarsUsed - N - 1;
         if(seedIdx < 0) return false;

         double sum = 0.0;
         for(int k = 0; k < N; k++) sum += tr[seedIdx + k];
         g_htf_atr[seedIdx] = sum / N;

         for(int i = g_htfBarsUsed - 1; i > seedIdx; i--)
            g_htf_atr[i] = EMPTY_VALUE;

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
   RBTLog(LOG_DEBUG, "ATR",
      StringFormat("%s OK — period=%d atr[0]=%s atr[last]=%s",
         EnumToString(InpATRSmoothing), N,
         DoubleToString(g_htf_atr[0], _Digits+1),
         DoubleToString(g_htf_atr[g_htfBarsUsed-1], _Digits+1)));
   return true;
}

//+------------------------------------------------------------------+
//| ComputeHTFState — Supertrend-style ratchet + state HTF           |
//+------------------------------------------------------------------+
// Step A: calcola g_htf_base[] (HL2 per Supertrend, MA per MA+ATR).
// Step B: seed stato sulla bar più vecchia (oldest in series indexing).
// Step C: itera dall'oldest verso il newest con la logica Supertrend:
//   basicUp/Low   = base ± mult·ATR (bande "grezze")
//   finalUp/Low   = ratchet (upper scende o si rompe up, lower sale o si rompe down)
//   state flip    = state=+1 & close<finalLow → -1 (break support)
//                   state=-1 & close>finalUp  → +1 (break resistance)
// Warmup: bar con base o atr EMPTY_VALUE → state=0, bande EMPTY_VALUE.
void ComputeHTFState()
{
   for(int i = 0; i < g_htfBarsUsed; i++)
   {
      if(InpEngineMode == ENGINE_SUPERTREND_CLASSIC)
         g_htf_base[i] = (g_htf_high[i] + g_htf_low[i]) * 0.5;
      else
         g_htf_base[i] = g_htf_ma[i];
   }

   int oldest = g_htfBarsUsed - 1;
   g_htf_state[oldest] = +1;
   if(g_htf_base[oldest] != EMPTY_VALUE && g_htf_atr[oldest] != EMPTY_VALUE)
   {
      g_htf_fUp [oldest] = g_htf_base[oldest] + InpATRMultiplier * g_htf_atr[oldest];
      g_htf_fLow[oldest] = g_htf_base[oldest] - InpATRMultiplier * g_htf_atr[oldest];
      // v1.12: seed bande di flip allargate (parallele alle bande visive)
      g_htf_fUpFlip [oldest] = g_htf_base[oldest] + InpATRMultiplierFlip * g_htf_atr[oldest];
      g_htf_fLowFlip[oldest] = g_htf_base[oldest] - InpATRMultiplierFlip * g_htf_atr[oldest];
   }
   else
   {
      g_htf_fUp [oldest] = EMPTY_VALUE;
      g_htf_fLow[oldest] = EMPTY_VALUE;
      g_htf_fUpFlip [oldest] = EMPTY_VALUE;  // v1.12
      g_htf_fLowFlip[oldest] = EMPTY_VALUE;  // v1.12
      g_htf_state[oldest] = 0;
   }

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
   }

   // Conta transizioni di stato su tutta la cache HTF (solo in DEBUG)
   if((int)InpLogLevel >= (int)LOG_DEBUG)
   {
      int flips = 0, longBars = 0, shortBars = 0, warmupBars = 0;
      for(int i = g_htfBarsUsed - 2; i >= 0; i--)
      {
         if(g_htf_state[i] != g_htf_state[i + 1] && g_htf_state[i] != 0 && g_htf_state[i + 1] != 0)
            flips++;
         if(g_htf_state[i] == +1) longBars++;
         else if(g_htf_state[i] == -1) shortBars++;
         else warmupBars++;
      }
      RBTLog(LOG_DEBUG, "STATE",
         StringFormat("%s — HTF state computed: flips=%d long=%d short=%d warmup=%d",
            (InpEngineMode == ENGINE_SUPERTREND_CLASSIC ? "Supertrend(HL2)" : "MA+ATR"),
            flips, longBars, shortBars, warmupBars));
   }
}

//+------------------------------------------------------------------+
//| ComputeHTFEfficiencyRatio — Kaufman Efficiency Ratio (v1.09)     |
//+------------------------------------------------------------------+
// ER[i] = |close[i] - close[i+N]| / Σ |close[i+k] - close[i+k+1]|  (k=0..N-1)
// Range: 0..1 (1 = trend perfetto, 0 = chop pieno).
//
// Stato VALID/CHOP con ISTERESI simmetrica (evita nervous flip):
//   ENTER VALID: ER > threshold + hysteresis   (es. 0.40)
//   EXIT  VALID: ER < threshold - hysteresis   (es. 0.30)
//
// NOTA indexing: g_htf_close è SERIES (0 = newest). Per N bar in dietro
// rispetto a i, uso g_htf_close[i + N]. Itera dalla bar più vecchia
// (g_htfBarsUsed-1) alla più recente (0) per propagare coerentemente
// lo stato isteresi.
//
// v1.09: questa funzione NON modifica g_htf_state — popola solo
// g_htf_er[] e g_htf_erState[] per osservazione.
void ComputeHTFEfficiencyRatio()
{
   int N = InpERLength;
   int total = g_htfBarsUsed;

   if(total < N + 2)
   {
      RBTLog(LOG_DEBUG, "ER",
         StringFormat("Storia insufficiente: %d bars (serve N+2=%d)", total, N+2));
      return;  // g_htf_er già inizializzato a EMPTY_VALUE, g_htf_erState a 0
   }

   double thrHi = InpERThreshold + InpERHysteresis;
   double thrLo = InpERThreshold - InpERHysteresis;

   // Itero da bar più vecchia (series alto) a più recente (series 0).
   // state eredita dal "bar precedente" = i+1 in series.
   int validCount = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      // Warmup: ho bisogno di N+1 close successive (più vecchie)
      if(i + N >= total)
      {
         g_htf_er[i]      = EMPTY_VALUE;
         g_htf_erState[i] = 0;
         continue;
      }

      double change = MathAbs(g_htf_close[i] - g_htf_close[i + N]);
      double vol    = 0.0;
      for(int k = 0; k < N; k++)
         vol += MathAbs(g_htf_close[i + k] - g_htf_close[i + k + 1]);

      double er = (vol > 0.0) ? change / vol : 0.0;
      g_htf_er[i] = er;

      // Isteresi: eredita stato da bar più vecchia (i+1), aggiorna se cross soglie
      int prevState = (i + 1 < total) ? g_htf_erState[i + 1] : 0;
      int newState  = prevState;
      if(prevState == 0 && er >= thrHi) newState = 1;  // enter VALID
      if(prevState == 1 && er <= thrLo) newState = 0;  // exit VALID
      g_htf_erState[i] = newState;
      if(newState == 1) validCount++;
   }

   RBTLog(LOG_DEBUG, "ER",
      StringFormat("OK — N=%d thr=%.2f±%.2f er[0]=%s state[0]=%s validBars=%d/%d",
         N, InpERThreshold, InpERHysteresis,
         DoubleToString(g_htf_er[0], 3),
         (g_htf_erState[0] == 1 ? "VALID" : "CHOP"),
         validCount, total));
}

//+------------------------------------------------------------------+
//| ComputeHTFSuperSmoother — Ehlers 2-pole Butterworth (v1.09)      |
//+------------------------------------------------------------------+
// Fonte: John Ehlers — "Cybernetic Analysis for Stocks and Futures" (2004)
// http://www.davenewberg.com/Trading/TS_Code/Ehlers_Indicators/2_pole_SuperSmoother.html
//
// Coefficienti:
//   a1 = exp(-sqrt(2)·π / N)
//   b1 = 2·a1·cos(sqrt(2)·π / N)
//   c2 = b1
//   c3 = -a1²
//   c1 = 1 - c2 - c3
//
// Ricorsione (natural indexing: i-1 = bar precedente):
//   SS[i] = c1·(close[i]+close[i-1])/2 + c2·SS[i-1] + c3·SS[i-2]
//
// Selettività: 12 dB/ottava (vs 6 dB/ottava di EMA). A parità di lag,
// smoothness superiore. Default Ehlers: N=15 (wave cycle noise cutoff).
//
// Implementazione: calcolo in natural-indexed temp array (come KAMA/JMA),
// poi conversione a series per g_htf_ss.
void ComputeHTFSuperSmoother()
{
   int N     = InpSuperSmoothPeriod;
   int total = g_htfBarsUsed;

   if(N < 2 || total < 3)
   {
      RBTLog(LOG_DEBUG, "SS",
         StringFormat("Skip: N=%d total=%d (serve N>=2 e total>=3)", N, total));
      return;  // g_htf_ss già EMPTY_VALUE
   }

   // Coefficienti Butterworth 2-pole
   double sqrt2pi_N = MathSqrt(2.0) * M_PI / (double)N;
   double a1 = MathExp(-sqrt2pi_N);
   double b1 = 2.0 * a1 * MathCos(sqrt2pi_N);
   double c2 = b1;
   double c3 = -a1 * a1;
   double c1 = 1.0 - c2 - c3;

   // Calcolo in natural (i=0 oldest, i=total-1 newest)
   double closeNat[], ssNat[];
   ArrayResize(closeNat, total);
   ArrayResize(ssNat,    total);
   SeriesToNatural(g_htf_close, closeNat, total);

   // Seed: prime 2 bar = close (warmup, non c'è abbastanza storia per la ricorsione)
   ssNat[0] = closeNat[0];
   ssNat[1] = closeNat[1];

   for(int i = 2; i < total; i++)
   {
      double avg = 0.5 * (closeNat[i] + closeNat[i - 1]);
      ssNat[i] = c1 * avg + c2 * ssNat[i - 1] + c3 * ssNat[i - 2];
   }

   NaturalToSeries(ssNat, g_htf_ss, total);

   RBTLog(LOG_DEBUG, "SS",
      StringFormat("OK — N=%d a1=%.4f c1=%.4f c2=%.4f c3=%.4f ss[0]=%s ss[last]=%s",
         N, a1, c1, c2, c3,
         DoubleToString(g_htf_ss[0], _Digits),
         DoubleToString(g_htf_ss[total-1], _Digits)));
}

//+------------------------------------------------------------------+
//| ProjectHTFToChart — mapping HTF→LTF con anti-repainting          |
//+------------------------------------------------------------------+
// Per ogni bar del chart (LTF) cerca la bar HTF che la contiene via
// iBarShift(), poi usa stateShift = htfShift + 1 (HTF **chiusa**
// precedente, mai quella in formazione). Questo garantisce che nessun
// tick intrabar HTF possa far cambiare stato retroattivamente.
//
// Warmup:
//   - iBarShift < 0 (time fuori range): warmup
//   - stateShift >= g_htfBarsUsed (bar troppo vecchia): warmup
//   - state HTF == 0 (bar non ancora validata): warmup
// In warmup: B_MainLine/Upper/Lower = EMPTY_VALUE, B_State = 0, color = dim.
//
// Flip detection: isFlip = stato LTF cambiato rispetto alla bar LTF precedente,
// ignorando transizioni da/a warmup. Questo alimenta le frecce Plot 3/4
// e il contatore dashboard.
void ProjectHTFToChart(const int rates_total,
                       const int prev_calculated,
                       const datetime &time[],
                       const double   &high[],
                       const double   &low[])
{
   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   for(int i = start; i < rates_total; i++)
   {
      int htfShift = iBarShift(_Symbol, InpBiasTF, time[i], false);
      // Anti-repainting: usa sempre la barra HTF chiusa PRECEDENTE a quella che contiene time[i]
      int stateShift = htfShift + 1;

      if(htfShift < 0 || stateShift < 0 || stateShift >= g_htfBarsUsed)
      {
         B_MainLine  [i] = EMPTY_VALUE;
         B_Upper     [i] = EMPTY_VALUE;
         B_Lower     [i] = EMPTY_VALUE;
         B_State     [i] = 0.0;
         B_Flip      [i] = 0.0;
         B_ColorIndex[i] = 2.0;
         B_FlipLong  [i] = EMPTY_VALUE;
         B_FlipShort [i] = EMPTY_VALUE;
         B_EfficiencyRatio[i] = EMPTY_VALUE;
         B_SuperSmoother  [i] = EMPTY_VALUE;
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
         B_FlipLong  [i] = EMPTY_VALUE;
         B_FlipShort [i] = EMPTY_VALUE;
         B_EfficiencyRatio[i] = EMPTY_VALUE;
         B_SuperSmoother  [i] = EMPTY_VALUE;
         continue;
      }

      B_MainLine[i] = base;
      B_Upper   [i] = (InpShowBands ? fUp  : EMPTY_VALUE);
      B_Lower   [i] = (InpShowBands ? fLow : EMPTY_VALUE);
      B_State   [i] = (double)st;
      B_ColorIndex[i] = (st == +1) ? 0.0 : (st == -1 ? 1.0 : 2.0);

      // Flip detection + posizione frecce sul low/high della candela LTF di flip
      bool isFlip = (i > 0 && B_State[i-1] != 0.0 && B_State[i] != B_State[i-1]);
      B_Flip[i] = isFlip ? 1.0 : 0.0;

      if(isFlip && st == +1)
      {
         B_FlipLong [i] = low [i];     // freccia ▲ ancorata al low
         B_FlipShort[i] = EMPTY_VALUE;
      }
      else if(isFlip && st == -1)
      {
         B_FlipLong [i] = EMPTY_VALUE;
         B_FlipShort[i] = high[i];     // freccia ▼ ancorata all'high
      }
      else
      {
         B_FlipLong [i] = EMPTY_VALUE;
         B_FlipShort[i] = EMPTY_VALUE;
      }

      // v1.09 observability: proietta ER e SuperSmoother dalla stessa bar HTF
      // (anti-repainting: stateShift = bar HTF chiusa precedente, identico a state)
      B_EfficiencyRatio[i] = g_htf_er[stateShift];   // può essere EMPTY_VALUE in warmup
      B_SuperSmoother  [i] = g_htf_ss[stateShift];   // idem
   }
}

//--- Riempie tutti i buffer con warmup (0/EMPTY/dim)
void FillWarmup(const int rates_total)
{
   for(int i = 0; i < rates_total; i++)
   {
      B_MainLine       [i] = EMPTY_VALUE;
      B_Upper          [i] = EMPTY_VALUE;
      B_Lower          [i] = EMPTY_VALUE;
      B_State          [i] = 0.0;
      B_Flip           [i] = 0.0;
      B_ColorIndex     [i] = 2.0;
      B_FlipLong       [i] = EMPTY_VALUE;
      B_FlipShort      [i] = EMPTY_VALUE;
      B_EfficiencyRatio[i] = EMPTY_VALUE;
      B_SuperSmoother  [i] = EMPTY_VALUE;
   }
}

//--- Periodo effettivamente usato dal tipo MA (JMA usa un input diverso)
int MAEffectivePeriod()
{
   if(InpMAType == BIAS_MA_JMA) return InpJMAPeriod;
   if(InpMAType == BIAS_MA_PMA || InpMAType == BIAS_MA_PMA_OEF)
      return 2 * InpPMAPeriod;   // v1.13: warmup richiede WMA della WMA
   return InpMAPeriod;
}

//--- Short name
string BuildShortName()
{
   string engineStr = (InpEngineMode == ENGINE_SUPERTREND_CLASSIC) ? "ST" : "MA+ATR";
   string maStr = "";
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
      maStr = " " + MATypeLabel() + "(" + IntegerToString(MAEffectivePeriod()) + ")";

   return StringFormat("RattBiasTrend [%s]%s ATR(%d×%.1f) @ %s",
                       engineStr, maStr, InpATRPeriod, InpATRMultiplier,
                       EnumToString(InpBiasTF));
}

//--- Restituisce etichetta testuale per InpMAType
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
   }
   return "?";
}

//--- Etichetta breve del TF bias (M15, H1, H4, D1, ...)
string TFLabel(ENUM_TIMEFRAMES tf)
{
   string s = EnumToString(tf);
   int p = StringFind(s, "PERIOD_");
   if(p == 0) s = StringSubstr(s, 7);
   return s;
}

//+------------------------------------------------------------------+
//| HELPERS — THEME CHART (pattern identico UTBotAdaptive)           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| SaveOriginalChartColors — salva originali UNA SOLA VOLTA (v1.11) |
//+------------------------------------------------------------------+
// Idempotente: se g_origSaved già true, no-op.
// Questa funzione NON applica nulla, solo salva lo stato originale.
void SaveOriginalChartColors()
{
   if(g_origSaved) return;

   g_origBG          = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   g_origFG          = (color)ChartGetInteger(0, CHART_COLOR_FOREGROUND);
   g_origGrid        = (color)ChartGetInteger(0, CHART_COLOR_GRID);
   g_origChartUp     = (color)ChartGetInteger(0, CHART_COLOR_CHART_UP);
   g_origChartDown   = (color)ChartGetInteger(0, CHART_COLOR_CHART_DOWN);
   g_origChartLine   = (color)ChartGetInteger(0, CHART_COLOR_CHART_LINE);
   g_origCandleBull  = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   g_origCandleBear  = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
   g_origBid         = (color)ChartGetInteger(0, CHART_COLOR_BID);
   g_origAsk         = (color)ChartGetInteger(0, CHART_COLOR_ASK);
   g_origVolume      = (color)ChartGetInteger(0, CHART_COLOR_VOLUME);
   g_origShowGrid    = (bool) ChartGetInteger(0, CHART_SHOW_GRID);
   g_origShowVolumes = (int)  ChartGetInteger(0, CHART_SHOW_VOLUMES);
   g_origForeground  = (bool) ChartGetInteger(0, CHART_FOREGROUND);

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
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,  InpThemeBG);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,  InpThemeFG);
   ChartSetInteger(0, CHART_COLOR_GRID,        InpThemeGrid);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,    InpThemeBullCandl);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,  InpThemeBearCandl);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE,  InpThemeFG);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, InpThemeBullCandl);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, InpThemeBearCandl);
   ChartSetInteger(0, CHART_COLOR_BID,         C'80,80,80');
   ChartSetInteger(0, CHART_COLOR_ASK,         C'80,80,80');
   ChartSetInteger(0, CHART_COLOR_VOLUME,      C'80,80,80');
   ChartSetInteger(0, CHART_SHOW_GRID,         InpShowGrid);
   ChartSetInteger(0, CHART_SHOW_VOLUMES,      0);
   ChartSetInteger(0, CHART_FOREGROUND,        false);
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

   ChartSetInteger(0, CHART_COLOR_BACKGROUND,  g_origBG);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,  g_origFG);
   ChartSetInteger(0, CHART_COLOR_GRID,        g_origGrid);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,    g_origChartUp);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,  g_origChartDown);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE,  g_origChartLine);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, g_origCandleBull);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, g_origCandleBear);
   ChartSetInteger(0, CHART_COLOR_BID,         g_origBid);
   ChartSetInteger(0, CHART_COLOR_ASK,         g_origAsk);
   ChartSetInteger(0, CHART_COLOR_VOLUME,      g_origVolume);
   ChartSetInteger(0, CHART_SHOW_GRID,         g_origShowGrid);
   ChartSetInteger(0, CHART_SHOW_VOLUMES,      g_origShowVolumes);
   ChartSetInteger(0, CHART_FOREGROUND,        g_origForeground);

   ChartRedraw(0);
   g_themeApplied = false;
   RBTLog(LOG_DEBUG, "THEME", "Original chart colors restored.");
}

//+------------------------------------------------------------------+
//| HELPERS — DASHBOARD (stile UTBot: rect card + label)             |
//+------------------------------------------------------------------+

//--- Crea un OBJ_RECTANGLE_LABEL con bordo flat
void RBTCreateRect(string id, int x, int y, int w, int h,
                   color bgClr, color brdClr = clrNONE, int zorder = 16000)
{
   string name = RBT_DASH_PREFIX + id;
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR,
                    (brdClr == clrNONE) ? bgClr : brdClr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, zorder);
}

//--- Crea un OBJ_LABEL con font/size custom
void RBTCreateLabel(string id, int x, int y, color clr,
                    string font = "Segoe UI", int size = 8, int zorder = 16100)
{
   string name = RBT_DASH_PREFIX + id;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, zorder);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//--- Setta testo + colore di una label esistente
void RBTSetLabel(string id, string text, color clr)
{
   string name = RBT_DASH_PREFIX + id;
   ObjectSetString (0, name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//--- Setta solo testo (mantiene colore)
void RBTSetLabelText(string id, string text)
{
   ObjectSetString(0, RBT_DASH_PREFIX + id, OBJPROP_TEXT, text);
}

//--- Setta solo background di un rect esistente
void RBTSetRectBG(string id, color bgClr)
{
   ObjectSetInteger(0, RBT_DASH_PREFIX + id, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, RBT_DASH_PREFIX + id, OBJPROP_BORDER_COLOR, bgClr);
}

//+------------------------------------------------------------------+
//| InitRBTDashboard — crea gli oggetti (layout 2 card)              |
//+------------------------------------------------------------------+
// Layout (px) con DASH_X=12, DASH_Y=22:
//   y=22..56    header bar (teal bg, white text)
//   y=66..82    sezione 1 label "▸ STATO BIAS"
//   y=86..190   card 1 (badge + TF + bias val + flip count + last flip)
//   y=200..216  sezione 2 label "▸ CONFIGURAZIONE"
//   y=220..296  card 2 (engine / source / ATR)
//+------------------------------------------------------------------+
void InitRBTDashboard()
{
   RBT_DASH_PREFIX = "RBT_DASH_";

   const int card1H   = 104;                          // espansa per 2 righe flip
   const int card2H   = 76;
   const int card3H   = 92;                           // v1.09: CARD VOTI PREVIEW (4 righe)
   const int bgHeight = 34 + 12 + 18 + card1H + 14 + 18 + card2H + 14 + 18 + card3H + 12;  // 406

   //--- Outer border (teal accent)
   RBTCreateRect("BORDER", DASH_X - 2, DASH_Y - 2, DASH_W + 4, bgHeight + 4,
                 CLR_BORDER, CLR_BORDER, 16000);

   //--- Background (dark navy)
   RBTCreateRect("BG", DASH_X, DASH_Y, DASH_W, bgHeight,
                 CLR_BG, CLR_BG, 16001);

   //--- Header bar (teal)
   RBTCreateRect("HDRBG", DASH_X, DASH_Y, DASH_W, DASH_HEADER_H,
                 CLR_HDR_BG, CLR_HDR_BG, 16002);

   //--- Header title
   RBTCreateLabel("HDR", DASH_X + 12, DASH_Y + 9, CLR_HDR_TXT,
                  "Segoe UI", 11, 16200);
   RBTSetLabelText("HDR", "RATT BIAS TREND");

   //--- SEZIONE 1: STATO BIAS
   int y_s1 = DASH_Y + DASH_HEADER_H + 12;    // 68
   int y_c1 = y_s1 + 18;                       // 86
   RBTCreateLabel("S1", DASH_X + 10, y_s1, CLR_SECTION, "Segoe UI", 8, 16100);
   RBTSetLabelText("S1", "▸ STATO BIAS");

   RBTCreateRect ("CARD1", DASH_X + 8, y_c1, DASH_CARD_W, card1H,
                  CLR_CARD_BG, CLR_CARD_BORDER, 16050);

   // Badge stato (LONG teal / SHORT coral / WARMUP dim)
   RBTCreateRect ("BADGE", DASH_X + 18, y_c1 + 10, 96, 24,
                  CLR_STATE_NEUT, CLR_STATE_NEUT, 16080);
   RBTCreateLabel("BADGETXT", DASH_X + 28, y_c1 + 14, CLR_HDR_TXT,
                  "Segoe UI", 10, 16200);

   // TF label (accanto al badge)
   RBTCreateLabel("TFLBL", DASH_X + 128, y_c1 + 12, CLR_TXT_DIM,   "Segoe UI", 8, 16200);
   RBTSetLabelText("TFLBL", "Timeframe HTF");
   RBTCreateLabel("TFVAL", DASH_X + 128, y_c1 + 26, CLR_TXT_PRIMARY, "Consolas", 10, 16200);

   // Main line value (sotto il badge)
   RBTCreateLabel("MLLBL",  DASH_X + 18,  y_c1 + 48, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("MLLBL", "Bias Line");
   RBTCreateLabel("MLVAL",  DASH_X + 80,  y_c1 + 48, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   // Flip count (sotto MA value)
   RBTCreateLabel("FLIPCNTLBL", DASH_X + 18,  y_c1 + 66, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("FLIPCNTLBL", "Flip count");
   RBTCreateLabel("FLIPCNTVAL", DASH_X + 80,  y_c1 + 66, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   // Last flip age (ultima riga)
   RBTCreateLabel("LASTFLIPLBL", DASH_X + 18, y_c1 + 84, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("LASTFLIPLBL", "Last flip");
   RBTCreateLabel("LASTFLIPVAL", DASH_X + 80, y_c1 + 84, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   //--- SEZIONE 2: CONFIGURAZIONE
   int y_s2 = y_c1 + card1H + 14;              // 204
   int y_c2 = y_s2 + 18;                       // 222
   RBTCreateLabel("S2", DASH_X + 10, y_s2, CLR_SECTION, "Segoe UI", 8, 16100);
   RBTSetLabelText("S2", "▸ CONFIGURAZIONE");

   RBTCreateRect ("CARD2", DASH_X + 8, y_c2, DASH_CARD_W, card2H,
                  CLR_CARD_BG, CLR_CARD_BORDER, 16050);

   RBTCreateLabel("CFG_ENG_LBL", DASH_X + 18,  y_c2 + 10, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("CFG_ENG_LBL", "Engine");
   RBTCreateLabel("CFG_ENG_VAL", DASH_X + 90,  y_c2 + 10, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   RBTCreateLabel("CFG_MA_LBL",  DASH_X + 18,  y_c2 + 30, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("CFG_MA_LBL", "Source");
   RBTCreateLabel("CFG_MA_VAL",  DASH_X + 90,  y_c2 + 30, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   RBTCreateLabel("CFG_ATR_LBL", DASH_X + 18,  y_c2 + 50, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("CFG_ATR_LBL", "ATR");
   RBTCreateLabel("CFG_ATR_VAL", DASH_X + 90,  y_c2 + 50, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   //--- v1.09 SEZIONE 3: VOTI PREVIEW (observability pack)
   int y_s3 = y_c2 + card2H + 14;              // 314
   int y_c3 = y_s3 + 18;                       // 332
   RBTCreateLabel("S3", DASH_X + 10, y_s3, CLR_SECTION, "Segoe UI", 8, 16100);
   RBTSetLabelText("S3", "▸ VOTI PREVIEW (non partecipano al gate)");

   RBTCreateRect ("CARD3", DASH_X + 8, y_c3, DASH_CARD_W, card3H,
                  CLR_CARD_BG, CLR_CARD_BORDER, 16050);

   // V1: Direzionale (B_State)
   RBTCreateLabel("V1_LBL", DASH_X + 18,  y_c3 + 10, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("V1_LBL", "V1 Direzionale");
   RBTCreateLabel("V1_VAL", DASH_X + 120, y_c3 + 10, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   // V2: Kaufman ER (con stato isteresi)
   RBTCreateLabel("V2_LBL", DASH_X + 18,  y_c3 + 30, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("V2_LBL", "V2 Efficiency");
   RBTCreateLabel("V2_VAL", DASH_X + 120, y_c3 + 30, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   // V3: SuperSmoother slope
   RBTCreateLabel("V3_LBL", DASH_X + 18,  y_c3 + 50, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("V3_LBL", "V3 SS-slope");
   RBTCreateLabel("V3_VAL", DASH_X + 120, y_c3 + 50, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   // Agreement preview (cosa voterebbe il committee se attivo)
   RBTCreateLabel("VAG_LBL", DASH_X + 18,  y_c3 + 72, CLR_TXT_DIM,     "Segoe UI", 8, 16200);
   RBTSetLabelText("VAG_LBL", "Agreement");
   RBTCreateLabel("VAG_VAL", DASH_X + 120, y_c3 + 72, CLR_TXT_PRIMARY, "Consolas", 9, 16200);

   UpdateRBTDashboard();
}

//--- Aggiorna i valori dinamici della dashboard
void UpdateRBTDashboard()
{
   if(ObjectFind(0, RBT_DASH_PREFIX + "BG") < 0) return; // non inizializzata

   //--- Stato corrente dalla chart bar più recente
   double st = 0.0;
   double ml = 0.0;
   int sz = ArraySize(B_State);
   if(sz > 0) st = B_State[sz - 1];
   if(ArraySize(B_MainLine) > 0) ml = B_MainLine[sz - 1];

   string stateStr = "WARMUP";
   color  stateClr = CLR_STATE_NEUT;
   if(st > 0.5)      { stateStr = "LONG ▲";  stateClr = CLR_STATE_LONG;  }
   else if(st < -0.5){ stateStr = "SHORT ▼"; stateClr = CLR_STATE_SHORT; }

   //--- Badge stato
   RBTSetRectBG("BADGE", stateClr);
   RBTSetLabel("BADGETXT", stateStr, CLR_HDR_TXT);

   //--- TF value (es. "H4")
   RBTSetLabel("TFVAL", TFLabel(InpBiasTF), CLR_TXT_PRIMARY);

   //--- Main line value (prezzo base corrente)
   if(ml != 0.0 && ml != EMPTY_VALUE)
      RBTSetLabel("MLVAL", DoubleToString(ml, _Digits), CLR_TXT_PRIMARY);
   else
      RBTSetLabel("MLVAL", "—", CLR_TXT_DIM);

   //--- Flip count + last flip age (scan del buffer B_Flip)
   int  flipCount   = 0;
   int  barsSinceLastFlip = -1;
   for(int k = 0; k < sz; k++)
   {
      if(B_Flip[k] > 0.5)
      {
         flipCount++;
         barsSinceLastFlip = sz - 1 - k;   // barre dall'ultimo flip al presente
      }
   }
   RBTSetLabel("FLIPCNTVAL", IntegerToString(flipCount), CLR_TXT_PRIMARY);

   if(barsSinceLastFlip < 0)
      RBTSetLabel("LASTFLIPVAL", "—", CLR_TXT_DIM);
   else if(barsSinceLastFlip == 0)
      RBTSetLabel("LASTFLIPVAL", "current bar", CLR_TXT_PRIMARY);
   else
      RBTSetLabel("LASTFLIPVAL", IntegerToString(barsSinceLastFlip) + " bars ago", CLR_TXT_PRIMARY);

   //--- Config: Engine + MA + ATR
   string engineStr = (InpEngineMode == ENGINE_SUPERTREND_CLASSIC)
                      ? "Supertrend (HL2)"
                      : "MA + ATR Band";
   RBTSetLabel("CFG_ENG_VAL", engineStr, CLR_TXT_PRIMARY);

   string maStr;
   if(InpEngineMode == ENGINE_MA_ATR_BAND)
      maStr = StringFormat("%s(%d)", MATypeLabel(), MAEffectivePeriod());
   else
      maStr = "HL2 (no MA)";
   RBTSetLabel("CFG_MA_VAL", maStr, CLR_TXT_PRIMARY);

   string atrStr = StringFormat("%d × %.2f", InpATRPeriod, InpATRMultiplier);
   RBTSetLabel("CFG_ATR_VAL", atrStr, CLR_TXT_PRIMARY);

   //--- v1.09 CARD3: VOTI PREVIEW (informativo, non influenza gate)
   int idxLast = sz - 1;

   // V1: replica lo stato GATE corrente (è lo stesso di B_State[last])
   string v1Txt  = "— WARMUP";
   color  v1Clr  = CLR_TXT_DIM;
   if(st > 0.5)      { v1Txt = "✓ LONG";   v1Clr = CLR_STATE_LONG;  }
   else if(st < -0.5){ v1Txt = "✓ SHORT";  v1Clr = CLR_STATE_SHORT; }
   RBTSetLabel("V1_VAL", v1Txt, v1Clr);

   // V2: Kaufman ER con stato isteresi
   double erVal = (idxLast >= 0 && idxLast < ArraySize(B_EfficiencyRatio))
                  ? B_EfficiencyRatio[idxLast] : EMPTY_VALUE;
   string v2Txt;
   color  v2Clr;
   if(erVal == EMPTY_VALUE)
   {
      v2Txt = "— WARMUP";
      v2Clr = CLR_TXT_DIM;
   }
   else
   {
      // v1.10 fix: 3 zone coerenti (colore + simbolo + testo allineati)
      // - ER >= thrHi  → VALID verde
      // - ER <= thrLo  → CHOP  rosso
      // - zona intermedia (thrLo..thrHi) → (zone) grigio neutrale
      // NB: questo è un display semplificato. Lo stato isteresi stateful
      //     vero è in g_htf_erState[] e viene usato per l'Agreement sotto.
      double thrHi = InpERThreshold + InpERHysteresis;
      double thrLo = InpERThreshold - InpERHysteresis;
      string marker, zoneLbl;
      if(erVal >= thrHi)      { marker = "✓"; zoneLbl = " VALID";  v2Clr = CLR_STATE_LONG;  }
      else if(erVal <= thrLo) { marker = "✗"; zoneLbl = " CHOP";   v2Clr = CLR_STATE_SHORT; }
      else                    { marker = "~"; zoneLbl = " (zone)"; v2Clr = CLR_TXT_SECOND;  }
      v2Txt = StringFormat("%s %.2f%s", marker, erVal, zoneLbl);
   }
   RBTSetLabel("V2_VAL", v2Txt, v2Clr);

   // V3: slope SuperSmoother — confronto ultimi 2 valori (newest vs previous)
   string v3Txt = "— WARMUP";
   color  v3Clr = CLR_TXT_DIM;
   int    v3Vote = 0;
   int    ssLen = ArraySize(B_SuperSmoother);
   if(idxLast >= 1 && idxLast < ssLen)
   {
      double ssNow  = B_SuperSmoother[idxLast];
      double ssPrev = B_SuperSmoother[idxLast - 1];
      if(ssNow != EMPTY_VALUE && ssPrev != EMPTY_VALUE)
      {
         if(ssNow > ssPrev)      { v3Txt = "✓ UP";   v3Clr = CLR_STATE_LONG;  v3Vote = +1; }
         else if(ssNow < ssPrev) { v3Txt = "✗ DOWN"; v3Clr = CLR_STATE_SHORT; v3Vote = -1; }
         else                    { v3Txt = "= FLAT"; v3Clr = CLR_TXT_SECOND;  v3Vote =  0; }
      }
   }
   RBTSetLabel("V3_VAL", v3Txt, v3Clr);

   // Agreement preview: cosa voterebbe un committee AND-stretto se attivo.
   // Regola: LONG ⇔ V1=+1 AND V2=VALID AND V3=+1; analogo SHORT; altrimenti NEUTRAL.
   //
   // v1.10 fix: legge lo stato isteresi STATEFUL da g_htf_erState[0] (bar HTF
   // più recente), NON una soglia istantanea su erVal. Questo riproduce
   // esattamente cosa farebbe il committee in v1.10+ (rispetta il memoria
   // dell'isteresi entry/exit, non solo il valore corrente).
   bool v2Valid = (g_htfBarsUsed > 0 && g_htf_erState[0] == 1);
   int  v1Vote  = (st > 0.5) ? +1 : (st < -0.5 ? -1 : 0);
   string agTxt;
   color  agClr;
   if(v1Vote == +1 && v2Valid && v3Vote == +1)      { agTxt = "LONG (3/3)";    agClr = CLR_STATE_LONG;  }
   else if(v1Vote == -1 && v2Valid && v3Vote == -1) { agTxt = "SHORT (3/3)";   agClr = CLR_STATE_SHORT; }
   else                                              { agTxt = "NEUTRAL";      agClr = CLR_TXT_DIM;     }
   RBTSetLabel("VAG_VAL", agTxt, agClr);
}

//--- Rimuovi tutti gli oggetti dashboard (prefix scan)
void CleanupRBTDashboard()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, RBT_DASH_PREFIX) == 0)
         ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
