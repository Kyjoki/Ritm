import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { GoogleCalendarStatus, TelegramStatus } from '../shared/types.ts';
import { ISSUE_MESSAGES, TIME_ZONES } from '../src/features/settings/settings-logic.ts';
import {
  SIDEBAR_LABELS,
  THEME_LABELS,
  googleSummary,
  leadLabel,
  openAiSummary,
  telegramSummary,
  workDaySummary,
} from '../src/features/settings/settings-summaries.ts';
import { settingsPageEnglish } from '../src/locales/settings-page.ts';
import { settingsAssistantEnglish } from '../src/locales/settings-assistant.ts';
import { coreEnglish } from '../src/locales/core.ts';

const google = (overrides: Partial<GoogleCalendarStatus>): GoogleCalendarStatus => ({
  configured: true,
  status: 'disconnected',
  mode: 'readwrite',
  calendarId: 'primary',
  lastFetchedAt: null,
  ...overrides,
});

test('the workday summary uses an en dash between the times', () => {
  assert.equal(workDaySummary({ workDayStart: '09:00', workDayEnd: '21:00' }), '09:00 – 21:00');
});

test('a lead time reads as "at the start" or as minutes before', () => {
  assert.deepEqual(leadLabel(0), { source: 'В момент начала' });
  assert.deepEqual(leadLabel(15), { source: 'за {minutes} мин', values: { minutes: 15 } });
});

test('OpenAI: not configured, saved and managed by the server', () => {
  assert.deepEqual(openAiSummary({ configured: false, model: 'm', source: 'none' }), {
    tone: 'idle',
    label: 'Не настроен',
    cta: 'Добавить ключ',
  });
  assert.equal(openAiSummary({ configured: true, model: 'm', source: 'saved' }).tone, 'ok');
  const managed = openAiSummary({ configured: true, model: 'm', source: 'environment' });
  assert.equal(managed.label, 'Задан сервером');
  assert.equal(managed.cta, null);
});

test('Google: needs a client, needs sign-in, reconnect, connected, unknown', () => {
  const missingClient = googleSummary(google({ configured: false }), false, false);
  assert.deepEqual([missingClient.tone, missingClient.action], ['warn', 'setup']);
  const off = googleSummary(google({}), true, false);
  assert.deepEqual([off.label, off.action], ['Не подключён', 'connect']);
  const reauth = googleSummary(google({ status: 'reauth_required' }), true, false);
  assert.deepEqual([reauth.tone, reauth.cta], ['warn', 'Переподключить']);
  const connected = googleSummary(google({ status: 'connected' }), true, false);
  assert.deepEqual([connected.tone, connected.cta, connected.action], ['ok', null, null]);
  const unknown = googleSummary(google({ status: 'connected' }), true, true);
  assert.equal(unknown.label, 'Статус не обновился');
});

test('Telegram: loading, failed, no bot, bot without chat, linked', () => {
  const status = (value: Partial<TelegramStatus>): TelegramStatus => ({
    configured: false,
    linked: false,
    ...value,
  });
  assert.equal(telegramSummary(null, false).label, 'Проверяем…');
  assert.equal(telegramSummary(null, true).tone, 'warn');
  assert.equal(telegramSummary(status({}), false).cta, 'Добавить бота');
  assert.equal(telegramSummary(status({ configured: true }), false).cta, 'Привязать чат');
  assert.equal(telegramSummary(status({ configured: true, linked: true }), false).tone, 'ok');
});

test('every Russian string passed to t() in the settings UI has an English translation', () => {
  const directory = join(import.meta.dirname, '..', 'src', 'features', 'settings');
  const files = readdirSync(directory)
    .filter((name) => name.endsWith('.tsx'))
    .map((name) => join(directory, name));
  files.push(join(import.meta.dirname, '..', 'src', 'features', 'SettingsPage.tsx'));
  const catalog = { ...coreEnglish, ...settingsAssistantEnglish, ...settingsPageEnglish };
  const missing: string[] = [];
  for (const file of files) {
    for (const match of readFileSync(file, 'utf8').matchAll(/\bt\(\s*'((?:[^'\\]|\\.)*)'/g)) {
      const key = match[1].replace(/\\'/g, "'");
      if (/[А-Яа-я]/.test(key) && !(key in catalog)) missing.push(key);
    }
  }
  assert.deepEqual(missing, []);
});

test('strings that reach t() through lookup tables are translated too', () => {
  const catalog: Record<string, string> = {
    ...coreEnglish,
    ...settingsAssistantEnglish,
    ...settingsPageEnglish,
  };
  const sources = [
    ...Object.values(ISSUE_MESSAGES),
    ...Object.values(THEME_LABELS),
    ...Object.values(SIDEBAR_LABELS),
    ...TIME_ZONES.map((zone) => zone.name),
  ];
  assert.deepEqual(
    sources.filter((source) => !(source in catalog)),
    [],
  );
});
