// Executes one step of an agent run. Invoked by the pg_net kick trigger and the sweeper.
// Phase 0: the step is a no-op that records an event and advances the run.

import { isServiceRequest } from "../_shared/auth.ts";
import { loadEnv } from "../_shared/env.ts";
import { errorResponse, HttpError, isUuid, json, readJsonObject } from "../_shared/http.ts";
import {
  type AgentEventRecord,
  CoalescingBroadcaster,
  conversationTopic,
  restSender,
} from "../_shared/realtime.ts";
import { abandonRun, type AgentRun, claimRun, releaseRun } from "../_shared/runtime/claim.ts";
import { decideNext } from "../_shared/runtime/step.ts";
import { TimeGuard } from "../_shared/runtime/time_guard.ts";
import { serviceClient } from "../_shared/supabase.ts";

const env = loadEnv();
const db = serviceClient(env);
const send = restSender(env);

type EdgeRuntimeGlobal = { EdgeRuntime?: { waitUntil(promise: Promise<unknown>): void } };

/** Keeps the worker alive after responding, so pg_net's short timeout never cuts a step. */
function runInBackground(work: Promise<unknown>): void {
  const runtime = (globalThis as EdgeRuntimeGlobal).EdgeRuntime;
  if (runtime) runtime.waitUntil(work);
}

async function executeStep(run: AgentRun, owner: string, guard: TimeGuard): Promise<void> {
  const realtime = new CoalescingBroadcaster(conversationTopic(run.conversation_id), send);
  try {
    const { data: event, error } = await db
      .from("agent_events")
      .insert({
        user_id: run.user_id,
        conversation_id: run.conversation_id,
        run_id: run.id,
        agent_id: run.agent_id,
        step_no: run.step_no,
        type: "noop_step",
        payload: { step_no: run.step_no },
      })
      .select("id, run_id, agent_id, step_no, type, payload, created_at")
      .single<AgentEventRecord>();
    if (error) throw new Error(`insert agent_event: ${error.message}`);
    await realtime.emit({ type: "agent_event", event });

    const next = decideNext(run.step_no, run.next_input, guard.expired() ? "checkpoint" : "done");
    const released = await releaseRun(db, run, owner, next);
    if (!released) throw new Error("lease lost before release");
    await realtime.emit({
      type: "run_status",
      run_id: run.id,
      status: released.status,
      step_no: released.step_no,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`agent-step ${run.id}#${run.step_no} failed: ${message}`);
    await abandonRun(db, run.id, owner, message).catch((e) => console.error(e));
  } finally {
    await realtime.flush().catch((e) => console.error(e));
  }
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") throw new HttpError(405, "method not allowed");
    if (!isServiceRequest(req, env.serviceRoleKey)) throw new HttpError(401, "unauthorized");

    const { run_id: runId } = await readJsonObject(req);
    if (!isUuid(runId)) throw new HttpError(400, "run_id must be a uuid");

    const guard = new TimeGuard();
    const owner = crypto.randomUUID();
    const run = await claimRun(db, runId, owner);
    if (!run) return json({ claimed: false, run_id: runId });

    const work = executeStep(run, owner, guard);
    runInBackground(work);
    // Outside the Edge Runtime (e.g. plain `deno run`), finish the step inline.
    if (!(globalThis as EdgeRuntimeGlobal).EdgeRuntime) await work;
    return json({ claimed: true, run_id: runId, step_no: run.step_no }, 202);
  } catch (error) {
    return errorResponse(error);
  }
});
