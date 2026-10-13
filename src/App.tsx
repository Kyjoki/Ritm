import { Activity, useCallback, useEffect, useRef, useState } from 'react';
import {
  CalendarDays,
  Check,
  CircleAlert,
  LayoutDashboard,
  LoaderCircle,
  Moon,
  Plus,
  RefreshCw,
  Settings2,
  Sparkles,
  Sun,
  Undo2,
  X,
} from 'lucide-react';
import type {
  Bootstrap,
  Conversation,
  GoogleCalendarEvent,
  GoogleEventInput,
  GoogleTransferResult,
  Settings,
  Task,
  TaskInput,
} from '../shared/types';
import { api, ApiError } from './lib/api';
import { dateInZone, minutesInZone } from './lib/date';
import { addDays, getDayOccurrences, isTimedOccurrence } from './features/calendar-utils';
import { CalendarPage } from './features/CalendarPage';
import { SettingsPage } from './features/SettingsPage';
import { AssistantPage } from './features/AssistantPage';
import { DashboardPage } from './components/DashboardPage';
import { TaskDialog } from './components/TaskDialog';
import { LoginPage } from './features/LoginPage';
import { GoogleEventDialog } from './components/GoogleEventDialog';
import { useGoogleCalendar } from './lib/google-calendar';
import { EventPreviewDialog } from './features/EventPreviewDialog';
import { calendarOccurrences } from './features/google-occurrences';

type Page = 'day' | 'calendar' | 'assistant' | 'settings' | 'login-preview';
const navigation = [
  { id: 'day' as const, label: 'Мой день', icon: LayoutDashboard },
  { id: 'calendar' as const, label: 'Календарь', icon: CalendarDays },
  { id: 'assistant' as const, label: 'ИИ-помощник', icon: Sparkles },
  { id: 'settings' as const, label: 'Настройки', icon: Settings2 },
];
function currentPage(): Page {
  if (new URLSearchParams(window.location.search).get('section') === 'settings') return 'settings';
  const hash = window.location.hash.slice(1);
  if (import.meta.env.DEV && hash === 'login-preview') return 'login-preview';
  return navigation.some((n) => n.id === hash) ? (hash as Page) : 'day';
}
type Toast = { message: string; error?: boolean; undo?: () => Promise<void>; id: number };
export default function App() {
  const [data, setData] = useState<Bootstrap | null>(null),
    [page, setPage] = useState<Page>(currentPage);
  const [requiresLogin, setRequiresLogin] = useState(false),
    [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState('');
  const [taskDialog, setTaskDialog] = useState<{ task?: Task; draft?: Partial<TaskInput> } | null>(
    null,
  );
  const [googleDialog, setGoogleDialog] = useState<{
    event?: GoogleCalendarEvent;
    draft?: Partial<GoogleEventInput>;
  } | null>(null);
  const [googlePreview, setGooglePreview] = useState<{ id: string; date: string } | null>(null);
  const transferRequests = useRef(new Map<string, Promise<GoogleTransferResult>>());
  const failedTransfers = useRef(new Set<string>());
  const migrationRunning = useRef(false);
  const [migrationLoading, setMigrationLoading] = useState(false);
  const [migrationError, setMigrationError] = useState('');
  const [migrationRevision, setMigrationRevision] = useState(0);
  const [toast, setToast] = useState<Toast | null>(null),
    [undoBusy, setUndoBusy] = useState(false),
    [busyIds, setBusyIds] = useState<Set<string>>(new Set());
  const [busyGoogleTaskIds, setBusyGoogleTaskIds] = useState<Set<string>>(new Set());
  const googleTaskRequests = useRef(new Set<string>());
  const [prompt, setPrompt] = useState<string>(),
    [clock, setClock] = useState(() => new Date());
  const [resolvedTheme, setResolvedTheme] = useState<'light' | 'dark'>('light');
  const loadGeneration = useRef(0),
    toastId = useRef(0),
    notified = useRef(new Set<string>());
  const notify = useCallback(
    (message: string, error = false, undo?: () => Promise<void>) =>
      setToast({ message, error, undo, id: ++toastId.current }),
    [],
  );
  const load = useCallback(async () => {
    const generation = ++loadGeneration.current;
    setLoading(true);
    setLoadError('');
    try {
      const session = await api.session();
      if (generation !== loadGeneration.current) return;
      setRequiresLogin(session.requiresLogin);
      if (!session.authenticated) {
        setData(null);
        return;
      }
      const next = await api.bootstrap();
      if (generation === loadGeneration.current) setData(next);
    } catch (e) {
      if (generation === loadGeneration.current)
        setLoadError(e instanceof Error ? e.message : 'Не удалось загрузить Ritm.');
    } finally {
      if (generation === loadGeneration.current) setLoading(false);
    }
  }, []);
  useEffect(() => {
    void load();
    return () => {
      loadGeneration.current++;
    };
  }, [load]);
  useEffect(() => {
    const onHash = () => setPage(currentPage());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);
  useEffect(() => {
    const expired = () => {
      loadGeneration.current++;
      setData(null);
      setRequiresLogin(true);
      setLoading(false);
      setLoadError('');
      setTaskDialog(null);
      setGoogleDialog(null);
      setGooglePreview(null);
      setToast(null);
      failedTransfers.current.clear();
      setMigrationLoading(false);
      setMigrationError('');
    };
    window.addEventListener('ritm:auth-required', expired);
    return () => window.removeEventListener('ritm:auth-required', expired);
  }, []);
  useEffect(() => {
    const timer = window.setInterval(() => setClock(new Date()), 15000);
    return () => clearInterval(timer);
  }, []);
  const theme = data?.settings.theme;
  useEffect(() => {
    if (page === 'login-preview') return;
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const update = () => {
      let selected = theme;
      if (!selected) {
        try {
          const saved = localStorage.getItem('ritm.theme.v1');
          if (['light', 'dark', 'system'].includes(saved ?? ''))
            selected = saved as Settings['theme'];
        } catch {
          /* preferences are optional */
        }
      }
      const resolved =
        selected === 'dark' || (selected === 'system' && media.matches) ? 'dark' : 'light';
      document.documentElement.dataset.theme = resolved;
      setResolvedTheme(resolved);
    };
    update();
    media.addEventListener('change', update);
    if (theme)
      try {
        localStorage.setItem('ritm.theme.v1', theme);
      } catch {
        /* storage may be unavailable */
      }
    return () => media.removeEventListener('change', update);
  }, [theme, page]);
  useEffect(() => {
    document.title = `${page === 'login-preview' ? 'Вход' : navigation.find((n) => n.id === page)?.label} — Ritm`;
  }, [page]);
  useEffect(() => {
    if (!toast) return;
    const timer = setTimeout(
      () => setToast((old) => (old?.id === toast.id ? null : old)),
      toast.undo ? 30000 : toast.error ? 12000 : 5000,
    );
    return () => clearTimeout(timer);
  }, [toast]);
  const today = dateInZone(data?.settings.timeZone ?? 'Asia/Qyzylorda', clock),
    now = minutesInZone(data?.settings.timeZone ?? 'Asia/Qyzylorda', clock);
  const google = useGoogleCalendar(
    Boolean(data),
    data?.settings.timeZone ?? 'Asia/Qyzylorda',
    today,
  );
  const googlePreviewEntry = googlePreview
    ? (calendarOccurrences(
        [],
        google.result?.events ?? [],
        googlePreview.date,
        data?.settings.timeZone ?? 'Asia/Qyzylorda',
      ).find((entry) => entry.source === 'google' && entry.event.id === googlePreview.id) ?? null)
    : null;
  const synchronizeTask = useCallback(
    (id: string) => {
      const pending = transferRequests.current.get(id);
      if (pending) return pending;
      const generation = loadGeneration.current;
      const request = api
        .transferTaskToGoogle(id)
        .then((result) => {
          if (generation === loadGeneration.current) {
            setData((old) =>
              old
                ? {
                    ...old,
                    tasks: old.tasks.filter((task) => task.id !== result.transferredTaskId),
                  }
                : old,
            );
            google.upsertEvent(result.event);
            google.refresh();
          }
          return result;
        })
        .finally(() => transferRequests.current.delete(id));
      transferRequests.current.set(id, request);
      return request;
    },
    [google.upsertEvent, google.refresh],
  );
  useEffect(() => {
    if (!data || google.status.status !== 'connected' || migrationRunning.current) return;
    const records = data.tasks.filter(
      (task) =>
        task.date &&
        task.calendarEntry !== false &&
        !task.completed &&
        !task.completedDates.length &&
        !failedTransfers.current.has(task.id),
    );
    if (!records.length) return;
    const generation = loadGeneration.current;
    migrationRunning.current = true;
    setMigrationLoading(true);
    setMigrationError('');
    void (async () => {
      for (const [index, task] of records.entries()) {
        if (generation !== loadGeneration.current) break;
        try {
          await synchronizeTask(task.id);
        } catch (failure) {
          if (generation !== loadGeneration.current) break;
          failedTransfers.current.add(task.id);
          setMigrationError(
            failure instanceof Error
              ? failure.message
              : 'Не удалось синхронизировать запись. Нажми «Обновить», чтобы повторить.',
          );
          // Pause the whole batch during an outage/auth/rate failure; retry explicitly.
          if (
            !(failure instanceof ApiError) ||
            failure.status === 0 ||
            failure.status === 401 ||
            failure.status === 403 ||
            failure.status === 429 ||
            failure.status >= 500
          ) {
            for (const remaining of records.slice(index + 1))
              failedTransfers.current.add(remaining.id);
            break;
          }
        }
      }
    })().finally(() => {
      migrationRunning.current = false;
      if (generation === loadGeneration.current) {
        setMigrationLoading(false);
      }
      setMigrationRevision((value) => value + 1);
    });
  }, [data, google.status.status, synchronizeTask, migrationRevision]);
  useEffect(() => {
    if (page !== 'calendar') google.setRange(today, addDays(today, 1));
  }, [page, today, google.setRange]);
  useEffect(() => {
    if (!data) return;
    const params = new URLSearchParams(window.location.search);
    const outcome = params.get('google');
    if (!outcome || params.get('section') !== 'settings') return;
    history.replaceState(null, '', `${window.location.pathname}#settings`);
    setPage('settings');
    let active = true;
    void google
      .refreshStatus()
      .then((status) => {
        if (!active) return;
        const connected = outcome === 'connected' && status.status === 'connected';
        notify(
          connected
            ? 'Google Calendar подключён'
            : 'Не удалось подключить Google Calendar. Повтори подключение в настройках.',
          !connected,
        );
      })
      .catch((handle) => {
        if (active)
          notify(
            handle instanceof Error ? handle.message : 'Не удалось проверить Google Calendar.',
            true,
          );
      });
    return () => {
      active = false;
    };
  }, [Boolean(data), notify, google.refreshStatus]);
  useEffect(() => {
    if (
      !data?.settings.notifications ||
      !('Notification' in window) ||
      Notification.permission !== 'granted'
    )
      return;
    const remind = (title: string, body: string, tag: string) => {
      try {
        new Notification(title, { body, icon: '/favicon.svg', tag });
      } catch {
        notify(`${title}: ${body}`);
      }
    };
    for (const o of getDayOccurrences(data.tasks, today).filter(isTimedOccurrence)) {
      const key = `${o.key}:${o.task.updatedAt}`;
      if (
        !o.completed &&
        o.task.time &&
        now >= o.start - 15 &&
        now < o.start - 14 &&
        !notified.current.has(key)
      ) {
        notified.current.add(key);
        remind('Ritm · Через 15 минут', o.task.title, key);
      }
    }
    if (
      data.settings.dailyBriefing &&
      data.settings.workDayStart ===
        `${String(Math.floor(now / 60)).padStart(2, '0')}:${String(now % 60).padStart(2, '0')}` &&
      !notified.current.has(`brief:${today}`)
    ) {
      notified.current.add(`brief:${today}`);
      const count = getDayOccurrences(data.tasks, today).filter((o) => !o.completed).length;
      remind(
        'Ritm · Ваш день',
        `В плане на сегодня: ${count}. Откройте «Мой день», чтобы выбрать первый шаг.`,
        `brief:${today}`,
      );
    }
  }, [data, today, now, notify]);
  const go = useCallback((next: Page) => {
    setPage(next);
    window.location.hash = next;
    window.scrollTo({ top: 0, behavior: 'instant' });
  }, []);
  const handleError = useCallback(
    (error: unknown) => {
      if (error instanceof ApiError && error.code === 'AUTH_REQUIRED') {
        setData(null);
        setRequiresLogin(true);
      }
      notify(error instanceof Error ? error.message : 'Не удалось выполнить действие.', true);
    },
    [notify],
  );
  const putTask = (task: Task) =>
    setData((old) =>
      old
        ? {
            ...old,
            tasks: old.tasks.some((t) => t.id === task.id)
              ? old.tasks.map((t) => (t.id === task.id ? task : t))
              : [...old.tasks, task],
          }
        : old,
    );
  const putConversation = (conversation: Conversation) =>
    setData((old) =>
      old
        ? {
            ...old,
            conversations: old.conversations.some((c) => c.id === conversation.id)
              ? old.conversations.map((c) => (c.id === conversation.id ? conversation : c))
              : [conversation, ...old.conversations],
          }
        : old,
    );
  const saveTask = async (value: TaskInput, id?: string) => {
    if (value.calendarEntry !== false && value.date && google.status.status !== 'connected')
      throw new Error('Подключи Google Calendar в настройках, чтобы назначить дату записи.');
    if (
      value.calendarEntry !== false &&
      value.date &&
      value.colorId?.startsWith('#') &&
      !google.status.extendedColors
    )
      throw new Error(
        'Разреши новые цвета в Настройках → Google Calendar, чтобы сохранить этот оттенок в календаре.',
      );
    const task = id ? await api.updateTask(id, value) : await api.createTask(value);
    putTask(task);
    notify(
      value.calendarEntry !== false && value.date
        ? 'Синхронизируем запись с календарём'
        : id
          ? 'Изменения сохранены'
          : 'Задача добавлена',
    );
  };
  const deleteTask = async (task: Task) => {
    const result = await api.deleteTask(task.id);
    setData((old) => (old ? { ...old, tasks: old.tasks.filter((t) => t.id !== task.id) } : old));
    notify('Задача удалена', false, async () => {
      putTask(await api.restoreTask(result.deletedTask));
      notify('Задача восстановлена');
    });
  };
  const quickAddTask = async (title: string) => {
    const generation = loadGeneration.current;
    const task = await api.createTask({
      title: title.trim(),
      description: '',
      date: today,
      time: null,
      duration: 30,
      priority: 'normal',
      repeat: 'none',
      kind: 'task',
      completed: false,
      calendarEntry: false,
    });
    if (generation === loadGeneration.current) putTask(task);
  };
  const toggleGoogleTask = async (event: GoogleCalendarEvent) => {
    if (!event.googleTask || googleTaskRequests.current.has(event.id)) return;
    const generation = loadGeneration.current;
    googleTaskRequests.current.add(event.id);
    setBusyGoogleTaskIds((old) => new Set(old).add(event.id));
    try {
      const { event: saved } = await api.completeGoogleTask(
        event,
        event.googleTask.status !== 'completed',
      );
      if (generation === loadGeneration.current) {
        google.upsertEvent(saved);
        google.refresh();
      }
    } catch (error) {
      if (generation === loadGeneration.current) google.refresh();
      throw error;
    } finally {
      googleTaskRequests.current.delete(event.id);
      if (generation === loadGeneration.current)
        setBusyGoogleTaskIds((old) => {
          const next = new Set(old);
          next.delete(event.id);
          return next;
        });
    }
  };
  const toggleTask = async (task: Task, occurrenceDate: string, completed: boolean) => {
    if (busyIds.has(task.id)) return;
    setBusyIds((old) => new Set(old).add(task.id));
    try {
      const date = task.repeat === 'none' ? undefined : occurrenceDate;
      const changed = await api.updateTask(task.id, {
        completed: !completed,
        occurrenceDate: date,
      });
      putTask(changed);
      notify(!completed ? 'Задача выполнена' : 'Задача возвращена в план', false, async () => {
        putTask(await api.updateTask(task.id, { completed, occurrenceDate: date }));
        notify('Действие отменено');
      });
    } catch (e) {
      handleError(e);
    } finally {
      setBusyIds((old) => {
        const next = new Set(old);
        next.delete(task.id);
        return next;
      });
    }
  };
  const saveSettings = async (settings: Settings) => {
    const saved = await api.saveSettings(settings);
    setData((old) => (old ? { ...old, settings: saved } : old));
  };
  const ai = useCallback(
    (initial?: string) => {
      setPrompt(initial);
      go('assistant');
    },
    [go],
  );
  const logout = async () => {
    await api.logout();
    loadGeneration.current++;
    setData(null);
    setLoading(false);
    setLoadError('');
    setRequiresLogin(true);
    setToast(null);
    setTaskDialog(null);
    setGoogleDialog(null);
    setGooglePreview(null);
    failedTransfers.current.clear();
    setMigrationLoading(false);
    setMigrationError('');
  };
  const themeToggle = async () => {
    if (!data) return;
    try {
      await saveSettings({ ...data.settings, theme: resolvedTheme === 'dark' ? 'light' : 'dark' });
    } catch (e) {
      handleError(e);
    }
  };
  const runUndo = async () => {
    if (!toast?.undo) return;
    setUndoBusy(true);
    try {
      await toast.undo();
    } catch (e) {
      handleError(e);
    } finally {
      setUndoBusy(false);
    }
  };

  if (page === 'login-preview')
    return <LoginPage preview onSubmit={async () => {}} onBack={() => go('day')} />;
  if (loading && !data)
    return (
      <div className="startup">
        <Brand />
        <div className="startup-card" role="status">
          <div className="skeleton skeleton-title" />
          <div className="skeleton skeleton-line" />
          <div className="skeleton-grid">
            {[0, 1, 2].map((n) => (
              <div key={n} className="skeleton skeleton-card" />
            ))}
          </div>
          <p>
            <LoaderCircle size={18} className="spinning" /> Собираем ваш день…
          </p>
        </div>
      </div>
    );
  if (loadError && !data)
    return (
      <div className="startup">
        <Brand />
        <div className="startup-card startup-error">
          <CircleAlert size={36} />
          <h1>Не удалось загрузить план</h1>
          <p>{loadError}</p>
          <button className="button button-primary" onClick={() => void load()}>
            <RefreshCw size={17} /> Попробовать снова
          </button>
        </div>
      </div>
    );
  if (!data)
    return (
      <LoginPage
        onSubmit={async ({ login, password }) => {
          await api.login(login, password);
          await load();
        }}
      />
    );
  return (
    <div className={`app-shell sidebar-${data.settings.sidebar}`}>
      <a
        className="skip-link"
        href="#main-content"
        onClick={(event) => {
          event.preventDefault();
          document.getElementById('main-content')?.focus();
        }}
      >
        Перейти к содержимому
      </a>
      <aside className="sidebar">
        <button className="brand-button" onClick={() => go('day')} aria-label="Ritm — Мой день">
          <Brand />
        </button>
        <nav className="sidebar-nav" aria-label="Основная навигация">
          {navigation.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              onClick={() => go(id)}
              className={page === id ? 'is-active' : ''}
              aria-current={page === id ? 'page' : undefined}
            >
              <Icon size={18} />
              <span>{label}</span>
              {page === id ? <span className="nav-dot" /> : null}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="sidebar-note">
            <span className="status-dot" />В своём ритме
          </div>
          <button className="profile-button" onClick={() => go('settings')}>
            <span className="avatar">{data.settings.displayName.slice(0, 1).toUpperCase()}</span>
            <span>
              <strong>{data.settings.displayName}</strong>
              <small>Личное пространство</small>
            </span>
            <Settings2 size={15} />
          </button>
        </div>
      </aside>
      <main id="main-content" className="main-content" tabIndex={-1}>
        <div className="workspace-top">
          <div className="workspace-brand">
            <Brand />
          </div>
          <span>ЛИЧНОЕ ПРОСТРАНСТВО</span>
          <button
            className="icon-button theme-switch"
            onClick={() => void themeToggle()}
            aria-label={resolvedTheme === 'dark' ? 'Включить светлую тему' : 'Включить тёмную тему'}
          >
            {resolvedTheme === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
          </button>
        </div>
        <div className="page-container">
          {page === 'day' ? (
            <DashboardPage
              tasks={data.tasks}
              googleEvents={google.result?.events ?? []}
              googleUncertain={
                google.checkingStatus ||
                migrationLoading ||
                Boolean(migrationError) ||
                Boolean(google.error) ||
                google.status.status === 'reauth_required' ||
                (google.status.status === 'connected' &&
                  ((google.loading && !google.result) ||
                    Boolean(google.error) ||
                    !google.result ||
                    google.result.partial))
              }
              googlePending={
                google.checkingStatus ||
                migrationLoading ||
                (google.status.status === 'connected' && !google.result && !google.error)
              }
              onGoogleEdit={(event) => setGooglePreview({ id: event.id, date: today })}
              onGoogleTaskToggle={toggleGoogleTask}
              busyGoogleTaskIds={busyGoogleTaskIds}
              tasksPermissionMessage={google.result?.tasks?.message}
              onEnableGoogleTasks={google.status.tasksEnabled ? undefined : google.connectTasks}
              onQuickAdd={quickAddTask}
              settings={data.settings}
              today={today}
              now={now}
              busyIds={busyIds}
              onEdit={(task) => {
                if (
                  task.date &&
                  task.calendarEntry !== false &&
                  !task.completed &&
                  !task.completedDates.length &&
                  google.status.status === 'connected'
                )
                  void synchronizeTask(task.id)
                    .then((result) => setGoogleDialog({ event: result.event }))
                    .catch(handleError);
                else setTaskDialog({ task });
              }}
              onCreate={(draft) => {
                if (google.status.status !== 'connected') {
                  notify('Подключи Google Calendar в настройках, чтобы добавить запись.', true);
                  go('settings');
                  return;
                }
                setGoogleDialog({
                  draft: {
                    date: draft?.date ?? today,
                    time: draft?.time === null ? null : (draft?.time ?? '09:00'),
                    allDay: draft?.time === null,
                    duration: draft?.duration ?? 30,
                  },
                });
              }}
              onToggle={(task, date, completed) => void toggleTask(task, date, completed)}
              onAI={ai}
              onCalendar={() => go('calendar')}
            />
          ) : null}
          <Activity mode={page === 'calendar' ? 'visible' : 'hidden'}>
            <CalendarPage
              tasks={data.tasks.filter((task) => !task.date)}
              today={today}
              timeZone={data.settings.timeZone}
              onEdit={(task) => setTaskDialog({ task })}
              onCreate={() => {
                notify('Подключи Google Calendar в настройках, чтобы добавить запись.', true);
                go('settings');
              }}
              googleStatus={google.status}
              googleEvents={google.result?.events ?? []}
              googleLoading={google.checkingStatus || google.loading || migrationLoading}
              googleError={google.error || migrationError}
              googlePartial={google.result?.partial ?? false}
              googleFetchedAt={google.result?.fetchedAt ?? null}
              onGoogleEdit={(event) => setGoogleDialog({ event })}
              onGoogleTaskToggle={toggleGoogleTask}
              busyGoogleTaskIds={busyGoogleTaskIds}
              onEnableGoogleTasks={google.status.tasksEnabled ? undefined : google.connectTasks}
              onGoogleCreate={(draft) => setGoogleDialog({ draft })}
              onRangeChange={google.setRange}
              onGoogleRefresh={() => {
                failedTransfers.current.clear();
                setMigrationError('');
                setMigrationRevision((value) => value + 1);
                google.refresh();
              }}
              onOpenSettings={() => go('settings')}
            />
          </Activity>
          <Activity mode={page === 'assistant' ? 'visible' : 'hidden'}>
            <AssistantPage
              conversations={data.conversations}
              aiStatus={data.aiStatus}
              onCreate={async () => {
                const c = await api.createConversation();
                putConversation(c);
                return c;
              }}
              onDelete={async (id) => {
                await api.deleteConversation(id);
                setData((old) =>
                  old
                    ? { ...old, conversations: old.conversations.filter((c) => c.id !== id) }
                    : old,
                );
              }}
              onSend={async (id, message, requestId) => {
                const c = await api.chat(id, message, requestId);
                putConversation(c);
                return c;
              }}
              onApply={async (conversationId, messageId, proposalIds) => {
                const result = await api.proposals('apply', conversationId, messageId, proposalIds);
                setData((old) =>
                  old
                    ? {
                        ...old,
                        tasks: result.tasks,
                        conversations: old.conversations.map((c) =>
                          c.id === result.conversation.id ? result.conversation : c,
                        ),
                      }
                    : old,
                );
                notify('Выбранные изменения применены');
              }}
              onReject={async (c, m, ids) => {
                putConversation(await api.reject(c, m, ids));
              }}
              onUndo={async (c, m, ids) => {
                const result = await api.proposals('undo', c, m, ids);
                setData((old) =>
                  old
                    ? {
                        ...old,
                        tasks: result.tasks,
                        conversations: old.conversations.map((v) =>
                          v.id === result.conversation.id ? result.conversation : v,
                        ),
                      }
                    : old,
                );
                notify('Изменения расписания отменены');
              }}
              onOpenSettings={() => go('settings')}
              initialPrompt={prompt}
              onPromptConsumed={() => setPrompt(undefined)}
            />
          </Activity>
          <Activity mode={page === 'settings' ? 'visible' : 'hidden'}>
            <SettingsPage
              settings={data.settings}
              aiStatus={data.aiStatus}
              googleStatus={google.status}
              onConnectGoogle={google.connect}
              onConnectGoogleTasks={google.connectTasks}
              googleTasksMessage={google.result?.tasks?.message}
              onDisconnectGoogle={google.disconnect}
              onGoogleConfigured={async () => {
                await google.refreshStatus();
              }}
              onSave={saveSettings}
              onConfigureAI={async (key, model) => {
                const aiStatus = await api.configureAI(key, model);
                setData((old) => (old ? { ...old, aiStatus } : old));
              }}
              onDisconnectAI={async () => {
                const aiStatus = await api.disconnectAI();
                setData((old) => (old ? { ...old, aiStatus } : old));
              }}
              onLogout={requiresLogin ? logout : undefined}
            />
          </Activity>
        </div>
        <footer className="app-footer">
          <span>Ritm</span>
          <span>Меньше шума. Больше ясности.</span>
        </footer>
      </main>
      <nav className="mobile-nav" aria-label="Основная мобильная навигация">
        {navigation.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => go(id)}
            className={page === id ? 'is-active' : ''}
            aria-current={page === id ? 'page' : undefined}
          >
            <Icon size={21} />
            <span>{label}</span>
          </button>
        ))}
      </nav>
      {taskDialog ? (
        <TaskDialog
          {...taskDialog}
          onClose={() => setTaskDialog(null)}
          onSave={saveTask}
          onDelete={deleteTask}
        />
      ) : null}
      {googlePreview ? (
        <EventPreviewDialog
          entry={googlePreviewEntry}
          date={googlePreview.date}
          timeZone={data.settings.timeZone}
          onClose={() => setGooglePreview(null)}
          onEdit={(entry) => {
            setGooglePreview(null);
            if (entry.source === 'google') setGoogleDialog({ event: entry.event });
          }}
          onGoogleTaskToggle={toggleGoogleTask}
          taskBusy={busyGoogleTaskIds.has(googlePreview.id)}
          onEnableGoogleTasks={google.status.tasksEnabled ? undefined : google.connectTasks}
        />
      ) : null}
      {googleDialog ? (
        <GoogleEventDialog
          {...googleDialog}
          extendedColorsEnabled={google.status.extendedColors ?? false}
          onEnableExtendedColors={() => google.connect(true)}
          timeZone={data.settings.timeZone}
          onClose={() => {
            setGoogleDialog(null);
            google.refresh();
          }}
          onSave={async (input, requestId, event) => {
            const saved = event
              ? await api.updateGoogleEvent(event.id, input, event.etag)
              : await api.createGoogleEvent(input, requestId);
            google.upsertEvent(saved);
            google.refresh();
            notify(event ? 'Изменения синхронизированы' : 'Запись добавлена в календарь');
          }}
          onDelete={async (event) => {
            await api.deleteGoogleEvent(event.id, event.etag);
            google.removeEvent(event.id);
            google.refresh();
            notify('Запись удалена из календаря');
          }}
        />
      ) : null}
      {toast ? (
        <div
          className={`toast${toast.error ? ' toast-error' : ''}`}
          role={toast.error ? 'alert' : 'status'}
        >
          {toast.error ? <CircleAlert size={18} /> : <Check size={18} />}
          <span>{toast.message}</span>
          {toast.undo ? (
            <button disabled={undoBusy} onClick={() => void runUndo()}>
              {undoBusy ? <LoaderCircle size={15} className="spinning" /> : <Undo2 size={15} />}
              Отменить
            </button>
          ) : null}
          <button
            className="toast-close"
            onClick={() => setToast(null)}
            aria-label="Закрыть уведомление"
          >
            <X size={16} />
          </button>
        </div>
      ) : null}
    </div>
  );
}
function Brand() {
  return (
    <span className="brand">
      <span className="brand-mark" aria-hidden="true">
        <img src="/ritm-mark.svg" width="36" height="36" alt="" />
      </span>
      Ritm
    </span>
  );
}
