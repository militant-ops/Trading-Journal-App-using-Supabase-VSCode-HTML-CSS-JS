//+------------------------------------------------------------------+
//|                                        MB_TradeCopier_EA.mq5      |
//|   Copies trades from one MT5 account (the Master) to any number  |
//|   of other MT5 accounts (Slaves) — as long as all their terminals |
//|   run on this same PC/VPS. Works whether the Master's trade was  |
//|   placed from this terminal, another device, or even the phone   |
//|   app — it copies whatever shows up in the Master account's own  |
//|   trade history, same as MB_TradeLab_EA does for journal sync.   |
//|                                                                    |
//|   HOW IT WORKS:                                                   |
//|   - Attach this EA to ONE chart on the Master account, with       |
//|     Role = Master. It watches for new trades and writes a small   |
//|     signal file into MT5's shared "Common\Files" folder — the     |
//|     one folder every MT5 terminal on this PC can both read and    |
//|     write, regardless of which account or broker it's logged      |
//|     into.                                                          |
//|   - Attach this SAME file to one chart on EACH Slave account,     |
//|     with Role = Slave and MasterAccountLogin set to the Master's  |
//|     account number. Each Slave checks that shared folder every    |
//|     few seconds and copies whatever it finds.                     |
//|   - Each Slave decides its OWN lot size independently — Risk %    |
//|     (sized off its own balance and the Master's stop-loss          |
//|     distance), a fixed Multiplier of the Master's lot size, or a  |
//|     flat Fixed Lots value. Set this differently per account.       |
//|                                                                    |
//|   LIMITS:                                                         |
//|   - All accounts must have their MT5 terminal open on this same   |
//|     PC/VPS — this does not work across separate machines.          |
//|   - Risk % sizing needs a stop-loss attached to the Master's       |
//|     trade at the moment it opens (same rule as the risk-based      |
//|     lot calc in the other EAs) — no SL means that trade is         |
//|     skipped on Slaves using Risk % mode, with a log line saying    |
//|     why, rather than copying it with an undefined risk.            |
//|   - Assumes the same symbol quotes about the same price across    |
//|     accounts (true for the vast majority of brokers on majors/     |
//|     metals) — it mirrors the Master's exact SL/TP price levels.    |
//+------------------------------------------------------------------+
#property copyright "MB Trade Lab"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

enum CopierRole   { ROLE_MASTER, ROLE_SLAVE };
enum SizingMode   { SIZE_RISK_PERCENT, SIZE_MULTIPLIER, SIZE_FIXED_LOTS };

input CopierRole  Role               = ROLE_SLAVE;  // Master: reports trades. Slave: copies them.
input long        MasterAccountLogin = 0;           // SLAVE ONLY — the Master account's login number to follow
input SizingMode  Sizing             = SIZE_RISK_PERCENT; // SLAVE ONLY — how this account's lot size is decided
input double      RiskPercent        = 1.0;   // SLAVE ONLY — used when Sizing = Risk %
input double      Multiplier         = 1.0;   // SLAVE ONLY — used when Sizing = Multiplier (e.g. 2.0 = double the Master's lots)
input double      FixedLots          = 0.01;  // SLAVE ONLY — used when Sizing = Fixed Lots
input int         PollSeconds        = 1;     // SLAVE ONLY — how often to check for new Master trades
input int         SlippagePoints     = 10;
input int         MagicNumber        = 990022;

const string COPIER_DIR = "MBTL_Copier";

//+------------------------------------------------------------------+
int OnInit()
  {
   FolderCreate(COPIER_DIR, FILE_COMMON);
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   if(Role == ROLE_MASTER)
      Print("MB Trade Copier: running as MASTER for account ", AccountInfoInteger(ACCOUNT_LOGIN), " — attach a copy of this EA to each Slave account with Role=Slave and MasterAccountLogin=", AccountInfoInteger(ACCOUNT_LOGIN), ".");
   else
     {
      if(MasterAccountLogin <= 0)
         Print("MB Trade Copier: SLAVE mode needs MasterAccountLogin set in the Inputs tab — paste in the Master account's login number.");
      else
        {
         Print("MB Trade Copier: running as SLAVE, following Master account ", MasterAccountLogin, ".");
         if(PollSeconds > 0)
            EventSetTimer(PollSeconds);
        }
     }
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Strips broker symbol suffixes (EURUSD.a, EURUSD_i, XAUUSDm, ...)  |
//| down to the base instrument code, so Master and Slave symbols     |
//| match even across different brokers.                              |
//+------------------------------------------------------------------+
string BaseSymbol(string s)
  {
   string up = s;
   StringToUpper(up);
   int len = StringLen(up);
   int baseLen = 0;
   for(int i = 0; i < len; i++)
     {
      ushort c = StringGetCharacter(up, i);
      if(c >= 'A' && c <= 'Z')
         baseLen++;
      else
         break;
     }
   if(baseLen < 6)
      baseLen = MathMin(len, 6);
   return StringSubstr(up, 0, MathMin(baseLen, 8));
  }

// Finds the equivalent tradable symbol on THIS account for a symbol name
// reported by the Master (which may be on a different broker) — returns ""
// if nothing matches.
string ResolveLocalSymbol(string masterSymbol)
  {
   string target = BaseSymbol(masterSymbol);
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      if(BaseSymbol(name) == target)
        {
         if(!SymbolSelect(name, true))
            continue;
         return name;
        }
     }
   return "";
  }

//+------------------------------------------------------------------+
//| MASTER SIDE — writes a small signal file whenever a position on   |
//| this account opens or closes, for any Slave EAs to pick up.       |
//+------------------------------------------------------------------+
void WriteSignalFile(string suffix, string contents)
  {
   string name = COPIER_DIR + "\\" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + suffix;
   int handle = FileOpen(name, FILE_WRITE | FILE_COMMON | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      Print("MB Trade Copier: could not write signal file ", name, ", error ", GetLastError());
      return;
     }
   FileWriteString(handle, contents);
   FileClose(handle);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(Role != ROLE_MASTER)
      return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket))
      return;
   if(HistoryDealGetInteger(dealTicket, DEAL_TYPE) == DEAL_TYPE_BALANCE)
      return; // deposits/withdrawals aren't trades — nothing to copy

   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   long posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   if(entry == DEAL_ENTRY_IN)
     {
      // A position just opened — read its live SL/TP right now (this is the
      // one moment we can be sure of what was actually attached at entry).
      double sl = 0, tp = 0, volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      string direction = (dealType == DEAL_TYPE_SELL) ? "SELL" : "BUY"; // this deal itself IS the opening side
      if(PositionSelectByTicket((ulong)posId))
        {
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
        }
      string line = (string)posId + "|" + symbol + "|" + direction + "|" +
                    DoubleToString(volume, 2) + "|" + DoubleToString(price, _Digits) + "|" +
                    DoubleToString(sl, _Digits) + "|" + DoubleToString(tp, _Digits);
      WriteSignalFile((string)posId + "_open.txt", line);
      Print("MB Trade Copier (Master): opened #", posId, " ", symbol, " ", direction, " ", DoubleToString(volume,2), " lots — signal written.");
      return;
     }

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
     {
      WriteSignalFile((string)posId + "_close.txt", (string)posId);
      Print("MB Trade Copier (Master): closed #", posId, " — signal written.");
     }
  }

//+------------------------------------------------------------------+
//| SLAVE SIDE — polls the shared folder for signals from the chosen  |
//| Master account and replicates them on this account.               |
//+------------------------------------------------------------------+
string SeenGVName(string kind, string posId)
  {
   return "MBTL_Copier_" + kind + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + posId;
  }

// Lots needed so (entry - sl) distance risks exactly RiskPercent of this
// account's balance — same formula as the Risk-Click EA, so Risk % mode
// behaves identically to a manually risk-sized trade.
double CalcRiskLots(string symbol, double entryPrice, double slPrice)
  {
   if(slPrice <= 0 || entryPrice <= 0)
      return 0;
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   if(tickSize <= 0 || tickValue <= 0 || balance <= 0)
      return 0;
   double riskAmount  = balance * RiskPercent / 100.0;
   double moneyPerLot = (MathAbs(entryPrice - slPrice) / tickSize) * tickValue;
   if(moneyPerLot <= 0)
      return 0;
   double lots = riskAmount / moneyPerLot;
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / step) * step; // round DOWN — never risk more than requested
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
  }

double NormalizeLots(string symbol, double lots)
  {
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lots = MathRound(lots / step) * step;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lots)), 2);
  }

void ProcessOpenSignal(string posId)
  {
   if(GlobalVariableCheck(SeenGVName("open", posId)))
      return; // already copied this one

   int handle = FileOpen(COPIER_DIR + "\\" + (string)MasterAccountLogin + "_" + posId + "_open.txt", FILE_READ | FILE_COMMON | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   string line = FileReadString(handle);
   FileClose(handle);

   string parts[];
   if(StringSplit(line, '|', parts) < 7)
      return;
   string masterSymbol = parts[1];
   string direction    = parts[2];
   double masterVolume = StringToDouble(parts[3]);
   double masterPrice  = StringToDouble(parts[4]);
   double masterSL     = StringToDouble(parts[5]);
   double masterTP     = StringToDouble(parts[6]);

   string localSymbol = ResolveLocalSymbol(masterSymbol);
   if(localSymbol == "")
     {
      Print("MB Trade Copier: no matching symbol for ", masterSymbol, " on this account — skipped #", posId, ".");
      GlobalVariableSet(SeenGVName("open", posId), 1); // don't keep retrying a symbol that doesn't exist here
      return;
     }

   double lots = 0;
   if(Sizing == SIZE_FIXED_LOTS)
      lots = NormalizeLots(localSymbol, FixedLots);
   else if(Sizing == SIZE_MULTIPLIER)
      lots = NormalizeLots(localSymbol, masterVolume * Multiplier);
   else // SIZE_RISK_PERCENT
     {
      if(masterSL <= 0)
        {
         Print("MB Trade Copier: Master trade #", posId, " had no stop-loss at entry — can't size by Risk %, skipped. Switch this account to Multiplier or Fixed Lots to copy it anyway.");
         GlobalVariableSet(SeenGVName("open", posId), 1);
         return;
        }
      lots = CalcRiskLots(localSymbol, masterPrice, masterSL);
     }
   if(lots <= 0)
     {
      Print("MB Trade Copier: computed lot size was 0 for #", posId, " — skipped.");
      GlobalVariableSet(SeenGVName("open", posId), 1);
      return;
     }

   ENUM_ORDER_TYPE type = (direction == "SELL") ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(localSymbol, SYMBOL_ASK) : SymbolInfoDouble(localSymbol, SYMBOL_BID);

   bool ok = (type == ORDER_TYPE_BUY)
      ? trade.Buy(lots, localSymbol, price, masterSL, masterTP, "MB Copier #" + posId)
      : trade.Sell(lots, localSymbol, price, masterSL, masterTP, "MB Copier #" + posId);

   if(ok)
     {
      // The resulting position's ticket equals its opening deal's ticket —
      // read it back from the deal rather than trusting the order ticket,
      // which isn't always the same thing depending on execution mode.
      ulong dealTicket = trade.ResultDeal();
      ulong slaveTicket = dealTicket;
      if(HistoryDealSelect(dealTicket))
         slaveTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      GlobalVariableSet(SeenGVName("open", posId), 1);
      GlobalVariableSet(SeenGVName("ticket", posId), (double)slaveTicket);
      Print("MB Trade Copier: copied #", posId, " as ", DoubleToString(lots,2), " lots on ", localSymbol, ".");
     }
   else
      Print("MB Trade Copier: copy failed for #", posId, " — ", trade.ResultRetcodeDescription());
  }

void ProcessCloseSignal(string posId)
  {
   if(GlobalVariableCheck(SeenGVName("close", posId)))
      return;
   if(!GlobalVariableCheck(SeenGVName("ticket", posId)))
      return; // never copied this one in the first place

   ulong slaveTicket = (ulong)GlobalVariableGet(SeenGVName("ticket", posId));
   if(PositionSelectByTicket(slaveTicket))
      trade.PositionClose(slaveTicket);
   GlobalVariableSet(SeenGVName("close", posId), 1);
   Print("MB Trade Copier: closed local copy of #", posId, ".");
  }

void OnTimer()
  {
   if(Role != ROLE_SLAVE || MasterAccountLogin <= 0)
      return;

   string fname;
   string prefix = (string)MasterAccountLogin + "_";

   int found = FileFindFirst(COPIER_DIR + "\\" + prefix + "*_open.txt", fname, FILE_COMMON);
   if(found != INVALID_HANDLE)
     {
      do
        {
         string posId = ExtractPosId(fname, prefix, "_open.txt");
         if(posId != "")
            ProcessOpenSignal(posId);
        }
      while(FileFindNext(found, fname));
      FileFindClose(found);
     }

   found = FileFindFirst(COPIER_DIR + "\\" + prefix + "*_close.txt", fname, FILE_COMMON);
   if(found != INVALID_HANDLE)
     {
      do
        {
         string posId = ExtractPosId(fname, prefix, "_close.txt");
         if(posId != "")
            ProcessCloseSignal(posId);
        }
      while(FileFindNext(found, fname));
      FileFindClose(found);
     }
  }

string ExtractPosId(string fname, string prefix, string suffix)
  {
   if(StringLen(fname) <= StringLen(prefix) + StringLen(suffix))
      return "";
   if(StringSubstr(fname, 0, StringLen(prefix)) != prefix)
      return "";
   int end = StringLen(fname) - StringLen(suffix);
   return StringSubstr(fname, StringLen(prefix), end - StringLen(prefix));
  }
//+------------------------------------------------------------------+
