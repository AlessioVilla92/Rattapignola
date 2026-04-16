# Implementazione Fase 1 — Indicatore UTBotAdaptive.mq5 (Test Visivo)

## OBIETTIVO
Modificare l'indicatore UTBotAdaptive.mq5 per testare VISIVAMENTE le 3 modifiche
di Fase 1 direttamente sul chart, PRIMA di toccare l'EA. Le frecce filtrate
verranno mostrate in colore diverso (grigio scuro) per distinguerle da quelle confermate.

**File da modificare**: `UTBotAdaptive.mq5` (una sola copia — rinominare il file
modificato come `UTBotAdaptive_Filtered.mq5` per non sovrascrivere l'originale)

---

## MODIFICA 0: Rinominare il file

Creare una copia di `UTBotAdaptive.mq5` chiamata `UTBotAdaptive_Filtered.mq5`.
Tutte le modifiche seguenti si applicano SOLO al file `_Filtered`.

---

## MODIFICA 1: Nuovi Input Parameters

### Inserimento: DOPO riga 195 (`input ENUM_TIMEFRAMES InpBiasTF = PERIOD_H1;`)

Aggiungere questi nuovi parametri:

```mql5
input group "                                                               "
input group "╔═══════════════════════════════════════════════════════════╗"
input group "║  🛡️ FILTRI FASE 1 — Test Visivo                         ║"
input group "╚═══════════════════════════════════════════════════════════╝"

input int             InpConfirmBars    = 2;        // Barre conferma crossover (0=off, 1=originale, 2=raccomandato M5)
input bool            InpERAsymmetric   = true;     // ER asimmetrico: inversioni richiedono ER >= ERStrong
input double          InpERStrong_Filt  = 0.35;     // Soglia ER per inversioni (se asimmetrico)
input double          InpERWeak_Filt    = 0.15;     // Soglia ER minima (segnali nella stessa direzione)
input bool            InpShowBlocked    = true;     // Mostra frecce bloccate in grigio scuro
```

### Spiegazione parametri:
- `InpConfirmBars`: quante barre consecutive il crossover deve persistere. 0=disattivo, 1=come oggi, 2=raccomandato su M5
- `InpERAsymmetric`: se true, per invertire direzione (da BUY a SELL o viceversa) serve ER >= InpERStrong_Filt. Per continuare nella stessa direzione basta ER >= InpERWeak_Filt
- `InpShowBlocked`: se true, le frecce bloccate dai filtri vengono mostrate in grigio scuro (indice colore 3). Se false, le frecce bloccate non vengono mostrate affatto

---

## MODIFICA 2: Nuove Variabili Globali per Conferma

### Inserimento: DOPO riga 325 (`int g_dash_ratesTotal = 0;`)

```mql5
//--- Stato conferma N-barre (Fase 1, Mod 2)
int    g_confirm_pendingDir   = 0;    // direzione in attesa: +1=BUY, -1=SELL, 0=nessuna
int    g_confirm_count        = 0;    // quante barre consecutive hanno confermato
int    g_confirm_lastDir      = 0;    // ultima direzione confermata (per ER asimmetrico)
```

---

## MODIFICA 3: Reset variabili conferma in OnInit

### Inserimento: DOPO riga 535 (`g_entryLevel = EMPTY_VALUE;`)

```mql5
   //--- Reset stato conferma Fase 1
   g_confirm_pendingDir = 0;
   g_confirm_count      = 0;
   g_confirm_lastDir    = 0;
```

---

## MODIFICA 4: Logica filtri nel loop OnCalculate — SOSTITUZIONE BLOCCO SEGNALI

Questa è la modifica principale. Sostituire il blocco segnali alle righe 1419-1454
(dentro `if(i < rates_total - 1)`).

### CODICE DA SOSTITUIRE (righe 1419-1454):

Trovare questo blocco:
```mql5
      if(i < rates_total - 1)
        {
         //--- Segnali con filtro bias HTF ---
         bool isBuy  = (src1 < t1) && (src > trail) && biasLong;
         bool isSell = (src1 > t1) && (src < trail) && biasShort;

         //--- Frecce colorate per ER ---
         B_Buy[i]     = isBuy  ? (low[i]  - g_atr[i] * 0.5) : EMPTY_VALUE;
         B_BuyClr[i]  = (double)erIdx;
         B_Sell[i]    = isSell ? (high[i] + g_atr[i] * 0.5) : EMPTY_VALUE;
         B_SellClr[i] = (double)erIdx;

         //--- Entry level line: carry-forward fino al prossimo segnale ---
         if(isBuy || isSell)
            g_entryLevel = close[i];
         B_EntryLine[i] = g_entryLevel;

         //--- Stato posizione (per EA, buffer 13) ---
         if(src1 < t1 && src > t1)
            B_State[i] = 1.0;
         else if(src1 > t1 && src < t1)
            B_State[i] = -1.0;
         else
            B_State[i] = B_State[i - 1];

         //--- Candele colorate ---
         // Barra trigger (BUY o SELL): GIALLA — indice 2 = C'255,235,59'.
         if(InpColorBars)
           {
            B_CO[i]   = open[i];
            B_CH[i]   = high[i];
            B_CL[i]   = low[i];
            B_CC[i]   = close[i];
            B_CClr[i] = (isBuy || isSell) ? 2.0 :
                         (src > trail) ? 0.0 : 1.0;
           }
        }
```

### SOSTITUIRE CON:

```mql5
      if(i < rates_total - 1)
        {
         //=== STEP A: Crossover grezzo (INVARIATO — identico a prima) ===
         bool rawBuy  = (src1 < t1) && (src > trail) && biasLong;
         bool rawSell = (src1 > t1) && (src < trail) && biasShort;

         //=== STEP B: Stato posizione GREZZO (per EA, buffer 13) ===
         // B_State riflette il crossover grezzo, NON filtrato.
         // L'EA legge questo per il bias HTF — deve essere il dato puro.
         if(src1 < t1 && src > t1)
            B_State[i] = 1.0;
         else if(src1 > t1 && src < t1)
            B_State[i] = -1.0;
         else
            B_State[i] = B_State[i - 1];

         //=== STEP C: Conferma N-barre (Mod 2) ===
         bool confirmedBuy  = false;
         bool confirmedSell = false;

         if(InpConfirmBars <= 1)
           {
            // Nessuna conferma richiesta — comportamento originale
            confirmedBuy  = rawBuy;
            confirmedSell = rawSell;
           }
         else
           {
            // Conferma richiesta: il crossover deve persistere per N barre
            if(rawBuy)
              {
               if(g_confirm_pendingDir == +1)
                  g_confirm_count++;
               else
                 {
                  g_confirm_pendingDir = +1;
                  g_confirm_count = 1;
                 }
              }
            else if(rawSell)
              {
               if(g_confirm_pendingDir == -1)
                  g_confirm_count++;
               else
                 {
                  g_confirm_pendingDir = -1;
                  g_confirm_count = 1;
                 }
              }
            else
              {
               // Nessun crossover — reset contatore
               g_confirm_count = 0;
               g_confirm_pendingDir = 0;
              }

            // Segnale confermato solo se il contatore raggiunge N
            if(g_confirm_pendingDir == +1 && g_confirm_count >= InpConfirmBars)
              {
               confirmedBuy = true;
               g_confirm_count = 0;        // reset dopo emissione
               g_confirm_pendingDir = 0;
              }
            if(g_confirm_pendingDir == -1 && g_confirm_count >= InpConfirmBars)
              {
               confirmedSell = true;
               g_confirm_count = 0;
               g_confirm_pendingDir = 0;
              }
           }

         //=== STEP D: Filtro ER Asimmetrico (Mod Bonus) ===
         bool erBlocked = false;

         if(InpERAsymmetric && (confirmedBuy || confirmedSell))
           {
            int newDir = confirmedBuy ? +1 : -1;
            bool isReversal = (g_confirm_lastDir != 0 && newDir != g_confirm_lastDir);

            double erThreshold = isReversal ? InpERStrong_Filt : InpERWeak_Filt;

            if(er_val < erThreshold)
              {
               erBlocked = true;
               confirmedBuy  = false;
               confirmedSell = false;
              }
           }

         // Aggiorna l'ultima direzione confermata
         if(confirmedBuy)  g_confirm_lastDir = +1;
         if(confirmedSell) g_confirm_lastDir = -1;

         //=== STEP E: Segnali finali (isBuy / isSell) ===
         bool isBuy  = confirmedBuy;
         bool isSell = confirmedSell;

         //=== STEP F: Frecce — segnali confermati + bloccati in grigio ===
         if(isBuy)
           {
            B_Buy[i]    = low[i] - g_atr[i] * 0.5;
            B_BuyClr[i] = (double)erIdx;    // colore ER normale
           }
         else if(rawBuy && InpShowBlocked)
           {
            // Freccia BUY grezza che è stata bloccata da conferma o ER
            B_Buy[i]    = low[i] - g_atr[i] * 0.5;
            B_BuyClr[i] = 3.0;    // grigio (indice 3) = segnale bloccato
           }
         else
           {
            B_Buy[i]    = EMPTY_VALUE;
            B_BuyClr[i] = 0.0;
           }

         if(isSell)
           {
            B_Sell[i]    = high[i] + g_atr[i] * 0.5;
            B_SellClr[i] = (double)erIdx;   // colore ER normale
           }
         else if(rawSell && InpShowBlocked)
           {
            // Freccia SELL grezza che è stata bloccata
            B_Sell[i]    = high[i] + g_atr[i] * 0.5;
            B_SellClr[i] = 3.0;   // grigio = bloccato
           }
         else
           {
            B_Sell[i]    = EMPTY_VALUE;
            B_SellClr[i] = 0.0;
           }

         //=== STEP G: Entry level line (solo su segnali CONFERMATI) ===
         if(isBuy || isSell)
            g_entryLevel = close[i];
         B_EntryLine[i] = g_entryLevel;

         //=== STEP H: Candele colorate ===
         if(InpColorBars)
           {
            B_CO[i]   = open[i];
            B_CH[i]   = high[i];
            B_CL[i]   = low[i];
            B_CC[i]   = close[i];
            // Gialla solo per segnali CONFERMATI
            B_CClr[i] = (isBuy || isSell) ? 2.0 :
                         (src > trail) ? 0.0 : 1.0;
           }
        }
```

---

## MODIFICA 5: Dashboard — Mostrare stato filtri

### Inserimento: nella funzione `UpdateUTBDashboard()` (cercare la sezione dashboard)

Aggiungere una riga dopo le informazioni di bias HTF per mostrare lo stato dei filtri:

```mql5
   // Dopo la riga che mostra il bias HTF, aggiungere:
   if(InpConfirmBars > 1)
      UTBSetRow(row++, "Confirm: " + IntegerToString(InpConfirmBars) + " bars" +
                (g_confirm_pendingDir != 0 ? " [PENDING " + IntegerToString(g_confirm_count) + "/" + IntegerToString(InpConfirmBars) + "]" : ""),
                clrYellow);
   if(InpERAsymmetric)
      UTBSetRow(row++, "ER Asym: Rev>=" + DoubleToString(InpERStrong_Filt,2) +
                " Cont>=" + DoubleToString(InpERWeak_Filt,2), clrYellow);
```

---

## RIEPILOGO IMPOSTAZIONI CONSIGLIATE PER TEST

### Test su M5 GBPJPY:
```
InpUseBias       = true
InpBiasTF        = PERIOD_M30
InpConfirmBars   = 2
InpERAsymmetric  = true
InpERStrong_Filt = 0.35
InpERWeak_Filt   = 0.15
InpShowBlocked   = true    ← per vedere quali frecce vengono filtrate
```

### Test su M15 GBPJPY:
```
InpUseBias       = true
InpBiasTF        = PERIOD_H1
InpConfirmBars   = 1       ← nessuna conferma aggiuntiva su M15
InpERAsymmetric  = true
InpERStrong_Filt = 0.35
InpERWeak_Filt   = 0.15
InpShowBlocked   = true
```

### Per confronto con l'originale:
Caricare ENTRAMBI gli indicatori sullo stesso chart:
1. `UTBotAdaptive.mq5` con impostazioni originali (tutti i filtri OFF)
2. `UTBotAdaptive_Filtered.mq5` con i filtri attivi

Le frecce grigie nel filtered mostrano cosa viene bloccato.
Le frecce colorate mostrano cosa passa i filtri.

---

## NOTA SUL B_State (BUFFER 13)

IMPORTANTE: il B_State (buffer 13) resta INVARIATO — riflette il crossover
GREZZO, non filtrato. Questo è intenzionale:
- L'EA legge B_State per il bias HTF di altre istanze
- Il bias deve essere basato sul dato puro, non filtrato
- I filtri sono decisioni dell'EA, non dell'indicatore

---

## COME VALIDARE

Dopo aver compilato e caricato il _Filtered:
1. Scorri lo storico su M5 GBPJPY
2. Cerca le zone dove c'è un uptrend forte con pullback
3. Verifica che le frecce SELL durante il pullback siano GRIGIE (bloccate)
4. Verifica che le frecce SELL durante le vere inversioni siano COLORATE (passano)
5. Conta: quante frecce grigie vs colorate? L'obiettivo è ~80-90% grigie

Se vedi troppe frecce colorate che sono whipsaw → alza InpERStrong_Filt a 0.40
Se vedi troppe frecce grigie che erano buone → abbassa InpConfirmBars a 1
