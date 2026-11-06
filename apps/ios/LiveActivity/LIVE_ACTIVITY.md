# Widget Extension и Live Activity

Эта папка включена как target/product `RitmWidgets` и объявлена в `xtool.yml`.
Общие ActivityAttributes, request-модели и snapshot находятся в модуле `RitmSystem`.

Инструкция сборки, изолированный patch xtool для одной App Group, генератор App Intents,
границы структурных проверок и сценарии устройства: [SYSTEM_FEATURES_BUILD.md](../SYSTEM_FEATURES_BUILD.md).

По умолчанию используется `RITM_INTERACTIVE=1`: действия отдыха и подтверждения заполненного
подхода выполняются через App Intents. Владелец проверил фоновые кнопки и ввод веса в Ritm
на iPhone 13. `RITM_INTERACTIVE=0` оставлен только как явный диагностический fallback со
ссылками. Заполнять недостающий вес/повторы и подтверждать завершение тренировки нужно
в приложении. Утверждённые основные экраны сохраняются. Актуальная проверка устройства —
в [SYSTEM_FEATURES_VERIFICATION.md](../SYSTEM_FEATURES_VERIFICATION.md).
