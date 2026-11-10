import RitmCore
import SwiftUI

/// «Live Activity»: the lock-screen switches (the card, hidden weights, the rest-over
/// notification). A status line appears only when something is wrong, so the page never claims a
/// working lock-screen card without the extension.
struct SettingsLiveActivityPage: View {
  @Environment(RitmStore.self) private var store

  private var alerts: WorkoutAlerts { store.workouts.alerts }
  private var settings: WorkoutAlertSettings { alerts.settings }

  var body: some View {
    SettingsPage(title: "Live Activity") {
      SettingsGroup {
        SettingsToggleRow(
          icon: "dot.radiowaves.left.and.right",
          title: store.text("Тренировка на экране блокировки", "Workout on the lock screen"),
          isOn: binding(\.showsLiveActivity))
        SettingsToggleRow(
          icon: "lock",
          title: store.text("Скрывать веса", "Hide weights"),
          subtitle: store.text("На экране блокировки", "On the lock screen"),
          isOn: binding(\.hidesWeights))
        SettingsToggleRow(
          icon: "bell",
          title: store.text("Окончание отдыха", "Rest is over"),
          subtitle: store.text("Уведомление", "Notification"),
          isOn: Binding(
            get: { settings.notifiesRestEnd },
            set: { value in
              settings.notifiesRestEnd = value
              Task {
                if value { await alerts.notifications.requestPermission() }
                store.workouts.alerts.resync()
              }
            }))
      }
      if liveActivityIsProblem { SettingsFootnote(text: liveActivityStatus, tone: .error) }
      if notificationIsProblem { SettingsFootnote(text: notificationStatus, tone: .error) }
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

/// «Виджеты»: the one widget of the app and how to put it on the Home Screen.
struct SettingsWidgetsPage: View {
  @Environment(RitmStore.self) private var store

  var body: some View {
    SettingsPage(title: store.text("Виджеты", "Widgets")) {
      SettingsGroup {
        SettingsInfoRow(
          icon: "square.grid.2x2", title: store.text("Мой день и привычки", "My day & habits"),
          subtitle: store.text(
            "Дела на сегодня, ближайшее событие и привычки.",
            "Today's tasks, your next event and habits."),
          value: SettingsTrailing("2×2, 4×2"))
      }
      SettingsFootnote(
        text: store.text(
          "Экран «Домой» → удерживайте → «+» → Ritm", "Home Screen → touch and hold → + → Ritm"))
    }
  }
}
