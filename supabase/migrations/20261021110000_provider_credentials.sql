-- Bring-your-own-key: per-user provider API keys. The key itself lives in Supabase
-- Vault; this table only holds the reference plus display metadata. Clients can read
-- the metadata of their own rows and nothing else; all writes go through the
-- service-role RPCs below (called by the api-keys Edge Function).

create table public.provider_credentials (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  provider text not null check (provider in ('mistral')),
  vault_secret_id uuid not null unique,
  key_hint text not null check (char_length(key_hint) <= 8),
  status text not null default 'valid' check (status in ('valid', 'invalid')),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, provider)
);

create trigger provider_credentials_set_updated_at before update on public.provider_credentials
  for each row execute function private.set_updated_at();

alter table public.provider_credentials enable row level security;

create policy "provider_credentials: owner reads" on public.provider_credentials
  for select to authenticated using (user_id = (select auth.uid()));

-- Column-level grant: vault_secret_id (and user_id) are never readable by clients.
revoke all on public.provider_credentials from public, anon, authenticated;
grant select (provider, key_hint, status, verified_at, updated_at)
  on public.provider_credentials to authenticated;

-- Deleting a credential (directly or via account deletion) removes its Vault secret.
create function private.delete_provider_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets where id = old.vault_secret_id;
  return null;
end;
$$;

create trigger provider_credentials_delete_secret
  after delete on public.provider_credentials
  for each row execute function private.delete_provider_secret();

-- RPCs (service role only) ------------------------------------------------------

-- Creates or rotates the user's key for a provider and returns the updated row.
create function public.set_provider_key(
  p_user_id uuid,
  p_provider text,
  p_key text,
  p_status text default 'valid'
)
returns public.provider_credentials
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := format('provider_key:%s:%s', p_user_id, p_provider);
  v_secret_id uuid;
  v_row public.provider_credentials;
begin
  if p_key is null or char_length(p_key) < 8 then
    raise exception 'set_provider_key: key is too short' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_name, 0));

  select id into v_secret_id from vault.secrets where name = v_name;
  if v_secret_id is null then
    v_secret_id := vault.create_secret(p_key, v_name, 'BYOK API key');
  else
    perform vault.update_secret(v_secret_id, p_key);
  end if;

  insert into public.provider_credentials (user_id, provider, vault_secret_id, key_hint, status, verified_at)
  values (
    p_user_id,
    p_provider,
    v_secret_id,
    '…' || right(p_key, 4),
    p_status,
    case when p_status = 'valid' then now() end
  )
  on conflict (user_id, provider) do update
     set vault_secret_id = excluded.vault_secret_id,
         key_hint = excluded.key_hint,
         status = excluded.status,
         verified_at = excluded.verified_at
  returning * into v_row;

  return v_row;
end;
$$;

-- Decrypted key, or null when the user has none.
create function public.get_provider_key(p_user_id uuid, p_provider text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select s.decrypted_secret
    from public.provider_credentials c
    join vault.decrypted_secrets s on s.id = c.vault_secret_id
   where c.user_id = p_user_id
     and c.provider = p_provider;
$$;

-- Removes the key; returns whether one existed. The trigger deletes the Vault secret.
create function public.delete_provider_key(p_user_id uuid, p_provider text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.provider_credentials where user_id = p_user_id and provider = p_provider;
  return found;
end;
$$;

revoke execute on function public.set_provider_key(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.get_provider_key(uuid, text) from public, anon, authenticated;
revoke execute on function public.delete_provider_key(uuid, text) from public, anon, authenticated;
grant execute on function public.set_provider_key(uuid, text, text, text) to service_role;
grant execute on function public.get_provider_key(uuid, text) to service_role;
grant execute on function public.delete_provider_key(uuid, text) to service_role;
