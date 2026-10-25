import { useI18n } from '../lib/i18n';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { CalendarDays, LoaderCircle, Trash2 } from 'lucide-react';
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
  onDelete,
  extendedColorsEnabled = false,
  onEnableExtendedColors,
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
  onDelete?: (event: GoogleCalendarEvent) => Promise<void>;
  extendedColorsEnabled?: boolean;
  onEnableExtendedColors?: () => Promise<void>;
}) {
  const { t, language, locale } = useI18n();
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
          repeat: 'none',
          ...draft,
        },
  );
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [retryLocked, setRetryLocked] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteConflict, setDeleteConflict] = useState(false);
  const attempt = useRef<{ id: string; input: GoogleEventInput } | null>(null);
  const actionLock = useRef(false);
  const deleteButtonRef = useRef<HTMLButtonElement>(null);
  const keepButtonRef = useRef<HTMLButtonElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const wasConfirming = useRef(false);
  const readOnly = Boolean(event && !canEditGoogleEvent(event, timeZone));
  const needsColorPermission = Boolean(
    value.colorId?.startsWith('#') &&
    !extendedColorsEnabled &&
    (!event || value.colorId !== event.colorId),
  );
  useEffect(() => {
    if (confirmDelete && !busy) keepButtonRef.current?.focus();
    else if (!confirmDelete && wasConfirming.current) {
      if (deleteButtonRef.current?.disabled) closeButtonRef.current?.focus();
      else deleteButtonRef.current?.focus();
    }
    wasConfirming.current = confirmDelete;
  }, [confirmDelete, busy]);
  const endpoint = (value: GoogleCalendarEvent['start']) =>
    value.date
      ? formatDate(value.date, { day: 'numeric', month: 'long', year: 'numeric' }, language)
      : value.dateTime
        ? `${new Intl.DateTimeFormat(locale, {
            timeZone,
            day: 'numeric',
            month: 'long',
            year: 'numeric',
          }).format(
            new Date(value.dateTime),
          )}, ${formatTime(minutesInZone(timeZone, new Date(value.dateTime)))}`
        : t('Не указано');
  const set = <K extends keyof GoogleEventInput>(key: K, next: GoogleEventInput[K]) => {
    setValue((old) => ({ ...old, [key]: next }));
    setError('');
  };
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (
      actionLock.current ||
      busy ||
      readOnly ||
      confirmDelete ||
      deleteConflict ||
      needsColorPermission
    )
      return;
    setError('');
    const candidate =
      retryLocked && attempt.current
        ? attempt.current.input
        : {
            ...value,
            title: value.title.trim(),
            description: value.description.trim(),
            time: value.allDay ? null : value.time,
          };
    const { repeat: _repeat, ...existingInput } = candidate;
    // Preserve the provider's current color unless the user actually changes it.
    const input =
      event && candidate.colorId === (event.colorId ?? null)
        ? (({ colorId: _color, ...unchangedColor }) => unchangedColor)(existingInput)
        : event
          ? existingInput
          : candidate;
    if (
      !input.allDay &&
      (!input.time ||
        Number(input.time.slice(0, 2)) * 60 + Number(input.time.slice(3)) + input.duration > 1440)
    ) {
      setError(t('Выбери время и длительность, чтобы событие завершилось до полуночи.'));
      return;
    }
    if (!attempt.current || !retryLocked)
      attempt.current = { id: attempt.current?.id ?? crypto.randomUUID(), input };
    actionLock.current = true;
    setBusy(true);
    try {
      await onSave(input, attempt.current.id, event);
      onClose();
    } catch (failure) {
      setError(
        event && failure instanceof ApiError && failure.status === 409
          ? t('{p0} Закрой форму и обнови календарь перед повторным изменением.', {
              p0: failure.message,
            })
          : failure instanceof Error
            ? failure.message
            : t('Не удалось сохранить запись.'),
      );
      setRetryLocked(
        !event && (!(failure instanceof ApiError) || failure.status === 0 || failure.status >= 500),
      );
      if (failure instanceof ApiError && failure.status >= 400 && failure.status < 500)
        attempt.current = null;
    } finally {
      actionLock.current = false;
      setBusy(false);
    }
  }
  async function remove() {
    if (!event || !onDelete || readOnly || actionLock.current || deleteConflict) return;
    actionLock.current = true;
    setBusy(true);
    setError('');
    try {
      await onDelete(event);
      onClose();
    } catch (failure) {
      const conflict = failure instanceof ApiError && failure.status === 409;
      setDeleteConflict(conflict);
      setError(
        conflict
          ? t('{p0} Закройте форму и обновите календарь перед удалением.', { p0: failure.message })
          : failure instanceof Error
            ? failure.message
            : t('Не удалось удалить запись. Попробуйте ещё раз.'),
      );
    } finally {
      actionLock.current = false;
      setBusy(false);
    }
  }
  return (
    <Dialog
      title={readOnly ? t('Запись') : event ? t('Редактировать запись') : t('Новая запись')}
      onClose={onClose}
      busy={busy}
      className="task-dialog"
    >
      <p className="info-note">
        <CalendarDays size={14} aria-hidden="true" />{' '}
        {readOnly
          ? event?.readOnlyReason
            ? t(event.readOnlyReason)
            : t('Эта запись доступна для просмотра. Измени её в Google Calendar.')
          : t('Изменения синхронизируются с Google Calendar.')}
      </p>
      {!readOnly && event?.recurring ? (
        <p className="field-hint">
          {t(
            'Изменится только этот экземпляр повторяющейся записи. Остальные события серии сохранятся.',
          )}
        </p>
      ) : null}
      {readOnly && event ? (
        <div className="google-event-preview">
          <strong>{event.title}</strong>
          <p>
            {endpoint(event.start)} →{' '}
            {endpoint(
              event.allDay && event.end.date ? { date: addDays(event.end.date, -1) } : event.end,
            )}
            {event.allDay ? t(' · весь день, даты включительно') : ''}
          </p>
          {event.description ? <p>{event.description}</p> : null}
          <p>{event.busy ? t('Занимает время в расписании') : t('Не блокирует свободное время')}</p>
        </div>
      ) : null}
      <form onSubmit={submit}>
        {!readOnly ? (
          <fieldset
            className="task-form"
            disabled={busy || retryLocked || confirmDelete || deleteConflict}
          >
            <label className="field">
              {t('Название')}
              <input
                autoFocus={!readOnly}
                required
                maxLength={160}
                value={value.title}
                onChange={(e) => set('title', e.target.value)}
              />
            </label>
            <label className="field">
              {t('Описание')}
              <textarea
                rows={3}
                maxLength={4000}
                value={value.description}
                onChange={(e) => set('description', e.target.value)}
              />
            </label>
            <label className="field">
              {t('Дата')}
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
              {t('Весь день')}
            </label>
            {!value.allDay ? (
              <div className="form-grid">
                <label className="field">
                  {t('Время')}
                  <input
                    type="time"
                    required
                    value={value.time ?? ''}
                    onChange={(e) => set('time', e.target.value)}
                  />
                </label>
                <label className="field">
                  {t('Длительность, мин')}
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
            {!extendedColorsEnabled && onEnableExtendedColors ? (
              <div className="calendar-color-permission">
                <p className="field-hint">
                  {t(
                    'Для новых оттенков Google попросит разрешение на управление календарями. С ним цвет будет одинаковым в Ritm и Google.',
                  )}
                </p>
                <button
                  className="text-button"
                  type="button"
                  disabled={busy}
                  onClick={async () => {
                    actionLock.current = true;
                    setBusy(true);
                    setError('');
                    try {
                      await onEnableExtendedColors();
                    } catch (failure) {
                      setError(
                        failure instanceof Error
                          ? failure.message
                          : t('Не удалось открыть разрешение Google.'),
                      );
                    } finally {
                      actionLock.current = false;
                      setBusy(false);
                    }
                  }}
                >
                  {t('Разрешить новые цвета')}
                </button>
                {needsColorPermission ? (
                  <p className="field-hint" role="status">
                    {t('Чтобы сохранить этот оттенок, сначала разреши новые цвета в Google.')}
                  </p>
                ) : null}
              </div>
            ) : null}
            {!event ? (
              <label className="field">
                {t('Повторение')}
                <select
                  value={value.repeat ?? 'none'}
                  onChange={(change) =>
                    set('repeat', change.target.value as GoogleEventInput['repeat'])
                  }
                >
                  <option value="none">{t('Не повторять')}</option>
                  <option value="daily">{t('Каждый день')}</option>
                  <option value="weekly">{t('Каждую неделю')}</option>
                  <option value="monthly">{t('Каждый месяц')}</option>
                </select>
              </label>
            ) : null}
          </fieldset>
        ) : null}
        {error ? (
          <p className="error-note" role="alert">
            {error}
          </p>
        ) : null}
        {retryLocked ? (
          <p className="field-hint">
            {t(
              'Ответ не получен. Событие уже могло сохраниться. Повтори сохранение с теми же данными — новая копия не создастся. Если закроешь форму, проверь календарь перед созданием новой записи.',
            )}
          </p>
        ) : null}
        {confirmDelete && event ? (
          <div
            className="delete-confirm"
            role="group"
            aria-label={t('Подтверждение удаления записи')}
          >
            <strong>{t('Удалить эту запись из календаря?')}</strong>
            <p>«{event.title}»</p>
            <p>
              {event.recurring
                ? t('Только эта встреча. Остальные события серии сохранятся.')
                : t('Удаление синхронизируется с Google Calendar.')}
            </p>
            {busy ? <p role="status">{t('Удаляем запись…')}</p> : null}
            <div className="button-row">
              <button
                ref={keepButtonRef}
                className="button button-secondary"
                type="button"
                disabled={busy}
                onClick={() => setConfirmDelete(false)}
              >
                {t('Оставить')}
              </button>
              <button
                className="button button-danger"
                type="button"
                disabled={busy || deleteConflict}
                onClick={() => void remove()}
              >
                {busy ? <LoaderCircle className="spinning" size={16} aria-hidden="true" /> : null}
                {busy ? t('Удаляем…') : t('Удалить запись')}
              </button>
            </div>
          </div>
        ) : (
          <>
            <div className="dialog-actions">
              <span className="field-hint">{timeZone}</span>
              <div className="button-row">
                <button
                  ref={closeButtonRef}
                  className="button button-secondary"
                  type="button"
                  disabled={busy}
                  data-dialog-dismiss
                >
                  {readOnly ? t('Закрыть') : t('Отмена')}
                </button>
                {!readOnly ? (
                  <button
                    className="button button-primary"
                    type="submit"
                    disabled={
                      busy ||
                      deleteConflict ||
                      needsColorPermission ||
                      !value.title.trim() ||
                      !value.date
                    }
                  >
                    {busy ? <LoaderCircle className="spinning" size={16} /> : null}
                    {busy
                      ? t('Сохраняем…')
                      : retryLocked
                        ? t('Повторить сохранение')
                        : event
                          ? t('Сохранить изменения')
                          : t('Создать запись')}
                  </button>
                ) : null}
              </div>
            </div>
            {event && onDelete && !readOnly ? (
              <div className="button-row">
                <button
                  ref={deleteButtonRef}
                  className="text-button danger"
                  type="button"
                  disabled={busy || deleteConflict}
                  onClick={() => {
                    setError('');
                    setConfirmDelete(true);
                  }}
                >
                  <Trash2 size={16} aria-hidden="true" />
                  {t('Удалить запись')}
                </button>
              </div>
            ) : null}
          </>
        )}
      </form>
    </Dialog>
  );
}
