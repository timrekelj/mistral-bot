-- Owner-only access. Runtime tables (agent_runs, tool_calls, usage_ledger) and
-- agent_events are written exclusively by the service role, which bypasses RLS.

alter table public.profiles enable row level security;
alter table public.agents enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.agent_events enable row level security;
alter table public.agent_runs enable row level security;
alter table public.tool_calls enable row level security;
alter table public.usage_ledger enable row level security;

-- profiles: created by the signup trigger, never deleted by the client.
create policy "profiles: owner reads" on public.profiles
  for select to authenticated using (user_id = (select auth.uid()));
create policy "profiles: owner updates" on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- agents: the main agent is created at signup and cannot be deleted.
create policy "agents: owner reads" on public.agents
  for select to authenticated using (user_id = (select auth.uid()));
create policy "agents: owner creates sub-agents" on public.agents
  for insert to authenticated
  with check (user_id = (select auth.uid()) and role = 'sub');
create policy "agents: owner updates" on public.agents
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "agents: owner deletes sub-agents" on public.agents
  for delete to authenticated using (user_id = (select auth.uid()) and role = 'sub');

-- role, user_id and mistral_agent_id are server-managed: changing role would let a
-- user mint a second main agent or delete the first.
revoke update on public.agents from authenticated;
grant update (
  name, avatar, instructions, model_policy, voice_model_policy, reasoning_effort, enabled_tools,
  connector_ids, library_ids, skill_ids, voice_id, can_message_agent_ids, is_active
) on public.agents to authenticated;

create policy "conversations: owner reads" on public.conversations
  for select to authenticated using (user_id = (select auth.uid()));
create policy "conversations: owner creates" on public.conversations
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "conversations: owner updates" on public.conversations
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "conversations: owner deletes" on public.conversations
  for delete to authenticated using (user_id = (select auth.uid()));

-- messages: clients may only author user turns; assistant output comes from functions.
create policy "messages: owner reads" on public.messages
  for select to authenticated using (user_id = (select auth.uid()));
create policy "messages: owner sends user turns" on public.messages
  for insert to authenticated
  with check (user_id = (select auth.uid()) and role = 'user');

create policy "agent_events: owner reads" on public.agent_events
  for select to authenticated using (user_id = (select auth.uid()));
create policy "agent_runs: owner reads" on public.agent_runs
  for select to authenticated using (user_id = (select auth.uid()));
create policy "tool_calls: owner reads" on public.tool_calls
  for select to authenticated using (user_id = (select auth.uid()));
create policy "usage_ledger: owner reads" on public.usage_ledger
  for select to authenticated using (user_id = (select auth.uid()));

revoke insert, update, delete on public.agent_events, public.agent_runs, public.tool_calls, public.usage_ledger
  from anon, authenticated;
revoke all on all tables in schema public from anon;
