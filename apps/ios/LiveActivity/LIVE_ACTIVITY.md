# Widget Extension и Live Activity

Эта папка включена как target/product `RitmWidgets` и объявлена в `xtool.yml`.
Общие ActivityAttributes, request-модели и snapshot находятся в модуле `RitmSystem`.

Инструкция сборки, изолированный patch xtool для одной App Group, генератор App Intents,
границы структурных проверок и сценарии устройства: [SYSTEM_FEATURES_BUILD.md](../SYSTEM_FEATURES_BUILD.md).

По умолчанию применяется проверенный в отдельном Lab подход со ссылками, открывающими app.
Для попытки прямых действий используется `RITM_INTERACTIVE=1`. Статус сборки и metadata
не означает проверенную доставку действий на iPhone. Утверждённые основные экраны
сохраняются при добавлении системных поверхностей.
