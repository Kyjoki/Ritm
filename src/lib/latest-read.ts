/** One cancellable read per mounted data owner; writes invalidate older snapshots. */
export class LatestRead {
  private controller: AbortController | null = null;
  start(): AbortSignal {
    this.cancel();
    this.controller = new AbortController();
    return this.controller.signal;
  }
  isCurrent(signal: AbortSignal): boolean {
    return this.controller?.signal === signal && !signal.aborted;
  }
  cancel(): void {
    this.controller?.abort();
    this.controller = null;
  }
}

/** Coalesce read requests until all optimistic writes settle and the page is active. */
export class RefreshGate {
  private active = false;
  private writes = 0;
  private queued = false;
  get writing(): boolean {
    return this.writes > 0;
  }
  activate(): void {
    this.active = true;
  }
  deactivate(): void {
    this.active = false;
  }
  request(): boolean {
    this.queued = true;
    return this.take();
  }
  beginWrite(needsSnapshot = false): void {
    this.writes++;
    this.queued ||= needsSnapshot;
  }
  endWrite(): boolean {
    this.writes = Math.max(0, this.writes - 1);
    return this.take();
  }
  private take(): boolean {
    if (!this.queued || !this.active || this.writes) return false;
    this.queued = false;
    return true;
  }
}
