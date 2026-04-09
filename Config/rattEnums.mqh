//+------------------------------------------------------------------+
//|                                                rattEnums.mqh     |
//|           Rattapignola EA v1.0.0 — Enumerations & Structs        |
//|                                                                  |
//|  Enum FRAMEWORK (stabili, non cambiano con engine swap)          |
//|  + struct CycleRecord                                            |
//|  + costanti globali                                              |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| === FRAMEWORK ENUMS (engine-agnostici) ===                       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| SYSTEM STATE — Stato globale del sistema                         |
//+------------------------------------------------------------------+
enum ENUM_SYSTEM_STATE
{
   STATE_INIT          = 0,   // Inizializzazione
   STATE_IDLE          = 1,   // Inattivo (premi START)
   STATE_ACTIVE        = 2,   // Operativo
   STATE_PAUSED        = 3,   // In pausa
   STATE_INITIALIZING  = 4,   // Inizializzazione in corso
   STATE_ERROR         = 99   // Errore critico
};

//+------------------------------------------------------------------+
//| CYCLE STATE — Stato di ogni ciclo di trading                     |
//+------------------------------------------------------------------+
enum ENUM_CYCLE_STATE
{
   CYCLE_IDLE,              // Slot disponibile
   CYCLE_PENDING,           // Ordine pendente (STOP/LIMIT)
   CYCLE_ACTIVE,            // Posizione attiva
   CYCLE_HEDGING,           // Entrambe le gambe aperte (Soup + Hedge)
   CYCLE_CLOSED             // Ciclo completato
};

//+------------------------------------------------------------------+
//| RISK MODE — Modalita' calcolo lotto                              |
//+------------------------------------------------------------------+
enum ENUM_RISK_MODE
{
   RISK_FIXED_LOT  = 0,     // Lotto fisso
   RISK_PERCENT    = 1,     // % equity per trade
   RISK_FIXED_CASH = 2      // Cash fisso per trade
};

//+------------------------------------------------------------------+
//| ENTRY MODE — Tipo ordine di ingresso                             |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
{
   ENTRY_MARKET = 0,        // Market (esecuzione immediata)
   ENTRY_LIMIT  = 1,        // Limit (prezzo migliore)
   ENTRY_STOP   = 2         // Stop (breakout/trigger)
};

// [MOD] Rimossa ENUM_SL_MODE (SL_BAND_OPPOSITE=0, SL_ATR_MULTIPLE=1, SL_FIXED_PIPS=2).
// Stop Loss completamente disattivato — gli ordini vengono piazzati senza SL.

//+------------------------------------------------------------------+
//| TP MODE — Modalita' calcolo Take Profit                          |
//+------------------------------------------------------------------+
enum ENUM_TP_MODE
{
   TP_SIGNAL_TO_SIGNAL = 0,  // Signal-to-Signal — chiudi al prossimo segnale opposto (DEFAULT)
   TP_SQUEEZE_EXIT     = 1,  // SqueezeMomentum — half-peak exit
   TP_ATR_MULTIPLE     = 2,  // ATR Multiple — TP = N * ATR dalla entry
   TP_FIXED_PIPS       = 3   // Fixed Pips — TP = N pips fissi dalla entry
};

//+------------------------------------------------------------------+
//| LOG LEVEL — Livello di logging                                   |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
{
   LOG_DEBUG   = -1,        // Debug — diagnostica verbose (DIAG)
   LOG_INFO    = 0,         // Info — standard
   LOG_WARNING = 1,         // Warning — avvisi
   LOG_ERROR   = 2          // Error — errori
};

//+------------------------------------------------------------------+
//| INSTRUMENT CLASS — Classificazione prodotto CFD                  |
//|                                                                  |
//| Ogni classe definisce:                                           |
//|  - pipSize: cosa è "1 pip" per quel prodotto (in unità prezzo)  |
//|  - Preset: spread max, min width, slippage, offset adeguati      |
//|                                                                  |
//| AUTO rileva automaticamente dal nome simbolo.                    |
//| CUSTOM usa i valori input dell'utente senza override.            |
//+------------------------------------------------------------------+
enum ENUM_INSTRUMENT_CLASS
{
   INSTRUMENT_AUTO        = 0,   // Auto-Detect (rileva dal simbolo)
   INSTRUMENT_FOREX       = 1,   // Forex Major (EURUSD, GBPUSD, AUDUSD...)
   INSTRUMENT_FOREX_JPY   = 2,   // Forex JPY (USDJPY, EURJPY...)
   INSTRUMENT_CRYPTO      = 3,   // Crypto BTC (BTCUSD, BTCEUR...)
   INSTRUMENT_CRYPTO_ALT  = 11,  // Crypto Altcoin (ETHUSD, SOLUSD, LTCUSD...)
   INSTRUMENT_INDEX_US    = 4,   // Indici US (US30, US500, NAS100...)
   INSTRUMENT_INDEX_EU    = 5,   // Indici EU (DAX40, FTMIB, STOXX50...)
   INSTRUMENT_GOLD        = 6,   // Gold (XAUUSD)
   INSTRUMENT_SILVER      = 7,   // Silver (XAGUSD)
   INSTRUMENT_OIL         = 8,   // Oil (WTI, BRENT...)
   INSTRUMENT_CUSTOM      = 9,   // Custom (valori manuali)
   INSTRUMENT_STOCK       = 10   // Stock CFD (AAPL, MSFT, TSLA...)
};

//+------------------------------------------------------------------+
//| === ENGINE-SPECIFIC ENUMS (UTBot Adaptive) ===                   |
//| Questi enum cambiano quando si swappa engine                     |
//+------------------------------------------------------------------+

enum ENUM_UTB_TF_PRESET
{
   UTB_TF_AUTO   = 0,    // Auto (basato su Period())
   UTB_TF_MANUAL = 1     // Manuale (usa input diretti)
};

enum ENUM_UTB_SRC_TYPE
{
   UTB_SRC_CLOSE = 0,    // Close — originale QuantNomad
   UTB_SRC_HMA   = 1,    // Hull Moving Average
   UTB_SRC_KAMA  = 2,    // Kaufman Adaptive MA (raccomandato)
   UTB_SRC_JMA   = 3     // Jurik-style MA (quasi zero lag)
};

//+------------------------------------------------------------------+
//| SIGNAL PATTERN — TBS vs TWS                                      |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_TWS  = 1,        // Turtle Wick Soup (solo wick sfonda)
   PATTERN_TBS  = 3         // Turtle Bar Soup (corpo sfonda)
};

//+------------------------------------------------------------------+
//| === STRUCT CycleRecord ===                                       |
//| Record semplificato — with HedgeSmart fields (v1.7.0)            |
//+------------------------------------------------------------------+
struct CycleRecord
{
   int                cycleID;         // ID univoco del ciclo
   ENUM_CYCLE_STATE   state;
   int                direction;       // +1=BUY, -1=SELL
   int                quality;         // 3=TBS, 1=TWS
   ulong              ticket;          // Ticket ordine/posizione Soup
   double             entryPrice;
   double             tpPrice;
   double             slPrice;
   double             lotSize;
   datetime           signalTime;      // Tempo del segnale
   datetime           placedTime;      // Tempo piazzamento ordine
   double             profit;          // P&L (floating o realized)

   // === HEDGE SMART FIELDS (v1.7.0 — non invasivo) ===
   ulong              hsTicket;           // Ticket ordine/posizione HS (0 = non attivo)
   double             hsTriggerPrice;     // Prezzo trigger al momento del piazzamento
   double             hsTpRefLevel;       // Livello TP riferimento visivo (non inviato al broker)
   double             hsLotSize;          // Lotto HS
   bool               hsPending;          // true = ordine HS pendente sul broker
   bool               hsActive;           // true = posizione HS riempita e aperta
   datetime           hsFillTime;         // Timestamp fill (per calcolo barre attive anti-whipsaw)
   string             hsLineName;         // Nome oggetto grafico linea trigger
   double             hsPL;               // P&L realizzato HS (aggiornato alla chiusura)

   // === HEDGE SMART v1.7.2 — Step1 BE + Step2 TP ===
   double             hsFillPrice;        // Prezzo fill reale HS (può differire da hsTriggerPrice per slippage)
   double             hsMidlineAtSignal;  // Midline al momento del segnale → usata come SL iniziale HS
   bool               hsBESet;            // true dopo che Step1 BE è stato impostato
   bool               hsStep2Reached;     // true dopo che Step2 tpRefLevel è stato raggiunto
};

//+------------------------------------------------------------------+
//| COSTANTI GLOBALI                                                 |
//+------------------------------------------------------------------+
const int    MAX_CYCLES         = 10;      // Max cicli contemporanei (array size)
const string EA_VERSION         = "1.2.0";
