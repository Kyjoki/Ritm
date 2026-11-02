# Live Activity «Тренировка» — prepared, NOT active

Status: the code exists and compiles, but this build installs **no** widget extension, so no
lock-screen card appears. Settings → «Тренировка вне приложения» says so honestly (it checks
whether the app bundle really contains a `com.apple.widgetkit-extension` appex).

This folder is deliberately outside `Package.swift` and `xtool.yml`, so `xtool dev build` stays
green. What is already done:

| Part                                                                           | Where                                                                          |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Pure state, update rules, lifecycle                                            | `Sources/RitmCore/LiveActivityState.swift`, `RestTimerCommands.swift` (tested) |
| Shared attributes (`ContentState` = `LiveActivityContent`)                     | `Sources/Ritm/RitmWorkoutAttributes.swift`                                     |
| App-side manager (start/reuse/update/end, errors swallowed)                    | `Sources/Ritm/LiveActivityManager.swift`                                       |
| `NSSupportsLiveActivities = true`                                              | `Info.plist`                                                                   |
| Extension sources (lock-screen card, minimal Dynamic Island, `ritm://workout`) | this folder                                                                    |

The card has no buttons: «+30 с», «Пропустить», «Подход выполнен» need App Intents, whose
metadata xtool 1.24.0 does not generate (xtool #145, PR #397 still a draft).

## Why it is not switched on

- xtool 1.24.0 does not build/sign a widget extension correctly: empty appex (#313), signing
  failure (#379). Fixes are unreleased.
- App Groups are limited on a free Apple ID, so sharing state through a group is not an option
  (the card needs none: everything travels in `ContentState`).

## Exact remaining steps

1. Get a toolchain that builds extensions: a newer xtool (main / patched, once #313 and #379 are
   fixed) **or** Xcode / the paid Apple Developer Program.
2. Make the extension target and give it the shared files:
   - create `Sources/RitmWidget/`; copy or symlink there `LiveActivity/RitmWidgetBundle.swift`,
     `LiveActivity/RitmWorkoutLiveActivity.swift` and **the same**
     `Sources/Ritm/RitmWorkoutAttributes.swift` (a symlink keeps the two from drifting; if the
     tooling dislikes symlinks, copy it and keep it identical);
   - copy `LiveActivity/RitmWidget-Info.plist` next to it.
3. `Package.swift`: add `.target(name: "RitmWidget", dependencies: ["RitmCore"])` (inside the
   `!coreTestsOnly` branch) and a product `.library(name: "RitmWidget", targets: ["RitmWidget"])`.
4. `xtool.yml`: add an `extensions:` entry for it (name, product `RitmWidget`, infoPath
   `RitmWidget-Info.plist`, bundle ID `app.ritm.personal.widget`; check xtool's current schema).
5. `NSSupportsLiveActivities` is already in `Info.plist`; keep it.
6. Build, install, then run the checks below. No app code needs to change: once the appex is in the
   bundle, `LiveActivityManager.extensionInstalled` becomes true and the manager starts requesting.

Type-checked: steps 2 files compile against the iPhoneOS SDK in a private SwiftPM package
(`xtool dev build`, no warnings, `@main` in a library target included). This does not prove that
xtool packages and signs them as an extension.

## Checks only the iPhone 13 can do

- The card appears on the lock screen after «Начать тренировку» with the switch on, and the app
  settings line changes to «Расширение есть в сборке…».
- The countdown runs by itself and matches the in-app rest timer; «+30 с» in the app moves it.
- With «Скрывать веса» on, no weights anywhere on the card; reps only.
- The card ends on finishing/cancelling a workout, and after a force-quit + relaunch no second
  card appears (the existing one is reused, a foreign one is ended).
- A tap opens Ritm (`ritm://workout`; the app just comes to the front).
- iOS Settings → Ritm → Live Activities off: the settings line says so and the workout is fine.
- Free-Apple-ID signing really installs an app with an extension (7-day profile, bundle IDs).

## Known limits

- The card is updated from the app only. When the rest ends while Ritm is in the background, the
  countdown stops at 00:00 but the label stays «Отдых» until the app is opened (or `staleDate`,
  rest end + 30 s, marks it stale). Remote push updates need a server and are not planned.
- The text on the card is Russian only.
- Links: xtool issues #313 (empty appex), #379 (extension signing), #145 and PR #397 (App Intents
  metadata) — https://github.com/xtool-org/xtool/issues/313 , /issues/379 , /issues/145 , /pull/397
