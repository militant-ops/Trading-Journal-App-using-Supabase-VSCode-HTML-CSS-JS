-- MB Trade Lab — adds which plan (monthly/yearly) a subscriber is on.
-- Run this once in the Supabase SQL Editor, after 001_subscriptions.sql.
--
-- Set by stripe-webhook only (same rule as every other column on this
-- table — see 001_subscriptions.sql for why the client never writes here).
-- Null until someone actually subscribes (trialing users have no plan yet).

alter table public.subscriptions
  add column if not exists plan text; -- 'monthly' | 'yearly' | null
