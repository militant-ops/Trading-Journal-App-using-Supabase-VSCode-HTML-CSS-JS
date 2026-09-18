-- MB Trade Lab — server-side trial/subscription enforcement.
-- Run this once in the Supabase SQL Editor, after 001–003.
--
-- The app already blocks the UI with a paywall once a trial expires or a
-- subscription lapses (see checkSubscriptionGate() in mb-trade-lab.html),
-- but that's a client-side check only — the existing RLS policies on trade
-- data just check "is this your own row," not "have you paid." Someone
-- deliberately bypassing the app's JS (devtools, a direct API call with
-- their own login token) could still read/write their own trades after
-- their trial ran out. This closes that gap at the database level, which
-- no amount of client-side bypassing can get around.
--
-- Approach: a RESTRICTIVE policy on each table, in addition to whatever
-- permissive "own rows only" policy already exists. Postgres ANDs a
-- restrictive policy with the permissive ones — so this never needs to
-- know or touch the existing ownership policies, it only ever narrows
-- what they already allow. The Stripe webhook (which writes via the
-- service-role key) bypasses RLS entirely, same as it always has, so
-- auto-sync keeps working in the background even during a lapsed trial —
-- the user just can't see or edit it through the app until they pay.

create or replace function public.has_active_access(uid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.subscriptions
    where user_id = uid
      and (
        status = 'active'
        or (status = 'trialing' and trial_ends_at > now())
      )
  );
$$;

-- Journal data: gated. Feedback is deliberately NOT gated below — someone
-- whose trial just lapsed should still be able to tell us why, or report a
-- billing problem, without having to pay first.
do $$
declare
  t text;
begin
  foreach t in array array['mido_trades','mido_strategies','mido_accounts','mido_account_transactions','mido_summaries']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists "requires active subscription" on public.%I', t);
      execute format(
        'create policy "requires active subscription" on public.%I as restrictive for all using (public.has_active_access(auth.uid())) with check (public.has_active_access(auth.uid()))',
        t
      );
    end if;
  end loop;
end $$;
