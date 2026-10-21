begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'alice@test.dev'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob@test.dev');

-- RPC roundtrip (as postgres, standing in for the service role) ------------------

select is(
  (public.set_provider_key('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mistral', 'alice-key-0001')).key_hint,
  '…0001',
  'set stores a last-four hint'
);
select is(
  public.get_provider_key('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mistral'),
  'alice-key-0001',
  'get returns the decrypted key'
);
select is(
  (select count(*)::int from vault.secrets
    where name = 'provider_key:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:mistral'),
  1,
  'the key lives in Vault under a per-user name'
);
select isnt(
  (select verified_at from public.provider_credentials where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  null,
  'a valid key records verified_at'
);

create temp table first_secret on commit drop as
  select vault_secret_id from public.provider_credentials
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select results_eq(
  $$select key_hint, vault_secret_id from public.set_provider_key(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mistral', 'alice-key-0002')$$,
  $$select '…0002'::text, vault_secret_id from first_secret$$,
  'rotating updates the hint and reuses the Vault secret'
);
select is(
  public.get_provider_key('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mistral'),
  'alice-key-0002',
  'get returns the rotated key'
);
select is(public.get_provider_key('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'mistral'), null,
  'get returns null without a key');
select throws_ok(
  $$select public.set_provider_key('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'openai', 'some-key-1234')$$,
  '23514',
  null,
  'unknown providers are rejected'
);

select public.set_provider_key('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'mistral', 'bob-key-9999');

-- Client access --------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}', true);

select results_eq(
  'select provider, key_hint, status from public.provider_credentials',
  $$values ('mistral', '…0002', 'valid')$$,
  'alice sees only her own credential metadata'
);
select throws_ok(
  'select vault_secret_id from public.provider_credentials',
  '42501',
  null,
  'clients cannot read vault_secret_id'
);
select throws_ok(
  'select * from vault.decrypted_secrets',
  '42501',
  null,
  'clients cannot read Vault'
);
select throws_ok(
  $$insert into public.provider_credentials (user_id, provider, vault_secret_id, key_hint)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mistral', gen_random_uuid(), '…0000')$$,
  '42501',
  null,
  'clients cannot insert credentials'
);
select throws_ok(
  $$update public.provider_credentials set status = 'invalid'$$,
  '42501',
  null,
  'clients cannot update credentials'
);
select throws_ok(
  $$select public.get_provider_key('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'mistral')$$,
  '42501',
  null,
  'clients cannot call get_provider_key'
);
select throws_ok(
  $$select public.set_provider_key('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mistral', 'x-key-12345')$$,
  '42501',
  null,
  'clients cannot call set_provider_key'
);
select throws_ok(
  $$select public.delete_provider_key('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'mistral')$$,
  '42501',
  null,
  'clients cannot call delete_provider_key'
);

reset role;

-- Delete ---------------------------------------------------------------------------

select ok(
  public.delete_provider_key('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mistral'),
  'delete reports that a key existed'
);
select is(
  (select count(*)::int from vault.secrets s join first_secret f on s.id = f.vault_secret_id),
  0,
  'delete removes the Vault secret'
);

delete from auth.users where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select is(
  (select count(*)::int from vault.secrets
    where name = 'provider_key:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:mistral'),
  0,
  'deleting the account removes its Vault secret'
);

select * from finish();
rollback;
