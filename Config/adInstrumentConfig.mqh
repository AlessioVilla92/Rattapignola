//+------------------------------------------------------------------+
//|                                     adInstrumentConfig.mqh        |
//|           AcquaDulza EA v1.7.1 — Instrument Classification        |
//|                                                                    |
//|  Sistema multi-prodotto CFD: rileva la classe dello strumento      |
//|  e auto-scala tutti i parametri pip-dipendenti.                    |
//|                                                                    |
//|  FLUSSO:                                                           |
//|    1. DetectInstrumentClass() — identifica dal nome simbolo        |
//|    2. ApplyInstrumentPresets() — setta g_pipSize + parametri       |
//|    3. InstrumentPresetsInit() — entry point chiamato da OnInit()   |
//|                                                                    |
//|  CLASSI SUPPORTATE:                                                |
//|    FOREX (5d), FOREX_JPY (3d), CRYPTO, INDEX_US, INDEX_EU,         |
//|    GOLD, SILVER, OIL, STOCK, CUSTOM                                |
//|                                                                    |
//|  TABELLA PRESET:                                                   |
//|  Classe     | pipSize | maxSprd | minW | slip | stopOff | limOff  |
//|  FOREX      | 10*pt   |   3.0   |  8.0 |   3  |   2.5   |  2.0   |
//|  FOREX_JPY  | 10*pt   |   3.0   |  8.0 |   3  |   2.5   |  2.0   |
//|  CRYPTO BTC | 1.0     |  80.0   |200.0 |  50  |  15.0   | 10.0   |
//|  CRYPTO_ALT | 1.0     |  30.0   | 50.0 |  50  |   5.0   |  3.0   |
//|  INDEX_US   | 1.0     |   5.0   | 50.0 |  10  |   5.0   |  3.0   |
//|  INDEX_EU   | 1.0     |  15.0   | 40.0 |  10  |   5.0   |  3.0   |
//|  GOLD       | 0.10    |   5.0   |  5.0 |  10  |   2.0   |  1.5   |
//|  SILVER     | 0.010   |   5.0   |  3.0 |  10  |   2.0   |  1.5   |
//|  OIL        | 0.10    |   5.0   | 15.0 |   5  |   3.0   |  2.0   |
//|  STOCK      | pt      |  15.0   |  x3  |   5  |   5.0   |  3.0   |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| DetectInstrumentClass — Auto-detect dal nome simbolo              |
//|                                                                    |
//| Analizza _Symbol per pattern noti (BTC, XAU, US30, DAX...)        |
//| Fallback: usa g_symbolDigits per distinguere forex 5d/3d          |
//| Ritorna la classe rilevata                                         |
//+------------------------------------------------------------------+
ENUM_INSTRUMENT_CLASS DetectInstrumentClass()
{
   string sym = _Symbol;
   StringToUpper(sym);  // Normalizza a maiuscolo per matching

   AdLogD(LOG_CAT_INIT, StringFormat(
      "DIAG InstrumentDetect: sym=%s | digits=%d | point=%.8f",
      sym, g_symbolDigits, g_symbolPoint));

   //--- Crypto BTC: widthFactor=25 (canali $500-5000)
   //    PRIORITA' ALTA: crypto prima di JPY per evitare match "BTCJPY" come forex JPY
   if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "XBT") >= 0)
      return INSTRUMENT_CRYPTO;

   //--- Crypto Altcoin: widthFactor=5 (canali piu' stretti di BTC)
   //    ETH ($1800), SOL ($150), LTC ($100), XRP ($0.50), ADA, DOGE, BNB
   if(StringFind(sym, "ETH") >= 0 || StringFind(sym, "LTC") >= 0 ||
      StringFind(sym, "XRP") >= 0 || StringFind(sym, "SOL") >= 0 ||
      StringFind(sym, "ADA") >= 0 || StringFind(sym, "DOGE") >= 0 ||
      StringFind(sym, "BNB") >= 0)
      return INSTRUMENT_CRYPTO_ALT;

   //--- Gold: XAU, GOLD
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
      return INSTRUMENT_GOLD;

   //--- Silver: XAG, SILVER
   if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
      return INSTRUMENT_SILVER;

   //--- Oil: WTI, BRENT, USOIL, UKOIL, CL, CRUDE
   if(StringFind(sym, "WTI") >= 0 || StringFind(sym, "BRENT") >= 0 ||
      StringFind(sym, "USOIL") >= 0 || StringFind(sym, "UKOIL") >= 0 ||
      StringFind(sym, "CRUDE") >= 0)
      return INSTRUMENT_OIL;
   // CL solo se all'inizio (evita match su "EURCL..." inesistenti)
   if(StringFind(sym, "CL") == 0)
      return INSTRUMENT_OIL;

   //--- Indici US: US30, DJ30, US500, SP500, SPX, NAS100, US100, NDX, USTEC
   if(StringFind(sym, "US30") >= 0 || StringFind(sym, "DJ30") >= 0 ||
      StringFind(sym, "US500") >= 0 || StringFind(sym, "SP500") >= 0 ||
      StringFind(sym, "SPX") >= 0 || StringFind(sym, "NAS") >= 0 ||
      StringFind(sym, "US100") >= 0 || StringFind(sym, "NDX") >= 0 ||
      StringFind(sym, "USTEC") >= 0)
      return INSTRUMENT_INDEX_US;

   //--- Indici EU: DAX, DE30, DE40, GER30, GER40, FTMIB, IT40, STOXX, EU50, UK100, FTSE, CAC, AEX
   if(StringFind(sym, "DAX") >= 0 || StringFind(sym, "DE30") >= 0 ||
      StringFind(sym, "DE40") >= 0 || StringFind(sym, "GER") >= 0 ||
      StringFind(sym, "FTMIB") >= 0 ||
      StringFind(sym, "IT40") >= 0 || StringFind(sym, "STOXX") >= 0 ||
      StringFind(sym, "EU50") >= 0 || StringFind(sym, "UK100") >= 0 ||
      StringFind(sym, "FTSE") >= 0 || StringFind(sym, "CAC") >= 0)
      return INSTRUMENT_INDEX_EU;

   //--- Forex JPY: qualsiasi coppia con JPY (3 digits tipicamente)
   if(StringFind(sym, "JPY") >= 0)
      return INSTRUMENT_FOREX_JPY;

   //--- Stock CFD: rilevamento via MT5 API (dopo fallimento pattern matching)
   //    Se il simbolo non e' forex/crypto/gold/silver/oil/indice ma e' CFD → probabilmente stock
   //    Filtro digits<=2: esclude forex CFD (5 digits) che alcuni broker catalogano come CFD
   long calcMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE);
   AdLogD(LOG_CAT_INIT, StringFormat(
      "DIAG InstrumentDetect: no pattern match — checking MT5 API | calcMode=%d | digits=%d",
      calcMode, g_symbolDigits));

   if((calcMode == SYMBOL_CALC_MODE_CFD ||
       calcMode == SYMBOL_CALC_MODE_CFDLEVERAGE ||
       calcMode == SYMBOL_CALC_MODE_EXCH_STOCKS) &&
      g_symbolDigits <= 2)
      return INSTRUMENT_STOCK;

   //--- Default: Forex Major (nessun pattern o API match)
   AdLogD(LOG_CAT_INIT, "DIAG InstrumentDetect: fallback to FOREX");
   return INSTRUMENT_FOREX;
}

//+------------------------------------------------------------------+
//| GetInstrumentClassName — Nome leggibile per log e dashboard       |
//+------------------------------------------------------------------+
string GetInstrumentClassName(ENUM_INSTRUMENT_CLASS cls)
{
   switch(cls)
   {
      case INSTRUMENT_AUTO:      return "Auto-Detect";
      case INSTRUMENT_FOREX:     return "Forex Major";
      case INSTRUMENT_FOREX_JPY: return "Forex JPY";
      case INSTRUMENT_CRYPTO:    return "Crypto BTC";
      case INSTRUMENT_INDEX_US:  return "Index US";
      case INSTRUMENT_INDEX_EU:  return "Index EU";
      case INSTRUMENT_GOLD:      return "Gold";
      case INSTRUMENT_SILVER:    return "Silver";
      case INSTRUMENT_OIL:       return "Oil";
      case INSTRUMENT_CUSTOM:    return "Custom";
      case INSTRUMENT_STOCK:     return "Stock CFD";
      case INSTRUMENT_CRYPTO_ALT: return "Crypto Altcoin";
   }
   return "Unknown";
}

//+------------------------------------------------------------------+
//| ApplyInstrumentPresets — Setta g_pipSize e parametri effettivi    |
//|                                                                    |
//| Ogni classe ha il suo preset calibrato per:                        |
//|  - g_pipSize: definizione di "1 pip" in unità prezzo               |
//|  - g_inst_maxSpread: spread massimo tollerato (in pip)             |
//|  - g_inst_slippage: tolleranza slippage (in points MT5)            |
//|  - g_inst_stopOffset: offset stop order dalla banda (in pip)       |
//|  - g_inst_limitOffset: offset limit order dalla entry (in pip)     |
//|  - g_inst_widthFactor: moltiplicatore per TF preset minWidth       |
//|                                                                    |
//| CUSTOM: usa i valori input dell'utente senza override              |
//+------------------------------------------------------------------+
void ApplyInstrumentPresets(ENUM_INSTRUMENT_CLASS cls)
{
   switch(cls)
   {
      //--- FOREX MAJOR (EURUSD, GBPUSD, AUDUSD, NZDUSD, USDCHF, USDCAD...)
      //    5 digits: 1 pip = 10 points = 0.0001
      case INSTRUMENT_FOREX:
         g_pipSize          = 10.0 * g_symbolPoint;   // 0.00001 * 10 = 0.0001
         g_inst_maxSpread   = 3.0;      // Max 3 pip spread

         g_inst_slippage    = 3;        // 3 points = 0.3 pip
         g_inst_stopOffset  = 2.5;      // 2.5 pip offset
         g_inst_limitOffset = 2.0;      // 2.0 pip offset
         g_inst_widthFactor = 1.0;      // Baseline (TF preset × 1.0)
         break;

      //--- FOREX JPY (USDJPY, EURJPY, GBPJPY, AUDJPY...)
      //    3 digits: 1 pip = 10 points = 0.01
      case INSTRUMENT_FOREX_JPY:
         g_pipSize          = 10.0 * g_symbolPoint;   // 0.001 * 10 = 0.01
         g_inst_maxSpread   = 3.0;      // Max 3 pip spread

         g_inst_slippage    = 3;        // 3 points
         g_inst_stopOffset  = 2.5;      // 2.5 pip offset
         g_inst_limitOffset = 2.0;      // 2.0 pip offset
         g_inst_widthFactor = 1.0;      // Baseline
         break;

      //--- CRYPTO BTC (BTCUSD, BTCEUR...)
      //    1-2 digits: 1 pip = $1.00
      //    Spread tipico BTC: $30-80, canali: $500-5000
      case INSTRUMENT_CRYPTO:
         g_pipSize          = 1.0;       // 1 pip = $1.00
         g_inst_maxSpread   = 80.0;      // Max $80 spread

         g_inst_slippage    = 50;        // 50 points = $0.50 (2 digits)
         g_inst_stopOffset  = 15.0;      // $15 offset
         g_inst_limitOffset = 10.0;      // $10 offset
         g_inst_widthFactor = 25.0;      // TF preset × 25 (7pip forex → 175$ crypto)
         break;

      //--- CRYPTO ALTCOIN (ETHUSD, SOLUSD, LTCUSD, XRPUSD, ADAUSD...)
      //    1-2 digits: 1 pip = $1.00
      //    Canali ETH: $30-200, SOL: $3-25 — molto piu' stretti di BTC
      case INSTRUMENT_CRYPTO_ALT:
         g_pipSize          = 1.0;       // 1 pip = $1.00 (come BTC)
         g_inst_maxSpread   = 30.0;      // Max $30 spread (ETH spread piu' basso di BTC)

         g_inst_slippage    = 50;        // 50 points = $0.50
         g_inst_stopOffset  = 5.0;       // $5 offset (meno volatile di BTC)
         g_inst_limitOffset = 3.0;       // $3 offset
         g_inst_widthFactor = 5.0;       // TF preset × 5 (10pip forex → 50$ altcoin)
         break;

      //--- INDICI US (US30, US500, NAS100...)
      //    1-2 digits: 1 pip = 1 punto indice
      //    Spread tipico US30: 2-5 pts, canali: 100-500 pts
      case INSTRUMENT_INDEX_US:
         g_pipSize          = 1.0;       // 1 pip = 1 punto indice
         g_inst_maxSpread   = 5.0;       // Max 5 pts spread

         g_inst_slippage    = 10;        // 10 points
         g_inst_stopOffset  = 5.0;       // 5 pts offset
         g_inst_limitOffset = 3.0;       // 3 pts offset
         g_inst_widthFactor = 6.0;       // TF preset × 6 (7pip forex → 42pts indice)
         break;

      //--- INDICI EU (DAX40, FTMIB, STOXX50, CAC40...)
      //    1-2 digits: 1 pip = 1 punto indice
      //    Spread tipico DAX: 1-3 pts, FTMIB: 5-15 pts
      case INSTRUMENT_INDEX_EU:
         g_pipSize          = 1.0;       // 1 pip = 1 punto indice
         g_inst_maxSpread   = 15.0;      // Max 15 pts spread (FTMIB ha spread 5-15)

         g_inst_slippage    = 10;        // 10 points
         g_inst_stopOffset  = 5.0;       // 5 pts offset
         g_inst_limitOffset = 3.0;       // 3 pts offset
         g_inst_widthFactor = 5.0;       // TF preset × 5
         break;

      //--- GOLD (XAUUSD)
      //    2 digits: 1 pip = $0.10
      //    Spread tipico: $0.20-0.50, canali: $5-30
      case INSTRUMENT_GOLD:
         g_pipSize          = 0.10;      // 1 pip = $0.10
         g_inst_maxSpread   = 5.0;       // Max $0.50 spread (5 × 0.10)

         g_inst_slippage    = 10;        // 10 points = $0.10
         g_inst_stopOffset  = 2.0;       // $0.20 offset
         g_inst_limitOffset = 1.5;       // $0.15 offset
         g_inst_widthFactor = 1.0;       // Gold simile a forex come scala
         break;

      //--- SILVER (XAGUSD)
      //    3-4 digits: 1 pip = $0.010
      //    Spread tipico: $0.02-0.05, canali: $0.30-2.00
      case INSTRUMENT_SILVER:
         g_pipSize          = 0.010;     // 1 pip = $0.010
         g_inst_maxSpread   = 5.0;       // Max $0.05 spread

         g_inst_slippage    = 10;        // 10 points
         g_inst_stopOffset  = 2.0;       // $0.02 offset
         g_inst_limitOffset = 1.5;       // $0.015 offset
         g_inst_widthFactor = 1.0;       // Silver simile a forex
         break;

      //--- OIL (WTI, BRENT)
      //    2 digits: 1 pip = $0.10
      //    Spread tipico: $0.03-0.05, canali: $1-5
      case INSTRUMENT_OIL:
         g_pipSize          = 0.10;      // 1 pip = $0.10
         g_inst_maxSpread   = 5.0;       // Max $0.50 spread

         g_inst_slippage    = 5;         // 5 points = $0.05
         g_inst_stopOffset  = 3.0;       // $0.30 offset
         g_inst_limitOffset = 2.0;       // $0.20 offset
         g_inst_widthFactor = 2.0;       // TF preset × 2
         break;

      //--- STOCK CFD (AAPL, MSFT, TSLA, AMZN, NVDA...)
      //    Tipicamente 2 digits: 1 pip = $0.01
      //    Spread tipico: $0.02-$0.15, canali: $2-$20
      case INSTRUMENT_STOCK:
         g_pipSize          = g_symbolPoint;    // 0.01 = 1 cent
         g_inst_maxSpread   = 15.0;     // Max $0.15 spread (15 × 0.01)

         g_inst_slippage    = 5;        // 5 points = $0.05
         g_inst_stopOffset  = 5.0;      // $0.05 offset
         g_inst_limitOffset = 3.0;      // $0.03 offset
         g_inst_widthFactor = 3.0;      // TF preset × 3 (10pip forex → 30 cent stock)
         break;

      //--- CUSTOM: usa i valori input dell'utente senza override
      //    La conversione pip funziona comunque tramite g_pipSize
      case INSTRUMENT_CUSTOM:
         // pipSize: usa la logica forex classica come fallback
         if(g_symbolDigits == 3 || g_symbolDigits == 5)
            g_pipSize = 10.0 * g_symbolPoint;
         else
            g_pipSize = g_symbolPoint;
         // Parametri: mantieni quelli dell'utente
         g_inst_maxSpread   = MaxSpreadPips;
         // g_inst_minWidth rimosso — minWidth effettivo è g_dpc_minWidth (scalato da widthFactor)
         g_inst_slippage    = Slippage;
         g_inst_stopOffset  = StopOffsetPips;
         g_inst_limitOffset = LimitOffsetPips;
         g_inst_widthFactor = 1.0;
         break;

      default:
         // Fallback sicuro = Forex
         g_pipSize          = 10.0 * g_symbolPoint;
         g_inst_maxSpread   = MaxSpreadPips;
         // g_inst_minWidth rimosso — minWidth effettivo è g_dpc_minWidth (scalato da widthFactor)
         g_inst_slippage    = Slippage;
         g_inst_stopOffset  = StopOffsetPips;
         g_inst_limitOffset = LimitOffsetPips;
         g_inst_widthFactor = 1.0;
         break;
   }
}

//+------------------------------------------------------------------+
//| InstrumentPresetsInit — Entry point: chiamato da OnInit()         |
//|                                                                    |
//| DEVE essere chiamato DOPO LoadBrokerSpecifications() (servono     |
//| g_symbolPoint e g_symbolDigits) e PRIMA di SetupTradeObject()     |
//| (che usa g_inst_slippage).                                         |
//|                                                                    |
//| Flusso:                                                            |
//|  1. Se AUTO → DetectInstrumentClass() dal nome simbolo             |
//|  2. ApplyInstrumentPresets() → setta g_pipSize + g_inst_*          |
//|  3. Sanity check su g_pipSize                                      |
//|  4. Log dettagliato della configurazione                           |
//+------------------------------------------------------------------+
bool InstrumentPresetsInit()
{
   //--- Step 1: Determina la classe strumento
   if(InstrumentClass == INSTRUMENT_AUTO)
      g_instrumentClass = DetectInstrumentClass();
   else
      g_instrumentClass = InstrumentClass;

   //--- Step 2: Applica i preset per la classe rilevata
   ApplyInstrumentPresets(g_instrumentClass);

   //--- Step 3: Sanity check su g_pipSize
   if(g_pipSize <= 0)
   {
      AdLogE(LOG_CAT_INIT, StringFormat("INSTRUMENT ERROR: g_pipSize=%.8f invalid for %s — forcing forex default",
         g_pipSize, _Symbol));
      g_pipSize = 10.0 * g_symbolPoint;
   }

   //--- Step 4: Log configurazione completa
   string detectMethod = (InstrumentClass == INSTRUMENT_AUTO) ? "AUTO-DETECTED" : "MANUAL";
   AdLogI(LOG_CAT_INIT, StringFormat(
      "INSTRUMENT: %s (%s from %s) — pipSize=%.5f | maxSpread=%.1f | slip=%d | stopOff=%.1f | limOff=%.1f | widthFact=%.1f",
      GetInstrumentClassName(g_instrumentClass),
      detectMethod, _Symbol,
      g_pipSize, g_inst_maxSpread,
      g_inst_slippage, g_inst_stopOffset, g_inst_limitOffset, g_inst_widthFactor));

   return true;
}
