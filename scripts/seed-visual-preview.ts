import { Store } from '../server/store';

const dataDir = process.env.DATA_DIR;
if (!dataDir || !dataDir.includes('ritm-visual-preview-'))
  throw new Error('Visual preview requires an isolated temporary data directory.');

const store = new Store(dataDir, true);
const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Qyzylorda' });
const dateMonthsAgo = (months: number) => {
  const date = new Date(`${today}T12:00:00Z`);
  date.setUTCMonth(date.getUTCMonth() - months);
  return date.toISOString().slice(0, 10);
};
const DAY_MS = 86_400_000;
const dayKey = (offset: number) =>
  new Date(Date.parse(`${today}T12:00:00Z`) + offset * DAY_MS).toISOString().slice(0, 10);
const wireDate = (key: string, hourUtc: number) =>
  `${key}T${String(hourUtc).padStart(2, '0')}:00:00Z`;
type DemoLift = [
  exerciseID: string,
  name: string,
  sets: number,
  reps: number,
  kg: number,
  rest: number,
];
const demoPrograms: Array<{ id: string; name: string; colorIndex: number; lifts: DemoLift[] }> = [
  {
    id: 'demo-chest',
    name: 'Грудь и трицепс',
    colorIndex: 0,
    lifts: [
      ['builtin.bench', 'Жим лёжа', 4, 8, 80, 180],
      ['builtin.incline', 'Жим гантелей на наклонной', 3, 10, 30, 120],
      ['builtin.fly', 'Разводка гантелей', 3, 12, 16, 90],
      ['builtin.french', 'Французский жим', 3, 10, 35, 90],
    ],
  },
  {
    id: 'demo-back',
    name: 'Спина и бицепс',
    colorIndex: 1,
    lifts: [
      ['builtin.row', 'Тяга штанги в наклоне', 4, 8, 70, 180],
      ['builtin.pullup', 'Подтягивания', 3, 8, 10, 120],
      ['builtin.hammer', 'Молотки', 3, 12, 14, 60],
    ],
  },
  {
    id: 'demo-legs',
    name: 'Ноги и плечи',
    colorIndex: 2,
    lifts: [
      ['builtin.squat', 'Присед со штангой', 4, 6, 100, 180],
      ['builtin.rdl', 'Румынская тяга', 3, 10, 80, 150],
      ['builtin.ohp', 'Жим стоя', 3, 10, 40, 120],
    ],
  },
];
/** Demo workouts only: three programs and six weeks of history, written like the iPhone writes them. */
function seedWorkouts(store: Store, habitID: string) {
  demoPrograms.forEach((program, order) =>
    store.putWorkout(
      'programs',
      program.id,
      {
        id: program.id,
        name: program.name,
        colorIndex: program.colorIndex,
        order,
        exercises: [],
        items: program.lifts.map(([exerciseID, , sets, reps, , rest], index) => ({
          id: `${program.id}-${index}`,
          exerciseID,
          sets,
          reps,
          restSeconds: rest,
        })),
      },
      null,
    ),
  );
  const weekday = new Date(`${today}T12:00:00Z`).getUTCDay();
  for (let week = 0; week < 6; week++)
    [1, 3, 5].forEach((day, slot) => {
      const offset = -weekday - 7 * week + day;
      if (offset > 0) return;
      const program = demoPrograms[(slot + week) % demoPrograms.length];
      const step = 2.5 * Math.floor((week + 1) / 2);
      const key = dayKey(offset);
      store.putWorkout(
        'sessions',
        `demo-session-${week}-${slot}`,
        {
          id: `demo-session-${week}-${slot}`,
          programID: program.id,
          programName: program.name,
          startedAt: wireDate(key, 4),
          endedAt: wireDate(key, 5),
          exercises: program.lifts.map(([exerciseID, name, sets, reps, kg]) => ({
            exerciseID,
            name,
            sets: Array.from({ length: sets }, (_, index) => ({
              weight: Math.max(0, kg - step - (index === sets - 1 && sets > 3 ? 2.5 : 0)),
              reps: reps - (week % 2 && index === sets - 1 ? 1 : 0),
            })),
          })),
        },
        null,
      );
    });
  store.putWorkout('settings', 'workouts', { linkedHabitID: habitID }, null);
}
try {
  const habits = [
    store.createHabit({ title: 'Gym', icon: 'activity', weekdays: [0, 1, 2, 3, 4, 5, 6] }),
    store.createHabit({ title: 'IELTS', icon: 'book', weekdays: [0, 1, 2, 3, 4, 5, 6] }),
    store.createHabit({
      title: 'Вода',
      icon: 'droplet',
      weekdays: [0, 1, 2, 3, 4, 5, 6],
      target: 8,
      unit: 'стаканов',
    }),
  ];
  seedWorkouts(store, habits[0].id);
  store.setHabitDay(habits[0].id, today, true, habits[0].updatedAt);
  store.setHabitProgress(habits[2].id, today, 5, habits[2].updatedAt);
  store.createFinanceEntry({
    type: 'account',
    valueMinor: 820_000_00,
    currency: 'KZT',
    asOf: dateMonthsAgo(5),
    note: '',
  });
  for (let month = 5; month >= 0; month--) {
    const date = dateMonthsAgo(month);
    store.createFinanceEntry({
      type: 'income',
      amountMinor: (210_000 + (5 - month) * 12_000) * 100,
      currency: 'KZT',
      date,
      category: 'Работа',
      note: '',
    });
    store.createFinanceEntry({
      type: 'expense',
      amountMinor: (74_000 + month * 5_000) * 100,
      currency: 'KZT',
      date,
      category: 'Покупки',
      note: '',
    });
  }
  store.createFinanceEntry({
    type: 'deposit',
    name: 'Накопления',
    valueMinor: 1_450_000_00,
    currency: 'KZT',
    asOf: today,
    note: '',
  });
} finally {
  store.close();
}
