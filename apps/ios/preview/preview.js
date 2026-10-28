import {
  renderDay,
  renderCalendar,
  handleDayCalendar,
  stylesDayCalendar,
} from './sections-day-calendar.js';
import {
  renderHabits,
  renderFinance,
  handleHabitsFinance,
  stylesHabitsFinance,
} from './sections-habits-finance.js';
import {
  renderAssistant,
  renderSettings,
  handleAssistantSettings,
  stylesAssistantSettings,
} from './sections-assistant-settings.js';

const sections = [
  ['day', 'Мой день', 'grid'],
  ['calendar', 'Календарь', 'calendar'],
  ['habits', 'Привычки', 'checklist'],
  ['assistant', 'ИИ-помощник', 'sparkles'],
  ['finance', 'Финансы', 'wallet'],
  ['settings', 'Настройки', 'settings'],
];
const paths = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  calendar:
    '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v5m10-5v5M3 11h18m-13 4h1m6 0h1m-8 3h1m6 0h1"/>',
  checklist: '<path d="m3 6 2 2 4-5M13 6h8M3 14l2 2 4-5m4 3h8M3 21h6m4 0h8"/>',
  sparkles:
    '<path d="m12 3 2.2 6.8L21 12l-6.8 2.2L12 21l-2.2-6.8L3 12l6.8-2.2L12 3Z"/><path d="m20 2 .7 2.3L23 5l-2.3.7L20 8l-.7-2.3L17 5l2.3-.7L20 2Z"/>',
  wallet: '<path d="M20 8V5a2 2 0 0 0-2-2H6a3 3 0 0 0 0 6h15v11H6a3 3 0 0 1-3-3V6m18 6h-5v5h5"/>',
  settings:
    '<path d="M3 5h8m6 0h4M3 12h2m6 0h10M3 19h12m6 0h0"/><circle cx="14" cy="5" r="3"/><circle cx="8" cy="12" r="3"/><circle cx="18" cy="19" r="3"/>',
  more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  'chevron-left': '<path d="m15 5-7 7 7 7"/>',
  'chevron-right': '<path d="m9 5 7 7-7 7"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  moon: '<path d="M20.5 14a8.5 8.5 0 0 1-10.5-10.5A8.8 8.8 0 1 0 20.5 14Z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
  'arrow-up-right': '<path d="M7 17 17 7M7 7h10v10"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',
  edit: '<path d="m15 4 5 5M4 20l5-1L21 7l-5-5L4 14v6Z"/>',
  refresh: '<path d="M20 7v5h-5M4 17v-5h5M6 6a8 8 0 0 1 14 6M4 12a8 8 0 0 0 14 6"/>',
};
function icon(name) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.sparkles}</svg>`;
}
const html = (value) =>
  String(value ?? '').replace(
    /[&<>"']/g,
    (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char],
  );
function fixtures() {
  const habits = [
    {
      id: 'h1',
      title: 'Читать 20 минут',
      icon: 'checklist',
      target: 20,
      unit: 'мин',
      weekdays: [0, 1, 2, 3, 4, 5, 6],
      marks: {},
      archived: false,
    },
    {
      id: 'h2',
      title: 'Тренировка',
      icon: 'sparkles',
      target: 1,
      unit: 'раз',
      weekdays: [1, 3, 5],
      marks: {},
      archived: false,
    },
    {
      id: 'h3',
      title: 'Выпить воду',
      icon: 'check',
      target: 6,
      unit: 'стаканов',
      weekdays: [0, 1, 2, 3, 4, 5, 6],
      marks: {},
      archived: false,
    },
  ];
  for (let d = 11; d <= 29; d++) {
    const key = `2026-10-${d}`;
    const day = new Date(key + 'T12:00:00Z').getUTCDay();
    for (let i = 0; i < habits.length; i++) {
      if (habits[i].weekdays.includes(day) && (d + i) % 4 !== 0)
        habits[i].marks[key] = habits[i].target;
    }
  }
  habits[0].marks['2026-10-29'] = 20;
  habits[2].marks['2026-10-29'] = 2;
  return {
    theme: 'light',
    section: 'day',
    today: '2026-10-29',
    selectedDate: '2026-10-29',
    profile: {
      name: 'Алекс',
      language: 'ru',
      timeZone: 'Asia/Qyzylorda',
      workStart: '09:00',
      workEnd: '18:00',
      notifications: false,
    },
    tasks: [
      {
        id: 't1',
        title: 'Подготовить план дня',
        date: '2026-10-29',
        time: null,
        duration: 30,
        completed: true,
        priority: 'normal',
      },
      {
        id: 't2',
        title: 'Доработать идею проекта',
        date: '2026-10-29',
        time: null,
        duration: 60,
        completed: false,
        priority: 'high',
      },
      {
        id: 't3',
        title: 'Записаться на тренировку',
        date: '2026-10-29',
        time: null,
        duration: 15,
        completed: false,
        priority: 'normal',
      },
      {
        id: 't4',
        title: 'Прочитать новую главу',
        date: '2026-10-30',
        time: null,
        duration: 30,
        completed: false,
        priority: 'normal',
      },
    ],
    events: [
      {
        id: 'e1',
        title: 'Работа над проектом',
        date: '2026-10-29',
        time: '10:00',
        duration: 90,
        color: '#9b7cce',
      },
      {
        id: 'e2',
        title: 'Встреча с командой',
        date: '2026-10-29',
        time: '14:00',
        duration: 60,
        color: '#7aa8a1',
      },
      {
        id: 'e3',
        title: 'Английский',
        date: '2026-10-28',
        time: '16:00',
        duration: 60,
        color: '#a78cb6',
      },
      {
        id: 'e4',
        title: 'Тренировка',
        date: '2026-10-30',
        time: '18:00',
        duration: 60,
        color: '#b49573',
      },
    ],
    habits,
    finance: [
      {
        id: 'f1',
        kind: 'account',
        title: 'Основной счёт',
        amount: 180000,
        currency: 'KZT',
        date: '2026-10-01',
      },
      {
        id: 'f2',
        kind: 'income',
        title: 'Работа над проектом',
        amount: 95000,
        currency: 'KZT',
        date: '2026-10-12',
      },
      {
        id: 'f3',
        kind: 'expense',
        title: 'Продукты',
        amount: 18500,
        currency: 'KZT',
        date: '2026-10-24',
      },
      {
        id: 'f4',
        kind: 'expense',
        title: 'Кофе и встреча',
        amount: 3500,
        currency: 'KZT',
        date: '2026-10-27',
      },
      {
        id: 'f5',
        kind: 'deposit',
        title: 'На новые идеи',
        amount: 250000,
        currency: 'KZT',
        date: '2026-10-01',
      },
      {
        id: 'f6',
        kind: 'stock',
        title: 'Демонстрационный портфель',
        amount: 65000,
        currency: 'KZT',
        date: '2026-10-25',
      },
    ],
  };
}
let state = fixtures();
const phone = document.querySelector('#phone');
const page = document.querySelector('#page-content');
const scroller = document.querySelector('#page-scroll');
const nav = document.querySelector('#phone-navigation');
const modal = document.querySelector('#modal-layer');
const modalForm = document.querySelector('#modal-form');
let modalSubmit = null,
  previousFocus = null,
  toastTimer = null;
const scrollPositions = {};
const ctx = {
  get state() {
    return state;
  },
  html,
  icon,
  money(value, currency = 'KZT') {
    return new Intl.NumberFormat('ru-KZ', {
      style: 'currency',
      currency,
      maximumFractionDigits: 0,
    }).format(value || 0);
  },
  dateLabel(key) {
    return new Intl.DateTimeFormat('ru-RU', {
      day: 'numeric',
      month: 'short',
      timeZone: 'UTC',
    }).format(new Date(key + 'T12:00:00Z'));
  },
  openModal,
  closeModal,
  render,
  notify,
  navigate,
  setTheme,
};
const renderers = {
  day: renderDay,
  calendar: renderCalendar,
  habits: renderHabits,
  assistant: renderAssistant,
  finance: renderFinance,
  settings: renderSettings,
};
document.querySelector('#feature-styles').textContent = [
  stylesDayCalendar,
  stylesHabitsFinance,
  stylesAssistantSettings,
].join('\n');
function render(options = {}) {
  const savedTop = scroller.scrollTop;
  const oldTimeline = page.querySelector('[data-calendar-timeline]');
  const timelineTop = oldTimeline?.scrollTop;
  page.innerHTML = renderers[state.section](ctx);
  page.classList.toggle('page-enter', !!options.entrance);
  if (options.entrance)
    page.addEventListener('animationend', () => page.classList.remove('page-enter'), {
      once: true,
    });
  scroller.scrollTop = options.entrance ? scrollPositions[state.section] || 0 : savedTop;
  const timeline = page.querySelector('[data-calendar-timeline]');
  if (timeline) timeline.scrollTop = timelineTop ?? 46 * 8;
  document.querySelectorAll('[data-section]').forEach((button) => {
    if (button.dataset.section === state.section) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
  nav.querySelectorAll('button').forEach((button) => {
    const selected =
      button.dataset.nav === state.section ||
      (button.dataset.nav === 'more' && ['finance', 'settings'].includes(state.section));
    if (selected) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
  updateIndicator();
}
function updateIndicator() {
  const active = nav.querySelector('[aria-current="page"]');
  if (!active) return;
  const indicator = nav.querySelector('.nav-indicator');
  indicator.style.width = `${active.offsetWidth}px`;
  indicator.style.transform = `translateX(${active.offsetLeft}px)`;
}
function navigate(section) {
  if (!renderers[section]) return;
  const composer = document.querySelector('#as-composer');
  if (composer && state.assistant) state.assistant.draft = composer.value;
  closeModal();
  scrollPositions[state.section] = scroller.scrollTop;
  state.section = section;
  render({ entrance: true });
}
function setTheme(theme) {
  state.theme = theme === 'dark' ? 'dark' : 'light';
  phone.dataset.theme = state.theme;
  document.querySelectorAll('[data-theme]').forEach((button) => {
    if (button.tagName === 'BUTTON')
      button.setAttribute('aria-pressed', String(button.dataset.theme === state.theme));
  });
  document.querySelector('#phone-theme').innerHTML = icon(state.theme === 'dark' ? 'sun' : 'moon');
}
function notify(message) {
  clearTimeout(toastTimer);
  const toast = document.querySelector('#toast');
  toast.textContent = message;
  toast.hidden = false;
  toastTimer = setTimeout(() => {
    toast.hidden = true;
  }, 3300);
}
function openModal({ title, body, onSubmit, submitLabel = 'Сохранить' }) {
  previousFocus = document.activeElement;
  modalSubmit = onSubmit || null;
  document.querySelector('#modal-title').textContent = title;
  document.querySelector('#modal-body').innerHTML = body;
  document.querySelector('#modal-footer').innerHTML = onSubmit
    ? `<button type="submit" class="primary">${html(submitLabel)}</button>`
    : '';
  modal.hidden = false;
  scroller.inert = true;
  nav.inert = true;
  phone.querySelector('.phone-header').inert = true;
  requestAnimationFrame(() => {
    (
      modal.querySelector('input:not([type=checkbox]),textarea,select') ||
      document.querySelector('#modal-close')
    ).focus({ preventScroll: true });
  });
}
function closeModal() {
  if (modal.hidden) return;
  modal.hidden = true;
  modalSubmit = null;
  scroller.inert = false;
  nav.inert = false;
  phone.querySelector('.phone-header').inert = false;
  if (previousFocus?.isConnected) previousFocus.focus({ preventScroll: true });
}
modalForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!modalSubmit) return;
  try {
    const result = await modalSubmit(new FormData(modalForm));
    if (result !== false) {
      closeModal();
      render();
    }
  } catch (error) {
    notify(error.message || 'Проверьте поля макета.');
  }
});
document.querySelector('#modal-close').addEventListener('click', closeModal);
modal.addEventListener('click', (event) => {
  if (event.target === modal) closeModal();
});
document.addEventListener('keydown', (event) => {
  if (modal.hidden) return;
  if (event.key === 'Escape') {
    event.preventDefault();
    closeModal();
  }
  if (event.key === 'Tab') {
    const items = [
      ...modal.querySelectorAll(
        'button:not(:disabled),input:not(:disabled),textarea:not(:disabled),select:not(:disabled),[tabindex="0"]',
      ),
    ].filter((item) => item.getClientRects().length);
    const first = items[0],
      last = items.at(-1);
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last?.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first?.focus();
    }
  }
});
const navItems = [...sections.slice(0, 4), ['more', 'Ещё', 'more']];
nav.innerHTML =
  '<div class="nav-indicator"></div>' +
  navItems
    .map(
      ([key, title, symbol]) =>
        `<button type="button" data-nav="${key}" aria-label="${title}">${icon(symbol)}<span>${key === 'assistant' ? 'ИИ-<br>помощник' : title}</span></button>`,
    )
    .join('');
document.querySelector('#section-shortcuts').innerHTML = sections
  .map(
    ([key, title, symbol]) =>
      `<button type="button" data-section="${key}">${icon(symbol)}<span>${title}</span></button>`,
  )
  .join('');
nav.addEventListener('click', (event) => {
  const button = event.target.closest('[data-nav]');
  if (!button) return;
  if (button.dataset.nav === 'more') {
    openModal({
      title: 'Ещё',
      body: `<div class="more-menu">${sections
        .slice(4)
        .map(
          ([key, title, symbol]) =>
            `<button type="button" data-action="preview-navigate" data-target="${key}">${icon(symbol)}${title}</button>`,
        )
        .join('')}</div>`,
    });
  } else navigate(button.dataset.nav);
});
document.querySelector('#section-shortcuts').addEventListener('click', (event) => {
  const button = event.target.closest('[data-section]');
  if (button) navigate(button.dataset.section);
});
document.querySelector('.review-theme').addEventListener('click', (event) => {
  const button = event.target.closest('button[data-theme]');
  if (button) setTheme(button.dataset.theme);
});
document
  .querySelector('#phone-theme')
  .addEventListener('click', () => setTheme(state.theme === 'light' ? 'dark' : 'light'));
phone.addEventListener('click', (event) => {
  const el = event.target.closest('[data-action]');
  if (!el) return;
  const action = el.dataset.action;
  if (action === 'preview-navigate') {
    navigate(el.dataset.target);
    return;
  }
  handleDayCalendar(action, el, ctx) ||
    handleHabitsFinance(action, el, ctx) ||
    handleAssistantSettings(action, el, ctx);
});
phone.addEventListener('change', (event) => {
  const el = event.target.closest('[data-change]');
  if (el) {
    const action = el.dataset.change;
    handleDayCalendar(action, el, ctx) ||
      handleHabitsFinance(action, el, ctx) ||
      handleAssistantSettings(action, el, ctx);
  }
});
document.querySelector('#device-size').addEventListener('change', (event) => {
  const [width, height] = event.target.value.split('x');
  document.querySelector('.device-stage').style.setProperty('--phone-width', width + 'px');
  document.querySelector('.device-stage').style.setProperty('--phone-height', height + 'px');
  document.querySelector('#device-caption').textContent =
    `${width === '390' ? 'iPhone 13' : 'Экран'} · ${width} × ${height} · интерактивный HTML-макет`;
  fitDevice();
  updateIndicator();
});
document.querySelector('#reset-demo').addEventListener('click', () =>
  openModal({
    title: 'Начать просмотр заново?',
    body: '<p class="muted">Сбросятся только демонстрационные изменения этого макета. Настоящие данные Ritm не затрагиваются.</p>',
    submitLabel: 'Сбросить макет',
    onSubmit() {
      const theme = state.theme;
      state = fixtures();
      state.theme = theme;
      Object.keys(scrollPositions).forEach((key) => delete scrollPositions[key]);
      setTheme(theme);
      notify('Макет сброшен');
    },
  }),
);
new ResizeObserver(updateIndicator).observe(nav);
function fitDevice() {
  const [width, height] = document.querySelector('#device-size').value.split('x').map(Number);
  const scale = Math.min(
    1,
    Math.max(490, innerHeight - 86) / (height + 22),
    (innerWidth - 40) / (width + 22),
  );
  const stage = document.querySelector('.device-stage');
  stage.style.setProperty('--device-scale', scale);
  stage.style.width = `${(width + 22) * scale}px`;
  stage.style.height = `${(height + 22) * scale + 30}px`;
}
addEventListener('resize', fitDevice);
fitDevice();
setTheme('light');
render({ entrance: true });
