import Foundation
import RitmCore
import RitmSystem
import UserNotifications

/// Keeps the little the background action needs about the signed-in account (see
/// `WalletAlertGate`). The running app writes it whenever it applies the account settings and
/// erases it on sign-out; a cold launch of the action only reads it. UserDefaults, this iPhone only.
@MainActor
enum WalletAlertGateStore {
  private static let key = "ritm.wallet.alert-gate.v1"

  static func load(defaults: UserDefaults = .standard) -> WalletAlertGate? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WalletAlertGate.self, from: $0) }
  }

  static func save(_ gate: WalletAlertGate, defaults: UserDefaults = .standard) {
    guard load(defaults: defaults) != gate, let data = try? JSONEncoder().encode(gate) else {
      return
    }
    defaults.set(data, forKey: key)
  }

  static func clear(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

/// The work of the Shortcuts action «Записать покупку»: in the app process, in the background,
/// without the UI and without the network. It uses only what the app persisted: the Wallet inbox
/// (UserDefaults JSON), the account epoch, the gate above and the notification permission.
@MainActor
enum PurchaseRecorder {
  enum Failure: Error { case invalid, notReady }
  enum Outcome: Equatable { case recorded(notified: Bool), duplicate }

  /// The running app's inbox, so a warm process never keeps a second, stale copy.
  static var liveInbox: WalletInboxStore?

  static func record(
    _ values: WalletShortcutValues, now: Date = Date(), defaults: UserDefaults = .standard,
    center: UNUserNotificationCenter = .current()
  ) async throws -> Outcome {
    let epoch = AccountSurfaceContext.current(defaults: defaults)
    let gate = WalletAlertGateStore.load(defaults: defaults)
    guard WalletShortcutPolicy.mayRecord(gate: gate, epoch: epoch) else { throw Failure.notReady }
    let today = HabitSchedule.dateKey(now, timeZone: gate?.timeZone ?? "Asia/Qyzylorda")
    guard
      let purchase = WalletShortcutIntake.purchase(
        values, today: today, receivedAt: ISO8601DateFormatter().string(from: now))
    else { throw Failure.invalid }
    let inbox = liveInbox ?? WalletInboxStore(defaults: defaults)
    guard inbox.receiveSilently(purchase) == .added else { return .duplicate }
    guard let plan = WalletShortcutPolicy.notice(for: purchase, gate: gate, epoch: epoch, now: now)
    else { return .recorded(notified: false) }
    let permission = await center.notificationSettings().authorizationStatus
    guard LocalNotifications.isAllowed(permission) else { return .recorded(notified: false) }
    // Same request-id shape as the in-app reconciler, so confirming or skipping the purchase
    // removes this banner too (LocalNotifications.removeWallet).
    let requestID = plan.identifier + ".request." + UUID().uuidString.lowercased()
    do {
      try await LocalNotifications.add(plan, requestID: requestID, to: center)
      return .recorded(notified: true)
    } catch {
      // The purchase is already in the inbox; the owner sees it when Ritm opens.
      return .recorded(notified: false)
    }
  }
}

enum PurchaseIntentFailure: LocalizedError {
  case invalid, notReady
  var errorDescription: String? {
    let ru = Locale.preferredLanguages.first?.hasPrefix("ru") == true
    switch self {
    case .invalid:
      return ru ? "Не удалось прочитать покупку: нужны сумма и магазин." : "Could not read the purchase: an amount and a merchant are needed."
    case .notReady:
      return ru ? "Откройте Ritm и войдите в аккаунт, затем повторите." : "Open Ritm and sign in, then try again."
    }
  }
}
