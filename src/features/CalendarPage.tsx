import { useEffect, useMemo, useRef, useState } from 'react';
import {
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Plus,
  Repeat2,
  Sparkles,
  AlertCircle,
  LoaderCircle,
  RefreshCw,
} from 'lucide-react';
import type {
  GoogleCalendarEvent,
  GoogleCalendarStatus,
  GoogleEventInput,
  Task,
  TaskInput,
} from '../../shared/types';
import {
  addDays,
  addMonths,
  dateKey,
  durationLabel,
  formatDate,
  minuteTime,
  parseDate,
  startOfWeek,
  timeMinutes,
} from './calendar-utils';
import {
  calendarOccurrences,
  calendarRange,
  layoutCalendarOccurrences,
  type CalendarOccurrence,
} from './google-occurrences';
import { formatTime, minutesInZone } from '../lib/date';
import { calendarEntryStyle } from '../lib/calendar-colors';
import '../styles/calendar-settings.css';

interface CalendarPageProps {
  tasks: Task[];
  today: string;
  timeZone: string;
  onEdit: (task: Task) => void;
  onCreate: (draft?: Partial<TaskInput>) => void;
  googleStatus?: GoogleCalendarStatus | null;
  googleEvents?: GoogleCalendarEvent[];
  googleLoading?: boolean;
  googleError?: string;
  googlePartial?: boolean;
  googleFetchedAt?: string | null;
  onGoogleEdit?: (event: GoogleCalendarEvent) => void;
  onGoogleCreate?: (draft: Partial<GoogleEventInput>) => void;
  onRangeChange?: (from: string, to: string) => void;
  onGoogleRefresh?: () => void;
  onOpenSettings?: () => void;
}

type CalendarView = 'day' | 'week' | 'month';
const VIEW_LABELS: Record<CalendarView, string> = { day: 'День', week: 'Неделя', month: 'Месяц' };
const WEEKDAYS = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
const HOURS = Array.from({ length: 24 }, (_, hour) => hour);
const GRID_TIME_COLUMN = 62;
const HOUR_HEIGHT = 48;
const INITIAL_HOUR = 9;
const EMPTY_GOOGLE_EVENTS: GoogleCalendarEvent[] = [];

function freeIntervals(entries: CalendarOccurrence[]): { start: number; end: number }[] {
  if (entries.some((entry) => entry.allDay && entry.busy)) return [];
  let cursor = 8 * 60;
  const intervals: { start: number; end: number }[] = [];
  for (const entry of entries) {
    if (!entry.busy || entry.start === null || entry.end === null) continue;
    const start = Math.max(8 * 60, entry.start);
    if (start - cursor >= 30) intervals.push({ start: cursor, end: Math.min(start, 20 * 60) });
    cursor = Math.max(cursor, entry.end);
    if (cursor >= 20 * 60) break;
  }
  if (cursor < 20 * 60) intervals.push({ start: cursor, end: 20 * 60 });
  return intervals.filter((interval) => interval.end - interval.start >= 30);
}

function occurrenceLabel(entry: CalendarOccurrence): string {
  const time = entry.allDay
    ? 'Весь день'
    : entry.start === null
      ? 'Без времени'
      : `${entry.startLabel ?? formatTime(entry.start)}–${entry.endLabel ?? formatTime(entry.end ?? entry.start)}`;
  return `${entry.title}, ${time}${entry.source === 'google' ? ', Google Calendar' : ', Ritm'}${entry.completed ? ', выполнено' : ''}${entry.source === 'ritm' && entry.task.repeat !== 'none' ? ', повторяющаяся запись, редактировать серию' : ''}${entry.source === 'google' && entry.event.readOnly ? ', только просмотр' : ''}${entry.clockChange ? ', перевод часов' : ''}`;
}

function entryTime(entry: CalendarOccurrence, edge: 'start' | 'end'): string {
  const label = edge === 'start' ? entry.startLabel : entry.endLabel;
  return label
    ? label.replace(/:00(?=\s[AP]M$)/, '')
    : formatTime(entry[edge] ?? 0, { compact: true });
}

function AgendaEntry({
  entry,
  onEdit,
}: {
  entry: CalendarOccurrence;
  onEdit: (entry: CalendarOccurrence) => void;
}) {
  return (
    <button
      type="button"
      className={`cal-agenda-entry ${entry.completed ? 'cal-completed' : ''} ${entry.source === 'google' ? 'cal-google-entry' : ''}`}
      onClick={() => onEdit(entry)}
      aria-label={occurrenceLabel(entry)}
      style={calendarEntryStyle(entry)}
    >
      <span className="cal-agenda-time">
        {entry.start === null ? <Clock3 size={18} aria-hidden="true" /> : entryTime(entry, 'start')}
      </span>
      <span className="cal-agenda-copy">
        <strong>{entry.title}</strong>
        <span>
          {entry.source === 'google'
            ? 'Google Calendar'
            : entry.task.kind === 'event'
              ? 'Событие Ritm'
              : 'Задача Ritm'}{' '}
          · {entry.allDay ? 'Весь день' : durationLabel(Math.ceil(entry.duration))}
          {entry.source === 'ritm' && entry.task.priority === 'high' ? ' · Высокий приоритет' : ''}
          {entry.continued ? ' · Продолжение' : ''}
          {entry.clockChange ? ' · Перевод часов' : ''}
          {entry.source === 'google' && entry.event.readOnly ? ' · Просмотр' : ''}
          {entry.source === 'google' && !entry.busy ? ' · Время свободно' : ''}
        </span>
      </span>
      {entry.source === 'ritm' && entry.task.repeat !== 'none' ? (
        <Repeat2 size={16} aria-label="Повторяющаяся запись" />
      ) : null}
      {entry.completed ? (
        <Check size={18} aria-label="Выполнено" />
      ) : (
        <ChevronRight size={17} aria-hidden="true" />
      )}
    </button>
  );
}

export function CalendarPage({
  tasks,
  today,
  timeZone,
  onEdit,
  onCreate,
  googleStatus = null,
  googleEvents = EMPTY_GOOGLE_EVENTS,
  googleLoading = false,
  googleError = '',
  googlePartial = false,
  googleFetchedAt = null,
  onGoogleEdit,
  onGoogleCreate,
  onRangeChange,
  onGoogleRefresh,
  onOpenSettings,
}: CalendarPageProps) {
  const [selectedDate, setSelectedDate] = useState(today);
  const googleConnected = googleStatus?.status === 'connected';
  const sourceAvailable = googleConnected && Boolean(onGoogleCreate);
  const rangeCallback = useRef(onRangeChange);
  const gridScrollRef = useRef<HTMLDivElement>(null);
  const scrolledPeriodRef = useRef<string | null>(null);
  useEffect(() => {
    rangeCallback.current = onRangeChange;
  }, [onRangeChange]);
  const [isMobile, setIsMobile] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(max-width: 760px)').matches,
  );
  const [view, setView] = useState<CalendarView>(() =>
    typeof window !== 'undefined' && window.matchMedia('(max-width: 760px)').matches
      ? 'day'
      : 'week',
  );
  useEffect(() => {
    const media = window.matchMedia('(max-width: 760px)');
    const listener = () => setIsMobile(media.matches);
    media.addEventListener('change', listener);
    return () => media.removeEventListener('change', listener);
  }, []);

  const weekStart = startOfWeek(selectedDate);
  const range = calendarRange(view, selectedDate);
  useEffect(() => {
    rangeCallback.current?.(range.from, range.to);
  }, [range.from, range.to, timeZone]);
  const periodDays = useMemo(
    () =>
      Array.from({ length: view === 'week' ? 7 : 1 }, (_, index) =>
        view === 'week' ? addDays(weekStart, index) : selectedDate,
      ),
    [view, weekStart, selectedDate],
  );
  const occurrencesByDay = useMemo(
    () =>
      periodDays.map((date) => ({
        date,
        entries: calendarOccurrences(tasks, googleEvents, date, timeZone),
      })),
    [tasks, googleEvents, periodDays, timeZone],
  );
  const selectedEntries = useMemo(
    () => calendarOccurrences(tasks, googleEvents, selectedDate, timeZone),
    [tasks, googleEvents, selectedDate, timeZone],
  );
  const monthDays = useMemo(() => {
    const month = parseDate(selectedDate);
    month.setUTCDate(1);
    const first = startOfWeek(dateKey(month));
    return Array.from({ length: 42 }, (_, index) => {
      const date = addDays(first, index);
      return {
        date,
        entries: calendarOccurrences(tasks, googleEvents, date, timeZone),
        currentMonth: date.slice(0, 7) === selectedDate.slice(0, 7),
      };
    });
  }, [tasks, googleEvents, selectedDate, timeZone]);
  const gridHeight = HOURS.length * HOUR_HEIGHT;
  useEffect(() => {
    if (isMobile || view === 'month') {
      scrolledPeriodRef.current = null;
      return;
    }
    const period = `${view}:${selectedDate}`;
    if (!gridScrollRef.current || scrolledPeriodRef.current === period) return;
    gridScrollRef.current.scrollTop = INITIAL_HOUR * HOUR_HEIGHT;
    scrolledPeriodRef.current = period;
  }, [isMobile, view, selectedDate]);
  const visibleCount = occurrencesByDay.reduce((total, day) => total + day.entries.length, 0);
  const noDateTasks = tasks.filter((task) => task.date === null && !task.completed);
  const periodLabel =
    view === 'month'
      ? formatDate(selectedDate, { month: 'long', year: 'numeric' })
      : view === 'day'
        ? formatDate(selectedDate, { day: 'numeric', month: 'long', weekday: 'short' })
        : `${formatDate(weekStart, { day: 'numeric', month: 'short' })} — ${formatDate(addDays(weekStart, 6), { day: 'numeric', month: 'short', year: 'numeric' })}`;

  function navigate(direction: number) {
    setSelectedDate((date) =>
      view === 'month'
        ? addMonths(date, direction)
        : addDays(date, direction * (view === 'week' ? 7 : 1)),
    );
  }

  function addEntry(date: string, time: string | null = null, duration = 60) {
    const boundedDuration = time ? Math.min(duration, 1440 - timeMinutes(time)) : duration;
    if (sourceAvailable)
      onGoogleCreate?.({ date, time, duration: boundedDuration, allDay: time === null });
    else onCreate({ date, time, duration: boundedDuration, kind: 'event' });
  }
  function editEntry(entry: CalendarOccurrence) {
    if (entry.source === 'google') onGoogleEdit?.(entry.event);
    else onEdit(entry.task);
  }
  const uncertainGoogle =
    googleLoading ||
    Boolean(googleError) ||
    googlePartial ||
    googleStatus?.status === 'reauth_required' ||
    (googleConnected && !googleFetchedAt);
  const fetchedDate = googleFetchedAt ? new Date(googleFetchedAt) : null;
  const fetchedLabel =
    fetchedDate && Number.isFinite(fetchedDate.getTime())
      ? new Intl.DateTimeFormat('ru-RU', {
          timeZone,
          day: 'numeric',
          month: 'short',
        }).format(fetchedDate) + ` · ${formatTime(minutesInZone(timeZone, fetchedDate))}`
      : null;

  return (
    <div className="cal-page">
      <header className="page-heading">
        <div>
          <p className="page-eyebrow">Пространство для твоих планов</p>
          <h1>Календарь</h1>
          <p className="page-description">Находи время для того, что важно.</p>
        </div>
        <button
          type="button"
          className="button button-primary"
          onClick={() => addEntry(selectedDate)}
        >
          <Plus size={17} aria-hidden="true" />
          <span>Добавить запись</span>
        </button>
      </header>
      <div className="cal-toolbar">
        <div className="cal-period">
          <button
            className="cal-icon-button"
            type="button"
            aria-label={`Предыдущий период: ${VIEW_LABELS[view].toLowerCase()}`}
            onClick={() => navigate(-1)}
          >
            <ChevronLeft size={19} aria-hidden="true" />
          </button>
          <h2 aria-live="polite">{periodLabel}</h2>
          <button
            className="cal-icon-button"
            type="button"
            aria-label={`Следующий период: ${VIEW_LABELS[view].toLowerCase()}`}
            onClick={() => navigate(1)}
          >
            <ChevronRight size={19} aria-hidden="true" />
          </button>
          <button
            className="button button-secondary cal-today"
            type="button"
            onClick={() => setSelectedDate(today)}
          >
            Сегодня
          </button>
        </div>
        <div className="cal-segment" role="group" aria-label="Вид календаря">
          {(Object.keys(VIEW_LABELS) as CalendarView[]).map((value) => (
            <button
              key={value}
              type="button"
              className={view === value ? 'cal-selected' : ''}
              aria-pressed={view === value}
              onClick={() => setView(value)}
            >
              {VIEW_LABELS[value]}
            </button>
          ))}
        </div>
      </div>

      {googleStatus || googleLoading || googleError ? (
        <div
          className={`cal-google-status ${googleError || googlePartial || googleStatus?.status === 'reauth_required' ? 'cal-google-status-warning' : ''}`}
          role={googleError ? 'alert' : 'status'}
        >
          {googleLoading ? (
            <LoaderCircle size={18} className="spinning" aria-hidden="true" />
          ) : googleError || googlePartial || googleStatus?.status === 'reauth_required' ? (
            <AlertCircle size={18} aria-hidden="true" />
          ) : (
            <CalendarDays size={18} aria-hidden="true" />
          )}
          <div className="cal-google-status-copy">
            <strong>
              {googleLoading
                ? 'Загружаем Google Calendar…'
                : googleError
                  ? 'Google Calendar требует внимания'
                  : googleStatus?.status === 'reauth_required'
                    ? 'Подключи Google Calendar заново'
                    : googlePartial
                      ? 'Загружена часть событий Google'
                      : googleConnected
                        ? 'Календарь синхронизирован'
                        : 'Google Calendar пока не подключён'}
            </strong>
            <span>
              {googleError
                ? `${googleError} Показанные события могут быть неактуальны.`
                : googlePartial
                  ? 'Часть событий не загружена. Свободное время нужно уточнить в Google Calendar.'
                  : googleLoading
                    ? 'Обновляем выбранный период и синхронизируем записи.'
                    : googleStatus?.status === 'reauth_required'
                      ? 'Разрешение нужно обновить в настройках.'
                      : googleConnected
                        ? 'Изменения сохраняются в Google Calendar. Расписание обновляется автоматически.'
                        : 'Подключи Google Calendar в настройках, чтобы работать с единым расписанием.'}
            </span>
            {fetchedLabel ? (
              <small className="cal-google-updated">
                Последнее обновление:{' '}
                <time dateTime={googleFetchedAt ?? undefined}>{fetchedLabel}</time>
              </small>
            ) : null}
          </div>
          <div className="cal-google-status-actions">
            {onGoogleRefresh && (googleConnected || Boolean(googleError)) ? (
              <button
                type="button"
                className="button button-secondary"
                disabled={googleLoading}
                onClick={onGoogleRefresh}
              >
                <RefreshCw size={15} aria-hidden="true" />
                Обновить
              </button>
            ) : null}
            {onOpenSettings && !googleConnected ? (
              <button type="button" className="cal-google-settings" onClick={onOpenSettings}>
                Настройки
                <ChevronRight size={15} aria-hidden="true" />
              </button>
            ) : null}
          </div>
        </div>
      ) : null}

      {view === 'month' ? (
        <section className="panel cal-month-panel" aria-label="Календарь на месяц">
          <div className="cal-month-grid">
            {WEEKDAYS.map((day) => (
              <span key={day} className="cal-weekday">
                {day}
              </span>
            ))}
            {monthDays.map(({ date, entries, currentMonth }) => (
              <div
                key={date}
                className={`cal-month-cell ${currentMonth ? '' : 'cal-other-month'} ${date === today ? 'cal-date-today' : ''}`}
              >
                <button
                  className="cal-month-day"
                  type="button"
                  aria-label={`${formatDate(date, { day: 'numeric', month: 'long' })}, записей: ${entries.length}. Открыть день`}
                  onClick={() => {
                    setSelectedDate(date);
                    setView('day');
                  }}
                >
                  <span>{parseDate(date).getUTCDate()}</span>
                  <small>
                    {entries.length
                      ? `${entries.length} ${entries.length === 1 ? 'запись' : entries.length < 5 ? 'записи' : 'записей'}`
                      : ''}
                  </small>
                </button>
                <div className="cal-month-events">
                  {isMobile
                    ? entries
                        .slice(0, 3)
                        .map((entry) => (
                          <span
                            key={entry.key}
                            className={`cal-month-dot ${entry.source === 'google' ? 'cal-google-dot' : ''}`}
                            style={calendarEntryStyle(entry)}
                            aria-hidden="true"
                          />
                        ))
                    : entries.slice(0, 2).map((entry) => (
                        <button
                          key={entry.key}
                          className={`cal-month-event ${entry.completed ? 'cal-completed' : ''} ${entry.source === 'google' ? 'cal-google-entry' : ''}`}
                          type="button"
                          onClick={() => editEntry(entry)}
                          aria-label={occurrenceLabel(entry)}
                          style={calendarEntryStyle(entry)}
                        >
                          {entry.start === null ? '' : `${entryTime(entry, 'start')} `}
                          {entry.title}
                        </button>
                      ))}
                  {!isMobile && entries.length > 2 ? (
                    <span className="cal-month-more">Ещё {entries.length - 2}</span>
                  ) : null}
                </div>
                {!isMobile ? (
                  <button
                    className="cal-month-add"
                    type="button"
                    aria-label={`Добавить запись на ${formatDate(date, { day: 'numeric', month: 'long' })}`}
                    onClick={() => addEntry(date)}
                  >
                    <Plus size={15} aria-hidden="true" />
                  </button>
                ) : null}
              </div>
            ))}
          </div>
        </section>
      ) : isMobile ? (
        <section className="panel cal-mobile-agenda">
          {occurrencesByDay.map(({ date, entries }) => (
            <div className="cal-agenda-day" key={date}>
              <div className="cal-section-head">
                <h2>{formatDate(date, { weekday: 'long', day: 'numeric', month: 'long' })}</h2>
                <span>Записей: {entries.length}</span>
              </div>
              {entries.length ? (
                entries.map((entry) => (
                  <AgendaEntry key={entry.key} entry={entry} onEdit={editEntry} />
                ))
              ) : (
                <div className="cal-empty-small">
                  <CalendarDays size={24} aria-hidden="true" />
                  <p>
                    {uncertainGoogle
                      ? 'В Ritm на этот день пока нет планов'
                      : 'На этот день пока нет планов'}
                  </p>
                </div>
              )}
              <div className="cal-free-intervals">
                {(uncertainGoogle ? [] : freeIntervals(entries)).slice(0, 2).map((interval) => (
                  <button
                    className="cal-free-time"
                    type="button"
                    key={interval.start}
                    onClick={() =>
                      addEntry(
                        date,
                        minuteTime(interval.start),
                        Math.min(60, interval.end - interval.start),
                      )
                    }
                  >
                    <Plus size={16} aria-hidden="true" />
                    <span>
                      {googleConnected ? 'Свободно' : 'Свободно в Ritm'}{' '}
                      {formatTime(interval.start, { compact: true })}–
                      {formatTime(interval.end, { compact: true })}
                    </span>
                  </button>
                ))}
              </div>
              <button className="cal-mobile-add" type="button" onClick={() => addEntry(date)}>
                <Plus size={17} aria-hidden="true" />
                Добавить запись
              </button>
            </div>
          ))}
        </section>
      ) : (
        <section
          className="panel cal-calendar-panel"
          aria-label={view === 'week' ? 'Расписание недели' : 'Расписание дня'}
        >
          <div
            className="cal-grid-header"
            style={{
              gridTemplateColumns: `${GRID_TIME_COLUMN}px repeat(${periodDays.length}, minmax(0, 1fr))`,
            }}
          >
            <span className="cal-timezone">
              {new Intl.DateTimeFormat('ru-RU', { timeZone, timeZoneName: 'shortOffset' })
                .formatToParts(parseDate(selectedDate))
                .find((part) => part.type === 'timeZoneName')
                ?.value.replace('GMT', 'UTC')}
            </span>
            {periodDays.map((date) => (
              <button
                key={date}
                className={`cal-day-heading ${date === today ? 'cal-date-today' : ''}`}
                type="button"
                onClick={() => {
                  setSelectedDate(date);
                  setView('day');
                }}
                aria-label={`Показать ${formatDate(date, { day: 'numeric', month: 'long' })}`}
              >
                <span>{formatDate(date, { weekday: 'short' })}</span>
                <strong>{parseDate(date).getUTCDate()}</strong>
              </button>
            ))}
          </div>
          {occurrencesByDay.some((day) => day.entries.some((entry) => entry.start === null)) ? (
            <div
              className="cal-all-day"
              style={{
                gridTemplateColumns: `${GRID_TIME_COLUMN}px repeat(${periodDays.length}, minmax(0, 1fr))`,
              }}
            >
              <span>Весь день / без времени</span>
              {occurrencesByDay.map(({ date, entries }) => (
                <div key={date}>
                  {entries
                    .filter((entry) => entry.start === null)
                    .map((entry) => (
                      <button
                        type="button"
                        key={entry.key}
                        className={`cal-all-day-event ${entry.source === 'google' ? 'cal-google-entry' : ''}`}
                        onClick={() => editEntry(entry)}
                        aria-label={occurrenceLabel(entry)}
                        style={calendarEntryStyle(entry)}
                      >
                        {entry.title}
                      </button>
                    ))}
                </div>
              ))}
            </div>
          ) : null}
          <div ref={gridScrollRef} className="cal-grid-scroll">
            <div
              className="cal-grid"
              style={{
                gridTemplateColumns: `${GRID_TIME_COLUMN}px repeat(${periodDays.length}, minmax(0, 1fr))`,
                height: gridHeight,
              }}
            >
              <div className="cal-hour-labels">
                {HOURS.map((hour) => (
                  <span key={hour} style={{ height: HOUR_HEIGHT }}>
                    {formatTime(hour * 60, { compact: true }).replace(' ', '')}
                  </span>
                ))}
              </div>
              {occurrencesByDay.map(({ date, entries }) => (
                <div
                  className={`cal-day-column ${date === today ? 'cal-today-column' : ''}`}
                  key={date}
                >
                  {HOURS.flatMap((hour) =>
                    [0, 30].map((minute) => (
                      <button
                        type="button"
                        className="cal-free-slot"
                        key={`${hour}:${minute}`}
                        style={{
                          top: ((hour * 60 + minute) / 60) * HOUR_HEIGHT,
                          height: HOUR_HEIGHT / 2,
                        }}
                        aria-label={`Добавить запись: ${formatDate(date, { day: 'numeric', month: 'long' })}, ${formatTime(hour * 60 + minute)}`}
                        onClick={() => addEntry(date, minuteTime(hour * 60 + minute))}
                      >
                        <Plus size={15} aria-hidden="true" />
                      </button>
                    )),
                  )}
                  {layoutCalendarOccurrences(entries).map((entry) => {
                    const duration = (entry.end ?? 0) - (entry.start ?? 0);
                    return (
                      <button
                        key={entry.key}
                        type="button"
                        className={`cal-grid-event ${entry.source === 'google' || entry.task.kind === 'event' ? 'cal-event-kind' : ''} ${entry.source === 'google' ? 'cal-google-entry' : ''} ${entry.completed ? 'cal-completed' : ''} ${duration < 75 ? 'cal-compact-event' : ''}`}
                        style={{
                          ...calendarEntryStyle(entry),
                          top: ((entry.start ?? 0) / 60) * HOUR_HEIGHT + 2,
                          height: Math.max(22, (duration / 60) * HOUR_HEIGHT - 4),
                          width: `calc(${100 / entry.lanes}% - 7px)`,
                          left: `calc(${(entry.lane * 100) / entry.lanes}% + 4px)`,
                        }}
                        onClick={() => editEntry(entry)}
                        title={occurrenceLabel(entry)}
                        aria-label={occurrenceLabel(entry)}
                      >
                        <strong>{entry.title}</strong>
                        <span>
                          {entryTime(entry, 'start')}–{entryTime(entry, 'end')}
                          {entry.source === 'ritm' && entry.task.repeat !== 'none' ? ' · ↻' : ''}
                          {entry.clockChange ? ' · Перевод часов' : ''}
                        </span>
                      </button>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>
          <footer className="cal-calendar-foot">
            <span>Одно расписание · Google Calendar</span>
            <span>Выбери свободный интервал, чтобы добавить запись</span>
          </footer>
        </section>
      )}

      <div className="cal-bottom-grid">
        <section className="panel cal-summary">
          <div className="cal-section-head">
            <h2>
              <Sparkles size={17} aria-hidden="true" />
              Твой темп
            </h2>
            <span>
              {view === 'month'
                ? 'Выбранный день'
                : view === 'week'
                  ? 'Эта неделя'
                  : 'Выбранный день'}
            </span>
          </div>
          <p>
            {(view === 'month' ? selectedEntries.length : visibleCount) ? (
              <>
                {uncertainGoogle ? 'Показано' : 'В плане'}{' '}
                <strong>{view === 'month' ? selectedEntries.length : visibleCount}</strong> записей.
                Оставь немного времени для себя.
              </>
            ) : uncertainGoogle ? (
              'Обновляем расписание. Дождись синхронизации.'
            ) : (
              'Пока всё свободно. Начни с одного важного дела.'
            )}
          </p>
          <small>При редактировании повторения изменится только выбранная запись.</small>
        </section>
        <section className="panel cal-backlog">
          <div className="cal-section-head">
            <h2>Без даты</h2>
            <span>{noDateTasks.length}</span>
          </div>
          {noDateTasks.length ? (
            noDateTasks.slice(0, 4).map((task) => (
              <button type="button" key={task.id} onClick={() => onEdit(task)}>
                <span>{task.title}</span>
                <ChevronRight size={16} aria-hidden="true" />
              </button>
            ))
          ) : (
            <p>Все дела уже нашли своё место в расписании.</p>
          )}
          {noDateTasks.length > 4 ? (
            <small>Ещё {noDateTasks.length - 4} в разделе «Мой день»</small>
          ) : null}
        </section>
      </div>
    </div>
  );
}
