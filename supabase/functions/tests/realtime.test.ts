import { assertEquals, assertRejects } from "@std/assert";
import {
  type BroadcastMessage,
  CoalescingBroadcaster,
  conversationTopic,
  restSender,
  type Scheduler,
} from "../_shared/realtime.ts";

const TOPIC = conversationTopic("c1");

function fakeScheduler() {
  const timers: { fn: () => void; ms: number; cancelled: boolean }[] = [];
  const schedule: Scheduler = (fn, ms) => {
    const timer = { fn, ms, cancelled: false };
    timers.push(timer);
    return () => (timer.cancelled = true);
  };
  const fire = () =>
    timers.filter((t) => !t.cancelled).forEach((t) => (t.cancelled = true, t.fn()));
  const active = () => timers.filter((t) => !t.cancelled).length;
  return { schedule, fire, active, timers };
}

function recorder() {
  const batches: BroadcastMessage[][] = [];
  return {
    batches,
    send: (messages: BroadcastMessage[]) => (batches.push(messages), Promise.resolve()),
  };
}

Deno.test("coalesces deltas into one message per flush interval", async () => {
  const clock = fakeScheduler();
  const out = recorder();
  const b = new CoalescingBroadcaster(TOPIC, out.send, { schedule: clock.schedule });

  b.delta("r1", "m1", "Hel");
  b.delta("r1", "m1", "lo");
  b.delta("r1", "m1", "");
  assertEquals(clock.active(), 1);
  assertEquals(clock.timers[0].ms, 50);
  assertEquals(out.batches.length, 0);

  clock.fire();
  await b.flush();
  assertEquals(out.batches, [[{
    topic: "conversation:c1",
    event: "delta",
    payload: { type: "delta", run_id: "r1", message_id: "m1", seq: 0, text: "Hello" },
  }]]);
});

Deno.test("numbers delta batches per message", async () => {
  const clock = fakeScheduler();
  const out = recorder();
  const b = new CoalescingBroadcaster(TOPIC, out.send, { schedule: clock.schedule });

  b.delta("r1", "m1", "a");
  b.delta("r1", "m2", "x");
  clock.fire();
  b.delta("r1", "m1", "b");
  await b.flush();

  const seqs = out.batches.flat().map((m) =>
    m.payload.type === "delta" && [m.payload.message_id, m.payload.seq]
  );
  assertEquals(seqs, [["m1", 0], ["m2", 0], ["m1", 1]]);
});

Deno.test("emit flushes pending deltas first and cancels the timer", async () => {
  const clock = fakeScheduler();
  const out = recorder();
  const b = new CoalescingBroadcaster(TOPIC, out.send, { schedule: clock.schedule });

  b.delta("r1", "m1", "partial");
  await b.emit({ type: "message_completed", run_id: "r1", message_id: "m1" });

  assertEquals(clock.active(), 0);
  assertEquals(out.batches.length, 1);
  assertEquals(out.batches[0].map((m) => m.event), ["delta", "message_completed"]);
});

Deno.test("flush with nothing pending sends nothing", async () => {
  const out = recorder();
  const b = new CoalescingBroadcaster(TOPIC, out.send, { schedule: fakeScheduler().schedule });
  await b.flush();
  assertEquals(out.batches.length, 0);
});

Deno.test("batches are delivered in order even when sends resolve out of order", async () => {
  const delivered: string[] = [];
  const delays = [20, 0];
  const send = async (messages: BroadcastMessage[]) => {
    await new Promise((resolve) => setTimeout(resolve, delays.shift()));
    delivered.push(...messages.map((m) => m.event));
  };
  const b = new CoalescingBroadcaster(TOPIC, send, { schedule: fakeScheduler().schedule });

  const first = b.emit({ type: "run_status", run_id: "r1", status: "running", step_no: 0 });
  const second = b.emit({ type: "message_completed", run_id: "r1", message_id: "m1" });
  await Promise.all([first, second]);
  assertEquals(delivered, ["run_status", "message_completed"]);
});

Deno.test("a failed send rejects that batch without blocking later ones", async () => {
  let calls = 0;
  const send = (_: BroadcastMessage[]) =>
    ++calls === 1 ? Promise.reject(new Error("down")) : Promise.resolve();
  const b = new CoalescingBroadcaster(TOPIC, send, { schedule: fakeScheduler().schedule });

  await assertRejects(() => b.emit({ type: "message_completed", run_id: null, message_id: "m1" }));
  await b.emit({ type: "message_completed", run_id: null, message_id: "m2" });
  assertEquals(calls, 2);
});

Deno.test("timer flush errors go to onError", async () => {
  const clock = fakeScheduler();
  const errors: unknown[] = [];
  const b = new CoalescingBroadcaster(TOPIC, () => Promise.reject(new Error("down")), {
    schedule: clock.schedule,
    onError: (e) => errors.push(e),
  });
  b.delta("r1", "m1", "x");
  clock.fire();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(errors.length, 1);
});

Deno.test("restSender posts private broadcasts with the service key", async () => {
  let captured: Request | undefined;
  const fetchFn: typeof fetch = (input, init) => {
    captured = new Request(input, init);
    return Promise.resolve(new Response(null, { status: 202 }));
  };
  const env = { supabaseUrl: "http://sb.test", anonKey: "anon", serviceRoleKey: "service" };
  await restSender(env, fetchFn)([{
    topic: TOPIC,
    event: "message_completed",
    payload: { type: "message_completed", run_id: null, message_id: "m1" },
  }]);

  assertEquals(captured?.url, "http://sb.test/realtime/v1/api/broadcast");
  assertEquals(captured?.headers.get("Authorization"), "Bearer service");
  assertEquals(captured?.headers.get("apikey"), "service");
  const body = await captured?.json();
  assertEquals(body.messages[0].private, true);
  assertEquals(body.messages[0].topic, "conversation:c1");
});

Deno.test("restSender surfaces HTTP errors", async () => {
  const fetchFn: typeof fetch = () => Promise.resolve(new Response("nope", { status: 401 }));
  const env = { supabaseUrl: "http://sb.test", anonKey: "anon", serviceRoleKey: "service" };
  await assertRejects(() => restSender(env, fetchFn)([]), Error, "401");
});
