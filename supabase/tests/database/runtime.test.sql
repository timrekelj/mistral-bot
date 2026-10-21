begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users (id, email) values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'runner@test.dev');
insert into public.conversations (id, user_id, agent_id)
select 'c0000000-0000-0000-0000-0000000000dd', user_id, id
  from public.agents where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

create function pg_temp.new_run(p_id uuid, p_status public.run_status default 'ready')
returns uuid
language sql
as $$
  insert into public.agent_runs (id, user_id, agent_id, conversation_id, status)
  select p_id, user_id, id, 'c0000000-0000-0000-0000-0000000000dd', p_status
    from public.agents where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
  returning id;
$$;

select pg_temp.new_run('00000000-0000-0000-0000-000000000001');

-- Claim ------------------------------------------------------------------------
select results_eq(
  $$select status::text, lease_owner, lease_until = now() + interval '420 seconds', started_at is not null
      from public.claim_agent_run('00000000-0000-0000-0000-000000000001', 'w1')$$,
  $$values ('running', 'w1', true, true)$$,
  'first claim leases the run for 420 s and marks it running'
);

select is(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000001', 'w2')).id,
  null,
  'second claim returns null'
);

select is(
  (public.claim_agent_run(gen_random_uuid(), 'w1')).id,
  null,
  'claiming an unknown run returns null'
);

select pg_temp.new_run('00000000-0000-0000-0000-000000000002');
update public.agent_runs set lease_until = now() + interval '1 minute'
 where id = '00000000-0000-0000-0000-000000000002';
select is(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000002', 'w1')).id,
  null,
  'a ready run with a live lease is not claimable'
);

update public.agent_runs set lease_until = now() - interval '1 second'
 where id = '00000000-0000-0000-0000-000000000002';
select is(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000002', 'w1')).lease_owner,
  'w1',
  'a ready run with an expired lease is claimable'
);

-- Release ----------------------------------------------------------------------
select is(
  (public.release_agent_run('00000000-0000-0000-0000-000000000001', 'w2', 'completed', 1)).id,
  null,
  'only the lease owner can release'
);

select results_eq(
  $$select status::text, step_no, lease_owner, lease_until, finished_at is not null
      from public.release_agent_run('00000000-0000-0000-0000-000000000001', 'w1', 'ready', 1,
                                    '{"target_steps": 3}')$$,
  $$values ('ready', 1, null::text, null::timestamptz, false)$$,
  'release to ready advances the step and clears the lease'
);

select is(
  (select next_input from public.agent_runs where id = '00000000-0000-0000-0000-000000000001'),
  '{"target_steps": 3}'::jsonb,
  'release stores next_input'
);

select is(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000001', 'w3')).step_no,
  1,
  'a released ready run is claimable again'
);

select throws_ok(
  $$select public.release_agent_run('00000000-0000-0000-0000-000000000001', 'w3', 'running', 2)$$,
  'P0001',
  null,
  'release cannot leave a run running'
);

select ok(
  (select finished_at is not null
     from public.release_agent_run('00000000-0000-0000-0000-000000000001', 'w3', 'completed', 2)),
  'release to completed sets finished_at'
);

-- Crash recovery -----------------------------------------------------------------
select pg_temp.new_run('00000000-0000-0000-0000-000000000003');
select public.claim_agent_run('00000000-0000-0000-0000-000000000003', 'crashed');
select is(
  (public.abandon_agent_run('00000000-0000-0000-0000-000000000003', 'crashed', 'boom')).error,
  'boom',
  'abandon records the error'
);

select private.sweep_agent_runs();
select results_eq(
  $$select status::text, attempts, lease_owner from public.agent_runs
     where id = '00000000-0000-0000-0000-000000000003'$$,
  $$values ('ready', 1, null::text)$$,
  'the sweeper returns an expired running run to ready and counts the attempt'
);

select is(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000003', 'w4')).lease_owner,
  'w4',
  'a swept run can be reclaimed'
);

update public.agent_runs set attempts = 4, lease_until = now() - interval '1 second'
 where id = '00000000-0000-0000-0000-000000000003';
select private.sweep_agent_runs();
select results_eq(
  $$select status::text, attempts, finished_at is not null from public.agent_runs
     where id = '00000000-0000-0000-0000-000000000003'$$,
  $$values ('failed', 5, true)$$,
  'the sweeper fails a run that exhausts max_attempts'
);

select pg_temp.new_run('00000000-0000-0000-0000-000000000004');
update public.agent_runs set budget_tokens = 100, used_tokens = 100
 where id = '00000000-0000-0000-0000-000000000004';
select private.sweep_agent_runs();
select is(
  (select status::text from public.agent_runs where id = '00000000-0000-0000-0000-000000000004'),
  'failed',
  'the sweeper fails a ready run that is over its token budget'
);

-- Per-user concurrency cap ---------------------------------------------------------
update public.agent_runs set status = 'completed', lease_until = null, lease_owner = null
 where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

select pg_temp.new_run(('00000000-0000-0000-0000-00000000001' || n)::uuid) from generate_series(0, 2) n;

select isnt(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000010', 'w', 420, 2)).id,
  null,
  'first run under the cap is claimed'
);
select isnt(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000011', 'w', 420, 2)).id,
  null,
  'second run under the cap is claimed'
);
select is(
  (public.claim_agent_run('00000000-0000-0000-0000-000000000012', 'w', 420, 2)).id,
  null,
  'a run over the per-user cap is not claimed'
);
select is(
  (select status::text from public.agent_runs where id = '00000000-0000-0000-0000-000000000012'),
  'ready',
  'the deferred run stays ready for the sweeper'
);

select * from finish();
rollback;
