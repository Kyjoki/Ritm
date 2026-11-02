import Foundation

// «Обязательные платежи»: recurring payments kept on this iPhone only. The server has no such
// model. Everything here is pure: dates are plain YYYY-MM-DD strings handled with civil-date
// arithmetic (no Calendar, no TimeZone), so DST and the device zone can never shift a date.
// A due date alone never creates an expense; only a confirmed «Оплачено» does, and each
// occurrence (payment id + planned date) can be booked once.

// MARK: - Dates

public enum PaymentDates {
  public struct Day: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
  }

  public static func isLeap(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  public static func daysInMonth(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: return isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  /// Strict `YYYY-MM-DD` for years 2000...2100; nil for anything else.
  public static func parse(_ key: String) -> Day? {
    let parts = key.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      (2000...2100).contains(year), (1...12).contains(month),
      (1...daysInMonth(year, month)).contains(day)
    else { return nil }
    return Day(year: year, month: month, day: day)
  }

  public static func isValid(_ key: String) -> Bool { parse(key) != nil }

  public static func key(_ year: Int, _ month: Int, _ day: Int) -> String {
    let pad = { (value: Int, width: Int) in
      String(repeating: "0", count: max(0, width - String(value).count)) + String(value)
    }
    return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
  }

  /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
  private static func serial(_ date: Day) -> Int {
    let y = date.month <= 2 ? date.year - 1 : date.year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let shifted = date.month > 2 ? date.month - 3 : date.month + 9
    let doy = (153 * shifted + 2) / 5 + date.day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
  }

  private static func day(fromSerial value: Int) -> Day {
    let z = value + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    return Day(year: yoe + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
  }

  public static func adding(days: Int, to key: String) -> String? {
    guard let date = parse(key) else { return nil }
    let result = day(fromSerial: serial(date) + days)
    return Self.key(result.year, result.month, result.day)
  }

  /// `to` minus `from` in whole days.
  public static func daysBetween(_ from: String, _ to: String) -> Int? {
    guard let a = parse(from), let b = parse(to) else { return nil }
    return serial(b) - serial(a)
  }

  /// The planned date after `planned`. The anchor is the day (and, yearly, the month) the owner
  /// chose, so 31 Jan -> 28/29 Feb -> 31 Mar and 29 Feb -> 28 Feb -> 29 Feb.
  public static func next(
    after planned: String, period: PaymentPeriod, anchorDay: Int, anchorMonth: Int
  ) -> String? {
    guard let date = parse(planned) else { return nil }
    switch period {
    case .week:
      return adding(days: 7, to: planned)
    case .month:
      let year = date.month == 12 ? date.year + 1 : date.year
      let month = date.month == 12 ? 1 : date.month + 1
      return key(year, month, min(anchorDay, daysInMonth(year, month)))
    case .year:
      let year = date.year + 1
      return key(year, anchorMonth, min(anchorDay, daysInMonth(year, anchorMonth)))
    }
  }
}

// MARK: - Model

public enum PaymentPeriod: String, Codable, CaseIterable, Sendable { case week, month, year }
public enum PaymentStatus: String, Sendable { case planned, today, overdue, paused }

public enum PaymentError: Error, Equatable, Sendable {
  case notFound
  case invalid
  case paused
  /// The stated planned date is no longer the payment's next date.
  case staleOccurrence
  /// This occurrence is already paid, skipped or being written.
  case occurrenceRecorded
}

public struct RecurringPayment: Codable, Equatable, Identifiable, Sendable {
  public static let nameLimit = 40
  public static let amountLimitMinor = 100_000_000_000
  public static let reminderChoices = [0, 1, 3, 7]
  public static let soonDays = 7

  public var id: String
  public var name: String
  public var amountMinor: Int
  /// The debit account (a finance entry id); it decides the currency.
  public var accountID: String
  public var currency: FinanceCurrency
  public var category: String
  public var nextDate: String
  public var period: PaymentPeriod
  public var anchorDay: Int
  public var anchorMonth: Int
  /// Stored as a setting only; nothing is scheduled from it in this version.
  public var reminderDays: Int
  public var paused: Bool

  public init(
    id: String = UUID().uuidString, name: String, amountMinor: Int, accountID: String,
    currency: FinanceCurrency, category: String, nextDate: String, period: PaymentPeriod,
    reminderDays: Int = 1, paused: Bool = false
  ) {
    let date = PaymentDates.parse(nextDate)
    self.id = id
    self.name = name
    self.amountMinor = amountMinor
    self.accountID = accountID
    self.currency = currency
    self.category = category
    self.nextDate = nextDate
    self.period = period
    self.anchorDay = date?.day ?? 1
    self.anchorMonth = date?.month ?? 1
    self.reminderDays = reminderDays
    self.paused = paused
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, amountMinor, accountID, currency, category, nextDate, period
    case anchorDay, anchorMonth, reminderDays, paused
  }

  /// Tolerant: unknown keys are ignored and optional ones fall back to defaults.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    amountMinor = try values.decode(Int.self, forKey: .amountMinor)
    accountID = try values.decode(String.self, forKey: .accountID)
    currency = try values.decode(FinanceCurrency.self, forKey: .currency)
    category =
      try values.decodeIfPresent(String.self, forKey: .category) ?? FinanceCategories.otherLabel
    nextDate = try values.decode(String.self, forKey: .nextDate)
    period = try values.decodeIfPresent(PaymentPeriod.self, forKey: .period) ?? .month
    let date = PaymentDates.parse(nextDate)
    anchorDay = try values.decodeIfPresent(Int.self, forKey: .anchorDay) ?? date?.day ?? 1
    anchorMonth = try values.decodeIfPresent(Int.self, forKey: .anchorMonth) ?? date?.month ?? 1
    reminderDays = try values.decodeIfPresent(Int.self, forKey: .reminderDays) ?? 1
    paused = try values.decodeIfPresent(Bool.self, forKey: .paused) ?? false
  }

  /// A record that can be used: a real date, a positive bounded amount, a name.
  public var isUsable: Bool {
    PaymentDates.isValid(nextDate) && amountMinor > 0 && amountMinor <= Self.amountLimitMinor
      && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (1...31).contains(anchorDay) && (1...12).contains(anchorMonth)
  }

  public func status(today: String) -> PaymentStatus {
    if paused { return .paused }
    if nextDate < today { return .overdue }
    return nextDate == today ? .today : .planned
  }

  /// Active and due within the next 7 days, overdue ones included.
  public func isUpcoming(today: String) -> Bool {
    guard !paused, let limit = PaymentDates.adding(days: Self.soonDays, to: today) else {
      return false
    }
    return nextDate <= limit
  }

  /// The date after the current planned one.
  public var followingDate: String? {
    PaymentDates.next(
      after: nextDate, period: period, anchorDay: anchorDay, anchorMonth: anchorMonth)
  }

  /// The reminder day, a setting only: `nextDate` minus `reminderDays`.
  public var reminderDate: String? { PaymentDates.adding(days: -reminderDays, to: nextDate) }
}

// MARK: - Validation of the form

public enum PaymentValidation {
  /// Positive, at most 2 decimals, comma or dot, bounded; nil otherwise.
  public static func amountMinor(_ text: String) -> Int? {
    let cleaned = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
    let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), !parts[0].isEmpty,
      parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      parts.count == 1 || (1...2).contains(parts[1].count),
      parts[0].count <= 12, let units = Int(parts[0])
    else { return nil }
    let cents =
      parts.count == 2 ? (Int(parts[1].padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0) : 0
    let total = units * 100 + cents
    return total > 0 && total <= RecurringPayment.amountLimitMinor ? total : nil
  }

  public static func cleanName(_ text: String) -> String? {
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty || name.count > RecurringPayment.nameLimit ? nil : name
  }
}

// MARK: - Ledger

/// One planned occurrence of one payment. `attempted` is written BEFORE the expense request, so
/// a lost response leaves a record that blocks a second expense until it is reconciled.
public struct PaymentOccurrence: Codable, Equatable, Sendable {
  public enum State: String, Codable, Sendable { case attempted, paid, skipped }
  public var paymentID: String
  public var planned: String
  public var state: State
  /// The stable note of the expense, used to recognise it in the history.
  public var note: String
  public var amountMinor: Int
  public var bookedOn: String
  public var entryID: String?

  public init(
    paymentID: String, planned: String, state: State, note: String = "", amountMinor: Int = 0,
    bookedOn: String = "", entryID: String? = nil
  ) {
    self.paymentID = paymentID
    self.planned = planned
    self.state = state
    self.note = note
    self.amountMinor = amountMinor
    self.bookedOn = bookedOn
    self.entryID = entryID
  }
}

/// What to write once the owner confirms: exactly one expense.
public struct PaymentCharge: Equatable, Sendable {
  public let paymentID: String
  public let planned: String
  public let note: String
  public let input: FinanceEntryInput
}

public struct UpcomingPayments: Equatable, Sendable {
  public let count: Int
  /// One total per currency, never converted or summed across currencies.
  public let totals: [FinanceTotal]
  public let hasOverdue: Bool
}

// MARK: - Book

public struct PaymentBook: Codable, Equatable, Sendable {
  public static let notePrefix = "Регулярный платёж"

  public private(set) var payments: [RecurringPayment]
  public private(set) var occurrences: [PaymentOccurrence]

  public init(payments: [RecurringPayment] = [], occurrences: [PaymentOccurrence] = []) {
    self.payments = payments
    self.occurrences = occurrences
  }

  private enum CodingKeys: String, CodingKey { case payments, occurrences }

  /// Tolerant: a broken record is dropped, the rest survive.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    payments = (try? values.decode(Lossy<RecurringPayment>.self, forKey: .payments))?.items
      .filter(\.isUsable) ?? []
    occurrences =
      (try? values.decode(Lossy<PaymentOccurrence>.self, forKey: .occurrences))?.items ?? []
  }

  private struct Lossy<Item: Decodable>: Decodable {
    let items: [Item]
    private struct Slot: Decodable {
      let item: Item?
      init(from decoder: any Decoder) throws { item = try? Item(from: decoder) }
    }
    init(from decoder: any Decoder) throws {
      var container = try decoder.unkeyedContainer()
      var result: [Item] = []
      while !container.isAtEnd {
        if let item = try container.decode(Slot.self).item { result.append(item) }
      }
      items = result
    }
  }

  public func payment(_ id: String) -> RecurringPayment? { payments.first { $0.id == id } }

  public func occurrence(_ id: String, planned: String) -> PaymentOccurrence? {
    occurrences.first { $0.paymentID == id && $0.planned == planned }
  }

  /// A write for the payment's current date started and has no confirmed result.
  public func hasUnresolvedAttempt(_ id: String) -> Bool {
    guard let payment = payment(id) else { return false }
    return occurrence(id, planned: payment.nextDate)?.state == .attempted
  }

  /// Overdue first, then today, planned, paused; by date inside a group.
  public func sorted(today: String) -> [RecurringPayment] {
    func rank(_ status: PaymentStatus) -> Int {
      switch status {
      case .overdue: 0
      case .today: 1
      case .planned: 2
      case .paused: 3
      }
    }
    return payments.sorted {
      let a = rank($0.status(today: today))
      let b = rank($1.status(today: today))
      return a != b ? a < b : $0.nextDate < $1.nextDate
    }
  }

  public func upcoming(today: String) -> UpcomingPayments {
    let soon = payments.filter { $0.isUpcoming(today: today) }
    let totals = FinanceCurrency.allCases.compactMap { currency -> FinanceTotal? in
      let sum = soon.filter { $0.currency == currency }.reduce(0) { $0 + $1.amountMinor }
      return soon.contains { $0.currency == currency }
        ? FinanceTotal(currency: currency, amountMinor: sum) : nil
    }
    return UpcomingPayments(
      count: soon.count, totals: totals, hasOverdue: soon.contains { $0.nextDate < today })
  }

  // MARK: Edits (each returns a new value)

  public func adding(_ payment: RecurringPayment) -> PaymentBook {
    guard payment.isUsable, self.payment(payment.id) == nil else { return self }
    return PaymentBook(payments: payments + [payment], occurrences: occurrences)
  }

  /// Replaces a payment. The anchor day stays when the date is unchanged and is re-taken from
  /// the new date otherwise. A date whose occurrence is already recorded is refused.
  public func updating(_ edited: RecurringPayment) -> Result<PaymentBook, PaymentError> {
    guard let old = payment(edited.id) else { return .failure(.notFound) }
    guard edited.isUsable else { return .failure(.invalid) }
    if edited.nextDate != old.nextDate, occurrence(old.id, planned: edited.nextDate) != nil {
      return .failure(.occurrenceRecorded)
    }
    var next = edited
    if edited.nextDate == old.nextDate {
      next.anchorDay = old.anchorDay
      next.anchorMonth = old.anchorMonth
    } else if let date = PaymentDates.parse(edited.nextDate) {
      next.anchorDay = date.day
      next.anchorMonth = date.month
    }
    return .success(replacing(next))
  }

  /// Removes the schedule and its ledger. Expenses already recorded are not touched.
  public func deleting(_ id: String) -> PaymentBook {
    PaymentBook(
      payments: payments.filter { $0.id != id }, occurrences: occurrences.filter { $0.paymentID != id }
    )
  }

  public func togglingPause(_ id: String) -> PaymentBook {
    guard var found = payment(id) else { return self }
    found.paused.toggle()
    return replacing(found)
  }

  /// Moves the date forward without an expense. Tied to the stated planned date.
  public func skipping(_ id: String, planned: String) -> Result<PaymentBook, PaymentError> {
    switch check(id, planned: planned) {
    case .failure(let error): return .failure(error)
    case .success(var found):
      guard let following = found.followingDate else { return .failure(.invalid) }
      found.nextDate = following
      let record = PaymentOccurrence(paymentID: id, planned: planned, state: .skipped)
      return .success(replacing(found, adding: record))
    }
  }

  /// Step 1 of paying: records the attempt and returns the one expense to write. Calling it
  /// again for the same occurrence fails, which is the double-confirmation guard. `planned` is
  /// the date the owner saw; an early payment is booked today but counted for that date.
  public func beginningPayment(_ id: String, planned: String, today: String)
    -> Result<(book: PaymentBook, charge: PaymentCharge), PaymentError>
  {
    switch check(id, planned: planned) {
    case .failure(let error): return .failure(error)
    case .success(let found):
      guard PaymentDates.isValid(today) else { return .failure(.invalid) }
      let note = "\(Self.notePrefix) · \(found.name) · \(planned)"
      let input = FinanceEntryInput(
        type: .expense, currency: found.currency, note: note, amountMinor: found.amountMinor,
        date: today, category: found.category)
      let record = PaymentOccurrence(
        paymentID: id, planned: planned, state: .attempted, note: note,
        amountMinor: found.amountMinor, bookedOn: today)
      let charge = PaymentCharge(paymentID: id, planned: planned, note: note, input: input)
      return .success((replacing(found, adding: record), charge))
    }
  }

  /// Step 2: the expense is confirmed. Marks the occurrence paid and moves the date on.
  public func confirmingPayment(_ id: String, planned: String, entryID: String?) -> PaymentBook {
    guard let index = occurrences.firstIndex(where: { $0.paymentID == id && $0.planned == planned }),
      occurrences[index].state == .attempted
    else { return self }
    var records = occurrences
    records[index].state = .paid
    records[index].entryID = entryID
    var list = payments
    if let at = list.firstIndex(where: { $0.id == id }), list[at].nextDate == planned,
      let following = list[at].followingDate
    {
      list[at].nextDate = following
    }
    return PaymentBook(payments: list, occurrences: records)
  }

  /// The write definitely did not happen: the occurrence can be paid again.
  public func releasingPayment(_ id: String, planned: String) -> PaymentBook {
    PaymentBook(
      payments: payments,
      occurrences: occurrences.filter {
        !($0.paymentID == id && $0.planned == planned && $0.state == .attempted)
      })
  }

  /// Recognises expenses whose answer was lost: an attempted occurrence whose stable note,
  /// amount and date are in the history is confirmed with that entry. No new expense is made.
  public func reconciling(with entries: [FinanceEntry]) -> PaymentBook {
    var book = self
    for record in occurrences where record.state == .attempted {
      let taken = Set(book.occurrences.compactMap(\.entryID))
      let match = entries.first {
        $0.type == .expense && $0.note == record.note && $0.amountMinor == record.amountMinor
          && $0.date == record.bookedOn && !taken.contains($0.id)
      }
      if let match {
        book = book.confirmingPayment(record.paymentID, planned: record.planned, entryID: match.id)
      }
    }
    return book
  }

  // MARK: Private

  private func check(_ id: String, planned: String) -> Result<RecurringPayment, PaymentError> {
    guard let found = payment(id) else { return .failure(.notFound) }
    if found.paused { return .failure(.paused) }
    if found.nextDate != planned { return .failure(.staleOccurrence) }
    if occurrence(id, planned: planned) != nil { return .failure(.occurrenceRecorded) }
    return .success(found)
  }

  private func replacing(_ payment: RecurringPayment, adding record: PaymentOccurrence? = nil)
    -> PaymentBook
  {
    PaymentBook(
      payments: payments.map { $0.id == payment.id ? payment : $0 },
      occurrences: record.map { occurrences + [$0] } ?? occurrences)
  }
}

// MARK: - File

/// The versioned JSON on disk. An unreadable file gives an empty book rather than a crash.
public enum PaymentBookFile {
  public static let version = 1

  private struct Envelope: Codable {
    var version: Int
    var book: PaymentBook
  }

  public static func encode(_ book: PaymentBook) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(Envelope(version: version, book: book))
  }

  public static func decode(_ data: Data) -> PaymentBook {
    (try? JSONDecoder().decode(Envelope.self, from: data))?.book ?? PaymentBook()
  }
}
