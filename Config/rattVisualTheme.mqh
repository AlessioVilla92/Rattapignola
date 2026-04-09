//+------------------------------------------------------------------+
//|                                        rattVisualTheme.mqh       |
//|          Rattapignola EA — Palette "Notti Estive in Campagna"     |
//|                                                                  |
//|  Colori hardcodati — editabili SOLO via codice sorgente          |
//|  NON visibili nelle impostazioni EA                              |
//|                                                                  |
//|  Palette: Fireflies — Summer Countryside Nights                  |
//|  Lucciole, cielo notturno estivo, verde campagna                 |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| SFONDI — Cielo notturno                                          |
//+------------------------------------------------------------------+
#define RATT_BG_DEEP         C'6,10,18'        // cielo notturno profondo, chart bg
#define RATT_BG_PANEL        C'10,16,28'       // panel background
#define RATT_BG_SECTION_A    C'14,22,36'       // sezioni alternate A
#define RATT_BG_SECTION_B    C'18,28,42'       // sezioni alternate B

//+------------------------------------------------------------------+
//| BORDI — Verde campagna                                           |
//+------------------------------------------------------------------+
#define RATT_BORDER          C'28,90,45'       // bordo pannello
#define RATT_BORDER_FRAME    C'255,220,50'     // firefly perimetrale dashboard (stile SugaraPivot gold)

// Alias dashboard
#define RATT_PANEL_BG        RATT_BG_PANEL
#define RATT_PANEL_BORDER    RATT_BORDER
#define RATT_SIDE_BORDER     C'180,155,30'     // Firefly dim per side panels

//+------------------------------------------------------------------+
//| ACCENT — Lucciole                                                |
//+------------------------------------------------------------------+
#define RATT_FIREFLY         C'255,220,50'     // giallo lucciola luminoso
#define RATT_FIREFLY_DIM     C'180,155,30'     // giallo lucciola smorzato
#define RATT_FIREFLY_GLOW    C'255,240,120'    // alone lucciola

//+------------------------------------------------------------------+
//| SEGNALI — Verde prato / Rosso tramonto                           |
//+------------------------------------------------------------------+
#define RATT_BUY             C'80,220,100'     // verde prato
#define RATT_BUY_DIM         C'40,120,55'      // BUY smorzato
#define RATT_SELL            C'255,85,75'      // rosso tramonto
#define RATT_SELL_DIM        C'140,40,35'      // SELL smorzato
#define RATT_AMBER           C'255,180,40'     // ambra estiva
#define RATT_AMBER_DIM       C'140,90,15'      // ambra smorzato
// Hedge Smart colors
#define RATT_HEDGE           C'255,140,0'      // Arancione — usato nel dashboard label "Hedge"
#define RATT_HEDGE_DIM       C'180,100,0'      // Arancione smorzato
#define RATT_HS_TRIGGER_CLR  C'255,140,0'      // Linea trigger HS
#define RATT_HS_BE_CLR       C'80,220,100'     // Verde — rombo Step1 BE
#define RATT_HS_TP_CLR       C'255,220,50'     // Giallo lucciola — rombo Step2 TP

//+------------------------------------------------------------------+
//| TESTO — Luce lunare                                              |
//+------------------------------------------------------------------+
#define RATT_TEXT_HI         C'230,230,200'    // testo principale, luce lunare
#define RATT_TEXT_MID        C'130,145,110'    // testo secondario
#define RATT_TEXT_LO         C'55,68,45'       // testo disabilitato

// Alias dashboard
#define RATT_TEXT_SECONDARY  RATT_TEXT_MID
#define RATT_TEXT_MUTED      RATT_TEXT_LO

//+------------------------------------------------------------------+
//| CANDELE CHART                                                    |
//+------------------------------------------------------------------+
#define RATT_CANDLE_BULL     C'38,166,154'     // teal (UTBotAdaptive)
#define RATT_CANDLE_BEAR     C'239,83,80'      // coral (UTBotAdaptive)

//+------------------------------------------------------------------+
//| OVERLAY CANALE — Trailing stop                                   |
//+------------------------------------------------------------------+
#define RATT_CHAN_UPPER_CLR   C'80,220,100'     // Verde prato (trailing bull)
#define RATT_CHAN_LOWER_CLR   C'255,85,75'      // Rosso tramonto (trailing bear)
#define RATT_CHAN_TRAIL_BULL  C'38,166,154'     // Teal trailing bull (UTBotAdaptive)
#define RATT_CHAN_TRAIL_BEAR  C'239,83,80'      // Coral trailing bear (UTBotAdaptive)
#define RATT_CHAN_MID_UP_CLR  C'80,220,100'     // Midline bullish
#define RATT_CHAN_MID_DN_CLR  C'255,85,75'      // Midline bearish
#define RATT_CHAN_MID_FLAT_CLR C'255,220,50'    // Midline flat (= RATT_FIREFLY)
#define RATT_CHAN_MID_CLR     C'255,220,50'     // Midline lucciola
#define RATT_CHAN_FILL_CLR    C'40,100,50'      // Fill verde campagna
#define RATT_CHAN_FILL_ALPHA  30                // Trasparenza fill
#define RATT_CHAN_MA_CLR      C'28,90,45'       // MA line verde campagna
#define RATT_CHAN_WIDTH       2                 // Spessore
#define RATT_CHAN_STYLE       STYLE_SOLID
#define RATT_CHAN_MID_STYLE   STYLE_DOT

// Hedge Smart entry channel (outer Donchian)
#define RATT_HS_CHAN_CLR      C'255,140,0'     // Arancione (= RATT_HEDGE)
#define RATT_HS_CHAN_STYLE    STYLE_DOT        // Tratteggiato
#define RATT_HS_CHAN_WIDTH    1                 // Spessore 1

//+------------------------------------------------------------------+
//| FRECCE SEGNALE — 4 livelli ER (UTBotAdaptive style)              |
//+------------------------------------------------------------------+
#define RATT_ARROW_BUY_0       C'76,175,80'    // ER >= 0.60 — FORTE (verde scuro)
#define RATT_ARROW_BUY_1       C'139,195,74'   // ER 0.35-0.59 — MODERATO (verde chiaro)
#define RATT_ARROW_BUY_2       C'255,193,7'    // ER 0.15-0.34 — DEBOLE (giallo)
#define RATT_ARROW_BUY_3       C'120,120,120'  // ER < 0.15 — RANGING (grigio)
#define RATT_ARROW_SELL_0      C'239,83,80'    // ER >= 0.60 — FORTE (rosso)
#define RATT_ARROW_SELL_1      C'255,138,101'  // ER 0.35-0.59 — MODERATO (arancio)
#define RATT_ARROW_SELL_2      C'255,193,7'    // ER 0.15-0.34 — DEBOLE (giallo)
#define RATT_ARROW_SELL_3      C'120,120,120'  // ER < 0.15 — RANGING (grigio)
#define RATT_ARROW_SIZE        2               // Arrow width (UTBotAdaptive)
#define RATT_ARROW_OFFSET      0.5             // Offset multiplier x ATR (UTBotAdaptive)

//+------------------------------------------------------------------+
//| ENTRY/EXIT                                                       |
//+------------------------------------------------------------------+
#define RATT_ENTRY_BUY_CLR   RATT_BUY
#define RATT_ENTRY_SELL_CLR  RATT_SELL
#define RATT_ENTRY_LEVEL_CLR    C'148,0,211'    // Viola — entry level line (UTBotAdaptive)
#define RATT_TRIGGER_CANDLE_CLR C'255,235,59'   // Giallo — highlight trigger candle

//+------------------------------------------------------------------+
//| TP TARGET                                                        |
//+------------------------------------------------------------------+
#define RATT_TP_DOT_BUY      C'80,255,120'    // TP dot BUY
#define RATT_TP_DOT_SELL     C'255,60,60'     // TP dot SELL
#define RATT_TP_HIT_CLR      C'255,220,50'    // TP hit star — lucciola
#define RATT_TP_LINE_WIDTH   1

//+------------------------------------------------------------------+
//| Z-ORDER                                                          |
//+------------------------------------------------------------------+
#define RATT_ZORDER_RECT     15000
#define RATT_ZORDER_LABEL    16000
#define RATT_ZORDER_BTN      16001

// Alias brevi usati dal dashboard
#define RATT_Z_RECT          RATT_ZORDER_RECT
#define RATT_Z_LABEL         RATT_ZORDER_LABEL
#define RATT_Z_BUTTON        RATT_ZORDER_BTN

//+------------------------------------------------------------------+
//| FONT                                                             |
//+------------------------------------------------------------------+
#define RATT_FONT_MONO       "Consolas"
#define RATT_FONT_TITLE      "Segoe UI Bold"
#define RATT_FONT_SECTION    "Segoe UI Semibold"
#define RATT_FONT_SIZE       9

// Alias dashboard
#define RATT_FONT_BODY       RATT_FONT_MONO
#define RATT_FONT_SIZE_BODY  RATT_FONT_SIZE

//+------------------------------------------------------------------+
//| DASHBOARD DIMENSIONI (layout 2 colonne stile SugaraPivot)        |
//+------------------------------------------------------------------+
#define RATT_DASH_X          10
#define RATT_DASH_Y          25
#define RATT_DASH_W          690               // full width (2 colonne)
#define RATT_DASH_COL_W      345               // larghezza singola colonna
#define RATT_PAD             14
#define RATT_GAP             4

#define RATT_H_TITLE         50                // Title panel (full width)
#define RATT_H_MODE          40                // Mode/Symbol panel (full width)
#define RATT_H_ENGINE        145               // UTBot Engine (left col)
#define RATT_H_SYSSTATUS     145               // System Status (right col)
#define RATT_H_PL            115               // P&L Session (left col)
#define RATT_H_CYCLES        145               // Active Cycles (right col)
#define RATT_H_STATUSBAR     20                // Status bar (full width)
#define RATT_SIDE_W          210

//+------------------------------------------------------------------+
//| PANEL BACKGROUND — Sfumature differenziate per sezione            |
//+------------------------------------------------------------------+
#define RATT_BG_ENGINE       C'10,18,30'       // Engine panel
#define RATT_BG_PL           C'8,12,22'        // P&L panel (piu' scura)
#define RATT_BG_CYCLES       C'12,20,32'       // Cycles panel
#define RATT_BG_SIGNALS      C'14,24,36'       // Signals panel

//+------------------------------------------------------------------+
//| ApplyChartTheme() — Applica palette Notti Estive al chart        |
//+------------------------------------------------------------------+
void ApplyChartTheme()
{
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,   RATT_BG_DEEP);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,   RATT_TEXT_HI);
   ChartSetInteger(0, CHART_COLOR_GRID,         C'20,30,20');
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL,  RATT_CANDLE_BULL);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR,  RATT_CANDLE_BEAR);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,     RATT_CANDLE_BULL);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,   RATT_CANDLE_BEAR);
   ChartSetInteger(0, CHART_COLOR_ASK,          RATT_BUY);
   ChartSetInteger(0, CHART_COLOR_BID,          RATT_SELL);
   ChartSetInteger(0, CHART_SHOW_GRID,          false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES,       CHART_VOLUME_HIDE);
}
