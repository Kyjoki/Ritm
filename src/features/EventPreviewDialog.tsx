import { useI18n, translate, type Language } from '../lib/i18n';
import {
  CalendarDays,
  Clock3,
  LockKeyhole,
  Pencil,
  Repeat2,
  Check,
  LoaderCircle,
} from 'lucide-react';
import { useState } from 'react';
import type { GoogleCalendarEvent } from '../../shared/types';
import { Dialog } from '../components/Dialog';
import { calendarEntryStyle } from '../lib/calendar-colors';
import { formatTime } from '../lib/date';
import { addDays, formatDate, timeMinutes } from './calendar-utils';
import { canEditGoogleEvent, type CalendarOccurrence } from './google-occurrences';
import '../styles/event-preview.css';

const dateOptions: Intl.DateTimeFormatOptions = {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
};

function instantLabel(value: string | undefined, timeZone: string, language: Language): string {
  const t = (source: string) => translate(language, source);
  const instant = new Date(value ?? '');
  if (!Number.isFinite(instant.getTime())) return t('Время не указано');
  const date = new Intl.DateTimeFormat(language === 'en' ? 'en-US' : 'ru-RU', {
    ...dateOptions,
    timeZone,
  }).format(instant);
  const time = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
    second: instant.getUTCSeconds() ? '2-digit' : undefined,
    hour12: true,
  }).format(instant);
  return `${date}, ${time}`;
}

function scheduleLabel(
  entry: CalendarOccurrence,
  date: string,
  timeZone: string,
  language: Language,
): string {
  const t = (source: string, values?: Record<string, string | number>) =>
    translate(language, source, values);
  if (entry.source === 'google') {
    const { event } = entry;
    if (event.allDay) {
      if (!event.start.date || !event.end.date) return t('Дата не указана');
      // Google ends all-day events at the beginning of the following day.
      const lastDate = addDays(event.end.date, -1);
      const first = formatDate(event.start.date, dateOptions, language);
      return event.start.date === lastDate
        ? t('{p0} · Весь день', { p0: first })
        : t('{p0} — {p1} · Весь день, даты включительно', {
            p0: first,
            p1: formatDate(lastDate, dateOptions, language),
          });
    }
    return `${instantLabel(event.start.dateTime, timeZone, language)} → ${instantLabel(event.end.dateTime, timeZone, language)}`;
  }
  // An occurrence can be a continuation after midnight: display its original interval.
  const firstDate = entry.continued ? addDays(entry.date || date, -1) : entry.date || date;
  if (!entry.task.time)
    return t('{p0} · Без времени', { p0: formatDate(firstDate, dateOptions, language) });
  const start = timeMinutes(entry.task.time);
  const end = start + entry.task.duration;
  const lastDate = addDays(firstDate, Math.floor(end / 1440));
  return `${formatDate(firstDate, dateOptions, language)}, ${formatTime(start)} → ${formatDate(lastDate, dateOptions, language)}, ${formatTime(end)}`;
}

export function EventPreviewDialog({
  entry,
  date,
  timeZone,
  onClose,
  onEdit,
  onGoogleTaskToggle,
  taskBusy = false,
  onEnableGoogleTasks,
}: {
  entry: CalendarOccurrence | null;
  date: string;
  timeZone: string;
  onClose: () => void;
  onEdit: (entry: CalendarOccurrence) => void;
  onGoogleTaskToggle?: (event: GoogleCalendarEvent) => Promise<void>;
  taskBusy?: boolean;
  onEnableGoogleTasks?: () => Promise<void>;
}) {
  const { t, language } = useI18n();
  const [actionError, setActionError] = useState('');
  const [connecting, setConnecting] = useState(false);
  const googleTaskEvent = entry?.source === 'google' && entry.event.taskLink ? entry.event : null;
  async function toggleTask() {
    if (!googleTaskEvent?.googleTask || !onGoogleTaskToggle || taskBusy) return;
    setActionError('');
    try {
      await onGoogleTaskToggle(googleTaskEvent);
    } catch (error) {
      setActionError(
        error instanceof Error ? error.message : t('Не удалось сохранить выполнение в Google.'),
      );
    }
  }
  const editable = Boolean(
    entry && (entry.source === 'ritm' || canEditGoogleEvent(entry.event, timeZone)),
  );
  const description =
    entry?.source === 'google' ? entry.event.description : entry?.task.description;
  const recurring =
    entry?.source === 'google' ? entry.event.recurring : entry?.task.repeat !== 'none';
  const readOnlyReason = googleTaskEvent
    ? googleTaskEvent.googleTask
      ? t(
          'Статус выполнения синхронизируется с Google Tasks. Дату и время можно изменить в Google Calendar.',
        )
      : (googleTaskEvent.taskUnavailableReason ??
        t('Подключи Google Tasks, чтобы отмечать выполнение.'))
    : entry?.source === 'google' && !editable
      ? (entry.event.readOnlyReason ??
        t('Эта запись доступна только для просмотра. Измени её в Google Calendar.'))
      : null;

  return (
    <Dialog
      title={googleTaskEvent?.googleTask ? t('Задача Google Tasks') : t('Просмотр события')}
      onClose={onClose}
      busy={taskBusy || connecting}
      className="event-preview-dialog"
    >
      {entry ? (
        <div className="event-preview-content">
          <div
            className={`event-preview-title ${entry.completed ? 'is-complete' : ''}`}
            style={calendarEntryStyle(entry)}
          >
            <h3>{entry.title}</h3>
          </div>
          <div className="event-preview-detail">
            <CalendarDays size={19} aria-hidden="true" />
            <p>{scheduleLabel(entry, date, timeZone, language)}</p>
          </div>
          {!entry.allDay && (entry.source === 'google' || entry.task.time) ? (
            <div className="event-preview-detail event-preview-muted">
              <Clock3 size={18} aria-hidden="true" />
              <p>{t('Часовой пояс: {zone}', { zone: timeZone })}</p>
            </div>
          ) : null}
          {description ? (
            <section className="event-preview-description" aria-label={t('Описание события')}>
              <h4>{t('Описание')}</h4>
              <p>{description}</p>
            </section>
          ) : null}
          {recurring ? (
            <div className="event-preview-detail event-preview-muted">
              <Repeat2 size={18} aria-hidden="true" />
              <p>
                {entry.source === 'google'
                  ? editable
                    ? t('Повторяющееся событие. При редактировании изменится только эта запись.')
                    : t('Повторяющееся событие.')
                  : t('Повторение: {p0}.', {
                      p0: {
                        daily: t('ежедневно'),
                        weekly: t('еженедельно'),
                        monthly: t('ежемесячно'),
                        none: t('нет'),
                      }[entry.task.repeat],
                    })}
              </p>
            </div>
          ) : null}
          {readOnlyReason ? (
            <div className="event-preview-detail event-preview-readonly">
              <LockKeyhole size={18} aria-hidden="true" />
              <p>{t(readOnlyReason)}</p>
            </div>
          ) : null}
          {actionError ? (
            <p className="error-text" role="alert">
              {actionError}
            </p>
          ) : null}
          {googleTaskEvent && !googleTaskEvent.googleTask && onEnableGoogleTasks ? (
            <button
              type="button"
              className="button button-secondary"
              disabled={connecting}
              onClick={() => {
                setConnecting(true);
                setActionError('');
                void onEnableGoogleTasks()
                  .catch((error) =>
                    setActionError(
                      error instanceof Error
                        ? error.message
                        : t('Не удалось подключить Google Tasks.'),
                    ),
                  )
                  .finally(() => setConnecting(false));
              }}
            >
              {t('Подключить Google Tasks')}
            </button>
          ) : null}
        </div>
      ) : (
        <p className="event-preview-unavailable" role="status">
          {t('Запись обновлена или удалена. Закрой просмотр и выбери событие в календаре ещё раз.')}
        </p>
      )}
      <div className="dialog-actions event-preview-actions">
        <button
          type="button"
          className="button button-secondary"
          data-dialog-dismiss
          disabled={taskBusy || connecting}
        >
          {t('Закрыть')}
        </button>
        {entry && editable ? (
          <button type="button" className="button button-primary" onClick={() => onEdit(entry)}>
            <Pencil size={16} aria-hidden="true" />
            {t('Редактировать')}
          </button>
        ) : null}
        {googleTaskEvent?.googleTask && onGoogleTaskToggle ? (
          <button
            type="button"
            className="button button-primary"
            disabled={taskBusy}
            onClick={() => void toggleTask()}
          >
            {taskBusy ? (
              <LoaderCircle size={16} className="spinning" aria-hidden="true" />
            ) : (
              <Check size={16} aria-hidden="true" />
            )}
            {googleTaskEvent.googleTask.status === 'completed'
              ? t('Вернуть в задачи')
              : t('Выполнить задачу')}
          </button>
        ) : null}
      </div>
    </Dialog>
  );
}
