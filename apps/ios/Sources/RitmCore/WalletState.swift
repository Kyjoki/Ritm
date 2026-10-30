import Foundation

// Everything the Wallet inbox keeps on this iPhone: the pending purchases, what the owner chose
// per merchant, and the ids already confirmed or skipped (so a repeated Shortcuts run does not
// bring a purchase back). The app stores it as local JSON and never sends it anywhere.

public struct WalletState: Codable, Equatable, Sendable {
  public static let maxKnownIDs = 1000

  public private(set) var inbox: WalletInbox
  public private(set) var memory: MerchantMemory
  /// Confirmed or skipped purchase ids, oldest first, capped at `maxKnownIDs`.
  public private(set) var knownIDs: [String]

  public init() {
    inbox = WalletInbox()
    memory = MerchantMemory()
    knownIDs = []
  }

  public var pending: [WalletPurchase] { inbox.pending }

  /// True when every pending purchase already has a category (suggested or chosen).
  public var allHaveCategory: Bool {
    !pending.isEmpty && pending.allSatisfy { !($0.suggestedCategory ?? "").isEmpty }
  }

  public func receiving(_ purchase: WalletPurchase) -> (state: WalletState, added: Bool) {
    let result = inbox.adding(purchase, memory: memory, knownIDs: Set(knownIDs))
    var copy = self
    copy.inbox = result.inbox
    return (copy, result.added)
  }

  public func settingCategory(_ category: String, for id: String) -> WalletState {
    var copy = self
    copy.inbox = inbox.settingCategory(category, for: id)
    return copy
  }

  /// The purchase became an expense: remove it, remember its id and learn merchant → category.
  /// A test purchase teaches nothing.
  public func confirming(id: String, category: String, at: String) -> WalletState {
    var copy = self
    if let purchase = pending.first(where: { $0.id == id }), !purchase.isTest {
      copy.memory = memory.learning(merchant: purchase.merchant, category: category, at: at)
    }
    return copy.removing(id: id)
  }

  public func skipping(id: String) -> WalletState { removing(id: id) }

  /// Lets the same id arrive again (the «Проверить» button repeats one fixed test purchase).
  public func forgettingKnown(id: String) -> WalletState {
    var copy = self
    copy.knownIDs.removeAll { $0 == id }
    return copy
  }

  public func clearingMemory() -> WalletState {
    var copy = self
    copy.memory = MerchantMemory()
    return copy
  }

  private func removing(id: String) -> WalletState {
    var copy = self
    copy.inbox = inbox.removing(id: id)
    copy.knownIDs.removeAll { $0 == id }
    copy.knownIDs.append(id)
    if copy.knownIDs.count > WalletState.maxKnownIDs {
      copy.knownIDs.removeFirst(copy.knownIDs.count - WalletState.maxKnownIDs)
    }
    return copy
  }
}

extension WalletLink {
  public static let testMerchant = "Тестовая покупка"
  public static let testCard = "TEST"
  public static let testAmountMajor = 1000

  /// The link the «Проверить» button feeds through the same pipeline as a real automation.
  public static func testURL(date: String) -> URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = "add"
    components.queryItems = [
      URLQueryItem(name: "amount", value: String(testAmountMajor)),
      URLQueryItem(name: "merchant", value: testMerchant),
      URLQueryItem(name: "card", value: testCard),
      URLQueryItem(name: "date", value: date),
    ]
    return components.url
  }
}

extension WalletPurchase {
  /// The labelled test purchase. It is never written to the finance records.
  public var isTest: Bool { merchant == WalletLink.testMerchant && card == WalletLink.testCard }
}

public enum WalletBooking {
  /// A purchase is booked into the account of its currency; without one the owner must create it
  /// first (the finance wallet starts from the account's opening balance).
  public static func hasAccount(for purchase: WalletPurchase, in entries: [FinanceEntry]) -> Bool {
    entries.contains { $0.type == .account && $0.currency == purchase.currency }
  }
}
