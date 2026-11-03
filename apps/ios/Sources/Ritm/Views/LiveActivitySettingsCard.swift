import RitmCore
import SwiftUI

/// The lock-screen switches of the «Apple Здоровье» card (proto: «Показывать тренировку на экране
/// блокировки», «Скрывать веса…», «Уведомление об окончании отдыха»): the end-of-rest notification
/// and the lock-screen card. A status line appears only when something is wrong, so the card never
/// claims a working lock-screen card without the extension.
struct LiveActivitySettingsRows: View {
  @Environment(RitmStore.self) private var store

  private var alerts: WorkoutAlerts { store.workouts.alerts }
  private var settings: WorkoutAlertSettings { alerts.settings }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsSwitchRow(
        title: store.text("Показывать тренировку на экране блокировки", "Show the workout on the lock screen"),
        isOn: binding(\.showsLiveActivity))
      if liveActivityIsProblem { statusLine(liveActivityStatus) }
      SettingsSwitchRow(
        title: store.text("Скрывать веса на экране блокировки", "Hide weights on the lock screen"),
        isOn: binding(\.hidesWeights))
      SettingsSwitchRow(
        title: store.text("Уведомление об окончании отдыха", "Rest-over notification"),
        isOn: Binding(
          get: { settings.notifiesRestEnd },
          set: { value in
            settings.notifiesRestEnd = value
            Task {
              if value { await alerts.notifications.requestPermission() }
              store.workouts.alerts.resync()
            }
          }))
      if notificationIsProblem { statusLine(notificationStatus) }
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

  private func statusLine(_ text: String) -> some View {
    Text(text)
      .ritmFont(10, lineSpacing: 3.5)
      .foregroundStyle(RitmTheme.danger)
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
    return ""
  }

  private var liveActivityIsProblem: Bool {
    guard settings.showsLiveActivity else { return false }
    if !LiveActivityManager.extensionInstalled || !LiveActivityManager.systemAllowsActivities { return true }
    if case .failed = alerts.liveActivity.status { return true }
    return false
  }

  private var notificationStatus: String {
    store.text(
      "iPhone не разрешил уведомления Ritm. Включите их в Настройках iPhone. Тренировка работает и без них.",
      "iPhone does not allow Ritm notifications. Turn them on in iPhone Settings. Workouts work without them.")
  }

  private var notificationIsProblem: Bool {
    settings.notifiesRestEnd && alerts.notifications.permission == .denied
  }
}
