//+------------------------------------------------------------------+
//|                                      adControlButtons.mqh        |
//|           AcquaDulza EA v1.6.1 — Control Buttons                 |
//|                                                                  |
//|  4 buttons: START, PAUSE, RECOVERY, STOP                        |
//|  Ocean palette colors                                            |
//|                                                                  |
//|  v1.4.0: STOP resetta stato hedge (pending/active/ticket)        |
//|           + chiama HedgeDeinit() per rimuovere linee fucsia      |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| Button Name Constants                                            |
//+------------------------------------------------------------------+
#define BTN_START    "AD_BTN_START"
#define BTN_PAUSE    "AD_BTN_PAUSE"
#define BTN_RECOVER  "AD_BTN_RECOVER"
#define BTN_STOP     "AD_BTN_STOP"

//+------------------------------------------------------------------+
//| Button Colors (Ocean)                                            |
//+------------------------------------------------------------------+
#define CLR_BTN_START    C'0,130,80'
#define CLR_BTN_ACTIVE   C'0,200,120'
#define CLR_BTN_PAUSE    C'180,120,0'
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
   ObjectSetString(0, objName, OBJPROP_FONT, AD_FONT_SECTION);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_STATE, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, objName, OBJPROP_ZORDER, AD_Z_BUTTON);
}

//+------------------------------------------------------------------+
//| CreateControlButtons — 4 buttons: START, PAUSE, RECOVERY, STOP |
//+------------------------------------------------------------------+
void CreateControlButtons(int startX, int startY, int panelWidth)
{
   int pad = 15;
   int btnGap = 8;
   int btnW = (panelWidth - 2 * pad - 3 * btnGap) / 4;
   int btnH = 28;
   int bx = startX + pad;
   int by = startY + 22;

   CreateControlButton(BTN_START, bx, by, btnW, btnH, "START", CLR_BTN_START);
   CreateControlButton(BTN_PAUSE, bx + btnW + btnGap, by, btnW, btnH, "PAUSE", CLR_BTN_PAUSE);
   CreateControlButton(BTN_RECOVER, bx + 2 * (btnW + btnGap), by, btnW, btnH, "RECOVERY", CLR_BTN_RECOVER);
   CreateControlButton(BTN_STOP, bx + 3 * (btnW + btnGap), by, btnW, btnH, "STOP", CLR_BTN_STOP);

   UpdateButtonFeedback();
   AdLogI(LOG_CAT_UI, "Control buttons created (4 buttons)");
}

//+------------------------------------------------------------------+
//| UpdateButtonFeedback — Sync button visuals with state           |
//+------------------------------------------------------------------+
void UpdateButtonFeedback()
{
   // START
   if(g_systemState == STATE_ACTIVE)
   {
      ObjectSetInteger(0, BtnObjName(BTN_START), OBJPROP_BGCOLOR, CLR_BTN_ACTIVE);
      ObjectSetString(0, BtnObjName(BTN_START), OBJPROP_TEXT, "RUNNING");
   }
   else
   {
      ObjectSetInteger(0, BtnObjName(BTN_START), OBJPROP_BGCOLOR, CLR_BTN_START);
      ObjectSetString(0, BtnObjName(BTN_START), OBJPROP_TEXT, "START");
   }

   // PAUSE / RESUME
   if(g_systemState == STATE_PAUSED)
   {
      ObjectSetString(0, BtnObjName(BTN_PAUSE), OBJPROP_TEXT, "RESUME");
      ObjectSetInteger(0, BtnObjName(BTN_PAUSE), OBJPROP_BGCOLOR, CLR_BTN_RESUME);
   }
   else
   {
      ObjectSetString(0, BtnObjName(BTN_PAUSE), OBJPROP_TEXT, "PAUSE");
      ObjectSetInteger(0, BtnObjName(BTN_PAUSE), OBJPROP_BGCOLOR, CLR_BTN_PAUSE);
   }
}

//+------------------------------------------------------------------+
//| HandleButtonClick — Process button clicks from OnChartEvent     |
//+------------------------------------------------------------------+
void HandleButtonClick(string sparam)
{
   // Reset button state (OBJ_BUTTON toggles on click)
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   // START — accetta IDLE, ERROR e INITIALIZING (l'utente puo' forzare l'avvio)
   if(sparam == BtnObjName(BTN_START))
   {
      if(g_systemState == STATE_IDLE || g_systemState == STATE_ERROR || g_systemState == STATE_INITIALIZING)
      {
         g_systemState = STATE_ACTIVE;
         AdLogI(LOG_CAT_UI, "Button: START -> ACTIVE");

         // Alert visivo — conferma avvio sistema con info chiave
         Alert("AcquaDulza: System ACTIVE | ",
               _Symbol, " ", EnumToString(Period()),
               " | Engine: DPC v7.19",
               " | Magic: ", MagicNumber,
               " | Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
      }
      UpdateButtonFeedback();
      ChartRedraw();
      return;
   }

   // PAUSE / RESUME
   if(sparam == BtnObjName(BTN_PAUSE))
   {
      if(g_systemState == STATE_ACTIVE)
      {
         g_systemState = STATE_PAUSED;
         AdLogI(LOG_CAT_UI, "Button: PAUSE");
      }
      else if(g_systemState == STATE_PAUSED)
      {
         g_systemState = STATE_ACTIVE;
         AdLogI(LOG_CAT_UI, "Button: RESUME -> ACTIVE");
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
