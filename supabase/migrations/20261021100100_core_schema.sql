-- Core data model for Phases 0–1 (docs/PLAN.md sections 2 and 3).
-- Child tables carry a denormalized user_id plus composite foreign keys onto
-- (id, user_id), so RLS policies stay trivial and rows can never point at
-- another user's parent.

create type public.agent_role as enum ('main', 'sub');
create type public.model_policy as enum ('large', 'small', 'auto');
create type public.reasoning_mode as enum ('fast', 'think');
create type public.conversation_source as enum ('chat', 'voice', 'action_button', 'schedule');
create type public.message_role as enum ('user', 'assistant', 'system', 'tool');
create type public.run_status as enum (
  'ready',
  'running',
  'waiting_input',
  'waiting_approval',
  'waiting_subtasks',
  'completed',
  'failed',
  'cancelled'
);
create type public.tool_call_status as enum ('pending', 'running', 'completed', 'failed', 'skipped');

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- profiles ------------------------------------------------------------------

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),
  custom_instructions text not null default '',
  default_voice_id text,
  quick_call_agent_id uuid,
  push_tokens jsonb not null default '[]' check (jsonb_typeof(push_tokens) = 'array'),
  daily_budget_usd numeric(10, 4) check (daily_budget_usd >= 0),
  settings jsonb not null default '{}' check (jsonb_typeof(settings) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- agents --------------------------------------------------------------------

create table public.agents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  avatar text,
  role public.agent_role not null default 'sub',
  instructions text not null default '',
  model_policy public.model_policy not null default 'auto',
  voice_model_policy public.model_policy not null default 'large',
  reasoning_effort public.reasoning_mode not null default 'fast',
  enabled_tools jsonb not null default '[]' check (jsonb_typeof(enabled_tools) = 'array'),
  connector_ids uuid[] not null default '{}',
  library_ids uuid[] not null default '{}',
  skill_ids uuid[] not null default '{}',
  voice_id text,
  can_message_agent_ids uuid[] not null default '{}',
  mistral_agent_id text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

-- Exactly one main agent per user.
create unique index agents_one_main_per_user on public.agents (user_id) where role = 'main';
create index agents_user_id_idx on public.agents (user_id);

alter table public.profiles
  add constraint profiles_quick_call_agent_fkey
  foreign key (quick_call_agent_id, user_id) references public.agents (id, user_id)
  on delete set null (quick_call_agent_id);

-- conversations -------------------------------------------------------------

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  project_id uuid, -- foreign key added with the projects table (Phase 6)
  agent_id uuid,
  title text check (char_length(title) <= 200),
  mistral_conversation_id text,
  mode public.reasoning_mode not null default 'fast',
  source public.conversation_source not null default 'chat',
  summary text,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (agent_id, user_id) references public.agents (id, user_id) on delete set null (agent_id)
);

create index conversations_user_recent_idx
  on public.conversations (user_id, coalesce(last_message_at, created_at) desc);

-- messages ------------------------------------------------------------------

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null,
  user_id uuid not null default auth.uid(),
  role public.message_role not null,
  author_agent_id uuid,
  content jsonb not null default '[]' check (jsonb_typeof(content) = 'array'),
  model text,
  tokens_in integer check (tokens_in >= 0),
  tokens_cached integer check (tokens_cached >= 0),
  tokens_out integer check (tokens_out >= 0),
  created_at timestamptz not null default now(),
  foreign key (conversation_id, user_id) references public.conversations (id, user_id) on delete cascade,
  foreign key (author_agent_id, user_id) references public.agents (id, user_id) on delete set null (author_agent_id)
);

create index messages_conversation_created_idx on public.messages (conversation_id, created_at);

create function private.touch_conversation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id
     and (last_message_at is null or last_message_at < new.created_at);
  return null;
end;
$$;

create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function private.touch_conversation();

-- agent_runs ----------------------------------------------------------------

create table public.agent_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  agent_id uuid not null,
  conversation_id uuid not null,
  task_id uuid, -- foreign key added with the tasks table (Phase 3)
  status public.run_status not null default 'ready',
  step_no integer not null default 0 check (step_no >= 0),
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts > 0),
  lease_until timestamptz,
  lease_owner text,
  next_input jsonb not null default '{}' check (jsonb_typeof(next_input) = 'object'),
  model text,
  tool_set_hash text,
  budget_tokens integer check (budget_tokens > 0),
  used_tokens integer not null default 0 check (used_tokens >= 0),
  used_tool_calls integer not null default 0 check (used_tool_calls >= 0),
  error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (agent_id, user_id) references public.agents (id, user_id) on delete cascade,
  foreign key (conversation_id, user_id) references public.conversations (id, user_id) on delete cascade
);

create index agent_runs_status_lease_idx on public.agent_runs (status, lease_until);
create index agent_runs_user_status_idx on public.agent_runs (user_id, status);
create index agent_runs_conversation_idx on public.agent_runs (conversation_id, created_at);

-- agent_events --------------------------------------------------------------

create table public.agent_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  conversation_id uuid not null,
  run_id uuid,
  agent_id uuid,
  step_no integer,
  type text not null check (type ~ '^[a-z][a-z0-9_]*$'),
  payload jsonb not null default '{}' check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default now(),
  foreign key (conversation_id, user_id) references public.conversations (id, user_id) on delete cascade,
  foreign key (run_id, user_id) references public.agent_runs (id, user_id) on delete set null (run_id),
  foreign key (agent_id, user_id) references public.agents (id, user_id) on delete set null (agent_id)
);

create index agent_events_conversation_created_idx on public.agent_events (conversation_id, created_at);
create index agent_events_run_idx on public.agent_events (run_id, step_no);

-- tool_calls (write-ahead log for side effects) ------------------------------

create table public.tool_calls (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  run_id uuid not null,
  step_no integer not null check (step_no >= 0),
  call_id text not null,
  tool text not null,
  args jsonb not null default '{}',
  idempotency_key text not null unique,
  status public.tool_call_status not null default 'pending',
  result jsonb,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (run_id, user_id) references public.agent_runs (id, user_id) on delete cascade
);

create index tool_calls_run_step_idx on public.tool_calls (run_id, step_no);

-- usage_ledger --------------------------------------------------------------

create table public.usage_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  run_id uuid,
  agent_id uuid,
  conversation_id uuid,
  kind text not null check (kind in ('model', 'tool', 'stt', 'tts')),
  model text,
  tool text,
  tokens_in integer not null default 0 check (tokens_in >= 0),
  tokens_cached integer not null default 0 check (tokens_cached >= 0),
  tokens_out integer not null default 0 check (tokens_out >= 0),
  web_searches integer not null default 0 check (web_searches >= 0),
  audio_seconds numeric(12, 3) not null default 0 check (audio_seconds >= 0),
  characters integer not null default 0 check (characters >= 0),
  cost_usd numeric(12, 6) not null default 0 check (cost_usd >= 0),
  created_at timestamptz not null default now(),
  foreign key (run_id, user_id) references public.agent_runs (id, user_id) on delete set null (run_id),
  foreign key (agent_id, user_id) references public.agents (id, user_id) on delete set null (agent_id),
  foreign key (conversation_id, user_id) references public.conversations (id, user_id)
    on delete set null (conversation_id)
);

create index usage_ledger_user_created_idx on public.usage_ledger (user_id, created_at);
create index usage_ledger_run_idx on public.usage_ledger (run_id);

-- updated_at triggers -------------------------------------------------------

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger agents_set_updated_at before update on public.agents
  for each row execute function private.set_updated_at();
create trigger conversations_set_updated_at before update on public.conversations
  for each row execute function private.set_updated_at();
create trigger agent_runs_set_updated_at before update on public.agent_runs
  for each row execute function private.set_updated_at();
create trigger tool_calls_set_updated_at before update on public.tool_calls
  for each row execute function private.set_updated_at();
