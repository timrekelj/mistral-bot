import { assertEquals } from "@std/assert";
import { decideNext, MAX_TARGET_STEPS, targetSteps } from "../_shared/runtime/step.ts";

Deno.test("targetSteps defaults to 1 for missing or invalid values", () => {
  assertEquals(targetSteps({}), 1);
  assertEquals(targetSteps({ target_steps: 0 }), 1);
  assertEquals(targetSteps({ target_steps: 2.5 }), 1);
  assertEquals(targetSteps({ target_steps: "3" }), 1);
});

Deno.test("targetSteps caps runaway loops", () => {
  assertEquals(targetSteps({ target_steps: 10_000 }), MAX_TARGET_STEPS);
});

Deno.test("a single-step run completes after step 0", () => {
  assertEquals(decideNext(0, { target_steps: 1 }, "done"), { status: "completed", stepNo: 1 });
});

Deno.test("a three-step run is re-queued twice, then completes", () => {
  const input = { target_steps: 3 };
  assertEquals(decideNext(0, input, "done"), { status: "ready", stepNo: 1 });
  assertEquals(decideNext(1, input, "done"), { status: "ready", stepNo: 2 });
  assertEquals(decideNext(2, input, "done"), { status: "completed", stepNo: 3 });
});

Deno.test("a checkpoint re-queues the same step", () => {
  assertEquals(decideNext(1, { target_steps: 1 }, "checkpoint"), { status: "ready", stepNo: 1 });
});
