import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type RefObject,
} from 'react';
import { easeOut } from '../../lib/motion-math';

/**
 * Motion of the habits screen: numbers gain momentum (600 ms from 35 %), rings and bars draw,
 * cells fade in column by column. Nothing re-runs for an unchanged value, and with reduced
 * motion every value is final immediately.
 */
export const HABIT_EASE = 'cubic-bezier(.2,.8,.2,1)';
const COUNT_FIRST_MS = 600;
const COUNT_CHANGE_MS = 450;
const COUNT_START_SHARE = 0.35;
const RING_FIRST_MS = 700;
const BAR_MS = 500;
const BAR_STAGGER_MS = 40;

const reducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export function useCountUp(value: number): number {
  const [shown, setShown] = useState(() => (reducedMotion() ? value : value * COUNT_START_SHARE));
  const presented = useRef(shown);
  const introduced = useRef(false);
  useEffect(() => {
    const first = !introduced.current;
    introduced.current = true;
    if (reducedMotion() || document.hidden || presented.current === value) {
      presented.current = value;
      setShown(value);
      return;
    }
    const from = first ? value * COUNT_START_SHARE : presented.current;
    const time = first ? COUNT_FIRST_MS : COUNT_CHANGE_MS;
    const begun = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const progress = Math.min(1, (now - begun) / time);
      presented.current = progress === 1 ? value : from + (value - from) * easeOut(progress);
      setShown(presented.current);
      if (progress < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [value]);
  return shown;
}

export function CountUp({
  value,
  format = (amount) => String(Math.round(amount)),
}: {
  value: number;
  format?: (amount: number) => string;
}) {
  const shown = useCountUp(value);
  return (
    <>
      <span className="hb-num" aria-hidden="true">
        {format(shown)}
      </span>
      <span className="hb-sr">{format(value)}</span>
    </>
  );
}

/** Runs once when an element first appears; an interrupted run starts again on reconnect. */
function useFirstAppear(ref: RefObject<Element | null>, play: (element: Element) => Animation[]) {
  const done = useRef(false);
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element || done.current) return;
    if (reducedMotion() || document.hidden) {
      done.current = true;
      return;
    }
    const animations = play(element);
    let pending = animations.length;
    if (!pending) done.current = true;
    for (const animation of animations)
      animation.onfinish = () => {
        pending--;
        animation.cancel();
        if (pending === 0) done.current = true;
      };
    return () => animations.forEach((animation) => animation.cancel());
    // The animation is described by the element alone.
  }, []);
}

/** Animates between the value on screen and the next one; the first run starts from `first`. */
function usePresented<T extends Element>(
  ref: RefObject<T | null>,
  value: number,
  options: {
    first: (to: number) => Keyframe[];
    change: (from: number, to: number) => Keyframe[];
    firstMs: number;
    delay?: number;
  },
) {
  const presented = useRef<number | null>(null);
  const options_ = useRef(options);
  options_.current = options;
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const from = presented.current;
    if (reducedMotion() || document.hidden || from === value) {
      presented.current = value;
      return;
    }
    const { first, change, firstMs, delay = 0 } = options_.current;
    const animation = element.animate(from === null ? first(value) : change(from, value), {
      duration: from === null ? firstMs : COUNT_CHANGE_MS,
      delay: from === null ? delay : 0,
      easing: HABIT_EASE,
      fill: 'backwards',
    });
    presented.current = value;
    return () => {
      // An interrupted run resumes from the start value, a finished one is simply done.
      if (animation.playState !== 'finished') presented.current = from;
      animation.cancel();
    };
  }, [ref, value]);
}

/** A streak ring: the value counts up while the arc sweeps from zero. */
export function HabitRing({
  count,
  fraction,
  size,
  label,
}: {
  count: number;
  fraction: number;
  size: number;
  label: string;
}) {
  const stroke = Math.max(4, Math.round(size * 0.1));
  const center = size / 2;
  const radius = center - stroke / 2 - 1;
  const percent = Math.round(Math.max(0, Math.min(1, fraction)) * 100);
  const arc = useRef<SVGCircleElement>(null);
  usePresented(arc, percent, {
    first: (to) => [
      { strokeDasharray: '0.01 100', opacity: 0 },
      { opacity: 1, offset: 0.08 },
      { strokeDasharray: `${to} 100`, opacity: 1 },
    ],
    change: (from, to) => [{ strokeDasharray: `${from} 100` }, { strokeDasharray: `${to} 100` }],
    firstMs: RING_FIRST_MS,
  });
  return (
    <div className="hb-ring" style={{ '--s': `${size}px` } as CSSProperties}>
      <svg viewBox={`0 0 ${size} ${size}`} width={size} height={size} aria-hidden="true">
        <circle
          className="hb-ring-track"
          cx={center}
          cy={center}
          r={radius}
          strokeWidth={stroke}
          fill="none"
        />
        {percent > 0 && (
          <circle
            ref={arc}
            className="hb-ring-fill"
            cx={center}
            cy={center}
            r={radius}
            strokeWidth={stroke}
            pathLength={100}
            strokeDasharray={`${percent} 100`}
            fill="none"
            transform={`rotate(-90 ${center} ${center})`}
          />
        )}
      </svg>
      <div className="hb-ring-value">
        <b>
          <CountUp value={count} />
        </b>
        <span>{label}</span>
      </div>
    </div>
  );
}

/** A horizontal progress bar that grows from zero, `index` staggers neighbouring bars. */
export function HabitBar({ fraction, index = 0 }: { fraction: number; index?: number }) {
  const fill = useRef<HTMLElement>(null);
  const value = Math.round(Math.max(0, Math.min(1, fraction)) * 1000) / 1000;
  usePresented(fill, value, {
    first: (to) => [{ transform: 'scaleX(0)' }, { transform: `scaleX(${to})` }],
    change: (from, to) => [{ transform: `scaleX(${from})` }, { transform: `scaleX(${to})` }],
    firstMs: BAR_MS,
    delay: Math.min(index, 12) * BAR_STAGGER_MS,
  });
  return (
    <span className="hb-pbar" role="presentation">
      <i ref={fill} style={{ transform: `scaleX(${value})` }} />
    </span>
  );
}

/** A vertical sparkline bar; the height comes from the scale. */
export function HabitSparkBar({
  fraction,
  index,
  today,
}: {
  fraction: number;
  index: number;
  today: boolean;
}) {
  const bar = useRef<HTMLElement>(null);
  const value = Math.round(Math.max(0, Math.min(1, fraction)) * 1000) / 1000;
  usePresented(bar, value, {
    first: (to) => [{ transform: 'scaleY(0)' }, { transform: `scaleY(${to})` }],
    change: (from, to) => [{ transform: `scaleY(${from})` }, { transform: `scaleY(${to})` }],
    firstMs: BAR_MS,
    delay: Math.min(index, 12) * BAR_STAGGER_MS,
  });
  return (
    <i ref={bar} className={today ? 'is-today' : ''} style={{ transform: `scaleY(${value})` }} />
  );
}

/** Heatmap cells fade in column by column the first time they appear. */
export function useCellsFade(ref: RefObject<HTMLElement | null>) {
  useFirstAppear(ref, (element) =>
    [...element.children].map((cell, index) =>
      cell.animate(
        { opacity: [0, 1] },
        { duration: 260, delay: Math.floor(index / 7) * 9, easing: HABIT_EASE, fill: 'backwards' },
      ),
    ),
  );
}

/** The line draws over 780 ms, the area fades in after 40 % and the end point pops in. */
export function useLineDraw(ref: RefObject<SVGSVGElement | null>) {
  useFirstAppear(ref, (svg) => {
    const line = svg.querySelector('.hb-line-stroke');
    const area = svg.querySelector('.hb-line-area');
    const point = svg.querySelector('.hb-line-point');
    const result: Animation[] = [];
    if (line)
      result.push(
        line.animate(
          [
            { strokeDasharray: '1 1', strokeDashoffset: 1 },
            { strokeDasharray: '1 1', strokeDashoffset: 0 },
          ],
          { duration: 780, easing: HABIT_EASE, fill: 'backwards' },
        ),
      );
    if (area)
      result.push(
        area.animate(
          { opacity: [0, 1] },
          { duration: 300, delay: 312, easing: HABIT_EASE, fill: 'backwards' },
        ),
      );
    if (point)
      result.push(
        point.animate(
          [
            { transform: 'scale(.6)', opacity: 0 },
            { transform: 'scale(1)', opacity: 1 },
          ],
          { duration: 160, delay: 780, easing: HABIT_EASE, fill: 'backwards' },
        ),
      );
    return result;
  });
}
