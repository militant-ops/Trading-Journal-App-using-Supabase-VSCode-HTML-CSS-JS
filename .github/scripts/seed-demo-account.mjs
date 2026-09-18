// Ensures the demo account (DEMO_ACCOUNT_EMAIL / DEMO_ACCOUNT_PASSWORD)
// exists and has a handful of clearly-synthetic sample trades in
// mido_trades, so the app's dashboard/journal/analytics views have
// realistic-looking data for marketing screenshots.
//
// Signs in as a normal user (not service-role) — the same anon key and
// auth flow the app itself uses — so this only ever writes the demo
// account's own rows, same as a real user would. The demo account still
// needs to be exempted from the subscription paywall via
// supabase/sql/005_access_exemptions.sql, run once by a human in the
// Supabase SQL Editor (that table has no API access by design).
import { createClient } from '@supabase/supabase-js';
import ws from 'ws';

const SB_URL = 'https://sijfjwvvlfjhnhyvozka.supabase.co';
const SB_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNpamZqd3Z2bGZqaG5oeXZvemthIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwMjY4NDMsImV4cCI6MjEwMzYwMjg0M30.p2RprpeKR-GRzCU8O6PcqmBmnj1rTSZQHNzJL56-fvM';

const email = process.env.DEMO_ACCOUNT_EMAIL;
const password = process.env.DEMO_ACCOUNT_PASSWORD;
if (!email || !password) {
  console.log('DEMO_ACCOUNT_EMAIL/DEMO_ACCOUNT_PASSWORD not set — skipping demo data seed.');
  process.exit(0);
}

// Node 20's runner has no native WebSocket, and supabase-js always spins up
// a RealtimeClient in createClient() even though this script never uses
// realtime subscriptions — so it needs an explicit transport or the import
// throws before any REST/auth call is made.
const supabase = createClient(SB_URL, SB_ANON_KEY, { realtime: { transport: ws } });

async function ensureSignedIn() {
  const signIn = await supabase.auth.signInWithPassword({ email, password });
  if (!signIn.error) return signIn.data;

  console.log('Sign-in failed, attempting sign-up:', signIn.error.message);
  const signUp = await supabase.auth.signUp({
    email,
    password,
    options: { data: { first_name: 'Demo', last_name: 'Account' } },
  });
  if (signUp.error) throw signUp.error;

  const retry = await supabase.auth.signInWithPassword({ email, password });
  if (retry.error) throw retry.error;
  return retry.data;
}

function isoDateDaysAgo(days) {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().slice(0, 10);
}

function demoTrades() {
  // Fixed ids so re-runs upsert/refresh instead of piling up duplicates.
  return [
    {
      id: 'demo-trade-1', pair: 'EURUSD', date: isoDateDaysAgo(1), time: '09:15',
      session: 'London', setup: 'Break and Retest', context: 'Trend Continuation',
      direction: 'Buy', risk: 1, outcome: 'Win', rr: 2.4, amount: 312,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
    {
      id: 'demo-trade-2', pair: 'XAUUSD', date: isoDateDaysAgo(2), time: '13:40',
      session: 'New York', setup: 'Liquidity Sweep', context: 'Reversal',
      direction: 'Sell', risk: 1.5, outcome: 'Loss', rr: -1, amount: -145,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
    {
      id: 'demo-trade-3', pair: 'GBPUSD', date: isoDateDaysAgo(3), time: '08:05',
      session: 'London', setup: 'Order Block', context: 'Trend Continuation',
      direction: 'Buy', risk: 1, outcome: 'Win', rr: 3.1, amount: 405,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
    {
      id: 'demo-trade-4', pair: 'USDJPY', date: isoDateDaysAgo(5), time: '23:10',
      session: 'Asia', setup: 'Range Fade', context: 'Range',
      direction: 'Sell', risk: 1, outcome: 'BE', rr: 0, amount: 0,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
    {
      id: 'demo-trade-5', pair: 'EURUSD', date: isoDateDaysAgo(6), time: '10:30',
      session: 'London', setup: 'Break and Retest', context: 'Trend Continuation',
      direction: 'Buy', risk: 1.2, outcome: 'Win', rr: 1.8, amount: 220,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
    {
      id: 'demo-trade-6', pair: 'GBPJPY', date: isoDateDaysAgo(8), time: '07:50',
      session: 'London', setup: 'Liquidity Sweep', context: 'Reversal',
      direction: 'Sell', risk: 1, outcome: 'Loss', rr: -1, amount: -160,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
    {
      id: 'demo-trade-7', pair: 'XAUUSD', date: isoDateDaysAgo(9), time: '14:20',
      session: 'New York', setup: 'Order Block', context: 'Trend Continuation',
      direction: 'Buy', risk: 1.5, outcome: 'Win', rr: 2.9, amount: 470,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
    {
      id: 'demo-trade-8', pair: 'EURUSD', date: isoDateDaysAgo(11), time: '09:05',
      session: 'London', setup: 'Range Fade', context: 'Range',
      direction: 'Sell', risk: 1, outcome: 'Win', rr: 1.5, amount: 165,
      trade_type: 'Live', strategy: 'main', chart: '', notes: 'Demo data — for marketing screenshots only.',
      images: [], missed: false,
    },
  ];
}

async function main() {
  const { user } = await ensureSignedIn();
  console.log('Signed in as demo account:', user.id);

  const trades = demoTrades().map((t) => ({ ...t, user_id: user.id }));
  const { error } = await supabase.from('mido_trades').upsert(trades, {
    onConflict: 'id',
  });

  if (error) {
    if (/row-level security|permission denied/i.test(error.message)) {
      console.error(
        'Insert blocked by RLS. The demo account needs to be exempted from the ' +
          'subscription paywall — run supabase/sql/005_access_exemptions.sql for ' +
          'this account in the Supabase SQL Editor, then re-run this workflow.'
      );
      process.exit(1);
    }
    throw error;
  }

  console.log(`Seeded ${trades.length} demo trades.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
