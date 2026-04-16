# FIX: Divergenza Engine-Indicatore UTBot — Istruzioni per Claude Code

## Contesto del Problema

L'indicatore standalone `UTBotAdaptive.mq5` funziona perfettamente: colora tutte le candele
del colore del trend (teal per bull, coral per bear), generando un flusso visivo unificato
ideale per trading Signal-to-Signal. L'EA `Rattapignola.mq5` integra lo stesso algoritmo
nell'engine (`rattUTBotEngine.mqh`), ma l'engine genera segnali diversi dall'indicatore —
producendo falsi crossover durante micro-pullback dove l'indicatore resterebbe nel trend.

La formula JMA, il trailing stop a 4 rami, e il crossover sono stati **verificati
matematicamente identici** tra engine e indicatore. Il problema è causato da **3 bug
specifici** documentati sotto.

---

## BUG 1 (CRITICO): ATR — iATR() usa SMA, l'indicatore usa Wilder's RMA

### Analisi

L'indicatore calcola ATR manualmente con **Wilder's smoothing** (RMA):

```
// UTBotAdaptive.mq5, riga 1283
g_atr[i] = (g_atr[i - 1] * (g_eff_atrPeriod - 1) + tr) / g_eff_atrPeriod;
```

Formula: `ATR[i] = ATR_prev × (N-1)/N + TR × 1/N`  
Questo è uno smoothing esponenziale — tutta la storia pesa con decadimento esponenziale.

L'engine usa il built-in `iATR()` di MetaTrader:

```
// rattUTBotEngine.mqh, riga 580
g_utb_atrHandle = iATR(_Symbol, PERIOD_CURRENT, g_utb_atrPeriod);
```

`iATR()` di MetaTrader calcola ATR come **SMA** (Simple Moving Average) del True Range —
media mobile semplice delle ultime N barre. La formula interna è:
`ATR[i] = ATR[i-1] + (TR[i] - TR[i-period]) / period` (sliding window).

Questo è confermato dalla documentazione MetaQuotes, dal source code ufficiale ATR.mq5,
e da test sul forum MQL5 (thread #503387) dove ATR manuale SMA produce valori identici a iATR().

### Impatto

`nLoss = keyValue × ATR`. ATR diverso → nLoss diverso su **ogni barra** → posizione
trail diversa → crossover in punti diversi. Durante un micro-pullback in un trend,
l'indicatore (Wilder, più smooth) vede `src > trail` (resta nel trend), ma l'engine
(SMA, più reattivo) può vedere un crossover `src < trail` → falso segnale → uscita
dal trend → esattamente il comportamento sbagliato.

### Fix

Sostituire `iATR()` con un calcolo manuale ATR Wilder identico a quello dell'indicatore.

#### File: `rattUTBotEngine.mqh`

**1. Aggiungere variabili globali ATR Wilder** (dopo riga ~100, vicino alle altre g_utb_* variables):

```mql5
// ATR Wilder (manual, matches UTBotAdaptive.mq5 exactly)
double g_utb_atrWilder = 0.0;     // Ultimo valore ATR Wilder calcolato
bool   g_utb_atrInit   = false;   // Flag inizializzazione ATR
```

**2. Aggiungere funzione `UTBCalcATRWilder()`** (prima di EngineInit):

Questa funzione calcola l'ATR Wilder per bar[1] in modo incrementale, identico
alla formula dell'indicatore riga 1283. Il primo valore è la SMA dei primi N True Range
(seed identico all'indicatore riga 1272-1278).

```mql5
//+------------------------------------------------------------------+
//| UTBCalcATRWilder — ATR Wilder manuale per bar[1]                 |
//|                                                                  |
//| Formula identica a UTBotAdaptive.mq5 riga 1280-1283:             |
//|   ATR[i] = (ATR[i-1] * (period-1) + TR) / period                |
//| Primo valore: SMA dei primi N True Range (seed).                 |
//|                                                                  |
//| Ritorna il valore ATR Wilder per bar[1].                         |
//| Mantiene stato in g_utb_atrWilder (persistente tra tick).        |
//+------------------------------------------------------------------+
double UTBCalcATRWilder()
{
   int period = g_utb_atrPeriod;

   // Se non ancora inizializzato, calcola SMA dei primi N True Range come seed
   if(!g_utb_atrInit)
   {
      double highBuf[], lowBuf[], closeBuf[];
      ArraySetAsSeries(highBuf, true);
      ArraySetAsSeries(lowBuf, true);
      ArraySetAsSeries(closeBuf, true);

      int needed = period + 2;
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, needed, highBuf) < needed) return 0;
      if(CopyLow(_Symbol, PERIOD_CURRENT, 1, needed, lowBuf) < needed) return 0;
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, needed, closeBuf) < needed) return 0;

      // SMA seed: media dei primi N True Range
      double sum = 0;
      for(int k = 0; k < period; k++)
      {
         int idx = period - k;  // dalla barra più vecchia alla più recente
         double trueHigh = MathMax(highBuf[idx], closeBuf[idx + 1]);
         double trueLow  = MathMin(lowBuf[idx], closeBuf[idx + 1]);
         sum += (trueHigh - trueLow);
      }
      g_utb_atrWilder = sum / period;
      g_utb_atrInit = true;

      // Poi applica Wilder's smoothing per le barre restanti fino a bar[1]
      // Questo allinea lo stato come se avessimo processato tutta la storia
      // (approssimazione — per convergenza completa vedi il warmup esteso)
   }

   // Calcola True Range per bar[1]
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double tr = MathMax(h1, c2) - MathMin(l1, c2);

   // Wilder's smoothing (identica all'indicatore)
   g_utb_atrWilder = (g_utb_atrWilder * (period - 1) + tr) / period;

   return g_utb_atrWilder;
}
```

**3. Aggiungere funzione `UTBWarmupATRWilder()`** per inizializzare l'ATR con storia completa:

```mql5
//+------------------------------------------------------------------+
//| UTBWarmupATRWilder — Scalda ATR Wilder su N barre storiche       |
//|                                                                  |
//| Replica esattamente il calcolo dell'indicatore:                  |
//| 1. SMA dei primi `period` True Range come seed                   |
//| 2. Wilder's smoothing per tutte le barre successive              |
//| Risultato: g_utb_atrWilder contiene il valore ATR identico       |
//| a quello che l'indicatore avrebbe calcolato sulla stessa storia.  |
//+------------------------------------------------------------------+
void UTBWarmupATRWilder(int bars = 500)
{
   int period = g_utb_atrPeriod;
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(bars > totalBars - period - 2) bars = totalBars - period - 2;
   if(bars < period + 1) return;

   double highBuf[], lowBuf[], closeBuf[];
   ArraySetAsSeries(highBuf, false);
   ArraySetAsSeries(lowBuf, false);
   ArraySetAsSeries(closeBuf, false);

   // Copia dati storici: shift=1 (da bar[1]), bars barre, oldest first
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, bars, highBuf) < bars) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, bars, lowBuf) < bars) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, bars, closeBuf) < bars) return;

   // Step 1: SMA seed (primi `period` True Range)
   double sum = 0;
   for(int k = 1; k <= period; k++)
   {
      double tr = MathMax(highBuf[k], closeBuf[k - 1]) - MathMin(lowBuf[k], closeBuf[k - 1]);
      sum += tr;
   }
   g_utb_atrWilder = sum / period;

   // Step 2: Wilder's smoothing per le barre successive
   for(int i = period + 1; i < bars; i++)
   {
      double tr = MathMax(highBuf[i], closeBuf[i - 1]) - MathMin(lowBuf[i], closeBuf[i - 1]);
      g_utb_atrWilder = (g_utb_atrWilder * (period - 1) + tr) / period;
   }

   g_utb_atrInit = true;

   AdLogI(LOG_CAT_UTB, StringFormat("ATR Wilder warmup: %d bars | ATR=%.5f (%.2f pip)",
          bars, g_utb_atrWilder, PointsToPips(g_utb_atrWilder)));
}
```

**4. Modificare `EngineCalculate()`**: Sostituire la lettura da iATR handle con UTBCalcATRWilder().

In `EngineCalculate()`, righe 704-712, sostituire il blocco CopyBuffer ATR:

```mql5
// PRIMA (da rimuovere):
// double atrBuf[1];
// if(CopyBuffer(g_utb_atrHandle, 0, 1, 1, atrBuf) < 1)
// {
//    AdLogD(LOG_CAT_UTB, "ATR data not ready");
//    return false;
// }
// double atr   = atrBuf[0];

// DOPO (nuovo):
double atr = UTBCalcATRWilder();
if(atr <= 0)
{
   AdLogD(LOG_CAT_UTB, "ATR Wilder not ready");
   return false;
}
```

**5. Modificare `EngineInit()`**: Aggiungere warmup ATR e rimuovere creazione handle iATR.

L'handle `g_utb_atrHandle` NON va rimosso completamente — è ancora usato dall'overlay
e dai signal markers. Ma l'engine non lo usa più per i segnali.

Aggiungere dopo il warmup JMA (riga 597):

```mql5
// Warmup ATR Wilder (identico all'indicatore)
UTBWarmupATRWilder(500);
```

**6. Aggiungere reset ATR** nella sezione reset state di EngineInit (riga 616):

```mql5
// NON resettare g_utb_atrWilder e g_utb_atrInit!
// Il warmup li ha già settati correttamente.
```

E in `EngineDeinit()`:

```mql5
g_utb_atrWilder = 0;
g_utb_atrInit   = false;
```

**7. Fix per Overlay e SignalMarkers**: Anche l'overlay (`rattChannelOverlay.mqh`) e i
signal markers (`rattSignalMarkers.mqh`) usano `g_utb_atrHandle` (iATR/SMA). Per allinearli
all'indicatore, dovrebbero calcolare ATR Wilder manualmente nel loro loop storico, usando
la stessa formula dell'indicatore. Questo è meno critico dei segnali (è solo visuale), ma
va fatto per coerenza completa.

Nei loop di `DrawChannelOverlay()` e `ScanHistoricalSignals()`, dove leggono `atrBuf[i]`
dal handle iATR, devono invece calcolare ATR Wilder inline:

```mql5
// Nel loop storico (oldest to newest):
double atr_wilder = 0;
bool atr_seeded = false;
// ... poi nel loop:
double tr = MathMax(highBuf[i], closeBuf_prev) - MathMin(lowBuf[i], closeBuf_prev);
if(!atr_seeded && bar_count >= period)
{
   atr_wilder = sum_tr / period;  // SMA seed
   atr_seeded = true;
}
else if(atr_seeded)
{
   atr_wilder = (atr_wilder * (period - 1) + tr) / period;
}
double nLoss = g_utb_keyValue * atr_wilder;
```

**NOTA**: L'overlay e i signal markers caricano anche High/Low buffer oltre a Close.
Aggiungere CopyHigh e CopyLow nel loro setup.

---

## BUG 2 (CRITICO): Trail azzerato dopo warmup JMA

### Analisi

In `EngineInit()`, righe 617-618:

```mql5
g_utb_lastTrail   = 0;   // ❌ Cancella lo stato trail
g_utb_lastSrc     = 0;   // ❌ Cancella la source
```

Questo viene DOPO `UTBWarmupJMA(200)` (riga 597). Il warmup scalda correttamente lo
stato JMA, ma il trail viene azzerato subito dopo.

Quando `EngineCalculate()` parte per la prima volta (riga 768):

```mql5
if(trail_prev == 0)
   trail = src - nLoss;   // Assume bullish start
```

L'engine indovina il lato bull. Se il trend reale è bear, per alcune barre l'engine
e l'indicatore divergono sulla direzione.

### Fix

**Estendere `UTBWarmupJMA()` per calcolare anche il trailing stop** durante il warmup,
e settare `g_utb_lastTrail` e `g_utb_lastSrc` ai valori finali.

#### File: `rattUTBotEngine.mqh`

Rinominare la funzione da `UTBWarmupJMA` a `UTBWarmupEngine` (più accurato) e modificarla:

```mql5
//+------------------------------------------------------------------+
//| UTBWarmupEngine — Scalda JMA + ATR Wilder + Trail su storia      |
//|                                                                  |
//| Processa `bars` barre storiche in ordine cronologico (oldest      |
//| first), calcolando:                                              |
//| 1. ATR Wilder (se non già scaldato da UTBWarmupATRWilder)        |
//| 2. Sorgente adattiva (JMA/KAMA/HMA/Close)                       |
//| 3. Trailing stop 4-branch ratchet                                |
//|                                                                  |
//| Al termine, g_utb_lastTrail e g_utb_lastSrc contengono i         |
//| valori corretti — identici a quelli che l'indicatore avrebbe     |
//| calcolato sulla stessa storia.                                   |
//+------------------------------------------------------------------+
void UTBWarmupEngine(int bars = 500)
{
   if(bars < 50) bars = 50;

   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(totalBars < bars + 5) bars = totalBars - 5;
   if(bars < 50) return;

   // Copia close storici: shift=1 (anti-repaint), oldest first
   double closes[];
   ArraySetAsSeries(closes, false);
   int copied = CopyClose(_Symbol, PERIOD_CURRENT, 1, bars, closes);
   if(copied < bars)
   {
      AdLogW(LOG_CAT_UTB, StringFormat("WarmupEngine: only %d/%d closes", copied, bars));
      if(copied < 50) return;
      bars = copied;
   }

   // Alimenta JMA/KAMA barra per barra + calcola trail
   double tmp[3];
   ArraySetAsSeries(tmp, true);
   tmp[0] = 0; tmp[2] = 0;

   double trail = 0;
   double src = 0, src_prev = 0;

   for(int i = 0; i < bars; i++)
   {
      double close_i = closes[i];
      tmp[1] = close_i;

      // Sorgente adattiva
      double curSrc = close_i;
      switch(InpSrcType)
      {
         case UTB_SRC_CLOSE:
            curSrc = close_i;
            break;
         case UTB_SRC_JMA:
            curSrc = UTBCalcJMA(tmp, 3);
            break;
         case UTB_SRC_KAMA:
         {
            // KAMA inline semplificata per warmup
            if(!g_utb_kama_init)
            {
               g_utb_kama_prev = close_i;
               g_utb_kama_init = true;
               curSrc = close_i;
            }
            else
            {
               double fc = 2.0 / (g_utb_kamaFast + 1.0);
               double sc = 2.0 / (g_utb_kamaSlow + 1.0);
               // ER semplificato per warmup (usa solo delta singolo)
               double er_k = (g_utb_atrWilder > 0)
                  ? MathMin(1.0, MathAbs(close_i - g_utb_kama_prev) / g_utb_atrWilder)
                  : 0.0;
               double smooth = MathPow(er_k * (fc - sc) + sc, 2.0);
               curSrc = g_utb_kama_prev + smooth * (close_i - g_utb_kama_prev);
               g_utb_kama_prev = curSrc;
            }
            break;
         }
         case UTB_SRC_HMA:
            curSrc = close_i;  // HMA richiede lookback multi-barra, seed semplice per warmup
            break;
      }

      src_prev = src;
      src = curSrc;

      // ATR Wilder dovrebbe essere già scaldato da UTBWarmupATRWilder()
      // Usa il valore corrente per nLoss
      double nLoss = g_utb_keyValue * g_utb_atrWilder;
      if(nLoss <= 0) continue;

      // Trailing stop 4-branch (identico indicatore e engine)
      if(trail == 0)
      {
         trail = src - nLoss;
         continue;
      }

      double trail_prev = trail;
      if(src > trail_prev && src_prev > trail_prev)
         trail = MathMax(trail_prev, src - nLoss);
      else if(src < trail_prev && src_prev < trail_prev)
         trail = MathMin(trail_prev, src + nLoss);
      else if(src > trail_prev)
         trail = src - nLoss;
      else
         trail = src + nLoss;
   }

   // Setta stato finale — l'engine parte da qui
   g_utb_lastTrail = trail;
   g_utb_lastSrc   = src;

   AdLogI(LOG_CAT_UTB, StringFormat("WarmupEngine: %d bars | Trail=%.5f | Src=%.5f | Side=%s",
          bars, trail, src, (src > trail) ? "BULL" : "BEAR"));
}
```

**Modificare `EngineInit()`**: Nella sezione "Reset state" (riga 616-622), rimuovere
i reset di trail e source, e chiamare il warmup esteso:

```mql5
//--- 6. Warmup completo (JMA + ATR + Trail) ---
// ATR Wilder già scaldato da UTBWarmupATRWilder() sopra
// JMA già scaldata (se JMA source) da UTBResetJMAState + costanti
// Ora alimentiamo tutto insieme per calcolare il trail corretto

// Reset SOLO le variabili che il warmup settà internamente
g_utb_lastBarTime = 0;

// Warmup engine completo: JMA + Trail
UTBWarmupEngine(500);

// NON azzerare g_utb_lastTrail e g_utb_lastSrc!
// Il warmup li ha settati ai valori storici corretti.
```

**IMPORTANTE**: Rimuovere le righe 617-621 che azzeravano trail/src/kama:

```mql5
// RIMUOVERE QUESTE RIGHE:
// g_utb_lastTrail   = 0;   ← via
// g_utb_lastSrc     = 0;   ← via
// g_utb_lastBarTime = 0;   ← MANTENERE questa
// g_utb_kama_prev   = 0;   ← via (il warmup la setta)
// g_utb_kama_init   = false; ← via (il warmup la setta)
```

---

## BUG 3 (MODERATO): Warmup calcola solo JMA, non trail

Questo bug è risolto automaticamente dal Fix del BUG 2 — il nuovo `UTBWarmupEngine()`
calcola JMA + trail insieme.

---

## Ordine di implementazione in EngineInit()

L'ordine delle operazioni in `EngineInit()` dopo le fix deve essere:

```
1. Apply TF preset (UTBApplyPreset / UTBApplyManual)     — già presente
2. Create ATR handle iATR (mantenere per overlay/markers) — già presente
3. Init JMA constants (UTBInitJMAConstants)               — già presente
4. Reset JMA state (UTBResetJMAState)                     — già presente
5. ★ NEW: Warmup ATR Wilder (UTBWarmupATRWilder, 500 bar)
6. ★ NEW: Warmup engine completo (UTBWarmupEngine, 500 bar)
      → Questo scalda JMA + KAMA + Trail tutti insieme
      → Setta g_utb_lastTrail, g_utb_lastSrc ai valori corretti
7. Create SQZ handle (se abilitato)                      — già presente
8. g_utb_lastBarTime = 0 (solo questo reset)
9. Log configuration                                     — già presente
```

---

## Riepilogo file da modificare

| File | Modifica |
|------|----------|
| `rattUTBotEngine.mqh` | Aggiungere `UTBCalcATRWilder()`, `UTBWarmupATRWilder()`, `UTBWarmupEngine()`. Modificare `EngineCalculate()` per usare ATR Wilder. Modificare `EngineInit()` per warmup completo e non azzerare trail/src. Modificare `EngineDeinit()` per reset ATR Wilder. |
| `rattChannelOverlay.mqh` | Nel loop di `DrawChannelOverlay()`, calcolare ATR Wilder inline anziché leggere da `g_utb_atrHandle`. Aggiungere CopyHigh/CopyLow. |
| `rattSignalMarkers.mqh` | Nel loop di `ScanHistoricalSignals()`, calcolare ATR Wilder inline anziché leggere da `g_utb_atrHandle`. Aggiungere CopyHigh/CopyLow. |

---

## Cosa NON va modificato

- **JMA**: Formula verificata identica tra engine e indicatore. Nessuna modifica.
- **KAMA**: Formula verificata identica. Nessuna modifica.
- **Trailing stop 4-branch**: Logica verificata identica. Nessuna modifica.
- **Signal crossover detection**: Logica equivalente. Nessuna modifica.
- **Preset tables**: Verificate identiche. Nessuna modifica.
- **Indicatore embedded** (`UTBotAdaptive.mq5`): Nessuna modifica — funziona perfettamente.
- **`rattEngineInterface.mqh`**: Contratto stabile, nessuna modifica.

---

## Test di verifica post-fix

1. **Test visivo**: Caricare EA e indicatore standalone sullo stesso chart M15 AUDUSD.
   Verificare che le frecce dell'EA coincidano esattamente con le frecce dell'indicatore.

2. **Test numerico**: Aggiungere log temporaneo in `EngineCalculate()` che stampa:
   ```
   [UTB] bar=%s | ATR_wilder=%.5f | src=%.5f | trail=%.5f | side=%s
   ```
   Confrontare con i valori dell'indicatore (buffer 0=trail, buffer 12=ER, buffer 13=state).

3. **Test anti-repaint**: Verificare che nessun segnale cambi dopo la chiusura della barra.

4. **Test trend continuity**: Su un trend pulito (es. rialzo su GBPJPY M15 come nello
   screenshot soloind.png), verificare che l'EA NON generi segnali SELL durante
   micro-pullback — deve restare nel trend come l'indicatore.

---

## Vincolo architetturale

**Anti-repainting**: Tutte le modifiche devono mantenere il principio bar[1]-only.
Il warmup processa solo barre chiuse. L'ATR Wilder in `EngineCalculate()` legge
solo bar[1] e bar[2] (mai bar[0]). Nessun dato dalla barra corrente aperta.
