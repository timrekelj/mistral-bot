// Pure step-transition logic, kept free of I/O so it can be unit-tested.

export const MAX_TARGET_STEPS = 50;

export type StepOutcome =
  /** The step's work is persisted; move on. */
  | "done"
  /** The time guard fired mid-step; resume the same step in a fresh invocation. */
  | "checkpoint";

export interface NextState {
  status: "ready" | "completed";
  stepNo: number;
}

/** Phase 0 no-op runs step until `next_input.target_steps` steps have completed. */
export function targetSteps(nextInput: Record<string, unknown>): number {
  const value = nextInput.target_steps;
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) return 1;
  return Math.min(value, MAX_TARGET_STEPS);
}

export function decideNext(
  stepNo: number,
  nextInput: Record<string, unknown>,
  outcome: StepOutcome,
): NextState {
  if (outcome === "checkpoint") return { status: "ready", stepNo };
  const next = stepNo + 1;
  return { status: targetSteps(nextInput) > next ? "ready" : "completed", stepNo: next };
}
