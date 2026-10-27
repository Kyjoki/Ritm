import {
  Children,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from 'react';
import { interpolateValues } from '../lib/motion-math';

export const motion = {
  chart: 920,
  update: 520,
  enter: 440,
  exit: 180,
  stagger: 55,
  ease: 'cubic-bezier(.22,1,.36,1)',
};
const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const compact = () => window.matchMedia('(max-width: 760px)').matches;
const duration = (ms: number) => (compact() ? Math.round(ms * 0.75) : ms);

/** Activity disconnects effects while hidden. Re-entry resumes from the presented value. */
export function useMotionValues(values: number[], enabled = true, fromZero = true, delay = 0) {
  const signature = JSON.stringify(values);
  const presented = useRef(fromZero && !reduced() ? values.map(() => 0) : values);
  const started = useRef(false);
  const [shown, setShown] = useState(presented.current);
  useEffect(() => {
    const target: number[] = JSON.parse(signature);
    if (!enabled) return;
    let frame = 0;
    const first = !started.current;
    started.current = true;
    const start = [...presented.current];
    const begun = performance.now() + (first ? duration(delay) : 0);
    const time = duration(first ? motion.chart : motion.update);
    const finish = () => {
      cancelAnimationFrame(frame);
      presented.current = target;
      setShown(target);
    };
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (
      preference.matches ||
      (start.length === target.length && start.every((v, i) => v === target[i]))
    ) {
      finish();
      return;
    }
    const tick = (now: number) => {
      if (document.hidden) {
        finish();
        return;
      }
      const progress = Math.max(0, Math.min(1, (now - begun) / time));
      presented.current = interpolateValues(start, target, progress);
      setShown(presented.current);
      if (progress < 1) frame = requestAnimationFrame(tick);
    };
    const onPreference = () => {
      if (preference.matches) finish();
    };
    preference.addEventListener('change', onPreference);
    frame = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(frame);
      preference.removeEventListener('change', onPreference);
    };
  }, [signature, enabled, delay]);
  return shown;
}
export function useMotionNumber(value: number, enabled = true) {
  return useMotionValues([value], enabled)[0] ?? value;
}
export function MotionNumber({
  value,
  format = (v) => String(Math.round(v)),
  className = '',
  step = 1,
}: {
  value: number;
  format?: (v: number) => string;
  className?: string;
  step?: number;
}) {
  const shown = useMotionNumber(value);
  const previousTarget = useRef(value);
  const range = useRef([0, value]);
  if (previousTarget.current !== value) {
    range.current = [shown, value];
    previousTarget.current = value;
  }
  const rounded = Math.min(
    Math.max(...range.current),
    Math.max(Math.min(...range.current), Math.round(shown / step) * step),
  );
  return (
    <span className={'motion-number ' + className} aria-label={format(value)}>
      <span aria-hidden="true">{format(shown === value ? value : rounded)}</span>
    </span>
  );
}
export function MotionBar({
  value,
  index = 0,
  className,
  title,
}: {
  value: number;
  index?: number;
  className: string;
  title?: string;
}) {
  const shown = useMotionValues([value], true, true, Math.min(index, 5) * motion.stagger)[0];
  return (
    <span
      className={className + ' motion-bar'}
      style={{ height: `${shown ?? value}%` }}
      title={title}
    />
  );
}
export function MotionRing({ value, children }: { value: number; children: ReactNode }) {
  const shown = useMotionNumber(value);
  return (
    <div className="progress-ring" style={{ '--progress': `${shown}deg` } as CSSProperties}>
      {children}
    </div>
  );
}
export function MotionArc({ value }: { value: number }) {
  const shown = useMotionNumber(value);
  return (
    <path
      d="M 12 92 A 78 78 0 0 1 168 92"
      pathLength="100"
      className="habits-gauge-fill"
      strokeDasharray={`${shown} 100`}
    />
  );
}

export function MotionLine({ values }: { values: number[] }) {
  const shown = useMotionValues(values, true, false);
  const line = useRef<SVGPolylineElement>(null);
  const area = useRef<SVGPolygonElement>(null);
  const introduced = useRef(false);
  useEffect(() => {
    if (introduced.current || reduced()) return;
    introduced.current = true;
    const draw = line.current?.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], {
      duration: duration(motion.chart),
      easing: motion.ease,
    });
    const fill = area.current?.animate([{ opacity: 0 }, { opacity: 1 }], {
      duration: duration(400),
      delay: duration(480),
      fill: 'backwards',
      easing: motion.ease,
    });
    return () => {
      draw?.cancel();
      fill?.cancel();
    };
  }, []);
  const points = shown
    .map((amount, index) => `${(index * 300) / Math.max(1, shown.length - 1)},${66 - amount * 49}`)
    .join(' ');
  return (
    <svg viewBox="0 0 300 76" preserveAspectRatio="none" className="motion-line">
      <line x1="0" y1="71" x2="300" y2="71" />
      <line x1="0" y1="45" x2="300" y2="45" />
      <line x1="0" y1="19" x2="300" y2="19" />
      <polygon ref={area} points={`0,72 ${points} 300,72`} />
      <polyline ref={line} pathLength="1" strokeDasharray="1" points={points} />
    </svg>
  );
}

/** Each scope lives INSIDE Activity: no keys or remounts to replay a transition. */
export function MotionPage({ name, children }: { name: string; children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const visited = useRef(false);
  const seen = useRef(new WeakSet<Element>());
  useLayoutEffect(() => {
    const root = ref.current;
    if (!root) return;
    const animations = new Set<Animation>();
    const first = !visited.current;
    visited.current = true;
    root.dataset.active = 'true';
    const stages = [
      '.page-heading, .cal-toolbar',
      '.overview-grid > .panel, .habits-analytics-top, .finance-hero, .finance-summary-tile',
      '.day-work-grid > .panel, .habits-analytics-graphs, .finance-chart-card, .assistant-history, .assistant-chat, .settings-card',
      '.dashboard-habits, .dashboard-bottom, .finance-records, .habits-list-heading',
    ];
    const reveal = (returning = false) => {
      stages.forEach((selector, stage) => {
        root.querySelectorAll<HTMLElement>(selector).forEach((element, index) => {
          if (seen.current.has(element) && !returning) return;
          seen.current.add(element);
          if (reduced()) return;
          const distance = compact() ? 5 : stage === 0 ? 8 : 12;
          const frames =
            returning || name === 'calendar'
              ? [{ opacity: 0.45 }, { opacity: 1 }]
              : [
                  { opacity: 0, transform: `translateY(${distance}px)` },
                  { opacity: 1, transform: 'translateY(0)' },
                ];
          const animation = element.animate(frames, {
            duration: duration(returning ? 200 : motion.enter),
            delay: returning
              ? stage * 25
              : Math.min(220, stage * motion.stagger + Math.min(index, compact() ? 1 : 3) * 40),
            easing: motion.ease,
            fill: 'backwards',
          });
          animations.add(animation);
          animation.onfinish = () => {
            animations.delete(animation);
            animation.cancel();
          };
        });
      });
    };
    reveal(!first);
    const observer = new MutationObserver((records) => {
      if (records.some((record) => [...record.addedNodes].some((node) => node instanceof Element)))
        reveal();
    });
    observer.observe(root, { childList: true, subtree: true });
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
    const cancel = () => {
      animations.forEach((a) => a.cancel());
      animations.clear();
    };
    preference.addEventListener('change', cancel);
    return () => {
      root.dataset.active = 'false';
      observer.disconnect();
      cancel();
      preference.removeEventListener('change', cancel);
    };
  }, [name]);
  return (
    <div ref={ref} className="motion-page" data-motion-page={name}>
      {children}
    </div>
  );
}

/** FLIP only for ordinary lists. Calendar geometry is deliberately outside this primitive. */
export function MotionList({
  children,
  className,
  as = 'div',
}: {
  children: ReactNode;
  className: string;
  as?: 'div' | 'ul';
}) {
  const ref = useRef<HTMLDivElement & HTMLUListElement>(null);
  const previous = useRef(
    new Map<
      string,
      { top: number; left: number; width: number; height: number; clone: HTMLElement }
    >(),
  );
  const animations = useRef(new Set<Animation>());
  const ghosts = useRef(new Set<HTMLElement>());
  useLayoutEffect(() => {
    const root = ref.current!;
    const bounds = root.getBoundingClientRect();
    const scale = bounds.width / root.offsetWidth || 1;
    const next = new Map<
      string,
      { top: number; left: number; width: number; height: number; clone: HTMLElement }
    >();
    const animate = (element: HTMLElement, frames: Keyframe[], done?: () => void) => {
      const animation = element.animate(frames, { duration: duration(330), easing: motion.ease });
      animations.current.add(animation);
      animation.onfinish = () => {
        animations.current.delete(animation);
        animation.cancel();
        done?.();
      };
    };
    [...root.children].forEach((node) => {
      const element = node as HTMLElement;
      const key = element.dataset.motionKey;
      if (!key) return;
      const rect = element.getBoundingClientRect();
      const snapshot = {
        top: (rect.top - bounds.top) / scale,
        left: (rect.left - bounds.left) / scale,
        width: rect.width / scale,
        height: rect.height / scale,
        clone: element.cloneNode(true) as HTMLElement,
      };
      next.set(key, snapshot);
      if (reduced()) return;
      const old = previous.current.get(key);
      if (old && Math.abs(old.top - snapshot.top) > 1)
        animate(element, [{ translate: `0 ${old.top - snapshot.top}px` }, { translate: '0 0' }]);
      else if (!old && previous.current.size)
        animate(element, [
          { opacity: 0, translate: `0 ${compact() ? 4 : 10}px` },
          { opacity: 1, translate: '0 0' },
        ]);
    });
    if (!reduced())
      previous.current.forEach((old, key) => {
        if (next.has(key)) return;
        const ghost = old.clone;
        ghost.removeAttribute('data-motion-key');
        ghost.querySelectorAll('[id]').forEach((el) => el.removeAttribute('id'));
        ghost.removeAttribute('id');
        ghost.inert = true;
        ghost.setAttribute('aria-hidden', 'true');
        Object.assign(ghost.style, {
          position: 'absolute',
          top: old.top + 'px',
          left: old.left + 'px',
          width: old.width + 'px',
          height: old.height + 'px',
          pointerEvents: 'none',
          margin: '0',
          zIndex: '1',
        });
        root.append(ghost);
        ghosts.current.add(ghost);
        animate(ghost, [{ opacity: 0.7 }, { opacity: 0, translate: '0 -6px' }], () => {
          ghost.remove();
          ghosts.current.delete(ghost);
        });
      });
    previous.current = next;
  });
  useLayoutEffect(
    () => () => {
      animations.current.forEach((a) => a.cancel());
      animations.current.clear();
      ghosts.current.forEach((el) => el.remove());
      ghosts.current.clear();
      previous.current.clear();
    },
    [],
  );
  const Tag = as;
  return (
    <Tag ref={ref} className={className + ' motion-list'}>
      {Children.toArray(children)}
    </Tag>
  );
}

/** Preserve a transient notification during its short exit, including keyboard dismissal. */
export function MotionPresence({ children }: { children: ReactNode }) {
  const [retained, setRetained] = useState(children);
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    if (children) {
      setRetained(children);
      return;
    }
    const root = ref.current?.firstElementChild as HTMLElement | null;
    if (!root || reduced()) {
      setRetained(null);
      return;
    }
    root.inert = true;
    const animation = root.animate([{ opacity: 1 }, { opacity: 0, translate: '0 5px' }], {
      duration: motion.exit,
      easing: motion.ease,
    });
    animation.onfinish = () => setRetained(null);
    return () => animation.cancel();
  }, [children]);
  useLayoutEffect(() => {
    if (children && ref.current?.firstElementChild instanceof HTMLElement) {
      ref.current.firstElementChild.inert = false;
    }
  }, [children, retained]);
  return (
    <div ref={ref} className="motion-presence">
      {children || retained}
    </div>
  );
}

export function MotionControls() {
  const anchor = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const shell = anchor.current?.closest<HTMLElement>('.app-shell');
    if (!shell) return;
    const selector =
      '.sidebar-nav, .mobile-nav, .cal-segment, .habits-segmented, .finance-views, .dashboard-task-days, .assistant-mode-switch';
    let frame = 0;
    const sync = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() =>
        document.querySelectorAll<HTMLElement>(selector).forEach((group) => {
          if (!group.getClientRects().length) return;
          const active = group.querySelector<HTMLElement>(
            ':scope > .is-active, :scope > [aria-pressed="true"], :scope > [aria-current="page"]',
          );
          if (!active) return;
          const box = group.getBoundingClientRect(),
            target = active.getBoundingClientRect();
          const scale = box.width / group.offsetWidth || 1;
          group.style.setProperty('--indicator-x', (target.left - box.left) / scale + 'px');
          group.style.setProperty('--indicator-y', (target.top - box.top) / scale + 'px');
          group.style.setProperty('--indicator-width', target.width / scale + 'px');
          group.style.setProperty('--indicator-height', target.height / scale + 'px');
          group.dataset.motionIndicator = 'true';
        }),
      );
    };
    sync();
    const observer = new MutationObserver((records) => {
      if (
        records.some(
          (r) => r.type === 'attributes' || [...r.addedNodes].some((n) => n instanceof Element),
        )
      )
        sync();
    });
    const visibility = () => {
      shell.dataset.documentHidden = String(document.hidden);
    };
    visibility();
    document.addEventListener('visibilitychange', visibility);
    observer.observe(shell, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ['aria-current', 'aria-pressed', 'class', 'data-page'],
    });
    const resize = new ResizeObserver(sync);
    resize.observe(shell);
    const disclosureAnimations = new Map<HTMLDetailsElement, Animation>();
    const disclose = (event: MouseEvent) => {
      const summary = (event.target as Element).closest('summary');
      if (!summary || reduced() || !(summary.parentElement instanceof HTMLDetailsElement)) return;
      const details = summary.parentElement;
      event.preventDefault();
      const wasClosing = details.dataset.closing === 'true';
      const opening = !details.open || wasClosing;
      const scale = details.getBoundingClientRect().width / details.offsetWidth || 1;
      const from = details.getBoundingClientRect().height / scale;
      disclosureAnimations.get(details)?.cancel();
      details.open = true;
      details.dataset.closing = String(!opening);
      const to = opening ? details.scrollHeight : summary.offsetHeight;
      details.style.overflow = 'hidden';
      const animation = details.animate([{ height: from + 'px' }, { height: to + 'px' }], {
        duration: duration(300),
        easing: motion.ease,
      });
      disclosureAnimations.set(details, animation);
      animation.onfinish = () => {
        details.open = opening;
        details.style.removeProperty('overflow');
        delete details.dataset.closing;
        animation.cancel();
        disclosureAnimations.delete(details);
      };
    };
    shell.addEventListener('click', disclose as EventListener);
    window.addEventListener('resize', sync);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      resize.disconnect();
      document.removeEventListener('visibilitychange', visibility);
      window.removeEventListener('resize', sync);
      shell.removeEventListener('click', disclose as EventListener);
      disclosureAnimations.forEach((a) => a.cancel());
    };
  }, []);
  return <span ref={anchor} hidden aria-hidden="true" />;
}
