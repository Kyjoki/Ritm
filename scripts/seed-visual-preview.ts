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
