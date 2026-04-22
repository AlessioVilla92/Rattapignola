# UTBot Adaptive — Modifiche Parte 1 (v2.10)

**Scopo**: file unico e definitivo con tutte le modifiche chirurgiche verificate, parametrizzate, pronte per Claude Code per creare `UTBotAdaptive.mq5` v2.10.

**Input**: `UTBotAdaptive-Ok-V1_-_Copia-originale.mq5` (v2.01, 1524 righe)
**Output**: `UTBotAdaptive.mq5` v2.10
**Breaking changes**: ZERO (buffer map invariata, Rattapignola compatibile)
**Rollback disponibile**: due toggle riportano al comportamento v2.01

---

## 1. Riepilogo delle 5 modifiche

| # | Modifica | Righe di codice | Impatto sul segnale | Controllo disattivazione |
|---|---|---|---|---|
| A | Frecce monocromatiche | 8 righe | No | — (cosmetica) |
| B | ER Kaufman uniforme | 14 righe | No | — (solo buffer esposto) |
| C | Auto SrcType per TF | ~15 righe | Sì su M5/M15 | `InpAutoSrcByTF=false` |
| D | 3 preset KAMA (Std/Mid/Slow) | ~100 righe | Sì su M15+ | `InpKamaPreset=STANDARD` |
| E | Cambio default `InpSrcType` | 1 riga | Solo con AUTO=off | Setting manuale |

**Ciò che NON cambia** (invariato rispetto v2.01):
- Formula trailing stop (4 rami Pine-fedele)
- Formula segnale (`isBuy = src1<t1 && src>trail && biasLong`)
- ATR Wilder (seed SMA + loop RMA)
- Anti-repainting (bar[1] confermato)
- Buffer map esposto: 0=Trail, 2=Buy, 4=Sell, 12=ER, 13=State

---

## 2. Preparazione

1. **Backup**: copia `UTBotAdaptive-Ok-V1_-_Copia-originale.mq5` in `UTBotAdaptive_v2.01_backup.mq5`
2. Lavora sulla copia **`UTBotAdaptive.mq5`** (nome finale per MT5)
3. Segui le FASI in ordine — sono dipendenti tra loro

---

## 3. FASE 1 — Header e version string

### 3.1 Version string (riga 57)

**Trova**:
```cpp
#property version   "2.01"
#property description "UT Bot Alerts — KAMA/HMA/JMA + anti-repainting + ER-colors"
#property description "v2.00: frecce ER-colorate, marker viola entrata, JMA adattiva, candela trigger gialla"
#property description "BUY/SELL su barre chiuse. Trigger bar = gialla. Entry marker = viola al close."
```

**Sostituisci con**:
```cpp
#property version   "2.10"
#property description "UT Bot Alerts — KAMA/HMA/JMA + anti-repainting + frecce monocromatiche"
#property description "v2.10: KAMA preset multipli (Standard/Middle/Slow) + ER Kaufman uniforme + Auto-SrcType per TF"
#property description "BUY/SELL su barre chiuse. Frecce verde/rosso pieno. Default M15: KAMA Middle (filtro anti-microstorno)."
```

---

## 4. FASE 2 — Frecce monocromatiche (Modifica A)

### 4.1 Sostituisci property colori frecce (righe 77-95)

**Trova**:
```cpp
// --- Plot 1: Freccia BUY — DRAW_COLOR_ARROW, 4 livelli ER ---
// Indice 0: verde pieno C'76,175,80'    ER>=0.60 — segnale affidabile
// Indice 1: verde chiar C'139,195,74'   ER 0.35-0.59 — moderato
// Indice 2: giallo      C'255,193,7'    ER 0.15-0.34 — debole
// Indice 3: grigio      C'120,120,120'  ER<0.15 — ranging, massima cautela
#property indicator_label2  "Buy"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_color2  C'76,175,80', C'139,195,74', C'255,193,7', C'120,120,120'
#property indicator_width2  2

// --- Plot 2: Freccia SELL — DRAW_COLOR_ARROW, 4 livelli ER ---
// Indice 0: rosso pieno  C'239,83,80'    ER>=0.60
// Indice 1: arancione    C'255,138,101'  ER 0.35-0.59
// Indice 2: giallo       C'255,193,7'    ER 0.15-0.34
// Indice 3: grigio       C'120,120,120'  ER<0.15
#property indicator_label3  "Sell"
#property indicator_type3   DRAW_COLOR_ARROW
#property indicator_color3  C'239,83,80', C'255,138,101', C'255,193,7', C'120,120,120'
#property indicator_width3  2
```

**Sostituisci con**:
```cpp
// --- Plot 1: Freccia BUY — monocromatica verde pieno (v2.10) ---
// v2.10: gradazione ER rimossa. Ogni segnale ha lo stesso peso visivo.
// Rationale: segnali con ER basso precedono spesso trend forti — colorarli
// in giallo/grigio creava bias di selezione controproducente.
// I 4 slot colore sono identici per preservare DRAW_COLOR_ARROW;
// il buffer B_BuyClr resta (buffer 3) per retrocompatibilità iCustom.
#property indicator_label2  "Buy"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_color2  C'76,175,80', C'76,175,80', C'76,175,80', C'76,175,80'
#property indicator_width2  2

// --- Plot 2: Freccia SELL — monocromatica rosso pieno (v2.10) ---
#property indicator_label3  "Sell"
#property indicator_type3   DRAW_COLOR_ARROW
#property indicator_color3  C'239,83,80', C'239,83,80', C'239,83,80', C'239,83,80'
#property indicator_width3  2
```

### 4.2 Forza Clr=0 nel loop OnCalculate (riga ~1446)

**Trova**:
```cpp
         //--- Frecce colorate per ER ---
         B_Buy[i]     = isBuy  ? (low[i]  - g_atr[i] * 0.5) : EMPTY_VALUE;
         B_BuyClr[i]  = (double)erIdx;
         B_Sell[i]    = isSell ? (high[i] + g_atr[i] * 0.5) : EMPTY_VALUE;
         B_SellClr[i] = (double)erIdx;
```

**Sostituisci con**:
```cpp
         //--- Frecce monocromatiche (v2.10) ---
         // BuyClr/SellClr forzati sempre a 0 (unico colore per direzione).
         B_Buy[i]     = isBuy  ? (low[i]  - g_atr[i] * 0.5) : EMPTY_VALUE;
         B_BuyClr[i]  = 0.0;
         B_Sell[i]    = isSell ? (high[i] + g_atr[i] * 0.5) : EMPTY_VALUE;
         B_SellClr[i] = 0.0;
```

---

## 5. FASE 3 — ER Kaufman uniforme (Modifica B)

### 5.1 Sostituisci blocco ER nel loop (righe ~1414-1428)

**Trova**:
```cpp
      //--- Efficiency Ratio inline ---
      // KAMA: ER esatto (stessa finestra g_eff_kamaN).
      // Altre sorgenti: proxy = min(1, |delta_src| / ATR).
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
```

**Sostituisci con**:
```cpp
      //--- Efficiency Ratio Kaufman windowed (v2.10) ---
      // ER autentico su close[] per TUTTE le sorgenti (non più proxy).
      // ER = |close[i] - close[i-N]| / Σ|close[k] - close[k-1]| su N=g_eff_kamaN
      // Range 0..1: 1 = perfettamente direzionale, 0 = totalmente choppy.
      // Misura l'efficienza del PREZZO (close), indipendente da g_eff_srcType.
      // Buffer 12 esposto all'EA host ora è coerente tra tutte le sorgenti.
      double er_val = 0.0;
      int erWin = g_eff_kamaN;
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

---

## 6. FASE 4 — Preset KAMA multipli + Auto-SrcType (Modifiche C+D)

### 6.1 Aggiungi ENUM_KAMA_PRESET (dopo ENUM_SRC_TYPE)

**Trova** (riga ~152):
```cpp
enum ENUM_SRC_TYPE
  {
   SRC_CLOSE = 0,  // Close — originale QuantNomad (nessun filtro)
   SRC_HMA   = 1,  // Hull Moving Average (lag ridotto, smoothing costante)
   SRC_KAMA  = 2,  // Kaufman Adaptive MA (anti-whipsaw adattivo) — RACCOMANDATO
   SRC_JMA   = 3,  // Jurik-style MA (adattivo, quasi zero lag)
  };
```

**Aggiungi subito dopo**:
```cpp
//+------------------------------------------------------------------+
//| ENUM — Preset KAMA (v2.10)                                       |
//+------------------------------------------------------------------+
// Tre configurazioni (N, Fast, Slow) calibrate per filtrare microstorni:
//   STANDARD (10,2,30):  KAMA ≈ EMA-32 su ER=0.3 — reattiva, filtro base
//   MIDDLE   (14,4,50):  KAMA ≈ EMA-91 su ER=0.3 — anti-microstorno M15
//   SLOW     (20,6,80):  KAMA ≈ EMA-188 su ER=0.3 — swing filter
//
// Trade-off: Middle ritarda 2-4 barre l'entry su trend forti (ER≈1) vs
// Standard. Per Signal-to-Signal è un prezzo accettabile per eliminare
// i falsi segnali da microstorno.
enum ENUM_KAMA_PRESET
  {
   KAMA_PRESET_AUTO     = 0,  // AUTO — rileva dal TF (M1/M5→STANDARD, M15+→MIDDLE)
   KAMA_PRESET_STANDARD = 1,  // STANDARD (10,2,30) — Kaufman default
   KAMA_PRESET_MIDDLE   = 2,  // MIDDLE (14,4,50) — anti-microstorno (raccomandato M15)
   KAMA_PRESET_SLOW     = 3,  // SLOW (20,6,80) — swing filter
   KAMA_PRESET_MANUAL   = 4   // MANUAL — usa InpKAMA_N/Fast/Slow dell'utente
  };
```

### 6.2 Aggiorna input `InpSrcType` e aggiungi `InpAutoSrcByTF` (riga ~174)

**Trova**:
```cpp
input ENUM_SRC_TYPE   InpSrcType     = SRC_JMA;   // ⚙ Tipo sorgente (JMA default v2.01)
input int             InpHMAPeriod   = 14;       // HMA Period (solo se SRC_HMA)
```

**Sostituisci con**:
```cpp
input ENUM_SRC_TYPE   InpSrcType     = SRC_KAMA;  // ⚙ Tipo sorgente (v2.10: KAMA default)
input bool            InpAutoSrcByTF = true;      // [v2.10] Auto SrcType per TF (M5/M15→KAMA)
input int             InpHMAPeriod   = 14;       // HMA Period (solo se SRC_HMA)
```

### 6.3 Aggiorna input KAMA con preset (riga ~177-180)

**Trova**:
```cpp
input group "    📐 KAMA (Kaufman Adaptive)"
input int             InpKAMA_N      = 10;       // KAMA ER Period (auto-preset)
input int             InpKAMA_Fast   = 2;        // KAMA Fast EMA (auto-preset)
input int             InpKAMA_Slow   = 30;       // KAMA Slow EMA (auto-preset)
```

**Sostituisci con**:
```cpp
input group "    📐 KAMA (Kaufman Adaptive)"
input ENUM_KAMA_PRESET InpKamaPreset  = KAMA_PRESET_AUTO;  // [v2.10] Preset KAMA (AUTO = M15→MIDDLE)
input int             InpKAMA_N      = 10;       // KAMA ER Period (solo se InpKamaPreset=MANUAL)
input int             InpKAMA_Fast   = 2;        // KAMA Fast EMA (solo se InpKamaPreset=MANUAL)
input int             InpKAMA_Slow   = 30;       // KAMA Slow EMA (solo se InpKamaPreset=MANUAL)
```

### 6.4 Aggiungi variabile globale `g_eff_srcType` (dopo riga ~289)

**Trova**:
```cpp
int    g_eff_jmaPhase;   // JMA Phase effettivo (-100..100)
```

**Aggiungi subito dopo**:
```cpp
ENUM_SRC_TYPE g_eff_srcType;   // [v2.10] SrcType effettivo (auto-preset per TF)
```

### 6.5 Sostituisci l'intera funzione `UTBotPresetsInit()` (righe 368-465)

**Trova l'intera funzione** `UTBotPresetsInit()` **e sostituiscila con**:

```cpp
//+------------------------------------------------------------------+
//| UTBotPresetsInit — Applica preset TF + preset KAMA (v2.10)       |
//+------------------------------------------------------------------+
// Imposta i parametri effettivi (g_eff_*) basandosi su:
//   1. InpTFPreset (AUTO/M1/M5/M15/M30/H1/H4/MANUAL) → Key, ATR, JMA, SrcType
//   2. InpKamaPreset (AUTO/STANDARD/MIDDLE/SLOW/MANUAL) → KAMA(N,Fast,Slow)
//   3. InpAutoSrcByTF → se true, SrcType auto per TF (M5/M15→KAMA, resto→JMA)
//                      se false, usa InpSrcType globale
//
// PRESET KAMA (v2.10):
//   STANDARD (10,2,30) — Kaufman default, filtro microstorni base
//   MIDDLE   (14,4,50) — anti-microstorno raccomandato per M15
//   SLOW     (20,6,80) — swing filter per H1/H4 o mercati choppy
//+------------------------------------------------------------------+
void UTBotPresetsInit()
  {
   ENUM_TF_PRESET_UT preset = InpTFPreset;

   //--- AUTO TF: rileva il TF corrente e mappa al preset UTBot
   if(preset == TF_PRESET_UT_AUTO)
     {
      switch(_Period)
        {
         case PERIOD_M1:  preset = TF_PRESET_UT_M1;  break;
         case PERIOD_M5:  preset = TF_PRESET_UT_M5;  break;
         case PERIOD_M15: preset = TF_PRESET_UT_M15; break;
         case PERIOD_M30: preset = TF_PRESET_UT_M30; break;
         case PERIOD_H1:  preset = TF_PRESET_UT_H1;  break;
         case PERIOD_H4:  preset = TF_PRESET_UT_H4;  break;
         default:         preset = TF_PRESET_UT_MANUAL; break;
        }
     }

   //--- STEP 1: Applica preset UTBot (Key, ATR, JMA, SrcType auto)
   // Nota: g_eff_kamaN/Fast/Slow vengono impostati come fallback,
   //       poi sovrascritti da UTBotKamaPresetApply() se non MANUAL.
   switch(preset)
     {
      case TF_PRESET_UT_M1:
         g_eff_keyValue  = 0.7;
         g_eff_atrPeriod = 5;
         g_eff_kamaN     = 5;  g_eff_kamaFast = 2;  g_eff_kamaSlow = 20;
         g_eff_jmaPeriod = 5;
         g_eff_jmaPhase  = 0;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_M5:
         g_eff_keyValue  = 1.0;
         g_eff_atrPeriod = 7;
         g_eff_kamaN     = 8;  g_eff_kamaFast = 2;  g_eff_kamaSlow = 20;
         g_eff_jmaPeriod = 8;
         g_eff_jmaPhase  = 0;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_KAMA : InpSrcType;
         break;

      case TF_PRESET_UT_M15:
         g_eff_keyValue  = 1.2;
         g_eff_atrPeriod = 10;
         g_eff_kamaN     = 10; g_eff_kamaFast = 2;  g_eff_kamaSlow = 30;
         g_eff_jmaPeriod = 14;
         g_eff_jmaPhase  = 0;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_KAMA : InpSrcType;  // [v2.10] M15 = KAMA
         break;

      case TF_PRESET_UT_M30:
         g_eff_keyValue  = 1.5;
         g_eff_atrPeriod = 10;
         g_eff_kamaN     = 10; g_eff_kamaFast = 2;  g_eff_kamaSlow = 30;
         g_eff_jmaPeriod = 18;
         g_eff_jmaPhase  = 50;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_H1:
         g_eff_keyValue  = 2.0;
         g_eff_atrPeriod = 14;
         g_eff_kamaN     = 14; g_eff_kamaFast = 2;  g_eff_kamaSlow = 35;
         g_eff_jmaPeriod = 20;
         g_eff_jmaPhase  = 50;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_H4:
         g_eff_keyValue  = 2.5;
         g_eff_atrPeriod = 14;
         g_eff_kamaN     = 14; g_eff_kamaFast = 2;  g_eff_kamaSlow = 40;
         g_eff_jmaPeriod = 28;
         g_eff_jmaPhase  = 75;
         g_eff_srcType   = InpAutoSrcByTF ? SRC_JMA  : InpSrcType;
         break;

      case TF_PRESET_UT_MANUAL:
      default:
         g_eff_keyValue  = InpKeyValue;
         g_eff_atrPeriod = InpATRPeriod;
         g_eff_kamaN     = InpKAMA_N;
         g_eff_kamaFast  = InpKAMA_Fast;
         g_eff_kamaSlow  = InpKAMA_Slow;
         g_eff_jmaPeriod = InpJMA_Period;
         g_eff_jmaPhase  = InpJMA_Phase;
         g_eff_srcType   = InpSrcType;
         break;
     }

   //--- STEP 2: Applica preset KAMA (sovrascrive kamaN/Fast/Slow se non MANUAL)
   UTBotKamaPresetApply(preset);
  }

//+------------------------------------------------------------------+
//| UTBotKamaPresetApply — Applica preset KAMA (v2.10)               |
//+------------------------------------------------------------------+
// Sovrascrive g_eff_kamaN/Fast/Slow in base a InpKamaPreset.
// Se AUTO: sceglie in base al TF
//   M1/M5  → STANDARD  (10,2,30)  — reattivo per scalping
//   M15+   → MIDDLE    (14,4,50)  — filtro anti-microstorno
// Se MANUAL: mantiene i valori già impostati dal preset TF.
//+------------------------------------------------------------------+
void UTBotKamaPresetApply(ENUM_TF_PRESET_UT tfPreset)
  {
   ENUM_KAMA_PRESET kPreset = InpKamaPreset;

   //--- AUTO: scelta preset KAMA in base al TF
   if(kPreset == KAMA_PRESET_AUTO)
     {
      switch(tfPreset)
        {
         case TF_PRESET_UT_M1:
         case TF_PRESET_UT_M5:
            kPreset = KAMA_PRESET_STANDARD;
            break;
         case TF_PRESET_UT_M15:
         case TF_PRESET_UT_M30:
         case TF_PRESET_UT_H1:
         case TF_PRESET_UT_H4:
            kPreset = KAMA_PRESET_MIDDLE;
            break;
         default:
            kPreset = KAMA_PRESET_MANUAL;
            break;
        }
     }

   //--- Applica preset
   switch(kPreset)
     {
      case KAMA_PRESET_STANDARD:
         g_eff_kamaN    = 10;
         g_eff_kamaFast = 2;
         g_eff_kamaSlow = 30;
         break;

      case KAMA_PRESET_MIDDLE:
         g_eff_kamaN    = 14;
         g_eff_kamaFast = 4;
         g_eff_kamaSlow = 50;
         break;

      case KAMA_PRESET_SLOW:
         g_eff_kamaN    = 20;
         g_eff_kamaFast = 6;
         g_eff_kamaSlow = 80;
         break;

      case KAMA_PRESET_MANUAL:
      default:
         // Non modifica: usa valori del preset TF o dell'utente
         break;
     }
  }
```

### 6.6 Sostituisci `InpSrcType` → `g_eff_srcType` nel loop OnCalculate (riga ~1313)

**Trova**:
```cpp
   //=== STEP 2: Sorgente adattiva ===
   switch(InpSrcType)
     {
      case SRC_CLOSE:
```

**Sostituisci con**:
```cpp
   //=== STEP 2: Sorgente adattiva — usa g_eff_srcType (v2.10) ===
   switch(g_eff_srcType)
     {
      case SRC_CLOSE:
```

### 6.7 Sostituisci `InpSrcType` → `g_eff_srcType` nello short name (riga ~515)

**Trova**:
```cpp
   string srcStr;
   switch(InpSrcType)
     {
      case SRC_CLOSE: srcStr = "Close"; break;
```

**Sostituisci con**:
```cpp
   string srcStr;
   switch(g_eff_srcType)   // [v2.10] usa sorgente effettiva
     {
      case SRC_CLOSE: srcStr = "Close"; break;
```

### 6.8 Aggiorna log OnInit (riga ~666)

**Trova**:
```cpp
   Print("[UTBot v2.00] Preset=", EnumToString(InpTFPreset),
         " | Key=", DoubleToString(g_eff_keyValue, 1),
         " | ATR=", g_eff_atrPeriod,
         " | Src=", EnumToString(InpSrcType),
         " | KAMA(", g_eff_kamaN, ",", g_eff_kamaFast, ",", g_eff_kamaSlow, ")",
         " | Warmup=", g_warmup);
```

**Sostituisci con**:
```cpp
   Print("[UTBot v2.10] TFPreset=", EnumToString(InpTFPreset),
         " | KAMAPreset=", EnumToString(InpKamaPreset),
         " | Key=", DoubleToString(g_eff_keyValue, 1),
         " | ATR=", g_eff_atrPeriod,
         " | Src=", EnumToString(g_eff_srcType),
         " | KAMA(", g_eff_kamaN, ",", g_eff_kamaFast, ",", g_eff_kamaSlow, ")",
         " | Warmup=", g_warmup);
```

---

## 7. Checklist post-implementazione

### 7.1 Verifica compilazione
- [ ] MetaEditor compila senza errori, senza warning
- [ ] `#property indicator_buffers 14` invariato
- [ ] `#property indicator_plots 5` invariato

### 7.2 Verifica comportamento default (AUTO + AUTO)

**Test M15 EURUSD** con `InpTFPreset=AUTO`, `InpKamaPreset=AUTO`, `InpAutoSrcByTF=true`:

Atteso nel log:
```
[UTBot v2.10] TFPreset=TF_PRESET_UT_AUTO | KAMAPreset=KAMA_PRESET_AUTO | Key=1.2 | ATR=10 | Src=SRC_KAMA | KAMA(14,4,50) | Warmup=74
```

Atteso sul chart:
- Dashboard: `KAMA(14,4,50)`
- Short name: `UTBot[1.2,10,KAMA(14,4,50)]`
- Frecce BUY: tutte verde pieno `C'76,175,80'`
- Frecce SELL: tutte rosso pieno `C'239,83,80'`

### 7.3 Verifica rollback (ripristino comportamento v2.01)

Imposta:
- `InpAutoSrcByTF = false`
- `InpSrcType = SRC_JMA`
- `InpKamaPreset = KAMA_PRESET_MANUAL`

Su M15, il comportamento deve essere **identico a v2.01**: stessa sorgente JMA, stessi parametri KAMA se utilizzati manualmente.

### 7.4 Verifica per altri TF

| TF | Src atteso | KAMA params attesi |
|---|---|---|
| M1 | SRC_JMA | KAMA(5,2,20) — irrilevante, sorgente è JMA |
| M5 | SRC_KAMA | KAMA(10,2,30) — STANDARD |
| M15 | SRC_KAMA | **KAMA(14,4,50) — MIDDLE** ⭐ |
| M30 | SRC_JMA | KAMA(14,4,50) — irrilevante, sorgente è JMA |
| H1 | SRC_JMA | KAMA(14,4,50) — irrilevante |
| H4 | SRC_JMA | KAMA(14,4,50) — irrilevante |

---

## 8. Impatto su Rattapignola

**Breaking changes**: zero.

Buffer esposti all'EA (invariati):
- Buffer 0: Trail value
- Buffer 2: BUY signal (posizione freccia)
- Buffer 4: SELL signal (posizione freccia)
- Buffer 12: ER (ora autentico Kaufman per tutte le sorgenti)
- Buffer 13: State (+1/-1/0)

Il motore embedded `rattUTBotEngine.mqh` se duplica internamente la logica KAMA dovrà essere allineato ai nuovi parametri (14,4,50) per M15. Finché legge i buffer via `iCustom`, è automaticamente compatibile.

---

## 9. Output atteso

File: `UTBotAdaptive.mq5` v2.10
Dimensione: ~1590-1610 righe (+70-90 rispetto a v2.01)
Buffer: 14 invariati
Plot: 5 invariati

Funzionalità aggiunte:
- ✅ Frecce monocromatiche
- ✅ ER Kaufman autentico per tutte le sorgenti
- ✅ Auto-SrcType per TF
- ✅ 3 preset KAMA selezionabili (AUTO = MIDDLE su M15+)
- ✅ Default `InpSrcType = SRC_KAMA`

Funzionalità NON incluse (rifiutate con motivazione):
- ❌ Flat Detection + gate
- ❌ Chandelier Exit
- ❌ Multi-ER arrows
- ❌ BiasContra markers
- ❌ Logging verbose
- ❌ Per-bar HTF bias storico

---

## 10. Tempo stimato per Claude Code

45-60 minuti per:
- Applicare le 5 modifiche
- Verificare compilazione
- Produrre il file finale in `/mnt/user-data/outputs/UTBotAdaptive.mq5`

Quando Claude Code ha finito, l'utente testa su M15 EURUSD per 24-48h prima del deploy finale.
