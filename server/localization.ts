import type { GoogleCalendarEvent, GoogleCalendarResult, Language } from '../shared/types.ts';

/** Choose the first supported language with a positive quality; never trust it as a permission. */
export function requestLanguage(header?: string): Language {
  const choices = (header ?? '')
    .split(',')
    .slice(0, 20)
    .map((part, index) => {
      const [tag, ...parameters] = part.trim().toLowerCase().split(';');
      const quality = parameters.find((parameter) => parameter.trim().startsWith('q='));
      const q = quality ? Number(quality.trim().slice(2)) : 1;
      return { language: tag.split('-')[0], q, index };
    })
    .filter(
      ({ language, q }) => ['ru', 'en'].includes(language) && Number.isFinite(q) && q > 0 && q <= 1,
    )
    .sort((a, b) => b.q - a.q || a.index - b.index);
  return choices[0]?.language === 'en' ? 'en' : 'ru';
}

// Only server-authored status/error text is translated. Personal text is never passed here.
const messages: Record<string, string> = {
  'Проверьте название привычки и выбранную дату.': 'Check the habit name and selected date.',
  'Привычка не найдена. Обновите страницу.': 'Habit not found. Refresh the page.',
  'Привычка изменилась. Обновите данные и повторите действие.':
    'This habit changed. Refresh your data and try again.',
  'Можно отметить только сегодняшний или прошедший день.': 'You can only mark today or a past day.',
  'Архивную привычку нельзя отмечать.': 'Archived habits cannot be marked.',
  'В этот день привычка не запланирована.': 'This habit is not scheduled on that day.',
  'Прогресс превышает цель привычки.': 'Progress exceeds the habit target.',
  'Достигнут предел в 100 привычек.': 'The 100 habit limit has been reached.',
  'Хранилище привычек заполнено.': 'Habit storage is full.',
  'Проверьте сумму, валюту, дату и описание финансовой записи.':
    'Check the amount, currency, date and details of the finance entry.',
  'Финансовая запись не найдена. Обновите страницу.': 'Finance entry not found. Refresh the page.',
  'Тип финансовой записи нельзя изменить.': 'The finance entry type cannot be changed.',
  'Финансовая запись изменилась. Обновите данные и повторите действие.':
    'This finance entry has changed. Refresh your data and try again.',
  'Достигнут предел финансовых записей. Удалите ненужные записи.':
    'The finance entry limit has been reached. Delete entries you no longer need.',
  'Достигнут предел хранения финансовых записей.':
    'Finance storage is full. Delete entries you no longer need.',
  'Эта оценка больше не является последней в обсуждении. Откройте новую оценку и продолжите от неё.':
    'This review is no longer the latest in the discussion. Open the latest review and continue from it.',
  'Обсуждение достигло предела объёма или числа уточнений. Начните новую идею с кратким описанием текущего варианта.':
    'This discussion has reached its length or round limit. Start a new idea with a short description of its current version.',
  'Запрос помощника использует недопустимый адрес или метод.':
    'The assistant request uses an unsupported address or method.',
  'OpenAI вернул перенаправление вместо ответа. Повторите позже.':
    'OpenAI returned a redirect instead of a response. Try again later.',
  'OpenAI вернул слишком большой ответ. Уточните запрос.':
    'OpenAI returned a response that is too large. Make your request more specific.',
  'Не отправляйте API-ключ в чат. Настройте его в разделе «Настройки».':
    'Do not send your API key in chat. Configure it in Settings.',
  'Запрос слишком большой для помощника. Сократите текст и повторите.':
    'The assistant request is too large. Shorten it and try again.',
  'OpenAI не принял ключ или доступ к модели. Проверьте подключение ИИ в настройках.':
    'OpenAI rejected the key or model access. Check your AI connection in Settings.',
  'OpenAI сообщил о лимите запросов или бюджета. Проверьте лимиты API и повторите позже.':
    'OpenAI reported a request or budget limit. Check your API limits and try again later.',
  'Модель недоступна или не поддерживает этот формат ответа. Проверьте название модели в настройках.':
    'The model is unavailable or does not support this response format. Check the model name in Settings.',
  'Помощник не смог подготовить корректный план. Попробуйте уточнить запрос.':
    'The assistant could not prepare a valid plan. Make your request more specific.',
  'Помощник не успел ответить. Повторите запрос через немного времени.':
    'The assistant timed out. Try again shortly.',
  'Сейчас OpenAI недоступен. Задачи сохранены; попробуйте снова позже.':
    'OpenAI is currently unavailable. Your tasks are saved; try again later.',
  'Помощник вернул неполный ответ. Попробуйте снова.':
    'The assistant returned an incomplete response. Try again.',
  'Помощник предложил некорректное изменение расписания. Уточните запрос и повторите.':
    'The assistant suggested an invalid schedule change. Clarify your request and try again.',
  'Помощник предложил время в прошлом или не изменил план. Попросите новый вариант.':
    'The assistant suggested a past time or left the plan unchanged. Ask for another option.',
  'Событие Google изменилось. Обновите календарь и повторите редактирование.':
    'The Google event has changed. Refresh the calendar and edit it again.',
  'Событие Google больше недоступно. Обновите календарь.':
    'The Google event is no longer available. Refresh the calendar.',
  'Google сообщил о лимите запросов. Подождите немного и повторите.':
    'Google reported a request limit. Wait briefly and try again.',
  'Подключите Google Calendar заново в настройках.': 'Reconnect Google Calendar in Settings.',
  'Google не разрешил это действие. Проверьте права события и подключение Calendar API.':
    'Google did not allow this action. Check the event permissions and Calendar API connection.',
  'Google не успел ответить. Обновите календарь перед повторной записью.':
    'Google timed out. Refresh the calendar before trying to save again.',
  'Не удалось подтвердить ответ Google. Обновите календарь перед повторным сохранением.':
    'The Google response could not be confirmed. Refresh the calendar before saving again.',
  'В выбранном часовом поясе такого времени нет из-за перевода часов. Выберите другое время.':
    'This time does not exist in the selected time zone because of daylight saving time. Choose another time.',
  'Это время повторяется при переводе часов. Выберите однозначное время.':
    'This time occurs twice because of daylight saving time. Choose an unambiguous time.',
  'Завершите событие до полуночи в выбранном часовом поясе.':
    'The event must end before midnight in the selected time zone.',
  'Google вернул неполное событие. Обновите календарь позднее.':
    'Google returned an incomplete event. Refresh the calendar later.',
  'Google вернул некорректные даты события.': 'Google returned invalid event dates.',
  'Google вернул некорректное время события.': 'Google returned an invalid event time.',
  'Google вернул некорректную длительность события.': 'Google returned an invalid event duration.',
  'В этом календаре доступно только чтение. Измените событие в Google Calendar.':
    'This calendar is read-only. Edit the event in Google Calendar.',
  'Google заблокировал изменение этой записи. Откройте её в Google Calendar.':
    'Google has locked this event. Open it in Google Calendar.',
  'Событие занимает несколько дней, имеет сложное время или связано с переводом часов. Измените его в Google Calendar.':
    'This event spans multiple days, has complex timing or crosses a daylight saving change. Edit it in Google Calendar.',
  'Это специальное событие Google. Измените его в Google Calendar.':
    'This is a special Google event. Edit it in Google Calendar.',
  'У встречи есть другие участники или организатор. Измените её в Google Calendar.':
    'This meeting has other attendees or an organizer. Edit it in Google Calendar.',
  'Это вся повторяющаяся серия. В Ritm можно изменить отдельную запись, а серию — в Google Calendar.':
    'This is an entire recurring series. Edit an individual occurrence in Ritm, or the series in Google Calendar.',
  'У события длинное название или описание. Измените его в Google Calendar.':
    'This event has a long title or description. Edit it in Google Calendar.',
  'Не удалось определить версию события. Обновите календарь перед изменением.':
    'The event version could not be determined. Refresh the calendar before editing.',
  'Не удалось прочитать настройку Google. Сохраните её заново.':
    'The Google configuration could not be read. Save it again.',
  'Настройте OAuth Google Calendar в разделе «Подключения».':
    'Configure Google Calendar OAuth in Connections.',
  'OAuth Google задан переменными сервера. Измените их, чтобы настроить подключение.':
    'Google OAuth is configured through server variables. Update them to change the connection.',
  'Проверьте Client ID Google и Client Secret без пробелов.':
    'Check the Google Client ID and Client Secret; remove any spaces.',
  'Для Google OAuth настройте на сервере APP_ORIGIN — адрес приложения.':
    'Set the APP_ORIGIN server variable to the application address for Google OAuth.',
  'Введите Client Secret для нового Client ID Google.':
    'Enter the Client Secret for the new Google Client ID.',
  'Настройка Google изменилась. Начните подключение заново.':
    'The Google configuration has changed. Start the connection again.',
  'Подключение Google изменилось. Обновите страницу.':
    'The Google connection has changed. Refresh the page.',
  'Подключите Google Calendar в настройках.': 'Connect Google Calendar in Settings.',
  'Подключение Google изменилось во время переноса. Запись Ritm сохранена; проверьте событие в прежнем аккаунте.':
    'The Google connection changed during transfer. The Ritm entry is saved; check the event in the previous account.',
  'Не удалось прочитать подключение Google. Настройте его заново.':
    'The Google connection could not be read. Configure it again.',
  'Обновление Google заняло слишком долго. Повторите из настроек.':
    'The Google refresh took too long. Try again from Settings.',
  'Подключение Google уже обновляется. Подождите немного и повторите.':
    'The Google connection is already refreshing. Wait briefly and try again.',
  'Войдите в Ritm перед подключением Google.': 'Sign in to Ritm before connecting Google.',
  'Подключение Google не подтверждено. Начните заново из настроек.':
    'The Google connection was not confirmed. Start again from Settings.',
  'Подключение Google устарело или уже использовано. Начните заново.':
    'The Google connection request expired or was already used. Start again.',
  'Подключение Google устарело. Войдите в Ritm и повторите.':
    'The Google connection request expired. Sign in to Ritm and try again.',
  'Это подключение Google уже обработано.': 'This Google connection request was already processed.',
  'Подключение было отменено. Начните подключение Google заново.':
    'The connection was cancelled. Start connecting Google again.',
  'Сессия Ritm завершилась. Войдите и подключите Google заново.':
    'Your Ritm session ended. Sign in and reconnect Google.',
  'Начато новое подключение Google. Используйте последний запрос из настроек.':
    'A new Google connection was started. Use the latest request from Settings.',
  'Доступ Google не предоставлен. Ваши задачи Ritm сохранены.':
    'Google access was not granted. Your Ritm tasks are saved.',
  'Google не передал код подключения. Повторите из настроек.':
    'Google did not provide an authorization code. Try again from Settings.',
  'Для сохранения событий разрешите доступ к событиям Google Calendar.':
    'Allow access to Google Calendar events to save events.',
  'Google не предоставил постоянный доступ. Подключите календарь заново с подтверждением разрешения.':
    'Google did not grant ongoing access. Reconnect the calendar and confirm the permission.',
  'Для всей палитры разрешите изменение свойств календаря Google. Прежнее подключение сохранено.':
    'Allow changes to Google calendar properties to use the full palette. Your previous connection is saved.',
  'Разрешите доступ к Google Tasks. Прежнее подключение календаря сохранено.':
    'Allow access to Google Tasks. Your previous calendar connection is saved.',
  'Подключите Google Calendar заново с разрешением изменения событий.':
    'Reconnect Google Calendar with permission to edit events.',
  'Google не разрешил доступ к задачам. Включите Google Tasks API в проекте Google Cloud и проверьте разрешение Google Tasks.':
    'Google did not allow task access. Enable Google Tasks API in your Google Cloud project and check Google Tasks permission.',
  'Слишком много списков Google Tasks. Не все статусы удалось проверить.':
    'There are too many Google Tasks lists. Some statuses could not be checked.',
  'Google Tasks вернул неполные данные. Повторите обновление.':
    'Google Tasks returned incomplete data. Refresh again.',
  'Слишком много задач Google. Не все статусы удалось проверить.':
    'There are too many Google tasks. Some statuses could not be checked.',
  'Google Tasks не завершил загрузку. Повторите обновление.':
    'Google Tasks did not finish loading. Refresh again.',
  'Разрешите Google Tasks в настройках, чтобы отмечать выполнение здесь.':
    'Allow Google Tasks in Settings to mark tasks complete here.',
  'Не удалось однозначно определить задачу Google. Откройте её в Google Tasks.':
    'The Google task could not be uniquely identified. Open it in Google Tasks.',
  'Задача не найдена в Google Tasks. Обновите календарь или откройте её в Google.':
    'The task was not found in Google Tasks. Refresh the calendar or open it in Google.',
  'Включите Google Tasks API в проекте Google Cloud и проверьте разрешение Google Tasks.':
    'Enable Google Tasks API in your Google Cloud project and check Google Tasks permission.',
  'Не удалось загрузить статусы Google Tasks. Календарь доступен; повторите обновление.':
    'Google Tasks statuses could not be loaded. The calendar is available; refresh again.',
  'Не удалось проверить связь задачи с календарём Google.':
    'The task link to Google Calendar could not be verified.',
  'Повторяющаяся задача изменяется в Google Tasks.': 'Edit recurring tasks in Google Tasks.',
  'У задачи несколько записей в календаре. Измените выполнение в Google Tasks.':
    'This task has several calendar entries. Change its completion in Google Tasks.',
  'Не удалось однозначно проверить запись задачи Google. Обновите календарь.':
    'The Google task entry could not be uniquely verified. Refresh the calendar.',
  'Связь задачи Google не удалось проверить полностью. Откройте её в Google Tasks.':
    'The Google task link could not be fully verified. Open it in Google Tasks.',
  'Подключение Google изменилось. Обновите календарь перед отметкой выполнения.':
    'The Google connection changed. Refresh the calendar before marking completion.',
  'Разрешите Google Tasks в настройках перед отметкой выполнения.':
    'Allow Google Tasks in Settings before marking completion.',
  'Эта запись не является поддерживаемой личной задачей Google. Откройте её в Google.':
    'This entry is not a supported personal Google task. Open it in Google.',
  'Запись Google больше недоступна. Обновите календарь.':
    'The Google entry is no longer available. Refresh the calendar.',
  'Запись Google изменилась. Обновите календарь перед отметкой выполнения.':
    'The Google entry changed. Refresh the calendar before marking completion.',
  'Для этой записи не найдено однозначной ссылки Google Tasks.':
    'No unique Google Tasks link was found for this entry.',
  'Не удалось однозначно определить задачу Google. Обновите календарь.':
    'The Google task could not be uniquely identified. Refresh the calendar.',
  'Задача Google изменилась или недоступна. Обновите календарь.':
    'The Google task changed or is unavailable. Refresh the calendar.',
  'Название или день задачи Google не совпадают с записью календаря. Обновите календарь или откройте Google Tasks.':
    'The Google task title or day does not match the calendar entry. Refresh the calendar or open Google Tasks.',
  'Статус задачи Google изменился. Обновите календарь перед повторной отметкой.':
    'The Google task status changed. Refresh the calendar before marking completion again.',
  'Связь задачи Google изменилась. Обновите календарь.':
    'The Google task link changed. Refresh the calendar.',
  'Не удалось подтвердить выполнение в Google. Обновите календарь перед повторной отметкой.':
    'Completion in Google could not be confirmed. Refresh the calendar before trying again.',
  'Google вернул неполную палитру календаря. Обновите календарь позднее.':
    'Google returned an incomplete calendar palette. Refresh the calendar later.',
  'Идентификатор цвета Google уже занят другой меткой. Обновите палитру в Google Calendar.':
    'This Google color ID is used by another label. Refresh the palette in Google Calendar.',
  'В Google Calendar уже 200 цветовых меток. Удалите ненужную метку в Google, затем повторите.':
    'Google Calendar already has 200 color labels. Remove an unused label in Google and try again.',
  'Не удалось подтвердить цветовую метку Google. Обновите календарь перед повторным сохранением.':
    'The Google color label could not be confirmed. Refresh the calendar before saving again.',
  'Палитра Google изменилась. Обновите календарь и повторите.':
    'The Google palette changed. Refresh the calendar and try again.',
  'Разрешите новые цвета в подключении Google Calendar, чтобы этот цвет сохранялся и в Google.':
    'Allow new colors in the Google Calendar connection to save this color in Google.',
  'Выберите период Google Calendar от одного до 93 дней.':
    'Choose a Google Calendar period between 1 and 93 days.',
  'Проверьте часовой пояс календаря.': 'Check the calendar time zone.',
  'Google вернул неполный календарь. Попробуйте позднее.':
    'Google returned an incomplete calendar. Try again later.',
  'Google не завершил загрузку календаря. Повторите позднее.':
    'Google did not finish loading the calendar. Try again later.',
  'Подключение Google изменилось. Запись Ritm сохранена; повторный перенос в другой аккаунт отменён.':
    'The Google connection changed. The Ritm entry is saved; transfer to a different account was cancelled.',
  'Идентификатор сохранения уже использован. Обновите календарь и начните новую запись.':
    'This save ID was already used. Refresh the calendar and start a new entry.',
  'Не удалось подтвердить сохранённое событие. Обновите календарь.':
    'The saved event could not be confirmed. Refresh the calendar.',
  'Повторение задаётся при создании. Для изменения всей серии откройте Google Calendar.':
    'Recurrence is set when creating an event. Open Google Calendar to change the whole series.',
  'Событие Google удалено. Обновите календарь.':
    'The Google event was deleted. Refresh the calendar.',
  'Google вернул другую запись. Обновите календарь перед изменением.':
    'Google returned a different entry. Refresh the calendar before editing.',
  'Это событие изменяется в Google Calendar.': 'Edit this event in Google Calendar.',
  'Событие Google изменилось. Обновите календарь перед сохранением.':
    'The Google event changed. Refresh the calendar before saving.',
  'Не удалось подтвердить изменение Google. Обновите календарь.':
    'The Google change could not be confirmed. Refresh the calendar.',
  'Google вернул другую запись. Обновите календарь.':
    'Google returned a different entry. Refresh the calendar.',
  'Это событие удаляется в Google Calendar.': 'Delete this event in Google Calendar.',
  'Событие Google изменилось. Обновите календарь перед удалением.':
    'The Google event changed. Refresh the calendar before deleting.',
  'Подключите Google заново, чтобы проверить план перед применением.':
    'Reconnect Google to check the plan before applying it.',
  'Проверяйте не больше 20 дней за одно применение плана.':
    'Check no more than 20 days when applying a plan.',
  'Google вернул неполное расписание. Уточните период перед применением плана.':
    'Google returned an incomplete schedule. Narrow the period before applying the plan.',
  'Адрес запроса слишком длинный.': 'The request address is too long.',
  'Этот метод запроса не поддерживается.': 'This request method is not supported.',
  'Отправьте JSON без сжатия.': 'Send JSON without compression.',
  'Запрос слишком большой. Сократите текст.': 'The request is too large. Shorten the text.',
  'Этот запрос не должен содержать тело.': 'This request must not contain a body.',
  'Один из агентов вернул неполную оценку. Общее мнение не сформировано; попробуйте уточнить идею.':
    'One agent returned an incomplete review. No overall opinion was formed; clarify the idea and try again.',
  'Опишите идею текстом до 6000 символов.': 'Describe your idea in up to 6,000 characters.',
  'Не отправляйте API-ключ в тексте идеи. Настройте его в разделе «Настройки».':
    'Do not include your API key in the idea. Configure it in Settings.',
  'Проверьте название модели в настройках ИИ.': 'Check the model name in AI Settings.',
  'Агенты не успели завершить оценку. Общее мнение не сформировано; попробуйте позже.':
    'The agents timed out. No overall opinion was formed; try again later.',
  'OpenAI не принял ключ или доступ к модели. Проверьте настройки ИИ.':
    'OpenAI rejected the key or model access. Check AI Settings.',
  'OpenAI сообщил о лимите запросов или бюджета. Повторите позже.':
    'OpenAI reported a request or budget limit. Try again later.',
  'Модель не поддерживает оценку идей в этом формате. Проверьте настройки ИИ.':
    'The model does not support this idea review format. Check AI Settings.',
  'Не удалось получить все четыре оценки. Общее мнение не сформировано; попробуйте позже.':
    'All four reviews could not be obtained. No overall opinion was formed; try again later.',
  'Используйте часовой пояс из настроек Ritm.': 'Use the time zone from Ritm Settings.',
  'Google Tasks пока недоступен.': 'Google Tasks is currently unavailable.',
  'Дождитесь ответа помощника перед удалением диалога.':
    'Wait for the assistant to finish before deleting the conversation.',
  'Этот идентификатор запроса уже использован для другого сообщения.':
    'This request ID was already used for another message.',
  'Помощник уже обрабатывает этот запрос. Дождитесь ответа.':
    'The assistant is already processing this request. Wait for the response.',
  'Подключите OpenAI в настройках, чтобы начать разговор.':
    'Connect OpenAI in Settings to start a conversation.',
  'В этом диалоге уже 100 запросов. Начните новый диалог.':
    'This conversation already has 100 requests. Start a new conversation.',
  'В этом диалоге помощник уже отвечает. Дождитесь завершения.':
    'The assistant is already responding in this conversation. Wait for it to finish.',
  'Запрос отменён.': 'The request was cancelled.',
  'Помощник уже отвечает. Дождитесь завершения ответа.':
    'The assistant is already responding. Wait for it to finish.',
  'Предложение уже обработано или удалено. Обновите диалог.':
    'The proposal was already processed or deleted. Refresh the conversation.',
  'Этот запрос не найден.': 'This request was not found.',
  'Проверьте ключ OpenAI (начинается с sk-) и название модели.':
    'Check the OpenAI key (starts with sk-) and model name.',
  'Введите Client ID Google и Client Secret без пробелов. Callback URL задаётся сервером.':
    'Enter the Google Client ID and Client Secret without spaces. The server sets the callback URL.',
  'Проверьте имя, почту, часовой пояс и время рабочего дня.':
    'Check the name, email, language, time zone and work hours.',
  'Введите логин и пароль приложения.': 'Enter your application login and password.',
  'Введите сообщение длиной до 6000 символов.': 'Enter a message of up to 6,000 characters.',
  'Не удалось выбрать изменения. Обновите диалог и повторите.':
    'The changes could not be selected. Refresh the conversation and try again.',
  'Проверьте заполненные поля: название, дату, время и длительность.':
    'Check the title, date, time and duration fields.',
  'Отправьте JSON в UTF-8 без сжатия.': 'Send UTF-8 JSON without compression.',
  'Не удалось прочитать запрос. Попробуйте снова.': 'The request could not be read. Try again.',
  'Не удалось выполнить действие. Ваши сохранённые данные доступны после обновления страницы.':
    'The action could not be completed. Your saved data is available after refreshing the page.',
  'Серверная база ещё не подготовлена. Выполните миграции Ritm.':
    'The server database is not ready. Run the Ritm migrations.',
  'Выполните миграции Ritm перед запуском приложения.':
    'Run the Ritm migrations before starting the application.',
  'Удалите ненужные диалоги, чтобы начать новый.':
    'Delete unused conversations to start a new one.',
  'Начало рабочего дня должно быть раньше окончания.': 'The work day must start before it ends.',
  'Достигнут лимит 2000 задач. Удалите ненужные записи.':
    'The 2,000-task limit was reached. Delete unused entries.',
  'Укажите дату существующего повторения задачи.': 'Enter the date of an existing task occurrence.',
  'Укажите дату повторения, которое хотите завершить.':
    'Enter the occurrence date you want to complete.',
  'Достигнут предел выполненных повторений. Создайте новую серию.':
    'The completed-occurrence limit was reached. Create a new series.',
  'Эту запись уже переносили в Google. Восстановленную копию Ritm нельзя перенести повторно.':
    'This entry was already transferred to Google. The restored Ritm copy cannot be transferred again.',
  'Есть 1000 незавершённых переносов. Завершите синхронизацию существующих записей перед добавлением новых.':
    'There are 1,000 unfinished transfers. Finish syncing existing entries before adding new ones.',
  'Запрос переноса не найден. Начните заново.': 'The transfer request was not found. Start again.',
  'Запрос переноса не найден. Запись Ritm сохранена; начните заново.':
    'The transfer request was not found. The Ritm entry is saved; start again.',
  'Перенесённая запись восстановлена. Обновите календарь.':
    'The transferred entry was restored. Refresh the calendar.',
  'Задание уже восстановлено. Обновите список.': 'The task was already restored. Refresh the list.',
  'Эту запись уже нельзя восстановить. Создайте новое задание.':
    'This entry can no longer be restored. Create a new task.',
  'Срок обработки запроса истёк или ответ уже сохранён. Обновите диалог и повторите.':
    'The request expired or the response was already saved. Refresh the conversation and try again.',
  'Это предложение уже обработано. Обновите диалог.':
    'This proposal was already processed. Refresh the conversation.',
  'Выберите одно изменение для каждого задания.': 'Select one change for each task.',
  'Задание изменилось после применения плана. Отмена не затронет новые изменения — обновите диалог.':
    'The task changed after the plan was applied. Undo will not overwrite newer changes; refresh the conversation.',
  'Расписание изменилось с момента ответа ИИ. Попросите помощника подготовить новый план.':
    'The schedule changed after the AI response. Ask the assistant for a new plan.',
  'Встречи и повторяющиеся серии изменяйте в календаре вручную.':
    'Edit meetings and recurring series manually in the calendar.',
  'Невозможно применить это время.': 'This time cannot be applied.',
  'Предложенное время уже прошло. Попросите помощника подготовить новый план.':
    'The proposed time has already passed. Ask the assistant for a new plan.',
  'Хранилище Ritm заполнено. Удалите старые задачи или диалоги и повторите действие.':
    'Ritm storage is full. Delete old tasks or conversations and try again.',
  'Эта задача сохранена только в списке дел и не переносится в календарь.':
    'This task is saved only in the to-do list and cannot be transferred to the calendar.',
  'Для переноса укажите дату незавершённой записи. Серия с историей выполнения остаётся в Ritm.':
    'Set a date for an incomplete entry to transfer it. Series with completion history stay in Ritm.',
  'Запись или часовой пояс изменились во время переноса. Новые правки Ritm сохранены; проверьте созданное событие Google перед следующим действием.':
    'The entry or time zone changed during transfer. Your newer Ritm edits are saved; check the created Google event before the next action.',
  'Подключение Google изменилось во время переноса. Запись Ritm сохранена; проверьте событие в прежнем аккаунте Google.':
    'The Google connection changed during transfer. The Ritm entry is saved; check the event in the previous Google account.',
  'Настройте SECRET_ENCRYPTION_KEY: 32 случайных байта в base64 или hex.':
    'Set SECRET_ENCRYPTION_KEY to 32 random bytes encoded as base64 or hex.',
  'Серверное шифрование ещё не настроено. Добавьте SECRET_ENCRYPTION_KEY.':
    'Server encryption is not configured. Add SECRET_ENCRYPTION_KEY.',
  'Не удалось прочитать защищённое хранилище.': 'The protected storage could not be read.',
  'Сохранённый секрет превышает допустимый размер.': 'The saved secret exceeds the size limit.',
  'Не удалось прочитать сохранённый секрет. Проверьте ключ шифрования или настройте подключение заново.':
    'The saved secret could not be read. Check the encryption key or configure the connection again.',
  'Хранилище подключения ещё не настроено.': 'Connection storage is not configured.',
  'Не удалось прочитать ключ ИИ.': 'The AI key could not be read.',
  'Ключ задан на сервере через OPENAI_API_KEY. Измените серверную переменную и перезапустите приложение.':
    'The key is set through OPENAI_API_KEY on the server. Update the server variable and restart the application.',
  'Проверьте формат ключа OpenAI и название модели.': 'Check the OpenAI key format and model name.',
  'Ключ задан через OPENAI_API_KEY. Удалите серверную переменную и перезапустите приложение.':
    'The key is set through OPENAI_API_KEY. Remove the server variable and restart the application.',
  'Сейчас обрабатывается несколько входов. Повторите через несколько секунд.':
    'Several sign-ins are being processed. Try again in a few seconds.',
  'Войдите в Ritm, чтобы продолжить.': 'Sign in to Ritm to continue.',
  'Недопустимый адрес приложения.': 'Invalid application address.',
  'Откройте Ritm по настроенному адресу приложения.':
    'Open Ritm at its configured application address.',
  'Настройте пароль приложения для сетевого доступа.':
    'Configure an application password for network access.',
  'Запрос с этого сайта запрещён.': 'Requests from this site are not allowed.',
  'Запрос с другого сайта запрещён.': 'Requests from another site are not allowed.',
  'Запрос должен содержать JSON.': 'The request must contain JSON.',
  'Неверный логин или пароль.': 'Incorrect login or password.',
  'Перенос ещё не завершён. Запись Ritm сохранена; повторите действие, чтобы подтвердить результат Google.':
    'The transfer is not finished. The Ritm entry is saved; try again to confirm the Google result.',
  'Эта запись уже переносится в Google. Подождите немного и повторите.':
    'This entry is already being transferred to Google. Wait briefly and try again.',
  'Google подтвердил событие, но перенос Ritm ещё не завершён. Повторите действие; новый дубль не создастся.':
    'Google confirmed the event, but the Ritm transfer is not finished. Try again; no new duplicate will be created.',
};

export function localizeError(
  message: string,
  code: string | undefined,
  language: Language,
): string {
  if (language !== 'en') return message;
  if (Object.hasOwn(messages, message)) return messages[message];
  // Anchored templates only: preserve the original personal title as a single capture.
  const overlap =
    /^«([\s\S]*)» пересекается с другой записью\. Выберите другое время или попросите новый план\.$/.exec(
      message,
    );
  if (overlap)
    return `“${overlap[1]}” overlaps another entry. Choose another time or ask for a new plan.`;
  const googleOverlap =
    /^«([\s\S]*)» пересекается с событием Google\. Выберите другое время\.$/.exec(message);
  if (googleOverlap) return `“${googleOverlap[1]}” overlaps a Google event. Choose another time.`;
  const rate =
    /^(Ritm временно ограничил частоту разбора идей|Слишком много запросов в Ritm)\. Повторите через (\d{1,4}) с\.$/.exec(
      message,
    );
  if (rate)
    return `${code === 'IDEA_REVIEW_RATE_LIMIT' ? 'Ritm temporarily limited idea reviews.' : 'Too many requests to Ritm.'} Try again in ${rate[2]} seconds.`;
  const missing = /^(Задание|Диалог|Предложение|Изменение) не найдено\. Обновите страницу\.$/.exec(
    message,
  );
  if (missing)
    return `${({ Задание: 'Task', Диалог: 'Conversation', Предложение: 'Proposal', Изменение: 'Change' } as Record<string, string>)[missing[1]]} not found. Refresh the page.`;
  // Unknown server errors get a safe English fallback, without leaking provider content.
  return 'The action could not be completed. Refresh the page and try again.';
}

export function localizeGoogleEvent(
  event: GoogleCalendarEvent,
  language: Language,
): GoogleCalendarEvent {
  if (language !== 'en') return event;
  return {
    ...event,
    ...(event.readOnlyReason
      ? { readOnlyReason: localizeError(event.readOnlyReason, undefined, language) }
      : {}),
    ...(event.taskUnavailableReason
      ? { taskUnavailableReason: localizeError(event.taskUnavailableReason, undefined, language) }
      : {}),
  };
}
export function localizeGoogleResult(
  result: GoogleCalendarResult,
  language: Language,
): GoogleCalendarResult {
  if (language !== 'en') return result;
  return {
    ...result,
    events: result.events.map((event) => localizeGoogleEvent(event, language)),
    ...(result.tasks
      ? {
          tasks: {
            ...result.tasks,
            ...(result.tasks.message
              ? { message: localizeError(result.tasks.message, undefined, language) }
              : {}),
          },
        }
      : {}),
  };
}
