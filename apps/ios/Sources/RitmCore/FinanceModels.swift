import Foundation

public enum FinanceCurrency: String, Codable, Sendable, CaseIterable { case KZT, USD, EUR, RUB }
public enum FinanceEntryKind: String, Codable, Sendable, CaseIterable {
  case transfer, account, income, expense, deposit, stock
}

/// Monetary amounts are integer hundredths; currencies are never silently combined or converted.
public struct FinanceEntryInput: Codable, Sendable, Equatable {
  public var type: FinanceEntryKind
  public var currency: FinanceCurrency
  public var note: String
  public var amountMinor: Int?
  public var valueMinor: Int?
  public var date: String?
  public var asOf: String?
  public var name: String?
  public var category: String?
  public var fromAccountId: String?
  public var toAccountId: String?
  public var exchange: String?
  public var ticker: String?
  public var quantity: Int?
  public var unitPriceMinor: Int?
  public var purchasePriceMinor: Int?
  public init(
    type: FinanceEntryKind, currency: FinanceCurrency = .KZT, note: String = "",
    amountMinor: Int? = nil,
    valueMinor: Int? = nil,
    date: String? = nil,
    asOf: String? = nil,
    name: String? = nil,
    category: String? = nil,
    fromAccountId: String? = nil,
    toAccountId: String? = nil,
    exchange: String? = nil,
    ticker: String? = nil,
    quantity: Int? = nil,
    unitPriceMinor: Int? = nil,
    purchasePriceMinor: Int? = nil
  ) {
    self.type = type
    self.currency = currency
    self.note = note
    self.amountMinor = amountMinor
    self.valueMinor = valueMinor
    self.date = date
    self.asOf = asOf
    self.name = name
    self.category = category
    self.fromAccountId = fromAccountId
    self.toAccountId = toAccountId
    self.exchange = exchange
    self.ticker = ticker
    self.quantity = quantity
    self.unitPriceMinor = unitPriceMinor
    self.purchasePriceMinor = purchasePriceMinor
  }

  private enum CodingKeys: String, CodingKey {
    case type, currency, note, amountMinor, valueMinor, date, asOf, name, category
    case fromAccountId, toAccountId, exchange, ticker, quantity, unitPriceMinor, purchasePriceMinor
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(type, forKey: .type)
    try values.encode(currency, forKey: .currency)
    try values.encode(note, forKey: .note)
    func required<T>(_ value: T?, _ key: CodingKeys) throws -> T {
      guard let value else {
        throw EncodingError.invalidValue(
          type.rawValue,
          .init(
            codingPath: encoder.codingPath + [key],
            debugDescription: "Required finance field is missing."))
      }
      return value
    }
    // The server's discriminated union is strict. Do not send fields from another form tab.
    switch type {
    case .transfer:
      try values.encode(required(amountMinor, .amountMinor), forKey: .amountMinor)
      try values.encode(required(date, .date), forKey: .date)
      try values.encode(required(fromAccountId, .fromAccountId), forKey: .fromAccountId)
      try values.encode(required(toAccountId, .toAccountId), forKey: .toAccountId)
    case .income, .expense:
      try values.encode(required(amountMinor, .amountMinor), forKey: .amountMinor)
      try values.encode(required(date, .date), forKey: .date)
      try values.encode(required(category, .category), forKey: .category)
    case .account:
      try values.encode(required(valueMinor, .valueMinor), forKey: .valueMinor)
      try values.encode(required(asOf, .asOf), forKey: .asOf)
    case .deposit, .stock:
      try values.encode(required(name, .name), forKey: .name)
      try values.encode(required(valueMinor, .valueMinor), forKey: .valueMinor)
      try values.encode(required(asOf, .asOf), forKey: .asOf)
      if type == .stock {
        try values.encodeIfPresent(exchange, forKey: .exchange)
        try values.encodeIfPresent(ticker, forKey: .ticker)
        try values.encodeIfPresent(quantity, forKey: .quantity)
        try values.encodeIfPresent(unitPriceMinor, forKey: .unitPriceMinor)
        try values.encodeIfPresent(purchasePriceMinor, forKey: .purchasePriceMinor)
      }
    }
  }
}

public struct FinanceEntry: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var input: FinanceEntryInput
  public var createdAt: String
  public var updatedAt: String
  public var type: FinanceEntryKind {
    get { input.type }
    set { input.type = newValue }
  }
  public var currency: FinanceCurrency {
    get { input.currency }
    set { input.currency = newValue }
  }
  public var note: String {
    get { input.note }
    set { input.note = newValue }
  }
  public var amountMinor: Int? {
    get { input.amountMinor }
    set { input.amountMinor = newValue }
  }
  public var valueMinor: Int? {
    get { input.valueMinor }
    set { input.valueMinor = newValue }
  }
  public var date: String? {
    get { input.date }
    set { input.date = newValue }
  }
  public var asOf: String? {
    get { input.asOf }
    set { input.asOf = newValue }
  }
  public var name: String? {
    get { input.name }
    set { input.name = newValue }
  }
  public var category: String? {
    get { input.category }
    set { input.category = newValue }
  }
  public var fromAccountId: String? {
    get { input.fromAccountId }
    set { input.fromAccountId = newValue }
  }
  public var toAccountId: String? {
    get { input.toAccountId }
    set { input.toAccountId = newValue }
  }
  public var exchange: String? {
    get { input.exchange }
    set { input.exchange = newValue }
  }
  public var ticker: String? {
    get { input.ticker }
    set { input.ticker = newValue }
  }
  public var quantity: Int? {
    get { input.quantity }
    set { input.quantity = newValue }
  }
  public var unitPriceMinor: Int? {
    get { input.unitPriceMinor }
    set { input.unitPriceMinor = newValue }
  }
  public var purchasePriceMinor: Int? {
    get { input.purchasePriceMinor }
    set { input.purchasePriceMinor = newValue }
  }

  public init(id: String, input: FinanceEntryInput, createdAt: String = "", updatedAt: String = "")
  {
    self.id = id
    self.input = input
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey { case id, createdAt, updatedAt }
  public init(from decoder: any Decoder) throws {
    input = try FinanceEntryInput(from: decoder)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    createdAt = try values.decode(String.self, forKey: .createdAt)
    updatedAt = try values.decode(String.self, forKey: .updatedAt)
  }
  public func encode(to encoder: any Encoder) throws {
    try input.encode(to: encoder)
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(createdAt, forKey: .createdAt)
    try values.encode(updatedAt, forKey: .updatedAt)
  }
}

/// Faithful port of shared/finance.ts: an opening snapshot includes transactions on its asOf date.
public enum FinanceLedger {
  private static func delta(_ entry: FinanceEntry, accountID: String) -> Int {
    guard entry.type == .transfer else { return 0 }
    return (entry.toAccountId == accountID ? entry.amountMinor ?? 0 : 0)
      - (entry.fromAccountId == accountID ? entry.amountMinor ?? 0 : 0)
  }

  public static func accountBalance(
    entries: [FinanceEntry], currency: FinanceCurrency, today: String
  ) -> Int? {
    guard let account = entries.first(where: { $0.type == .account && $0.currency == currency }),
      let asOf = account.asOf, asOf <= today, var balance = account.valueMinor
    else { return nil }
    for entry in entries {
      guard entry.currency == currency, let date = entry.date, date >= asOf, date <= today else {
        continue
      }
      switch entry.type {
      case .transfer: balance += delta(entry, accountID: account.id)
      case .income: balance += entry.amountMinor ?? 0
      case .expense: balance -= entry.amountMinor ?? 0
      default: break
      }
    }
    return balance
  }

  public static func depositBalance(entries: [FinanceEntry], depositId: String, today: String)
    -> Int?
  {
    guard let deposit = entries.first(where: { $0.type == .deposit && $0.id == depositId }),
      let asOf = deposit.asOf, asOf <= today, var balance = deposit.valueMinor
    else { return nil }
    for entry in entries {
      guard entry.type == .transfer, entry.currency == deposit.currency,
        let date = entry.date, date >= asOf, date <= today
      else { continue }
      balance += delta(entry, accountID: deposit.id)
    }
    return balance
  }
}
