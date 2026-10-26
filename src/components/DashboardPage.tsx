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
import { addDays, getDayOccurrences } from '../features/calendar-utils';
import { calendarOccurrences, type CalendarOccurrence } from '../features/google-occurrences';
import { durationText, formatDate, formatTime, greeting } from '../lib/date';
import { calendarEntryStyle } from '../lib/calendar-colors';
import { Orb } from './Orb';
import { DashboardHabits } from './DashboardHabits';
import { useI18n } from '../lib/i18n';

interface Props {
  tasks: Task[];
  googleEvents: GoogleCalendarEvent[];
  googleUncertain: boolean;
  googlePending: boolean;
  onGoogleEdit: (event: GoogleCalendarEvent, date: string) => void;
  onGoogleTaskToggle: (event: GoogleCalendarEvent) => Promise<void>;
  busyGoogleTaskIds?: ReadonlySet<string>;
  tasksPermissionMessage?: string;
  onEnableGoogleTasks?: () => Promise<void>;
  onQuickAdd: (title: string, date: string) => Promise<void>;
  settings: Settings;
  today: string;
  now: number;
  busyIds: Set<string>;
  onEdit: (task: Task) => void;
  onCreate: (draft?: Partial<TaskInput>) => void;
  onToggle: (task: Task, occurrenceDate: string, completed: boolean) => void;
  onAI: (prompt?: string) => void;
  onCalendar: () => void;
  onHabits: () => void;
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
  onHabits,
}: Props) {
  const { language, locale, t: tr } = useI18n();
  const taskPlural = new Intl.PluralRules(locale);
  const [quickTitle, setQuickTitle] = useState('');
  const [taskDay, setTaskDay] = useState<'today' | 'tomorrow'>('today');
  const [quickBusy, setQuickBusy] = useState(false);
  const [quickError, setQuickError] = useState('');
  const [googleTaskError, setGoogleTaskError] = useState('');
  const [permissionBusy, setPermissionBusy] = useState(false);
  const quickInFlight = useRef(false);
  const taskDate = taskDay === 'today' ? today : addDays(today, 1);
  const occurrences = getDayOccurrences(
    tasks.filter((task) => task.kind === 'task'),
    taskDate,
    language,
  );
  const dayEntries = occurrences.sort(
    (a, b) => Number(a.completed) - Number(b.completed) || (a.start ?? 1441) - (b.start ?? 1441),
  );
  const combined = calendarOccurrences(
    tasks,
    googleEvents,
    today,
    settings.timeZone,
    language,
  ).filter((entry) => entry.source === 'google' || entry.task.calendarEntry !== false);
  const taskDayCombined =
    taskDay === 'today'
      ? combined
      : calendarOccurrences(tasks, googleEvents, taskDate, settings.timeZone, language).filter(
          (entry) => entry.source === 'google' || entry.task.calendarEntry !== false,
        );
  const googleTodos = taskDayCombined
    .filter(
      (entry) => entry.source === 'google' && (entry.event.taskLink || entry.event.googleTask),
    )
    .sort(
      (a, b) => Number(a.completed) - Number(b.completed) || (a.start ?? 1441) - (b.start ?? 1441),
    );
  const completed =
    dayEntries.filter((entry) => entry.completed).length +
    googleTodos.filter(
      (entry) => entry.source === 'google' && entry.event.googleTask?.status === 'completed',
    ).length;
  const todoCount = dayEntries.length + googleTodos.length;
  const unknownGoogleCount = googleTodos.filter(
    (entry) => entry.source === 'google' && !entry.event.googleTask,
  ).length;
  const todayTaskEntries =
    taskDay === 'today'
      ? dayEntries
      : getDayOccurrences(
          tasks.filter((task) => task.kind === 'task'),
          today,
          language,
        );
  const todayGoogleTodos =
    taskDay === 'today'
      ? googleTodos
      : combined.filter(
          (entry) => entry.source === 'google' && (entry.event.taskLink || entry.event.googleTask),
        );
  const todayCount = todayTaskEntries.length + todayGoogleTodos.length;
  const todayCompleted =
    todayTaskEntries.filter((entry) => entry.completed).length +
    todayGoogleTodos.filter(
      (entry) => entry.source === 'google' && entry.event.googleTask?.status === 'completed',
    ).length;
  const todayUnknownGoogleCount = todayGoogleTodos.filter(
    (entry) => entry.source === 'google' && !entry.event.googleTask,
  ).length;
  const taskCountLabel = `${todoCount} ${tr(taskPlural.select(todoCount) === 'one' ? tr('задача') : taskPlural.select(todoCount) === 'few' ? tr('задачи') : tr('задач'))}`;
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
    entry.source === 'google' ? onGoogleEdit(entry.event, entry.date) : onEdit(entry.task);
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
      await onQuickAdd(title, taskDate);
      setQuickTitle('');
    } catch (error) {
      setQuickError(error instanceof Error ? error.message : tr('Не удалось добавить задачу.'));
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
        error instanceof Error ? error.message : tr('Не удалось изменить статус задачи Google.'),
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
        error instanceof Error ? error.message : tr('Не удалось открыть подключение Google Tasks.'),
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
            {formatDate(today, { weekday: 'long', day: 'numeric', month: 'long' }, language)} ·{' '}
            {tr('Мой день')}
          </p>
          <h1 className="gradient-title" id="dashboard-title">
            {tr(greeting(Math.floor(now / 60)))}, {greetingName}
          </h1>
          <p className="page-description">{tr('Ваши дела. Ваш темп. Один ясный план.')}</p>
        </div>
        <button className="button button-primary" onClick={() => onCreate({ date: today })}>
          <CirclePlus size={18} /> {tr('Добавить запись')}{' '}
        </button>
      </header>
      <div className="overview-grid">
        <div className="panel progress-card">
          <span className="card-eyebrow">{tr('Твой прогресс')}</span>
          <div className="progress-body">
            <div
              className="progress-ring"
              style={
                {
                  '--progress': `${todayCount && !todayUnknownGoogleCount ? (todayCompleted / todayCount) * 360 : 0}deg`,
                } as CSSProperties
              }
            >
              <Sparkles size={19} />
            </div>
            <div>
              <strong>
                {todayUnknownGoogleCount
                  ? '—'
                  : googlePending && !todayCount
                    ? '…'
                    : todayCount
                      ? tr('{completed} из {total}', {
                          completed: todayCompleted,
                          total: todayCount,
                        })
                      : googleUncertain
                        ? '—'
                        : tr('Нет задач')}
              </strong>
              <span>
                {todayUnknownGoogleCount
                  ? tr('Статус Google Tasks не проверен')
                  : googlePending && !todayCount
                    ? tr('Загружаем задачи')
                    : todayCount
                      ? tr('задач выполнено')
                      : googleUncertain
                        ? tr('Данные Google не проверены')
                        : tr('на сегодня')}
              </span>
            </div>
          </div>
          <p className="card-footnote">
            {googleUncertain
              ? tr('Уточняем расписание Google')
              : free
                ? tr('Свободно {duration}', { duration: durationText(free, language) })
                : now >= workEnd
                  ? tr('Рабочий день завершён')
                  : tr('Всё время уже в плане')}
          </p>
        </div>
        <button
          className="panel focus-card"
          onClick={() => (upcoming ? openEntry(upcoming) : onCalendar())}
        >
          <span className="card-eyebrow">
            {upcoming && upcoming.start <= now
              ? tr('Сейчас в плане')
              : googleUncertain
                ? tr('Ближайшая известная запись')
                : tr('Ближайшее событие')}
          </span>
          <strong className="focus-time">
            {upcoming
              ? formatTime(upcoming.start)
              : waitingForPlan
                ? tr('Проверяем…')
                : googleUncertain
                  ? tr('Нет данных')
                  : tr('Без спешки')}
          </strong>
          <span className="focus-name">
            {upcoming?.title ??
              (googleUncertain
                ? tr('События Google пока не загружены')
                : tr('Впереди свободное время'))}
          </span>
          <span className="focus-meta">
            {upcoming
              ? `${durationText(upcoming.duration, language)} · ${upcoming.source === 'google' ? 'Google Calendar' : upcoming.task.kind === 'event' ? tr('Событие') : tr('Задача')}`
              : tr('Открыть календарь')}
            <ArrowUpRight size={16} />
          </span>
        </button>
        <div className="panel ai-overview">
          <div className="ai-overview-head">
            <Orb />
            <strong>{tr('Помощник Ritm')}</strong>
          </div>
          <p>
            {tr('Поможет собрать удобный план')} <br className="desktop-break" />{' '}
            {tr('и оставить время для себя.')}{' '}
          </p>
          <button
            className="button button-secondary"
            onClick={() =>
              onAI(tr('Спланируй мой день с учётом приоритетов и свободного времени.'))
            }
          >
            <Sparkles size={15} /> {tr('Спланировать день')} <ArrowUpRight size={15} />
          </button>
        </div>
      </div>
      <div className="day-work-grid">
        <div className="panel tasks-panel">
          <div className="section-heading">
            <h2>{tr(taskDay === 'today' ? 'Задачи на сегодня' : 'Задачи на завтра')}</h2>
            <span>
              {unknownGoogleCount
                ? taskCountLabel
                : googlePending && !todoCount
                  ? tr('Загружаем…')
                  : googleUncertain && !todoCount
                    ? tr('Не проверено')
                    : tr('{completed} из {total}', { completed, total: todoCount })}
            </span>
          </div>
          <div
            className="dashboard-task-days"
            role="group"
            aria-label={tr('День для списка задач')}
          >
            <button
              type="button"
              aria-pressed={taskDay === 'today'}
              onClick={() => setTaskDay('today')}
            >
              {tr('Сегодня')}
            </button>
            <button
              type="button"
              aria-pressed={taskDay === 'tomorrow'}
              onClick={() => setTaskDay('tomorrow')}
            >
              {tr('Завтра')}
            </button>
          </div>
          <form
            className="dashboard-quick-add"
            onSubmit={quickAdd}
            aria-label={tr('Быстрое добавление задачи')}
          >
            <label className="visually-hidden" htmlFor="dashboard-quick-title">
              {tr(taskDay === 'today' ? 'Новая задача на сегодня' : 'Новая задача на завтра')}{' '}
            </label>
            <input
              id="dashboard-quick-title"
              value={quickTitle}
              onChange={(event) => setQuickTitle(event.target.value)}
              placeholder={tr(
                taskDay === 'today' ? 'Что нужно сделать сегодня?' : 'Что нужно сделать завтра?',
              )}
              maxLength={160}
              autoComplete="off"
              disabled={quickBusy}
            />
            <button
              className="button button-secondary"
              type="submit"
              disabled={quickBusy || !quickTitle.trim()}
              aria-label={tr(
                taskDay === 'today' ? 'Добавить задачу на сегодня' : 'Добавить задачу на завтра',
              )}
            >
              {quickBusy ? (
                <LoaderCircle size={18} className="spinning" />
              ) : (
                <CirclePlus size={18} />
              )}
              <span>{tr('Добавить')}</span>
            </button>
          </form>
          <p className="field-hint dashboard-quick-hint">
            {tr('Только в списке задач — без записи в календаре.')}{' '}
          </p>
          {quickError ? (
            <p className="error-note" role="alert">
              {quickError}
            </p>
          ) : null}
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
                          ? `${isComplete ? tr('Вернуть в задачи') : tr('Выполнить')}: ${entry.title}`
                          : tr('Открыть задачу: {title}', { title: entry.title })
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
                        {isComplete ? tr(' · Выполнено') : ''}
                        {!event.googleTask
                          ? ` · ${event.taskUnavailableReason ?? tr('Статус пока недоступен')}`
                          : ''}
                      </span>
                    </button>
                    <time>
                      {entry.start === null
                        ? tr('Весь день')
                        : formatTime(entry.start, { compact: true })}
                    </time>
                  </div>
                );
              })}
              {dayEntries.map((o) => {
                const task = o.task;
                return (
                  <div className={`task-row${o.completed ? ' is-complete' : ''}`} key={o.key}>
                    <button
                      className="check-target"
                      onClick={() => onToggle(task, o.date, o.completed)}
                      disabled={busyIds.has(task.id)}
                      aria-label={`${o.completed ? tr('Вернуть в план') : tr('Выполнить')}: ${task.title}`}
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
                        {task.calendarEntry === false ? tr('Личная задача') : tr('Задача')}
                        {task.priority === 'high'
                          ? tr(' · Высокий приоритет')
                          : task.priority === 'low'
                            ? tr(' · Низкий приоритет')
                            : tr(' · Обычный приоритет')}
                        {task.time ? ` · ${durationText(task.duration, language)}` : ''}
                        {task.repeat !== 'none' ? tr(' · Повторяется') : ''}
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
              <h3>
                {googlePending ? tr('Загружаем задачи') : tr('Задачи Google пока недоступны')}
              </h3>
              <p>
                {googlePending
                  ? tr(
                      taskDay === 'today'
                        ? 'Проверяем задачи на сегодня.'
                        : 'Проверяем задачи на завтра.',
                    )
                  : tr(
                      'Личные задачи можно добавить ниже. Подключение Google проверь в календаре.',
                    )}
              </p>
              {!googlePending ? (
                <button className="text-button" onClick={onCalendar}>
                  {tr('Открыть календарь')}{' '}
                </button>
              ) : null}
            </div>
          ) : (
            <div className="empty-inline">
              <CheckCheck size={32} />
              <h3>
                {tr(taskDay === 'today' ? 'Пока нет задач на сегодня' : 'Пока нет задач на завтра')}
              </h3>
              <p>{tr('Добавьте первое дело ниже. Встречи и занятия — в расписании справа.')}</p>
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
                  {tr('Подключить Google Tasks')}{' '}
                </button>
              ) : null}
            </div>
          ) : null}
          {googleTaskError ? (
            <p className="error-note" role="alert">
              {googleTaskError}
            </p>
          ) : null}
        </div>
        <div className="panel schedule-panel">
          <div className="section-heading">
            <h2>{tr('Расписание')}</h2>
            <button className="text-button" onClick={onCalendar}>
              {tr('Сегодня')} <ArrowUpRight size={13} />
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
                        ? tr('Завершено')
                        : `${o.startLabel ?? formatTime(o.start)}–${o.endLabel ?? formatTime(o.end)}${o.end === 1440 ? tr(' · следующий день') : ''}${o.source === 'google' ? ' · Google' : ''}`}
                    </span>
                  </button>
                </div>
              ))}
              {schedule.length > 6 ? (
                <button className="text-button" onClick={onCalendar}>
                  {tr('Ещё {count} в календаре', { count: schedule.length - 6 })}
                </button>
              ) : null}
            </div>
          ) : (
            <div className="empty-schedule">
              <CalendarDays size={26} />
              <p>{googleUncertain ? tr('Уточняем расписание') : tr('Свободное расписание')}</p>
              <button
                className="text-button"
                onClick={() => onAI(tr('Найди свободное время в моём расписании на сегодня.'))}
              >
                <Clock3 size={14} /> {tr('Найти удобное время')}{' '}
              </button>
            </div>
          )}
          {combined
            .filter((o) => o.allDay)
            .map((o) => (
              <button key={o.key} className="text-button" onClick={() => openEntry(o)}>
                {tr('Весь день')} · {o.title} · Google
              </button>
            ))}
          {googleUncertain ? (
            <p className="field-hint" role="status">
              {tr(
                'Google Calendar ещё не проверен. Открой календарь, чтобы обновить события.',
              )}{' '}
            </p>
          ) : null}
          <div className="backlog-grid">
            <Backlog title={tr('Без даты')} tasks={undated} onEdit={onEdit} />
            <Backlog title={tr('Просрочено')} tasks={overdue} onEdit={onEdit} />
          </div>
        </div>
      </div>
      <DashboardHabits today={today} onOpen={onHabits} />
      <div className="dashboard-bottom">
        <span>
          <ListTodo size={14} />{' '}
          {todayCompleted === todayCount && todayCount
            ? tr('Все дела завершены. Можно выдохнуть.')
            : tr('Следуйте своему темпу — всё важное перед вами.')}
        </span>
        <button
          className="text-button"
          onClick={() => onAI(tr('Найди свободное время в моём расписании на сегодня.'))}
        >
          <Clock3 size={15} /> {tr('Найти свободное время')}{' '}
        </button>
      </div>
      <div className="ai-dock">
        <button onClick={() => onAI()}>
          <Orb small /> {tr('Спросить ИИ')} <Sparkles size={15} />
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
  const { t: tr } = useI18n();
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
        <p>{tr('Всё в порядке')}</p>
      )}
      {tasks.length > 3 ? (
        <button
          className="backlog-expand"
          onClick={() => setExpanded(!expanded)}
          aria-expanded={expanded}
        >
          {expanded ? tr('Свернуть') : tr('Показать все {count}', { count: tasks.length })}
        </button>
      ) : null}
    </div>
  );
}
