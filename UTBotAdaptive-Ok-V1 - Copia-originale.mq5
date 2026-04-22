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
//|   - SRC_JMA:   Jurik-style MA adattiva (quasi zero lag) [v2.00] |
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
//| COMPONENTI VISIVE (5 plot, v2.00):                               |
//|   Plot 0: Linea trailing stop colorata (teal bull / coral bear)  |
//|   Plot 1: Freccia BUY ER-colorata (verde/chiaro/giallo/grigio)  |
//|   Plot 2: Freccia SELL ER-colorata (rosso/arancio/giallo/grigio)|
//|   Plot 3: Marker entry viola (quadratino al close trigger bar)  |
//|   Plot 4: Candele colorate (teal/coral/giallo trigger)          |
//|                                                                  |
//| BUFFER ESPOSTI PER EA ESTERNI (v2.00):                           |
//|   Buffer 0:  valore trailing stop (prezzo)                       |
//|   Buffer 2:  segnale BUY (prezzo freccia o EMPTY_VALUE)          |
//|   Buffer 4:  segnale SELL (prezzo freccia o EMPTY_VALUE)         |
//|   Buffer 12: Efficiency Ratio 0.0-1.0                            |
//|   Buffer 13: stato posizione (+1.0 long, -1.0 short, 0 neutro)  |
//|                                                                  |
//+------------------------------------------------------------------+
//| CHANGELOG v2.10 — modifiche rispetto a v2.01                     |
//+------------------------------------------------------------------+
//|                                                                  |
//| Sintesi: 5 modifiche chirurgiche (A→E) + 1 fix critico (F).      |
//| Buffer map invariata (14 buffer, 5 plot). Compatibilità EA host  |
//| (Rattapignola) tramite iCustom: ZERO breaking changes.            |
//|                                                                  |
//| ── A. FRECCE MONOCROMATICHE ─────────────────────────────────── |
//|   PRIMA: BUY/SELL DRAW_COLOR_ARROW con 4 colori in base a ER     |
//|     (verde/chiaro/giallo/grigio per BUY; rosso/arancio/giallo/   |
//|     grigio per SELL). Il color index era B_BuyClr=erIdx.         |
//|   DOPO: 4 slot colore identici (verde pieno BUY, rosso pieno     |
//|     SELL). Color index forzato a 0.0 nel loop OnCalculate.       |
//|   RAZIONALE: i segnali con ER basso precedono spesso trend       |
//|     forti (breakout da range). Colorarli giallo/grigio creava    |
//|     un bias di selezione che spingeva a ignorare trade validi.   |
//|     L'ER autentico resta esposto sul buffer 12 per analisi EA.   |
//|   PUNTI MODIFICATI:                                              |
//|     - #property indicator_color2/3 (4× stesso colore)            |
//|     - Loop OnCalculate: B_BuyClr[i]=0.0, B_SellClr[i]=0.0        |
//|                                                                  |
//| ── B. ER KAUFMAN UNIFORME ──────────────────────────────────── |
//|   PRIMA: ER nel loop usava 2 formule diverse:                    |
//|     - SRC_KAMA: Kaufman autentico su close[]                      |
//|     - Altre sorgenti: proxy = min(1, |Δsrc|/ATR)                 |
//|     Il proxy non è un ER vero (range non normalizzato).           |
//|   DOPO: ER Kaufman windowed su close[] per TUTTE le sorgenti,    |
//|     finestra g_eff_kamaN. Stessa formula del calcolo KAMA.       |
//|   RAZIONALE: il buffer 12 (ER) viene letto da Rattapignola EA    |
//|     come metrica di qualità del segnale. Avere 2 scale diverse   |
//|     a seconda della sorgente rendeva la soglia (es. ER>=0.35)    |
//|     non confrontabile cross-sorgente.                            |
//|   PUNTI MODIFICATI:                                              |
//|     - Loop OnCalculate: blocco "Efficiency Ratio inline"         |
//|     - Rimossa variabile erIdx (ora unused dopo Modifica A)       |
//|                                                                  |
//| ── C. AUTO-SRCTYPE PER TIMEFRAME ───────────────────────────── |
//|   PRIMA: InpSrcType era globale (default SRC_JMA). Il preset TF  |
//|     impostava i parametri KAMA ma la sorgente rimaneva quella    |
//|     manuale dell'utente. Nessuna logica per scegliere KAMA/JMA   |
//|     in base al TF in modo automatico.                            |
//|   DOPO: nuovo input bool InpAutoSrcByTF (default true). Se ON:   |
//|     - M5 e M15 → SRC_KAMA (KAMA filtra microstorni intraday)     |
//|     - M1, M30, H1, H4 → SRC_JMA (JMA quasi-zero-lag su scalping  |
//|       ultra-veloce e su swing dove serve reattività)             |
//|     Se OFF: usa InpSrcType (rollback al comportamento v2.01).    |
//|     Nuova variabile globale g_eff_srcType (sorgente effettiva).  |
//|   RAZIONALE: M15 era il TF problematico — KAMA in v2.01 dava     |
//|     30% meno falsi segnali ma andava impostato manualmente.      |
//|     L'AUTO toglie il rischio di dimenticarsi di cambiare InpSrc  |
//|     quando si cambia chart.                                      |
//|   PUNTI MODIFICATI:                                              |
//|     - Nuovo input InpAutoSrcByTF                                 |
//|     - Default InpSrcType cambiato da SRC_JMA a SRC_KAMA (Mod E)  |
//|     - Nuova var globale g_eff_srcType                            |
//|     - UTBotPresetsInit(): ogni case TF setta g_eff_srcType       |
//|     - OnCalculate STEP 2: switch(g_eff_srcType) [era InpSrcType] |
//|     - Short name + dashboard + Print log: usano g_eff_srcType    |
//|                                                                  |
//| ── D. PRESET KAMA MULTIPLI (Standard/Middle/Slow) ──────────── |
//|   PRIMA: KAMA aveva 3 input (N/Fast/Slow) impostati dal preset   |
//|     TF o manualmente. Nessuna possibilità di switchare tra       |
//|     "reattivo" e "anti-chop" senza modificare 3 numeri.          |
//|   DOPO: nuovo enum ENUM_KAMA_PRESET con 5 valori:                |
//|     - AUTO     → M1/M5=STANDARD, M15+=MIDDLE                     |
//|     - STANDARD → (10, 2, 30)  Kaufman classico, reattivo         |
//|     - MIDDLE   → (14, 4, 50)  anti-microstorno (M15 raccomandato)|
//|     - SLOW     → (20, 6, 80)  swing filter                       |
//|     - MANUAL   → usa InpKAMA_N/Fast/Slow dell'utente             |
//|     Nuovo input InpKamaPreset (default AUTO).                    |
//|     Nuova funzione UTBotKamaPresetApply(tfPreset) chiamata da    |
//|     UTBotPresetsInit() come STEP 2 (sovrascrive kamaN/Fast/Slow).|
//|   RAZIONALE: backtesting su EURUSD M15 ha mostrato che           |
//|     KAMA(14,4,50) elimina ~60% dei segnali da microstorno (range |
//|     5-8 pip che durano <5 barre) al costo di 2-4 barre di lag    |
//|     sull'entry dei trend forti. Trade-off favorevole su signal-  |
//|     to-signal. SLOW(20,6,80) mira a swing su H1/H4 in mercati    |
//|     choppy.                                                      |
//|   PUNTI MODIFICATI:                                              |
//|     - Nuovo enum ENUM_KAMA_PRESET (5 valori)                     |
//|     - Nuovo input InpKamaPreset                                  |
//|     - Nuova funzione UTBotKamaPresetApply()                      |
//|     - UTBotPresetsInit() chiama UTBotKamaPresetApply() in coda   |
//|                                                                  |
//| ── E. DEFAULT InpSrcType = SRC_KAMA ─────────────────────────── |
//|   PRIMA: input ENUM_SRC_TYPE InpSrcType = SRC_JMA;               |
//|   DOPO:  input ENUM_SRC_TYPE InpSrcType = SRC_KAMA;              |
//|   RAZIONALE: con InpAutoSrcByTF=false (rollback), il nuovo       |
//|     default fallisce in modo "sicuro" verso KAMA che è la        |
//|     sorgente raccomandata dal documento di analisi originale.    |
//|     Effetto pratico SOLO con AutoSrcByTF=false.                  |
//|                                                                  |
//| ── F. FIX iCustom HTF BIAS (non documentato nel .md, critico) ─ |
//|   PROBLEMA: la chiamata iCustom() per il figlio HTF in OnInit    |
//|     usa argomenti POSIZIONALI. Aggiungere InpAutoSrcByTF e       |
//|     InpKamaPreset agli input sposta tutti gli input successivi   |
//|     di 2 posizioni. Senza aggiornare iCustom, su InpUseBias=true |
//|     il figlio HTF avrebbe ricevuto:                              |
//|       - InpHMAPeriod al posto di InpAutoSrcByTF                  |
//|       - InpKAMA_N al posto di InpKamaPreset                      |
//|       - shift di tutti i parametri tema/alert                    |
//|     → segnali bias completamente corrotti.                       |
//|   FIX: chiamata iCustom() aggiornata in OnInit() con i 2 nuovi   |
//|     parametri nelle posizioni corrette + commento esplicativo.   |
//|                                                                  |
//| ── COSE CHE NON SONO CAMBIATE ──────────────────────────────── |
//|   - Buffer map (14 buffer, 5 plot — invariati)                   |
//|   - Formula trailing stop (4 rami Pine-fedele)                   |
//|   - Formula segnale (isBuy = src1<t1 && src>trail && biasLong)   |
//|   - ATR Wilder (seed SMA + loop RMA)                             |
//|   - Anti-repainting (segnali su bar chiuse i<rates_total-1)      |
//|   - Compat Rattapignola via iCustom (buf 0/2/4/12/13)            |
//|                                                                  |
//| ── DEFAULT RETROCOMPATIBILI v2.01 (v2.10 fix) ─────────────── |
//|   I default delle 3 nuove opzioni sono volutamente OFF, così    |
//|   l'indicatore caricato senza modifiche ha comportamento        |
//|   IDENTICO a v2.01 sui segnali:                                  |
//|     - InpSrcType     = SRC_JMA            (default v2.01)       |
//|     - InpAutoSrcByTF = false              (opt-in)              |
//|     - InpKamaPreset  = KAMA_PRESET_MANUAL (opt-in)              |
//|   Per attivare le features v2.10 (KAMA Auto + Preset Middle):   |
//|     - InpAutoSrcByTF = true                                     |
//|     - InpKamaPreset  = KAMA_PRESET_AUTO                         |
//|   ATTENZIONE: KAMA Middle (14,4,50) su M15 può bloccare segnali |
//|   su trend forti (SC max=0.16 vs 0.44 di Standard). Testare     |
//|   sempre prima di lasciarla in produzione.                      |
//|   Note: le frecce restano monocromatiche e l'ER resta Kaufman   |
//|   uniforme (modifiche A e B non hanno toggle di rollback —      |
//|   sono cosmetica e correzione di scala). Per rollback totale    |
//|   anche di A e B: git revert del commit v2.10.                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Alessio / AcquaDulza ecosystem"
#property version   "2.10"
#property description "UT Bot Alerts — KAMA/HMA/JMA + anti-repainting + frecce monocromatiche"
#property description "v2.10: KAMA preset multipli (Standard/Middle/Slow) + ER Kaufman uniforme + Auto-SrcType per TF"
#property description "BUY/SELL su barre chiuse. Frecce verde/rosso pieno. Default M15: KAMA Middle (filtro anti-microstorno)."
#property indicator_chart_window
#property indicator_buffers 14
#property indicator_plots   5

//+------------------------------------------------------------------+
//| DEFINIZIONE DEI 5 PLOT (v2.00)                                   |
//+------------------------------------------------------------------+

// --- Plot 0: Trailing Stop Line ---
// DRAW_COLOR_LINE con 2 colori: indice 0 = teal (bull), indice 1 = coral (bear)
#property indicator_label1  "Trail Stop"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'38,166,154', C'239,83,80'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// --- Plot 1: Freccia BUY — monocromatica verde pieno (v2.10) ---
// v2.10: gradazione ER rimossa. Ogni segnale ha lo stesso peso visivo.
// Rationale: segnali con ER basso precedono spesso trend forti — colorarli
// in giallo/grigio creava bias di selezione controproducente.
// I 4 slot colore sono identici per preservare DRAW_COLOR_ARROW;
// il buffer B_BuyClr resta (buffer 3) per retrocompatibilità iCustom.
#property indicator_label2  "Buy"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_color2  C'76,175,80', C'76,175,80', C'76,175,80', C'76,175,80'
#property indicator_width2  2

// --- Plot 2: Freccia SELL — monocromatica rosso pieno (v2.10) ---
#property indicator_label3  "Sell"
#property indicator_type3   DRAW_COLOR_ARROW
#property indicator_color3  C'239,83,80', C'239,83,80', C'239,83,80', C'239,83,80'
#property indicator_width3  2

// --- Plot 3: Entry Level Line — linea orizzontale viola al livello di entrata ---
// Linea DASH al prezzo di chiusura della barra trigger. Si estende
// orizzontalmente fino al prossimo segnale BUY o SELL.
#property indicator_label4  "Entry Level"
#property indicator_type4   DRAW_LINE
#property indicator_color4  C'148,0,211'
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

// --- Plot 4: Candele colorate — 3 colori ---
// Indice 0: teal   C'38,166,154'   candela bull normale
// Indice 1: coral  C'239,83,80'    candela bear normale
// Indice 2: giallo C'255,235,59'   candela TRIGGER (barra che genera BUY o SELL)
// CHART_FOREGROUND=false richiesto per mostrare le candele sopra quelle native.
#property indicator_label5  "Candles"
#property indicator_type5   DRAW_COLOR_CANDLES
#property indicator_color5  C'38,166,154', C'239,83,80', C'255,235,59'
#property indicator_width5  1

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
//| ENUM — Preset KAMA (v2.10)                                       |
//+------------------------------------------------------------------+
// Tre configurazioni (N, Fast, Slow) calibrate per filtrare microstorni:
//   STANDARD (10,2,30):  KAMA ≈ EMA-32 su ER=0.3 — reattiva, filtro base
//   MIDDLE   (14,4,50):  KAMA ≈ EMA-91 su ER=0.3 — anti-microstorno M15
//   SLOW     (20,6,80):  KAMA ≈ EMA-188 su ER=0.3 — swing filter
//
// Trade-off: Middle ritarda 2-4 barre l'entry su trend forti (ER≈1) vs
// Standard. Per Signal-to-Signal è un prezzo accettabile per eliminare
// i falsi segnali da microstorno.
enum ENUM_KAMA_PRESET
  {
   KAMA_PRESET_AUTO     = 0,  // AUTO — rileva dal TF (M1/M5→STANDARD, M15+→MIDDLE)
   KAMA_PRESET_STANDARD = 1,  // STANDARD (10,2,30) — Kaufman default
   KAMA_PRESET_MIDDLE   = 2,  // MIDDLE (14,4,50) — anti-microstorno (raccomandato M15)
   KAMA_PRESET_SLOW     = 3,  // SLOW (20,6,80) — swing filter
   KAMA_PRESET_MANUAL   = 4   // MANUAL — usa InpKAMA_N/Fast/Slow dell'utente
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

input ENUM_SRC_TYPE   InpSrcType     = SRC_JMA;   // ⚙ Tipo sorgente (v2.10 fix: rollback a JMA per retrocompat v2.01)
input bool            InpAutoSrcByTF = false;     // [v2.10 fix] OFF di default — opt-in per attivare KAMA M5/M15
input int             InpHMAPeriod   = 14;       // HMA Period (solo se SRC_HMA)

input group "    📐 KAMA (Kaufman Adaptive)"
input ENUM_KAMA_PRESET InpKamaPreset  = KAMA_PRESET_MANUAL;  // [v2.10 fix] OFF (MANUAL) di default — attiva AUTO/STANDARD/MIDDLE/SLOW solo se serve
input int             InpKAMA_N      = 10;       // KAMA ER Period (solo se InpKamaPreset=MANUAL)
input int             InpKAMA_Fast   = 2;        // KAMA Fast EMA (solo se InpKamaPreset=MANUAL)
input int             InpKAMA_Slow   = 30;       // KAMA Slow EMA (solo se InpKamaPreset=MANUAL)

input group "    ⚡ JMA (Jurik-style — SRC_JMA)"
input int             InpJMA_Period  = 14;       // JMA Period (auto-preset)
input int             InpJMA_Phase   = 0;        // JMA Phase -100..100 (auto-preset)

input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  📡 FILTRO BIAS HTF                                      ║"
input group "╚═══════════════════════════════════════════════════════════╝"

// Legge B_State (buffer 13) dello stesso indicatore su TF superiore.
// BUY accettato solo se HTF_state=+1. SELL solo se HTF_state=-1.
// Non attivare se TF chart >= InpBiasTF (evita ricorsione).
input bool            InpUseBias     = false;       // Attiva filtro bias HTF
input ENUM_TIMEFRAMES InpBiasTF      = PERIOD_H1;   // Timeframe del bias (default H1)

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
//| BUFFER — 14 buffer totali, 5 plot (v2.00)                       |
//+------------------------------------------------------------------+
// Buf 0-1:  Plot 0 DRAW_COLOR_LINE    Trail stop + color
// Buf 2-3:  Plot 1 DRAW_COLOR_ARROW   BUY + ER color index (0-3)
// Buf 4-5:  Plot 2 DRAW_COLOR_ARROW   SELL + ER color index (0-3)
// Buf 6:    Plot 3 DRAW_LINE          Entry level line (viola, STYLE_DASH)
// Buf 7-11: Plot 4 DRAW_COLOR_CANDLES OHLC + color (0=teal,1=coral,2=giallo)
// Buf 12:   CALCULATIONS              Efficiency Ratio 0.0-1.0 (per EA)
// Buf 13:   CALCULATIONS              Stato posizione +1/-1/0 (per EA)
//
// EA extern: CopyBuffer(h,2,..) BUY | CopyBuffer(h,4,..) SELL
//            CopyBuffer(h,12,..) ER | CopyBuffer(h,13,..) State
double B_Trail[];       // buffer 0
double B_TrailClr[];    // buffer 1 (COLOR_INDEX)
double B_Buy[];         // buffer 2
double B_BuyClr[];      // buffer 3 (COLOR_INDEX: 0=verde,1=v.chiaro,2=giallo,3=grigio)
double B_Sell[];        // buffer 4
double B_SellClr[];     // buffer 5 (COLOR_INDEX: 0=rosso,1=arancio,2=giallo,3=grigio)
double B_EntryLine[];   // buffer 6 (livello entrata continuo — linea viola dash)
double B_CO[];          // buffer 7
double B_CH[];          // buffer 8
double B_CL[];          // buffer 9
double B_CC[];          // buffer 10
double B_CClr[];        // buffer 11 (COLOR_INDEX: 0=teal,1=coral,2=giallo trigger)
double B_ER[];          // buffer 12 (CALCULATIONS) Efficiency Ratio per EA
double B_State[];       // buffer 13 (CALCULATIONS) +1.0/-1.0/0.0 per EA

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
ENUM_SRC_TYPE g_eff_srcType;   // [v2.10] SrcType effettivo (auto-preset per TF)

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

//--- Dashboard (v2.00) ---
bool   g_dash_vis_trail   = true;   // Trail Stop line
bool   g_dash_vis_arrows  = true;   // Frecce BUY/SELL
bool   g_dash_vis_entry   = true;   // Entry marker viola
bool   g_dash_vis_candles = true;   // Candele colorate
string UTB_DASH_PREFIX = "UTB_DASH_";
#define UTB_DASH_MAX_ROWS 20
double g_lastHtfState     = 0.0;    // HTF state per dashboard
int    g_dash_ratesTotal  = 0;      // rates_total dall'ultimo OnCalculate

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

   //--- AUTO TF: rileva il TF corrente e mappa al preset UTBot
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

   //--- STEP 1: Applica preset UTBot (Key, ATR, JMA, SrcType auto)
   // Nota: g_eff_kamaN/Fast/Slow vengono impostati come fallback,
   //       poi sovrascritti da UTBotKamaPresetApply() se non MANUAL.
   switch(preset)
     {
      case TF_PRESET_UT_M1:
         g_eff_keyValue  = 0.7;
         g_eff_atrPeriod = 5;
         g_eff_kamaN     = 5;  g_eff_kamaFast = 2;  g_eff_kamaSlow = 20;
         g_eff_jmaPeriod = 5;
         g_eff_jmaPhase  = 0;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_M5:
         g_eff_keyValue  = 1.0;
         g_eff_atrPeriod = 7;
         g_eff_kamaN     = 8;  g_eff_kamaFast = 2;  g_eff_kamaSlow = 20;
         g_eff_jmaPeriod = 8;
         g_eff_jmaPhase  = 0;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_KAMA : InpSrcType;
         break;

      case TF_PRESET_UT_M15:
         g_eff_keyValue  = 1.2;
         g_eff_atrPeriod = 10;
         g_eff_kamaN     = 10; g_eff_kamaFast = 2;  g_eff_kamaSlow = 30;
         g_eff_jmaPeriod = 14;
         g_eff_jmaPhase  = 0;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_KAMA : InpSrcType;  // [v2.10] M15 = KAMA
         break;

      case TF_PRESET_UT_M30:
         g_eff_keyValue  = 1.5;
         g_eff_atrPeriod = 10;
         g_eff_kamaN     = 10; g_eff_kamaFast = 2;  g_eff_kamaSlow = 30;
         g_eff_jmaPeriod = 18;
         g_eff_jmaPhase  = 50;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_H1:
         g_eff_keyValue  = 2.0;
         g_eff_atrPeriod = 14;
         g_eff_kamaN     = 14; g_eff_kamaFast = 2;  g_eff_kamaSlow = 35;
         g_eff_jmaPeriod = 20;
         g_eff_jmaPhase  = 50;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_H4:
         g_eff_keyValue  = 2.5;
         g_eff_atrPeriod = 14;
         g_eff_kamaN     = 14; g_eff_kamaFast = 2;  g_eff_kamaSlow = 40;
         g_eff_jmaPeriod = 28;
         g_eff_jmaPhase  = 75;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_MANUAL:
      default:
         g_eff_keyValue  = InpKeyValue;
         g_eff_atrPeriod = InpATRPeriod;
         g_eff_kamaN     = InpKAMA_N;
         g_eff_kamaFast  = InpKAMA_Fast;
         g_eff_kamaSlow  = InpKAMA_Slow;
         g_eff_jmaPeriod = InpJMA_Period;
         g_eff_jmaPhase  = InpJMA_Phase;
         g_eff_srcType   = InpSrcType;
         break;
     }

   //--- STEP 2: Applica preset KAMA (sovrascrive kamaN/Fast/Slow se non MANUAL)
   UTBotKamaPresetApply(preset);
  }

//+------------------------------------------------------------------+
//| UTBotKamaPresetApply — Applica preset KAMA (v2.10)               |
//+------------------------------------------------------------------+
// Sovrascrive g_eff_kamaN/Fast/Slow in base a InpKamaPreset.
// Se AUTO: sceglie in base al TF
//   M1/M5  → STANDARD  (10,2,30)  — reattivo per scalping
//   M15+   → MIDDLE    (14,4,50)  — filtro anti-microstorno
// Se MANUAL: mantiene i valori già impostati dal preset TF.
//+------------------------------------------------------------------+
void UTBotKamaPresetApply(ENUM_TF_PRESET_UT tfPreset)
  {
   ENUM_KAMA_PRESET kPreset = InpKamaPreset;

   //--- AUTO: scelta preset KAMA in base al TF
   if(kPreset == KAMA_PRESET_AUTO)
     {
      switch(tfPreset)
        {
         case TF_PRESET_UT_M1:
         case TF_PRESET_UT_M5:
            kPreset = KAMA_PRESET_STANDARD;
            break;
         case TF_PRESET_UT_M15:
         case TF_PRESET_UT_M30:
         case TF_PRESET_UT_H1:
         case TF_PRESET_UT_H4:
            kPreset = KAMA_PRESET_MIDDLE;
            break;
         default:
            kPreset = KAMA_PRESET_MANUAL;
            break;
        }
     }

   //--- Applica preset
   switch(kPreset)
     {
      case KAMA_PRESET_STANDARD:
         g_eff_kamaN    = 10;
         g_eff_kamaFast = 2;
         g_eff_kamaSlow = 30;
         break;

      case KAMA_PRESET_MIDDLE:
         g_eff_kamaN    = 14;
         g_eff_kamaFast = 4;
         g_eff_kamaSlow = 50;
         break;

      case KAMA_PRESET_SLOW:
         g_eff_kamaN    = 20;
         g_eff_kamaFast = 6;
         g_eff_kamaSlow = 80;
         break;

      case KAMA_PRESET_MANUAL:
      default:
         // Non modifica: usa valori del preset TF o dell'utente
         break;
     }
  }

//+------------------------------------------------------------------+
//| OnInit — Inizializzazione indicatore                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Preset TF (PRIMA di tutto: determina g_eff_keyValue e g_eff_atrPeriod)
   UTBotPresetsInit();

   //--- Binding buffer v2.00 (14 buffer, 5 plot)
   SetIndexBuffer(0,  B_Trail,     INDICATOR_DATA);
   SetIndexBuffer(1,  B_TrailClr,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,  B_Buy,       INDICATOR_DATA);
   SetIndexBuffer(3,  B_BuyClr,    INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4,  B_Sell,      INDICATOR_DATA);
   SetIndexBuffer(5,  B_SellClr,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6,  B_EntryLine, INDICATOR_DATA);
   SetIndexBuffer(7,  B_CO,        INDICATOR_DATA);
   SetIndexBuffer(8,  B_CH,        INDICATOR_DATA);
   SetIndexBuffer(9,  B_CL,        INDICATOR_DATA);
   SetIndexBuffer(10, B_CC,        INDICATOR_DATA);
   SetIndexBuffer(11, B_CClr,      INDICATOR_COLOR_INDEX);
   SetIndexBuffer(12, B_ER,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, B_State,     INDICATOR_CALCULATIONS);

   //--- Codici freccia (plot number, NON buffer number)
   PlotIndexSetInteger(1, PLOT_ARROW, 233);   // ▲ BUY  (COLOR_ARROW)
   PlotIndexSetInteger(2, PLOT_ARROW, 234);   // ▼ SELL (COLOR_ARROW)
   // Plot 3 is now DRAW_LINE — no arrow code needed

   //--- Empty values per tutti i 5 plot
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Disabilita plot opzionali
   if(!InpColorBars)
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);   // Plot 4 = Candles
   if(!InpShowArrows)
     {
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);   // Plot 1 = BUY
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);   // Plot 2 = SELL
      PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);   // Plot 3 = Entry level
     }
   if(!InpShowTrailLine)
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);   // Plot 0 = Trail Stop

   //--- Short name dinamico (usa g_eff_* per mostrare i valori effettivi)
   // Formato: UTBot[Key,ATR,Sorgente] — i parametri KAMA effettivi sono inclusi
   // così il trader vede immediatamente quale configurazione è attiva.
   string srcStr;
   switch(g_eff_srcType)   // [v2.10] usa sorgente effettiva
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
      "UTBot[" + DoubleToString(g_eff_keyValue, 1) + "," +
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
   // Carica lo stesso indicatore su TF superiore. Legge B_State (buffer 13).
   // InpUseBias=false sull'istanza HTF evita ricorsione infinita.
   // InpApplyTheme=false: il child NON deve toccare il tema chart.
   if(InpUseBias && _Period != InpBiasTF)
     {
      // Ordine parametri iCustom: deve corrispondere ESATTAMENTE alla
      // dichiarazione degli input in testa al file.
      // [v2.10] aggiunti InpAutoSrcByTF (dopo InpSrcType) e InpKamaPreset (dopo InpHMAPeriod).
      // InpTFPreset, InpKeyValue, InpATRPeriod,
      // InpSrcType, InpAutoSrcByTF, InpHMAPeriod,
      // InpKamaPreset, InpKAMA_N, InpKAMA_Fast, InpKAMA_Slow,
      // InpJMA_Period, InpJMA_Phase,
      // InpUseBias(=false), InpBiasTF(=dummy),
      // InpColorBars(=false), InpShowArrows(=false),
      // InpApplyTheme(=false), InpShowGrid(=false),
      // InpThemeBG, InpThemeFG, InpThemeGrid,
      // InpThemeBullCandl, InpThemeBearCandl,
      // InpAlertPopup(=false), InpAlertPush(=false)
      g_htfHandle = iCustom(_Symbol, InpBiasTF, "UTBotAdaptive",
                            InpTFPreset,   InpKeyValue,   InpATRPeriod,
                            InpSrcType,    InpAutoSrcByTF,           // [v2.10]
                            InpHMAPeriod,
                            InpKamaPreset,                            // [v2.10]
                            InpKAMA_N,     InpKAMA_Fast,  InpKAMA_Slow,
                            InpJMA_Period, InpJMA_Phase,
                            false, PERIOD_H1,        // bias OFF + dummy TF
                            false, false,             // ColorBars OFF, Arrows OFF
                            false, false,             // ApplyTheme OFF, ShowGrid OFF
                            InpThemeBG,    InpThemeFG,    InpThemeGrid,
                            InpThemeBullCandl, InpThemeBearCandl,
                            false, false);            // Alert OFF, Push OFF
      if(g_htfHandle == INVALID_HANDLE)
         Print("[UTBot v2.10] WARN: handle HTF bias non valido, bias disabilitato");
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
   Print("[UTBot v2.10] TFPreset=", EnumToString(InpTFPreset),
         " | KAMAPreset=", EnumToString(InpKamaPreset),
         " | Key=", DoubleToString(g_eff_keyValue, 1),
         " | ATR=", g_eff_atrPeriod,
         " | Src=", EnumToString(g_eff_srcType),
         " | KAMA(", g_eff_kamaN, ",", g_eff_kamaFast, ",", g_eff_kamaSlow, ")",
         " | Warmup=", g_warmup);

   //--- Dashboard: sync toggle con input, crea oggetti, primo render
   g_dash_vis_arrows  = InpShowArrows;
   g_dash_vis_entry   = InpShowArrows;
   g_dash_vis_candles = InpColorBars;
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

   //--- Button pool (4 toggle: TRAIL, ARROWS, ENTRY, CANDLES)
   string btnIds[4] = {"TRAIL", "ARROWS", "ENTRY", "CANDLES"};
   for(int i = 0; i < 4; i++)
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
   UTBSetRow(row++, "UTBot v2.10 | " + _Symbol + " | " + EnumToString(_Period),
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
     }
   else
     {
      UTBSetRow(row++, "Stato:   ATTESA DATI...", C'150,165,185');
      UTBSetRow(row++, "Trail:   ---", C'150,165,185');
      UTBSetRow(row++, "ER:      ---", C'150,165,185');
     }

   //--- CONFIG ---
   UTBSetRow(row++, "━━━ CONFIG ━━━━━━━━━━━━━━━━━━━━━━━━━", C'60,70,100', 7);

   // Sorgente
   string srcStr;
   switch(g_eff_srcType)   // [v2.10] usa sorgente effettiva (coerente con short name + log)
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

   // Bias HTF
   if(InpUseBias && g_htfHandle != INVALID_HANDLE)
     {
      string htfDir = (g_lastHtfState > 0.5)  ? "LONG ▲" :
                      (g_lastHtfState < -0.5) ? "SHORT ▼" : "NEUTRO";
      color  htfClr = (g_lastHtfState > 0.5)  ? C'50,220,120' :
                      (g_lastHtfState < -0.5) ? C'239,83,80'  : C'150,165,185';
      UTBSetRow(row++, "Bias HTF: " + EnumToString(InpBiasTF) + " " + htfDir, htfClr);
     }
   else
      UTBSetRow(row++, "Bias HTF: OFF", C'80,90,110');

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

   //--- ARROWS: Plot 1,2 DRAW_COLOR_ARROW
   if(btn_id == "ARROWS")
     {
      g_dash_vis_arrows = !g_dash_vis_arrows;
      int drawType = g_dash_vis_arrows ? DRAW_COLOR_ARROW : DRAW_NONE;
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, drawType);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, drawType);
     }

   //--- ENTRY: Plot 3 DRAW_LINE
   if(btn_id == "ENTRY")
     {
      g_dash_vis_entry = !g_dash_vis_entry;
      PlotIndexSetInteger(3, PLOT_DRAW_TYPE,
                          g_dash_vis_entry ? DRAW_LINE : DRAW_NONE);
     }

   //--- CANDLES: Plot 4 DRAW_COLOR_CANDLES
   if(btn_id == "CANDLES")
     {
      g_dash_vis_candles = !g_dash_vis_candles;
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE,
                          g_dash_vis_candles ? DRAW_COLOR_CANDLES : DRAW_NONE);
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

   //=== STEP 2: Sorgente adattiva — usa g_eff_srcType (v2.10) ===
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

   if(fullRecalc || B_Trail[trail_start - 1] == 0.0)
     {
      B_Trail[trail_start - 1]      = g_src[trail_start - 1];
      B_TrailClr[trail_start - 1]   = 0;
      B_BuyClr[trail_start - 1]     = 0;
      B_SellClr[trail_start - 1]    = 0;
      B_EntryLine[trail_start - 1]  = EMPTY_VALUE;
      B_ER[trail_start - 1]         = 0;
      B_State[trail_start - 1]      = 0;
      g_entryLevel = EMPTY_VALUE;   // reset su fullRecalc
     }

   //--- Legge bias HTF una sola volta prima del loop ---
   // Offset=1: usa sempre barra chiusa del TF superiore (anti-repainting).
   double htfState = 0.0;
   if(InpUseBias && g_htfHandle != INVALID_HANDLE)
     {
      double tmp[1];
      if(CopyBuffer(g_htfHandle, 13, 1, 1, tmp) == 1)
         htfState = tmp[0];
     }
   g_lastHtfState = htfState;   // per dashboard
   bool biasLong  = !InpUseBias || (htfState > 0.5);   // +1 = accetta BUY
   bool biasShort = !InpUseBias || (htfState < -0.5);   // -1 = accetta SELL

   for(int i = trail_start; i < rates_total; i++)
     {
      double src   = g_src[i];
      double src1  = g_src[i - 1];
      double nLoss = g_eff_keyValue * g_atr[i];
      double t1    = B_Trail[i - 1];

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

      //--- Efficiency Ratio Kaufman windowed (v2.10) ---
      // ER autentico su close[] per TUTTE le sorgenti (non più proxy).
      // ER = |close[i] - close[i-N]| / Σ|close[k] - close[k-1]| su N=g_eff_kamaN
      // Range 0..1: 1 = perfettamente direzionale, 0 = totalmente choppy.
      // Misura l'efficienza del PREZZO (close), indipendente da g_eff_srcType.
      // Buffer 12 esposto all'EA host ora è coerente tra tutte le sorgenti.
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

      //--- ANTI-REPAINTING ---
      // Barre chiuse (i < rates_total-1): tutto confermato e permanente.
      // Barra corrente (i == rates_total-1): nessuna freccia, colore normale.
      if(i < rates_total - 1)
        {
         //--- Segnali con filtro bias HTF ---
         bool isBuy  = (src1 < t1) && (src > trail) && biasLong;
         bool isSell = (src1 > t1) && (src < trail) && biasShort;

         //--- Frecce monocromatiche (v2.10) ---
         // BuyClr/SellClr forzati sempre a 0 (unico colore per direzione).
         B_Buy[i]     = isBuy  ? (low[i]  - g_atr[i] * 0.5) : EMPTY_VALUE;
         B_BuyClr[i]  = 0.0;
         B_Sell[i]    = isSell ? (high[i] + g_atr[i] * 0.5) : EMPTY_VALUE;
         B_SellClr[i] = 0.0;

         //--- Entry level line: carry-forward fino al prossimo segnale ---
         if(isBuy || isSell)
            g_entryLevel = close[i];
         B_EntryLine[i] = g_entryLevel;

         //--- Stato posizione (per EA, buffer 13) ---
         if(src1 < t1 && src > t1)
            B_State[i] = 1.0;
         else if(src1 > t1 && src < t1)
            B_State[i] = -1.0;
         else
            B_State[i] = B_State[i - 1];

         //--- Candele colorate ---
         // Barra trigger (BUY o SELL): GIALLA — indice 2 = C'255,235,59'.
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
         //--- Barra corrente (aperta): zero frecce, zero marker, stato ereditato ---
         B_Buy[i]       = EMPTY_VALUE;
         B_BuyClr[i]    = 0.0;
         B_Sell[i]      = EMPTY_VALUE;
         B_SellClr[i]   = 0.0;
         B_EntryLine[i] = g_entryLevel;    // carry-forward (non repaint — livello già confermato)
         B_State[i]     = B_State[i - 1];

         //--- Barra corrente: colore normale (teal/coral), NO giallo ---
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

   //=== STEP 4: Alert deduplicati ===
   if(prev_calculated > 0 && rates_total >= 2)
     {
      int last = rates_total - 2;
      if(time[last] != g_lastAlert)
        {
         bool alertBuy  = (B_Buy[last]  != EMPTY_VALUE);
         bool alertSell = (B_Sell[last] != EMPTY_VALUE);
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
