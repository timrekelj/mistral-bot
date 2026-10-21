begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'alice@test.dev'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob@test.dev');

-- Alice's fixtures, written as postgres (as the functions would with the service role).
insert into public.conversations (id, user_id, agent_id)
select 'c0000000-0000-0000-0000-00000000000a', user_id, id
  from public.agents where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into public.messages (conversation_id, user_id, role, content)
values ('c0000000-0000-0000-0000-00000000000a', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'user',
        '[{"type": "text", "text": "hi"}]');
insert into public.agent_runs (user_id, agent_id, conversation_id, status)
select user_id, id, 'c0000000-0000-0000-0000-00000000000a', 'completed'
  from public.agents where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- As Bob ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "role": "authenticated"}', true);

select is((select count(*)::int from public.profiles), 1, 'bob sees only his profile');
select is((select count(*)::int from public.agents), 1, 'bob sees only his agent');
select is_empty('select 1 from public.conversations', 'bob cannot see alice''s conversation');
select is_empty('select 1 from public.messages', 'bob cannot see alice''s messages');
select is_empty('select 1 from public.agent_runs', 'bob cannot see alice''s runs');

select throws_ok(
  $$insert into public.messages (conversation_id, user_id, role, content)
    values ('c0000000-0000-0000-0000-00000000000a', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'user', '[]')$$,
  '23503',
  null,
  'bob cannot post into alice''s conversation under his own id'
);

select throws_ok(
  $$insert into public.messages (conversation_id, user_id, role, content)
    values ('c0000000-0000-0000-0000-00000000000a', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'user', '[]')$$,
  '42501',
  null,
  'bob cannot post into alice''s conversation as alice'
);

select throws_ok(
  $$insert into public.conversations (user_id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  '42501',
  null,
  'bob cannot create a conversation owned by alice'
);

update public.conversations set title = 'pwned' where id = 'c0000000-0000-0000-0000-00000000000a';

select throws_ok(
  $$insert into public.agent_runs (user_id, agent_id, conversation_id)
    select user_id, id, 'c0000000-0000-0000-0000-00000000000a' from public.agents$$,
  '42501',
  null,
  'clients cannot enqueue runs directly'
);

select throws_ok(
  $$update public.agents set role = 'sub'$$,
  '42501',
  null,
  'clients cannot change an agent''s role'
);

select throws_ok(
  $$select public.claim_agent_run(gen_random_uuid(), 'bob')$$,
  '42501',
  null,
  'clients cannot call runtime RPCs'
);

-- Bob's own data works.
select lives_ok(
  $$insert into public.conversations (id, user_id, agent_id)
    select 'c0000000-0000-0000-0000-00000000000b', user_id, id from public.agents$$,
  'bob can create his own conversation'
);
select lives_ok(
  $$insert into public.messages (conversation_id, user_id, role, content)
    values ('c0000000-0000-0000-0000-00000000000b', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'user',
            '[{"type": "text", "text": "hello"}]')$$,
  'bob can send a user message'
);
select throws_ok(
  $$insert into public.messages (conversation_id, user_id, role, content)
    values ('c0000000-0000-0000-0000-00000000000b', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'assistant', '[]')$$,
  '42501',
  null,
  'clients cannot author assistant messages'
);
select isnt(
  (select last_message_at from public.conversations where id = 'c0000000-0000-0000-0000-00000000000b'),
  null,
  'sending a message touches the conversation'
);

-- As Alice -------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}', true);

select is(
  (select title from public.conversations where id = 'c0000000-0000-0000-0000-00000000000a'),
  null,
  'bob''s update did not touch alice''s conversation'
);
select is((select count(*)::int from public.agent_runs), 1, 'alice can read her runs');

select * from finish();
rollback;
