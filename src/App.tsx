import { Activity, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { flushSync } from 'react-dom';
import {
  CalendarDays,
  Check,
  CircleAlert,
  Dumbbell,
  LayoutDashboard,
  ListChecks,
  LoaderCircle,
  Moon,
  MoreHorizontal,
  WalletCards,
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
import { useI18n, getLanguage, translate } from './lib/i18n';
import { dateInZone, minutesInZone } from './lib/date';
import { revealTheme } from './lib/theme-reveal';
import { addDays, getDayOccurrences, isTimedOccurrence } from './features/calendar-utils';
import { CalendarPage } from './features/CalendarPage';
import { SettingsPage } from './features/SettingsPage';
import { AssistantPage } from './features/AssistantPage';
import { DashboardPage } from './components/DashboardPage';
import { FinancePage } from './features/FinancePage';
import { HabitsPage } from './features/HabitsPage';
import { WorkoutsPage } from './features/WorkoutsPage';
import { TaskDialog } from './components/TaskDialog';
import { LoginPage } from './features/LoginPage';
import { GoogleEventDialog } from './components/GoogleEventDialog';
import { useGoogleCalendar } from './lib/google-calendar';
import { EventPreviewDialog } from './features/EventPreviewDialog';
import { Dialog } from './components/Dialog';
import './styles/visual-refresh.css';
import './styles/motion.css';
import './styles/navigation-glass.css';
import './styles/desktop-shell.css';
import { MotionControls, MotionPage, MotionPresence } from './components/Motion';
import {
  calendarOccurrences,
  canEditGoogleEvent,
  googleEventDraft,
} from './features/google-occurrences';

const EMPTY_GOOGLE_EVENTS: GoogleCalendarEvent[] = [];

type Page =
  | 'day'
  | 'calendar'
  | 'habits'
  | 'assistant'
  | 'finance'
  | 'workouts'
  | 'settings'
  | 'login-preview';
const SIDEBAR_ORDER = [
  'day',
  'calendar',
  'habits',
  'finance',
  'assistant',
  'workouts',
  'settings',
] as const;
const navigation = [
  { id: 'day' as const, label: 'Мой день', icon: LayoutDashboard },
  { id: 'calendar' as const, label: 'Календарь', icon: CalendarDays },
  { id: 'habits' as const, label: 'Привычки', icon: ListChecks },
  { id: 'assistant' as const, label: 'ИИ-помощник', icon: Sparkles },
  { id: 'finance' as const, label: 'Финансы', icon: WalletCards },
  { id: 'workouts' as const, label: 'Тренировки', icon: Dumbbell },
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
  const { language, t: tr, setLanguage } = useI18n();
  const [data, setData] = useState<Bootstrap | null>(null),
    [page, setPage] = useState<Page>(currentPage);
  const sidebarScroll = useRef<HTMLDivElement>(null);
  const hasData = Boolean(data);
  useEffect(() => {
    const container = sidebarScroll.current;
    if (!container) return;
    const revealActive = () => {
      const active = container.querySelector<HTMLElement>('[aria-current="page"]');
      if (!active || container.scrollHeight <= container.clientHeight) return;
      const bounds = container.getBoundingClientRect();
      const item = active.getBoundingClientRect();
      const scale = bounds.height / container.offsetHeight || 1;
      if (item.top < bounds.top + 4 * scale)
        container.scrollTop -= (bounds.top + 4 * scale - item.top) / scale;
      else if (item.bottom > bounds.bottom - 4 * scale)
        container.scrollTop += (item.bottom - bounds.bottom + 4 * scale) / scale;
    };
    revealActive();
    window.addEventListener('resize', revealActive);
    return () => window.removeEventListener('resize', revealActive);
  }, [page, hasData]);
  const pageRef = useRef(page);
  const visitedPages = useRef(new Set<Page>());
  const [pageVisit, setPageVisit] = useState<'first' | 'return'>('first');
  const activatePage = useCallback((next: Page) => {
    if (pageRef.current === next) return;
    visitedPages.current.add(pageRef.current);
    pageRef.current = next;
    setPageVisit(visitedPages.current.has(next) ? 'return' : 'first');
    setPage(next);
  }, []);
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
  const [previewTheme, setPreviewTheme] = useState<'light' | 'dark' | null>(() => {
    if (!import.meta.env.DEV) return null;
    const value = new URLSearchParams(window.location.search).get('previewTheme');
    return value === 'light' || value === 'dark' ? value : null;
  });
  const visualPreview =
    import.meta.env.DEV && new URLSearchParams(window.location.search).has('design-preview');
  const calendarTasks = useMemo(
    () =>
      data?.tasks.filter((task) => !task.date || (visualPreview && task.calendarEntry !== false)) ??
      [],
    [data?.tasks, visualPreview],
  );
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
      if (generation === loadGeneration.current) {
        setLanguage(next.settings.language);
        setData(next);
      }
    } catch (e) {
      if (generation === loadGeneration.current)
        setLoadError(
          e instanceof Error ? e.message : translate(getLanguage(), 'Не удалось загрузить Ritm.'),
        );
    } finally {
      if (generation === loadGeneration.current) setLoading(false);
    }
  }, [setLanguage]);
  useEffect(() => {
    if (data) setLanguage(data.settings.language);
  }, [data?.settings.language, setLanguage]);
  useEffect(() => {
    void load();
    return () => {
      loadGeneration.current++;
    };
  }, [load]);
  useEffect(() => {
    const onHash = () => activatePage(currentPage());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, [activatePage]);
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
    let timer = 0;
    const update = () => {
      window.clearTimeout(timer);
      const backgroundNotifications =
        data?.settings.notifications &&
        'Notification' in window &&
        Notification.permission === 'granted';
      if (document.hidden && !backgroundNotifications) return;
      const current = new Date();
      setClock((previous) =>
        Math.floor(previous.getTime() / 60_000) === Math.floor(current.getTime() / 60_000)
          ? previous
          : current,
      );
      timer = window.setTimeout(update, document.hidden ? 15_000 : 60_000 - (Date.now() % 60_000));
    };
    update();
    document.addEventListener('visibilitychange', update);
    window.addEventListener('pageshow', update);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener('visibilitychange', update);
      window.removeEventListener('pageshow', update);
    };
  }, [data?.settings.notifications]);
  const theme = data?.settings.theme;
  const themeShown = useRef(false);
  const applyTheme = useCallback((next: 'light' | 'dark', trigger?: Element | null) => {
    const root = document.documentElement;
    const apply = () => {
      root.dataset.theme = next;
      setResolvedTheme(next);
    };
    const changed = themeShown.current && root.dataset.theme !== next;
    themeShown.current = true;
    if (changed) revealTheme(apply, trigger);
    else apply();
  }, []);
  useEffect(() => {
    if (page === 'login-preview') return;
    if (previewTheme) {
      applyTheme(previewTheme);
      return;
    }
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
      applyTheme(resolved);
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
  }, [theme, page, previewTheme, applyTheme]);
  useEffect(() => {
    document.title = `${tr(page === 'login-preview' ? tr('Вход') : (navigation.find((n) => n.id === page)?.label ?? tr('Мой день')))} — Ritm`;
  }, [page, tr]);
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
        google.result?.events ?? EMPTY_GOOGLE_EVENTS,
        googlePreview.date,
        data?.settings.timeZone ?? 'Asia/Qyzylorda',
        language,
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
              : tr('Не удалось синхронизировать запись. Нажми «Обновить», чтобы повторить.'),
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
    if (page !== 'calendar') google.setRange(today, addDays(today, page === 'day' ? 2 : 1));
  }, [page, today, google.setRange]);
  useEffect(() => {
    if (!data) return;
    const params = new URLSearchParams(window.location.search);
    const outcome = params.get('google');
    if (!outcome || params.get('section') !== 'settings') return;
    history.replaceState(null, '', `${window.location.pathname}#settings`);
    activatePage('settings');
    let active = true;
    void google
      .refreshStatus()
      .then((status) => {
        if (!active) return;
        const connected = outcome === 'connected' && status.status === 'connected';
        notify(
          connected
            ? tr('Google Calendar подключён')
            : tr('Не удалось подключить Google Calendar. Повтори подключение в настройках.'),
          !connected,
        );
      })
      .catch((handle) => {
        if (active)
          notify(
            handle instanceof Error ? handle.message : tr('Не удалось проверить Google Calendar.'),
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
    for (const o of getDayOccurrences(data.tasks, today, language).filter(isTimedOccurrence)) {
      const key = `${o.key}:${o.task.updatedAt}`;
      if (
        !o.completed &&
        o.task.time &&
        now >= o.start - 15 &&
        now < o.start - 14 &&
        !notified.current.has(key)
      ) {
        notified.current.add(key);
        remind(tr('Ritm · Через 15 минут'), o.task.title, key);
      }
    }
    if (
      data.settings.dailyBriefing &&
      data.settings.workDayStart ===
        `${String(Math.floor(now / 60)).padStart(2, '0')}:${String(now % 60).padStart(2, '0')}` &&
      !notified.current.has(`brief:${today}`)
    ) {
      notified.current.add(`brief:${today}`);
      const count = getDayOccurrences(data.tasks, today, language).filter(
        (o) => !o.completed,
      ).length;
      remind(
        tr('Ritm · Ваш день'),
        tr('В плане на сегодня: {count}. Откройте «Мой день», чтобы выбрать первый шаг.', {
          count,
        }),
        `brief:${today}`,
      );
    }
  }, [data, today, now, notify, tr, language]);
  const go = useCallback(
    (next: Page) => {
      activatePage(next);
      window.location.hash = next;
      window.scrollTo({ top: 0, behavior: 'instant' });
    },
    [activatePage],
  );
  const handleError = useCallback(
    (error: unknown) => {
      if (error instanceof ApiError && error.code === 'AUTH_REQUIRED') {
        setData(null);
        setRequiresLogin(true);
      }
      notify(error instanceof Error ? error.message : tr('Не удалось выполнить действие.'), true);
    },
    [notify, tr],
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
      throw new Error(tr('Подключи Google Calendar в настройках, чтобы назначить дату записи.'));
    if (
      value.calendarEntry !== false &&
      value.date &&
      value.colorId?.startsWith('#') &&
      !google.status.extendedColors
    )
      throw new Error(
        tr(
          'Разреши новые цвета в Настройках → Google Calendar, чтобы сохранить этот оттенок в календаре.',
        ),
      );
    const task = id ? await api.updateTask(id, value) : await api.createTask(value);
    putTask(task);
    notify(
      value.calendarEntry !== false && value.date
        ? tr('Синхронизируем запись с календарём')
        : id
          ? tr('Изменения сохранены')
          : tr('Задача добавлена'),
    );
  };
  const deleteTask = async (task: Task) => {
    const result = await api.deleteTask(task.id);
    setData((old) => (old ? { ...old, tasks: old.tasks.filter((t) => t.id !== task.id) } : old));
    notify(tr('Задача удалена'), false, async () => {
      putTask(await api.restoreTask(result.deletedTask));
      notify(tr('Задача восстановлена'));
    });
  };
  const quickAddTask = async (title: string, date: string) => {
    const generation = loadGeneration.current;
    const task = await api.createTask({
      title: title.trim(),
      description: '',
      date,
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
      notify(
        !completed ? tr('Задача выполнена') : tr('Задача возвращена в план'),
        false,
        async () => {
          putTask(await api.updateTask(task.id, { completed, occurrenceDate: date }));
          notify(tr('Действие отменено'));
        },
      );
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
  const themeToggle = async (trigger: Element) => {
    if (previewTheme) {
      setPreviewTheme(previewTheme === 'dark' ? 'light' : 'dark');
      return;
    }
    if (!data) return;
    const next = resolvedTheme === 'dark' ? 'light' : 'dark';
    applyTheme(next, trigger);
    try {
      await saveSettings({ ...data.settings, theme: next });
    } catch (e) {
      applyTheme(resolvedTheme, trigger);
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
            <LoaderCircle size={18} className="spinning" /> {tr('Собираем ваш день…')}{' '}
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
          <h1>{tr('Не удалось загрузить план')}</h1>
          <p>{loadError}</p>
          <button className="button button-primary" onClick={() => void load()}>
            <RefreshCw size={17} /> {tr('Попробовать снова')}{' '}
          </button>
        </div>
      </div>
    );
  if (!data)
    return (
      <LoginPage
        onSubmit={async ({ login, password, totp, recoveryCode }) => {
          await api.login(login, password, { totp, recoveryCode });
          await load();
        }}
      />
    );
  return (
    <div className={`app-shell ritm-glass motion-v2 sidebar-${data.settings.sidebar}`}>
      <MotionControls />
      {visualPreview ? (
        <div className="visual-preview-badge">{tr('Локальный preview · демоданные')}</div>
      ) : null}
      <a
        className="skip-link"
        href="#main-content"
        onClick={(event) => {
          event.preventDefault();
          document.getElementById('main-content')?.focus();
        }}
      >
        {tr('Перейти к содержимому')}{' '}
      </a>
      <aside className="sidebar">
        <button
          className="brand-button"
          onClick={() => go('day')}
          aria-label={tr('Ritm — Мой день')}
        >
          <Brand />
        </button>
        <div className="sidebar-nav-scroll" ref={sidebarScroll}>
          <nav className="sidebar-nav" aria-label={tr('Основная навигация')}>
            {SIDEBAR_ORDER.map((order) => navigation.find((item) => item.id === order)!).map(
              ({ id, label, icon: Icon }) => (
                <button
                  key={id}
                  onClick={() => go(id)}
                  className={page === id ? 'is-active' : ''}
                  aria-current={page === id ? 'page' : undefined}
                  data-tooltip={tr(label)}
                  aria-label={tr(label)}
                >
                  <span className="nav-button-content">
                    <Icon size={18} aria-hidden="true" />
                    <span className="nav-label">{tr(label)}</span>
                  </span>
                  {page === id ? <span className="nav-dot" /> : null}
                </button>
              ),
            )}
          </nav>
        </div>
        <div className="sidebar-bottom">
          <div className="sidebar-note">
            <span className="status-dot" />
            {tr('В своём ритме')}{' '}
          </div>
          <button
            className="profile-button"
            onClick={() => go('settings')}
            aria-label={`${data.settings.displayName} · ${tr('Настройки')}`}
            data-tooltip={`${data.settings.displayName} · ${tr('Настройки')}`}
          >
            <span className="avatar">{data.settings.displayName.slice(0, 1).toUpperCase()}</span>
            <span>
              <strong>{data.settings.displayName}</strong>
              <small>{tr('Личное пространство')}</small>
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
          <span>{tr('ЛИЧНОЕ ПРОСТРАНСТВО')}</span>
          <p className="dtop-title gradient-title" aria-hidden="true">
            {tr(navigation.find((item) => item.id === page)?.label ?? 'Мой день')}
          </p>
          <button
            className="icon-button theme-switch"
            data-theme-toggle=""
            onClick={(event) => void themeToggle(event.currentTarget)}
            aria-label={
              resolvedTheme === 'dark' ? tr('Включить светлую тему') : tr('Включить тёмную тему')
            }
          >
            {resolvedTheme === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
          </button>
        </div>
        <div className="page-container" data-page={page} data-visit={pageVisit}>
          <Activity mode={page === 'day' ? 'visible' : 'hidden'}>
            {(page === 'day' || visitedPages.current.has('day')) && (
              <MotionPage name="day">
                <DashboardPage
                  tasks={data.tasks}
                  googleEvents={google.result?.events ?? EMPTY_GOOGLE_EVENTS}
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
                  onGoogleEdit={(event, date) => setGooglePreview({ id: event.id, date })}
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
                      notify(
                        tr('Подключи Google Calendar в настройках, чтобы добавить запись.'),
                        true,
                      );
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
                  onHabits={() => go('habits')}
                />
              </MotionPage>
            )}
          </Activity>
          <Activity mode={page === 'calendar' ? 'visible' : 'hidden'}>
            {(page === 'calendar' || visitedPages.current.has('calendar')) && (
              <MotionPage name="calendar">
                <CalendarPage
                  tasks={calendarTasks}
                  today={today}
                  timeZone={data.settings.timeZone}
                  onEdit={(task) => setTaskDialog({ task })}
                  onCreate={() => {
                    notify(
                      tr('Подключи Google Calendar в настройках, чтобы добавить запись.'),
                      true,
                    );
                    go('settings');
                  }}
                  googleStatus={google.status}
                  googleEvents={google.result?.events ?? EMPTY_GOOGLE_EVENTS}
                  googleLoading={google.checkingStatus || google.loading || migrationLoading}
                  googleError={google.error || migrationError}
                  googlePartial={google.result?.partial ?? false}
                  googleFetchedAt={google.result?.fetchedAt ?? null}
                  onGoogleEdit={(event) => setGoogleDialog({ event })}
                  onGoogleMove={async (event, date, time) => {
                    try {
                      if (
                        !canEditGoogleEvent(event, data.settings.timeZone) ||
                        event.taskLink ||
                        event.googleTask ||
                        event.allDay !== (time === null)
                      )
                        throw new Error(
                          tr('Эту запись нельзя перетащить. Открой её для просмотра.'),
                        );
                      const input = {
                        ...googleEventDraft(event, data.settings.timeZone),
                        date,
                        time,
                      };
                      const saved = await api.updateGoogleEvent(event.id, input, event.etag);
                      google.upsertEvent(saved);
                      google.refresh();
                      notify(tr('Запись перенесена в календаре'));
                    } catch (error) {
                      handleError(error);
                      google.refresh();
                    }
                  }}
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
              </MotionPage>
            )}
          </Activity>
          <Activity mode={page === 'assistant' ? 'visible' : 'hidden'}>
            {(page === 'assistant' || visitedPages.current.has('assistant')) && (
              <MotionPage name="assistant">
                <AssistantPage
                  active={page === 'assistant'}
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
                  onSend={async (id, message, requestId, mode, reviewMessageId) => {
                    try {
                      const c = await api.chat(id, message, requestId, mode, reviewMessageId);
                      putConversation(c);
                      return c;
                    } catch (failure) {
                      if (failure instanceof ApiError && failure.code === 'AI_DISCUSSION_STALE') {
                        try {
                          const fresh = await api.bootstrap();
                          setData((old) =>
                            old ? { ...old, conversations: fresh.conversations } : old,
                          );
                        } catch {
                          // Preserve the failed reply; the user can reload if history is unavailable.
                        }
                      }
                      throw failure;
                    }
                  }}
                  onApply={async (conversationId, messageId, proposalIds) => {
                    const result = await api.proposals(
                      'apply',
                      conversationId,
                      messageId,
                      proposalIds,
                    );
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
                    notify(tr('Выбранные изменения применены'));
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
                    notify(tr('Изменения расписания отменены'));
                  }}
                  onOpenSettings={() => go('settings')}
                  initialPrompt={prompt}
                  onPromptConsumed={() => setPrompt(undefined)}
                />
              </MotionPage>
            )}
          </Activity>
          <Activity mode={page === 'finance' ? 'visible' : 'hidden'}>
            {(page === 'finance' || visitedPages.current.has('finance')) && (
              <MotionPage name="finance">
                <FinancePage
                  active={page === 'finance'}
                  today={`${clock.getFullYear()}-${String(clock.getMonth() + 1).padStart(2, '0')}-${String(clock.getDate()).padStart(2, '0')}`}
                />
              </MotionPage>
            )}
          </Activity>
          <Activity mode={page === 'habits' ? 'visible' : 'hidden'}>
            {(page === 'habits' || visitedPages.current.has('habits')) && (
              <MotionPage name="habits">
                <HabitsPage
                  active={page === 'habits'}
                  timeZone={data.settings.timeZone}
                  today={today}
                />
              </MotionPage>
            )}
          </Activity>
          <Activity mode={page === 'workouts' ? 'visible' : 'hidden'}>
            {(page === 'workouts' || visitedPages.current.has('workouts')) && (
              <MotionPage name="workouts">
                <WorkoutsPage
                  active={page === 'workouts'}
                  timeZone={data.settings.timeZone}
                  today={today}
                  onNotify={notify}
                />
              </MotionPage>
            )}
          </Activity>
          <Activity mode={page === 'settings' ? 'visible' : 'hidden'}>
            {(page === 'settings' || visitedPages.current.has('settings')) && (
              <MotionPage name="settings">
                <SettingsPage
                  active={page === 'settings'}
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
              </MotionPage>
            )}
          </Activity>
        </div>
        <footer className="app-footer">
          <span>Ritm</span>
          <span>{tr('Меньше шума. Больше ясности.')}</span>
        </footer>
      </main>
      <MobileNavigation page={page} onNavigate={go} />
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
            notify(event ? tr('Изменения синхронизированы') : tr('Запись добавлена в календарь'));
          }}
          onDelete={async (event) => {
            await api.deleteGoogleEvent(event.id, event.etag);
            google.removeEvent(event.id);
            google.refresh();
            notify(tr('Запись удалена из календаря'));
          }}
        />
      ) : null}
      <MotionPresence>
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
                {tr('Отменить')}{' '}
              </button>
            ) : null}
            <button
              className="toast-close"
              onClick={() => setToast(null)}
              aria-label={tr('Закрыть уведомление')}
            >
              <X size={16} />
            </button>
          </div>
        ) : null}
      </MotionPresence>
    </div>
  );
}
function MobileNavigation({ page, onNavigate }: { page: Page; onNavigate: (page: Page) => void }) {
  const { t: tr } = useI18n();
  const [moreOpen, setMoreOpen] = useState(false);
  const overflowItems = navigation.filter(
    ({ id }) => id === 'finance' || id === 'workouts' || id === 'settings',
  );
  const currentOverflow = overflowItems.find(({ id }) => id === page);
  useEffect(() => {
    setMoreOpen(false);
  }, [page]);
  useEffect(() => {
    const desktop = window.matchMedia('(min-width: 761px)');
    const closeOnDesktop = () => {
      if (desktop.matches) setMoreOpen(false);
    };
    desktop.addEventListener('change', closeOnDesktop);
    return () => desktop.removeEventListener('change', closeOnDesktop);
  }, []);
  return (
    <>
      <nav className="mobile-nav" aria-label={tr('Основная мобильная навигация')}>
        {navigation.slice(0, 4).map(({ id, label, icon: Icon }) => (
          <button
            type="button"
            key={id}
            onClick={() => onNavigate(id)}
            className={page === id ? 'is-active' : ''}
            aria-current={page === id ? 'page' : undefined}
          >
            <span className="nav-button-content">
              <Icon size={21} aria-hidden="true" />
              <span className="nav-label">{tr(label)}</span>
            </span>
          </button>
        ))}
        <button
          type="button"
          className={currentOverflow ? 'is-active' : ''}
          aria-haspopup="dialog"
          aria-expanded={moreOpen}
          aria-label={
            currentOverflow
              ? tr('Ещё разделы. Сейчас открыт: {section}', { section: tr(currentOverflow.label) })
              : tr('Ещё разделы')
          }
          onClick={() => setMoreOpen(true)}
        >
          <span className="nav-button-content">
            <MoreHorizontal size={21} aria-hidden="true" />
            <span className="nav-label">{tr(currentOverflow?.label ?? 'Ещё')}</span>
          </span>
        </button>
      </nav>
      {moreOpen ? (
        <Dialog
          title={tr('Ещё разделы')}
          className="navigation-more-dialog"
          onClose={() => setMoreOpen(false)}
        >
          <div className="navigation-more-items">
            {overflowItems.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                className={page === id ? 'is-active' : ''}
                aria-current={page === id ? 'page' : undefined}
                onClick={() => {
                  // Restore the dialog's locked viewport before go() resets the new page scroll.
                  flushSync(() => setMoreOpen(false));
                  onNavigate(id);
                }}
              >
                <Icon size={22} aria-hidden="true" />
                <span>{tr(label)}</span>
                {page === id ? <Check size={18} aria-hidden="true" /> : null}
              </button>
            ))}
          </div>
        </Dialog>
      ) : null}
    </>
  );
}

function Brand() {
  return (
    <span className="brand">
      <span className="brand-mark" aria-hidden="true">
        <img src="/ritm-mark.svg" width="36" height="36" alt="" draggable={false} />
      </span>
      <span className="brand-name">Ritm</span>
    </span>
  );
}
