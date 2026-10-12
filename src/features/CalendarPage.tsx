import { useEffect, useMemo, useState } from 'react';
import {
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Plus,
  Repeat2,
  Sparkles,
} from 'lucide-react';
import type { Task, TaskInput } from '../../shared/types';
import {
  addDays,
  addMonths,
  dateKey,
  durationLabel,
  formatDate,
  getDayOccurrences,
  layoutOccurrences,
  minuteTime,
  parseDate,
  startOfWeek,
} from './calendar-utils';
import type { TaskOccurrence } from './calendar-utils';
import '../styles/calendar-settings.css';

interface CalendarPageProps {
  tasks: Task[];
  today: string;
  timeZone: string;
  onEdit: (task: Task) => void;
  onCreate: (draft?: Partial<TaskInput>) => void;
}

type CalendarView = 'day' | 'week' | 'month';
const VIEW_LABELS: Record<CalendarView, string> = { day: 'День', week: 'Неделя', month: 'Месяц' };
const WEEKDAYS = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

function freeIntervals(entries: TaskOccurrence[]): { start: number; end: number }[] {
  let cursor = 8 * 60;
  const intervals: { start: number; end: number }[] = [];
  for (const entry of entries) {
    if (entry.start === null || entry.end === null) continue;
    const start = Math.max(8 * 60, entry.start);
    if (start - cursor >= 30) intervals.push({ start: cursor, end: Math.min(start, 20 * 60) });
    cursor = Math.max(cursor, entry.end);
    if (cursor >= 20 * 60) break;
  }
  if (cursor < 20 * 60) intervals.push({ start: cursor, end: 20 * 60 });
  return intervals.filter((interval) => interval.end - interval.start >= 30);
}

function occurrenceLabel(entry: TaskOccurrence): string {
  const time =
    entry.start === null
      ? 'Без времени'
      : `${minuteTime(entry.start)}–${entry.end === 1440 ? '00:00' : minuteTime(entry.end ?? entry.start)}`;
  return `${entry.task.title}, ${time}${entry.completed ? ', выполнено' : ''}${entry.task.repeat !== 'none' ? ', повторяющаяся запись, редактировать серию' : ''}`;
}

function AgendaEntry({ entry, onEdit }: { entry: TaskOccurrence; onEdit: (task: Task) => void }) {
  return (
    <button
      type="button"
      className={`cal-agenda-entry ${entry.completed ? 'cal-completed' : ''}`}
      onClick={() => onEdit(entry.task)}
      aria-label={occurrenceLabel(entry)}
    >
      <span className="cal-agenda-time">
        {entry.start === null ? <Clock3 size={18} aria-hidden="true" /> : minuteTime(entry.start)}
      </span>
      <span className="cal-agenda-copy">
        <strong>{entry.task.title}</strong>
        <span>
          {entry.task.kind === 'event' ? 'Событие' : 'Задача'} ·{' '}
          {durationLabel(entry.task.duration)}
          {entry.task.priority === 'high' ? ' · Высокий приоритет' : ''}
          {entry.key.endsWith(':continued') ? ' · Продолжение' : ''}
        </span>
      </span>
      {entry.task.repeat !== 'none' ? (
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

export function CalendarPage({ tasks, today, timeZone, onEdit, onCreate }: CalendarPageProps) {
  const [selectedDate, setSelectedDate] = useState(today);
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
  const periodDays = useMemo(
    () =>
      Array.from({ length: view === 'week' ? 7 : 1 }, (_, index) =>
        view === 'week' ? addDays(weekStart, index) : selectedDate,
      ),
    [view, weekStart, selectedDate],
  );
  const occurrencesByDay = useMemo(
    () => periodDays.map((date) => ({ date, entries: getDayOccurrences(tasks, date) })),
    [tasks, periodDays],
  );
  const selectedEntries = useMemo(
    () => getDayOccurrences(tasks, selectedDate),
    [tasks, selectedDate],
  );
  const monthDays = useMemo(() => {
    const month = parseDate(selectedDate);
    month.setUTCDate(1);
    const first = startOfWeek(dateKey(month));
    return Array.from({ length: 42 }, (_, index) => {
      const date = addDays(first, index);
      return {
        date,
        entries: getDayOccurrences(tasks, date),
        currentMonth: date.slice(0, 7) === selectedDate.slice(0, 7),
      };
    });
  }, [tasks, selectedDate]);
  const [startHour, endHour] = useMemo(() => {
    let start = 8;
    let end = 20;
    for (const day of occurrencesByDay)
      for (const entry of day.entries) {
        if (entry.start !== null && entry.end !== null) {
          start = Math.min(start, Math.floor(entry.start / 60));
          end = Math.max(end, Math.ceil(entry.end / 60));
        }
      }
    return [Math.max(0, start), Math.min(24, end)];
  }, [occurrencesByDay]);
  const hours = Array.from({ length: endHour - startHour }, (_, index) => startHour + index);
  const gridHeight = hours.length * 62;
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
    onCreate({ date, time, duration, kind: 'event' });
  }

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
                          <span key={entry.key} className="cal-month-dot" aria-hidden="true" />
                        ))
                    : entries.slice(0, 2).map((entry) => (
                        <button
                          key={entry.key}
                          className={`cal-month-event ${entry.completed ? 'cal-completed' : ''}`}
                          type="button"
                          onClick={() => onEdit(entry.task)}
                          aria-label={occurrenceLabel(entry)}
                        >
                          {entry.start === null ? '' : `${minuteTime(entry.start)} `}
                          {entry.task.title}
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
                  <AgendaEntry key={entry.key} entry={entry} onEdit={onEdit} />
                ))
              ) : (
                <div className="cal-empty-small">
                  <CalendarDays size={24} aria-hidden="true" />
                  <p>На этот день пока нет планов</p>
                </div>
              )}
              <div className="cal-free-intervals">
                {freeIntervals(entries)
                  .slice(0, 2)
                  .map((interval) => (
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
                        Свободно {minuteTime(interval.start)}–{minuteTime(interval.end)}
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
            style={{ gridTemplateColumns: `52px repeat(${periodDays.length}, minmax(0, 1fr))` }}
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
              style={{ gridTemplateColumns: `52px repeat(${periodDays.length}, minmax(0, 1fr))` }}
            >
              <span>
                Без
                <br />
                времени
              </span>
              {occurrencesByDay.map(({ date, entries }) => (
                <div key={date}>
                  {entries
                    .filter((entry) => entry.start === null)
                    .map((entry) => (
                      <button
                        type="button"
                        key={entry.key}
                        className="cal-all-day-event"
                        onClick={() => onEdit(entry.task)}
                      >
                        {entry.task.title}
                      </button>
                    ))}
                </div>
              ))}
            </div>
          ) : null}
          <div className="cal-grid-scroll">
            <div
              className="cal-grid"
              style={{
                gridTemplateColumns: `52px repeat(${periodDays.length}, minmax(0, 1fr))`,
                height: gridHeight,
              }}
            >
              <div className="cal-hour-labels">
                {hours.map((hour) => (
                  <span key={hour} style={{ height: 62 }}>
                    {String(hour).padStart(2, '0')}:00
                  </span>
                ))}
              </div>
              {occurrencesByDay.map(({ date, entries }) => (
                <div
                  className={`cal-day-column ${date === today ? 'cal-today-column' : ''}`}
                  key={date}
                >
                  {hours.flatMap((hour) =>
                    [0, 30].map((minute) => (
                      <button
                        type="button"
                        className="cal-free-slot"
                        key={`${hour}:${minute}`}
                        style={{ top: (((hour - startHour) * 60 + minute) / 60) * 62, height: 31 }}
                        aria-label={`Добавить запись: ${formatDate(date, { day: 'numeric', month: 'long' })}, ${minuteTime(hour * 60 + minute)}`}
                        onClick={() => addEntry(date, minuteTime(hour * 60 + minute))}
                      >
                        <Plus size={15} aria-hidden="true" />
                      </button>
                    )),
                  )}
                  {layoutOccurrences(entries).map((entry) => {
                    const duration = (entry.end ?? 0) - (entry.start ?? 0);
                    return (
                      <button
                        key={entry.key}
                        type="button"
                        className={`cal-grid-event ${entry.task.kind === 'event' ? 'cal-event-kind' : ''} ${entry.completed ? 'cal-completed' : ''} ${duration < 40 ? 'cal-compact-event' : ''}`}
                        style={{
                          top: (((entry.start ?? 0) - startHour * 60) / 60) * 62 + 2,
                          height: Math.max(22, (duration / 60) * 62 - 4),
                          width: `calc(${100 / entry.lanes}% - 7px)`,
                          left: `calc(${(entry.lane * 100) / entry.lanes}% + 4px)`,
                        }}
                        onClick={() => onEdit(entry.task)}
                        title={occurrenceLabel(entry)}
                        aria-label={occurrenceLabel(entry)}
                      >
                        <strong>{entry.task.title}</strong>
                        <span>
                          {minuteTime(entry.start ?? 0)}–
                          {entry.end === 1440 ? '00:00' : minuteTime(entry.end ?? 0)}
                          {entry.task.repeat !== 'none' ? ' · ↻' : ''}
                        </span>
                      </button>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>
          <footer className="cal-calendar-foot">
            <span>
              <i className="cal-legend-task" />
              Задачи
              <i className="cal-legend-event" />
              События
            </span>
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
                В плане <strong>{view === 'month' ? selectedEntries.length : visibleCount}</strong>{' '}
                записей. Оставь немного времени для себя.
              </>
            ) : (
              'Пока всё свободно. Начни с одного важного дела.'
            )}
          </p>
          <small>Повторяющаяся запись редактируется целой серией.</small>
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
