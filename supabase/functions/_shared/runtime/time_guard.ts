// Edge Functions are killed at 400 s wall clock on paid plans; steps checkpoint at 300 s.
export const STEP_BUDGET_MS = 300_000;

export class TimeGuard {
  readonly #startedAt: number;

  constructor(
    readonly budgetMs: number = STEP_BUDGET_MS,
    private readonly now: () => number = Date.now,
  ) {
    this.#startedAt = now();
  }

  elapsedMs(): number {
    return this.now() - this.#startedAt;
  }

  remainingMs(): number {
    return Math.max(0, this.budgetMs - this.elapsedMs());
  }

  expired(): boolean {
    return this.elapsedMs() >= this.budgetMs;
  }
}
