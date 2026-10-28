import { useEffect } from 'react';
import { OUTCOME_MS, idle, nextFeedback, type Feedback } from '../lib/action-feedback';

/**
 * One document-level layer that gives every control consistent feedback without
 * per-screen wiring:
 * - press: a "beat" ring expands from the control (Ritm's signature pulse);
 * - async buttons: loading → success / error, derived from the existing
 *   `disabled={busy}` pattern (see lib/action-feedback.ts);
 * - toggles and checkboxes: a beat burst when they turn on;
 * - validation: invalid fields and freshly reported errors shake once.
 * Everything collapses to instant state changes under reduced motion.
 */
const PRESSABLE =
  'button, [role="button"], [role="tab"], [role="switch"], [role="checkbox"], summary, a.button, input[type="checkbox"], input[type="radio"]';
const TOGGLE =
  '[role="switch"], [role="checkbox"], input[type="checkbox"], input[type="radio"], [aria-pressed], .task-checkbox';
const ERROR_SIGNAL = '[role="alert"], .toast-error, .error-note, [aria-invalid="true"]';
const BEAT_EASE = 'cubic-bezier(.22,1,.36,1)';

const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function beat(element: Element, strong = false) {
  if (reduced() || !(element instanceof HTMLElement || element instanceof SVGElement)) return;
  // Keyframes need a resolved colour; --beat-color lets a control override the accent.
  const style = getComputedStyle(element);
  const color =
    style.getPropertyValue('--beat-color').trim() || style.getPropertyValue('--accent').trim();
  element.animate(
    [
      { outline: `2px solid ${color}`, outlineOffset: '0px', opacity: 1 },
      { outline: `2px solid transparent`, outlineOffset: strong ? '9px' : '6px' },
    ],
    { duration: strong ? 620 : 460, easing: BEAT_EASE, composite: 'replace' },
  );
}

function shake(element: Element) {
  if (!(element instanceof HTMLElement)) return;
  if (reduced()) {
    element.animate([{ opacity: 0.55 }, { opacity: 1 }], { duration: 180 });
    return;
  }
  element.animate(
    [
      { translate: '0 0' },
      { translate: '-5px 0' },
      { translate: '4px 0' },
      { translate: '-2px 0' },
      { translate: '1px 0' },
      { translate: '0 0' },
    ],
    { duration: 340, easing: 'ease-out' },
  );
}

function isOn(element: Element) {
  if (element instanceof HTMLInputElement) return element.checked;
  if (
    element.getAttribute('aria-checked') === 'true' ||
    element.getAttribute('aria-pressed') === 'true'
  )
    return true;
  return Boolean(element.closest('.is-complete'));
}

export function InteractionLayer() {
  useEffect(() => {
    const feedback = new Map<HTMLElement, Feedback>();
    const timers = new Map<HTMLElement, number>();
    const forcedPosition = new WeakSet<HTMLElement>();
    let lastErrorAt = -Infinity;

    const paint = (button: HTMLElement, value: Feedback) => {
      const visible =
        value.state === 'loading' || value.state === 'success' || value.state === 'error';
      if (visible) {
        if (getComputedStyle(button).position === 'static') {
          button.style.position = 'relative';
          forcedPosition.add(button);
        }
        button.dataset.feedback = value.state;
        if (value.state === 'loading') button.setAttribute('aria-busy', 'true');
        else button.removeAttribute('aria-busy');
        if (value.state === 'error') shake(button);
        if (value.state === 'success') beat(button, true);
        return;
      }
      delete button.dataset.feedback;
      button.removeAttribute('aria-busy');
      if (forcedPosition.has(button)) {
        button.style.removeProperty('position');
        forcedPosition.delete(button);
      }
    };

    const dispatch = (button: HTMLElement, event: Parameters<typeof nextFeedback>[1]) => {
      const before = feedback.get(button) ?? idle;
      const after = nextFeedback(before, event);
      if (after === before) return;
      if (after.state === 'idle') feedback.delete(button);
      else feedback.set(button, after);
      paint(button, after);
      window.clearTimeout(timers.get(button));
      if (after.state === 'armed' || after.state === 'success' || after.state === 'error') {
        const wait = after.state === 'armed' ? 700 : OUTCOME_MS;
        timers.set(
          button,
          window.setTimeout(
            () => dispatch(button, { type: 'settle', at: performance.now() }),
            wait,
          ),
        );
      }
    };

    const onPointerDown = (event: PointerEvent) => {
      if (event.button !== 0) return;
      const target = (event.target as Element).closest<HTMLElement>(PRESSABLE);
      if (!target || (target as HTMLButtonElement).disabled) return;
      beat(target);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.key !== 'Enter' && event.key !== ' ') || event.repeat) return;
      const target = (event.target as Element).closest<HTMLElement>(PRESSABLE);
      if (target && !(target as HTMLButtonElement).disabled) beat(target);
    };
    const onClick = (event: MouseEvent) => {
      const target = event.target as Element;
      const button = target.closest<HTMLButtonElement>('button');
      if (button && !button.disabled) dispatch(button, { type: 'press', at: performance.now() });
      const toggle = target.closest(TOGGLE);
      if (toggle)
        requestAnimationFrame(() =>
          requestAnimationFrame(() => {
            if (toggle.isConnected && isOn(toggle)) {
              const visual = toggle.matches('input')
                ? toggle
                : toggle.querySelector('.task-checkbox') || toggle;
              beat(visual, true);
            }
          }),
        );
    };
    const onInvalid = (event: Event) => shake(event.target as Element);

    // Controls disabled in the same commit as a loading button (`disabled={busy}` on the
    // input next to `disabled={busy || !title}` on the button). When any of them comes
    // back, the request is over even if the button itself stays disabled.
    const companions = new Map<HTMLElement, Set<Element>>();
    const finish = (button: HTMLElement, now: number) => {
      companions.delete(button);
      dispatch(button, {
        type: 'enabled',
        at: now,
        errorSince: lastErrorAt >= (feedback.get(button)?.since ?? Infinity),
      });
    };
    const isControl = (el: Element): el is HTMLButtonElement | HTMLInputElement =>
      el instanceof HTMLButtonElement ||
      el instanceof HTMLInputElement ||
      el instanceof HTMLTextAreaElement ||
      el instanceof HTMLSelectElement;

    const observer = new MutationObserver((records) => {
      const now = performance.now();
      const disabledNow: Element[] = [];
      for (const record of records) {
        const target = record.target as HTMLElement;
        if (record.type === 'attributes') {
          if (record.attributeName === 'disabled' && isControl(target)) {
            if (target.disabled) {
              disabledNow.push(target);
              if (target instanceof HTMLButtonElement)
                dispatch(target, { type: 'disabled', at: now });
            } else {
              if (target instanceof HTMLButtonElement && feedback.get(target)?.state === 'loading')
                finish(target, now);
              for (const [button, set] of companions)
                if (set.has(target) && feedback.get(button)?.state === 'loading')
                  finish(button, now);
            }
          } else if (
            record.attributeName === 'aria-invalid' &&
            target.getAttribute('aria-invalid') === 'true'
          ) {
            lastErrorAt = now;
            shake(target);
          }
          continue;
        }
        for (const node of record.addedNodes) {
          if (!(node instanceof Element)) continue;
          if (node.matches(ERROR_SIGNAL) || node.querySelector(ERROR_SIGNAL)) lastErrorAt = now;
          // A result toast also closes any request whose button stays disabled.
          const toast = node.matches('.toast') ? node : node.querySelector('.toast');
          if (toast)
            for (const [button, state] of feedback)
              if (state.state === 'loading') finish(button, now);
        }
        for (const node of record.removedNodes) {
          if (node instanceof HTMLElement) {
            for (const button of feedback.keys())
              if (!button.isConnected) {
                feedback.delete(button);
                companions.delete(button);
                window.clearTimeout(timers.get(button));
              }
          }
        }
      }
      for (const [button, state] of feedback) {
        if (state.state !== 'loading' || state.since !== now || companions.has(button)) continue;
        const scope = button.closest('form, dialog, .panel') ?? button.parentElement;
        companions.set(
          button,
          new Set(disabledNow.filter((el) => el !== button && scope?.contains(el))),
        );
      }
    });
    // Safety net: a request that never reports back must not leave a spinner behind.
    const watchdog = window.setInterval(() => {
      const now = performance.now();
      for (const [button, state] of feedback)
        if (state.state === 'loading' && now - state.since > 15000) {
          companions.delete(button);
          feedback.delete(button);
          paint(button, idle);
        }
    }, 2000);
    observer.observe(document.body, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ['disabled', 'aria-invalid'],
    });
    document.addEventListener('pointerdown', onPointerDown, true);
    document.addEventListener('keydown', onKeyDown, true);
    document.addEventListener('click', onClick, true);
    document.addEventListener('invalid', onInvalid, true);
    return () => {
      observer.disconnect();
      window.clearInterval(watchdog);
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('keydown', onKeyDown, true);
      document.removeEventListener('click', onClick, true);
      document.removeEventListener('invalid', onInvalid, true);
      timers.forEach((timer) => window.clearTimeout(timer));
      feedback.forEach((_, button) => paint(button, idle));
    };
  }, []);
  return null;
}
