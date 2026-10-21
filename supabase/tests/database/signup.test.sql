begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'a@test.dev', '{"display_name": "Ada"}');

select is(
  (select display_name from public.profiles where user_id = '11111111-1111-1111-1111-111111111111'),
  'Ada',
  'signup creates a profile'
);

select results_eq(
  $$select name, role::text, model_policy::text from public.agents
     where user_id = '11111111-1111-1111-1111-111111111111'$$,
  $$values ('Mistral', 'main', 'large')$$,
  'signup creates exactly one main agent named Mistral on the large policy'
);

select is(
  (select quick_call_agent_id from public.profiles where user_id = '11111111-1111-1111-1111-111111111111'),
  (select id from public.agents where user_id = '11111111-1111-1111-1111-111111111111' and role = 'main'),
  'the main agent is the default quick-call agent'
);

select throws_ok(
  $$insert into public.agents (user_id, name, role)
    values ('11111111-1111-1111-1111-111111111111', 'Second', 'main')$$,
  '23505',
  null,
  'a user cannot have two main agents'
);

select lives_ok(
  $$insert into public.agents (user_id, name, role)
    values ('11111111-1111-1111-1111-111111111111', 'Researcher', 'sub')$$,
  'sub-agents are not limited'
);

select is(
  (select count(*)::int from public.agents where user_id = '11111111-1111-1111-1111-111111111111'),
  2,
  'user has a main agent and a sub-agent'
);

select is(
  (select count(*)::int from pg_tables
    where schemaname = 'public'
      and tablename in ('profiles', 'agents', 'conversations', 'messages', 'agent_events',
                        'agent_runs', 'tool_calls', 'usage_ledger')
      and rowsecurity),
  8,
  'RLS is enabled on every table'
);

select * from finish();
rollback;
