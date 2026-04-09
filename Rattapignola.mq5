//+------------------------------------------------------------------+
//|                                            Rattapignola.mq5      |
//|  "Il canto della campagna nelle notti d'estate."                  |
//+------------------------------------------------------------------+
//|  Copyright (C) 2026 - Rattapignola Development                   |
//|  Version: 1.0.0                                                   |
//|  Engine: UTBot Adaptive — swappable                               |
//+------------------------------------------------------------------+
//|                                                                  |
//|  Rattapignola EA — Framework di trading modulare a 7 livelli     |
//|                                                                  |
//|  ARCHITETTURA:                                                   |
//|    Layer 0: Config    — Enums, parametri input, interfaccia eng.  |
//|    Layer 1: Core      — Variabili globali, helpers, sessioni      |
//|    Layer 2: Engine    — UTBot Adaptive (trailing stop ATR adattivo)|
//|             ↳ Trailing stop adattivo basato su ATR × KeyValue     |
//|             ↳ Sorgente: KAMA/HMA/JMA/Close (adattive)             |
//|             ↳ Classificazione TBS/TWS (qualita' ER)               |
//|             ↳ Auto TF Preset (parametri adattivi per TF)          |
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
#property copyright "Rattapignola (C) 2026"
#property version   "1.00"
#property description "Rattapignola EA v1.0.0 — Reusable Trading Framework"
#property description "Engine: UTBot Adaptive (Trailing Stop ATR Adattivo)"
#property description "Segnali: UTBot Crossover (TBS forte 2x / TWS debole 1x)"
#property description "TP: Signal-to-Signal (flip strategy)"
#property description "Anti-repaint: bar[1] signals only"
#property strict

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

   // Dashboard prima di tutto — visibile anche in caso di errore
   ApplyChartTheme();
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
   g_initialDrawDone = false;  // Reset retry timer per TF change

   // 5b. Draw channel overlay + historical signals immediately
   if(ShowChannelOverlay)
      DrawChannelOverlay();
   if(ShowSignalArrows)
      ScanHistoricalSignals();
   ChartRedraw();  // Force immediate visual update

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

   EventKillTimer();
   AdLogI(LOG_CAT_SYSTEM, StringFormat("DEINIT — Reason: %d", reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ── 1. DASHBOARD UPDATE (throttle 500ms) ─────────────────────────
   static uint lastDashUpdate = 0;
   uint now = GetTickCount();
   if(now - lastDashUpdate > 500)
   {
      lastDashUpdate = now;
      UpdateDashboard();

      // Channel overlay live edge — lightweight update (only bar[0] segment)
      if(ShowChannelOverlay && g_engineReady)
         UpdateChannelLiveEdge();
   }

   // ── 1b. CHANNEL OVERLAY + HISTORICAL ARROWS (solo nuova barra, pre-gate) ──
   if(g_engineReady && IsNewBarOverlay())
   {
      if(ShowChannelOverlay) DrawChannelOverlay();
      if(ShowSignalArrows)   ScanHistoricalSignals();
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
      // DIAG: log periodico quando sessione blocca (max 1 ogni 5 min)
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
         passChecks = false;

      // HTF filter
      if(UseHTFFilter && !HTFCheckSignal(sig.direction))
      {
         AdLogI(LOG_CAT_HTF, StringFormat("HTF filter blocked %s",
                sig.direction > 0 ? "BUY" : "SELL"));
         passChecks = false;
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

         // Visual markers
         DrawSignalMarkers(sig);

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

               DrawTriggerArrow(g_cycles[slot].cycleID, sig.entryPrice,
                               sig.barTime, sig.direction > 0);

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
      HandleButtonClick(sparam);

   // Redraw canvas fill on chart scroll/zoom/resize
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(ShowChannelOverlay && g_engineReady)
      {
         UpdateChannelLiveEdge();
      }
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Timer handler — Auto-save                                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Retry initial overlay draw (timeseries not ready during OnInit/TF change)
   // g_initialDrawDone e' globale — resettata in OnInit ad ogni init/TF change
   // cosi' il retry funziona anche dopo REASON_CHARTCHANGE
   if(!g_initialDrawDone && g_engineReady)
   {
      int bars = iBars(_Symbol, PERIOD_CURRENT);
      if(bars > 50)
      {
         if(ShowChannelOverlay) DrawChannelOverlay();
         if(ShowSignalArrows) ScanHistoricalSignals();
         UpdateDashboard();
         ChartRedraw();
         g_initialDrawDone = true;
         EventSetTimer(60);  // Switch to 60s for auto-save
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
