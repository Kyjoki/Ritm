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

type DemoOperation = [number, 'income' | 'expense', string, number, string?];
const dateDaysAgo = (days: number) => {
  const date = new Date(`${today}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
};
/** Fictional demo ledger: two currencies, deposits, stocks and three months of operations. */
function seedFinance() {
  const start = dateMonthsAgo(3);
  const kzt = store.createFinanceEntry({
    type: 'account',
    valueMinor: 283_000_00,
    currency: 'KZT',
    asOf: start,
    note: '',
  });
  const saving = store.createFinanceEntry({
    type: 'deposit',
    name: 'Накопления',
    valueMinor: 600_000_00,
    currency: 'KZT',
    asOf: start,
    note: '',
  });
  store.createFinanceEntry({
    type: 'deposit',
    name: 'Подушка',
    valueMinor: 150_000_00,
    currency: 'KZT',
    asOf: start,
    note: '',
  });
  const usd = store.createFinanceEntry({
    type: 'account',
    valueMinor: 700_00,
    currency: 'USD',
    asOf: start,
    note: '',
  });
  const stock = {
    type: 'stock' as const,
    currency: 'KZT' as const,
    asOf: dateDaysAgo(2),
    note: '',
    exchange: 'KASE' as const,
  };
  store.createFinanceEntry({
    ...stock,
    name: 'Halyk Bank',
    ticker: 'HSBK',
    quantity: 400,
    unitPriceMinor: 250_00,
    purchasePriceMinor: 218_00,
    valueMinor: 400 * 250_00,
  });
  store.createFinanceEntry({
    ...stock,
    name: 'Kcell',
    ticker: 'KCEL',
    quantity: 45,
    unitPriceMinor: 3_800_00,
    purchasePriceMinor: 3_560_00,
    valueMinor: 45 * 3_800_00,
  });
  const kztOps: DemoOperation[] = [
    [85, 'expense', 'Продукты', 21_350],
    [80, 'income', 'Зарплата', 320_000],
    [78, 'expense', 'Транспорт', 1_800],
    [74, 'expense', 'Дом', 24_600],
    [70, 'expense', 'Продукты', 17_900],
    [66, 'expense', 'Здоровье', 6_750],
    [62, 'expense', 'Развлечения', 5_200],
    [58, 'income', 'Подработка', 60_000],
    [55, 'expense', 'Покупки', 38_900],
    [50, 'expense', 'Продукты', 23_100],
    [46, 'expense', 'Кафе', 4_800],
    [45, 'income', 'Зарплата', 320_000],
    [41, 'expense', 'Продукты', 19_800],
    [38, 'expense', 'Транспорт', 2_300],
    [35, 'expense', 'Развлечения', 9_000],
    [30, 'expense', 'Дом', 7_900],
    [27, 'expense', 'Продукты', 26_400],
    [24, 'expense', 'Кафе', 3_100],
    [21, 'expense', 'Покупки', 64_900],
    [18, 'income', 'Подарок', 25_000],
    [16, 'expense', 'Здоровье', 35_000],
    [15, 'income', 'Зарплата', 320_000],
    [13, 'expense', 'Продукты', 22_750],
    [11, 'expense', 'Транспорт', 2_100],
    [9, 'expense', 'Кафе', 2_800],
    [8, 'income', 'Подработка', 40_000],
    [6, 'expense', 'Продукты', 24_300],
    [5, 'expense', 'Развлечения', 18_500],
    [4, 'expense', 'Дом', 25_800],
    [3, 'expense', 'Кафе', 5_600],
    [2, 'expense', 'Продукты', 20_900],
    [1, 'expense', 'Транспорт', 1_200],
    [0, 'expense', 'Покупки', 12_400],
    [20, 'expense', 'Комиссия', 500, saving.id],
  ];
  for (const [ago, type, category, amount, accountId] of kztOps)
    store.createFinanceEntry({
      type,
      amountMinor: amount * 100,
      currency: 'KZT',
      date: dateDaysAgo(ago),
      category,
      note: '',
      ...(accountId ? { accountId } : {}),
    });
  const usdOps: DemoOperation[] = [
    [60, 'income', 'Подработка', 350],
    [40, 'expense', 'Развлечения', 15],
    [22, 'expense', 'Покупки', 90],
    [7, 'income', 'Подработка', 420],
    [3, 'expense', 'Кафе', 25],
  ];
  for (const [ago, type, category, amount] of usdOps)
    store.createFinanceEntry({
      type,
      amountMinor: amount * 100,
      currency: 'USD',
      date: dateDaysAgo(ago),
      category,
      note: '',
    });
  for (const ago of [79, 49, 19])
    store.createFinanceEntry({
      type: 'transfer',
      amountMinor: 100_000_00,
      currency: 'KZT',
      date: dateDaysAgo(ago),
      fromAccountId: kzt.id,
      toAccountId: saving.id,
      note: '',
    });
  void usd;
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
  seedFinance();
} finally {
  store.close();
}
