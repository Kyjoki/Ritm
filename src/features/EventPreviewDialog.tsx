import { CalendarDays, Clock3, LockKeyhole, Pencil, Repeat2 } from 'lucide-react';
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

function instantLabel(value: string | undefined, timeZone: string): string {
  const instant = new Date(value ?? '');
  if (!Number.isFinite(instant.getTime())) return 'Время не указано';
  const date = new Intl.DateTimeFormat('ru-RU', { ...dateOptions, timeZone }).format(instant);
  const time = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
    second: instant.getUTCSeconds() ? '2-digit' : undefined,
    hour12: true,
  }).format(instant);
  return `${date}, ${time}`;
}

function scheduleLabel(entry: CalendarOccurrence, date: string, timeZone: string): string {
  if (entry.source === 'google') {
    const { event } = entry;
    if (event.allDay) {
      if (!event.start.date || !event.end.date) return 'Дата не указана';
      // Google ends all-day events at the beginning of the following day.
      const lastDate = addDays(event.end.date, -1);
      const first = formatDate(event.start.date, dateOptions);
      return event.start.date === lastDate
        ? `${first} · Весь день`
        : `${first} — ${formatDate(lastDate, dateOptions)} · Весь день, даты включительно`;
    }
    return `${instantLabel(event.start.dateTime, timeZone)} → ${instantLabel(event.end.dateTime, timeZone)}`;
  }
  // An occurrence can be a continuation after midnight: display its original interval.
  const firstDate = entry.continued ? addDays(entry.date || date, -1) : entry.date || date;
  if (!entry.task.time) return `${formatDate(firstDate, dateOptions)} · Без времени`;
  const start = timeMinutes(entry.task.time);
  const end = start + entry.task.duration;
  const lastDate = addDays(firstDate, Math.floor(end / 1440));
  return `${formatDate(firstDate, dateOptions)}, ${formatTime(start)} → ${formatDate(lastDate, dateOptions)}, ${formatTime(end)}`;
}

export function EventPreviewDialog({
  entry,
  date,
  timeZone,
  onClose,
  onEdit,
}: {
  entry: CalendarOccurrence | null;
  date: string;
  timeZone: string;
  onClose: () => void;
  onEdit: (entry: CalendarOccurrence) => void;
}) {
  const editable = Boolean(
    entry && (entry.source === 'ritm' || canEditGoogleEvent(entry.event, timeZone)),
  );
  const description =
    entry?.source === 'google' ? entry.event.description : entry?.task.description;
  const recurring =
    entry?.source === 'google' ? entry.event.recurring : entry?.task.repeat !== 'none';
  const readOnlyReason =
    entry?.source === 'google' && !editable
      ? (entry.event.readOnlyReason ??
        'Эта запись доступна только для просмотра. Измени её в Google Calendar.')
      : null;

  return (
    <Dialog title="Просмотр события" onClose={onClose} className="event-preview-dialog">
      {entry ? (
        <div className="event-preview-content">
          <div className="event-preview-title" style={calendarEntryStyle(entry)}>
            <h3>{entry.title}</h3>
          </div>
          <div className="event-preview-detail">
            <CalendarDays size={19} aria-hidden="true" />
            <p>{scheduleLabel(entry, date, timeZone)}</p>
          </div>
          {!entry.allDay && (entry.source === 'google' || entry.task.time) ? (
            <div className="event-preview-detail event-preview-muted">
              <Clock3 size={18} aria-hidden="true" />
              <p>Часовой пояс: {timeZone}</p>
            </div>
          ) : null}
          {description ? (
            <section className="event-preview-description" aria-label="Описание события">
              <h4>Описание</h4>
              <p>{description}</p>
            </section>
          ) : null}
          {recurring ? (
            <div className="event-preview-detail event-preview-muted">
              <Repeat2 size={18} aria-hidden="true" />
              <p>
                {entry.source === 'google'
                  ? editable
                    ? 'Повторяющееся событие. При редактировании изменится только эта запись.'
                    : 'Повторяющееся событие.'
                  : `Повторение: ${{ daily: 'ежедневно', weekly: 'еженедельно', monthly: 'ежемесячно', none: 'нет' }[entry.task.repeat]}.`}
              </p>
            </div>
          ) : null}
          {readOnlyReason ? (
            <div className="event-preview-detail event-preview-readonly">
              <LockKeyhole size={18} aria-hidden="true" />
              <p>{readOnlyReason}</p>
            </div>
          ) : null}
        </div>
      ) : (
        <p className="event-preview-unavailable" role="status">
          Запись обновлена или удалена. Закрой просмотр и выбери событие в календаре ещё раз.
        </p>
      )}
      <div className="dialog-actions event-preview-actions">
        <button type="button" className="button button-secondary" onClick={onClose}>
          Закрыть
        </button>
        {entry && editable ? (
          <button type="button" className="button button-primary" onClick={() => onEdit(entry)}>
            <Pencil size={16} aria-hidden="true" />
            Редактировать
          </button>
        ) : null}
      </div>
    </Dialog>
  );
}
