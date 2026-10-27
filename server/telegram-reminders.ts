import { createHash } from 'node:crypto';
import type { GoogleCalendarResult, Task } from '../shared/types.ts';
import { REMINDER_FAILURE_NAME, REMINDER_HEARTBEAT_NAME } from './telegram.ts';

const MAX_LATE_MS = 5 * 60_000;
const CURSOR_NAME = 'telegram-reminder-cursor';
const LEASE_NAME = 'telegram-reminder-run';
type State = {
  getServerSecret(name: string): Promise<string | null> | string | null;
  setServerSecret(name: string, value: string): Promise<void> | void;
  acquireLease(name: string, ttlMs: number): Promise<string | null> | string | null;
  releaseLease(name: string, token: string): Promise<void> | void;
};
type Reminder = { key: string; title: string; start: number; end: number };

export function localDateAt(instant: number, timeZone: string) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(instant));
}
function localParts(instant: number, timeZone: string) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(instant));
  const part = (name: string) => Number(parts.find((item) => item.type === name)?.value);
  return {
    year: part('year'),
    month: part('month'),
    day: part('day'),
    hour: part('hour'),
    minute: part('minute'),
    second: part('second'),
  };
}
export function localStart(date: string, time: string, timeZone: string) {
  const [year, month, day] = date.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  const intended = Date.UTC(year, month - 1, day, hour, minute);
  let guess = intended;
  for (let iteration = 0; iteration < 4; iteration++) {
    const actual = localParts(guess, timeZone);
    const offset =
      Date.UTC(
        actual.year,
        actual.month - 1,
        actual.day,
        actual.hour,
        actual.minute,
        actual.second,
      ) - guess;
    guess = intended - offset;
  }
  const actual = localParts(guess, timeZone);
  return actual.year === year &&
    actual.month === month &&
    actual.day === day &&
    actual.hour === hour &&
    actual.minute === minute
    ? guess
    : null;
}
function occursOn(task: Task, date: string) {
  if (!task.date || date < task.date) return false;
  if (task.date === date) return true;
  if (task.repeat === 'daily') return true;
  if (task.repeat === 'weekly')
    return (Date.parse(date) - Date.parse(task.date)) % (7 * 86_400_000) === 0;
  return task.repeat === 'monthly' && task.date.slice(8) === date.slice(8);
}
export function localReminders(tasks: Task[], dates: string[], timeZone: string): Reminder[] {
  const reminders: Reminder[] = [];
  for (const task of tasks) {
    if (!task.time || !task.date) continue;
    for (const date of dates) {
      if (
        !occursOn(task, date) ||
        task.completedDates.includes(date) ||
        (task.repeat === 'none' && task.completed)
      )
        continue;
      const start = localStart(date, task.time, timeZone);
      if (start === null) continue;
      reminders.push({
        key: `task:${task.id}:${date}`,
        title: task.title,
        start,
        end: start + task.duration * 60_000,
      });
    }
  }
  return reminders;
}
export function googleReminders(result: GoogleCalendarResult): Reminder[] {
  return result.events.flatMap((event) => {
    if (event.allDay || !event.start.dateTime || event.googleTask?.status === 'completed')
      return [];
    const start = Date.parse(event.start.dateTime);
    const end = event.end.dateTime ? Date.parse(event.end.dateTime) : start;
    return Number.isFinite(start)
      ? [{ key: `google:${event.id}`, title: event.title, start, end }]
      : [];
  });
}
export function reminderText(
  reminder: Reminder,
  leadMinutes: number,
  timeZone: string,
  language: string,
  now: number,
) {
  const locale = language === 'en' ? 'en-US' : 'ru-RU';
  const date = new Intl.DateTimeFormat(locale, { timeZone, day: 'numeric', month: 'long' }).format(
    new Date(reminder.start),
  );
  const time = (value: number) =>
    new Intl.DateTimeFormat(locale, {
      timeZone,
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).format(new Date(value));
  const today = localDateAt(now, timeZone) === localDateAt(reminder.start, timeZone);
  const heading =
    language === 'en'
      ? leadMinutes
        ? `🔔 In ${leadMinutes} minutes`
        : '🔔 Starting now'
      : leadMinutes
        ? `🔔 Через ${leadMinutes} минут`
        : '🔔 Сейчас';
  const day = today ? (language === 'en' ? 'Today' : 'Сегодня') : date;
  // No parse_mode: Telegram renders the title literally, including HTML/Markdown characters.
  const title = reminder.title.replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  return `${heading}\n${title}\n${day}, ${time(reminder.start)}–${time(reminder.end)}\n${language === 'en' ? 'Time zone' : 'Часовой пояс'}: ${timeZone}`;
}
export function createTelegramReminderRunner(options: {
  state: State;
  telegram: {
    reminderSnapshot(): Promise<{ settings: { leadMinutes: number }; chatId: number } | null>;
    deliverReminder(
      text: string,
      chatId: number,
    ): Promise<'sent' | 'disabled' | 'uncertain' | 'rejected'>;
  };
  store: {
    tasks(): Promise<Task[]> | Task[];
    settings():
      Promise<{ timeZone: string; language: string }> | { timeZone: string; language: string };
  };
  google: {
    status(): Promise<{ status: string }>;
    listEvents(input: {
      from: string;
      to: string;
      timeZone: string;
    }): Promise<GoogleCalendarResult>;
  };
  now?: () => number;
}) {
  const { state, telegram, store, google } = options;
  const clock = options.now ?? Date.now;
  return async function run(verifiedSchedule = true) {
    const lease = await state.acquireLease(LEASE_NAME, 45_000);
    if (!lease) return { busy: true, sent: 0 };
    let failureCode = 'internal_error';
    try {
      const current = clock();
      const snapshot = await telegram.reminderSnapshot();
      if (!snapshot) {
        if (verifiedSchedule) await state.setServerSecret(REMINDER_HEARTBEAT_NAME, String(current));
        return { busy: false, sent: 0 };
      }
      const settings = await store.settings();
      const cursor = Number(await state.getServerSecret(CURSOR_NAME));
      const from = Math.max(
        current - MAX_LATE_MS,
        Number.isFinite(cursor) && cursor > 0 ? cursor : current - MAX_LATE_MS,
      );
      const dates = [
        ...new Set(
          [current - 86_400_000, current, current + 86_400_000].map((value) =>
            localDateAt(value, settings.timeZone),
          ),
        ),
      ];
      const local = localReminders(await store.tasks(), dates, settings.timeZone);
      let remote: Reminder[] = [];
      failureCode = 'google_error';
      if ((await google.status()).status === 'connected') {
        const fromDate = localDateAt(current - 86_400_000, settings.timeZone);
        const toDate = localDateAt(current + 2 * 86_400_000, settings.timeZone);
        const result = await google.listEvents({
          from: fromDate,
          to: toDate,
          timeZone: settings.timeZone,
        });
        if (result.partial) throw new Error('Google Calendar returned a partial result');
        remote = googleReminders(result);
      }
      let sent = 0;
      let deliveryProblem: string | null = null;
      for (const reminder of [...local, ...remote]) {
        const due = reminder.start - snapshot.settings.leadMinutes * 60_000;
        if (due <= from || due > current || current - due > MAX_LATE_MS) continue;
        const key =
          'telegram-reminder:' +
          createHash('sha256')
            .update(
              `${snapshot.chatId}:${reminder.key}:${reminder.start}:${snapshot.settings.leadMinutes}`,
            )
            .digest('hex');
        const claim = await state.acquireLease(key, 30_000);
        if (!claim) continue;
        try {
          if (await state.getServerSecret(key)) continue;
          // Persist before the network call. A crash/timeout is treated as uncertain, not retried blindly.
          await state.setServerSecret(key, 'uncertain');
          failureCode = 'telegram_error';
          const result = await telegram.deliverReminder(
            reminderText(
              reminder,
              snapshot.settings.leadMinutes,
              settings.timeZone,
              settings.language,
              current,
            ),
            snapshot.chatId,
          );
          await state.setServerSecret(key, result);
          if (result === 'sent') sent++;
          if (result === 'rejected') deliveryProblem = 'telegram_rejected';
          if (result === 'uncertain') deliveryProblem = 'telegram_uncertain';
        } finally {
          await state.releaseLease(key, claim);
        }
      }
      await state.setServerSecret(CURSOR_NAME, String(current));
      if (verifiedSchedule) await state.setServerSecret(REMINDER_HEARTBEAT_NAME, String(current));
      await state.setServerSecret(
        REMINDER_FAILURE_NAME,
        deliveryProblem ? JSON.stringify({ at: current, code: deliveryProblem }) : '',
      );
      return { busy: false, sent };
    } catch (error) {
      await state.setServerSecret(
        REMINDER_FAILURE_NAME,
        JSON.stringify({ at: clock(), code: failureCode }),
      );
      throw error;
    } finally {
      await state.releaseLease(LEASE_NAME, lease);
    }
  };
}
