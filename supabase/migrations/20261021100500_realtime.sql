-- Realtime Authorization: private `conversation:{id}` broadcast channels can only
-- be joined by the conversation's owner. Functions broadcast with the service role.

create policy "conversation topics: owner receives broadcasts" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and exists (
      select 1
        from public.conversations c
       where c.user_id = (select auth.uid())
         and 'conversation:' || c.id::text = (select realtime.topic())
    )
  );

-- Row changes for multi-device sync (user turns) and run state outside an open chat.
alter publication supabase_realtime add table public.messages, public.agent_runs;
