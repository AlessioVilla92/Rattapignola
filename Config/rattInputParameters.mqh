//+------------------------------------------------------------------+
//|                                      rattInputParameters.mqh     |
//|           Rattapignola EA v1.6.1 — Input Parameters              |
//|                                                                  |
//|  Sezione FRAMEWORK: parametri stabili (non cambiano con engine)  |
//|  Sezione ENGINE:    parametri UTBot-specifici (da sostituire)     |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

#include "rattVisualTheme.mqh"

//+------------------------------------------------------------------+
//|                                                                  |
//|  ╔═════════════════════════════════════════════════════════════╗  |
//|  ║          === FRAMEWORK INPUTS ===                           ║  |
//|  ║  Questi parametri NON cambiano quando si swappa engine      ║  |
//|  ╚═════════════════════════════════════════════════════════════╝  |
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 1. SYSTEM CONFIGURATION                                          |
//+------------------------------------------------------------------+

input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  ⚙️ SYSTEM CONFIGURATION                                  ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    🔧 CORE SETTINGS"
input bool           EnableSystem           = true;        // ✅ Enable EA
input int            MagicNumber            = 88401;       // 🆔 Magic Number (Unique EA ID)
input int            Slippage               = 3;           // 📏 Slippage (points, auto-scaled per prodotto)
input bool           VirtualMode            = false;       // 🔮 Virtual Mode (paper trading)

input group "    🌐 INSTRUMENT CLASS"
input ENUM_INSTRUMENT_CLASS InstrumentClass = INSTRUMENT_AUTO; // 📋 Prodotto CFD ▼ (Auto = rileva dal simbolo)

//+------------------------------------------------------------------+
//| 2. RISK MANAGEMENT                                               |
//+------------------------------------------------------------------+

input group "                                                           "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  💰 RISK MANAGEMENT                                       ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    📊 POSITION SIZING"
input ENUM_RISK_MODE RiskMode               = RISK_FIXED_LOT; // 📋 Risk Mode ▼
input double         LotSize                = 0.02;          // 📏 Fixed Lot Size (if FIXED_LOT)
input double         RiskPercent            = 1.0;           // 📊 Risk % Equity (if RISK_PCT)
input double         RiskCashPerTrade       = 50.0;          // 💵 Risk Cash per Trade (if FIXED_CASH)

input group "    📐 SIGNAL QUALITY LOT SIZING"
//  TBS (Turtle Body Soup) = segnale FORTE: il corpo della candela penetra la banda
//  TWS (Turtle Wick Soup) = segnale DEBOLE: solo la shadow/wick tocca la banda
//  Il lotto base viene moltiplicato per questi fattori in base alla qualita' del segnale.
//  Esempio: LotSize=0.01, TBS_mult=2.0, TWS_mult=1.0 → TBS apre 0.02, TWS apre 0.01
input double         TBSLotMultiplier       = 2.0;           // 📈 TBS (segnale forte): moltiplicatore lotti (es. 2.0 = doppio)
input double         TWSLotMultiplier       = 1.0;           // 📉 TWS (segnale debole): moltiplicatore lotti (es. 1.0 = invariato)

input group "    🛡️ RISK LIMITS"
input int            MaxConcurrentTrades    = 3;             // 📊 Max Concurrent Trades
input double         MaxSpreadPips          = 3.0;           // 📏 Max Spread (pip)
input double         DailyLossLimitPct      = 2.0;           // 🛑 Daily Loss Limit (% equity, 0=off)

//+------------------------------------------------------------------+
//| 3. TRADE PARAMETERS                                              |
//+------------------------------------------------------------------+

input group "                                                           "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📈 TRADE PARAMETERS                                      ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    🎯 ENTRY MODE"
input ENUM_ENTRY_MODE  EntryMode            = ENTRY_STOP;    // 📋 Entry Mode (MARKET/LIMIT/STOP) ▼
input double           LimitOffsetPips      = 2.0;           // 📏 Limit Offset (pip, se LIMIT mode)
input double           StopOffsetPips       = 1.0;           // 📏 Stop Offset from trigger (pip, se STOP mode)
input int              PendingExpiryBars    = 8;             // ⏱️ Expiry Pending (barre, 0=mai)

// [MOD] Rimosso gruppo "STOP LOSS" con i parametri SLMode (ENUM_SL_MODE) e SLValue (double).
// Il calcolo SL era buggato (SL_BAND_OPPOSITE invertiva la direzione) e causava
// il rifiuto di tutti gli ordini pendenti. SL ora disattivato: ordini senza stop loss.

input group "    ✅ TAKE PROFIT"
input ENUM_TP_MODE     TPMode               = TP_SIGNAL_TO_SIGNAL; // 📋 TP Mode ▼
input double           TPValue              = 2.0;           // 📏 TP Value (ATR mult o pip, in base a TPMode)

//+------------------------------------------------------------------+
//| 4. SESSION FILTER                                                |
//+------------------------------------------------------------------+

input group "                                                           "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  ⏰ SESSION FILTER                                        ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    🌍 SESSION WINDOWS"
input bool           EnableSessionFilter    = false;         // ❌ Session Filter OFF (crypto 24/7, Forex tutte le sessioni)
input bool           SessionLondon          = true;          // 🇬🇧 London Session (08:00-16:30 UTC)
input bool           SessionNewYork         = true;          // 🇺🇸 New York Session (13:00-21:00 UTC)
input bool           SessionAsian           = false;         // 🇯🇵 Asian Session (00:00-08:00 UTC)

input group "    🚫 BLOCKED TIME"
input string         BlockedTimeStart       = "00:00";       // ⏱️ Blocked Time Start (HH:MM server)
input string         BlockedTimeEnd         = "00:00";       // ⏱️ Blocked Time End (HH:MM server)

//+------------------------------------------------------------------+
//| 5. MTF DIRECTION FILTER                                          |
//+------------------------------------------------------------------+

input group "                                                           "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📊 MTF DIRECTION FILTER                                  ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    🔍 HTF SETTINGS"
input bool           UseHTFFilter           = false;         // ✅ Enable HTF Filter
input ENUM_TIMEFRAMES HTFTimeframe          = PERIOD_H1;     // 📋 HTF Timeframe ▼
input int            HTFPeriod              = 20;            // 📊 HTF Donchian Period

//+------------------------------------------------------------------+
//| 6. VISUAL                                                        |
//+------------------------------------------------------------------+

input group "                                                           "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🎨 VISUAL SETTINGS                                       ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    🖥️ CHART DISPLAY"
input bool           ShowChannelOverlay     = true;          // ✅ Show Channel Overlay on Chart
input bool           ShowSignalArrows       = true;          // ✅ Show Signal Arrows
input bool           ShowTPTargetLines      = true;          // ✅ Show TP Target Lines
input int            OverlayDepth           = 500;           // 📊 Channel Overlay Depth (bars, 0=arrows only)
input bool           ColorCandlesByTrend    = true;          // 🎨 Color Candles by Trend (off=trail/frecce restano, candele MT5 native)

//+------------------------------------------------------------------+
//| 7. ADVANCED                                                      |
//+------------------------------------------------------------------+

input group "                                                           "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🔧 ADVANCED SETTINGS                                     ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    💾 AUTO-SAVE & RECOVERY"
input bool           ClearStateOnRemove     = true;          // 🗑️ Clear State when EA Removed
input bool           EnableAutoSave         = true;          // ✅ Enable Auto-Save (GlobalVariables)
input int            AutoSaveIntervalMin    = 5;             // ⏱️ Auto-Save Interval (minutes)
input bool           EnableAutoRecovery     = true;          // ✅ Enable Auto-Recovery on Restart

input group "    📊 FRAMEWORK ATR (Dashboard/Display)"
input int            InpATR_Period          = 14;             // 📊 ATR Period (framework display)
input ENUM_TIMEFRAMES InpATR_Timeframe     = PERIOD_CURRENT;  // 📋 ATR Timeframe ▼

input group "    📝 LOGGING"
input ENUM_LOG_LEVEL MinLogLevel            = LOG_INFO;      // 📋 Minimum Log Level ▼
input bool           LogToCSVFile           = false;         // 📝 Write Log to CSV File
input int            MaxRetries             = 3;             // 🔄 Max Order Retries
input int            RetryDelayMs           = 500;           // ⏱️ Retry Delay (ms)

//+------------------------------------------------------------------+
//|                                                                  |
//|  ╔═════════════════════════════════════════════════════════════╗  |
//|  ║          === ENGINE INPUTS (UTBot Adaptive) ===             ║  |
//|  ║  Questi parametri sono specifici del UTBot Engine.          ║  |
//|  ║  Quando si swappa engine, sostituire SOLO questo blocco.    ║  |
//|  ╚═════════════════════════════════════════════════════════════╝  |
//|                                                                  |
//+------------------------------------------------------------------+

// ╔══════════════════════════════════════════════════════════════╗
// ║          === ENGINE INPUTS (UTBot Adaptive) ===              ║
// ╚══════════════════════════════════════════════════════════════╝

// E1. UTBOT CORE
input group "    ⚙️ E1. UTBOT CORE"
input ENUM_UTB_TF_PRESET InpUTBPreset     = UTB_TF_AUTO;  // Preset Timeframe
input double             InpKeyValue      = 1.0;           // Key Value (ATR multiplier)
input int                InpATRPeriod_UTB = 10;            // ATR Period

// E2. SORGENTE ADATTIVA
input group "    ⚙️ E2. SORGENTE ADATTIVA"
input ENUM_UTB_SRC_TYPE  InpSrcType       = UTB_SRC_JMA;  // Tipo sorgente
input int                InpHMAPeriod     = 14;            // HMA Period
input int                InpKAMA_N        = 10;            // KAMA ER Period
input int                InpKAMA_Fast     = 2;             // KAMA Fast EMA
input int                InpKAMA_Slow     = 30;            // KAMA Slow EMA
input int                InpJMA_Period    = 14;            // JMA Period
input int                InpJMA_Phase     = 0;             // JMA Phase -100..100

// E3. QUALITA' SEGNALE
input group "    ⚙️ E3. QUALITA' SEGNALE (ER)"
input double             InpERStrong      = 0.35;          // ER soglia TBS (forte)
input double             InpERWeak        = 0.15;          // ER soglia minima (sotto = skip)
input bool               InpShowWeakSig   = true;          // Mostra segnali deboli (ER<0.35)

// E4. SQUEEZE MOMENTUM EXIT (secondario)
input group "    📊 E4. SQUEEZE MOMENTUM EXIT (secondario)"
input bool   InpUseSqzExit     = false;     // Abilita exit via SqueezeMomentum
input int    InpSqzBBLength    = 20;         // BB Length
input double InpSqzBBMult      = 2.0;        // BB MultFactor
input int    InpSqzKCLength    = 20;         // KC Length
input double InpSqzKCMult      = 1.5;        // KC MultFactor
input bool   InpSqzUseTR       = true;       // Usa True Range
input double InpSqzHalfPeakRatio = 0.50;     // Soglia half-peak (0.50 = 50%)

// E9. HEDGE SMART — Sistema hedge non invasivo (v1.7.0)
input group "                                                           "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🛡️ HEDGE SMART — Non-invasivo (preserva Soup)          ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input group "    ⚙️ MASTER SWITCH"
input bool   EnableHedge            = false;   // ❌ Abilita sistema hedge
input bool   HsEnabled              = false;   // ❌ Abilita Hedge Smart

input group "    📊 LOTTO"
input double HsLot                  = 0.01;    // 📏 Lotto fisso HS (indipendente dalla Soup)

input group "    📐 TRIGGER"
input double HsTriggerPct           = 0.30;    // 📏 Trigger: banda ± X% channel_width
// ↑ Esempio: cw=15pip, 0.30 → trigger a 4.5pip dalla banda

input group "    🚪 EXIT CONDITIONS"
input int    HsAntiWhipsawBars      = 3;       // ⏱️ Min barre prima di exit su segnale UTBot
// ↑ Anti-whipsaw: ignora segnali nelle prime N barre dall'attivazione HS

input bool   HsCloseOnSoupProfit    = false;   // [DEPRECATED v1.7.2] Sostituito da HsCleanup in MonitorActive

input int    HsTimeoutBars          = 32;      // ⏱️ Timeout barre (0 = disattivato, 32 = 8h su M15)
// ↑ Se HS rimane aperto per N barre, chiudi a mercato. 0 = nessun timeout.

input group "    🔧 STEP1 BE + STEP2 TP (v1.7.2)"
input double HsMidlineSL            = 1.0;     // 🛡️ SL iniziale HS = midline (1.0=ON, 0=no SL broker)
// ↑ La midline = SoupTP: perdita HS compensata dal profitto Soup
input double HsStep1Pct             = 0.30;    // 📏 Step1 BE: % cw per trigger breakeven dal fill
// ↑ es. 0.30 su cw=40pip → BE scatta dopo 12pip profitto
input double HsTpPct                = 0.60;    // 📏 Step2 TP: % cw per tpRefLevel dal trigger
// ↑ es. 0.60 su cw=40pip → Step2 a 24pip dal trigger
input bool   HsBEEnabled            = true;    // ✅ Attiva logica Step1 (breakeven)
input bool   HsUseStep2Close        = true;    // ✅ Chiudi HS quando raggiunge tpRefLevel (Step2)

input group "    🔬 BODY FILTER (opzionale)"
input bool   HsBodyFilter           = true;    // ✅ Abilita body/wick ratio filter
// ↑ HS si attiva SOLO se body_ratio della candela breakout [1] >= HsBodyRatioMin

input double HsBodyRatioMin         = 0.55;    // 📏 Body ratio minimo (0.0–1.0)
// ↑ body_ratio = |close-open|/(high-low) della candela [1]
//   < 0.50 = wick dominante → probabile falso breakout → NO hedge
//   0.55 = default M15 GBPUSD    0.70 = conservativo

input group "    🎨 VISUALIZZAZIONE"
input bool   HsShowZones            = true;    // ✅ Zone colorate trigger+TP sul grafico
input bool   HsShowTriggerLine      = true;    // ✅ Linea tratteggiata al trigger
input color  HsTriggerZoneColor     = C'80,50,0';   // 🎨 Colore zona trigger (arancione scuro)
input color  HsTPZoneColor          = C'0,40,80';   // 🎨 Colore zona TP ref (blu scuro)
input int    HsTriggerLineWidth     = 6;             // 📏 Durata linea trigger (barre)
