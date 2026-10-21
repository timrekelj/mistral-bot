import { assert, assertEquals, assertFalse } from "@std/assert";
import { STEP_BUDGET_MS, TimeGuard } from "../_shared/runtime/time_guard.ts";

function fakeClock(start = 1_000) {
  let now = start;
  return { now: () => now, advance: (ms: number) => (now += ms) };
}

Deno.test("defaults to a 300 s budget", () => {
  assertEquals(STEP_BUDGET_MS, 300_000);
  assertEquals(new TimeGuard().budgetMs, 300_000);
});

Deno.test("tracks elapsed and remaining time", () => {
  const clock = fakeClock();
  const guard = new TimeGuard(300_000, clock.now);
  clock.advance(120_000);
  assertEquals(guard.elapsedMs(), 120_000);
  assertEquals(guard.remainingMs(), 180_000);
  assertFalse(guard.expired());
});

Deno.test("expires at the budget and never reports negative remaining time", () => {
  const clock = fakeClock();
  const guard = new TimeGuard(300_000, clock.now);
  clock.advance(299_999);
  assertFalse(guard.expired());
  clock.advance(1);
  assert(guard.expired());
  clock.advance(60_000);
  assertEquals(guard.remainingMs(), 0);
});
