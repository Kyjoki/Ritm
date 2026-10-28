// Interactive design reference only: no API calls, credentials, or real AI answers.
function assistantState(ctx) {
  ctx.state.assistant ??= {
    mode: 'assistant',
    draft: '',
    selected: 'demo-chat',
    conversations: [{ id: 'demo-chat', title: 'Спокойно разберёмся', messages: [] }],
  };
  return ctx.state.assistant;
}

function selectedChat(ctx) {
  const state = assistantState(ctx);
  return state.conversations.find((chat) => chat.id === state.selected);
}

function captureComposer(ctx) {
  const composer = document.getElementById('as-composer');
  if (composer) assistantState(ctx).draft = composer.value;
}

function modeButton(ctx, value, title) {
  return `<button type="button" data-action="as-mode" data-mode="${value}" aria-pressed="${assistantState(ctx).mode === value}">${title}</button>`;
}

function proposal(ctx, message) {
  const { html, icon } = ctx;
  const status = message.proposalStatus ?? 'pending';
  return `<div class="as-proposal stack">
    <div class="row between"><strong>Планирование дня</strong><span class="pill">30 мин</span></div>
    <p class="muted caption">Завтра, 09:00–09:30 · пример предложения</p>
    ${status === 'pending' ? `<div class="row as-wrap"><button type="button" class="primary" data-action="as-proposal-review" data-id="${html(message.id)}">${icon('check')} Посмотреть изменение</button><button type="button" class="as-quiet" data-action="as-proposal-reject" data-id="${html(message.id)}">Отклонить</button></div>` : `<div class="row between"><span class="caption">${status === 'applied' ? 'Добавлено в демонстрационный список' : status === 'undone' ? 'Изменение отменено в макете' : 'Предложение отклонено'}</span>${status === 'applied' ? `<button type="button" class="as-quiet" data-action="as-proposal-undo" data-id="${html(message.id)}">Отменить</button>` : ''}</div>`}
  </div>`;
}

function renderMessage(ctx, message) {
  const { html, icon } = ctx;
  if (message.role === 'user') {
    return `<article class="as-message as-user"><p>${html(message.text)}</p><span class="caption muted">Вы · только в макете</span></article>`;
  }
  if (message.mode === 'idea') {
    const experts = [
      ['Продукт', 'Начни с одной понятной задачи для конкретной группы людей.'],
      ['Пользователь', 'Проверь, как люди решают эту задачу сейчас и что им мешает.'],
      ['Технологии', 'Для первого прототипа достаточно одного основного сценария.'],
      ['Бизнес', 'Проверь готовность платить до расширения функций.'],
    ];
    return `<article class="card stack as-message"><div class="row">${icon('sparkles')}<strong>Разбор идеи</strong></div><p class="as-demo-note">Пример ответа для макета. ИИ не запускался.</p><div class="as-experts">${experts.map(([title, text]) => `<div class="as-expert"><strong>${title}</strong><p class="caption muted">${text}</p></div>`).join('')}</div><div class="as-proposal"><strong>Общий вывод</strong><p>Сформулируй проблему одним предложением и обсуди её с несколькими будущими пользователями.</p></div><button type="button" class="as-quiet" data-action="as-continue" data-id="${html(message.id)}">Продолжить обсуждение ${icon('arrow-up-right')}</button></article>`;
  }
  return `<article class="card stack as-message"><div class="row">${icon('sparkles')}<strong>Помощник Ritm</strong></div><p class="as-demo-note">Пример ответа для макета. ИИ не запускался.</p><p>Можно начать с короткого планирования, выделить время на главное дело и оставить свободный промежуток между встречами.</p>${proposal(ctx, message)}</article>`;
}

export function renderAssistant(ctx) {
  const { html, icon } = ctx;
  const state = assistantState(ctx);
  const chat = selectedChat(ctx);
  return `<section class="stack as-page">
    <div class="row between"><p class="eyebrow">RITM · ПОМОЩНИК</p><div class="row"><button type="button" class="icon-button" data-action="as-history" aria-label="История диалогов">${icon('clock')}</button><button type="button" class="icon-button" data-action="as-new" aria-label="Новый диалог">${icon('edit')}</button></div></div>
    <h1 class="page-title">${html(chat?.title ?? 'Спокойно разберёмся')}</h1>
    <p class="muted">Изменения расписания — только после подтверждения.</p>
    <p class="as-demo-note">Демонстрация интерфейса · без запросов к ИИ</p>
    <div class="stack as-messages">${chat?.messages.length ? chat.messages.map((message) => renderMessage(ctx, message)).join('') : `<div class="stack">${['Что у меня сегодня?', 'Спланируй неделю', 'Разбей задачу на шаги', 'Подготовь отчёт о выполненном'].map((prompt) => `<button type="button" class="card as-suggestion row between" data-action="as-suggestion" data-prompt="${html(prompt)}"><span class="row">${icon('sparkles')}<span>${prompt}</span></span>${icon('arrow-up-right')}</button>`).join('')}</div>`}</div>
    <div class="card stack as-composer">
      <div class="segmented as-mode" aria-label="Режим помощника">${modeButton(ctx, 'assistant', 'Помощник')}${modeButton(ctx, 'idea', 'Разбор идеи')}</div>
      ${state.mode === 'idea' ? '<p class="caption muted">Новая идея: четыре роли и общий вывод</p>' : ''}
      <label class="as-sr-only" for="as-composer">Сообщение помощнику</label>
      <textarea id="as-composer" class="field" rows="3" maxlength="2000" placeholder="${state.mode === 'idea' ? 'Опиши свою идею…' : 'Что хочешь разобрать?'}">${html(state.draft)}</textarea>
      <div class="row between"><span class="caption muted">Ответ будет демонстрационным</span><button type="button" class="icon-button as-send" data-action="as-send" aria-label="Показать пример ответа">${icon('arrow-up-right')}</button></div>
    </div>
  </section>`;
}

function switchButton(action, enabled, label, ctx) {
  return `<button type="button" class="as-switch ${enabled ? 'is-on' : ''}" data-action="${action}" role="switch" aria-checked="${Boolean(enabled)}" aria-label="${ctx.html(label)}"><span></span></button>`;
}

export function renderSettings(ctx) {
  const { state, html, icon } = ctx;
  const profile = state.profile;
  profile.dailyBriefing ??= false;
  profile.email ??= 'alex@example.test';
  return `<section class="stack as-page">
    <p class="eyebrow">RITM · ЛИЧНОЕ ПРОСТРАНСТВО</p><h1 class="page-title">Настройки</h1><p class="muted">Ваш Ritm, привычный на каждом устройстве.</p>
    <article class="card stack"><div class="row between"><h2>Профиль</h2><button type="button" class="icon-button" data-action="as-profile" aria-label="Изменить профиль">${icon('edit')}</button></div><div class="as-profile"><div class="as-avatar">${html((profile.name || 'А')[0])}</div><div><strong>${html(profile.name)}</strong><p class="muted caption">${html(profile.email)}</p></div></div><div class="as-setting-row"><span>Язык</span><span class="muted">${profile.language === 'en' ? 'English' : 'Русский'}</span></div><div class="as-setting-row"><span>Часовой пояс</span><span class="muted as-break">${html(profile.timeZone)}</span></div></article>
    <article class="card stack"><h2>Оформление</h2><div class="segmented as-mode"><button type="button" data-action="as-theme" data-theme="light" aria-pressed="${state.theme === 'light'}">${icon('sun')} Светлая</button><button type="button" data-action="as-theme" data-theme="dark" aria-pressed="${state.theme === 'dark'}">${icon('moon')} Тёмная</button></div><p class="caption muted">Оформление этого макета можно выбрать отдельно.</p></article>
    <article class="card stack"><div class="row between"><h2>Рабочий день</h2><button type="button" class="icon-button" data-action="as-workday" aria-label="Изменить рабочий день">${icon('clock')}</button></div><div class="as-hours"><div><span class="caption muted">Начало</span><strong>${html(profile.workStart)}</strong></div><span class="muted">—</span><div><span class="caption muted">Окончание</span><strong>${html(profile.workEnd)}</strong></div></div><p class="caption muted">Помощник и свободное время учитывают часы аккаунта.</p></article>
    <article class="card stack"><h2>Уведомления</h2><div class="as-setting-row"><span>Напоминания о событиях</span>${switchButton('as-notifications', profile.notifications, 'Напоминания о событиях', ctx)}</div><div class="as-setting-row"><span>Утренний обзор</span>${switchButton('as-briefing', profile.dailyBriefing, 'Утренний обзор', ctx)}</div><p class="caption muted">Переключатели меняют только состояние макета. Разрешение iPhone здесь не запрашивается.</p></article>
    <h2 class="as-section-title">Интеграции</h2>
    ${[
      ['google', 'calendar', 'Google Calendar', 'Расписание и события'],
      ['ai', 'sparkles', 'ИИ-помощник', 'Модель и ключ API'],
      ['telegram', 'arrow-up-right', 'Telegram', 'Уведомления и напоминания'],
    ]
      .map(
        ([id, symbol, name, subtitle]) =>
          `<article class="card stack"><div class="row">${icon(symbol)}<div><h2>${name}</h2><p class="caption muted">${subtitle}</p></div></div><p class="as-demo-note">Подключение не проверяется в макете</p><button type="button" class="as-quiet as-left" data-action="as-integration" data-kind="${id}">Посмотреть настройку ${icon('chevron-right')}</button></article>`,
      )
      .join('')}
    <article class="card stack"><h2>Синхронизация и безопасность</h2><p class="muted">В приложении веб и iPhone будут использовать один аккаунт. Этот просмотр работает только с вымышленными записями.</p><button type="button" class="as-quiet as-left" data-action="as-refresh">${icon('refresh')} Обновить данные</button><div class="as-setting-row caption"><span>Версия просмотра</span><span class="muted">HTML · 6 разделов</span></div><button type="button" class="as-quiet as-left as-danger" data-action="as-logout">Выйти из аккаунта</button></article>
  </section>`;
}

function findMessage(ctx, id) {
  return selectedChat(ctx)?.messages.find((message) => message.id === id);
}

function createConversation(ctx) {
  const assistant = assistantState(ctx);
  const id = `demo-chat-${Date.now()}`;
  assistant.conversations.unshift({ id, title: 'Новый диалог', messages: [] });
  assistant.selected = id;
  assistant.draft = '';
}

export function handleAssistantSettings(action, el, ctx) {
  if (!action.startsWith('as-')) return false;
  const { state, html, icon } = ctx;
  const assistant = assistantState(ctx);
  if (action.startsWith('as-proposal')) captureComposer(ctx);
  switch (action) {
    case 'as-mode':
      captureComposer(ctx);
      assistant.mode = el.dataset.mode;
      ctx.render();
      break;
    case 'as-suggestion':
      assistant.draft = el.dataset.prompt;
      ctx.render();
      document.getElementById('as-composer')?.focus();
      break;
    case 'as-send': {
      captureComposer(ctx);
      const text = assistant.draft.trim();
      if (!text) {
        document.getElementById('as-composer')?.focus();
        break;
      }
      if (!selectedChat(ctx)) createConversation(ctx);
      const chat = selectedChat(ctx);
      if (!chat.messages.length) chat.title = text.length > 40 ? `${text.slice(0, 40)}…` : text;
      chat.messages.push({ id: `u-${Date.now()}`, role: 'user', text });
      chat.messages.push({ id: `a-${Date.now()}`, role: 'assistant', mode: assistant.mode });
      assistant.draft = '';
      ctx.render();
      document.getElementById('as-composer')?.scrollIntoView({ block: 'nearest' });
      break;
    }
    case 'as-new':
      captureComposer(ctx);
      createConversation(ctx);
      ctx.render();
      break;
    case 'as-history':
      captureComposer(ctx);
      ctx.openModal({
        title: 'История диалогов',
        body: `<p class="caption muted">Все диалоги ниже существуют только в этом макете.</p><div class="stack">${assistant.conversations.map((chat) => `<div class="as-history-row"><button type="button" class="as-quiet as-left" data-action="as-select-chat" data-id="${html(chat.id)}">${icon('sparkles')} ${html(chat.title)}</button><button type="button" class="icon-button as-danger" data-action="as-delete-chat" data-id="${html(chat.id)}" aria-label="Удалить демонстрационный диалог">${icon('trash')}</button></div>`).join('') || '<p>Пока нет диалогов.</p>'}</div>`,
      });
      break;
    case 'as-select-chat':
      assistant.selected = el.dataset.id;
      assistant.draft = '';
      ctx.closeModal();
      ctx.render();
      break;
    case 'as-delete-chat': {
      const id = el.dataset.id;
      ctx.openModal({
        title: 'Удалить диалог?',
        body: '<p>Будет удалён только выбранный демонстрационный диалог.</p>',
        submitLabel: 'Удалить из макета',
        onSubmit() {
          assistant.conversations = assistant.conversations.filter((chat) => chat.id !== id);
          if (assistant.selected === id) assistant.selected = assistant.conversations[0]?.id;
          ctx.closeModal();
          ctx.render();
        },
      });
      break;
    }
    case 'as-proposal-review': {
      const message = findMessage(ctx, el.dataset.id);
      if (!message || message.proposalStatus) break;
      ctx.openModal({
        title: 'Применить предложение?',
        body: '<p>В демонстрационный список будет добавлена задача «Планирование дня» на завтра в 09:00, длительность 30 минут.</p><p class="caption muted">Реальный календарь и аккаунт не изменятся.</p>',
        submitLabel: 'Добавить в макет',
        onSubmit() {
          const date = new Date(`${state.today}T12:00:00Z`);
          date.setUTCDate(date.getUTCDate() + 1);
          message.taskID = `preview-ai-${Date.now()}`;
          state.tasks.push({
            id: message.taskID,
            title: 'Планирование дня',
            date: date.toISOString().slice(0, 10),
            time: '09:00',
            duration: 30,
            completed: false,
            priority: 'normal',
          });
          message.proposalStatus = 'applied';
          ctx.closeModal();
          ctx.render();
          ctx.notify('Задача добавлена только в макет');
        },
      });
      break;
    }
    case 'as-proposal-reject': {
      const message = findMessage(ctx, el.dataset.id);
      if (message) {
        message.proposalStatus = 'rejected';
        ctx.render();
      }
      break;
    }
    case 'as-proposal-undo': {
      const message = findMessage(ctx, el.dataset.id);
      if (message?.taskID) {
        state.tasks = state.tasks.filter((task) => task.id !== message.taskID);
        message.proposalStatus = 'undone';
        ctx.render();
      }
      break;
    }
    case 'as-continue':
      assistant.mode = 'idea';
      assistant.draft = 'Давай подробнее обсудим первый шаг.';
      ctx.render();
      document.getElementById('as-composer')?.focus();
      break;
    case 'as-profile':
      ctx.openModal({
        title: 'Профиль',
        body: `<div class="stack"><label>Имя<input class="field" name="name" maxlength="60" required value="${html(state.profile.name)}"></label><label>Email<input class="field" name="email" type="email" value="${html(state.profile.email)}"></label><label>Язык<select class="field" name="language"><option value="ru" ${state.profile.language === 'ru' ? 'selected' : ''}>Русский</option><option value="en" ${state.profile.language === 'en' ? 'selected' : ''}>English</option></select></label><label>Часовой пояс<select class="field" name="timeZone">${['Asia/Qyzylorda', 'Asia/Almaty', 'Europe/Moscow', 'Europe/London', 'UTC'].map((zone) => `<option ${state.profile.timeZone === zone ? 'selected' : ''}>${zone}</option>`).join('')}</select></label><p class="caption muted">Изменения сохранятся только до перезагрузки макета. Тексты просмотра представлены на русском.</p></div>`,
        onSubmit(data) {
          state.profile.name = String(data.get('name')).trim();
          state.profile.email = String(data.get('email')).trim();
          state.profile.language = String(data.get('language'));
          state.profile.timeZone = String(data.get('timeZone'));
          ctx.closeModal();
          ctx.render();
          ctx.notify('Профиль изменён только в макете');
        },
      });
      break;
    case 'as-theme':
      ctx.setTheme(el.dataset.theme);
      break;
    case 'as-workday':
      ctx.openModal({
        title: 'Рабочий день',
        body: `<div class="stack"><label>Начало<input class="field" type="time" name="start" value="${html(state.profile.workStart)}" required></label><label>Окончание<input class="field" type="time" name="end" value="${html(state.profile.workEnd)}" required></label></div>`,
        onSubmit(data) {
          if (data.get('end') <= data.get('start')) {
            ctx.notify('Окончание должно быть позже начала');
            return false;
          }
          state.profile.workStart = String(data.get('start'));
          state.profile.workEnd = String(data.get('end'));
          ctx.closeModal();
          ctx.render();
        },
      });
      break;
    case 'as-notifications':
      state.profile.notifications = !state.profile.notifications;
      if (!state.profile.notifications) state.profile.dailyBriefing = false;
      ctx.render();
      break;
    case 'as-briefing':
      state.profile.dailyBriefing = !state.profile.dailyBriefing;
      if (state.profile.dailyBriefing) state.profile.notifications = true;
      ctx.render();
      break;
    case 'as-integration': {
      const kind = el.dataset.kind;
      const details = {
        google: [
          'Google Calendar',
          'В приложении Google подключается в безопасном системном браузере. Уже подключённый календарь доступен в нативных экранах.',
          'Доступ к календарю',
          'Основной календарь · события · Google Tasks',
        ],
        ai: [
          'ИИ-помощник',
          'В настоящем приложении здесь задаются модель и серверный API-ключ. Макет не принимает и не сохраняет ключи.',
          'Модель и подключение',
          'Статус, выбранная модель и настройка ключа',
        ],
        telegram: [
          'Telegram',
          'В приложении здесь настраивается бот, привязка аккаунта и время напоминаний. Этот макет не отправляет сообщения.',
          'Напоминания',
          'Привязка бота · за 15 минут до события',
        ],
      }[kind];
      if (details)
        ctx.openModal({
          title: details[0],
          body: `<div class="stack"><p>${details[1]}</p><div class="as-proposal stack"><strong>${details[2]}</strong><p class="muted">${details[3]}</p><span class="pill">Предпросмотр настройки</span></div><p class="as-demo-note">Реальные подключения здесь не выполняются.</p></div>`,
        });
      break;
    }
    case 'as-refresh':
      ctx.notify('Макет открыт локально. Запросы к серверу не выполняются.');
      break;
    case 'as-logout':
      ctx.openModal({
        title: 'Выйти на этом устройстве?',
        body: '<div class="stack"><p>В приложении ваши данные останутся на сервере, а локальная сессия будет удалена.</p><p class="as-demo-note">Это просмотр диалога. В макете нет входа в аккаунт, поэтому выход не выполняется.</p></div>',
      });
      break;
    default:
      return false;
  }
  return true;
}

export const stylesAssistantSettings = `
.as-page{gap:18px}.as-page h1,.as-page h2,.as-page p{margin:0}.as-page h2{font-size:18px;line-height:1.3}.as-page p{line-height:1.5}.as-page svg{flex:none}.as-wrap{flex-wrap:wrap}.as-demo-note{font-size:11px;color:var(--muted,#84768e);line-height:1.45}.as-mode{display:flex;gap:4px}.as-mode button{flex:1;display:flex;align-items:center;justify-content:center;gap:6px;min-height:44px}.as-mode svg{width:16px;height:16px}.as-suggestion{width:100%;text-align:left;color:inherit;font-size:14px;min-height:64px;cursor:pointer}.as-suggestion span.row{gap:12px}.as-suggestion svg{width:20px;height:20px}.as-messages{gap:16px}.as-message{animation:as-message-in .2s ease-out}.as-message p{white-space:pre-wrap;overflow-wrap:anywhere}.as-user{margin-left:24px;border-radius:22px 22px 6px 22px;padding:16px 18px;background:color-mix(in srgb,var(--accent,#8c60c9) 16%,transparent);border:1px solid color-mix(in srgb,var(--accent,#8c60c9) 25%,transparent)}.as-user .caption{display:block;margin-top:8px}.as-proposal{padding:14px;border-radius:16px;background:color-mix(in srgb,var(--accent,#8c60c9) 8%,transparent);border:1px solid color-mix(in srgb,var(--accent,#8c60c9) 14%,transparent)}.as-proposal .primary{font-size:12px;min-height:44px;max-width:100%;display:flex;gap:6px;align-items:center;justify-content:center}.as-proposal .primary svg{width:16px;height:16px}.as-quiet{background:none;color:var(--accent,#8555bc);border:0;padding:8px 4px;min-height:44px;display:inline-flex;gap:8px;align-items:center;justify-content:center;font:inherit;font-size:14px;cursor:pointer}.as-left{text-align:left;justify-content:flex-start}.as-quiet svg{width:18px;height:18px}.as-danger{color:#c56172}.as-composer{padding:14px!important;gap:12px}.as-composer textarea{resize:vertical;min-height:80px;max-height:220px;width:100%;font-size:16px}.as-send{background:var(--accent,#8c60c9)!important;color:white!important;border-radius:50%!important}.as-experts{display:grid;grid-template-columns:1fr 1fr;gap:10px}.as-expert{padding:12px;border-radius:14px;background:color-mix(in srgb,var(--accent,#8c60c9) 7%,transparent);min-width:0}.as-expert strong{font-size:13px}.as-expert p{margin-top:7px}.as-profile{display:flex;align-items:center;gap:14px}.as-avatar{display:grid;place-items:center;width:50px;height:50px;border-radius:18px;font-size:23px;font-weight:650;background:color-mix(in srgb,var(--accent,#8c60c9) 22%,transparent);color:var(--accent,#8c60c9)}.as-setting-row{display:flex;align-items:center;justify-content:space-between;gap:14px;min-height:40px;font-size:14px}.as-setting-row+.as-setting-row{border-top:1px solid var(--line,rgba(150,125,180,.13));padding-top:12px}.as-break{overflow-wrap:anywhere;text-align:right;max-width:58%}.as-hours{display:flex;align-items:center;justify-content:space-around;gap:12px}.as-hours>div{display:flex;flex-direction:column;gap:7px}.as-hours strong{font-size:27px;font-weight:600;font-variant-numeric:tabular-nums}.as-switch{flex:none;width:49px;height:44px;padding:0 0;display:flex;align-items:center;background:none;border:0;position:relative;cursor:pointer}.as-switch:before{content:'';position:absolute;inset:7px 0;background:color-mix(in srgb,var(--muted,#84768e) 26%,transparent);border-radius:999px;transition:background .18s}.as-switch>span{width:26px;height:26px;margin-left:2px;z-index:1;border-radius:50%;background:#fff;box-shadow:0 1px 3px #0002;transition:transform .18s}.as-switch.is-on:before{background:var(--accent,#8c60c9)}.as-switch.is-on>span{transform:translateX(19px)}.as-section-title{padding:4px 2px}.as-history-row{display:grid;grid-template-columns:minmax(0,1fr) 44px;gap:8px;align-items:center}.as-history-row>.as-quiet{overflow-wrap:anywhere}.as-sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}@keyframes as-message-in{from{opacity:0;transform:translateY(7px)}to{opacity:1;transform:translateY(0)}}@media(prefers-reduced-motion:reduce){.as-message{animation:none}.as-switch:before,.as-switch>span{transition:none}}
`;
