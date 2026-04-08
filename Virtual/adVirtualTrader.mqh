//+------------------------------------------------------------------+
//|                                       adVirtualTrader.mqh        |
//|           AcquaDulza EA v1.6.1 — Virtual (Paper) Trader          |
//|                                                                  |
//|  Simulates trade cycles without broker orders.                   |
//|  Uses same CycleRecord structure for consistency.                |
//|  Enabled via VirtualMode input parameter.                        |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| Virtual Trade State                                              |
//+------------------------------------------------------------------+
double   g_virtualTotalProfit = 0;
int      g_virtualWins  = 0;
int      g_virtualLosses = 0;

//+------------------------------------------------------------------+
//| VirtualCreateTrade — Simulate order placement                   |
//|  No actual OrderSend — just record the cycle                     |
//+------------------------------------------------------------------+
int VirtualCreateTrade(const EngineSignal &sig)
{
   if(CountActiveCycles() >= MaxConcurrentTrades) return -1;

   int slot = FindFreeCycleSlot();
   if(slot < 0) return -1;

   g_nextCycleID++;
   double slDist = MathAbs(sig.entryPrice - sig.slPrice);

   g_cycles[slot].cycleID    = g_nextCycleID;
   g_cycles[slot].direction  = sig.direction;
   g_cycles[slot].state      = CYCLE_ACTIVE;  // Immediately "filled"
   g_cycles[slot].ticket     = 0;             // No real ticket
   g_cycles[slot].entryPrice = sig.entryPrice;
   g_cycles[slot].slPrice    = sig.slPrice;
   g_cycles[slot].tpPrice    = sig.tpPrice;
   g_cycles[slot].lotSize    = CalculateLotSize(slDist, sig.quality);
   g_cycles[slot].signalTime = sig.barTime;
   g_cycles[slot].placedTime = TimeCurrent();
   g_cycles[slot].quality    = sig.quality;
   g_cycles[slot].profit     = 0;

   g_totalSignals++;
   if(sig.direction > 0) g_buySignals++;
   else g_sellSignals++;

   AdLogI(LOG_CAT_VIRTUAL, StringFormat("VIRTUAL #%d %s | Entry=%s | SL=%s | TP=%s | Lot=%.2f",
          g_nextCycleID, sig.direction > 0 ? "BUY" : "SELL",
          FormatPrice(sig.entryPrice), FormatPrice(sig.slPrice),
          FormatPrice(sig.tpPrice), g_cycles[slot].lotSize));

   return slot;
}

//+------------------------------------------------------------------+
//| VirtualMonitor — Check active virtual trades against price      |
//|  Simulates TP/SL hits using current bid/ask                      |
//+------------------------------------------------------------------+
void VirtualMonitor()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_ACTIVE) continue;
      if(g_cycles[i].ticket != 0) continue;  // Skip real trades

      // [MOD] SL rimosso — solo monitoraggio TP per trade virtuali.
      // Prima qui c'erano anche i check per SL hit:
      //   BUY:  if(slPrice > 0 && bid <= slPrice) slHit = true;
      //   SELL: if(slPrice > 0 && ask >= slPrice) slHit = true;
      // Ora i trade virtuali si chiudono solo quando il TP viene raggiunto.
      bool tpHit = false;

      if(g_cycles[i].direction > 0)  // Virtual BUY: TP colpito quando bid >= tpPrice
      {
         if(g_cycles[i].tpPrice > 0 && bid >= g_cycles[i].tpPrice)
            tpHit = true;
      }
      else  // Virtual SELL: TP colpito quando ask <= tpPrice
      {
         if(g_cycles[i].tpPrice > 0 && ask <= g_cycles[i].tpPrice)
            tpHit = true;
      }

      if(tpHit)
      {
         // Calculate simulated profit (solo TP, niente SL)
         double exitPrice = g_cycles[i].tpPrice;

         double priceDiff = (g_cycles[i].direction > 0) ?
            (exitPrice - g_cycles[i].entryPrice) :
            (g_cycles[i].entryPrice - exitPrice);

         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double profit = 0;
         if(tickSize > 0)
            profit = (priceDiff / tickSize) * tickValue * g_cycles[i].lotSize;

         g_cycles[i].profit = profit;
         g_cycles[i].state  = CYCLE_CLOSED;

         g_virtualTotalProfit += profit;
         if(profit > 0) g_virtualWins++;
         else           g_virtualLosses++;

         g_sessionRealizedProfit += profit;
         g_dailyRealizedProfit   += profit;

         string result = "TP HIT";  // [MOD] SL rimosso, solo TP possibile
         AdLogI(LOG_CAT_VIRTUAL, StringFormat("VIRTUAL CLOSED #%d — %s | Profit=%.2f | Total=%.2f | W=%d L=%d",
                g_cycles[i].cycleID, result, profit, g_virtualTotalProfit,
                g_virtualWins, g_virtualLosses));
      }
   }
}


