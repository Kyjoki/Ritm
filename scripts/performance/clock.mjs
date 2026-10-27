// Deterministic demo clock, loaded ONLY by the local performance runner/probe.
// Production application code never imports this file.
(() => {
  const NativeDate = Date;
  const epoch = NativeDate.parse('2026-10-27T12:00:00Z');
  const started = performance.now();
  class DemoDate extends NativeDate {
    constructor(...args) {
      if (args.length) super(...args);
      else super(Math.trunc(epoch + performance.now() - started));
    }
    static now() {
      return Math.trunc(epoch + performance.now() - started);
    }
  }
  globalThis.Date = DemoDate;
})();
