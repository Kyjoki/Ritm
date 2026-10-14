import test from 'node:test';
import assert from 'node:assert/strict';
import { translate, normalizeLanguage, localeFor } from '../src/lib/i18n.tsx';
import { coreEnglish } from '../src/locales/core.ts';
import { calendarEnglish } from '../src/locales/calendar.ts';
import { settingsAssistantEnglish } from '../src/locales/settings-assistant.ts';
import { formatDate, durationText, formatTime } from '../src/lib/date.ts';
import {
  recordWord,
  startOfWeek,
  formatDate as formatCalendarDate,
} from '../src/features/calendar-utils.ts';

test('translation changes interface text while interpolation preserves personal text verbatim', () => {
  const title = 'Купить акции <script> $& {name}';
  assert.equal(translate('en', 'Открыть задачу: {title}', { title }), 'Open task: ' + title);
  assert.equal(translate('ru', 'Открыть задачу: {title}', { title }), 'Открыть задачу: ' + title);
  assert.equal(translate('en', '{completed} из {total}', { completed: 2, total: 5 }), '2 of 5');
  assert.equal(translate('en', 'Личный авторский текст'), 'Личный авторский текст');
  assert.equal(translate('en', 'Мой день'), 'My day');
  assert.equal(translate('ru', 'Мой день'), 'Мой день');
  assert.equal(normalizeLanguage('en'), 'en');
  assert.equal(normalizeLanguage('fr'), 'ru');
  assert.equal(localeFor('en'), 'en-US');
});
test('each locale catalog preserves all dynamic placeholders and has nonempty translations', () => {
  const placeholders = (value: string) =>
    [...value.matchAll(/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g)].map((m) => m[1]).sort();
  for (const catalog of [coreEnglish, calendarEnglish, settingsAssistantEnglish]) {
    for (const [source, translated] of Object.entries(catalog)) {
      assert.ok(translated.trim(), source);
      assert.deepEqual(
        placeholders(translated),
        placeholders(source),
        'Placeholder mismatch: ' + source,
      );
    }
  }
});
test('date and duration labels follow language while Sunday weeks and AM/PM stay stable', () => {
  assert.equal(formatDate('2026-10-14', { month: 'long' }, 'en'), 'October');
  assert.equal(formatDate('2026-10-14', { month: 'long' }, 'ru'), 'октябрь');
  assert.equal(formatCalendarDate('2026-10-14', { weekday: 'short' }, 'en'), 'Wed');
  assert.equal(durationText(90, 'en'), '1 h 30 min');
  assert.equal(durationText(90, 'ru'), '1 ч 30 мин');
  assert.equal(recordWord(2, 'en'), 'entries');
  assert.equal(recordWord(2, 'ru'), 'записи');
  assert.equal(startOfWeek('2026-10-14'), '2026-10-11');
  assert.equal(formatTime('13:30'), '1:30 PM');
});
