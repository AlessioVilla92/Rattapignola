//+------------------------------------------------------------------+
//|                                      adSessionManager.mqh        |
//|           AcquaDulza EA v1.6.1 — Session Manager                 |
//|                                                                  |
//|  Session filter + ParseTimeToMinutes + IsInBlockedTime           |
//|  Semplificato: solo un magic number, no hedge logic              |
//+------------------------------------------------------------------+
#property copyright "AcquaDulza (C) 2026"

//+------------------------------------------------------------------+
//| Session Variables                                                |
//+------------------------------------------------------------------+
bool     g_sessionCloseTriggered = false;
int      g_lastSessionDay       = -1;
string   g_currentSessionName   = "NONE";

//+------------------------------------------------------------------+
//| ParseTimeToMinutes — "HH:MM" -> total minutes from midnight      |
//+------------------------------------------------------------------+
int ParseTimeToMinutes(string timeStr)
{
   if(StringLen(timeStr) < 4) return -1;

   int colonPos = StringFind(timeStr, ":");
   if(colonPos < 0) return -1;

   int hours = (int)StringToInteger(StringSubstr(timeStr, 0, colonPos));
   int mins  = (int)StringToInteger(StringSubstr(timeStr, colonPos + 1));

   if(hours < 0 || hours > 23 || mins < 0 || mins > 59) return -1;

   return hours * 60 + mins;
}

//+------------------------------------------------------------------+
//| IsInBlockedTime — Check if current time is in blocked range      |
//| Used by DPC Engine time filter                                   |
//+------------------------------------------------------------------+
bool IsInBlockedTime(int blockStartMin, int blockEndMin)
{
   if(blockStartMin < 0 || blockEndMin < 0) return false;
   if(blockStartMin == blockEndMin) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMin = dt.hour * 60 + dt.min;

   if(blockStartMin < blockEndMin)
      return (currentMin >= blockStartMin && currentMin < blockEndMin);
   else
      return (currentMin >= blockStartMin || currentMin < blockEndMin);
}

//+------------------------------------------------------------------+
//| DetectCurrentSession — Determine which session is active         |
//+------------------------------------------------------------------+
string DetectCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;

   // Approximate UTC-based session times (broker server time)
   // London:    08:00-16:30
   // New York:  13:00-21:00
   // Asian:     00:00-08:00
   if(h >= 8 && h < 13)        return "LONDON";
   if(h >= 13 && h < 17)       return "LONDON+NY";
   if(h >= 17 && h < 21)       return "NEW YORK";
   if(h >= 0 && h < 8)         return "ASIAN";
   return "OFF HOURS";
}

//+------------------------------------------------------------------+
//| IsWithinSession — Check if trading is allowed                    |
//+------------------------------------------------------------------+
bool IsWithinSession()
{
   if(!EnableSessionFilter) return true;

   g_currentSessionName = DetectCurrentSession();

   // Crypto trades 24/7 — bypass session filter (dopo DetectCurrentSession per dashboard)
   if(g_instrumentClass == INSTRUMENT_CRYPTO || g_instrumentClass == INSTRUMENT_CRYPTO_ALT) return true;

   // Blocked time range check
   int blockStart = ParseTimeToMinutes(BlockedTimeStart);
   int blockEnd   = ParseTimeToMinutes(BlockedTimeEnd);
   if(IsInBlockedTime(blockStart, blockEnd)) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;

   // Check named sessions
   if(SessionLondon && h >= 8 && h < 17)   return true;
   if(SessionNewYork && h >= 13 && h < 21) return true;
   if(SessionAsian && (h >= 0 && h < 8))   return true;

   return false;
}

//+------------------------------------------------------------------+
//| ResetDailySessionFlags                                           |
//+------------------------------------------------------------------+
void ResetDailySessionFlags()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.day_of_year != g_lastSessionDay)
   {
      g_sessionCloseTriggered = false;
      g_lastSessionDay = dt.day_of_year;
   }
}

//+------------------------------------------------------------------+
//| HandleSessionEnd — Close positions at session end                |
//| Closes both Soup (MagicNumber) and HS (MagicNumber+1)           |
//+------------------------------------------------------------------+
void HandleSessionEnd()
{
   if(!EnableSessionFilter) return;
   ResetDailySessionFlags();
   if(g_sessionCloseTriggered) return;

   // Not yet at session end
   if(IsWithinSession()) return;

   g_sessionCloseTriggered = true;
   int closedPositions = 0;
   int deletedOrders   = 0;

   // Close all positions with our magic
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic != MagicNumber && posMagic != MagicNumber + 1) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double price  = PositionGetDouble(POSITION_PRICE_CURRENT);
      bool closed = false;
      for(int r = 0; r < MaxRetries; r++)
      {
         if(g_trade.PositionClose(ticket)) { closed = true; break; }
         AdLogW(LOG_CAT_SESSION, StringFormat("PositionClose #%d failed (retry %d/%d): %s",
                ticket, r + 1, MaxRetries, g_trade.ResultRetcodeDescription()));
         if(r < MaxRetries - 1) Sleep(RetryDelayMs);
      }
      if(closed)
      {
         closedPositions++;
         Log_PositionClosed(ticket, "SESSION_END", profit, price);
      }
      else
         AdLogE(LOG_CAT_SESSION, StringFormat("Failed to close position #%d after %d retries", ticket, MaxRetries));
   }

   // Delete all pending orders with our magic
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      long ordMagic = OrderGetInteger(ORDER_MAGIC);
      if(ordMagic != MagicNumber && ordMagic != MagicNumber + 1) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      bool deleted = false;
      for(int r = 0; r < MaxRetries; r++)
      {
         if(g_trade.OrderDelete(ticket)) { deleted = true; break; }
         AdLogW(LOG_CAT_SESSION, StringFormat("OrderDelete #%d failed (retry %d/%d): %s",
                ticket, r + 1, MaxRetries, g_trade.ResultRetcodeDescription()));
         if(r < MaxRetries - 1) Sleep(RetryDelayMs);
      }
      if(deleted)
      {
         deletedOrders++;
         Log_OrderCancelled(ticket, "SESSION_END");
      }
      else
         AdLogE(LOG_CAT_SESSION, StringFormat("Failed to delete pending order #%d after %d retries", ticket, MaxRetries));
   }

   if(closedPositions > 0 || deletedOrders > 0)
      AdLogI(LOG_CAT_SESSION, StringFormat("Session end: closed=%d deleted=%d", closedPositions, deletedOrders));
}

//+------------------------------------------------------------------+
//| GetSessionStatus — Human-readable status string                  |
//+------------------------------------------------------------------+
string GetSessionStatus()
{
   if(!EnableSessionFilter) return "DISABLED";
   if(IsWithinSession()) return g_currentSessionName;
   return "CLOSED";
}

//+------------------------------------------------------------------+
//| InitializeSessionManager                                         |
//+------------------------------------------------------------------+
void InitializeSessionManager()
{
   if(!EnableSessionFilter)
   {
      Log_InitConfig("Session", "DISABLED");
      return;
   }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_lastSessionDay = dt.day_of_year;
   g_sessionCloseTriggered = false;
   g_currentSessionName = DetectCurrentSession();

   Log_InitConfig("Session.London", SessionLondon ? "YES" : "NO");
   Log_InitConfig("Session.NewYork", SessionNewYork ? "YES" : "NO");
   Log_InitConfig("Session.Asian", SessionAsian ? "YES" : "NO");
   Log_InitComplete("Session");
}
