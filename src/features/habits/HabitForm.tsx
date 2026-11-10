import { useState, type FormEvent } from 'react';
import { Archive, Check, LoaderCircle } from 'lucide-react';
import type { HabitIcon, HabitInput } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { weekdayShort } from './habit-format';
import { HabitIconView, Segmented, iconChoices, iconLabels } from './habit-parts';

const ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];
const WORK_DAYS = [1, 2, 3, 4, 5];
const WEEKEND = [0, 6];
const MAX_TARGET = 10_000;
const DEFAULT_COUNT_TARGET = 10;

export const defaultHabitDraft: HabitInput = {
  title: '',
  icon: 'sparkles',
  weekdays: ALL_DAYS,
  target: null,
  unit: '',
  archived: false,
};

type Kind = 'check' | 'count';

export function HabitForm({
  initial,
  busy,
  onSubmit,
  onCancel,
  onArchive,
}: {
  initial: HabitInput;
  busy: boolean;
  onSubmit: (input: HabitInput) => void;
  onCancel: () => void;
  /** Present when an existing, active habit is edited. */
  onArchive?: () => void;
}) {
  const { t, language } = useI18n();
  const [title, setTitle] = useState(initial.title);
  const [icon, setIcon] = useState<HabitIcon>(initial.icon ?? 'sparkles');
  const [days, setDays] = useState<number[]>(initial.weekdays ?? ALL_DAYS);
  const [kind, setKind] = useState<Kind>(initial.target ? 'count' : 'check');
  const [target, setTarget] = useState(String(initial.target ?? DEFAULT_COUNT_TARGET));
  const [unit, setUnit] = useState(initial.unit ?? '');
  const [attempted, setAttempted] = useState(false);
  const count = kind === 'count';
  const targetValue = Number(target);
  const targetValid =
    !count ||
    (target.trim() !== '' &&
      Number.isInteger(targetValue) &&
      targetValue >= 1 &&
      targetValue <= MAX_TARGET);
  const error = !title.trim()
    ? t('Введите название привычки.')
    : !days.length
      ? t('Выберите хотя бы один день.')
      : !targetValid
        ? t('Укажите цель целым числом от 1 до {max}.', { max: MAX_TARGET })
        : '';

  function submit(event: FormEvent) {
    event.preventDefault();
    setAttempted(true);
    if (error || busy) return;
    onSubmit({
      title: title.trim(),
      icon,
      weekdays: [...days].sort((a, b) => a - b),
      target: count ? targetValue : null,
      unit: count ? unit.trim() : '',
      archived: initial.archived ?? false,
    });
  }
  const toggleDay = (day: number) =>
    setDays((current) =>
      current.includes(day) ? current.filter((value) => value !== day) : [...current, day],
    );
  const quick = (values: number[], label: string) => (
    <button type="button" onClick={() => setDays(values)}>
      {label}
    </button>
  );

  return (
    <form className="hb-form" onSubmit={submit} noValidate>
      <label className="hb-field" htmlFor="habit-form-title">
        <span>{t('Название привычки')}</span>
        <input
          id="habit-form-title"
          className="hb-input"
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          maxLength={80}
          placeholder={t('Например, читать 20 минут')}
          autoComplete="off"
        />
      </label>
      <fieldset className="hb-field">
        <legend>{t('Иконка')}</legend>
        <div className="hb-icon-grid">
          {(Object.keys(iconChoices) as HabitIcon[]).map((choice) => (
            <button
              key={choice}
              type="button"
              aria-label={t('Иконка: {icon}', { icon: t(iconLabels[choice]) })}
              aria-pressed={icon === choice}
              onClick={() => setIcon(choice)}
            >
              <HabitIconView icon={choice} />
            </button>
          ))}
        </div>
      </fieldset>
      <fieldset className="hb-field">
        <legend>{t('Дни недели')}</legend>
        <div className="hb-weekday-grid">
          {ALL_DAYS.map((day) => {
            const selected = days.includes(day);
            return (
              <button
                key={day}
                type="button"
                aria-pressed={selected}
                aria-label={t('{day}: {state}', {
                  day: weekdayShort(day, language),
                  state: t(selected ? 'Запланировано' : 'Не запланировано'),
                })}
                onClick={() => toggleDay(day)}
              >
                {weekdayShort(day, language)}
              </button>
            );
          })}
        </div>
        <div className="hb-quick">
          {quick(ALL_DAYS, t('Каждый день'))}
          {quick(WORK_DAYS, t('Пн–Пт'))}
          {quick(WEEKEND, t('Выходные'))}
        </div>
      </fieldset>
      <fieldset className="hb-field">
        <legend>{t('Цель за день')}</legend>
        <Segmented
          full
          label={t('Цель за день')}
          value={kind}
          onChange={setKind}
          options={[
            ['check', t('Отметка')],
            ['count', t('Количество')],
          ]}
        />
        {count && (
          <div className="hb-field-row">
            <label className="hb-field" htmlFor="habit-form-target">
              <span>{t('Сколько')}</span>
              <input
                id="habit-form-target"
                className="hb-input"
                type="number"
                min={1}
                max={MAX_TARGET}
                step={1}
                inputMode="numeric"
                value={target}
                onChange={(event) => setTarget(event.target.value)}
              />
            </label>
            <label className="hb-field" htmlFor="habit-form-unit">
              <span>{t('Единица')}</span>
              <input
                id="habit-form-unit"
                className="hb-input"
                value={unit}
                onChange={(event) => setUnit(event.target.value)}
                maxLength={24}
                placeholder={t('Например, страниц')}
              />
            </label>
          </div>
        )}
      </fieldset>
      {attempted && error && (
        <p className="hb-form-error" role="alert">
          {error}
        </p>
      )}
      <div className="hb-form-actions">
        {onArchive && (
          <button type="button" className="hb-btn" disabled={busy} onClick={onArchive}>
            <Archive size={16} aria-hidden="true" />
            {t('В архив')}
          </button>
        )}
        <span className="hb-spacer" />
        <button type="button" className="hb-btn" onClick={onCancel}>
          {t('Отмена')}
        </button>
        <button type="submit" className="hb-btn is-primary" disabled={busy}>
          {busy ? <LoaderCircle className="spin" size={16} /> : <Check size={16} />}
          {t('Сохранить')}
        </button>
      </div>
    </form>
  );
}
