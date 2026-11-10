import type { CSSProperties, ReactNode } from 'react';
import { useI18n } from '../../lib/i18n';
import { MUSCLE_TITLES, type MuscleKey } from './model';

const MUSCLE_COLOR: Record<MuscleKey, string> = {
  chest: '--wk-c0',
  triceps: '--wk-c1',
  shoulders: '--wk-c2',
  back: '--wk-c3',
  biceps: '--wk-c4',
  legs: '--wk-c5',
  abs: '--wk-c3',
};
export const muscleColor = (muscle: MuscleKey | null) =>
  `var(${muscle ? MUSCLE_COLOR[muscle] : '--wk-c0'})`;
export const gradientOf = (index: number) => `var(--wk-g${((index % 6) + 6) % 6})`;
export const letterOf = (name: string) => name.trim().charAt(0).toUpperCase() || '•';

export function MuscleChip({ muscle }: { muscle: MuscleKey | null }) {
  const { t } = useI18n();
  if (!muscle) return null;
  return (
    <span className="wk-mc" style={{ '--mc': muscleColor(muscle) } as CSSProperties}>
      {t(MUSCLE_TITLES[muscle])}
    </span>
  );
}

/** A progress ring; `fraction` is 0..1, `children` sit in the middle. */
export function Ring({
  fraction,
  children,
  className = '',
}: {
  fraction: number;
  children?: ReactNode;
  className?: string;
}) {
  const value = Math.max(0, Math.min(1, fraction));
  return (
    <div className={`wk-ring ${className}`}>
      <svg viewBox="0 0 100 100" aria-hidden="true">
        <circle className="tr" cx="50" cy="50" r="42" />
        <circle
          className="pg"
          cx="50"
          cy="50"
          r="42"
          pathLength={100}
          style={{ strokeDasharray: `${value * 100} 100` }}
        />
      </svg>
      {children ? <div className="mid">{children}</div> : null}
    </div>
  );
}

/** − value + : the stepper of one plan value (sets, reps, rest). */
export function PlanStepper({
  label,
  value,
  canDecrease,
  canIncrease,
  onStep,
}: {
  label: string;
  value: ReactNode;
  canDecrease: boolean;
  canIncrease: boolean;
  onStep: (direction: 1 | -1) => void;
}) {
  const { t } = useI18n();
  return (
    <div className="wk-sp">
      <small>{label}</small>
      <div>
        <button
          type="button"
          disabled={!canDecrease}
          aria-label={t('{label} меньше', { label })}
          onClick={() => onStep(-1)}
        >
          −
        </button>
        <b>{value}</b>
        <button
          type="button"
          disabled={!canIncrease}
          aria-label={t('{label} больше', { label })}
          onClick={() => onStep(1)}
        >
          +
        </button>
      </div>
    </div>
  );
}

export function SectionHeading({ title, action }: { title: string; action?: ReactNode }) {
  return (
    <div className="wk-sh">
      <h2>{title}</h2>
      {action}
    </div>
  );
}
