/* Local-only diagnostic probe. Not included in the released application. */
(() => {
  let active = false,
    frames = [],
    longTasks = [],
    requests = [],
    interactions = [],
    reads = 0,
    clones = 0,
    start = performance.now(),
    last = 0,
    raf = 0;
  const rect = Element.prototype.getBoundingClientRect;
  Element.prototype.getBoundingClientRect = function (...args) {
    if (active) reads++;
    return rect.apply(this, args);
  };
  const clone = Node.prototype.cloneNode;
  Node.prototype.cloneNode = function (...args) {
    if (active) clones++;
    return clone.apply(this, args);
  };
  const originalFetch = window.fetch;
  window.fetch = function (...args) {
    if (active) requests.push(String(args[0]).split('?')[0]);
    return originalFetch.apply(this, args);
  };
  let observer;
  if (PerformanceObserver.supportedEntryTypes.includes('longtask')) {
    observer = new PerformanceObserver((list) => {
      if (active) longTasks.push(...list.getEntries().map((e) => Math.round(e.duration)));
    });
    observer.observe({ type: 'longtask', buffered: false });
  }
  const tick = (now) => {
    if (!active) return;
    if (last) frames.push(now - last);
    last = now;
    raf = requestAnimationFrame(tick);
  };
  raf = requestAnimationFrame(tick);
  document.addEventListener(
    'click',
    (e) => {
      if (!active || e.target.closest('#perf-probe')) return;
      const label = e.target.closest('button,a')?.textContent?.trim().slice(0, 60) || 'content';
      const began = performance.now();
      requestAnimationFrame(() =>
        requestAnimationFrame(() => {
          if (active) interactions.push({ label, twoRafMs: Math.round(performance.now() - began) });
        }),
      );
    },
    true,
  );
  function report() {
    const sorted = [...frames].sort((a, b) => a - b);
    return {
      environment: 'Desktop Chromium; mobile viewport is NOT iPhone hardware',
      viewport: [innerWidth, innerHeight],
      seconds: Math.round((performance.now() - start) / 100) / 10,
      frames: frames.length,
      frameP95Ms: Math.round(sorted[Math.floor(sorted.length * 0.95)] || 0),
      framesOver34ms: frames.filter((x) => x > 34).length,
      longTasks,
      rectReads: reads,
      deepClones: clones,
      requests,
      interactions,
      heapMB: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null,
      domElements: document.querySelectorAll('#root *').length,
    };
  }
  addEventListener('DOMContentLoaded', () => {
    const panel = document.createElement('details');
    panel.id = 'perf-probe';
    panel.style.cssText =
      'position:fixed;right:4px;top:4px;z-index:100000;background:#fff;color:#222;border:1px solid #7655b9;border-radius:8px;padding:5px;max-width:96vw;font:12px monospace;max-height:55vh;overflow:auto';
    panel.innerHTML =
      '<summary>Performance · local</summary><button id="perf-reset">Reset measurement</button> <button id="perf-stop">Stop and report</button><pre id="perf-report"></pre>';
    document.body.append(panel);
    document.getElementById('perf-reset').onclick = () => {
      cancelAnimationFrame(raf);
      active = true;
      frames = [];
      longTasks = [];
      requests = [];
      interactions = [];
      reads = 0;
      clones = 0;
      start = performance.now();
      last = 0;
      raf = requestAnimationFrame(tick);
      document.getElementById('perf-report').textContent = 'Recording';
    };
    document.getElementById('perf-stop').onclick = () => {
      active = false;
      cancelAnimationFrame(raf);
      document.getElementById('perf-report').textContent = JSON.stringify(report(), null, 2);
    };
  });
})();
