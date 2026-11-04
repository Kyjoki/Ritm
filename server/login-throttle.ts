import type { RuntimeState } from './runtime-state.ts';
import { AppError } from './errors.ts';

/** Account-wide failure budget; it only slows guessing and never locks the owner out for good. */
export const FAILURE_BUDGET = 20;
export const FAILURE_WINDOW_MS = 60 * 60_000;
export const FIRST_DELAY_MS = 15_000;
export const MAX_DELAY_MS = 15 * 60_000;
const STATE_NAME = 'auth:failure-budget';

interface ThrottleRecord {
  count: number;
  windowStart: number;
  blockedUntil: number;
}

/** Delay after the n-th failure of the window: none within budget, then 15 s doubling up to 15 min. */
export function lockoutDelayMs(failures: number) {
  const over = failures - FAILURE_BUDGET;
  if (over <= 0) return 0;
  return Math.min(MAX_DELAY_MS, FIRST_DELAY_MS * 2 ** Math.min(over - 1, 20));
}

const parse = (text: string | null): ThrottleRecord => {
  try {
    const value = JSON.parse(text ?? '');
    if (
      Number.isFinite(value?.count) &&
      Number.isFinite(value?.windowStart) &&
      Number.isFinite(value?.blockedUntil)
    )
      return value;
  } catch {
    // A damaged record is treated as an empty budget instead of locking the owner.
  }
  return { count: 0, windowStart: 0, blockedUntil: 0 };
};

export class LoginThrottle {
  constructor(
    private state: RuntimeState,
    private now: () => number = Date.now,
  ) {}
  private async load() {
    return parse(await this.state.getServerSecret(STATE_NAME));
  }
  async assertOpen() {
    const record = await this.load(),
      time = this.now();
    if (record.blockedUntil > time) {
      const seconds = Math.max(1, Math.ceil((record.blockedUntil - time) / 1000));
      throw new AppError(
        429,
        'LOGIN_LOCKED',
        `Слишком много неудачных попыток входа. Повторите через ${seconds} с.`,
        Math.min(seconds, 3600),
      );
    }
  }
  async recordFailure() {
    const record = await this.load(),
      time = this.now();
    const fresh = time - record.windowStart >= FAILURE_WINDOW_MS;
    const count = (fresh ? 0 : record.count) + 1;
    const next: ThrottleRecord = {
      count,
      windowStart: fresh ? time : record.windowStart,
      blockedUntil: lockoutDelayMs(count) ? time + lockoutDelayMs(count) : 0,
    };
    await this.state.setServerSecret(STATE_NAME, JSON.stringify(next));
  }
  async recordSuccess() {
    await this.state.deleteServerSecret(STATE_NAME);
  }
}
