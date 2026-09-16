-- MB Trade Lab — subscriptions / trial tracking
-- Run this once in the Supabase SQL Editor (Dashboard → SQL Editor → New query → paste → Run).
--
-- Every new signup gets a row here automatically (via the trigger below):
-- a 14-day trial starting the moment they sign up. Stripe webhook events
-- (see supabase/functions/stripe-webhook) are the ONLY thing allowed to
-- change status after that — the client never writes to this table, so a
-- user can't extend their own trial or fake "active" from devtools.

create table if not exists public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'trialing',            -- trialing | active | past_due | canceled
  trial_started_at timestamptz not null default now(),
  trial_ends_at timestamptz not null default (now() + interval '14 days'),
  stripe_customer_id text,
  stripe_subscription_id text,
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

-- Users can read their own row (needed for the client-side paywall check).
create policy "read own subscription"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- No insert/update/delete policy for anon or authenticated roles on purpose —
-- only the service-role key (used inside the Stripe edge functions) can
-- write here, since service role bypasses RLS entirely.

-- Auto-create the trial row the instant someone signs up.
create or replace function public.handle_new_user_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.subscriptions (user_id, status, trial_started_at, trial_ends_at)
  values (new.id, 'trialing', now(), now() + interval '14 days');
  return new;
end;
$$;

create or replace trigger on_auth_user_created_subscription
  after insert on auth.users
  for each row execute function public.handle_new_user_subscription();
