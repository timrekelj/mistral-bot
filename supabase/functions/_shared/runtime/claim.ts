import type { SupabaseClient } from "@supabase/supabase-js";

export type RunStatus =
  | "ready"
  | "running"
  | "waiting_input"
  | "waiting_approval"
  | "waiting_subtasks"
  | "completed"
  | "failed"
  | "cancelled";

export interface AgentRun {
  id: string;
  user_id: string;
  agent_id: string;
  conversation_id: string;
  status: RunStatus;
  step_no: number;
  attempts: number;
  lease_owner: string | null;
  lease_until: string | null;
  next_input: Record<string, unknown>;
  model: string | null;
  tool_set_hash: string | null;
}

export const LEASE_SECONDS = 420;
export const MAX_RUNNING_PER_USER = 6;

// The RPCs return a composite type; "no row" comes back as null or an all-null record.
function rowOrNull(data: unknown): AgentRun | null {
  const run = data as AgentRun | null;
  return run?.id ? run : null;
}

/** Leases a ready run to `owner`. Null means another worker owns it or the user is at the cap. */
export async function claimRun(
  db: SupabaseClient,
  runId: string,
  owner: string,
): Promise<AgentRun | null> {
  const { data, error } = await db.rpc("claim_agent_run", {
    p_run_id: runId,
    p_owner: owner,
    p_lease_seconds: LEASE_SECONDS,
    p_max_running: MAX_RUNNING_PER_USER,
  });
  if (error) throw new Error(`claim_agent_run: ${error.message}`);
  return rowOrNull(data);
}

export interface Release {
  status: Exclude<RunStatus, "running">;
  stepNo: number;
  nextInput?: Record<string, unknown>;
  error?: string;
}

export async function releaseRun(
  db: SupabaseClient,
  run: AgentRun,
  owner: string,
  release: Release,
): Promise<AgentRun | null> {
  const { data, error } = await db.rpc("release_agent_run", {
    p_run_id: run.id,
    p_owner: owner,
    p_status: release.status,
    p_step_no: release.stepNo,
    p_next_input: release.nextInput ?? null,
    p_error: release.error ?? null,
  });
  if (error) throw new Error(`release_agent_run: ${error.message}`);
  return rowOrNull(data);
}

/** Records the error and expires the lease; the sweeper retries or fails the run. */
export async function abandonRun(
  db: SupabaseClient,
  runId: string,
  owner: string,
  message: string,
): Promise<void> {
  const { error } = await db.rpc("abandon_agent_run", {
    p_run_id: runId,
    p_owner: owner,
    p_error: message,
  });
  if (error) throw new Error(`abandon_agent_run: ${error.message}`);
}
