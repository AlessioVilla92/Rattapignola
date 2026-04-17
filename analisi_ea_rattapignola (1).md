# ANALISI EA — Rattapignola (rattUTBotEngine.mqh + moduli correlati)

**Data:** 17 Aprile 2026
**File analizzati:** rattUTBotEngine.mqh (912 righe), rattOrderManager.mqh, Rattapignola.mq5
**Scope:** Bug engine confermati + modifiche raccomandate per l'EA

---

## SEZIONE A — BUG CONFERMATI NELL'ENGINE (già documentati)

Questi 3 bug sono già stati identificati nel file `fix_engine_indicator_divergence.md`
e confermati in questa conversazione. Li riporto per completezza.

### BUG CRITICO 1 — ATR SMA vs Wilder RMA
**File:** rattUTBotEngine.mqh, riga 580
**Stato:** CONFERMATO, NON ANCORA FIXATO
```mql5
g_utb_atrHandle = iATR(_Symbol, PERIOD_CURRENT, g_utb_atrPeriod);
```
`iATR()` di MetaTrader usa SMA del True Range.
L'indicatore standalone usa Wilder RMA manuale: `(prev*(period-1) + TR) / period`.
Questi producono valori di `nLoss` DIVERSI su ogni barra → trail divergenti →
segnali diversi tra indicatore e EA.

**Fix:** Sostituire `iATR()` con calcolo Wilder RMA manuale.
Il file `fix_engine_indicator_divergence.md` contiene il codice completo
(`UTBCalcATRWilder`, `UTBWarmupATRWilder`).

### BUG CRITICO 2 — Reset trail/src dopo warmup JMA
**File:** rattUTBotEngine.mqh, righe 617-618
**Stato:** CONFERMATO, NON ANCORA FIXATO
```mql5
g_utb_lastTrail   = 0;
g_utb_lastSrc     = 0;
```
Dopo il warmup JMA (200 barre), il trail e la sorgente vengono azzerati.
Questo forza la prima iterazione di EngineCalculate a entrare nel ramo
`if(trail_prev == 0)` (riga 768) che assegna `trail = src - nLoss`,
forzando una partenza bullish indipendentemente dal trend reale.

**Fix:** `UTBWarmupEngine()` deve calcolare il trail completo sulle barre
di warmup e conservare l'ultimo stato valido. Vedi fix_engine_indicator_divergence.md.

### BUG CRITICO 3 — Warmup JMA non calcola storia trail
**File:** rattUTBotEngine.mqh, funzione UTBWarmupJMA()
**Stato:** CONFERMATO, NON ANCORA FIXATO
Il warmup alimenta lo stato JMA (e0, det0, det1, bands) ma NON calcola
la sequenza trail corrispondente. Non esiste uno stato trail valido
da cui partire dopo il warmup.

**Fix:** Nuova funzione `UTBWarmupEngine()` che:
1. Copia 200 barre storiche
2. Calcola ATR Wilder su tutte
3. Calcola sorgente (JMA/KAMA/HMA) su tutte
4. Calcola trail 4-rami su tutte
5. Salva `g_utb_lastTrail` e `g_utb_lastSrc` dall'ultima barra
Vedi fix_engine_indicator_divergence.md per il codice completo.

---

## SEZIONE B — PROBLEMI AGGIUNTIVI NELL'ENGINE

### PROBLEMA 4 — Condizione crossover leggermente diversa dall'indicatore
**File:** rattUTBotEngine.mqh, righe 798-799
**Gravità:** BASSA (divergenza rara, solo alla prima barra dopo init)
```mql5
// Engine:
bool isBuy  = (src_prev < trail_prev || src_prev == 0) && (src > trail) && trail_prev != 0;
// Indicatore:
bool isBuy  = (src1 < t1) && (src > trail) && biasLong;
```
L'engine ha un fallback `src_prev == 0` per gestire la prima barra dopo
inizializzazione. L'indicatore non ha questo fallback perché seed il trail
a `g_src[trail_start - 1]` prima del loop.

**Impatto:** Potenziale segnale fantasma alla prima barra post-init.
Mitigato dal guard `trail_prev != 0`.

**Fix:** Dopo l'implementazione di UTBWarmupEngine (Bug 3), `src_prev` non sarà
mai 0 → il fallback `src_prev == 0` diventa dead code. Rimuoverlo per chiarezza.

### PROBLEMA 5 — ER nell'engine
**File:** rattUTBotEngine.mqh, funzione UTBCalcER()
**Gravità:** MEDIA
Non ho visto la funzione UTBCalcER nel codice letto, ma basandomi sulla
struttura dell'engine (che replica l'indicatore), probabilmente usa lo
stesso proxy single-bar per sorgenti non-KAMA.

**Fix:** Applicare lo stesso ER finestrato raccomandato per l'indicatore
(Modifica 3 nel documento indicatore).

---

## SEZIONE C — MODIFICHE RACCOMANDATE PER L'EA

### MODIFICA EA-1 — Fix dei 3 bug critici engine (PRIORITÀ MASSIMA)

Questa è la modifica più urgente e deve essere implementata PRIMA di qualsiasi
altra modifica all'EA. Il file `fix_engine_indicator_divergence.md` contiene
tutte le istruzioni. In sintesi:

1. Sostituire `iATR()` con ATR Wilder manuale
2. Creare `UTBWarmupEngine()` che calcola trail storico completo
3. Rimuovere il reset trail/src dopo warmup
4. Verificare: segnale per segnale, l'engine deve matchare l'indicatore

---

### MODIFICA EA-2 — Dual Sensitivity nell'engine

**Obiettivo:** Replicare la Modifica 1 dell'indicatore nell'engine
**Impatto:** ALTO
**Rischio:** BASSO

L'engine deve leggere i parametri `InpDualSens`, `InpKeyValueSell`, `InpATRPeriodSell`
e applicare la stessa logica dell'indicatore alla condizione di emissione SELL
(riga 799 dell'engine). La modifica è concettualmente identica a quella
dell'indicatore, con la differenza che l'engine lavora barra-per-barra
(non loop su array).

---

### MODIFICA EA-3 — ADX gate nell'engine

**Obiettivo:** Replicare la Modifica 2 dell'indicatore nell'engine
**Impatto:** ALTO
**Rischio:** BASSO

Aggiungere `g_utb_adxHandle = iADX(...)` in EngineInit.
In EngineCalculate, leggere ADX da bar[1] e aggiungere `&& adxPass` alle
condizioni isBuy/isSell (righe 798-799).

---

### MODIFICA EA-4 — Trailing TP a stadi ("walking bass")

**Obiettivo:** Proteggere i profitti indipendentemente dai segnali
**Impatto:** ALTO
**Rischio:** MEDIO (richiede tuning)
**Dove:** Nuovo modulo `rattTrailingTP.mqh` oppure estensione di `rattOrderManager.mqh`

Questa modifica è ESCLUSIVA dell'EA — l'indicatore non ha posizioni da gestire.

**Nuovi input parameters (in rattInputParameters.mqh):**
```mql5
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🔒 TRAILING TAKE PROFIT (Walking Bass)                  ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input bool    InpUseTrailingTP    = false;    // Abilita trailing TP a stadi
input double  InpBE_ATRMult       = 1.0;      // Profitto per breakeven (in ATR multipli)
input double  InpTrail_ATRMult    = 1.5;      // Profitto per attivare trailing (in ATR multipli)
input int     InpChandPeriod      = 22;       // Chandelier period (lookback barre)
input double  InpChandMult        = 3.0;      // Chandelier multiplier (ATR multipli)
```

**Logica a 3 stadi (da implementare in OnTick dell'EA):**

```
STADIO 0 — POSIZIONE APPENA APERTA
   SL = entry ∓ 1.5 × ATR (hard stop iniziale)
   TP = 0 (nessun TP broker, gestito internamente)

STADIO 1 — BREAKEVEN (profitto >= InpBE_ATRMult × ATR)
   Sposta SL a entry ± spread (breakeven)
   Flag: posizione è "risk-free"

STADIO 2 — CHANDELIER TRAIL (profitto >= InpTrail_ATRMult × ATR)
   Per LONG: SL = HighestHigh(InpChandPeriod) - InpChandMult × ATR
   Per SHORT: SL = LowestLow(InpChandPeriod) + InpChandMult × ATR
   Il Chandelier si muove solo a favore (SL non indietreggia mai)
```

**Differenza chiave rispetto al trail UTBot:**
Il Chandelier è ancorato al prezzo estremo (highest high / lowest low),
NON al close corrente. Durante un pullback:
- Trail UTBot: si stringe verso il prezzo → flippa
- Chandelier: resta fermo → il pullback viene assorbito

**Interazione con segnali UTBot opposti:**
```
SE arriva segnale SELL e siamo LONG:
   SE trailing TP è attivo (stadio 2) E SL Chandelier NON è stato colpito:
      → NON chiudere la posizione LONG
      → Aprire SELL come posizione separata (hedging) o ignorare
      → La posizione LONG vive finché il Chandelier SL non viene colpito
   SE trailing TP NON è attivo (stadio 0 o 1):
      → Chiudere LONG normalmente e aprire SELL (comportamento attuale)
```

**ATTENZIONE — Hedging vs Netting:**
Su account NETTING (default MT5), non è possibile avere BUY e SELL contemporanei
sullo stesso simbolo. In questo caso, se arriva SELL con trailing TP attivo:
- Opzione A: Ignorare il SELL, lasciare che il Chandelier chiuda il LONG
- Opzione B: Chiudere il LONG solo se il profitto attuale è < profitto al Chandelier
- Opzione C: Ridurre il lot del LONG (partial close)

Su account HEDGING: è possibile aprire SELL separato mantenendo LONG aperto.

**Raccomando Opzione A per la prima implementazione** (semplicità massima).

**Implementazione pratica (pseudo-codice):**
```mql5
void ManageTrailingTP()
{
   if(!InpUseTrailingTP) return;
   if(!PositionSelect(_Symbol)) return;

   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool isLong  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   // ATR corrente (da rattATRCalculator)
   double atr = GetATRPrice();  // ATR in prezzo, non in pip
   if(atr <= 0) return;

   double profitPrice = isLong ? (bid - entry) : (entry - ask);

   // STADIO 1: Breakeven
   if(profitPrice >= InpBE_ATRMult * atr)
   {
      double newSL = isLong ? entry + _Point * 10 : entry - _Point * 10;
      if(isLong && sl < newSL)
         ModifySL(newSL);
      else if(!isLong && (sl > newSL || sl == 0))
         ModifySL(newSL);
   }

   // STADIO 2: Chandelier trail
   if(profitPrice >= InpTrail_ATRMult * atr)
   {
      double hh = iHigh(_Symbol, PERIOD_CURRENT,
                        iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpChandPeriod, 1));
      double ll = iLow(_Symbol, PERIOD_CURRENT,
                       iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpChandPeriod, 1));

      double chandSL = isLong ? (hh - InpChandMult * atr)
                               : (ll + InpChandMult * atr);

      // SL non indietreggia mai
      if(isLong && chandSL > sl)
         ModifySL(chandSL);
      else if(!isLong && (chandSL < sl || sl == 0))
         ModifySL(chandSL);
   }
}
```

**Dove chiamare ManageTrailingTP():**
In `OnTick()` di Rattapignola.mq5, dopo il check `OnNewBar` e dopo
`EngineCalculate`, ma PRIMA della logica di apertura ordini.

---

### MODIFICA EA-5 — Entry LTF (Point of No Return)

**Obiettivo:** Migliorare il prezzo di entry di qualche pip
**Impatto:** MEDIO
**Rischio:** MEDIO
**Stato:** Già documentato nel file di progetto. Da implementare DOPO le
Modifiche EA-1/2/3/4 sono stabili.

Non ripeto qui le specifiche — il documento PNR esiste già.

---

## SEZIONE D — COSA NON MODIFICARE NELL'EA

### I 4 rami del ratchet
Il calcolo del trail (righe 773-791 dell'engine) non va toccato.
Ogni filtro va applicato SOPRA il trail, non al suo interno.

### La logica anti-repaint
L'engine usa bar[1] (barra chiusa). L'indicatore usa `i < rates_total - 1`.
Entrambi sono corretti. Non introdurre logica su bar[0] per i segnali.

### Il modulo rattCycleManager
Non ha interazione diretta con le modifiche proposte. Non toccarlo.

### Il modulo rattHedgeManager
Se il trailing TP (Modifica EA-4) viene implementato con hedging,
il HedgeManager potrebbe entrare in conflitto. Verificare che le posizioni
aperte dal trailing TP siano escluse dalla logica hedge.

---

## SEZIONE E — ORDINE DI IMPLEMENTAZIONE EA

**Fase 1 (URGENTE):** Modifica EA-1 — Fix 3 bug critici engine.
Senza questo fix, l'engine produce segnali diversi dall'indicatore.
Qualsiasi altra modifica è inutile se la base è divergente.

**Fase 2 (dopo test regressione engine):** Modifiche EA-2 + EA-3
(Dual Sensitivity + ADX gate nell'engine).
Devono essere sincronizzate con le Modifiche 1+2 dell'indicatore.

**Fase 3 (indipendente, può essere parallela):** Modifica EA-4
(Trailing TP / walking bass).
Questa modifica è nell'EA, non nell'engine/indicatore.
Può essere testata indipendentemente.

**Fase 4 (opzionale):** Modifica EA-5 (PNR/LTF entry).

---

## SEZIONE F — TEST DI VERIFICA EA

### Test EA-1: Match engine-indicatore post fix
Dopo il fix dei 3 bug, eseguire l'EA in visual tester e confrontare:
- Trail dell'engine vs trail dell'indicatore (devono coincidere)
- Segnali BUY/SELL dell'engine vs frecce dell'indicatore (devono coincidere)
- Verificare su almeno 3 mesi di dati USDJPY M5

### Test EA-2: Trailing TP - protezione profitti
1. Aprire posizione manuale LONG
2. Prezzo sale di 1.5 × ATR → verificare che SL si sposta a breakeven
3. Prezzo sale di 2 × ATR → verificare che Chandelier trail si attiva
4. Prezzo fa pullback di 1 × ATR → verificare che SL NON si muove
5. Prezzo continua a salire → verificare che SL sale con il Chandelier

### Test EA-3: Interazione segnale opposto + trailing TP
1. Posizione LONG con trailing TP attivo (stadio 2)
2. UTBot genera segnale SELL
3. Verificare che la posizione LONG NON viene chiusa (Opzione A)
4. Il prezzo scende e colpisce il Chandelier SL → posizione chiusa
5. Il SELL successivo apre normalmente

### Test EA-4: Dual Sensitivity
Stessa zona degli screenshot. Il SELL durante pullback in uptrend
non deve essere emesso con Key_SELL=1.5 (dove con Key=1.0 veniva emesso).
