# Supabase backend

Postgres schema, RLS, the step-based agent runtime (pg_net kick + pg_cron sweeper) and Edge
Functions. See `docs/PLAN.md` sections 2–3 for the design.

## Local development

`config.toml` enables the CLI's stack engine and leaves ports unset; read URLs and keys from
`supabase status` rather than assuming defaults.

```sh
supabase start --runtime native   # or --runtime docker
supabase db reset                 # re-apply migrations
```

Edge Functions are served by the stack (`supabase functions serve` when running Docker).
Local secrets go in `supabase/functions/.env` (git-ignored; see `.env.example`).

## Vault secrets (required for the kick loop)

`private.kick_agent_run` reads two Vault secrets to call `agent-step`. Without them runs stay
`ready` and Postgres logs a warning. Set them once per database (SQL editor or `psql`):

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<service-role-key>', 'service_role_key');
```

Use the legacy JWT `service_role` key: it is what Edge Functions receive as
`SUPABASE_SERVICE_ROLE_KEY`, and `agent-step` compares the bearer against it. Locally,
`project_url` is the API URL from `supabase status` (Postgres reaches it directly with the
native runtime; with Docker use `http://host.docker.internal:<port>`). To rotate, use
`vault.update_secret`.

## Deploy

```sh
supabase link --project-ref <project-ref>
supabase db push
supabase functions deploy agent-step chat-send
supabase secrets set --env-file supabase/functions/.env
```

`agent-step` is deployed with `verify_jwt = false` (it checks the service key itself);
`chat-send` requires a user JWT.

## Tests

```sh
cd supabase/functions && deno task ci   # fmt, lint, type-check, unit tests
supabase test db                        # pgTAP (needs a running stack)
```

To exercise the kick loop by hand, enqueue a multi-step no-op run:

```sql
insert into agent_runs (user_id, agent_id, conversation_id, next_input)
select user_id, agent_id, id, '{"target_steps": 3}' from conversations limit 1;
```
