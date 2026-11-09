import Foundation

public enum FinancePeriod: String, CaseIterable, Sendable { case week, month, year }

public struct FinanceCard: Identifiable, Equatable, Sendable {
  public enum Kind: String, Sendable { case account, deposit, stocks }
  /// Account and deposit: the entry id. Stocks: `stocks-<CUR>`.
  public let id: String
  public let kind: Kind
  public let currency: FinanceCurrency
  public let name: String?
  /// nil when the card has not started yet (asOf after today) or has no snapshot.
  public let balanceMinor: Int?
  public let asOf: String?

  public init(
    id: String, kind: Kind, currency: FinanceCurrency, name: String? = nil,
    balanceMinor: Int? = nil, asOf: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.currency = currency
    self.name = name
    self.balanceMinor = balanceMinor
    self.asOf = asOf
  }
}

public struct FinanceTotal: Equatable, Sendable {
  public let currency: FinanceCurrency
  public let amountMinor: Int
  public init(currency: FinanceCurrency, amountMinor: Int) {
    self.currency = currency
    self.amountMinor = amountMinor
  }
}

public struct FinancePeriodStats: Equatable, Sendable {
  public static let zero = FinancePeriodStats()
  public let incomeMinor: Int
  public let expenseMinor: Int
  public let transfersInMinor: Int
  public let transfersOutMinor: Int
  public var netMinor: Int { incomeMinor - expenseMinor + transfersInMinor - transfersOutMinor }

  public init(
    incomeMinor: Int = 0, expenseMinor: Int = 0, transfersInMinor: Int = 0,
    transfersOutMinor: Int = 0
  ) {
    self.incomeMinor = incomeMinor
    self.expenseMinor = expenseMinor
    self.transfersInMinor = transfersInMinor
    self.transfersOutMinor = transfersOutMinor
  }
}

public struct FinancePoint: Equatable, Sendable {
  public let date: String
  public let valueMinor: Int
  public init(date: String, valueMinor: Int) {
    self.date = date
    self.valueMinor = valueMinor
  }
}

public struct FinanceCategoryShare: Equatable, Sendable {
  /// nil is the «Другое» bucket.
  public let name: String?
  public let amountMinor: Int
  public let share: Double
  public init(name: String?, amountMinor: Int, share: Double) {
    self.name = name
    self.amountMinor = amountMinor
    self.share = share
  }
}

public struct FinanceShare: Equatable, Sendable {
  public let cardID: String
  public let amountMinor: Int
  public let share: Double
  public init(cardID: String, amountMinor: Int, share: Double) {
    self.cardID = cardID
    self.amountMinor = amountMinor
    self.share = share
  }
}

public struct FinancePosition: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let ticker: String?
  public let exchange: String?
  public let quantity: Int?
  public let valueMinor: Int
  /// quantity × (unit price − purchase price) when all three are known.
  public let gainMinor: Int?

  public init(
    id: String, name: String, ticker: String? = nil, exchange: String? = nil,
    quantity: Int? = nil, valueMinor: Int, gainMinor: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.ticker = ticker
    self.exchange = exchange
    self.quantity = quantity
    self.valueMinor = valueMinor
    self.gainMinor = gainMinor
  }
}

/// Wallet-style read model over the raw finance entries. Every amount stays in its own currency;
/// transfers move money between cards and are never income or expense.
public enum FinanceWallet {
  /// Per currency in `FinanceCurrency.allCases` order: the main account, its deposits by
  /// `createdAt`, then the stocks card when the currency has a stock entry.
  public static func cards(_ entries: [FinanceEntry], today: String) -> [FinanceCard] {
    FinanceCurrency.allCases.flatMap { cards(of: $0, in: entries, today: today) }
  }

  /// Per currency, the sum of the known card balances; only currencies that have cards.
  public static func totals(_ cards: [FinanceCard]) -> [FinanceTotal] {
    FinanceCurrency.allCases.compactMap { currency in
      let own = cards.filter { $0.currency == currency }
      guard !own.isEmpty else { return nil }
      return FinanceTotal(
        currency: currency, amountMinor: own.reduce(0) { $0 + ($1.balanceMinor ?? 0) })
    }
  }

  /// Calendar period to date: Monday…today, the 1st…today or January 1…today.
  public static func interval(_ period: FinancePeriod, today: String) -> (
    start: String, end: String
  ) {
    guard HabitSchedule.isValidDate(today) else { return (today, today) }
    let start: String?
    switch period {
    case .week:
      let sinceMonday = ((HabitSchedule.weekday(today) ?? 1) + 6) % 7
      start = HabitSchedule.addDays(to: today, days: -sinceMonday)
    case .month: start = TaskSchedule.startOfMonth(today)
    case .year: start = String(today.prefix(4)) + "-01-01"
    }
    return (start ?? today, today)
  }

  /// Account and deposit: the income and expense of the card (see `operation(_:belongsTo:)`) from
  /// its snapshot date on, plus its transfers. Stocks: zero.
  public static func stats(
    _ entries: [FinanceEntry], card: FinanceCard, period: FinancePeriod, today: String
  ) -> FinancePeriodStats {
    guard card.kind != .stocks, let asOf = card.asOf else { return .zero }
    let range = interval(period, today: today)
    let start = max(range.start, asOf)
    var income = 0
    var expense = 0
    var transfersIn = 0
    var transfersOut = 0
    for entry in entries where entry.currency == card.currency {
      guard isDated(entry, from: start, to: range.end) else { continue }
      let amount = entry.amountMinor ?? 0
      switch entry.type {
      case .income where operation(entry, belongsTo: card): income += amount
      case .expense where operation(entry, belongsTo: card): expense += amount
      case .transfer:
        if entry.toAccountId == card.id { transfersIn += amount }
        if entry.fromAccountId == card.id { transfersOut += amount }
      default: break
      }
    }
    return FinancePeriodStats(
      incomeMinor: income, expenseMinor: expense, transfersInMinor: transfersIn,
      transfersOutMinor: transfersOut)
  }

  /// Income and expense of one currency in the interval, from the main account's snapshot date
  /// on; transfers are left out. Without a started account the stats are zero.
  public static func overviewStats(
    _ entries: [FinanceEntry], currency: FinanceCurrency, period: FinancePeriod, today: String
  ) -> FinancePeriodStats {
    guard let asOf = entries.first(where: { $0.type == .account && $0.currency == currency })?.asOf,
      asOf <= today
    else { return .zero }
    let range = interval(period, today: today)
    var income = 0
    var expense = 0
    for entry in entries where entry.currency == currency {
      guard isDated(entry, from: max(range.start, asOf), to: range.end) else { continue }
      switch entry.type {
      case .income: income += entry.amountMinor ?? 0
      case .expense: expense += entry.amountMinor ?? 0
      default: break
      }
    }
    return FinancePeriodStats(incomeMinor: income, expenseMinor: expense)
  }

  /// End-of-day balances starting with the day before the interval and ending today; the year
  /// has month ends, then today. Nothing is drawn before the card's snapshot date, where the
  /// series starts instead. A card that has not started has no series.
  public static func balanceSeries(
    _ entries: [FinanceEntry], card: FinanceCard, period: FinancePeriod, today: String
  ) -> [FinancePoint] {
    guard card.balanceMinor != nil, let asOf = card.asOf, asOf <= today else { return [] }
    return seriesDates(period, today: today, from: asOf).map {
      FinancePoint(date: $0, valueMinor: balance(of: card, in: entries, on: $0))
    }
  }

  /// The same series summed over every started card of one currency.
  public static func overviewSeries(
    _ entries: [FinanceEntry], currency: FinanceCurrency, period: FinancePeriod, today: String
  ) -> [FinancePoint] {
    let own = cards(entries, today: today).filter {
      $0.currency == currency && $0.balanceMinor != nil
    }
    guard let asOf = own.compactMap(\.asOf).min() else { return [] }
    return seriesDates(period, today: today, from: asOf).map { day in
      FinancePoint(
        date: day, valueMinor: own.reduce(0) { $0 + balance(of: $1, in: entries, on: day) })
    }
  }

  /// Expenses of an account or deposit card by trimmed category, largest first. Past `limit` rows the
  /// smallest ones fold into one «Другое» row (name nil), which is always last.
  public static func categories(
    _ entries: [FinanceEntry], card: FinanceCard, period: FinancePeriod, today: String,
    limit: Int = 5
  ) -> [FinanceCategoryShare] {
    guard card.kind != .stocks, let asOf = card.asOf else { return [] }
    let range = interval(period, today: today)
    var totals: [String: Int] = [:]
    var uncategorized = 0
    for entry in entries where entry.type == .expense && operation(entry, belongsTo: card) {
      guard isDated(entry, from: max(range.start, asOf), to: range.end),
        let amount = entry.amountMinor, amount > 0
      else { continue }
      let name = (entry.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if name.isEmpty { uncategorized += amount } else { totals[name, default: 0] += amount }
    }
    let named = totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    let sum = named.reduce(uncategorized) { $0 + $1.value }
    guard sum > 0 else { return [] }
    func row(_ name: String?, _ amount: Int) -> FinanceCategoryShare {
      FinanceCategoryShare(name: name, amountMinor: amount, share: Double(amount) / Double(sum))
    }
    let keep = max(limit, 1)
    let folds = named.count + (uncategorized > 0 ? 1 : 0) > keep
    let shown = folds ? named.prefix(keep - 1) : named[...]
    let rest = (folds ? named.dropFirst(keep - 1).reduce(0) { $0 + $1.value } : 0) + uncategorized
    return shown.map { row($0.key, $0.value) } + (rest > 0 ? [row(nil, rest)] : [])
  }

  /// Cards of one currency with a positive balance and their share of those balances.
  public static func distribution(_ cards: [FinanceCard], currency: FinanceCurrency)
    -> [FinanceShare]
  {
    let positive = cards.filter { $0.currency == currency && ($0.balanceMinor ?? 0) > 0 }
    let total = positive.reduce(0) { $0 + ($1.balanceMinor ?? 0) }
    guard total > 0 else { return [] }
    return positive.map {
      let amount = $0.balanceMinor ?? 0
      return FinanceShare(cardID: $0.id, amountMinor: amount, share: Double(amount) / Double(total))
    }
  }

  /// Every operation that touches the card, whatever its date; newest date first, then newest
  /// `createdAt`.
  public static func history(_ entries: [FinanceEntry], card: FinanceCard) -> [FinanceEntry] {
    newestFirst(entries.filter { touches($0, card: card) })
  }

  public static func recent(_ entries: [FinanceEntry], limit: Int) -> [FinanceEntry] {
    guard limit > 0 else { return [] }
    return Array(newestFirst(entries.filter(isOperation)).prefix(limit))
  }

  /// Stock entries of one currency, largest value first.
  public static func positions(_ entries: [FinanceEntry], currency: FinanceCurrency)
    -> [FinancePosition]
  {
    entries.filter { $0.type == .stock && $0.currency == currency }
      .stableSorted { ($0.valueMinor ?? 0) > ($1.valueMinor ?? 0) }
      .map { entry in
        var gain: Int?
        if let quantity = entry.quantity, let unit = entry.unitPriceMinor,
          let purchase = entry.purchasePriceMinor
        {
          gain = quantity * (unit - purchase)
        }
        return FinancePosition(
          id: entry.id, name: entry.name ?? "", ticker: entry.ticker, exchange: entry.exchange,
          quantity: entry.quantity, valueMinor: entry.valueMinor ?? 0, gainMinor: gain)
      }
  }

  public static func cardID(for entry: FinanceEntry, cards: [FinanceCard]) -> String? {
    func card(_ kind: FinanceCard.Kind) -> String? {
      cards.first { $0.kind == kind && $0.currency == entry.currency }?.id
    }
    switch entry.type {
    case .income, .expense:
      if let id = entry.accountId, cards.contains(where: { $0.id == id }) { return id }
      return card(.account)
    case .stock: return card(.stocks)
    case .transfer:
      return [entry.toAccountId, entry.fromAccountId].compactMap { $0 }
        .first { id in cards.contains { $0.id == id } }
    case .account, .deposit: return cards.contains { $0.id == entry.id } ? entry.id : nil
    }
  }
}

extension FinanceWallet {
  private static func cards(of currency: FinanceCurrency, in entries: [FinanceEntry], today: String)
    -> [FinanceCard]
  {
    let own = entries.filter { $0.currency == currency }
    var result: [FinanceCard] = []
    if let account = own.first(where: { $0.type == .account }) {
      result.append(
        FinanceCard(
          id: account.id, kind: .account, currency: currency,
          balanceMinor: FinanceLedger.accountBalance(
            entries: own, currency: currency, today: today),
          asOf: account.asOf))
    }
    for deposit in own.filter({ $0.type == .deposit }).stableSorted(by: { $0.createdAt < $1.createdAt }) {
      result.append(
        FinanceCard(
          id: deposit.id, kind: .deposit, currency: currency, name: deposit.name,
          balanceMinor: FinanceLedger.depositBalance(
            entries: own, depositId: deposit.id, today: today),
          asOf: deposit.asOf))
    }
    let stocks = own.filter { $0.type == .stock }
    if !stocks.isEmpty {
      result.append(
        FinanceCard(
          id: "stocks-\(currency.rawValue)", kind: .stocks, currency: currency,
          balanceMinor: stocksValue(stocks, on: today), asOf: stocks.compactMap(\.asOf).min()))
    }
    return result
  }

  /// Stocks count from their own asOf date; no started stock means no balance.
  private static func stocksValue(_ stocks: [FinanceEntry], on day: String) -> Int? {
    let values = stocks.compactMap { entry -> Int? in
      guard let asOf = entry.asOf, asOf <= day else { return nil }
      return entry.valueMinor
    }
    return values.isEmpty ? nil : values.reduce(0, +)
  }

  private static func balance(of card: FinanceCard, in entries: [FinanceEntry], on day: String)
    -> Int
  {
    switch card.kind {
    case .account:
      return FinanceLedger.accountBalance(entries: entries, currency: card.currency, today: day)
        ?? 0
    case .deposit:
      return FinanceLedger.depositBalance(entries: entries, depositId: card.id, today: day) ?? 0
    case .stocks:
      let stocks = entries.filter { $0.type == .stock && $0.currency == card.currency }
      return stocksValue(stocks, on: day) ?? 0
    }
  }

  private static func isDated(_ entry: FinanceEntry, from start: String, to end: String) -> Bool {
    guard let date = entry.date else { return false }
    return date >= start && date <= end
  }

  /// An income or expense counts on the main account when it names no account or the main's own
  /// id, and on a named account (deposit) only when it names that account.
  public static func operation(_ entry: FinanceEntry, belongsTo card: FinanceCard) -> Bool {
    guard entry.type == .income || entry.type == .expense, entry.currency == card.currency
    else { return false }
    switch card.kind {
    case .account: return entry.accountId == nil || entry.accountId == card.id
    case .deposit: return entry.accountId == card.id
    case .stocks: return false
    }
  }

  private static func touches(_ entry: FinanceEntry, card: FinanceCard) -> Bool {
    guard entry.currency == card.currency else { return false }
    switch (card.kind, entry.type) {
    case (.account, .income), (.account, .expense), (.deposit, .income), (.deposit, .expense):
      return operation(entry, belongsTo: card)
    case (.stocks, .stock): return true
    case (.account, .transfer), (.deposit, .transfer):
      return entry.fromAccountId == card.id || entry.toAccountId == card.id
    default: return false
    }
  }

  /// Stock entries have no `date`; their snapshot date takes its place.
  private static func newestFirst(_ entries: [FinanceEntry]) -> [FinanceEntry] {
    entries.stableSorted { lhs, rhs in
      let left = lhs.date ?? lhs.asOf ?? ""
      let right = rhs.date ?? rhs.asOf ?? ""
      return left != right ? left > right : lhs.createdAt > rhs.createdAt
    }
  }

  /// The day before the interval, then the points of the period, without anything before
  /// `asOf`; when the snapshot falls inside the interval the series starts on that day.
  private static func seriesDates(_ period: FinancePeriod, today: String, from asOf: String)
    -> [String]
  {
    guard HabitSchedule.isValidDate(today) else { return [] }
    let start = interval(period, today: today).start
    guard let before = HabitSchedule.addDays(to: start, days: -1) else { return [] }
    let points = period == .year ? monthEnds(from: start, today: today) : days(from: start, to: today)
    let kept = ([before] + points).filter { $0 >= asOf }
    return asOf > before && kept.first != asOf ? [asOf] + kept : kept
  }

  private static func days(from start: String, to end: String) -> [String] {
    var result: [String] = []
    var cursor: String? = start
    while let day = cursor, day <= end {
      result.append(day)
      cursor = HabitSchedule.addDays(to: day, days: 1)
    }
    return result
  }

  /// The last day of each month from `start` (a 1st), the current month ending today.
  private static func monthEnds(from start: String, today: String) -> [String] {
    var result: [String] = []
    var first: String? = start
    while let monthStart = first, monthStart <= today {
      let next = TaskSchedule.addMonths(to: monthStart, months: 1)
      let end = next.flatMap { HabitSchedule.addDays(to: $0, days: -1) } ?? today
      result.append(min(end, today))
      first = next
    }
    return result
  }
}

public struct FinanceNotice: Identifiable, Equatable, Sendable {
  public let id: String
  public let kind: FinanceEntryKind
  public let amountMinor: Int
  public let currency: FinanceCurrency
  /// The trimmed category, else the trimmed note, else "".
  public let title: String
  public let date: String
  public let createdAt: String
  public let cardID: String?

  public init(
    id: String, kind: FinanceEntryKind, amountMinor: Int, currency: FinanceCurrency, title: String,
    date: String, createdAt: String, cardID: String?
  ) {
    self.id = id
    self.kind = kind
    self.amountMinor = amountMinor
    self.currency = currency
    self.title = title
    self.date = date
    self.createdAt = createdAt
    self.cardID = cardID
  }
}

public enum FinanceNotices {
  /// The newest `createdAt` of any entry, "" when there are none. Stored once per device so
  /// old history never floods the bell.
  public static func baseline(_ entries: [FinanceEntry]) -> String {
    entries.map(\.createdAt).max() ?? ""
  }

  /// Income, expense and transfer entries created after the baseline, newest first.
  public static func notices(
    _ entries: [FinanceEntry], since baseline: String, cards: [FinanceCard], limit: Int = 30
  ) -> [FinanceNotice] {
    guard limit > 0 else { return [] }
    return entries.filter { isOperation($0) && $0.createdAt > baseline }
      .stableSorted { $0.createdAt > $1.createdAt }
      .prefix(limit)
      .map { entry in
        FinanceNotice(
          id: entry.id, kind: entry.type, amountMinor: entry.amountMinor ?? 0,
          currency: entry.currency, title: title(entry), date: entry.date ?? "",
          createdAt: entry.createdAt, cardID: FinanceWallet.cardID(for: entry, cards: cards))
      }
  }

  private static func title(_ entry: FinanceEntry) -> String {
    for text in [entry.category, entry.note] {
      let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return ""
  }
}

private func isOperation(_ entry: FinanceEntry) -> Bool {
  entry.type == .income || entry.type == .expense || entry.type == .transfer
}
