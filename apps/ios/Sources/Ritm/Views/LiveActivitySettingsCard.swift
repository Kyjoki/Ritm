import RitmCore
import SwiftUI

/// «Тренировка вне приложения»: the end-of-rest notification and the lock-screen card. The state
/// lines say only what is confirmed: whether the extension is in this build, what iOS allows,
/// and what the last request returned. They never claim a working card without the extension.
struct LiveActivitySettingsCard: View {
  @Environment(RitmStore.self) private var store

  private var alerts: WorkoutAlerts { store.workouts.alerts }
  private var settings: WorkoutAlertSettings { alerts.settings }

  var body: some View {
    SettingsCard(symbol: "lock.iphone", title: store.text("Тренировка вне приложения", "Workout outside the app")) {
      SettingsSwitchRow(
        title: store.text("Показывать тренировку на экране блокировки", "Show the workout on the lock screen"),
        note: store.text(
          "Отдых, упражнение и подход. Веса там только плановые, не выполненные.",
          "Rest, exercise and set. Weights there are planned ones, never done."),
        isOn: binding(\.showsLiveActivity))
      statusLine(liveActivityStatus, isProblem: liveActivityIsProblem)
      Rectangle().fill(RitmTheme.line).frame(height: 1)
      SettingsSwitchRow(
        title: store.text("Скрывать веса на экране блокировки", "Hide weights on the lock screen"),
        note: store.text(
          "Касается карточки и уведомления об отдыхе.", "Applies to the card and the rest notification."),
        isOn: binding(\.hidesWeights))
      Rectangle().fill(RitmTheme.line).frame(height: 1)
      SettingsSwitchRow(
        title: store.text("Уведомление об окончании отдыха", "Rest-over notification"),
        note: store.text(
          "Один сигнал, когда таймер отдыха дойдёт до нуля, пока Ritm свёрнут.",
          "One alert when the rest timer reaches zero while Ritm is in the background."),
        isOn: Binding(
          get: { settings.notifiesRestEnd },
          set: { value in
            settings.notifiesRestEnd = value
            Task {
              if value { await alerts.notifications.requestPermission() }
              store.workouts.alerts.resync()
            }
          }))
      statusLine(notificationStatus, isProblem: notificationIsProblem)
    }
    .task { await alerts.notifications.refreshPermission() }
  }

  private func binding(_ keyPath: ReferenceWritableKeyPath<WorkoutAlertSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { settings[keyPath: keyPath] },
      set: { value in
        settings[keyPath: keyPath] = value
        alerts.resync()
      })
  }

  private func statusLine(_ text: String, isProblem: Bool) -> some View {
    Text(text)
      .ritmFont(10, lineSpacing: 4)
      .foregroundStyle(isProblem ? RitmTheme.danger : RitmTheme.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 12)
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: Honest state text

  private var liveActivityStatus: String {
    guard LiveActivityManager.extensionInstalled else {
      return store.text(
        "В этой сборке Ritm нет расширения Live Activity, поэтому карточка на экране блокировки пока не появится. Настройка сохранится.",
        "This Ritm build has no Live Activity extension, so the lock-screen card cannot appear yet. The setting is kept.")
    }
    guard LiveActivityManager.systemAllowsActivities else {
      return store.text(
        "Live Activities выключены в Настройках iPhone для Ritm.",
        "Live Activities are turned off for Ritm in iPhone Settings.")
    }
    if case .failed(let reason) = alerts.liveActivity.status {
      return store.text(
        "iOS не запустила карточку: \(reason). Тренировка это не затрагивает.",
        "iOS did not start the card: \(reason). The workout is not affected.")
    }
    return store.text(
      "Расширение есть в сборке и iOS разрешает Live Activities. Карточка появится, когда начнётся тренировка.",
      "The extension is in this build and iOS allows Live Activities. The card appears when a workout starts.")
  }

  private var liveActivityIsProblem: Bool {
    guard settings.showsLiveActivity else { return false }
    if !LiveActivityManager.extensionInstalled || !LiveActivityManager.systemAllowsActivities { return true }
    if case .failed = alerts.liveActivity.status { return true }
    return false
  }

  private var notificationStatus: String {
    switch alerts.notifications.permission {
    case .notDetermined:
      return store.text(
        "Разрешение iPhone попросим, когда вы включите это уведомление.",
        "iPhone permission is asked when you turn this notification on.")
    case .denied:
      return store.text(
        "iPhone не разрешил уведомления Ritm. Включите их в Настройках iPhone. Тренировка работает и без них.",
        "iPhone does not allow Ritm notifications. Turn them on in iPhone Settings. Workouts work without them.")
    case .allowed:
      return store.text("Разрешение iPhone выдано.", "iPhone permission is granted.")
    }
  }

  private var notificationIsProblem: Bool {
    settings.notifiesRestEnd && alerts.notifications.permission == .denied
  }
}
