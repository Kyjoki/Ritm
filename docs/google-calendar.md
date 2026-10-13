# Google Calendar

Интеграция рассчитана на одного владельца Ritm и основной календарь `primary`.
Пользователь разрешил чтение, создание и изменение событий. Приложение
запрашивает `calendar.events`; удаление событий, управление календарями,
приглашение участников и изменение ACL не реализованы.
[Разрешения Google Calendar](https://developers.google.com/workspace/calendar/api/auth).

## Настройка OAuth-клиента

Нужен OAuth-клиент типа **Web application**. В проекте Google Cloud включите
Google Calendar API. В Ritm откройте **Настройки → Подключения → Google Calendar →
Настроить**. Форма показывает точный callback текущего сервера и позволяет
сохранить Client ID и Client Secret. Добавьте показанный адрес в Google Cloud,
затем сохраните данные. Сохранение не запускает Google consent: аккаунт можно
подключить позже отдельной кнопкой «Подключить».

Client Secret передаётся только авторизованным запросом на свой сервер Ritm,
сохраняется в существующем AES-GCM хранилище и не возвращается клиенту.
В PostgreSQL сохранён шифротекст, ключ задаётся `SECRET_ENCRYPTION_KEY`.
При повторном редактировании пустое поле сохраняет прежний secret только
для того же Client ID. Новый Client ID требует новый secret. Изменение
credentials прекращает прежнее подключение и отменяет старые OAuth flows;
задачи Ritm и события Google сохраняются.

Callback вычисляется из серверного `APP_ORIGIN`, его нельзя изменить в форме.
Для локального Vite установите `APP_ORIGIN=http://127.0.0.1:5173`; для
опубликованного Ritm — `https://ritm-eta-hazel.vercel.app`. Если доверенный
origin неизвестен, форма объясняет отсутствие callback и не сохраняет данные.

Альтернативно можно задать серверные переменные. Они имеют приоритет над
сохранённой настройкой; форма показывает этот режим без изменения credentials:

```dotenv
GOOGLE_CLIENT_ID=your-web-client.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-server-only-client-secret
GOOGLE_REDIRECT_URI=http://127.0.0.1:5173/api/integrations/google/callback
```

В **Google Auth Platform → Clients → выбранный Web application client →
Authorized redirect URIs** добавьте точный адрес. Возможные адреса:

- разработка с Vite: `http://127.0.0.1:5173/api/integrations/google/callback`;
- локальная собранная версия: `http://127.0.0.1:3001/api/integrations/google/callback`;
- согласованное сетевое размещение:
  `https://ВАШ-ДОМЕН/api/integrations/google/callback`.

Публичный callback должен совпадать с `APP_ORIGIN` и использовать HTTPS.
`localhost` и `127.0.0.1` — разные адреса: выберите один и используйте его
последовательно. Домен, порт, путь и завершающий слеш должны совпадать с
зарегистрированным URI. Javascript origins для серверного redirect flow
не требуются. Существующие redirect URI другого приложения оставьте на месте;
его secret не нужно менять для добавления адреса Ritm.
[Настройка OAuth clients](https://support.google.com/cloud/answer/15549257?hl=en).

Общий клиент/Google Cloud project сохраняет общую область разрешений и
consent-настройки с другим приложением. Для полной изоляции можно использовать
отдельный проект. Ritm не выполняет глобальный revoke при отключении, потому
что Google отзывает разрешения всех клиентов проекта.
[Google OAuth и отзыв разрешений](https://developers.google.com/identity/protocols/oauth2/web-server#tokenrevoke).

## Подключение и сохранение токенов

Сохранение настройки или env само по себе не подключает календарь. Без полного OAuth config
API возвращает `unconfigured`, без подтверждённого grant — `disconnected`.
Кнопка подключения открывает Google только после явного действия владельца.

Используются Authorization Code, PKCE S256, offline access и подтверждение
разрешения. Каждый flow привязан к действующей сессии владельца, отдельной
HttpOnly correlation-cookie с SameSite=Lax, одноразовому state и TTL десять
минут. Это позволяет обработать внешний callback при основной сессии
SameSite=Strict. Повторный state, выход владельца, изменение серверных
credentials и более новый flow отменяют предыдущий запрос подключения.
Сам callback не создаёт сессию входа в Ritm.
[Официальный Node.js OAuth SDK](https://googleapis.dev/nodejs/google-auth-library/latest/classes/OAuth2Client.html).

State/PKCE и токены хранятся серверно через `SecretStore`: локально —
зашифрованные записи SQLite, в общем размещении — зашифрованные записи
PostgreSQL. AES-256-GCM связывает шифротекст с именем записи. Для PostgreSQL
нужен постоянный `SECRET_ENCRYPTION_KEY`; локально используется закрытый
`.secret-key`. Client secret и токены не входят в bootstrap или UI.

Refresh координируется durable lease между серверными экземплярами. Если
refresh-response не содержит нового refresh token, сохраняется прежний.
При `invalid_grant` показывается `reauth_required`. Для первого подключения
нужен полученный refresh token; токен другого приложения не заимствуется.
В режиме External/Testing токены для Calendar обычно истекают через семь
дней; повторное подключение не следует скрывать за постоянным статусом успеха.
[Сроки действия OAuth-токенов](https://developers.google.com/identity/protocols/oauth2#expiration).

«Отключить» удаляет только grant Ritm, прекращает использование его токенов
и отменяет незавершённый flow. События Google и локальные задачи сохраняются.

## События и запись

Загрузка ограничена диапазоном до 93 дней и 1000 просмотренных записей.
Обрабатываются страницы, включая пустую страницу с `nextPageToken`.
Google раскрывает повторения через `singleEvents=true`; фиксированные
периодные запросы не смешиваются с `syncToken`. При достижении лимита API
возвращает `partial=true`. Общий срок чтения — 25 секунд, отдельный HTTP-запрос
ограничен 15 секундами; транспорт получает сигнал отмены. Проверка нескольких
дней перед применением плана использует общий срок и максимум четыре
одновременных запроса, при ошибке остальные отменяются. Время события сохраняет offset, отображение
использует часовой пояс пользователя. Для all-day конец является исключающей
датой, а отменённые события не показываются.
[Загрузка событий](https://developers.google.com/workspace/calendar/api/v3/reference/events/list),
[формат события](https://developers.google.com/workspace/calendar/api/v3/reference/events).

Импортированные записи имеют отдельный тип `GoogleCalendarEvent`; локальный
CRUD задач их не изменяет. Запись выполняется только явным сохранением формы.
Создание использует стабильный requestId и детерминированный Google ID, поэтому
повтор того же запроса после сетевой ошибки не создаёт новую запись.
Редактирование сверяет ETag, передаёт If-Match, а конфликт версии возвращает 409.
[Версии ресурсов](https://developers.google.com/workspace/calendar/api/guides/version-resources).

Личные экземпляры повторяющихся событий редактируются по их собственному ID.
Форма сообщает, что изменяется только выбранная запись; сервер перед PATCH
повторно получает именно этот экземпляр. Родительская серия с recurrence
через этот маршрут не изменяется.
[Отдельные экземпляры](https://developers.google.com/workspace/calendar/api/guides/recurringevents#modify_or_delete_instances).

Цвет читается из Google colorId и отображается мягким полупрозрачным оттенком.
В форме можно выбрать один из 11 цветов либо «По умолчанию». Выбранный цвет
сохраняется в Google; отсутствие colorId в запросе сохраняет прежний цвет,
а null сбрасывает переопределение. Остальные поля, включая напоминания,
участников и служебные данные серии, в PATCH не передаются.
[Частичное изменение](https://developers.google.com/workspace/calendar/api/v3/reference/events/patch).

Первая форма поддерживает личное событие одного дня либо временной интервал
до 12 часов, завершающийся до полуночи. Время, отсутствующее или повторяющееся
при переводе часов, отклоняется с понятным сообщением. Сложные многодневные
события, специальные типы, locked events и встречи с другими участниками
доступны для просмотра; изменяются в Google Calendar. API повторно проверяет
это ограничение перед записью. Attendees не передаются; используется
`sendUpdates=none`. Абсолютное отсутствие писем Google не гарантирует.
[Создание событий и sendUpdates](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert).

ИИ не имеет инструмента записи в Google. При подтверждении изменения
локального плана сервер повторно читает занятое время Google. All-day busy
событие блокирует день. Неполная загрузка или необходимость повторного входа
не разрешают применить план с обещанием свободного времени. После проверки
события всё ещё могут поменяться непосредственно в Google.

## API

- `GET /api/integrations/google/status` — безопасный статус;
- `POST /api/integrations/google/connect` — начало OAuth;
- `GET /api/integrations/google/callback` — единственный callback;
- `GET /api/integrations/google/events?from=YYYY-MM-DD&to=YYYY-MM-DD` —
  период, где `to` не включается;
- `POST /api/integrations/google/events` — `{ event, requestId }`;
- `PATCH /api/integrations/google/events/:id` — `{ event, etag }`;
- `DELETE /api/integrations/google/connection` — локальное отключение.

У `event` поля `title`, `description`, `date`, `time`, `duration`, `allDay`,
необязательный `colorId` (строки 1–11 либо null).
При `allDay=true` время равно null. Произвольные calendar ID и OAuth endpoints
не принимаются. Ошибки Google не возвращаются сырыми: они могут содержать
credential headers, authorization code и тело запроса.

## Проверка

`tests/google-calendar.test.ts` проверяет привязку/replay/истечение state,
конкурентную замену flow, refresh, пагинацию, частичную загрузку, часовые пояса
и DST, idempotency создания, ETag, права гостей и блокирование занятого времени.
Все внешние вызовы в этих тестах заменены контрактным transport. Реальные
credentials, consent и изменение пользовательского календаря не выполнялись.
Подключение и публикация проверяются после серверной настройки и отдельного
согласования размещения с пользователем.
