//+------------------------------------------------------------------+
//|                                    MB_RiskClickTrader_EA.mq5      |
//|   One-click, risk-based market execution. Drag a line to where   |
//|   your stop loss should be, type your risk % once, then click    |
//|   BUY or SELL — the lot size is calculated fresh at that instant |
//|   from the CURRENT market price to your SL line, so you never    |
//|   place a "test" pending order just to see what size to use.     |
//|                                                                    |
//|   HOW IT WORKS:                                                   |
//|   - A red dashed line ("SL") appears on the chart — drag it to    |
//|     wherever your stop loss should sit for the trade you're       |
//|     about to take.                                                |
//|   - The Risk % box (top-left) is your risk per trade, as % of     |
//|     account Balance (or Equity — see RiskBasis input). Type a     |
//|     new number and press Enter to change it any time.             |
//|   - The panel updates live, showing the lot size it WOULD use if  |
//|     you clicked BUY or SELL right now, given where price and the  |
//|     SL line currently are.                                        |
//|   - Click BUY or SELL: it re-reads the current Ask/Bid and the SL |
//|     line's price at that exact moment, computes the lot size that |
//|     risks exactly your target % (rounded DOWN to the broker's lot |
//|     step — it will never risk more than you asked for), and sends |
//|     a market order with that stop loss attached immediately.      |
//|   - The SL/TP lines are yours to drag anywhere, any time, even     |
//|     while price is moving — there's no "placing a pending order   |
//|     to preview size" step anymore.                                 |
//|                                                                    |
//|   SETUP:                                                           |
//|   1. Compile this file in MetaEditor (F7).                         |
//|   2. Drag it onto the chart you want to trade from.                |
//|   3. Make sure "Algo Trading" is enabled (top toolbar button) —    |
//|      the buttons do nothing without it.                            |
//|   4. Drag the red SL line to your stop loss, check the Risk % box, |
//|      then click BUY or SELL.                                       |
//|                                                                    |
//|   NOTE: this is a separate EA from MB_TradeLab_EA.mq5 (which logs  |
//|   closed trades to your MB Trade Lab journal). MT5 only allows one |
//|   EA per chart — if you want both running on the same symbol,     |
//|   open a second chart window for it (New Window), or just leave   |
//|   this one running and let the sync EA run on another chart.       |
//+------------------------------------------------------------------+
#property copyright "MB Trade Lab"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum RiskBasisType { RISK_BALANCE, RISK_EQUITY };

input double        RiskPercent          = 1.0;   // Default risk % per click (editable live on-chart too)
input RiskBasisType RiskBasis            = RISK_BALANCE; // % of Balance or of Equity
input bool          UseTakeProfit        = false;  // Show a draggable TP line and attach it to orders
input double        DefaultSLDistancePts = 200;    // Where the SL line starts, in points, on first load
input double        DefaultTPDistancePts = 400;    // Where the TP line starts, in points, on first load
input int           SlippagePoints       = 10;      // Max acceptable slippage on market fill
input int           MagicNumber          = 990011;
input string        ObjPrefix            = "MBRCT_"; // Chart object name prefix

string SLName, TPName, BuyBtnName, SellBtnName, RiskEditName, RiskLblName, InfoName;

//+------------------------------------------------------------------+
int OnInit()
  {
   SLName       = ObjPrefix+"SL";
   TPName       = ObjPrefix+"TP";
   BuyBtnName   = ObjPrefix+"Buy";
   SellBtnName  = ObjPrefix+"Sell";
   RiskEditName = ObjPrefix+"RiskEdit";
   RiskLblName  = ObjPrefix+"RiskLbl";
   InfoName     = ObjPrefix+"Info";

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   CreatePanel();
   UpdateInfoLabel();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, ObjPrefix);
  }

void OnTick()
  {
   UpdateInfoLabel(); // keeps the "if you clicked now" preview honest as price moves
  }

//+------------------------------------------------------------------+
//| Builds the SL/TP lines, Buy/Sell buttons, risk box and info label |
//+------------------------------------------------------------------+
void CreatePanel()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ObjectFind(0, SLName) < 0)
      ObjectCreate(0, SLName, OBJ_HLINE, 0, 0, bid - DefaultSLDistancePts*_Point);
   ObjectSetInteger(0, SLName, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, SLName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, SLName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, SLName, OBJPROP_SELECTABLE, true);
   ObjectSetString(0, SLName, OBJPROP_TEXT, "SL — drag me");

   if(UseTakeProfit)
     {
      if(ObjectFind(0, TPName) < 0)
         ObjectCreate(0, TPName, OBJ_HLINE, 0, 0, bid + DefaultTPDistancePts*_Point);
      ObjectSetInteger(0, TPName, OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(0, TPName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, TPName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, TPName, OBJPROP_SELECTABLE, true);
      ObjectSetString(0, TPName, OBJPROP_TEXT, "TP — drag me");
     }

   CreateButton(BuyBtnName,  "BUY",  20,  20, 75, 30, clrWhite, C'0,140,60');
   CreateButton(SellBtnName, "SELL", 100, 20, 75, 30, clrWhite, C'180,40,40');

   CreateLabelObj(RiskLblName, "Risk %", 185, 20);
   if(ObjectFind(0, RiskEditName) < 0)
      ObjectCreate(0, RiskEditName, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, RiskEditName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, RiskEditName, OBJPROP_XDISTANCE, 185);
   ObjectSetInteger(0, RiskEditName, OBJPROP_YDISTANCE, 34);
   ObjectSetInteger(0, RiskEditName, OBJPROP_XSIZE, 55);
   ObjectSetInteger(0, RiskEditName, OBJPROP_YSIZE, 22);
   ObjectSetString(0, RiskEditName, OBJPROP_TEXT, DoubleToString(RiskPercent, 2));
   ObjectSetInteger(0, RiskEditName, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, RiskEditName, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, RiskEditName, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, RiskEditName, OBJPROP_BGCOLOR, clrWhite);

   if(ObjectFind(0, InfoName) < 0)
      ObjectCreate(0, InfoName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, InfoName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, InfoName, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, InfoName, OBJPROP_YDISTANCE, 65);
   ObjectSetInteger(0, InfoName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, InfoName, OBJPROP_COLOR, clrWhite);
  }

void CreateButton(string name, string text, int x, int y, int w, int h, color textClr, color bg)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void CreateLabelObj(string name, string text, int x, int y)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
  }

//+------------------------------------------------------------------+
//| Reads the on-chart Risk % box (falls back to the input default   |
//| if it's been left empty or typed invalid)                        |
//+------------------------------------------------------------------+
double GetCurrentRiskPercent()
  {
   string s = ObjectGetString(0, RiskEditName, OBJPROP_TEXT);
   double v = StringToDouble(s);
   if(v <= 0 || v > 100)
      return RiskPercent;
   return v;
  }

//+------------------------------------------------------------------+
//| Lots needed so (entry - sl) distance risks exactly riskPercent   |
//| of the account — uses tick value/size so it's correct for ANY    |
//| symbol (forex, metals, indices), not just standard forex pips.   |
//| Rounds DOWN to the broker's lot step on purpose: rounding up      |
//| could silently risk more than what was asked for.                |
//+------------------------------------------------------------------+
double CalcLots(double entryPrice, double slPrice, double riskPercent)
  {
   double slDistance = MathAbs(entryPrice - slPrice);
   if(slDistance <= 0)
      return 0;

   double balance = (RiskBasis == RISK_EQUITY) ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * riskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0)
      return 0;

   double moneyPerLot = (slDistance / tickSize) * tickValue; // $ risk for 1.00 lot at this SL distance
   if(moneyPerLot <= 0)
      return 0;

   double lots = riskAmount / moneyPerLot;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / step) * step; // round DOWN — never risk more than requested
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Live "if you clicked now" preview, refreshed every tick and every |
//| time the SL/TP line is dragged or the risk box is edited          |
//+------------------------------------------------------------------+
void UpdateInfoLabel()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slPrice = ObjectGetDouble(0, SLName, OBJPROP_PRICE, 0);
   double riskPct = GetCurrentRiskPercent();

   double buyLots  = CalcLots(ask, slPrice, riskPct);
   double sellLots = CalcLots(bid, slPrice, riskPct);

   double balance = (RiskBasis == RISK_EQUITY) ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * riskPct / 100.0;

   string txt = StringFormat(
      "Risking %.2f%% = %.2f %s | SL %.1f pts from Bid\nIf BUY now: %.2f lots   |   If SELL now: %.2f lots",
      riskPct, riskMoney, AccountInfoString(ACCOUNT_CURRENCY),
      MathAbs(bid - slPrice) / _Point,
      buyLots, sellLots
   );
   ObjectSetString(0, InfoName, OBJPROP_TEXT, txt);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Fires a market order sized to risk exactly the current % between |
//| the live price and wherever the SL line sits right now            |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type)
  {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Alert("MB RiskClick: enable 'Algo Trading' (top toolbar) before clicking Buy/Sell.");
      return;
     }

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = ObjectGetDouble(0, SLName, OBJPROP_PRICE, 0);
   double tpPrice = UseTakeProfit ? ObjectGetDouble(0, TPName, OBJPROP_PRICE, 0) : 0;

   if(type == ORDER_TYPE_BUY && slPrice >= price)
     {
      Alert("MB RiskClick: Buy blocked — drag the SL line BELOW the current Ask ("+DoubleToString(price,_Digits)+").");
      return;
     }
   if(type == ORDER_TYPE_SELL && slPrice <= price)
     {
      Alert("MB RiskClick: Sell blocked — drag the SL line ABOVE the current Bid ("+DoubleToString(price,_Digits)+").");
      return;
     }

   long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopsLevelPts * _Point;
   if(minDistance > 0 && MathAbs(price - slPrice) < minDistance)
     {
      Alert("MB RiskClick: SL too close to price — this broker requires at least "+(string)stopsLevelPts+" points.");
      return;
     }

   double riskPct = GetCurrentRiskPercent();
   double lots = CalcLots(price, slPrice, riskPct);
   if(lots <= 0)
     {
      Alert("MB RiskClick: could not compute a valid lot size — check the SL line's distance from price.");
      return;
     }

   // Warn (don't block) if the broker's minimum lot size forces the trade to
   // risk more than what was asked for — the trader should know before it fires.
   double balance = (RiskBasis == RISK_EQUITY) ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double actualRiskMoney = (MathAbs(price - slPrice) / tickSize) * tickValue * lots;
   double actualRiskPct = (balance > 0) ? (actualRiskMoney / balance * 100.0) : 0;
   if(actualRiskPct > riskPct + 0.01)
      Print("MB RiskClick: NOTE — broker's minimum lot size (", DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),2),
            ") pushed actual risk to ", DoubleToString(actualRiskPct,2), "% instead of the requested ", DoubleToString(riskPct,2), "%.");

   bool ok = (type == ORDER_TYPE_BUY)
      ? trade.Buy(lots, _Symbol, price, slPrice, tpPrice, "MB RiskClick")
      : trade.Sell(lots, _Symbol, price, slPrice, tpPrice, "MB RiskClick");

   if(ok)
      Print("MB RiskClick: ", (type==ORDER_TYPE_BUY?"BUY":"SELL"), " ", DoubleToString(lots,2), " lots — risking ~",
            DoubleToString(actualRiskMoney,2), " ", AccountInfoString(ACCOUNT_CURRENCY), " (", DoubleToString(actualRiskPct,2), "%)");
   else
      Alert("MB RiskClick: order failed — ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == BuyBtnName)
        {
         ObjectSetInteger(0, BuyBtnName, OBJPROP_STATE, false); // un-press so it's clickable again
         ExecuteTrade(ORDER_TYPE_BUY);
        }
      else if(sparam == SellBtnName)
        {
         ObjectSetInteger(0, SellBtnName, OBJPROP_STATE, false);
         ExecuteTrade(ORDER_TYPE_SELL);
        }
     }

   if(id == CHARTEVENT_OBJECT_DRAG && (sparam == SLName || sparam == TPName))
      UpdateInfoLabel();

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == RiskEditName)
      UpdateInfoLabel();
  }
//+------------------------------------------------------------------+
