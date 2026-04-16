# Rattapignola EA v1.0.0 → v1.1.0 — Istruzioni Modifiche per Claude Code

> **Data**: Aprile 2026
> **Autore**: Review tecnica completa dell'EA
> **Obiettivo**: Correzioni bug, completamento preset, nuovi TP mode, SL emergenza
> **File coinvolti**: rattEnums.mqh, rattInputParameters.mqh, rattUTBotEngine.mqh, rattCycleManager.mqh, rattOrderManager.mqh, rattSignalMarkers.mqh, rattChannelOverlay.mqh, Rattapignola.mq5, rattGlobalVariables.mqh

---

## INDICE MODIFICHE

| # | Priorità | Tipo | Descrizione |
|---|----------|------|-------------|
| FIX-01 | 🔴 CRITICO | Bug Fix | SL di emergenza — posizioni senza protezione |
| FIX-02 | 🔴 CRITICO | Bug Fix | S2S fallback mancante quando TPMode != S2S |
| FIX-03 | 🟡 IMPORTANTE | Completamento | Preset JMA incompleti per M30/H1/H4 |
| FIX-04 | 🟡 IMPORTANTE | Completamento | Preset mancanti D1/W1/MN |
| FIX-05 | 🟡 IMPORTANTE | Bug Fix | Scan storico frecce usa solo Close (disallineamento JMA/KAMA) |
| ADD-01 | 🟢 FEATURE | Nuovo TP Mode | TP_TRAILING_ATR — trailing stop ATR dinamico |
| ADD-02 | 🟢 FEATURE | Nuovo TP Mode | TP_PIVOT_EXIT — exit su pivot high/low confermato |
| ADD-03 | 🟢 FEATURE | Enhancement | Uscita parziale SQZ (close 50% lotto, rest fino a S2S) |
| ADD-04 | 🟢 FEATURE | Enhancement | SQZ HalfPeakRatio nei preset TF |
| ADD-05 | 🟢 FEATURE | Enhancement | Indicatore visivo "FLAT" nel dashboard quando SQZ chiude prima del flip |

---

## FIX-01: SL DI EMERGENZA (CRITICO)

### Problema
Il SL è completamente disattivato. Il commento nel codice dice: *"Il calcolo SL era buggato (SL_BAND_OPPOSITE invertiva la direzione) e causava il rifiuto di tutti gli ordini pendenti."* Le posizioni vengono piazzate senza stop loss. Un crash di connessione con S2S attivo lascia posizioni completamente scoperte.

### Soluzione
Aggiungere un SL di emergenza opzionale basato su ATR multiplo. NON ripristinare il vecchio sistema SL_BAND_OPPOSITE che era buggato.

### File: `rattInputParameters.mqh`

Aggiungere dopo la sezione "TAKE PROFIT" (dopo `input double TPValue`):

```mql5
input group "    🛡️ STOP LOSS EMERGENZA"
input bool           EnableEmergencySL       = true;          // ✅ SL di emergenza (safety net)
input double         EmergencySLMultiplier   = 5.0;           // 📏 SL = N × ATR dalla entry (default 5.0)
```

### File: `rattCycleManager.mqh` — Funzione `CreateCycle`

Dopo il calcolo del lotSize e prima della chiamata `OrderPlace`, aggiungere il calcolo del SL di emergenza:

```mql5
// ── SL di emergenza: safety net basato su ATR ──
if(EnableEmergencySL && EmergencySLMultiplier > 0)
{
   double emergencyATR = 0;
   double atrBuf[1];
   if(CopyBuffer(g_utb_atrHandle, 0, 1, 1, atrBuf) >= 1)
      emergencyATR = atrBuf[0];

   if(emergencyATR > 0)
   {
      double slDistance = EmergencySLMultiplier * emergencyATR;
      if(sig.direction > 0)
         g_cycles[slot].slPrice = NormalizeDouble(sig.entryPrice - slDistance, (int)g_symbolDigits);
      else
         g_cycles[slot].slPrice = NormalizeDouble(sig.entryPrice + slDistance, (int)g_symbolDigits);

      // Aggiorna anche sig.slPrice per passarlo a OrderPlace
      sig.slPrice = g_cycles[slot].slPrice;

      AdLogI(LOG_CAT_CYCLE, StringFormat("EMERGENCY SL: %s @ %s (%.1f × ATR=%.5f)",
             sig.direction > 0 ? "below" : "above",
             FormatPrice(g_cycles[slot].slPrice),
             EmergencySLMultiplier, emergencyATR));
   }
   else
   {
      AdLogW(LOG_CAT_CYCLE, "EMERGENCY SL: ATR non disponibile — SL non impostato");
   }
}
```

### File: `rattOrderManager.mqh` — Tutte le funzioni OrderPlace

Dove attualmente il SL viene passato come `0`, passare invece `sig.slPrice` (che sarà 0 se l'emergency SL è disabilitato, oppure il valore calcolato se abilitato). Modificare:

- `OrderPlaceMarket(sig.direction, lots, 0, sig.tpPrice, comment)` → `OrderPlaceMarket(sig.direction, lots, sig.slPrice, sig.tpPrice, comment)`
- `OrderPlacePending(...)` — stesso cambio, il terzo parametro `sl` deve ricevere `sig.slPrice` invece di `0`

**ATTENZIONE**: verificare che la direzione del SL sia corretta (BUY → SL sotto entry, SELL → SL sopra entry) nella funzione `ValidateStopLoss` se esiste, o aggiungerla se non esiste.

---

## FIX-02: S2S FALLBACK QUANDO TPMode != S2S (CRITICO)

### Problema
`CloseOppositeOnSignal(sig.direction)` viene chiamato SOLO se `TPMode == TP_SIGNAL_TO_SIGNAL`. Se l'utente usa `TP_SQUEEZE_EXIT` o `TP_ATR_MULTIPLE` o `TP_FIXED_PIPS`, e il TP non viene raggiunto prima del segnale opposto, le posizioni vecchie NON vengono chiuse. Questo può causare accumulo di posizioni in direzioni opposte.

### Soluzione
Chiamare SEMPRE `CloseOppositeOnSignal` al segnale opposto, indipendentemente dal TPMode. Il S2S flip è una safety net universale.

### File: `Rattapignola.mq5` — Step 10, sezione PROCESS SIGNAL

Trovare:
```mql5
// ── S2S: Chiudi/cancella cicli opposti PRIMA di aprire il nuovo ──
if(TPMode == TP_SIGNAL_TO_SIGNAL)
{
    int flipped = CloseOppositeOnSignal(sig.direction);
    if(flipped > 0)
        AdLogI(LOG_CAT_CYCLE, StringFormat("S2S: %d cicli opposti chiusi/cancellati", flipped));
}
```

Sostituire con:
```mql5
// ── FLIP UNIVERSALE: Chiudi/cancella cicli opposti PRIMA di aprire il nuovo ──
// Indipendentemente dal TPMode, un segnale opposto chiude sempre i cicli vecchi.
// Questo è il safety net: se TP_SQUEEZE_EXIT o TP_ATR_MULTIPLE non hanno
// ancora chiuso la posizione, il flip la chiude comunque.
{
    int flipped = CloseOppositeOnSignal(sig.direction);
    if(flipped > 0)
        AdLogI(LOG_CAT_CYCLE, StringFormat("FLIP: %d cicli opposti chiusi/cancellati (TPMode=%s)",
               flipped, EnumToString(TPMode)));
}
```

---

## FIX-03: PRESET JMA INCOMPLETI PER M30/H1/H4

### Problema
Nello switch dei preset in `rattUTBotEngine.mqh` (funzione che applica i preset, probabilmente `UTBApplyPreset` o lo switch nei case `TF_PRESET_UT_M30`, `TF_PRESET_UT_H1`, `TF_PRESET_UT_H4`), i valori `g_utb_jmaPeriod` e `g_utb_jmaPhase` non vengono settati per M30, H1, H4.

### Soluzione
Aggiungere i valori JMA nei case mancanti. I valori sono derivati dalla stessa logica degli altri parametri (periodo cresce con il TF, phase=0 bilanciato):

### File: `rattUTBotEngine.mqh` — Switch dei preset

Per ogni case, aggiungere DOPO le righe `g_eff_kamaSlow`:

**Case TF_PRESET_UT_M30 / UTB_TF_M30:**
```mql5
g_utb_jmaPeriod = 14;   // M30: 14 periodi = 7 ore lookback
g_utb_jmaPhase  = 0;    // bilanciato
```

**Case TF_PRESET_UT_H1 / UTB_TF_H1:**
```mql5
g_utb_jmaPeriod = 20;   // H1: 20 periodi = 20 ore lookback (quasi 1 giorno)
g_utb_jmaPhase  = 0;    // bilanciato
```

**Case TF_PRESET_UT_H4 / UTB_TF_H4:**
```mql5
g_utb_jmaPeriod = 20;   // H4: 20 periodi = 80 ore lookback (~3.3 giorni)
g_utb_jmaPhase  = -10;  // leggermente più smooth per ridurre whipsaw su TF alto
```

**NOTA**: verificare che la struct `UTBPreset` contenga i campi `jmaPeriod` e `jmaPhase` (dalla review del codice risulta che li ha). Se i preset sono in un array `g_utb_presetTable[]`, aggiornare anche lì.

---

## FIX-04: PRESET MANCANTI D1/W1/MN

### Problema
I TF D1, W1, MN non hanno preset. Il fallback è MANUAL con i parametri di default dell'input (Key=1.0, ATR=10) che sono tarati per M5 e risultano troppo stretti su TF alti.

### Soluzione

### File: `rattEnums.mqh`

Aggiungere all'enum `ENUM_UTB_TF_PRESET`:
```mql5
UTB_TF_D1  = 7,   // D1 Preset
UTB_TF_W1  = 8,   // W1 Preset
UTB_TF_MN  = 9,   // MN Preset
```

### File: `rattUTBotEngine.mqh`

1. Aggiungere i case nello switch di AUTO detection:
```mql5
case PERIOD_D1:  preset = UTB_TF_D1;  break;
case PERIOD_W1:  preset = UTB_TF_W1;  break;
case PERIOD_MN1: preset = UTB_TF_MN;  break;
```

2. Aggiungere i preset (nella tabella o nello switch):

**D1:**
```mql5
// D1: Key=3.0, ATR=14, KAMA(20/2/40), JMA(20/0)
// Rationale: trend giornaliero, ER su 20 sessioni, massimo smoothing KAMA
g_utb_keyValue  = 3.0;
g_utb_atrPeriod = 14;
g_utb_kamaN     = 20;
g_utb_kamaFast  = 2;
g_utb_kamaSlow  = 40;
g_utb_jmaPeriod = 20;
g_utb_jmaPhase  = 0;
g_pendingExpiry = 3;   // 3 barre = 3 giorni
```

**W1:**
```mql5
// W1: Key=3.5, ATR=14, KAMA(14/2/40), JMA(14/-10)
// Rationale: trend settimanale, necessita stop largo per assorbire rumore intraweek
g_utb_keyValue  = 3.5;
g_utb_atrPeriod = 14;
g_utb_kamaN     = 14;
g_utb_kamaFast  = 2;
g_utb_kamaSlow  = 40;
g_utb_jmaPeriod = 14;
g_utb_jmaPhase  = -10;
g_pendingExpiry = 2;   // 2 barre = 2 settimane
```

**MN:**
```mql5
// MN: Key=4.0, ATR=10, KAMA(10/2/30), JMA(10/-20)
// Rationale: trend mensile, pochissime barre, parametri conservativi
g_utb_keyValue  = 4.0;
g_utb_atrPeriod = 10;
g_utb_kamaN     = 10;
g_utb_kamaFast  = 2;
g_utb_kamaSlow  = 30;
g_utb_jmaPeriod = 10;
g_utb_jmaPhase  = -20;
g_pendingExpiry = 2;   // 2 barre = 2 mesi
```

---

## FIX-05: SCAN STORICO FRECCE — ALLINEAMENTO SORGENTE ADATTIVA

### Problema
`ScanHistoricalSignals()` in `rattSignalMarkers.mqh` usa SOLO `closeBuf[i]` come sorgente, anche quando l'engine è configurato con JMA/KAMA/HMA. Questo causa disallineamento fra le frecce storiche e i segnali che l'engine avrebbe generato in real-time.

### Soluzione
Implementare il calcolo della sorgente adattiva anche nello scan storico. Per JMA e KAMA servono calcoli ricorsivi da oldest a newest (che è già il verso dello scan).

### File: `rattSignalMarkers.mqh` — Funzione `ScanHistoricalSignals`

Sostituire la riga:
```mql5
double curSrc = closeBuf[i];  // Default: close
// For HMA/KAMA/JMA, simplified version using close for historical scan
// (Full adaptive source would require extensive computation per bar)
```

Con un blocco switch completo. Dato che lo scan va già da oldest a newest, i calcoli ricorsivi (KAMA, JMA) funzionano naturalmente:

```mql5
double curSrc = closeBuf[i];  // Default: close

switch(InpSrcType)
{
   case UTB_SRC_CLOSE:
      curSrc = closeBuf[i];
      break;

   case UTB_SRC_KAMA:
   {
      // KAMA ricorsivo: SC = ER * (fast - slow) + slow; KAMA = KAMA_prev + SC^2 * (close - KAMA_prev)
      double sc_fast = 2.0 / (g_utb_kamaFast + 1.0);
      double sc_slow = 2.0 / (g_utb_kamaSlow + 1.0);

      if(!kama_init)
      {
         kama_prev = closeBuf[i];
         kama_init = true;
         curSrc = closeBuf[i];
      }
      else
      {
         // Calcola ER su finestra N barre (serve guardare indietro di N barre)
         // Nota: nello scan i è decrescente (oldest=depth+lookback-2, newest=1)
         // quindi "N barre fa" = i + g_utb_kamaN
         double erKama = 0;
         if(i + g_utb_kamaN < depth + lookback - 1)
         {
            double direction_k = MathAbs(closeBuf[i] - closeBuf[i + g_utb_kamaN]);
            double volatility_k = 0;
            for(int k = i; k < i + g_utb_kamaN; k++)
               volatility_k += MathAbs(closeBuf[k] - closeBuf[k + 1]);
            erKama = (volatility_k > 0) ? direction_k / volatility_k : 0;
         }
         double sc = erKama * (sc_fast - sc_slow) + sc_slow;
         curSrc = kama_prev + sc * sc * (closeBuf[i] - kama_prev);
         kama_prev = curSrc;
      }
      break;
   }

   case UTB_SRC_HMA:
   {
      // HMA = WMA(2*WMA(close, N/2) - WMA(close, N), sqrt(N))
      // Approssimazione semplificata per scan storico: usa WMA su closeBuf
      int halfPeriod = g_utb_hmaPeriod / 2;
      int sqrtPeriod = (int)MathSqrt(g_utb_hmaPeriod);
      if(halfPeriod < 1) halfPeriod = 1;
      if(sqrtPeriod < 1) sqrtPeriod = 1;

      // Verifica che abbiamo abbastanza barre
      if(i + g_utb_hmaPeriod + sqrtPeriod < depth + lookback - 1)
      {
         // WMA(N/2)
         double wma_half = 0, wsum_half = 0;
         for(int w = 0; w < halfPeriod; w++)
         {
            double weight = (double)(halfPeriod - w);
            wma_half += closeBuf[i + w] * weight;
            wsum_half += weight;
         }
         if(wsum_half > 0) wma_half /= wsum_half;

         // WMA(N)
         double wma_full = 0, wsum_full = 0;
         for(int w = 0; w < g_utb_hmaPeriod; w++)
         {
            double weight = (double)(g_utb_hmaPeriod - w);
            wma_full += closeBuf[i + w] * weight;
            wsum_full += weight;
         }
         if(wsum_full > 0) wma_full /= wsum_full;

         curSrc = 2.0 * wma_half - wma_full;
         // Nota: manca il WMA finale su sqrt(N) — approssimazione accettabile per scan storico
      }
      break;
   }

   case UTB_SRC_JMA:
   {
      // JMA ricorsivo (3 stadi IIR)
      // Usa le stesse costanti dell'engine: g_utb_jma_bet, g_utb_jma_beta, g_utb_jma_pow1, g_utb_jma_len1
      if(!jma_init)
      {
         jma_e0 = closeBuf[i];
         jma_e1 = 0;
         jma_e2 = closeBuf[i];
         jma_prev = closeBuf[i];
         jma_init = true;
         curSrc = closeBuf[i];
      }
      else
      {
         double price = closeBuf[i];
         // Calcolo identico a UTBCalcJMA nell'engine
         // Se le costanti JMA (g_utb_jma_bet, g_utb_jma_beta, etc.) sono globali e accessibili,
         // usale direttamente. Altrimenti ricalcolale qui con UTBInitJMAConstants().
         double phaseRatio = (g_utb_jmaPhase >= -100 && g_utb_jmaPhase <= 100)
            ? ((g_utb_jmaPhase < 0) ? (g_utb_jmaPhase + 100.0) / 100.0 * 0.5
                                     : (g_utb_jmaPhase > 0) ? 0.5 + g_utb_jmaPhase / 100.0 * 0.5 : 0.5)
            : 0.5;

         // Questi calcoli sono semplificati — per un'implementazione esatta,
         // chiama le stesse funzioni dell'engine (UTBCalcJMA) se possibile,
         // oppure replica la formula IIR 3-stadi completa.
         // Il codice esatto è in rattUTBotEngine.mqh → UTBCalcJMA()
         //
         // PER ORA: usa la formula semplificata EMA-like come placeholder
         // da sostituire con la formula JMA completa
         double alpha = 2.0 / (g_utb_jmaPeriod + 1.0);
         curSrc = jma_prev + alpha * (price - jma_prev);
         jma_prev = curSrc;
      }
      break;
   }
}
```

**NOTA IMPORTANTE PER CLAUDE CODE**: La formula JMA completa è molto specifica (3 stadi IIR con power dinamico). La versione sopra è un placeholder EMA. Per l'implementazione esatta:
1. Leggi la funzione `UTBCalcJMA()` in `rattUTBotEngine.mqh`
2. Replica la stessa logica usando variabili locali `jma_e0, jma_e1, jma_e2` al posto delle globali `g_utb_jma_e0`, etc.
3. Le costanti (`g_utb_jma_bet`, `g_utb_jma_beta`, `g_utb_jma_pow1`, `g_utb_jma_len1`) sono già calcolate da `EngineInit()` e sono globali — puoi riusarle direttamente.

Fare lo stesso per `RedrawOverlayFill()` in `rattChannelOverlay.mqh` che ha lo stesso problema (usa solo Close per il ricalcolo del trailing stop).

---

## ADD-01: TP_TRAILING_ATR — TRAILING STOP ATR DINAMICO (NUOVO TP MODE)

### Descrizione
Trailing stop che si attiva dopo un profitto minimo e segue il prezzo a distanza di M×ATR dal massimo raggiunto. Esce quando il prezzo ritraccia di M×ATR dal top.

### File: `rattEnums.mqh`

Aggiungere all'enum `ENUM_TP_MODE`:
```mql5
TP_TRAILING_ATR   = 4,  // Trailing ATR — trailing stop dinamico (attiva dopo N×ATR profitto)
```

### File: `rattInputParameters.mqh`

Aggiungere nella sezione TP (dopo `input double TPValue`):
```mql5
input group "    📈 TRAILING ATR EXIT"
input double         TrailActivationATR     = 1.5;           // 📏 Attivazione: profitto minimo in N × ATR
input double         TrailDistanceATR       = 1.0;           // 📏 Distanza trail: M × ATR dal prezzo max raggiunto
```

### File: `rattCycleManager.mqh` — Aggiungere campi al ciclo

Nella struct `CycleInfo` (o dove sono definiti i campi di g_cycles), aggiungere:
```mql5
double   maxFavorablePrice;    // Prezzo massimo favorevole raggiunto (high per BUY, low per SELL)
bool     trailActivated;       // true quando il profitto ha superato TrailActivationATR
double   trailStopPrice;       // Livello corrente del trailing stop
```

Inizializzare in `InitializeCycles()` e `CreateCycle()`:
```mql5
g_cycles[slot].maxFavorablePrice = 0;
g_cycles[slot].trailActivated   = false;
g_cycles[slot].trailStopPrice   = 0;
```

### File: `rattCycleManager.mqh` — Nuova funzione `CheckTrailingATRExit`

Aggiungere PRIMA di `MonitorCycles`:

```mql5
//+------------------------------------------------------------------+
//| CheckTrailingATRExit — Trailing stop ATR dinamico                |
//+------------------------------------------------------------------+
void CheckTrailingATRExit()
{
   double atrBuf[1];
   if(CopyBuffer(g_utb_atrHandle, 0, 1, 1, atrBuf) < 1) return;
   double atr = atrBuf[0];
   if(atr <= 0) return;

   double activationDist = TrailActivationATR * atr;
   double trailDist      = TrailDistanceATR * atr;

   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_ACTIVE) continue;

      double currentPrice = SymbolInfoDouble(_Symbol,
         g_cycles[i].direction > 0 ? SYMBOL_BID : SYMBOL_ASK);

      // Aggiorna prezzo massimo favorevole
      if(g_cycles[i].direction > 0)  // BUY: tracka il massimo
      {
         if(currentPrice > g_cycles[i].maxFavorablePrice || g_cycles[i].maxFavorablePrice == 0)
            g_cycles[i].maxFavorablePrice = currentPrice;
      }
      else  // SELL: tracka il minimo
      {
         if(currentPrice < g_cycles[i].maxFavorablePrice || g_cycles[i].maxFavorablePrice == 0)
            g_cycles[i].maxFavorablePrice = currentPrice;
      }

      // Controlla attivazione
      if(!g_cycles[i].trailActivated)
      {
         double profitDist = 0;
         if(g_cycles[i].direction > 0)
            profitDist = g_cycles[i].maxFavorablePrice - g_cycles[i].entryPrice;
         else
            profitDist = g_cycles[i].entryPrice - g_cycles[i].maxFavorablePrice;

         if(profitDist >= activationDist)
         {
            g_cycles[i].trailActivated = true;
            AdLogI(LOG_CAT_CYCLE, StringFormat("TRAIL ATR ACTIVATED #%d: profit=%.1fp >= activation=%.1fp (%.1f×ATR)",
                   g_cycles[i].cycleID, PointsToPips(profitDist), PointsToPips(activationDist), TrailActivationATR));
         }
      }

      // Se attivato, calcola e controlla trailing stop
      if(g_cycles[i].trailActivated)
      {
         double newTrail = 0;
         if(g_cycles[i].direction > 0)
            newTrail = g_cycles[i].maxFavorablePrice - trailDist;
         else
            newTrail = g_cycles[i].maxFavorablePrice + trailDist;

         // Trail si muove solo nella direzione favorevole (ratchet)
         if(g_cycles[i].direction > 0)
            g_cycles[i].trailStopPrice = MathMax(g_cycles[i].trailStopPrice, newTrail);
         else
         {
            if(g_cycles[i].trailStopPrice == 0)
               g_cycles[i].trailStopPrice = newTrail;
            else
               g_cycles[i].trailStopPrice = MathMin(g_cycles[i].trailStopPrice, newTrail);
         }

         // Controlla se il prezzo ha attraversato il trailing stop
         bool doExit = false;
         if(g_cycles[i].direction > 0 && currentPrice <= g_cycles[i].trailStopPrice)
            doExit = true;
         if(g_cycles[i].direction < 0 && currentPrice >= g_cycles[i].trailStopPrice)
            doExit = true;

         if(doExit)
         {
            string dirStr = g_cycles[i].direction > 0 ? "BUY" : "SELL";
            AdLogI(LOG_CAT_CYCLE, StringFormat("TRAIL ATR EXIT: Chiudo %s #%d | MaxPrice=%s | TrailStop=%s | Current=%s",
                   dirStr, g_cycles[i].cycleID,
                   FormatPrice(g_cycles[i].maxFavorablePrice),
                   FormatPrice(g_cycles[i].trailStopPrice),
                   FormatPrice(currentPrice)));

            if(EnableHedge && HsEnabled) HsCleanup(i, "Trail_ATR_Exit");

            if(ClosePosition(g_cycles[i].ticket))
            {
               double soupPL = GetClosedPositionProfit(g_cycles[i].ticket);
               g_cycles[i].profit = soupPL + g_cycles[i].hsPL;
               g_cycles[i].state  = CYCLE_CLOSED;
               g_sessionRealizedProfit += soupPL;
               g_dailyRealizedProfit   += soupPL;
               if(g_cycles[i].profit > 0) { g_sessionWins++; g_dailyWins++; }
               else                       { g_sessionLosses++; g_dailyLosses++; }
               AddFeedItem("Trail exit " + DoubleToString(soupPL, 2), RATT_AMBER);
               RemoveTPLine(g_cycles[i].cycleID);
            }
         }
      }
   }
}
```

### File: `rattCycleManager.mqh` — Aggiornare `MonitorCycles`

```mql5
void MonitorCycles(const EngineSignal &sig)
{
   PollFills();
   CheckExpiry();
   UpdatePending(sig);
   if(InpUseSqzExit)                    CheckSqzExit();
   if(TPMode == TP_TRAILING_ATR)        CheckTrailingATRExit();   // NUOVO
   MonitorActive();
}
```

**NOTA**: `CheckTrailingATRExit` va chiamato ogni tick (non solo su nuova barra) perché il trailing stop deve reagire in tempo reale. Attualmente `MonitorCycles` è chiamato solo dopo `IsNewBar()` gate. Per il trailing ATR serve una chiamata separata pre-gate in OnTick. Aggiungere in `Rattapignola.mq5`, PRIMA del gate `if(!IsNewBar()) return;`:

```mql5
// ── TRAILING ATR: monitoraggio continuo (ogni tick, non solo nuova barra) ──
if(g_systemState == STATE_ACTIVE && g_engineReady && TPMode == TP_TRAILING_ATR)
   CheckTrailingATRExit();
```

---

## ADD-02: TP_PIVOT_EXIT — EXIT SU PIVOT HIGH/LOW CONFERMATO (NUOVO TP MODE)

### Descrizione
Rileva un pivot high (per BUY) o pivot low (per SELL) confermato e chiude la posizione. Un pivot high di ordine N è una barra il cui High è maggiore degli High delle N barre a sinistra e delle N barre a destra. Richiede N barre di conferma (ritardo inevitabile).

### File: `rattEnums.mqh`

Aggiungere all'enum `ENUM_TP_MODE`:
```mql5
TP_PIVOT_EXIT     = 5,  // Pivot Exit — exit su pivot high/low confermato
```

### File: `rattInputParameters.mqh`

Aggiungere nella sezione TP:
```mql5
input group "    🔄 PIVOT EXIT"
input int            PivotLeftBars          = 3;             // 📏 Barre sinistra per conferma pivot
input int            PivotRightBars         = 2;             // 📏 Barre destra per conferma pivot (ritardo)
```

### File: `rattCycleManager.mqh` — Nuova funzione `CheckPivotExit`

```mql5
//+------------------------------------------------------------------+
//| CheckPivotExit — Exit su pivot high/low confermato               |
//|                                                                  |
//| Pivot High (per BUY exit): High[N] > High[N-1..N-L] e           |
//|                            High[N] > High[N+1..N+R]             |
//| dove N = PivotRightBars (la barra "centro" confermata)           |
//|      L = PivotLeftBars, R = PivotRightBars                      |
//|                                                                  |
//| Il pivot è confermato R barre DOPO il top reale.                 |
//| Usiamo bar[R] come centro del pivot (confermato da bar[1..R-1]). |
//+------------------------------------------------------------------+
void CheckPivotExit()
{
   int center = PivotRightBars;  // La barra "centro" del pivot
   int totalNeeded = PivotLeftBars + PivotRightBars + 1;

   double highBuf[], lowBuf[];
   ArraySetAsSeries(highBuf, true);
   ArraySetAsSeries(lowBuf, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, totalNeeded + 5, highBuf) < totalNeeded) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, totalNeeded + 5, lowBuf) < totalNeeded) return;

   // Controlla Pivot High (per exit BUY)
   bool isPivotHigh = true;
   double centerHigh = highBuf[center];
   for(int j = 1; j <= PivotLeftBars; j++)
   {
      if(highBuf[center + j] >= centerHigh) { isPivotHigh = false; break; }
   }
   if(isPivotHigh)
   {
      for(int j = 1; j <= PivotRightBars; j++)
      {
         if(highBuf[center - j] >= centerHigh) { isPivotHigh = false; break; }
      }
   }

   // Controlla Pivot Low (per exit SELL)
   bool isPivotLow = true;
   double centerLow = lowBuf[center];
   for(int j = 1; j <= PivotLeftBars; j++)
   {
      if(lowBuf[center + j] <= centerLow) { isPivotLow = false; break; }
   }
   if(isPivotLow)
   {
      for(int j = 1; j <= PivotRightBars; j++)
      {
         if(lowBuf[center - j] <= centerLow) { isPivotLow = false; break; }
      }
   }

   // Chiudi cicli se pivot confermato
   for(int i = 0; i < ArraySize(g_cycles); i++)
   {
      if(g_cycles[i].state != CYCLE_ACTIVE) continue;

      bool doExit = false;
      if(g_cycles[i].direction == +1 && isPivotHigh) doExit = true;  // BUY → esce su Pivot High
      if(g_cycles[i].direction == -1 && isPivotLow)  doExit = true;  // SELL → esce su Pivot Low

      if(doExit)
      {
         string dirStr = g_cycles[i].direction > 0 ? "BUY" : "SELL";
         string pivotStr = g_cycles[i].direction > 0 ? "PIVOT HIGH" : "PIVOT LOW";
         double pivotPrice = g_cycles[i].direction > 0 ? centerHigh : centerLow;

         AdLogI(LOG_CAT_CYCLE, StringFormat("PIVOT EXIT: %s confermato — Chiudo %s #%d | PivotPrice=%s",
                pivotStr, dirStr, g_cycles[i].cycleID, FormatPrice(pivotPrice)));

         if(EnableHedge && HsEnabled) HsCleanup(i, "Pivot_Exit");

         if(ClosePosition(g_cycles[i].ticket))
         {
            double soupPL = GetClosedPositionProfit(g_cycles[i].ticket);
            g_cycles[i].profit = soupPL + g_cycles[i].hsPL;
            g_cycles[i].state  = CYCLE_CLOSED;
            g_sessionRealizedProfit += soupPL;
            g_dailyRealizedProfit   += soupPL;
            if(g_cycles[i].profit > 0) { g_sessionWins++; g_dailyWins++; }
            else                       { g_sessionLosses++; g_dailyLosses++; }
            AddFeedItem("Pivot exit " + DoubleToString(soupPL, 2), RATT_AMBER);
            RemoveTPLine(g_cycles[i].cycleID);
         }
      }
   }
}
```

### Aggiornare `MonitorCycles`:
```mql5
if(TPMode == TP_PIVOT_EXIT)           CheckPivotExit();     // NUOVO
```

---

## ADD-03: USCITA PARZIALE SQZ (50% LOTTO)

### Descrizione
Quando SQZ half-peak scatta, chiude il 50% del lotto e lascia il resto fino al segnale opposto (S2S flip). Questo cattura profitto vicino al top mantenendo esposizione residua per il trend residuo.

### File: `rattInputParameters.mqh`

Aggiungere nella sezione E4 (Squeeze Momentum Exit):
```mql5
input bool   InpSqzPartialClose  = false;    // 🔀 Chiusura parziale SQZ (50% lotto, rest fino a S2S)
input double InpSqzPartialPct    = 0.50;     // 📏 % lotto da chiudere su SQZ exit (0.50 = 50%)
```

### File: `rattCycleManager.mqh` — Modificare `CheckSqzExit`

Aggiungere campi al ciclo:
```mql5
bool     sqzPartialDone;       // true se la chiusura parziale SQZ è già stata eseguita
```

Modificare `CheckSqzExit()` — sostituire il blocco `if(doExit)`:

```mql5
if(doExit)
{
   // Se chiusura parziale abilitata e non ancora eseguita
   if(InpSqzPartialClose && !g_cycles[i].sqzPartialDone)
   {
      double partialLot = NormalizeLotSize(g_cycles[i].lotSize * InpSqzPartialPct);
      if(partialLot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         AdLogI(LOG_CAT_CYCLE, StringFormat("SQZ PARTIAL: Chiudo %.0f%% (%s lot) di %s #%d",
                InpSqzPartialPct * 100, DoubleToString(partialLot, 2),
                g_cycles[i].direction > 0 ? "BUY" : "SELL",
                g_cycles[i].cycleID));

         if(ClosePositionPartial(g_cycles[i].ticket, partialLot))
         {
            g_cycles[i].lotSize -= partialLot;
            g_cycles[i].sqzPartialDone = true;
            AddFeedItem("SQZ partial close " + DoubleToString(partialLot, 2) + " lot", RATT_AMBER);
         }
      }
      else
      {
         // Lotto troppo piccolo per parziale — chiudi tutto
         goto full_sqz_close;
      }
   }
   else
   {
      full_sqz_close:
      // Chiusura completa (comportamento originale)
      AdLogI(LOG_CAT_CYCLE, StringFormat("SQZ EXIT: Chiudo %s #%d",
             g_cycles[i].direction > 0 ? "BUY" : "SELL",
             g_cycles[i].cycleID));

      if(EnableHedge && HsEnabled) HsCleanup(i, "SQZ_Exit");

      if(ClosePosition(g_cycles[i].ticket))
      {
         double soupPL = GetClosedPositionProfit(g_cycles[i].ticket);
         g_cycles[i].profit = soupPL + g_cycles[i].hsPL;
         g_cycles[i].state  = CYCLE_CLOSED;
         g_sessionRealizedProfit += soupPL;
         g_dailyRealizedProfit   += soupPL;
         if(g_cycles[i].profit > 0) { g_sessionWins++; g_dailyWins++; }
         else                       { g_sessionLosses++; g_dailyLosses++; }
         AddFeedItem("SQZ exit " + DoubleToString(soupPL, 2), RATT_AMBER);
         RemoveTPLine(g_cycles[i].cycleID);
      }
   }
}
```

### File: `rattOrderManager.mqh` — Aggiungere `ClosePositionPartial`

```mql5
//+------------------------------------------------------------------+
//| ClosePositionPartial — Chiude parte di una posizione             |
//+------------------------------------------------------------------+
bool ClosePositionPartial(ulong ticket, double partialLot)
{
   if(!PositionSelectByTicket(ticket))
   {
      AdLogW(LOG_CAT_ORDER, StringFormat("ClosePartial: Position %d not found", ticket));
      return false;
   }

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   string symbol = PositionGetString(POSITION_SYMBOL);
   partialLot = NormalizeLotSize(partialLot);

   g_trade.SetExpertMagicNumber(MagicNumber);
   bool result = false;

   if(posType == POSITION_TYPE_BUY)
      result = g_trade.Sell(partialLot, symbol, 0, 0, 0, StringFormat("RATT_PARTIAL_%d", ticket));
   else
      result = g_trade.Buy(partialLot, symbol, 0, 0, 0, StringFormat("RATT_PARTIAL_%d", ticket));

   if(!result)
      AdLogW(LOG_CAT_ORDER, StringFormat("ClosePartial FAILED: ticket=%d lot=%.2f err=%d",
             ticket, partialLot, GetLastError()));
   else
      AdLogI(LOG_CAT_ORDER, StringFormat("ClosePartial OK: ticket=%d lot=%.2f", ticket, partialLot));

   // Ripristina magic number originale
   g_trade.SetExpertMagicNumber(MagicNumber);
   return result;
}
```

---

## ADD-04: SQZ HALFPEAKRATIO NEI PRESET TF

### File: `rattUTBotEngine.mqh` — Nei preset TF

Aggiungere un campo `halfPeakRatio` alla struct `UTBPreset` e impostarlo per ogni TF:

```
TF    HalfPeakRatio   Rationale
M1    0.70            Momentum oscillante veloce — esci presto
M5    0.65            Buon compromesso
M15   0.60            Default bilanciato
M30   0.55            Trend più stabili
H1    0.50            Default attuale — lascia correre
H4    0.45            Trend forti — massima permanenza
D1    0.40            Trend molto lunghi
```

Aggiungere alla struct:
```mql5
double halfPeakRatio;
```

E nel codice di applicazione preset:
```mql5
if(InpSqzHalfPeakRatio == 0.50)  // Solo se l'utente non ha modificato manualmente
   g_eff_halfPeakRatio = preset.halfPeakRatio;
```

**NOTA**: questo richiede che il parametro `InpSqzHalfPeakRatio` venga passato all'indicatore SqueezeMomentum. Attualmente viene passato in `iCustom()` durante `EngineInit()`. Se il preset cambia il ratio, bisogna ricreare l'handle o trovare un modo per passare il valore aggiornato.

---

## ADD-05: INDICATORE VISIVO "FLAT" NEL DASHBOARD

### Descrizione
Quando SQZ (o Trail ATR, o Pivot) chiude prima del segnale opposto, il sistema è "flat" (nessuna posizione aperta) in attesa del prossimo segnale. Il dashboard deve mostrare questo stato.

### File: `rattDashboard.mqh`

Nella funzione `UpdateDashboard()`, aggiungere la logica:

```mql5
// Stato operativo: FLAT detection
int activeCycles = CountActiveCycles();
string opStatus = "";
if(g_systemState == STATE_ACTIVE && activeCycles == 0)
{
   opStatus = "FLAT — Waiting for signal";
   // Colore ambra per indicare "non in errore, ma senza posizioni"
}
```

Mostrare `opStatus` in una delle righe del dashboard (es. nella riga STATUS sotto la riga principale).

---

## RIEPILOGO ORDINE DI IMPLEMENTAZIONE

Per Claude Code, suggerisco di implementare in questo ordine per minimizzare conflitti:

1. **FIX-02** (S2S fallback) — 1 riga da modificare, zero rischio di regressione
2. **FIX-03** (Preset JMA M30/H1/H4) — aggiunte nei case dello switch
3. **FIX-04** (Preset D1/W1/MN) — enum + case + preset values
4. **FIX-01** (SL emergenza) — input + calcolo + wiring in OrderPlace
5. **ADD-01** (TP_TRAILING_ATR) — nuovo TP mode completo
6. **ADD-02** (TP_PIVOT_EXIT) — nuovo TP mode completo
7. **ADD-03** (Uscita parziale SQZ) — modifica CheckSqzExit + ClosePositionPartial
8. **ADD-05** (Dashboard FLAT) — visuale, nessun impatto sulla logica
9. **FIX-05** (Scan storico sorgente adattiva) — il più complesso, fare per ultimo
10. **ADD-04** (SQZ ratio nei preset) — richiede gestione handle, fare per ultimo

---

## NOTE PER CLAUDE CODE

### Struttura directory
I file `.mqh` sono organizzati in sottocartelle:
- `Config/` → rattEnums.mqh, rattInputParameters.mqh, rattEngineInterface.mqh, rattInstrumentConfig.mqh, rattVisualTheme.mqh
- `Core/` → rattGlobalVariables.mqh, rattBrokerValidation.mqh, rattSessionManager.mqh
- `Engine/` → rattUTBotEngine.mqh
- `Orders/` → rattATRCalculator.mqh, rattRiskManager.mqh, rattOrderManager.mqh, rattCycleManager.mqh, rattHedgeManager.mqh
- `Persistence/` → rattStatePersistence.mqh, rattRecoveryManager.mqh
- `Filters/` → rattHTFFilter.mqh
- `Virtual/` → rattVirtualTrader.mqh
- `UI/` → rattDashboard.mqh, rattControlButtons.mqh, rattChannelOverlay.mqh, rattSignalMarkers.mqh
- `Utilities/` → rattHelpers.mqh

### Convenzioni codice
- Logging: `AdLogI(LOG_CAT_*, "msg")` per info, `AdLogD` per debug, `AdLogW` per warning, `AdLogE` per errore
- Prezzi: `FormatPrice(price)` per formattazione, `NormalizeDouble(price, (int)g_symbolDigits)` per normalizzazione
- Pip conversion: `PipsToPrice()`, `PointsToPips()`
- Feed dashboard: `AddFeedItem("msg", color)`
- Lotti: `NormalizeLotSize(lot)`

### Variabili globali rilevanti
- `g_utb_atrHandle` — handle iATR dell'engine
- `g_utb_keyValue` — KeyValue effettivo (dopo preset)
- `g_utb_atrPeriod` — ATR period effettivo
- `g_sqzHandle` — handle SqueezeMomentum
- `g_cycles[]` — array cicli
- `g_symbolDigits`, `g_symbolPoint` — specifiche simbolo
- `g_trade` — oggetto CTrade per ordini
- `MagicNumber` — magic number EA

### Test post-implementazione
1. Compilare senza errori/warning
2. Backtest M15 EURUSD con ogni TPMode singolarmente
3. Verificare che S2S flip funzioni come fallback universale
4. Verificare che SL emergenza NON interferisca con S2S (il SL deve essere abbastanza largo da non scattare prima del flip)
5. Verificare che la chiusura parziale SQZ non lasci lotti "orfani" (il S2S flip deve chiudere anche il residuo)
6. Verificare che i nuovi preset D1/W1 non facciano scattare segnali troppo rari (almeno 1-2 segnali a settimana su D1)
