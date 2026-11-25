//+------------------------------------------------------------------+
//|                                                  ROBOTchattyV2.mq5 |
//|  EMA trend + RSI pullback scalper, candle-size TP, wide SL,       |
//|  on-chart dashboard (balance, profit, losses).                   |
//+------------------------------------------------------------------+
#property copyright "ROBOTchattyV2"
#property version   "1.20"
#property description "Frequent-trading trend/pullback EA for small accounts."
#property description "ALWAYS test on a demo account first."

#include <Trade\Trade.mqh>

//--- inputs
input group "=== Trade settings ==="
input double InpLots            = 0.01;     // Lot size (0.01 = smallest on most brokers)
input long   InpMagic           = 1001004;  // Magic number
input int    InpSlippage        = 20;       // Max slippage (points)
input int    InpMaxPositions    = 1;        // Max open trades at once
input int    InpMaxSpreadPoints = 25;       // Skip trading if spread above this (points, 0 = off)

input group "=== Signal settings ==="
input int    InpFastEMA         = 9;        // Fast EMA
input int    InpSlowEMA         = 21;       // Slow EMA
input int    InpRSIPeriod       = 14;       // RSI period
input double InpRSIBuyBelow     = 60.0;     // Buy in uptrend when RSI is below this
input double InpRSISellAbove    = 40.0;     // Sell in downtrend when RSI is above this

input group "=== Exits (based on candle size) ==="
input int    InpCandleLookback  = 10;       // How many recent candles to measure
input double InpTPCandleFactor  = 1.0;      // Take profit = typical candle size x this
input double InpSLtoTPRatio     = 2.5;      // Stop loss = take profit distance x this (bigger = further away)
input bool   InpUseBreakeven    = true;     // Move SL to breakeven after some profit
input double InpBreakevenFrac   = 0.7;      // Breakeven when price has covered this fraction of the way to TP

input group "=== Account protection ==="
input double InpMaxRiskPct      = 10.0;     // Skip trade if SL loss > this % of balance (0 = off)
input double InpMaxDailyLossPct = 10.0;     // Stop opening trades for the day after losing this % (0 = off)

input group "=== Dashboard ==="
input bool   InpShowDashboard   = true;     // Show dashboard on chart

//--- globals
CTrade   trade;
int      hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hRSI = INVALID_HANDLE;
datetime lastBar = 0;

int      dayWins = 0, dayLosses = 0, totalTrades = 0;
double   dayGrossProfit = 0.0, dayGrossLoss = 0.0, dayNet = 0.0, totalNet = 0.0;

const string PREFIX  = "MUSY_";
const int    PANEL_X = 10;
const int    PANEL_Y = 25;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpFastEMA >= InpSlowEMA)
     {
      Print("ROBOTchattyV2: Fast EMA must be smaller than Slow EMA.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   hFast = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI  = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hRSI == INVALID_HANDLE)
     {
      Print("ROBOTchattyV2: failed to create indicators, error ", GetLastError());
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   EventSetTimer(1);
   CreateDashboard();
   RefreshStats();
   UpdateDashboard();
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hRSI  != INVALID_HANDLE) IndicatorRelease(hRSI);
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();

   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime != lastBar)
     {
      lastBar = barTime;
      RefreshStats();
      TryEntry();
     }
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
void OnTrade()
  {
   RefreshStats();
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
//| Entry logic (runs once per new bar, uses the last closed bar)    |
//+------------------------------------------------------------------+
void TryEntry()
  {
   string reason;
   if(!CanOpenTrades(reason))
      return;

   double dummy = 0.0;
   if(CountPositions(dummy) >= InpMaxPositions)
      return;

   double fast[1], slow[1], rsi[1];
   if(CopyBuffer(hFast, 0, 1, 1, fast) < 1 || CopyBuffer(hSlow, 0, 1, 1, slow) < 1 ||
      CopyBuffer(hRSI,  0, 1, 1, rsi)  < 1 || Bars(_Symbol, _Period) <= InpCandleLookback + 2)
     {
      lastBar = 0;   // data not ready yet, try again on the next tick
      return;
     }

   double candle = TypicalCandleSize();
   if(candle <= 0.0)
      return;

   bool buySignal  = (fast[0] > slow[0] && rsi[0] < InpRSIBuyBelow);
   bool sellSignal = (fast[0] < slow[0] && rsi[0] > InpRSISellAbove);

   if(buySignal)
      OpenTrade(true, candle);
   else
      if(sellSignal)
         OpenTrade(false, candle);
  }
//+------------------------------------------------------------------+
void OpenTrade(const bool isBuy, const double candle)
  {
   double lot   = NormalizeLot(InpLots);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = isBuy ? ask : bid;
   if(price <= 0.0)
      return;

   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double floorDist  = MathMax(stopsLevel + 2 * _Point, 10 * _Point);
   double spreadDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double tpDist     = MathMax(candle * InpTPCandleFactor, MathMax(floorDist, 3.0 * spreadDist));
   double slDist     = MathMax(tpDist * InpSLtoTPRatio, floorDist);

   double sl, tp;
   if(isBuy)
     {
      sl = NormalizeDouble(price - slDist, _Digits);
      tp = NormalizeDouble(price + tpDist, _Digits);
     }
   else
     {
      sl = NormalizeDouble(price + slDist, _Digits);
      tp = NormalizeDouble(price - tpDist, _Digits);
     }

   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   //--- enough free margin?
   double margin = 0.0;
   if(OrderCalcMargin(type, _Symbol, lot, price, margin))
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
        {
         Print("ROBOTchattyV2: not enough free margin for ", DoubleToString(lot, 2), " lots.");
         return;
        }

   //--- risk per trade guard
   if(InpMaxRiskPct > 0.0)
     {
      double loss = 0.0;
      if(OrderCalcProfit(type, _Symbol, lot, price, sl, loss))
         if(MathAbs(loss) > AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxRiskPct / 100.0)
           {
            Print("ROBOTchattyV2: trade skipped, stop loss would risk ", DoubleToString(MathAbs(loss), 2),
                  " ", AccountInfoString(ACCOUNT_CURRENCY), " which is more than ", DoubleToString(InpMaxRiskPct, 1), "% of the balance.");
            return;
           }
     }

   bool ok = isBuy ? trade.Buy(lot, _Symbol, 0.0, sl, tp, "ROBOTchattyV2")
             : trade.Sell(lot, _Symbol, 0.0, sl, tp, "ROBOTchattyV2");
   if(ok)
     {
      double pip = (_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point;
      Print("ROBOTchattyV2: ", (isBuy ? "BUY" : "SELL"), " opened. Typical candle ", DoubleToString(candle / pip, 1),
            " pips, TP ", DoubleToString(tpDist / pip, 1), " pips, SL ", DoubleToString(slDist / pip, 1), " pips.");
     }
   else
      Print("ROBOTchattyV2: order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
  }
//+------------------------------------------------------------------+
//| Typical (median) candle size, high minus low, of recent candles  |
//+------------------------------------------------------------------+
double TypicalCandleSize()
  {
   int n = MathMax(InpCandleLookback, 3);
   double sizes[];
   ArrayResize(sizes, n);
   for(int i = 0; i < n; i++)
      sizes[i] = iHigh(_Symbol, _Period, i + 1) - iLow(_Symbol, _Period, i + 1);
   ArraySort(sizes);
   if(n % 2 == 1)
      return(sizes[n / 2]);
   return((sizes[n / 2 - 1] + sizes[n / 2]) / 2.0);
  }
//+------------------------------------------------------------------+
//| Move SL to breakeven once the trade has some profit              |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   if(!InpUseBreakeven)
      return;

   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double buffer     = MathMax((double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), 1.0) * _Point;
   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      if(tp == 0.0)
         continue;
      double trigger = MathAbs(tp - open) * InpBreakevenFrac;

      if(type == POSITION_TYPE_BUY)
        {
         if(bid - open >= trigger)
           {
            double newSL = NormalizeDouble(open + buffer, _Digits);
            if((sl == 0.0 || newSL > sl) && (bid - newSL) > stopsLevel)
               trade.PositionModify(ticket, newSL, tp);
           }
        }
      else
         if(type == POSITION_TYPE_SELL)
           {
            if(open - ask >= trigger)
              {
               double newSL = NormalizeDouble(open - buffer, _Digits);
               if((sl == 0.0 || newSL < sl) && (newSL - ask) > stopsLevel)
                  trade.PositionModify(ticket, newSL, tp);
              }
           }
     }
  }
//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minL, MathMin(maxL, lot));
   if(step > 0.0)
      lot = MathFloor(lot / step + 1e-8) * step;
   if(lot < minL)
      lot = minL;
   return(NormalizeDouble(lot, 3));
  }
//+------------------------------------------------------------------+
//| Counts this EA's open positions and sums their floating P/L      |
//+------------------------------------------------------------------+
int CountPositions(double &floating)
  {
   int count = 0;
   floating = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return(count);
  }
//+------------------------------------------------------------------+
bool CanOpenTrades(string &reason)
  {
   reason = "ACTIVE";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     { reason = "Algo Trading button is OFF"; return(false); }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     { reason = "Algo trading not allowed for this EA"; return(false); }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     { reason = "Account does not allow EA trading"; return(false); }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
     { reason = "Trading disabled on this symbol"; return(false); }

   double startBalance = AccountInfoDouble(ACCOUNT_BALANCE) - dayNet;
   if(InpMaxDailyLossPct > 0.0 && dayNet <= -(startBalance * InpMaxDailyLossPct / 100.0))
     { reason = "PAUSED: daily loss limit reached"; return(false); }

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
     { reason = "Waiting: spread too high"; return(false); }

   return(true);
  }
//+------------------------------------------------------------------+
//| Reads closed-trade history for today and all time (this EA only) |
//+------------------------------------------------------------------+
void RefreshStats()
  {
   dayWins = 0; dayLosses = 0; totalTrades = 0;
   dayGrossProfit = 0.0; dayGrossLoss = 0.0; dayNet = 0.0; totalNet = 0.0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   if(!HistorySelect(0, TimeCurrent()))
      return;

   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0)
         continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
         continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic)
         continue;

      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;

      double p = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                 + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      totalNet += p;
      totalTrades++;

      datetime t = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      if(t >= dayStart)
        {
         dayNet += p;
         if(p >= 0.0) { dayWins++;   dayGrossProfit += p; }
         else         { dayLosses++; dayGrossLoss   += p; }
        }
     }
  }
//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   if(!InpShowDashboard)
      return;

   string bg = PREFIX + "bg";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, PANEL_X);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, PANEL_Y);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, 270);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, 200);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'25,25,30');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
     }
  }
//+------------------------------------------------------------------+
void SetLine(const string name, const int row, const string text, const color clr)
  {
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, PANEL_X + 10);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, PANEL_Y + 8 + row * 18);
      ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
  }
//+------------------------------------------------------------------+
color PnlColor(const double v)
  {
   return(v >= 0.0 ? clrLime : clrTomato);
  }
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDashboard)
      return;

   CreateDashboard();

   double floating = 0.0;
   int    open     = CountPositions(floating);
   string reason;
   bool   ok       = CanOpenTrades(reason);
   string cur      = AccountInfoString(ACCOUNT_CURRENCY);
   long   spread   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   SetLine("l0",  0, "ROBOTchattyV2  " + _Symbol, clrGold);
   SetLine("l1",  1, StringFormat("Balance    : %.2f %s", AccountInfoDouble(ACCOUNT_BALANCE), cur), clrWhite);
   SetLine("l2",  2, StringFormat("Equity     : %.2f %s", AccountInfoDouble(ACCOUNT_EQUITY), cur), clrWhite);
   SetLine("l3",  3, StringFormat("Floating   : %.2f %s", floating, cur), PnlColor(floating));
   SetLine("l4",  4, StringFormat("Today net  : %.2f %s", dayNet, cur), PnlColor(dayNet));
   SetLine("l5",  5, StringFormat("Today profit: %.2f %s", dayGrossProfit, cur), clrLime);
   SetLine("l6",  6, StringFormat("Today loss : %.2f %s", dayGrossLoss, cur), clrTomato);
   SetLine("l7",  7, StringFormat("Wins/Losses: %d / %d", dayWins, dayLosses), clrWhite);
   SetLine("l8",  8, StringFormat("All-time net: %.2f %s (%d trades)", totalNet, cur, totalTrades), PnlColor(totalNet));
   SetLine("l9",  9, StringFormat("Open: %d   Spread: %d pts", open, (int)spread), clrWhite);
   SetLine("l10", 10, "Status: " + reason, ok ? clrLime : clrOrange);

   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
