//+------------------------------------------------------------------+
//|                                      rattControlButtons.mqh      |
//|           Rattapignola EA v1.1 — Control Buttons                  |
//|                                                                  |
//|  3 buttons stile SugaraPivot: START, RECOVERY, STOP              |
//|  PAUSE/RESUME integrato nel bottone START                         |
//|                                                                  |
//|  v1.1: 3 bottoni (era 4), START toggle ACTIVE/PAUSED             |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

//+------------------------------------------------------------------+
//| Button Name Constants                                            |
//+------------------------------------------------------------------+
#define BTN_START    "RATT_BTN_START"
#define BTN_RECOVER  "RATT_BTN_RECOVER"
#define BTN_STOP     "RATT_BTN_STOP"

//+------------------------------------------------------------------+
//| Button Colors (Firefly)                                          |
//+------------------------------------------------------------------+
#define CLR_BTN_START    C'0,130,80'
#define CLR_BTN_ACTIVE   C'0,200,120'
#define CLR_BTN_RESUME   C'0,160,220'
#define CLR_BTN_RECOVER  C'0,140,140'
#define CLR_BTN_STOP     C'180,30,30'

//+------------------------------------------------------------------+
//| Multi-chart button name                                          |
//+------------------------------------------------------------------+
string BtnObjName(string baseName)
{
   return baseName + "_" + _Symbol;
}

//+------------------------------------------------------------------+
//| CreateControlButton — Standard button style                     |
//+------------------------------------------------------------------+
void CreateControlButton(string name, int x, int y, int width, int height,
                         string text, color bgColor)
{
   string objName = BtnObjName(name);
   ObjectDelete(0, objName);

   if(!ObjectCreate(0, objName, OBJ_BUTTON, 0, 0, 0)) return;

   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, height);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, objName, OBJPROP_FONT, RATT_FONT_SECTION);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_STATE, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, objName, OBJPROP_ZORDER, RATT_Z_BUTTON);
}

//+------------------------------------------------------------------+
//| CreateControlButtons — 3 buttons: START, RECOVERY, STOP          |
//+------------------------------------------------------------------+
void CreateControlButtons(int startX, int startY, int panelWidth)
{
   int pad = 15;
   int btnGap = 8;
   int btnW = (panelWidth - 2 * pad - 2 * btnGap) / 3;
   int btnH = 32;
   int bx = startX + pad;
   int by = startY + 24;

   CreateControlButton(BTN_START, bx, by, btnW, btnH, "START", CLR_BTN_START);
   CreateControlButton(BTN_RECOVER, bx + btnW + btnGap, by, btnW, btnH, "RECOVERY", CLR_BTN_RECOVER);
   CreateControlButton(BTN_STOP, bx + 2 * (btnW + btnGap), by, btnW, btnH, "STOP", CLR_BTN_STOP);

   UpdateButtonFeedback();
   AdLogI(LOG_CAT_UI, "Control buttons created (3 buttons)");
}

//+------------------------------------------------------------------+
//| UpdateButtonFeedback — Sync button visuals with state           |
//+------------------------------------------------------------------+
void UpdateButtonFeedback()
{
   // START: shows RUNNING (active), PAUSE (click to pause), RESUME (paused)
   if(g_systemState == STATE_ACTIVE)
   {
      ObjectSetInteger(0, BtnObjName(BTN_START), OBJPROP_BGCOLOR, CLR_BTN_ACTIVE);
      ObjectSetString(0, BtnObjName(BTN_START), OBJPROP_TEXT, "RUNNING");
   }
   else if(g_systemState == STATE_PAUSED)
   {
      ObjectSetInteger(0, BtnObjName(BTN_START), OBJPROP_BGCOLOR, CLR_BTN_RESUME);
      ObjectSetString(0, BtnObjName(BTN_START), OBJPROP_TEXT, "RESUME");
   }
   else
   {
      ObjectSetInteger(0, BtnObjName(BTN_START), OBJPROP_BGCOLOR, CLR_BTN_START);
      ObjectSetString(0, BtnObjName(BTN_START), OBJPROP_TEXT, "START");
   }
}

//+------------------------------------------------------------------+
//| HandleButtonClick — Process button clicks from OnChartEvent     |
//+------------------------------------------------------------------+
void HandleButtonClick(string sparam)
{
   // Reset button state (OBJ_BUTTON toggles on click)
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   // START — ciclo: IDLE/ERROR/INIT → ACTIVE → PAUSED → ACTIVE
   if(sparam == BtnObjName(BTN_START))
   {
      if(g_systemState == STATE_ACTIVE)
      {
         // ACTIVE → PAUSED
         g_systemState = STATE_PAUSED;
         AdLogI(LOG_CAT_UI, "Button: PAUSE (via START)");
         Alert("Rattapignola: System PAUSED | ", _Symbol);
      }
      else if(g_systemState == STATE_PAUSED)
      {
         // PAUSED → ACTIVE (resume)
         g_systemState = STATE_ACTIVE;
         AdLogI(LOG_CAT_UI, "Button: RESUME -> ACTIVE (via START)");
         Alert("Rattapignola: System RESUMED | ", _Symbol);
      }
      else if(g_systemState == STATE_IDLE || g_systemState == STATE_ERROR || g_systemState == STATE_INITIALIZING)
      {
         // IDLE/ERROR/INIT → ACTIVE
         g_systemState = STATE_ACTIVE;
         AdLogI(LOG_CAT_UI, "Button: START -> ACTIVE");

         Alert("Rattapignola: System ACTIVE | ",
               _Symbol, " ", EnumToString(Period()),
               " | Engine: UTBot v2.01",
               " | Magic: ", MagicNumber,
               " | Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
      }
      UpdateButtonFeedback();
      ChartRedraw();
      return;
   }

   // RECOVERY
   if(sparam == BtnObjName(BTN_RECOVER))
   {
      AdLogI(LOG_CAT_UI, "Button: RECOVERY");
      AttemptRecovery();
      UpdateButtonFeedback();
      ChartRedraw();
      return;
   }

   // STOP
   if(sparam == BtnObjName(BTN_STOP))
   {
      AdLogI(LOG_CAT_UI, "Button: STOP — closing all");
      Alert("Rattapignola: STOP — Closing all orders | ", _Symbol);
      CloseAllOrders();
      // Cleanup hedge state on all cycles
      if(EnableHedge)
      {
         for(int _ci = 0; _ci < ArraySize(g_cycles); _ci++)
         {
            g_cycles[_ci].hsPending = false;
            g_cycles[_ci].hsActive  = false;
            g_cycles[_ci].hsTicket  = 0;
         }
         HedgeDeinit();  // Remove all fuchsia lines
      }
      g_systemState = STATE_IDLE;
      UpdateButtonFeedback();
      ChartRedraw();
      return;
   }
}
