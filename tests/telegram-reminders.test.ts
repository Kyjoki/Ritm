import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createTelegramReminderRunner,
  googleReminders,
  localReminders,
  localStart,
  reminderText,
} from '../server/telegram-reminders.ts';
import type { GoogleCalendarResult, Task } from '../shared/types.ts';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';
import { SqliteRuntimeState } from '../server/runtime-state.ts';

const zone = 'Asia/Qyzylorda';
const instant = Date.parse('2026-10-27T05:50:00Z'); // 10:50 local
function task(overrides: Partial<Task> = {}): Task {
  return {
    id: 'task-1',
    title: 'Gym',
    description: '',
    date: '2026-10-27',
    time: '11:00',
    duration: 120,
    priority: 'normal',
    repeat: 'none',
    kind: 'task',
    completed: false,
    calendarEntry: false,
    completedDates: [],
    createdAt: '2026-10-20T00:00:00Z',
    updatedAt: '2026-10-20T00:00:00Z',
    ...overrides,
  };
}
function result(events: GoogleCalendarResult['events'] = []): GoogleCalendarResult {
  return {
    events,
    from: '2026-10-26',
    to: '2026-10-29',
    timeZone: zone,
    fetchedAt: new Date(instant).toISOString(),
    partial: false,
  };
}
function event(
  id = 'g1',
  start = '2026-10-27T11:00:00+05:00',
): GoogleCalendarResult['events'][number] {
  return {
    id,
    source: 'google',
    calendarId: 'primary',
    title: '<Gym & Study>',
    description: '',
    etag: 'a',
    start: { dateTime: start },
    end: { dateTime: '2026-10-27T13:00:00+05:00' },
    timeZone: zone,
    allDay: false,
    busy: true,
    readOnly: false,
  };
}
function fixture() {
  const values = new Map<string, string>();
  const leases = new Set<string>();
  let clock = instant;
  let tasks = [task()];
  let events = result();
  let enabled = true;
  let googleStatus = 'connected';
  let failGoogle = false;
  let delivery: 'sent' | 'uncertain' | 'rejected' = 'sent';
  const sent: string[] = [];
  const runner = createTelegramReminderRunner({
    state: {
      getServerSecret: (key) => values.get(key) ?? null,
      setServerSecret: (key, value) => {
        values.set(key, value);
      },
      acquireLease: (key) => {
        if (leases.has(key)) return null;
        leases.add(key);
        return key;
      },
      releaseLease: (key) => {
        leases.delete(key);
      },
    },
    telegram: {
      reminderSnapshot: async () =>
        enabled ? { chatId: 42, settings: { leadMinutes: 10 } } : null,
      deliverReminder: async (text) => {
        sent.push(text);
        return delivery;
      },
    },
    store: { tasks: async () => tasks, settings: async () => ({ timeZone: zone, language: 'ru' }) },
    google: {
      status: async () => ({ status: googleStatus }),
      listEvents: async () => {
        if (failGoogle) throw new Error('Google unavailable');
        return events;
      },
    },
    now: () => clock,
  });
  return {
    runner,
    sent,
    values,
    setClock: (value: number) => {
      clock = value;
    },
    setTasks: (value: Task[]) => {
      tasks = value;
    },
    setEvents: (value: GoogleCalendarResult) => {
      events = value;
    },
    setEnabled: (value: boolean) => {
      enabled = value;
    },
    setGoogleStatus: (value: string) => {
      googleStatus = value;
    },
    setFailGoogle: (value: boolean) => {
      failGoogle = value;
    },
    setDelivery: (value: 'sent' | 'uncertain' | 'rejected') => {
      delivery = value;
    },
  };
}

test('timed local task sends once, persists claim and excludes date-only/completed tasks', async () => {
  const f = fixture();
  f.setTasks([
    task(),
    task({ id: 'date-only', time: null }),
    task({ id: 'done', completed: true }),
  ]);
  assert.equal((await f.runner()).sent, 1);
  assert.match(f.sent[0], /Через 10 минут\nGym\nСегодня, 11:00–13:00/);
  assert.equal((await f.runner()).sent, 0);
  assert.equal(f.sent.length, 1);
  assert.ok(
    [...f.values].some(([key, value]) => key.startsWith('telegram-reminder:') && value === 'sent'),
  );
});

test('Google instances, move, deletion, completion, all-day and disabled state', async () => {
  const f = fixture();
  f.setTasks([]);
  f.setEvents(
    result([
      event('instance-1'),
      { ...event('all-day'), allDay: true, start: { date: '2026-10-27' } },
      {
        ...event('completed'),
        googleTask: { id: 't', taskListId: 'l', etag: 'e', status: 'completed', connectionId: 'c' },
      },
    ]),
  );
  assert.equal((await f.runner()).sent, 1);
  assert.match(f.sent[0], /<Gym & Study>/); // literal text, no parse_mode
  f.setClock(instant + 60_000);
  f.setEvents(result([]));
  assert.equal((await f.runner()).sent, 0);
  f.setClock(instant + 10 * 60_000);
  f.setEvents(result([event('instance-1', '2026-10-27T11:10:00+05:00')]));
  assert.equal((await f.runner()).sent, 1); // new start yields a new key
  f.setEnabled(false);
  f.setClock(instant + 11 * 60_000);
  assert.equal((await f.runner()).sent, 0);
});

test('late run catches a short delay but does not send stale backlog', async () => {
  const f = fixture();
  f.setClock(instant + 4 * 60_000);
  assert.equal((await f.runner()).sent, 1);
  const stale = fixture();
  stale.setClock(instant + 6 * 60_000);
  assert.equal((await stale.runner()).sent, 0);
});

test('Google errors do not advance progress and uncertain Telegram delivery is never blindly retried', async () => {
  const f = fixture();
  f.setFailGoogle(true);
  await assert.rejects(f.runner(), /Google unavailable/);
  assert.equal(f.values.has('telegram-reminder-cursor'), false);
  f.setFailGoogle(false);
  f.setDelivery('uncertain');
  assert.equal((await f.runner()).sent, 0);
  assert.equal(f.sent.length, 1);
  assert.equal((await f.runner()).sent, 0);
  assert.equal(f.sent.length, 1);
});

test('timezone and recurring local occurrence calculation', () => {
  assert.equal(localStart('2026-10-27', '11:00', zone), Date.parse('2026-10-27T06:00:00Z'));
  assert.equal(
    localReminders(
      [task({ repeat: 'weekly', date: '2026-10-20', completedDates: ['2026-10-20'] })],
      ['2026-10-27'],
      zone,
    ).length,
    1,
  );
  assert.equal(
    localReminders(
      [task({ repeat: 'weekly', completedDates: ['2026-10-27'] })],
      ['2026-10-27'],
      zone,
    ).length,
    0,
  );
  assert.equal(googleReminders(result([event('one'), event('two')])).length, 2);
  assert.match(
    reminderText(
      { key: 'x', title: '<b>&', start: instant + 600_000, end: instant + 1_200_000 },
      10,
      zone,
      'en',
      instant,
    ),
    /<b>&/,
  );
});

test('scheduler endpoint rejects missing/wrong secret and accepts server secret', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-reminder-route-'));
  const secret = 'r'.repeat(40);
  const instance = createApp({
    dataDir,
    seed: false,
    env: {
      NODE_ENV: 'test',
      APP_ORIGIN: 'https://ritm.example.com',
      SECRET_ENCRYPTION_KEY: Buffer.alloc(32, 4).toString('base64'),
      REMINDER_SCHEDULER_SECRET: secret,
    },
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    rmSync(dataDir, { recursive: true, force: true });
  });
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/integrations/telegram/reminders/run`;
  const call = (value?: string) =>
    fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Upstash-Schedule-Id': 'ritm-telegram-reminders',
        ...(value ? { 'x-ritm-reminder-secret': value } : {}),
      },
      body: '{}',
    });
  assert.equal((await call()).status, 401);
  assert.equal((await call('x'.repeat(40))).status, 401);
  assert.equal((await call(secret)).status, 200);
});

test('reminder cursor and delivery claims survive a runtime restart', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-reminder-state-'));
  try {
    const first = new SqliteRuntimeState(directory);
    first.setServerSecret('telegram-reminder-cursor', String(instant));
    first.setServerSecret('telegram-reminder:key', 'sent');
    first.close();
    const second = new SqliteRuntimeState(directory);
    assert.equal(second.getServerSecret('telegram-reminder-cursor'), String(instant));
    assert.equal(second.getServerSecret('telegram-reminder:key'), 'sent');
    second.close();
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
