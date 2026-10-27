import assert from 'node:assert/strict';
import test from 'node:test';
import { LatestRead, RefreshGate } from '../src/lib/latest-read';
import { dateTimeFormatter, numberFormatter } from '../src/lib/intl-formatters';
import { dateInZone, minutesInZone, formatDate } from '../src/lib/date';

test('a slower superseded read cannot overwrite a later response', async () => {
  const read = new LatestRead();
  let completeOld!: (value: string) => void;
  let visible = '';
  const oldSignal = read.start();
  const oldResponse = new Promise<string>((resolve) => {
    completeOld = resolve;
  }).then((value) => {
    if (read.isCurrent(oldSignal)) visible = value;
  });
  const currentSignal = read.start();
  if (read.isCurrent(currentSignal)) visible = 'new';
  completeOld('old');
  await oldResponse;
  assert.equal(visible, 'new');
  assert.equal(oldSignal.aborted, true);
  assert.equal(read.isCurrent(currentSignal), true);
});

test('cleanup and mutations invalidate pending reads, and reconnect can read again', () => {
  const read = new LatestRead();
  const pending = read.start();
  read.cancel();
  read.cancel();
  assert.equal(pending.aborted, true);
  assert.equal(read.isCurrent(pending), false);
  const resumed = read.start();
  assert.equal(read.isCurrent(resumed), true);
  assert.equal(read.isCurrent(pending), false);
});

test('formatter reuse keeps locale, currency and precision isolated', () => {
  const integer = {
    style: 'currency',
    currency: 'KZT',
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  } as const;
  const fractional = { ...integer, minimumFractionDigits: 2 };
  assert.equal(
    numberFormatter('ru-RU', integer),
    numberFormatter('ru-RU', {
      maximumFractionDigits: 2,
      currency: 'KZT',
      style: 'currency',
      minimumFractionDigits: 0,
    }),
  );
  for (const locale of ['ru-RU', 'en-US']) {
    for (const options of [integer, fractional, { ...fractional, currency: 'USD' }]) {
      assert.equal(
        numberFormatter(locale, options).format(123.45),
        new Intl.NumberFormat(locale, options).format(123.45),
      );
    }
  }
});

test('cached dates preserve timezone boundaries, language and DST output', () => {
  const instant = new Date('2026-10-27T20:05:00Z');
  assert.equal(dateInZone('Asia/Qyzylorda', instant), '2026-10-28');
  assert.equal(minutesInZone('Asia/Qyzylorda', instant), 65);
  assert.equal(dateInZone('America/New_York', instant), '2026-10-27');
  for (const timeZone of ['UTC', 'Asia/Qyzylorda', 'America/New_York']) {
    const options = { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' } as const;
    assert.equal(
      dateTimeFormatter('en-US', options).format(instant),
      new Intl.DateTimeFormat('en-US', options).format(instant),
    );
  }
  for (const language of ['ru', 'en'] as const) {
    assert.equal(
      formatDate('2026-10-27', { weekday: 'long' }, language),
      new Intl.DateTimeFormat(language === 'en' ? 'en-US' : 'ru-RU', { weekday: 'long' }).format(
        new Date('2026-10-27T12:00:00'),
      ),
    );
  }
});

test('reconciliation waits for every parallel write before reading a snapshot', () => {
  const gate = new RefreshGate();
  const read = new LatestRead();
  gate.activate();
  assert.equal(gate.request(), true);
  const stale = read.start();
  read.cancel();
  gate.beginWrite(); // A
  gate.beginWrite(); // B
  assert.equal(gate.request(), false); // A fails and requests reconciliation.
  assert.equal(gate.endWrite(), false); // B is still pending.
  assert.equal(gate.request(), false); // Focus/manual retry must also wait.
  assert.equal(gate.endWrite(), true); // Exactly one queued reconciliation.
  assert.equal(gate.writing, false);
  assert.equal(read.isCurrent(stale), false);
  assert.equal(gate.endWrite(), false);
});

test('a hidden page queues late write recovery until its Activity reconnects', () => {
  const gate = new RefreshGate();
  gate.activate();
  gate.beginWrite();
  gate.deactivate();
  assert.equal(gate.request(), false); // Late failure callback after cleanup.
  assert.equal(gate.endWrite(), false);
  gate.activate();
  assert.equal(gate.request(), true); // The normal reconnect read consumes recovery.
  assert.equal(gate.endWrite(), false);
});

test('reconnecting during a write waits rather than reading an older server version', () => {
  const gate = new RefreshGate();
  gate.activate();
  gate.beginWrite();
  gate.deactivate();
  gate.activate();
  assert.equal(gate.request(), false);
  assert.equal(gate.endWrite(), true);
  gate.beginWrite();
  assert.equal(gate.endWrite(), false); // Successful write alone does not cause a redundant GET.
});

test('creating before the initial snapshot cancels the old read and queues a complete snapshot', () => {
  const gate = new RefreshGate();
  const read = new LatestRead();
  gate.activate();
  assert.equal(gate.request(), true);
  const initial = read.start();
  read.cancel();
  gate.beginWrite(true); // Creating with no initial list must not leave only the new item visible.
  assert.equal(gate.endWrite(), true);
  assert.equal(gate.request(), true);
  const reconciliation = read.start();
  assert.equal(read.isCurrent(initial), false);
  assert.equal(read.isCurrent(reconciliation), true);
  assert.equal(gate.endWrite(), false);
});

test('initial snapshot recovery survives hiding before the create finishes', () => {
  const gate = new RefreshGate();
  gate.activate();
  gate.beginWrite(true);
  gate.deactivate();
  assert.equal(gate.endWrite(), false);
  gate.activate();
  assert.equal(gate.request(), true);
  gate.beginWrite(false); // A later write after the initial snapshot needs no redundant reload.
  assert.equal(gate.endWrite(), false);
});
