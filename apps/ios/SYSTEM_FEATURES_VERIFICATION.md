# Проверка системных поверхностей — 6 ноября 2026

Работа изолирована в `chatgpt/ios-notifications-widgets-live-activities`, база
`b1d4927fd255150f9bfed46cdb6cce7a2f74cd05`. Обновление `main`, установка на телефон и
Vercel deployment в эту проверку не входят. Публикация Vercel для feature-ветки отключена.

## Подтверждено

- **450 portable Swift tests, 0 failures**, включая 26 `SystemSurfacesTests`,
  18 проверок уведомлений/reconciliation и 16 `RestTimerCommandsTests`.
- Swift 6.4.2 / iPhoneOS SDK 27.1: **DEBUG с `RITM_INTERACTIVE=1`** и **RELEASE с
  `RITM_INTERACTIVE=0`** скомпилированы. Оба содержат настоящий WidgetKit appex с кодом и
  определённым `_main`, общий Attributes type, ActivityKit flag и одинаковую App Group.
- DEBUG metadata: одно внутреннее `LiveActivityIntent`, `request: String`,
  `isDiscoverable=false`, согласованный routing app/appex. RELEASE metadata пустой,
  действия в базовом варианте открывают приложение.
- Изолированный подписыватель проверен на offline app/appex: собственные app/keychain IDs,
  общая synthetic group, HealthKit только у app; отсутствующие и внешние scopes отклоняются.
- **Настоящий подписанный RELEASE IPA экспортирован** существующей авторизацией xtool.
  Проверены подписи/профили app и appex: разные корректные application identifiers и
  собственные Keychain scopes, одна общая группа с grant Apple, отсутствие HealthKit у
  extension. Runtime-алгоритм выбора контейнера совпадает с реальным group entitlement.
  Срок проверенных профилей: **13 ноября 2026, 09:39:32 UTC**.
- После ошибки Apple 35 read-only аудит подтвердил наличие ровно одной ожидаемой группы
  в данном аккаунте. Экспорт с переиспользованием существующей группы завершился успешно.
  Другие группы не удалялись и не переименовывались.
- Shell/Python syntax, metadata/bundle checks и `git diff --check` пройдены.

Локальный архив исключён из Git:
`.build/ritm-artifacts/Ritm-system-features-release.ipa`.

SHA-256: `f47ab27fe89c4d9855d3eee8b791997aae8e7cf54143871d0dcdff46ca339ce2`.

## Что ещё требует iPhone

Эта новая сборка Ritm **не установлена и не проверена на телефоне**. Прошлая проверка
отдельного Ritm Lab не заменяет её. Проверка структуры и grant профилей также не доказывает
запуск iOS или фактическое чтение контейнера extension.

Нужен проход на iPhone: разрешение/доставка уведомления при блокировке; старт, отдых,
следующий подход/упражнение и завершение Activity; добавление small/medium виджета с
реальными данными; обновление после привычки и очистка после выхода. Прямые фоновые
`Button(intent:)` из экспериментального режима отдельно требуют проверки dispatch на iOS.

Для сборок WSL использовалась Linux filesystem: `/var/tmp`, ограничение CPU affinity до
двух ядер и постоянный `RITM_ARTIFACT_ROOT`. На `/mnt/c` наблюдался сбой dependency scanner
Swift; каталог сборки в `/tmp` после завершения процессов оказался недоступен. Итоговые
артефакты сохранены в постоянной папке Windows; повторная сборка из `/var/tmp` пройдена.
В неизменённых native views остаются предупреждения Swift 6.4 об actor isolation;
компиляция завершается успешно.
