//+------------------------------------------------------------------+
//|                                        adOrderManager.mqh        |
//|           AcquaDulza EA v1.6.1 — Order Manager                   |
//|                                                                  |
//|  3 entry modes: MARKET, LIMIT, STOP                              |
//|  Retry logic con MaxRetries e RetryDelayMs.                      |
//|  Absorbed from carnOrderManager + carnTriggerSystem              |
//|                                                                  |
//|  MAGIC NUMBERS:                                                  |
//|    MagicNumber     = Soup (ordine principale)                    |
//|    MagicNumber + 1 = Hedge Smart (HS)                             |
//|                                                                  |
//|  CloseAll/DeleteAll gestiscono Magic e Magic+1                    |
//|    Magic number restaurato a MagicNumber dopo ogni operazione     |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| GetOrderTypeString — Order type to string                       |
//+------------------------------------------------------------------+
string GetOrderTypeString(ENUM_ORDER_TYPE orderType)
{
   switch(orderType)
   {
      case ORDER_TYPE_BUY:             return "BUY";
      case ORDER_TYPE_SELL:            return "SELL";
      case ORDER_TYPE_BUY_LIMIT:       return "BUY_LIMIT";
      case ORDER_TYPE_SELL_LIMIT:      return "SELL_LIMIT";
      case ORDER_TYPE_BUY_STOP:        return "BUY_STOP";
      case ORDER_TYPE_SELL_STOP:       return "SELL_STOP";
      case ORDER_TYPE_BUY_STOP_LIMIT:  return "BUY_STOP_LIMIT";
      case ORDER_TYPE_SELL_STOP_LIMIT: return "SELL_STOP_LIMIT";
      default:                         return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| RefreshRates — Validate symbol tick data                        |
//+------------------------------------------------------------------+
bool RefreshRates()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      AdLogW(LOG_CAT_ORDER, StringFormat("RefreshRates: SymbolInfoTick failed err=%d", GetLastError()));
      return false;
   }
   if(tick.ask <= 0 || tick.bid <= 0)
   {
      AdLogW(LOG_CAT_ORDER, StringFormat("RefreshRates: invalid tick data ask=%.5f bid=%.5f", tick.ask, tick.bid));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| OrderPlaceMarket — Market BUY/SELL                              |
//+------------------------------------------------------------------+
ulong OrderPlaceMarket(int direction, double lots, double sl, double tp, string comment)
{
   string dirStr = direction > 0 ? "BUY" : "SELL";
   lots = NormalizeLotSize(lots);
   sl   = NormalizeDouble(sl, (int)g_symbolDigits);
   tp   = NormalizeDouble(tp, (int)g_symbolDigits);

   // ── DIAG: Log parametri ricevuti ──
   AdLogD(LOG_CAT_ORDER, StringFormat("DIAG OrderPlaceMarket: %s | Lot=%.4f | SL=%s | TP=%s",
          dirStr, lots, FormatPrice(sl), FormatPrice(tp)));

   // Validazione TP broker
   double refPrice = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tpBefore = tp;
   tp = ValidateTakeProfit(refPrice, tp, direction > 0);
   if(MathAbs(tp - tpBefore) > g_symbolPoint)
      AdLogW(LOG_CAT_ORDER, StringFormat("DIAG: TP market aggiustato: %s -> %s (ref=%s)", FormatPrice(tpBefore), FormatPrice(tp), FormatPrice(refPrice)));

   g_trade.SetExpertMagicNumber(MagicNumber);

   // ── DIAG: Log invio al broker ──
   AdLogD(LOG_CAT_ORDER, StringFormat("DIAG BROKER SEND: MARKET %s | Lot=%.4f | SL=%s | TP=%s | RefPrice=%s",
          dirStr, lots, FormatPrice(sl), FormatPrice(tp), FormatPrice(refPrice)));

   int retries = 0;
   while(retries < MaxRetries)
   {
      if(!RefreshRates()) { retries++; Sleep(RetryDelayMs); continue; }

      bool result = false;
      if(direction > 0)
         result = g_trade.Buy(lots, _Symbol, 0, sl, tp, comment);
      else
         result = g_trade.Sell(lots, _Symbol, 0, sl, tp, comment);

      if(result)
      {
         ulong ticket = g_trade.ResultOrder();
         if(ticket > 0)
         {
            AdLogD(LOG_CAT_ORDER, StringFormat("DIAG SUCCESSO: MARKET %s #%d ESEGUITO | Lot=%.2f | SL=%s | TP=%s",
                   dirStr, ticket, lots, FormatPrice(sl), FormatPrice(tp)));
            return ticket;
         }
      }

      uint errorCode = g_trade.ResultRetcode();
      string errorDesc = g_trade.ResultRetcodeDescription();

      if(errorCode == 10033 || errorCode == 10034 || errorCode == 10040)
      {
         AdLogW(LOG_CAT_ORDER, StringFormat("DIAG BROKER REJECT (no retry): %s (code %d)", errorDesc, errorCode));
         return 0;
      }

      AdLogW(LOG_CAT_ORDER, StringFormat("DIAG BROKER FAIL: Market %s — %s (code %d) — retry %d/%d",
             dirStr, errorDesc, errorCode, retries + 1, MaxRetries));
      retries++;
      if(retries < MaxRetries) Sleep(RetryDelayMs);
   }

   AdLogE(LOG_CAT_ORDER, StringFormat("DIAG: Market %s FALLITO dopo %d tentativi", dirStr, MaxRetries));
   return 0;
}

//+------------------------------------------------------------------+
//| OrderPlacePending — Place LIMIT or STOP order                   |
//+------------------------------------------------------------------+
ulong OrderPlacePending(ENUM_ORDER_TYPE orderType, double lots, double price,
                         double sl, double tp, string comment)
{
   price = NormalizeDouble(price, (int)g_symbolDigits);
   sl    = NormalizeDouble(sl, (int)g_symbolDigits);
   tp    = NormalizeDouble(tp, (int)g_symbolDigits);
   lots  = NormalizeLotSize(lots);

   // ── DIAG: Log parametri ricevuti ──
   AdLogD(LOG_CAT_ORDER, StringFormat("DIAG OrderPlacePending: %s | Lot=%.4f | Price=%s | SL=%s | TP=%s",
          GetOrderTypeString(orderType), lots, FormatPrice(price), FormatPrice(sl), FormatPrice(tp)));

   // Validazione TP broker
   bool isBuyOrder = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
   double tpBefore = tp;
   tp = ValidateTakeProfit(price, tp, isBuyOrder);
   if(MathAbs(tp - tpBefore) > g_symbolPoint)
      AdLogW(LOG_CAT_ORDER, StringFormat("DIAG: TP aggiustato da broker validation: %s -> %s", FormatPrice(tpBefore), FormatPrice(tp)));
   else
      AdLogD(LOG_CAT_ORDER, StringFormat("DIAG: TP validato OK: %s (ref price=%s)", FormatPrice(tp), FormatPrice(price)));

   // Broker order limit check
   int currentOrders = OrdersTotal() + PositionsTotal();
   int brokerLimit = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   if(brokerLimit <= 0) brokerLimit = 200;
   if(currentOrders >= brokerLimit - 2)
   {
      AdLogW(LOG_CAT_ORDER, StringFormat("DIAG BLOCCATO: Limite ordini broker raggiunto: %d/%d — ordine NON inviato", currentOrders, brokerLimit));
      return 0;
   }

   // Price validity check
   if(!IsValidPendingPrice(price, orderType))
   {
      double checkAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double checkBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      AdLogW(LOG_CAT_ORDER, StringFormat("DIAG BLOCCATO: Prezzo non valido per %s @ %s | Bid=%s | Ask=%s — ordine NON inviato",
             GetOrderTypeString(orderType), FormatPrice(price), FormatPrice(checkBid), FormatPrice(checkAsk)));
      return 0;
   }
   AdLogD(LOG_CAT_ORDER, "DIAG: Prezzo valido per pending — invio al broker...");

   g_trade.SetExpertMagicNumber(MagicNumber);

   // ── DIAG: Log parametri finali inviati al broker ──
   AdLogD(LOG_CAT_ORDER, StringFormat("DIAG BROKER SEND: %s | Lot=%.4f | Price=%s | SL=%s | TP=%s | Comment=%s",
          GetOrderTypeString(orderType), lots, FormatPrice(price), FormatPrice(sl), FormatPrice(tp), comment));

   int retries = 0;
   while(retries < MaxRetries)
   {
      if(!RefreshRates()) { retries++; Sleep(RetryDelayMs); continue; }

      bool result = false;
      switch(orderType)
      {
         case ORDER_TYPE_BUY_LIMIT:
            result = g_trade.BuyLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment); break;
         case ORDER_TYPE_SELL_LIMIT:
            result = g_trade.SellLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment); break;
         case ORDER_TYPE_BUY_STOP:
            result = g_trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment); break;
         case ORDER_TYPE_SELL_STOP:
            result = g_trade.SellStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment); break;
         default:
            AdLogE(LOG_CAT_ORDER, "DIAG: Tipo ordine non valido: " + IntegerToString(orderType));
            return 0;
      }

      if(result)
      {
         ulong ticket = g_trade.ResultOrder();
         if(ticket > 0)
         {
            AdLogD(LOG_CAT_ORDER, StringFormat("DIAG SUCCESSO: %s #%d PIAZZATO | Lot=%.2f | Entry=%s | SL=%s | TP=%s",
                   GetOrderTypeString(orderType), ticket, lots,
                   FormatPrice(price), FormatPrice(sl), FormatPrice(tp)));
            return ticket;
         }
      }

      uint errorCode = g_trade.ResultRetcode();
      string errorDesc = g_trade.ResultRetcodeDescription();

      if(errorCode == 10033 || errorCode == 10034 || errorCode == 10040)
      {
         AdLogW(LOG_CAT_ORDER, StringFormat("DIAG BROKER REJECT (no retry): %s (code %d)", errorDesc, errorCode));
         return 0;
      }

      AdLogW(LOG_CAT_ORDER, StringFormat("DIAG BROKER FAIL: %s (code %d) — retry %d/%d",
             errorDesc, errorCode, retries + 1, MaxRetries));
      retries++;
      if(retries < MaxRetries) Sleep(RetryDelayMs);
   }

   AdLogE(LOG_CAT_ORDER, StringFormat("DIAG: Ordine pending FALLITO dopo %d tentativi — NESSUN ordine piazzato", MaxRetries));
   return 0;
}

//+------------------------------------------------------------------+
//| OrderPlace — Unified entry: routes by EntryMode                 |
//|  sig: EngineSignal with entry/sl/tp prices                       |
//|  lots: pre-calculated lot size                                   |
//|  Returns: order ticket (0 if failed)                             |
//+------------------------------------------------------------------+
ulong OrderPlace(const EngineSignal &sig, double lots, int cycleID)
{
   string dirStr = sig.direction > 0 ? "BUY" : "SELL";
   string comment = StringFormat("AD_%s_#%d", dirStr, cycleID);

   // ── DIAG: Log ingresso in OrderPlace ──
   AdLogD(LOG_CAT_ORDER, StringFormat("DIAG OrderPlace: %s #%d | Lot=%.4f | Entry=%s | TP=%s | Mode=%s",
          dirStr, cycleID, lots, FormatPrice(sig.entryPrice), FormatPrice(sig.tpPrice), EnumToString(EntryMode)));

   // Validate entry/TP consistency
   if(sig.direction > 0)
   {
      if(sig.tpPrice > 0 && sig.tpPrice <= sig.entryPrice)
      {
         AdLogW(LOG_CAT_ORDER, StringFormat("DIAG REJECTED: BUY TP (%s) <= Entry (%s) — ordine ANNULLATO",
                FormatPrice(sig.tpPrice), FormatPrice(sig.entryPrice)));
         return 0;
      }
   }
   else
   {
      if(sig.tpPrice > 0 && sig.tpPrice >= sig.entryPrice)
      {
         AdLogW(LOG_CAT_ORDER, StringFormat("DIAG REJECTED: SELL TP (%s) >= Entry (%s) — ordine ANNULLATO",
                FormatPrice(sig.tpPrice), FormatPrice(sig.entryPrice)));
         return 0;
      }
   }
   AdLogD(LOG_CAT_ORDER, "DIAG: Validazione Entry/TP OK — procedo al routing");

   // Route by entry mode
   // [MOD] SL rimosso: sl=0 in tutte le modalita'
   switch(EntryMode)
   {
      case ENTRY_MARKET:
         AdLogD(LOG_CAT_ORDER, StringFormat("DIAG: ENTRY_MARKET — invio %s market | Lot=%.4f | TP=%s",
                dirStr, lots, FormatPrice(sig.tpPrice)));
         return OrderPlaceMarket(sig.direction, lots, 0, sig.tpPrice, comment);

      case ENTRY_LIMIT:
      {
         double limitOffset = PipsToPrice(g_inst_limitOffset);
         double limitPrice = 0;
         ENUM_ORDER_TYPE type;

         if(sig.direction > 0)
         {
            limitPrice = sig.entryPrice - limitOffset;
            type = ORDER_TYPE_BUY_LIMIT;
         }
         else
         {
            limitPrice = sig.entryPrice + limitOffset;
            type = ORDER_TYPE_SELL_LIMIT;
         }
         AdLogD(LOG_CAT_ORDER, StringFormat("DIAG: ENTRY_LIMIT — %s @ %s (offset=%.1fp da entry %s) | TP=%s",
                GetOrderTypeString(type), FormatPrice(limitPrice),
                PointsToPips(limitOffset), FormatPrice(sig.entryPrice), FormatPrice(sig.tpPrice)));
         return OrderPlacePending(type, lots, limitPrice, 0, sig.tpPrice, comment);
      }

      case ENTRY_STOP:
      {
         ENUM_ORDER_TYPE type;
         double entryPrice = sig.entryPrice;

         double minDistance = g_symbolStopsLevel * g_symbolPoint;
         if(minDistance < g_pipSize)
            minDistance = 3 * g_pipSize;

         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         AdLogD(LOG_CAT_ORDER, StringFormat("DIAG: ENTRY_STOP — entry originale=%s | Bid=%s | Ask=%s | minDist=%s (%.1fp)",
                FormatPrice(entryPrice), FormatPrice(currentBid), FormatPrice(currentAsk),
                FormatPrice(minDistance), PointsToPips(minDistance)));

         if(sig.direction > 0)
         {
            type = ORDER_TYPE_BUY_STOP;
            if(entryPrice <= currentAsk + minDistance)
            {
               double old = entryPrice;
               entryPrice = NormalizeDouble(currentAsk + minDistance + g_symbolPoint, (int)g_symbolDigits);
               AdLogW(LOG_CAT_ORDER, StringFormat("DIAG: BUY STOP prezzo aggiustato: %s -> %s (era troppo vicino ad Ask %s)",
                      FormatPrice(old), FormatPrice(entryPrice), FormatPrice(currentAsk)));
            }
            else
            {
               AdLogD(LOG_CAT_ORDER, StringFormat("DIAG: BUY STOP prezzo OK: %s > Ask(%s) + minDist(%s)",
                      FormatPrice(entryPrice), FormatPrice(currentAsk), FormatPrice(minDistance)));
            }
         }
         else
         {
            type = ORDER_TYPE_SELL_STOP;
            if(entryPrice >= currentBid - minDistance)
            {
               double old = entryPrice;
               entryPrice = NormalizeDouble(currentBid - minDistance - g_symbolPoint, (int)g_symbolDigits);
               AdLogW(LOG_CAT_ORDER, StringFormat("DIAG: SELL STOP prezzo aggiustato: %s -> %s (era troppo vicino a Bid %s)",
                      FormatPrice(old), FormatPrice(entryPrice), FormatPrice(currentBid)));
            }
            else
            {
               AdLogD(LOG_CAT_ORDER, StringFormat("DIAG: SELL STOP prezzo OK: %s < Bid(%s) - minDist(%s)",
                      FormatPrice(entryPrice), FormatPrice(currentBid), FormatPrice(minDistance)));
            }
         }

         AdLogD(LOG_CAT_ORDER, StringFormat("DIAG: Invio %s @ %s | Lot=%.4f | SL=0 | TP=%s",
                GetOrderTypeString(type), FormatPrice(entryPrice), lots, FormatPrice(sig.tpPrice)));
         return OrderPlacePending(type, lots, entryPrice, 0, sig.tpPrice, comment);
      }
   }

   AdLogW(LOG_CAT_ORDER, StringFormat("DIAG: EntryMode non riconosciuto (%d) — nessun ordine", (int)EntryMode));
   return 0;
}

//+------------------------------------------------------------------+
//| DeletePendingOrder — Delete with retry logic                    |
//+------------------------------------------------------------------+
bool DeletePendingOrder(ulong ticket)
{
   if(ticket == 0) return false;
   if(!OrderSelect(ticket)) return true;  // Already gone

   int retries = 0;
   while(retries < MaxRetries)
   {
      if(g_trade.OrderDelete(ticket)) return true;

      AdLogW(LOG_CAT_ORDER, StringFormat("Delete failed #%d: %s, retry %d",
             ticket, g_trade.ResultRetcodeDescription(), retries + 1));
      retries++;
      if(retries < MaxRetries) Sleep(RetryDelayMs);
   }

   AdLogE(LOG_CAT_ORDER, StringFormat("Failed to delete order #%d", ticket));
   return false;
}

//+------------------------------------------------------------------+
//| ClosePosition — Close by ticket with retry logic                |
//|                                                                  |
//| Chiude una posizione a mercato con slippage g_inst_slippage.     |
//| Se gia' chiusa (PositionSelectByTicket fail) ritorna true.       |
//| Retry fino a MaxRetries con delay RetryDelayMs.                  |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return true;  // Already closed

   double closePrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   AdLogI(LOG_CAT_ORDER, StringFormat(
      "CLOSING position #%d | CurrentPrice=%s | Slippage=%d",
      ticket, FormatPrice(closePrice), g_inst_slippage));

   int retries = 0;
   while(retries < MaxRetries)
   {
      if(g_trade.PositionClose(ticket, g_inst_slippage)) return true;

      AdLogW(LOG_CAT_ORDER, StringFormat("Close failed #%d: %s, retry %d",
             ticket, g_trade.ResultRetcodeDescription(), retries + 1));
      retries++;
      if(retries < MaxRetries) Sleep(RetryDelayMs);
   }

   AdLogE(LOG_CAT_ORDER, StringFormat("Failed to close position #%d", ticket));
   return false;
}

//+------------------------------------------------------------------+
//| CloseAllPositions — Close all with our magic                    |
//+------------------------------------------------------------------+
int CloseAllPositions()
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      // Chiude Soup (Magic) e Hedge Smart (Magic+1)
      if(posMagic != MagicNumber && posMagic != MagicNumber + 1) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      g_trade.SetExpertMagicNumber((int)posMagic);
      if(ClosePosition(ticket)) closed++;
   }
   g_trade.SetExpertMagicNumber(MagicNumber);
   return closed;
}

//+------------------------------------------------------------------+
//| DeleteAllPendingOrders — Delete all with our magic              |
//+------------------------------------------------------------------+
int DeleteAllPendingOrders()
{
   int deleted = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      long ordMagic = OrderGetInteger(ORDER_MAGIC);
      // Cancella pendenti Soup (Magic) e Hedge Smart (Magic+1)
      if(ordMagic != MagicNumber && ordMagic != MagicNumber + 1) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      g_trade.SetExpertMagicNumber((int)ordMagic);
      if(DeletePendingOrder(ticket)) deleted++;
   }
   g_trade.SetExpertMagicNumber(MagicNumber);
   return deleted;
}

//+------------------------------------------------------------------+
//| CloseAllOrders — Close everything (positions + pending)         |
//+------------------------------------------------------------------+
void CloseAllOrders()
{
   AdLogI(LOG_CAT_ORDER, "=== CLOSE ALL REQUESTED ===");
   int pos = CloseAllPositions();
   int ord = DeleteAllPendingOrders();
   AdLogI(LOG_CAT_ORDER, StringFormat("CLOSE COMPLETE — Positions=%d Orders=%d", pos, ord));
}

//+------------------------------------------------------------------+
//| ModifyPendingOrder — Update entry/SL/TP of pending order        |
//|                                                                  |
//| Usato da UpdatePending() quando le bande DPC si muovono e        |
//| l'entry/TP del pending deve essere aggiornato.                   |
//| Valida il TP con ValidateTakeProfit() prima di inviare.          |
//+------------------------------------------------------------------+
bool ModifyPendingOrder(ulong ticket, double newPrice, double newSL, double newTP)
{
   AdLogD(LOG_CAT_ORDER, StringFormat(
      "DIAG ModifyPending: ticket=%d | newPrice=%s | newSL=%s | newTP=%s",
      ticket, FormatPrice(newPrice), FormatPrice(newSL), FormatPrice(newTP)));

   if(!OrderSelect(ticket)) return false;

   newPrice = NormalizeDouble(newPrice, (int)g_symbolDigits);
   newSL    = NormalizeDouble(newSL, (int)g_symbolDigits);
   newTP    = NormalizeDouble(newTP, (int)g_symbolDigits);

   // Validazione broker: garantisce che il nuovo TP rispetti SYMBOL_TRADE_STOPS_LEVEL.
   // Legge il tipo d'ordine corrente (già selezionato con OrderSelect sopra)
   // per determinare se è un BUY o SELL e validare la direzione del TP.
   ENUM_ORDER_TYPE currentType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   bool isBuyMod = (currentType == ORDER_TYPE_BUY_LIMIT || currentType == ORDER_TYPE_BUY_STOP);
   newTP = ValidateTakeProfit(newPrice, newTP, isBuyMod);

   g_trade.SetExpertMagicNumber(MagicNumber);
   if(g_trade.OrderModify(ticket, newPrice, newSL, newTP, ORDER_TIME_GTC, 0))
   {
      AdLogI(LOG_CAT_ORDER, StringFormat(
         "MODIFY OK #%d | Price=%s | SL=%s | TP=%s",
         ticket, FormatPrice(newPrice), FormatPrice(newSL), FormatPrice(newTP)));
      return true;
   }

   AdLogW(LOG_CAT_ORDER, StringFormat("Modify failed #%d: %s",
          ticket, g_trade.ResultRetcodeDescription()));
   return false;
}
