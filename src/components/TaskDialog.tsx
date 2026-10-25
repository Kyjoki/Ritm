import { useI18n } from '../lib/i18n';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { ChevronDown, LoaderCircle, Trash2 } from 'lucide-react';
import type { Task, TaskInput } from '../../shared/types';
import { Dialog } from './Dialog';
import { CalendarColorPicker } from './CalendarColorPicker';
import { CALENDAR_PALETTE } from '../../shared/calendar-colors';

interface Props {
  task?: Task;
  draft?: Partial<TaskInput>;
  onClose: () => void;
  onSave: (task: TaskInput, id?: string) => Promise<void>;
  onDelete: (task: Task) => Promise<void>;
}
export function TaskDialog({ task, draft, onClose, onSave, onDelete }: Props) {
  const { t } = useI18n();
  const [value, setValue] = useState<TaskInput>(() => {
    const source = task ?? draft;
    return {
      title: source?.title ?? '',
      description: source?.description ?? '',
      date: source?.date ?? null,
      time: source?.time ?? null,
      duration: source?.duration ?? 30,
      priority: source?.priority ?? 'normal',
      repeat: source?.repeat ?? 'none',
      kind: source?.kind ?? 'task',
      completed: source?.completed ?? false,
      colorId: source?.colorId ?? null,
      ...(source?.calendarEntry === false ? { calendarEntry: false } : {}),
    };
  });
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [advanced, setAdvanced] = useState(
      Boolean(task?.description || (task?.repeat !== 'none' && task)),
    );
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [showColors, setShowColors] = useState(false);
  const selectedColor = CALENDAR_PALETTE.find((color) => color.id === value.colorId)?.hex;
  const colorPreview =
    selectedColor ??
    (/^#[0-9a-f]{6}$/i.test(value.colorId ?? '') ? value.colorId! : 'var(--accent)');
  const keepButton = useRef<HTMLButtonElement>(null),
    deleteButton = useRef<HTMLButtonElement>(null),
    wasConfirming = useRef(false);
  useEffect(() => {
    if (confirmDelete && !busy) keepButton.current?.focus();
    else if (!confirmDelete && wasConfirming.current) deleteButton.current?.focus();
    wasConfirming.current = confirmDelete;
  }, [confirmDelete, busy]);
  const set = <K extends keyof TaskInput>(key: K, next: TaskInput[K]) =>
    setValue((old) => ({ ...old, [key]: next }));
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setError('');
    if (
      value.time &&
      Number(value.time.slice(0, 2)) * 60 + Number(value.time.slice(3)) + value.duration > 1440
    ) {
      setError(
        t(
          'Запись должна завершиться до полуночи. Уменьшите длительность или выберите другое время.',
        ),
      );
      return;
    }
    setBusy(true);
    try {
      const repeat = value.date ? value.repeat : 'none';
      await onSave(
        {
          ...value,
          title: value.title.trim(),
          description: value.description.trim(),
          time: value.date ? value.time : null,
          repeat,
          completed: repeat === 'none' ? value.completed : false,
        },
        task?.id,
      );
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : t('Задача не сохранилась. Попробуйте ещё раз.'));
    } finally {
      setBusy(false);
    }
  };
  const remove = async () => {
    if (!task) return;
    setBusy(true);
    setError('');
    try {
      await onDelete(task);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : t('Не удалось удалить задачу.'));
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog
      title={task ? t('Редактировать задачу') : t('Новая задача')}
      onClose={onClose}
      busy={busy}
      className="task-dialog"
    >
      <form onSubmit={submit}>
        <fieldset className="task-form" disabled={busy}>
          {task?.repeat !== 'none' && task ? (
            <p className="info-note">
              {t('Повторяющаяся задача: изменения применятся ко всей серии.')}
            </p>
          ) : null}
          <label className="field">
            {t('Название')}
            <input
              autoFocus
              required
              maxLength={160}
              placeholder={t('Что нужно сделать?')}
              value={value.title}
              onChange={(e) => set('title', e.target.value)}
            />
          </label>
          <div className="form-grid">
            <label className="field">
              {t('Дата')}
              <input
                type="date"
                value={value.date ?? ''}
                onChange={(e) => {
                  setValue((old) => ({
                    ...old,
                    date: e.target.value || null,
                    time: e.target.value ? old.time : null,
                    repeat: e.target.value ? old.repeat : 'none',
                  }));
                }}
              />
            </label>
            {value.calendarEntry !== false ? (
              <label className="field">
                {t('Время')}
                <input
                  type="time"
                  value={value.time ?? ''}
                  disabled={!value.date}
                  onChange={(e) => set('time', e.target.value || null)}
                />
              </label>
            ) : null}
          </div>
          <div className="form-grid">
            {value.calendarEntry !== false ? (
              <label className="field">
                {t('Длительность')}
                <select
                  value={value.duration}
                  onChange={(e) => set('duration', Number(e.target.value))}
                >
                  {[
                    15,
                    30,
                    45,
                    60,
                    90,
                    120,
                    180,
                    240,
                    480,
                    ...(![15, 30, 45, 60, 90, 120, 180, 240, 480].includes(value.duration)
                      ? [value.duration]
                      : []),
                  ]
                    .sort((a, b) => a - b)
                    .map((n) => (
                      <option key={n} value={n}>
                        {n < 60 ? t('{p0} минут', { p0: n }) : t('{p0} ч', { p0: n / 60 })}
                      </option>
                    ))}
                </select>
              </label>
            ) : null}
            <label className="field">
              {t('Приоритет')}
              <select
                value={value.priority}
                onChange={(e) => set('priority', e.target.value as TaskInput['priority'])}
              >
                <option value="low">{t('Низкий')}</option>
                <option value="normal">{t('Обычный')}</option>
                <option value="high">{t('Высокий')}</option>
              </select>
            </label>
          </div>
          <div className="task-color-section">
            <button
              className="disclosure"
              type="button"
              onClick={() => setShowColors((open) => !open)}
              aria-expanded={showColors}
              aria-controls="task-color-options"
            >
              <ChevronDown size={16} className={showColors ? 'rotated' : ''} />
              {t('Цвет записи')}
              <span
                className="task-color-preview"
                aria-hidden="true"
                style={{ background: colorPreview }}
              />
            </button>
            {showColors ? (
              <div id="task-color-options">
                <CalendarColorPicker value={value.colorId} onChange={(id) => set('colorId', id)} />
              </div>
            ) : null}
          </div>
          <button
            className="disclosure"
            type="button"
            onClick={() => setAdvanced(!advanced)}
            aria-expanded={advanced}
          >
            <ChevronDown size={16} className={advanced ? 'rotated' : ''} />
            {t('Дополнительные поля')}
          </button>
          {advanced ? (
            <div className="advanced-fields">
              <label className="field">
                {t('Описание')}
                <textarea
                  value={value.description}
                  rows={3}
                  maxLength={2000}
                  placeholder={t('Детали и важные шаги')}
                  onChange={(e) => set('description', e.target.value)}
                />
              </label>
              <div className="form-grid">
                <label className="field">
                  {t('Повторение')}
                  <select
                    value={value.repeat}
                    disabled={!value.date}
                    onChange={(e) => set('repeat', e.target.value as TaskInput['repeat'])}
                  >
                    <option value="none">{t('Не повторять')}</option>
                    <option value="daily">{t('Каждый день')}</option>
                    <option value="weekly">{t('Каждую неделю')}</option>
                    <option value="monthly">{t('Каждый месяц')}</option>
                  </select>
                </label>
                {value.calendarEntry !== false ? (
                  <label className="field">
                    {t('Тип')}
                    <select
                      value={value.kind}
                      onChange={(e) => set('kind', e.target.value as TaskInput['kind'])}
                    >
                      <option value="task">{t('Задача')}</option>
                      <option value="event">{t('Событие')}</option>
                    </select>
                  </label>
                ) : null}
              </div>
            </div>
          ) : null}
          {value.calendarEntry === false ? (
            <p className="field-hint">
              {t('Личная задача остаётся в списке дел и не занимает время в календаре.')}
            </p>
          ) : !value.date ? (
            <p className="field-hint">
              {t('Без даты — задача останется в списке, пока вы не запланируете её.')}
            </p>
          ) : value.time ? (
            <p className="field-hint">
              {t('Выберите длительность, чтобы запись завершилась до полуночи.')}
            </p>
          ) : null}
          {error ? (
            <p role="alert" className="error-note">
              {error}
            </p>
          ) : null}
          {confirmDelete ? (
            <div
              className="delete-confirm"
              role="group"
              aria-label={t('Подтверждение удаления задачи')}
            >
              <strong>
                {task?.repeat !== 'none' ? t('Удалить всю серию') : t('Удалить')} «{task?.title}»?
              </strong>
              <p>{t('После удаления задачу можно будет восстановить.')}</p>
              <div className="button-row">
                <button
                  className="button button-danger"
                  type="button"
                  disabled={busy}
                  onClick={remove}
                >
                  {t('Удалить')}
                </button>
                <button
                  className="button button-secondary"
                  type="button"
                  disabled={busy}
                  ref={keepButton}
                  onClick={() => setConfirmDelete(false)}
                >
                  {t('Оставить')}
                </button>
              </div>
            </div>
          ) : (
            <div className="dialog-actions">
              {task ? (
                <button
                  className="icon-button danger"
                  type="button"
                  aria-label={t('Удалить задачу')}
                  ref={deleteButton}
                  onClick={() => setConfirmDelete(true)}
                  disabled={busy}
                >
                  <Trash2 size={19} />
                </button>
              ) : (
                <span />
              )}
              <div className="button-row">
                <button
                  className="button button-secondary"
                  type="button"
                  disabled={busy}
                  data-dialog-dismiss
                >
                  {t('Отмена')}
                </button>
                <button
                  className="button button-primary"
                  type="submit"
                  disabled={busy || !value.title.trim()}
                >
                  {busy ? <LoaderCircle size={17} className="spinning" /> : null}
                  {busy ? t('Сохраняем…') : task ? t('Сохранить') : t('Создать задачу')}
                </button>
              </div>
            </div>
          )}
        </fieldset>
      </form>
    </Dialog>
  );
}
