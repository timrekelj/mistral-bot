// Realtime broadcast for `conversation:{id}` channels (contracts/realtime-event.schema.json).
// Token deltas are coalesced and flushed about every 50 ms; other events flush pending
// deltas first so clients always see them in order.

import type { Env } from "./env.ts";
import type { RunStatus } from "./runtime/claim.ts";

export interface DeltaEvent {
  type: "delta";
  run_id: string;
  message_id: string;
  seq: number;
  text: string;
}

export interface MessageCompletedEvent {
  type: "message_completed";
  run_id: string | null;
  message_id: string;
}

export interface AgentEventRecord {
  id: string;
  run_id: string | null;
  agent_id: string | null;
  step_no: number | null;
  type: string;
  payload: Record<string, unknown>;
  created_at: string;
}

export interface AgentEventEvent {
  type: "agent_event";
  event: AgentEventRecord;
}

export interface RunStatusEvent {
  type: "run_status";
  run_id: string;
  status: RunStatus;
  step_no: number;
  error?: string;
}

export type RealtimeEvent = DeltaEvent | MessageCompletedEvent | AgentEventEvent | RunStatusEvent;

export interface BroadcastMessage {
  topic: string;
  event: RealtimeEvent["type"];
  payload: RealtimeEvent;
}

export type Sender = (messages: BroadcastMessage[]) => Promise<void>;
export type Scheduler = (fn: () => void, ms: number) => () => void;

export function conversationTopic(conversationId: string): string {
  return `conversation:${conversationId}`;
}

const defaultScheduler: Scheduler = (fn, ms) => {
  const id = setTimeout(fn, ms);
  return () => clearTimeout(id);
};

export interface BroadcasterOptions {
  intervalMs?: number;
  schedule?: Scheduler;
  onError?: (error: unknown) => void;
}

export class CoalescingBroadcaster {
  readonly #topic: string;
  readonly #send: Sender;
  readonly #intervalMs: number;
  readonly #schedule: Scheduler;
  readonly #onError: (error: unknown) => void;
  // Insertion-ordered by message so interleaved streams keep their relative order.
  readonly #pending = new Map<string, { runId: string; text: string }>();
  readonly #seq = new Map<string, number>();
  #cancelTimer: (() => void) | null = null;
  #chain: Promise<void> = Promise.resolve();

  constructor(topic: string, send: Sender, options: BroadcasterOptions = {}) {
    this.#topic = topic;
    this.#send = send;
    this.#intervalMs = options.intervalMs ?? 50;
    this.#schedule = options.schedule ?? defaultScheduler;
    this.#onError = options.onError ?? ((error) => console.error("realtime flush failed", error));
  }

  /** Buffers a token delta; it goes out with the next flush. */
  delta(runId: string, messageId: string, text: string): void {
    if (text.length === 0) return;
    const pending = this.#pending.get(messageId);
    if (pending) pending.text += text;
    else this.#pending.set(messageId, { runId, text });
    this.#cancelTimer ??= this.#schedule(() => {
      this.#cancelTimer = null;
      this.flush().catch(this.#onError);
    }, this.#intervalMs);
  }

  /** Sends an event immediately, preceded by any buffered deltas. */
  emit(event: Exclude<RealtimeEvent, DeltaEvent>): Promise<void> {
    return this.#enqueue([...this.#drain(), this.#message(event)]);
  }

  flush(): Promise<void> {
    return this.#enqueue(this.#drain());
  }

  #drain(): BroadcastMessage[] {
    this.#cancelTimer?.();
    this.#cancelTimer = null;
    const messages = [...this.#pending].map(([messageId, { runId, text }]) => {
      const seq = this.#seq.get(messageId) ?? 0;
      this.#seq.set(messageId, seq + 1);
      return this.#message({ type: "delta", run_id: runId, message_id: messageId, seq, text });
    });
    this.#pending.clear();
    return messages;
  }

  #message(payload: RealtimeEvent): BroadcastMessage {
    return { topic: this.#topic, event: payload.type, payload };
  }

  // Sends are chained so batches reach Realtime in the order they were produced.
  #enqueue(messages: BroadcastMessage[]): Promise<void> {
    if (messages.length === 0) return this.#chain;
    const sent = this.#chain.then(() => this.#send(messages));
    this.#chain = sent.catch(() => {});
    return sent;
  }
}

/** Sends batches through the Realtime broadcast REST endpoint as private-channel messages. */
export function restSender(env: Env, fetchFn: typeof fetch = fetch): Sender {
  const url = `${env.supabaseUrl}/realtime/v1/api/broadcast`;
  return async (messages) => {
    const response = await fetchFn(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: env.serviceRoleKey,
        Authorization: `Bearer ${env.serviceRoleKey}`,
      },
      body: JSON.stringify({
        messages: messages.map((m) => ({ ...m, private: true })),
      }),
    });
    if (!response.ok) {
      throw new Error(`realtime broadcast failed: ${response.status} ${await response.text()}`);
    }
    await response.body?.cancel();
  };
}
