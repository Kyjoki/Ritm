import test from 'node:test';
import assert from 'node:assert/strict';
import type { Settings } from '../shared/types.ts';
import {
  applySettingsPatch,
  createSerialQueue,
  dayRangeIssue,
  diffPatch,
  isValidEmail,
  prepareSettingsPatch,
  profileInitials,
  rollbackSettingsPatch,
  timeZoneName,
  utcOffsetLabel,
  zoneClock,
} from '../src/features/settings/settings-logic.ts';

const base: Settings = {
  displayName: 'Максим',
  email: 'maks@example.com',
  theme: 'dark',
  sidebar: 'dark',
  language: 'ru',
  timeZone: 'Asia/Almaty',
  notifications: true,
  dailyBriefing: false,
  workDayStart: '09:00',
  workDayEnd: '18:00',
};

test('a patch carries only the fields that changed', () => {
  const patch = diffPatch(base, { theme: 'light', language: 'ru', notifications: true });
  assert.deepEqual(patch, { theme: 'light' });
});

test('an unchanged change produces an empty patch and no issue', () => {
  assert.deepEqual(prepareSettingsPatch(base, { theme: 'dark' }), { patch: {}, issue: null });
});

test('name and email are trimmed before they are compared and sent', () => {
  const { patch } = prepareSettingsPatch(base, {
    displayName: '  Максим К  ',
    email: ' maks@example.com ',
  });
  assert.deepEqual(patch, { displayName: 'Максим К' });
});

test('an empty or overlong name is not sent', () => {
  assert.equal(prepareSettingsPatch(base, { displayName: '   ' }).issue, 'name-required');
  assert.equal(prepareSettingsPatch(base, { displayName: 'я'.repeat(61) }).issue, 'name-too-long');
  assert.deepEqual(prepareSettingsPatch(base, { displayName: '   ' }).patch, {});
});

test('email may be empty but must otherwise be a valid address', () => {
  assert.equal(isValidEmail(''), true);
  assert.equal(isValidEmail('a@b.co'), true);
  assert.equal(isValidEmail('bad@'), false);
  assert.equal(isValidEmail('no-at.example.com'), false);
  assert.equal(prepareSettingsPatch(base, { email: 'bad@' }).issue, 'email-invalid');
  assert.deepEqual(prepareSettingsPatch(base, { email: '' }).patch, { email: '' });
});

test('the workday must end after it starts, checked against the saved other half', () => {
  assert.equal(dayRangeIssue('09:00', '18:00'), null);
  assert.equal(dayRangeIssue('18:00', '18:00'), 'day-order');
  assert.equal(dayRangeIssue('19:00', '18:00'), 'day-order');
  assert.equal(dayRangeIssue('9:00', '18:00'), 'time-invalid');
  assert.equal(dayRangeIssue('', '18:00'), 'time-invalid');
  assert.equal(prepareSettingsPatch(base, { workDayEnd: '08:30' }).issue, 'day-order');
  assert.equal(prepareSettingsPatch(base, { workDayStart: '18:30' }).issue, 'day-order');
  assert.deepEqual(prepareSettingsPatch(base, { workDayEnd: '20:00' }).patch, {
    workDayEnd: '20:00',
  });
});

test('moving both ends together is valid when the new range is', () => {
  const { patch, issue } = prepareSettingsPatch(base, {
    workDayStart: '19:00',
    workDayEnd: '22:00',
  });
  assert.equal(issue, null);
  assert.deepEqual(patch, { workDayStart: '19:00', workDayEnd: '22:00' });
});

test('an unknown time zone is rejected and a known one passes', () => {
  assert.equal(prepareSettingsPatch(base, { timeZone: 'Mars/Olympus' }).issue, 'zone-invalid');
  assert.deepEqual(prepareSettingsPatch(base, { timeZone: 'Europe/Berlin' }).patch, {
    timeZone: 'Europe/Berlin',
  });
});

test('applying a patch returns a new object and leaves the original alone', () => {
  const next = applySettingsPatch(base, { theme: 'light' });
  assert.notEqual(next, base);
  assert.equal(base.theme, 'dark');
  assert.equal(next.theme, 'light');
  assert.equal(next.displayName, base.displayName);
});

test('rollback restores only fields that still hold the failed value', () => {
  const optimistic = applySettingsPatch(base, { theme: 'light', language: 'en' });
  const newer = applySettingsPatch(optimistic, { language: 'ru' });
  const restored = rollbackSettingsPatch(newer, { theme: 'light', language: 'en' }, base);
  assert.equal(restored.theme, 'dark');
  assert.equal(restored.language, 'ru');
});

test('the serial queue runs tasks in order even when an earlier one is slower or fails', async () => {
  const run = createSerialQueue();
  const order: string[] = [];
  const slow = run(async () => {
    await new Promise((resolve) => setTimeout(resolve, 20));
    order.push('slow');
  });
  const failing = run(async () => {
    order.push('failing');
    throw new Error('boom');
  });
  const last = run(async () => {
    order.push('last');
    return 'done';
  });
  await slow;
  await assert.rejects(failing, /boom/);
  assert.equal(await last, 'done');
  assert.deepEqual(order, ['slow', 'failing', 'last']);
});

test('the offset follows daylight saving and the clock uses the zone', () => {
  const winter = new Date('2026-01-15T12:00:00Z');
  const summer = new Date('2026-07-15T12:00:00Z');
  assert.equal(utcOffsetLabel('Asia/Almaty', winter), 'UTC+5');
  assert.equal(utcOffsetLabel('Europe/Berlin', winter), 'UTC+1');
  assert.equal(utcOffsetLabel('Europe/Berlin', summer), 'UTC+2');
  assert.equal(utcOffsetLabel('Europe/London', winter), 'UTC+0');
  assert.equal(utcOffsetLabel('America/New_York', winter), 'UTC−5');
  assert.equal(zoneClock('Asia/Almaty', winter), '17:00');
  assert.equal(zoneClock('Nowhere/Land', winter), '--:--');
});

test('zone names and initials fall back sensibly', () => {
  assert.equal(timeZoneName('Asia/Almaty'), 'Алматы, Астана');
  assert.equal(timeZoneName('Pacific/Auckland'), 'Pacific/Auckland');
  assert.equal(profileInitials('Максим Кузнецов Иванов', 'Р'), 'МК');
  assert.equal(profileInitials('   ', 'Р'), 'Р');
});
