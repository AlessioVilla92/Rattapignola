//+------------------------------------------------------------------+
//|                                      adBrokerValidation.mqh      |
//|           AcquaDulza EA v1.6.1 — Broker Validation               |
//|                                                                  |
//|  Load broker specs, validate inputs, normalize lots              |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| LoadBrokerSpecifications                                         |
//+------------------------------------------------------------------+
bool LoadBrokerSpecifications()
{
   Log_Header("LOADING BROKER SPECIFICATIONS");

   g_symbolPoint  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(g_symbolPoint <= 0)
   {
      Log_SystemError("Broker", 0, StringFormat("Invalid symbol point: %f", g_symbolPoint));
      return false;
   }

   g_symbolStopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_symbolFreezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_symbolMinLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_symbolMaxLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_symbolLotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_symbolSpreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(g_symbolMinLot <= 0)
   {
      Log_SystemError("Broker", 0, StringFormat("Invalid min lot: %f", g_symbolMinLot));
      return false;
   }
   if(g_symbolLotStep <= 0)
   {
      Log_SystemError("Broker", 0, StringFormat("Invalid lot step: %f", g_symbolLotStep));
      return false;
   }

   Log_KeyValue("Symbol", _Symbol);
   Log_KeyValueNum("Point", g_symbolPoint, g_symbolDigits);
   Log_KeyValueNum("Digits", g_symbolDigits, 0);
   Log_KeyValueNum("Stops Level", g_symbolStopsLevel, 0);
   Log_KeyValueNum("Freeze Level", g_symbolFreezeLevel, 0);
   Log_KeyValueNum("Min Lot", g_symbolMinLot, 2);
   Log_KeyValueNum("Max Lot", g_symbolMaxLot, 2);
   Log_KeyValueNum("Lot Step", g_symbolLotStep, 2);
   Log_KeyValue("Spread", StringFormat("%d pts (%.1f pips)",
      g_symbolSpreadPoints, PointsToPips(g_symbolSpreadPoints * g_symbolPoint)));
   Log_Separator();

   return true;
}

//+------------------------------------------------------------------+
//| ValidateInputParameters                                          |
//+------------------------------------------------------------------+
bool ValidateInputParameters()
{
   Log_Header("VALIDATING INPUT PARAMETERS");
   int errors = 0;

   // Lot size (for FIXED_LOT mode)
   if(RiskMode == RISK_FIXED_LOT)
   {
      if(LotSize <= 0)
      {
         Log_SystemError("Validation", 0, StringFormat("LotSize must be > 0 (current: %.2f)", LotSize));
         errors++;
      }
      if(LotSize < g_symbolMinLot)
      {
         Log_SystemError("Validation", 0, StringFormat("LotSize %.2f below broker min %.2f", LotSize, g_symbolMinLot));
         errors++;
      }
      if(LotSize > g_symbolMaxLot)
      {
         Log_SystemError("Validation", 0, StringFormat("LotSize %.2f exceeds broker max %.2f", LotSize, g_symbolMaxLot));
         errors++;
      }
   }

   // Risk percent
   if(RiskMode == RISK_PERCENT && (RiskPercent <= 0 || RiskPercent > 10))
   {
      Log_SystemError("Validation", 0, StringFormat("RiskPercent out of range (current: %.1f)", RiskPercent));
      errors++;
   }

   // Max concurrent trades
   if(MaxConcurrentTrades < 1)
   {
      Log_SystemError("Validation", 0, StringFormat("MaxConcurrentTrades must be >= 1 (current: %d)", MaxConcurrentTrades));
      errors++;
   }

   // Hedging mode required
   ENUM_ACCOUNT_MARGIN_MODE marginMode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Log_SystemError("Validation", 0, StringFormat("Requires HEDGING mode (current: %s)", EnumToString(marginMode)));
      errors++;
   }

   // Magic number
   if(MagicNumber <= 0)
   {
      Log_SystemError("Validation", 0, StringFormat("MagicNumber must be positive (current: %d)", MagicNumber));
      errors++;
   }

   // DPC Engine period
   if(InpLenDC < 5)
   {
      Log_SystemError("Validation", 0, StringFormat("InpLenDC must be >= 5 (current: %d)", InpLenDC));
      errors++;
   }

   // Summary
   Log_SubHeader("VALIDATION SUMMARY");
   Log_KeyValueNum("Errors", errors, 0);

   if(errors > 0)
   {
      Log_KeyValue("Result", StringFormat("FAILED - %d error(s)", errors));
      Log_Separator();
      return false;
   }

   Log_KeyValue("Result", "PASSED - All parameters valid");
   Log_Separator();
   return true;
}

//+------------------------------------------------------------------+
//| NormalizeLotSize                                                 |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lot)
{
   double originalLot = lot;

   if(lot < g_symbolMinLot) lot = g_symbolMinLot;
   if(lot > g_symbolMaxLot) lot = g_symbolMaxLot;

   if(g_symbolLotStep > 0)
      lot = MathFloor(lot / g_symbolLotStep) * g_symbolLotStep;

   if(lot < g_symbolMinLot) lot = g_symbolMinLot;

   // Decimali dinamici da lotStep (crypto può avere 0.001 = 3 decimali)
   int lotDecimals = 2;
   if(g_symbolLotStep > 0)
   {
      double step = g_symbolLotStep;
      lotDecimals = 0;
      while(step < 1.0 && lotDecimals < 8) { step *= 10; lotDecimals++; }
   }
   lot = NormalizeDouble(lot, lotDecimals);

   if(MathAbs(lot - originalLot) > 0.001)
      AdLogW(LOG_CAT_BROKER, StringFormat("Lot normalized: %.*f -> %.*f", lotDecimals, originalLot, lotDecimals, lot));

   return lot;
}

//+------------------------------------------------------------------+
//| ValidateTakeProfit                                               |
//+------------------------------------------------------------------+
double ValidateTakeProfit(double price, double tp, bool isBuy)
{
   if(tp == 0)
   {
      AdLogD(LOG_CAT_BROKER, "DIAG ValidateTP: TP=0 — nessun Take Profit impostato");
      return 0;
   }

   double originalTP = tp;
   double minDistance = g_symbolStopsLevel * g_symbolPoint;
   if(minDistance < g_pipSize)
      minDistance = 3 * g_pipSize;
   minDistance *= 1.1;

   // ── DIAG: Log parametri validazione TP ──
   AdLogD(LOG_CAT_BROKER, StringFormat("DIAG ValidateTP: %s | RefPrice=%s | TP=%s | MinDist=%s (%.1fp) | StopsLevel=%d",
          isBuy ? "BUY" : "SELL", DoubleToString(price, g_symbolDigits),
          DoubleToString(tp, g_symbolDigits), DoubleToString(minDistance, g_symbolDigits),
          PointsToPips(minDistance), (int)g_symbolStopsLevel));

   if(isBuy)
   {
      double minTP = price + minDistance;
      if(tp < minTP)
      {
         AdLogW(LOG_CAT_BROKER, StringFormat("DIAG ValidateTP: BUY TP troppo vicino — %s < minTP(%s) — aggiusto a %s",
                DoubleToString(tp, g_symbolDigits), DoubleToString(minTP, g_symbolDigits), DoubleToString(minTP, g_symbolDigits)));
         tp = minTP;
      }
   }
   else
   {
      double maxTP = price - minDistance;
      if(tp > maxTP)
      {
         AdLogW(LOG_CAT_BROKER, StringFormat("DIAG ValidateTP: SELL TP troppo vicino — %s > maxTP(%s) — aggiusto a %s",
                DoubleToString(tp, g_symbolDigits), DoubleToString(maxTP, g_symbolDigits), DoubleToString(maxTP, g_symbolDigits)));
         tp = maxTP;
      }
   }

   tp = NormalizeDouble(tp, g_symbolDigits);

   if(MathAbs(tp - originalTP) > g_symbolPoint)
      AdLogW(LOG_CAT_BROKER, StringFormat("DIAG ValidateTP RISULTATO: TP aggiustato %s -> %s",
         DoubleToString(originalTP, g_symbolDigits), DoubleToString(tp, g_symbolDigits)));
   else
      AdLogD(LOG_CAT_BROKER, StringFormat("DIAG ValidateTP RISULTATO: TP OK = %s (nessun aggiustamento)",
         DoubleToString(tp, g_symbolDigits)));

   return tp;
}

//+------------------------------------------------------------------+
//| IsValidPendingPrice                                              |
//+------------------------------------------------------------------+
bool IsValidPendingPrice(double price, ENUM_ORDER_TYPE orderType)
{
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(currentAsk <= 0 || currentBid <= 0) return true;

   double minDistance = g_symbolStopsLevel * g_symbolPoint;
   if(minDistance < g_pipSize)
      minDistance = 3 * g_pipSize;

   switch(orderType)
   {
      case ORDER_TYPE_BUY_LIMIT:  return (price < currentAsk - minDistance);
      case ORDER_TYPE_SELL_LIMIT: return (price > currentBid + minDistance);
      case ORDER_TYPE_BUY_STOP:   return (price > currentAsk + minDistance);
      case ORDER_TYPE_SELL_STOP:  return (price < currentBid - minDistance);
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| Setup Trade Object — Filling mode detection                      |
//+------------------------------------------------------------------+
void SetupTradeObject()
{
   g_trade.SetExpertMagicNumber(MagicNumber);
   // Slippage: usa valore effettivo scalato per prodotto (in points)
   g_trade.SetDeviationInPoints(g_inst_slippage);

   // Auto-detect filling mode
   long fillPolicy = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillPolicy & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillPolicy & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   AdLogI(LOG_CAT_BROKER, StringFormat("Trade object: magic=%d slippage=%d (instrument-scaled)",
      MagicNumber, g_inst_slippage));
}
