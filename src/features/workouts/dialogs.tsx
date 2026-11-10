import { useCallback, useState, type ReactNode } from 'react';
import {
  Activity as ActivityIcon,
  Ban,
  BookOpen,
  Check,
  Droplet,
  Moon,
  Sparkles,
  Target,
  Trash2,
} from 'lucide-react';
import type { Habit, HabitIcon } from '../../../shared/types';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { dateKey, zonedNoon } from './dates';
import { weeklyGoal } from './stats';
import { plural } from './format';
import { formatWeight, parseReps, parseWeight, stepReps, stepWeight } from './numbers';
import { allExercises, type Best, type Exercise, type RecordCard } from './model';
import type { WorkoutSettings } from './model';

const HABIT_ICONS = {
  sparkles: Sparkles,
  book: BookOpen,
  activity: ActivityIcon,
  droplet: Droplet,
  moon: Moon,
  target: Target,
} as const;
export const habitIcon = (icon?: HabitIcon) => HABIT_ICONS[icon ?? 'sparkles'] ?? Sparkles;

// --- «Ask»: a question with its own buttons -----------------------------------------------------
export interface AskOptions<T extends string> {
  title: string;
  text?: string;
  buttons: Array<{ label: string; value: T | null; primary?: boolean; danger?: boolean }>;
}
interface Pending {
  options: AskOptions<string>;
  resolve: (value: string | null) => void;
}
/** `ask()` resolves to the chosen button's value, or null when the dialog is dismissed. */
export function useAsk() {
  const [pending, setPending] = useState<Pending | null>(null);
  const ask = useCallback(
    <T extends string>(options: AskOptions<T>) =>
      new Promise<T | null>((resolve) =>
        setPending({ options, resolve: resolve as (value: string | null) => void }),
      ),
    [],
  );
  const finish = (value: string | null) => {
    pending?.resolve(value);
    setPending(null);
  };
  const node: ReactNode = pending ? (
    <Dialog title={pending.options.title} className="wkm" onClose={() => finish(null)}>
      {pending.options.text ? <p className="wkm-note">{pending.options.text}</p> : null}
      <div className="wkm-btns">
        {pending.options.buttons.map((button) => (
          <button
            key={button.label}
            type="button"
            className={`btn wide${button.primary ? ' primary' : ''}${button.danger ? ' danger' : ''}`}
            onClick={() => finish(button.value)}
          >
            {button.label}
          </button>
        ))}
      </div>
    </Dialog>
  ) : null;
  return { ask, node };
}

// --- «Настройки тренировок»: the habit a finished workout ticks ---------------------------------
export function SettingsDialog({
  habits,
  settings,
  onLink,
  onClose,
}: {
  habits: Habit[];
  settings: WorkoutSettings;
  onLink: (habitID: string | null) => void;
  onClose: () => void;
}) {
  const { t, language } = useI18n();
  const active = habits.filter((habit) => !habit.archived);
  const linked = active.some((habit) => habit.id === settings.linkedHabitID)
    ? settings.linkedHabitID
    : null;
  const option = (id: string | null, Icon: typeof Ban, title: string, note: string) => (
    <button
      key={id ?? 'none'}
      type="button"
      className={`wk-opt${linked === id ? ' on' : ''}`}
      aria-pressed={linked === id}
      onClick={() => onLink(id)}
    >
      <span className="st">
        <Icon className="wk-i" aria-hidden="true" />
      </span>
      <span className="tx">
        <b>{title}</b>
        <small>{note}</small>
      </span>
      {linked === id ? <Check className="wk-i ck" aria-hidden="true" /> : null}
    </button>
  );
  return (
    <Dialog title={t('Настройки тренировок')} className="wkm" onClose={onClose}>
      <div className="wk-lb tight">{t('Связь с привычкой')}</div>
      {active.map((habit) => {
        const days = weeklyGoal(habit);
        const note =
          language === 'en'
            ? `${days} ${days === 1 ? 'day' : 'days'} a week`
            : `${days} ${plural(days, 'день', 'дня', 'дней')} в неделю`;
        return option(habit.id, habitIcon(habit.icon), habit.title, note);
      })}
      {option(null, Ban, t('Без привычки'), t('Тренировки не отмечают привычки'))}
      <p className="wk-fine">
        {t(
          'Завершённая тренировка один раз в день отмечает выбранную привычку. Кольцо недели показывает её дни.',
        )}
      </p>
      <button
        type="button"
        className="btn primary wide"
        style={{ marginTop: 14 }}
        onClick={onClose}
      >
        {t('Готово')}
      </button>
    </Dialog>
  );
}

// --- a record: exercise, weight, reps, date -----------------------------------------------------
export function RecordDialog({
  card,
  custom,
  today,
  timeZone,
  onSave,
  onDelete,
  onClose,
}: {
  card: RecordCard | null;
  custom: Exercise[];
  today: string;
  timeZone: string;
  onSave: (bests: Best[]) => void;
  onDelete: (card: RecordCard) => void;
  onClose: () => void;
}) {
  const { t, language } = useI18n();
  const exercises = allExercises(custom, language);
  const [exerciseID, setExerciseID] = useState(card?.exerciseID ?? 'builtin.bench');
  const [weight, setWeight] = useState(card ? formatWeight(card.weight) : '60');
  const [reps, setReps] = useState(card ? String(card.reps) : '5');
  const [date, setDate] = useState(card ? dateKey(card.date, timeZone) : today);
  const kg = parseWeight(weight);
  const count = parseReps(reps);
  const valid = kg !== null && kg > 0 && count !== null && date !== '' && date <= today;
  const save = () => {
    if (!valid) return;
    const name = exercises.find((item) => item.id === exerciseID)?.name ?? card?.name ?? '';
    const unchangedDay = card && date === dateKey(card.date, timeZone);
    const moved: Best[] =
      card && card.exerciseID !== exerciseID
        ? [
            {
              exerciseID: card.exerciseID,
              name: card.name,
              weight: 0,
              reps: 1,
              date: card.date,
              deleted: true,
            },
          ]
        : [];
    onSave([
      ...moved,
      {
        exerciseID,
        name,
        weight: kg,
        reps: count,
        date: unchangedDay && card ? card.date : zonedNoon(date, timeZone),
        deleted: false,
      },
    ]);
  };
  return (
    <Dialog title={card ? t('Рекорд') : t('Новый рекорд')} className="wkm" onClose={onClose}>
      <div className="wk-lb tight">{t('Упражнение')}</div>
      <select
        className="wk-inp"
        value={exerciseID}
        onChange={(event) => setExerciseID(event.target.value)}
      >
        {exercises.map((item) => (
          <option key={item.id} value={item.id}>
            {item.name}
          </option>
        ))}
      </select>
      <div className="wk-lb">{t('Вес, кг')}</div>
      <div className="wk-nstep">
        <button type="button" onClick={() => setWeight(stepWeight(weight, -2.5))}>
          −2,5
        </button>
        <input
          className="wk-inp c"
          inputMode="decimal"
          value={weight}
          aria-label={t('Вес, кг')}
          onChange={(event) => setWeight(event.target.value)}
        />
        <button type="button" onClick={() => setWeight(stepWeight(weight, 2.5))}>
          +2,5
        </button>
      </div>
      <div className="wk-lb">{t('Повторы')}</div>
      <div className="wk-nstep">
        <button type="button" onClick={() => setReps(stepReps(reps, -1))}>
          −1
        </button>
        <input
          className="wk-inp c"
          inputMode="numeric"
          value={reps}
          aria-label={t('Повторы')}
          onChange={(event) => setReps(event.target.value)}
        />
        <button type="button" onClick={() => setReps(stepReps(reps, 1))}>
          +1
        </button>
      </div>
      <div className="wk-lb">{t('Дата')}</div>
      <input
        className="wk-inp"
        type="date"
        max={today}
        value={date}
        onChange={(event) => setDate(event.target.value)}
      />
      <button
        type="button"
        className="btn primary wide"
        style={{ marginTop: 16 }}
        disabled={!valid}
        onClick={save}
      >
        {t('Сохранить')}
      </button>
      {card ? (
        <button
          type="button"
          className="btn wide danger"
          style={{ marginTop: 8 }}
          onClick={() => onDelete(card)}
        >
          <Trash2 className="wk-i wk-tiny" aria-hidden="true" />
          {t('Удалить рекорд')}
        </button>
      ) : null}
    </Dialog>
  );
}
