import Foundation

// The Ritm action «Записать покупку» (an App Intent) is called by the Shortcuts «Транзакция»
// automation with the Transaction variables as plain text, exactly the values that the
// `purchases.txt` line carries. This file turns them into the SAME purchase (same id) the file
// import produces, and decides whether a notification may be shown without opening the app.

/// The five texts the Shortcuts action passes. Nothing is validated here.
public struct WalletShortcutValues: Equatable, Sendable {
  public var amount: String
  public var merchant: String
  public var card: String
  public var date: String
  public var at: String

  public init(amount: String, merchant: String, card: String, date: String, at: String) {
    self.amount = amount
    self.merchant = merchant
    self.card = card
    self.date = date
    self.at = at
  }
}

public enum WalletShortcutIntake {
  /// The purchase for these values, or nil when they are not a purchase (no amount, no merchant).
  /// It goes through `WalletFileImport`, so a value pair that is also written to `purchases.txt`
  /// yields the same id and the later file import counts it as a duplicate.
  public static func purchase(
    _ values: WalletShortcutValues, today: String, receivedAt: String
  ) -> WalletPurchase? {
    WalletFileImport.parse(text: line(for: values), today: today, receivedAt: receivedAt)
      .purchases.first
  }

  /// The `ritm://add?…` line these values stand for. Characters that would split or change a
  /// query value are percent-encoded, so «AT&T» or «A+B» stay one merchant; everything else is
  /// written raw, as the Shortcuts «Добавить в файл» step writes it.
  static func line(for values: WalletShortcutValues) -> String {
    let fields: [(String, String)] = [
      ("amount", values.amount), ("merchant", values.merchant), ("card", values.card),
      ("date", values.date), ("at", values.at),
    ]
    let query =
      fields
      .map { "\($0.0)=\(escaped(clean($0.1)))" }
      .joined(separator: "&")
    return "\(WalletLink.scheme)://add?" + query
  }

  /// A value is one line of text: line breaks would turn it into several file lines.
  private static func clean(_ text: String) -> String {
    text.components(separatedBy: .newlines).joined(separator: " ")
  }

  private static let structural: [Character: String] = [
    "%": "%25", "&": "%26", "=": "%3D", "#": "%23", "+": "%2B",
  ]

  private static func escaped(_ text: String) -> String {
    text.reduce(into: "") { $0 += structural[$1] ?? String($1) }
  }
}

/// What the app last knew about the signed-in account, written by the running app and read by a
/// cold background launch of the intent (the account settings live on the server and are not
/// loaded then). It holds no secret: an opaque epoch, a flag, an expiry and two display values.
public struct WalletAlertGate: Codable, Equatable, Sendable {
  /// `AccountSurfaceContext` value of the signed-in account. Sign-out rotates it.
  public let epoch: String
  /// The account's saved «notifications» opt-in.
  public let notificationsEnabled: Bool
  /// The session expiry: a notice is never shown for a session that has ended.
  public let expires: Date
  public let language: Language
  public let timeZone: String

  public init(
    epoch: String, notificationsEnabled: Bool, expires: Date, language: Language, timeZone: String
  ) {
    self.epoch = epoch
    self.notificationsEnabled = notificationsEnabled
    self.expires = expires
    self.language = language
    self.timeZone = timeZone
  }
}

public enum WalletShortcutPolicy {
  /// The purchase may enter the inbox only for the account that wrote the gate: after a sign-out
  /// (epoch rotated) or before the first launch of this build there is nobody to book it for.
  public static func mayRecord(gate: WalletAlertGate?, epoch: String) -> Bool {
    gate?.epoch == epoch
  }

  /// The immediate notice for a newly recorded purchase, or nil: no account, notifications not
  /// opted in, an ended session, or the labelled test purchase. OS permission is checked by the
  /// caller, which is the only one that can ask the system.
  public static func notice(
    for purchase: WalletPurchase, gate: WalletAlertGate?, epoch: String, now: Date
  ) -> LocalNotificationPlan? {
    guard let gate, gate.epoch == epoch, gate.notificationsEnabled, gate.expires > now else {
      return nil
    }
    return WalletNotificationPlanner.plan(
      purchase: purchase, language: gate.language, accountEpoch: epoch, until: gate.expires)
  }
}
