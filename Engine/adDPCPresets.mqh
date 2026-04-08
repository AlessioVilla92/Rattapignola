//+------------------------------------------------------------------+
//|                                          adDPCPresets.mqh        |
//|           AcquaDulza EA v1.6.1 — DPC TF Auto-Preset             |
//|                                                                  |
//|  Inizializza parametri effettivi per il TF corrente.             |
//|  Se InpEngineAutoTFPreset=true, sovrascrive i valori input.      |
//|                                                                  |
//|  v1.6.1: Allineato a DPC v2.0 (v7.19):                          |
//|    - NUOVO preset M1: maLen=200, minWidth=4.0, flatTol=0.95      |
//|    - M15 flatTol 0.65→0.70 (+8-12% segnali)                      |
//|    - M30 minWidth 14→12, flatTol 0.50→0.60, minLevelAge 2→4     |
//|    - H1/H4 minLevelAge hardcoded (5/3) invece di input           |
//|  v1.5.2: Aggiunto preset TF-aware per LTFEntry, LevelAge,       |
//|          PendingExpiry (M5/M15/M30). H1/H4 usano input.          |
//|  v1.3.0: M5/M15 allineati a Carneval EA (flatTol, cooldown)      |
//|  PRESET ALLINEATI a DonchianPredictiveChannel v2.0 (v7.19)       |
//|  Logica: MA scala INVERSAMENTE col TF (finestra temporale ~cost) |
//|    M5=50 barre×5min=250min≈4h  |  H4=12 barre×240min=48h≈2gg   |
//|  Cooldown/flatLook scalano inversamente (1 barra H4 = 4h già)   |
//|  MinWidth scala direttamente col TF (canali più ampi su TF alti) |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| DPC Engine effective parameters (set by preset or input)         |
//+------------------------------------------------------------------+
int    g_dpc_dcLen     = 20;
int    g_dpc_maLen     = 30;
double g_dpc_minWidth  = 8.0;
int    g_dpc_flatLook  = 2;
double g_dpc_flatTol   = 0.85;
int    g_dpc_nSame     = 2;
int    g_dpc_nOpp      = 1;

//+------------------------------------------------------------------+
//| DPC Preset: framework params TF-aware (v1.5.2)                  |
//| Gestiti dal preset per M5/M15/M30; H1/H4/default usano input    |
//+------------------------------------------------------------------+
bool   g_dpc_useLTFEntry   = false;
bool   g_dpc_ltfOnlyTBS    = true;
bool   g_dpc_useLevelAge   = false;
int    g_dpc_minLevelAge   = 3;
int    g_dpc_pendingExpiry  = 8;

//+------------------------------------------------------------------+
//| DPCPresetsInit — Auto-preset based on chart timeframe            |
//|                                                                  |
//| Values aligned with DonchianPredictiveChannel v2.0 (v7.19)       |
//|                                                                  |
//|  TF   | dcLen | maLen | minW  | nS | nO | fL | fT   | LTF | LvlAge | mAge | exp |
//|  M1   |  20   | 200   |  4.0  |  1 |  1 |  1 | 0.95 | OFF | OFF    |   1  | 15  |
//|  M5   |  20   |  50   |  7.0  |  2 |  1 |  2 | 0.85 | OFF | OFF    |   3  |  8  |
//|  M15  |  20   |  34   | 10.0  |  2 |  1 |  2 | 0.70 | ON  | inp    |   3  |  3  |
//|  M30  |  20   |  24   | 12.0  |  2 |  1 |  2 | 0.60 | ON  | inp    |   4  |  2  |
//|  H1   |  20   |  18   | 18.0  |  1 |  1 |  2 | 0.38 | inp | inp    |   5  | inp |
//|  H4   |  20   |  12   | 30.0  |  1 |  1 |  1 | 0.35 | inp | inp    |   3  | inp |
//+------------------------------------------------------------------+
bool DPCPresetsInit()
{
   if(!InpEngineAutoTFPreset)
   {
      // Manual mode: use input values directly
      g_dpc_dcLen    = InpLenDC;
      g_dpc_maLen    = InpMALen;
      g_dpc_minWidth = InpMinWidthPips;
      g_dpc_flatLook = InpFlatLookback;
      g_dpc_flatTol  = InpFlatnessTolerance;
      g_dpc_nSame    = InpNSameBars;
      g_dpc_nOpp     = InpNOppositeBars;
      // Framework params: use inputs as-is
      g_dpc_useLTFEntry   = InpUseLTFEntry;
      g_dpc_ltfOnlyTBS    = InpLTFOnlyTBS;
      g_dpc_useLevelAge   = InpUseLevelAge;
      g_dpc_minLevelAge   = InpMinLevelAge;
      g_dpc_pendingExpiry  = PendingExpiryBars;

      // Scala minWidth per classe strumento anche in modalità manuale
      // (es. BTCUSD con input 8.0 pip → 8.0 × 25.0 = 200.0 pip effettivi)
      if(g_inst_widthFactor > 1.0)
      {
         double origWidth = g_dpc_minWidth;
         g_dpc_minWidth *= g_inst_widthFactor;
         AdLogI(LOG_CAT_ENGINE, StringFormat("DPC MANUAL minWidth scaled by instrument factor: %.1f × %.1f = %.1f pip",
            origWidth, g_inst_widthFactor, g_dpc_minWidth));
      }

      AdLogI(LOG_CAT_ENGINE, StringFormat("DPC Preset: MANUAL — dcLen=%d maLen=%d minW=%.1f flatL=%d flatT=%.2f nS=%d nO=%d",
         g_dpc_dcLen, g_dpc_maLen, g_dpc_minWidth, g_dpc_flatLook, g_dpc_flatTol, g_dpc_nSame, g_dpc_nOpp));
      AdLogI(LOG_CAT_ENGINE, StringFormat("DPC Preset: MANUAL — LTF=%s LTFtbs=%s LvlAge=%s minAge=%d expiry=%d",
         g_dpc_useLTFEntry ? "ON" : "OFF", g_dpc_ltfOnlyTBS ? "YES" : "NO",
         g_dpc_useLevelAge ? "ON" : "OFF", g_dpc_minLevelAge, g_dpc_pendingExpiry));
      return true;
   }

   // Auto-preset based on Period() — aligned with DPC v2.0 (v7.19)
   switch(Period())
   {
      case PERIOD_M1:
         // M1: preset entry precision e backtest LTF (DPC v2.0)
         g_dpc_dcLen       = 20;
         g_dpc_maLen       = 200;     // 200×1min=200min≈3h20 bias sessione
         g_dpc_minWidth    = 4.0;     // TP=2pip > spread M1~1.5pip
         g_dpc_flatLook    = 1;       // solo barra precedente (M1 noisy)
         g_dpc_flatTol     = 0.95;    // quasi disabilitato su M1
         g_dpc_nSame       = 1;       // 1bar = 1min cooldown same dir
         g_dpc_nOpp        = 1;       // 1bar = 1min cooldown opp dir
         // Framework params M1
         g_dpc_useLTFEntry   = false;  // M1→M1 = loop logico, disabilitato
         g_dpc_ltfOnlyTBS    = true;
         g_dpc_useLevelAge   = false;  // M1 troppo noisy per LevelAge (come M5)
         g_dpc_minLevelAge   = 1;      // valore DPC 2.0 (inattivo se useLevelAge=OFF)
         g_dpc_pendingExpiry  = 15;    // 15×1min = 15min
         break;

      case PERIOD_M5:
         g_dpc_dcLen    = 20;
         g_dpc_maLen    = 50;       // MA=50×5min=250min≈4h
         g_dpc_minWidth = 7.0;      // minWidth alzato 5→7 pip (v7.19)
         g_dpc_flatLook = 2;        // 2 barre = 10min lookback (allineato Carneval)
         g_dpc_flatTol  = 0.85;     // tolleranza Carneval (ATR~8pip → soglia 6.8pip)
         g_dpc_nSame    = 2;        // 2 barre = 10min (allineato Carneval)
         g_dpc_nOpp     = 1;        // 1 barra = 5min (allineato Carneval)
         // Framework params M5
         g_dpc_useLTFEntry   = false;  // LTF M5→M1 non testato, disabilitato
         g_dpc_ltfOnlyTBS    = true;
         g_dpc_useLevelAge   = false;  // Impossibile su M5 (banda cambia ogni barra)
         g_dpc_minLevelAge   = 3;
         g_dpc_pendingExpiry  = 8;     // 8×5min = 40min
         break;

      case PERIOD_M15:
         // TF PRINCIPALE AcquaDulza — v1.6.1: flatTol 0.65→0.70 (DPC v2.0, +8-12% segnali)
         g_dpc_dcLen    = 20;
         g_dpc_maLen    = 34;       // MA=34×15min=510min≈8.5h
         g_dpc_minWidth = 10.0;
         g_dpc_flatLook = 2;        // 2 barre = 30min lookback
         g_dpc_flatTol  = 0.70;     // v1.6.1: era 0.65 → 0.70 (+8-12% segnali, DPC v2.0)
         g_dpc_nSame    = 2;        // 2 barre = 30min
         g_dpc_nOpp     = 1;        // 1 barra = 15min
         // Framework params M15
         g_dpc_useLTFEntry   = true;   // M15→M5 conferma eccellente
         g_dpc_ltfOnlyTBS    = true;
         g_dpc_useLevelAge   = InpUseLevelAge;  // da input (default OFF) — era hardcoded true
         g_dpc_minLevelAge   = 3;      // 3×15min = 45min di banda stabile
         g_dpc_pendingExpiry  = 3;     // 3×15min = 45min (~equiv. M5 40min)
         break;

      case PERIOD_M30:
         // v1.6.1: minWidth 14→12, flatTol 0.50→0.60, minLevelAge 2→4 (DPC v2.0)
         g_dpc_dcLen    = 20;
         g_dpc_maLen    = 24;       // MA=24×30min=720min=12h
         g_dpc_minWidth = 12.0;     // v1.6.1: era 14.0 (meno restrittivo, DPC v2.0)
         g_dpc_flatLook = 2;        // 2 barre = 1h lookback
         g_dpc_flatTol  = 0.60;     // v1.6.1: era 0.50 (scala ATR M30, DPC v2.0)
         g_dpc_nSame    = 2;        // 2 barre = 1h
         g_dpc_nOpp     = 1;        // 1 barra = 30min
         // Framework params M30
         g_dpc_useLTFEntry   = true;   // M30→M5 conferma valida
         g_dpc_ltfOnlyTBS    = true;
         g_dpc_useLevelAge   = InpUseLevelAge;  // da input (default OFF) — era hardcoded true
         g_dpc_minLevelAge   = 4;      // v1.6.1: era 2 → 4×30min = 2h banda stabile (DPC v2.0)
         g_dpc_pendingExpiry  = 2;     // 2×30min = 60min
         break;

      case PERIOD_H1:
         g_dpc_dcLen    = 20;
         g_dpc_maLen    = 18;       // MA=18×60min=1080min=18h
         g_dpc_minWidth = 18.0;     // canali H1 ampi
         g_dpc_flatLook = 2;        // 2 barre = 2h lookback
         g_dpc_flatTol  = 0.38;     // tolleranza ridotta H1 (ATR~25pip → soglia 9.5pip)
         g_dpc_nSame    = 1;        // 1 barra = 1h
         g_dpc_nOpp     = 1;        // 1 barra = 1h
         // Framework params H1: use inputs (no preset) — except minLevelAge (DPC v2.0 calibrato)
         g_dpc_useLTFEntry   = InpUseLTFEntry;
         g_dpc_ltfOnlyTBS    = InpLTFOnlyTBS;
         g_dpc_useLevelAge   = InpUseLevelAge;
         g_dpc_minLevelAge   = 5;      // v1.6.1: hardcoded 5×60min = 5h (era InpMinLevelAge)
         g_dpc_pendingExpiry  = PendingExpiryBars;
         break;

      case PERIOD_H4:
         g_dpc_dcLen    = 20;
         g_dpc_maLen    = 12;       // MA=12×240min=2880min≈2gg
         g_dpc_minWidth = 30.0;     // canali H4 molto ampi
         g_dpc_flatLook = 1;        // 1 barra = 4h lookback
         g_dpc_flatTol  = 0.35;     // tolleranza restrittiva H4 (trend pesanti, filtro forte)
         g_dpc_nSame    = 1;        // 1 barra = 4h
         g_dpc_nOpp     = 1;        // 1 barra = 4h
         // Framework params H4: use inputs (no preset) — except minLevelAge (DPC v2.0 calibrato)
         g_dpc_useLTFEntry   = InpUseLTFEntry;
         g_dpc_ltfOnlyTBS    = InpLTFOnlyTBS;
         g_dpc_useLevelAge   = InpUseLevelAge;
         g_dpc_minLevelAge   = 3;      // v1.6.1: hardcoded 3×240min = 12h (era InpMinLevelAge)
         g_dpc_pendingExpiry  = PendingExpiryBars;
         break;

      default:
         // H1, H4, and other TF: fallback to manual input values
         g_dpc_dcLen    = InpLenDC;
         g_dpc_maLen    = InpMALen;
         g_dpc_minWidth = InpMinWidthPips;
         g_dpc_flatLook = InpFlatLookback;
         g_dpc_flatTol  = InpFlatnessTolerance;
         g_dpc_nSame    = InpNSameBars;
         g_dpc_nOpp     = InpNOppositeBars;
         // Framework params: use inputs as-is
         g_dpc_useLTFEntry   = InpUseLTFEntry;
         g_dpc_ltfOnlyTBS    = InpLTFOnlyTBS;
         g_dpc_useLevelAge   = InpUseLevelAge;
         g_dpc_minLevelAge   = InpMinLevelAge;
         g_dpc_pendingExpiry  = PendingExpiryBars;

         AdLogW(LOG_CAT_ENGINE, StringFormat("DPC Preset: TF %s not in preset table — using manual values",
            EnumToString(Period())));
         return true;
   }

   // Scala minWidth per classe strumento (crypto=25x, indici=5-6x, oil=2x, forex/gold=1x)
   // g_inst_widthFactor è settato da InstrumentPresetsInit() che gira PRIMA di EngineInit()
   if(g_inst_widthFactor > 1.0)
   {
      double origWidth = g_dpc_minWidth;
      g_dpc_minWidth *= g_inst_widthFactor;
      AdLogI(LOG_CAT_ENGINE, StringFormat("DPC minWidth scaled by instrument factor: %.1f × %.1f = %.1f pip",
         origWidth, g_inst_widthFactor, g_dpc_minWidth));
   }

   AdLogI(LOG_CAT_ENGINE, StringFormat("DPC Preset: %s — dcLen=%d maLen=%d minW=%.1f flatL=%d flatT=%.2f nS=%d nO=%d",
      EnumToString(Period()), g_dpc_dcLen, g_dpc_maLen, g_dpc_minWidth,
      g_dpc_flatLook, g_dpc_flatTol, g_dpc_nSame, g_dpc_nOpp));
   AdLogI(LOG_CAT_ENGINE, StringFormat("DPC Preset: %s — LTF=%s LTFtbs=%s LvlAge=%s minAge=%d expiry=%d",
      EnumToString(Period()),
      g_dpc_useLTFEntry ? "ON" : "OFF", g_dpc_ltfOnlyTBS ? "YES" : "NO",
      g_dpc_useLevelAge ? "ON" : "OFF", g_dpc_minLevelAge, g_dpc_pendingExpiry));
   return true;
}
