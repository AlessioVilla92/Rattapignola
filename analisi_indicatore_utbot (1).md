# ANALISI INDICATORE — UTBotAdaptive-Ok.mq5

**Data:** 17 Aprile 2026
**File analizzato:** UTBotAdaptive-Ok.mq5 (v2.01, 1525 righe)
**Scope:** Bug verificati + modifiche raccomandate per l'indicatore standalone

---

## SEZIONE A — BUG E PROBLEMI VERIFICATI NEL CODICE ATTUALE

### BUG 1 — iCustom HTF bias: mancano 2 parametri
**Riga:** 581-591
**Gravità:** BASSA (non crash, ma potenziale spreco risorse)
**Descrizione:**
L'indicatore ha 25 input parameters. La chiamata `iCustom()` per il bias HTF
(riga 581) passa solo 23 parametri. Mancano `InpShowDashboard` e `InpShowTrailLine`.

MQL5 assegna i valori di default (`true`, `true`) ai parametri non specificati.
L'istanza HTF child tenta di creare oggetti dashboard su un chart inesistente.
Non causa crash ma genera warning nel log e spreca risorse.

**Fix:**
```mql5
// Aggiungere alla fine della chiamata iCustom (dopo false, false per Alert):
                        false, false,             // Alert OFF, Push OFF
                        false,                    // InpShowDashboard OFF  ← AGGIUNGERE
                        false);                   // InpShowTrailLine OFF  ← AGGIUNGERE
```

---

### BUG 2 — ER proxy single-bar per sorgenti non-KAMA
**Riga:** 1426-1427
**Gravità:** MEDIA (colori frecce inaffidabili con JMA/HMA/Close)
**Descrizione:**
```mql5
else if(g_atr[i] > 0.0)
   er_val = MathMin(1.0, MathAbs(src - src1) / g_atr[i]);
```
Con JMA (sorgente di default), l'ER è `|JMA[i] - JMA[i-1]| / ATR`.
Questo è un proxy a SINGOLA BARRA — estremamente volatile.
Una barra forte in un range dà ER=0.60 ("affidabile"), un trend
costante composto da piccole barre dà ER=0.08 ("debole").

Il colore delle frecce (verde/chiaro/giallo/grigio) basato su questo ER
è INGANNEVOLE: segnala come "deboli" trend reali e come "forti" spike di rumore.

Con SRC_KAMA l'ER è calcolato correttamente su N barre (righe 1418-1424).

**Fix:** Vedi Modifica 3 sotto.

---

### PROBLEMA 3 — HMA ricalcolo completo ad ogni tick
**Riga:** 1321
**Gravità:** BASSA (performance, non correttezza)
**Descrizione:**
```mql5
case SRC_HMA:
   ApplyHMA(close, rates_total, InpHMAPeriod);
   break;
```
A differenza di KAMA e JMA che hanno path incrementale, `ApplyHMA()` ricalcola
l'intera HMA da zero su ogni chiamata OnCalculate. Su chart con 10000+ barre,
questo è lento. Non impatta i risultati, solo le performance.

**Fix:** Implementare un path incrementale per HMA (solo barre nuove), ma
NON è prioritario rispetto alle altre modifiche.

---

### PROBLEMA 4 — HMA non ha preset adattivo per timeframe
**Riga:** 368-461 (UTBotPresetsInit)
**Gravità:** BASSA (inconsistenza)
**Descrizione:**
I preset TF assegnano parametri effettivi per KAMA (N/Fast/Slow) e JMA (Period/Phase),
ma HMA usa sempre `InpHMAPeriod` (input utente) anche in modalità AUTO.
Non esiste `g_eff_hmaPeriod`. Se un utente usa SRC_HMA con AUTO, il periodo HMA
non si adatta al timeframe.

**Nota:** Poiché la sorgente raccomandata è JMA, questo è un problema marginale.

---

### PROBLEMA 5 — Warmup leggermente corto per JMA su M1
**Riga:** 543-546
**Gravità:** MINIMA (i primi 3 segnali su M1 potrebbero essere meno precisi)
**Descrizione:**
Su M1: `g_warmup = 5*2 + max(25, 42, 15) + 10 = 62`.
Ma la JMA usa `avgLen = 65` (riga 857) per la media della volatilità.
Alle barre 62-64, la media è calcolata su una finestra più corta del previsto.
L'impatto pratico è minimo (la JMA è smooth by design).

---

## SEZIONE B — CONFERMA: COSA FUNZIONA CORRETTAMENTE

### ATR Wilder (RMA) — ✅ CORRETTO
Righe 1287-1310. La formula `(prev * (period-1) + TR) / period` è Wilder RMA,
identica a `ta.atr()` di TradingView. Seed con SMA iniziale. Confermato.

### Trail 4 rami — ✅ CORRETTO
Righe 1402-1409. Fedele all'originale Pine di QuantNomad. I 4 rami sono:
1. Ratchet up (entrambi sopra)
2. Ratchet down (entrambi sotto)
3. Flip bull (crossover su)
4. Flip bear (crossover giù)
La logica è matematicamente equivalente all'originale.

### Anti-repainting — ✅ CORRETTO
Righe 1436 e 1473. Le frecce appaiono solo su `i < rates_total - 1` (barre chiuse).
La barra corrente (rates_total-1) non emette mai segnali. Corretto.

### B_State crossover — ✅ CORRETTO
Righe 1454-1459. Usa `src > t1` (trail precedente) per il crossover.
Ho verificato che le condizioni di isBuy (riga 1439) e B_State (riga 1454)
producono risultati equivalenti in tutti i casi (vedi analisi nella conversazione).

### KAMA formula — ✅ CORRETTO
Righe 791-809. ER = |P[n]-P[0]| / Σ|P[i]-P[i-1]|, SC = (ER*(FC-SC)+SC)²,
KAMA = prev + SC*(P-prev). Fedele a Kaufman.

### JMA formula — ✅ CORRETTO
Righe 831-921. IIR 3 stadi con Jurik Bands + volatilità dinamica.
Fonte: Igor PDF 2008 + mihakralj. Verificata strutturalmente.

---

## SEZIONE C — MODIFICHE RACCOMANDATE PER L'INDICATORE

### MODIFICA 1 — Dual Sensitivity (Key/ATR separati per BUY e SELL)

**Obiettivo:** Risolvere il Problema B (doppio flip su pullback fisiologico)
**Impatto:** ALTO
**Rischio:** BASSO
**Righe da modificare:** ~30

**Nuovi input parameters (dopo InpATRPeriod, riga 167):**
```mql5
input group "    ⚖️ SENSIBILITA' ASIMMETRICA (Dual Sensitivity)"
input bool    InpDualSens     = false;    // Abilita Key/ATR separati BUY vs SELL
input double  InpKeyValueSell = 1.5;      // Key Value SELL (solo se Dual=true)
input int     InpATRPeriodSell = 10;       // ATR Period SELL (solo se Dual=true)
```

**Nuove variabili effettive (dopo g_eff_jmaPhase, riga 289):**
```mql5
double g_eff_keyValueSell;
int    g_eff_atrPeriodSell;
```

**Logica:** Il trail viene calcolato normalmente (con i parametri base).
La modifica è SOLO nella condizione di emissione segnale:

```mql5
// PRIMA (riga 1397):
double nLoss = g_eff_keyValue * g_atr[i];

// DOPO:
double nLossBuy  = g_eff_keyValue * g_atr[i];
double nLossSell = InpDualSens ? g_eff_keyValueSell * g_atrSell[i] : nLossBuy;

// Il trail usa nLossBuy di default.
// Il segnale SELL richiede src < trail_SELL (calcolato con nLossSell).
```

**ATTENZIONE — COMPLESSITÀ NASCOSTA:**
Il trail a 4 rami usa un UNICO nLoss per calcolare sia il ratchet che il flip.
Se separiamo nLoss per BUY e SELL, dobbiamo decidere quale nLoss usare nei rami
di ratchet. Ci sono due approcci:

**Approccio A (semplice — raccomandato):** Il trail continua a usare nLossBuy per
tutti e 4 i rami. L'unica modifica è che il segnale SELL richiede una distanza
maggiore dal trail: `isSell = (src1 > t1) && (src < trail - extraBuffer)` dove
`extraBuffer = (nLossSell - nLossBuy)`. In pratica: il trail flippa normalmente,
ma l'indicatore NON emette la freccia SELL a meno che il prezzo non sia sceso
abbastanza da superare anche la soglia SELL più ampia.

**Approccio B (due trail paralleli):** Calcolare due trail separati (uno per BUY,
uno per SELL) e usare ciascuno per la propria direzione. Più complesso, più
parametri, più rischio di bug. NON raccomandato per la prima implementazione.

**Raccomando Approccio A.**

Implementazione Approccio A nel loop (riga 1393):
```mql5
for(int i = trail_start; i < rates_total; i++)
{
   double src   = g_src[i];
   double src1  = g_src[i - 1];
   double nLoss = g_eff_keyValue * g_atr[i];  // invariato, trail usa sempre questo
   double t1    = B_Trail[i - 1];

   // Trail 4 rami — INVARIATO
   double trail;
   if(src > t1 && src1 > t1)
      trail = MathMax(t1, src - nLoss);
   else if(src < t1 && src1 < t1)
      trail = MathMin(t1, src + nLoss);
   else if(src > t1)
      trail = src - nLoss;
   else
      trail = src + nLoss;

   B_Trail[i]    = trail;
   B_TrailClr[i] = (src > trail) ? 0.0 : 1.0;

   // ... ER calculation invariato ...

   if(i < rates_total - 1)
   {
      //--- Segnali con Dual Sensitivity ---
      bool isBuy  = (src1 < t1) && (src > trail) && biasLong;

      // SELL: se DualSens attivo, richiede distanza maggiore
      bool isSell;
      if(InpDualSens)
      {
         double nLossSell = g_eff_keyValueSell * g_atr[i];
         double trailSell = src + nLossSell;  // dove sarebbe il trail SELL
         // Il trail grezzo ha già flippato (trail = src + nLoss).
         // Ma emettiamo SELL solo se la distanza è sufficiente per nLossSell.
         isSell = (src1 > t1) && (src < trail) && biasShort
                  && (t1 - src >= nLossSell - nLoss);
         // Spiegazione: t1-src è quanto il prezzo è sceso sotto il trail precedente.
         // Richiediamo che questa discesa sia >= la differenza tra i due nLoss.
         // Se nLossSell == nLoss (Key uguali), la condizione extra è sempre true.
      }
      else
         isSell = (src1 > t1) && (src < trail) && biasShort;

      // ... resto invariato ...
   }
}
```

**Preset AUTO suggeriti per Dual Sensitivity:**
```
TF    Key_BUY  ATR_BUY  Key_SELL  ATR_SELL
M1    0.7      5        1.0       7
M5    1.0      7        1.5       10
M15   1.2      10       1.8       14
M30   1.5      10       2.0       14
H1    2.0      14       2.5       14
H4    2.5      14       3.0       14
```

---

### MODIFICA 2 — ADX gate (filtro ranging)

**Obiettivo:** Risolvere il Problema A (rumore in fase laterale)
**Impatto:** ALTO
**Rischio:** BASSO
**Righe da aggiungere:** ~20

**Nuovi input parameters:**
```mql5
input group "    📊 FILTRO ADX (Anti-Ranging)"
input bool    InpUseADXFilter = false;    // Abilita filtro ADX
input int     InpADXPeriod    = 14;       // ADX Period
input int     InpADXThreshold = 20;       // ADX soglia minima (segnali solo se ADX >= soglia)
```

**Nuove variabili globali:**
```mql5
int g_adxHandle = INVALID_HANDLE;
```

**In OnInit (dopo il bias HTF, riga ~594):**
```mql5
if(InpUseADXFilter)
{
   g_adxHandle = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   if(g_adxHandle == INVALID_HANDLE)
      Print("[UTBot] WARN: ADX handle non valido, filtro disabilitato");
}
```

**In OnDeinit (dopo rilascio HTF, riga ~697):**
```mql5
if(g_adxHandle != INVALID_HANDLE)
{
   IndicatorRelease(g_adxHandle);
   g_adxHandle = INVALID_HANDLE;
}
```

**Nel loop OnCalculate, prima della lettura bias HTF (riga ~1380):**
```mql5
// Legge ADX per filtro ranging
double adxValue = 100.0;  // default: nessun filtro (passa sempre)
if(InpUseADXFilter && g_adxHandle != INVALID_HANDLE)
{
   double adxBuf[1];
   // Buffer 0 di iADX = linea ADX principale
   if(CopyBuffer(g_adxHandle, 0, 0, 1, adxBuf) == 1)
      adxValue = adxBuf[0];
}
bool adxPass = (adxValue >= InpADXThreshold);
```

**Nella condizione segnale (righe 1439-1440):**
```mql5
// PRIMA:
bool isBuy  = (src1 < t1) && (src > trail) && biasLong;
bool isSell = (src1 > t1) && (src < trail) && biasShort;

// DOPO:
bool isBuy  = (src1 < t1) && (src > trail) && biasLong && adxPass;
bool isSell = (src1 > t1) && (src < trail) && biasShort && adxPass;
```

**NOTA IMPORTANTE:** L'ADX è letto dalla barra corrente (shift=0), NON dalla barra
chiusa (shift=1). Questo è intenzionale: il filtro ADX è un gate "ambientale"
(il mercato è in trend?) non un segnale puntuale. Se si preferisce anti-repaint
puro, usare shift=1 — ma l'ADX cambia molto lentamente, la differenza è minima.

---

### MODIFICA 3 — ER finestrato (fix del proxy single-bar)

**Obiettivo:** Rendere il colore delle frecce affidabile con tutte le sorgenti
**Impatto:** MEDIO-ALTO
**Rischio:** BASSO
**Righe da modificare:** ~10

**Sostituzione nel loop (righe 1417-1428):**
```mql5
// PRIMA:
double er_val = 0.0;
if(InpSrcType == SRC_KAMA && i >= g_eff_kamaN)
{
   double d = MathAbs(close[i] - close[i - g_eff_kamaN]);
   double n = 0.0;
   for(int k = 1; k <= g_eff_kamaN; k++)
      n += MathAbs(close[i - k + 1] - close[i - k]);
   er_val = (n > 0.0) ? d / n : 0.0;
}
else if(g_atr[i] > 0.0)
   er_val = MathMin(1.0, MathAbs(src - src1) / g_atr[i]);
B_ER[i] = er_val;

// DOPO (ER finestrato SEMPRE su close, per tutte le sorgenti):
double er_val = 0.0;
int erWin = g_eff_kamaN;  // riusa il periodo KAMA come finestra ER
if(i >= erWin)
{
   double d = MathAbs(close[i] - close[i - erWin]);
   double n = 0.0;
   for(int k = 1; k <= erWin; k++)
      n += MathAbs(close[i - k + 1] - close[i - k]);
   er_val = (n > 0.0) ? d / n : 0.0;
}
B_ER[i] = er_val;
```

**Effetto:** Il colore delle frecce (erIdx 0-3) ora riflette il vero ER di Kaufman
su 8 barre (M5) o 10 barre (M15), indipendentemente dalla sorgente.
Le frecce grigie significano VERAMENTE "ranging", non "la JMA si è mossa poco
in questa singola barra".

---

### MODIFICA 4 — Candele grigie (zona neutra visiva)

**Obiettivo:** Feedback visivo quando i segnali sono filtrati
**Impatto:** MEDIO
**Rischio:** BASSO
**Righe da modificare:** ~15

**Modifica property (riga 107-113):**
```mql5
// PRIMA (3 colori):
#property indicator_color5  C'38,166,154', C'239,83,80', C'255,235,59'

// DOPO (4 colori):
#property indicator_color5  C'38,166,154', C'239,83,80', C'255,235,59', C'120,120,120'
// Indice 0: teal (bull), 1: coral (bear), 2: giallo (trigger), 3: GRIGIO (neutro)
```

**Modifica nel loop, colorazione candele (righe 1463-1471):**
```mql5
// PRIMA:
B_CClr[i] = (isBuy || isSell) ? 2.0 :
             (src > trail) ? 0.0 : 1.0;

// DOPO:
if(isBuy || isSell)
   B_CClr[i] = 2.0;                                  // giallo trigger
else if(!adxPass)
   B_CClr[i] = 3.0;                                  // GRIGIO — ranging (ADX < soglia)
else
   B_CClr[i] = (src > trail) ? 0.0 : 1.0;           // teal/coral normale
```

**Stessa modifica per la barra corrente (righe 1484-1491):**
```mql5
// DOPO:
if(!adxPass)
   B_CClr[i] = 3.0;                                  // GRIGIO
else
   B_CClr[i] = (src > trail) ? 0.0 : 1.0;
```

**Effetto:** Quando l'ADX è sotto soglia, le candele diventano grigie.
Il trader vede immediatamente "zona di non-operatività".
Nessuno stato persistente, nessun `lastDir`, nessun bug tipo Filtered.
Il colore segue SEMPRE la condizione corrente.

---

## SEZIONE D — ORDINE DI IMPLEMENTAZIONE

1. **BUG 1** (iCustom parametri) — fix immediato, 2 righe
2. **Modifica 3** (ER finestrato) — prerequisito per colori affidabili, 10 righe
3. **Modifica 2** (ADX gate) — filtro ranging, 20 righe
4. **Modifica 4** (candele grigie) — dipende dalla Modifica 2, 15 righe
5. **Modifica 1** (Dual Sensitivity) — più complessa, da testare separatamente, 30 righe

**TOTALE:** ~77 righe di codice nuovo/modificato.

---

## SEZIONE E — TEST DI VERIFICA

### Test 1: Regressione (nessuna modifica attiva)
Con InpDualSens=false, InpUseADXFilter=false, il comportamento deve essere
IDENTICO all'originale, segnale per segnale. Verificare su USDJPY M5,
zona 25 Feb - 3 Mar (screenshot 13_37_15.png).

### Test 2: Solo ADX filter
Attivare InpUseADXFilter=true, InpADXThreshold=20.
Le zone di ranging negli screenshot (14-15 Apr M5) devono mostrare candele grigie
e nessuna freccia. I trend puliti (25-26 Feb ribasso M5) devono avere frecce normali.

### Test 3: Solo Dual Sensitivity
Attivare InpDualSens=true, InpKeyValueSell=1.5.
Nella zona M30 (19 Mar, screenshot 13_36_44.png), il pullback in uptrend
NON deve generare una freccia SELL (perché il Key SELL più alto assorbe lo storno).

### Test 4: ER finestrato
Confrontare il colore delle frecce PRIMA e DOPO il fix.
Le frecce in trend costante (piccole barre) devono essere verdi (ER alto).
Le frecce da spike isolati in range devono essere grigie (ER basso).
