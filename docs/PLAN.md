# Le Bot: Implementation Plan

**Le Bot** (bundle ID `com.timrekelj.lebot`) is a Grok-style mobile assistant built on Mistral models. It runs a **main agent** plus any number of **sub-agents**. The main agent can delegate work to sub-agents, and agents can message each other. Each agent gets the same capabilities as Mistral Vibe **Work mode** (connectors, web search, code interpreter, libraries, files and canvas, skills, scheduled tasks, approvals). Voice runs on **Voxtral 3**. You can start a voice call from anywhere with the **iPhone Action Button**, without opening the app.

- **Platform order:** **iOS first** (native Swift/SwiftUI). Android (native Kotlin/Jetpack Compose) follows once the iOS app is feature-complete (Phase 8).
- **Backend:** Supabase only. All agent logic runs in Supabase Edge Functions (TypeScript/Deno). There is no separate agent server.
- **Voice:** a thin voice adapter hosted by **LiveKit Cloud** (`lk agent deploy`). You don't run a server for it.
- **Models:**
  - `mistral-large-4` is the default reasoning model (public preview since 2026-10-06; 1M context; function calling, structured outputs, Agents/Conversations API, Connectors)
  - `mistral-small-4` handles cheaper or faster work (section 7)
- **Speech:**
  - `voxtral-mini-transcribe-realtime-3-0` (streaming STT)
  - `voxtral-mini-tts-3-0` / Voxtral Speech 3 (TTS)
- **Web search:** Mistral's built-in `web_search` / `web_search_premium`

> Model IDs and prices are kept in config (`supabase/functions/_shared/models.ts`), not hard-coded. Large 4 and Voxtral 3 are previews, and the docs examples still show `voxtral-mini-transcribe-realtime-2602`.

---

## 1. Architecture

```
┌──────────────────────────────┐   ┌───────────────┐
│ iOS app (first)              │   │ Android app   │  (Phase 8)
│ SwiftUI · supabase-swift     │   │ Compose ·     │
│ LiveKit Swift SDK            │   │ supabase-kt   │
│ App Intents · Live Activity  │   └───────┬───────┘
│ Control widget (Action Btn)  │           │
└──────────────┬───────────────┘           │
               │ Auth · PostgREST · Realtime · Storage · Functions
               ▼                           ▼
┌──────────────────────────────────────────────────────────────┐
│ Supabase                                                     │
│                                                              │
│  Auth (Apple, Google, email)      Postgres + RLS + pgvector  │
│  Storage (uploads, canvas, imgs)  Realtime (broadcast)       │
│  pg_net (kick functions)          pg_cron (sweeper, schedules)│
│  Vault (connector OAuth tokens)                              │
│                                                              │
│  Edge Functions (TypeScript / Deno)                          │
│   chat-send ─┐                                               │
│   approvals ─┼─► agent_runs row ─► pg_net ─► agent-step ──┐  │
│   scheduler ─┘        ▲                       (1 step)    │  │
│                       └──── re-kick until done ◄──────────┘  │
│   voice-token   voice-turn   connector-oauth   push-notify   │
│                                                              │
│  _shared/: mistral adapter · runtime · orchestrator ·        │
│            mcp gateway · tool policies · model router ·      │
│            findings cache                                    │
└──────────────┬──────────────────────────────┬────────────────┘
               │                              │ HTTPS stream
               ▼                              │
     Mistral API (Large 4, Small 4,   ┌───────┴────────────────┐
     built-in tools incl. web search, │ LiveKit Cloud          │
     Libraries, Voxtral STT/TTS)      │  voice adapter (hosted)│
     Remote MCP servers               │  Voxtral STT → voice-  │
                                      │  turn → Voxtral TTS    │
                                      └────────────────────────┘
```

### Why it works without a separate server
Supabase Edge Functions are limited per invocation: 150 s on Free and 400 s on paid plans, 256 MB of memory, and a CPU limit that **excludes async I/O**. An agent spends nearly all its time waiting on Mistral and MCP calls, so CPU is not the bottleneck. Wall-clock time is, so the runtime is **step-based**:

- One `agent-step` invocation does one unit of work. It sends one `conversations.append` call to Mistral, with built-in tools such as web search and the code interpreter running on Mistral's side during that call. Then it executes any function calls that came back, persists everything, and re-queues itself if more work remains.
- The **Mistral Conversations API keeps the conversation state server-side**, so resuming a step costs almost nothing.
- Parallel sub-agents are just parallel `agent-step` invocations.
- Long-lived audio is the one thing that can't fit in a function, and LiveKit Cloud hosts that piece.

### Streaming to the apps
`agent-step` publishes coalesced token deltas (about every 50 ms) and agent events to Supabase Realtime broadcast on a `conversation:{id}` channel. It also persists finished messages and events to Postgres. If a client reconnects mid-turn, it reloads from the DB and resubscribes. The same channel powers multi-device sync and live updates for background tasks.

---

## 2. Step-based durable runtime

### Tables
- **`agent_runs`:** `id, user_id, agent_id, conversation_id, task_id, status, step_no, lease_until, lease_owner, next_input jsonb, model, tool_set_hash, budget_tokens, used_tokens, used_tool_calls, error`
- **`tool_calls`:** `id, run_id, step_no, call_id, tool, args, idempotency_key, status, result, started_at, finished_at`. This table is the write-ahead log for side effects.

### Lifecycle
1. **Enqueue.** `chat-send`, `approvals`, the scheduler, the orchestrator, or `voice-turn` inserts or updates an `agent_runs` row and sets `status = 'ready'`.
2. **Kick.** An `AFTER` trigger calls `net.http_post` to `agent-step` with `{run_id}`, authenticated with the service key. Latency is roughly 50–150 ms.
3. **Claim.** The function claims the run atomically:
   `UPDATE agent_runs SET lease_until = now() + '420 s', lease_owner = $id WHERE id = $run AND status = 'ready' AND (lease_until IS NULL OR lease_until < now()) RETURNING *`.
   If no row comes back, another worker already owns the run, so this invocation exits.
4. **Step.**
   - Stream `conversations.append` (or `start` on the first step), forwarding deltas to Realtime.
   - Persist the messages and events, and record usage, including cached tokens.
   - Harvest the outputs of built-in web search into `findings` (section 7.3).
   - For each function call: write a `tool_calls` row first, keyed by `idempotency_key = run_id:step_no:call_id`, and skip any call that is already completed. Then execute it through the orchestrator, the MCP gateway, or local tools.
   - Some calls block: approval needed, waiting on sub-tasks, or waiting for input. In that case, set `status = 'waiting_*'`, release the lease, and stop.
5. **Continue or finish.**
   - If there are tool results to send back, store them in `next_input` and set `status = 'ready'`. The trigger re-kicks the run.
   - If the model produced a final answer, set `status = 'completed'`, notify the parent task or user, and push-notify the user if they're away.
6. **Time guard.** If the step has run longer than 300 s, checkpoint and re-kick rather than risk hitting the 400 s limit.
7. **Sweeper.** A `pg_cron` job runs every minute. It re-kicks `ready` runs whose lease expired (meaning the function crashed or timed out) and fails runs that exceed their retry or budget limits.

### Wake-ups
These DB triggers flip waiting runs back to `ready`:
- An approval is decided
- All of a run's awaited sub-tasks reach a final state
- A mailbox message arrives for a run that is `waiting_input`
- A scheduled time is reached

### Concurrency
- A per-user cap on runs in `running` (default 6), enforced in the claim query
- A global cap that stays under the plan's Edge Function concurrency limit

---

## 3. Data model (Postgres, RLS on everything, keyed by `user_id`)

| Table | Purpose |
|---|---|
| `profiles` | settings, custom instructions, default voice, default **quick-call agent**, push tokens, daily budget |
| `agents` | `id, user_id, name, avatar, role (main\|sub), instructions, model_policy (large\|small\|auto), voice_model_policy, reasoning_effort, enabled_tools jsonb, connector_ids[], library_ids[], skill_ids[], voice_id, can_message_agent_ids[], mistral_agent_id, is_active` |
| `projects` | groups conversations, files, and knowledge (like Vibe Projects) |
| `conversations` | `id, user_id, project_id, agent_id, title, mistral_conversation_id, mode (fast\|think), source (chat\|voice\|action_button\|schedule), summary` |
| `messages` | `id, conversation_id, role, author_agent_id, content jsonb (text/image/file/tool parts), model, tokens_in, tokens_cached, tokens_out, created_at` |
| `agent_events` | tool calls and results, todo updates, thinking summaries, delegation events (powers the "steps" UI) |
| `agent_runs`, `tool_calls` | durable runtime (section 2) |
| `tasks` | `id, user_id, parent_task_id, assigned_by_agent_id, assignee_agent_id, run_id, title, instructions, status, result jsonb, budget_usd, spent_usd, depth, deadline` |
| `agent_messages` | inter-agent mailbox: `from_agent_id, to_agent_id, task_id, body, read_at` |
| `todos` | per-task live checklist (the Work-mode todos panel) |
| `approvals` | pending sensitive actions: `run_id, tool_call_id, tool, args jsonb, status, decided_at` |
| `findings` | facts harvested from web search: `user_id, task_root_id, query, source_url, title, excerpt, fetched_at, ttl_class (news\|general\|reference), embedding vector` (section 7.3) |
| `connectors` | `user_id, kind (catalog\|custom_mcp\|mistral_connector), name, server_url, auth_type, vault_secret_id, tools_cache jsonb, tool_policies jsonb` |
| `libraries` / `library_files` | mirror of Mistral Libraries (document RAG) |
| `skills` | reusable instructions, checklists, and templates, invoked with `@skill` |
| `memories` | knowledge-base facts with pgvector embeddings (`mistral-embed`) |
| `scheduled_tasks` | RRULE/cron + prompt + agent + `use_batch` flag |
| `files` | Storage objects: uploads, generated images, canvas artifacts and versions |
| `usage_ledger` | one row per model call or tool call: model, tokens (in/cached/out), web searches, audio minutes, characters, `cost_usd`. This feeds budgets, the cache-hit metrics, and the usage screen. |

Task state machine:
`queued → running → (waiting_input | waiting_approval | waiting_subtasks) → running → completed | failed | cancelled`

---

## 4. Multi-agent system

### Concepts
- **Main agent:** one per user, created at signup. It is the default chat, voice, and Action Button target.
- **Sub-agents:** created by the user, either manually or from templates such as "Researcher", "Inbox manager", "Coder", or "Analyst". Each one has its own instructions, model policy, tools, connectors, libraries, and voice. Users can chat with or call any sub-agent directly.
- Every agent is mirrored as a **Mistral Agent** (`agents.create/update`) so built-in tools are configured server-side. Each run is a **Mistral Conversation**.

### How delegation works
Mistral's native **handoffs** transfer control from one agent to the next in sequence. That fits routing but not parallel, asynchronous delegation. So delegation is done with orchestration **function tools** that `agent-step` executes:

**Main agent tools**
- `list_agents()`: names, descriptions, capabilities, and model tier
- `assign_task(agent, title, instructions, context, budget_usd?, wait=false)`: creates a `tasks` row and its `agent_runs` row (which kicks it off). The relevant `findings` already gathered are attached automatically. Returns a `task_id`.
- `wait_for_tasks([ids], timeout)`: the run parks in `waiting_subtasks`, and a trigger wakes it when they finish. There's no polling.
- `get_task(task_id)`, `cancel_task(task_id)`
- `send_message(agent, body, task_id?)`: writes to the inter-agent mailbox
- `create_agent(spec)`: optional, always needs user approval

**Sub-agent tools**
- `update_todos(items)`, `report_progress(note)`
- `ask(agent="main"|peer, question)`: parks the task in `waiting_input` until a reply arrives
- `complete_task(result, artifacts[])`, `fail_task(reason)`

**Peer messaging:** agents can `send_message` only to agents listed in their `can_message_agent_ids`. A message wakes a parked recipient or starts a new run for it.

### Guardrails
- Maximum delegation depth (default 3)
- Maximum concurrent runs per user (default 6)
- A per-task `budget_usd` that is inherited from the parent and split among children. Runs stop at their budget and report partial results.
- A cap on web searches per task (default 8)
- Loop detection: no agent may wait on its own ancestor
- Rate-limited agent-to-agent messaging
- Cancelling a task cascades to its children, and the user can stop any task or the whole tree from the app

---

## 5. Work-mode feature parity

| Vibe Work feature | Implementation |
|---|---|
| Fast / Think toggle | `reasoning_effort` per request (exposed per message) |
| Web search | **Mistral built-in `web_search`** (default), plus `web_search_premium` for news (AFP/AP). Results are harvested into `findings` for reuse (section 7.3). |
| Open URL | `open_url` function tool (fetch + readability inside the Edge Function) |
| Code interpreter | Mistral built-in `code_interpreter`; output files are saved to Storage |
| Image generation | Mistral built-in `image_generation`; images are saved to Storage |
| Image/file understanding | Large 4 image input; Mistral OCR for PDFs and documents |
| Libraries (RAG) | Mistral Libraries API plus the built-in `document_library` tool; managed from the app |
| Files & Canvas | Agents emit canvas artifacts (markdown, code, tables, HTML, docs). The app has a canvas viewer and editor, with versions stored in Storage. |
| Connectors | MCP gateway (section 6) |
| Skills | `skills` table, injected on `@skill`; "Deep research" ships as a built-in skill |
| Knowledge base / memories | `memories` with pgvector, `remember` / `recall` tools, editable in Settings |
| Custom instructions & Projects | `profiles.custom_instructions`, `projects` scoping files, memories, and conversations |
| Scheduled tasks | `scheduled_tasks`; `pg_cron` creates runs (once, daily, weekly, monthly, yearly). Runs can optionally use the batch API at 50% off. |
| Approvals for sensitive actions | Tools are marked `requires_approval` by policy. The approval appears as an in-app card and a push notification. |
| Live todos, visible tool calls, stop/redirect | `todos` + `agent_events` over Realtime. Stop cancels the run, and a follow-up message redirects it. |

---

## 6. Connectors (MCP gateway, inside Edge Functions)

**Approach:** our own MCP client lives in `_shared/mcp/`. It uses the official `@modelcontextprotocol/sdk` with the Streamable HTTP or SSE client transport, which runs in Deno. Each connected server's tools are exposed to Mistral as function tools, namespaced like `gmail__send_email`.

There are two reasons not to rely only on Mistral's Connectors API (which is in public preview). First, its credentials belong to the *Mistral workspace* user, not to our app's users. Second, its docs say OAuth tokens can't be passed in programmatically. Running our own gateway gives per-user OAuth and per-tool approval policies. Registered Mistral connectors are still supported as `kind = mistral_connector` for anyone who wants them.

- **Stateless use:** each `agent-step` opens a short MCP session to the servers the current agent needs and closes it when the step ends. Tool lists are cached in `connectors.tools_cache` and refreshed on demand.
- **Catalog connectors** (OAuth 2.1 + PKCE via `connector-oauth` start/callback; tokens stored in **Supabase Vault** and refreshed automatically): Gmail, Google Calendar, Google Drive, Outlook/Microsoft 365, SharePoint, Slack, Notion, GitHub, Jira/Linear. These use the vendors' official remote MCP servers where they exist.
- **Custom MCP:** any remote server URL, with no auth, header/API-key auth, or OAuth discovery
- **Tool policies:** each tool is marked read, write, or destructive. Write and destructive tools require approval by default, and users can change this per connector. Side-effecting calls go through the `tool_calls` write-ahead log, so a retried step never runs them twice.
- **Small, stable prompts:** agents only see connectors attached to them. The tool set is fixed for the whole run so the prompt cache stays valid (section 7.2).

---

## 7. Model routing, caching & cost

> With bring-your-own-key (section 13), Mistral usage bills to each user's own Mistral account. These estimates are what one user pays Mistral. The operator pays only the fixed costs.

### 7.1 Unit prices (Mistral list prices, October 2026; previews, so subject to change)

| Item | Price |
|---|---|
| Mistral Large 4 | $1.36 per 1M input tokens · **$0.14 cached input** · $4.18 per 1M output tokens (the launch discount ended Oct 20) |
| Mistral Small 4 | $0.15 per 1M input · $0.60 per 1M output |
| Voxtral Mini Transcribe Realtime 3 | $0.008 per audio minute |
| Voxtral Speech 3 (TTS) | $13 per 1M characters (about $0.005 per minute of agent speech) |
| Mistral bundled voice agent API (alternative) | $0.04/min with Small 4 · $0.08/min with another model |
| Web search · code interpreter (built-in) | $30 per 1k calls ($0.03 each), on top of tokens |
| Image generation | about $100 per 1k images (third-party figure, unconfirmed) |
| Batch API | 50% off |

### 7.2 Prompt caching: the biggest cost lever

Every agent step resends the whole conversation, including the search results already in it. Cached input on Large 4 costs about 10× less.

| Cache hit rate | Effective Large 4 input price | 300k-token research task |
|---|---|---|
| 0% | $1.36 per 1M | ~$0.41 |
| 50% | $0.75 per 1M | ~$0.23 |
| **75% (target)** | $0.45 per 1M | ~$0.13 |
| 90% | $0.26 per 1M | ~$0.08 |

A multi-agent job costs **~$2.20 with no caching and ~$1.15 at 75%**. In the heavy scenario that's roughly **$300 a month saved**.

**Rules, enforced in `_shared/runtime`:**
1. **A stable prefix:** instructions first, then tool definitions in a deterministic order. Nothing that changes goes at the top, and the current date and time go in the latest user turn.
2. **Append-only history.** Never edit or reorder earlier messages.
3. **The tool set is fixed per run** and recorded in `agent_runs.tool_set_hash`. Tools are never toggled mid-run.
4. **The model is fixed per run.** Large 4 and Small 4 have separate caches. The `auto` routing decision is made when a run starts, never per step.
5. **Compact rarely,** only at fixed token limits (Small 4 summarizes). Each compaction starts a new cached prefix.
6. **Measure it.** `usage_ledger.tokens_cached` gives the hit rate per agent and day, shown on the usage screen. The target is above 70%, and dropping below 50% triggers an alert.

### 7.3 Findings cache: fewer web searches

Built-in search has a flat price per call ($0.03), and it runs on Mistral's side, so the queries can't be intercepted. Instead, we **reuse what was already found** to avoid searching again:

- **Harvest:** after each step, built-in search results (URL, title, excerpt, query) are written to `findings` with an embedding and a freshness class. The TTL is about 1 hour for news, about 7 days for general facts, and about 30 days for reference material.
- **Within a job:** `assign_task` automatically attaches the relevant findings from the task tree. Sub-agents are told "search only for what the provided findings don't cover".
- **Across tasks:** when a run starts, a pgvector lookup over fresh findings is injected as context. If coverage is high, `web_search` is left out of that run's tool set. This is decided once at the start, so caching rule 3 still holds.
- **Scheduled tasks** (such as a daily briefing) reuse findings from the same day.

Expected savings in the heavy scenario (about 4,500 searches, $135 a month):

| Searches avoided | Monthly search cost | Saved |
|---|---|---|
| 20% | $108 | $27 |
| 35% | $88 | $47 |
| 50% | $67 | $68 |

### 7.4 Estimated cost per action (75% prompt-cache hit rate)

| Action | Large 4 | Small 4 / mixed |
|---|---|---|
| Chat message (~6k tokens in, 600 out) | ~$0.011 uncached · **~$0.005 cached** | ~$0.0013 |
| Single-agent task (15 steps, 5 searches) | ~$0.17 tokens + $0.15 search ≈ **$0.32** | ≈ $0.20 |
| Multi-agent job (main + 3 sub-agents, 15 searches) | **≈ $1.15** | Main on Large, sub-agents on Small: **≈ $0.70** |
| Voice per minute (STT + TTS + LLM + LiveKit) | ~$0.037 cached / $0.068 uncached (**$2.20–$4 per hour**) | ~$0.028 (**~$1.70 per hour**) |

### 7.5 Estimated monthly cost (one user)

| Scenario | All Large 4 | Mixed routing | Mixed + findings cache (~30%) |
|---|---|---|---|
| Light: 30 chats/day, 2 agent tasks/day, ~30 min voice/week | ~$28 | ~$20 | ~$17 |
| Heavy: 100 chats/day, 10 multi-agent jobs/day, 30 min voice/day | ~$385 | ~$250 | **~$210** |

**Fixed costs:**
- Supabase Pro: $25/month. It's required for the 400 s function limit, and free projects pause when idle.
- LiveKit Cloud: free up to 1,000 agent minutes a month, then the Ship plan at about $50/month.
- Apple Developer: $99/year. Google Play: $25 one-time, only once Android starts.

### 7.6 Routing policy (`_shared/router.ts`)
**Large 4:**
- Main agent planning and delegation, and the final answer it writes
- Complex reasoning or coding
- Hard vision or document work
- Voice by default

**Small 4:**
- Mechanical sub-agent work: search and summarize, inbox triage, extraction, filling templates
- Chat titles, compressing long conversations, extracting memories and findings
- The voice model when "fast voice" is enabled

**`auto`:** decided when a run starts. It picks Small 4 unless the reasoning effort is Think, the task is planning or synthesis, the context exceeds Small 4's window, or a previous run of the same task failed. If a Small 4 run fails a tool call or its structured output doesn't validate, it finishes, and a Large 4 follow-up run takes over.

Each agent stores a `model_policy` and a `voice_model_policy` that the user can edit.

### 7.7 Other cost controls
1. **The batch API** for scheduled or non-interactive tasks.
2. **Budgets:** per task (`budget_usd`), per user per day (`profiles.daily_budget`), and a cap on web searches per task. Everything is enforced from `usage_ledger`.
3. **A usage screen** in the app showing cost, cache-hit rate, and search count per agent, task, and day.
4. **Escape hatch (not planned):** the `web_search` tool sits behind an interface, so a cheaper search API could replace it later if search starts to dominate the bill.

---

## 8. Voice agent (Voxtral 3 on LiveKit Cloud)

**Transport:** LiveKit (WebRTC). Mistral's voice agent SDK is built on LiveKit, and LiveKit's native iOS SDK handles echo cancellation, noise suppression, Bluetooth routing, and background audio.

### Flow
1. **Token.** The app calls the `voice-token` Edge Function. It checks the Supabase JWT, creates a LiveKit room `voice:{conversation_id}` using `livekit-server-sdk`, and attaches signed room metadata `{user_id, agent_id, conversation_id}`. It dispatches the hosted voice agent and returns a participant token.
2. **Voice adapter.** The adapter (`voice/`, Python, LiveKit Agents plus Mistral's voice SDK plugins) is deployed with `lk agent deploy`. It joins the room and runs:
   - **STT:** `voxtral-mini-transcribe-realtime-3-0` with native end-of-turn detection, context biasing from the user's names and terms, and `target_streaming_delay_ms` of about 240–480 ms
   - **LLM node:** an HTTPS stream to the **`voice-turn`** Edge Function. It authenticates with an adapter secret and passes the signed room metadata. `voice-turn` runs the **same runtime and tools** as text chat, inline and streaming, and returns text as it's generated.
   - **TTS:** Voxtral Speech 3 streaming, starting from the first sentence, with the agent's voice and emotion/pacing tags
3. **Long work.** Voice turns get a voice-specific prompt: short spoken answers, long content goes to canvas, and anything slow is delegated with `assign_task`. The adapter subscribes to the conversation's Realtime channel and speaks task results when they arrive ("The researcher finished, here's the summary…").
4. **Barge-in.** User speech interrupts TTS playback and cancels the in-flight `voice-turn` stream.
5. **History.** Transcripts and tool events are written to `messages`, so a voice session shows up as a normal conversation.

**Latency:** Large 4 is a ~1T-parameter mixture-of-experts model, so time-to-first-token may be slower than Small 4. To compensate:
- Stream TTS from the first sentence
- Speak a filler acknowledgement during tool calls
- Offer the `voice_model_policy = small` ("fast voice") option

Time-to-first-audio gets measured in Phase 5.

**Alternative evaluated in Phase 5:** Mistral's bundled voice agent API ($0.08/min with a non-Small model). Pick whichever has lower latency and cost while keeping full tool access.

**Later:** push-to-talk dictation in the text composer goes directly from the app to Voxtral realtime STT, using `POST /v1/client/sessions` ephemeral tokens (TTL about 15 min) minted by an Edge Function. No LiveKit needed.

**In-app UI (Grok-style):** a full-screen voice mode with an animated orb, live captions, a voice/agent picker, mute and hang-up controls, a camera toggle (send frames to Large 4 vision), and a "continue in chat" handoff.

---

## 9. Action Button quick call (iOS)

**Goal:** press the iPhone Action Button from anywhere, including the lock screen or another app, and a voice call with the main agent starts immediately. The app doesn't come to the foreground. A **Live Activity** banner shows the app icon, the agent name, "Calling…" then "Connected · 0:42", a **mute** toggle, and a red **end** button, just like the Grok "Clank" banner. It also appears in the Dynamic Island and on the lock screen.

### Entry points (all call the same intent)
1. **`StartVoiceCallIntent`** (App Intents) conforms to **`AudioRecordingIntent`** (iOS 18+). This lets the intent start microphone capture from the background, provided a Live Activity is started at the same time.
   - Optional parameter: `agent: AgentEntity` (an `AppEntity` backed by the user's agents). The default is the main agent or `profiles.quick_call_agent`.
   - Exposed through an **`AppShortcutsProvider`** ("Call Mistral", "Call {agent}"), so it appears in the **Shortcuts** app automatically and works with **Siri** and Spotlight.
2. **Shortcut → Action Button:** Settings → Action Button → Shortcut → "Call Mistral". This is the setup you asked for.
3. **Control widget** (`ControlWidgetButton`, iOS 18+) running the same intent. It can be assigned to the Action Button **directly** (Settings → Action Button → Controls), without a Shortcut, and also added to Control Center and the lock screen. It's offered as the one-tap alternative.
4. **Deep link** `lebot://call?agent=…` for automations, plus a "Call" button in the app.

### What happens when you press it
1. `StartVoiceCallIntent.perform()` immediately:
   - activates `AVAudioSession` (`.playAndRecord`, `.voiceChat`, Bluetooth/AirPlay allowed)
   - **starts the Live Activity** in the "Calling…" state
   - starts mic capture into a **local ring buffer**, so nothing you say while it connects is lost
   - plays a short connect tone
2. In parallel, it calls `voice-token`, joins the LiveKit room, and flushes the buffered audio to the adapter. A `source = 'action_button'` conversation is created.
3. The Live Activity switches to "Connected" with a call timer. An optional short caption line shows the last thing the agent said.
4. **Live Activity buttons** run `LiveActivityIntent`s in the app process:
   - `ToggleMuteIntent`
   - `EndCallIntent` (leaves the room, ends the activity, and saves the transcript)
   - tapping the banner opens the full in-app voice mode for that conversation
5. The call continues in the background through `UIBackgroundModes: audio`. It ends when you tap end, after a configurable silence timeout (default 2 min), or if the connection drops (with one automatic reconnect).

### Making it fast (target: under 1.5 s from press to "Connected")
- **Pre-warming:** when the app goes to the background, it prefetches a short-lived `voice-token` (LiveKit token TTL about 10 min) and caches it in the Keychain. The intent uses it if it's still valid.
- **Pre-dispatched agent:** `voice-token` asks LiveKit Cloud to dispatch the adapter as soon as the room is created. The adapter keeps a warm worker pool.
- **No waiting on the network for audio:** the mic is buffered locally (step 1), so you can start talking right away.
- **The Edge Function stays warm:** a pg_cron ping every few minutes reduces cold starts on `voice-token`.

### Plumbing
- **App Group + shared Keychain access group:** the app, the widget extension, and the intents share the Supabase session and cached tokens.
- **Targets:** `LeBot` (app, with intents running in-process for audio), `LeBotWidgets` (Live Activity UI, Dynamic Island, Control widget), and `LeBotKit` (a shared Swift package: models, Supabase client, voice session, intents).
- **Info.plist:** `NSMicrophoneUsageDescription`, `UIBackgroundModes = [audio, remote-notification]`, `NSSupportsLiveActivities = YES`.
- **First-run onboarding** includes an "Add to Action Button" step with instructions and a button that opens the relevant Settings or Shortcuts page.

### Fallback
If iOS refuses the background start (for example, mic permission was never granted or a Live Activity can't start), the intent sets `openAppWhenRun`-style behavior: it opens the app straight into voice mode and starts the call there. **CallKit** (system call UI) is kept as an option to evaluate. Its UI matches the "call" metaphor, but App Review may reject using it for a non-telephony assistant, so the Live Activity approach is the default.

---

## 10. Mobile apps

### iOS (built first)
Swift 6, SwiftUI, **iOS 26+** (Liquid Glass; also covers `AudioRecordingIntent` and Control widgets from iOS 18), XcodeGen (`ios/project.yml`), the Observation framework, `supabase-swift`, `LiveKit` Swift SDK, App Intents, ActivityKit, WidgetKit, a Markdown renderer, PhotosUI/camera, APNs, Sign in with Apple. Built with Swift Package Manager.

### Design language
Mistral's brand system, made native to iOS:
- **Colour:** the five-step Mistral rainbow (`#FFD800` → `#FFAF00` → `#FF8205` → `#FA500F` → `#E10500`), warm beige surfaces (`#FFFAEB`) in light mode, and a tinted near-black (`#0E0D0B` / `#1E1E1E`) in dark mode. Primary buttons are ink capsules, Mistral's black call to action.
- **Type:** SF Pro for reading, and SF Mono uppercase "eyebrow" labels (`MISTRAL · LARGE 4`) as the technical, pixel-era accent.
- **Motif:** pixels and stripes. Le Bot's own mark is a rising pixel sun with one rainbow colour per row. It deliberately avoids Mistral's logo while sharing its language.
- **Native structure:** standard navigation, Liquid Glass controls (composer, call buttons), SF Symbols, haptics, Dynamic Type, and Reduce Motion support.
- **Live call visual:** a Metal shader (`PixelSun.metal`) draws a pixel sun whose heat is banded into the rainbow. While connecting, a comet orbits the rim. While listening, rings drift inward. While thinking, heat spirals through the core. While speaking, rings radiate outward with the agent's voice. Loudness eases with a VU-meter attack and decay, and a soft bloom glows underneath. The Live Activity and Dynamic Island use a static pixel-equalizer version.

### Android (Phase 8, after iOS is feature-complete)
Kotlin, Jetpack Compose with Material 3, minSdk 28, Coroutines/Flow, Hilt, `supabase-kt`, LiveKit Android SDK, CameraX, FCM, and Google sign-in via Credential Manager.

The Android equivalent of the Action Button call: a Quick Settings tile, a home-screen widget, a Google Assistant App Action, and an ongoing-call notification (foreground service of type `microphone`) with mute and end actions.

`contracts/` holds JSON Schemas for message parts, agent events, and Realtime payloads. Because the backend never depends on iOS specifics, the Android app is a pure client port.

### Screens
1. Onboarding and auth, including the Action Button setup step
2. **Chat:** streaming markdown, code blocks, images, attachments, Fast/Think toggle, `@agent` / `@skill` mentions, expandable tool-step timeline, approval cards
3. **Voice mode** (section 8), plus the **Live Activity / Dynamic Island** call UI (section 9)
4. **Agents:** list, create, and edit (instructions, model policy, tools, connectors, libraries, voice, who it may message), plus templates and "set as quick-call agent"
5. **Tasks:** a live tree of delegated tasks with status, todos, cost so far, the inter-agent message log, and stop/cancel/approve controls
6. **Canvas:** artifact viewer and editor, with share and export
7. **Connectors:** catalog, OAuth connect, custom MCP URL, tool policy toggles
8. **Libraries & files**, **Skills**, **Scheduled tasks**, **Memories/Knowledge base**
9. Settings: custom instructions, default voice, quick-call agent, **usage & budgets** (cost, cache-hit rate, search count), notifications

---

## 11. Repository layout

```
mistral-bot/
├── docs/                      # this plan, ADRs
├── contracts/                 # JSON Schemas shared by functions + apps
├── supabase/
│   ├── config.toml            # edge_runtime policy = "per_worker" for local bg work
│   ├── migrations/            # schema, RLS, triggers (pg_net kicks, wake-ups), pg_cron jobs
│   ├── seed.sql               # agent templates, built-in skills
│   ├── tests/                 # pgTAP: RLS, triggers, state transitions
│   └── functions/
│       ├── _shared/
│       │   ├── mistral.ts     # thin adapter over the Mistral SDK (preview-API isolation)
│       │   ├── models.ts      # model IDs + prices (config)
│       │   ├── router.ts      # Large/Small/auto routing (per run)
│       │   ├── runtime/       # claim, step, checkpoint, streaming, cache rules, usage ledger
│       │   ├── orchestrator/  # delegation tools, mailbox, guardrails, budgets
│       │   ├── findings/      # harvest + lookup of web-search findings
│       │   ├── mcp/           # MCP client, OAuth refresh, tool policies
│       │   └── realtime.ts    # coalesced broadcast
│       ├── chat-send/
│       ├── agent-step/
│       ├── voice-token/
│       ├── voice-turn/
│       ├── connector-oauth/
│       ├── approvals/
│       └── push-notify/
├── voice/                     # LiveKit voice adapter (Python), deployed via `lk agent deploy`
├── ios/
│   ├── LeBot/                 # app target (SwiftUI, in-process App Intents)
│   ├── LeBotWidgets/     # Live Activity, Dynamic Island, Control widget
│   └── LeBotKit/         # shared Swift package
└── android/                   # Phase 8
```

---

## 12. Delivery phases (iOS first)

Phases 0–7 build the backend and the **iOS app**. Phase 8 ports the finished experience to Android.

| # | Phase | Scope | Done when |
|---|---|---|---|
| 0 | Foundations | Repo scaffolding; Supabase project + local stack (`supabase start`); base migrations + RLS; auth (Apple + email); `agent_runs` + pg_net kick + sweeper with a no-op `agent-step`; iOS app shell with App Group + shared Keychain; CI (`deno test`, pgTAP, `xcodebuild test`) | Sign in on iOS; a test run steps 3× through the kick loop and survives a killed step |
| 1 | Text chat | Main agent on Large 4 via the step runtime, Realtime streaming, history, image/file attachments, Fast/Think, usage ledger, prompt-cache rules 1–4 | Multi-turn streaming chat with images works; costs and cached tokens recorded |
| 2 | Built-in tools + canvas | Built-in web search, open URL, code interpreter, image gen, Libraries, canvas artifacts, tool-step timeline | Agent researches, runs code, produces an image and a canvas doc; **cache-hit rate above 70%** on a 15-step task |
| 3 | Multi-agent + routing | Agent CRUD + templates, orchestration tools, tasks/mailbox, park/wake triggers, guardrails, budgets, model router, **findings cache**, Tasks screen | Main agent splits a job across 2+ Small 4 sub-agents in parallel; sub-agents reuse findings instead of re-searching; you can cancel a branch and see cost per task |
| 4 | Connectors + approvals | MCP gateway, OAuth catalog (Google, Microsoft, Slack, Notion, GitHub), custom MCP, Vault tokens, tool policies, write-ahead log, approval cards + push | "Summarize my unread mail and draft replies" works, and sending needs your approval and never sends twice |
| 5 | Voice + Action Button | LiveKit Cloud project, `voice-token`, `voice-turn`, adapter deploy, Voxtral STT/TTS, barge-in, spoken task results, in-app voice mode; **`StartVoiceCallIntent` (AudioRecordingIntent), App Shortcut, Control widget, Live Activity + Dynamic Island with mute/end, pre-warming, local audio buffer**; latency/cost benchmark vs. the bundled voice agent API | Press the Action Button on the lock screen → "Calling…" banner → talking to the agent in **under 1.5 s**, without opening the app; it delegates a task and speaks the result; mute and end work from the banner |
| 6 | Work-mode extras | Skills, memories/knowledge base, projects, scheduled tasks (with batch option), history compaction, push for background completions | Daily scheduled briefing runs and notifies you |
| 7 | iOS hardening & release | Daily budgets, Sentry (functions, voice adapter, iOS), load test of concurrent runs vs. Edge Function concurrency, privacy policy, App Store review prep (mic/background-audio justification) | Build on TestFlight; you use it daily |
| 8 | Android | Compose app against the same backend, with feature parity; Quick Settings tile, widget, Assistant App Action, ongoing-call notification | Play internal testing build with the same flows as iOS |

**Testing approach**
- **Functions:** `deno test` for the runtime, orchestrator state machine, guardrails, router, budget math, cache-rule invariants (stable prefix, fixed tool set per run), and findings TTL. Includes crash/replay tests that kill a step mid-way and assert there are no duplicate side effects.
- **Integration:** against the local Supabase stack, with Mistral recorded fixtures behind a flag
- **MCP gateway:** tested against a local fake MCP server
- **Database:** pgTAP for RLS, triggers, and wake-ups
- **iOS:**
  - Swift Testing for view models and voice session state
  - XCUITest for the main flows
  - snapshot tests for chat rendering and Live Activity layouts
  - a manual test matrix on a real device for the Action Button, covering lock screen, in another app, AirPods connected, and no network
- **Android (Phase 8):** JUnit + Compose UI tests

---

## 13. Defaults chosen (change any of them)

- **iOS first**, native SwiftUI, iOS 26+. Android native Compose afterwards.
- **Backend:** Supabase only (Pro plan). Voice is the only non-Supabase piece, and LiveKit Cloud hosts it.
- **Web search:** Mistral built-in, with the findings cache and per-task caps
- **Quick call:** `AudioRecordingIntent` + Live Activity (not CallKit). Triggered from the Action Button via the Shortcut or the Control widget.
- **Audience:** built multi-user-safe (RLS, per-user OAuth) even if it's only for you at first
- **Bring your own key:** each user adds their own Mistral API key in Settings (or from the prompt card in chat). The `api-keys` Edge Function checks it against Mistral (`GET /v1/models`), then stores it encrypted in **Supabase Vault**. A `provider_credentials` row holds only the last four characters and the verification status, and clients can't read the Vault reference. The runtime decrypts the key server-side with `getMistralKey()`, so background and scheduled runs keep working while the app is closed. The app never sees the key again. Usage, including voice and web search, bills to the user's own Mistral account. A server-wide `MISTRAL_API_KEY` is only a dev fallback, and `chat-send` returns `412 missing_api_key` when neither key exists. Clients only ever get Supabase JWTs, LiveKit tokens, or ephemeral Mistral client sessions.

## 14. Risks

- **Preview APIs:** Large 4, Voxtral 3, the Connectors API, and parts of the Agents/Conversations API are preview or beta. Isolate them behind `_shared/mistral.ts` and keep IDs and prices in config.
- **Edge Function limits:** wall-clock time is handled by step chunking and the 300 s guard. The CPU budget is a risk only for heavy local work (large file parsing), which is offloaded to Mistral OCR or Files. Concurrency is capped per user and globally. If limits bite later, `agent-step` can be lifted into any long-running Deno container without changing code, since it's plain HTTP + Postgres.
- **Exactly-once side effects:** handled by the `tool_calls` write-ahead log and idempotency keys. Covered by crash/replay tests.
- **Background voice start on iOS:** `AudioRecordingIntent` requires a Live Activity and mic permission granted beforehand. It's verified early in Phase 5 on a real device, with the open-app fallback. App Review needs a clear justification for background audio.
- **Voice latency on Large 4:** mitigations are in sections 8 and 9; benchmarked in Phase 5.
- **Cost:** parallel sub-agents and web search add up quickly. Mitigated by prompt caching, routing, the findings cache, budgets, and search caps (section 7).
- **Prompt-cache regressions:** a small prompt change can silently drop the hit rate. Cache-rule tests and the below-50% alert catch it.
- **Supabase Realtime throughput:** deltas are coalesced. Fallback is SSE straight from `chat-send` for the foreground turn.
