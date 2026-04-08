//+------------------------------------------------------------------+
//|                                      adEngineInterface.mqh       |
//|           AcquaDulza EA v1.6.1 — Engine Contract                 |
//|                                                                  |
//|  CONTRATTO STABILE — QUESTO FILE NON CAMBIA MAI                  |
//|                                                                  |
//|  Per swappare engine (DPC -> ATR Bands -> LuxAlgo):              |
//|    1. Crea Engine/adNewEngine.mqh (+ sottomoduli)                |
//|    2. Implementa le 3 funzioni del contratto                     |
//|    3. Cambia le righe #include Engine/ in AcquaDulza.mq5         |
//|    ZERO modifiche a: UI, Orders, Persistence, Core               |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| EngineSignal — Unico canale Engine -> Framework                  |
//|                                                                  |
//| Il framework legge SOLO questa struct. Non importa MAI nulla     |
//| da Engine/ direttamente.                                         |
//+------------------------------------------------------------------+
struct EngineSignal
{
   // === Segnale ===
   int      direction;        // +1=BUY, -1=SELL, 0=nessuno
   int      quality;          // 3=TBS (forte), 1=TWS (debole), 0=nessuno
   bool     isNewSignal;      // true solo sulla barra dove scatta (anti-duplicato)

   // === Prezzi ===
   double   entryPrice;       // Punto di ingresso suggerito
   double   tpPrice;          // Take profit suggerito
   double   slPrice;          // Stop loss suggerito
   double   bandLevel;        // Banda toccata (lower=BUY, upper=SELL)

   // === Canale completo (per dashboard e overlay) ===
   double   upperBand;
   double   midline;
   double   lowerBand;
   double   channelWidthPip;

   // === Regime ===
   bool     isFlat;           // true = regime ranging — segnali attivi
   int      ltfConfirm;       // +1/-1/0 — conferma LTF
   datetime barTime;          // Timestamp bar[1]

   // === Engine Extra (dati engine-specifici per display) ===
   // Il framework non interpreta questi campi — li passa al dashboard per display
   double   extraValues[12];  // Valori numerici opzionali (es. ATR, EMA ATR, MA value, config, etc.)
   string   extraLabels[12];  // Labels opzionali per dashboard (es. "EMA ATR", "SmartCD", etc.)
   int      extraCount;       // Quanti extra values sono populati (0-12)

   // === Filter status (per dashboard filter bar) ===
   int      filterStates[8];  // 0=off, 1=pass, -1=fail per ogni filtro
   string   filterNames[8];   // Nomi filtri (es. "Flat", "Width", "MA", etc.)
   int      filterCount;      // Quanti filtri sono registrati (0-8)

   // === Reset ===
   void Reset()
   {
      direction      = 0;
      quality        = 0;
      isNewSignal    = false;
      entryPrice     = 0.0;
      tpPrice        = 0.0;
      slPrice        = 0.0;
      bandLevel      = 0.0;
      upperBand      = 0.0;
      midline        = 0.0;
      lowerBand      = 0.0;
      channelWidthPip= 0.0;
      isFlat         = false;
      ltfConfirm     = 0;
      barTime        = 0;
      extraCount     = 0;
      filterCount    = 0;
      for(int i = 0; i < 12; i++)
      {
         extraValues[i] = 0.0;
         extraLabels[i] = "";
      }
      for(int i = 0; i < 8; i++)
      {
         filterStates[i] = 0;
         filterNames[i]  = "";
      }
   }
};

//+------------------------------------------------------------------+
//| Le 3 funzioni del contratto — implementate dall'engine           |
//|                                                                  |
//| EngineInit()        — Crea handle, inizializza stato             |
//| EngineDeinit()      — Rilascia handle, pulisce                   |
//| EngineCalculate()   — Legge bar[1], popola EngineSignal          |
//|                       Return: true se segnale valido             |
//+------------------------------------------------------------------+
bool  EngineInit();
void  EngineDeinit();
bool  EngineCalculate(EngineSignal &sig);
