//+------------------------------------------------------------------+
//|                                      adHedgeManager.mqh          |
//|           AcquaDulza EA v1.7.2 — Hedge Smart Manager             |
//|                                                                   |
//|  Hedge Smart: hedge non invasivo a lotto fisso.                   |
//|  La Soup NON viene mai chiusa o modificata da questo modulo.     |
//|                                                                   |
//|  LOGICA v1.7.2:                                                   |
//|   BUY Soup  → SELL STOP @ lower_band − (cw × HsTriggerPct)      |
//|   SELL Soup → BUY STOP  @ upper_band + (cw × HsTriggerPct)      |
//|   SL iniziale HS = midline (= SoupTP): perdita HS sempre definita|
//|                                                                   |
//|  STEP 1 — BREAKEVEN (se HsBEEnabled):                            |
//|   Dopo HsStep1Pct×cw pip di profitto → SL spostato a fill price  |
//|   Effetto: HS non può più chiudersi in perdita                   |
//|                                                                   |
//|  STEP 2 — CLOSE AL TPREVLEVEL (se HsUseStep2Close):             |
//|   Quando prezzo raggiunge tpRefLevel → chiudi HS con profitto    |
//|   tpRefLevel = trigger ± (cw × HsTpPct)                          |
//|                                                                   |
//|  EXIT (priorità decrescente):                                     |
//|   1. Prossimo segnale DPC stesso senso Soup (≥ HsAntiWhipsawBars)|
//|   2. Timeout N barre (HsTimeoutBars, default 32 = 8h M15)        |
//|   3. Soup chiusa → cleanup contestuale in MonitorActive           |
//|                                                                   |
//|  MAGIC: HS = MagicNumber + 1                                      |
//|  COMMENT FORMAT: "AD_HS_SELL_#12" / "AD_HS_BUY_#12"             |
//|                                                                   |
//|  API PUBBLICA:                                                     |
//|    HedgeInit()                                                    |
//|    HedgeDeinit()                                                   |
//|    HsPlaceOrder(slot, sig)                                        |
//|    HsMonitor(slot, sig, hasNewSignal)                             |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

#define HS_LINE_PREFIX    "AD_HS_LINE_"
#define HS_ZONE_TRIGGER   "AD_HS_ZONE_TRG"
#define HS_ZONE_TP        "AD_HS_ZONE_TP"

//+------------------------------------------------------------------+
//| HedgeInit                                                         |
//+------------------------------------------------------------------+
void HedgeInit()
{
   AdLogI(LOG_CAT_HEDGE, StringFormat(
      "HedgeSmart INIT v1.7.2 | Enabled=%s | Lot=%.2f | TriggerPct=%.2f | "
      "TpPct=%.2f | MidlineSL=%.1f | Step1BE=%s(%.0f%%) | Step2TP=%s | "
      "AntiWhipsaw=%d | Timeout=%d | BodyFilter=%s(%.2f) | Zones=%s",
      HsEnabled ? "YES" : "NO", HsLot, HsTriggerPct,
      HsTpPct, HsMidlineSL,
      HsBEEnabled ? "YES" : "NO", HsStep1Pct * 100,
      HsUseStep2Close ? "YES" : "NO",
      HsAntiWhipsawBars, HsTimeoutBars,
      HsBodyFilter ? "YES" : "NO", HsBodyRatioMin,
      HsShowZones ? "YES" : "NO"));
   // Warning: Step2 richiede Step1 BE — se BE disabilitato, Step2 non scatterà mai
   if(!HsBEEnabled && HsUseStep2Close)
      AdLogW(LOG_CAT_HEDGE, "WARNING: HsBEEnabled=false ma HsUseStep2Close=true — Step2 TP non scatterà mai (richiede hsBESet)");
}

//+------------------------------------------------------------------+
//| HedgeDeinit — Rimuove tutti gli oggetti grafici HS               |
//+------------------------------------------------------------------+
void HedgeDeinit()
{
   int removed = 0;
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, HS_LINE_PREFIX)  >= 0 ||
         StringFind(name, HS_ZONE_TRIGGER) >= 0 ||
         StringFind(name, HS_ZONE_TP)      >= 0 ||
         StringFind(name, "AD_HS_BE_")     >= 0 ||
         StringFind(name, "AD_HS_TP_")     >= 0)
      {
         ObjectDelete(0, name);
         removed++;
      }
   }
   AdLogI(LOG_CAT_HEDGE, StringFormat("HedgeSmart DEINIT — %d oggetti rimossi", removed));
}

//+------------------------------------------------------------------+
//| GetClosedHsProfit — P&L realizzato HS da deal history            |
//+------------------------------------------------------------------+
double GetClosedHsProfit(ulong posTicket)
{
   datetime from = TimeCurrent() - 86400 * 7;
   if(!HistorySelect(from, TimeCurrent())) return 0;

   double totalProfit = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber + 1) continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         if((ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == posTicket)
         {
            totalProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                         + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                         + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         }
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| HsBodyFilterOK — Verifica body/wick ratio sulla candela [1]      |
//|                                                                   |
//| Legge la candela che ha generato il segnale DPC (barra [1]).     |
//| body_ratio = |close-open| / (high-low)                           |
//| Ritorna true se filtro disabilitato o body_ratio >= HsBodyRatioMin|
//+------------------------------------------------------------------+
bool HsBodyFilterOK()
{
   if(!HsBodyFilter) return true;

   double o = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);

   double range = h - l;
   if(range < g_symbolPoint) return true;   // candela degenere → skip filtro

   double bodyRatio = MathAbs(c - o) / range;

   AdLogD(LOG_CAT_HEDGE, StringFormat(
      "HS BodyFilter: ratio=%.2f threshold=%.2f → %s",
      bodyRatio, HsBodyRatioMin,
      bodyRatio >= HsBodyRatioMin ? "PASS" : "FAIL"));

   return (bodyRatio >= HsBodyRatioMin);
}

//+------------------------------------------------------------------+
//| HsDrawTriggerLine — Linea tratteggiata arancione al trigger      |
//+------------------------------------------------------------------+
void HsDrawTriggerLine(int slot, double triggerLevel, datetime barTime)
{
   if(!HsShowTriggerLine) return;

   string name = HS_LINE_PREFIX + IntegerToString(g_cycles[slot].cycleID);
   g_cycles[slot].hsLineName = name;
   ObjectDelete(0, name);

   datetime t1 = barTime;
   datetime t2 = barTime + (datetime)(HsTriggerLineWidth * PeriodSeconds());

   if(ObjectCreate(0, name, OBJ_TREND, 0, t1, triggerLevel, t2, triggerLevel))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR,     AD_HS_TRIGGER_CLR);
      ObjectSetInteger(0, name, OBJPROP_STYLE,     STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,     1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK,      true);
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
         StringFormat("HS TRIGGER #%d @ %s | %.0f%% cw",
            g_cycles[slot].cycleID,
            DoubleToString(triggerLevel, _Digits),
            HsTriggerPct * 100));
   }
}

//+------------------------------------------------------------------+
//| HsRemoveLine — Rimuove linea trigger HS                          |
//+------------------------------------------------------------------+
void HsRemoveLine(int slot)
{
   if(g_cycles[slot].hsLineName == "") return;
   ObjectDelete(0, g_cycles[slot].hsLineName);
   g_cycles[slot].hsLineName = "";
}

//+------------------------------------------------------------------+
//| HsDrawBEMarker — Rombo verde al livello BE (Step1 completato)    |
//+------------------------------------------------------------------+
void HsDrawBEMarker(int slot, double fillPrice)
{
   string name = StringFormat("AD_HS_BE_%d", g_cycles[slot].cycleID);
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), fillPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 4);      // Rombo (◆)
   ObjectSetInteger(0, name, OBJPROP_COLOR,     AD_HS_BE_CLR);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,
      StringFormat("HS BE #%d @ %s", g_cycles[slot].cycleID,
         DoubleToString(fillPrice, _Digits)));
}

//+------------------------------------------------------------------+
//| HsDrawTPMarker — Rombo blu al livello TP (Step2 raggiunto)      |
//+------------------------------------------------------------------+
void HsDrawTPMarker(int slot, double tpRefLevel)
{
   string name = StringFormat("AD_HS_TP_%d", g_cycles[slot].cycleID);
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), tpRefLevel);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 4);      // Rombo (◆)
   ObjectSetInteger(0, name, OBJPROP_COLOR,     AD_HS_TP_CLR);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,
      StringFormat("HS TP #%d @ %s", g_cycles[slot].cycleID,
         DoubleToString(tpRefLevel, _Digits)));
}

//+------------------------------------------------------------------+
//| HsPlaceOrder — Valuta e piazza l'ordine HS                       |
//|                                                                   |
//| Chiamato da AcquaDulza.mq5 dopo CreateCycle().                   |
//| Non invia TP al broker: la chiusura è sempre programmata.        |
//|                                                                   |
//| FORMULA TRIGGER:                                                  |
//|   cw = upperBand - lowerBand                                     |
//|   BUY Soup  → SELL STOP @ lowerBand - (cw × HsTriggerPct)       |
//|   SELL Soup → BUY STOP  @ upperBand + (cw × HsTriggerPct)       |
//+------------------------------------------------------------------+
void HsPlaceOrder(int slot, const EngineSignal &sig)
{
   if(!EnableHedge || !HsEnabled) return;
   if(slot < 0 || slot >= ArraySize(g_cycles)) return;
   if(g_cycles[slot].state == CYCLE_CLOSED) return;
   if(g_cycles[slot].hsPending || g_cycles[slot].hsActive)
   {
      AdLogD(LOG_CAT_HEDGE, StringFormat("HS già attivo #%d — skip", g_cycles[slot].cycleID));
      return;
   }

   // Body/wick filter
   if(!HsBodyFilterOK())
   {
      AdLogI(LOG_CAT_HEDGE, StringFormat(
         "HS SKIP #%d — body filter: candela wick-dominante (falso breakout probabile)",
         g_cycles[slot].cycleID));
      return;
   }

   // Channel width
   double cw = sig.upperBand - sig.lowerBand;
   if(cw < g_symbolPoint * 10)
   {
      AdLogW(LOG_CAT_HEDGE, StringFormat("HS SKIP #%d — channel width troppo piccolo %.5f",
             g_cycles[slot].cycleID, cw));
      return;
   }

   // Calcola livelli — v1.7.2: tpRefDist ora usa HsTpPct (era hardcoded 0.60)
   double triggerDist = cw * HsTriggerPct;
   double tpRefDist   = cw * HsTpPct;
   double triggerLevel, tpRefLevel;

   if(g_cycles[slot].direction > 0)   // BUY Soup → SELL STOP
   {
      triggerLevel = sig.lowerBand - triggerDist;
      tpRefLevel   = triggerLevel  - tpRefDist;
   }
   else                                // SELL Soup → BUY STOP
   {
      triggerLevel = sig.upperBand + triggerDist;
      tpRefLevel   = triggerLevel  + tpRefDist;
   }
   triggerLevel = NormalizeDouble(triggerLevel, _Digits);
   tpRefLevel   = NormalizeDouble(tpRefLevel,   _Digits);

   // Verifica distanza minima broker
   double minDist = (g_symbolStopsLevel + 2) * g_symbolPoint;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(g_cycles[slot].direction > 0)   // SELL STOP: deve essere sotto bid
   {
      if(triggerLevel >= bid - minDist)
      {
         triggerLevel = NormalizeDouble(bid - minDist - g_symbolPoint, _Digits);
         tpRefLevel   = NormalizeDouble(triggerLevel - tpRefDist, _Digits);
         AdLogW(LOG_CAT_HEDGE, StringFormat("HS SELL STOP aggiustato → %s", DoubleToString(triggerLevel, _Digits)));
      }
   }
   else                                // BUY STOP: deve essere sopra ask
   {
      if(triggerLevel <= ask + minDist)
      {
         triggerLevel = NormalizeDouble(ask + minDist + g_symbolPoint, _Digits);
         tpRefLevel   = NormalizeDouble(triggerLevel + tpRefDist, _Digits);
         AdLogW(LOG_CAT_HEDGE, StringFormat("HS BUY STOP aggiustato → %s", DoubleToString(triggerLevel, _Digits)));
      }
   }

   // Lotto
   double hsLot = NormalizeLotSize(HsLot);
   if(hsLot <= 0) hsLot = g_symbolMinLot;

   // Comment per recovery
   string comment = StringFormat("AD_HS_%s_#%d",
      g_cycles[slot].direction > 0 ? "SELL" : "BUY",
      g_cycles[slot].cycleID);

   // v1.7.2: SL iniziale = midline (= SoupTP)
   // Se il prezzo torna alla midline, la Soup sta per fare TP → la perdita HS
   // è compensata dal profitto Soup. La midline è il livello naturale di protezione.
   double initSL = 0;
   if(HsMidlineSL > 0.0)
   {
      initSL = sig.midline;

      // Verifica distanza minima SL dal trigger (requisito broker)
      double slDist   = MathAbs(triggerLevel - initSL);
      double minSLDist = (g_symbolStopsLevel + 2) * g_symbolPoint;
      if(slDist < minSLDist)
      {
         AdLogW(LOG_CAT_HEDGE, StringFormat(
            "HS SL iniziale troppo vicino al trigger (dist=%.5f < min=%.5f) — SL disabilitato",
            slDist, minSLDist));
         initSL = 0;
      }
   }

   // Piazza STOP con SL iniziale = midline (se valido)
   g_trade.SetExpertMagicNumber(MagicNumber + 1);
   bool placed = false;
   if(g_cycles[slot].direction > 0)
      placed = g_trade.SellStop(hsLot, triggerLevel, _Symbol, initSL, 0, ORDER_TIME_GTC, 0, comment);
   else
      placed = g_trade.BuyStop(hsLot, triggerLevel, _Symbol, initSL, 0, ORDER_TIME_GTC, 0, comment);

   if(placed)
   {
      g_cycles[slot].hsTicket            = g_trade.ResultOrder();
      g_cycles[slot].hsTriggerPrice      = triggerLevel;
      g_cycles[slot].hsTpRefLevel        = tpRefLevel;
      g_cycles[slot].hsLotSize           = hsLot;
      g_cycles[slot].hsPending           = true;
      g_cycles[slot].hsActive            = false;
      g_cycles[slot].hsFillTime          = 0;
      g_cycles[slot].hsPL                = 0;
      // v1.7.2 — nuovi campi
      g_cycles[slot].hsFillPrice         = 0;              // sarà settato in HsDetectFill
      g_cycles[slot].hsMidlineAtSignal   = sig.midline;    // midline congelata al segnale
      g_cycles[slot].hsBESet             = false;
      g_cycles[slot].hsStep2Reached      = false;

      double ptp = PipsToPrice(1);
      double cwPip = (ptp > 0) ? cw / ptp : 0;
      AdLogI(LOG_CAT_HEDGE, StringFormat(
         "HS PLACED #%d | %s STOP @ %s | SL(midline)=%s | TpRef=%s | Lot=%.2f | TrigPct=%.0f%% | TpPct=%.0f%% | cw=%.1fpip",
         g_cycles[slot].cycleID,
         g_cycles[slot].direction > 0 ? "SELL" : "BUY",
         DoubleToString(triggerLevel, _Digits),
         DoubleToString(initSL, _Digits),
         DoubleToString(tpRefLevel, _Digits),
         hsLot, HsTriggerPct * 100, HsTpPct * 100, cwPip));

      Alert(StringFormat("AcquaDulza HS PIAZZATO #%d %s STOP @ %s | Lot=%.2f | %s",
            g_cycles[slot].cycleID,
            g_cycles[slot].direction > 0 ? "SELL" : "BUY",
            DoubleToString(triggerLevel, _Digits), hsLot, _Symbol));

      if(HsShowTriggerLine)
         HsDrawTriggerLine(slot, triggerLevel, sig.barTime);
   }
   else
   {
      AdLogE(LOG_CAT_HEDGE, StringFormat("HS PLACE FAILED #%d | Error: %s",
             g_cycles[slot].cycleID, g_trade.ResultRetcodeDescription()));
   }
}

//+------------------------------------------------------------------+
//| HsDetectFill — Rileva se l'ordine HS è stato riempito            |
//+------------------------------------------------------------------+
bool HsDetectFill(int slot)
{
   if(!g_cycles[slot].hsPending) return false;
   if(g_cycles[slot].hsTicket == 0) return false;

   bool stillPending = false;
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(OrderGetTicket(j) == g_cycles[slot].hsTicket)
      { stillPending = true; break; }
   }

   if(!stillPending)
   {
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         ulong posTkt = PositionGetTicket(j);
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber + 1) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

         string posComment = PositionGetString(POSITION_COMMENT);
         if(StringFind(posComment, StringFormat("#%d", g_cycles[slot].cycleID)) >= 0)
         {
            g_cycles[slot].hsTicket    = posTkt;
            g_cycles[slot].hsPending   = false;
            g_cycles[slot].hsActive    = true;
            g_cycles[slot].hsFillTime  = TimeCurrent();
            // v1.7.2: salva fill price reale (può differire da trigger per slippage)
            g_cycles[slot].hsFillPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            g_cycles[slot].hsBESet          = false;   // reset BE flag al fill
            g_cycles[slot].hsStep2Reached   = false;   // reset Step2 flag al fill
            if(g_cycles[slot].state == CYCLE_ACTIVE)
               g_cycles[slot].state = CYCLE_HEDGING;
            HsRemoveLine(slot);

            double fillPrice = g_cycles[slot].hsFillPrice;
            AdLogI(LOG_CAT_HEDGE, StringFormat(
               "=== HS ACTIVATED #%d === Fill @ %s | Trigger @ %s | Slippage=%.1fpip | Lot=%.2f",
               g_cycles[slot].cycleID,
               DoubleToString(fillPrice, _Digits),
               DoubleToString(g_cycles[slot].hsTriggerPrice, _Digits),
               PointsToPips(MathAbs(fillPrice - g_cycles[slot].hsTriggerPrice)),
               PositionGetDouble(POSITION_VOLUME)));
            Alert(StringFormat("AcquaDulza HS ATTIVATO #%d @ %s | Lot=%.2f | %s",
                  g_cycles[slot].cycleID,
                  DoubleToString(fillPrice, _Digits),
                  PositionGetDouble(POSITION_VOLUME), _Symbol));
            return true;
         }
      }

      AdLogW(LOG_CAT_HEDGE, StringFormat("HS order #%d SCOMPARSO — reset pending", g_cycles[slot].cycleID));
      g_cycles[slot].hsPending = false;
      g_cycles[slot].hsTicket  = 0;
      HsRemoveLine(slot);
   }
   return false;
}

//+------------------------------------------------------------------+
//| HsCancel — Cancella ordine HS pendente                           |
//+------------------------------------------------------------------+
void HsCancel(int slot, string reason)
{
   if(!g_cycles[slot].hsPending) return;
   if(g_cycles[slot].hsTicket == 0) return;

   g_trade.SetExpertMagicNumber(MagicNumber + 1);
   if(g_trade.OrderDelete(g_cycles[slot].hsTicket))
   {
      AdLogI(LOG_CAT_HEDGE, StringFormat("HS CANCELLED #%d | Reason: %s | Ticket=%d",
             g_cycles[slot].cycleID, reason, g_cycles[slot].hsTicket));
   }
   else
   {
      AdLogE(LOG_CAT_HEDGE, StringFormat("HS CANCEL FAILED #%d | Error: %s",
             g_cycles[slot].cycleID, g_trade.ResultRetcodeDescription()));
   }
   g_cycles[slot].hsPending = false;
   g_cycles[slot].hsTicket  = 0;
   HsRemoveLine(slot);
}

//+------------------------------------------------------------------+
//| HsClose — Chiude posizione HS attiva a mercato                   |
//+------------------------------------------------------------------+
void HsClose(int slot, string reason)
{
   if(!g_cycles[slot].hsActive) return;
   if(g_cycles[slot].hsTicket == 0) return;

   ulong tkt = g_cycles[slot].hsTicket;
   g_trade.SetExpertMagicNumber(MagicNumber + 1);

   if(PositionSelectByTicket(tkt))
   {
      if(g_trade.PositionClose(tkt))
      {
         double hsPL = GetClosedHsProfit(tkt);
         g_cycles[slot].hsPL             += hsPL;
         g_cycles[slot].profit           += hsPL;
         g_sessionRealizedProfit         += hsPL;
         g_dailyRealizedProfit           += hsPL;

         AdLogI(LOG_CAT_HEDGE, StringFormat(
            "=== HS CLOSED #%d === Reason: %s | P&L=%.2f",
            g_cycles[slot].cycleID, reason, hsPL));
         Alert(StringFormat("AcquaDulza HS CHIUSO #%d | %s | P&L=%+.2f | %s",
               g_cycles[slot].cycleID, reason, hsPL, _Symbol));
      }
      else
      {
         AdLogE(LOG_CAT_HEDGE, StringFormat("HS CLOSE FAILED #%d | Error: %s",
                g_cycles[slot].cycleID, g_trade.ResultRetcodeDescription()));
         return;
      }
   }
   else
   {
      AdLogW(LOG_CAT_HEDGE, StringFormat("HS #%d già chiusa dal broker", g_cycles[slot].cycleID));
   }

   g_cycles[slot].hsActive          = false;
   g_cycles[slot].hsTicket          = 0;
   g_cycles[slot].hsFillTime        = 0;
   // v1.7.2: reset campi Step1/Step2
   g_cycles[slot].hsFillPrice       = 0;
   g_cycles[slot].hsMidlineAtSignal = 0;
   g_cycles[slot].hsBESet           = false;
   g_cycles[slot].hsStep2Reached    = false;

   if(g_cycles[slot].state == CYCLE_HEDGING)
   {
      if(g_cycles[slot].ticket > 0 && PositionSelectByTicket(g_cycles[slot].ticket))
         g_cycles[slot].state = CYCLE_ACTIVE;
   }
}

//+------------------------------------------------------------------+
//| HsCleanup — Cancella/chiudi HS quando la Soup si chiude         |
//+------------------------------------------------------------------+
void HsCleanup(int slot, string reason)
{
   if(g_cycles[slot].hsPending)
      HsCancel(slot, reason);
   if(g_cycles[slot].hsActive)
      HsClose(slot, reason);
}

//+------------------------------------------------------------------+
//| HsMonitor — Monitor principale Hedge Smart                       |
//|                                                                   |
//| Chiamato ogni nuova barra per ogni slot.                          |
//|                                                                   |
//| PARAMETRI:                                                        |
//|   slot         — indice nel g_cycles array                        |
//|   sig          — segnale DPC corrente da EngineCalculate()        |
//|   hasNewSignal — true se questa barra ha prodotto un segnale DPC |
//+------------------------------------------------------------------+
void HsMonitor(int slot, const EngineSignal &sig, bool hasNewSignal)
{
   if(!EnableHedge || !HsEnabled) return;
   if(slot < 0 || slot >= ArraySize(g_cycles)) return;

   ENUM_CYCLE_STATE st = g_cycles[slot].state;

   // Cleanup se ciclo già chiuso (sicurezza)
   if(st == CYCLE_CLOSED)
   {
      HsCleanup(slot, "CycleAlreadyClosed");
      return;
   }

   // v1.8.0: Soup ACTIVE ma HS mai piazzato → piazza ora.
   // Copre due scenari:
   //   1) ENTRY_MARKET: fill avviene in CreateCycle (state=ACTIVE prima di DetectFill),
   //      DetectFill non scatta (cerca solo CYCLE_PENDING), HS non piazzato.
   //   2) Recovery: EA crasha, Soup filla offline, al restart AttemptRecovery
   //      ripristina CYCLE_ACTIVE ma HS è assente.
   // Guard hsTriggerPrice==0: evita ri-piazzamento dopo HsClose/HsCancel
   //   (queste funzioni non resettano hsTriggerPrice, che resta > 0).
   if(st == CYCLE_ACTIVE && !g_cycles[slot].hsPending && !g_cycles[slot].hsActive
      && g_cycles[slot].hsTicket == 0 && g_cycles[slot].hsTriggerPrice == 0
      && !VirtualMode)
   {
      HsPlaceOrder(slot, sig);
      return;
   }

   // ── Detect fill se pendente ──
   if(g_cycles[slot].hsPending)
      HsDetectFill(slot);

   // Se non ancora attivo → niente da monitorare
   if(!g_cycles[slot].hsActive) return;

   // ── Verifica se Soup ancora aperta ──
   // (la chiusura HS al TP Soup è gestita in MonitorActive → SoupClosed_MonitorActive)
   bool soupOpen = (g_cycles[slot].ticket > 0)
                   && PositionSelectByTicket(g_cycles[slot].ticket);
   if(!soupOpen)
   {
      // Fallback di sicurezza: se MonitorActive non ha già fatto cleanup
      HsCleanup(slot, "SoupClosed_HsMonitorFallback");
      return;
   }

   // ── Calcola pip profit HS corrente ──
   double hsPipProfit = 0;
   double hsFillPx    = g_cycles[slot].hsFillPrice;

   if(hsFillPx > 0 && PositionSelectByTicket(g_cycles[slot].hsTicket))
   {
      double curPx = PositionGetDouble(POSITION_PRICE_CURRENT);
      // SELL HS (da BUY Soup): profitto quando prezzo scende (fillPx > curPx)
      // BUY HS  (da SELL Soup): profitto quando prezzo sale  (curPx > fillPx)
      if(g_cycles[slot].direction > 0)
         hsPipProfit = PointsToPips(hsFillPx - curPx);
      else
         hsPipProfit = PointsToPips(curPx - hsFillPx);
   }

   // ── Calcola barre attive dall'attivazione ──
   int barsActive = 0;
   if(g_cycles[slot].hsFillTime > 0)
   {
      int periodSec = PeriodSeconds();
      if(periodSec > 0)
         barsActive = (int)((TimeCurrent() - g_cycles[slot].hsFillTime) / periodSec);
   }

   // ════════════════════════════════════════════════════════════
   // STEP 1 — PRE-BE: sposta SL da midline → fill (breakeven vero)
   // Trigger: HS accumula HsStep1Pct × cw pip di profitto
   // Effetto: l'HS non può più trasformarsi in perdita
   //
   // TODO v1.7.3 — STEP 0.5 (intermedio, da valutare):
   //   Dopo ~50% del threshold Step1 (es. 6pip su 12), spostare SL
   //   dalla midline al bordo del canale violato ± pochi pip.
   //   Geometria: BUY Soup → SL da midline a lowerBand + 2pip
   //              SELL Soup → SL da midline a upperBand - 2pip
   //   Effetto: riduce rischio da ~32pip a ~14pip prima del full BE.
   //   La banda è supporto/resistenza naturale: se prezzo la ripassa,
   //   la Soup funziona (mean reversion) e l'HS non serve più.
   //   Richiede: nuovo flag hsBandSLSet, nuovo input HsStep05Pct,
   //             e salvataggio della banda (sig.lowerBand/upperBand)
   //             nella struct al momento del segnale.
   // ════════════════════════════════════════════════════════════
   if(HsBEEnabled && !g_cycles[slot].hsBESet && hsFillPx > 0)
   {
      // Calcola step1 threshold in pip usando cw dal tpRefLevel
      double cw_approx = 0;
      if(g_cycles[slot].hsTpRefLevel > 0 && HsTpPct > 0)
         cw_approx = MathAbs(g_cycles[slot].hsTriggerPrice - g_cycles[slot].hsTpRefLevel) / HsTpPct;

      double step1Pips = (cw_approx > 0)
                       ? PointsToPips(cw_approx * HsStep1Pct)
                       : 6.0;  // fallback 6pip se cw non disponibile

      if(hsPipProfit >= step1Pips)
      {
         double newSL    = hsFillPx;  // breakeven = prezzo di fill reale
         bool   slOK     = true;

         // Verifica distanza minima broker prima di modificare
         if(PositionSelectByTicket(g_cycles[slot].hsTicket))
         {
            double curPx   = PositionGetDouble(POSITION_PRICE_CURRENT);
            double dist    = MathAbs(curPx - newSL);
            double minDist = (g_symbolStopsLevel + 2) * g_symbolPoint;
            if(dist < minDist)
            {
               AdLogD(LOG_CAT_HEDGE, StringFormat(
                  "HS Step1 BE: SL troppo vicino al prezzo corrente (dist=%.5f < min=%.5f) — attendo barra successiva",
                  dist, minDist));
               slOK = false;
            }
         }

         if(slOK)
         {
            g_trade.SetExpertMagicNumber(MagicNumber + 1);
            if(g_trade.PositionModify(g_cycles[slot].hsTicket, newSL, 0))
            {
               g_cycles[slot].hsBESet = true;
               HsDrawBEMarker(slot, newSL);
               AdLogI(LOG_CAT_HEDGE, StringFormat(
                  "=== HS STEP1 BE SET #%d === SL spostato a fill=%.5f | profit=%.1fpip (soglia=%.1fpip)",
                  g_cycles[slot].cycleID, newSL, hsPipProfit, step1Pips));
            }
            else
            {
               AdLogW(LOG_CAT_HEDGE, StringFormat(
                  "HS Step1 BE MODIFY FAILED #%d: %s",
                  g_cycles[slot].cycleID,
                  g_trade.ResultRetcodeDescription()));
            }
         }
      }
   }

   // ════════════════════════════════════════════════════════════
   // STEP 2 — CLOSE AL TPREVLEVEL: chiudi HS con profitto
   // Trigger: prezzo raggiunge tpRefLevel (= HsTpPct × cw dal trigger)
   // Condizione: BE già impostato (Step1 deve essere completato prima)
   // Effetto: incassa il profitto massimo teorico dell'HS
   // ════════════════════════════════════════════════════════════
   if(HsUseStep2Close && !g_cycles[slot].hsStep2Reached
      && g_cycles[slot].hsTpRefLevel > 0
      && g_cycles[slot].hsBESet)
   {
      bool tpHit = false;
      if(PositionSelectByTicket(g_cycles[slot].hsTicket))
      {
         double curPx = PositionGetDouble(POSITION_PRICE_CURRENT);
         // SELL HS: tpRefLevel è SOTTO il trigger → TP quando curPx <= tpRefLevel
         // BUY HS:  tpRefLevel è SOPRA il trigger → TP quando curPx >= tpRefLevel
         if(g_cycles[slot].direction > 0)
            tpHit = (curPx <= g_cycles[slot].hsTpRefLevel);
         else
            tpHit = (curPx >= g_cycles[slot].hsTpRefLevel);
      }

      if(tpHit)
      {
         g_cycles[slot].hsStep2Reached = true;
         HsDrawTPMarker(slot, g_cycles[slot].hsTpRefLevel);
         AdLogI(LOG_CAT_HEDGE, StringFormat(
            "=== HS STEP2 TP HIT #%d === tpRefLevel=%.5f | profit=%.1fpip",
            g_cycles[slot].cycleID,
            g_cycles[slot].hsTpRefLevel, hsPipProfit));
         HsClose(slot, "Step2_TpRefLevel");
         return;
      }
   }

   // ════════════════════════════════════════════════════════════
   // EXIT 1 — Prossimo segnale DPC nella stessa direzione della Soup
   // (anti-whipsaw: attendere minimo HsAntiWhipsawBars barre)
   // ════════════════════════════════════════════════════════════
   if(hasNewSignal && sig.isNewSignal && sig.direction == g_cycles[slot].direction)
   {
      if(barsActive >= HsAntiWhipsawBars)
      {
         AdLogI(LOG_CAT_HEDGE, StringFormat(
            "HS EXIT1: NextDPCSignal #%d | barsActive=%d | dir=%d",
            g_cycles[slot].cycleID, barsActive, sig.direction));
         HsClose(slot, "NextDPCSignal");
         return;
      }
      else
      {
         AdLogD(LOG_CAT_HEDGE, StringFormat(
            "HS anti-whipsaw #%d: segnale troppo presto (%d<%d barre)",
            g_cycles[slot].cycleID, barsActive, HsAntiWhipsawBars));
      }
   }

   // ════════════════════════════════════════════════════════════
   // EXIT 2 — Timeout: rete di sicurezza finale
   // HsTimeoutBars default = 32 (8h su M15)
   // ════════════════════════════════════════════════════════════
   if(HsTimeoutBars > 0 && barsActive >= HsTimeoutBars)
   {
      AdLogI(LOG_CAT_HEDGE, StringFormat(
         "HS EXIT2: Timeout #%d | barsActive=%d >= %d | profit=%.1fpip",
         g_cycles[slot].cycleID, barsActive, HsTimeoutBars, hsPipProfit));
      HsClose(slot, "Timeout");
      return;
   }

   // ── Log diagnostico periodico ──
   if(barsActive % 8 == 0 && barsActive > 0)
   {
      AdLogD(LOG_CAT_HEDGE, StringFormat(
         "HS LIVE #%d | bars=%d | profit=%.1fpip | BE=%s | Step2=%s | SL(broker)=%s",
         g_cycles[slot].cycleID, barsActive, hsPipProfit,
         g_cycles[slot].hsBESet ? "SET" : "no",
         g_cycles[slot].hsStep2Reached ? "HIT" : "no",
         PositionSelectByTicket(g_cycles[slot].hsTicket)
            ? DoubleToString(PositionGetDouble(POSITION_SL), _Digits)
            : "n/a"));
   }
}
