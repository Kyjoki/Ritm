import test from 'node:test';
import assert from 'node:assert/strict';
import { activateDialogViewport } from '../src/lib/dialog-viewport';

function harness(run: (env: ReturnType<typeof environment>) => void) {
  const originals = ['window', 'document', 'getComputedStyle'].map(
    (key) => [key, Object.getOwnPropertyDescriptor(globalThis, key)] as const,
  );
  const env = environment();
  Object.defineProperties(globalThis, {
    window: { value: env.window, configurable: true },
    document: { value: env.document, configurable: true },
    getComputedStyle: { value: () => ({ zoom: '0.8' }), configurable: true },
  });
  try {
    run(env);
  } finally {
    for (const [key, descriptor] of originals) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else Reflect.deleteProperty(globalThis, key);
    }
  }
}
function environment() {
  const frames = new Map<number, FrameRequestCallback>();
  let sequence = 0;
  const writes: [string, string][] = [];
  const values = new Map<string, string>();
  const viewport = Object.assign(new EventTarget(), {
    offsetTop: 0,
    offsetLeft: 0,
    width: 390,
    height: 844,
  });
  const scrolls: [number, number][] = [];
  const window = Object.assign(new EventTarget(), {
    visualViewport: viewport,
    innerWidth: 390,
    innerHeight: 844,
    scrollY: 325,
    requestAnimationFrame(callback: FrameRequestCallback) {
      frames.set(++sequence, callback);
      return sequence;
    },
    cancelAnimationFrame(id: number) {
      frames.delete(id);
    },
    scrollTo(x: number, y: number) {
      scrolls.push([x, y]);
    },
  });
  const document = {
    body: { style: { position: '', top: '', width: '', overflow: '' } },
    documentElement: { style: { overflow: '' } },
  };
  const dialog = {
    style: {
      setProperty(key: string, value: string) {
        writes.push([key, value]);
        values.set(key, value);
      },
    },
  } as unknown as HTMLDialogElement;
  const flush = () => {
    const pending = [...frames.values()];
    frames.clear();
    pending.forEach((callback) => callback(0));
  };
  return { window, viewport, document, dialog, frames, writes, values, flush, scrolls };
}

test('dialog keeps synchronous initial position and coalesces keyboard viewport event bursts', () =>
  harness((env) => {
    const release = activateDialogViewport(env.dialog);
    try {
      assert.equal(env.values.get('--dialog-vv-width'), '487.5px');
      assert.equal(env.values.get('--dialog-vv-height'), '1055px');
      assert.equal(env.writes.length, 6);
      env.viewport.height = 400;
      env.viewport.offsetTop = 44;
      env.viewport.dispatchEvent(new Event('resize'));
      env.viewport.dispatchEvent(new Event('scroll'));
      env.window.dispatchEvent(new Event('resize'));
      assert.equal(env.frames.size, 1);
      assert.equal(env.writes.length, 6);
      env.flush();
      assert.equal(env.values.get('--dialog-vv-top'), '55px');
      assert.equal(env.values.get('--dialog-vv-height'), '500px');
      assert.equal(env.values.get('--dialog-vv-bottom'), '500px');
      assert.equal(env.writes.length, 12);
      env.viewport.dispatchEvent(new Event('resize'));
      env.flush();
      assert.equal(env.writes.length, 12, 'unchanged geometry does not rewrite styles');
    } finally {
      release();
    }
  }));

test('closing dialog cancels queued viewport work, removes listeners and restores scroll', () =>
  harness((env) => {
    const release = activateDialogViewport(env.dialog);
    env.viewport.dispatchEvent(new Event('resize'));
    assert.equal(env.frames.size, 1);
    release();
    release();
    assert.equal(env.frames.size, 0);
    env.viewport.dispatchEvent(new Event('resize'));
    env.window.dispatchEvent(new Event('resize'));
    assert.equal(env.frames.size, 0);
    assert.equal(env.document.body.style.position, '');
    assert.equal(env.document.documentElement.style.overflow, '');
    assert.deepEqual(env.scrolls, [[0, 325]]);
  }));

test('nested dialog cleanup keeps background locked until the last dialog closes', () =>
  harness((env) => {
    const first = activateDialogViewport(env.dialog);
    const second = activateDialogViewport(env.dialog);
    try {
      first();
      assert.equal(env.document.body.style.position, 'fixed');
      assert.deepEqual(env.scrolls, []);
    } finally {
      first();
      second();
    }
    assert.equal(env.document.body.style.position, '');
    assert.deepEqual(env.scrolls, [[0, 325]]);
  }));
