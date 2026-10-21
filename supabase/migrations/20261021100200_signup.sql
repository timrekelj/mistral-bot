-- Every new auth user gets a profile and their main agent.

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent_id uuid;
begin
  insert into public.agents (user_id, name, role, model_policy, voice_model_policy)
  values (new.id, 'Mistral', 'main', 'large', 'large')
  returning id into v_agent_id;

  insert into public.profiles (user_id, display_name, quick_call_agent_id)
  values (new.id, new.raw_user_meta_data ->> 'display_name', v_agent_id);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();
