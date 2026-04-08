//+------------------------------------------------------------------+
//|                                          rattDashboard.mqh       |
//|           Rattapignola EA v1.0.0 — Dashboard Display             |
//|                                                                  |
//|  Firefly theme dashboard — Pragmatic approach.                   |
//|                                                                  |
//|  LAYOUT VERTICALE (top -> bottom, ogni pannello ha altezza fissa):|
//|    1. Header     (36px) — Logo RATTAPIGNOLA + versione + ENGINE  |
//|    2. TitleBar   (32px) — Pair + prezzo + spread + TF + state    |
//|    3. SysStatus  (80px) — 3x3 grid: session/uptime/margin/etc.  |
//|    4. EnginePanel(88px) — Trail + Source + ER + KeyValue + ATR   |
//|    5. FilterBar  (22px) — Pills colorate per ogni filtro attivo  |
//|    6. LastSignals(76px) — Ultimi 3 segnali con direzione + TBS   |
//|    7. ActiveCycles(100px)— Fino a 4 cicli con P&L floating      |
//|    8. PLSession  (90px) — P&L, WinRate, MaxDD, Float, Daily     |
//|    9. Controls   (52px) — Titolo + ora + button feedback         |
//|   10. StatusBar  (20px) — Barra riassuntiva EA state + features  |
//|                                                                  |
//|  SIDE PANEL (a destra del dashboard, offset +10px):              |
//|    - Engine Monitor (13 righe): UTBot Engine, ATR, ER, etc.     |
//|    - Signal Feed (6 righe): ultime azioni EA in tempo reale      |
//|                                                                  |
//|  CORNICE PERIMETRALE (stile SugamaraPivot):                      |
//|    - Sfondo scuro (RATT_BG_DEEP) creato PRIMO (sotto tutto)      |
//|    - 4 rettangoli solidi (T/B/L/R) creati ULTIMI (sopra tutto)   |
//|    - Titoli decorativi "────── RATTAPIGNOLA ──────" top/bottom    |
//|                                                                  |
//|  Z-ORDER e VISUAL STACKING:                                      |
//|    - RATT_Z_RECT (rattVisualTheme): Z-order per rettangoli      |
//|    - RATT_Z_LABEL: Z-order per etichette testo (sopra rettangoli)|
//|    - Frame border Z = RATT_Z_LABEL + 1000: sempre in primo piano |
//|    - BACK=false su tutti: dashboard SOPRA il chart (foreground)   |
//|    - Overlay (rattChannelOverlay) usa BACK=true: DIETRO le candele|
//|                                                                  |
//|  THEME COLORS (da rattVisualTheme.mqh):                          |
//|    RATT_FIREFLY      — giallo lucciola C'255,220,50' (accento)   |
//|    RATT_FIREFLY_DIM  — giallo lucciola smorzato (titoli second.) |
//|    RATT_BUY/RATT_SELL — lime/rosso (P&L positivo/negativo)       |
//|    RATT_AMBER        — giallo/ambra (warning, TWS, pending)      |
//|    RATT_HEDGE        — fucsia (stato HEDG e H1)                  |
//|    RATT_BG_DEEP      — blu scuro profondo (sfondo pannelli)      |
//|    RATT_PANEL_BG     — grigio scuro (sfondo sezioni alternate)   |
//|    RATT_TEXT_HI/MID/LO/MUTED — gerarchia testo (bianco->grigio)  |
//|                                                                  |
//|  v1.0.0: Integrazione hedge nel dashboard (6 punti)              |
//|    DrawActiveCycles — stato "HEDG" fucsia + P&L combinato        |
//|    DrawPLSession    — FLOAT include CYCLE_HEDGING (entrambe)     |
//|    DrawFilterBar    — pill [+Hedge]/[_Hedge] in fucsia           |
//|    DrawStatusBar    — Hedge:ON/OFF nella barra inferiore         |
//|    UpdateSidePanel  — riga 13 "Hedge" con conteggio attivi       |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| DashRectangle — Crea/aggiorna un pannello rettangolare           |
//+------------------------------------------------------------------+
void DashRectangle(string name, int x, int y, int width, int height,
                   color bgClr, color borderClr)
{
   string objName = "RATT_" + name;

   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_ZORDER, RATT_Z_RECT);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
   }

   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, borderClr);
}

//+------------------------------------------------------------------+
//| DashLabel — Crea/aggiorna un'etichetta testo                     |
//+------------------------------------------------------------------+
void DashLabel(string id, int x, int y, string text, color clr,
               int fontSize = RATT_FONT_SIZE_BODY, string fontName = "")
{
   if(fontName == "") fontName = RATT_FONT_BODY;
   string name = "RATT_DASH_" + id;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, RATT_Z_LABEL);
   }

   ObjectSetString(0, name, OBJPROP_FONT, fontName);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text == "" ? " " : text);
}

// ApplyChartTheme() definita in rattVisualTheme.mqh

//+------------------------------------------------------------------+
//| DrawHeaderRow — Title header: RATTAPIGNOLA + version + ENGINE    |
//+------------------------------------------------------------------+
void DrawHeaderRow(int x, int y, int w)
{
   DashRectangle("HDR_PANEL", x, y, w, RATT_H_HEADER, RATT_BG_SECTION_A, RATT_FIREFLY_DIM);

   // RATTAPIGNOLA — grande, font title
   DashLabel("HDR_LOGO", x + RATT_PAD, y + 7, "RATTAPIGNOLA", RATT_FIREFLY, 14, RATT_FONT_TITLE);

   // Versione
   DashLabel("HDR_VER", x + RATT_PAD + 175, y + 12, "v" + EA_VERSION, RATT_TEXT_MUTED, 9);

   // ENGINE: UTBot Adaptive
   DashLabel("HDR_ENG", x + w - 280, y + 12, "ENGINE: UTBot Adaptive", RATT_FIREFLY_DIM, 9, RATT_FONT_SECTION);
}

//+------------------------------------------------------------------+
//| DrawTitleBar — Pair + Price + Spread + State (32px)             |
//+------------------------------------------------------------------+
void DrawTitleBar(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("TITLE_PANEL", x, y, w, RATT_H_TOPBAR, RATT_BG_SECTION_A, RATT_PANEL_BORDER);

   // Pair + price + spread
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DashLabel("H_PAIR", x + pad, y + 8, _Symbol, RATT_TEXT_HI, 11, RATT_FONT_SECTION);
   DashLabel("H_PRICE", x + pad + 90, y + 8, DoubleToString(bid, _Digits), RATT_FIREFLY, 11);
   DashLabel("H_SPREAD", x + pad + 200, y + 10, StringFormat("Spread:%.1f", GetSpreadPips()), RATT_TEXT_MUTED, 8);

   // TF preset badge
   string tfBadge = "UTBot v2.01";
   if(InpUTBPreset == UTB_TF_AUTO)
      tfBadge += " " + EnumToString(Period());
   DashLabel("H_TF", x + pad + 310, y + 10, tfBadge, RATT_FIREFLY_DIM, 8);

   // State badge with dot
   string stateStr = "IDLE"; color stateClr = RATT_TEXT_MUTED;
   switch(g_systemState)
   {
      case STATE_ACTIVE:       stateStr = "ACTIVE";       stateClr = RATT_BUY; break;
      case STATE_PAUSED:       stateStr = "PAUSED";       stateClr = RATT_AMBER; break;
      case STATE_ERROR:        stateStr = "ERROR";        stateClr = RATT_SELL; break;
      case STATE_INITIALIZING: stateStr = "INIT...";      stateClr = RATT_FIREFLY; break;
   }
   DashLabel("H_STATE", x + w - 100, y + 8, ShortToString(0x25CF) + " " + stateStr, stateClr, 11, RATT_FONT_SECTION);
}

//+------------------------------------------------------------------+
//| DrawSystemStatus — 2x3 grid: Session|Uptime|Spread|ATR|Bal|Eq  |
//+------------------------------------------------------------------+
void DrawSystemStatus(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("SYS_PANEL", x, y, w, RATT_H_SYSSTATUS, RATT_PANEL_BG, RATT_PANEL_BORDER);
   DashLabel("SYS_TITLE", x + pad, y + 4, "SYSTEM STATUS", RATT_FIREFLY_DIM, 9, RATT_FONT_SECTION);

   // Grid: 3 rows x 2 columns, labels + values
   int col1 = x + pad;
   int col3 = x + pad + 220;
   int col5 = x + pad + 440;
   int row1 = y + 22;
   int row2 = y + 40;
   int row3 = y + 58;

   // Row 1: Session | Uptime | Free Margin
   DashLabel("SY_L1", col1, row1, "SESSION", RATT_TEXT_LO, 7);
   DashLabel("SY_V1", col1, row1 + 10, GetSessionStatus(), RATT_TEXT_HI, 10, RATT_FONT_SECTION);

   DashLabel("SY_L2", col3, row1, "UPTIME", RATT_TEXT_LO, 7);
   int upSec = (int)(TimeCurrent() - g_systemStartTime);
   int upH = upSec / 3600; int upM = (upSec % 3600) / 60; int upS = upSec % 60;
   DashLabel("SY_V2", col3, row1 + 10,
             StringFormat("%02d:%02d:%02d", upH, upM, upS), RATT_TEXT_HI, 10);

   double freeMargin = GetFreeMargin();
   double marginLvl  = GetMarginLevel();
   DashLabel("SY_L3", col5, row1, "FREE MARGIN", RATT_TEXT_LO, 7);
   DashLabel("SY_V3", col5, row1 + 10, FormatMoney(freeMargin),
             marginLvl > 500 ? RATT_BUY : (marginLvl > 200 ? RATT_AMBER : RATT_SELL), 10);

   // Row 2: Spread | ATR | Balance
   double spread = GetSpreadPips();
   DashLabel("SY_L4", col1, row2, "SPREAD", RATT_TEXT_LO, 7);
   DashLabel("SY_V4", col1, row2 + 10,
             StringFormat("%.1f pip", spread),
             spread > g_inst_maxSpread ? RATT_SELL : RATT_BUY, 10);

   DashLabel("SY_L5", col3, row2, "ATR(14)", RATT_TEXT_LO, 7);
   DashLabel("SY_V5", col3, row2 + 10,
             StringFormat("%.1f pip", g_atrCache.valuePips), RATT_FIREFLY, 10);

   DashLabel("SY_L6", col5, row2, "BALANCE", RATT_TEXT_LO, 7);
   DashLabel("SY_V6", col5, row2 + 10, FormatMoney(GetBalance()), RATT_TEXT_HI, 10);

   // Row 3: Equity | Margin Level
   double equity = GetEquity();
   double balance = GetBalance();
   DashLabel("SY_L7", col1, row3, "EQUITY", RATT_TEXT_LO, 7);
   DashLabel("SY_V7", col1, row3 + 10, FormatMoney(equity),
             equity >= balance ? RATT_BUY : RATT_SELL, 10, RATT_FONT_SECTION);

   DashLabel("SY_L8", col3, row3, "MARGIN LVL", RATT_TEXT_LO, 7);
   DashLabel("SY_V8", col3, row3 + 10,
             marginLvl > 0 ? StringFormat("%.0f%%", marginLvl) : "---",
             marginLvl > 500 ? RATT_BUY : (marginLvl > 200 ? RATT_AMBER : RATT_SELL), 10);
}

//+------------------------------------------------------------------+
//| DrawEnginePanel — UTBot Engine: Trail + Source + ER + Config     |
//+------------------------------------------------------------------+
void DrawEnginePanel(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("ENG_PANEL", x, y, w, RATT_H_ENGINE, RATT_BG_DEEP, RATT_PANEL_BORDER);
   DashLabel("ENG_TITLE", x + pad, y + 6, "UTBOT ENGINE", RATT_FIREFLY, 10, RATT_FONT_SECTION);

   bool ready = g_engineReady;
   DashLabel("ENG_STATUS", x + w - 100, y + 6,
             ready ? "ACTIVE" : "INIT...", ready ? RATT_BUY : RATT_AMBER, 10, RATT_FONT_SECTION);

   // TP Mode label — centrato tra titolo e status
   string tpStr = "";
   switch(TPMode)
   {
      case TP_SIGNAL_TO_SIGNAL: tpStr = "TP: S2S FLIP";                      break;
      case TP_SQUEEZE_EXIT:     tpStr = "TP: SQZ EXIT";                      break;
      case TP_ATR_MULTIPLE:     tpStr = "TP: ATR" + ShortToString(0x00D7) + StringFormat("%.1f", TPValue); break;
      case TP_FIXED_PIPS:       tpStr = StringFormat("TP: %.0f pip", TPValue);  break;
   }
   DashLabel("ENG_TP", x + w / 2, y + 6, tpStr, RATT_AMBER, 9, RATT_FONT_SECTION);

   if(g_lastSignal.upperBand > 0)
   {
      // Trail Stop value
      DashLabel("ENG_UPPER", x + pad, y + 26,
                StringFormat("Trail  %s", DoubleToString(g_lastSignal.upperBand, _Digits)),
                RATT_SELL, 9);
      // Source value
      DashLabel("ENG_MID", x + pad + 180, y + 26,
                StringFormat("Source %s", DoubleToString(g_lastSignal.midline, _Digits)),
                RATT_FIREFLY, 9);
      // ER value
      DashLabel("ENG_LOWER", x + pad + 360, y + 26,
                StringFormat("ER     %.3f", g_lastSignal.extraValues[1]),
                RATT_BUY, 9);

      // Key Value + ATR
      DashLabel("ENG_WIDTH", x + pad, y + 44,
                StringFormat("KeyValue: %.1f", g_utb_keyValue),
                RATT_FIREFLY, 9, RATT_FONT_SECTION);
      DashLabel("ENG_REGIME", x + pad + 140, y + 44,
                StringFormat("ATR(%d): %.1f pip", g_utb_atrPeriod, g_lastSignal.channelWidthPip),
                RATT_AMBER, 9, RATT_FONT_SECTION);

      // ER Quality display
      string erStr = "";
      double erVal = g_lastSignal.extraValues[1];
      if(erVal >= InpERStrong)
         erStr = "Strong";
      else if(erVal >= InpERWeak)
         erStr = "Moderate";
      else
         erStr = "Weak";
      DashLabel("ENG_CD", x + pad + 280, y + 44,
                StringFormat("ER Quality: %s", erStr), RATT_TEXT_SECONDARY, 9);

      // Engine config summary
      DashLabel("ENG_CFG", x + pad, y + 62,
                StringFormat("Key:%.1f | ATR:%d | Src:JMA(P,Ph)",
                g_utb_keyValue, g_utb_atrPeriod),
                RATT_TEXT_MUTED, 8);
   }
   else
   {
      DashLabel("ENG_UPPER", x + pad, y + 26, "Waiting for data...", RATT_TEXT_MUTED, 9);
      DashLabel("ENG_MID", x + pad + 180, y + 26, " ", RATT_TEXT_MUTED, 9);
      DashLabel("ENG_LOWER", x + pad + 360, y + 26, " ", RATT_TEXT_MUTED, 9);
      DashLabel("ENG_WIDTH", x + pad, y + 44, " ", RATT_TEXT_MUTED, 9);
      DashLabel("ENG_REGIME", x + pad + 140, y + 44, " ", RATT_TEXT_MUTED, 9);
      DashLabel("ENG_CD", x + pad + 280, y + 44, " ", RATT_TEXT_MUTED, 9);
      DashLabel("ENG_CFG", x + pad, y + 62, " ", RATT_TEXT_MUTED, 8);
   }
}

//+------------------------------------------------------------------+
//| DrawFilterBar — Individual colored pills (22px)                 |
//+------------------------------------------------------------------+
void DrawFilterBar(int x, int y, int w)
{
   DashRectangle("FILT_PANEL", x, y, w, RATT_H_FILTERS, RATT_PANEL_BG, RATT_PANEL_BORDER);

   int px = x + RATT_PAD;
   for(int f = 0; f < g_lastSignal.filterCount && f < 8; f++)
   {
      string state = "";
      color  clr   = RATT_TEXT_MUTED;

      if(g_lastSignal.filterStates[f] == 1)
      {  state = "+"; clr = RATT_BUY; }
      else if(g_lastSignal.filterStates[f] == -1)
      {  state = "!"; clr = RATT_SELL; }
      else
      {  state = "_"; clr = RATT_TEXT_LO; }

      string pill = "[" + state + g_lastSignal.filterNames[f] + "]";
      DashLabel(StringFormat("FP%d", f), px, y + 3, pill, clr, 8);
      px += StringLen(pill) * 6 + 4;
   }

   // Session pill
   bool inSession = IsWithinSession();
   DashLabel("FP_SESS", px, y + 3,
             inSession ? "[+Sess]" : "[!Sess]",
             inSession ? RATT_BUY : RATT_SELL, 8);
   px += 48;

   // Hedge pill
   DashLabel("FP_HEDGE", px, y + 3,
             EnableHedge ? "[+Hedge]" : "[_Hedge]",
             EnableHedge ? RATT_HEDGE : RATT_TEXT_LO, 8);
}

//+------------------------------------------------------------------+
//| DrawLastSignals — Last 3 signals with direction + route (76px) |
//+------------------------------------------------------------------+
void DrawLastSignals(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("SIG_PANEL", x, y, w, RATT_H_LASTSIG, RATT_BG_SECTION_B, RATT_PANEL_BORDER);
   DashLabel("SIG_TITLE", x + pad, y + 4, "LAST SIGNALS", RATT_AMBER_DIM, 9, RATT_FONT_SECTION);
   DashLabel("SIG_CNT", x + w - 120, y + 5,
             StringFormat("B:%d S:%d Tot:%d", g_buySignals, g_sellSignals, g_totalSignals),
             RATT_TEXT_MUTED, 8);

   int ly = y + 22;
   for(int i = 0; i < 3; i++)
   {
      if(i < g_signalHistCount)
      {
         string arrow = g_signalHist[i].dir > 0 ? "\x25B2" : "\x25BC";
         string dirStr = g_signalHist[i].dir > 0 ? "BUY " : "SELL";
         color dirClr = g_signalHist[i].dir > 0 ? RATT_BUY : RATT_SELL;
         string qStr = g_signalHist[i].quality == PATTERN_TBS ? "[TBS]" : "[TWS]";
         color qClr = g_signalHist[i].quality == PATTERN_TBS ? RATT_BUY : RATT_AMBER;

         DashLabel(StringFormat("SH%d_DIR", i), x + pad, ly,
                   arrow + " " + dirStr + FormatPrice(g_signalHist[i].entry) +
                   " -> " + FormatPrice(g_signalHist[i].tp),
                   dirClr, 9);
         DashLabel(StringFormat("SH%d_Q", i), x + pad + 350, ly, qStr, qClr, 9, RATT_FONT_SECTION);
         DashLabel(StringFormat("SH%d_T", i), x + w - 80, ly,
                   TimeToString(g_signalHist[i].time, TIME_MINUTES),
                   RATT_TEXT_MUTED, 8);
         DashLabel(StringFormat("SH%d_S", i), x + w - 40, ly,
                   g_signalHist[i].status, RATT_TEXT_MID, 8);
      }
      else
      {
         DashLabel(StringFormat("SH%d_DIR", i), x + pad, ly, " ", RATT_TEXT_MUTED, 9);
         DashLabel(StringFormat("SH%d_Q", i), x + pad + 350, ly, " ", RATT_TEXT_MUTED, 9);
         DashLabel(StringFormat("SH%d_T", i), x + w - 80, ly, " ", RATT_TEXT_MUTED, 8);
         DashLabel(StringFormat("SH%d_S", i), x + w - 40, ly, " ", RATT_TEXT_MUTED, 8);
      }
      ly += 16;
   }
}

//+------------------------------------------------------------------+
//| DrawActiveCycles — Header + max 4 cycle rows (100px)             |
//+------------------------------------------------------------------+
void DrawActiveCycles(int x, int y, int w)
{
   int pad = RATT_PAD;
   int cycH = RATT_H_CYCLES;
   DashRectangle("CYCLE_PANEL", x, y, w, cycH, RATT_BG_DEEP, RATT_PANEL_BORDER);
   DashLabel("CY_TITLE", x + pad, y + 4, "ACTIVE CYCLES", RATT_BUY_DIM, 9, RATT_FONT_SECTION);

   int activeCycles = CountActiveCycles();
   DashLabel("CY_CNT", x + w - 70, y + 5,
             StringFormat("%d/%d", activeCycles, MaxConcurrentTrades), RATT_BUY, 9, RATT_FONT_SECTION);

   // Column header
   DashLabel("CY_HDR", x + pad, y + 20,
             "#   Dir  State  Lot    Entry         toTP     P&L", RATT_TEXT_LO, 7);

   int cy = y + 34;
   int displayed = 0;
   for(int i = 0; i < ArraySize(g_cycles) && displayed < 4; i++)
   {
      if(g_cycles[i].state == CYCLE_IDLE || g_cycles[i].state == CYCLE_CLOSED) continue;

      string dirStr = g_cycles[i].direction > 0 ? "BUY " : "SELL";
      string stStr = "LIVE";
      color  rowClr = g_cycles[i].direction > 0 ? RATT_BUY : RATT_SELL;
      if(g_cycles[i].state == CYCLE_PENDING)      { stStr = "PEND"; rowClr = RATT_AMBER; }
      else if(g_cycles[i].state == CYCLE_HEDGING) { stStr = "HEDG"; rowClr = RATT_HEDGE; }

      // Lot size display
      string lotStr = StringFormat("%.2f", g_cycles[i].lotSize);

      // Distance to TP in pips
      string tpDistStr = "---";
      if(g_cycles[i].tpPrice > 0 && g_cycles[i].state != CYCLE_PENDING)
      {
         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double distToTP = 0;
         if(g_cycles[i].direction > 0)
            distToTP = g_cycles[i].tpPrice - currentBid;  // BUY: TP sopra
         else
            distToTP = currentBid - g_cycles[i].tpPrice;  // SELL: TP sotto
         double pipDist = PointsToPips(distToTP);
         tpDistStr = StringFormat("%+.0f", pipDist);
      }

      // Floating P&L — separato per HEDG
      double soupPL  = 0;
      double hedgePL = 0;
      double floatPL = 0;
      if(g_cycles[i].state == CYCLE_ACTIVE && g_cycles[i].ticket > 0)
      {
         soupPL = GetFloatingProfit(g_cycles[i].ticket);
         floatPL = soupPL;
      }
      else if(g_cycles[i].state == CYCLE_HEDGING)
      {
         if(g_cycles[i].ticket > 0)
            soupPL = GetFloatingProfit(g_cycles[i].ticket);
         if(g_cycles[i].hsActive && g_cycles[i].hsTicket > 0)
            hedgePL = GetFloatingProfit(g_cycles[i].hsTicket);
         floatPL = soupPL + hedgePL;
      }
      color plClr = floatPL >= 0 ? RATT_BUY : RATT_SELL;

      // Riga principale: ID Dir State Lot Entry toTP
      DashLabel(StringFormat("CY%d", displayed), x + pad, cy,
                StringFormat("%02d  %s  %s  %s  %s",
                g_cycles[i].cycleID, dirStr, stStr, lotStr, FormatPrice(g_cycles[i].entryPrice)),
                rowClr, 9);

      // TP distance (colonna separata per allineamento)
      DashLabel(StringFormat("CY%d_TP", displayed), x + w - 150, cy,
                tpDistStr, RATT_FIREFLY_DIM, 9);

      // P&L — se HEDG mostra "S:+12 H:-8" altrimenti solo totale
      if(g_cycles[i].state == CYCLE_HEDGING)
      {
         color splClr = soupPL >= 0 ? RATT_BUY : RATT_SELL;
         color hplClr = hedgePL >= 0 ? RATT_BUY : RATT_SELL;
         DashLabel(StringFormat("CY%d_PL", displayed), x + w - 100, cy,
                   StringFormat("S:%+.0f", soupPL), splClr, 8);
         DashLabel(StringFormat("CY%d_HPL", displayed), x + w - 50, cy,
                   StringFormat("H:%+.0f", hedgePL), hplClr, 8);
      }
      else
      {
         DashLabel(StringFormat("CY%d_PL", displayed), x + w - 80, cy,
                   StringFormat("%+.2f", floatPL), plClr, 9);
         DashLabel(StringFormat("CY%d_HPL", displayed), x + w - 50, cy,
                   " ", RATT_TEXT_MUTED, 8);
      }

      cy += 16;
      displayed++;
   }
   for(int c = displayed; c < 4; c++)
   {
      DashLabel(StringFormat("CY%d", c), x + pad, cy, " ", RATT_TEXT_MUTED, 9);
      DashLabel(StringFormat("CY%d_TP", c), x + w - 150, cy, " ", RATT_TEXT_MUTED, 9);
      DashLabel(StringFormat("CY%d_PL", c), x + w - 80, cy, " ", RATT_TEXT_MUTED, 9);
      DashLabel(StringFormat("CY%d_HPL", c), x + w - 50, cy, " ", RATT_TEXT_MUTED, 8);
      cy += 16;
   }
}

//+------------------------------------------------------------------+
//| DrawPLSession — 3x2 grid: P&L|WinRate|MaxDD|Trades|Float|Daily  |
//+------------------------------------------------------------------+
void DrawPLSession(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("PL_PANEL", x, y, w, RATT_H_PL, RATT_PANEL_BG, RATT_PANEL_BORDER);
   DashLabel("PL_TITLE", x + pad, y + 4, "P&L SESSION", RATT_SELL_DIM, 9, RATT_FONT_SECTION);

   int colW = (w - 2 * pad) / 3;
   int c1 = x + pad;
   int c2 = x + pad + colW;
   int c3 = x + pad + 2 * colW;
   int r1 = y + 22;
   int r2 = y + 54;

   // Row 1: P&L | Win Rate | Max DD
   color plClr = g_sessionRealizedProfit >= 0 ? RATT_BUY : RATT_SELL;
   DashLabel("PL_L1", c1, r1, "P&L", RATT_TEXT_LO, 7);
   DashLabel("PL_V1", c1, r1 + 10, StringFormat("%+.2f", g_sessionRealizedProfit), plClr, 11, RATT_FONT_SECTION);
   double pnlPct = GetBalance() > 0 ? (g_sessionRealizedProfit / GetBalance() * 100) : 0;
   DashLabel("PL_S1", c1, r1 + 24, StringFormat("%+.2f%%", pnlPct), RATT_TEXT_MID, 8);

   int totalT = g_sessionWins + g_sessionLosses;
   double winrate = totalT > 0 ? (double)g_sessionWins / totalT * 100.0 : 0;
   DashLabel("PL_L2", c2, r1, "WIN RATE", RATT_TEXT_LO, 7);
   DashLabel("PL_V2", c2, r1 + 10, StringFormat("%.0f%%", winrate),
             winrate >= 50 ? RATT_BUY : RATT_SELL, 11, RATT_FONT_SECTION);
   DashLabel("PL_S2", c2, r1 + 24,
             StringFormat("%dW · %dL", g_sessionWins, g_sessionLosses), RATT_TEXT_MID, 8);

   DashLabel("PL_L3", c3, r1, "MAX DD", RATT_TEXT_LO, 7);
   DashLabel("PL_V3", c3, r1 + 10, StringFormat("%.1f%%", g_maxDrawdownPct),
             g_maxDrawdownPct > 3.0 ? RATT_SELL : RATT_TEXT_HI, 11, RATT_FONT_SECTION);
   double ddMoney = GetBalance() * g_maxDrawdownPct / 100.0;
   DashLabel("PL_S3", c3, r1 + 24, StringFormat("-$%.0f", ddMoney), RATT_TEXT_MID, 8);

   // Row 2: Trades | Float | Daily Loss
   DashLabel("PL_L4", c1, r2, "TRADES", RATT_TEXT_LO, 7);
   DashLabel("PL_V4", c1, r2 + 10, IntegerToString(totalT), RATT_TEXT_HI, 11, RATT_FONT_SECTION);
   DashLabel("PL_S4", c1, r2 + 24, "total", RATT_TEXT_MID, 8);

   double totalFloat = 0;
   for(int fi = 0; fi < ArraySize(g_cycles); fi++)
   {
      if((g_cycles[fi].state == CYCLE_ACTIVE || g_cycles[fi].state == CYCLE_HEDGING)
         && g_cycles[fi].ticket > 0)
         totalFloat += GetFloatingProfit(g_cycles[fi].ticket);
      if(g_cycles[fi].state == CYCLE_HEDGING
         && g_cycles[fi].hsActive && g_cycles[fi].hsTicket > 0)
         totalFloat += GetFloatingProfit(g_cycles[fi].hsTicket);
   }
   color fClr = totalFloat >= 0 ? RATT_BUY : RATT_SELL;
   DashLabel("PL_L5", c2, r2, "FLOAT", RATT_TEXT_LO, 7);
   DashLabel("PL_V5", c2, r2 + 10, StringFormat("%+.2f", totalFloat), fClr, 11, RATT_FONT_SECTION);
   DashLabel("PL_S5", c2, r2 + 24, "open", RATT_TEXT_MID, 8);

   color dClr = g_dailyRealizedProfit >= 0 ? RATT_BUY : RATT_SELL;
   DashLabel("PL_L6", c3, r2, "DAILY", RATT_TEXT_LO, 7);
   DashLabel("PL_V6", c3, r2 + 10, StringFormat("%+.2f", g_dailyRealizedProfit), dClr, 11, RATT_FONT_SECTION);
   DashLabel("PL_S6", c3, r2 + 24, "today", RATT_TEXT_MID, 8);
}

//+------------------------------------------------------------------+
//| DrawControls — Title + session + time (52px)                    |
//+------------------------------------------------------------------+
void DrawControls(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("CTRL_PANEL", x, y, w, RATT_H_CONTROLS, RATT_PANEL_BG, RATT_PANEL_BORDER);
   DashLabel("CT_TITLE", x + pad, y + 4, "CONTROLS", RATT_AMBER_DIM, 9, RATT_FONT_SECTION);

   DashLabel("CT_TIME", x + w - 80, y + 5,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), RATT_TEXT_MUTED, 8);

   // Button feedback
   if(ObjectFind(0, "RATT_BTN_START_" + _Symbol) >= 0)
      UpdateButtonFeedback();
}

//+------------------------------------------------------------------+
//| DrawStatusBar — Bottom summary bar (20px)                       |
//+------------------------------------------------------------------+
void DrawStatusBar(int x, int y, int w)
{
   DashRectangle("SBAR_PANEL", x, y, w, RATT_H_STATUSBAR, RATT_BG_SECTION_A, RATT_PANEL_BORDER);

   string stateStr = "IDLE";
   switch(g_systemState)
   {
      case STATE_ACTIVE:       stateStr = "ACTIVE"; break;
      case STATE_PAUSED:       stateStr = "PAUSED"; break;
      case STATE_ERROR:        stateStr = "ERROR";  break;
      case STATE_INITIALIZING: stateStr = "INIT";   break;
   }

   string hedgeMode = EnableHedge ? "Hedge:ON" : "Hedge:OFF";

   string bar = ShortToString(0x25CF) + " " + stateStr
              + "  UTBot v2.01"
              + "  ER:ON"
              + "  " + hedgeMode
              + "  v" + EA_VERSION
              + "  M:" + IntegerToString(MagicNumber);

   DashLabel("SBAR_TXT", x + RATT_PAD, y + 3, bar, RATT_TEXT_MID, 8);
}

//+------------------------------------------------------------------+
//| UpdateSidePanel — Engine Monitor (12 righe) + Signal Feed (6)    |
//|                                                                  |
//| Posizionato a destra del dashboard (offset RATT_DASH_W + 10px).  |
//| Due sezioni:                                                     |
//|                                                                  |
//| ENGINE MONITOR (235px, 12 righe da lh=15px):                     |
//|   1.  UTBot Engine — ACTIVE/INIT (g_engineReady)                 |
//|   2.  ATR(14) — da atrBuf o g_atrCache                          |
//|   3.  EMA ATR — da extraValues[1]                                |
//|   4.  Daily Trades — W/L odierni                                 |
//|   5.  TF Preset — timeframe corrente                             |
//|   6.  Key Value — g_utb_keyValue                                 |
//|   7.  Source — source value from engine                          |
//|   8.  ER Quality — efficiency ratio quality                      |
//|   9.  Expired — ordini pending scaduti                            |
//|  10.  AutoSave — tempo dall'ultimo salvataggio GV                 |
//|  11.  HTF Filter — stato filtro higher timeframe                  |
//|  12.  Hedge — ON (count) o OFF                                   |
//|  [13.] VIRTUAL MODE — badge arancio se VirtualMode=true          |
//|                                                                  |
//| SIGNAL FEED (110px, MAX_FEED_ITEMS righe):                       |
//|   Feed cronologico delle ultime azioni EA (g_feedLines[]).        |
//|   Colori per tipo: RATT_BUY, RATT_SELL, RATT_AMBER, RATT_TEXT_MUTED.|
//+------------------------------------------------------------------+
void UpdateSidePanel()
{
   int sx = RATT_DASH_X + RATT_DASH_W + 10;
   int sy = RATT_DASH_Y;
   int sw = RATT_SIDE_W;

   // === ENGINE MONITOR ===
   DashRectangle("SIDE_MON", sx, sy, sw, 235, RATT_BG_DEEP, RATT_SIDE_BORDER);
   DashLabel("SM_TITLE", sx + 10, sy + 5, "ENGINE MONITOR", RATT_FIREFLY_DIM, 9, RATT_FONT_SECTION);

   int ly = sy + 22;
   int lh = 15;
   int valX = sx + 100;

   // 1. Engine status
   DashLabel("SM_R01L", sx + 10, ly, "UTBot Engine", RATT_TEXT_MID, 8);
   DashLabel("SM_R01V", valX, ly, g_engineReady ? "ACTIVE" : "INIT", g_engineReady ? RATT_BUY : RATT_AMBER, 8, RATT_FONT_SECTION);
   ly += lh;

   // 2. ATR
   DashLabel("SM_R02L", sx + 10, ly, "ATR(14)", RATT_TEXT_MID, 8);
   DashLabel("SM_R02V", valX, ly,
             StringFormat("%.1f pip", g_lastSignal.extraValues[0] > 0 ? PointsToPips(g_lastSignal.extraValues[0]) : g_atrCache.valuePips),
             RATT_FIREFLY, 8);
   ly += lh;

   // 3. ER (Efficiency Ratio)
   DashLabel("SM_R03L", sx + 10, ly, "ER", RATT_TEXT_MID, 8);
   DashLabel("SM_R03V", valX, ly,
             g_lastSignal.extraValues[1] > 0 ? StringFormat("%.3f", g_lastSignal.extraValues[1]) : "---",
             RATT_TEXT_SECONDARY, 8);
   ly += lh;

   // 4. Daily Trades
   DashLabel("SM_R04L", sx + 10, ly, "Daily Trades", RATT_TEXT_MID, 8);
   DashLabel("SM_R04V", valX, ly,
             StringFormat("%dW %dL", g_dailyWins, g_dailyLosses),
             g_dailyWins >= g_dailyLosses ? RATT_BUY : RATT_SELL, 8);
   ly += lh;

   // 5. TF Preset
   DashLabel("SM_R05L", sx + 10, ly, "TF Preset", RATT_TEXT_MID, 8);
   DashLabel("SM_R05V", valX, ly, EnumToString(Period()), RATT_TEXT_SECONDARY, 8);
   ly += lh;

   // 6. Key Value
   DashLabel("SM_R06L", sx + 10, ly, "Key Value", RATT_TEXT_MID, 8);
   DashLabel("SM_R06V", valX, ly, StringFormat("%.1f", g_utb_keyValue), RATT_TEXT_SECONDARY, 8);
   ly += lh;

   // 7. Source
   DashLabel("SM_R07L", sx + 10, ly, "Source", RATT_TEXT_MID, 8);
   DashLabel("SM_R07V", valX, ly,
             g_lastSignal.extraValues[4] > 0 ? DoubleToString(g_lastSignal.extraValues[4], _Digits) : "---",
             RATT_TEXT_SECONDARY, 8);
   ly += lh;

   // 8. ER Quality
   DashLabel("SM_R08L", sx + 10, ly, "ER Quality", RATT_TEXT_MID, 8);
   double erVal = g_lastSignal.extraValues[1];
   string erQualStr = "---";
   color erQualClr = RATT_TEXT_MUTED;
   if(erVal > 0)
   {
      if(erVal >= InpERStrong)
      {  erQualStr = StringFormat("Strong (%.2f)", erVal); erQualClr = RATT_BUY; }
      else if(erVal >= InpERWeak)
      {  erQualStr = StringFormat("Moderate (%.2f)", erVal); erQualClr = RATT_AMBER; }
      else
      {  erQualStr = StringFormat("Weak (%.2f)", erVal); erQualClr = RATT_SELL; }
   }
   DashLabel("SM_R08V", valX, ly, erQualStr, erQualClr, 8);
   ly += lh;

   // 9. Expired Orders
   DashLabel("SM_R09L", sx + 10, ly, "Expired", RATT_TEXT_MID, 8);
   DashLabel("SM_R09V", valX, ly,
             g_totalExpiredOrders > 0 ? IntegerToString(g_totalExpiredOrders) : "0",
             g_totalExpiredOrders > 0 ? RATT_AMBER : RATT_TEXT_MUTED, 8);
   ly += lh;

   // 10. AutoSave
   DashLabel("SM_R10L", sx + 10, ly, "AutoSave", RATT_TEXT_MID, 8);
   string saveStr = "---";
   if(g_lastAutoSaveTime > 0)
   {
      int ago = (int)(TimeCurrent() - g_lastAutoSaveTime);
      saveStr = IntegerToString(ago) + "s ago";
   }
   DashLabel("SM_R10V", valX, ly, saveStr, RATT_TEXT_MUTED, 8);
   ly += lh;

   // 11. HTF
   DashLabel("SM_R11L", sx + 10, ly, "HTF Filter", RATT_TEXT_MID, 8);
   DashLabel("SM_R11V", valX, ly, HTFGetStatusString(), RATT_TEXT_SECONDARY, 8);
   ly += lh;

   // 12. Hedge
   DashLabel("SM_R12L", sx + 10, ly, "Hedge", RATT_TEXT_MID, 8);
   if(EnableHedge)
   {
      int hedgeCount = 0;
      for(int hi = 0; hi < ArraySize(g_cycles); hi++)
      {
         if(g_cycles[hi].hsPending || g_cycles[hi].hsActive) hedgeCount++;
      }
      DashLabel("SM_R12V", valX, ly,
                hedgeCount > 0 ? StringFormat("ON (%d)", hedgeCount) : "ON",
                RATT_HEDGE, 8, RATT_FONT_SECTION);
   }
   else
      DashLabel("SM_R12V", valX, ly, "OFF", RATT_TEXT_MUTED, 8);
   ly += lh;

   // Virtual mode indicator
   if(VirtualMode)
   {
      ly += 4;
      DashLabel("SM_VIRT", sx + 10, ly, "VIRTUAL MODE", RATT_AMBER, 9, RATT_FONT_SECTION);
   }
   else
      DashLabel("SM_VIRT", sx + 10, ly + 4, " ", RATT_TEXT_MUTED, 8);

   // === SIGNAL FEED ===
   int feedY = sy + 245;
   DashRectangle("SIDE_FEED", sx, feedY, sw, 110, RATT_BG_PANEL, RATT_SIDE_BORDER);
   DashLabel("SF_TITLE", sx + 10, feedY + 5, "SIGNAL FEED", RATT_AMBER_DIM, 9, RATT_FONT_SECTION);

   int fy = feedY + 22;
   for(int i = 0; i < MAX_FEED_ITEMS; i++)
   {
      if(i < g_feedCount)
         DashLabel(StringFormat("SF%d", i), sx + 10, fy, g_feedLines[i], g_feedColors[i], 8);
      else
         DashLabel(StringFormat("SF%d", i), sx + 10, fy, " ", RATT_TEXT_MUTED, 8);
      fy += 15;
   }
}

//+------------------------------------------------------------------+
//| UpdateDashboard — Main dashboard update (chiamata ogni 500ms)    |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int x = RATT_DASH_X;
   int y = RATT_DASH_Y;
   int w = RATT_DASH_W;

   // Altezza totale dashboard: somma pannelli + 9 gap
   int totalH = RATT_H_HEADER + RATT_H_TOPBAR + RATT_H_SYSSTATUS + RATT_H_ENGINE
              + RATT_H_FILTERS + RATT_H_LASTSIG + RATT_H_CYCLES + RATT_H_PL
              + RATT_H_CONTROLS + RATT_H_STATUSBAR + (9 * RATT_GAP);

   // ── Cornice perimetrale con bordo solido 3px (stile SugamaraPivot) ──
   int fm = 4;    // margine cornice (px tra bordo e pannelli)
   int ftH = 20;  // area titolo superiore
   int fbH = 16;  // area titolo inferiore
   int frameX = x - fm;
   int frameY = y - ftH - fm;
   int frameW = w + 2 * fm;
   int frameH = totalH + ftH + fbH + 2 * fm;

   // Sfondo completo frame (creato primo = disegnato sotto i pannelli)
   DashRectangle("FRAME_BG", frameX, frameY,
                 frameW, frameH, RATT_BG_DEEP, RATT_BG_DEEP);

   // Barra decorativa orizzontale
   string hBar = "";
   for(int b = 0; b < 6; b++) hBar += ShortToString(0x2500);

   // Titolo superiore centrato "────── RATTAPIGNOLA ──────"
   DashLabel("FRAME_TITLE", x + w / 2, frameY + 3,
             hBar + " RATTAPIGNOLA " + hBar, RATT_BORDER_FRAME, 11, RATT_FONT_TITLE);
   ObjectSetInteger(0, "RATT_DASH_FRAME_TITLE", OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, "RATT_DASH_FRAME_TITLE", OBJPROP_ZORDER, RATT_Z_LABEL + 1000);

   // Titolo inferiore centrato "────── v1.0.0 · UTBot Adaptive Engine ──────"
   DashLabel("FRAME_BOTTOM", x + w / 2, y + totalH + fm + 1,
             hBar + " v" + EA_VERSION + " " + ShortToString(0x00B7) + " UTBot Adaptive Engine " + hBar,
             RATT_BORDER_FRAME, 8, RATT_FONT_SECTION);
   ObjectSetInteger(0, "RATT_DASH_FRAME_BOTTOM", OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, "RATT_DASH_FRAME_BOTTOM", OBJPROP_ZORDER, RATT_Z_LABEL + 1000);

   DrawHeaderRow(x, y, w);       y += RATT_H_HEADER + RATT_GAP;
   DrawTitleBar(x, y, w);        y += RATT_H_TOPBAR + RATT_GAP;
   DrawSystemStatus(x, y, w);    y += RATT_H_SYSSTATUS + RATT_GAP;
   DrawEnginePanel(x, y, w);     y += RATT_H_ENGINE + RATT_GAP;
   DrawFilterBar(x, y, w);       y += RATT_H_FILTERS + RATT_GAP;
   DrawLastSignals(x, y, w);     y += RATT_H_LASTSIG + RATT_GAP;
   DrawActiveCycles(x, y, w);    y += RATT_H_CYCLES + RATT_GAP;
   DrawPLSession(x, y, w);       y += RATT_H_PL + RATT_GAP;
   DrawControls(x, y, w);        y += RATT_H_CONTROLS + RATT_GAP;
   DrawStatusBar(x, y, w);

   UpdateSidePanel();

   // ── Bordo solido 4 rettangoli (creati ULTIMI per stacking MT5) ──
   int bw = 3;
   color bClr = RATT_BORDER_FRAME;  // verde campagna perimetrale
   DashRectangle("FRAME_BORDER_T", frameX - bw, frameY - bw,
                 frameW + 2*bw, bw, bClr, bClr);
   DashRectangle("FRAME_BORDER_B", frameX - bw, frameY + frameH,
                 frameW + 2*bw, bw, bClr, bClr);
   DashRectangle("FRAME_BORDER_L", frameX - bw, frameY - bw,
                 bw, frameH + 2*bw, bClr, bClr);
   DashRectangle("FRAME_BORDER_R", frameX + frameW, frameY - bw,
                 bw, frameH + 2*bw, bClr, bClr);
}

//+------------------------------------------------------------------+
//| CreateDashboard — Creazione iniziale dashboard + bottoni         |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   UpdateDashboard();

   // Calculate controls Y position for buttons
   int ctrlY = RATT_DASH_Y;
   ctrlY += RATT_H_HEADER + RATT_GAP;
   ctrlY += RATT_H_TOPBAR + RATT_GAP;
   ctrlY += RATT_H_SYSSTATUS + RATT_GAP;
   ctrlY += RATT_H_ENGINE + RATT_GAP;
   ctrlY += RATT_H_FILTERS + RATT_GAP;
   ctrlY += RATT_H_LASTSIG + RATT_GAP;
   ctrlY += RATT_H_CYCLES + RATT_GAP;
   ctrlY += RATT_H_PL + RATT_GAP;

   CreateControlButtons(RATT_DASH_X, ctrlY, RATT_DASH_W);
   AdLogI(LOG_CAT_UI, "Dashboard created (Firefly Pragmatic v1.0)");
}

//+------------------------------------------------------------------+
//| DestroyDashboard — Rimuove TUTTI gli oggetti con prefisso "RATT_"|
//+------------------------------------------------------------------+
void DestroyDashboard()
{
   ObjectsDeleteAll(0, "RATT_");
}
