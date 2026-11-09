import Foundation
import Observation
import RitmCore

/// Purchases that arrived from the Shortcuts «Transaction» automation and wait for the owner,
/// plus what the owner chose per merchant. Kept on this iPhone only (UserDefaults JSON): it is
/// never sent to the server, to the assistant or to any AI request.
@MainActor @Observable
final class WalletInboxStore {
  private static let key = "ritm.wallet.state.v1"

  enum Receipt: Equatable {
    case added
    case duplicate
    case invalid
    /// Not a Ritm link at all; nothing to tell the owner.
    case ignored
  }

  private(set) var state: WalletState
  /// Counts the links that should bring Finance to the front; the root view watches it.
  private(set) var showRequest = 0
  /// Ids being written right now, so a double tap cannot book a purchase twice.
  private(set) var booking: Set<String> = []
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored var onAdded: (([WalletPurchase]) -> Void)?
  @ObservationIgnored var onRemoved: (([String]) -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    state =
      defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode(WalletState.self, from: $0) } ?? WalletState()
  }

  var pending: [WalletPurchase] { state.pending }
  var rememberedMerchants: Int { state.memory.merchantCount }

  /// Parses, dedupes and stores one link.
  func receive(_ url: URL, today: String, now: Date = Date()) -> Receipt {
    switch WalletLink.parse(url, today: today, receivedAt: Self.timestamp(now)) {
    case .failure(.wrongScheme): return .ignored
    case .failure: return .invalid
    case .success(let purchase): return add(purchase)
    }
  }

  /// The «Проверить» button: the fixed test purchase through the same path as a real link.
  func receiveTest(today: String, now: Date = Date()) -> Receipt {
    guard let url = WalletLink.testURL(date: today),
      case .success(let purchase) = WalletLink.parse(
        url, today: today, receivedAt: Self.timestamp(now))
    else { return .invalid }
    update(state.forgettingKnown(id: purchase.id))
    return add(purchase)
  }

  /// Puts the purchases read from `purchases.txt` into the inbox in one step. Anything already
  /// pending, confirmed or skipped is a duplicate; a full inbox leaves the rest in the file.
  func receive(file purchases: [WalletPurchase]) -> WalletState.FileReceipt {
    let result = state.receiving(file: purchases)
    update(result.state)
    return result.receipt
  }

  func requestShowingInbox() { showRequest += 1 }

  func setCategory(_ category: String, for id: String) {
    update(state.settingCategory(category, for: id))
  }

  func skip(id: String) { update(state.skipping(id: id)) }

  func confirmed(id: String, category: String, now: Date = Date()) {
    update(state.confirming(id: id, category: category, at: Self.timestamp(now)))
  }

  func clearMemory() { update(state.clearingMemory()) }

  /// Sign-out or a server switch: nothing about the previous account stays on the device.
  func reset() {
    booking = []
    state = WalletState()
    defaults.removeObject(forKey: Self.key)
  }

  func beginBooking(_ id: String) -> Bool { booking.insert(id).inserted }
  func endBooking(_ id: String) { booking.remove(id) }

  // MARK: - Private

  private func add(_ purchase: WalletPurchase) -> Receipt {
    let result = state.receiving(purchase)
    guard result.added else { return .duplicate }
    update(result.state)
    return .added
  }

  private func update(_ next: WalletState) {
    guard next != state else { return }
    let previous = Set(state.pending.map(\.id))
    let remaining = Set(next.pending.map(\.id))
    let added = next.pending.filter { !previous.contains($0.id) && !$0.isTest }
    let removed = Array(previous.subtracting(remaining))
    state = next
    if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.key) }
    if !removed.isEmpty { onRemoved?(removed) }
    if !added.isEmpty { onAdded?(added) }
  }

  private static func timestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}

// MARK: - Store wiring

extension RitmStore {
  /// `onOpenURL`: parse the link, add it to the inbox and bring Finance forward.
  func handleWalletLink(_ url: URL) {
    receiveWallet { $0.receive(url, today: HabitSchedule.dateKey(Date(), timeZone: timeZone)) }
  }

  /// The settings «Проверить» button.
  func receiveWalletTest() {
    receiveWallet { $0.receiveTest(today: HabitSchedule.dateKey(Date(), timeZone: timeZone)) }
  }

  private func receiveWallet(_ receive: (WalletInboxStore) -> WalletInboxStore.Receipt) {
    switch receive(wallet) {
    case .ignored: return
    case .invalid:
      toasts.show(text("Не удалось разобрать покупку", "Could not read the purchase"))
    case .duplicate:
      toasts.show(text("Эта покупка уже в списке", "This purchase is already in the list"))
    case .added:
      toasts.show(text("Покупка из Wallet · подтвердите", "Wallet purchase · confirm it"))
    }
    wallet.requestShowingInbox()
  }

  /// Books one pending purchase as an expense of its currency's account. Nothing is lost on a
  /// failure: the purchase stays pending. `accountID` is the named account to book into; nil is
  /// the main account of the currency. Returns whether it was booked.
  @discardableResult
  func confirmWalletPurchase(_ purchase: WalletPurchase, accountID: String? = nil) async -> Bool {
    guard let category = purchase.suggestedCategory, !category.isEmpty,
      wallet.beginBooking(purchase.id)
    else { return false }
    defer { wallet.endBooking(purchase.id) }
    if purchase.isTest {
      // The test purchase exercises the flow without touching the owner's finances.
      wallet.confirmed(id: purchase.id, category: category)
      toasts.show(text("Проверка пройдена · в расходы не записана", "Test passed · not recorded"))
      return true
    }
    guard financeLoaded, WalletBooking.hasAccount(for: purchase, in: financeEntries) else {
      toasts.show(
        text(
          "Нет счёта в \(purchase.currency.rawValue). Задайте стартовый остаток.",
          "No \(purchase.currency.rawValue) account. Set an opening balance first."))
      return false
    }
    let input = WalletEntryBuilder.expense(from: purchase, category: category, accountID: accountID)
    guard await write({ try await $0.createFinanceEntry(input) }) != nil else { return false }
    wallet.confirmed(id: purchase.id, category: category)
    // The new expense raises the banner and a bell notice (notices.update), so no toast.
    return true
  }

  /// Confirms every pending purchase that has a category, stopping at the first failure.
  /// `accountIDs` maps a purchase id to its named account; the others go to the main account.
  func confirmAllWalletPurchases(accountIDs: [String: String] = [:]) async {
    for purchase in wallet.pending {
      guard await confirmWalletPurchase(purchase, accountID: accountIDs[purchase.id]) else {
        return
      }
    }
  }
}
