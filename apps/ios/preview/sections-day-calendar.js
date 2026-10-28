// Interactive, fictional-data companion to the native Day and Calendar screens.
// This module does not execute SwiftUI and never sends requests to Ritm services.
const DAY = 86_400_000;
const weekdays = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
const key = (date) => date.toISOString().slice(0, 10);
const asDate = (value) => new Date(`${value}T12:00:00Z`);
const addDays = (value, amount) => key(new Date(asDate(value).getTime() + amount * DAY));
const week = (value) =>
  Array.from({ length: 7 }, (_, i) => addDays(value, i - asDate(value).getUTCDay()));
const minutes = (time) => {
  if (!/^\d{2}:\d{2}$/.test(time ?? '')) return null;
  const [h, m] = time.split(':').map(Number);
  return h < 24 && m < 60 ? h * 60 + m : null;
};
const clock = (time) => {
  const value = minutes(time);
  if (value === null) return 'Без времени';
  const h = Math.floor(value / 60);
  return `${h % 12 || 12}:${String(value % 60).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
};
const ending = (item) => {
  const start = minutes(item.time);
  if (start === null) return '';
  const end = (start + Number(item.duration || 60)) % 1440;
  return `${String(Math.floor(end / 60)).padStart(2, '0')}:${String(end % 60).padStart(2, '0')}`;
};
const attr = (ctx, value) => ctx.html(String(value ?? ''));
const color = (value) => (/^#[a-f\d]{6}$/i.test(value ?? '') ? value : '#aa80df');
function schedule(state, date) {
  return [
    ...state.events
      .filter((item) => item.date === date)
      .map((item) => ({ ...item, type: 'event' })),
    ...state.tasks
      .filter((item) => item.date === date && minutes(item.time) !== null)
      .map((item) => ({ ...item, type: 'task' })),
  ].sort((a, b) => (minutes(a.time) ?? -1) - (minutes(b.time) ?? -1));
}
function scheduleRows(ctx, date) {
  const items = schedule(ctx.state, date);
  return items.length
    ? items
        .map(
          (item) =>
            `<button type="button" class="dc-agenda-row" data-action="dc-edit-${item.type}" data-id="${attr(ctx, item.id)}"><span class="dc-agenda-time">${ctx.html(clock(item.time))}</span><span class="dc-agenda-body" style="--event-color:${color(item.color)}"><strong>${ctx.html(item.title)}</strong><span class="caption muted">${ctx.html(clock(item.time))} – ${ctx.html(clock(ending(item)))} · ${item.type === 'task' ? 'Ritm' : 'Календарь'}</span></span></button>`,
        )
        .join('')
    : `<p class="empty">На этот день ничего не запланировано.</p>`;
}
function taskRows(ctx, date) {
  const items = ctx.state.tasks.filter((item) => item.date === date || !item.date);
  return items.length
    ? items
        .map(
          (item) =>
            `<div class="dc-task-row"><button type="button" class="dc-check ${item.completed ? 'is-done' : ''}" data-action="dc-toggle-task" data-id="${attr(ctx, item.id)}" aria-label="${attr(ctx, item.completed ? `Вернуть задачу ${item.title}` : `Выполнить задачу ${item.title}`)}" aria-pressed="${Boolean(item.completed)}">${item.completed ? ctx.icon('check') : ''}</button><button type="button" class="dc-task-copy ${item.completed ? 'is-done' : ''}" data-action="dc-edit-task" data-id="${attr(ctx, item.id)}"><strong>${ctx.html(item.title)}</strong><span class="caption muted">${item.time ? ctx.html(clock(item.time)) + ' · ' : ''}${item.priority === 'high' ? 'Высокий приоритет' : 'Личная задача'}</span></button></div>`,
        )
        .join('')
    : `<p class="empty">Пока нет задач. Добавь первую — день станет яснее.</p>`;
}
function weeklyHabits(ctx) {
  const { state } = ctx;
  const dates = week(state.today);
  const habits = state.habits.filter((h) => !h.archived);
  const eligible = habits.filter((h) =>
    (h.weekdays ?? [0, 1, 2, 3, 4, 5, 6]).includes(asDate(state.today).getUTCDay()),
  );
  const complete = eligible.filter(
    (h) => Number(h.marks?.[state.today] ?? 0) >= Number(h.target || 1),
  ).length;
  return `<section class="card stack"><div class="row between"><div><p class="eyebrow">Привычки на неделю</p><h2>Привычки <span class="caption muted">${complete}/${eligible.length} за сегодня</span></h2></div><button type="button" class="icon-button" aria-label="Все привычки" data-action="dc-go-habits">${ctx.icon('arrow-up-right')}</button></div><div class="dc-habits-scroll"><div class="dc-habits-grid"><span class="caption muted">Привычка</span>${dates.map((date) => `<span class="dc-week-heading ${date === state.today ? 'is-today' : ''}">${weekdays[asDate(date).getUTCDay()]}<strong>${Number(date.slice(-2))}</strong></span>`).join('')}${habits
    .map(
      (h) =>
        `<span class="dc-habit-title">${ctx.html(h.title)}</span>${dates
          .map((date) => {
            const scheduled = (h.weekdays ?? [0, 1, 2, 3, 4, 5, 6]).includes(
              asDate(date).getUTCDay(),
            );
            const done = Number(h.marks?.[date] ?? 0) >= Number(h.target || 1);
            return `<div class="dc-habit-cell ${date === state.today ? 'is-today' : ''}"><button type="button" class="dc-habit-dot ${done ? 'is-done' : ''}" data-action="dc-toggle-habit" data-id="${attr(ctx, h.id)}" data-date="${date}" ${!scheduled || date > state.today ? 'disabled' : ''} aria-label="${attr(ctx, h.title + ', ' + ctx.dateLabel(date) + (done ? ', выполнено' : ', не выполнено'))}" aria-pressed="${done}">${done ? ctx.icon('check') : ''}</button></div>`;
          })
          .join('')}`,
    )
    .join(
      '',
    )}</div></div>${habits.length ? '' : '<p class="empty">Добавь привычку в одноимённом разделе.</p>'}</section>`;
}
export function renderDay(ctx) {
  const { state } = ctx;
  state.dayOffset ??= 0;
  const selected = addDays(state.today, state.dayOffset);
  const tasks = state.tasks.filter((item) => item.date === state.today || !item.date);
  const done = tasks.filter((item) => item.completed).length;
  const percent = tasks.length ? done / tasks.length : 0;
  const entries = schedule(state, state.today).filter((item) => !item.completed);
  const next = entries.find(
    (item) => (minutes(item.time) ?? 0) + Number(item.duration || 60) > 581,
  );
  const occupied = new Set();
  entries.forEach((item) => {
    const from = minutes(item.time);
    if (from === null) return;
    for (
      let value = Math.max(581, from);
      value < Math.min(1080, from + Number(item.duration || 60));
      value++
    )
      occupied.add(value);
  });
  const free = Math.max(0, 1080 - 581 - occupied.size);
  const points = Array.from({ length: 13 }, (_, index) => {
    const hour = index + 9;
    const busy = new Set();
    entries.forEach((item) => {
      const from = minutes(item.time);
      if (from === null) return;
      for (
        let value = Math.max(hour * 60, from);
        value < Math.min((hour + 1) * 60, from + Number(item.duration || 60));
        value++
      )
        busy.add(value);
    });
    return `${index * 25},${64 - busy.size * 0.8}`;
  }).join(' ');
  return `<div class="dc-page stack"><header class="stack"><p class="eyebrow">${ctx.html(ctx.dateLabel(state.today))} · Мой день</p><div class="row between"><h1 class="page-title">Доброе утро${state.profile?.name ? ', ' + ctx.html(state.profile.name.split(' ')[0]) : ''}</h1><button class="icon-button dc-add" type="button" data-action="dc-new-task" aria-label="Добавить задачу">${ctx.icon('plus')}</button></div><p class="muted">Ваши дела. Ваш темп. Один ясный план.</p></header><section class="card stack"><span class="muted">Твой прогресс</span><div class="row dc-progress"><div class="dc-progress-ring" style="--progress:${Math.round(percent * 360)}deg" aria-hidden="true">${ctx.icon(done && done === tasks.length ? 'check' : 'sparkles')}</div><div><strong class="dc-big-number">${done} из ${tasks.length}</strong><p class="caption muted">задач выполнено</p></div></div><svg class="dc-activity-chart" viewBox="0 0 300 75" role="img" aria-label="Занятые минуты по часам"><path d="M0 20H300 M0 43H300 M0 65H300" fill="none" stroke="currentColor" opacity=".12"/><polygon points="0,74 ${points} 300,74" fill="currentColor" opacity=".12"/><polyline points="${points}" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round"/></svg><div class="row between caption muted"><span>9 AM</span><span>3 PM</span><span>9 PM</span></div><p class="caption muted">Свободно до конца рабочего дня: ${Math.floor(free / 60)} ч ${free % 60} мин</p></section><button type="button" class="dc-upcoming stack" data-action="${next ? `dc-edit-${next.type}` : 'dc-go-calendar'}" ${next ? `data-id="${attr(ctx, next.id)}"` : ''}><span class="caption">Ближайшее событие</span><strong>${next ? ctx.html(next.title) : 'Без спешки'}</strong><span>${next ? ctx.html(clock(next.time) + ' – ' + clock(ending(next))) : 'Впереди свободное время'}</span><span class="row between caption dc-upcoming-link">Открыть календарь ${ctx.icon('arrow-up-right')}</span></button><section class="card stack"><div class="row"><span class="dc-assistant-orb" aria-hidden="true"></span><h2>Помощник Ritm</h2></div><p class="muted">Поможет собрать удобный план и оставить время для себя.</p><button type="button" class="pill" data-action="dc-go-assistant">Спланировать день ${ctx.icon('arrow-up-right')}</button></section><section class="card stack"><h2>Задачи на день</h2><div class="segmented" aria-label="День задач"><button type="button" data-action="dc-task-today" class="${state.dayOffset === 0 ? 'active' : ''}" aria-pressed="${state.dayOffset === 0}">Сегодня</button><button type="button" data-action="dc-task-tomorrow" class="${state.dayOffset === 1 ? 'active' : ''}" aria-pressed="${state.dayOffset === 1}">Завтра</button></div>${taskRows(ctx, selected)}<button type="button" class="pill" data-action="dc-new-task">${ctx.icon('plus')} Добавить задачу</button></section><section class="card stack"><div class="row between"><h2>Расписание</h2><button type="button" class="icon-button" data-action="dc-go-calendar" aria-label="Открыть календарь">${ctx.icon('arrow-up-right')}</button></div>${scheduleRows(ctx, state.today)}</section>${weeklyHabits(ctx)}</div>`;
}
function monthDates(selected) {
  const date = asDate(selected);
  const first = key(new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1, 12)));
  const start = week(first)[0];
  return Array.from({ length: 42 }, (_, i) => addDays(start, i));
}
function calendarTimeline(ctx, dates) {
  const mode = dates.length === 1 ? 'day' : 'week';
  const hours = Array.from({ length: 24 }, (_, hour) => hour);
  const hourLabels = hours
    .map((hour) => `<span>${String(hour).padStart(2, '0')}:00</span>`)
    .join('');
  return `<div class="dc-timeline" data-calendar-timeline><div class="dc-time-gutter"><span class="caption">UTC+5</span>${hourLabels}</div><div class="dc-timeline-scroll"><div class="dc-timeline-days dc-timeline-${mode}">${dates
    .map(
      (date) =>
        `<div class="dc-timeline-day"><button type="button" class="dc-column-header ${date === ctx.state.today ? 'is-today' : ''}" data-action="dc-select-day" data-date="${date}"><span>${weekdays[asDate(date).getUTCDay()]}</span><strong>${Number(date.slice(-2))}</strong></button><div class="dc-time-cells">${hours.map((hour) => `<button type="button" class="dc-empty-hour" data-action="dc-new-event" data-date="${date}" data-time="${String(hour).padStart(2, '0')}:00" aria-label="Добавить событие, ${attr(ctx, ctx.dateLabel(date))}, ${hour}:00"></button>`).join('')}${schedule(
          ctx.state,
          date,
        )
          .filter((item) => minutes(item.time) !== null)
          .map((item) => {
            const top = (minutes(item.time) * 46) / 60;
            const height = Math.max(34, (Number(item.duration || 60) * 46) / 60 - 3);
            return `<button type="button" class="dc-calendar-event ${item.completed ? 'is-done' : ''}" data-action="dc-edit-${item.type}" data-id="${attr(ctx, item.id)}" style="top:${top}px;height:${height}px;--event-color:${color(item.color)}"><strong>${ctx.html(item.title)}</strong><span>${ctx.html(item.time)} – ${ctx.html(ending(item))}</span></button>`;
          })
          .join('')}</div></div>`,
    )
    .join('')}</div></div></div>`;
}
export function renderCalendar(ctx) {
  const { state } = ctx;
  state.calendarMode ??= 'week';
  state.selectedDate ??= state.today;
  const selected = state.selectedDate;
  const dates = state.calendarMode === 'day' ? [selected] : week(selected);
  const label =
    state.calendarMode === 'week'
      ? `${ctx.dateLabel(dates[0])} — ${ctx.dateLabel(dates[6])}`
      : ctx.dateLabel(selected);
  const month = selected.slice(0, 7);
  return `<div class="dc-page stack"><header class="row between"><h1 class="page-title">Календарь</h1><div class="row"><button type="button" class="icon-button" data-action="dc-today" aria-label="К сегодняшнему дню">${ctx.icon('clock')}</button><button type="button" class="icon-button dc-add" data-action="dc-new-event" aria-label="Добавить событие">${ctx.icon('plus')}</button></div></header><div class="row between dc-calendar-date"><button type="button" class="icon-button" data-action="dc-previous" aria-label="Предыдущий период">${ctx.icon('chevron-left')}</button><button type="button" class="dc-date-label" data-action="dc-pick-date">${ctx.html(label)}</button><button type="button" class="icon-button" data-action="dc-next" aria-label="Следующий период">${ctx.icon('chevron-right')}</button></div><div class="segmented" aria-label="Вид календаря">${[
    ['day', 'День'],
    ['week', 'Неделя'],
    ['month', 'Месяц'],
  ]
    .map(
      ([id, title]) =>
        `<button type="button" data-action="dc-mode" data-mode="${id}" class="${state.calendarMode === id ? 'active' : ''}" aria-pressed="${state.calendarMode === id}">${title}</button>`,
    )
    .join('')}</div><section class="card dc-calendar-card">${
    state.calendarMode === 'month'
      ? `<div class="dc-month"><div class="dc-month-grid">${weekdays.map((day) => `<span class="caption muted">${day}</span>`).join('')}${monthDates(
          selected,
        )
          .map((date) => {
            const entries = schedule(state, date);
            return `<button type="button" class="dc-month-day ${date === selected ? 'selected' : ''} ${date === state.today ? 'today' : ''} ${date.slice(0, 7) !== month ? 'outside' : ''}" data-action="dc-select-month-date" data-date="${date}" aria-label="${attr(ctx, ctx.dateLabel(date))}, записей: ${entries.length}" aria-pressed="${date === selected}"><span>${Number(date.slice(-2))}</span><span class="dc-month-dots">${entries
              .slice(0, 3)
              .map(() => '<i></i>')
              .join('')}</span></button>`;
          })
          .join(
            '',
          )}</div><h2 class="dc-date-agenda-title">${ctx.html(ctx.dateLabel(selected))}</h2>${scheduleRows(ctx, selected)}</div>`
      : calendarTimeline(ctx, dates)
  }</section><section class="card stack"><div class="row between"><h2>Задачи вне сетки</h2><button type="button" class="icon-button" data-action="dc-new-task" data-date="${selected}" aria-label="Добавить задачу">${ctx.icon('plus')}</button></div>${taskRows(ctx, selected)}</section><p class="caption muted">В этом макете записи открываются нажатием. В нативном приложении предусмотрены перенос и изменение длительности с подтверждением.</p></div>`;
}
function openTask(ctx, existing, selectedDate) {
  const item = existing ?? {
    title: '',
    date: selectedDate ?? ctx.state.selectedDate ?? ctx.state.today,
    time: '',
    duration: 60,
    priority: 'normal',
  };
  ctx.openModal({
    title: existing ? 'Изменить задачу' : 'Новая задача',
    body: `<div class="stack"><label class="field">Название<input name="title" required maxlength="160" value="${attr(ctx, item.title)}" placeholder="Что нужно сделать?"></label><label class="field">Дата<input name="date" type="date" value="${attr(ctx, item.date ?? '')}"></label><label class="field">Время<input name="time" type="time" value="${attr(ctx, item.time ?? '')}"></label><label class="field">Длительность, минут<input name="duration" type="number" min="5" max="720" step="5" value="${Number(item.duration || 60)}"></label><label class="field">Приоритет<select name="priority"><option value="normal" ${item.priority !== 'high' ? 'selected' : ''}>Обычный</option><option value="high" ${item.priority === 'high' ? 'selected' : ''}>Высокий</option></select></label><p class="caption muted">Изменения останутся только в демонстрационном макете.</p>${existing ? `<button type="button" class="dc-danger" data-action="dc-delete-task" data-id="${attr(ctx, item.id)}">${ctx.icon('trash')} Удалить задачу</button>` : ''}</div>`,
    onSubmit(form) {
      const title = String(form.get('title') ?? '').trim();
      if (!title) return false;
      const value = {
        title,
        date: String(form.get('date') || ''),
        time: String(form.get('time') || ''),
        duration: Math.max(5, Math.min(720, Number(form.get('duration')) || 60)),
        priority: String(form.get('priority') || 'normal'),
      };
      if (existing) Object.assign(existing, value);
      else ctx.state.tasks.push({ id: `demo-task-${Date.now()}`, completed: false, ...value });
      ctx.closeModal();
      ctx.render();
      ctx.notify('Задача сохранена в макете.');
      return true;
    },
  });
}
function openEvent(ctx, existing, date, time) {
  const item = existing ?? {
    title: '',
    description: '',
    date: date ?? ctx.state.selectedDate ?? ctx.state.today,
    time: time ?? '10:00',
    duration: 60,
    color: '#aa80df',
  };
  ctx.openModal({
    title: existing ? 'Изменить событие' : 'Новое событие',
    body: `<div class="stack"><label class="field">Название<input name="title" required maxlength="160" value="${attr(ctx, item.title)}" placeholder="Например, работа над проектом"></label><label class="field">Описание<textarea name="description" rows="3" placeholder="Детали и заметки">${ctx.html(item.description ?? '')}</textarea></label><label class="field">Дата<input name="date" type="date" required value="${attr(ctx, item.date)}"></label><div class="dc-form-pair"><label class="field">Начало<input name="time" type="time" required value="${attr(ctx, item.time)}"></label><label class="field">Минуты<input name="duration" type="number" min="5" max="720" step="5" value="${Number(item.duration || 60)}"></label></div><label class="field">Цвет<select name="color">${[
      ['#aa80df', 'Лавандовый'],
      ['#719fe0', 'Синий'],
      ['#6ba799', 'Мятный'],
      ['#d59a6d', 'Персиковый'],
    ]
      .map(
        ([c, title]) =>
          `<option value="${c}" ${color(item.color) === c ? 'selected' : ''}>${title}</option>`,
      )
      .join(
        '',
      )}</select></label><p class="caption muted">Демонстрационная запись. В Google Calendar ничего не отправляется.</p>${existing ? `<button type="button" class="dc-danger" data-action="dc-delete-event" data-id="${attr(ctx, item.id)}">${ctx.icon('trash')} Удалить событие</button>` : ''}</div>`,
    onSubmit(form) {
      const title = String(form.get('title') ?? '').trim();
      if (!title) return false;
      const value = {
        title,
        description: String(form.get('description') ?? ''),
        date: String(form.get('date') || ctx.state.today),
        time: String(form.get('time') || '10:00'),
        duration: Math.max(5, Math.min(720, Number(form.get('duration')) || 60)),
        color: color(String(form.get('color') || '')),
      };
      if (existing) Object.assign(existing, value);
      else ctx.state.events.push({ id: `demo-event-${Date.now()}`, ...value });
      ctx.closeModal();
      ctx.render();
      ctx.notify('Событие сохранено в макете.');
      return true;
    },
  });
}
export function handleDayCalendar(action, el, ctx) {
  if (!action.startsWith('dc-')) return false;
  const { state } = ctx;
  const id = String(el.dataset.id ?? '');
  const task = state.tasks.find((value) => String(value.id) === id);
  const event = state.events.find((value) => String(value.id) === id);
  switch (action) {
    case 'dc-go-calendar':
      ctx.navigate('calendar');
      return true;
    case 'dc-go-habits':
      ctx.navigate('habits');
      return true;
    case 'dc-go-assistant':
      state.assistantDraft = 'Помоги спланировать мой день с учётом задач и расписания.';
      ctx.navigate('assistant');
      return true;
    case 'dc-task-today':
      state.dayOffset = 0;
      break;
    case 'dc-task-tomorrow':
      state.dayOffset = 1;
      break;
    case 'dc-toggle-task':
      if (task) task.completed = !task.completed;
      break;
    case 'dc-new-task':
      openTask(ctx, null, el.dataset.date ?? addDays(state.today, state.dayOffset ?? 0));
      return true;
    case 'dc-edit-task':
      if (task) openTask(ctx, task);
      return true;
    case 'dc-new-event':
      openEvent(ctx, null, el.dataset.date, el.dataset.time);
      return true;
    case 'dc-edit-event':
      if (event) openEvent(ctx, event);
      return true;
    case 'dc-delete-task':
    case 'dc-delete-event': {
      const kind = action.endsWith('task') ? 'tasks' : 'events';
      const entry = kind === 'tasks' ? task : event;
      if (!entry) return true;
      ctx.openModal({
        title: 'Удалить запись из макета?',
        body: `<p>«${ctx.html(entry.title)}» будет удалена только из демонстрационных данных.</p>`,
        onSubmit() {
          state[kind] = state[kind].filter((value) => String(value.id) !== id);
          ctx.closeModal();
          ctx.render();
          ctx.notify('Демонстрационная запись удалена.');
          return true;
        },
      });
      return true;
    }
    case 'dc-toggle-habit': {
      const habit = state.habits.find((value) => String(value.id) === id);
      const date = el.dataset.date;
      if (habit && date && date <= state.today) {
        habit.marks ??= {};
        habit.marks[date] =
          Number(habit.marks[date] ?? 0) >= Number(habit.target || 1)
            ? 0
            : Number(habit.target || 1);
      }
      break;
    }
    case 'dc-mode':
      state.calendarMode = el.dataset.mode;
      break;
    case 'dc-select-day':
      state.selectedDate = el.dataset.date;
      state.calendarMode = 'day';
      break;
    case 'dc-select-month-date':
      state.selectedDate = el.dataset.date;
      break;
    case 'dc-today':
      state.selectedDate = state.today;
      state.calendarMode = 'day';
      break;
    case 'dc-previous':
    case 'dc-next': {
      const direction = action === 'dc-next' ? 1 : -1;
      if (state.calendarMode === 'month') {
        const current = asDate(state.selectedDate ?? state.today);
        state.selectedDate = key(
          new Date(Date.UTC(current.getUTCFullYear(), current.getUTCMonth() + direction, 1, 12)),
        );
      } else
        state.selectedDate = addDays(
          state.selectedDate ?? state.today,
          direction * (state.calendarMode === 'day' ? 1 : 7),
        );
      break;
    }
    case 'dc-pick-date':
      ctx.openModal({
        title: 'Выбрать дату',
        body: `<label class="field">Дата<input name="date" type="date" required value="${attr(ctx, state.selectedDate ?? state.today)}"></label>`,
        onSubmit(form) {
          state.selectedDate = String(form.get('date') || state.today);
          ctx.closeModal();
          ctx.render();
          return true;
        },
      });
      return true;
    default:
      return false;
  }
  ctx.render();
  return true;
}
export const stylesDayCalendar = `
.dc-page h1,.dc-page h2,.dc-page p{margin:0}.dc-page h2{font-size:17px;line-height:1.3}.dc-page .page-title{font-size:30px;line-height:1.15;letter-spacing:-1px}.dc-page{gap:16px}.dc-add{background:color-mix(in srgb,var(--accent,#ac80e8) 22%,transparent);border-radius:16px}.dc-progress{gap:18px}.dc-progress-ring{width:64px;height:64px;flex-shrink:0;display:grid;place-items:center;border-radius:50%;background:conic-gradient(var(--accent,#aa80df) var(--progress),color-mix(in srgb,var(--accent,#aa80df) 15%,transparent) 0);position:relative}.dc-progress-ring:before{content:'';position:absolute;inset:7px;border-radius:50%;background:var(--surface,#f4effa)}.dc-progress-ring svg{width:25px;height:25px;position:relative;color:var(--accent,#aa80df)}.dc-big-number{font-size:31px;letter-spacing:-.8px;font-variant-numeric:tabular-nums}.dc-activity-chart{width:100%;height:70px;display:block;color:var(--accent,#aa80df)}.phone-screen .dc-upcoming{width:100%;padding:20px;text-align:left;color:#fff;background:linear-gradient(130deg,#573686,#8c5ebd);border:1px solid #ffffff38;border-radius:24px;box-shadow:0 8px 24px #170a3210;gap:16px}.dc-upcoming>strong{font-size:27px;line-height:1.15;letter-spacing:-.7px}.dc-upcoming-link{margin-top:10px}.dc-upcoming svg{width:18px;height:18px}.dc-assistant-orb{width:32px;height:32px;border-radius:50%;border:5px solid var(--accent,#aa80df);box-shadow:0 0 16px #aa80df30;flex-shrink:0}.dc-task-row{display:flex;align-items:center;gap:8px;padding:10px 0;border-bottom:1px solid color-mix(in srgb,currentColor 9%,transparent)}.dc-task-row:last-child{border-bottom:0}.dc-check{width:44px;height:44px;min-width:44px;background:none;border:0;position:relative;display:grid;place-items:center;color:var(--accent,#aa80df)}.dc-check:before{content:'';width:22px;height:22px;border:1.5px solid currentColor;border-radius:50%;position:absolute}.dc-check.is-done:before{background:var(--accent,#aa80df)}.dc-check svg{width:16px;height:16px;position:relative;color:white}.dc-task-copy{background:none;border:0;text-align:left;flex:1;min-width:0;display:flex;flex-direction:column;gap:6px;padding:3px 0;color:inherit;line-height:1.4}.dc-task-copy strong{font-size:14px;overflow-wrap:anywhere}.dc-task-copy.is-done strong{text-decoration:line-through;opacity:.55}.dc-agenda-row{display:flex;gap:12px;align-items:start;width:100%;border:0;background:none;text-align:left;color:inherit;padding:5px 0}.dc-agenda-time{width:51px;flex-shrink:0;font-size:10px;padding-top:12px;line-height:1.4;opacity:.6}.dc-agenda-body{display:flex;flex:1;min-width:0;flex-direction:column;gap:5px;padding:12px;border-radius:14px;border-left:3px solid var(--event-color);background:color-mix(in srgb,var(--event-color) 14%,transparent)}.dc-agenda-body strong{font-size:13px;overflow-wrap:anywhere}.dc-agenda-body .caption{font-size:10px}.dc-habits-scroll{overflow-x:auto;overscroll-behavior-x:contain;padding-bottom:5px}.dc-habits-grid{display:grid;grid-template-columns:108px repeat(7,44px);min-width:416px;align-items:center}.dc-week-heading{font-size:10px;text-align:center;padding:8px 0;display:flex;flex-direction:column;gap:4px}.dc-week-heading strong{font-size:12px}.dc-habit-title{font-size:12px;font-weight:600;padding:16px 6px 16px 0;border-top:1px solid #b99cd31b;overflow-wrap:anywhere}.dc-habit-cell{height:48px;border-top:1px solid #b99cd31b;display:grid;place-items:center}.dc-habit-dot{border:0;background:none;color:var(--accent,#aa80df);height:44px;width:44px;display:grid;place-items:center;position:relative}.dc-habit-dot:before{content:'';position:absolute;inset:11px;border:1px solid currentColor;border-radius:50%}.dc-habit-dot.is-done:before{background:var(--accent,#aa80df)}.dc-habit-dot svg{width:13px;height:13px;position:relative;color:#fff}.dc-habit-dot:disabled{opacity:.2}.dc-habits-grid .is-today{background:color-mix(in srgb,var(--accent,#aa80df) 9%,transparent)}.dc-form-pair{display:grid;grid-template-columns:1fr 1fr;gap:12px;min-width:0}.dc-danger{display:flex;gap:8px;align-items:center;justify-content:center;min-height:44px;border:0;border-radius:12px;background:#d75b6d14;color:#c4465a;font-weight:600}.dc-danger svg{width:18px;height:18px}.dc-calendar-date{gap:5px}.dc-date-label{border:0;background:none;min-height:44px;color:inherit;font-weight:600;font-size:12px;line-height:1.4;flex:1}.dc-calendar-card{padding:12px!important;overflow:hidden}.dc-timeline{display:flex;max-height:425px;overflow-y:auto;overscroll-behavior:contain;position:relative}.dc-time-gutter{display:flex;flex-direction:column;flex:0 0 42px;padding-right:5px;position:sticky;left:0;z-index:2;background:var(--surface,#f4effa)}.dc-time-gutter>span{height:46px;flex-shrink:0;font-size:9px;opacity:.6;padding-top:4px}.dc-time-gutter>span:first-child{height:58px;padding-top:18px}.dc-timeline-scroll{flex:1;min-width:0;overflow-x:auto;overflow-y:hidden;overscroll-behavior-x:contain}.dc-timeline-days{display:flex;min-width:100%}.dc-timeline-day{flex:1;min-width:0;border-left:1px solid color-mix(in srgb,currentColor 10%,transparent)}.dc-timeline-week .dc-timeline-day{min-width:82px}.dc-timeline-week{min-width:574px}.dc-column-header{height:58px;display:flex;flex-direction:column;gap:4px;align-items:center;justify-content:center;width:100%;border:0;background:none;color:inherit;position:sticky;top:0;z-index:2}.dc-column-header span{font-size:10px;opacity:.65}.dc-column-header strong{font-size:17px}.dc-column-header.is-today{color:var(--accent,#aa80df);background:color-mix(in srgb,var(--accent,#aa80df) 11%,transparent)}.dc-time-cells{position:relative;height:1104px}.dc-empty-hour{height:46px;display:block;width:100%;border:0;border-top:1px solid color-mix(in srgb,currentColor 9%,transparent);background:transparent}.dc-calendar-event{position:absolute;left:3px;right:3px;z-index:1;overflow:hidden;display:flex;align-items:flex-start;flex-direction:column;gap:3px;padding:6px;text-align:left;border:1px solid color-mix(in srgb,var(--event-color) 70%,transparent);border-left:3px solid var(--event-color);border-radius:7px;background:color-mix(in srgb,var(--event-color) 24%,var(--surface,#f4effa));color:inherit}.dc-calendar-event strong{font-size:10px;line-height:1.3;overflow-wrap:anywhere}.dc-calendar-event span{font-size:8px;line-height:1.3;opacity:.8}.dc-calendar-event.is-done{opacity:.5}.dc-calendar-event.is-done strong{text-decoration:line-through}.dc-month-grid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));text-align:center;row-gap:5px}.dc-month-grid>.caption{padding:10px 0}.dc-month-day{height:46px;border:0;border-radius:12px;color:inherit;background:none;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;font-variant-numeric:tabular-nums}.dc-month-day.selected{background:var(--accent,#aa80df);color:white}.dc-month-day.today:not(.selected){background:color-mix(in srgb,var(--accent,#aa80df) 15%,transparent);color:var(--accent,#aa80df);font-weight:700}.dc-month-day.outside{opacity:.35}.dc-month-dots{display:flex;gap:3px;min-height:4px}.dc-month-dots i{height:3px;width:3px;border-radius:50%;background:currentColor}.dc-date-agenda-title{margin:20px 0 10px!important;font-size:15px!important}.dc-page .pill{display:flex;align-items:center;justify-content:center;gap:7px}.dc-page .pill svg{width:17px;height:17px}.dc-page button{touch-action:manipulation}.dc-page button:active{filter:brightness(.96)}
`;
