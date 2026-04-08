//+------------------------------------------------------------------+
//|                                        adDPCCooldown.mqh         |
//|           AcquaDulza EA v1.6.1 — DPC SmartCooldown               |
//|                                                                  |
//|  SmartCooldown state machine: previene segnali ridondanti        |
//|  implementando un cooldown intelligente basato su direzione      |
//|  e touch della midline.                                          |
//|                                                                  |
//|  LOGICA TURTLE SOUP:                                             |
//|  Dopo un segnale, il prezzo deve "resettarsi" prima di           |
//|  generare un nuovo segnale nella stessa direzione.               |
//|  Il reset avviene quando il prezzo tocca la midline              |
//|  (ritorno al centro del canale = nuova condizione di equilibrio).|
//|                                                                  |
//|  STATI:                                                          |
//|    1. g_dpcLastDirection_cd == 0 -> NESSUN segnale precedente    |
//|       -> primo segnale sempre accettato                          |
//|    2. Same direction (es. SELL dopo SELL):                        |
//|       a) Se InpRequireMidTouch: richiede midline touch + nSame   |
//|       b) Altrimenti: solo nSame barre di attesa                  |
//|    3. Opposite direction (es. SELL dopo BUY):                    |
//|       -> solo nOpp barre minime di attesa (piu' permissivo)      |
//|                                                                  |
//|  SmartCooldown OFF: cooldown fisso di dcLen barre (legacy)       |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| SmartCooldown State Variables (DPC Engine scoped)                |
//|                                                                  |
//| g_dpcLastSignalBarIdx:   indice barra dell'ultimo segnale        |
//| g_dpcLastDirection_cd:   direzione ultimo segnale (+1/-1/0)      |
//| g_dpcMidlineTouched_cd:  true se midline toccata dopo segnale    |
//| g_dpcMidlineTouchBarIdx: barra in cui midline e' stata toccata   |
//| g_dpcWaitingForMidTouch: true se in attesa del touch midline     |
//+------------------------------------------------------------------+
int      g_dpcLastSignalBarIdx   = 0;
int      g_dpcLastDirection_cd   = 0;      // +1=BUY, -1=SELL, 0=none
bool     g_dpcMidlineTouched_cd  = false;
int      g_dpcMidlineTouchBarIdx = 0;
bool     g_dpcWaitingForMidTouch = false;

//+------------------------------------------------------------------+
//| DPCResetCooldown — Reset completo dello stato cooldown           |
//|                                                                  |
//| Chiamato da: EngineInit(), OnDeinit(), cambio TF                 |
//| Postcondizione: tutti i flag azzerati, primo segnale accettato   |
//+------------------------------------------------------------------+
void DPCResetCooldown()
{
   g_dpcLastSignalBarIdx   = 0;
   g_dpcLastDirection_cd   = 0;
   g_dpcMidlineTouched_cd  = false;
   g_dpcMidlineTouchBarIdx = 0;
   g_dpcWaitingForMidTouch = false;

   AdLogD(LOG_CAT_DPC, "DIAG Cooldown: RESET — all state cleared, next signal will be accepted");
}

//+------------------------------------------------------------------+
//| DPCCheckSmartCooldown_Sell — Cooldown check per segnali SELL     |
//|                                                                  |
//| LOGICA:                                                          |
//| - SmartCooldown OFF: cooldown fisso di dcLen barre               |
//| - First signal (dir=0): sempre accettato                         |
//| - Same dir (SELL dopo SELL): midline touch + nSame barre         |
//| - Opposite (SELL dopo BUY): solo nOpp barre                     |
//|                                                                  |
//| Returns: true se segnale SELL puo' essere accettato              |
//+------------------------------------------------------------------+
bool DPCCheckSmartCooldown_Sell(int currentBarIdx)
{
   int barsFromLast = currentBarIdx - g_dpcLastSignalBarIdx;

   if(!InpUseSmartCooldown)
   {
      bool pass = (barsFromLast >= g_dpc_dcLen);
      AdLogD(LOG_CAT_DPC, StringFormat(
         "DIAG Cooldown SELL [FIXED]: barsFromLast=%d | dcLen=%d | result=%s",
         barsFromLast, g_dpc_dcLen, pass ? "PASS" : "BLOCK"));
      return pass;
   }

   // First signal always accepted
   if(g_dpcLastDirection_cd == 0)
   {
      AdLogD(LOG_CAT_DPC, "DIAG Cooldown SELL: first signal — PASS");
      return true;
   }

   if(g_dpcLastDirection_cd == -1)
   {
      // Same direction (SELL after SELL): require midline touch + N bars
      if(InpRequireMidTouch)
      {
         int barsFromMid = currentBarIdx - g_dpcMidlineTouchBarIdx;
         bool pass = g_dpcMidlineTouched_cd && (barsFromMid >= g_dpc_nSame);
         AdLogD(LOG_CAT_DPC, StringFormat(
            "DIAG Cooldown SELL [SAME+MID]: midTouched=%s | barsFromMid=%d | nSame=%d | result=%s",
            g_dpcMidlineTouched_cd ? "YES" : "NO", barsFromMid, g_dpc_nSame, pass ? "PASS" : "BLOCK"));
         return pass;
      }
      else
      {
         bool pass = (barsFromLast >= g_dpc_nSame);
         AdLogD(LOG_CAT_DPC, StringFormat(
            "DIAG Cooldown SELL [SAME]: barsFromLast=%d | nSame=%d | result=%s",
            barsFromLast, g_dpc_nSame, pass ? "PASS" : "BLOCK"));
         return pass;
      }
   }
   else
   {
      // Opposite direction (SELL after BUY): only minimum bars
      bool pass = (barsFromLast >= g_dpc_nOpp);
      AdLogD(LOG_CAT_DPC, StringFormat(
         "DIAG Cooldown SELL [OPP]: barsFromLast=%d | nOpp=%d | result=%s",
         barsFromLast, g_dpc_nOpp, pass ? "PASS" : "BLOCK"));
      return pass;
   }
}

//+------------------------------------------------------------------+
//| DPCCheckSmartCooldown_Buy — Cooldown check per segnali BUY      |
//|                                                                  |
//| Logica speculare a DPCCheckSmartCooldown_Sell                    |
//| Same dir = BUY dopo BUY, Opposite = BUY dopo SELL               |
//+------------------------------------------------------------------+
bool DPCCheckSmartCooldown_Buy(int currentBarIdx)
{
   int barsFromLast = currentBarIdx - g_dpcLastSignalBarIdx;

   if(!InpUseSmartCooldown)
   {
      bool pass = (barsFromLast >= g_dpc_dcLen);
      AdLogD(LOG_CAT_DPC, StringFormat(
         "DIAG Cooldown BUY [FIXED]: barsFromLast=%d | dcLen=%d | result=%s",
         barsFromLast, g_dpc_dcLen, pass ? "PASS" : "BLOCK"));
      return pass;
   }

   if(g_dpcLastDirection_cd == 0)
   {
      AdLogD(LOG_CAT_DPC, "DIAG Cooldown BUY: first signal — PASS");
      return true;
   }

   if(g_dpcLastDirection_cd == +1)
   {
      // Same direction (BUY after BUY)
      if(InpRequireMidTouch)
      {
         int barsFromMid = currentBarIdx - g_dpcMidlineTouchBarIdx;
         bool pass = g_dpcMidlineTouched_cd && (barsFromMid >= g_dpc_nSame);
         AdLogD(LOG_CAT_DPC, StringFormat(
            "DIAG Cooldown BUY [SAME+MID]: midTouched=%s | barsFromMid=%d | nSame=%d | result=%s",
            g_dpcMidlineTouched_cd ? "YES" : "NO", barsFromMid, g_dpc_nSame, pass ? "PASS" : "BLOCK"));
         return pass;
      }
      else
      {
         bool pass = (barsFromLast >= g_dpc_nSame);
         AdLogD(LOG_CAT_DPC, StringFormat(
            "DIAG Cooldown BUY [SAME]: barsFromLast=%d | nSame=%d | result=%s",
            barsFromLast, g_dpc_nSame, pass ? "PASS" : "BLOCK"));
         return pass;
      }
   }
   else
   {
      // Opposite direction (BUY after SELL)
      bool pass = (barsFromLast >= g_dpc_nOpp);
      AdLogD(LOG_CAT_DPC, StringFormat(
         "DIAG Cooldown BUY [OPP]: barsFromLast=%d | nOpp=%d | result=%s",
         barsFromLast, g_dpc_nOpp, pass ? "PASS" : "BLOCK"));
      return pass;
   }
}

//+------------------------------------------------------------------+
//| DPCUpdateCooldownState — Aggiorna stato dopo segnale confermato  |
//|                                                                  |
//| Chiamato DOPO che un segnale e' stato accettato dal motore.      |
//| Salva indice barra e direzione, resetta flag midline touch       |
//| per iniziare l'attesa del prossimo touch midline.                |
//|                                                                  |
//| Precondizione: segnale gia' validato da tutti i filtri           |
//| Postcondizione: cooldown attivo, waitingForMidTouch=true         |
//+------------------------------------------------------------------+
void DPCUpdateCooldownState(int direction, int currentBarIdx)
{
   int prevDir = g_dpcLastDirection_cd;
   g_dpcLastSignalBarIdx   = currentBarIdx;
   g_dpcLastDirection_cd   = direction;
   g_dpcMidlineTouched_cd  = false;
   g_dpcMidlineTouchBarIdx = 0;
   g_dpcWaitingForMidTouch = true;

   AdLogD(LOG_CAT_DPC, StringFormat(
      "DIAG Cooldown: STATE UPDATE | prevDir=%d | newDir=%d | barIdx=%d | waitingMidTouch=YES",
      prevDir, direction, currentBarIdx));
}

//+------------------------------------------------------------------+
//| DPCCheckMidlineTouch — Rileva touch midline (SmartCooldown)     |
//|                                                                  |
//| LOGICA TURTLE SOUP:                                              |
//| Dopo un segnale BUY, il prezzo deve SALIRE fino alla midline    |
//| (high >= midline) per "resettare" il canale.                     |
//| Dopo un segnale SELL, il prezzo deve SCENDERE fino alla midline |
//| (low <= midline) per "resettare" il canale.                      |
//|                                                                  |
//| Il touch midline sblocca la possibilita' di un nuovo segnale    |
//| nella STESSA direzione (same-direction cooldown).                |
//|                                                                  |
//| Postcondizione: se touch rilevato, midlineTouched=true e         |
//| waitingForMidTouch=false                                         |
//+------------------------------------------------------------------+
void DPCCheckMidlineTouch(int barShift, int currentBarIdx, double midline)
{
   if(!g_dpcWaitingForMidTouch || g_dpcLastDirection_cd == 0)
      return;

   double high1 = iHigh(_Symbol, PERIOD_CURRENT, barShift);
   double low1  = iLow(_Symbol, PERIOD_CURRENT, barShift);

   bool midlineCrossed = false;
   if(g_dpcLastDirection_cd == +1 && high1 >= midline)
      midlineCrossed = true;
   else if(g_dpcLastDirection_cd == -1 && low1 <= midline)
      midlineCrossed = true;

   if(midlineCrossed)
   {
      if(InpUseSmartCooldown)
      {
         g_dpcMidlineTouched_cd  = true;
         g_dpcMidlineTouchBarIdx = currentBarIdx;
      }
      g_dpcWaitingForMidTouch = false;

      AdLogD(LOG_CAT_DPC, StringFormat(
         "DIAG Cooldown: MIDLINE TOUCH | dir=%s | midline=%.5f | H=%.5f L=%.5f | barIdx=%d",
         g_dpcLastDirection_cd > 0 ? "BUY" : "SELL", midline, high1, low1, currentBarIdx));
   }
}
