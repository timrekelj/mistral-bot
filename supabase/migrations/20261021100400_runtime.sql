-- Step-based durable runtime (docs/PLAN.md section 2): claim/release RPCs used by
-- agent-step, the pg_net kick on `ready`, and the pg_cron sweeper.

-- Claim -----------------------------------------------------------------------

-- Atomically leases a ready run to one worker and marks it running. Returns null
-- when the run is not claimable or the user already has p_max_running live runs
-- (the run stays ready and the sweeper re-kicks it later).
create function public.claim_agent_run(
  p_run_id uuid,
  p_owner text,
  p_lease_seconds integer default 420,
  p_max_running integer default 6
)
returns public.agent_runs
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_run public.agent_runs;
begin
  select user_id into v_user_id from public.agent_runs where id = p_run_id;
  if v_user_id is null then
    return null;
  end if;

  -- Serialize claims per user so the concurrency cap cannot be raced.
  perform pg_advisory_xact_lock(hashtextextended('agent_runs:' || v_user_id::text, 0));

  if (
    select count(*)
      from public.agent_runs
     where user_id = v_user_id
       and status = 'running'
       and lease_until > now()
       and id <> p_run_id
  ) >= p_max_running then
    return null;
  end if;

  update public.agent_runs
     set status = 'running',
         lease_owner = p_owner,
         lease_until = now() + make_interval(secs => p_lease_seconds),
         started_at = coalesce(started_at, now())
   where id = p_run_id
     and status = 'ready'
     and (lease_until is null or lease_until <= now())
  returning * into v_run;

  return v_run;
end;
$$;

-- Ends the current step: moves the run to its next status, advances step_no and
-- clears the lease. Only the lease owner can release; returns null otherwise.
create function public.release_agent_run(
  p_run_id uuid,
  p_owner text,
  p_status public.run_status,
  p_step_no integer,
  p_next_input jsonb default null,
  p_error text default null
)
returns public.agent_runs
language plpgsql
set search_path = ''
as $$
declare
  v_run public.agent_runs;
begin
  if p_status = 'running' then
    raise exception 'release_agent_run: status must not be running';
  end if;

  update public.agent_runs
     set status = p_status,
         step_no = p_step_no,
         next_input = coalesce(p_next_input, next_input),
         attempts = 0,
         error = left(p_error, 4000),
         lease_owner = null,
         lease_until = null,
         finished_at = case
           when p_status in ('completed', 'failed', 'cancelled') then now()
         end
   where id = p_run_id
     and status = 'running'
     and lease_owner = p_owner
  returning * into v_run;

  return v_run;
end;
$$;

-- Records a failed step and expires the lease so the sweeper retries it on its
-- next tick (or fails the run once max_attempts is reached).
create function public.abandon_agent_run(p_run_id uuid, p_owner text, p_error text)
returns public.agent_runs
language plpgsql
set search_path = ''
as $$
declare
  v_run public.agent_runs;
begin
  update public.agent_runs
     set error = left(p_error, 4000),
         lease_until = now()
   where id = p_run_id
     and status = 'running'
     and lease_owner = p_owner
  returning * into v_run;

  return v_run;
end;
$$;

revoke execute on function public.claim_agent_run(uuid, text, integer, integer) from public, anon, authenticated;
revoke execute on function public.release_agent_run(uuid, text, public.run_status, integer, jsonb, text) from public, anon, authenticated;
revoke execute on function public.abandon_agent_run(uuid, text, text) from public, anon, authenticated;
grant execute on function public.claim_agent_run(uuid, text, integer, integer) to service_role;
grant execute on function public.release_agent_run(uuid, text, public.run_status, integer, jsonb, text) to service_role;
grant execute on function public.abandon_agent_run(uuid, text, text) to service_role;

-- Kick ------------------------------------------------------------------------

-- Fires agent-step for a run. Secrets come from Vault (see supabase/README.md);
-- without them the kick is skipped and the sweeper keeps retrying.
create function private.kick_agent_run(p_run_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_url text;
  v_service_role_key text;
begin
  select decrypted_secret into v_project_url
    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_service_role_key
    from vault.decrypted_secrets where name = 'service_role_key';

  if v_project_url is null or v_service_role_key is null then
    raise warning 'kick_agent_run: vault secrets project_url/service_role_key are not set';
    return null;
  end if;

  return net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/agent-step',
    body := jsonb_build_object('run_id', p_run_id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key
    ),
    timeout_milliseconds := 10000
  );
end;
$$;

revoke execute on function private.kick_agent_run(uuid) from public;

create function private.on_agent_run_ready()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.kick_agent_run(new.id);
  return null;
end;
$$;

create trigger agent_runs_kick
  after insert or update of status on public.agent_runs
  for each row
  when (new.status = 'ready')
  execute function private.on_agent_run_ready();

-- Sweeper ---------------------------------------------------------------------

create function private.sweep_agent_runs(p_stale_after interval default '30 seconds')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Expired leases on the last allowed attempt: give up.
  update public.agent_runs
     set status = 'failed',
         attempts = attempts + 1,
         error = coalesce(error, 'lease expired'),
         lease_owner = null,
         lease_until = null,
         finished_at = now()
   where status = 'running'
     and lease_until <= now()
     and attempts + 1 >= max_attempts;

  -- Out of token budget.
  update public.agent_runs
     set status = 'failed',
         error = 'token budget exceeded',
         finished_at = now()
   where status = 'ready'
     and budget_tokens is not null
     and used_tokens >= budget_tokens;

  -- Expired leases (crashed or timed-out steps) go back to ready; the trigger kicks them.
  update public.agent_runs
     set status = 'ready',
         attempts = attempts + 1,
         lease_owner = null,
         lease_until = null
   where status = 'running'
     and lease_until <= now();

  -- Ready runs whose kick was lost or deferred by the concurrency cap.
  perform private.kick_agent_run(id)
     from public.agent_runs
    where status = 'ready'
      and updated_at < now() - p_stale_after;
end;
$$;

revoke execute on function private.sweep_agent_runs(interval) from public;

select cron.schedule('sweep-agent-runs', '* * * * *', 'select private.sweep_agent_runs()');
