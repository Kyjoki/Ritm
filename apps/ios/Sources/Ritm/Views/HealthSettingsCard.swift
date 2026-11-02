import RitmCore
import SwiftUI
import UIKit

/// «Apple Здоровье»: whether finished workouts are saved to Apple Health. Ritm only writes a
/// strength-training record (type, start, end, duration); it reads nothing and computes no
/// calories. The connection state shows only what iOS confirms for WRITE access.
struct HealthSettingsCard: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

  private var health: HealthExportStore { store.health }

  var body: some View {
    SettingsCard(symbol: "heart.text.square", title: store.text("Apple Здоровье", "Apple Health")) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsHint(
          text: store.text(
            "Ritm сохраняет в Здоровье только завершённые тренировки: тип «Силовая тренировка», время начала и окончания и длительность. Подходы, веса и упражнения остаются в журнале Ritm. Тренировка может появиться в приложении «Фитнес». Калории Ritm не считает и ничего не читает из Здоровья.",
            "Ritm saves only finished workouts to Health: the Strength Training type, start and end time and duration. Sets, weights and exercises stay in the Ritm journal. The workout may appear in the Fitness app. Ritm computes no calories and reads nothing from Health."
          ))
        stateRow.padding(.top, 14)
        SettingsSwitchRow(
          title: store.text(
            "Сохранять завершённые тренировки в Apple Здоровье",
            "Save finished workouts to Apple Health"),
          note: store.text(
            "Если тренировку записывают и Apple Watch, в Здоровье могут быть две записи: Ritm сохраняет свою и ничего не объединяет сам. Выключите переключатель, если это не нужно.",
            "If an Apple Watch also records the workout, Health may show two entries: Ritm saves its own and merges nothing by itself. Turn the switch off if you do not want that."
          ),
          isOn: Binding(get: { health.saveToHealth }, set: { health.saveToHealth = $0 })
        )
        .disabled(health.shareStatus == .unavailable)
        resultSection
      }
    }
    .task { await health.refreshStatus() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await health.refreshStatus() } }
    }
  }

  // MARK: Connection

  private var stateRow: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(stateTitle).ritmFont(13, weight: .semibold).foregroundStyle(RitmTheme.text)
      if let hint = stateHint {
        Text(hint).ritmFont(10, lineSpacing: 3).foregroundStyle(RitmTheme.muted)
      }
      switch health.shareStatus {
      case .notDetermined:
        SettingsSmallButton(title: store.text("Подключить", "Connect")) {
          Task { await health.connect() }
        }
      case .denied:
        SettingsSmallButton(title: store.text("Открыть Настройки iOS", "Open iOS Settings")) {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
      case .allowed, .unavailable:
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }

  private var stateTitle: String {
    switch health.shareStatus {
    case .unavailable: store.text("Здоровье недоступно на этом устройстве", "Health is not available on this device")
    case .notDetermined: store.text("Не подключено", "Not connected")
    case .allowed: store.text("Запись разрешена", "Writing is allowed")
    case .denied: store.text("Запись запрещена", "Writing is denied")
    }
  }

  private var stateHint: String? {
    switch health.shareStatus {
    case .denied:
      store.text(
        "Откройте Настройки iOS → Здоровье → Доступ к данным и устройства → Ritm и разрешите запись тренировок.",
        "Open iOS Settings → Health → Data Access & Devices → Ritm and allow writing workouts.")
    case .notDetermined:
      store.text(
        "iOS спросит разрешение только на запись тренировок.",
        "iOS will ask only for permission to write workouts.")
    default: nil
    }
  }

  // MARK: Results

  @ViewBuilder private var resultSection: some View {
    if let last = health.lastAttempt, let summary = summary(of: last) {
      VStack(alignment: .leading, spacing: 10) {
        Text(summary).ritmFont(12).foregroundStyle(RitmTheme.text)
          .fixedSize(horizontal: false, vertical: true)
        if health.hasRetryable {
          SettingsSmallButton(title: store.text("Повторить", "Retry")) { health.retryAllFailed() }
        }
      }
      .padding(.top, 4)
    } else if health.hasRetryable {
      SettingsSmallButton(title: store.text("Повторить", "Retry")) { health.retryAllFailed() }
    }
    let recent = health.recent(limit: 3)
    if !recent.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(store.text("Последние записи", "Recent saves"))
          .ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.muted)
        ForEach(recent) { record in
          Text(row(record)).ritmFont(11).foregroundStyle(RitmTheme.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.top, 14)
    }
  }

  private func summary(of record: HealthExportRecord) -> String? {
    guard let result = record.lastResult else { return nil }
    switch result {
    case .saved(_, let at): return store.text("Сохранено \(stamp(at))", "Saved \(stamp(at))")
    case .failed(let reason, _, _):
      return store.text("Не удалось сохранить: \(reasonText(reason))", "Could not save: \(reasonText(reason))")
    case .uncertain:
      return store.text(
        "Результат неизвестен, проверим при следующем запуске",
        "The result is unknown; Ritm will check at the next launch")
    case .notRequested, .pending, .saving: return nil
    }
  }

  private func row(_ record: HealthExportRecord) -> String {
    let minutes = max(1, Int((record.payload.activeDuration / 60).rounded()))
    let state: String
    switch record.status {
    case .saved: state = store.text("сохранено", "saved")
    case .failed: state = store.text("не сохранено", "not saved")
    case .uncertain: state = store.text("результат неизвестен", "result unknown")
    case .saving: state = store.text("сохраняется", "saving")
    case .pending, .notRequested: state = store.text("ожидает", "waiting")
    }
    return store.text(
      "\(stamp(record.payload.end)) · \(minutes) мин · \(state)",
      "\(stamp(record.payload.end)) · \(minutes) min · \(state)")
  }

  private func reasonText(_ reason: HealthExportFailure) -> String {
    switch reason {
    case .notAuthorized: store.text("нет разрешения на запись", "writing is not allowed")
    case .healthUnavailable: store.text("Здоровье недоступно", "Health is not available")
    case .dataProtected: store.text("iPhone заблокирован", "the iPhone is locked")
    case .saveFailed: store.text("Здоровье не приняло запись", "Health did not accept the record")
    case .unknown: store.text("неизвестная ошибка", "unknown error")
    }
  }

  private func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: store.language == .ru ? "ru_RU" : "en_GB")
    formatter.dateFormat = "dd.MM, HH:mm"
    return formatter.string(from: date)
  }
}
