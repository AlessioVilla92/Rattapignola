//+------------------------------------------------------------------+
//|                                    adRecoveryManager.mqh         |
//|           AcquaDulza EA v1.7.2 — Recovery Manager                |
//|                                                                  |
//|  Broker scan recovery: reconstruct cycles from positions/orders  |
//|                                                                  |
//|  Magic: Soup=MagicNumber, HS=MagicNumber+1                       |
//|  Legacy H2 (Magic+2): auto-cleanup al primo avvio post-v1.7.0   |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| Recovery Variables                                               |
//+------------------------------------------------------------------+
bool     g_recoveryPerformed  = false;
int      g_recoveredPositions = 0;
int      g_recoveredPendings  = 0;

//+------------------------------------------------------------------+
//| ParseCycleIDFromComment — Extract cycle ID from order comment   |
//|                                                                  |
//| Il comment di ogni ordine/posizione AcquaDulza segue il formato: |
//|   Soup: "AD_BUY_#12" / "AD_SELL_#3"                             |
//|   HS:   "AD_HS_SELL_#12" / "AD_HS_BUY_#3"                      |
//| Questa funzione estrae il numero dopo "#".                       |
//| Il cycleID e' l'unico modo affidabile per collegare              |
//| Soup → HS durante il recovery (non il ticket).                   |
//+------------------------------------------------------------------+
int ParseCycleIDFromComment(string comment)
{
   int hashPos = StringFind(comment, "#");
   if(hashPos < 0) return -1;

   string idStr = StringSubstr(comment, hashPos + 1);

   // Remove non-numeric chars after ID
   int len = StringLen(idStr);
   for(int i = 0; i < len; i++)
   {
      int ch = StringGetCharacter(idStr, i);
      if(ch < '0' || ch > '9')
      {
         idStr = StringSubstr(idStr, 0, i);
         break;
      }
   }

   if(StringLen(idStr) == 0) return -1;
   return (int)StringToInteger(idStr);
}

//+------------------------------------------------------------------+
//| ParseDirection — Determine direction from comment               |
//+------------------------------------------------------------------+
int ParseDirectionFromComment(string comment)
{
   if(StringFind(comment, "AD_BUY") >= 0)  return +1;
   if(StringFind(comment, "AD_SELL") >= 0) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| FindOrCreateCycleSlot — Find existing or create new slot        |
//+------------------------------------------------------------------+
int FindOrCreateCycleSlot(int cycleID)
{
   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].cycleID == cycleID)
         return i;
   }

   int newSize = ArraySize(g_cycles) + 1;
   if(newSize > MAX_CYCLES) newSize = MAX_CYCLES;
   ArrayResize(g_cycles, newSize);
   int slot = newSize - 1;
   g_cycles[slot].state   = CYCLE_IDLE;
   g_cycles[slot].cycleID = cycleID;
   return slot;
}

//+------------------------------------------------------------------+
//| AttemptRecovery — Scan broker positions/orders, rebuild cycles  |
//|                                                                  |
//| ORDINE DI SCAN:                                                  |
//|  0. Cleanup Legacy H2 (Magic+2 — rimosso in v1.7.0)             |
//|  1. Soup positions (Magic) → crea cicli ACTIVE                   |
//|  2. HS positions (Magic+1) → associa ad existing cycle           |
//|  3. Soup pending (Magic) → crea cicli PENDING                    |
//|  4. HS pending (Magic+1) → associa                               |
//|                                                                  |
//| L'ordine importa: prima le positions (Soup crea lo slot),        |
//| poi gli hedge si associano allo slot gia' creato.                |
//+------------------------------------------------------------------+
void AttemptRecovery()
{
   AdLogI(LOG_CAT_RECOVERY, "=== STARTING BROKER SCAN ===");

   g_recoveredPositions = 0;
   g_recoveredPendings  = 0;
   int maxCycleID = 0;

   // === CLEANUP LEGACY H2 (MagicNumber+2 — rimosso in v1.7.0) ===
   {
      int legacyCleaned = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber + 2)
         {
            g_trade.SetExpertMagicNumber(MagicNumber + 2);
            g_trade.PositionClose(t);
            legacyCleaned++;
         }
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(t == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber + 2)
         {
            g_trade.SetExpertMagicNumber(MagicNumber + 2);
            g_trade.OrderDelete(t);
            legacyCleaned++;
         }
      }
      if(legacyCleaned > 0)
         AdLogW(LOG_CAT_RECOVERY, StringFormat(
            "Legacy H2 cleanup: %d ordini/posizioni Magic+2 rimossi", legacyCleaned));
   }

   // === SCAN OPEN POSITIONS ===
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      int cycleID = ParseCycleIDFromComment(comment);
      if(cycleID < 0) continue;

      int direction = ParseDirectionFromComment(comment);
      if(direction == 0) continue;

      int slot = FindOrCreateCycleSlot(cycleID);
      g_cycles[slot].direction  = direction;
      g_cycles[slot].ticket     = ticket;
      g_cycles[slot].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      g_cycles[slot].tpPrice    = PositionGetDouble(POSITION_TP);
      g_cycles[slot].slPrice    = PositionGetDouble(POSITION_SL);
      g_cycles[slot].lotSize    = PositionGetDouble(POSITION_VOLUME);
      g_cycles[slot].signalTime = (datetime)PositionGetInteger(POSITION_TIME);
      g_cycles[slot].state      = CYCLE_ACTIVE;

      AdLogI(LOG_CAT_RECOVERY, StringFormat("Position recovered — #%d %s | Ticket=%d | Entry=%s",
             cycleID, direction > 0 ? "BUY" : "SELL", ticket,
             DoubleToString(g_cycles[slot].entryPrice, _Digits)));

      if(cycleID > maxCycleID) maxCycleID = cycleID;
      g_recoveredPositions++;
   }

   // === SCAN HEDGE POSITIONS (MagicNumber + 1) ===
   if(EnableHedge)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber + 1) continue;

         string comment = PositionGetString(POSITION_COMMENT);
         int cycleID = ParseCycleIDFromComment(comment);
         if(cycleID < 0) continue;

         for(int j = 0; j < ArraySize(g_cycles); j++)
         {
            if(g_cycles[j].cycleID == cycleID)
            {
               g_cycles[j].hsTicket       = ticket;
               g_cycles[j].hsActive       = true;
               g_cycles[j].hsPending      = false;
               g_cycles[j].hsLotSize      = PositionGetDouble(POSITION_VOLUME);
               g_cycles[j].hsTriggerPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               g_cycles[j].hsFillTime     = (datetime)PositionGetInteger(POSITION_TIME);
               if(g_cycles[j].state == CYCLE_ACTIVE)
                  g_cycles[j].state = CYCLE_HEDGING;

               AdLogI(LOG_CAT_RECOVERY, StringFormat(
                  "HS position recovered — #%d | Ticket=%d | Entry=%s",
                  cycleID, ticket, DoubleToString(g_cycles[j].hsTriggerPrice, _Digits)));
               break;
            }
         }
      }
   }

   // === SCAN PENDING ORDERS ===
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

      string comment = OrderGetString(ORDER_COMMENT);
      int cycleID = ParseCycleIDFromComment(comment);
      if(cycleID < 0) continue;

      int direction = ParseDirectionFromComment(comment);
      if(direction == 0) continue;

      int slot = FindOrCreateCycleSlot(cycleID);
      g_cycles[slot].direction  = direction;
      g_cycles[slot].ticket     = ticket;
      g_cycles[slot].entryPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      g_cycles[slot].tpPrice    = OrderGetDouble(ORDER_TP);
      g_cycles[slot].slPrice    = OrderGetDouble(ORDER_SL);
      g_cycles[slot].lotSize    = OrderGetDouble(ORDER_VOLUME_CURRENT);
      g_cycles[slot].placedTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      g_cycles[slot].state      = CYCLE_PENDING;

      AdLogI(LOG_CAT_RECOVERY, StringFormat("Pending recovered — #%d %s | Ticket=%d | Entry=%s",
             cycleID, direction > 0 ? "BUY" : "SELL", ticket,
             DoubleToString(g_cycles[slot].entryPrice, _Digits)));

      if(cycleID > maxCycleID) maxCycleID = cycleID;
      g_recoveredPendings++;
   }

   // === SCAN HEDGE PENDING ORDERS (MagicNumber + 1) ===
   if(EnableHedge)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) != MagicNumber + 1) continue;

         string comment = OrderGetString(ORDER_COMMENT);
         int cycleID = ParseCycleIDFromComment(comment);
         if(cycleID < 0) continue;

         for(int j = 0; j < ArraySize(g_cycles); j++)
         {
            if(g_cycles[j].cycleID == cycleID)
            {
               g_cycles[j].hsTicket       = ticket;
               g_cycles[j].hsPending      = true;
               g_cycles[j].hsActive       = false;
               g_cycles[j].hsLotSize      = OrderGetDouble(ORDER_VOLUME_CURRENT);
               g_cycles[j].hsTriggerPrice = OrderGetDouble(ORDER_PRICE_OPEN);

               AdLogI(LOG_CAT_RECOVERY, StringFormat(
                  "HS pending recovered — #%d | Ticket=%d | Trigger=%s",
                  cycleID, ticket, DoubleToString(g_cycles[j].hsTriggerPrice, _Digits)));
               break;
            }
         }
      }
   }

   // Update next cycle ID
   g_nextCycleID = maxCycleID;

   // Summary
   int activeCycles = CountActiveCycles();
   g_recoveryPerformed = (g_recoveredPositions > 0 || g_recoveredPendings > 0);

   AdLogI(LOG_CAT_RECOVERY, StringFormat("=== SCAN COMPLETE === Positions=%d | Pendings=%d | Active=%d | NextID=%d",
          g_recoveredPositions, g_recoveredPendings, activeCycles, g_nextCycleID));

   if(g_recoveryPerformed)
   {
      g_systemState = STATE_ACTIVE;
      AdLogI(LOG_CAT_RECOVERY, StringFormat("System set to ACTIVE — recovered %d cycle(s)", activeCycles));
   }
   else
   {
      AdLogI(LOG_CAT_RECOVERY, "No AcquaDulza orders found — clean start");
   }
}
