//+------------------------------------------------------------------+
//|                                       rattSignalMarkers.mqh      |
//|           Rattapignola EA v1.3.0 — Cleanup-only stub             |
//|                                                                  |
//|  In v1.3.0 la grafica trend/segnali e' disegnata direttamente    |
//|  dall'EA in rattChannelOverlay.mqh (rendering diretto con        |
//|  OBJ_RECTANGLE + OBJ_TREND + OBJ_ARROW).                        |
//|                                                                  |
//|  Questo modulo conserva SOLO la funzione di pulizia per          |
//|  rimuovere oggetti residui di versioni precedenti dell'EA.       |
//+------------------------------------------------------------------+
#property copyright "Rattapignola (C) 2026"

void CleanupSignalMarkers()
{
   ObjectsDeleteAll(0, "RATT_SIG_");
   ObjectsDeleteAll(0, "RATT_DOT_");
   ObjectsDeleteAll(0, "RATT_LBL_");
   ObjectsDeleteAll(0, "RATT_TRIG_");
   ObjectsDeleteAll(0, "RATT_HSIG_");
   ObjectsDeleteAll(0, "RATT_HDOT_");
   ObjectsDeleteAll(0, "RATT_HLBL_");
   ObjectsDeleteAll(0, "RATT_TRIG_CDL_");
   ObjectDelete(0, "RATT_ENTRY_LEVEL");
}
