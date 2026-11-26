/** Token bucket with lazy refill. */
export class TokenBucket {
  private tokens: number;
  private last: number;

  constructor(
    private readonly ratePerSec: number,
    private readonly burst: number,
    now: number = Date.now(),
  ) {
    this.tokens = burst;
    this.last = now;
  }

  /** Consumes one token; false when the bucket is empty. */
  take(now: number = Date.now()): boolean {
    const elapsed = Math.max(0, now - this.last);
    this.last = now;
    this.tokens = Math.min(this.burst, this.tokens + (elapsed / 1000) * this.ratePerSec);
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}
