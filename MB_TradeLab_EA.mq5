//+------------------------------------------------------------------+
//|                                              MB_TradeLab_EA.mq5   |
//|   Sends every closed trade to your MB Trade Lab account so it    |
//|   gets logged automatically — no manual entry needed. Also keeps |
//|   your account's real balance in sync (including deposits and    |
//|   withdrawals) via a lightweight heartbeat, even on days you      |
//|   don't trade. On every startup it also runs a catch-up scan, so  |
//|   trades/deposits/withdrawals that happened while this was off    |
//|   (PC shut down, terminal closed, etc.) still get synced.         |
//|                                                                    |
//|   It also works out each trade's real Risk % on its own: if a      |
//|   stop-loss was attached at the moment the trade opened, it knows  |
//|   the price distance to that stop, the lot size, and the account   |
//|   balance — enough to compute exactly what % of the account was    |
//|   risked, with nothing to type in by hand. (Only works if the SL   |
//|   was set AS the trade opened — one added a few seconds later via  |
//|   a separate modify isn't recorded in the trade's history.)        |
//|                                                                    |
//|   SETUP:                                                          |
//|   1. In MT5: Tools > Options > Expert Advisors > check "Allow     |
//|      WebRequest for listed URL" and add your Supabase project's   |
//|      URL (https://<project-ref>.supabase.co) to the list.         |
//|   2. Compile this file in MetaEditor (F7).                        |
//|   3. Drag it onto any chart. In the Inputs tab, paste the full    |
//|      Webhook URL shown on the Accounts page in the app (it        |
//|      already includes your account id and secret token).          |
//|   4. Check the "Experts" log tab in MT5 for confirmation after     |
//|      your next trade closes.                                      |
//+------------------------------------------------------------------+
#property copyright "MB Trade Lab"
#property version   "1.41"
#property strict

input string WebhookURL = ""; // Full URL from the app's Accounts page
input int    BalancePingMinutes = 15; // How often to refresh the account balance when no trade has closed
input int    CatchupLookbackDays = 3; // First-ever run only: how far back to scan if nothing's been synced before

//+------------------------------------------------------------------+
int OnInit()
  {
   if(WebhookURL=="")
      Print("MB Trade Lab EA: paste your Webhook URL (from the app's Accounts page) into the Inputs tab.");
   if(BalancePingMinutes>0)
      EventSetTimer(BalancePingMinutes*60);
   if(WebhookURL!="")
     {
      RunCatchupScan();
      OnTimer(); // send balance immediately on attach, not just on the next periodic tick — this is what Starting Balance auto-fills from if left blank
     }
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

// Periodic heartbeat — keeps the app's "current balance" fresh even when
// you haven't closed a trade recently (e.g. right after a withdrawal).
void OnTimer()
  {
   SendPayload(StringFormat("{\"account_balance\":%.2f,\"account_currency\":\"%s\"}", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoString(ACCOUNT_CURRENCY)));
  }

// Broker server clocks almost never run on true UTC (commonly UTC+2/+3, with
// their own DST rules) — TimeGMTOffset() is MT5's built-in, always-accurate
// answer for "how far is this server clock from real UTC right now, in
// seconds," so the backend can convert precisely instead of guessing.
string IsoNoTz(datetime t)
  {
   string s = TimeToString(t, TIME_DATE) + "T" + TimeToString(t, TIME_SECONDS);
   StringReplace(s, ".", "-");
   return s;
  }

void SendPayload(string json)
  {
   char postData[]; StringToCharArray(json, postData, 0, StringLen(json));
   char result_data[]; string result_headers;
   int timeout = 5000;

   ResetLastError();
   int res = WebRequest("POST", WebhookURL, "Content-Type: application/json\r\n", timeout, postData, result_data, result_headers);
   if(res == -1)
      Print("MB Trade Lab EA: WebRequest failed, error ", GetLastError(), " — check Options > Expert Advisors > allowed URLs.");
   else
      Print("MB Trade Lab EA: sent, response code ", res);
  }

// % of account balance that was risked, given the entry price, the SL that
// was attached at entry, and the position's volume — 0 if any piece is
// missing (no SL recorded on the opening deal, so it can't be known).
double CalcRiskPercent(double openPrice, double openSL, double volume)
  {
   if(openSL <= 0 || openPrice <= 0 || volume <= 0)
      return 0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   if(tickSize <= 0 || balance <= 0)
      return 0;
   double riskMoney = (MathAbs(openPrice - openSL) / tickSize) * tickValue * volume;
   return NormalizeDouble(riskMoney / balance * 100.0, 2);
  }

// Persists "how far we've scanned" across restarts, per account, so a
// restart doesn't resend the same history every time — only whatever
// closed since the last successful scan.
string CatchupGVName()
  {
   return "MBTL_LastCatchup_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
  }

// Runs once on every EA startup (PC/terminal was off, chart reloaded,
// recompiled, etc.) and resends anything — closed trades, deposits,
// withdrawals — that happened since the last time this ran. Safe to resend
// the same deal more than once: the backend upserts by ticket, so a repeat
// just re-confirms the same row instead of duplicating it.
void RunCatchupScan()
  {
   datetime toTime = TimeCurrent();
   string   gvName = CatchupGVName();
   datetime fromTime = GlobalVariableCheck(gvName)
      ? (datetime)GlobalVariableGet(gvName)
      : toTime - CatchupLookbackDays*24*60*60;

   if(fromTime >= toTime || !HistorySelect(fromTime, toTime))
      return;

   int total = HistoryDealsTotal();
   int sent = 0;
   for(int i=0; i<total; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      long  dealType   = HistoryDealGetInteger(dealTicket, DEAL_TYPE);

      if(dealType == DEAL_TYPE_BALANCE)
        {
         double   amount = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         datetime dTime  = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         SendPayload(StringFormat(
            "{\"kind\":\"transaction\",\"ticket\":%I64u,\"amount\":%.2f,\"time\":\"%s\",\"server_gmt_offset_sec\":%d,\"account_balance\":%.2f,\"account_currency\":\"%s\"}",
            dealTicket, amount, IsoNoTz(dTime), TimeGMTOffset(), AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoString(ACCOUNT_CURRENCY)
         ));
         sent++;
         continue;
        }

      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue; // only closes are trades; opens are picked up below by position

      long     posId      = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      string   symbol     = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      double   closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double   profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double   swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double   commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      datetime closeTime  = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      string   direction  = (dealType == DEAL_TYPE_SELL) ? "buy" : "sell";

      double   openPrice = 0;
      datetime openTime  = 0;
      double   openSL    = 0;
      double   openVolume = 0;
      if(HistorySelectByPosition(posId))
        {
         int posTotal = HistoryDealsTotal();
         for(int j=0; j<posTotal; j++)
           {
            ulong t = HistoryDealGetTicket(j);
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN)
              {
               openPrice  = HistoryDealGetDouble(t, DEAL_PRICE);
               openTime   = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
               openSL     = HistoryDealGetDouble(t, DEAL_SL);
               openVolume = HistoryDealGetDouble(t, DEAL_VOLUME);
               break;
              }
           }
         // HistorySelectByPosition() just swapped out the active history set —
         // restore the date-range selection so the outer loop's total/indices
         // (captured before this) keep referring to the right deals.
         HistorySelect(fromTime, toTime);
        }
      double riskPercent = CalcRiskPercent(openPrice, openSL, openVolume);

      SendPayload(StringFormat(
         "{\"ticket\":%I64u,\"symbol\":\"%s\",\"direction\":\"%s\",\"open_time\":\"%s\",\"close_time\":\"%s\",\"server_gmt_offset_sec\":%d,\"price_open\":%.5f,\"price_close\":%.5f,\"sl\":%.5f,\"risk_percent\":%.2f,\"profit\":%.2f,\"swap\":%.2f,\"commission\":%.2f,\"account_balance\":%.2f,\"account_currency\":\"%s\"}",
         (ulong)posId, symbol, direction, IsoNoTz(openTime), IsoNoTz(closeTime), TimeGMTOffset(),
         openPrice, closePrice, openSL, riskPercent, profit, swap, commission, AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoString(ACCOUNT_CURRENCY)
      ));
      sent++;
     }

   GlobalVariableSet(gvName, (double)toTime);
   Print("MB Trade Lab EA: catch-up scan done, ", sent, " item(s) resent for the time since last run");
  }

//+------------------------------------------------------------------+
//| Fires on every trade-related event; we only act on closing deals |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket))
      return;

   long dealTypeCheck = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   if(dealTypeCheck == DEAL_TYPE_BALANCE)
     {
      // A deposit or withdrawal — not a trade at all, so it's reported
      // separately. Deposits post as a positive DEAL_PROFIT, withdrawals as
      // negative; the sign alone tells the backend which it is.
      double   amount = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      datetime dTime   = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      string json = StringFormat(
         "{\"kind\":\"transaction\",\"ticket\":%I64u,\"amount\":%.2f,\"time\":\"%s\",\"server_gmt_offset_sec\":%d,\"account_balance\":%.2f,\"account_currency\":\"%s\"}",
         dealTicket, amount, IsoNoTz(dTime), TimeGMTOffset(), AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoString(ACCOUNT_CURRENCY)
      );
      SendPayload(json);
      Print("MB Trade Lab EA: ", (amount>=0?"deposit":"withdrawal"), " of ", DoubleToString(MathAbs(amount),2), " sent");
      return;
     }

   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return; // only report closes, not opens

   long     posId       = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   string   symbol      = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   double   closePrice  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double   profit      = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double   swap        = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double   commission  = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   long     dealType    = HistoryDealGetInteger(dealTicket, DEAL_TYPE); // closing side
   datetime closeTime   = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

   // The closing deal's direction is the opposite of the position's own
   // direction — a long position is closed by a sell deal, and vice versa.
   string direction = (dealType == DEAL_TYPE_SELL) ? "buy" : "sell";

   // Find the opening deal for this position to get entry price AND entry
   // time — the app logs "when you took the trade," which means entry, not
   // exit.
   double   openPrice = 0;
   datetime openTime  = 0;
   double   openSL    = 0;
   double   openVolume = 0;
   if(HistorySelectByPosition(posId))
     {
      int total = HistoryDealsTotal();
      for(int i=0; i<total; i++)
        {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            openPrice  = HistoryDealGetDouble(t, DEAL_PRICE);
            openTime   = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
            openSL     = HistoryDealGetDouble(t, DEAL_SL);
            openVolume = HistoryDealGetDouble(t, DEAL_VOLUME);
            break;
           }
        }
     }
   // Real Risk % — computed from the SL that was attached when the trade
   // opened, the lot size, and the account balance. 0 if no SL was recorded
   // at entry (the app falls back to its usual placeholder in that case).
   double riskPercent = CalcRiskPercent(openPrice, openSL, openVolume);

   // account_balance is MT5's own real balance right now (after this trade
   // settled) — the backend uses this as the source of truth for "current
   // balance" instead of summing trades itself, so it can never drift and
   // automatically reflects any deposit or withdrawal too.
   string json = StringFormat(
      "{\"ticket\":%I64u,\"symbol\":\"%s\",\"direction\":\"%s\",\"open_time\":\"%s\",\"close_time\":\"%s\",\"server_gmt_offset_sec\":%d,\"price_open\":%.5f,\"price_close\":%.5f,\"sl\":%.5f,\"risk_percent\":%.2f,\"profit\":%.2f,\"swap\":%.2f,\"commission\":%.2f,\"account_balance\":%.2f,\"account_currency\":\"%s\"}",
      (ulong)posId, symbol, direction, IsoNoTz(openTime), IsoNoTz(closeTime), TimeGMTOffset(),
      openPrice, closePrice, openSL, riskPercent, profit, swap, commission, AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoString(ACCOUNT_CURRENCY)
   );

   SendPayload(json);
   Print("MB Trade Lab EA: trade #", posId, " sent");
  }
//+------------------------------------------------------------------+
