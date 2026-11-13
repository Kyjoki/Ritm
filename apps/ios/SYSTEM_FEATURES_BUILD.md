# WidgetKit / ActivityKit: сборка и границы проверки

Общие Foundation-модели и ActivityAttributes находятся в `Sources/RitmSystem`, который зависит
от `RitmCore`. Приложение и extension `RitmWidgets` используют один модуль, без копирования
типа Attributes. Основные экраны приложения этим пайплайном не меняются.

## Unsigned сборка

Установленный toolchain проверен: Swift 6.4.2, iPhoneOS SDK 27.1, xtool 1.24.0.
В отдельном Ritm Lab владелец подтвердил уведомление, виджет-пример и Activity с таймером
на iPhone 13 / iOS 27.2. Это не проверка новой сборки Ritm, App Group или фоновых кнопок.

Из корня репозитория в WSL:

```bash
bash apps/ios/scripts/build-system-features.sh debug
RITM_INTERACTIVE=1 bash apps/ios/scripts/build-system-features.sh debug
```

Wrapper подключает Swiftly, создаёт пустой bootstrap-index, собирает app/appex и сохраняет
копию в `apps/ios/.build/ritm-artifacts/<configuration>-<mode>-<unique>/Ritm.app` вместе со
`structure.json`. В interactive режиме: compile → constvalues → metadata → повторная упаковка.
Скрипт никогда не авторизуется в Apple, не регистрирует App Group, не подписывает для устройства
и не устанавливает. Допустимые конфигурации: `debug` и `release`.
`RITM_ARTIFACT_ROOT=/persistent/path` задаёт конечный каталог артефактов, если исходники
собираются во временной WSL-копии. Копирование и проверка завершаются в том же Bash-вызове.

Наблюдение на этом компьютере 6 ноября: Swift 6.4.2 падал в `lib_InternalSwiftScan` при
native сборке с cache на `/mnt/c`. Причина падения не установлена. Настоящие SDK-сборки
успешно прошли из `/var/tmp/ritm-native-features-20261106` с CPU affinity `0,1` и
`RITM_ARTIFACT_ROOT`, указывающим на Windows `.build/ritm-artifacts`. `/tmp` очищался после
перезапуска WSL, поэтому для рабочей копии используется `/var/tmp`, а готовый `.app`/IPA
копируется во внешний постоянный каталог до выхода из того же Bash-вызова.

Проверенный developer-signed export 6 ноября: RELEASE0 IPA сохранён как
`.build/ritm-artifacts/Ritm-system-features-release.ipa`. Строгий `--signed` verifier прошёл:
отдельные app/extension application IDs и личные keychain scopes, одна одинаковая настоящая
App Group в signatures и grants обоих profiles. Profiles истекают
`2026-11-13T09:39:32Z`. Это подтверждённый подписанный артефакт и provisioning;
установка нового Ritm и исполнение его поверхностей на устройстве не выполнялись.

По умолчанию включён `RITM_INTERACTIVE=1`; диагностический `RITM_INTERACTIVE=0` оставляет
deep links, открывающие app. `RITM_INTERACTIVE=1` определяет compile flag
во всех targets/dependencies и включает экспериментальные прямые `Button(intent:)`.
Компиляцию и metadata нельзя выдавать за подтверждённую доставку действий iOS.

`RITM_CORE_TESTS_ONLY=1 swift test` из `apps/ios` включает Foundation-части обоих общих
модулей в существующий test target. Перед native сборкой этот флаг нужно убрать.

## Изолированный tool с App Group

Штатный 1.24.0 отфильтровывает App Groups для free team. Глобальный инструмент менять не нужно:

```bash
bash apps/ios/scripts/prepare-xtool.sh --source-only
bash apps/ios/scripts/prepare-system-toolchain.sh --build-and-test
RITM_XTOOL=/absolute/path/to/apps/ios/.build/ritm-tools/xtool-1.24.0-pr284/.build/release/xtool \
  bash apps/ios/scripts/build-system-features.sh debug
```

Официальный source закреплён на `70e1568fdfcb20b560774057cd783f02361293b9` (1.24.0),
patch — upstream merge PR #284 `0c63e6979fd3ebeba3bbd5c8f9eca91142db19ae`.
PR #284 меняет доступность App Groups для free team и явный отказ при запросе нескольких групп.
Полный prepare-system-toolchain дополнительно применяет узкий per-bundle patch к xtool и
zsign 1.9.0, закреплённому на `f6158be9e62a5ce2a53d72b1a6d880880da956c8`, через локальный
SwiftPM editable override. Он собирает private tool и отдельный синтетический fixture.
Source, MIT LICENSE и provenance JSON хранятся в игнорируемом `.build/ritm-tools`;
MIT notices также находятся рядом с reviewable patches в `scripts/patches`.
Подготовка/компиляция инструмента не читает Apple auth и не создаёт идентификаторы или группы.

Проверка 6 ноября 2026: private xtool с PR #284 и per-bundle patches собран. Полный offline
fixture прошёл: отдельные application/keychain IDs, общий synthetic App Group, root-only
HealthKit только у app, отказы при отсутствии child scope и пути вне root. Локальный receipt:
`.build/ritm-tools/signer-fixture-lKuXKG/signer-fixture-report.json`; provenance содержит
`offlineFixtureVerified=true` и SHA-256 binary/report. В этом тесте Apple credentials,
provisioning и устройство не использовались. Настоящий App Group grant проверяется по
профилям отдельного developer export; offline receipt его не заменяет.

При первом developer export обнаружена гонка: root app и extension provisioning выполняются
параллельно и могут использовать пустые snapshots списка групп. Read-only Apple-запрос
6 ноября подтвердил 3 owned groups, 1 exact match ожидаемой Ritm-группы и 1 logical-base
match; реальные имена и IDs в receipt не сохраняются. `xtool-1.24.0-group-reuse.patch`
использует exact IDs в исходном snapshot, а после ошибки единственного create-запроса
выполняет максимум три read-only refetch с короткой паузой. Он переиспользует только одно
точное owned совпадение; иной ID, отсутствие и неоднозначность не дают assign и не вызывают
повторного create. Диагностическая команда private tool `ds app-groups-audit` выводит только
counts/matches; обычный offline prepare её не вызывает.
Offline recovery-проверки прошли: delayed exact match найден на третьем чтении, иной owned
ID отклонён после трёх чтений, два одинаковых exact records отклонены сразу. Новых create
запросов этот recovery не выполняет. Этот failure-path проверен offline; successful signed
export выше подтверждает настоящее переиспользование уже существовавшей группы.

Оба targets запрашивают `group.app.ritm.personal`; в обоих Info.plist — ключ `RitmAppGroup`.
При будущей подписи xtool может заменить ID на `group.<signed root bundle ID>`.
Runtime разрешает этот вариант без hardcoded Team ID. Приложение — единственный писатель
снимка; extension только читает. Сессии и пароли в снимок не входят.
Наличие entitlement в исходниках не доказывает grant Apple или работающий shared container.

## Собственный узкий metadata emitter

`scripts/appintents-metadata.py` не копирует GPL-генератор MicYou. Он читает текущие
`*-OutputFileMap.json` и реальные `.swiftconstvalues` общего модуля `RitmSystem`, затем
создаёт index для app и extension. SwiftPM fallback читает outputs того же общего модуля.
В index сохраняется compiler mangling; оба bundle ID присутствуют в
`mangledTypeNameByBundleIdentifier` и V2.

Поддерживается только `LiveActivityIntent` struct с одним nonoptional
`@Parameter(title: "Request") request: String`, literal title и
`perform() -> some IntentResult`. Неизвестные объявления, wrapper arguments, authentication
policy или режимы вызывают ошибку. Строка request несёт session/set/version; приложение
проверяет их при выполнении. Metadata не заменяет stale-tap guards.

Этот shape проверен отдельным Swift 6.4.2/SDK 27.1 probe; работа dispatch на устройстве
ещё требует проверки. Data format index не является публичным контрактом Apple.

### Действие Shortcuts «Записать покупку»

Второй поддерживаемый shape — обычный `AppIntent` модуля `Ritm` (`Sources/Ritm/PurchaseIntent.swift`,
`RecordPurchaseIntent`): только обязательные `String`-параметры с literal `title`, `openAppWhenRun =
false`, `perform() -> some IntentResult`, без своего `parameterSummary`, без system protocol.
Действие записывается только в index приложения (не виджета), `isDiscoverable` true,
`systemProtocols`/`systemProtocolMetadata` пустые, routing только на bundle ID приложения.
Index виджета и действие тренировки остаются прежними байт-в-байт: `scripts/test-appintents-metadata.py`
сравнивает вывод с golden-файлом, снятым старым emitter-ом на реальных constvalues. Источники формата:
реальный Xcode-вывод для `LiveActivityIntent` со `String`-параметром (ссылка выше) и дамп
`WidgetConfigurationIntent` из блога mengtnt (набор ключей, `descriptionMetadata`); **пустые
`systemProtocols` для обычного AppIntent и отсутствие `parameterSummary` — вывод по аналогии, не
наблюдение Apple-вывода**. Всё остальное (опциональные/нечисловые параметры, summary, entities,
`AppShortcutsProvider`) по-прежнему вызывает ошибку.

```bash
python3 apps/ios/scripts/test-appintents-metadata.py
```

Видит ли Shortcuts действие и выполняется ли оно в фоне — проверяется только на iPhone.

```bash
python3 apps/ios/scripts/appintents-metadata.py --configuration debug
python3 apps/ios/scripts/appintents-metadata.py --configuration debug --check
```

Для будущих signed routing IDs есть `RITM_METADATA_APP_ID` и `RITM_METADATA_EXTENSION_ID`;
defaults соответствуют unsigned app. После любого изменения signed IDs index нужно сверять.

## Подпись и device test — отдельный этап

Экспорт с developer-профилем имеет форму `xtool dev build --configuration release --sign --ipa`
с заранее подготовленными metadata. Unsigned wrapper эту отдельную команду не выполняет.
Экспорт артефакта и установка на телефон — разные операции. Итоговый IPA проверяется без установки:

```bash
python3 apps/ios/scripts/verify-system-bundle.py /absolute/path/Ritm.ipa --signed
# Для interactive варианта: также --interactive.
```

Проверки: app/appex, непустой `__text`, defined extension `_main`, WidgetKit extension point,
ActivityKit flag, одна одинаковая App Group в signatures и grants profiles, сроки profiles,
Info/signature/profile IDs, parameters и routing metadata. Это структурная проверка, не
проверка цепочки доверия подписи или запуска iOS. Legacy signer 1.24.0 имеет ограничение
per-target entitlements (TODO #131); несовпадение должно приводить к ошибке проверки.

У старого backend zsign 1.9.0 `src/lib/Zupersign.cpp` использует только `entitlements[0]`.
Полный prepare-script исправляет оба слоя: Swift передаёт все entries, C backend валидирует
canonical paths внутри root app и выбирает XML отдельно для каждого bundle; вспомогательные
executables не наследуют root entitlements. Fixture использует tiny C/Mach-O app/appex,
синтетические IDs и ad-hoc identity; проверяет разные app/keychain IDs, одну общую группу,
отсутствие root-only HealthKit у extension и отказы для отсутствующего child scope/чужого пути.
Результат записывается в `signer-fixture-report.json`, его SHA-256 — в provenance.
Fixture не регистрирует группу и не подтверждает Apple provisioning или запуск на iOS.

`xtool install` 1.24.0 повторно подписывает и не имеет `--skip-signing`; в Lab это привело
к повторному XTL-префиксу. Повторное изменение ID ломает подготовленный routing index.
Для будущей установки нужно сохранять одну идентичность и сверять итоговый payload.

На iPhone отдельно проверить: виджет с реальными данными/датой снимка; чтение после
перезапуска и блокировки; очистку после выхода/смены сервера; timezone/day rollover;
старт, обновление и завершение Activity; timer в фоне; stale/duplicate taps; отказ разрешений;
одиночное локальное уведомление и переход по ссылке. Система выбирает частоту WidgetKit reload.
Бесплатные profiles действуют 7 дней, до 3 приложений/устройство и 10 App IDs; extension
требует отдельный App ID. Существующее приложение не удаляется ради освобождения слота.

## Первичные источники

- [xtool extensions](https://github.com/xtool-org/xtool/blob/1.24.0/Documentation/xtool.docc/Appex.md)
- [PR #284: одна App Group для free team](https://github.com/xtool-org/xtool/pull/284)
- [PR #393: удержание WidgetBundle main](https://github.com/xtool-org/xtool/pull/393)
- [PR #389: отдельные entitlements app/appex через RCodesign](https://github.com/xtool-org/xtool/pull/389)
- [PR #397: metadata из constvalues](https://github.com/xtool-org/xtool/pull/397)
- [Публичный референс String parameter от автора myRemote](https://github.com/IlyasKhallouki/myRemote/blob/main/Tools/generate-appintents-metadata.py)
- [Apple: интерактивность и процесс intents](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Apple: App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple: Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)
