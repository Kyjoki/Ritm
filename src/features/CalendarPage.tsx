import { useI18n, translate, type Language } from '../lib/i18n';
import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent,
  type PointerEvent,
} from 'react';
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
  Layers2,
} from 'lucide-react';
import { Dialog } from '../components/Dialog';
import { mobileCalendarGroups } from './mobile-calendar-groups';
import { calendarWeekSwipe, type SwipePoint } from './calendar-swipe';
import { calendarDragTarget, calendarDragWeekEdge } from './calendar-drag';
import { CALENDAR_GRID_METRICS } from './calendar-grid-metrics';
import { EventPreviewDialog } from './EventPreviewDialog';
import { canEditGoogleEvent, googleEventDraft } from './google-occurrences';
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
  recordWord,
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
  onGoogleMove?: (event: GoogleCalendarEvent, date: string, time: string | null) => Promise<void>;
  onGoogleTaskToggle?: (event: GoogleCalendarEvent) => Promise<void>;
  busyGoogleTaskIds?: ReadonlySet<string>;
  onEnableGoogleTasks?: () => Promise<void>;
  onGoogleCreate?: (draft: Partial<GoogleEventInput>) => void;
  onRangeChange?: (from: string, to: string) => void;
  onGoogleRefresh?: () => void;
  onOpenSettings?: () => void;
}

type CalendarView = 'day' | 'week' | 'month';
const VIEW_LABELS: Record<CalendarView, string> = { day: 'День', week: 'Неделя', month: 'Месяц' };
const WEEKDAYS = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
const HOURS = Array.from({ length: 24 }, (_, hour) => hour);
const INITIAL_HOUR = 9;
const FIT_VISIBLE_HOURS = 9.5;
const MIN_VISUAL_HOUR_HEIGHT = 44;
const MAX_HOUR_HEIGHT = 160;
const EMPTY_GOOGLE_EVENTS: GoogleCalendarEvent[] = [];
const MOTION_ENTRIES =
  '.cal-grid-event, .cal-all-day-event, .cal-month-event, .cal-agenda-entry, .cal-month-dot';

interface DragPreview {
  key: string;
  title: string;
  date: string;
  minutes: number | null;
  duration: number;
  x: number;
  y: number;
  width: number;
  edge: -1 | 0 | 1;
  saving: boolean;
}

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

function occurrenceLabel(entry: CalendarOccurrence, language: Language): string {
  const t = (source: string) => translate(language, source);
  const time = entry.allDay
    ? t('Весь день')
    : entry.start === null
      ? t('Без времени')
      : `${entry.startLabel ?? formatTime(entry.start)}–${entry.endLabel ?? formatTime(entry.end ?? entry.start)}`;
  return `${entry.title}, ${time}${entry.source === 'google' ? ', Google Calendar' : ', Ritm'}${entry.completed ? t(', выполнено') : ''}${entry.source === 'ritm' && entry.task.repeat !== 'none' ? t(', повторяющаяся запись, редактировать серию') : ''}${entry.source === 'google' && entry.event.readOnly ? t(', только просмотр') : ''}${entry.clockChange ? t(', перевод часов') : ''}`;
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
  const { t, language } = useI18n();
  return (
    <button
      type="button"
      className={`cal-agenda-entry ${entry.completed ? 'cal-completed' : ''} ${entry.source === 'google' ? 'cal-google-entry' : ''}`}
      onClick={() => onEdit(entry)}
      aria-label={occurrenceLabel(entry, language)}
      style={calendarEntryStyle(entry)}
    >
      <span className="cal-agenda-time">
        {entry.start === null ? <Clock3 size={18} aria-hidden="true" /> : entryTime(entry, 'start')}
      </span>
      <span className="cal-agenda-copy">
        <strong>
          {entry.source === 'google' && entry.event.googleTask
            ? entry.completed
              ? '✓ '
              : '○ '
            : ''}
          {entry.title}
        </strong>
        <span>
          {entry.source === 'google'
            ? 'Google Calendar'
            : entry.task.kind === 'event'
              ? t('Событие Ritm')
              : t('Задача Ritm')}{' '}
          · {entry.allDay ? t('Весь день') : durationLabel(Math.ceil(entry.duration), language)}
          {entry.source === 'ritm' && entry.task.priority === 'high'
            ? t(' · Высокий приоритет')
            : ''}
          {entry.continued ? t(' · Продолжение') : ''}
          {entry.clockChange ? t(' · Перевод часов') : ''}
          {entry.source === 'google' && entry.event.readOnly ? t(' · Просмотр') : ''}
          {entry.source === 'google' && !entry.busy ? t(' · Время свободно') : ''}
        </span>
      </span>
      {entry.source === 'ritm' && entry.task.repeat !== 'none' ? (
        <Repeat2 size={16} aria-label={t('Повторяющаяся запись')} />
      ) : null}
      {entry.completed ? (
        <Check size={18} aria-label={t('Выполнено')} />
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
  onGoogleMove,
  onGoogleTaskToggle,
  busyGoogleTaskIds,
  onEnableGoogleTasks,
  onGoogleCreate,
  onRangeChange,
  onGoogleRefresh,
  onOpenSettings,
}: CalendarPageProps) {
  const { t, language, locale } = useI18n();
  const [selectedDate, setSelectedDate] = useState(today);
  const [focusedSlot, setFocusedSlot] = useState({ date: today, minutes: INITIAL_HOUR * 60 });
  const googleConnected = googleStatus?.status === 'connected';
  const sourceAvailable = googleConnected && Boolean(onGoogleCreate);
  const rangeCallback = useRef(onRangeChange);
  const gridScrollRef = useRef<HTMLDivElement>(null);
  const gridVisualRef = useRef<HTMLDivElement>(null);
  const allDayRef = useRef<HTMLDivElement>(null);
  const motionPanelRef = useRef<HTMLElement>(null);
  const periodHeadingRef = useRef<HTMLHeadingElement>(null);
  const previousMotionPeriod = useRef<{ view: CalendarView; period: string } | null>(null);
  const dragCleanupRef = useRef<(() => void) | null>(null);
  const moveSavingRef = useRef(false);
  const [dragPreview, setDragPreview] = useState<DragPreview | null>(null);
  const [dropFeedback, setDropFeedback] = useState<{
    id: string;
    date: string;
    minutes: number | null;
  } | null>(null);
  const scrolledPeriodRef = useRef<string | null>(null);
  const weekGesture = useRef<(SwipePoint & { pointerId: number; date: string }) | null>(null);
  const suppressSwipeClick = useRef(0);
  useEffect(() => {
    rangeCallback.current = onRangeChange;
  }, [onRangeChange]);
  useEffect(() => () => dragCleanupRef.current?.(), []);
  useEffect(() => {
    if (!dropFeedback) return;
    const timer = window.setTimeout(() => setDropFeedback(null), 750);
    return () => window.clearTimeout(timer);
  }, [dropFeedback]);
  const [isMobile, setIsMobile] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(max-width: 760px)').matches,
  );
  const gridMetrics = isMobile ? CALENDAR_GRID_METRICS.mobile : CALENDAR_GRID_METRICS.desktop;
  const [fitHourHeight, setFitHourHeight] = useState<number | null>(null);
  const hourHeight = isMobile ? gridMetrics.hourHeight : (fitHourHeight ?? gridMetrics.hourHeight);
  const { timeColumn } = gridMetrics;
  const [view, setView] = useState<CalendarView>('week');
  const [eventPicker, setEventPicker] = useState<{ date: string; keys: string[] } | null>(null);
  const [preview, setPreview] = useState<{ date: string; key: string } | null>(null);
  useEffect(
    () => () => {
      weekGesture.current = null;
      suppressSwipeClick.current = 0;
      if (gridVisualRef.current) {
        gridVisualRef.current.style.transform = '';
        gridVisualRef.current.style.transition = '';
      }
    },
    [isMobile, view],
  );
  useEffect(() => {
    if (!isMobile || view !== 'week') setEventPicker(null);
  }, [isMobile, view]);
  const [nowMinutes, setNowMinutes] = useState(() => minutesInZone(timeZone, new Date()));
  useEffect(() => {
    const update = () => setNowMinutes(minutesInZone(timeZone, new Date()));
    update();
    const timer = window.setInterval(update, 60_000);
    return () => window.clearInterval(timer);
  }, [timeZone]);
  useEffect(() => {
    const media = window.matchMedia('(max-width: 760px)');
    const listener = () => setIsMobile(media.matches);
    // Activity pauses listeners while hidden; reconcile the current viewport on return.
    listener();
    media.addEventListener('change', listener);
    return () => media.removeEventListener('change', listener);
  }, []);
  useLayoutEffect(() => {
    const panel = motionPanelRef.current;
    const page = panel?.closest<HTMLElement>('.cal-page');
    if (!panel || !page) return;
    const fitPanel = () => {
      const viewport = window.visualViewport;
      const pageZoom = Number.parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
      page.style.setProperty(
        '--cal-visible-height',
        `${(viewport?.height ?? window.innerHeight) / pageZoom}px`,
      );
      page.style.setProperty(
        '--cal-panel-top',
        `${(panel.getBoundingClientRect().top - (viewport?.offsetTop ?? 0)) / pageZoom}px`,
      );
    };
    fitPanel();
    const observer = new ResizeObserver(fitPanel);
    for (const selector of ['.cal-toolbar']) {
      const control = page.querySelector(selector);
      if (control) observer.observe(control);
    }
    window.addEventListener('resize', fitPanel);
    window.visualViewport?.addEventListener('resize', fitPanel);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', fitPanel);
      window.visualViewport?.removeEventListener('resize', fitPanel);
    };
  }, [view, isMobile, googleStatus?.status, googleLoading, googleError, googlePartial]);
  useLayoutEffect(() => {
    const scroll = gridScrollRef.current;
    const panel = motionPanelRef.current;
    if (!scroll || !panel) return;
    const alignColumns = () => {
      panel.style.setProperty(
        '--cal-scrollbar-gutter',
        `${scroll.offsetWidth - scroll.clientWidth}px`,
      );
      if (isMobile) return;
      // Desktop rows scale with the panel: about 9-10 hours fit, never below 44 visual px.
      const pageZoom = Number.parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
      const next = Math.round(
        Math.min(
          MAX_HOUR_HEIGHT,
          Math.max(MIN_VISUAL_HOUR_HEIGHT / pageZoom, scroll.clientHeight / FIT_VISIBLE_HOURS),
        ),
      );
      setFitHourHeight((current) => (current === next ? current : next));
    };
    alignColumns();
    const observer = new ResizeObserver(alignColumns);
    observer.observe(scroll);
    window.addEventListener('resize', alignColumns);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', alignColumns);
    };
  }, [view, isMobile]);

  const weekStart = startOfWeek(selectedDate);
  const range = calendarRange(view, selectedDate);
  const motionPeriod =
    view === 'week' ? weekStart : view === 'month' ? selectedDate.slice(0, 7) : selectedDate;
  useLayoutEffect(() => {
    const previous = previousMotionPeriod.current;
    previousMotionPeriod.current = { view, period: motionPeriod };
    const panel = motionPanelRef.current;
    if (
      !panel ||
      panel.closest('[hidden]') ||
      document.hidden ||
      dragCleanupRef.current ||
      !panel.animate ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches ||
      (previous?.view === view && previous.period === motionPeriod)
    )
      return;
    const direction = previous
      ? motionPeriod > previous.period
        ? 1
        : motionPeriod < previous.period
          ? -1
          : 0
      : 0;
    const easing = 'cubic-bezier(0.2, 0.8, 0.2, 1)';
    const animations: Animation[] = [];
    if (previous)
      animations.push(
        panel.animate([{ opacity: 0.76 }, { opacity: 1 }], {
          duration: isMobile ? 190 : 240,
          easing,
        }),
      );
    if (previous && periodHeadingRef.current) {
      animations.push(
        periodHeadingRef.current.animate(
          [
            { opacity: 0.55, transform: `translateX(${direction * (isMobile ? 5 : 9)}px)` },
            { opacity: 1, transform: 'translateX(0)' },
          ],
          { duration: isMobile ? 190 : 260, easing },
        ),
      );
    }
    const entries = panel.querySelectorAll<HTMLElement>(MOTION_ENTRIES);
    for (let index = 0; index < Math.min(entries.length, 30); index++) {
      animations.push(
        entries[index].animate([{ opacity: 0.5 }, { opacity: 1 }], {
          duration: isMobile ? 220 : 300,
          delay: Math.min(Math.floor(index / 3) * (isMobile ? 25 : 45), isMobile ? 100 : 180),
          easing,
          fill: 'backwards',
        }),
      );
    }
    return () => animations.forEach((animation) => animation.cancel());
  }, [view, motionPeriod, isMobile]);
  useEffect(() => {
    const panel = motionPanelRef.current;
    if (!panel || typeof MutationObserver === 'undefined') return;
    const seen = new WeakSet<Element>();
    const animations = new Set<Animation>();
    panel.querySelectorAll(MOTION_ENTRIES).forEach((entry) => seen.add(entry));
    const observer = new MutationObserver((records) => {
      if (document.hidden || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      const added: Element[] = [];
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (!(node instanceof Element)) continue;
          if (node.matches(MOTION_ENTRIES)) added.push(node);
          added.push(...node.querySelectorAll(MOTION_ENTRIES));
        }
      }
      let animated = 0;
      for (const entry of added) {
        if (seen.has(entry) || !entry.animate) continue;
        seen.add(entry);
        const animation = entry.animate([{ opacity: 0.5 }, { opacity: 1 }], {
          duration: isMobile ? 200 : 280,
          delay: Math.min(animated++ * 35, isMobile ? 70 : 140),
          easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)',
        });
        animations.add(animation);
        animation.addEventListener('finish', () => animations.delete(animation), { once: true });
      }
    });
    observer.observe(panel, { childList: true, subtree: true });
    return () => {
      observer.disconnect();
      animations.forEach((animation) => animation.cancel());
    };
  }, [view, motionPeriod, isMobile]);
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
  const keyboardSlotDate = periodDays.includes(focusedSlot.date) ? focusedSlot.date : selectedDate;
  function moveSlotFocus(event: KeyboardEvent<HTMLButtonElement>, date: string, minutes: number) {
    const dayIndex = periodDays.indexOf(date);
    let nextDay = dayIndex;
    let nextMinutes = minutes;
    switch (event.key) {
      case 'ArrowLeft':
        nextDay = Math.max(0, dayIndex - 1);
        break;
      case 'ArrowRight':
        nextDay = Math.min(periodDays.length - 1, dayIndex + 1);
        break;
      case 'ArrowUp':
        nextMinutes = Math.max(0, minutes - 30);
        break;
      case 'ArrowDown':
        nextMinutes = Math.min(23 * 60 + 30, minutes + 30);
        break;
      case 'Home':
        nextMinutes = 0;
        break;
      case 'End':
        nextMinutes = 23 * 60 + 30;
        break;
      default:
        return;
    }
    event.preventDefault();
    const nextDate = periodDays[nextDay];
    if (!nextDate) return;
    setFocusedSlot({ date: nextDate, minutes: nextMinutes });
    gridScrollRef.current
      ?.querySelector<HTMLButtonElement>(
        `[data-calendar-date="${nextDate}"][data-calendar-minutes="${nextMinutes}"]`,
      )
      ?.focus();
  }
  const slotDateLabels = useMemo(
    () =>
      new Map(
        periodDays.map((date) => [
          date,
          formatDate(date, { day: 'numeric', month: 'long' }, language),
        ]),
      ),
    [periodDays, language],
  );
  const occurrencesByDay = useMemo(
    () =>
      periodDays.map((date) => ({
        date,
        entries: calendarOccurrences(tasks, googleEvents, date, timeZone, language),
      })),
    [tasks, googleEvents, periodDays, timeZone, language],
  );
  const selectedEntries = useMemo(
    () => calendarOccurrences(tasks, googleEvents, selectedDate, timeZone, language),
    [tasks, googleEvents, selectedDate, timeZone, language],
  );
  const overlapsByDay = useMemo(
    () =>
      occurrencesByDay.map(({ date, entries }) => ({
        date,
        entries: mobileCalendarGroups(entries)
          .filter((group) => group.entries.length > 1)
          .flatMap((group) => group.entries),
      })),
    [occurrencesByDay],
  );
  const monthDays = useMemo(() => {
    if (view !== 'month') return [];
    const month = parseDate(selectedDate);
    month.setUTCDate(1);
    const first = startOfWeek(dateKey(month));
    return Array.from({ length: 42 }, (_, index) => {
      const date = addDays(first, index);
      return {
        date,
        entries: calendarOccurrences(tasks, googleEvents, date, timeZone, language),
        currentMonth: date.slice(0, 7) === selectedDate.slice(0, 7),
      };
    });
  }, [tasks, googleEvents, selectedDate, timeZone, language, view]);
  const gridHeight = HOURS.length * hourHeight;
  useEffect(() => {
    if ((isMobile && view === 'day') || view === 'month') {
      scrolledPeriodRef.current = null;
      return;
    }
    const period = `${view}:${selectedDate}:${hourHeight}`;
    if (!gridScrollRef.current || scrolledPeriodRef.current === period) return;
    const showsToday = periodDays.includes(today);
    const startHour = showsToday
      ? Math.max(0, minutesInZone(timeZone, new Date()) / 60 - 1)
      : INITIAL_HOUR - 1;
    gridScrollRef.current.scrollTop = startHour * hourHeight;
    scrolledPeriodRef.current = period;
  }, [isMobile, view, selectedDate, hourHeight, periodDays, today, timeZone]);
  const visibleCount = occurrencesByDay.reduce((total, day) => total + day.entries.length, 0);
  const noDateTasks = tasks.filter((task) => task.date === null && !task.completed);
  const periodLabel =
    view === 'month'
      ? formatDate(selectedDate, { month: 'long', year: 'numeric' }, language)
      : view === 'day'
        ? formatDate(selectedDate, { day: 'numeric', month: 'long', weekday: 'short' }, language)
        : `${formatDate(weekStart, { day: 'numeric', month: 'short' }, language)} — ${formatDate(addDays(weekStart, 6), { day: 'numeric', month: 'short', year: 'numeric' }, language)}`;

  function navigate(direction: number) {
    setSelectedDate((date) =>
      view === 'month'
        ? addMonths(date, direction)
        : addDays(date, direction * (view === 'week' ? 7 : 1)),
    );
  }

  function showNow() {
    scrolledPeriodRef.current = `${view}:${today}:${hourHeight}`;
    setSelectedDate(today);
    window.requestAnimationFrame(() =>
      gridScrollRef.current?.scrollTo({
        top: Math.max(0, (minutesInZone(timeZone, new Date()) / 60) * hourHeight - hourHeight),
        behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches
          ? 'instant'
          : 'smooth',
      }),
    );
  }

  function addEntry(date: string, time: string | null = null, duration = 60) {
    const boundedDuration = time ? Math.min(duration, 1440 - timeMinutes(time)) : duration;
    if (sourceAvailable)
      onGoogleCreate?.({ date, time, duration: boundedDuration, allDay: time === null });
    else onCreate({ date, time, duration: boundedDuration, kind: 'event' });
  }
  function editEntry(entry: CalendarOccurrence) {
    setPreview({ date: entry.date, key: entry.key });
  }
  function beginEditing(entry: CalendarOccurrence) {
    setPreview(null);
    if (entry.source === 'google') onGoogleEdit?.(entry.event);
    else onEdit(entry.task);
  }
  const previewEntry = preview
    ? (calendarOccurrences(tasks, googleEvents, preview.date, timeZone, language).find(
        (entry) => entry.key === preview.key,
      ) ?? null)
    : null;
  function startWeekGesture(event: PointerEvent<HTMLDivElement>) {
    if (!isMobile || view !== 'week' || event.pointerType !== 'touch' || !event.isPrimary) {
      weekGesture.current = null;
      return;
    }
    weekGesture.current = {
      x: event.clientX,
      y: event.clientY,
      time: event.timeStamp,
      pointerId: event.pointerId,
      date: selectedDate,
    };
  }
  function moveWeekGesture(event: PointerEvent<HTMLDivElement>) {
    const start = weekGesture.current;
    if (!start || event.pointerId !== start.pointerId) return;
    const dx = Math.abs(event.clientX - start.x),
      dy = Math.abs(event.clientY - start.y);
    if (dy > 12 && dy > dx * 1.2) {
      weekGesture.current = null;
      resetWeekVisual();
      return;
    }
    if (dx > 8 && dx > dy * 1.2 && gridVisualRef.current) {
      const limit = event.currentTarget.clientWidth * 0.4;
      gridVisualRef.current.style.transition = 'none';
      gridVisualRef.current.style.transform = `translate3d(${Math.max(-limit, Math.min(limit, event.clientX - start.x))}px, 0, 0)`;
    }
  }
  function resetWeekVisual() {
    const grid = gridVisualRef.current;
    if (!grid) return;
    grid.style.transition = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      ? 'none'
      : 'transform 220ms cubic-bezier(0.2, 0.8, 0.2, 1)';
    grid.style.transform = '';
  }
  function finishWeekGesture(event: PointerEvent<HTMLDivElement>) {
    const start = weekGesture.current;
    weekGesture.current = null;
    if (
      !start ||
      event.pointerId !== start.pointerId ||
      start.date !== selectedDate ||
      !isMobile ||
      view !== 'week'
    ) {
      resetWeekVisual();
      return;
    }
    const direction = calendarWeekSwipe(
      start,
      { x: event.clientX, y: event.clientY, time: event.timeStamp },
      event.currentTarget.clientWidth,
    );
    if (direction) {
      suppressSwipeClick.current = performance.now() + 450;
      navigate(direction);
    }
    resetWeekVisual();
  }
  function canDragEntry(
    entry: CalendarOccurrence,
  ): entry is CalendarOccurrence & { source: 'google' } {
    return Boolean(
      onGoogleMove &&
      entry.source === 'google' &&
      !entry.continued &&
      !entry.event.taskLink &&
      !entry.event.googleTask &&
      canEditGoogleEvent(entry.event, timeZone),
    );
  }
  function startEventDrag(event: PointerEvent<HTMLButtonElement>, entry: CalendarOccurrence) {
    if (
      event.button !== 0 ||
      !event.isPrimary ||
      !canDragEntry(entry) ||
      dragCleanupRef.current ||
      moveSavingRef.current
    )
      return;
    const moveGoogle = onGoogleMove;
    if (!moveGoogle) return;
    event.stopPropagation();
    const element = event.currentTarget;
    const card = element.getBoundingClientRect();
    const draft = googleEventDraft(entry.event, timeZone);
    const allDay = entry.event.allDay;
    const session = {
      pointerId: event.pointerId,
      pointerType: event.pointerType,
      sourceDate: draft.date,
      sourceMinutes: allDay ? null : timeMinutes(draft.time!),
      duration: draft.duration,
      targetDate: draft.date,
      targetMinutes: allDay ? null : timeMinutes(draft.time!),
      point: { x: event.clientX, y: event.clientY },
      start: { x: event.clientX, y: event.clientY },
      grabX: event.clientX - card.left,
      grabY: event.clientY - card.top,
      width: Math.max(card.width, isMobile ? 130 : 170),
      active: false,
      periodStart: view === 'week' ? weekStart : selectedDate,
      currentDate: selectedDate,
      edge: 0 as -1 | 0 | 1,
      edgeSince: 0,
    };
    let holdTimer: number | null = null;
    let edgeTimer: number | null = null;
    const dragSurface = () => (allDay ? allDayRef.current : gridVisualRef.current);
    const updatePreview = () => {
      const surface = dragSurface();
      if (!surface) return;
      const rect = surface.getBoundingClientRect();
      const target = calendarDragTarget(
        session.point.x,
        session.point.y,
        {
          left: rect.left,
          top: rect.top,
          width: rect.width,
          timeColumn,
          days: view === 'week' ? 7 : 1,
          hourHeight,
        },
        session.grabY,
        session.duration,
      );
      session.targetDate = addDays(session.periodStart, target.dayIndex);
      session.targetMinutes = allDay ? null : target.minutes;
      const nextEdge = calendarDragWeekEdge(session.point.x, rect.left, rect.right);
      if (session.edge !== nextEdge) {
        session.edge = nextEdge;
        session.edgeSince = performance.now();
      }
      const nextPreview: DragPreview = {
        key: entry.key,
        title: entry.title,
        date: session.targetDate,
        minutes: session.targetMinutes,
        duration: session.duration,
        x: session.point.x - session.grabX,
        y: session.point.y - session.grabY,
        width: session.width,
        edge: session.edge,
        saving: false,
      };
      setDragPreview((current) =>
        current &&
        current.key === nextPreview.key &&
        current.date === nextPreview.date &&
        current.minutes === nextPreview.minutes &&
        current.x === nextPreview.x &&
        current.y === nextPreview.y &&
        current.edge === nextPreview.edge
          ? current
          : nextPreview,
      );
    };
    const activate = () => {
      if (session.active || dragCleanupRef.current === null) return;
      session.active = true;
      updatePreview();
      edgeTimer = window.setInterval(() => {
        const scroll = gridScrollRef.current;
        if (!allDay && scroll) {
          const bounds = scroll.getBoundingClientRect();
          if (session.point.y < bounds.top + 18) scroll.scrollTop -= hourHeight / 6;
          else if (session.point.y > bounds.bottom - 18) scroll.scrollTop += hourHeight / 6;
        }
        if (session.edge && performance.now() - session.edgeSince >= 650) {
          session.currentDate = addDays(
            session.currentDate,
            session.edge * (view === 'week' ? 7 : 1),
          );
          session.periodStart =
            view === 'week' ? startOfWeek(session.currentDate) : session.currentDate;
          scrolledPeriodRef.current = `${view}:${session.currentDate}`;
          setSelectedDate(session.currentDate);
          session.edgeSince = performance.now();
        }
        updatePreview();
      }, 50);
    };
    const cleanup = () => {
      if (holdTimer !== null) window.clearTimeout(holdTimer);
      if (edgeTimer !== null) window.clearInterval(edgeTimer);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', finish);
      window.removeEventListener('pointercancel', cancel);
      window.removeEventListener('keydown', keydown);
      window.removeEventListener('blur', cancel);
      dragCleanupRef.current = null;
    };
    const move = (pointer: globalThis.PointerEvent) => {
      if (pointer.pointerId !== session.pointerId) return;
      session.point = { x: pointer.clientX, y: pointer.clientY };
      if (
        !session.active &&
        Math.hypot(pointer.clientX - session.start.x, pointer.clientY - session.start.y) >= 8
      ) {
        if (session.pointerType === 'touch') {
          suppressSwipeClick.current = performance.now() + 500;
          cleanup();
          return;
        }
        activate();
      }
      if (session.active) {
        pointer.preventDefault();
        updatePreview();
      }
    };
    const finish = (pointer: globalThis.PointerEvent) => {
      if (pointer.pointerId !== session.pointerId) return;
      session.point = { x: pointer.clientX, y: pointer.clientY };
      if (session.active) updatePreview();
      cleanup();
      if (!session.active) return;
      suppressSwipeClick.current = performance.now() + 500;
      if (
        session.targetDate === session.sourceDate &&
        session.targetMinutes === session.sourceMinutes
      ) {
        setDragPreview(null);
        return;
      }
      moveSavingRef.current = true;
      setDragPreview((current) => (current ? { ...current, saving: true, edge: 0 } : current));
      void moveGoogle(
        entry.event,
        session.targetDate,
        session.targetMinutes === null ? null : minuteTime(session.targetMinutes),
      )
        .then(() =>
          setDropFeedback({
            id: entry.event.id,
            date: session.targetDate,
            minutes: session.targetMinutes,
          }),
        )
        .catch(() => {})
        .finally(() => {
          moveSavingRef.current = false;
          setDragPreview(null);
        });
    };
    const cancel = () => {
      if (session.active) suppressSwipeClick.current = performance.now() + 500;
      cleanup();
      setDragPreview(null);
    };
    const keydown = (key: globalThis.KeyboardEvent) => {
      if (key.key === 'Escape') cancel();
    };
    dragCleanupRef.current = cleanup;
    holdTimer = window.setTimeout(activate, event.pointerType === 'touch' ? 280 : 160);
    window.addEventListener('pointermove', move, { passive: false });
    window.addEventListener('pointerup', finish);
    window.addEventListener('pointercancel', cancel);
    window.addEventListener('keydown', keydown);
    window.addEventListener('blur', cancel);
  }
  const pickerEntries = eventPicker
    ? calendarOccurrences(tasks, googleEvents, eventPicker.date, timeZone, language).filter(
        (entry) => eventPicker.keys.includes(entry.key),
      )
    : [];
  const uncertainGoogle =
    (googleLoading && !googleFetchedAt) ||
    Boolean(googleError) ||
    googlePartial ||
    googleStatus?.status === 'reauth_required' ||
    (googleConnected && !googleFetchedAt);
  const fetchedDate = googleFetchedAt ? new Date(googleFetchedAt) : null;
  const initialGoogleLoading = googleLoading && !googleFetchedAt;
  const fetchedLabel =
    fetchedDate && Number.isFinite(fetchedDate.getTime())
      ? new Intl.DateTimeFormat(locale, {
          timeZone,
          day: 'numeric',
          month: 'short',
        }).format(fetchedDate) + ` · ${formatTime(minutesInZone(timeZone, fetchedDate))}`
      : null;

  return (
    <div className={`cal-page ${isMobile && view === 'week' ? 'cal-mobile-week' : ''}`}>
      <div className="cal-toolbar">
        <h1 className="cal-toolbar-title">{t('Календарь')}</h1>
        <div className="cal-period">
          <button
            className="cal-icon-button"
            type="button"
            aria-label={t('Предыдущий период: {p0}', { p0: t(VIEW_LABELS[view]).toLowerCase() })}
            onClick={() => navigate(-1)}
          >
            <ChevronLeft size={19} aria-hidden="true" />
          </button>
          <h2 ref={periodHeadingRef} aria-live="polite">
            {periodLabel}
          </h2>
          <button
            className="cal-icon-button"
            type="button"
            aria-label={t('Следующий период: {p0}', { p0: t(VIEW_LABELS[view]).toLowerCase() })}
            onClick={() => navigate(1)}
          >
            <ChevronRight size={19} aria-hidden="true" />
          </button>
          <button
            className="button button-secondary cal-today"
            type="button"
            onClick={() => setSelectedDate(today)}
          >
            {t('Сегодня')}
          </button>
          {view !== 'month' && (!isMobile || view === 'week') ? (
            <button
              className="button button-secondary cal-now"
              type="button"
              onClick={showNow}
              aria-label={t('Показать текущее время')}
            >
              <Clock3 size={15} aria-hidden="true" />
              {t('Сейчас')}
            </button>
          ) : null}
        </div>
        <div
          className="cal-segment"
          role="group"
          aria-label={t('Вид календаря')}
          style={
            {
              '--n': 3,
              '--i': (Object.keys(VIEW_LABELS) as CalendarView[]).indexOf(view),
            } as CSSProperties
          }
        >
          {(Object.keys(VIEW_LABELS) as CalendarView[]).map((value) => (
            <button
              key={value}
              type="button"
              className={view === value ? 'cal-selected' : ''}
              aria-pressed={view === value}
              onClick={() => setView(value)}
            >
              {t(VIEW_LABELS[value])}
            </button>
          ))}
        </div>
        {googleStatus || googleLoading || googleError ? (
          <div
            className={`cal-google-status cal-sync-footer ${googleError || googlePartial || googleStatus?.status === 'reauth_required' ? 'cal-google-status-warning' : ''}`}
            role={googleError ? 'alert' : initialGoogleLoading ? 'status' : undefined}
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
                {initialGoogleLoading
                  ? t('Загружаем Google Calendar…')
                  : googleError
                    ? t('Google Calendar требует внимания')
                    : googleStatus?.status === 'reauth_required'
                      ? t('Подключи Google Calendar заново')
                      : googlePartial
                        ? t('Загружена часть событий Google')
                        : googleConnected
                          ? t('Календарь синхронизирован')
                          : t('Google Calendar пока не подключён')}
              </strong>
              <span>
                {googleError
                  ? t('{p0} Показанные события могут быть неактуальны.', { p0: googleError })
                  : googlePartial
                    ? t(
                        'Часть событий не загружена. Свободное время нужно уточнить в Google Calendar.',
                      )
                    : initialGoogleLoading
                      ? t('Обновляем выбранный период и синхронизируем записи.')
                      : googleStatus?.status === 'reauth_required'
                        ? t('Разрешение нужно обновить в настройках.')
                        : googleConnected
                          ? t(
                              'Изменения сохраняются в Google Calendar. Расписание обновляется автоматически.',
                            )
                          : t(
                              'Подключи Google Calendar в настройках, чтобы работать с единым расписанием.',
                            )}
              </span>
              {fetchedLabel ? (
                <small className="cal-google-updated">
                  {t('Последнее обновление:')}{' '}
                  <time dateTime={googleFetchedAt ?? undefined}>{fetchedLabel}</time>
                  {googleLoading ? t(' · Обновляем…') : ''}
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
                  {t('Обновить')}
                </button>
              ) : null}
              {onOpenSettings && !googleConnected ? (
                <button type="button" className="cal-google-settings" onClick={onOpenSettings}>
                  {t('Настройки')}
                  <ChevronRight size={15} aria-hidden="true" />
                </button>
              ) : null}
            </div>
          </div>
        ) : null}
        <button
          type="button"
          className="button button-primary cal-toolbar-add"
          aria-label={t('Добавить запись')}
          onClick={() => addEntry(selectedDate)}
        >
          <Plus size={17} aria-hidden="true" />
          <span>{t('Добавить запись')}</span>
        </button>
      </div>

      {view === 'month' ? (
        <section
          ref={motionPanelRef}
          className="panel cal-month-panel"
          aria-label={t('Календарь на месяц')}
        >
          <div className="cal-month-grid">
            {WEEKDAYS.map((day) => (
              <span key={day} className="cal-weekday">
                {t(day)}
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
                  aria-label={t('{p0}, записей: {p1}. Открыть день', {
                    p0: formatDate(date, { day: 'numeric', month: 'long' }, language),
                    p1: entries.length,
                  })}
                  onClick={() => {
                    setSelectedDate(date);
                    setView('day');
                  }}
                >
                  <span>{parseDate(date).getUTCDate()}</span>
                  <small>
                    {entries.length
                      ? `${entries.length} ${recordWord(entries.length, language)}`
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
                          aria-label={occurrenceLabel(entry, language)}
                          title={occurrenceLabel(entry, language)}
                          style={calendarEntryStyle(entry)}
                        >
                          {entry.source === 'google' && entry.event.googleTask
                            ? entry.completed
                              ? '✓ '
                              : '○ '
                            : ''}
                          {entry.start === null ? '' : `${entryTime(entry, 'start')} `}
                          {entry.title}
                        </button>
                      ))}
                  {!isMobile && entries.length > 2 ? (
                    <span className="cal-month-more">
                      {t('Ещё {count}', { count: entries.length - 2 })}
                    </span>
                  ) : null}
                </div>
                {!isMobile ? (
                  <button
                    className="cal-month-add"
                    type="button"
                    aria-label={t('Добавить запись на {p0}', {
                      p0: formatDate(date, { day: 'numeric', month: 'long' }, language),
                    })}
                    onClick={() => addEntry(date)}
                  >
                    <Plus size={15} aria-hidden="true" />
                  </button>
                ) : null}
              </div>
            ))}
          </div>
        </section>
      ) : isMobile && view === 'day' ? (
        <section ref={motionPanelRef} className="panel cal-mobile-agenda">
          {occurrencesByDay.map(({ date, entries }) => (
            <div className="cal-agenda-day" key={date}>
              <div className="cal-section-head">
                <h2>
                  {formatDate(date, { weekday: 'long', day: 'numeric', month: 'long' }, language)}
                </h2>
                <span>{t('Записей: {count}', { count: entries.length })}</span>
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
                      ? t('В Ritm на этот день пока нет планов')
                      : t('На этот день пока нет планов')}
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
                      {googleConnected ? t('Свободно') : t('Свободно в Ritm')}{' '}
                      {formatTime(interval.start, { compact: true })}–
                      {formatTime(interval.end, { compact: true })}
                    </span>
                  </button>
                ))}
              </div>
              <button className="cal-mobile-add" type="button" onClick={() => addEntry(date)}>
                <Plus size={17} aria-hidden="true" />
                {t('Добавить запись')}
              </button>
            </div>
          ))}
        </section>
      ) : (
        <section
          ref={motionPanelRef}
          className="panel cal-calendar-panel"
          aria-label={view === 'week' ? t('Расписание недели') : t('Расписание дня')}
        >
          <div
            className="cal-grid-header"
            style={{
              gridTemplateColumns: `${timeColumn}px repeat(${periodDays.length}, minmax(0, 1fr))`,
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
                aria-label={t('Показать {p0}', {
                  p0: slotDateLabels.get(date)!,
                })}
              >
                <span>{formatDate(date, { weekday: 'short' }, language)}</span>
                <strong>{parseDate(date).getUTCDate()}</strong>
              </button>
            ))}
          </div>
          {isMobile && view === 'week' && overlapsByDay.some((day) => day.entries.length) ? (
            <div
              className="cal-overlap-row"
              style={{ gridTemplateColumns: `40px repeat(7, minmax(0, 1fr))` }}
            >
              <span
                className="cal-overlap-row-label"
                title={t('Пересекающиеся записи')}
                aria-hidden="true"
              >
                <Layers2 size={13} />
              </span>
              {overlapsByDay.map(({ date, entries }) =>
                entries.length ? (
                  <button
                    key={date}
                    type="button"
                    className="cal-overlap-day-button"
                    onClick={() =>
                      setEventPicker({ date, keys: entries.map((entry) => entry.key) })
                    }
                    aria-haspopup="dialog"
                    aria-label={t('{p0}: {p1} {p2} с пересечением. Выбрать событие', {
                      p0: slotDateLabels.get(date)!,
                      p1: entries.length,
                      p2: recordWord(entries.length, language),
                    })}
                    title={t('Открыть пересекающиеся записи')}
                  >
                    <Layers2 size={11} aria-hidden="true" />
                    <span>{entries.length}</span>
                  </button>
                ) : (
                  <span key={date} />
                ),
              )}
            </div>
          ) : null}
          {occurrencesByDay.some((day) => day.entries.some((entry) => entry.start === null)) ||
          (dragPreview && dragPreview.minutes === null) ? (
            <div
              ref={allDayRef}
              className="cal-all-day"
              style={{
                gridTemplateColumns: `${timeColumn}px repeat(${periodDays.length}, minmax(0, 1fr))`,
              }}
            >
              <span>{t('Весь день / без времени')}</span>
              {occurrencesByDay.map(({ date, entries }) => (
                <div
                  key={date}
                  className={
                    dragPreview?.minutes === null && dragPreview.date === date
                      ? 'cal-drag-all-day-target'
                      : undefined
                  }
                >
                  {entries
                    .filter((entry) => entry.start === null)
                    .map((entry) => (
                      <button
                        type="button"
                        key={entry.key}
                        className={`cal-all-day-event ${entry.source === 'google' ? 'cal-google-entry' : ''} ${canDragEntry(entry) ? 'cal-draggable-event' : ''} ${dragPreview?.key === entry.key ? 'cal-drag-source' : ''} ${entry.source === 'google' && dropFeedback?.id === entry.event.id && dropFeedback.date === entry.date && dropFeedback.minutes === null ? 'cal-drop-settle' : ''}`}
                        onPointerDown={(event) => startEventDrag(event, entry)}
                        onClick={() => {
                          if (performance.now() >= suppressSwipeClick.current) editEntry(entry);
                        }}
                        aria-label={occurrenceLabel(entry, language)}
                        aria-description={
                          canDragEntry(entry)
                            ? t('Удерживайте и перетащите запись на другой день.')
                            : undefined
                        }
                        style={calendarEntryStyle(entry)}
                      >
                        {entry.title}
                      </button>
                    ))}
                </div>
              ))}
            </div>
          ) : null}
          <div
            ref={gridScrollRef}
            className={`cal-grid-scroll ${isMobile && view === 'week' ? 'cal-swipe-week' : ''}`}
            onPointerDown={startWeekGesture}
            onPointerMove={moveWeekGesture}
            onPointerUp={finishWeekGesture}
            onPointerCancel={() => {
              weekGesture.current = null;
              resetWeekVisual();
            }}
            onClickCapture={(event) => {
              if (event.detail > 0 && performance.now() < suppressSwipeClick.current) {
                suppressSwipeClick.current = 0;
                event.preventDefault();
                event.stopPropagation();
              }
            }}
          >
            <div
              ref={gridVisualRef}
              className="cal-grid"
              style={{
                gridTemplateColumns: `${timeColumn}px repeat(${periodDays.length}, minmax(0, 1fr))`,
                height: gridHeight,
              }}
            >
              <div className="cal-hour-labels">
                {HOURS.map((hour) => (
                  <span key={hour} style={{ height: hourHeight }}>
                    {formatTime(hour * 60, { compact: true }).replace(' ', '')}
                  </span>
                ))}
              </div>
              {occurrencesByDay.map(({ date, entries }) => (
                <div
                  className={`cal-day-column ${date === today ? 'cal-today-column' : ''}`}
                  key={date}
                >
                  {dragPreview &&
                  dragPreview.minutes !== null &&
                  dragPreview.date === date &&
                  !dragPreview.saving ? (
                    <div
                      className="cal-drag-target"
                      style={{
                        top: (dragPreview.minutes / 60) * hourHeight,
                        height: Math.max(22, (dragPreview.duration / 60) * hourHeight),
                      }}
                      aria-hidden="true"
                    >
                      {formatTime(dragPreview.minutes)}
                    </div>
                  ) : null}
                  {HOURS.flatMap((hour) =>
                    [0, 30].map((minute) => (
                      <button
                        type="button"
                        className="cal-free-slot"
                        key={`${hour}:${minute}`}
                        data-calendar-date={date}
                        data-calendar-minutes={hour * 60 + minute}
                        tabIndex={
                          date === keyboardSlotDate && hour * 60 + minute === focusedSlot.minutes
                            ? 0
                            : -1
                        }
                        style={{
                          top: ((hour * 60 + minute) / 60) * hourHeight,
                          height: hourHeight / 2,
                        }}
                        aria-label={t('Добавить запись: {p0}, {p1}', {
                          p0: slotDateLabels.get(date)!,
                          p1: formatTime(hour * 60 + minute),
                        })}
                        aria-description={
                          date === keyboardSlotDate && hour * 60 + minute === focusedSlot.minutes
                            ? t('Стрелки перемещают по времени и дням, Enter добавляет запись.')
                            : undefined
                        }
                        onFocus={() => setFocusedSlot({ date, minutes: hour * 60 + minute })}
                        onKeyDown={(event) => moveSlotFocus(event, date, hour * 60 + minute)}
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
                        className={`cal-grid-event ${entry.source === 'google' || entry.task.kind === 'event' ? 'cal-event-kind' : ''} ${entry.source === 'google' ? 'cal-google-entry' : ''} ${entry.completed ? 'cal-completed' : ''} ${duration < 75 ? 'cal-compact-event' : ''} ${duration < 45 ? 'cal-tiny-event' : ''} ${canDragEntry(entry) ? 'cal-draggable-event' : ''} ${dragPreview?.key === entry.key ? 'cal-drag-source' : ''} ${entry.source === 'google' && dropFeedback?.id === entry.event.id && dropFeedback.date === entry.date && dropFeedback.minutes === entry.start ? 'cal-drop-settle' : ''}`}
                        style={{
                          ...calendarEntryStyle(entry),
                          top: ((entry.start ?? 0) / 60) * hourHeight + 2,
                          height: Math.max(22, (duration / 60) * hourHeight - 4),
                          width: `calc(${100 / entry.lanes}% - ${isMobile ? 2 : 7}px)`,
                          left: `calc(${(entry.lane * 100) / entry.lanes}% + ${isMobile ? 1 : 4}px)`,
                        }}
                        onPointerDown={(event) => startEventDrag(event, entry)}
                        onClick={() => {
                          if (performance.now() >= suppressSwipeClick.current) editEntry(entry);
                        }}
                        title={occurrenceLabel(entry, language)}
                        aria-label={occurrenceLabel(entry, language)}
                        aria-description={
                          canDragEntry(entry)
                            ? t('Удерживайте и перетащите запись на другое время или день.')
                            : undefined
                        }
                      >
                        <strong>
                          {entry.source === 'google' && entry.event.googleTask
                            ? entry.completed
                              ? '✓ '
                              : '○ '
                            : ''}
                          {entry.title}
                        </strong>
                        <span className="cal-event-time">
                          {entryTime(entry, 'start')}–{entryTime(entry, 'end')}
                          {entry.source === 'ritm' && entry.task.repeat !== 'none' ? ' · ↻' : ''}
                          {entry.clockChange ? t(' · Перевод часов') : ''}
                        </span>
                      </button>
                    );
                  })}
                  {date === today ? (
                    <div
                      className="cal-now-line"
                      style={{ top: (nowMinutes / 60) * hourHeight }}
                      aria-hidden="true"
                    />
                  ) : null}
                </div>
              ))}
            </div>
          </div>
        </section>
      )}

      <details className="cal-secondary">
        <summary>
          {t('Твой темп')} · {t('Без даты')} ({noDateTasks.length})
        </summary>
        <div className="cal-bottom-grid">
          <section className="panel cal-summary">
            <div className="cal-section-head">
              <h2>
                <Sparkles size={17} aria-hidden="true" />
                {t('Твой темп')}
              </h2>
              <span>
                {view === 'month'
                  ? t('Выбранный день')
                  : view === 'week'
                    ? t('Эта неделя')
                    : t('Выбранный день')}
              </span>
            </div>
            <p>
              {(view === 'month' ? selectedEntries.length : visibleCount) ? (
                <>
                  {uncertainGoogle ? t('Показано') : t('В плане')}{' '}
                  <strong>{view === 'month' ? selectedEntries.length : visibleCount}</strong>{' '}
                  {recordWord(view === 'month' ? selectedEntries.length : visibleCount, language)}
                  {t('. Оставь немного времени для себя.')}
                </>
              ) : uncertainGoogle ? (
                t('Обновляем расписание. Дождись синхронизации.')
              ) : (
                t('Пока всё свободно. Начни с одного важного дела.')
              )}
            </p>
            <small>{t('При редактировании повторения изменится только выбранная запись.')}</small>
          </section>
          <section className="panel cal-backlog">
            <div className="cal-section-head">
              <h2>{t('Без даты')}</h2>
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
              <p>{t('Все дела уже нашли своё место в расписании.')}</p>
            )}
            {noDateTasks.length > 4 ? (
              <small>
                {t('Ещё {count} в разделе «Мой день»', { count: noDateTasks.length - 4 })}
              </small>
            ) : null}
          </section>
        </div>
      </details>
      {eventPicker && isMobile && view === 'week' ? (
        <Dialog
          title={t('Пересекающиеся события')}
          className="cal-event-picker"
          onClose={() => setEventPicker(null)}
        >
          <p className="cal-picker-description">
            {formatDate(
              eventPicker.date,
              { weekday: 'long', day: 'numeric', month: 'long' },
              language,
            )}
            {t('. Выбери запись, чтобы посмотреть подробности или изменить её.')}
          </p>
          <div className="cal-picker-list">
            {pickerEntries.map((entry) => (
              <button
                key={entry.key}
                type="button"
                className="cal-picker-entry"
                style={calendarEntryStyle(entry)}
                onClick={() => {
                  setEventPicker(null);
                  editEntry(entry);
                }}
                aria-label={occurrenceLabel(entry, language)}
              >
                <span className="cal-picker-color" aria-hidden="true" />
                <span className="cal-picker-copy">
                  <strong>{entry.title}</strong>
                  <span>
                    {entry.allDay
                      ? t('Весь день')
                      : entry.start === null
                        ? t('Без времени')
                        : `${entryTime(entry, 'start')}–${entryTime(entry, 'end')}`}
                    {entry.source === 'google' && entry.event.readOnly
                      ? t(' · Только просмотр')
                      : ''}
                  </span>
                </span>
                <ChevronRight size={18} aria-hidden="true" />
              </button>
            ))}
            {!pickerEntries.length ? (
              <p className="cal-picker-description">
                {t(
                  'Эти события уже изменились. Закрой список и выбери запись в обновлённом календаре.',
                )}
              </p>
            ) : null}
          </div>
          <div className="dialog-actions">
            <button
              type="button"
              className="button button-secondary"
              onClick={() => setEventPicker(null)}
            >
              {t('Закрыть список')}
            </button>
          </div>
        </Dialog>
      ) : null}
      {dragPreview ? (
        <>
          <div
            className={`cal-drag-ghost ${dragPreview.saving ? 'cal-drag-saving' : ''}`}
            style={{
              width: dragPreview.width,
              transform: `translate3d(${dragPreview.x}px, ${dragPreview.y}px, 0)`,
            }}
            aria-hidden="true"
          >
            <strong>{dragPreview.title}</strong>
            <span>
              {dragPreview.saving
                ? t('Сохраняем перенос…')
                : `${formatDate(dragPreview.date, { day: 'numeric', month: 'short' }, language)}${dragPreview.minutes === null ? ` · ${t('Весь день')}` : ` · ${formatTime(dragPreview.minutes)}`}`}
            </span>
          </div>
          {dragPreview.edge && !dragPreview.saving ? (
            <div
              className={`cal-drag-edge cal-drag-edge-${dragPreview.edge < 0 ? 'left' : 'right'}`}
              aria-hidden="true"
            >
              {dragPreview.edge < 0 ? <ChevronLeft size={20} /> : <ChevronRight size={20} />}
              {t(
                view === 'week'
                  ? dragPreview.edge < 0
                    ? 'Предыдущая неделя'
                    : 'Следующая неделя'
                  : dragPreview.edge < 0
                    ? 'Предыдущий день'
                    : 'Следующий день',
              )}
            </div>
          ) : null}
          <span className="visually-hidden" role="status">
            {dragPreview.saving
              ? t('Сохраняем перенос…')
              : t('Новая позиция: {p0}, {p1}', {
                  p0: formatDate(dragPreview.date, { day: 'numeric', month: 'long' }, language),
                  p1:
                    dragPreview.minutes === null ? t('Весь день') : formatTime(dragPreview.minutes),
                })}
          </span>
        </>
      ) : null}
      {preview ? (
        <EventPreviewDialog
          entry={previewEntry}
          date={preview.date}
          timeZone={timeZone}
          onClose={() => setPreview(null)}
          onEdit={beginEditing}
          onGoogleTaskToggle={onGoogleTaskToggle}
          taskBusy={Boolean(
            previewEntry?.source === 'google' && busyGoogleTaskIds?.has(previewEntry.event.id),
          )}
          onEnableGoogleTasks={onEnableGoogleTasks}
        />
      ) : null}
    </div>
  );
}
