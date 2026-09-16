-- MB Trade Lab — support contact form storage.
-- Run in the Supabase SQL Editor after 001_subscriptions.sql.
--
-- Anyone (including a logged-out visitor on support.html) can INSERT a
-- message here — that's the whole point of a contact form — but nobody
-- can read them back through the API. Only you (Supabase dashboard) or a
-- future support agent (via the service-role key) can read this table.

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  subject text not null,
  message text not null,
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.support_messages enable row level security;

create policy "anyone can submit a support message"
  on public.support_messages for insert
  to anon, authenticated
  with check (true);

-- No select/update/delete policy for anon or authenticated — intentional.
