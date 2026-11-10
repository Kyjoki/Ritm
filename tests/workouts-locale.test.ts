import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { workoutsEnglish } from '../src/locales/workouts.ts';
import { translate } from '../src/lib/i18n.tsx';

const root = join(import.meta.dirname, '..', 'src');
const files = [
  ...readdirSync(join(root, 'features', 'workouts'))
    .filter((name) => /\.tsx?$/.test(name))
    .map((name) => join(root, 'features', 'workouts', name)),
  join(root, 'features', 'WorkoutsPage.tsx'),
];
const placeholders = (value: string) =>
  [...value.matchAll(/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g)].map((match) => match[1]).sort();

test('every Russian string of the workouts UI has an English translation with the same placeholders', () => {
  const used = new Set<string>();
  for (const file of files)
    for (const match of readFileSync(file, 'utf8').matchAll(/\bt\(\s*'((?:[^'\\]|\\.)*)'/g))
      used.add(match[1]);
  assert.ok(used.size > 100);
  const missing = [...used].filter((source) => !(source in workoutsEnglish));
  assert.deepEqual(missing, []);
  for (const [source, english] of Object.entries(workoutsEnglish)) {
    assert.ok(english.trim(), source);
    assert.deepEqual(placeholders(english), placeholders(source), source);
  }
});

test('workout strings translate through the shared mechanism and keep names verbatim', () => {
  assert.equal(translate('en', 'Тренировки'), 'Workouts');
  assert.equal(translate('ru', 'Тренировки'), 'Тренировки');
  assert.equal(
    translate('en', 'Привычка «{title}» отмечена', { title: 'Жим {x}' }),
    'Habit “Жим {x}” ticked',
  );
});
