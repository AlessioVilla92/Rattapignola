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
#define RATT_BORDER_FRAME    C'55,180,75'      // verde campagna perimetrale dashboard

// Alias dashboard
#define RATT_PANEL_BG        RATT_BG_PANEL
#define RATT_PANEL_BORDER    RATT_BORDER
#define RATT_SIDE_BORDER     C'55,180,75'      // Verde campagna per side panels

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
#define RATT_CANDLE_BULL     C'80,220,100'     // verde prato
#define RATT_CANDLE_BEAR     C'255,85,75'      // rosso tramonto

//+------------------------------------------------------------------+
//| OVERLAY CANALE — Trailing stop                                   |
//+------------------------------------------------------------------+
#define RATT_CHAN_UPPER_CLR   C'80,220,100'     // Verde prato (trailing bull)
#define RATT_CHAN_LOWER_CLR   C'255,85,75'      // Rosso tramonto (trailing bear)
#define RATT_CHAN_TRAIL_BULL  C'80,220,100'     // Verde prato trailing bull
#define RATT_CHAN_TRAIL_BEAR  C'255,85,75'      // Rosso tramonto trailing bear
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
//| FRECCE SEGNALE                                                   |
//+------------------------------------------------------------------+
#define RATT_ARROW_STRONG_BUY  C'80,255,120'   // Strong BUY — verde brillante
#define RATT_ARROW_STRONG_SELL C'255,60,60'    // Strong SELL — rosso brillante
#define RATT_ARROW_WEAK_BUY    C'50,140,70'    // Weak BUY — verde scuro
#define RATT_ARROW_WEAK_SELL   C'160,50,50'    // Weak SELL — rosso scuro
#define RATT_ARROW_SIZE        5               // Arrow width
#define RATT_ARROW_OFFSET      0.15            // Offset multiplier x ATR

//+------------------------------------------------------------------+
//| ENTRY/EXIT                                                       |
//+------------------------------------------------------------------+
#define RATT_ENTRY_BUY_CLR   RATT_BUY
#define RATT_ENTRY_SELL_CLR  RATT_SELL

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
#define RATT_FONT_TITLE      "Arial Black"
#define RATT_FONT_SECTION    "Arial Bold"
#define RATT_FONT_SIZE       9

// Alias dashboard
#define RATT_FONT_BODY       RATT_FONT_MONO
#define RATT_FONT_SIZE_BODY  RATT_FONT_SIZE

//+------------------------------------------------------------------+
//| DASHBOARD DIMENSIONI                                             |
//+------------------------------------------------------------------+
#define RATT_DASH_X          10
#define RATT_DASH_Y          25
#define RATT_DASH_W          640
#define RATT_PAD             14
#define RATT_GAP             4

#define RATT_H_HEADER        36                // Header
#define RATT_H_TOPBAR        32                // TitleBar: Pair + Price + Spread + State
#define RATT_H_SYSSTATUS     76
#define RATT_H_ENGINE        88
#define RATT_H_FILTERS       22
#define RATT_H_LASTSIG       76
#define RATT_H_CYCLES        (26 + 4 * 16 + 4)
#define RATT_H_PL            88
#define RATT_H_CONTROLS      52
#define RATT_H_STATUSBAR     20
#define RATT_SIDE_W          210

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
