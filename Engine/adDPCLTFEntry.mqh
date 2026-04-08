//+------------------------------------------------------------------+
//|                                        adDPCLTFEntry.mqh         |
//|           AcquaDulza EA v1.6.1 — DPC LTF Entry Confirmation      |
//|                                                                  |
//|  Lower TimeFrame entry confirmation for precise timing.          |
//|  Based on DPC0404 v7.19 Section 5c.                              |
//|                                                                  |
//|  LOGICA: Dopo un segnale sul TF principale, apre una "finestra"  |
//|  di conferma sul TF inferiore. Se una candela LTF chiusa mostra  |
//|  un rejection dalla banda (touch + close inside), il segnale     |
//|  viene confermato con timing piu' preciso.                       |
//|                                                                  |
//|  FLOW:                                                           |
//|    1. Main TF signal -> DPCLTFOpenWindow() apre finestra         |
//|    2. OnTick() chiama DPCLTFCheckConfirmation() ad ogni tick      |
//|    3. Legge candela LTF chiusa (shift=1, zero repaint)           |
//|    4. BUY: low <= banda E close > banda -> rejection bullish     |
//|    5. SELL: high >= banda E close < banda -> rejection bearish   |
//|    6. Finestra scade dopo 1 barra del TF principale              |
//|                                                                  |
//|  ANTI-REPAINT: usa sempre bar[1] del LTF (barra chiusa).        |
//|  ANTI-DUPLICATE: g_ltfLastProcessed previene check multipli      |
//|  sulla stessa barra LTF.                                        |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| LTF State Variables (DPC Engine scoped)                          |
//|                                                                  |
//| g_ltfWindowOpen:     true se finestra di conferma e' attiva      |
//| g_ltfDirection:      direzione da confermare (+1=BUY, -1=SELL)   |
//| g_ltfBandLevel:      livello banda da monitorare (upper o lower) |
//| g_ltfWindowExpiry:   timestamp scadenza (barTime + PeriodSec)    |
//| g_ltfLastProcessed:  timestamp ultima barra LTF processata       |
//| g_ltfConfirmedBar:   barra main TF dove LTF e' stato confermato |
//+------------------------------------------------------------------+
bool     g_ltfWindowOpen     = false;
int      g_ltfDirection      = 0;       // +1=BUY, -1=SELL
double   g_ltfBandLevel      = 0.0;     // Band level to monitor
datetime g_ltfWindowExpiry   = 0;       // Window expiry time
datetime g_ltfLastProcessed  = 0;       // Last LTF bar processed (anti-duplicate)
datetime g_ltfConfirmedBar   = 0;       // Bar where LTF was confirmed (anti-reopen)

//+------------------------------------------------------------------+
//| DPCGetLTFTimeframe — Auto-adaptive LTF mapping                  |
//|                                                                  |
//| Mapping TF principale -> TF di conferma:                         |
//|   M5  -> M1  (5 candele LTF per ogni barra principale)          |
//|   M15 -> M5  (3 candele LTF)                                    |
//|   M30 -> M5  (6 candele LTF)                                    |
//|   H1  -> M15 (4 candele LTF)                                    |
//|   H4  -> M30 (8 candele LTF)                                    |
//|   default -> M1 (fallback sicuro)                                |
//|                                                                  |
//| NOTA: Su M1 questo restituisce M1 (stesso TF) = loop.           |
//| Usare g_dpc_useLTFEntry=false su M1 (gestito da adDPCPresets).   |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES DPCGetLTFTimeframe()
{
   switch(Period())
   {
      case PERIOD_M5:  return PERIOD_M1;
      case PERIOD_M15: return PERIOD_M5;
      case PERIOD_M30: return PERIOD_M5;
      case PERIOD_H1:  return PERIOD_M15;
      case PERIOD_H4:  return PERIOD_M30;
      default:         return PERIOD_M1;
   }
}

//+------------------------------------------------------------------+
//| DPCResetLTF — Reset completo stato LTF                          |
//|                                                                  |
//| Chiamato da: EngineInit(), OnDeinit(), cambio stato              |
//| Postcondizione: finestra chiusa, nessun segnale in attesa        |
//+------------------------------------------------------------------+
void DPCResetLTF()
{
   g_ltfWindowOpen    = false;
   g_ltfDirection     = 0;
   g_ltfBandLevel     = 0.0;
   g_ltfWindowExpiry  = 0;
   g_ltfLastProcessed = 0;
   g_ltfConfirmedBar  = 0;

   AdLogD(LOG_CAT_DPC, "DIAG LTF: RESET — window closed, all state cleared");
}

//+------------------------------------------------------------------+
//| DPCLTFOpenWindow — Open LTF confirmation window                 |
//|                                                                  |
//| Chiamato quando il TF principale genera un segnale DPC.          |
//| Apre una finestra temporale sul LTF per confermare il segnale.   |
//|                                                                  |
//| direction: +1=BUY, -1=SELL                                      |
//| bandLevel: lower band (BUY) o upper band (SELL)                  |
//| barTime: tempo apertura barra[0] corrente                        |
//|                                                                  |
//| Precondizione: g_dpc_useLTFEntry = true                         |
//| Anti-reopen: se barTime == g_ltfConfirmedBar, non riapre        |
//| (previene loop di conferma sulla stessa barra)                   |
//+------------------------------------------------------------------+
void DPCLTFOpenWindow(int direction, double bandLevel, datetime barTime)
{
   if(!g_dpc_useLTFEntry) return;

   // Don't reopen on already-confirmed bar
   if(barTime == g_ltfConfirmedBar) return;

   g_ltfWindowOpen    = true;
   g_ltfDirection     = direction;
   g_ltfBandLevel     = bandLevel;
   g_ltfWindowExpiry  = barTime + PeriodSeconds();
   g_ltfLastProcessed = 0;

   AdLogI(LOG_CAT_DPC, StringFormat("LTF window opened: %s | Band=%s | Expiry=%s | LTF=%s",
          direction > 0 ? "BUY" : "SELL",
          DoubleToString(bandLevel, _Digits),
          TimeToString(g_ltfWindowExpiry, TIME_MINUTES),
          EnumToString(DPCGetLTFTimeframe())));
}

//+------------------------------------------------------------------+
//| DPCLTFCheckConfirmation — Check LTF closed bar for confirmation |
//|                                                                  |
//| Chiamato ad ogni tick quando la finestra e' aperta.              |
//| Legge SOLO barre LTF chiuse (shift=1) per zero repaint.         |
//|                                                                  |
//| CONFERMA BUY:  ltfLow <= bandLevel E ltfClose > bandLevel       |
//|   -> la candela ha toccato la lower band ma ha chiuso sopra      |
//|   -> rejection bullish (il prezzo ha "rimbalzato" sul supporto)  |
//|                                                                  |
//| CONFERMA SELL: ltfHigh >= bandLevel E ltfClose < bandLevel      |
//|   -> la candela ha toccato la upper band ma ha chiuso sotto      |
//|   -> rejection bearish (il prezzo ha "rimbalzato" sulla resist.) |
//|                                                                  |
//| Returns: +1=BUY confirmed, -1=SELL confirmed, 0=no confirmation |
//+------------------------------------------------------------------+
int DPCLTFCheckConfirmation()
{
   if(!g_dpc_useLTFEntry) return 0;
   if(!g_ltfWindowOpen) return 0;

   // Check expiry
   if(TimeCurrent() >= g_ltfWindowExpiry)
   {
      g_ltfWindowOpen = false;
      AdLogI(LOG_CAT_DPC, "LTF window expired — no confirmation");
      return 0;
   }

   ENUM_TIMEFRAMES ltfPeriod = DPCGetLTFTimeframe();

   // Read most recent CLOSED LTF bar (shift=1) — zero repaint
   datetime ltfBarTime = iTime(_Symbol, ltfPeriod, 1);
   if(ltfBarTime <= 0) return 0;

   // Anti-duplicate: process each LTF bar only once
   if(ltfBarTime == g_ltfLastProcessed) return 0;
   g_ltfLastProcessed = ltfBarTime;

   double ltfHigh  = iHigh(_Symbol, ltfPeriod, 1);
   double ltfLow   = iLow(_Symbol, ltfPeriod, 1);
   double ltfClose = iClose(_Symbol, ltfPeriod, 1);

   bool ltfConfirmed = false;

   if(g_ltfDirection == -1)
   {
      // SELL LTF: candle touches upper band AND closes below (rejection bearish)
      ltfConfirmed = (ltfHigh >= g_ltfBandLevel) && (ltfClose < g_ltfBandLevel);
   }
   else if(g_ltfDirection == +1)
   {
      // BUY LTF: candle touches lower band AND closes above (rejection bullish)
      ltfConfirmed = (ltfLow <= g_ltfBandLevel) && (ltfClose > g_ltfBandLevel);
   }

   if(ltfConfirmed)
   {
      g_ltfWindowOpen   = false;
      g_ltfConfirmedBar = iTime(_Symbol, PERIOD_CURRENT, 0);

      AdLogI(LOG_CAT_DPC, StringFormat("LTF CONFIRMED %s | LTF bar: H=%s L=%s C=%s | Band=%s",
             g_ltfDirection > 0 ? "BUY" : "SELL",
             DoubleToString(ltfHigh, _Digits), DoubleToString(ltfLow, _Digits),
             DoubleToString(ltfClose, _Digits), DoubleToString(g_ltfBandLevel, _Digits)));

      return g_ltfDirection;
   }

   // Non-confirmation: log dettaglio perche' la barra LTF non ha confermato
   AdLogD(LOG_CAT_DPC, StringFormat(
      "DIAG LTF no confirm: %s | H=%.5f L=%.5f C=%.5f | band=%.5f | touch=%s close_ok=%s",
      g_ltfDirection > 0 ? "BUY" : "SELL", ltfHigh, ltfLow, ltfClose, g_ltfBandLevel,
      (g_ltfDirection > 0 ? (ltfLow <= g_ltfBandLevel) : (ltfHigh >= g_ltfBandLevel)) ? "YES" : "NO",
      (g_ltfDirection > 0 ? (ltfClose > g_ltfBandLevel) : (ltfClose < g_ltfBandLevel)) ? "YES" : "NO"));

   return 0;
}

//+------------------------------------------------------------------+
//| DPCLTFIsWaiting — Check if LTF window is active                 |
//+------------------------------------------------------------------+
bool DPCLTFIsWaiting()
{
   return g_ltfWindowOpen;
}

//+------------------------------------------------------------------+
//| DPCLTFShouldFilter — Should signal wait for LTF confirmation?   |
//|                                                                  |
//| Determina se il segnale corrente deve attendere conferma LTF.    |
//| Se g_dpc_ltfOnlyTBS=true, solo i segnali TBS vengono filtrati   |
//| (TWS passa direttamente senza conferma LTF).                    |
//|                                                                  |
//| Returns: true se il segnale deve attendere conferma LTF         |
//+------------------------------------------------------------------+
bool DPCLTFShouldFilter(int quality)
{
   if(!g_dpc_useLTFEntry) return false;

   // If LTFOnlyTBS, only filter TBS signals (TWS bypasses LTF)
   if(g_dpc_ltfOnlyTBS && quality != PATTERN_TBS)
      return false;

   return true;
}
