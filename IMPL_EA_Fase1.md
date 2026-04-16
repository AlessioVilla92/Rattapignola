# Implementazione Fase 1 — Expert Advisor Rattapignola (Produzione)

## OBIETTIVO
Implementare le 4 modifiche di Fase 1 nell'EA Rattapignola per eliminare
i whipsaw contro-trend su M5/M15. Ogni modifica è attivabile/disattivabile
con toggle input e ha default OFF per backward compatibility.

**File da modificare** (in ordine di dipendenza):
1. `rattEnums.mqh` — nuovo enum per HTF filter mode
2. `rattInputParameters.mqh` — nuovi input parameters
3. `rattGlobalVariables.mqh` — nuove variabili globali
4. `rattHTFFilter.mqh` — sostituzione Donchian → UTBot bias
5. `rattUTBotEngine.mqh` — conferma N-barre + ER asimmetrico
6. `Rattapignola.mq5` — cooldown post-entry

---

## FILE 1: rattEnums.mqh

### Inserimento: DOPO l'enum ENUM_TP_MODE (dopo riga 71)

```mql5
//+------------------------------------------------------------------+
//| ENUM — HTF Filter Mode (Fase 1)                                  |
//+------------------------------------------------------------------+
enum ENUM_HTF_FILTER_MODE
  {
   HTF_DONCHIAN = 0,  // Donchian Midline (originale)
   HTF_UTBOT    = 1   // UTBot B_State (raccomandato)
  };
```

---

## FILE 2: rattInputParameters.mqh

### MODIFICA A: Sostituzione blocco HTF (righe 115-121)

Trovare:
```mql5
input group "    🔍 HTF SETTINGS"
input bool           UseHTFFilter           = false;         // ✅ Enable HTF Filter
input ENUM_TIMEFRAMES HTFTimeframe          = PERIOD_H1;     // 📋 HTF Timeframe ▼
input int            HTFPeriod              = 20;            // 📊 HTF Donchian Period
```

Sostituire con:
```mql5
input group "    🔍 HTF SETTINGS"
input bool                UseHTFFilter      = false;         // ✅ Enable HTF Filter
input ENUM_HTF_FILTER_MODE HTFFilterMode    = HTF_UTBOT;     // 📋 HTF Mode: UTBot (raccomandato) o Donchian ▼
input ENUM_TIMEFRAMES     HTFTimeframe      = PERIOD_M30;    // 📋 HTF Timeframe ▼ (M30 per M5, H1 per M15)
input int                 HTFPeriod         = 20;            // 📊 HTF Donchian Period (solo se Donchian mode)
```

### MODIFICA B: Nuovi input Fase 1 — Inserire DOPO il blocco HTF SETTINGS

```mql5
input group "    🛡️ ANTI-WHIPSAW (Fase 1)"
input int            InpConfirmBars         = 0;             // 🔢 Barre conferma crossover (0=off, 2=raccomandato M5)
input int            InpCooldownBars        = 0;             // ⏱️ Cooldown anti-flip (barre, 0=off, 6=raccomandato M5)
input bool           InpERReversalMode      = false;         // 🔄 ER asimmetrico: inversioni richiedono ER forte
```

**NOTA**: tutti i default sono OFF/0 per backward compatibility.
Nessun comportamento cambia finché l'utente non attiva esplicitamente i filtri.

---

## FILE 3: rattGlobalVariables.mqh

### Inserimento: DOPO riga 87 (`int g_sqzHandle = INVALID_HANDLE;`)

```mql5
//+------------------------------------------------------------------+
//| Fase 1: Anti-whipsaw state                                       |
//+------------------------------------------------------------------+

// --- Handle UTBot HTF bias ---
int    g_htfUTBHandle = INVALID_HANDLE;

// --- Conferma N-barre (Mod 2) ---
int    g_confirmPendingDir = 0;    // +1=BUY pending, -1=SELL pending, 0=nessuno
int    g_confirmCount      = 0;    // barre consecutive di conferma

// --- Cooldown post-entry (Mod 3) ---
datetime g_cooldownEntryTime = 0;  // timestamp dell'ultima entrata
int      g_cooldownEntryDir  = 0;  // direzione dell'ultima entrata (+1/-1)

// --- ER asimmetrico (Mod Bonus) ---
int    g_lastConfirmedDir = 0;     // ultima direzione confermata (+1/-1)
```

---

## FILE 4: rattHTFFilter.mqh — SOSTITUZIONE COMPLETA

Sostituire l'INTERO contenuto del file con:

```mql5
//+------------------------------------------------------------------+
//|                                          rattHTFFilter.mqh       |
//|           Rattapignola EA v1.8.0 — HTF Direction Filter          |
//|                                                                  |
//|  Two modes:                                                      |
//|    HTF_DONCHIAN: Original midline filter (backward compatible)   |
//|    HTF_UTBOT:    UTBot B_State on higher TF (recommended)        |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| HTF Filter State                                                 |
//+------------------------------------------------------------------+
int g_htfDirection = 0;  // +1=bullish, -1=bearish, 0=neutral

//+------------------------------------------------------------------+
//| HTFGetDirection_Donchian — Original Donchian midline             |
//+------------------------------------------------------------------+
int HTFGetDirection_Donchian()
{
   int totalBars = iBars(_Symbol, HTFTimeframe);
   if(totalBars < HTFPeriod + 2) return 0;

   int highIdx = iHighest(_Symbol, HTFTimeframe, MODE_HIGH, HTFPeriod, 1);
   int lowIdx  = iLowest(_Symbol, HTFTimeframe, MODE_LOW, HTFPeriod, 1);
   if(highIdx < 0 || lowIdx < 0) return 0;

   double htfUpper = iHigh(_Symbol, HTFTimeframe, highIdx);
   double htfLower = iLow(_Symbol, HTFTimeframe, lowIdx);
   double htfMid   = (htfUpper + htfLower) / 2.0;
   double htfClose = iClose(_Symbol, HTFTimeframe, 1);

   if(htfClose > htfMid) return +1;
   if(htfClose < htfMid) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| HTFGetDirection_UTBot — Read B_State from UTBot on HTF           |
//|                                                                  |
//|  Reads buffer 13 (B_State) from embedded UTBotAdaptive on HTF.  |
//|  bar[1] = barra chiusa (anti-repainting garantito).              |
//|  Returns: +1 (UTBot HTF LONG), -1 (SHORT), 0 (neutral/error)   |
//+------------------------------------------------------------------+
int HTFGetDirection_UTBot()
{
   if(g_htfUTBHandle == INVALID_HANDLE) return 0;

   double stateArr[1];
   // Buffer 13 = B_State, bar index 1 = ultima barra chiusa HTF
   if(CopyBuffer(g_htfUTBHandle, 13, 1, 1, stateArr) < 1)
   {
      AdLogD(LOG_CAT_HTF, "HTF UTBot: CopyBuffer failed — data not ready");
      return 0;
   }

   if(stateArr[0] > 0.5)  return +1;   // UTBot HTF is LONG
   if(stateArr[0] < -0.5) return -1;   // UTBot HTF is SHORT
   return 0;                             // Neutral
}

//+------------------------------------------------------------------+
//| HTFGetDirection — Dispatcher (seleziona mode)                    |
//+------------------------------------------------------------------+
int HTFGetDirection()
{
   if(!UseHTFFilter) return 0;

   if(HTFFilterMode == HTF_UTBOT)
      return HTFGetDirection_UTBot();
   else
      return HTFGetDirection_Donchian();
}

//+------------------------------------------------------------------+
//| HTFCheckSignal — Check if signal is compatible with HTF         |
//+------------------------------------------------------------------+
bool HTFCheckSignal(int direction)
{
   if(!UseHTFFilter) return true;

   g_htfDirection = HTFGetDirection();

   if(direction > 0 && g_htfDirection < 0)
   {
      AdLogI(LOG_CAT_FILTER, StringFormat("HTF BLOCKED BUY — HTF %s",
             HTFFilterMode == HTF_UTBOT ? "UTBot SHORT" : "Donchian bearish"));
      return false;
   }

   if(direction < 0 && g_htfDirection > 0)
   {
      AdLogI(LOG_CAT_FILTER, StringFormat("HTF BLOCKED SELL — HTF %s",
             HTFFilterMode == HTF_UTBOT ? "UTBot LONG" : "Donchian bullish"));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| HTFGetStatusString — For dashboard display                      |
//+------------------------------------------------------------------+
string HTFGetStatusString()
{
   if(!UseHTFFilter) return "OFF";
   g_htfDirection = HTFGetDirection();
   string modeStr = (HTFFilterMode == HTF_UTBOT) ? "UTB " : "DON ";
   if(g_htfDirection > 0)  return modeStr + "BULL";
   if(g_htfDirection < 0)  return modeStr + "BEAR";
   return modeStr + "NEUTRAL";
}

//+------------------------------------------------------------------+
//| InitializeHTFFilter                                              |
//+------------------------------------------------------------------+
void InitializeHTFFilter()
{
   if(!UseHTFFilter)
   {
      Log_InitConfig("HTF Filter", "DISABLED");
      return;
   }

   //--- Create UTBot handle on HTF if UTBot mode ---
   if(HTFFilterMode == HTF_UTBOT)
   {
      // Mapping enum: EA usa UTB_TF_AUTO=0, indicatore usa TF_PRESET_UT_AUTO=0
      // Entrambi hanno valore 0 per AUTO → cast diretto OK
      // Passiamo AUTO: l'indicatore applicherà il preset per HTFTimeframe automaticamente.
      //
      // ORDINE PARAMETRI iCustom — deve corrispondere ESATTAMENTE alla
      // dichiarazione degli input in UTBotAdaptive.mq5:
      //   InpTFPreset, InpKeyValue, InpATRPeriod,
      //   InpSrcType, InpHMAPeriod,
      //   InpKAMA_N, InpKAMA_Fast, InpKAMA_Slow,
      //   InpJMA_Period, InpJMA_Phase,
      //   InpUseBias(=false), InpBiasTF(=dummy),
      //   InpColorBars(=false), InpShowArrows(=false),
      //   InpApplyTheme(=false), InpShowGrid(=false),
      //   InpThemeBG, InpThemeFG, InpThemeGrid,
      //   InpThemeBullCandl, InpThemeBearCandl,
      //   InpAlertPopup(=false), InpAlertPush(=false)
      g_htfUTBHandle = iCustom(_Symbol, HTFTimeframe,
                               "::Indicators\\UTBotAdaptive.ex5",
                               0,                  // InpTFPreset = AUTO
                               InpKeyValue,         // InpKeyValue (user input)
                               InpATRPeriod_UTB,    // InpATRPeriod
                               (int)InpSrcType,     // InpSrcType
                               InpHMAPeriod,        // InpHMAPeriod
                               InpKAMA_N,           // InpKAMA_N
                               InpKAMA_Fast,        // InpKAMA_Fast
                               InpKAMA_Slow,        // InpKAMA_Slow
                               InpJMA_Period,       // InpJMA_Period
                               InpJMA_Phase,        // InpJMA_Phase
                               false, PERIOD_H1,    // InpUseBias=OFF, InpBiasTF=dummy
                               false, false,         // InpColorBars=OFF, InpShowArrows=OFF
                               false, false,         // InpApplyTheme=OFF, InpShowGrid=OFF
                               C'19,23,34', C'131,137,150', C'42,46,57',  // Theme colors (dummy)
                               C'38,166,154', C'239,83,80',                // Candle colors (dummy)
                               false, false);        // InpAlertPopup=OFF, InpAlertPush=OFF

      if(g_htfUTBHandle == INVALID_HANDLE)
      {
         AdLogE(LOG_CAT_HTF, StringFormat("CRITICAL: Failed to create UTBot HTF handle on %s",
                EnumToString(HTFTimeframe)));
         AdLogW(LOG_CAT_HTF, "Falling back to Donchian mode");
         // Non serve fallback esplicito — HTFGetDirection_UTBot() ritorna 0 con INVALID_HANDLE
      }
      else
      {
         AdLogI(LOG_CAT_HTF, StringFormat("UTBot HTF handle created on %s (handle=%d)",
                EnumToString(HTFTimeframe), g_htfUTBHandle));
      }
   }

   g_htfDirection = HTFGetDirection();
   Log_InitConfig("HTF.Mode", HTFFilterMode == HTF_UTBOT ? "UTBot" : "Donchian");
   Log_InitConfig("HTF.Timeframe", EnumToString(HTFTimeframe));
   if(HTFFilterMode == HTF_DONCHIAN)
      Log_InitConfig("HTF.Period", IntegerToString(HTFPeriod));
   Log_InitConfig("HTF.Direction", HTFGetStatusString());
   Log_InitComplete("HTF Filter");
}

//+------------------------------------------------------------------+
//| DeinitializeHTFFilter — Release HTF handle                      |
//+------------------------------------------------------------------+
void DeinitializeHTFFilter()
{
   if(g_htfUTBHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_htfUTBHandle);
      g_htfUTBHandle = INVALID_HANDLE;
      AdLogI(LOG_CAT_HTF, "UTBot HTF handle released");
   }
}
```

### IMPORTANTE: Chiamare DeinitializeHTFFilter() in OnDeinit

In `Rattapignola.mq5`, nella funzione `OnDeinit()`, PRIMA di `EngineDeinit()`,
aggiungere:
```mql5
   DeinitializeHTFFilter();
```

---

## FILE 5: rattUTBotEngine.mqh — Conferma N-Barre + ER Asimmetrico

### MODIFICA A: In EngineCalculate(), DOPO STEP 4 (riga 799) e PRIMA di STEP 5 (riga 803)

Trovare:
```mql5
   bool isBuy  = (src_prev < trail_prev || src_prev == 0) && (src > trail) && trail_prev != 0;
   bool isSell = (src_prev > trail_prev || src_prev == 0) && (src < trail) && trail_prev != 0;

   // ================================================================
   // STEP 5: Efficiency Ratio + quality classification
```

Sostituire con:
```mql5
   bool rawBuy  = (src_prev < trail_prev || src_prev == 0) && (src > trail) && trail_prev != 0;
   bool rawSell = (src_prev > trail_prev || src_prev == 0) && (src < trail) && trail_prev != 0;

   // ================================================================
   // STEP 4b: Conferma N-barre (Fase 1, Mod 2)
   // Il crossover deve persistere per InpConfirmBars barre consecutive.
   // Se il prezzo torna sopra/sotto il trail prima della conferma,
   // il segnale viene annullato.
   // ================================================================
   bool isBuy  = rawBuy;
   bool isSell = rawSell;

   if(InpConfirmBars >= 2)
   {
      if(rawBuy)
      {
         if(g_confirmPendingDir == +1)
            g_confirmCount++;
         else
         {
            g_confirmPendingDir = +1;
            g_confirmCount = 1;
         }
      }
      else if(rawSell)
      {
         if(g_confirmPendingDir == -1)
            g_confirmCount++;
         else
         {
            g_confirmPendingDir = -1;
            g_confirmCount = 1;
         }
      }
      else
      {
         g_confirmCount = 0;
         g_confirmPendingDir = 0;
      }

      // Segnale confermato solo dopo N barre
      isBuy  = (g_confirmPendingDir == +1 && g_confirmCount >= InpConfirmBars);
      isSell = (g_confirmPendingDir == -1 && g_confirmCount >= InpConfirmBars);

      // Reset dopo emissione
      if(isBuy || isSell)
      {
         g_confirmCount = 0;
         g_confirmPendingDir = 0;
      }

      // Log per debug
      if(rawBuy || rawSell)
         AdLogD(LOG_CAT_UTB, StringFormat("CONFIRM: raw=%s pending=%d count=%d/%d → %s",
                rawBuy ? "BUY" : "SELL", g_confirmPendingDir, g_confirmCount, InpConfirmBars,
                (isBuy || isSell) ? "CONFIRMED" : "PENDING"));
   }

   // ================================================================
   // STEP 5: Efficiency Ratio + quality classification
```

### MODIFICA B: Filtro ER Asimmetrico — SOSTITUZIONE del blocco ER filter

Trovare (righe 813-819):
```mql5
   // Skip weak signals if ER below minimum and weak signals not shown
   if((isBuy || isSell) && er < InpERWeak && !InpShowWeakSig)
   {
      AdLogD(LOG_CAT_UTB, StringFormat("Signal skipped: ER=%.3f < ERWeak=%.3f (ShowWeak=false)", er, InpERWeak));
      isBuy  = false;
      isSell = false;
   }
```

Sostituire con:
```mql5
   // Skip weak signals — con modalità asimmetrica per inversioni
   if((isBuy || isSell))
   {
      if(InpERReversalMode)
      {
         // Modalità asimmetrica: inversioni richiedono ER forte
         int newDir = isBuy ? +1 : -1;
         bool isReversal = (g_lastConfirmedDir != 0 && newDir != g_lastConfirmedDir);
         double erThreshold = isReversal ? InpERStrong : InpERWeak;

         if(er < erThreshold)
         {
            AdLogI(LOG_CAT_UTB, StringFormat("ER ASYM FILTER: %s ER=%.3f < %.3f (%s) — BLOCKED",
                   isBuy ? "BUY" : "SELL", er, erThreshold,
                   isReversal ? "REVERSAL threshold" : "CONTINUATION threshold"));
            isBuy  = false;
            isSell = false;
         }
      }
      else
      {
         // Modalità originale: filtro simmetrico
         if(er < InpERWeak && !InpShowWeakSig)
         {
            AdLogD(LOG_CAT_UTB, StringFormat("Signal skipped: ER=%.3f < ERWeak=%.3f", er, InpERWeak));
            isBuy  = false;
            isSell = false;
         }
      }
   }

   // Aggiorna ultima direzione confermata (per ER asimmetrico)
   if(isBuy)  g_lastConfirmedDir = +1;
   if(isSell) g_lastConfirmedDir = -1;
```

### MODIFICA C: Reset stato conferma in EngineInit()

In `EngineInit()`, DOPO riga 621 (`g_lastSignal.Reset();`), aggiungere:
```mql5
   // Reset Fase 1 state
   g_confirmPendingDir = 0;
   g_confirmCount      = 0;
   g_lastConfirmedDir  = 0;
   g_cooldownEntryTime = 0;
   g_cooldownEntryDir  = 0;
```

---

## FILE 6: Rattapignola.mq5 — Cooldown Post-Entry

### MODIFICA A: Cooldown check — Inserire DOPO riga 495, PRIMA di PerformRiskChecks

Trovare:
```mql5
   if(hasSignal && sig.isNewSignal && sig.direction != 0)
   {
      // Pre-trade checks (spread + daily loss checked inside PerformRiskChecks)
      bool passChecks = true;

      if(!PerformRiskChecks())
```

Sostituire con:
```mql5
   if(hasSignal && sig.isNewSignal && sig.direction != 0)
   {
      // Pre-trade checks
      bool passChecks = true;

      // ── COOLDOWN CHECK (Fase 1, Mod 3) ───────────────────────────
      // Blocca segnali nella direzione OPPOSTA all'ultimo trade
      // per InpCooldownBars barre. Impedisce il flip-flop rapido.
      if(InpCooldownBars > 0 && g_cooldownEntryDir != 0
         && sig.direction == -g_cooldownEntryDir)
      {
         int barsSinceEntry = 0;
         if(g_cooldownEntryTime > 0)
         {
            datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
            barsSinceEntry = (int)((currentBarTime - g_cooldownEntryTime)
                             / PeriodSeconds(PERIOD_CURRENT));
         }

         if(barsSinceEntry < InpCooldownBars)
         {
            AdLogI(LOG_CAT_FILTER, StringFormat(
                   "COOLDOWN: %s BLOCCATO — %d/%d barre dal %s precedente",
                   sig.direction > 0 ? "BUY" : "SELL",
                   barsSinceEntry, InpCooldownBars,
                   g_cooldownEntryDir > 0 ? "BUY" : "SELL"));
            passChecks = false;
         }
      }

      if(!PerformRiskChecks())
```

### MODIFICA B: Aggiornamento cooldown dopo piazzamento ordine

Trovare (circa riga 618, dentro il blocco `if(slot >= 0)`):
```mql5
               AdLogD(LOG_CAT_TRIGGER, StringFormat("DIAG: CreateCycle OK — slot=%d | CycleID=#%d | Ticket=%d",
                      slot, g_cycles[slot].cycleID, g_cycles[slot].ticket));
```

SUBITO DOPO questa riga, aggiungere:
```mql5
               // ── Aggiorna stato cooldown (Fase 1) ──
               g_cooldownEntryTime = iTime(_Symbol, PERIOD_CURRENT, 1);
               g_cooldownEntryDir  = sig.direction;
```

### MODIFICA B2: Stesso aggiornamento per VirtualMode

Trovare (circa riga 602, dentro `if(vSlot >= 0)`):
```mql5
               AdLogI(LOG_CAT_VIRTUAL, "Virtual trade created");
```

SUBITO DOPO, aggiungere:
```mql5
               g_cooldownEntryTime = iTime(_Symbol, PERIOD_CURRENT, 1);
               g_cooldownEntryDir  = sig.direction;
```

---

## DASHBOARD: Mostrare stato filtri Fase 1

In `rattDashboard.mqh`, nella sezione dove si costruisce il dashboard,
aggiungere dopo la riga HTF:

```mql5
   // Fase 1 status
   if(InpConfirmBars >= 2)
      DashSetRow(row++, "Confirm", IntegerToString(InpConfirmBars) + " bars", RATT_AMBER);
   if(InpCooldownBars > 0)
   {
      int barsSince = 0;
      if(g_cooldownEntryTime > 0)
         barsSince = (int)((iTime(_Symbol,PERIOD_CURRENT,0) - g_cooldownEntryTime) / PeriodSeconds(PERIOD_CURRENT));
      string cdStatus = (barsSince < InpCooldownBars && g_cooldownEntryDir != 0)
                         ? StringFormat("ACTIVE %d/%d", barsSince, InpCooldownBars)
                         : "READY";
      DashSetRow(row++, "Cooldown", cdStatus,
                 barsSince < InpCooldownBars ? RATT_SELL : RATT_BUY);
   }
   if(InpERReversalMode)
      DashSetRow(row++, "ER Asym", "ON (rev>=" + DoubleToString(InpERStrong,2) + ")", RATT_AMBER);
```

---

## CHECKLIST PRE-COMPILAZIONE

1. [ ] `rattEnums.mqh`: nuovo enum `ENUM_HTF_FILTER_MODE` aggiunto
2. [ ] `rattInputParameters.mqh`: nuovi input + `HTFFilterMode` + default M30
3. [ ] `rattGlobalVariables.mqh`: 6 nuove variabili globali aggiunte
4. [ ] `rattHTFFilter.mqh`: file completamente sostituito con versione dual-mode
5. [ ] `Rattapignola.mq5 OnDeinit()`: chiamata `DeinitializeHTFFilter()` aggiunta
6. [ ] `rattUTBotEngine.mqh EngineCalculate()`: conferma N-barre inserita dopo STEP 4
7. [ ] `rattUTBotEngine.mqh EngineCalculate()`: ER asimmetrico sostituito al filtro ER
8. [ ] `rattUTBotEngine.mqh EngineInit()`: reset variabili Fase 1 aggiunto
9. [ ] `Rattapignola.mq5 OnTick()`: cooldown check inserito prima di PerformRiskChecks
10. [ ] `Rattapignola.mq5 OnTick()`: aggiornamento cooldown dopo CreateCycle
11. [ ] Dashboard: righe stato Fase 1 aggiunte

## PARAMETRI CONSIGLIATI PER PRIMO TEST

### M5 GBPJPY (aggressivo — tutti i filtri attivi):
```
UseHTFFilter      = true
HTFFilterMode     = HTF_UTBOT
HTFTimeframe      = PERIOD_M30
InpConfirmBars    = 2
InpCooldownBars   = 6
InpERReversalMode = true
```

### M15 GBPJPY (moderato):
```
UseHTFFilter      = true
HTFFilterMode     = HTF_UTBOT
HTFTimeframe      = PERIOD_H1
InpConfirmBars    = 1        ← nessuna conferma su M15
InpCooldownBars   = 3
InpERReversalMode = true
```

### Test conservativo (una modifica alla volta):
Attiva solo Mod 1 prima, testa, poi aggiungi le altre:
```
Step 1: UseHTFFilter=true, HTFFilterMode=HTF_UTBOT, resto OFF
Step 2: + InpConfirmBars=2
Step 3: + InpCooldownBars=6
Step 4: + InpERReversalMode=true
```
