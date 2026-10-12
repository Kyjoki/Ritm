import { useState, type CSSProperties } from 'react';
import {
  ArrowUpRight,
  CalendarDays,
  Check,
  CheckCheck,
  CirclePlus,
  Clock3,
  ListTodo,
  Sparkles,
} from 'lucide-react';
import type { Settings, Task, TaskInput } from '../../shared/types';
import { getDayOccurrences, isTimedOccurrence } from '../features/calendar-utils';
import { durationText, formatDate, formatTime, greeting } from '../lib/date';
import { Orb } from './Orb';

interface Props {
  tasks: Task[];
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
  const occurrences = getDayOccurrences(tasks, today);
  const todayEntries = occurrences.sort(
    (a, b) => Number(a.completed) - Number(b.completed) || (a.start ?? 1441) - (b.start ?? 1441),
  );
  const completed = todayEntries.filter((t) => t.completed).length;
  const upcoming = occurrences
    .filter(isTimedOccurrence)
    .filter((o) => !o.completed && o.end > now)
    .sort((a, b) => a.start - b.start)[0];
  const schedule = occurrences.filter(isTimedOccurrence).sort((a, b) => a.start - b.start);
  const undated = tasks.filter((t) => !t.date && !t.completed),
    overdue = tasks.filter((t) => t.date && t.date < today && !t.completed && t.repeat === 'none');
  const workStart =
      Number(settings.workDayStart.slice(0, 2)) * 60 + Number(settings.workDayStart.slice(3)),
    workEnd = Number(settings.workDayEnd.slice(0, 2)) * 60 + Number(settings.workDayEnd.slice(3));
  const intervals = schedule
    .filter((o) => !o.completed)
    .map((o) => [Math.max(workStart, o.start, now), Math.min(workEnd, o.end)])
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
          <CirclePlus size={18} /> Добавить задачу
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
                  '--progress': `${todayEntries.length ? (completed / todayEntries.length) * 360 : 0}deg`,
                } as CSSProperties
              }
            >
              <Sparkles size={19} />
            </div>
            <div>
              <strong>
                {completed} из {todayEntries.length}
              </strong>
              <span>задач выполнено</span>
            </div>
          </div>
          <p className="card-footnote">
            {free
              ? `Свободно ${durationText(free)}`
              : now >= workEnd
                ? 'Рабочий день завершён'
                : 'Всё время уже в плане'}
          </p>
        </div>
        <button
          className="panel focus-card"
          onClick={() => (upcoming ? onEdit(upcoming.task) : onCalendar())}
        >
          <span className="card-eyebrow">
            {upcoming && upcoming.start <= now ? 'Сейчас в плане' : 'Ближайшее событие'}
          </span>
          <strong className="focus-time">
            {upcoming ? formatTime(upcoming.start) : 'Без спешки'}
          </strong>
          <span className="focus-name">{upcoming?.task.title ?? 'Впереди свободное время'}</span>
          <span className="focus-meta">
            {upcoming
              ? `${durationText(upcoming.task.duration)} · ${upcoming.task.kind === 'event' ? 'Событие' : 'Задача'}`
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
            <span>{todayEntries.length} в плане</span>
          </div>
          {todayEntries.length ? (
            <div className="today-list">
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
                      <span className="task-checkbox">
                        {o.completed ? <Check size={14} strokeWidth={3} /> : null}
                      </span>
                    </button>
                    <button className="task-copy" onClick={() => onEdit(task)}>
                      <span className="task-title">{task.title}</span>
                      <span className="task-meta">
                        {task.kind === 'event' ? 'Событие' : 'Задача'}
                        {task.priority === 'high'
                          ? ' · Высокий приоритет'
                          : task.priority === 'low'
                            ? ' · Низкий приоритет'
                            : ' · Обычный приоритет'}
                        {` · ${durationText(task.duration)}`}
                        {task.repeat !== 'none' ? ' · Повторяется' : ''}
                      </span>
                    </button>
                    <time>{o.start === null ? 'Без времени' : formatTime(o.start)}</time>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="empty-inline">
              <CheckCheck size={32} />
              <h3>Сегодня — чистый лист</h3>
              <p>Добавьте первое дело и задайте ритм дню.</p>
              <button className="button button-secondary" onClick={() => onCreate({ date: today })}>
                Добавить задачу
              </button>
            </div>
          )}
          <button className="text-button list-footer" onClick={() => onCreate({ date: today })}>
            <CirclePlus size={16} /> Добавить ещё одну задачу
          </button>
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
                    onClick={() => onEdit(o.task)}
                  >
                    <strong>{o.task.title}</strong>
                    <span>
                      {o.completed
                        ? 'Завершено'
                        : `${formatTime(o.start)}–${formatTime(o.end)}${o.end === 1440 ? ' · следующий день' : ''}`}
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
              <p>Свободное расписание</p>
              <button
                className="text-button"
                onClick={() => onAI('Найди свободное время в моём расписании на сегодня.')}
              >
                <Clock3 size={14} /> Найти удобное время
              </button>
            </div>
          )}
          <div className="backlog-grid">
            <Backlog title="Без даты" tasks={undated} onEdit={onEdit} />
            <Backlog title="Просрочено" tasks={overdue} onEdit={onEdit} />
          </div>
        </div>
      </div>
      <div className="dashboard-bottom">
        <span>
          <ListTodo size={14} />{' '}
          {completed === todayEntries.length && todayEntries.length
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
