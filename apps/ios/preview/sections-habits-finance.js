const weekdayNames = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
const financeKinds = {
  account: ['Основной счёт', 'wallet'],
  income: ['Доход', 'arrow-up-right'],
  expense: ['Расход', 'wallet'],
  deposit: ['Депозит', 'wallet'],
  stock: ['Акции', 'sparkles'],
  transfer: ['Перевод', 'refresh'],
};
const date = (key) => new Date(`${key}T12:00:00Z`);
const dateKey = (value) => value.toISOString().slice(0, 10);
const addDays = (key, count) => {
  const value = date(key);
  value.setUTCDate(value.getUTCDate() + count);
  return dateKey(value);
};
const target = (habit) => Math.max(1, Number(habit.target) || 1);
const scheduled = (habit, key) =>
  (habit.weekdays?.length ? habit.weekdays : [0, 1, 2, 3, 4, 5, 6]).includes(date(key).getUTCDay());
const done = (habit, key) => Number(habit.marks?.[key] || 0) >= target(habit);
function periodDates(state) {
  const anchor = state.hfHabitsAnchor || state.today;
  if (state.hfPeriod === 'month') {
    const value = date(anchor);
    value.setUTCDate(1);
    const result = [],
      month = value.getUTCMonth();
    while (value.getUTCMonth() === month) {
      result.push(dateKey(value));
      value.setUTCDate(value.getUTCDate() + 1);
    }
    return result;
  }
  const start = addDays(anchor, -date(anchor).getUTCDay());
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
}
function daySummary(habits, key) {
  const planned = habits.filter((habit) => scheduled(habit, key));
  return { planned: planned.length, completed: planned.filter((habit) => done(habit, key)).length };
}
function streak(habit, today, best = false) {
  let current = 0,
    highest = 0;
  if (best) {
    for (let i = 365; i >= 0; i--) {
      const key = addDays(today, -i);
      if (!scheduled(habit, key)) continue;
      current = done(habit, key) ? current + 1 : 0;
      highest = Math.max(highest, current);
    }
    return highest;
  }
  for (let i = 0; i < 366; i++) {
    const key = addDays(today, -i);
    if (!scheduled(habit, key) || (i === 0 && !done(habit, key))) continue;
    if (!done(habit, key)) break;
    current++;
  }
  return current;
}
function badgeIcon(ctx, habit) {
  return ctx.icon(
    ['grid', 'calendar', 'checklist', 'sparkles', 'wallet', 'clock'].includes(habit.icon)
      ? habit.icon
      : 'checklist',
  );
}
function habitEditor(ctx, habit) {
  const { html: h } = ctx;
  ctx.openModal({
    title: habit ? 'Изменить привычку' : 'Новая привычка',
    body: `<div class="stack"><label class="field">Название<input name="title" required maxlength="80" value="${h(habit?.title || '')}" placeholder="Например, читать 20 минут"></label>
      <div class="hf-form-grid"><label class="field">Цель за день<input name="target" type="number" min="1" max="10000" required value="${target(habit || {})}"></label><label class="field">Единица<input name="unit" maxlength="24" value="${h(habit?.unit || '')}" placeholder="минуты, стаканы"></label></div>
      <label class="field">Значок<select name="icon">${[
        ['checklist', 'Действие'],
        ['sparkles', 'Забота о себе'],
        ['clock', 'Время'],
        ['calendar', 'Обучение'],
      ]
        .map(
          ([value, label]) =>
            `<option value="${value}" ${habit?.icon === value ? 'selected' : ''}>${label}</option>`,
        )
        .join('')}</select></label>
      <fieldset class="hf-week-select"><legend>Дни недели</legend>${weekdayNames.map((name, i) => `<label><input name="weekday" type="checkbox" value="${i}" ${(habit?.weekdays || [0, 1, 2, 3, 4, 5, 6]).includes(i) ? 'checked' : ''}><span>${name}</span></label>`).join('')}</fieldset>
      <p class="caption muted">Изменения останутся только в этом макете.</p></div>`,
    onSubmit: (form) => {
      const title = String(form.get('title') || '').trim(),
        weekdays = form.getAll('weekday').map(Number);
      if (!title || !weekdays.length) {
        ctx.notify('Укажи название и хотя бы один день недели.');
        return;
      }
      const values = {
        title,
        weekdays,
        target: Math.max(1, Math.min(10000, Number(form.get('target')) || 1)),
        unit: String(form.get('unit') || '').trim(),
        icon: String(form.get('icon') || 'checklist'),
      };
      if (habit) Object.assign(habit, values);
      else
        ctx.state.habits.push({ id: `habit-${Date.now()}`, marks: {}, archived: false, ...values });
      ctx.closeModal();
      ctx.render();
      ctx.notify('Привычка сохранена в макете.');
    },
  });
}
function habitMark(ctx, habit, key) {
  if (key > ctx.state.today || !scheduled(habit, key) || habit.archived) return;
  if (target(habit) === 1) {
    habit.marks ??= {};
    habit.marks[key] = done(habit, key) ? 0 : 1;
    ctx.render();
    ctx.notify(habit.marks[key] ? 'Отметка добавлена в макете.' : 'Отметка снята.');
    return;
  }
  ctx.openModal({
    title: habit.title,
    body: `<p class="muted">${ctx.html(ctx.dateLabel(key))}</p><label class="field">Количество · цель ${target(habit)} ${ctx.html(habit.unit || '')}<input name="progress" type="number" min="0" max="${target(habit)}" required value="${Number(habit.marks?.[key] || 0)}"></label><p class="caption muted">Полное достижение цели отмечает день выполненным.</p>`,
    onSubmit: (form) => {
      habit.marks ??= {};
      habit.marks[key] = Math.max(0, Math.min(target(habit), Number(form.get('progress')) || 0));
      ctx.closeModal();
      ctx.render();
      ctx.notify('Количество сохранено в макете.');
    },
  });
}
export function renderHabits(ctx) {
  const { state: s, html: h, icon: i } = ctx;
  s.hfPeriod ??= 'week';
  s.hfHabitsAnchor ??= s.today;
  s.hfArchive ??= false;
  const habits = s.habits.filter((item) => Boolean(item.archived) === s.hfArchive),
    dates = periodDates(s);
  const elapsed = dates.filter((key) => key <= s.today),
    summaries = elapsed.map((key) => daySummary(habits, key));
  const planned = summaries.reduce((sum, item) => sum + item.planned, 0),
    completed = summaries.reduce((sum, item) => sum + item.completed, 0);
  const percent = planned ? Math.round((completed / planned) * 100) : 0;
  const today = daySummary(habits, s.today),
    current = Math.max(0, ...habits.map((item) => streak(item, s.today))),
    best = Math.max(0, ...habits.map((item) => streak(item, s.today, true)));
  const start = addDays(s.today, -date(s.today).getUTCDay()),
    week = Array.from({ length: 7 }, (_, index) => addDays(start, index));
  const fullDays = dates.map((key) => ({ ...daySummary(habits, key), key }));
  return `<header class="row between"><div><div class="eyebrow">RITM · Ежедневные привычки</div><h1 class="page-title">Привычки</h1></div><button class="icon-button hf-add" data-action="hf-habit-create" aria-label="Создать привычку">${i('plus')}</button></header>
    <p class="muted">Маленькие действия складываются в устойчивый ритм.</p>
    <section class="card stack hf-analytics"><div><div class="caption muted">История ${s.hfArchive ? 'архивных' : 'активных'} привычек</div><h2>Прогресс привычек</h2></div>
      <div class="row between hf-controls"><div class="segmented"><button data-action="hf-period-week" aria-pressed="${s.hfPeriod === 'week'}" class="${s.hfPeriod === 'week' ? 'active' : ''}">Неделя</button><button data-action="hf-period-month" aria-pressed="${s.hfPeriod === 'month'}" class="${s.hfPeriod === 'month' ? 'active' : ''}">Месяц</button></div><div class="row"><button class="icon-button" data-action="hf-period-prev" aria-label="Предыдущий период">${i('chevron-left')}</button><button class="icon-button" data-action="hf-period-next" aria-label="Следующий период">${i('chevron-right')}</button></div></div>
      <div class="caption muted">${h(ctx.dateLabel(dates[0]))} — ${h(ctx.dateLabel(dates.at(-1)))}</div>
      <div class="hf-gauge" aria-label="Выполнено ${completed} из ${planned}, ${percent} процентов"><svg viewBox="0 0 280 160" role="presentation"><path class="hf-gauge-track" d="M25 136 A115 115 0 0 1 255 136" pathLength="100"/><path class="hf-gauge-value" d="M25 136 A115 115 0 0 1 255 136" pathLength="100" style="stroke-dasharray:${percent} 100"/></svg><div><strong>${planned ? percent + '%' : '—'}</strong><span class="caption muted">${planned ? 'выполнено за период' : 'нет запланированных отметок'}</span></div></div>
      <div class="hf-metrics"><div class="metric"><span class="caption muted">Сегодня<br>выполнено</span><strong>${today.completed}<small> / ${today.planned}</small></strong></div><div class="metric"><span class="caption muted">Текущая<br>серия</span><strong>${current}<small> дн.</small></strong></div><div class="metric"><span class="caption muted">Лучшая<br>серия</span><strong>${best}<small> дн.</small></strong></div></div>
      <div class="hf-chart-section"><h3>Выполнение по дням</h3><div class="hf-bars ${s.hfPeriod === 'month' ? 'month' : ''}">${fullDays.map((day, index) => `<div class="hf-bar-column" title="${h(day.key)}: ${day.completed}/${day.planned}"><div class="hf-bar-track"><span style="height:${day.planned && day.key <= s.today ? (100 * day.completed) / day.planned : 0}%"></span></div><span class="caption muted">${s.hfPeriod === 'week' ? weekdayNames[date(day.key).getUTCDay()] : index % 5 === 0 ? date(day.key).getUTCDate() : ''}</span></div>`).join('')}</div></div>
      <div class="hf-chart-section"><h3>Карта регулярности</h3><div class="hf-heatmap-scroll"><div class="hf-heatmap">${weekdayNames.map((label) => `<span class="caption muted">${label}</span>`).join('')}${Array.from({ length: date(dates[0]).getUTCDay() }, () => '<span></span>').join('')}${fullDays.map((day) => `<button data-action="hf-review-day" data-date="${day.key}" class="hf-heat-cell ${day.key === s.today ? 'today' : ''}" style="--completion:${day.planned && day.key <= s.today ? day.completed / day.planned : 0}" aria-label="${h(ctx.dateLabel(day.key))}: выполнено ${day.completed} из ${day.planned}">${date(day.key).getUTCDate()}</button>`).join('')}</div></div><p class="caption muted">Нажми на день, чтобы посмотреть отметки.</p></div>
    </section>
    <div class="row between"><h2>${s.hfArchive ? 'Архив привычек' : 'Ваши привычки'}</h2><button class="pill" data-action="hf-archive-toggle">${s.hfArchive ? 'Активные' : 'Архив'}</button></div>
    ${habits.length ? habits.map((habit) => `<article class="card stack hf-habit"><div class="row between"><div class="row"><span class="hf-symbol">${badgeIcon(ctx, habit)}</span><div><h3>${h(habit.title)}</h3><div class="caption muted">${target(habit) > 1 ? `${target(habit)} ${h(habit.unit || 'за день')}` : 'Одно действие в день'} · Серия ${streak(habit, s.today)}</div></div></div><button class="icon-button" data-action="hf-habit-edit" data-id="${h(habit.id)}" aria-label="Изменить ${h(habit.title)}">${i('edit')}</button></div><div class="hf-week-scroll"><div class="hf-habit-week">${week.map((key) => `<button data-action="hf-habit-mark" data-id="${h(habit.id)}" data-date="${key}" class="hf-day-mark ${done(habit, key) ? 'done' : ''} ${key === s.today ? 'today' : ''}" ${key > s.today || !scheduled(habit, key) || habit.archived ? 'disabled' : ''} aria-label="${h(habit.title)}, ${h(ctx.dateLabel(key))}: ${Number(habit.marks?.[key] || 0)} из ${target(habit)}"><span class="caption">${weekdayNames[date(key).getUTCDay()]}</span><span class="hf-check">${done(habit, key) ? i('check') : Number(habit.marks?.[key] || 0) > 0 ? Number(habit.marks[key]) : date(key).getUTCDate()}</span></button>`).join('')}</div></div><div class="row between"><span class="caption muted">${habit.weekdays?.length === 7 ? 'Каждый день' : (habit.weekdays || []).map((day) => weekdayNames[day]).join(' · ')}</span><button class="pill" data-action="hf-habit-archive" data-id="${h(habit.id)}">${habit.archived ? 'Восстановить' : 'В архив'}</button>${habit.archived ? `<button class="icon-button" data-action="hf-habit-delete" data-id="${h(habit.id)}" aria-label="Удалить привычку">${i('trash')}</button>` : ''}</div></article>`).join('') : `<section class="card empty"><h3>${s.hfArchive ? 'Архив пуст' : 'Начните с одной привычки'}</h3><p class="muted">${s.hfArchive ? 'Здесь появятся привычки, которые вы уберёте в архив.' : 'Выберите действие, дни недели и цель.'}</p>${s.hfArchive ? '' : `<button class="primary" data-action="hf-habit-create">Создать привычку</button>`}</section>`}`;
}

function money(value, currency) {
  return new Intl.NumberFormat('ru-KZ', {
    style: 'currency',
    currency,
    maximumFractionDigits: 0,
  }).format(value);
}
function financeEditor(ctx, entry) {
  const { state: s, html: h } = ctx;
  const balances = s.finance.filter((item) => ['account', 'deposit'].includes(item.kind));
  ctx.openModal({
    title: entry ? 'Изменить запись' : 'Новая запись',
    body: `<div class="stack"><label class="field">Тип<select name="kind">${Object.entries(
      financeKinds,
    )
      .map(
        ([key, [label]]) =>
          `<option value="${key}" ${(entry?.kind || 'income') === key ? 'selected' : ''}>${label}</option>`,
      )
      .join(
        '',
      )}</select></label><label class="field">Название<input name="title" required maxlength="100" placeholder="Например, продукты" value="${h(entry?.title || '')}"></label><div class="hf-form-grid"><label class="field">Сумма<input name="amount" type="number" min="0" max="10000000000" step="0.01" required value="${entry?.amount ?? ''}"></label><label class="field">Валюта<select name="currency">${['KZT', 'USD', 'EUR'].map((value) => `<option ${value === (entry?.currency || s.hfCurrency) ? 'selected' : ''}>${value}</option>`).join('')}</select></label></div><label class="field">Дата<input type="date" name="date" required value="${h(entry?.date || s.today)}"></label><details class="hf-transfer-fields"><summary>Счета для перевода</summary><label class="field">Откуда<select name="fromId"><option value="">Выберите счёт</option>${balances.map((item) => `<option value="${h(item.id)}" ${entry?.fromId === item.id ? 'selected' : ''}>${h(item.title)} · ${h(item.currency)}</option>`).join('')}</select></label><label class="field">Куда<select name="toId"><option value="">Выберите счёт</option>${balances.map((item) => `<option value="${h(item.id)}" ${entry?.toId === item.id ? 'selected' : ''}>${h(item.title)} · ${h(item.currency)}</option>`).join('')}</select></label></details><p class="caption muted">Это демонстрационная запись. Банковских операций не будет. Для акций сумма означает текущую ручную оценку позиции.</p></div>`,
    onSubmit: (form) => {
      const values = {
        kind: String(form.get('kind')),
        title: String(form.get('title') || '').trim(),
        amount: Number(form.get('amount')),
        currency: String(form.get('currency')),
        date: String(form.get('date')),
        fromId: String(form.get('fromId') || ''),
        toId: String(form.get('toId') || ''),
      };
      if (
        !values.title ||
        !Number.isFinite(values.amount) ||
        values.amount < 0 ||
        values.amount > 1e10
      ) {
        ctx.notify('Проверь название и сумму.');
        return;
      }
      if (values.kind === 'transfer') {
        const from = balances.find((item) => item.id === values.fromId),
          to = balances.find((item) => item.id === values.toId);
        if (
          !from ||
          !to ||
          from.id === to.id ||
          from.currency !== values.currency ||
          to.currency !== values.currency
        ) {
          ctx.notify('Для перевода выбери два разных счёта в одной валюте.');
          return;
        }
      }
      if (
        values.kind === 'account' &&
        s.finance.some(
          (item) =>
            item.kind === 'account' && item.currency === values.currency && item.id !== entry?.id,
        )
      ) {
        ctx.notify('Основной счёт в этой валюте уже есть. Измени существующую запись.');
        return;
      }
      if (entry) Object.assign(entry, values);
      else s.finance.push({ id: `finance-${Date.now()}`, ...values });
      ctx.closeModal();
      ctx.render();
      ctx.notify('Запись сохранена в макете.');
    },
  });
}
function accountValue(entries, account, today) {
  return (
    account.amount +
    entries
      .filter((item) => item.date >= account.date && item.date <= today && item.id !== account.id)
      .reduce((sum, item) => {
        if (item.kind === 'transfer')
          return (
            sum +
            (item.toId === account.id ? item.amount : 0) -
            (item.fromId === account.id ? item.amount : 0)
          );
        if (account.kind === 'account')
          return (
            sum +
            (item.kind === 'income' ? item.amount : item.kind === 'expense' ? -item.amount : 0)
          );
        return sum;
      }, 0)
  );
}
export function renderFinance(ctx) {
  const { state: s, html: h, icon: i } = ctx;
  s.hfCurrency ??= 'KZT';
  s.hfFinanceSection ??= 'account';
  const entries = s.finance.filter((item) => item.currency === s.hfCurrency),
    month = s.today.slice(0, 7);
  const income = entries
      .filter((item) => item.kind === 'income' && item.date?.startsWith(month))
      .reduce((sum, item) => sum + item.amount, 0),
    expense = entries
      .filter((item) => item.kind === 'expense' && item.date?.startsWith(month))
      .reduce((sum, item) => sum + item.amount, 0);
  const accounts = entries.filter((item) => item.kind === 'account'),
    deposits = entries.filter((item) => item.kind === 'deposit'),
    stocks = entries.filter((item) => item.kind === 'stock');
  const accountTotal = accounts.reduce(
      (sum, item) => sum + accountValue(entries, item, s.today),
      0,
    ),
    depositTotal = deposits.reduce((sum, item) => sum + accountValue(entries, item, s.today), 0),
    stockTotal = stocks.reduce((sum, item) => sum + item.amount, 0);
  const total =
    s.hfFinanceSection === 'account'
      ? accountTotal
      : s.hfFinanceSection === 'deposits'
        ? depositTotal
        : s.hfFinanceSection === 'stocks'
          ? stockTotal
          : accountTotal + depositTotal + stockTotal;
  const names = {
    account: 'Основной счёт',
    deposits: 'Депозиты',
    stocks: 'Акции',
    all: 'Все активы',
  };
  const records = entries
    .filter(
      (item) =>
        s.hfFinanceSection === 'all' ||
        (s.hfFinanceSection === 'account'
          ? ['account', 'income', 'expense', 'transfer'].includes(item.kind)
          : s.hfFinanceSection === 'deposits'
            ? ['deposit', 'transfer'].includes(item.kind)
            : item.kind === 'stock'),
    )
    .sort((a, b) => b.date.localeCompare(a.date));
  const months = Array.from({ length: 6 }, (_, index) => {
    const value = date(s.today);
    value.setUTCDate(1);
    value.setUTCMonth(value.getUTCMonth() - 5 + index);
    const key = dateKey(value).slice(0, 7);
    return {
      label: new Intl.DateTimeFormat('ru', { month: 'short', timeZone: 'UTC' }).format(value),
      income: entries
        .filter((item) => item.kind === 'income' && item.date.startsWith(key))
        .reduce((sum, item) => sum + item.amount, 0),
      expense: entries
        .filter((item) => item.kind === 'expense' && item.date.startsWith(key))
        .reduce((sum, item) => sum + item.amount, 0),
    };
  });
  const maximum = Math.max(1, ...months.flatMap((item) => [item.income, item.expense]));
  const amount = (value) => money(value, s.hfCurrency);
  return `<header class="row between"><div><div class="eyebrow">RITM · Личные финансы</div><h1 class="page-title">Деньги под контролем</h1></div><button class="icon-button hf-add" data-action="hf-finance-create" aria-label="Добавить финансовую запись">${i('plus')}</button></header><p class="muted">Личные записи. Без подключения к банкам.</p>
    <div class="row between"><h2>Финансы</h2><div class="row hf-currencies">${['KZT', 'USD', 'EUR'].map((value) => `<button class="pill ${s.hfCurrency === value ? 'active' : ''}" aria-pressed="${s.hfCurrency === value}" data-action="hf-currency" data-currency="${value}">${value}</button>`).join('')}</div></div>
    <div class="hf-filter-scroll"><div class="segmented">${Object.entries(names)
      .map(
        ([key, label]) =>
          `<button data-action="hf-finance-section" data-section="${key}" class="${s.hfFinanceSection === key ? 'active' : ''}" aria-pressed="${s.hfFinanceSection === key}">${label}</button>`,
      )
      .join('')}</div></div>
    <section class="card stack hf-finance-overview"><div class="caption muted">${names[s.hfFinanceSection]} · ${h(ctx.dateLabel(s.today))}</div><strong class="hf-balance">${amount(total)}</strong><div class="hf-cash-metrics"><div><span class="caption muted">Доходы за месяц</span><strong class="hf-positive">+${amount(income)}</strong></div><div><span class="caption muted">Расходы за месяц</span><strong>−${amount(expense)}</strong></div></div><div class="row"><button class="pill" data-action="hf-finance-create">${i('plus')} Добавить запись</button></div></section>
    <section class="card stack"><div class="row between"><h2>Движение денег</h2><span class="caption muted">6 месяцев</span></div><div class="hf-money-chart">${months.map((item) => `<div class="hf-money-month"><div class="hf-money-bars"><span class="income" style="height:${(100 * item.income) / maximum}%" title="Доход ${amount(item.income)}"></span><span class="expense" style="height:${(100 * item.expense) / maximum}%" title="Расход ${amount(item.expense)}"></span></div><span class="caption muted">${h(item.label)}</span></div>`).join('')}</div><div class="row hf-chart-legend"><span><i></i>Доходы</span><span><i></i>Расходы</span></div>${income === 0 && expense === 0 ? '<p class="caption muted">За текущий месяц операций нет.</p>' : ''}</section>
    ${
      s.hfFinanceSection === 'all'
        ? `<section class="card stack"><h2>Распределение активов</h2>${[
            ['На счёте', accountTotal],
            ['Депозиты', depositTotal],
            ['Акции', stockTotal],
          ]
            .map(
              ([label, value]) =>
                `<div class="row between"><span class="muted">${label}</span><strong>${amount(value)}</strong></div>`,
            )
            .join('')}</section>`
        : ''
    }
    <section class="card stack"><div class="row between"><h2>Записи</h2><span class="caption muted">${records.length}</span></div>${records.length ? records.map((entry) => `<button class="hf-finance-record" data-action="hf-finance-detail" data-id="${h(entry.id)}"><span class="hf-symbol">${i(financeKinds[entry.kind]?.[1] || 'wallet')}</span><span class="hf-record-title"><strong>${h(entry.title)}</strong><span class="caption muted">${financeKinds[entry.kind]?.[0] || ''} · ${h(ctx.dateLabel(entry.date))}</span></span><strong class="hf-record-value ${entry.kind === 'income' ? 'hf-positive' : ''}">${entry.kind === 'expense' ? '−' : entry.kind === 'income' ? '+' : ''}${amount(entry.amount)}</strong></button>`).join('') : `<div class="empty"><p class="muted">Здесь пока нет записей в ${h(s.hfCurrency)}.</p><button class="primary" data-action="hf-finance-create">Добавить запись</button></div>`}</section><p class="caption muted">Разные валюты считаются отдельно. Все значения — из демонстрационных записей.</p>`;
}
export function handleHabitsFinance(action, el, ctx) {
  const { state: s, html: h, icon: i } = ctx;
  if (!action.startsWith('hf-')) return false;
  const habit = s.habits.find((item) => item.id === el.dataset.id),
    entry = s.finance.find((item) => item.id === el.dataset.id);
  if (action === 'hf-habit-create') habitEditor(ctx);
  else if (action === 'hf-habit-edit' && habit) habitEditor(ctx, habit);
  else if (action === 'hf-habit-mark' && habit) habitMark(ctx, habit, el.dataset.date || s.today);
  else if (action === 'hf-habit-archive' && habit) {
    habit.archived = !habit.archived;
    ctx.render();
    ctx.notify(habit.archived ? 'Привычка перенесена в архив макета.' : 'Привычка восстановлена.');
  } else if (action === 'hf-habit-delete' && habit)
    ctx.openModal({
      title: 'Удалить привычку?',
      body: `<p>«${h(habit.title)}» и её отметки исчезнут из этого демонстрационного макета.</p>`,
      submitLabel: 'Удалить',
      onSubmit: () => {
        s.habits = s.habits.filter((item) => item.id !== habit.id);
        ctx.closeModal();
        ctx.render();
      },
    });
  else if (action === 'hf-archive-toggle') {
    s.hfArchive = !s.hfArchive;
    ctx.render();
  } else if (action === 'hf-period-week' || action === 'hf-period-month') {
    s.hfPeriod = action.endsWith('month') ? 'month' : 'week';
    s.hfHabitsAnchor = s.today;
    ctx.render();
  } else if (action === 'hf-period-prev' || action === 'hf-period-next') {
    const delta = action.endsWith('prev') ? -1 : 1;
    if (s.hfPeriod === 'month') {
      const value = date(s.hfHabitsAnchor || s.today);
      value.setUTCDate(1);
      value.setUTCMonth(value.getUTCMonth() + delta);
      s.hfHabitsAnchor = dateKey(value);
    } else s.hfHabitsAnchor = addDays(s.hfHabitsAnchor || s.today, delta * 7);
    ctx.render();
  } else if (action === 'hf-review-day') {
    const key = el.dataset.date,
      habits = s.habits.filter(
        (item) => Boolean(item.archived) === s.hfArchive && scheduled(item, key),
      );
    ctx.openModal({
      title: ctx.dateLabel(key),
      body: `<div class="stack">${habits.length ? habits.map((item) => `<button class="hf-day-review row between" data-action="hf-review-mark" data-id="${h(item.id)}" data-date="${key}" ${key > s.today || item.archived ? 'disabled' : ''}><span>${h(item.title)}</span><strong>${Number(item.marks?.[key] || 0)}/${target(item)} ${done(item, key) ? i('check') : ''}</strong></button>`).join('') : '<p class="muted">На этот день привычки не запланированы.</p>'}</div><p class="caption muted">${key > s.today ? 'Будущие дни нельзя отмечать.' : 'Нажми на привычку, чтобы изменить отметку.'}</p>`,
    });
  } else if (action === 'hf-review-mark' && habit) {
    ctx.closeModal();
    habitMark(ctx, habit, el.dataset.date);
  } else if (action === 'hf-currency') {
    s.hfCurrency = el.dataset.currency;
    ctx.render();
  } else if (action === 'hf-finance-section') {
    s.hfFinanceSection = el.dataset.section;
    ctx.render();
  } else if (action === 'hf-finance-create') financeEditor(ctx);
  else if (action === 'hf-finance-edit' && entry) financeEditor(ctx, entry);
  else if (action === 'hf-finance-detail' && entry)
    ctx.openModal({
      title: entry.title,
      body: `<div class="stack"><strong class="hf-balance">${h(money(entry.amount, entry.currency))}</strong><div class="row between"><span class="muted">Тип</span><strong>${financeKinds[entry.kind][0]}</strong></div><div class="row between"><span class="muted">Дата</span><strong>${h(ctx.dateLabel(entry.date))}</strong></div><button class="primary" data-action="hf-finance-edit" data-id="${h(entry.id)}">Изменить запись</button><button class="hf-delete" data-action="hf-finance-delete" data-id="${h(entry.id)}">Удалить запись</button><p class="caption muted">Демонстрационные данные. Реальные деньги не перемещаются.</p></div>`,
    });
  else if (
    action === 'hf-finance-delete' &&
    entry &&
    s.finance.some(
      (item) => item.kind === 'transfer' && (item.fromId === entry.id || item.toId === entry.id),
    )
  )
    ctx.openModal({
      title: 'Счёт используется в переводах',
      body: '<p>Сначала удали связанные демонстрационные переводы, чтобы сохранить правильные балансы.</p>',
    });
  else if (action === 'hf-finance-delete' && entry)
    ctx.openModal({
      title: 'Удалить запись?',
      body: `<p>Запись «${h(entry.title)}» будет удалена только из макета.</p>`,
      submitLabel: 'Удалить',
      onSubmit: () => {
        s.finance = s.finance.filter((item) => item.id !== entry.id);
        ctx.closeModal();
        ctx.render();
        ctx.notify('Демонстрационная запись удалена.');
      },
    });
  return true;
}

export const stylesHabitsFinance = `
.hf-add{background:var(--accent-soft,rgba(169,128,229,.22));flex:none}
.hf-controls{flex-wrap:wrap;gap:8px}.hf-controls .row{gap:4px}.hf-analytics h2,.hf-habit h3{margin:0}
.hf-gauge{position:relative;width:100%;max-width:280px;margin:6px auto 0;aspect-ratio:280/170}
.hf-gauge svg{width:100%;height:auto;overflow:visible}.hf-gauge path{fill:none;stroke-width:20;stroke-linecap:round}
.hf-gauge-track{stroke:rgba(169,128,229,.15)}.hf-gauge-value{stroke:var(--accent,#b999ee);transition:stroke-dasharray .4s ease}
.hf-gauge>div{position:absolute;inset:auto 0 5px;text-align:center;display:grid;gap:4px}.hf-gauge strong{font-size:42px;line-height:1.1;letter-spacing:-1.8px}
.hf-metrics{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}.hf-metrics .metric{padding:12px 9px;border-radius:17px;background:rgba(160,130,210,.09);display:grid;gap:10px;min-width:0}.hf-metrics strong{font-size:26px;letter-spacing:-1px}.hf-metrics small{font-size:12px;letter-spacing:0;font-weight:500;color:var(--muted,#91859f)}
.hf-chart-section{border-top:1px solid rgba(153,133,185,.15);padding-top:16px}.hf-chart-section h3{margin:0 0 16px}.hf-bars{display:flex;gap:8px;align-items:flex-end}.hf-bar-column{flex:1;min-width:0;display:grid;gap:8px;text-align:center}.hf-bar-track{height:86px;display:flex;align-items:flex-end;border-radius:7px;background:rgba(169,128,229,.09);overflow:hidden}.hf-bar-track span{display:block;width:100%;background:linear-gradient(0deg,#9473c4,#c6a9ef);border-radius:6px 6px 0 0;transition:height .35s ease;min-height:0}.hf-bars.month{gap:3px}.hf-bars.month .caption{font-size:9px;white-space:nowrap}.hf-bars.month .hf-bar-track{border-radius:3px}
.hf-heatmap-scroll,.hf-week-scroll{overflow-x:auto;overscroll-behavior-inline:contain;scrollbar-width:thin}.hf-heatmap{display:grid;grid-template-columns:repeat(7,minmax(40px,1fr));gap:4px;min-width:304px;text-align:center}.hf-heat-cell{min-height:44px;border:0;border-radius:12px;background:color-mix(in srgb,var(--accent,#ad8ddd) calc(7% + var(--completion)*55%),transparent);color:inherit;font:inherit}.hf-heat-cell.today{box-shadow:inset 0 0 0 1px var(--accent,#ad8ddd)}
.hf-habit-week{display:grid;grid-template-columns:repeat(7,minmax(40px,1fr));gap:4px;min-width:304px}.hf-day-mark{display:grid;justify-items:center;gap:7px;border:0;background:none;color:inherit;padding:2px 0;min-height:66px}.hf-day-mark:disabled{opacity:.35}.hf-check{width:34px;height:34px;display:grid;place-items:center;border:1px solid rgba(160,130,210,.35);border-radius:50%;font-size:12px}.hf-check svg{width:18px;height:18px}.hf-day-mark.done .hf-check{background:var(--accent,#b999ee);color:#291b41;border-color:transparent}.hf-day-mark.today .caption{color:var(--accent,#b999ee);font-weight:700}
.hf-symbol{width:40px;height:40px;border-radius:13px;background:rgba(169,128,229,.14);display:grid;place-items:center;flex:none;color:var(--accent,#b999ee)}.hf-symbol svg{width:22px;height:22px}.hf-habit .row>div{min-width:0}.hf-habit h3{overflow-wrap:anywhere}
.hf-form-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.hf-week-select{padding:0;border:0;display:flex;gap:4px;justify-content:space-between;flex-wrap:wrap}.hf-week-select legend{margin-bottom:10px;font-size:13px}.hf-week-select label{position:relative;display:block;flex:1;min-width:36px}.hf-week-select input{position:absolute;opacity:0}.hf-week-select span{display:grid;place-items:center;min-height:44px;border-radius:12px;background:rgba(169,128,229,.08);border:1px solid rgba(169,128,229,.15);font-size:12px}.hf-week-select input:checked+span{background:var(--accent,#b999ee);color:#291b41}.hf-week-select input:focus-visible+span{outline:2px solid var(--accent,#b999ee);outline-offset:2px}
.hf-day-review{width:100%;min-height:54px;border:0;background:rgba(169,128,229,.07);color:inherit;padding:12px;border-radius:12px;text-align:left}.hf-day-review strong{display:flex;align-items:center;gap:5px;white-space:nowrap}.hf-day-review svg{width:18px;height:18px}.hf-day-review:disabled{opacity:.5}
.hf-filter-scroll{overflow-x:auto;scrollbar-width:thin;padding:2px 0}.hf-filter-scroll .segmented{min-width:max-content}.hf-currencies{gap:4px!important}.hf-currencies .pill{padding-inline:9px}.hf-currencies .active{background:rgba(169,128,229,.22);color:var(--accent,#b999ee)}
.hf-balance{display:block;font-size:clamp(27px,7.5vw,36px);letter-spacing:-1.2px;line-height:1.12;overflow-wrap:anywhere}.hf-cash-metrics{display:grid;grid-template-columns:1fr 1fr;gap:12px}.hf-cash-metrics>div{display:grid;gap:7px}.hf-cash-metrics strong{font-size:17px;overflow-wrap:anywhere}.hf-positive{color:var(--positive,#67a88d)}
.hf-money-chart{display:flex;align-items:flex-end;gap:14px;height:150px}.hf-money-month{display:grid;gap:10px;flex:1;text-align:center;min-width:0}.hf-money-month .caption{font-size:11px;white-space:nowrap}.hf-money-bars{height:112px;display:flex;gap:4px;align-items:flex-end;justify-content:center;border-bottom:1px solid rgba(169,128,229,.18)}.hf-money-bars>span{width:14px;max-width:45%;border-radius:5px 5px 0 0;transition:height .3s ease}.hf-money-bars .income{background:#aa89da}.hf-money-bars .expense{background:#827197}
.hf-chart-legend{gap:18px;font-size:12px}.hf-chart-legend span{display:flex;gap:6px;align-items:center}.hf-chart-legend i{width:7px;height:7px;border-radius:50%;background:#aa89da}.hf-chart-legend span+span i{background:#827197}
.hf-finance-record{display:flex;align-items:center;gap:10px;border:0;border-top:1px solid rgba(169,128,229,.13);background:none;color:inherit;padding:13px 0;text-align:left;width:100%;min-height:64px}.hf-record-title{display:grid;gap:5px;min-width:0;flex:1}.hf-record-title strong{font-size:14px;overflow-wrap:anywhere}.hf-record-value{font-size:14px;flex:none;max-width:42%;overflow-wrap:anywhere;text-align:right}.hf-record-title .caption{font-size:11px}.hf-finance-record .hf-symbol{width:34px;height:34px;border-radius:11px}
.hf-transfer-fields{border:1px solid rgba(169,128,229,.18);border-radius:12px;padding:12px}.hf-transfer-fields summary{min-height:30px;cursor:pointer}.hf-transfer-fields .field{margin-top:12px}.hf-delete{min-height:44px;border:0;border-radius:13px;background:rgba(207,91,111,.12);color:#cf6b80;padding:12px;font:inherit}
@media(prefers-reduced-motion:reduce){.hf-gauge-value,.hf-bar-track span,.hf-money-bars>span{transition:none}}
`;
