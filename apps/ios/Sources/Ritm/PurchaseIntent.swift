#if canImport(AppIntents) && RITM_INTERACTIVE
import AppIntents
import RitmCore

/// «Записать покупку»: the Shortcuts «Транзакция» automation calls it with the Transaction
/// variables. It runs in the Ritm app process in the background (no foreground launch), stores
/// the purchase in the Wallet inbox and shows the Wallet notice at once. All five parameters are
/// plain text, exactly what the `purchases.txt` line carries, so both routes give the same id.
/// The metadata for this action comes from scripts/appintents-metadata.py (SYSTEM_FEATURES_BUILD.md).
struct RecordPurchaseIntent: AppIntent {
  static let title: LocalizedStringResource = "Записать покупку"
  static let openAppWhenRun: Bool = false
  static let isDiscoverable: Bool = true

  @Parameter(title: "Сумма") var amount: String
  @Parameter(title: "Магазин") var merchant: String
  @Parameter(title: "Карта") var card: String
  @Parameter(title: "Дата") var date: String
  @Parameter(title: "Время") var at: String

  init() {}

  func perform() async throws -> some IntentResult {
    let values = WalletShortcutValues(
      amount: amount, merchant: merchant, card: card, date: date, at: at)
    do {
      _ = try await Self.record(values)
    } catch PurchaseRecorder.Failure.invalid {
      throw PurchaseIntentFailure.invalid
    } catch PurchaseRecorder.Failure.notReady {
      throw PurchaseIntentFailure.notReady
    }
    return .result()
  }

  @MainActor private static func record(_ values: WalletShortcutValues) async throws
    -> PurchaseRecorder.Outcome
  {
    try await PurchaseRecorder.record(values)
  }
}
#endif
