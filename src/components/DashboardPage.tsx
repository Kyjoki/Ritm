import { useRef, useState, type CSSProperties, type FormEvent } from 'react';
import {
  ArrowUpRight,
  CalendarDays,
  Check,
  CheckCheck,
  CirclePlus,
  Clock3,
  ListTodo,
  LoaderCircle,
  CircleAlert,
  Sparkles,
} from 'lucide-react';
import type { GoogleCalendarEvent, Settings, Task, TaskInput } from '../../shared/types';
import { getDayOccurrences } from '../features/calendar-utils';
import { calendarOccurrences, type CalendarOccurrence } from '../features/google-occurrences';
import { durationText, formatDate, formatTime, greeting } from '../lib/date';
import { calendarEntryStyle } from '../lib/calendar-colors';
import { Orb } from './Orb';

const taskPlural = new Intl.PluralRules('ru-RU');

interface Props {
  tasks: Task[];
  googleEvents: GoogleCalendarEvent[];
  googleUncertain: boolean;
  googlePending: boolean;
  onGoogleEdit: (event: GoogleCalendarEvent) => void;
  onGoogleTaskToggle: (event: GoogleCalendarEvent) => Promise<void>;
  busyGoogleTaskIds?: ReadonlySet<string>;
  tasksPermissionMessage?: string;
  onEnableGoogleTasks?: () => Promise<void>;
  onQuickAdd: (title: string) => Promise<void>;
  settings: Settings;
  today: string;
  now: number;
  busyIds: Set<string>;
  onEdit: (task: Task) => void;
  onCreate: (draft?: Partial<TaskInput>) => void;
  onToggle: (task: Task, occurrenceDate: string, completed: boolean) => void;
  onAI: (prompt?: string) => void;
  onCalendar: () => void;
}
export function DashboardPage({
  tasks,
  googleEvents,
  googleUncertain,
  googlePending,
  onGoogleEdit,
  onGoogleTaskToggle,
  busyGoogleTaskIds,
  tasksPermissionMessage,
  onEnableGoogleTasks,
  onQuickAdd,
  settings,
  today,
  now,
  busyIds,
  onEdit,
  onCreate,
  onToggle,
  onAI,
  onCalendar,
}: Props) {
  const [quickTitle, setQuickTitle] = useState('');
  const [quickBusy, setQuickBusy] = useState(false);
  const [quickError, setQuickError] = useState('');
  const [googleTaskError, setGoogleTaskError] = useState('');
  const [permissionBusy, setPermissionBusy] = useState(false);
  const quickInFlight = useRef(false);
  const occurrences = getDayOccurrences(
    tasks.filter((task) => task.kind === 'task'),
    today,
  );
  const todayEntries = occurrences.sort(
    (a, b) => Number(a.completed) - Number(b.completed) || (a.start ?? 1441) - (b.start ?? 1441),
  );
  const combined = calendarOccurrences(tasks, googleEvents, today, settings.timeZone).filter(
    (entry) => entry.source === 'google' || entry.task.calendarEntry !== false,
  );
  const googleTodos = combined
    .filter(
      (entry) => entry.source === 'google' && (entry.event.taskLink || entry.event.googleTask),
    )
    .sort(
      (a, b) => Number(a.completed) - Number(b.completed) || (a.start ?? 1441) - (b.start ?? 1441),
    );
  const completed =
    todayEntries.filter((entry) => entry.completed).length +
    googleTodos.filter(
      (entry) => entry.source === 'google' && entry.event.googleTask?.status === 'completed',
    ).length;
  const todoCount = todayEntries.length + googleTodos.length;
  const unknownGoogleCount = googleTodos.filter(
    (entry) => entry.source === 'google' && !entry.event.googleTask,
  ).length;
  const taskCountLabel = `${todoCount} ${taskPlural.select(todoCount) === 'one' ? 'задача' : taskPlural.select(todoCount) === 'few' ? 'задачи' : 'задач'}`;
  const waitingForPlan = googlePending && !combined.length;
  const timed = combined.filter(
    (o): o is CalendarOccurrence & { start: number; end: number } =>
      o.start !== null && o.end !== null,
  );
  const upcoming = timed
    .filter((o) => !o.completed && o.end > now)
    .sort((a, b) => a.start - b.start)[0];
  const schedule = timed.sort((a, b) => a.start - b.start);
  const openEntry = (entry: CalendarOccurrence) =>
    entry.source === 'google' ? onGoogleEdit(entry.event) : onEdit(entry.task);
  const undated = tasks.filter((t) => !t.date && !t.completed),
    overdue = tasks.filter((t) => t.date && t.date < today && !t.completed && t.repeat === 'none');
  const workStart =
      Number(settings.workDayStart.slice(0, 2)) * 60 + Number(settings.workDayStart.slice(3)),
    workEnd = Number(settings.workDayEnd.slice(0, 2)) * 60 + Number(settings.workDayEnd.slice(3));
  const intervals = combined
    .filter((o) => o.busy)
    .map((o) => [
      Math.max(workStart, o.allDay ? workStart : (o.start ?? workEnd), now),
      Math.min(workEnd, o.allDay ? workEnd : (o.end ?? workStart)),
    ])
    .filter(([s, e]) => e > s)
    .sort((a, b) => a[0] - b[0]);
  let occupied = 0,
    end = Math.max(workStart, now);
  for (const [s, e] of intervals) {
    occupied += Math.max(0, e - Math.max(s, end));
    end = Math.max(end, e);
  }
  const free = Math.max(0, workEnd - Math.max(workStart, now) - occupied);
  const greetingName = settings.displayName.split(' ')[0];
  const quickAdd = async (event: FormEvent) => {
    event.preventDefault();
    const title = quickTitle.trim();
    if (!title || quickInFlight.current) return;
    quickInFlight.current = true;
    setQuickBusy(true);
    setQuickError('');
    try {
      await onQuickAdd(title);
      setQuickTitle('');
    } catch (error) {
      setQuickError(error instanceof Error ? error.message : 'Не удалось добавить задачу.');
    } finally {
      quickInFlight.current = false;
      setQuickBusy(false);
    }
  };
  const toggleGoogleTask = async (event: GoogleCalendarEvent) => {
    setGoogleTaskError('');
    try {
      await onGoogleTaskToggle(event);
    } catch (error) {
      setGoogleTaskError(
        error instanceof Error ? error.message : 'Не удалось изменить статус задачи Google.',
      );
    }
  };
  const enableGoogleTasks = async () => {
    if (!onEnableGoogleTasks || permissionBusy) return;
    setPermissionBusy(true);
    setGoogleTaskError('');
    try {
      await onEnableGoogleTasks();
    } catch (error) {
      setGoogleTaskError(
        error instanceof Error ? error.message : 'Не удалось открыть подключение Google Tasks.',
      );
    } finally {
      setPermissionBusy(false);
    }
  };
  return (
    <section className="page dashboard-page" aria-labelledby="dashboard-title">
      <header className="page-heading">
        <div>
          <p className="page-eyebrow">
            {formatDate(today, { weekday: 'long', day: 'numeric', month: 'long' })} · Мой день
          </p>
          <h1 className="gradient-title" id="dashboard-title">
            {greeting(Math.floor(now / 60))}, {greetingName}
          </h1>
          <p className="page-description">Ваши дела. Ваш темп. Один ясный план.</p>
        </div>
        <button className="button button-primary" onClick={() => onCreate({ date: today })}>
          <CirclePlus size={18} /> Добавить запись
        </button>
      </header>
      <div className="overview-grid">
        <div className="panel progress-card">
          <span className="card-eyebrow">Твой прогресс</span>
          <div className="progress-body">
            <div
              className="progress-ring"
              style={
                {
                  '--progress': `${todoCount && !unknownGoogleCount ? (completed / todoCount) * 360 : 0}deg`,
                } as CSSProperties
              }
            >
              <Sparkles size={19} />
            </div>
            <div>
              <strong>
                {unknownGoogleCount
                  ? '—'
                  : googlePending && !todoCount
                    ? '…'
                    : todoCount
                      ? `${completed} из ${todoCount}`
                      : googleUncertain
                        ? '—'
                        : 'Нет задач'}
              </strong>
              <span>
                {unknownGoogleCount
                  ? 'Статус Google Tasks не проверен'
                  : googlePending && !todoCount
                    ? 'Загружаем задачи'
                    : todoCount
                      ? 'задач выполнено'
                      : googleUncertain
                        ? 'Данные Google не проверены'
                        : 'на сегодня'}
              </span>
            </div>
          </div>
          <p className="card-footnote">
            {googleUncertain
              ? 'Уточняем расписание Google'
              : free
                ? `Свободно ${durationText(free)}`
                : now >= workEnd
                  ? 'Рабочий день завершён'
                  : 'Всё время уже в плане'}
          </p>
        </div>
        <button
          className="panel focus-card"
          onClick={() => (upcoming ? openEntry(upcoming) : onCalendar())}
        >
          <span className="card-eyebrow">
            {upcoming && upcoming.start <= now
              ? 'Сейчас в плане'
              : googleUncertain
                ? 'Ближайшая известная запись'
                : 'Ближайшее событие'}
          </span>
          <strong className="focus-time">
            {upcoming
              ? formatTime(upcoming.start)
              : waitingForPlan
                ? 'Проверяем…'
                : googleUncertain
                  ? 'Нет данных'
                  : 'Без спешки'}
          </strong>
          <span className="focus-name">
            {upcoming?.title ??
              (googleUncertain ? 'События Google пока не загружены' : 'Впереди свободное время')}
          </span>
          <span className="focus-meta">
            {upcoming
              ? `${durationText(upcoming.duration)} · ${upcoming.source === 'google' ? 'Google Calendar' : upcoming.task.kind === 'event' ? 'Событие' : 'Задача'}`
              : 'Открыть календарь'}
            <ArrowUpRight size={16} />
          </span>
        </button>
        <div className="panel ai-overview">
          <div className="ai-overview-head">
            <Orb />
            <strong>Помощник Ritm</strong>
          </div>
          <p>
            Поможет собрать удобный план
            <br className="desktop-break" /> и оставить время для себя.
          </p>
          <button
            className="button button-secondary"
            onClick={() => onAI('Спланируй мой день с учётом приоритетов и свободного времени.')}
          >
            <Sparkles size={15} /> Спланировать день
            <ArrowUpRight size={15} />
          </button>
        </div>
      </div>
      <div className="day-work-grid">
        <div className="panel tasks-panel">
          <div className="section-heading">
            <h2>Задачи на сегодня</h2>
            <span>
              {unknownGoogleCount
                ? taskCountLabel
                : googlePending && !todoCount
                  ? 'Загружаем…'
                  : googleUncertain && !todoCount
                    ? 'Не проверено'
                    : `${completed} из ${todoCount}`}
            </span>
          </div>
          {todoCount ? (
            <div className="today-list">
              {googleTodos.map((entry) => {
                if (entry.source !== 'google') return null;
                const event = entry.event;
                const isComplete = event.googleTask?.status === 'completed';
                const busy = busyGoogleTaskIds?.has(event.id) ?? false;
                return (
                  <div className={`task-row${isComplete ? ' is-complete' : ''}`} key={entry.key}>
                    <button
                      className="check-target"
                      onClick={() =>
                        event.googleTask ? void toggleGoogleTask(event) : openEntry(entry)
                      }
                      disabled={busy}
                      aria-label={
                        event.googleTask
                          ? `${isComplete ? 'Вернуть в задачи' : 'Выполнить'}: ${entry.title}`
                          : `Открыть задачу: ${entry.title}`
                      }
                      aria-pressed={event.googleTask ? isComplete : undefined}
                    >
                      {busy ? (
                        <LoaderCircle size={18} className="spinning" />
                      ) : event.googleTask ? (
                        <span className="task-checkbox">
                          {isComplete ? <Check size={14} strokeWidth={3} /> : null}
                        </span>
                      ) : (
                        <ListTodo size={18} className="task-pending-icon" />
                      )}
                    </button>
                    <button className="task-copy" onClick={() => openEntry(entry)}>
                      <span className="task-title">{entry.title}</span>
                      <span className="task-meta">
                        Google Tasks
                        {isComplete ? ' · Выполнено' : ''}
                        {!event.googleTask
                          ? ` · ${event.taskUnavailableReason ?? 'Статус пока недоступен'}`
                          : ''}
                      </span>
                    </button>
                    <time>
                      {entry.start === null
                        ? 'Весь день'
                        : formatTime(entry.start, { compact: true })}
                    </time>
                  </div>
                );
              })}
              {todayEntries.map((o) => {
                const task = o.task;
                return (
                  <div className={`task-row${o.completed ? ' is-complete' : ''}`} key={o.key}>
                    <button
                      className="check-target"
                      onClick={() => onToggle(task, o.date, o.completed)}
                      disabled={busyIds.has(task.id)}
                      aria-label={`${o.completed ? 'Вернуть в план' : 'Выполнить'}: ${task.title}`}
                      aria-pressed={o.completed}
                    >
                      {busyIds.has(task.id) ? (
                        <LoaderCircle size={18} className="spinning" />
                      ) : (
                        <span className="task-checkbox">
                          {o.completed ? <Check size={14} strokeWidth={3} /> : null}
                        </span>
                      )}
                    </button>
                    <button className="task-copy" onClick={() => onEdit(task)}>
                      <span className="task-title">{task.title}</span>
                      <span className="task-meta">
                        {task.calendarEntry === false ? 'Личная задача' : 'Задача'}
                        {task.priority === 'high'
                          ? ' · Высокий приоритет'
                          : task.priority === 'low'
                            ? ' · Низкий приоритет'
                            : ' · Обычный приоритет'}
                        {task.time ? ` · ${durationText(task.duration)}` : ''}
                        {task.repeat !== 'none' ? ' · Повторяется' : ''}
                      </span>
                    </button>
                    {o.start !== null ? <time>{formatTime(o.start)}</time> : null}
                  </div>
                );
              })}
            </div>
          ) : googleUncertain ? (
            <div className="empty-inline" role={googlePending ? 'status' : undefined}>
              {googlePending ? (
                <LoaderCircle size={28} className="spinning" aria-hidden="true" />
              ) : (
                <CircleAlert size={28} aria-hidden="true" />
              )}
              <h3>{googlePending ? 'Загружаем задачи' : 'Задачи Google пока недоступны'}</h3>
              <p>
                {googlePending
                  ? 'Проверяем задачи на сегодня.'
                  : 'Личные задачи можно добавить ниже. Подключение Google проверь в календаре.'}
              </p>
              {!googlePending ? (
                <button className="text-button" onClick={onCalendar}>
                  Открыть календарь
                </button>
              ) : null}
            </div>
          ) : (
            <div className="empty-inline">
              <CheckCheck size={32} />
              <h3>Пока нет задач на сегодня</h3>
              <p>Добавьте первое дело ниже. Встречи и занятия — в расписании справа.</p>
            </div>
          )}
          {tasksPermissionMessage ? (
            <div className="dashboard-task-permission">
              <p className="field-hint">{tasksPermissionMessage}</p>
              {onEnableGoogleTasks ? (
                <button
                  className="text-button"
                  onClick={() => void enableGoogleTasks()}
                  disabled={permissionBusy}
                >
                  {permissionBusy ? (
                    <LoaderCircle size={15} className="spinning" />
                  ) : (
                    <CheckCheck size={15} />
                  )}
                  Подключить Google Tasks
                </button>
              ) : null}
            </div>
          ) : null}
          {googleTaskError ? (
            <p className="error-note" role="alert">
              {googleTaskError}
            </p>
          ) : null}
          <form
            className="dashboard-quick-add"
            onSubmit={quickAdd}
            aria-label="Быстрое добавление задачи"
          >
            <label className="visually-hidden" htmlFor="dashboard-quick-title">
              Новая задача на сегодня
            </label>
            <input
              id="dashboard-quick-title"
              value={quickTitle}
              onChange={(event) => setQuickTitle(event.target.value)}
              placeholder="Что нужно сделать сегодня?"
              maxLength={160}
              autoComplete="off"
              disabled={quickBusy}
            />
            <button
              className="button button-secondary"
              type="submit"
              disabled={quickBusy || !quickTitle.trim()}
              aria-label="Добавить задачу на сегодня"
            >
              {quickBusy ? (
                <LoaderCircle size={18} className="spinning" />
              ) : (
                <CirclePlus size={18} />
              )}
              <span>Добавить</span>
            </button>
          </form>
          <p className="field-hint dashboard-quick-hint">
            Только в списке задач — без записи в календаре.
          </p>
          {quickError ? (
            <p className="error-note" role="alert">
              {quickError}
            </p>
          ) : null}
        </div>
        <div className="panel schedule-panel">
          <div className="section-heading">
            <h2>Расписание</h2>
            <button className="text-button" onClick={onCalendar}>
              Сегодня
              <ArrowUpRight size={13} />
            </button>
          </div>
          {schedule.length ? (
            <div className="schedule-list">
              {schedule.slice(0, 6).map((o) => (
                <div className="schedule-row" key={o.key}>
                  <time>{formatTime(o.start)}</time>
                  <button
                    className={`schedule-event${o.completed ? ' is-complete' : ''}`}
                    style={calendarEntryStyle(o)}
                    onClick={() => openEntry(o)}
                  >
                    <strong>{o.title}</strong>
                    <span>
                      {o.completed
                        ? 'Завершено'
                        : `${o.startLabel ?? formatTime(o.start)}–${o.endLabel ?? formatTime(o.end)}${o.end === 1440 ? ' · следующий день' : ''}${o.source === 'google' ? ' · Google' : ''}`}
                    </span>
                  </button>
                </div>
              ))}
              {schedule.length > 6 ? (
                <button className="text-button" onClick={onCalendar}>
                  Ещё {schedule.length - 6} в календаре
                </button>
              ) : null}
            </div>
          ) : (
            <div className="empty-schedule">
              <CalendarDays size={26} />
              <p>{googleUncertain ? 'Уточняем расписание' : 'Свободное расписание'}</p>
              <button
                className="text-button"
                onClick={() => onAI('Найди свободное время в моём расписании на сегодня.')}
              >
                <Clock3 size={14} /> Найти удобное время
              </button>
            </div>
          )}
          {combined
            .filter((o) => o.allDay)
            .map((o) => (
              <button key={o.key} className="text-button" onClick={() => openEntry(o)}>
                Весь день · {o.title} · Google
              </button>
            ))}
          {googleUncertain ? (
            <p className="field-hint" role="status">
              Google Calendar ещё не проверен. Открой календарь, чтобы обновить события.
            </p>
          ) : null}
          <div className="backlog-grid">
            <Backlog title="Без даты" tasks={undated} onEdit={onEdit} />
            <Backlog title="Просрочено" tasks={overdue} onEdit={onEdit} />
          </div>
        </div>
      </div>
      <div className="dashboard-bottom">
        <span>
          <ListTodo size={14} />{' '}
          {completed === todoCount && todoCount
            ? 'Все дела завершены. Можно выдохнуть.'
            : 'Следуйте своему темпу — всё важное перед вами.'}
        </span>
        <button
          className="text-button"
          onClick={() => onAI('Найди свободное время в моём расписании на сегодня.')}
        >
          <Clock3 size={15} /> Найти свободное время
        </button>
      </div>
      <div className="ai-dock">
        <button onClick={() => onAI()}>
          <Orb small /> Спросить ИИ
          <Sparkles size={15} />
        </button>
      </div>
    </section>
  );
}
function Backlog({
  title,
  tasks,
  onEdit,
}: {
  title: string;
  tasks: Task[];
  onEdit: (task: Task) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  return (
    <div>
      <span className="card-eyebrow">
        {title}
        {tasks.length ? ` · ${tasks.length}` : ''}
      </span>
      {tasks.length ? (
        (expanded ? tasks : tasks.slice(0, 3)).map((t) => (
          <button key={t.id} onClick={() => onEdit(t)}>
            {t.title}
          </button>
        ))
      ) : (
        <p>Всё в порядке</p>
      )}
      {tasks.length > 3 ? (
        <button
          className="backlog-expand"
          onClick={() => setExpanded(!expanded)}
          aria-expanded={expanded}
        >
          {expanded ? 'Свернуть' : `Показать все ${tasks.length}`}
        </button>
      ) : null}
    </div>
  );
}
