import { useRef, useState, type FormEvent } from 'react';
import { CalendarDays, LoaderCircle } from 'lucide-react';
import type { GoogleCalendarEvent, GoogleEventInput } from '../../shared/types';
import { Dialog } from './Dialog';
import { CalendarColorPicker } from './CalendarColorPicker';
import { canEditGoogleEvent, googleEventDraft } from '../features/google-occurrences';
import { ApiError } from '../lib/api';
import { addDays, formatDate } from '../features/calendar-utils';
import { formatTime, minutesInZone } from '../lib/date';
import '../styles/google.css';

export function GoogleEventDialog({
  event,
  draft,
  timeZone,
  onClose,
  onSave,
}: {
  event?: GoogleCalendarEvent;
  draft?: Partial<GoogleEventInput>;
  timeZone: string;
  onClose: () => void;
  onSave: (
    input: GoogleEventInput,
    requestId: string,
    event?: GoogleCalendarEvent,
  ) => Promise<void>;
}) {
  const [value, setValue] = useState<GoogleEventInput>(() =>
    event
      ? { ...googleEventDraft(event, timeZone), colorId: event.colorId ?? null }
      : {
          title: '',
          description: '',
          date: '',
          time: '09:00',
          duration: 30,
          allDay: false,
          colorId: null,
          ...draft,
        },
  );
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [retryLocked, setRetryLocked] = useState(false);
  const attempt = useRef<{ id: string; input: GoogleEventInput } | null>(null);
  const readOnly = Boolean(event && !canEditGoogleEvent(event, timeZone));
  const endpoint = (value: GoogleCalendarEvent['start']) =>
    value.date
      ? formatDate(value.date, { day: 'numeric', month: 'long', year: 'numeric' })
      : value.dateTime
        ? `${new Intl.DateTimeFormat('ru-RU', {
            timeZone,
            day: 'numeric',
            month: 'long',
            year: 'numeric',
          }).format(
            new Date(value.dateTime),
          )}, ${formatTime(minutesInZone(timeZone, new Date(value.dateTime)))}`
        : 'Не указано';
  const set = <K extends keyof GoogleEventInput>(key: K, next: GoogleEventInput[K]) => {
    setValue((old) => ({ ...old, [key]: next }));
    setError('');
  };
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy || readOnly) return;
    setError('');
    const input =
      retryLocked && attempt.current
        ? attempt.current.input
        : {
            ...value,
            title: value.title.trim(),
            description: value.description.trim(),
            time: value.allDay ? null : value.time,
          };
    if (
      !input.allDay &&
      (!input.time ||
        Number(input.time.slice(0, 2)) * 60 + Number(input.time.slice(3)) + input.duration > 1440)
    ) {
      setError('Выбери время и длительность, чтобы событие завершилось до полуночи.');
      return;
    }
    if (!attempt.current || !retryLocked)
      attempt.current = { id: attempt.current?.id ?? crypto.randomUUID(), input };
    setBusy(true);
    try {
      await onSave(input, attempt.current.id, event);
      onClose();
    } catch (failure) {
      setError(
        event && failure instanceof ApiError && failure.status === 409
          ? `${failure.message} Закрой форму и обнови календарь перед повторным изменением.`
          : failure instanceof Error
            ? failure.message
            : 'Не удалось сохранить событие Google.',
      );
      setRetryLocked(
        !event && (!(failure instanceof ApiError) || failure.status === 0 || failure.status >= 500),
      );
      if (failure instanceof ApiError && failure.status >= 400 && failure.status < 500)
        attempt.current = null;
    } finally {
      setBusy(false);
    }
  }
  return (
    <Dialog
      title={
        readOnly ? 'Событие Google' : event ? 'Изменить событие Google' : 'Новое событие Google'
      }
      onClose={onClose}
      busy={busy}
      className="task-dialog"
    >
      <p className="info-note">
        <CalendarDays size={14} />{' '}
        {readOnly
          ? (event?.readOnlyReason ??
            'Эта запись доступна для просмотра. Измени её в Google Calendar.')
          : event?.recurring
            ? 'Изменится только эта запись. Остальные события повторяющейся серии сохранятся.'
            : 'Запись сохраняется в твоём основном календаре Google.'}
      </p>
      {readOnly && event ? (
        <div className="google-event-preview">
          <strong>{event.title}</strong>
          <p>
            {endpoint(event.start)} →{' '}
            {endpoint(
              event.allDay && event.end.date ? { date: addDays(event.end.date, -1) } : event.end,
            )}
            {event.allDay ? ' · весь день, даты включительно' : ''}
          </p>
          {event.description ? <p>{event.description}</p> : null}
          <p>{event.busy ? 'Занимает время в расписании' : 'Не блокирует свободное время'}</p>
        </div>
      ) : null}
      <form onSubmit={submit}>
        {!readOnly ? (
          <fieldset className="task-form" disabled={busy || retryLocked}>
            <label className="field">
              Название
              <input
                autoFocus={!readOnly}
                required
                maxLength={160}
                value={value.title}
                onChange={(e) => set('title', e.target.value)}
              />
            </label>
            <label className="field">
              Описание
              <textarea
                rows={3}
                maxLength={4000}
                value={value.description}
                onChange={(e) => set('description', e.target.value)}
              />
            </label>
            <label className="field">
              Дата
              <input
                type="date"
                required
                value={value.date}
                onChange={(e) => set('date', e.target.value)}
              />
            </label>
            <label className="google-all-day">
              <input
                type="checkbox"
                checked={value.allDay}
                onChange={(e) => set('allDay', e.target.checked)}
              />
              Весь день
            </label>
            {!value.allDay ? (
              <div className="form-grid">
                <label className="field">
                  Время
                  <input
                    type="time"
                    required
                    value={value.time ?? ''}
                    onChange={(e) => set('time', e.target.value)}
                  />
                </label>
                <label className="field">
                  Длительность, мин
                  <input
                    type="number"
                    required
                    min={5}
                    max={720}
                    step={5}
                    value={value.duration}
                    onChange={(e) => set('duration', Number(e.target.value))}
                  />
                </label>
              </div>
            ) : null}
            <CalendarColorPicker value={value.colorId} onChange={(id) => set('colorId', id)} />
          </fieldset>
        ) : null}
        {error ? (
          <p className="error-note" role="alert">
            {error}
          </p>
        ) : null}
        {retryLocked ? (
          <p className="field-hint">
            Ответ не получен. Событие уже могло сохраниться. Повтори сохранение с теми же данными —
            новая копия не создастся. Если закроешь форму, проверь календарь перед созданием новой
            записи.
          </p>
        ) : null}
        <div className="dialog-actions">
          <span className="field-hint">{timeZone}</span>
          <div className="button-row">
            <button
              className="button button-secondary"
              type="button"
              disabled={busy}
              onClick={onClose}
            >
              {readOnly ? 'Закрыть' : 'Отмена'}
            </button>
            {!readOnly ? (
              <button
                className="button button-primary"
                type="submit"
                disabled={busy || !value.title.trim() || !value.date}
              >
                {busy ? <LoaderCircle className="spinning" size={16} /> : null}
                {busy
                  ? 'Сохраняем…'
                  : retryLocked
                    ? 'Повторить сохранение'
                    : event
                      ? 'Сохранить в Google'
                      : 'Создать в Google'}
              </button>
            ) : null}
          </div>
        </div>
      </form>
    </Dialog>
  );
}
