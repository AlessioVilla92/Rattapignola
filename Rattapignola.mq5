//+------------------------------------------------------------------+
//|                                            Rattapignola.mq5      |
//|  "Il canto della campagna nelle notti d'estate."                  |
//+------------------------------------------------------------------+
//|  Copyright (C) 2026 - Rattapignola Development                   |
//|  Version: 1.5.0                                                   |
//|  Engine: UTBot Adaptive v2.13 — swappable                         |
//+------------------------------------------------------------------+
//|                                                                  |
//|  Rattapignola EA — Framework di trading modulare a 7 livelli     |
//|                                                                  |
//|  ARCHITETTURA:                                                   |
//|    Layer 0: Config    — Enums, parametri input, interfaccia eng.  |
//|    Layer 1: Core      — Variabili globali, helpers, sessioni      |
//|    Layer 2: Engine    — UTBot Adaptive v2.13 (trailing stop ATR)  |
//|             ↳ Trailing stop adattivo basato su ATR × KeyValue     |
//|             ↳ Sorgente: KAMA/HMA/JMA/Close (adattive)             |
//|             ↳ Auto-Source per TF (M5/M15→KAMA, altri→JMA)         |
//|             ↳ KAMA preset AUTO/STANDARD/MIDDLE/SLOW/MANUAL        |
//|             ↳ ER Kaufman uniforme (cross-source coerente)         |
//|             ↳ Classificazione TBS/TWS (qualita' ER)               |
//|             ↳ TF Preset espliciti (AUTO/M1/M5/M15/M30/H1/H4)      |
//|             ↳ State (+1/-1/0) e EntryLevel carry-forward          |
//|    Layer 3: Orders    — Risk manager, lot sizing, order placement |
//|             ↳ 3 risk modes (Fixed/Percent/Cash)                   |
//|             ↳ Moltiplicatore TBS/TWS lotti (TBS=2x, TWS=1x)      |
//|             ↳ Signal-to-Signal TP (flip strategy)                 |
//|             ↳ SqueezeMomentum half-peak exit (opzionale)          |
//|             ↳ Hedge Smart (HS=Magic+1, disabilitato default)      |
//|    Layer 4: Persistence — Auto-save/recovery GlobalVariables      |
//|    Layer 5: Filters   — HTF Direction Filter (multi-timeframe)    |
//|    Layer 6: Virtual   — Paper trading con P&L tracking            |
//|    Layer 7: UI        — Dashboard, overlay trail, frecce segnale  |
//|                                                                  |
//|  SEGNALI:                                                        |
//|    UTBot Adaptive — trailing stop crossover (mean reversion)      |
//|    TBS = ER forte (>= 0.35): lotto 2x                            |
//|    TWS = ER debole (< 0.35): lotto 1x                            |
//|                                                                  |
//|  TP MODES:                                                       |
//|    Signal-to-Signal — chiudi al prossimo segnale opposto (DEFAULT)|
//|    SqueezeMomentum  — half-peak exit (secondario, opzionale)      |
//|    ATR Multiple / Fixed Pips — fallback fissi                     |
//|                                                                  |
//|  STRUMENTI SUPPORTATI:                                           |
//|    Forex, Crypto (BTC/ETH), Gold, Silver, Oil, Indices, Stock CFD |
//|    Auto-detection della classe strumento dal nome simbolo          |
//|                                                                  |
//+------------------------------------------------------------------+
//|                          CHANGELOG                                |
//+------------------------------------------------------------------+
//|                                                                  |
//|  v1.5.0 — 2026-04-27 — UTBot Engine allineato a v2.13            |
//|                                                                  |
//|  Sintesi: l'engine UTBot dell'EA e' ora identico funzionalmente   |
//|  e visivamente all'indicatore standalone UTBotAdaptive-DA         |
//|  IMPLEMENTARE.mq5 v2.13. Calcoli, segnali, frecce, candele,       |
//|  entry-level, theme chart: tutto sincronizzato 1:1.               |
//|                                                                  |
//|  ── A. INPUTS & ENUMS [Config/rattEnums.mqh +                    |
//|        Config/rattInputParameters.mqh] ─────────────────────     |
//|                                                                  |
//|    1. ENUM_UTB_TF_PRESET esteso a 8 valori:                       |
//|       AUTO/M1/M5/M15/M30/H1/H4/MANUAL.                            |
//|       Permette override esplicito del preset per testing.        |
//|                                                                  |
//|    2. ENUM_KAMA_PRESET nuovo:                                     |
//|       AUTO/STANDARD(10,2,30)/MIDDLE(14,4,50)/SLOW(20,6,80)/      |
//|       MANUAL.                                                     |
//|       AUTO: M1/M5 → STANDARD, M15+ → MIDDLE (anti-microstorno).   |
//|                                                                  |
//|    3. Nuovi input opzionali:                                      |
//|       • InpAutoSrcByTF=false — auto-sorgente per TF (opt-in)      |
//|       • InpKamaPreset=MANUAL — preset KAMA flessibile              |
//|       • InpERKaufmanUniform=true — fix bug ER scale (DEFAULT ON) |
//|       • InpMonochromeArrows=false — frecce sempre verde/rosso    |
//|       • InpShowEntryLine=true — entry level multi-segment        |
//|       • InpApplyTheme=false — tema chart navy+teal (opt-in)      |
//|                                                                  |
//|  ── B. ENGINE CORE [Engine/rattUTBotEngine.mqh] ────────────     |
//|                                                                  |
//|    1. UTBPreset esteso con campo autoSrcType.                    |
//|       Tabella preset popolata: M5/M15→KAMA, altri TF→JMA.        |
//|                                                                  |
//|    2. UTBResolvePresetEnum: mappa enum input → indice tabella.   |
//|       AUTO usa Period(); M1..H4 forzano indice 0..5; MANUAL=-1.  |
//|                                                                  |
//|    3. UTBApplyKamaPreset: override KAMA params dopo TF preset.   |
//|       Allineato 1:1 a UTBotKamaPresetApply indicatore.            |
//|                                                                  |
//|    4. g_utb_srcEffective: nuova globale per sorgente effettiva.   |
//|       Settata in UTBApplyPreset/UTBApplyManual rispettando       |
//|       InpAutoSrcByTF. Tutto il codice engine + overlay legge       |
//|       questa variabile (era InpSrcType).                          |
//|                                                                  |
//|    5. FIX BUG ER: UTBCalcER ora supporta Kaufman uniforme.        |
//|       Se InpERKaufmanUniform=true → ER Kaufman su close[]         |
//|       finestra kamaN per TUTTE le sorgenti (scala 0..1 coerente). |
//|       Risolve incoerenza con soglie InpERStrong/Weak cross-src.   |
//|                                                                  |
//|    6. g_utb_state (+1/-1/0) e g_utb_entryLevel: nuove globali     |
//|       carry-forward, popolate in EngineCalculate STEP 7 e         |
//|       UTBWarmupEngine. Equivalenti a B_State/B_EntryLine          |
//|       indicatore. Esposte via sig.extraValues[5..7].              |
//|                                                                  |
//|    7. Formula segnale STEP 4 allineata a indicatore:              |
//|       (src_prev<trail_prev) && (src>trail) — rimosso fallback     |
//|       src_prev==0 ridondante grazie al warmup.                    |
//|                                                                  |
//|    8. closeLookback STEP 2 esteso a kamaN+2 quando                |
//|       InpERKaufmanUniform=true (storia sufficiente per ER).      |
//|                                                                  |
//|    9. EngineInit ordine: ResolvePresetEnum → ApplyPreset/Manual   |
//|       → ApplyKamaPreset → InitJMAConstants (se srcEff=JMA) →      |
//|       Warmup. Garantisce srcEffective noto prima di JMA warmup.   |
//|                                                                  |
//|    10. UTBWarmupEngine traccia state ed entryLevel storici per   |
//|        allineare il primo OnTick reale ai valori indicatore.     |
//|                                                                  |
//|  ── C. OVERLAY GRAFICO [UI/rattChannelOverlay.mqh] ─────────     |
//|                                                                  |
//|    1. Frecce v2.12 direzionali (no giallo/grigio):                |
//|       • InpMonochromeArrows=true → solo verde/rosso pieno         |
//|       • ER >= 0.60 → pieno (RATT_ARROW_BUY_0 / SELL_0)             |
//|       • ER <  0.60 → chiaro (RATT_ARROW_BUY_1 / SELL_1)            |
//|                                                                  |
//|    2. Entry level multi-segment OBJ_TREND dashed viola:           |
//|       Accumulo signalTimes/signalEntries durante scan storico,    |
//|       poi N segmenti consecutivi con RAY_RIGHT sull'ultimo.      |
//|       Replica B_EntryLine[] indicatore (carry-forward bar-bar).   |
//|                                                                  |
//|    3. Candele trigger gialle direttamente sul body (arrIsTrigger  |
//|       array). Eliminato rectangle separato RATT_TRIG_CDL_*       |
//|       (sostituito da color giallo nel body OBJ_RECTANGLE).        |
//|                                                                  |
//|    4. Frecce: width 2 + offset 0.5×ATR (allineati a indicatore   |
//|       indicator_width2/3 = 2 e g_atr[i]*0.5).                     |
//|                                                                  |
//|    5. ER calc nello scan storico: useKaufman = srcEff==KAMA OR    |
//|       InpERKaufmanUniform → formula identica a UTBCalcER engine.  |
//|       Lookback esteso a kamaN+5 anche per non-KAMA quando ER     |
//|       uniforme attivo.                                            |
//|                                                                  |
//|    6. Toggle visibility g_dash_show_trail/arrows/entry/candles    |
//|       gatano disegno + cleanup oggetti su disattivazione.        |
//|                                                                  |
//|  ── D. PANNELLO ENGINE [UI/rattDashboard.mqh] ──────────────     |
//|                                                                  |
//|    Pannello UTBot Engine esteso (NON sostituito) con:             |
//|     • Badge stato LONG▲/SHORT▼/NEUTRO— colorato (extraValues[5]). |
//|     • ER bar grafica con fill proporzionale (verde/ambra/dim).    |
//|     • 4 toggle button (TRAIL/ARROWS/ENTRY/CANDLES) prefisso       |
//|       RATT_DASH_TGL_, dispatcher in OnChartEvent.                |
//|     • Mostra KAMA preset, sorgente effettiva, AutoTF flag.        |
//|     • RATT_H_ENGINE 145→178px per accomodare badge + toggle.     |
//|                                                                  |
//|  ── E. THEME CHART [Config/rattVisualTheme.mqh] ────────────     |
//|                                                                  |
//|    1. SaveOriginalChartTheme/RestoreOriginalChartTheme:           |
//|       backup/restore palette chart originale al boot/deinit.      |
//|       Restore solo su REASON_REMOVE/CHART_CLOSE (no flicker su    |
//|       PARAMETERS/CHARTCHANGE/TEMPLATE).                           |
//|                                                                  |
//|    2. Costanti chart-theme dedicate (separate da palette          |
//|       Firefly dashboard) allineate 1:1 a InpThemeBG/FG/Grid:      |
//|       • RATT_CHART_THEME_BG    = C'19,23,34' (navy)              |
//|       • RATT_CHART_THEME_FG    = C'131,137,150' (testo/assi)     |
//|       • RATT_CHART_THEME_GRID  = C'42,46,57'                     |
//|       Le candele native vengono nascoste con stesso bg chart       |
//|       (invisibili sotto i nostri OBJ_RECTANGLE).                  |
//|                                                                  |
//|    3. ApplyChartTheme gateato in OnInit con:                      |
//|       if(InpApplyTheme || ColorCandlesByTrend) → applica.        |
//|       Default opt-in (InpApplyTheme=false): l'utente sceglie.    |
//|                                                                  |
//|  ── F. CLEANUP DEAD CODE ────────────────────────────────────    |
//|                                                                  |
//|    Rimossi 4 elementi obsoleti (~70 righe):                       |
//|     • Macro alias frecce RATT_ARROW_*_2/_3 (no usi)               |
//|     • Input deprecato HsCloseOnSoupProfit (v1.7.2 deprecation)    |
//|     • Funzione UTBWarmupJMA() (sostituita da UTBWarmupEngine)    |
//|     • Globale g_utb_atrHandle (handle iATR mai usato per         |
//|       CopyBuffer — calcolo ATR Wilder e' manuale)                 |
//|     • Warning compile ArraySetAsSeries su array static fixato.    |
//|                                                                  |
//|  ── COMPATIBILITA' ───────────────────────────────────────────    |
//|                                                                  |
//|  Contratto EngineSignal IMMUTABILE: i nuovi dati (state,          |
//|  entryLevel, srcEffective) vanno in extraValues[5..7]. Layer       |
//|  Orders/Filters/Persistence/Virtual/UI invariati a livello API.    |
//|  HTF Filter (rattHTFFilter) NON toccato — e' un layer separato    |
//|  framework, non la ricorsione iCustom rimossa in indicatore v2.11.|
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"
#property version   "1.50"
#property description "Rattapignola EA v1.5.0 — UTBot Adaptive v2.13"
#property description "Engine UTBot allineato 1:1 a UTBotAdaptive-DA IMPLEMENTARE v2.13"
#property description "Auto-Source TF (M5/M15=KAMA), KAMA preset AUTO/STD/MID/SLOW"
#property description "ER Kaufman uniforme cross-source, frecce v2.12 direzionali"
#property description "Entry level multi-segment carry-forward, theme chart opt-in"
#property description "TP: Signal-to-Signal (flip strategy) | Anti-repaint: bar[1] only"
#property strict

//+------------------------------------------------------------------+
//| RENDERING DIRETTO v1.5.0                                         |
//|                                                                  |
//| L'EA disegna direttamente TUTTA la grafica trend/segnali:        |
//|  - Candele colorate per trend (OBJ_RECTANGLE body + OBJ_TREND   |
//|    wick) — teal bull, coral bear, giallo trigger su segnale     |
//|  - Trail line teal/coral (OBJ_TREND segmenti, width 2)          |
//|  - Frecce BUY/SELL direzionali (OBJ_ARROW codice 233/234,        |
//|    width 2, offset 0.5 × ATR — allineato a indicatore v2.13)    |
//|  - Entry level dashed viola multi-segment carry-forward          |
//|    (OBJ_TREND con STYLE_DASH e RAY_RIGHT su ultimo segmento)     |
//|  - Dashboard + control buttons + TP markers + HS markers         |
//|  - Pannello Engine v2.13: badge stato + ER bar + 4 toggle button |
//|                                                                  |
//| Le candele native MT5 vengono nascoste via ApplyChartTheme       |
//| (CHART_COLOR_CANDLE_*/CHART_UP/DOWN = RATT_CHART_THEME_BG).      |
//| Palette chart allineata a InpThemeBG/FG/Grid indicatore.         |
//| I calcoli (ATR Wilder, trail, sorgente, ER, state, entryLevel)   |
//| sono identici 1:1 a UTBotAdaptive-DA IMPLEMENTARE.mq5 v2.13.    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| INCLUDE MODULES — Ordine di dipendenza rigoroso                  |
//+------------------------------------------------------------------+

// === Layer 0: Config ===
#include "Config/rattEnums.mqh"
#include "Config/rattEngineInterface.mqh"
#include "Config/rattInputParameters.mqh"

// === Layer 1: Core + Utilities ===
#include "Core/rattGlobalVariables.mqh"
#include "Utilities/rattHelpers.mqh"
#include "Config/rattInstrumentConfig.mqh"    // Multi-prodotto: detect + preset strumento
#include "Core/rattBrokerValidation.mqh"
#include "Core/rattSessionManager.mqh"

// === Layer 2: Engine (SWAPPABLE — UTBot Adaptive) ===
#include "Engine/rattUTBotEngine.mqh"

// === Layer 3: Orders ===
#include "Orders/rattATRCalculator.mqh"
#include "Orders/rattRiskManager.mqh"
#include "Orders/rattOrderManager.mqh"
#include "Orders/rattCycleManager.mqh"
#include "Orders/rattHedgeManager.mqh"   // Layer 3.5: Hedge Smart Engine (disabilitato default)

// === Layer 4: Persistence ===
#include "Persistence/rattStatePersistence.mqh"
#include "Persistence/rattRecoveryManager.mqh"

// === Layer 5: Filters ===
#include "Filters/rattHTFFilter.mqh"

// === Layer 6: Virtual ===
#include "Virtual/rattVirtualTrader.mqh"

// === Layer 7: UI ===
#include "UI/rattControlButtons.mqh"
#include "UI/rattDashboard.mqh"
#include "UI/rattChannelOverlay.mqh"
#include "UI/rattSignalMarkers.mqh"

//+------------------------------------------------------------------+
//| UTBotAdaptive embedded indicator — handle & helpers              |
//|                                                                  |
//| Indicatore caricato in modalita' "solo grafica": viene aggiunto  |
//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_UninitReason == REASON_CHARTCHANGE)
      AdLogI(LOG_CAT_INIT, StringFormat("RE-INIT: TF changed -> %s", EnumToString(Period())));

   AdLogI(LOG_CAT_INIT, "=======================================================");
   AdLogI(LOG_CAT_INIT, StringFormat("RATTAPIGNOLA EA v%s — Symbol: %s | TF: %s",
          EA_VERSION, _Symbol, EnumToString(Period())));
   AdLogI(LOG_CAT_INIT, "Engine: UTBot Adaptive (Trailing Stop ATR)");
   AdLogI(LOG_CAT_INIT, StringFormat("Magic: %d | Entry: %s | Risk: %s",
          MagicNumber, EnumToString(EntryMode), EnumToString(RiskMode)));
   AdLogI(LOG_CAT_INIT, "=======================================================");

   g_systemState = STATE_INITIALIZING;
   g_systemStartTime = TimeCurrent();

   // Dashboard e tema prima di tutto — visibile anche in caso di errore
   // [v2.13] Tema chart applicato solo se InpApplyTheme=true (opt-in).
   //   Se ColorCandlesByTrend=true, ApplyChartTheme nasconde anche le candele
   //   native — necessario per evitare che si vedano sotto i nostri rectangle.
   //   Quindi se l'utente vuole ColorCandlesByTrend, di fatto deve attivare
   //   anche InpApplyTheme (fail-safe: applichiamo lo stesso, log warning).
   if(InpApplyTheme || ColorCandlesByTrend)
   {
      SaveOriginalChartTheme();
      ApplyChartTheme();
      g_themeApplied = true;
      if(!InpApplyTheme && ColorCandlesByTrend)
         AdLogW(LOG_CAT_INIT, "ApplyTheme=false ma ColorCandlesByTrend=true: tema applicato per nascondere candele native");
   }
   ObjectsDeleteAll(0, "UTB_DASH_");  // Pulizia residui indicatore standalone

   CreateDashboard();

   if(!EnableSystem)
   {
      g_systemState = STATE_IDLE;
      AdLogI(LOG_CAT_SYSTEM, "System DISABLED by user");
      UpdateDashboard();
      return INIT_SUCCEEDED;
   }

   // 1. Broker specifications
   if(!LoadBrokerSpecifications())
   {
      AdLogE(LOG_CAT_INIT, "FAILED: LoadBrokerSpecifications");
      g_systemState = STATE_ERROR;
      UpdateDashboard();
      return INIT_SUCCEEDED;
   }

   // 1b. Instrument classification: detect/apply pip scaling + preset parametri
   //     DEVE girare dopo LoadBrokerSpecifications (usa g_symbolPoint, g_symbolDigits)
   //     e PRIMA di SetupTradeObject (che usa g_inst_slippage)
   InstrumentPresetsInit();

   // 2. Trade object (usa g_inst_slippage per SetDeviationInPoints)
   SetupTradeObject();

   // 3. Validate inputs
   if(!ValidateInputParameters())
   {
      AdLogE(LOG_CAT_INIT, "FAILED: ValidateInputParameters");
      g_systemState = STATE_ERROR;
      UpdateDashboard();
      return INIT_SUCCEEDED;
   }

   // 4. ATR
   if(!InitializeATR())
   {
      AdLogE(LOG_CAT_INIT, "FAILED: InitializeATR");
      g_systemState = STATE_ERROR;
      UpdateDashboard();
      return INIT_SUCCEEDED;
   }

   // 5. Engine init (UTBot: handle iATR, preset, sorgente adattiva)
   if(!EngineInit())
   {
      AdLogE(LOG_CAT_INIT, "FAILED: EngineInit");
      g_systemState = STATE_ERROR;
      UpdateDashboard();
      return INIT_SUCCEEDED;
   }
   g_engineReady = true;
   g_initialDrawDone = false;

   // 5b. Draw channel overlay + trend candles + historical signals
   DrawChannelOverlay();
   ChartRedraw();

   // 6. Initialize cycles array
   InitializeCycles();

   // 7. Session manager
   InitializeSessionManager();

   // 8. Risk manager
   InitializeRiskManager();

   // 8b. Hedge Engine
   if(EnableHedge) HedgeInit();

   // 9. HTF filter
   if(UseHTFFilter)
      InitializeHTFFilter();

   // 10. Recovery: stato salvato, poi scan broker
   if(HasSavedState())
   {
      AdLogI(LOG_CAT_INIT, "Saved state found — restoring...");
      if(RestoreState())
         AdLogI(LOG_CAT_INIT, "State restored from GlobalVariables");
      else
      {
         AdLogW(LOG_CAT_INIT, "Restore failed — falling back to broker scan");
         AttemptRecovery();
      }
   }
   else
   {
      AttemptRecovery();
   }

   // 11. Timer per auto-save
   EventSetTimer(1);  // 1s initially for overlay retry, then 60s

   // Fresh start: sistema parte IDLE — utente deve premere START
   if(!g_recoveryPerformed && g_systemState == STATE_INITIALIZING)
   {
      g_systemState = STATE_IDLE;
      AdLogI(LOG_CAT_INIT, "State: INITIALIZING -> IDLE (press START)");
   }

   UpdateDashboard();

   // Feed: engine ready
   if(_UninitReason == REASON_CHARTCHANGE)
      AddFeedItem("TF changed -> " + EnumToString(Period()), RATT_FIREFLY);
   AddFeedItem("Engine UTBot ready · " + EnumToString(Period()), RATT_FIREFLY);
   if(g_systemState == STATE_IDLE)
      AddFeedItem("Press START to begin trading", RATT_AMBER);

   AdLogI(LOG_CAT_INIT, StringFormat("RATTAPIGNOLA ready — %s",
          g_recoveryPerformed ? "RECOVERED" : "IDLE (press START)"));

   Alert(StringFormat("Rattapignola AVVIATO | %s %s | Magic=%d | %s",
         _Symbol, EnumToString(Period()), MagicNumber,
         g_recoveryPerformed ? "RECOVERED" : "Premi START per attivare"));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(reason == REASON_CHARTCHANGE)
      AdLogI(LOG_CAT_SYSTEM, "DEINIT: Timeframe change — releasing handles");

   // Salva stato prima di uscire
   if(reason == REASON_REMOVE && ClearStateOnRemove)
   {
      ClearSavedState();
      AdLogI(LOG_CAT_SYSTEM, "State cleared (EA removed)");
   }
   else
   {
      SaveState();
      AdLogI(LOG_CAT_PERSIST, "State saved on deinit");
   }

   // Rilascio risorse
   EngineDeinit();
   g_engineReady = false;

   if(EnableHedge) HedgeDeinit();
   ReleaseATRHandle();

   // UI cleanup
   CleanupOverlay();
   CleanupSignalMarkers();
   DestroyDashboard();

   // [v2.13] Ripristina tema chart originale solo su REMOVE/CHART_CLOSE.
   //   Su CHARTCHANGE/PARAMETERS/TEMPLATE l'EA si reinizializzera' subito,
   //   il restore causerebbe flicker visivo inutile.
   if(g_themeApplied
      && reason != REASON_PARAMETERS
      && reason != REASON_CHARTCHANGE
      && reason != REASON_TEMPLATE)
   {
      RestoreOriginalChartTheme();
      AdLogI(LOG_CAT_SYSTEM, "Chart theme restored to original");
   }

   EventKillTimer();
   AdLogI(LOG_CAT_SYSTEM, StringFormat("DEINIT — Reason: %d", reason));

   if(reason == REASON_REMOVE)
      Alert(StringFormat("Rattapignola RIMOSSO | %s %s", _Symbol, EnumToString(Period())));
   else if(reason == REASON_CHARTCHANGE)
      Alert(StringFormat("Rattapignola TF CAMBIATO | %s %s", _Symbol, EnumToString(Period())));
   else
      Alert(StringFormat("Rattapignola FERMATO | %s %s | Reason=%d", _Symbol, EnumToString(Period()), reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ── 1. DASHBOARD + LIVE EDGE UPDATE (throttle 500ms) ────────────
   static uint lastDashUpdate = 0;
   uint now = GetTickCount();
   if(now - lastDashUpdate > 500)
   {
      lastDashUpdate = now;
      UpdateDashboard();
      if(g_engineReady)
         UpdateChannelLiveEdge();
   }

   // ── 1b. CHANNEL OVERLAY (full redraw su nuova barra) ─────────────
   if(g_engineReady && IsNewBarOverlay())
   {
      DrawChannelOverlay();
      ChartRedraw();
   }

   // ── 2. VIRTUAL MONITOR (ogni tick, qualsiasi stato) ──────────────
   if(VirtualMode)
      VirtualMonitor();

   // ── 3. GATE: solo se ACTIVE + Engine pronto ──────────────────────
   if(g_systemState != STATE_ACTIVE) return;
   if(!g_engineReady) return;

   // ── 4. SESSION FILTER ────────────────────────────────────────────
   if(EnableSessionFilter && !IsWithinSession())
   {
      // DIAG: log periodico quando sessione blocca (max 1 ogni 5 min = 300s)
      // Throttle 300s: evita spam nel journal (sessione fuori orario puo'
      // durare ore, senza throttle loggerebbe ad ogni tick per tutta la durata)
      static datetime lastSessBlockLog = 0;
      datetime nowDT = TimeCurrent();
      if(nowDT - lastSessBlockLog > 300)
      {
         MqlDateTime dtSess;
         TimeToStruct(nowDT, dtSess);
         AdLogD(LOG_CAT_SESSION, StringFormat("DIAG SESSION BLOCKED: %s | h=%02d:%02d",
                g_currentSessionName, dtSess.hour, dtSess.min));
         lastSessBlockLog = nowDT;
      }
      HandleSessionEnd();
      return;
   }

   // ── 5. NEW BAR GATE ──────────────────────────────────────────────
   if(!IsNewBar()) return;

   AdLogI(LOG_CAT_SYSTEM, StringFormat("NEW BAR %s | Bid=%s | Cycles=%d/%d",
          TimeToString(iTime(_Symbol, PERIOD_CURRENT, 0), TIME_DATE|TIME_MINUTES),
          DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits),
          CountActiveCycles(), MaxConcurrentTrades));

   // ── 6. ATR UPDATE ────────────────────────────────────────────────
   UpdateATR();
   UpdateEquityTracking();

   // ── 7. ENGINE: calcola trail + segnali su bar[1] (anti-repaint) ─
   EngineSignal sig;
   sig.Reset();
   bool hasSignal = EngineCalculate(sig);
   g_lastSignal = sig;

   // ── 8. (LTF CHECK rimosso — UTBot non ha LTF entry) ─────────────

   // ── 10. PROCESS SIGNAL ────────────────────────────────────────────
   if(hasSignal && sig.isNewSignal && sig.direction != 0)
   {
      // Pre-trade checks (spread + daily loss checked inside PerformRiskChecks)
      bool passChecks = true;

      if(!PerformRiskChecks())
      {
         passChecks = false;
         Alert(StringFormat("Rattapignola BLOCCATO: Risk check fallito per %s | %s",
               sig.direction > 0 ? "BUY" : "SELL", _Symbol));
      }

      // HTF filter
      if(UseHTFFilter && !HTFCheckSignal(sig.direction))
      {
         AdLogI(LOG_CAT_HTF, StringFormat("HTF filter blocked %s",
                sig.direction > 0 ? "BUY" : "SELL"));
         passChecks = false;
         Alert(StringFormat("Rattapignola BLOCCATO: HTF filter ha bloccato %s | %s",
               sig.direction > 0 ? "BUY" : "SELL", _Symbol));
      }

      // TP validation: il broker rifiuterebbe l'ordine, scartiamo il segnale
      // prima di qualsiasi side effect (alert, history, marker, ordine).
      if(TPMode != TP_SIGNAL_TO_SIGNAL && sig.tpPrice > 0)
      {
         bool tpInvalidBuy  = (sig.direction > 0 && sig.tpPrice <= sig.entryPrice);
         bool tpInvalidSell = (sig.direction < 0 && sig.tpPrice >= sig.entryPrice);
         if(tpInvalidBuy || tpInvalidSell)
         {
            AdLogW(LOG_CAT_TRIGGER, StringFormat(
                   "BLOCCATO: TP invalido %s TP=%s Entry=%s — segnale scartato",
                   sig.direction > 0 ? "BUY" : "SELL",
                   FormatPrice(sig.tpPrice), FormatPrice(sig.entryPrice)));
            Alert(StringFormat("Rattapignola BLOCCATO: TP invalido %s | %s",
                  sig.direction > 0 ? "BUY" : "SELL", _Symbol));
            passChecks = false;
         }
      }

      if(passChecks)
      {
         string dirStr = sig.direction > 0 ? "BUY" : "SELL";
         color  dirClr = sig.direction > 0 ? RATT_BUY : RATT_SELL;
         string qStr   = sig.quality == PATTERN_TBS ? "TBS" : "TWS";

         AdLogI(LOG_CAT_ENGINE, StringFormat("*** SIGNAL %s Q=%d | Entry=%s | SL=%s | TP=%s ***",
                dirStr, sig.quality,
                FormatPrice(sig.entryPrice), FormatPrice(sig.slPrice), FormatPrice(sig.tpPrice)));

         // ── DIAG: Log diagnostico completo del trigger ──
         double diagBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double diagAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         AdLogI(LOG_CAT_TRIGGER, "════════════════════════════════════════════════════");
         AdLogI(LOG_CAT_TRIGGER, StringFormat("TRIGGER %s %s RILEVATO", qStr, dirStr));
         AdLogI(LOG_CAT_TRIGGER, StringFormat("  Direction=%d | Quality=%d (%s)", sig.direction, sig.quality, qStr));
         AdLogI(LOG_CAT_TRIGGER, StringFormat("  Entry=%s | TP=%s | SL=%s", FormatPrice(sig.entryPrice), FormatPrice(sig.tpPrice), FormatPrice(sig.slPrice)));
         AdLogI(LOG_CAT_TRIGGER, StringFormat("  Trail: Upper=%s | Src=%s | Lower=%s", FormatPrice(sig.upperBand), FormatPrice(sig.midline), FormatPrice(sig.lowerBand)));
         AdLogD(LOG_CAT_TRIGGER, StringFormat("  Mercato: Bid=%s | Ask=%s | Spread=%.1fp", FormatPrice(diagBid), FormatPrice(diagAsk), PointsToPips(diagAsk - diagBid)));
         AdLogI(LOG_CAT_TRIGGER, StringFormat("  EntryMode=%s | Cicli attivi=%d/%d", EnumToString(EntryMode), CountActiveCycles(), MaxConcurrentTrades));
         AdLogI(LOG_CAT_TRIGGER, StringFormat("  BarTime=%s | VirtualMode=%s", TimeToString(sig.barTime, TIME_DATE|TIME_MINUTES), VirtualMode ? "ON" : "OFF"));
         AdLogI(LOG_CAT_TRIGGER, "════════════════════════════════════════════════════");

         // Alert popup per il trigger
         Alert(StringFormat("Rattapignola TRIGGER %s %s | Entry=%s | TP=%s | %s",
               qStr, dirStr, FormatPrice(sig.entryPrice), FormatPrice(sig.tpPrice), _Symbol));

         // Feed + history
         AddFeedItem(qStr + " " + dirStr + " · " + FormatPrice(sig.entryPrice), dirClr);
         AddSignalHistory(sig.direction, sig.entryPrice, sig.tpPrice, sig.quality, "OPEN");

         // Visual markers per il segnale (frecce, entry-level, trigger giallo)
         // sono disegnati dall'indicatore UTBotAdaptive embedded via buffer
         // nativi — l'EA non tocca piu' nulla qui sul segnale stesso.

         // TP visuals — solo se tpPrice > 0 (Signal-to-Signal ha tpPrice=0)
         if(sig.tpPrice > 0)
            DrawTPAsterisk(sig.tpPrice, sig.barTime, sig.direction > 0);

         // ── DIAG: Log TP diagnostico ──
         if(TPMode == TP_SIGNAL_TO_SIGNAL)
         {
            AdLogD(LOG_CAT_TRIGGER, "DIAG TP: Mode=SIGNAL_TO_SIGNAL — nessun TP broker, chiusura al flip");
         }
         else
         {
            AdLogD(LOG_CAT_TRIGGER, StringFormat("DIAG TP: Mode=%s | Value=%.2f | TP calcolato=%s",
                   EnumToString(TPMode), TPValue, FormatPrice(sig.tpPrice)));
            if(sig.tpPrice > 0 && sig.direction > 0 && sig.tpPrice <= sig.entryPrice)
               AdLogW(LOG_CAT_TRIGGER, StringFormat("DIAG TP WARNING: BUY ma TP (%s) <= Entry (%s) — ordine sara' RIFIUTATO",
                      FormatPrice(sig.tpPrice), FormatPrice(sig.entryPrice)));
            if(sig.tpPrice > 0 && sig.direction < 0 && sig.tpPrice >= sig.entryPrice)
               AdLogW(LOG_CAT_TRIGGER, StringFormat("DIAG TP WARNING: SELL ma TP (%s) >= Entry (%s) — ordine sara' RIFIUTATO",
                      FormatPrice(sig.tpPrice), FormatPrice(sig.entryPrice)));
         }

         // ── S2S: Chiudi/cancella cicli opposti PRIMA di aprire il nuovo ──
         if(TPMode == TP_SIGNAL_TO_SIGNAL)
         {
            int flipped = CloseOppositeOnSignal(sig.direction);
            if(flipped > 0)
               AdLogI(LOG_CAT_CYCLE, StringFormat("S2S: %d cicli opposti chiusi/cancellati", flipped));
         }

         // Create cycle
         if(VirtualMode)
         {
            AdLogD(LOG_CAT_TRIGGER, "DIAG: VirtualMode ON — creo trade virtuale (nessun ordine reale)");
            int vSlot = VirtualCreateTrade(sig);
            if(vSlot >= 0)
            {
               AdLogI(LOG_CAT_VIRTUAL, "Virtual trade created");
               if(sig.tpPrice > 0)
                  DrawTPLine(g_nextCycleID, sig.tpPrice, sig.direction > 0);
            }
            else
               AdLogW(LOG_CAT_TRIGGER, "DIAG: VirtualCreateTrade FALLITO — vSlot < 0");
         }
         else
         {
            AdLogD(LOG_CAT_TRIGGER, "DIAG: Invoco CreateCycle() per piazzare ordine reale...");
            int slot = CreateCycle(sig);
            if(slot >= 0)
            {
               AdLogD(LOG_CAT_TRIGGER, StringFormat("DIAG: CreateCycle OK — slot=%d | CycleID=#%d | Ticket=%d",
                      slot, g_cycles[slot].cycleID, g_cycles[slot].ticket));
               AdLogD(LOG_CAT_TRIGGER, StringFormat("DIAG: Ordine PIAZZATO — %s Lot=%.2f | Entry=%s | TP=%s",
                      dirStr, g_cycles[slot].lotSize, FormatPrice(g_cycles[slot].entryPrice), FormatPrice(g_cycles[slot].tpPrice)));
               Alert(StringFormat("Rattapignola ORDINE PIAZZATO #%d %s | Lot=%.2f | %s",
                     g_cycles[slot].cycleID, dirStr, g_cycles[slot].lotSize, _Symbol));

               // TP visuals — solo se tpPrice > 0 (Signal-to-Signal ha tpPrice=0)
               if(sig.tpPrice > 0)
               {
                  DrawTPLine(g_cycles[slot].cycleID, sig.tpPrice, sig.direction > 0);
                  DrawTPDot(g_cycles[slot].cycleID, sig.tpPrice, sig.barTime, sig.direction > 0);
               }

               // HS piazzato al FILL della Soup, non al piazzamento.
               // Per ordini STOP/LIMIT la Soup e' ancora pending qui — l'HS
               // viene piazzato da DetectFill/PollFills (rattCycleManager) quando
               // il broker filla la Soup, o da HsMonitor (rattHedgeManager) come
               // fallback per ENTRY_MARKET e recovery post-crash.
            }
            else
            {
               AdLogW(LOG_CAT_TRIGGER, "DIAG: CreateCycle FALLITO — slot < 0 — NESSUN ORDINE PIAZZATO");
               AdLogW(LOG_CAT_TRIGGER, "DIAG: Controlla i log [CYCLE] e [ORDER] sopra per il motivo del fallimento");
               Alert(StringFormat("Rattapignola ORDINE FALLITO %s %s — controlla log Experts | %s",
                     qStr, dirStr, _Symbol));
            }
         }
      }
   }

   // ── 11. MONITOR CYCLES ────────────────────────────────────────────
   MonitorCycles(sig);

   // ── 11b. HEDGE SMART MONITOR ──────────────────────────────────────
   if(EnableHedge && HsEnabled)
   {
      for(int _hi = 0; _hi < ArraySize(g_cycles); _hi++)
         HsMonitor(_hi, sig, hasSignal);
   }

   // ── 12. DAILY RESET ──────────────────────────────────────────────
   CheckDailyReset();
}

//+------------------------------------------------------------------+
//| Trade transaction handler — Layer 1 fill detection               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   DetectFill(trans, request, result);
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // [v2.13] Toggle button del pannello Engine (Trail/Arrows/Entry/Candles)
      if(StringFind(sparam, "RATT_DASH_TGL_") == 0)
         HandleEngineToggle(sparam);
      else
         HandleButtonClick(sparam);
   }

   // Redraw su scroll/zoom/resize + live edge update
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(g_engineReady)
         UpdateChannelLiveEdge();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Timer handler — Auto-save                                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Retry initial overlay draw (timeseries non pronte durante OnInit/TF change)
   if(!g_initialDrawDone && g_engineReady)
   {
      int bars = iBars(_Symbol, PERIOD_CURRENT);
      if(bars > 50)
      {
         DrawChannelOverlay();
         UpdateDashboard();
         ChartRedraw();
         g_initialDrawDone = true;
         EventSetTimer(60);
         AdLogI(LOG_CAT_UI, StringFormat("Initial overlay draw — %d bars available", bars));
      }
   }

   // DIAG: Warning periodico se sistema e' IDLE con EnableSystem=true
   static int idleWarningCount = 0;
   if(g_systemState == STATE_IDLE && EnableSystem)
   {
      if(++idleWarningCount % 10 == 1)
         AdLogW(LOG_CAT_SYSTEM, "ATTENZIONE: Sistema IDLE con EnableSystem=true — premi START per attivare");
   }
   else
      idleWarningCount = 0;

   if(EnableAutoSave)
      ExecuteAutoSave();
}
//+------------------------------------------------------------------+
