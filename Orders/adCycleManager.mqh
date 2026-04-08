//+------------------------------------------------------------------+
//|                                        adCycleManager.mqh        |
//|           AcquaDulza EA v1.7.2 — Cycle Manager                   |
//|                                                                  |
//|  Manages trade cycles: create, monitor, expire, detect fills     |
//|  HedgeSmart: 13 campi HS in CycleRecord (v1.7.0 + v1.7.2)      |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| IsPositionOpen — Check if position ticket still exists          |
//+------------------------------------------------------------------+
bool IsPositionOpen(ulong ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == ticket)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetClosedPositionProfit — P&L realizzato da deal history         |
//|                                                                  |
//| Cerca negli ultimi 7 giorni di deal history per trovare          |
//| le uscite (DEAL_ENTRY_OUT) associate al posTicket.               |
//| Include: DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION per il       |
//| P&L netto reale (non solo il delta prezzo).                     |
//|                                                                  |
//| NOTA: 7 giorni copre la vita massima ragionevole di un ciclo.   |
//| Se un ciclo dura piu' di 7 giorni, il P&L non sara' trovato.   |
//| Match by DEAL_POSITION_ID == posTicket (non per magic, perche'  |
//| il position ID e' univoco per posizione).                        |
//+------------------------------------------------------------------+
double GetClosedPositionProfit(ulong posTicket)
{
   // Search in deal history — finestra 7 giorni
   datetime from = TimeCurrent() - 86400 * 7;
   if(!HistorySelect(from, TimeCurrent()))
   {
      AdLogW(LOG_CAT_CYCLE, StringFormat("GetClosedPositionProfit: HistorySelect failed for ticket=%d", posTicket));
   }

   double totalProfit = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;

      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         // Match by position ID
         ulong posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         if(posId == posTicket)
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
//| GetFloatingProfit — Get unrealized P&L of open position         |
//+------------------------------------------------------------------+
double GetFloatingProfit(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0;
   return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
}

//+------------------------------------------------------------------+
//| CountActiveCycles — Count non-CLOSED cycles                     |
//+------------------------------------------------------------------+
int CountActiveCycles()
{
   int count = 0;
   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_IDLE && g_cycles[i].state != CYCLE_CLOSED)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| FindFreeCycleSlot — Find first IDLE/CLOSED slot                 |
//+------------------------------------------------------------------+
int FindFreeCycleSlot()
{
   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state == CYCLE_IDLE || g_cycles[i].state == CYCLE_CLOSED)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| CreateCycle — Create new trade cycle from EngineSignal          |
//|  Returns: slot index, or -1 if full                              |
//+------------------------------------------------------------------+
int CreateCycle(const EngineSignal &sig)
{
   string dirStr = sig.direction > 0 ? "BUY" : "SELL";

   // ── DIAG: Log ingresso in CreateCycle ──
   AdLogD(LOG_CAT_CYCLE, StringFormat("DIAG CreateCycle: %s | Entry=%s | TP=%s | Quality=%d",
          dirStr, FormatPrice(sig.entryPrice), FormatPrice(sig.tpPrice), sig.quality));

   // Check max concurrent
   int activeCycles = CountActiveCycles();
   if(activeCycles >= MaxConcurrentTrades)
   {
      AdLogW(LOG_CAT_CYCLE, StringFormat("DIAG BLOCCATO: Max concurrent trades raggiunto: %d/%d — ordine NON creato",
             activeCycles, MaxConcurrentTrades));
      return -1;
   }
   AdLogD(LOG_CAT_CYCLE, StringFormat("DIAG: Cicli attivi %d/%d — OK, procedo", activeCycles, MaxConcurrentTrades));

   int slot = FindFreeCycleSlot();
   if(slot < 0)
   {
      AdLogW(LOG_CAT_CYCLE, "DIAG BLOCCATO: Nessuno slot libero nel cycle array — ordine NON creato");
      return -1;
   }
   AdLogD(LOG_CAT_CYCLE, StringFormat("DIAG: Slot libero trovato: %d", slot));

   // Initialize cycle
   g_nextCycleID++;
   g_cycles[slot].cycleID         = g_nextCycleID;
   g_cycles[slot].direction       = sig.direction;
   g_cycles[slot].state           = CYCLE_PENDING;
   g_cycles[slot].ticket          = 0;
   g_cycles[slot].entryPrice      = sig.entryPrice;
   g_cycles[slot].slPrice         = sig.slPrice;
   g_cycles[slot].tpPrice         = sig.tpPrice;
   g_cycles[slot].lotSize         = 0;
   g_cycles[slot].signalTime      = sig.barTime;
   g_cycles[slot].placedTime      = iTime(_Symbol, PERIOD_CURRENT, 0);
   g_cycles[slot].quality         = sig.quality;
   g_cycles[slot].profit          = 0;
   // HedgeSmart fields reset
   g_cycles[slot].hsTicket            = 0;
   g_cycles[slot].hsTriggerPrice      = 0;
   g_cycles[slot].hsTpRefLevel        = 0;
   g_cycles[slot].hsLotSize           = 0;
   g_cycles[slot].hsPending           = false;
   g_cycles[slot].hsActive            = false;
   g_cycles[slot].hsFillTime          = 0;
   g_cycles[slot].hsLineName          = "";
   g_cycles[slot].hsPL                = 0;
   // v1.7.2 — Step1 BE + Step2 TP
   g_cycles[slot].hsFillPrice         = 0;
   g_cycles[slot].hsMidlineAtSignal   = 0;
   g_cycles[slot].hsBESet             = false;
   g_cycles[slot].hsStep2Reached      = false;

   // [MOD] SL rimosso — CalculateLotSize(0, quality) usa il LotSize fisso come fallback.
   // Il secondo parametro (sig.quality) applica il moltiplicatore TBS/TWS:
   //   TBS (corpo penetra banda) → TBSLotMultiplier (default 2.0x = doppio lotto)
   //   TWS (solo wick tocca)     → TWSLotMultiplier (default 1.0x = lotto standard)
   g_cycles[slot].lotSize = CalculateLotSize(0, sig.quality);
   AdLogD(LOG_CAT_CYCLE, StringFormat("DIAG: LotSize calcolato=%.4f (RiskMode=%s, Quality=%s, Mult=%.1fx)",
          g_cycles[slot].lotSize, EnumToString(RiskMode),
          sig.quality == PATTERN_TBS ? "TBS" : "TWS",
          sig.quality == PATTERN_TBS ? TBSLotMultiplier : TWSLotMultiplier));

   // ── DIAG: Log pre-OrderPlace ──
   AdLogD(LOG_CAT_CYCLE, StringFormat("DIAG: Invoco OrderPlace() — CycleID=#%d | %s | Lot=%.4f | Entry=%s | TP=%s",
          g_nextCycleID, dirStr, g_cycles[slot].lotSize, FormatPrice(sig.entryPrice), FormatPrice(sig.tpPrice)));

   // Place order
   ulong ticket = OrderPlace(sig, g_cycles[slot].lotSize, g_nextCycleID);

   if(ticket > 0)
   {
      g_cycles[slot].ticket = ticket;

      // For MARKET mode, position is immediately active
      if(EntryMode == ENTRY_MARKET)
         g_cycles[slot].state = CYCLE_ACTIVE;

      AdLogI(LOG_CAT_CYCLE, StringFormat("CYCLE #%d CREATED | %s %s | Ticket=%d | Lot=%.2f | Entry=%s | SL=%s | TP=%s",
             g_nextCycleID, dirStr,
             sig.quality == PATTERN_TBS ? "TBS" : "TWS",
             ticket, g_cycles[slot].lotSize,
             FormatPrice(sig.entryPrice), FormatPrice(sig.slPrice), FormatPrice(sig.tpPrice)));

      // Update signal counters
      g_totalSignals++;
      if(sig.direction > 0) g_buySignals++;
      else g_sellSignals++;
      g_lastSignalTime = TimeCurrent();
      g_dailyCyclesCount++;

      return slot;
   }
   else
   {
      g_cycles[slot].state = CYCLE_CLOSED;
      AdLogW(LOG_CAT_CYCLE, StringFormat("CYCLE #%d FAILED — OrderPlace() ha ritornato 0 — ordine NON piazzato", g_nextCycleID));
      AdLogW(LOG_CAT_CYCLE, "DIAG: Controlla i log [ORDER] sopra per il motivo specifico del fallimento");
      return -1;
   }
}

//+------------------------------------------------------------------+
//| DetectFill — Layer 1: OnTradeTransaction (reactive)             |
//|  Instant detection when STOP/LIMIT fills                         |
//+------------------------------------------------------------------+
void DetectFill(const MqlTradeTransaction& trans,
                const MqlTradeRequest& request,
                const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;
   if(!HistoryDealSelect(dealTicket)) return;

   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

   if(dealMagic != MagicNumber || dealEntry != DEAL_ENTRY_IN) return;

   double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   string dealComment = HistoryDealGetString(dealTicket, DEAL_COMMENT);

   if(StringFind(dealComment, "AD_") < 0) return;

   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_PENDING) continue;

      if(StringFind(dealComment, StringFormat("#%d", g_cycles[i].cycleID)) >= 0)
      {
         double slippage = PointsToPips(MathAbs(dealPrice - g_cycles[i].entryPrice));

         g_cycles[i].entryPrice = dealPrice;
         g_cycles[i].state      = CYCLE_ACTIVE;

         AdLogI(LOG_CAT_CYCLE, StringFormat("=== FILLED #%d === %s @ %s | Slippage=%.1fp",
                g_cycles[i].cycleID,
                g_cycles[i].direction > 0 ? "BUY" : "SELL",
                FormatPrice(dealPrice), slippage));

         // v1.8.0: Soup fillata → piazza HS pending (ordine STOP opposto al Soup).
         // g_lastSignal contiene le bande correnti dall'ultimo EngineCalculate.
         // HsPlaceOrder ha guard interni (hsPending/hsActive → skip).
         if(EnableHedge && HsEnabled && !VirtualMode)
            HsPlaceOrder(i, g_lastSignal);

         break;
      }
   }
}

//+------------------------------------------------------------------+
//| PollFills — Layer 2: Polling backup for missed fills            |
//|                                                                  |
//| DetectFill (Layer 1) usa OnTradeTransaction per fill istantaneo. |
//| Questo polling e' il FALLBACK: se la transazione manca           |
//| (broker lag, riconnessione), PollFills rileva il fill cercando   |
//| il ticket tra le posizioni aperte.                               |
//|                                                                  |
//| Se il pending e' sparito e la posizione NON esiste, il ciclo    |
//| viene chiuso come DISAPPEARED (ordine rifiutato silenziosamente).|
//+------------------------------------------------------------------+
void PollFills()
{
   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_PENDING) continue;

      // Check if pending order still exists
      bool pendingExists = false;
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         if(OrderGetTicket(j) == g_cycles[i].ticket)
         {
            pendingExists = true;
            break;
         }
      }

      if(!pendingExists)
      {
         // Search in positions
         bool foundAsPosition = false;
         for(int j = PositionsTotal() - 1; j >= 0; j--)
         {
            ulong posTicket = PositionGetTicket(j);
            if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, StringFormat("#%d", g_cycles[i].cycleID)) >= 0)
            {
               g_cycles[i].ticket     = posTicket;
               g_cycles[i].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               g_cycles[i].state      = CYCLE_ACTIVE;
               foundAsPosition = true;

               AdLogI(LOG_CAT_CYCLE, StringFormat("POLL FILLED #%d | Ticket=%d @ %s",
                      g_cycles[i].cycleID, posTicket, FormatPrice(g_cycles[i].entryPrice)));

               // v1.8.0: Soup fillata (poll fallback) → piazza HS pending.
               // Identico a DetectFill: backup se OnTradeTransaction non arriva.
               if(EnableHedge && HsEnabled && !VirtualMode)
                  HsPlaceOrder(i, g_lastSignal);

               break;
            }
         }

         if(!foundAsPosition)
         {
            g_cycles[i].state = CYCLE_CLOSED;
            AdLogW(LOG_CAT_CYCLE, StringFormat("POLL DISAPPEARED #%d — closing cycle", g_cycles[i].cycleID));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CheckExpiry — Cancel pending orders after N bars                |
//|                                                                  |
//| Cancella ordini pendenti che non sono stati riempiti entro       |
//| g_dpc_pendingExpiry barre. Il valore e' TF-aware:               |
//|   M5=3 (15min), M15=3 (45min), M30=3 (90min)                   |
//| Se pendingExpiry=0, la scadenza e' disabilitata.                 |
//+------------------------------------------------------------------+
void CheckExpiry()
{
   if(g_dpc_pendingExpiry <= 0) return;

   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_PENDING) continue;
      if(g_cycles[i].placedTime == 0) continue;

      int barsElapsed = iBarShift(_Symbol, PERIOD_CURRENT, g_cycles[i].placedTime);

      // Log check pre-expiry per debugging (ogni barra per ogni pending)
      AdLogD(LOG_CAT_CYCLE, StringFormat(
         "DIAG Expiry check #%d: barsElapsed=%d / max=%d",
         g_cycles[i].cycleID, barsElapsed, g_dpc_pendingExpiry));

      if(barsElapsed >= g_dpc_pendingExpiry)
      {
         AdLogI(LOG_CAT_CYCLE, StringFormat("EXPIRING #%d after %d/%d bars",
                g_cycles[i].cycleID, barsElapsed, g_dpc_pendingExpiry));

         DeletePendingOrder(g_cycles[i].ticket);
         g_cycles[i].state = CYCLE_CLOSED;
         g_totalExpiredOrders++;
      }
   }
}

//+------------------------------------------------------------------+
//| UpdatePending — Modify pending if bands moved (STOP mode)       |
//+------------------------------------------------------------------+
void UpdatePending(const EngineSignal &sig)
{
   if(EntryMode != ENTRY_STOP) return;

   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_PENDING) continue;
      if(!OrderSelect(g_cycles[i].ticket)) continue;

      double newEntry = sig.entryPrice;
      double newTP    = sig.tpPrice;

      // Skip se il segnale non ha prezzi validi (nessun segnale attivo)
      if(newEntry <= 0 || newTP <= 0) continue;

      // Only modify if difference > 1 pip
      double entryDiff = MathAbs(newEntry - g_cycles[i].entryPrice);
      double tpDiff    = MathAbs(newTP - g_cycles[i].tpPrice);

      if(entryDiff > PipsToPrice(1.0) || tpDiff > PipsToPrice(1.0))
      {
         // [MOD] SL rimosso: terzo parametro (sl) impostato a 0.
         // Prima si passava g_cycles[i].slPrice, ora sempre 0 (nessun stop loss).
         if(ModifyPendingOrder(g_cycles[i].ticket, newEntry, 0, newTP))
         {
            AdLogI(LOG_CAT_CYCLE, StringFormat("UPD #%d | Entry: %s->%s | TP: %s->%s",
                   g_cycles[i].cycleID,
                   FormatPrice(g_cycles[i].entryPrice), FormatPrice(newEntry),
                   FormatPrice(g_cycles[i].tpPrice), FormatPrice(newTP)));
            g_cycles[i].entryPrice = newEntry;
            g_cycles[i].tpPrice    = newTP;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MonitorActive — Monitor active positions, detect closes         |
//|                                                                  |
//| P&L ACCOUNTING:                                                  |
//|   g_cycles[i].profit = soupPL + hsPL                             |
//|     → include P&L HS già realizzato per display NET dashboard    |
//|   g_sessionRealizedProfit += soupPL ONLY                         |
//|     → hsPL è già stato aggiunto a session quando HsClose() è    |
//|       stato chiamato (prevenzione double-counting)               |
//+------------------------------------------------------------------+
void MonitorActive()
{
   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      // v1.7.2: include CYCLE_HEDGING — quando Soup chiude con HS attiva,
      // MonitorActive deve contabilizzare soupPL e fare HsCleanup
      if(g_cycles[i].state != CYCLE_ACTIVE && g_cycles[i].state != CYCLE_HEDGING) continue;

      if(!IsPositionOpen(g_cycles[i].ticket))
      {
         // v1.7.2: Chiudi HS contestualmente alla chiusura Soup
         // Sostituisce l'ex Exit 2 (HsCloseOnSoupProfit) rimossa da HsMonitor
         if(EnableHedge && HsEnabled)
         {
            AdLogI(LOG_CAT_HEDGE, StringFormat(
               "HS CLEANUP on SoupClose #%d (Soup ticket=%d closed by broker/TP)",
               g_cycles[i].cycleID, g_cycles[i].ticket));
            HsCleanup(i, "SoupClosed_MonitorActive");
         }

         // Position closed (TP/SL hit or manual close)
         double soupPL = GetClosedPositionProfit(g_cycles[i].ticket);
         // Cycle NET = soupPL + hsPL (per display dashboard)
         // Session += soupPL ONLY (hsPL gia' contabilizzato da HsClose)
         g_cycles[i].profit = soupPL + g_cycles[i].hsPL;
         g_cycles[i].state  = CYCLE_CLOSED;

         // Update counters — solo soupPL (hsPL gia' aggiunto a session da HsClose)
         g_sessionRealizedProfit += soupPL;
         g_dailyRealizedProfit   += soupPL;
         double netPL = g_cycles[i].profit;  // NET = soupPL + hsPL
         if(netPL > 0) { g_sessionWins++; g_dailyWins++; }
         else          { g_sessionLosses++; g_dailyLosses++; }

         string result = netPL > 0 ? "WIN" : "LOSS";
         AdLogI(LOG_CAT_CYCLE, StringFormat("=== CLOSED #%d — %s === %s | Profit=%.2f | Session: W=%d L=%d PL=%.2f",
                g_cycles[i].cycleID, result,
                g_cycles[i].direction > 0 ? "BUY" : "SELL", netPL,
                g_sessionWins, g_sessionLosses, g_sessionRealizedProfit));

         // Alert popup + Feed item for dashboard
         if(netPL > 0)
         {
            Alert(StringFormat("AcquaDulza TP HIT #%d %s | Profit=+%.2f | TP=%s | %s",
                  g_cycles[i].cycleID,
                  g_cycles[i].direction > 0 ? "BUY" : "SELL",
                  netPL, FormatPrice(g_cycles[i].tpPrice), _Symbol));
            AddFeedItem("TP hit " + FormatPrice(g_cycles[i].tpPrice) + " +$" + DoubleToString(netPL, 2), AD_BUY);
         }
         else
         {
            Alert(StringFormat("AcquaDulza CLOSED #%d %s | Loss=%.2f | %s",
                  g_cycles[i].cycleID,
                  g_cycles[i].direction > 0 ? "BUY" : "SELL",
                  netPL, _Symbol));
            AddFeedItem("SL hit -$" + DoubleToString(MathAbs(netPL), 2), AD_SELL);
         }

         Log_PositionClosed(g_cycles[i].ticket, result, netPL,
                           g_cycles[i].entryPrice);

         // Cleanup chart objects: TP hit marker + remove TP line/dot
         if(netPL > 0 && ShowTPTargetLines)
            DrawTPHitMarker(g_cycles[i].cycleID, g_cycles[i].tpPrice, TimeCurrent());
         RemoveTPLine(g_cycles[i].cycleID);
      }
   }
}

//+------------------------------------------------------------------+
//| MonitorCycles — Full cycle monitoring (call each tick/new bar)  |
//+------------------------------------------------------------------+
void MonitorCycles(const EngineSignal &sig)
{
   PollFills();
   CheckExpiry();
   UpdatePending(sig);
   MonitorActive();
}

//+------------------------------------------------------------------+
//| InitializeCycles — Reset all cycle slots                        |
//+------------------------------------------------------------------+
void InitializeCycles()
{
   ArrayResize(g_cycles, MAX_CYCLES);
   for(int i = 0; i < MAX_CYCLES; i++)
   {
      g_cycles[i].state     = CYCLE_IDLE;
      g_cycles[i].cycleID   = 0;
      g_cycles[i].ticket    = 0;
      g_cycles[i].direction = 0;
      g_cycles[i].entryPrice = 0;
      g_cycles[i].slPrice   = 0;
      g_cycles[i].tpPrice   = 0;
      g_cycles[i].lotSize   = 0;
      g_cycles[i].signalTime = 0;
      g_cycles[i].placedTime = 0;
      g_cycles[i].quality   = 0;
      g_cycles[i].profit    = 0;
      // HedgeSmart fields
      g_cycles[i].hsTicket            = 0;
      g_cycles[i].hsTriggerPrice      = 0;
      g_cycles[i].hsTpRefLevel        = 0;
      g_cycles[i].hsLotSize           = 0;
      g_cycles[i].hsPending           = false;
      g_cycles[i].hsActive            = false;
      g_cycles[i].hsFillTime          = 0;
      g_cycles[i].hsLineName          = "";
      g_cycles[i].hsPL                = 0;
      // v1.7.2 — Step1 BE + Step2 TP
      g_cycles[i].hsFillPrice         = 0;
      g_cycles[i].hsMidlineAtSignal   = 0;
      g_cycles[i].hsBESet             = false;
      g_cycles[i].hsStep2Reached      = false;
   }

   Log_InitComplete("Cycle Manager");
}
