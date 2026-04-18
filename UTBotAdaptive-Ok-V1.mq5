//+------------------------------------------------------------------+
//| UTBotAdaptive.mq5                                                |
//| Copyright Alessio / AcquaDulza ecosystem                         |
//| UT Bot Alerts — porting MQL5 con sorgente adattiva KAMA/HMA/JMA   |
//+------------------------------------------------------------------+
//|                                                                  |
//| DESCRIZIONE GENERALE                                             |
//| Porting fedele dell'indicatore Pine Script "UT Bot Alerts" di    |
//| QuantNomad (v4), con estensione della sorgente adattiva:         |
//|   - SRC_CLOSE: identico all'originale Pine Script (src = close)  |
//|   - SRC_HMA:   Hull Moving Average (lag ridotto)                 |
//|   - SRC_KAMA:  Kaufman Adaptive MA (anti-whipsaw nei range)      |
//|   - SRC_JMA:   Jurik-style MA adattiva (quasi zero lag) [v2.00+]|
//|                                                                  |
//| L'indicatore calcola un Trailing Stop basato su ATR che segue    |
//| il prezzo: si alza progressivamente in uptrend (ratchet up) e    |
//| si abbassa in downtrend (ratchet down). Quando il prezzo         |
//| attraversa il trailing stop si genera un segnale BUY o SELL.     |
//|                                                                  |
//| PRESET TF COMPLETI (v1.04):                                      |
//|   AUTO rileva il TF dal chart e applica Key/ATR/KAMA ottimizzati.|
//|   MANUALE usa tutti i parametri inseriti dall'utente.             |
//|   Ricerca: KAMA pre-filtra rumore → Key ~25-35% più basso del   |
//|   close puro. Slow cresce con TF per resistenza al chop.         |
//|                                                                  |
//|   TF   Key  ATR  KAMA(N/Fast/Slow)  Stile                       |
//|   M1   0.7   5   5 / 2 / 20        ultra-scalping reattivo      |
//|   M5   1.0   7   8 / 2 / 20        scalping intraday            |
//|   M15  1.2  10  10 / 2 / 30        day trade (Kaufman default)   |
//|   M30  1.5  10  10 / 2 / 30        day trade / swing intraday   |
//|   H1   2.0  14  14 / 2 / 35        swing intraday               |
//|   H4   2.5  14  14 / 2 / 40        swing / position             |
//|                                                                  |
//| ANTI-REPAINTING (v1.03):                                         |
//|   Le frecce BUY/SELL appaiono SOLO su barre chiuse (confermate). |
//|   Una volta disegnata, la freccia resta permanente.               |
//|   Il trailing stop line e le candele si aggiornano in real-time. |
//|   B_State per EA: confermato solo su barre chiuse.                |
//|   Alert: già su barra chiusa (rates_total-2).                    |
//|                                                                  |
//| COMPONENTI VISIVE (13 plot, v3.00):                              |
//|   Plot 0:  Linea trailing stop colorata (teal/coral)            |
//|   Plot 1-3: Frecce BUY multi-ER (3/2/1 per forza segnale)      |
//|   Plot 4-6: Frecce SELL multi-ER (3/2/1 per forza segnale)     |
//|   Plot 7:  Caution marker (ER<0.15)                             |
//|   Plot 8:  Entry level line (viola dash)                        |
//|   Plot 9-11: Flat zone (fill blu + bordi bianco dot)            |
//|   Plot 12: Candele colorate (teal/coral/giallo trigger)         |
//|                                                                  |
//| BUFFER ESPOSTI PER EA ESTERNI (v3.00):                           |
//|   Buffer 2:  segnale BUY (prezzo freccia o EMPTY_VALUE)          |
//|   Buffer 8:  segnale SELL (prezzo freccia o EMPTY_VALUE)         |
//|   Buffer 26: Efficiency Ratio 0.0-1.0                            |
//|   Buffer 27: stato posizione (+1.0 long, -1.0 short, 0 neutro)  |
//|   Buffer 28: FlatState (1.0=active, 0.0=flat)                    |
//|   Buffer 29: ChannelWidth (in prezzo)                             |
//|                                                                  |
//+------------------------------------------------------------------+
//|                                                                  |
//| CHANGELOG                                                        |
//|                                                                  |
//| v4.03 — Polish: dashboard ER avg + banner nav + cleanup          |
//|   - Dashboard: ER visualizzato come media su InpFlatERBars barre |
//|     (era istantaneo → confusione quando FLAT attivo ma ER ist.>  |
//|     soglia). Ora coerente con la metrica usata in detection.     |
//|   - #property version allineato a 4.02→4.03 (era rimasto 4.01).  |
//|   - Banner ASCII (A/B/C/D/E/F) nel main loop OnCalculate per     |
//|     navigazione visiva rapida delle sezioni funzionali.          |
//|   - Commenti potenziati: anti-repainting gate, entry level line, |
//|     B_State, barra formante carry-forward, bias gate/contra.     |
//|   - Cleanup: rimossa ridondanza in UTBotPresetsInit case MANUAL  |
//|     (g_eff_flatMinWidth ora fa default semplice, override globale|
//|     post-switch unifica il path per tutti i preset).             |
//|                                                                  |
//| v4.02 — Flat Zone detection ATR-relativa (auto-adattiva)         |
//|   - Nuovo InpFlatKATR=0.75: soglia = k × 2 × KeyValue × ATR_m20  |
//|     auto-scala per TF/simbolo/volatilità (no pips assoluti).     |
//|   - Nuovo InpFlatATRLong=20: barre per ATR medio lungo.          |
//|   - Fallback legacy: se InpFlatKATR=0 usa g_eff_flatMinWidth     |
//|     in pips come prima (backward compat).                        |
//|   - Dashboard: diagnostica doppia (ChWidth + ER avg) con colori  |
//|     verde/rosso per identificare quale condizione blocca flat.   |
//|   - Fix radice bug "canale azzurro mai visibile": soglie pips    |
//|     dei preset erano troppo strette (chWidth tipico ≈ 2xATR,     |
//|     soglia 3.5p su M5 vs ATR tipico 3-8p → isFlat sempre false). |
//|                                                                  |
//| v4.01 — Toggle CHAND sempre visibile + logico                    |
//|   - Pulsante CHAND nel dashboard: sempre visibile (era nascosto  |
//|     quando InpShowChandelier=false → impossibile attivarlo).     |
//|   - Toggle CHAND ora è LOGICO (come BIAS): attiva/disattiva il   |
//|     calcolo Chandelier + forza fullRecalc al prossimo tick.       |
//|   - InpShowChandelier → g_dash_vis_chand nel loop calc e nella   |
//|     barra corrente: il runtime toggle controlla il calcolo.       |
//|   - InpShowChandelier rimane solo come valore iniziale in OnInit. |
//|                                                                  |
//| v4.00 — Chandelier Exit + BiasGate + BiasContra marker           |
//|   - Chandelier Exit Anchored: overlay trailing (long/short)      |
//|     HH/LL anchor resettato ad ogni crossover trail, ratchet,     |
//|     vol normalization opzionale (avgATR/ATR). Plot 13-14.        |
//|   - BiasGate (buffer 30 CALC): 1.0=con-bias, 0.0=contro-bias    |
//|     per EA: apri solo su con-bias, chiudi su contro-bias.        |
//|   - BiasContra marker ◆ (Plot 15 COLOR_ARROW): segnale visivo   |
//|     su crossover bloccati dal bias HTF. Wingdings 169.           |
//|   - Dashboard: pulsante CHAND (toggle visivo Plot 13-14).        |
//|   - iCustom: 33 parametri (era 30), 3 nuovi Chandelier.         |
//|   - FIX CRITICO (spec): g_chandLL init 0 → 999999 per           |
//|     catturare correttamente i low iniziali.                      |
//|   - Buffer 30-34, Plot 13-16, btnIds 7, MAX_ROWS 30.            |
//|                                                                  |
//| v3.52 — Bias HTF auto-preset + B_State bias-aware                |
//|   - g_eff_biasTF: TF bias automatico per preset                  |
//|     M1→M15, M5→M30, M15→H1, M30→H4, H1→H4, H4→D1              |
//|     MANUAL: usa InpBiasTF dall'input utente                      |
//|   - InpBiasTF → g_eff_biasTF in tutti i path runtime            |
//|     (iCustom, iBars, iBarShift, dashboard)                       |
//|   - Fix: B_State ora rispetta il filtro bias HTF                 |
//|     Prima usava crossover raw (src vs t1): l'EA vedeva           |
//|     cambio di stato su pullback piccoli contro-trend anche       |
//|     quando l'HTF era in trending → chiusure inutili.             |
//|     Ora B_State cambia SOLO con isBuy/isSell filtrati.           |
//|                                                                  |
//| v3.51 — Bugfix post-audit v3.50                                 |
//|   - Fix: iBarShift -1 guard (anti-repainting HTF bias per-bar)  |
//|     iBarShift ritorna -1 se tempo non trovato → htfIdx=0 →      |
//|     leggeva barra formante. Aggiunto if(htfShift >= 0) guard.    |
//|   - Fix: Donchian reset su OGNI fullRecalc (init, cambio TF)    |
//|     Prima il reset g_wasFlatPrev/HH/LL era solo nel path        |
//|     force-recalc → prima flat zone dopo load ereditava stantii.  |
//|   - Fix: InpShowFlatZone → g_dash_vis_flatzone nel loop calc    |
//|     Input immutabile ignorava toggle dashboard FLAT; buffer      |
//|     restavano EMPTY_VALUE anche con toggle ON.                   |
//|   - Fix: FLAT toggle OFF→ON resetta Donchian (g_wasFlatPrev,    |
//|     g_flatRangeHigh/Low) per evitare range stantii ereditati     |
//|     dal periodo flat precedente alla riattivazione.              |
//|                                                                  |
//| v3.50 — HTF bias per-bar + Donchian flat + dashboard toggles     |
//|   - HTF bias per-bar con iBarShift (backtest visivo corretto)    |
//|     CopyBuffer full solo in fullRecalc (performance fix)         |
//|   - Flat zone: Donchian orizzontale (HH/LL persistenti)          |
//|   - Dashboard: +2 pulsanti toggle (FLAT visivo, BIAS logico)     |
//|   - BIAS toggle: force-recalc tutte le frecce + reset Donchian   |
//|   - Handle HTF sempre creato (toggle indipendente da input)      |
//|   - Preset FlatMinWidth ridotti per reattivita migliorata        |
//|   - Button pool 4→6 (fix: FLAT+BIAS non cliccabili)             |
//|   - Bias dashboard 3 stati: ON/OFF(toggle)/N/A(stesso TF)       |
//|                                                                  |
//| v3.01 — Dashboard trading avanzata + bugfix                      |
//|   - Dashboard: +4 righe live (ATR pips, Entry P/L, Ultimo        |
//|     Segnale con barre fa, Spread con colore semaforo)            |
//|   - UTB_DASH_MAX_ROWS 20→24 per ospitare le nuove righe         |
//|   - Bugfix: g_dash_vis_trail sincronizzato con InpShowTrailLine  |
//|     (prima restava true anche in embed mode EA)                  |
//|   - Bugfix: scan segnale dashboard usava MathMax(0,...) che      |
//|     leggeva barre warmup (B_Buy1=0.0 != EMPTY_VALUE) → falso    |
//|     positivo. Fix: MathMax(g_warmup,...) evita zona non scritta  |
//|   - Bugfix: InpFlatERBars=0 causava 0.0/0→NaN, flat detection   |
//|     silenziosamente disabilitata. Fix: MathMax(InpFlatERBars,1)  |
//|                                                                  |
//| v3.00 — Upgrade strutturale da v2.01                             |
//|   - 14→30 buffer, 5→13 plot                                     |
//|   - Frecce multi-ER: 3/2/1+caution per forza segnale            |
//|     (ER>=0.60→3 frecce, >=0.35→2, >=0.15→1, <0.15→1+quadrato)  |
//|   - ER windowed Kaufman su close[] per TUTTE le sorgenti         |
//|     (era proxy |delta_src|/ATR per non-KAMA — impreciso)         |
//|   - Preset sorgente auto per TF: g_eff_srcType                  |
//|     (M1/M30/H1/H4→JMA, M5/M15→KAMA)                            |
//|   - Flat detection: chWidth<minWidth && erAvg<threshold          |
//|     → blocca segnali in lateralita, canale blu visivo            |
//|   - Buffer esposti per EA: FlatState(28), ChWidth(29)            |
//|   - B_Buy→B_Buy1, B_Sell→B_Sell1 (rename per multi-frecce)      |
//|   - OnChartEvent: plot index aggiornati (ARROWS 1-7, ENTRY 8,   |
//|     CANDLES 12) — fix NON presente nella specifica originale     |
//|   - iCustom HTF: 30 parametri, nome self-reference V1            |
//|   - CopyBuffer HTF: buffer 13→27 per B_State                    |
//|   - Dashboard: regime FLAT/ACTIVE, ChWidth in pips               |
//|   - InpSrcType→g_eff_srcType in short name, Print, dashboard    |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Alessio / AcquaDulza ecosystem"
#property version   "4.03"
#property description "UT Bot Alerts — KAMA/HMA/JMA + anti-repainting + frecce multi-ER"
#property description "v4.03: Flat Zone ATR-relativa + dashboard ER avg + banner nav + cleanup"
#property description "BUY/SELL su barre chiuse. Canale laterale blu. Entry marker viola."
#property indicator_chart_window
#property indicator_buffers 35
#property indicator_plots   16

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

// --- Plot 7: Caution marker (ER < 0.15) ---
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

//+------------------------------------------------------------------+
//| ENUM — Preset Timeframe                                          |
//+------------------------------------------------------------------+
// AUTO rileva il TF dal chart e applica i preset ottimizzati.
// MANUALE usa tutti i parametri inseriti dall'utente senza override.
// Regola generale: TF più alto → KeyValue più alto (stop più largo).
enum ENUM_TF_PRESET_UT
  {
   TF_PRESET_UT_AUTO   = 0,  // AUTO — rileva TF dal chart (raccomandato)
   TF_PRESET_UT_M1     = 1,  // M1  — scalping/entry di precisione
   TF_PRESET_UT_M5     = 2,  // M5  — intraday standard
   TF_PRESET_UT_M15    = 3,  // M15 — intraday
   TF_PRESET_UT_M30    = 4,  // M30 — swing intraday
   TF_PRESET_UT_H1     = 5,  // H1  — swing
   TF_PRESET_UT_H4     = 6,  // H4  — position
   TF_PRESET_UT_MANUAL = 7   // MANUALE — parametri dall'utente
  };

//+------------------------------------------------------------------+
//| ENUM — Sorgente adattiva                                         |
//+------------------------------------------------------------------+
// SRC_CLOSE: close pura, identica al Pine Script originale
// SRC_HMA:   Hull MA — riduce il lag, smoothing costante
// SRC_KAMA:  Kaufman Adaptive — si adatta alla volatilità:
//   trend forte → segue veloce (come EMA2)
//   range → quasi piatta (come EMA30), elimina i whipsaw
// SRC_JMA: Jurik-style MA (reverse-engineered, open source).
// Formula IIR 3 stadi completa con Jurik Bands + volatilita dinamica.
// alpha cambia ad ogni barra in base alla volatilita relativa del prezzo.
// Fonte: Igor PDF 2008 + mihakralj (match <2% vs DLL Jurik) + lastguru/TradingView.
// Phase=0 bilanciato, Phase>0 meno lag, Phase<0 piu smooth.
// Power non e un input: viene calcolato dinamicamente dalla volatilita.
enum ENUM_SRC_TYPE
  {
   SRC_CLOSE = 0,  // Close — originale QuantNomad (nessun filtro)
   SRC_HMA   = 1,  // Hull Moving Average (lag ridotto, smoothing costante)
   SRC_KAMA  = 2,  // Kaufman Adaptive MA (anti-whipsaw adattivo) — RACCOMANDATO
   SRC_JMA   = 3,  // Jurik-style MA (adattivo, quasi zero lag)
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📊 UT BOT ADAPTIVE                                      ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input ENUM_TF_PRESET_UT InpTFPreset  = TF_PRESET_UT_AUTO;  // ⚙ Preset Timeframe
input double          InpKeyValue    = 1.0;      // Key Value (auto-preset)
input int             InpATRPeriod   = 10;       // ATR Period (auto-preset)

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  ⚡ SORGENTE ADATTIVA                                    ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input ENUM_SRC_TYPE   InpSrcType     = SRC_JMA;   // ⚙ Tipo sorgente (JMA default v2.01)
input int             InpHMAPeriod   = 14;       // HMA Period (solo se SRC_HMA)

input group "    📐 KAMA (Kaufman Adaptive)"
input int             InpKAMA_N      = 10;       // KAMA ER Period (auto-preset)
input int             InpKAMA_Fast   = 2;        // KAMA Fast EMA (auto-preset)
input int             InpKAMA_Slow   = 30;       // KAMA Slow EMA (auto-preset)

input group "    ⚡ JMA (Jurik-style — SRC_JMA)"
input int             InpJMA_Period  = 14;       // JMA Period (auto-preset)
input int             InpJMA_Phase   = 0;        // JMA Phase -100..100 (auto-preset)

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📡 FILTRO BIAS HTF                                      ║"
input group "╚═══════════════════════════════════════════════════════════╝"

// Legge B_State (buffer 27) dello stesso indicatore su TF superiore.
// BUY accettato solo se HTF_state=+1. SELL solo se HTF_state=-1.
// Non attivare se TF chart >= InpBiasTF (evita ricorsione).
input bool            InpUseBias     = false;       // Attiva filtro bias HTF
input ENUM_TIMEFRAMES InpBiasTF      = PERIOD_H1;   // Timeframe del bias (default H1)

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📐 RILEVAMENTO LATERALITÀ                               ║"
input group "╚═══════════════════════════════════════════════════════════╝"

// [v3.00] Gruppo nuovo: rileva zone di lateralita (flat/ranging).
// Doppia condizione: canale stretto (chWidth < minWidth) E ER medio basso.
// Quando isFlat=true, i segnali BUY/SELL vengono bloccati (FLAT gate)
// e il canale viene visualizzato in blu sul chart (DRAW_FILLING).
// InpFlatMinWidth=0 usa il valore auto dal preset TF (g_eff_flatMinWidth).
input bool            InpFlatDetect     = true;    // Attiva rilevamento zona FLAT
input double          InpFlatKATR       = 0.75;    // [v4.02] Soglia ATR-relativa (0=usa pips)
input int             InpFlatATRLong    = 20;      // [v4.02] Barre per ATR medio lungo
input double          InpFlatMinWidth   = 0.0;     // Min Channel Width pips (0=auto-preset, fallback se KATR=0)
input double          InpFlatERThresh   = 0.20;    // ER medio soglia per FLAT
input int             InpFlatERBars     = 8;       // Barre per media ER
input bool            InpShowFlatZone   = true;    // Mostra zona FLAT (canale blu)

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📏 CHANDELIER EXIT OVERLAY                              ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool            InpShowChandelier = false;     // Mostra Chandelier Exit (overlay)
input double          InpChandMult      = 2.5;       // Chandelier ATR multiplier
input bool            InpChandVolNorm   = true;      // Normalizzazione volatilità ATR

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🎨 COLORI E STILE                                       ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool            InpColorBars   = true;     // Colora le candele
input bool            InpShowArrows  = true;     // Mostra frecce BUY/SELL

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🎭 TEMA CHART                                           ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool            InpApplyTheme     = true;          // Applica Tema Scuro
input bool            InpShowGrid       = false;         // Mostra Griglia

input group "    🎨 COLORI TEMA"
input color           InpThemeBG        = C'19,23,34';   // Sfondo Chart
input color           InpThemeFG        = C'131,137,150'; // Testo, Assi
input color           InpThemeGrid      = C'42,46,57';   // Griglia
input color           InpThemeBullCandl = C'38,166,154'; // Candela Rialzista
input color           InpThemeBearCandl = C'239,83,80';  // Candela Ribassista

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🔔 NOTIFICHE E ALERT                                    ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool            InpAlertPopup  = true;     // Alert popup su nuova barra
input bool            InpAlertPush   = false;    // Alert push notification

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🧩 EMBED MODE (per host EA — usalo SOLO da iCustom)     ║"
input group "╚═══════════════════════════════════════════════════════════╝"

// Quando UTBotAdaptive viene caricato come resource embedded da un EA host
// (es. Rattapignola), la dashboard interna e la trail line possono entrare
// in conflitto con quelle dell'EA. Disattivarli con questi due flag.
input bool            InpShowDashboard  = true;  // Mostra dashboard interna (off da EA host)
input bool            InpShowTrailLine  = true;  // Mostra trail line Plot 0 (off da EA host)

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
double B_Buy2[];        // buffer 4  — freccia BUY secondaria (ER>=0.35)
double B_Buy2Clr[];     // buffer 5
double B_Buy3[];        // buffer 6  — freccia BUY terziaria (ER>=0.60)
double B_Buy3Clr[];     // buffer 7
double B_Sell1[];       // buffer 8  — freccia SELL primaria
double B_Sell1Clr[];    // buffer 9
double B_Sell2[];       // buffer 10 — freccia SELL secondaria (ER>=0.35)
double B_Sell2Clr[];    // buffer 11
double B_Sell3[];       // buffer 12 — freccia SELL terziaria (ER>=0.60)
double B_Sell3Clr[];    // buffer 13
double B_Caution[];     // buffer 14 — quadratino cautela (ER<0.15)
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
// [v4.00] Nuovi buffer: BiasGate (CALC), Chandelier (DATA×2), BiasContra (COLOR_ARROW)
double B_BiasGate[];     // buffer 30 (CALC) 1.0=con-bias, 0.0=contro-bias, EMPTY=no signal
double B_ChandLong[];    // buffer 31 (Plot 13) Chandelier trailing long
double B_ChandShort[];   // buffer 32 (Plot 14) Chandelier trailing short
double B_BiasContra[];   // buffer 33 (Plot 15) marker ◆ contro-bias
double B_BiasContraClr[];// buffer 34 (Plot 15 COLOR)

//+------------------------------------------------------------------+
//| Variabili interne                                                |
//+------------------------------------------------------------------+
double g_src[];         // sorgente calcolata (close/HMA/KAMA)
double g_atr[];         // ATR Wilder calcolato manualmente
datetime g_lastAlert;   // dedup alert per timestamp barra
int g_warmup;           // barre di warmup prima del trailing stop
double g_entryLevel;    // livello entrata attivo (carry-forward fino a segnale opposto)

// --- Parametri effettivi (overridati da preset TF) ---
// Quando il preset è AUTO o un TF specifico, questi valori sovrascrivono
// gli input dell'utente. In modalità MANUALE, copiano gli input.
// KAMA: ER Period (N) controlla il lookback dell'Efficiency Ratio,
//       Fast/Slow controllano la velocità min/max della media adattiva.
//       TF bassi → N corto + Slow basso (reattivo ai micro-trend)
//       TF alti  → N lungo + Slow alto (filtra il chop sulle 4H)
double g_eff_keyValue;   // Key Value effettivo
int    g_eff_atrPeriod;  // ATR Period effettivo
int    g_eff_kamaN;      // KAMA ER Period effettivo
int    g_eff_kamaFast;   // KAMA Fast EMA effettivo
int    g_eff_kamaSlow;   // KAMA Slow EMA effettivo
int    g_eff_jmaPeriod;  // JMA Period effettivo
int    g_eff_jmaPhase;   // JMA Phase effettivo (-100..100)

// --- Preset sorgente auto (v3.00) ---
ENUM_SRC_TYPE g_eff_srcType;    // SrcType effettivo (overridato da preset AUTO)

// --- Flat detection (v3.00) ---
double g_eff_flatMinWidth;       // MinWidth effettivo (auto-preset o manuale)

// --- Bias HTF auto-preset (v3.52) ---
ENUM_TIMEFRAMES g_eff_biasTF;   // TF bias effettivo (overridato da preset AUTO)

// --- Stato interno JMA (persistente tra chiamate OnCalculate) ---
// Formula completa con Jurik Bands + volatilita dinamica.
// Fonte: Igor 2008 + mihakralj (match <2% vs DLL Jurik) + lastguru + pandas_ta.
double g_jma_e0[];       // Stage 1 — EMA adattiva
double g_jma_det0[];     // Stage 2 — errore Kalman
double g_jma_det1[];     // Stage 3 — filtro Jurik
double g_jma_uBand[];    // Jurik Band superiore
double g_jma_lBand[];    // Jurik Band inferiore
double g_jma_volty[];    // Volatilita istantanea
double g_jma_vSum[];     // Running sum volatilita
// Costanti JMA (calcolate una volta in UTBotPresetsInit)
double g_jma_PR;         // phase ratio (clamp phase/100+1.5)
double g_jma_len1;       // log-derived length param
double g_jma_pow1;       // power exponent base
double g_jma_bet;        // band smoothing factor (diverso da beta!)
double g_jma_beta;       // IIR base factor

// Handle bias HTF (INVALID_HANDLE se InpUseBias=false)
int    g_htfHandle = INVALID_HANDLE;

// --- Chart theme: colori originali per ripristino ---
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

//--- Dashboard (v3.00) ---
bool   g_dash_vis_trail   = true;   // Trail Stop line
bool   g_dash_vis_arrows  = true;   // Frecce BUY/SELL
bool   g_dash_vis_entry   = true;   // Entry marker viola
bool   g_dash_vis_candles = true;   // Candele colorate
bool   g_dash_vis_flatzone = true;  // [v3.50] Flat zone visibilità (toggle dashboard)
bool   g_dash_vis_bias     = true;  // [v3.50] Bias HTF attivo (toggle logico dashboard)
string UTB_DASH_PREFIX = "UTB_DASH_";
#define UTB_DASH_MAX_ROWS 30        // [v3.50] era 24, +4 per pulsanti FLAT+BIAS + margine
double g_lastHtfState     = 0.0;    // HTF state per dashboard
int    g_dash_ratesTotal  = 0;      // rates_total dall'ultimo OnCalculate

// --- HTF Bias runtime toggle (v3.50) ---
bool   g_biasEnabled;               // runtime toggle (init da InpUseBias)
int    g_forceRecalcCounter = 0;    // incrementato da OnChartEvent per forzare fullRecalc

// --- Flat zone Donchian (v3.50) ---
double g_flatRangeHigh;             // HH dall'inizio della flat zone
double g_flatRangeLow;              // LL dall'inizio della flat zone
bool   g_wasFlatPrev;               // isFlat della barra precedente

// --- Chandelier state (v4.00) ---
double g_chandHH;                // Highest High dal segnale (anchor)
double g_chandLL;                // Lowest Low dal segnale (anchor)
double g_chandLastLong;          // ultimo valore Chandelier Long (ratchet up)
double g_chandLastShort;         // ultimo valore Chandelier Short (ratchet down)

// --- Dashboard vis toggle (v4.00) ---
bool   g_dash_vis_chand = true;  // Chandelier visibilità

//+------------------------------------------------------------------+
//| UTBotPresetsInit — Applica preset TF ai parametri effettivi      |
//+------------------------------------------------------------------+
// Struttura identica a KCPresetsInit() del KeltnerPredictiveChannel.
// AUTO: rileva _Period e seleziona il preset corrispondente.
// MANUALE: usa tutti i parametri inseriti dall'utente senza override.
//
// LOGICA DEI PRESET (v1.04):
//   I parametri sono ottimizzati per KAMA come sorgente (SRC_KAMA).
//   KAMA pre-filtra il rumore → il KeyValue è ~25-35% più basso
//   rispetto all'uso con close pura (doppia protezione evitata).
//
//   KeyValue: cresce con il TF (micro-trend veloci → stop stretto,
//             macro-trend lenti → stop largo per assorbire il rumore).
//   ATR Period: cresce con il TF (5 barre su M1=5min, 14 su H1=14ore).
//   KAMA N (ER Period): cresce con il TF. Più corto = più reattivo
//             ai micro-trend, più lungo = efficienza su window ampia.
//   KAMA Slow: cresce con il TF. Più alto = KAMA più piatta in range,
//             massima resistenza al chop sui TF alti (H1/H4).
//   KAMA Fast: sempre 2 (massima reattività in trend confermato,
//             SC_fast = 2/(2+1) = 0.667, come raccomandato da Kaufman).
//
//   TF   Key  ATR  KAMA(N/F/S)  Rationale
//   M1   0.7   5   5/2/20  — ER su 5 min, Slow basso per micro-trade
//   M5   1.0   7   8/2/20  — ER su 40 min, ATR su 35 min
//   M15  1.2  10  10/2/30  — default Kaufman (gold standard)
//   M30  1.5  10  10/2/30  — ATR su 5 ore (1 sessione)
//   H1   2.0  14  14/2/35  — ER su 14 ore, Slow conservativo
//   H4   2.5  14  14/2/40  — massimo chop-filter su 4H
//+------------------------------------------------------------------+
void UTBotPresetsInit()
  {
   ENUM_TF_PRESET_UT preset = InpTFPreset;

   //--- AUTO: rileva il TF corrente dal chart e mappa al preset
   //--- Se il TF non è coperto (es. D1, W1), fallback a MANUAL
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

   //--- Applica i valori del preset selezionato
   //--- Ogni case imposta: Key, ATR, SrcType, KAMA, JMA, FlatMinWidth
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
         g_eff_flatMinWidth = 2.0;   // pips
         g_eff_biasTF      = PERIOD_M15;  // [v3.52] Bias HTF auto
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
         g_eff_flatMinWidth = 3.5;
         g_eff_biasTF      = PERIOD_M30;  // [v3.52] Bias HTF auto
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
         g_eff_flatMinWidth = 6.0;
         g_eff_biasTF      = PERIOD_H1;   // [v3.52] Bias HTF auto
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
         g_eff_flatMinWidth = 10.0;
         g_eff_biasTF      = PERIOD_H4;   // [v3.52] Bias HTF auto
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
         g_eff_flatMinWidth = 15.0;
         g_eff_biasTF      = PERIOD_H4;   // [v3.52] Bias HTF auto
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
         g_eff_flatMinWidth = 20.0;
         g_eff_biasTF      = PERIOD_D1;   // [v3.52] Bias HTF auto
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
         g_eff_flatMinWidth = 8.0;        // default MANUAL (override post-switch se InpFlatMinWidth>0)
         g_eff_biasTF      = InpBiasTF;   // [v3.52] MANUAL: utente decide
         break;
     }

   // Override FlatMinWidth da input se l'utente l'ha specificato (> 0).
   // Vale per TUTTI i preset (M1-H4 + MANUAL): l'input > 0 vince sempre.
   if(InpFlatMinWidth > 0.0)
      g_eff_flatMinWidth = InpFlatMinWidth;
  }

//+------------------------------------------------------------------+
//| OnInit — Inizializzazione indicatore                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Preset TF (PRIMA di tutto: determina g_eff_keyValue e g_eff_atrPeriod)
   UTBotPresetsInit();

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
   // [v4.00] Nuovi buffer: BiasGate, Chandelier, BiasContra
   SetIndexBuffer(30, B_BiasGate,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(31, B_ChandLong,     INDICATOR_DATA);
   SetIndexBuffer(32, B_ChandShort,    INDICATOR_DATA);
   SetIndexBuffer(33, B_BiasContra,    INDICATOR_DATA);
   SetIndexBuffer(34, B_BiasContraClr, INDICATOR_COLOR_INDEX);

   //--- Codici freccia per ogni plot
   PlotIndexSetInteger(1, PLOT_ARROW, 233);   // Buy1  ▲
   PlotIndexSetInteger(2, PLOT_ARROW, 233);   // Buy2  ▲
   PlotIndexSetInteger(3, PLOT_ARROW, 233);   // Buy3  ▲
   PlotIndexSetInteger(4, PLOT_ARROW, 234);   // Sell1 ▼
   PlotIndexSetInteger(5, PLOT_ARROW, 234);   // Sell2 ▼
   PlotIndexSetInteger(6, PLOT_ARROW, 234);   // Sell3 ▼
   PlotIndexSetInteger(7, PLOT_ARROW, 158);   // Caution ■ (filled square)
   PlotIndexSetInteger(15, PLOT_ARROW, 169);  // [v4.00] BiasContra ◆ (diamond)

   //--- Empty values per tutti i 13 plot
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, 0.0);          // Trail
   for(int p = 1; p <= 7; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE); // Frecce + Caution
   PlotIndexSetDouble(8,  PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Entry line
   PlotIndexSetDouble(9,  PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Flat fill
   PlotIndexSetDouble(10, PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Flat upper
   PlotIndexSetDouble(11, PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Flat lower
   PlotIndexSetDouble(12, PLOT_EMPTY_VALUE, EMPTY_VALUE);   // Candles
   PlotIndexSetDouble(13, PLOT_EMPTY_VALUE, EMPTY_VALUE);  // [v4.00] Chand Long
   PlotIndexSetDouble(14, PLOT_EMPTY_VALUE, EMPTY_VALUE);  // [v4.00] Chand Short
   PlotIndexSetDouble(15, PLOT_EMPTY_VALUE, EMPTY_VALUE);  // [v4.00] Bias Contra

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
   // [v4.00] Toggle Chandelier overlay
   if(!InpShowChandelier)
     {
      PlotIndexSetInteger(13, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(14, PLOT_DRAW_TYPE, DRAW_NONE);
     }
   // [v4.00] BiasContra markers (visibili solo se bias HTF possibile)
   if(g_htfHandle == INVALID_HANDLE)
      PlotIndexSetInteger(15, PLOT_DRAW_TYPE, DRAW_NONE);

   //--- Short name dinamico (usa g_eff_* per mostrare i valori effettivi)
   string srcStr;
   switch(g_eff_srcType)
     {
      case SRC_CLOSE: srcStr = "Close"; break;
      case SRC_HMA:   srcStr = "HMA" + IntegerToString(InpHMAPeriod); break;
      case SRC_KAMA:
         srcStr = "KAMA(" + IntegerToString(g_eff_kamaN) + "," +
                  IntegerToString(g_eff_kamaFast) + "," +
                  IntegerToString(g_eff_kamaSlow) + ")";
         break;
      case SRC_JMA:
         srcStr = "JMA(" + IntegerToString(g_eff_jmaPeriod) + "," +
                  IntegerToString(g_eff_jmaPhase) + ")";
         break;
      default: srcStr = "?"; break;
     }
   IndicatorSetString(INDICATOR_SHORTNAME,
      "UTBot3[" + DoubleToString(g_eff_keyValue, 1) + "," +
      IntegerToString(g_eff_atrPeriod) + "," + srcStr + "]");

   //--- Warmup: barre minime prima che il trailing stop sia affidabile.
   // ATR Wilder necessita ~2x period per convergere (SMA seed + ricorsione).
   // KAMA necessita N + Slow barre per stabilizzarsi.
   // HMA necessita ~3x period (WMA half + WMA full + WMA sqrt).
   // +10 barre di margine di sicurezza.
   // Usa g_eff_* (parametri effettivi) per calcolo corretto su ogni TF.
   // Warmup: massimo tra tutti i componenti + margine.
   // JMA: ~3x period per convergere Jurik Bands + 3 stadi IIR.
   g_warmup = g_eff_atrPeriod * 2 +
              MathMax(MathMax(g_eff_kamaN + g_eff_kamaSlow,
                              InpHMAPeriod * 3),
                      g_eff_jmaPeriod * 3) + 10;
   g_lastAlert = 0;
   g_entryLevel = EMPTY_VALUE;

   //--- Pre-calcola costanti JMA (una volta sola) ---
   {
      double halfLen = 0.5 * (g_eff_jmaPeriod - 1.0);
      g_jma_PR   = (g_eff_jmaPhase < -100) ? 0.5 :
                   (g_eff_jmaPhase >  100) ? 2.5 :
                   g_eff_jmaPhase / 100.0 + 1.5;
      g_jma_len1 = MathMax(MathLog(MathSqrt(halfLen)) / MathLog(2.0) + 2.0, 0.0);
      g_jma_pow1 = MathMax(g_jma_len1 - 2.0, 0.5);
      double len2 = MathSqrt(halfLen) * g_jma_len1;
      g_jma_bet  = len2 / (len2 + 1.0);
      g_jma_beta = 0.45 * (g_eff_jmaPeriod - 1.0) / (0.45 * (g_eff_jmaPeriod - 1.0) + 2.0);
   }

   //--- Inizializza handle bias HTF ---
   // Carica lo stesso indicatore su TF superiore. Legge B_State (buffer 27).
   // InpUseBias=false sull'istanza HTF evita ricorsione infinita.
   // InpApplyTheme=false: il child NON deve toccare il tema chart.
   // InpSrcType (NON g_eff_srcType): il child fa il proprio UTBotPresetsInit().
   // [v3.50] Handle HTF creato SEMPRE (se TF diverso), indipendentemente da InpUseBias.
   // Così il toggle dashboard BIAS funziona anche se InpUseBias era false all'avvio.
   // [v3.52] g_eff_biasTF: preset auto per TF (M1→M15, M5→M30, M15→H1, ecc.)
   if(_Period != g_eff_biasTF)
     {
      g_htfHandle = iCustom(_Symbol, g_eff_biasTF, "UTBotAdaptive-Ok-V1",
                            InpTFPreset,      InpKeyValue,      InpATRPeriod,
                            InpSrcType,       InpHMAPeriod,
                            InpKAMA_N,        InpKAMA_Fast,     InpKAMA_Slow,
                            InpJMA_Period,    InpJMA_Phase,
                            false, PERIOD_H1,                   // bias OFF (child)
                            false, 0.0, 0.20, 8, false,         // Flat OFF (child)
                            false, 2.5, true,                    // Chand OFF (child) [v4.00]
                            false, false,                        // ColorBars OFF, Arrows OFF
                            false, false,                        // Theme OFF, Grid OFF
                            InpThemeBG, InpThemeFG, InpThemeGrid,
                            InpThemeBullCandl, InpThemeBearCandl,
                            false, false,                        // Alert OFF
                            false, false);                       // Dashboard OFF, Trail OFF
      if(g_htfHandle == INVALID_HANDLE)
         Print("[UTBot v4.03] WARN: handle HTF bias non valido, bias disabilitato");
     }

   //--- Chart theme (anti-flash con GlobalVariables)
   if(InpApplyTheme)
     {
      string gvKey = "UTBot_" + IntegerToString(ChartID()) + "_";
      if(GlobalVariableCheck(gvKey + "BG"))
        {
         g_origBG         = (color)(long)GlobalVariableGet(gvKey + "BG");
         g_origFG         = (color)(long)GlobalVariableGet(gvKey + "FG");
         g_origGrid       = (color)(long)GlobalVariableGet(gvKey + "GRID");
         g_origChartUp    = (color)(long)GlobalVariableGet(gvKey + "CU");
         g_origChartDown  = (color)(long)GlobalVariableGet(gvKey + "CD");
         g_origChartLine  = (color)(long)GlobalVariableGet(gvKey + "CL");
         g_origCandleBull = (color)(long)GlobalVariableGet(gvKey + "CB");
         g_origCandleBear = (color)(long)GlobalVariableGet(gvKey + "CE");
         g_origBid        = (color)(long)GlobalVariableGet(gvKey + "BID");
         g_origAsk        = (color)(long)GlobalVariableGet(gvKey + "ASK");
         g_origVolume     = (color)(long)GlobalVariableGet(gvKey + "VOL");
         g_origShowGrid   = (bool)(long)GlobalVariableGet(gvKey + "GRD");
         g_origShowVolumes = (int)(long)GlobalVariableGet(gvKey + "VLS");
         g_origForeground = (bool)(long)GlobalVariableGet(gvKey + "FRG");
         GlobalVariableDel(gvKey + "BG");  GlobalVariableDel(gvKey + "FG");
         GlobalVariableDel(gvKey + "GRID"); GlobalVariableDel(gvKey + "CU");
         GlobalVariableDel(gvKey + "CD");  GlobalVariableDel(gvKey + "CL");
         GlobalVariableDel(gvKey + "CB");  GlobalVariableDel(gvKey + "CE");
         GlobalVariableDel(gvKey + "BID"); GlobalVariableDel(gvKey + "ASK");
         GlobalVariableDel(gvKey + "VOL"); GlobalVariableDel(gvKey + "GRD");
         GlobalVariableDel(gvKey + "VLS"); GlobalVariableDel(gvKey + "FRG");
        }
      else
        {
         g_origBG         = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
         g_origFG         = (color)ChartGetInteger(0, CHART_COLOR_FOREGROUND);
         g_origGrid       = (color)ChartGetInteger(0, CHART_COLOR_GRID);
         g_origChartUp    = (color)ChartGetInteger(0, CHART_COLOR_CHART_UP);
         g_origChartDown  = (color)ChartGetInteger(0, CHART_COLOR_CHART_DOWN);
         g_origChartLine  = (color)ChartGetInteger(0, CHART_COLOR_CHART_LINE);
         g_origCandleBull = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
         g_origCandleBear = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
         g_origBid        = (color)ChartGetInteger(0, CHART_COLOR_BID);
         g_origAsk        = (color)ChartGetInteger(0, CHART_COLOR_ASK);
         g_origVolume     = (color)ChartGetInteger(0, CHART_COLOR_VOLUME);
         g_origShowGrid   = (bool)ChartGetInteger(0, CHART_SHOW_GRID);
         g_origShowVolumes = (int)ChartGetInteger(0, CHART_SHOW_VOLUMES);
         g_origForeground = (bool)ChartGetInteger(0, CHART_FOREGROUND);
        }

      ChartSetInteger(0, CHART_COLOR_BACKGROUND,  InpThemeBG);
      ChartSetInteger(0, CHART_COLOR_FOREGROUND,  InpThemeFG);
      ChartSetInteger(0, CHART_COLOR_GRID,        InpThemeGrid);
      ChartSetInteger(0, CHART_COLOR_CHART_UP,    InpThemeBG);
      ChartSetInteger(0, CHART_COLOR_CHART_DOWN,  InpThemeBG);
      ChartSetInteger(0, CHART_COLOR_CHART_LINE,  InpThemeBG);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, InpThemeBullCandl);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, InpThemeBearCandl);
      ChartSetInteger(0, CHART_COLOR_BID,         C'80,80,80');
      ChartSetInteger(0, CHART_COLOR_ASK,         C'80,80,80');
      ChartSetInteger(0, CHART_COLOR_VOLUME,      C'80,80,80');
      ChartSetInteger(0, CHART_SHOW_GRID,         InpShowGrid);
      ChartSetInteger(0, CHART_SHOW_VOLUMES,      0);
      g_themeApplied = true;
     }

   //--- CHART_FOREGROUND=false: candele DRAW_COLOR_CANDLES davanti alle native
   if(!InpApplyTheme)
      g_origForeground = (bool)ChartGetInteger(0, CHART_FOREGROUND);
   ChartSetInteger(0, CHART_FOREGROUND, false);

   ChartRedraw();

   // Log completo dei parametri effettivi nel tab Experts.
   // Utile per verificare quale preset è attivo e i valori KAMA applicati.
   Print("[UTBot v4.03] Preset=", EnumToString(InpTFPreset),
         " | Key=", DoubleToString(g_eff_keyValue, 1),
         " | ATR=", g_eff_atrPeriod,
         " | Src=", EnumToString(g_eff_srcType),
         " | KAMA(", g_eff_kamaN, ",", g_eff_kamaFast, ",", g_eff_kamaSlow, ")",
         " | Warmup=", g_warmup);

   //--- Dashboard: sync toggle con input, crea oggetti, primo render
   // [v3.01 fix] g_dash_vis_trail DEVE essere sincronizzato con InpShowTrailLine.
   // In v3.00 mancava questa riga: quando l'EA host caricava l'indicatore con
   // InpShowTrailLine=false (embed mode), il plot veniva nascosto (L.637) ma
   // la dashboard mostrava "Trail Line ON" — stato incoerente.
   g_dash_vis_trail   = InpShowTrailLine;
   g_dash_vis_arrows  = InpShowArrows;
   g_dash_vis_entry   = InpShowArrows;
   g_dash_vis_candles = InpColorBars;
   // [v3.50] Init stato runtime per toggle dashboard
   g_biasEnabled       = InpUseBias;
   g_dash_vis_bias     = InpUseBias;
   g_dash_vis_flatzone = InpShowFlatZone;
   g_wasFlatPrev       = false;
   g_flatRangeHigh     = 0;
   g_flatRangeLow      = 0;
   // [v4.00] Init Chandelier state
   g_chandHH         = 0;
   g_chandLL         = 999999;   // FIX: deve essere alto per catturare low[i]
   g_chandLastLong   = 0;
   g_chandLastShort  = 999999;
   g_dash_vis_chand  = InpShowChandelier;
   if(InpShowDashboard)
     {
      InitUTBDashboard();
      UpdateUTBDashboard(true);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit — Ripristino chart theme                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpShowDashboard)
      DestroyUTBDashboard();

   if(g_htfHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_htfHandle);
      g_htfHandle = INVALID_HANDLE;
     }

   bool skipRestore = (reason == REASON_PARAMETERS || reason == REASON_CHARTCHANGE);

   if(reason == REASON_CHARTCHANGE && g_themeApplied)
     {
      string gvKey = "UTBot_" + IntegerToString(ChartID()) + "_";
      GlobalVariableSet(gvKey + "BG",   (double)(long)g_origBG);
      GlobalVariableSet(gvKey + "FG",   (double)(long)g_origFG);
      GlobalVariableSet(gvKey + "GRID", (double)(long)g_origGrid);
      GlobalVariableSet(gvKey + "CU",   (double)(long)g_origChartUp);
      GlobalVariableSet(gvKey + "CD",   (double)(long)g_origChartDown);
      GlobalVariableSet(gvKey + "CL",   (double)(long)g_origChartLine);
      GlobalVariableSet(gvKey + "CB",   (double)(long)g_origCandleBull);
      GlobalVariableSet(gvKey + "CE",   (double)(long)g_origCandleBear);
      GlobalVariableSet(gvKey + "BID",  (double)(long)g_origBid);
      GlobalVariableSet(gvKey + "ASK",  (double)(long)g_origAsk);
      GlobalVariableSet(gvKey + "VOL",  (double)(long)g_origVolume);
      GlobalVariableSet(gvKey + "GRD",  (double)(long)g_origShowGrid);
      GlobalVariableSet(gvKey + "VLS",  (double)(long)g_origShowVolumes);
      GlobalVariableSet(gvKey + "FRG",  (double)(long)g_origForeground);
     }

   if(g_themeApplied && !skipRestore)
     {
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
      g_themeApplied = false;
     }

   if(!skipRestore)
      ChartSetInteger(0, CHART_FOREGROUND, g_origForeground);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| WMAPoint — WMA su un singolo punto (building block per HMA)      |
//+------------------------------------------------------------------+
double WMAPoint(const double &src[], int i, int period)
  {
   double num = 0, den = 0;
   for(int k = 0; k < period; k++)
     {
      double w = (double)(period - k);
      num += w * src[i - k];
      den += w;
     }
   return (den > 0.0) ? num / den : src[i];
  }

//+------------------------------------------------------------------+
//| ApplyHMA — Hull Moving Average (ricalcolo completo)              |
//+------------------------------------------------------------------+
// HMA = WMA(2*WMA(close, period/2) - WMA(close, period), √period)
void ApplyHMA(const double &price[], int total, int period)
  {
   int half = MathMax(period / 2, 2);
   int sqn  = (int)MathRound(MathSqrt((double)period));

   double tmp[];
   ArrayResize(tmp, total, 0);
   ArrayInitialize(tmp, 0.0);

   for(int i = period - 1; i < total; i++)
      tmp[i] = 2.0 * WMAPoint(price, i, half) - WMAPoint(price, i, period);

   int hma_start = period + sqn - 2;
   for(int i = hma_start; i < total; i++)
      g_src[i] = WMAPoint(tmp, i, sqn);

   for(int i = 0; i < hma_start && i < total; i++)
      g_src[i] = price[i];
  }

//+------------------------------------------------------------------+
//| ApplyKAMA — Kaufman Adaptive Moving Average (calcolo completo)   |
//+------------------------------------------------------------------+
// ER = |P[i]-P[i-N]| / Σ|P[j]-P[j-1]|
// SC = (ER*(FastSC-SlowSC)+SlowSC)²
// KAMA[i] = KAMA[i-1] + SC*(P[i]-KAMA[i-1])
void ApplyKAMA(const double &price[], int total, int N, int fast, int slow)
  {
   double fc = 2.0 / (fast + 1.0);
   double sc = 2.0 / (slow + 1.0);

   for(int i = 0; i <= N && i < total; i++)
      g_src[i] = price[i];

   for(int i = N + 1; i < total; i++)
     {
      double direction = MathAbs(price[i] - price[i - N]);
      double noise     = 0.0;
      for(int k = 1; k <= N; k++)
         noise += MathAbs(price[i - k + 1] - price[i - k]);
      double er     = (noise > 0.0) ? direction / noise : 0.0;
      double smooth = MathPow(er * (fc - sc) + sc, 2.0);
      g_src[i]      = g_src[i - 1] + smooth * (price[i] - g_src[i - 1]);
     }
  }

//+------------------------------------------------------------------+
//| ApplyJMA — Jurik-style MA completa (volatilita dinamica)        |
//+------------------------------------------------------------------+
// Formula IIR 3 stadi con Jurik Bands + volatilita relativa.
// alpha cambia DINAMICAMENTE ad ogni barra: trend→piu reattivo, range→piu smooth.
//
// Fonte: Igor PDF 2008 (reverse-engineering originale)
// Verificata: mihakralj Python (match <2% vs DLL Jurik proprietary),
//             testomirka/Loxx Pine Script v5, pandas_ta dopo bugfix PR #672.
//
// Architettura:
//   1. Jurik Bands (uBand/lBand) — bande adattive che tracciano estremi
//   2. Volatilita: volty = max excursion oltre le bande
//   3. Running sum (sliding window 10 bar) + media 65 bar → rVolty
//   4. Dynamic alpha: alpha = beta^(rVolty^pow1)
//   5. IIR 3 stadi: e0 (EMA) → det0 (Kalman) → det1 (Jurik) → JMA
//
// Costanti g_jma_PR/len1/pow1/bet/beta pre-calcolate in OnInit.
// startIdx: indice da cui iniziare (per path incrementale).
//+------------------------------------------------------------------+
void ApplyJMA(const double &price[], int total, int startIdx)
  {
   int res = 500;
   if(ArraySize(g_jma_e0)    < total) ArrayResize(g_jma_e0,    total, res);
   if(ArraySize(g_jma_det0)  < total) ArrayResize(g_jma_det0,  total, res);
   if(ArraySize(g_jma_det1)  < total) ArrayResize(g_jma_det1,  total, res);
   if(ArraySize(g_jma_uBand) < total) ArrayResize(g_jma_uBand, total, res);
   if(ArraySize(g_jma_lBand) < total) ArrayResize(g_jma_lBand, total, res);
   if(ArraySize(g_jma_volty) < total) ArrayResize(g_jma_volty, total, res);
   if(ArraySize(g_jma_vSum)  < total) ArrayResize(g_jma_vSum,  total, res);

   //--- Seed (solo su fullRecalc, startIdx==0 o 1) ---
   if(startIdx <= 1)
     {
      g_src[0]        = price[0];
      g_jma_e0[0]     = price[0];
      g_jma_det0[0]   = 0.0;
      g_jma_det1[0]   = 0.0;
      g_jma_uBand[0]  = price[0];
      g_jma_lBand[0]  = price[0];
      g_jma_volty[0]  = 0.0;
      g_jma_vSum[0]   = 0.0;
      startIdx = 1;
     }

   int    sumLen = 10;
   int    avgLen = 65;

   for(int i = startIdx; i < total; i++)
     {
      double p = price[i];

      //--- STEP 1: Jurik Bands + Volatilita istantanea ---
      double del1 = p - g_jma_uBand[i - 1];
      double del2 = p - g_jma_lBand[i - 1];

      // volty = max excursion oltre le bande (0 se equidistante — edge case)
      double absD1 = MathAbs(del1);
      double absD2 = MathAbs(del2);
      double volty = (absD1 != absD2) ? MathMax(absD1, absD2) : 0.0;
      g_jma_volty[i] = volty;

      // Running sum sliding window (SumLen=10)
      int    oldIdx  = (i >= sumLen) ? (i - sumLen) : 0;
      double oldVolt = g_jma_volty[oldIdx];
      g_jma_vSum[i]  = g_jma_vSum[i - 1] + (volty - oldVolt) / (double)sumLen;

      // Media di vSum su avgLen=65 barre (SMA approssimata efficiente)
      double avgVolty = 0.0;
      int    avgStart = (i >= avgLen) ? (i - avgLen + 1) : 0;
      int    avgCount = i - avgStart + 1;
      for(int j = avgStart; j <= i; j++)
         avgVolty += g_jma_vSum[j];
      avgVolty = (avgCount > 0) ? avgVolty / (double)avgCount : 0.0;

      // Relative volatility (clampata)
      double dVolty = (avgVolty > 0.0) ? volty / avgVolty : 0.0;
      double maxRV  = MathPow(g_jma_len1, 1.0 / g_jma_pow1);
      double rVolty = MathMax(1.0, MathMin(maxRV, dVolty));

      // Dynamic power + band coefficient
      double pow2 = MathPow(rVolty, g_jma_pow1);
      double Kv   = MathPow(g_jma_bet, MathSqrt(pow2));

      // Aggiorna Jurik Bands
      g_jma_uBand[i] = (del1 > 0) ? p : p - Kv * del1;
      g_jma_lBand[i] = (del2 < 0) ? p : p - Kv * del2;

      //--- STEP 2: Dynamic alpha ---
      double alpha = MathPow(g_jma_beta, pow2);
      double a2    = alpha * alpha;
      double b2    = (1.0 - alpha) * (1.0 - alpha);

      //--- STEP 3: IIR 3 stadi ---
      // Stage 1: Adaptive EMA
      double e0 = (1.0 - alpha) * p + alpha * g_jma_e0[i - 1];
      g_jma_e0[i] = e0;

      // Stage 2: Kalman-like error correction
      double det0 = (p - e0) * (1.0 - g_jma_beta) + g_jma_beta * g_jma_det0[i - 1];
      g_jma_det0[i] = det0;
      double ma2 = e0 + g_jma_PR * det0;

      // Stage 3: Final Jurik adaptive smoothing
      double det1 = (ma2 - g_src[i - 1]) * b2 + a2 * g_jma_det1[i - 1];
      g_jma_det1[i] = det1;

      // Output JMA
      g_src[i] = g_src[i - 1] + det1;
     }
  }

//+------------------------------------------------------------------+
//| Dashboard — Helper: setta una riga di testo                      |
//+------------------------------------------------------------------+
void UTBSetRow(int row, string text, color clr, int fontSize = 8)
  {
   if(row >= UTB_DASH_MAX_ROWS)
      return;
   string name = UTB_DASH_PREFIX + "R" + IntegerToString(row, 2, '0');
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  }

//+------------------------------------------------------------------+
//| Dashboard — Helper: setta un bottone toggle ON/OFF               |
//+------------------------------------------------------------------+
void UTBSetBtn(string id, bool is_on, int y)
  {
   string name = UTB_DASH_PREFIX + "BTN_" + id;
   int btn_x = 10 + 280;
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, btn_x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, is_on ? "ON" : "OFF");
   ObjectSetInteger(0, name, OBJPROP_COLOR,        is_on ? C'220,255,220' : C'180,120,120');
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      is_on ? C'25,80,40'   : C'70,25,25');
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, is_on ? C'40,120,60'  : C'100,40,40');
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  }

//+------------------------------------------------------------------+
//| Dashboard — Ridimensiona background                              |
//+------------------------------------------------------------------+
void UTBResizeBG(int totalRows)
  {
   int y_step = 16;
   int panel_h = 28 + totalRows * y_step + 8;
   string border = UTB_DASH_PREFIX + "BORDER";
   string bg     = UTB_DASH_PREFIX + "BG";
   ObjectSetInteger(0, border, OBJPROP_YSIZE, panel_h);
   ObjectSetInteger(0, bg,     OBJPROP_YSIZE, panel_h - 6);
  }

//+------------------------------------------------------------------+
//| InitUTBDashboard — Crea tutti gli oggetti dashboard              |
//+------------------------------------------------------------------+
void InitUTBDashboard()
  {
   UTB_DASH_PREFIX = "UTB_DASH_";

   int x_base = 10, y_base = 20;
   int panel_w = 320;

   //--- Border (gold)
   string border = UTB_DASH_PREFIX + "BORDER";
   ObjectCreate(0, border, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, border, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, border, OBJPROP_XDISTANCE, x_base);
   ObjectSetInteger(0, border, OBJPROP_YDISTANCE, y_base);
   ObjectSetInteger(0, border, OBJPROP_XSIZE, panel_w);
   ObjectSetInteger(0, border, OBJPROP_YSIZE, 400);
   ObjectSetInteger(0, border, OBJPROP_BGCOLOR, C'200,180,50');
   ObjectSetInteger(0, border, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, border, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, border, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, border, OBJPROP_ZORDER, 16000);

   //--- Background (dark blue)
   string bg = UTB_DASH_PREFIX + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x_base + 3);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y_base + 3);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, panel_w - 6);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 394);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'12,20,45');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, 16001);

   //--- Label pool (20 righe)
   for(int i = 0; i < UTB_DASH_MAX_ROWS; i++)
     {
      string name = UTB_DASH_PREFIX + "R" + IntegerToString(i, 2, '0');
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x_base + 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y_base + 6 + i * 16);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, C'150,165,185');
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 16100);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
     }

   //--- Button pool (7 toggle: +CHAND v4.00)
   string btnIds[7] = {"TRAIL", "ARROWS", "ENTRY", "CANDLES", "FLAT", "BIAS", "CHAND"};
   for(int i = 0; i < 7; i++)
     {
      string name = UTB_DASH_PREFIX + "BTN_" + btnIds[i];
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 17000);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 36);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 15);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
     }
  }

//+------------------------------------------------------------------+
//| UpdateUTBDashboard — Aggiorna contenuto (throttled 500ms)        |
//+------------------------------------------------------------------+
void UpdateUTBDashboard(bool forceUpdate = false)
  {
   static uint s_lastUpdate = 0;
   uint now = GetTickCount();
   if(!forceUpdate && now - s_lastUpdate < 500)
      return;
   s_lastUpdate = now;

   int y_base = 20, y_step = 16;
   int row = 0;

   //--- HEADER ---
   UTBSetRow(row++, "UTBot v4.03 | " + _Symbol + " | " + EnumToString(_Period),
             C'70,130,255', 10);
   UTBSetRow(row++, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", C'60,70,100', 7);

   //--- STATO POSIZIONE ---
   int rt = g_dash_ratesTotal;
   if(rt >= 3)
     {
      int idx = rt - 2;   // ultima barra chiusa

      // Stato
      double stVal = B_State[idx];
      string stTxt = (stVal > 0.5)  ? "LONG  ▲" :
                     (stVal < -0.5) ? "SHORT ▼" : "NEUTRO —";
      color  stClr = (stVal > 0.5)  ? C'50,220,120' :
                     (stVal < -0.5) ? C'239,83,80'  : C'150,165,185';
      UTBSetRow(row++, "Stato:   " + stTxt, stClr);

      // Trail: valore real-time + delta dal prezzo corrente
      double trailVal = B_Trail[rt - 1];
      double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double delta    = curPrice - trailVal;
      string sign     = (delta >= 0) ? "+" : "";
      UTBSetRow(row++, "Trail:   " + DoubleToString(trailVal, _Digits) +
                "  (" + sign + DoubleToString(delta, _Digits) + ")", C'150,165,185');

      // ER: ultima barra chiusa + quality text
      double erVal = B_ER[idx];
      int    filled = (int)MathRound(erVal * 5.0);
      string erBar = "";
      for(int b = 0; b < 5; b++)
         erBar += (b < filled) ? "#" : ".";
      string erQual;
      color  erClr;
      if(erVal >= 0.60)      { erQual = "FORTE";    erClr = C'50,220,120'; }
      else if(erVal >= 0.35) { erQual = "MODERATO"; erClr = C'255,180,50'; }
      else if(erVal >= 0.15) { erQual = "DEBOLE";   erClr = C'255,235,59'; }
      else                   { erQual = "RANGING";   erClr = C'150,165,185'; }
      UTBSetRow(row++, "ER:      " + DoubleToString(erVal, 2) +
                " " + erBar + " " + erQual, erClr);

      // [v3.01] 4 nuove righe dashboard per trading live:
      //   1. ATR in pips — volatilità corrente (utile per sizing)
      //   2. Entry Level + P/L — ultimo livello di ingresso con delta dal bid
      //   3. Ultimo Segnale — direzione + quante barre fa (scan su B_Buy1/B_Sell1)
      //   4. Spread — colore semaforo (verde ≤1.5p, giallo ≤3.0p, rosso >3.0p)
      // UTB_DASH_MAX_ROWS alzato da 20 a 24 per ospitare le righe extra.

      // ATR in pips (real-time)
      double atrPrice = g_atr[rt - 1];
      double pipSize  = _Point * ((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0);
      double atrPips  = atrPrice / pipSize;
      UTBSetRow(row++, "ATR:     " + DoubleToString(atrPips, 1) + " pips", C'150,165,185');

      // Entry Level + P/L dal prezzo corrente
      if(g_entryLevel != EMPTY_VALUE)
        {
         double eDelta = curPrice - g_entryLevel;
         double eDeltaPips = eDelta / pipSize;
         string eSign  = (eDelta >= 0) ? "+" : "";
         color  eClr   = (eDelta >= 0) ? C'50,220,120' : C'239,83,80';
         UTBSetRow(row++, "Entry:   " + DoubleToString(g_entryLevel, _Digits) +
                   "  (" + eSign + DoubleToString(eDeltaPips, 1) + "p)", eClr);
        }
      else
         UTBSetRow(row++, "Entry:   ---", C'80,90,110');

      // [v3.01] Ultimo segnale: scan all'indietro da barra chiusa corrente.
      // [v3.01 fix] MathMax(g_warmup, ...) impedisce di leggere buffer nella
      // zona warmup (0..g_warmup-1) dove B_Buy1=0.0 (default MQL5) che è
      // diverso da EMPTY_VALUE(DBL_MAX), causando un falso positivo "BUY ▲".
      string lastSigTxt = "---";
      color  lastSigClr = C'80,90,110';
      for(int s = idx; s >= MathMax(g_warmup, idx - 500); s--)
        {
         if(B_Buy1[s] != EMPTY_VALUE)
           {
            lastSigTxt = "BUY ▲  " + IntegerToString(idx - s) + " barre fa";
            lastSigClr = C'50,220,120';
            break;
           }
         if(B_Sell1[s] != EMPTY_VALUE)
           {
            lastSigTxt = "SELL ▼  " + IntegerToString(idx - s) + " barre fa";
            lastSigClr = C'239,83,80';
            break;
           }
        }
      UTBSetRow(row++, "Segnale: " + lastSigTxt, lastSigClr);

      // Spread in pips (real-time)
      double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - curPrice) / pipSize;
      color  spClr = (spreadPips <= 1.5) ? C'50,220,120' :
                     (spreadPips <= 3.0) ? C'255,180,50' : C'239,83,80';
      UTBSetRow(row++, "Spread:  " + DoubleToString(spreadPips, 1) + " pips", spClr);
     }
   else
     {
      UTBSetRow(row++, "Stato:   ATTESA DATI...", C'150,165,185');
      UTBSetRow(row++, "Trail:   ---", C'150,165,185');
      UTBSetRow(row++, "ER:      ---", C'150,165,185');
      UTBSetRow(row++, "ATR:     ---", C'150,165,185');
      UTBSetRow(row++, "Entry:   ---", C'80,90,110');
      UTBSetRow(row++, "Segnale: ---", C'80,90,110');
      UTBSetRow(row++, "Spread:  ---", C'150,165,185');
     }

   //--- CONFIG ---
   UTBSetRow(row++, "━━━ CONFIG ━━━━━━━━━━━━━━━━━━━━━━━━━", C'60,70,100', 7);

   // [v3.00] Sorgente: usa g_eff_srcType (era InpSrcType in v2.01).
   // g_eff_srcType è impostato dal preset TF in UTBotPresetsInit().
   // Se il preset ha cambiato la sorgente rispetto all'input utente,
   // viene aggiunto il tag " [auto]" nel display.
   string srcStr;
   switch(g_eff_srcType)
     {
      case SRC_CLOSE: srcStr = "Close (originale)"; break;
      case SRC_HMA:   srcStr = "HMA(" + IntegerToString(InpHMAPeriod) + ")"; break;
      case SRC_KAMA:
         srcStr = "KAMA(" + IntegerToString(g_eff_kamaN) + "," +
                  IntegerToString(g_eff_kamaFast) + "," +
                  IntegerToString(g_eff_kamaSlow) + ")";
         break;
      case SRC_JMA:
         srcStr = "JMA(" + IntegerToString(g_eff_jmaPeriod) + "," +
                  IntegerToString(g_eff_jmaPhase) + ")";
         break;
      default: srcStr = "?"; break;
     }
   if(InpTFPreset != TF_PRESET_UT_MANUAL && g_eff_srcType != InpSrcType)
      srcStr += " [auto]";
   UTBSetRow(row++, "Sorgente: " + srcStr, C'150,165,185');

   // Preset
   string presetStr;
   if(InpTFPreset == TF_PRESET_UT_AUTO)
      presetStr = "AUTO " + EnumToString(_Period);
   else if(InpTFPreset == TF_PRESET_UT_MANUAL)
      presetStr = "MANUALE";
   else
      presetStr = EnumToString(InpTFPreset);
   UTBSetRow(row++, "Preset:   " + presetStr, C'150,165,185');

   // Key + ATR
   UTBSetRow(row++, "Key: " + DoubleToString(g_eff_keyValue, 1) +
             " | ATR: " + IntegerToString(g_eff_atrPeriod), C'150,165,185');

   // [v3.50] Bias HTF — usa g_biasEnabled (runtime toggle)
   if(g_biasEnabled && g_htfHandle != INVALID_HANDLE)
     {
      string htfDir = (g_lastHtfState > 0.5)  ? "LONG ▲" :
                      (g_lastHtfState < -0.5) ? "SHORT ▼" : "NEUTRO";
      color  htfClr = (g_lastHtfState > 0.5)  ? C'50,220,120' :
                      (g_lastHtfState < -0.5) ? C'239,83,80'  : C'150,165,185';
      UTBSetRow(row++, "Bias HTF: " + EnumToString(g_eff_biasTF) + " " + htfDir, htfClr);
     }
   else if(g_htfHandle != INVALID_HANDLE)
      UTBSetRow(row++, "Bias HTF: OFF (toggle)", C'80,90,110');
   else
      UTBSetRow(row++, "Bias HTF: N/A (stesso TF)", C'60,60,80');

   // [v3.00] Sezione FLAT STATUS — mostra regime corrente (FLAT/ACTIVE)
   // e channel width in pips. Legge B_FlatState[barra chiusa]:
   //   < 0.5 → FLAT (laterale, colore blu)
   //   >= 0.5 → ACTIVE (trending, colore verde)
   //--- FLAT STATUS ---
   // [v4.02] Dashboard diagnostico esteso: mostra ChWidth + ER avg con colori
   // verde/rosso per far capire quale condizione blocca la flat detection.
   if(InpFlatDetect)
     {
      int rt2 = g_dash_ratesTotal;
      if(rt2 >= 3)
        {
         double flatVal = B_FlatState[rt2 - 2];
         double cwVal   = B_ChWidth[rt2 - 2];
         double cwPips  = cwVal / (_Point * ((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0));

         // [v4.02 fix] ER mostrato = stessa media usata da detection (InpFlatERBars barre).
         // Prima era B_ER istantaneo → confusione quando regime=FLAT ma ER istantaneo > soglia.
         int flatERBarsDash = MathMax(InpFlatERBars, 1);
         double erVal = B_ER[rt2 - 2];
         if(rt2 >= (flatERBarsDash + 2))
           {
            double erSum = 0.0;
            for(int k = 0; k < flatERBarsDash; k++)
               erSum += B_ER[rt2 - 2 - k];
            erVal = erSum / flatERBarsDash;
           }

         // Soglia attiva: ATR-relativa o pips legacy
         double minPips;
         string modeTxt;
         if(InpFlatKATR > 0.0 && rt2 >= (InpFlatATRLong + 2))
           {
            double atrSum = 0.0;
            for(int k = 0; k < InpFlatATRLong; k++)
               atrSum += g_atr[rt2 - 2 - k];
            double atrLong = atrSum / InpFlatATRLong;
            double minPrice = InpFlatKATR * 2.0 * g_eff_keyValue * atrLong;
            minPips = minPrice / (_Point * ((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0));
            modeTxt = "k=" + DoubleToString(InpFlatKATR, 2) + "xATR";
           }
         else
           {
            minPips = g_eff_flatMinWidth;
            modeTxt = "pips";
           }

         if(flatVal < 0.5) // FLAT
           {
            UTBSetRow(row++, "Regime:  FLAT — laterale", C'100,150,220');
            UTBSetRow(row++, "ChWidth: " + DoubleToString(cwPips, 1) + "p < " +
                      DoubleToString(minPips, 1) + "p (" + modeTxt + ")", C'100,150,220');
            UTBSetRow(row++, "ER avg:  " + DoubleToString(erVal, 2) + " < " +
                      DoubleToString(InpFlatERThresh, 2), C'100,150,220');
           }
         else // ACTIVE
           {
            UTBSetRow(row++, "Regime:  ACTIVE — trending", C'50,220,120');
            color cwClr = (cwPips < minPips) ? C'70,200,130' : C'220,100,100';
            UTBSetRow(row++, "ChWidth: " + DoubleToString(cwPips, 1) + "p vs " +
                      DoubleToString(minPips, 1) + "p (" + modeTxt + ")", cwClr);
            color erClr = (erVal < InpFlatERThresh) ? C'70,200,130' : C'220,100,100';
            UTBSetRow(row++, "ER avg:  " + DoubleToString(erVal, 2) + " vs " +
                      DoubleToString(InpFlatERThresh, 2), erClr);
           }
        }
     }
   else
      UTBSetRow(row++, "Flat:    OFF", C'80,90,110');

   //--- VISUALS ---
   UTBSetRow(row++, "━━━ VISUALS ━━━━━━━━━━━━━━━━━━━━━━━━", C'60,70,100', 7);

   string vst;
   color  vcl;

   // Trail
   vst = g_dash_vis_trail ? "● ON" : "○ OFF";
   vcl = g_dash_vis_trail ? C'70,200,130' : C'50,70,120';
   UTBSetRow(row, "Trail Line         " + vst, vcl);
   UTBSetBtn("TRAIL", g_dash_vis_trail, y_base + 6 + row * y_step);
   row++;

   // Arrows
   vst = g_dash_vis_arrows ? "● ON" : "○ OFF";
   vcl = g_dash_vis_arrows ? C'70,200,130' : C'50,70,120';
   UTBSetRow(row, "Frecce BUY/SELL    " + vst, vcl);
   UTBSetBtn("ARROWS", g_dash_vis_arrows, y_base + 6 + row * y_step);
   row++;

   // Entry
   vst = g_dash_vis_entry ? "● ON" : "○ OFF";
   vcl = g_dash_vis_entry ? C'70,200,130' : C'50,70,120';
   UTBSetRow(row, "Entry Level        " + vst, vcl);
   UTBSetBtn("ENTRY", g_dash_vis_entry, y_base + 6 + row * y_step);
   row++;

   // Candles
   vst = g_dash_vis_candles ? "● ON" : "○ OFF";
   vcl = g_dash_vis_candles ? C'70,200,130' : C'50,70,120';
   UTBSetRow(row, "Candele Trigger    " + vst, vcl);
   UTBSetBtn("CANDLES", g_dash_vis_candles, y_base + 6 + row * y_step);
   row++;

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

   // [v4.01 fix] Chandelier overlay toggle — sempre visibile (attivabile da dashboard).
   // Era dentro if(InpShowChandelier): se input=false, pulsante nascosto → impossibile attivare.
   vst = g_dash_vis_chand ? "● ON" : "○ OFF";
   vcl = g_dash_vis_chand ? C'70,200,130' : C'50,70,120';
   UTBSetRow(row, "Chandelier         " + vst, vcl);
   UTBSetBtn("CHAND", g_dash_vis_chand, y_base + 6 + row * y_step);
   row++;

   //--- Hide unused rows
   for(int r = row; r < UTB_DASH_MAX_ROWS; r++)
     {
      string name = UTB_DASH_PREFIX + "R" + IntegerToString(r, 2, '0');
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
     }

   UTBResizeBG(row);
  }

//+------------------------------------------------------------------+
//| DestroyUTBDashboard — Elimina tutti gli oggetti dashboard        |
//+------------------------------------------------------------------+
void DestroyUTBDashboard()
  {
   if(UTB_DASH_PREFIX != "")
      ObjectsDeleteAll(0, UTB_DASH_PREFIX);
  }

//+------------------------------------------------------------------+
//| OnChartEvent — Handler bottoni dashboard                         |
//+------------------------------------------------------------------+
// [v3.00] Plot index aggiornati per 13 plot (era 5 in v2.01).
// QUESTO FIX NON ERA NELLA SPECIFICA ORIGINALE — aggiunto in fase di audit.
//   TRAIL:   Plot 0    (invariato)
//   ARROWS:  Plot 1-7  (era 1-2: solo Buy+Sell, ora Buy1-3+Sell1-3+Caution)
//   ENTRY:   Plot 8    (era 3)
//   CANDLES: Plot 12   (era 4)
// Senza questo fix, cliccare "ARROWS OFF" nascondeva solo Buy1+Buy2
// lasciando visibili Buy3, Sell1-3 e Caution.
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   string btn_prefix = UTB_DASH_PREFIX + "BTN_";
   if(StringFind(sparam, btn_prefix) != 0)
      return;

   string btn_id = StringSubstr(sparam, StringLen(btn_prefix));

   //--- TRAIL: Plot 0 DRAW_COLOR_LINE
   if(btn_id == "TRAIL")
     {
      g_dash_vis_trail = !g_dash_vis_trail;
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE,
                          g_dash_vis_trail ? DRAW_COLOR_LINE : DRAW_NONE);
     }

   //--- ARROWS: Plot 1-7 (Buy1-3, Sell1-3, Caution)
   if(btn_id == "ARROWS")
     {
      g_dash_vis_arrows = !g_dash_vis_arrows;
      int drawType = g_dash_vis_arrows ? DRAW_COLOR_ARROW : DRAW_NONE;
      for(int p = 1; p <= 7; p++)
         PlotIndexSetInteger(p, PLOT_DRAW_TYPE, drawType);
     }

   //--- ENTRY: Plot 8 DRAW_LINE
   if(btn_id == "ENTRY")
     {
      g_dash_vis_entry = !g_dash_vis_entry;
      PlotIndexSetInteger(8, PLOT_DRAW_TYPE,
                          g_dash_vis_entry ? DRAW_LINE : DRAW_NONE);
     }

   //--- CANDLES: Plot 12 DRAW_COLOR_CANDLES
   if(btn_id == "CANDLES")
     {
      g_dash_vis_candles = !g_dash_vis_candles;
      PlotIndexSetInteger(12, PLOT_DRAW_TYPE,
                          g_dash_vis_candles ? DRAW_COLOR_CANDLES : DRAW_NONE);
     }

   //--- [v3.50] FLAT: toggle visivo Plot 9-11 (fill + upper + lower)
   // Cambia solo la visibilità (DRAW_FILLING/LINE vs DRAW_NONE).
   // I buffer flat sono sempre calcolati se InpFlatDetect=true.
   if(btn_id == "FLAT")
     {
      bool wasVis = g_dash_vis_flatzone;
      g_dash_vis_flatzone = !g_dash_vis_flatzone;
      // [v3.51 fix] Reset Donchian quando toggle FLAT passa OFF→ON: evita che
      // la prossima flat zone erediti HH/LL stantii dal periodo precedente.
      if(!wasVis && g_dash_vis_flatzone)
        {
         g_wasFlatPrev   = false;
         g_flatRangeHigh = 0;
         g_flatRangeLow  = 0;
        }
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

   //--- [v4.01 fix] CHAND: toggle LOGICO + visivo Plot 13-14 (Chandelier Long + Short)
   // Era solo visivo (v4.00): nascondeva le linee ma il calcolo restava invariato.
   // Ora attiva/disattiva il calcolo Chandelier + forza fullRecalc per ricalcolare buffer.
   if(btn_id == "CHAND")
     {
      g_dash_vis_chand = !g_dash_vis_chand;
      PlotIndexSetInteger(13, PLOT_DRAW_TYPE,
                          g_dash_vis_chand ? DRAW_LINE : DRAW_NONE);
      PlotIndexSetInteger(14, PLOT_DRAW_TYPE,
                          g_dash_vis_chand ? DRAW_LINE : DRAW_NONE);
      g_forceRecalcCounter++;  // [v4.01] forza fullRecalc al prossimo tick
     }

   UpdateUTBDashboard(true);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| OnCalculate — Calcolo principale                                 |
//+------------------------------------------------------------------+
// STEP 1: ATR Wilder (RMA) con g_eff_atrPeriod
// STEP 2: Sorgente adattiva (Close/HMA/KAMA)
// STEP 3: Trailing Stop + Segnali + Visuali (con g_eff_keyValue)
// STEP 4: Alert deduplicati su barra chiusa
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

   if(ArraySize(g_src) != rates_total)
      ArrayResize(g_src, rates_total, 500);
   if(ArraySize(g_atr) != rates_total)
      ArrayResize(g_atr, rates_total, 500);

   bool fullRecalc = (prev_calculated < g_warmup + 2);
   int  start      = fullRecalc ? 1 : prev_calculated - 1;

   // [v3.50] Force fullRecalc quando dashboard toggle BIAS cambia stato.
   // g_forceRecalcCounter viene incrementato in OnChartEvent → BIAS handler.
   // Al prossimo tick, il contatore diverso da s_lastRecalcCheck forza fullRecalc.
   static int s_lastRecalcCheck = 0;
   if(g_forceRecalcCounter != s_lastRecalcCheck)
     {
      s_lastRecalcCheck = g_forceRecalcCounter;
      fullRecalc = true;
      start = 1;
     }

   // [v3.51 fix] Reset stato Donchian su OGNI fullRecalc (init, cambio TF, force-recalc).
   // In v3.50 il reset era solo nel path force-recalc → la prima flat zone dopo
   // caricamento iniziale o cambio TF ereditava HH/LL stantii.
   if(fullRecalc)
     {
      g_wasFlatPrev   = false;
      g_flatRangeHigh = 0;
      g_flatRangeLow  = 0;
     }

   //=== STEP 1: ATR Wilder (RMA) — usa g_eff_atrPeriod ===
   if(fullRecalc)
     {
      double sum = 0;
      for(int k = 1; k <= g_eff_atrPeriod; k++)
        {
         double tr = MathMax(high[k], close[k - 1]) - MathMin(low[k], close[k - 1]);
         sum += tr;
        }
      g_atr[g_eff_atrPeriod] = sum / g_eff_atrPeriod;

      for(int i = g_eff_atrPeriod + 1; i < rates_total; i++)
        {
         double tr = MathMax(high[i], close[i - 1]) - MathMin(low[i], close[i - 1]);
         g_atr[i]  = (g_atr[i - 1] * (g_eff_atrPeriod - 1) + tr) / g_eff_atrPeriod;
        }
     }
   else
     {
      for(int i = start; i < rates_total; i++)
        {
         double tr = MathMax(high[i], close[i - 1]) - MathMin(low[i], close[i - 1]);
         g_atr[i]  = (g_atr[i - 1] * (g_eff_atrPeriod - 1) + tr) / g_eff_atrPeriod;
        }
     }

   // [v3.00] STEP 2: Sorgente adattiva — usa g_eff_srcType (era InpSrcType).
   // g_eff_srcType viene impostato da UTBotPresetsInit() in base al TF:
   //   M1/M30/H1/H4 → JMA (filtra rumore, quasi zero lag)
   //   M5/M15       → KAMA (anti-whipsaw nei range intraday)
   //   MANUAL       → usa InpSrcType dell'utente
   //=== STEP 2: Sorgente adattiva ===
   switch(g_eff_srcType)
     {
      case SRC_CLOSE:
         for(int i = (fullRecalc ? 0 : start); i < rates_total; i++)
            g_src[i] = close[i];
         break;

      case SRC_HMA:
         ApplyHMA(close, rates_total, InpHMAPeriod);
         break;

      case SRC_KAMA:
         // KAMA usa i parametri effettivi g_eff_kama* (non InpKAMA_*).
         // fullRecalc: ricalcolo da zero (prima esecuzione o cambio TF).
         //   Chiama ApplyKAMA() che fa seed + loop ricorsivo completo.
         // incremental: solo le barre nuove (tick per tick).
         //   Calcola ER/SC/KAMA inline per efficienza (evita riallocare).
         //   fc_k/sc_k pre-calcolati fuori dal loop per performance.
         if(fullRecalc)
           {
            ApplyKAMA(close, rates_total, g_eff_kamaN, g_eff_kamaFast, g_eff_kamaSlow);
           }
         else
           {
            double fc_k    = 2.0 / (g_eff_kamaFast + 1.0);  // Fast SC (0.667 con Fast=2)
            double sc_k    = 2.0 / (g_eff_kamaSlow + 1.0);   // Slow SC (varia per TF)
            int kama_start = MathMax(start, g_eff_kamaN + 1);
            for(int i = kama_start; i < rates_total; i++)
              {
               // ER: quanto è "efficiente" il movimento degli ultimi N bar
               // direction = spostamento netto, noise = percorso totale
               double direction = MathAbs(close[i] - close[i - g_eff_kamaN]);
               double noise     = 0.0;
               for(int k = 1; k <= g_eff_kamaN; k++)
                  noise += MathAbs(close[i - k + 1] - close[i - k]);
               double er     = (noise > 0.0) ? direction / noise : 0.0;
               // SC: media pesata tra fc (trend) e sc (range), elevata al quadrato
               // per amplificare la distinzione trend/range (Kaufman insight)
               double smooth = MathPow(er * (fc_k - sc_k) + sc_k, 2.0);
               // Aggiornamento ricorsivo: KAMA si muove verso close di "smooth"
               g_src[i]      = g_src[i - 1] + smooth * (close[i] - g_src[i - 1]);
              }
           }
         break;

      case SRC_JMA:
         // Path incrementale: fullRecalc→da 0, altrimenti solo barre nuove.
         // ApplyJMA usa gli array di stato persistenti g_jma_*.
         ApplyJMA(close, rates_total, fullRecalc ? 0 : start);
         break;
     }

   //=== STEP 3: Trailing Stop + Segnali + Visuali — usa g_eff_keyValue ===
   int trail_start = MathMax(g_warmup, start);

   // [v3.00] fullRecalc init: inizializza la barra "seed" (trail_start-1).
   // v2.01 inizializzava B_TrailClr, B_BuyClr, B_SellClr (rinominati in v3.00).
   // v3.00 aggiunge B_FlatState=1.0 (active) e B_ChWidth=0 per i nuovi buffer.
   if(fullRecalc || B_Trail[trail_start - 1] == 0.0)
     {
      B_Trail[trail_start - 1]      = g_src[trail_start - 1];
      B_TrailClr[trail_start - 1]   = 0;
      B_Buy1Clr[trail_start - 1]    = 0;       // [v3.00] era B_BuyClr
      B_Sell1Clr[trail_start - 1]   = 0;       // [v3.00] era B_SellClr
      B_EntryLine[trail_start - 1]  = EMPTY_VALUE;
      B_ER[trail_start - 1]         = 0;
      B_State[trail_start - 1]      = 0;
      B_FlatState[trail_start - 1]  = 1.0;    // [v3.00] active by default
      B_ChWidth[trail_start - 1]    = 0;      // [v3.00] nuovo buffer
      B_BiasGate[trail_start - 1]     = EMPTY_VALUE;
      B_ChandLong[trail_start - 1]    = EMPTY_VALUE;
      B_ChandShort[trail_start - 1]   = EMPTY_VALUE;
      B_BiasContra[trail_start - 1]   = EMPTY_VALUE;
      B_BiasContraClr[trail_start - 1] = 0;
      // [v4.00] Reset stato Chandelier
      g_chandHH         = 0;
      g_chandLL         = 999999;   // FIX: deve essere alto per catturare low[i]
      g_chandLastLong   = 0;
      g_chandLastShort  = 999999;
      g_entryLevel = EMPTY_VALUE;
     }

   //--- HTF Bias — per-bar durante fullRecalc, singolo altrimenti (v3.50) ---
   // [v3.50] Durante fullRecalc, il bias va letto barra per barra dall'istanza HTF
   // per avere il backtest visivo corretto. In v3.01 il bias era letto UNA volta prima
   // del loop → tutte le barre storiche usavano il bias ODIERNO, falsando le frecce.
   // Ora si copia l'intero B_State dall'HTF e si usa iBarShift per mappare ogni barra.
   // CopyBuffer full SOLO durante fullRecalc; incrementale: solo barra chiusa corrente.
   double htfStateArr[];
   int htfCopied = 0;
   bool htfAvailable = g_biasEnabled && g_htfHandle != INVALID_HANDLE;
   double htfStateCurrent = 0.0;

   if(htfAvailable)
     {
      if(fullRecalc)
        {
         // [v3.50] Full copy per per-bar mapping (una volta per fullRecalc)
         int htfBars = iBars(_Symbol, g_eff_biasTF);
         if(htfBars > 0)
           {
            ArraySetAsSeries(htfStateArr, true);
            htfCopied = CopyBuffer(g_htfHandle, 27, 0, htfBars, htfStateArr);
           }
         if(htfCopied > 1)
            htfStateCurrent = htfStateArr[1];
        }
      else
        {
         // Incrementale: solo barra chiusa corrente (come v3.01, efficiente)
         double tmp[1];
         if(CopyBuffer(g_htfHandle, 27, 1, 1, tmp) == 1)
            htfStateCurrent = tmp[0];
        }
     }

   g_lastHtfState = htfStateCurrent;   // per dashboard
   bool biasLong  = !g_biasEnabled || (htfStateCurrent > 0.5);
   bool biasShort = !g_biasEnabled || (htfStateCurrent < -0.5);

   //═══════════════════════════════════════════════════════════════════
   //  MAIN LOOP — Per ogni barra da trail_start a rates_total-1
   //═══════════════════════════════════════════════════════════════════
   //  Pipeline per barra:
   //    (A) Trailing stop + per-bar HTF bias
   //    (B) Metriche: Efficiency Ratio + Channel Width
   //    (C) Flat detection + canale Donchian orizzontale
   //    (D) Chandelier Exit Anchored (overlay trailing alternativo)
   //    (E) Signal gating (solo su barre chiuse): bias + flat + ER
   //    (F) Carry-forward sulla barra formante (anti-repainting)
   //═══════════════════════════════════════════════════════════════════
   for(int i = trail_start; i < rates_total; i++)
     {
      double src   = g_src[i];
      double src1  = g_src[i - 1];
      double nLoss = g_eff_keyValue * g_atr[i];
      double t1    = B_Trail[i - 1];

      //─── (A.1) TRAILING STOP — Porting fedele Pine UT Bot Alerts ──
      // 4 rami: ratchet up/down in trend continuo, reset hard al flip.
      // src/src1 = sorgente adattiva (KAMA/HMA/JMA/CLOSE) della barra.
      // nLoss = KeyValue × ATR[i] = distanza stop dal prezzo.
      //───────────────────────────────────────────────────────────────
      //--- Trailing stop 4 rami (Pine-fedele, invariato) ---
      double trail;
      if(src > t1 && src1 > t1)
         trail = MathMax(t1, src - nLoss);
      else if(src < t1 && src1 < t1)
         trail = MathMin(t1, src + nLoss);
      else if(src > t1)
         trail = src - nLoss;
      else
         trail = src + nLoss;

      B_Trail[i]    = trail;
      B_TrailClr[i] = (src > trail) ? 0.0 : 1.0;

      //─── (A.2) PER-BAR HTF BIAS — Anti-repainting backtest ────────
      // In fullRecalc ogni barra storica usa il bias dell'HTF AL SUO
      // TEMPO (non quello odierno) per backtest visivo fedele.
      // iBarShift mappa il tempo LTF nell'indice HTF; +1 = barra chiusa.
      //───────────────────────────────────────────────────────────────
      // [v3.50] Per-bar HTF bias durante fullRecalc.
      // Sovrascrivi biasLong/biasShort con lo stato HTF al momento della barra i.
      // iBarShift converte il tempo LTF nell'indice HTF. +1 = barra chiusa (anti-repainting).
      // htfStateArr è in modalità series (indice 0 = barra più recente).
      if(fullRecalc && htfAvailable && htfCopied > 0)
        {
         int htfShift = iBarShift(_Symbol, g_eff_biasTF, time[i]);
         double htfBarState = 0.0;
         // [v3.51 fix] iBarShift restituisce -1 se il tempo non è trovato:
         // senza guard, htfIdx = -1+1 = 0 → legge barra formante → viola anti-repainting.
         if(htfShift >= 0)
           {
            int htfIdx = htfShift + 1; // +1 = barra chiusa HTF (anti-repainting)
            if(htfIdx < htfCopied)
               htfBarState = htfStateArr[htfIdx];
           }
         biasLong  = !g_biasEnabled || (htfBarState > 0.5);
         biasShort = !g_biasEnabled || (htfBarState < -0.5);
        }

      //═══════════════════════════════════════════════════════════════
      //  (B) METRICHE — Efficiency Ratio + Channel Width
      //═══════════════════════════════════════════════════════════════
      //  ER:       misura efficienza del prezzo (0=choppy, 1=trending)
      //  chWidth:  ampiezza del canale del trailing (2 × nLoss)
      //  Entrambi alimentano la Flat Detection qui sotto.
      //═══════════════════════════════════════════════════════════════

      //─── (B.1) EFFICIENCY RATIO (Kaufman windowed) ────────────────
      // [v3.00] Efficiency Ratio windowed (Kaufman) su close[].
      // In v2.01 l'ER era calcolato solo per SRC_KAMA (proxy |delta_src|/ATR
      // per le altre sorgenti). Ora TUTTE le sorgenti usano la formula
      // Kaufman originale: ER = |close[i] - close[i-N]| / Σ|close[k]-close[k-1]|
      // su finestra g_eff_kamaN. Misura l'efficienza del PREZZO (non del filtro),
      // quindi è indipendente dalla sorgente scelta.
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

      //─── (B.2) CHANNEL WIDTH ──────────────────────────────────────
      // Ampiezza del canale del trailing = 2 × nLoss = 2 × Key × ATR.
      // Buffer esposto per EA + input a flat detection.
      //───────────────────────────────────────────────────────────────
      // [v3.00] Channel Width = 2×nLoss. Buffer nuovo (B_ChWidth) esposto
      // per l'EA host via iCustom e usato internamente per flat detection.
      double chWidth = 2.0 * nLoss;
      B_ChWidth[i] = chWidth;

      //═══════════════════════════════════════════════════════════════
      //  (C) FLAT DETECTION — Gate doppio per mercato laterale
      //═══════════════════════════════════════════════════════════════
      //  Gate 1: chWidth < k × 2 × KeyValue × ATR_mediaN (contrazione
      //          di volatilità relativa; auto-scala simbolo/TF)
      //  Gate 2: erAvg < InpFlatERThresh (bassa efficienza)
      //  Output: B_FlatState[i] (0=flat, 1=active), isFlat.
      //  Effetti downstream:
      //    • canale Donchian azzurro disegnato (visualizzazione)
      //    • segnali BUY/SELL soppressi (signal gate)
      //═══════════════════════════════════════════════════════════════
      // [v4.02] Flat Detection — soglia ATR-relativa (auto-adattiva simbolo/TF).
      // isFlat quando chWidth[i] < k × 2 × KeyValue × ATR_medio20 ≡ volatility contraction.
      // Fallback legacy: se InpFlatKATR=0 usa g_eff_flatMinWidth in pips assoluti.
      // [v4.02 note] InpFlatATRLong è la finestra della media ATR (default 20).
      double minWidthPrice;
      if(InpFlatKATR > 0.0 && i >= InpFlatATRLong)
        {
         double atrSum = 0.0;
         for(int k = 0; k < InpFlatATRLong; k++)
            atrSum += g_atr[i - k];
         double atrLong = atrSum / InpFlatATRLong;
         minWidthPrice = InpFlatKATR * 2.0 * g_eff_keyValue * atrLong;
        }
      else
        {
         minWidthPrice = g_eff_flatMinWidth * _Point * (((_Digits == 3 || _Digits == 5) ? 10.0 : 1.0));
        }

      double erAvg = er_val;
      // [v3.01 fix] MathMax(InpFlatERBars, 1) protegge da NaN (0/0) se utente mette 0.
      int flatERBars = MathMax(InpFlatERBars, 1);
      if(InpFlatDetect && i >= flatERBars)
        {
         double erSum = 0.0;
         for(int k = 0; k < flatERBars; k++)
            erSum += B_ER[i - k];
         erAvg = erSum / flatERBars;
        }

      bool isFlat = InpFlatDetect
                 && (chWidth < minWidthPrice)
                 && (erAvg < InpFlatERThresh);
      B_FlatState[i] = isFlat ? 0.0 : 1.0;

      //─── FLAT ZONE VISUALIZATION — Donchian orizzontale ───────────
      // Disegna un rettangolo azzurro (DRAW_FILLING) + 2 linee DOT
      // bianche solo nelle barre dove isFlat=true. HH/LL congelati al
      // primo bar flat, espansi se nuovi estremi entro la lateralità.
      // EMPTY_VALUE fuori flat → MT5 interrompe il fill istantaneamente.
      //───────────────────────────────────────────────────────────────
      //--- Flat zone visualization — Donchian orizzontale (v3.50) ---
      // [v3.50] Il canale usa HH/LL persistenti dall'inizio della lateralità.
      // Le bande sono ORIZZONTALI (si espandono solo se prezzo fa nuovo HH/LL).
      // Alla fine della lateralità scompaiono istantaneamente (EMPTY_VALUE).
      // [v3.51 fix] InpShowFlatZone → g_dash_vis_flatzone: rispetta toggle dashboard.
      if(isFlat && g_dash_vis_flatzone && InpFlatDetect)
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

      //═══════════════════════════════════════════════════════════════
      //  (D) CHANDELIER EXIT ANCHORED — Trailing alternativo v4.00
      //═══════════════════════════════════════════════════════════════
      //  Overlay indipendente dal trailing principale.
      //  Anchor HH/LL riazzerato ad ogni crossover trail.
      //  Ratchet monodirezionale: Long MathMax, Short MathMin.
      //  Volatility normalization opzionale (avgATR/ATR su 50 barre).
      //  Output: B_ChandLong/B_ChandShort (Plot 13-14).
      //═══════════════════════════════════════════════════════════════
      //--- Chandelier Exit Anchored (v4.00) ---
      // Trailing dal segnale UTBot più recente. HH/LL anchor resettato ad ogni
      // crossover trail. Ratchet: Long solo sale, Short solo scende.
      // [v4.01 fix] g_dash_vis_chand = toggle runtime da dashboard.
      // Era InpShowChandelier (input immutabile): impossibile attivare da dashboard.
      if(g_dash_vis_chand)
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

         // ATR con volatility normalization opzionale
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

         // Chandelier levels con ratchet
         double chandLongVal  = g_chandHH - adjATR;
         double chandShortVal = g_chandLL + adjATR;

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

      //═══════════════════════════════════════════════════════════════
      //  (E) SIGNAL GATING — Solo barre CHIUSE (anti-repainting)
      //═══════════════════════════════════════════════════════════════
      //  Il branch `if(i < rates_total-1)` garantisce che ogni freccia
      //  BUY/SELL, ogni cambio di B_State, ogni marker BiasContra venga
      //  scritto SOLO su barre definitive. La barra formante (i ==
      //  rates_total-1) cade nel branch else più sotto (sezione F) che
      //  fa carry-forward senza ridisegnare.
      //═══════════════════════════════════════════════════════════════
      //--- ANTI-REPAINTING ---
      if(i < rates_total - 1)
        {
         //─── (E.1) SIGNAL GATES — crossover + bias HTF + flat ─────
         // isBuy/isSell effettivi:  crossover AND bias OK AND non-flat.
         // rawBuy/rawSell: crossover grezzo (senza bias) per BiasGate.
         // [v3.00] Segnali con filtro bias HTF + FLAT gate.
         // v2.01 aveva solo bias; v3.00 aggiunge "&& !isFlat" per bloccare
         // segnali durante le zone laterali rilevate dal flat detector sopra.
         bool isBuy  = (src1 < t1) && (src > trail) && biasLong  && !isFlat;
         bool isSell = (src1 > t1) && (src < trail) && biasShort && !isFlat;

         //─── (E.2) BIAS GATE (buffer esposto EA) ──────────────────
         // Tagga ogni crossover raw come con/contro bias HTF.
         // L'EA legge B_BiasGate: 1.0=apri, 0.0=solo chiudi, EMPTY=skip.
         //───────────────────────────────────────────────────────────
         // [v4.00] BiasGate: tagga il segnale come con-bias o contro-bias.
         // L'EA usa B_BiasGate per decidere: 1.0=apri trade, 0.0=solo chiudi.
         // Crossover RAW (senza bias) per rilevare segnali bloccati.
         bool rawBuy  = (src1 < t1) && (src > trail) && !isFlat;
         bool rawSell = (src1 > t1) && (src < trail) && !isFlat;

         if(rawBuy)
            B_BiasGate[i] = biasLong ? 1.0 : 0.0;
         else if(rawSell)
            B_BiasGate[i] = biasShort ? 1.0 : 0.0;
         else
            B_BiasGate[i] = EMPTY_VALUE;

         //─── (E.3) BIAS CONTRA marker ◆ ───────────────────────────
         // Segnale visivo: diamante sopra/sotto le barre con crossover
         // bloccato dal bias HTF. Utile per riconoscere "quasi-segnali".
         //───────────────────────────────────────────────────────────
         // Bias Contra marker ◆: visibile su crossover bloccati dal bias HTF.
         // !isBuy è ridondante (isBuy = rawBuy && biasLong) ma difensivo.
         if(rawBuy && !biasLong && !isBuy)
           { B_BiasContra[i] = high[i] + g_atr[i] * 0.3; B_BiasContraClr[i] = 0.0; }
         else if(rawSell && !biasShort && !isSell)
           { B_BiasContra[i] = low[i] - g_atr[i] * 0.3; B_BiasContraClr[i] = 1.0; }
         else
           { B_BiasContra[i] = EMPTY_VALUE; B_BiasContraClr[i] = 0.0; }

         //─── (E.4) MULTI-ER ARROWS — Forza segnale ────────────────
         // Impila 1-3 frecce verticali a seconda del valore ER:
         //   ≥0.60 → 3 frecce (trend forte)
         //   ≥0.35 → 2 frecce (moderato)
         //   ≥0.15 → 1 freccia (debole)
         //   <0.15 → 1 freccia + ■ caution marker
         //───────────────────────────────────────────────────────────
         // [v3.00] Sistema frecce multiple basato su ER.
         // v2.01: 1 freccia BUY + 1 freccia SELL (Plot 1-2, B_Buy/B_Sell).
         // v3.00: 7 plot arrow (Plot 1-7): Buy1/2/3, Sell1/2/3, Caution.
         //   ER >= 0.60 → 3 frecce (forte):    Buy1+Buy2+Buy3
         //   ER >= 0.35 → 2 frecce (moderato): Buy1+Buy2
         //   ER >= 0.15 → 1 freccia (debole):  Buy1
         //   ER <  0.15 → 1 freccia + ■ caution marker
         // Frecce impilate verticalmente con gap = ATR×0.35.
         // I colori variano per soglia ER (4 livelli per Buy, 4 per Sell).
         double buyBase  = low[i]  - g_atr[i] * 0.5;
         double sellBase = high[i] + g_atr[i] * 0.5;
         double arrowGap = g_atr[i] * 0.35;

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
            else if(!isBuy)
              { B_Caution[i] = EMPTY_VALUE; B_CautionClr[i] = 0.0; }
           }
         else
           {
            B_Sell1[i] = EMPTY_VALUE; B_Sell1Clr[i] = 0.0;
            B_Sell2[i] = EMPTY_VALUE; B_Sell2Clr[i] = 0.0;
            B_Sell3[i] = EMPTY_VALUE; B_Sell3Clr[i] = 0.0;
            if(!isBuy)
              { B_Caution[i] = EMPTY_VALUE; B_CautionClr[i] = 0.0; }
           }

         //─── (E.5) ENTRY LEVEL LINE ──────────────────────────────
         // Memorizza il close del segnale più recente. Plot 8 disegna
         // una riga orizzontale tratteggiata viola che persiste fino al
         // prossimo segnale. Usata per calcolare P/L live nel dashboard.
         //──────────────────────────────────────────────────────────
         //--- Entry level line ---
         if(isBuy || isSell)
            g_entryLevel = close[i];
         B_EntryLine[i] = g_entryLevel;

         //─── (E.6) B_State — STATO POSIZIONE per EA host ─────────
         // +1.0=long, -1.0=short, 0=neutro. Cambia SOLO se isBuy/isSell
         // sono effettivi (post bias+flat gate) — fix v3.52 contro
         // chiusure spurie su pullback.
         //──────────────────────────────────────────────────────────
         //--- Stato posizione (per EA) ---
         // [v3.52 fix] B_State rispetta il filtro bias HTF.
         // In v3.51 il crossover raw (src vs t1) cambiava B_State anche quando
         // il bias bloccava il segnale → l'EA chiudeva posizioni su pullback
         // piccoli contro-trend mentre l'HTF era ancora in trending.
         // Ora B_State cambia SOLO se isBuy/isSell sono effettivamente attivi.
         if(isBuy)
            B_State[i] = 1.0;
         else if(isSell)
            B_State[i] = -1.0;
         else
            B_State[i] = B_State[i - 1];

         //─── (E.7) CANDELE COLORATE ──────────────────────────────
         // 3 colori: teal (bull), coral (bear), giallo (trigger segnale).
         //──────────────────────────────────────────────────────────
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
         //═══════════════════════════════════════════════════════════
         //  (F) BARRA FORMANTE — Carry-forward anti-repainting
         //═══════════════════════════════════════════════════════════
         //  Su i == rates_total-1 (barra in formazione):
         //    • Nessuna freccia nuova (restano EMPTY_VALUE)
         //    • Entry/B_State/Chandelier → copia dal bar chiuso prec.
         //    • BiasGate/BiasContra → EMPTY_VALUE (niente segnali)
         //    • Candele → colore trail-coerente senza trigger
         //  Così il trader non vede frecce "in movimento" che cambiano
         //  posizione finché la barra non chiude.
         //═══════════════════════════════════════════════════════════
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

         // [v4.00] Barra corrente: buffer BiasGate + BiasContra = no signal
         B_BiasGate[i]      = EMPTY_VALUE;
         B_BiasContra[i]    = EMPTY_VALUE;
         B_BiasContraClr[i] = 0.0;
         // [v4.01 fix] Chandelier: carry-forward livelli confermati (non repaint).
         // Era InpShowChandelier (input immutabile) → g_dash_vis_chand (toggle runtime).
         if(g_dash_vis_chand)
           {
            B_ChandLong[i]  = (src > trail) ? g_chandLastLong  : EMPTY_VALUE;
            B_ChandShort[i] = (src < trail) ? g_chandLastShort : EMPTY_VALUE;
           }
         else
           {
            B_ChandLong[i]  = EMPTY_VALUE;
            B_ChandShort[i] = EMPTY_VALUE;
           }

         if(InpColorBars)
           {
            B_CO[i]   = open[i];
            B_CH[i]   = high[i];
            B_CL[i]   = low[i];
            B_CC[i]   = close[i];
            B_CClr[i] = (src > trail) ? 0.0 : 1.0;
           }
        }
     }

   //═══════════════════════════════════════════════════════════════════
   //  STEP 4 — ALERT DEDUPLICATI (popup + push notification)
   //═══════════════════════════════════════════════════════════════════
   //  Scatta solo su barra chiusa (rates_total-2) E solo se non è già
   //  stato triggerato su questo timestamp (g_lastAlert dedup).
   //  Controlla solo la freccia primaria Buy1/Sell1 — multi-freccia
   //  sono derivate, non aggiungono trigger distinti.
   //═══════════════════════════════════════════════════════════════════
   // [v3.00] Alert deduplicati — rinominati B_Buy→B_Buy1, B_Sell→B_Sell1
   // per coerenza con il sistema multi-freccia. La logica è invariata:
   // controlla solo la freccia primaria (Buy1/Sell1) per triggerare l'alert.
   //=== STEP 4: Alert deduplicati ===
   if(prev_calculated > 0 && rates_total >= 2)
     {
      int last = rates_total - 2;
      if(time[last] != g_lastAlert)
        {
         bool alertBuy  = (B_Buy1[last]  != EMPTY_VALUE);
         bool alertSell = (B_Sell1[last] != EMPTY_VALUE);
         if(alertBuy || alertSell)
           {
            string dir = alertBuy ? "BUY ▲" : "SELL ▼";
            string msg = "UTBot Adaptive — " + dir + "  " +
                         _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)Period());
            if(InpAlertPopup)
               Alert(msg);
            if(InpAlertPush)
               SendNotification(msg);
            g_lastAlert = time[last];
           }
        }
     }

   //--- Dashboard update (throttled 500ms)
   g_dash_ratesTotal = rates_total;
   if(InpShowDashboard)
      UpdateUTBDashboard();

   return rates_total;
  }
//+------------------------------------------------------------------+
