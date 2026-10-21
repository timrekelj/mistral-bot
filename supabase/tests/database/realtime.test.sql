begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'alice@test.dev'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob@test.dev');
insert into public.conversations (id, user_id)
values ('c0000000-0000-0000-0000-00000000000a', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Realtime authorizes a channel join by selecting from realtime.messages with
-- realtime.topic set to the channel name: any visible row means access.
insert into realtime.messages (topic, extension, event, payload, private)
values ('conversation:c0000000-0000-0000-0000-00000000000a', 'broadcast', 'probe', '{}', true),
       ('conversation:c0000000-0000-0000-0000-0000000000ff', 'broadcast', 'probe', '{}', true);

set local role authenticated;

select set_config('request.jwt.claims',
  '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}', true);
select set_config('realtime.topic', 'conversation:c0000000-0000-0000-0000-00000000000a', true);
select ok(exists (select 1 from realtime.messages), 'owner can join their conversation topic');

select set_config('realtime.topic', 'conversation:c0000000-0000-0000-0000-0000000000ff', true);
select is((select count(*)::int from realtime.messages), 0, 'unknown conversation topics are denied');

select set_config('realtime.topic', 'conversation:c0000000-0000-0000-0000-00000000000a', true);
select set_config('request.jwt.claims',
  '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "role": "authenticated"}', true);
select is((select count(*)::int from realtime.messages), 0, 'other users cannot join the topic');

reset role;
select set_config('realtime.topic', 'conversation:c0000000-0000-0000-0000-00000000000a', true);
select set_config('request.jwt.claims', '{"role": "anon"}', true);
set local role anon;
select is((select count(*)::int from realtime.messages), 0, 'anonymous clients cannot join');

select * from finish();
rollback;
