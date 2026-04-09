//+------------------------------------------------------------------+
//|                                          rattDashboard.mqh       |
//|           Rattapignola EA v1.1 — Dashboard Display                |
//|                                                                  |
//|  2-column layout stile SugaraPivot con palette Firefly.          |
//|                                                                  |
//|  LAYOUT (top -> bottom):                                          |
//|    FULL WIDTH (690px):                                             |
//|      1. Title   (50px) — Logo RATTAPIGNOLA + ENGINE + version     |
//|      2. Mode    (40px) — Pair + price + spread + TF + state       |
//|                                                                  |
//|    LEFT COLUMN (345px):                  RIGHT COLUMN (345px):    |
//|      3. EnginePanel (145px)              5. SysStatus  (145px)    |
//|      4. PLSession   (115px)              6. ActiveCycl  (145px)   |
//|      7. Controls    (dynamic)            8. Signals     (dynamic) |
//|                                                                  |
//|    FULL WIDTH (690px):                                             |
//|      9. StatusBar (20px)                                           |
//|                                                                  |
//|  SIDE PANEL (a destra del dashboard, offset +10px):               |
//|    - Engine Monitor (235px): UTBot, ATR, ER, etc.                 |
//|    - Signal Feed (110px): ultime azioni EA                        |
//|                                                                  |
//|  CORNICE PERIMETRALE (stile SugaraPivot):                         |
//|    - Sfondo scuro (RATT_BG_DEEP) creato PRIMO (sotto tutto)       |
//|    - 4 rettangoli firefly 3px creati ULTIMI (sopra tutto)         |
//|    - Titoli decorativi top/bottom                                  |
//|                                                                  |
//|  Z-ORDER e VISUAL STACKING:                                       |
//|    - RATT_Z_RECT: rettangoli (sotto testo)                        |
//|    - RATT_Z_LABEL: etichette testo (sopra rettangoli)             |
//|    - Frame border Z = RATT_Z_LABEL + 1000: primo piano            |
//|    - BACK=false: dashboard SOPRA il chart (foreground)             |
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

//+------------------------------------------------------------------+
//| DashStatusBox — Quadratino 8x8 colorato (stile SugaraPivot)      |
//+------------------------------------------------------------------+
void DashStatusBox(string id, int x, int y, color clr)
{
   DashRectangle("SB_" + id, x, y, 8, 8, clr, clr);
}

// ApplyChartTheme() definita in rattVisualTheme.mqh

//+------------------------------------------------------------------+
//| DrawTitlePanel — Logo + ENGINE + version (50px, full width)       |
//+------------------------------------------------------------------+
void DrawTitlePanel(int x, int y, int w)
{
   DashRectangle("TITLE_PANEL", x, y, w, RATT_H_TITLE, RATT_BG_SECTION_A, RATT_FIREFLY_DIM);

   // RATTAPIGNOLA — grande
   DashLabel("T_LOGO", x + RATT_PAD, y + 10, "RATTAPIGNOLA", RATT_FIREFLY, 16, RATT_FONT_TITLE);

   // Versione
   DashLabel("T_VER", x + RATT_PAD + 220, y + 18, "v" + EA_VERSION, RATT_TEXT_MUTED, 9);

   // ENGINE: UTBot Adaptive
   DashLabel("T_ENG", x + w - 280, y + 10, "ENGINE: UTBot Adaptive", RATT_FIREFLY_DIM, 10, RATT_FONT_SECTION);

   // Status box 8x8
   color stBoxClr = g_engineReady ? RATT_BUY : RATT_AMBER;
   DashStatusBox("T_ST", x + w - 60, y + 14, stBoxClr);
   DashLabel("T_STXT", x + w - 48, y + 11,
             g_engineReady ? "ON" : "INIT", stBoxClr, 9, RATT_FONT_SECTION);
}

//+------------------------------------------------------------------+
//| DrawModePanel — Pair + Price + Spread + TF + State (40px)        |
//+------------------------------------------------------------------+
void DrawModePanel(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("MODE_PANEL", x, y, w, RATT_H_MODE, RATT_BG_SECTION_A, RATT_PANEL_BORDER);

   // Riga 1: Symbol + Price + Spread
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DashLabel("M_PAIR", x + pad, y + 5, _Symbol, RATT_TEXT_HI, 11, RATT_FONT_SECTION);
   DashLabel("M_PRICE", x + pad + 100, y + 5, DoubleToString(bid, _Digits), RATT_FIREFLY, 11);
   DashLabel("M_SPREAD", x + pad + 220, y + 7, StringFormat("Spread:%.1f", GetSpreadPips()), RATT_TEXT_MUTED, 8);

   // Riga 2: TF + TP Mode + State
   string tfBadge = "UTBot v2.01";
   if(InpUTBPreset == UTB_TF_AUTO)
      tfBadge += " " + EnumToString(Period());
   DashLabel("M_TF", x + pad, y + 22, tfBadge, RATT_FIREFLY_DIM, 8);

   // TP Mode
   string tpStr = "";
   switch(TPMode)
   {
      case TP_SIGNAL_TO_SIGNAL: tpStr = "TP: S2S FLIP";                      break;
      case TP_SQUEEZE_EXIT:     tpStr = "TP: SQZ EXIT";                      break;
      case TP_ATR_MULTIPLE:     tpStr = "TP: ATR" + ShortToString(0x00D7) + StringFormat("%.1f", TPValue); break;
      case TP_FIXED_PIPS:       tpStr = StringFormat("TP: %.0f pip", TPValue);  break;
   }
   DashLabel("M_TP", x + pad + 200, y + 22, tpStr, RATT_AMBER, 8, RATT_FONT_SECTION);

   // State badge con dot — a destra
   string stateStr = "IDLE"; color stateClr = RATT_TEXT_MUTED;
   switch(g_systemState)
   {
      case STATE_ACTIVE:       stateStr = "ACTIVE";       stateClr = RATT_BUY; break;
      case STATE_PAUSED:       stateStr = "PAUSED";       stateClr = RATT_AMBER; break;
      case STATE_ERROR:        stateStr = "ERROR";        stateClr = RATT_SELL; break;
      case STATE_INITIALIZING: stateStr = "INIT...";      stateClr = RATT_FIREFLY; break;
   }
   DashLabel("M_STATE", x + w - 120, y + 10, ShortToString(0x25CF) + " " + stateStr, stateClr, 11, RATT_FONT_SECTION);
}

//+------------------------------------------------------------------+
//| DrawEnginePanel — UTBot Engine details (345px, left column)      |
//+------------------------------------------------------------------+
void DrawEnginePanel(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("ENG_PANEL", x, y, w, RATT_H_ENGINE, RATT_BG_ENGINE, RATT_PANEL_BORDER);

   // Title + status box
   DashLabel("ENG_TITLE", x + pad, y + 6, "UTBOT ENGINE", RATT_FIREFLY, 10, RATT_FONT_SECTION);
   color engStClr = g_engineReady ? RATT_BUY : RATT_AMBER;
   DashStatusBox("ENG_ST", x + w - 70, y + 9, engStClr);
   DashLabel("ENG_STXT", x + w - 58, y + 6,
             g_engineReady ? "ACTIVE" : "INIT", engStClr, 9, RATT_FONT_SECTION);

   if(g_lastSignal.upperBand > 0)
   {
      int ly = y + 26;
      int lh = 16;
      int valX = x + pad + 90;

      // Trail Stop (bandLevel = trail effettivo; upperBand = src + nLoss = banda superiore)
      DashLabel("ENG_L1", x + pad, ly, "Trail Stop", RATT_TEXT_MID, 8);
      DashLabel("ENG_V1", valX, ly,
                DoubleToString(g_lastSignal.bandLevel, _Digits), RATT_SELL, 8);
      ly += lh;

      // Source
      DashLabel("ENG_L2", x + pad, ly, "Source", RATT_TEXT_MID, 8);
      DashLabel("ENG_V2", valX, ly,
                DoubleToString(g_lastSignal.midline, _Digits), RATT_FIREFLY, 8);
      ly += lh;

      // ER
      double erVal = g_lastSignal.extraValues[1];
      DashLabel("ENG_L3", x + pad, ly, "ER", RATT_TEXT_MID, 8);
      DashLabel("ENG_V3", valX, ly,
                StringFormat("%.3f", erVal), RATT_TEXT_SECONDARY, 8);
      ly += lh;

      // ER Quality
      string erStr = "---";
      color erClr = RATT_TEXT_MUTED;
      if(erVal >= InpERStrong)      { erStr = "Strong";   erClr = RATT_BUY; }
      else if(erVal >= InpERWeak)   { erStr = "Moderate"; erClr = RATT_AMBER; }
      else                          { erStr = "Weak";     erClr = RATT_SELL; }
      DashLabel("ENG_L4", x + pad, ly, "ER Quality", RATT_TEXT_MID, 8);
      DashLabel("ENG_V4", valX, ly, erStr, erClr, 8, RATT_FONT_SECTION);
      ly += lh;

      // Key Value
      DashLabel("ENG_L5", x + pad, ly, "Key Value", RATT_TEXT_MID, 8);
      DashLabel("ENG_V5", valX, ly,
                StringFormat("%.1f", g_utb_keyValue), RATT_FIREFLY, 8);
      ly += lh;

      // ATR
      DashLabel("ENG_L6", x + pad, ly, StringFormat("ATR(%d)", g_utb_atrPeriod), RATT_TEXT_MID, 8);
      DashLabel("ENG_V6", valX, ly,
                StringFormat("%.1f pip", g_lastSignal.channelWidthPip), RATT_AMBER, 8);
      ly += lh;

      // Config
      // Sorgente adattiva dinamica (non hardcoded JMA)
      string srcName = "Close";
      switch(InpSrcType)
      {
         case UTB_SRC_JMA:   srcName = "JMA";   break;
         case UTB_SRC_KAMA:  srcName = "KAMA";  break;
         case UTB_SRC_HMA:   srcName = "HMA";   break;
         case UTB_SRC_CLOSE: srcName = "Close"; break;
      }
      DashLabel("ENG_CFG", x + pad, ly,
                StringFormat("Key:%.1f | ATR:%d | Src:%s", g_utb_keyValue, g_utb_atrPeriod, srcName),
                RATT_TEXT_MUTED, 7);
   }
   else
   {
      DashLabel("ENG_L1", x + pad, y + 26, "Waiting for data...", RATT_TEXT_MUTED, 9);
      DashLabel("ENG_V1", x + pad + 90, y + 26, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_L2", x + pad, y + 42, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_V2", x + pad + 90, y + 42, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_L3", x + pad, y + 58, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_V3", x + pad + 90, y + 58, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_L4", x + pad, y + 74, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_V4", x + pad + 90, y + 74, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_L5", x + pad, y + 90, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_V5", x + pad + 90, y + 90, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_L6", x + pad, y + 106, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_V6", x + pad + 90, y + 106, " ", RATT_TEXT_MUTED, 8);
      DashLabel("ENG_CFG", x + pad, y + 122, " ", RATT_TEXT_MUTED, 7);
   }
}

//+------------------------------------------------------------------+
//| DrawSystemStatus — System health (345px, right column)           |
//+------------------------------------------------------------------+
void DrawSystemStatus(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("SYS_PANEL", x, y, w, RATT_H_SYSSTATUS, RATT_BG_SECTION_A, RATT_PANEL_BORDER);

   // Title + status box
   DashLabel("SYS_TITLE", x + pad, y + 6, "SYSTEM STATUS", RATT_FIREFLY, 10, RATT_FONT_SECTION);
   DashStatusBox("SYS_ST", x + w - 20, y + 9, RATT_BUY);

   int ly = y + 26;
   int lh = 15;
   int valX = x + pad + 100;

   // Session
   DashLabel("SY_L1", x + pad, ly, "Session", RATT_TEXT_MID, 8);
   DashLabel("SY_V1", valX, ly, GetSessionStatus(), RATT_TEXT_HI, 8, RATT_FONT_SECTION);
   ly += lh;

   // Uptime
   int upSec = (int)(TimeCurrent() - g_systemStartTime);
   int upH = upSec / 3600; int upM = (upSec % 3600) / 60; int upS = upSec % 60;
   DashLabel("SY_L2", x + pad, ly, "Uptime", RATT_TEXT_MID, 8);
   DashLabel("SY_V2", valX, ly,
             StringFormat("%02d:%02d:%02d", upH, upM, upS), RATT_TEXT_HI, 8);
   ly += lh;

   // Spread
   double spread = GetSpreadPips();
   DashLabel("SY_L3", x + pad, ly, "Spread", RATT_TEXT_MID, 8);
   DashLabel("SY_V3", valX, ly,
             StringFormat("%.1f pip", spread),
             spread > g_inst_maxSpread ? RATT_SELL : RATT_BUY, 8);
   ly += lh;

   // Free Margin
   double freeMargin = GetFreeMargin();
   double marginLvl  = GetMarginLevel();
   DashLabel("SY_L4", x + pad, ly, "Free Margin", RATT_TEXT_MID, 8);
   DashLabel("SY_V4", valX, ly, FormatMoney(freeMargin),
             marginLvl > 500 ? RATT_BUY : (marginLvl > 200 ? RATT_AMBER : RATT_SELL), 8);
   ly += lh;

   // Balance
   DashLabel("SY_L5", x + pad, ly, "Balance", RATT_TEXT_MID, 8);
   DashLabel("SY_V5", valX, ly, FormatMoney(GetBalance()), RATT_TEXT_HI, 8);
   ly += lh;

   // Equity
   double equity = GetEquity();
   double balance = GetBalance();
   DashLabel("SY_L6", x + pad, ly, "Equity", RATT_TEXT_MID, 8);
   DashLabel("SY_V6", valX, ly, FormatMoney(equity),
             equity >= balance ? RATT_BUY : RATT_SELL, 8, RATT_FONT_SECTION);
   ly += lh;

   // Margin Level
   DashLabel("SY_L7", x + pad, ly, "Margin Lvl", RATT_TEXT_MID, 8);
   DashLabel("SY_V7", valX, ly,
             marginLvl > 0 ? StringFormat("%.0f%%", marginLvl) : "---",
             marginLvl > 500 ? RATT_BUY : (marginLvl > 200 ? RATT_AMBER : RATT_SELL), 8);
   ly += lh;

   // ATR (periodo dinamico da preset TF)
   DashLabel("SY_L8", x + pad, ly, StringFormat("ATR(%d)", g_utb_atrPeriod), RATT_TEXT_MID, 8);
   DashLabel("SY_V8", valX, ly,
             StringFormat("%.1f pip", g_atrCache.valuePips), RATT_FIREFLY, 8);
}

//+------------------------------------------------------------------+
//| DrawPLSession — Performance metrics (345px, left column)         |
//+------------------------------------------------------------------+
void DrawPLSession(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("PL_PANEL", x, y, w, RATT_H_PL, RATT_BG_PL, RATT_PANEL_BORDER);
   DashLabel("PL_TITLE", x + pad, y + 6, "PERFORMANCE", RATT_FIREFLY, 10, RATT_FONT_SECTION);

   int ly = y + 26;
   int lh = 15;
   int valX = x + pad + 90;

   // P&L
   color plClr = g_sessionRealizedProfit >= 0 ? RATT_BUY : RATT_SELL;
   DashLabel("PL_L1", x + pad, ly, "P&L", RATT_TEXT_MID, 8);
   DashLabel("PL_V1", valX, ly,
             StringFormat("%+.2f", g_sessionRealizedProfit), plClr, 9, RATT_FONT_SECTION);
   double pnlPct = GetBalance() > 0 ? (g_sessionRealizedProfit / GetBalance() * 100) : 0;
   DashLabel("PL_P1", valX + 90, ly, StringFormat("(%+.2f%%)", pnlPct), RATT_TEXT_MID, 8);
   ly += lh;

   // Win Rate
   int totalT = g_sessionWins + g_sessionLosses;
   double winrate = totalT > 0 ? (double)g_sessionWins / totalT * 100.0 : 0;
   DashLabel("PL_L2", x + pad, ly, "Win Rate", RATT_TEXT_MID, 8);
   DashLabel("PL_V2", valX, ly,
             StringFormat("%.0f%%", winrate),
             winrate >= 50 ? RATT_BUY : RATT_SELL, 9, RATT_FONT_SECTION);
   DashLabel("PL_P2", valX + 50, ly,
             StringFormat("%dW/%dL", g_sessionWins, g_sessionLosses), RATT_TEXT_MID, 8);
   ly += lh;

   // Max DD
   DashLabel("PL_L3", x + pad, ly, "Max DD", RATT_TEXT_MID, 8);
   DashLabel("PL_V3", valX, ly,
             StringFormat("%.1f%%", g_maxDrawdownPct),
             g_maxDrawdownPct > 3.0 ? RATT_SELL : RATT_TEXT_HI, 9, RATT_FONT_SECTION);
   double ddMoney = GetBalance() * g_maxDrawdownPct / 100.0;
   DashLabel("PL_P3", valX + 60, ly, StringFormat("-$%.0f", ddMoney), RATT_TEXT_MID, 8);
   ly += lh;

   // Trades
   DashLabel("PL_L4", x + pad, ly, "Trades", RATT_TEXT_MID, 8);
   DashLabel("PL_V4", valX, ly, IntegerToString(totalT), RATT_TEXT_HI, 9, RATT_FONT_SECTION);
   ly += lh;

   // Float
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
   DashLabel("PL_L5", x + pad, ly, "Float", RATT_TEXT_MID, 8);
   DashLabel("PL_V5", valX, ly, StringFormat("%+.2f", totalFloat), fClr, 9, RATT_FONT_SECTION);
   ly += lh;

   // Daily
   color dClr = g_dailyRealizedProfit >= 0 ? RATT_BUY : RATT_SELL;
   DashLabel("PL_L6", x + pad, ly, "Daily", RATT_TEXT_MID, 8);
   DashLabel("PL_V6", valX, ly, StringFormat("%+.2f", g_dailyRealizedProfit), dClr, 9, RATT_FONT_SECTION);
}

//+------------------------------------------------------------------+
//| DrawActiveCycles — Active trades (345px, right column)           |
//+------------------------------------------------------------------+
void DrawActiveCycles(int x, int y, int w)
{
   int pad = RATT_PAD;
   DashRectangle("CYCLE_PANEL", x, y, w, RATT_H_CYCLES, RATT_BG_CYCLES, RATT_PANEL_BORDER);

   // Title + count
   DashLabel("CY_TITLE", x + pad, y + 6, "ACTIVE CYCLES", RATT_FIREFLY, 10, RATT_FONT_SECTION);
   int activeCycles = CountActiveCycles();
   DashLabel("CY_CNT", x + w - 60, y + 7,
             StringFormat("%d/%d", activeCycles, MaxConcurrentTrades), RATT_BUY, 9, RATT_FONT_SECTION);

   // Column header
   DashLabel("CY_HDR", x + pad, y + 24,
             "#  Dir  State Lot   Entry      P&L", RATT_TEXT_LO, 7);

   int cy = y + 38;
   int rowH = 15;
   int displayed = 0;
   for(int i = 0; i < ArraySize(g_cycles) && displayed < 4; i++)
   {
      if(g_cycles[i].state == CYCLE_IDLE || g_cycles[i].state == CYCLE_CLOSED) continue;

      string dirStr = g_cycles[i].direction > 0 ? "BUY " : "SELL";
      string stStr = "LIVE";
      color  rowClr = g_cycles[i].direction > 0 ? RATT_BUY : RATT_SELL;
      if(g_cycles[i].state == CYCLE_PENDING)      { stStr = "PEND"; rowClr = RATT_AMBER; }
      else if(g_cycles[i].state == CYCLE_HEDGING) { stStr = "HEDG"; rowClr = RATT_HEDGE; }

      string lotStr = StringFormat("%.2f", g_cycles[i].lotSize);

      // P&L
      double soupPL = 0, hedgePL = 0, floatPL = 0;
      if(g_cycles[i].state == CYCLE_ACTIVE && g_cycles[i].ticket > 0)
      {
         soupPL = GetFloatingProfit(g_cycles[i].ticket);
         floatPL = soupPL;
      }
      else if(g_cycles[i].state == CYCLE_HEDGING)
      {
         if(g_cycles[i].ticket > 0) soupPL = GetFloatingProfit(g_cycles[i].ticket);
         if(g_cycles[i].hsActive && g_cycles[i].hsTicket > 0) hedgePL = GetFloatingProfit(g_cycles[i].hsTicket);
         floatPL = soupPL + hedgePL;
      }
      color plClr = floatPL >= 0 ? RATT_BUY : RATT_SELL;

      // Row
      DashLabel(StringFormat("CY%d", displayed), x + pad, cy,
                StringFormat("%02d %s %s %s %s",
                g_cycles[i].cycleID, dirStr, stStr, lotStr, FormatPrice(g_cycles[i].entryPrice)),
                rowClr, 8);

      // P&L column
      if(g_cycles[i].state == CYCLE_HEDGING)
      {
         DashLabel(StringFormat("CY%d_PL", displayed), x + w - 90, cy,
                   StringFormat("S:%+.0f H:%+.0f", soupPL, hedgePL),
                   plClr, 8);
      }
      else
      {
         DashLabel(StringFormat("CY%d_PL", displayed), x + w - 60, cy,
                   StringFormat("%+.2f", floatPL), plClr, 8);
      }

      cy += rowH;
      displayed++;
   }
   // Clear unused rows
   for(int c = displayed; c < 4; c++)
   {
      DashLabel(StringFormat("CY%d", c), x + pad, cy, " ", RATT_TEXT_MUTED, 8);
      DashLabel(StringFormat("CY%d_PL", c), x + w - 60, cy, " ", RATT_TEXT_MUTED, 8);
      cy += rowH;
   }

   // Hedge status
   int hedgeY = y + RATT_H_CYCLES - 20;
   DashLabel("CY_HEDGE", x + pad, hedgeY,
             EnableHedge ? "[Hedge:ON]" : "[Hedge:OFF]",
             EnableHedge ? RATT_HEDGE : RATT_TEXT_LO, 8);
}

//+------------------------------------------------------------------+
//| DrawControlsPanel — 3 buttons + time (345px, left column)        |
//+------------------------------------------------------------------+
void DrawControlsPanel(int x, int y, int w, int h)
{
   int pad = RATT_PAD;
   DashRectangle("CTRL_PANEL", x, y, w, h, RATT_PANEL_BG, RATT_PANEL_BORDER);
   DashLabel("CT_TITLE", x + pad, y + 6, "CONTROLS", RATT_FIREFLY_DIM, 10, RATT_FONT_SECTION);

   DashLabel("CT_TIME", x + w - 110, y + 7,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), RATT_TEXT_MUTED, 8);

   // Buttons are created by rattControlButtons.mqh
   if(ObjectFind(0, BtnObjName(BTN_START)) >= 0)
      UpdateButtonFeedback();
}

//+------------------------------------------------------------------+
//| DrawSignalsPanel — Signals + Filters (345px, right column)       |
//+------------------------------------------------------------------+
void DrawSignalsPanel(int x, int y, int w, int h)
{
   int pad = RATT_PAD;
   DashRectangle("SIG_PANEL", x, y, w, h, RATT_BG_SIGNALS, RATT_PANEL_BORDER);
   DashLabel("SIG_TITLE", x + pad, y + 6, "SIGNALS", RATT_FIREFLY, 10, RATT_FONT_SECTION);
   DashLabel("SIG_CNT", x + w - 100, y + 7,
             StringFormat("B:%d S:%d", g_buySignals, g_sellSignals),
             RATT_TEXT_MUTED, 8);

   // Filter pills (compact row) — with overflow guard
   int px = x + pad;
   int fy = y + 24;
   int maxPx = x + w - 70;  // Reserve space for Session+Hedge pills
   for(int f = 0; f < g_lastSignal.filterCount && f < 6; f++)
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
      int pillWidth = StringLen(pill) * 5 + 3;
      if(px + pillWidth > maxPx)
      {
         // Clear remaining unused pill labels
         for(int r = f; r < 6; r++)
            DashLabel(StringFormat("FP%d", r), px, fy, " ", RATT_TEXT_MUTED, 7);
         break;
      }
      DashLabel(StringFormat("FP%d", f), px, fy, pill, clr, 7);
      px += pillWidth;
   }
   // Session + Hedge pills (always shown)
   bool inSession = IsWithinSession();
   DashLabel("FP_SESS", px, fy,
             inSession ? "[+Ss]" : "[!Ss]",
             inSession ? RATT_BUY : RATT_SELL, 7);
   px += 32;
   DashLabel("FP_HEDGE", px, fy,
             EnableHedge ? "[+Hg]" : "[_Hg]",
             EnableHedge ? RATT_HEDGE : RATT_TEXT_LO, 7);

   // Signal rows
   int ly = fy + 16;
   for(int i = 0; i < 3; i++)
   {
      if(i < g_signalHistCount)
      {
         string arrow = g_signalHist[i].dir > 0 ? "\x25B2" : "\x25BC";
         string dirStr = g_signalHist[i].dir > 0 ? "BUY " : "SELL";
         color dirClr = g_signalHist[i].dir > 0 ? RATT_BUY : RATT_SELL;

         string sigLine = arrow + " " + dirStr + FormatPrice(g_signalHist[i].entry);
         if(g_signalHist[i].tp > 0)
            sigLine += ShortToString(0x2192) + FormatPrice(g_signalHist[i].tp);
         DashLabel(StringFormat("SH%d", i), x + pad, ly, sigLine, dirClr, 8);
         DashLabel(StringFormat("SH%d_T", i), x + w - 60, ly,
                   TimeToString(g_signalHist[i].time, TIME_MINUTES),
                   RATT_TEXT_MUTED, 7);
      }
      else
      {
         DashLabel(StringFormat("SH%d", i), x + pad, ly, " ", RATT_TEXT_MUTED, 8);
         DashLabel(StringFormat("SH%d_T", i), x + w - 60, ly, " ", RATT_TEXT_MUTED, 7);
      }
      ly += 14;
   }
}

//+------------------------------------------------------------------+
//| DrawStatusBar — Bottom summary bar (full width, 20px)            |
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

   // 2. ATR (periodo dinamico da preset TF)
   DashLabel("SM_R02L", sx + 10, ly, StringFormat("ATR(%d)", g_utb_atrPeriod), RATT_TEXT_MID, 8);
   DashLabel("SM_R02V", valX, ly,
             StringFormat("%.1f pip", g_lastSignal.extraValues[0] > 0 ? g_lastSignal.extraValues[0] : g_atrCache.valuePips),
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
//| UpdateDashboard — Main 2-column layout orchestrator              |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int x = RATT_DASH_X;
   int y = RATT_DASH_Y;
   int totalW = RATT_DASH_W;
   int colW   = RATT_DASH_COL_W;
   int gap    = RATT_GAP;

   // ── Heights ──
   int titleH   = RATT_H_TITLE;
   int modeH    = RATT_H_MODE;
   int engineH  = RATT_H_ENGINE;
   int sysH     = RATT_H_SYSSTATUS;
   int plH      = RATT_H_PL;
   int cycH     = RATT_H_CYCLES;
   int statusH  = RATT_H_STATUSBAR;

   // Right column total: sys + cycles + gap
   int rightFixedH = sysH + gap + cycH;
   // Left column fixed: engine + pl + gap
   int leftFixedH  = engineH + gap + plH;
   // Dynamic panel height (controls / signals)
   int columnH = MathMax(leftFixedH, rightFixedH);
   int ctrlH   = columnH - leftFixedH + gap > 0 ? columnH - leftFixedH : 60;
   int sigH    = columnH - rightFixedH + gap > 0 ? columnH - rightFixedH : 60;
   // Ensure minimum height
   if(ctrlH < 60) ctrlH = 60;
   if(sigH < 60)  sigH = 60;
   // Recalculate to align
   columnH = MathMax(leftFixedH + gap + ctrlH, rightFixedH + gap + sigH);
   ctrlH = columnH - leftFixedH - gap;
   sigH  = columnH - rightFixedH - gap;

   // Total dashboard height
   int totalH = titleH + gap + modeH + gap + columnH + gap + statusH;

   // ── Cornice perimetrale (sfondo) ──
   int fm = 4;
   int ftH = 20;
   int fbH = 16;
   int frameX = x - fm;
   int frameY = y - ftH - fm;
   int frameW = totalW + 2 * fm;
   int frameH = totalH + ftH + fbH + 2 * fm;

   DashRectangle("FRAME_BG", frameX, frameY,
                 frameW, frameH, RATT_BG_DEEP, RATT_BG_DEEP);

   // Decorative bar
   string hBar = "";
   for(int b = 0; b < 6; b++) hBar += ShortToString(0x2500);

   // Top title
   DashLabel("FRAME_TITLE", x + totalW / 2, frameY + 3,
             hBar + " RATTAPIGNOLA " + hBar, RATT_BORDER_FRAME, 11, RATT_FONT_TITLE);
   ObjectSetInteger(0, "RATT_DASH_FRAME_TITLE", OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, "RATT_DASH_FRAME_TITLE", OBJPROP_ZORDER, RATT_Z_LABEL + 1000);

   // Bottom title
   DashLabel("FRAME_BOTTOM", x + totalW / 2, y + totalH + fm + 1,
             hBar + " v" + EA_VERSION + " " + ShortToString(0x00B7) + " UTBot Adaptive Engine " + hBar,
             RATT_BORDER_FRAME, 8, RATT_FONT_SECTION);
   ObjectSetInteger(0, "RATT_DASH_FRAME_BOTTOM", OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, "RATT_DASH_FRAME_BOTTOM", OBJPROP_ZORDER, RATT_Z_LABEL + 1000);

   // ── Full width panels ──
   DrawTitlePanel(x, y, totalW);          y += titleH + gap;
   DrawModePanel(x, y, totalW);           y += modeH + gap;

   // ── Two-column section ──
   int leftX  = x;
   int rightX = x + colW;
   int colTop = y;

   // Left column
   int ly = colTop;
   DrawEnginePanel(leftX, ly, colW);      ly += engineH + gap;
   DrawPLSession(leftX, ly, colW);        ly += plH + gap;
   DrawControlsPanel(leftX, ly, colW, ctrlH);

   // Right column
   int ry = colTop;
   DrawSystemStatus(rightX, ry, colW);    ry += sysH + gap;
   DrawActiveCycles(rightX, ry, colW);    ry += cycH + gap;
   DrawSignalsPanel(rightX, ry, colW, sigH);

   // ── Full width bottom ──
   y = colTop + columnH + gap;
   DrawStatusBar(x, y, totalW);

   // Side panels
   UpdateSidePanel();

   // ── Border frame (4 rettangoli, creati ULTIMI per stacking MT5) ──
   int bw = 3;
   color bClr = RATT_BORDER_FRAME;
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

   // Calculate controls Y position for buttons (left column, after engine + PL)
   int ctrlY = RATT_DASH_Y + RATT_H_TITLE + RATT_GAP + RATT_H_MODE + RATT_GAP
             + RATT_H_ENGINE + RATT_GAP + RATT_H_PL + RATT_GAP;

   CreateControlButtons(RATT_DASH_X, ctrlY, RATT_DASH_COL_W);
   AdLogI(LOG_CAT_UI, "Dashboard created (2-column SugaraPivot style v1.2)");
}

//+------------------------------------------------------------------+
//| DestroyDashboard — Rimuove TUTTI gli oggetti con prefisso "RATT_"|
//+------------------------------------------------------------------+
void DestroyDashboard()
{
   ObjectsDeleteAll(0, "RATT_");
}
