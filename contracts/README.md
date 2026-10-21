# Contracts

JSON Schemas (draft 2020-12) shared by the Edge Functions and the iOS/Android clients.

- `message-content.schema.json`: the `messages.content` array (text, image, file, tool_call, tool_result parts).
- `realtime-event.schema.json`: payloads broadcast on the private `conversation:{id}` Realtime channel; the broadcast event name equals the payload `type`.
