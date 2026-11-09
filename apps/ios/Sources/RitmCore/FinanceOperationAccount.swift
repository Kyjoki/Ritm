import Foundation

/// One account the operation form can book into: the main account of a currency or a named
/// account (a `deposit` entry). Brokerage `stock` entries are never options.
public struct FinanceAccountOption: Identifiable, Equatable, Sendable {
  public let id: String
  /// nil for the main account.
  public let name: String?
  public let currency: FinanceCurrency

  public var isMain: Bool { name == nil }

  public init(id: String, name: String?, currency: FinanceCurrency) {
    self.id = id
    self.name = name
    self.currency = currency
  }
}

/// Which account an income or expense is booked into: the options of a currency, the account the
/// form starts on and the `accountId` the request carries. Pure, so it is tested without a UI.
public enum FinanceOperationAccount {
  /// The main account first, then the named accounts by `createdAt`.
  public static func options(_ entries: [FinanceEntry], currency: FinanceCurrency)
    -> [FinanceAccountOption]
  {
    let own = entries.filter { $0.currency == currency }
    let main = own.first { $0.type == .account }.map {
      FinanceAccountOption(id: $0.id, name: nil, currency: currency)
    }
    let named = own.filter { $0.type == .deposit }.stableSorted { $0.createdAt < $1.createdAt }
      .map { entry in
        let trimmed = (entry.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return FinanceAccountOption(
          id: entry.id, name: trimmed.isEmpty ? entry.id : trimmed, currency: currency)
      }
    return (main.map { [$0] } ?? []) + named
  }

  public static func mainID(_ entries: [FinanceEntry], currency: FinanceCurrency) -> String? {
    entries.first { $0.type == .account && $0.currency == currency }?.id
  }

  /// The account the form starts on: the card the owner is looking at, else the one used last,
  /// else the main account, else the first account. "" when the currency has no account.
  public static func preselected(
    _ entries: [FinanceEntry], currency: FinanceCurrency, card: String? = nil,
    lastUsed: String? = nil
  ) -> String {
    let options = options(entries, currency: currency)
    for candidate in [card, lastUsed] {
      if let candidate, options.contains(where: { $0.id == candidate }) { return candidate }
    }
    return options.first { $0.isMain }?.id ?? options.first?.id ?? ""
  }

  /// The `accountId` to send: nil for the main account, so an older server never sees the field.
  public static func requestAccountID(
    _ selected: String, entries: [FinanceEntry], currency: FinanceCurrency
  ) -> String? {
    guard !selected.isEmpty, selected != mainID(entries, currency: currency),
      options(entries, currency: currency).contains(where: { $0.id == selected })
    else { return nil }
    return selected
  }
}

/// Matches the card label of an Apple Wallet purchase to the name of an account.
public enum WalletAccountMatch {
  /// The account whose name matches the label, case-insensitively: an equal name first, then a
  /// label that contains the name (the longest name wins), then a name that contains the label.
  /// Masked labels («•••• 1234») and unnamed (main) accounts never match.
  public static func accountID(cardLabel: String?, options: [FinanceAccountOption]) -> String? {
    let label = (cardLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !label.isEmpty, !label.hasPrefix("•") else { return nil }
    let named = options.compactMap { option -> (id: String, name: String)? in
      guard let name = option.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        !name.isEmpty
      else { return nil }
      return (option.id, name)
    }
    if let exact = named.first(where: { $0.name == label }) { return exact.id }
    let inLabel = named.filter { label.contains($0.name) }
      .stableSorted { $0.name.count > $1.name.count }
    if let first = inLabel.first { return first.id }
    return named.first { $0.name.contains(label) }?.id
  }

  /// The account a pending purchase starts on: the match for its card label, else the main
  /// account (else the first account of its currency).
  public static func defaultAccountID(for purchase: WalletPurchase, entries: [FinanceEntry])
    -> String
  {
    let options = FinanceOperationAccount.options(entries, currency: purchase.currency)
    return accountID(cardLabel: purchase.card, options: options)
      ?? options.first { $0.isMain }?.id ?? options.first?.id ?? ""
  }
}
