import RitmCore
import SwiftUI
import UIKit

/// «Apple Здоровье»: whether finished workouts are saved to Apple Health, with the lock-screen
/// switches below (proto settings.js `healthCard`). Ritm only writes a strength-training record
/// (type, start, end, duration); it reads nothing and computes no calories. The connection state
/// shows only what iOS confirms for WRITE access.
struct HealthSettingsCard: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

  private var health: HealthExportStore { store.health }
  private var allowed: Bool { health.shareStatus == .allowed }

  var body: some View {
    SettingsCard(symbol: "heart.text.square", title: store.text("Apple Здоровье", "Apple Health")) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsHint(
          text: store.text(
            "Завершённые тренировки: тип — силовая, время начала и окончания, длительность. Подходы, веса и упражнения остаются в журнале Ritm. Тренировки могут отображаться в Apple «Фитнес».",
            "Finished workouts: type strength, start and end time, duration. Sets, weights and exercises stay in the Ritm journal. Workouts may show in Apple Fitness."
          ))
        connectionRow.padding(.top, 16)
        SettingsSwitchRow(
          title: store.text(
            "Сохранять завершённые тренировки в Apple Здоровье",
            "Save finished workouts to Apple Health"),
          isOn: Binding(
            get: { allowed && health.saveToHealth }, set: { health.saveToHealth = $0 })
        )
        .disabled(!allowed)
        resultLine
        LiveActivitySettingsRows()
      }
    }
    .task { await health.refreshStatus() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await health.refreshStatus() } }
    }
  }

  // MARK: Connection

  private var connectionRow: some View {
    SettingsConnectionRow(
      symbol: "heart", name: store.text("Доступ к Здоровью", "Health access"),
      status: statusText, connected: allowed, notes: stateHint.map { [$0] } ?? []
    ) {
      switch health.shareStatus {
      case .notDetermined:
        SettingsSmallButton(title: store.text("Подключить", "Connect")) {
          Task { await health.connect() }
        }
      case .denied:
        SettingsSmallButton(title: store.text("Открыть настройки", "Open Settings")) {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
      case .allowed, .unavailable:
        EmptyView()
      }
    }
  }

  private var statusText: String {
    switch health.shareStatus {
    case .unavailable: store.text("Здоровье недоступно на этом устройстве", "Health is not available on this device")
    case .notDetermined: store.text("Не подключено", "Not connected")
    case .allowed: store.text("Подключено", "Connected")
    case .denied: store.text("Доступ запрещён", "Access denied")
    }
  }

  private var stateHint: String? {
    guard health.shareStatus == .denied else { return nil }
    return store.text(
      "Откройте Настройки iOS → Здоровье → Доступ к данным и устройства → Ritm и разрешите запись тренировок.",
      "Open iOS Settings → Health → Data Access & Devices → Ritm and allow writing workouts.")
  }

  // MARK: Last save

  /// `.s-hl`: one line with the result of the last save, and Retry when something failed.
  @ViewBuilder private var resultLine: some View {
    if health.shareStatus == .allowed {
      if let last = health.lastAttempt, let result = line(of: last) {
        HStack(spacing: 6) {
          RitmSymbol(result.symbol).font(.system(size: 13))
          Text(result.text).fixedSize(horizontal: false, vertical: true)
          if health.hasRetryable {
            Button(store.text("Повторить", "Retry")) { health.retryAllFailed() }
              .buttonStyle(SettingsTextButtonStyle())
          }
        }
        .ritmFont(12, weight: .medium)
        .foregroundStyle(result.color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 8)
      } else if health.hasRetryable {
        Button(store.text("Повторить", "Retry")) { health.retryAllFailed() }
          .buttonStyle(SettingsTextButtonStyle())
      }
    }
  }

  private struct ResultLine {
    let symbol: String
    let text: String
    let color: Color
  }

  private static var saved: Color { Color(light: 0x2A7F66, dark: 0x86D4B6) }

  private func line(of record: HealthExportRecord) -> ResultLine? {
    guard let result = record.lastResult else { return nil }
    switch result {
    case .saved(_, let at):
      return ResultLine(
        symbol: "checkmark.circle", text: store.text("Сохранено \(stamp(at))", "Saved \(stamp(at))"),
        color: Self.saved)
    case .failed(let reason, _, _):
      return ResultLine(
        symbol: "exclamationmark.circle",
        text: store.text("Не удалось сохранить: \(reasonText(reason))", "Could not save: \(reasonText(reason))"),
        color: RitmTheme.danger)
    case .uncertain:
      return ResultLine(
        symbol: "questionmark.circle",
        text: store.text(
          "Результат неизвестен, проверим при следующем запуске",
          "The result is unknown; Ritm will check at the next launch"),
        color: RitmTheme.muted)
    case .notRequested, .pending, .saving: return nil
    }
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

  private static let formatterRU = makeFormatter("ru_RU")
  private static let formatterEN = makeFormatter("en_GB")

  private static func makeFormatter(_ locale: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: locale)
    formatter.dateFormat = "dd.MM, HH:mm"
    return formatter
  }

  private func stamp(_ date: Date) -> String {
    (store.language == .ru ? Self.formatterRU : Self.formatterEN).string(from: date)
  }
}
