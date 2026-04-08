//+------------------------------------------------------------------+
//|                                    adStatePersistence.mqh        |
//|           AcquaDulza EA v1.7.2 — State Persistence               |
//|                                                                  |
//|  Auto-save & restore CycleRecord array via GlobalVariables       |
//|  HedgeSmart: 13 campi HS (v1.7.0 base + v1.7.2 Step1/Step2)     |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| Global Variable Prefix                                           |
//|                                                                  |
//| Namespace: AD_STATE_{SYMBOL}_{MAGIC}_{varName}                   |
//| Es: AD_STATE_EURUSD_12345_sessionProfit                          |
//| Ogni combinazione Symbol+Magic ha il suo namespace isolato,      |
//| permettendo EA multipli sullo stesso terminale.                  |
//+------------------------------------------------------------------+
#define AD_GV_PREFIX "AD_STATE_"

//+------------------------------------------------------------------+
//| Persistence State Variables                                      |
//|                                                                  |
//| g_lastAutoSaveTime:   timestamp ultimo auto-save riuscito        |
//| g_savedVariableCount: contatore vars salvate nell'ultimo save    |
//| g_saveErrors:         errori GlobalVariableSet nell'ultimo save  |
//+------------------------------------------------------------------+
datetime g_lastAutoSaveTime    = 0;
int      g_savedVariableCount  = 0;
int      g_saveErrors          = 0;

//+------------------------------------------------------------------+
//| GetStateKey — Unique key for symbol + magic                     |
//+------------------------------------------------------------------+
string GetStateKey(string varName)
{
   return AD_GV_PREFIX + _Symbol + "_" + IntegerToString(MagicNumber) + "_" + varName;
}

//+------------------------------------------------------------------+
//| Save/Restore Helpers                                             |
//+------------------------------------------------------------------+
bool SaveStateDouble(string name, double value)
{
   datetime result = GlobalVariableSet(GetStateKey(name), value);
   if(result == 0) { g_saveErrors++; return false; }
   g_savedVariableCount++;
   return true;
}

bool SaveStateInt(string name, int value)       { return SaveStateDouble(name, (double)value); }
bool SaveStateUlong(string name, ulong value)   { return SaveStateDouble(name, (double)value); }
bool SaveStateBool(string name, bool value)     { return SaveStateDouble(name, value ? 1.0 : 0.0); }

double RestoreStateDouble(string name, double defaultValue = 0)
{
   string key = GetStateKey(name);
   if(!GlobalVariableCheck(key)) return defaultValue;
   return GlobalVariableGet(key);
}

int   RestoreStateInt(string name, int defaultValue = 0)       { return (int)RestoreStateDouble(name, (double)defaultValue); }
ulong RestoreStateUlong(string name, ulong defaultValue = 0)   { return (ulong)RestoreStateDouble(name, (double)defaultValue); }
bool  RestoreStateBool(string name, bool defaultValue = false)  { return RestoreStateDouble(name, defaultValue ? 1.0 : 0.0) > 0.5; }

//+------------------------------------------------------------------+
//| HasSavedState — Check for valid saved state                     |
//|                                                                  |
//| Verifica 3 condizioni per uno stato valido:                      |
//|  1. EnableAutoRecovery=true E lastSaveTime esiste                |
//|  2. Eta' < 7 giorni (stato piu' vecchio = probabilmente stale)   |
//|  3. Almeno una posizione/ordine AD esiste nel broker             |
//|     (Magic, Magic+1)                                             |
//|                                                                  |
//| Se condizione 3 fallisce → "fresh start" (stato orfano).        |
//| L'EA si era chiuso normalmente, lo stato non serve.              |
//+------------------------------------------------------------------+
bool HasSavedState()
{
   if(!EnableAutoRecovery) return false;

   string key = GetStateKey("lastSaveTime");
   if(!GlobalVariableCheck(key)) return false;

   // Max 7 day age
   datetime lastSave = (datetime)GlobalVariableGet(key);
   if(TimeCurrent() - lastSave > 7 * 86400)
   {
      AdLogW(LOG_CAT_PERSIST, "Saved state too old — clearing");
      ClearSavedState();
      return false;
   }

   int savedCount = (int)RestoreStateDouble("cycleCount", 0);
   if(savedCount <= 0) return false;

   // Fresh start detection: no actual positions = orphan state
   bool hasOrders = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic == MagicNumber || posMagic == MagicNumber + 1)
      { hasOrders = true; break; }
   }
   if(!hasOrders)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         long ordMagic = OrderGetInteger(ORDER_MAGIC);
         if(ordMagic == MagicNumber || ordMagic == MagicNumber + 1)
         { hasOrders = true; break; }
      }
   }

   if(!hasOrders)
   {
      AdLogI(LOG_CAT_PERSIST, "Fresh start — no AcquaDulza orders. Clearing orphan state.");
      ClearSavedState();
      return false;
   }

   AdLogI(LOG_CAT_PERSIST, StringFormat("Valid saved state found — %d cycles, last save: %s",
          savedCount, TimeToString(lastSave, TIME_DATE|TIME_SECONDS)));
   return true;
}

//+------------------------------------------------------------------+
//| SaveState — Save complete state via GlobalVariables              |
//|                                                                  |
//| Chiamato da ExecuteAutoSave() ogni AutoSaveIntervalMin minuti.   |
//| Salva solo in STATE_ACTIVE o STATE_PAUSED (non in IDLE/STOPPED). |
//|                                                                  |
//| CAMPI SALVATI:                                                   |
//|  - Core: systemState, nextCycleID                                |
//|  - P&L: sessionProfit, wins, losses                              |
//|  - Signals: totalSignals, buySignals, sellSignals                |
//|  - Equity: maxEquity, maxDrawdown                                |
//|  - Daily: dailyProfit, dailyWins, dailyLosses                    |
//|  - Cycles[i]: 12 campi base + 8 H1 + 6 H2 = 26 per ciclo       |
//|  - Timestamp: lastSaveTime                                       |
//+------------------------------------------------------------------+
void SaveState()
{
   if(!EnableAutoSave) return;
   if(g_systemState != STATE_ACTIVE && g_systemState != STATE_PAUSED) return;

   g_savedVariableCount = 0;
   g_saveErrors = 0;

   // Core state
   SaveStateInt("systemState", (int)g_systemState);
   SaveStateInt("nextCycleID", g_nextCycleID);

   // P&L
   SaveStateDouble("sessionProfit", g_sessionRealizedProfit);
   SaveStateInt("sessionWins", g_sessionWins);
   SaveStateInt("sessionLosses", g_sessionLosses);

   // Signal tracking
   SaveStateInt("totalSignals", g_totalSignals);
   SaveStateInt("buySignals", g_buySignals);
   SaveStateInt("sellSignals", g_sellSignals);

   // Equity
   SaveStateDouble("maxEquity", g_maxEquity);
   SaveStateDouble("maxDrawdown", g_maxDrawdownPct);

   // Daily tracking
   SaveStateDouble("dailyProfit", g_dailyRealizedProfit);
   SaveStateInt("dailyWins", g_dailyWins);
   SaveStateInt("dailyLosses", g_dailyLosses);

   // Cycles array
   int cycleCount = ArraySize(g_cycles);
   SaveStateInt("cycleCount", cycleCount);

   for(int i = 0; i < cycleCount; i++)
   {
      string p = "cy" + IntegerToString(i) + "_";

      SaveStateInt(p + "id", g_cycles[i].cycleID);
      SaveStateInt(p + "dir", g_cycles[i].direction);
      SaveStateInt(p + "state", (int)g_cycles[i].state);
      SaveStateUlong(p + "ticket", g_cycles[i].ticket);
      SaveStateDouble(p + "entry", g_cycles[i].entryPrice);
      SaveStateDouble(p + "sl", g_cycles[i].slPrice);
      SaveStateDouble(p + "tp", g_cycles[i].tpPrice);
      SaveStateDouble(p + "lot", g_cycles[i].lotSize);
      SaveStateInt(p + "sigTime", (int)g_cycles[i].signalTime);
      SaveStateInt(p + "placTime", (int)g_cycles[i].placedTime);
      SaveStateInt(p + "quality", g_cycles[i].quality);
      SaveStateDouble(p + "profit", g_cycles[i].profit);
      // HedgeSmart fields
      SaveStateUlong(p + "hsTkt",    g_cycles[i].hsTicket);
      SaveStateDouble(p + "hsTrig",  g_cycles[i].hsTriggerPrice);
      SaveStateDouble(p + "hsTpRef", g_cycles[i].hsTpRefLevel);
      SaveStateDouble(p + "hsLot",   g_cycles[i].hsLotSize);
      SaveStateBool(p + "hsPend",    g_cycles[i].hsPending);
      SaveStateBool(p + "hsAct",     g_cycles[i].hsActive);
      SaveStateInt(p + "hsFill",     (int)g_cycles[i].hsFillTime);
      SaveStateDouble(p + "hsPL",    g_cycles[i].hsPL);
      // v1.7.2 — Step1 BE + Step2 TP
      SaveStateDouble(p + "hsFillPx",  g_cycles[i].hsFillPrice);
      SaveStateDouble(p + "hsMidSig",  g_cycles[i].hsMidlineAtSignal);
      SaveStateBool(p + "hsBESet",     g_cycles[i].hsBESet);
      SaveStateBool(p + "hsS2Rch",     g_cycles[i].hsStep2Reached);
   }

   // Timestamp
   SaveStateInt("lastSaveTime", (int)TimeCurrent());
   GlobalVariablesFlush();

   g_lastAutoSaveTime = TimeCurrent();
   AdLogI(LOG_CAT_PERSIST, StringFormat("State saved — %d vars | %d cycles | %d errors",
          g_savedVariableCount, cycleCount, g_saveErrors));
}

//+------------------------------------------------------------------+
//| RestoreState — Restore complete state from GlobalVariables       |
//|                                                                  |
//| Ripristina tutti i campi salvati da SaveState().                  |
//| Dopo il restore, VALIDA ogni ciclo contro il broker:             |
//|  - CYCLE_ACTIVE: la posizione esiste ancora?                     |
//|  - CYCLE_PENDING: l'ordine esiste ancora?                        |
//|  - CYCLE_HEDGING: soup + hedge ancora vivi?                      |
//| Cicli con posizioni/ordini spariti vengono chiusi.               |
//|                                                                  |
//| NOTA: hsLineName non è persistita                                |
//| (oggetti grafici vengono ricreati da HsMonitor/HsDrawTriggerLine)|
//+------------------------------------------------------------------+
bool RestoreState()
{
   AdLogI(LOG_CAT_PERSIST, "=== RESTORING STATE ===");

   // Core state
   g_systemState   = (ENUM_SYSTEM_STATE)RestoreStateInt("systemState", (int)STATE_IDLE);
   g_nextCycleID   = RestoreStateInt("nextCycleID", 1);

   AdLogI(LOG_CAT_PERSIST, StringFormat(
      "Core: state=%d | nextCycleID=%d", (int)g_systemState, g_nextCycleID));

   // P&L
   g_sessionRealizedProfit = RestoreStateDouble("sessionProfit");
   g_sessionWins   = RestoreStateInt("sessionWins");
   g_sessionLosses = RestoreStateInt("sessionLosses");

   // Signal tracking
   g_totalSignals  = RestoreStateInt("totalSignals");
   g_buySignals    = RestoreStateInt("buySignals");
   g_sellSignals   = RestoreStateInt("sellSignals");

   // Equity
   g_maxEquity      = RestoreStateDouble("maxEquity");
   g_maxDrawdownPct = RestoreStateDouble("maxDrawdown");

   // Daily
   g_dailyRealizedProfit = RestoreStateDouble("dailyProfit");
   g_dailyWins   = RestoreStateInt("dailyWins");
   g_dailyLosses = RestoreStateInt("dailyLosses");

   AdLogI(LOG_CAT_PERSIST, StringFormat(
      "P&L: session=%.2f W=%d L=%d | daily=%.2f W=%d L=%d | equity=%.2f dd=%.2f%%",
      g_sessionRealizedProfit, g_sessionWins, g_sessionLosses,
      g_dailyRealizedProfit, g_dailyWins, g_dailyLosses,
      g_maxEquity, g_maxDrawdownPct));

   // Cycles
   int cycleCount = RestoreStateInt("cycleCount", 0);
   if(cycleCount > 0)
   {
      int arraySize = MathMax(cycleCount, MAX_CYCLES);
      ArrayResize(g_cycles, arraySize);
      for(int i = 0; i < cycleCount; i++)
      {
         string p = "cy" + IntegerToString(i) + "_";

         g_cycles[i].cycleID    = RestoreStateInt(p + "id");
         g_cycles[i].direction  = RestoreStateInt(p + "dir");
         g_cycles[i].state      = (ENUM_CYCLE_STATE)RestoreStateInt(p + "state");
         g_cycles[i].ticket     = RestoreStateUlong(p + "ticket");
         g_cycles[i].entryPrice = RestoreStateDouble(p + "entry");
         g_cycles[i].slPrice    = RestoreStateDouble(p + "sl");
         g_cycles[i].tpPrice    = RestoreStateDouble(p + "tp");
         g_cycles[i].lotSize    = RestoreStateDouble(p + "lot");
         g_cycles[i].signalTime = (datetime)RestoreStateInt(p + "sigTime");
         g_cycles[i].placedTime = (datetime)RestoreStateInt(p + "placTime");
         g_cycles[i].quality    = RestoreStateInt(p + "quality");
         g_cycles[i].profit     = RestoreStateDouble(p + "profit");
         // HedgeSmart fields
         g_cycles[i].hsTicket       = RestoreStateUlong(p + "hsTkt");
         g_cycles[i].hsTriggerPrice = RestoreStateDouble(p + "hsTrig");
         g_cycles[i].hsTpRefLevel   = RestoreStateDouble(p + "hsTpRef");
         g_cycles[i].hsLotSize      = RestoreStateDouble(p + "hsLot");
         g_cycles[i].hsPending      = RestoreStateBool(p + "hsPend");
         g_cycles[i].hsActive       = RestoreStateBool(p + "hsAct");
         g_cycles[i].hsFillTime     = (datetime)RestoreStateInt(p + "hsFill");
         g_cycles[i].hsLineName        = "";  // Visual objects not persisted
         g_cycles[i].hsPL              = RestoreStateDouble(p + "hsPL");
         // v1.7.2 — Step1 BE + Step2 TP
         g_cycles[i].hsFillPrice       = RestoreStateDouble(p + "hsFillPx");
         g_cycles[i].hsMidlineAtSignal = RestoreStateDouble(p + "hsMidSig");
         g_cycles[i].hsBESet           = RestoreStateBool(p + "hsBESet");
         g_cycles[i].hsStep2Reached    = RestoreStateBool(p + "hsS2Rch");
      }
   }

   // Validate against broker
   int validated = 0, invalidated = 0;
   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state == CYCLE_IDLE || g_cycles[i].state == CYCLE_CLOSED)
         continue;

      if(g_cycles[i].state == CYCLE_ACTIVE && !IsPositionOpen(g_cycles[i].ticket))
      {
         g_cycles[i].state = CYCLE_CLOSED;
         invalidated++;
      }
      else if(g_cycles[i].state == CYCLE_PENDING && !OrderSelect(g_cycles[i].ticket))
      {
         g_cycles[i].state = CYCLE_CLOSED;
         invalidated++;
      }
      else if(g_cycles[i].state == CYCLE_HEDGING)
      {
         bool soupValid = (g_cycles[i].ticket > 0) && IsPositionOpen(g_cycles[i].ticket);

         // HS valido?
         bool hsValid = false;
         if(g_cycles[i].hsActive && g_cycles[i].hsTicket > 0)
            hsValid = IsPositionOpen(g_cycles[i].hsTicket);
         else if(g_cycles[i].hsPending && g_cycles[i].hsTicket > 0)
            hsValid = OrderSelect(g_cycles[i].hsTicket);

         if(!soupValid && !hsValid)
         {
            g_cycles[i].state     = CYCLE_CLOSED;
            g_cycles[i].hsPending = false;
            g_cycles[i].hsActive  = false;
            invalidated++;
         }
         else if(!hsValid)
         {
            // HS sparito ma Soup viva — torna ACTIVE
            g_cycles[i].state     = CYCLE_ACTIVE;
            g_cycles[i].hsPending = false;
            g_cycles[i].hsActive  = false;
            g_cycles[i].hsTicket  = 0;
            validated++;
         }
         else if(!soupValid)
         {
            // Soup sparita ma HS vivo — HsMonitor farà cleanup
            g_cycles[i].state = CYCLE_CLOSED;
            invalidated++;
         }
         else
            validated++;
      }
      else
         validated++;
   }

   AdLogI(LOG_CAT_PERSIST, StringFormat("=== RESTORE COMPLETE === %d cycles | %d valid | %d invalidated",
          cycleCount, validated, invalidated));
   return (cycleCount > 0);
}

//+------------------------------------------------------------------+
//| ExecuteAutoSave — Periodic save (check interval)                |
//|                                                                  |
//| Chiamato da OnTimer(). Verifica se sono passati abbastanza      |
//| minuti (AutoSaveIntervalMin) dall'ultimo save.                   |
//| Il primo tick dopo OnInit() forza un save immediato.             |
//+------------------------------------------------------------------+
void ExecuteAutoSave()
{
   if(!EnableAutoSave) return;
   if(g_systemState != STATE_ACTIVE && g_systemState != STATE_PAUSED) return;

   if(g_lastAutoSaveTime == 0)
   {
      SaveState();
      return;
   }

   if(TimeCurrent() - g_lastAutoSaveTime >= AutoSaveIntervalMin * 60)
      SaveState();
}

//+------------------------------------------------------------------+
//| ClearSavedState — Delete all saved state variables              |
//+------------------------------------------------------------------+
void ClearSavedState()
{
   string prefix = AD_GV_PREFIX + _Symbol + "_" + IntegerToString(MagicNumber) + "_";
   int deleted = 0;

   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0)
      {
         GlobalVariableDel(name);
         deleted++;
      }
   }

   GlobalVariablesFlush();
   AdLogI(LOG_CAT_PERSIST, StringFormat("Cleared %d saved state variables", deleted));
}
