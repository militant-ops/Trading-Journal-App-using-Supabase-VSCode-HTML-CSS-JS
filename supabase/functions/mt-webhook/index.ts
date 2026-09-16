// Supabase Edge Function — receives closed-trade pings from the MB Trade Lab
// MT4/MT5 Expert Advisor (see MB_TradeLab_EA.mq5) and logs them automatically.
//
// Deploy with the Supabase CLI from the project root:
//   supabase functions deploy mt-webhook --no-verify-jwt
//
// --no-verify-jwt is required: MT4/5 has no Supabase login token to send, only
// the account id + webhook_token in the URL, which this function checks itself.
// Without that flag Supabase rejects every call with 401 before your code runs.
//
// No extra secrets to set — SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
// injected automatically for every Edge Function. The service-role key is
// required here (not the anon key) because this function authenticates the
// caller itself via the account's webhook_token, not via a logged-in user JWT.
//
// The EA calls:
//   POST https://<project-ref>.supabase.co/functions/v1/mt-webhook?account=<id>&token=<secret>
//   Trade body: { ticket, symbol, direction, open_time, close_time,
//           server_gmt_offset_sec, price_open, price_close, sl, tp, profit,
//           swap, commission, risk_percent, account_balance, account_currency }
// risk_percent is computed by the EA itself from the SL attached at entry,
// the lot size, and the account balance at close time — real risk % with no
// manual entry, whenever a stop-loss was set as the trade opened. 0/absent
// means the EA couldn't determine it (no SL recorded at entry), in which
// case the placeholder below is used instead.
//   Heartbeat body (periodic, no trade): { account_balance, account_currency }
//   Transaction body (deposit/withdrawal): { kind: "transaction", ticket,
//           amount, time, server_gmt_offset_sec, account_balance, account_currency }
// account_currency is MT5's own AccountInfoString(ACCOUNT_CURRENCY) — stored
// per-account so the app can show the right symbol ($/€/£/etc.) for THIS
// account's figures instead of always using one global Settings currency,
// which would be wrong for any account not in that currency.
// open_time/close_time are the broker's own wall-clock (no timezone marker),
// and server_gmt_offset_sec (from MT5's TimeGMTOffset()) is how far that
// clock sits from true UTC right now — brokers are almost never on real UTC,
// and the offset shifts with each side's own DST, so this is computed by MT5
// itself rather than assumed here.
// account_balance is MT5's own real balance (AccountInfoDouble(ACCOUNT_BALANCE))
// at send-time — used as the source of truth for "current balance" instead of
// summing trades ourselves, so it can't drift and automatically reflects any
// deposit or withdrawal.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Converts the broker's naive wall-clock string + its GMT offset into a true
// UTC instant (milliseconds since epoch).
function toTrueUtcMillis(naiveIso: string, offsetSec: number): number {
  const asIfUtc = Date.parse(naiveIso.replace(/\./g, "-") + "Z");
  return asIfUtc - offsetSec * 1000;
}

// Trader's own session hours, in real UK local time (handles GMT/BST
// automatically via the Europe/London timezone — no manual DST maintenance).
const LONDON_TZ_FMT = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/London",
  year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});
function londonParts(utcMillis: number) {
  const parts = Object.fromEntries(LONDON_TZ_FMT.formatToParts(new Date(utcMillis)).map((p) => [p.type, p.value]));
  return { date: `${parts.year}-${parts.month}-${parts.day}`, time: `${parts.hour}:${parts.minute}`, hour: parseInt(parts.hour, 10) };
}
// 8am-11:59am London, 12pm-9pm New York (this trader's own defined hours —
// adjust here if they ever change).
function sessionForLondonHour(h: number): string {
  if (h >= 8 && h < 12) return "London";
  if (h >= 12 && h < 21) return "New York";
  return "Out of Session";
}

// Brokers often suffix symbols (EURUSD.a, EURUSD_i, EURUSDm, ...) — strip
// anything after the base 6-8 char instrument code so it matches the app's
// own pair list.
function normalizePair(symbol: string): string {
  const m = symbol.match(/^[A-Z]{6,8}/);
  return (m ? m[0] : symbol).toUpperCase();
}

// Shared "mark this account as freshly synced" update, used by all three
// payload kinds (transaction/heartbeat/trade) — keeps balance and currency
// current wherever the EA happens to report them from. If the trader never
// typed in a Starting Balance themselves, the first balance MT5 ever reports
// becomes it automatically — that's the true "balance when connected" moment,
// and without this it would just sit as "Not set" forever until edited by hand.
function buildAcctUpdate(accountBalance: unknown, accountCurrency: unknown, existingStartingBalance: unknown) {
  const update: Record<string, unknown> = {
    status: "connected", last_synced_at: new Date().toISOString(), last_error: null,
  };
  if (accountBalance != null) {
    update.current_balance = Number(accountBalance);
    if (existingStartingBalance == null) update.starting_balance = Number(accountBalance);
  }
  if (accountCurrency) update.currency = String(accountCurrency).toUpperCase();
  return update;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const url = new URL(req.url);
  const accountId = url.searchParams.get("account");
  const token = url.searchParams.get("token");
  if (!accountId || !token) {
    return new Response(JSON.stringify({ error: "Missing account or token" }), { status: 400 });
  }

  const { data: account, error: acctErr } = await supabase
    .from("mido_accounts")
    .select("id, user_id, strategy, webhook_token, starting_balance")
    .eq("id", accountId)
    .single();

  if (acctErr || !account || account.webhook_token !== token) {
    return new Response(JSON.stringify({ error: "Invalid account or token" }), { status: 401 });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 });
  }

  const {
    kind, ticket, symbol, direction, open_time, close_time, time,
    server_gmt_offset_sec, price_open, price_close, sl, profit, swap, commission, amount,
    risk_percent, account_balance, account_currency,
  } = body;

  // A deposit or withdrawal — not a trade. Deposits arrive as a positive
  // amount, withdrawals negative; stored as always-positive + a type label.
  if (kind === "transaction") {
    if (!ticket || amount == null || !time) {
      return new Response(JSON.stringify({ error: "Missing ticket, amount, or time for transaction" }), { status: 400 });
    }
    const utcMillis = toTrueUtcMillis(time, Number(server_gmt_offset_sec) || 0);
    const { date } = londonParts(utcMillis);
    const txn = {
      user_id: account.user_id,
      account_id: account.id,
      type: Number(amount) >= 0 ? "deposit" : "withdrawal",
      amount: Math.abs(Number(amount)),
      date,
      time: londonParts(utcMillis).time,
      external_id: String(ticket),
    };
    const { error: txnErr } = await supabase
      .from("mido_account_transactions")
      .upsert(txn, { onConflict: "account_id,external_id" });
    if (txnErr) {
      return new Response(JSON.stringify({ error: txnErr.message }), { status: 500 });
    }
    await supabase.from("mido_accounts").update(buildAcctUpdate(account_balance, account_currency, account.starting_balance)).eq("id", account.id);
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  }

  // Balance-only heartbeat (no ticket) — the EA sends this periodically so the
  // account's real balance stays fresh even on days with no closed trade,
  // which is also how a deposit/withdrawal gets picked up without a trade.
  if (!ticket) {
    if (account_balance == null) {
      return new Response(JSON.stringify({ error: "Missing ticket (trade) or account_balance (heartbeat)" }), { status: 400 });
    }
    await supabase.from("mido_accounts").update(buildAcctUpdate(account_balance, account_currency, account.starting_balance)).eq("id", account.id);
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  }

  if (!symbol || !(open_time || close_time)) {
    return new Response(JSON.stringify({ error: "Missing symbol or open_time/close_time" }), { status: 400 });
  }

  const netAmount = (Number(profit) || 0) + (Number(swap) || 0) + (Number(commission) || 0);
  const outcome = netAmount > 0 ? "Win" : netAmount < 0 ? "Loss" : "BE";
  // "Time I took the trade" = entry, not exit — fall back to close_time only
  // for payloads from an older EA build that didn't send open_time yet.
  const entryUtcMillis = toTrueUtcMillis(open_time || close_time, Number(server_gmt_offset_sec) || 0);
  const { date, time, hour } = londonParts(entryUtcMillis);
  const session = sessionForLondonHour(hour);

  // R:R isn't something MT4/5 reports directly — if a stop-loss was set we can
  // approximate it from distance-to-SL vs. the actual move, otherwise this is
  // left blank and the app's currency view (which this trade always has an
  // amount for) is what's shown instead of R:R for it.
  let rr: number | null = null;
  if (sl && price_open && price_close) {
    const riskDistance = Math.abs(Number(price_open) - Number(sl));
    const moveDistance = Math.abs(Number(price_close) - Number(price_open));
    if (riskDistance > 0) {
      rr = Number((moveDistance / riskDistance).toFixed(2));
      if (outcome === "Loss") rr = -Math.abs(rr);
    }
  }

  const trade = {
    // mido_trades.id is plain text (app generates it client-side) with no DB
    // default, and must stay IDENTICAL across retries of the same ticket —
    // this upsert updates every column named here on conflict, so a random id
    // would get overwritten on each resend. Deriving it from (account, ticket)
    // keeps it stable no matter how many times this trade is (re)synced.
    id: account.id + "-" + ticket,
    user_id: account.user_id, // required — mido_trades RLS is keyed on this; without it the row is invisible to its own owner
    pair: normalizePair(symbol),
    date, time, session,
    direction: /sell/i.test(String(direction)) ? "Sell" : "Buy",
    outcome,
    rr: rr ?? 0,
    amount: netAmount,
    // Real risk % from the EA when it could work one out (SL was set at
    // entry); otherwise the same 1% placeholder as before, until edited.
    risk: risk_percent && Number(risk_percent) > 0 ? Number(risk_percent) : 1,
    trade_type: "Live",
    strategy: account.strategy,
    source: "auto",
    account_id: account.id,
    external_id: String(ticket),
    notes: "",
    chart: "",
    images: [],
  };

  const { error: upsertErr } = await supabase
    .from("mido_trades")
    .upsert(trade, { onConflict: "account_id,external_id" });

  if (upsertErr) {
    await supabase.from("mido_accounts").update({
      status: "error", last_error: upsertErr.message,
    }).eq("id", account.id);
    return new Response(JSON.stringify({ error: upsertErr.message }), { status: 500 });
  }

  await supabase.from("mido_accounts").update(buildAcctUpdate(account_balance, account_currency, account.starting_balance)).eq("id", account.id);

  return new Response(JSON.stringify({ ok: true }), { status: 200 });
});
