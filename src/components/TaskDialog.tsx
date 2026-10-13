import { useEffect, useRef, useState, type FormEvent } from 'react';
import { ChevronDown, LoaderCircle, Trash2 } from 'lucide-react';
import type { Task, TaskInput } from '../../shared/types';
import { Dialog } from './Dialog';
import { CalendarColorPicker } from './CalendarColorPicker';

interface Props {
  task?: Task;
  draft?: Partial<TaskInput>;
  onClose: () => void;
  onSave: (task: TaskInput, id?: string) => Promise<void>;
  onDelete: (task: Task) => Promise<void>;
}
export function TaskDialog({ task, draft, onClose, onSave, onDelete }: Props) {
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
    };
  });
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [advanced, setAdvanced] = useState(
      Boolean(task?.description || (task?.repeat !== 'none' && task)),
    );
  const [confirmDelete, setConfirmDelete] = useState(false);
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
        'Запись должна завершиться до полуночи. Уменьшите длительность или выберите другое время.',
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
      setError(e instanceof Error ? e.message : 'Задача не сохранилась. Попробуйте ещё раз.');
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
      setError(e instanceof Error ? e.message : 'Не удалось удалить задачу.');
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog
      title={task ? 'Редактировать задачу' : 'Новая задача'}
      onClose={onClose}
      busy={busy}
      className="task-dialog"
    >
      <form onSubmit={submit}>
        <fieldset className="task-form" disabled={busy}>
          {task?.repeat !== 'none' && task ? (
            <p className="info-note">Повторяющаяся задача: изменения применятся ко всей серии.</p>
          ) : null}
          <label className="field">
            Название
            <input
              autoFocus
              required
              maxLength={160}
              placeholder="Что нужно сделать?"
              value={value.title}
              onChange={(e) => set('title', e.target.value)}
            />
          </label>
          <div className="form-grid">
            <label className="field">
              Дата
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
            <label className="field">
              Время
              <input
                type="time"
                value={value.time ?? ''}
                disabled={!value.date}
                onChange={(e) => set('time', e.target.value || null)}
              />
            </label>
          </div>
          <div className="form-grid">
            <label className="field">
              Длительность
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
                      {n < 60 ? `${n} минут` : `${n / 60} ч`}
                    </option>
                  ))}
              </select>
            </label>
            <label className="field">
              Приоритет
              <select
                value={value.priority}
                onChange={(e) => set('priority', e.target.value as TaskInput['priority'])}
              >
                <option value="low">Низкий</option>
                <option value="normal">Обычный</option>
                <option value="high">Высокий</option>
              </select>
            </label>
          </div>
          <CalendarColorPicker value={value.colorId} onChange={(id) => set('colorId', id)} />
          <button
            className="disclosure"
            type="button"
            onClick={() => setAdvanced(!advanced)}
            aria-expanded={advanced}
          >
            <ChevronDown size={16} className={advanced ? 'rotated' : ''} /> Дополнительные поля
          </button>
          {advanced ? (
            <div className="advanced-fields">
              <label className="field">
                Описание
                <textarea
                  value={value.description}
                  rows={3}
                  maxLength={2000}
                  placeholder="Детали и важные шаги"
                  onChange={(e) => set('description', e.target.value)}
                />
              </label>
              <div className="form-grid">
                <label className="field">
                  Повторение
                  <select
                    value={value.repeat}
                    disabled={!value.date}
                    onChange={(e) => set('repeat', e.target.value as TaskInput['repeat'])}
                  >
                    <option value="none">Не повторять</option>
                    <option value="daily">Каждый день</option>
                    <option value="weekly">Каждую неделю</option>
                    <option value="monthly">Каждый месяц</option>
                  </select>
                </label>
                <label className="field">
                  Тип
                  <select
                    value={value.kind}
                    onChange={(e) => set('kind', e.target.value as TaskInput['kind'])}
                  >
                    <option value="task">Задача</option>
                    <option value="event">Событие</option>
                  </select>
                </label>
              </div>
            </div>
          ) : null}
          {!value.date ? (
            <p className="field-hint">
              Без даты — задача останется в списке, пока вы не запланируете её.
            </p>
          ) : value.time ? (
            <p className="field-hint">
              Выберите длительность, чтобы запись завершилась до полуночи.
            </p>
          ) : null}
          {error ? (
            <p role="alert" className="error-note">
              {error}
            </p>
          ) : null}
          {confirmDelete ? (
            <div className="delete-confirm" role="group" aria-label="Подтверждение удаления задачи">
              <strong>
                {task?.repeat !== 'none' ? 'Удалить всю серию' : 'Удалить'} «{task?.title}»?
              </strong>
              <p>После удаления задачу можно будет восстановить.</p>
              <div className="button-row">
                <button
                  className="button button-danger"
                  type="button"
                  disabled={busy}
                  onClick={remove}
                >
                  Удалить
                </button>
                <button
                  className="button button-secondary"
                  type="button"
                  disabled={busy}
                  ref={keepButton}
                  onClick={() => setConfirmDelete(false)}
                >
                  Оставить
                </button>
              </div>
            </div>
          ) : (
            <div className="dialog-actions">
              {task ? (
                <button
                  className="icon-button danger"
                  type="button"
                  aria-label="Удалить задачу"
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
                  onClick={onClose}
                >
                  Отмена
                </button>
                <button
                  className="button button-primary"
                  type="submit"
                  disabled={busy || !value.title.trim()}
                >
                  {busy ? <LoaderCircle size={17} className="spinning" /> : null}
                  {busy ? 'Сохраняем…' : task ? 'Сохранить' : 'Создать задачу'}
                </button>
              </div>
            </div>
          )}
        </fieldset>
      </form>
    </Dialog>
  );
}
