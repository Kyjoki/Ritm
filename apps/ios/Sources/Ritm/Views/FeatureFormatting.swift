import Foundation
import RitmCore
import SwiftUI

/// Formatters are expensive to build and rows format on every render, so each distinct
/// configuration is built once and reused. They are never mutated after creation.
final class FormatterCache: @unchecked Sendable {
  static let shared = FormatterCache()
  private let lock = NSLock()
  private var dates: [String: DateFormatter] = [:]
  private var numbers: [String: NumberFormatter] = [:]
  private var calendars: [String: Calendar] = [:]

  func date(_ key: String, make: () -> DateFormatter) -> DateFormatter {
    cached(key, in: \.dates, make: make)
  }
  func number(_ key: String, make: () -> NumberFormatter) -> NumberFormatter {
    cached(key, in: \.numbers, make: make)
  }
  func calendar(_ zone: String, make: () -> Calendar) -> Calendar {
    cached(zone, in: \.calendars, make: make)
  }

  /// `make` runs outside the lock: a formatter is often built from another cached value (a date
  /// formatter asks for the cached calendar), and NSLock is not re-entrant.
  private func cached<Value>(
    _ key: String, in table: ReferenceWritableKeyPath<FormatterCache, [String: Value]>,
    make: () -> Value
  ) -> Value {
    lock.lock()
    let found = self[keyPath: table][key]
    lock.unlock()
    if let found { return found }
    let made = make()
    lock.lock()
    defer { lock.unlock() }
    if let raced = self[keyPath: table][key] { return raced }
    self[keyPath: table][key] = made
    return made
  }

  /// «h:mm a» in the account zone (times use AM/PM in both languages).
  func clock(_ date: Date, zone: String) -> String {
    self.date("clock|\(zone)") {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: zone)
      formatter.dateFormat = "h:mm a"
      return formatter
    }.string(from: date)
  }
  /// A localized template such as «EEEE d MMMM» in the account zone.
  func template(_ template: String, date: Date, zone: String, language: Language) -> String {
    self.date("tpl|\(template)|\(zone)|\(language.rawValue)") {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
      formatter.timeZone = TimeZone(identifier: zone)
      formatter.setLocalizedDateFormatFromTemplate(template)
      return formatter
    }.string(from: date)
  }
}

/// Date-only fields are interpreted in the account's calendar, not the phone's zone.
enum FeatureDate {
  static func calendar(_ zone: String) -> Calendar {
    FormatterCache.shared.calendar(zone) {
      var value = Calendar(identifier: .gregorian)
      value.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
      value.firstWeekday = 1
      return value
    }
  }
  static func date(_ key: String, zone: String) -> Date {
    let formatter = FormatterCache.shared.date("key|\(zone)") {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = calendar(zone)
      formatter.timeZone = formatter.calendar.timeZone
      formatter.dateFormat = "yyyy-MM-dd HH:mm"
      return formatter
    }
    return formatter.date(from: key + " 12:00") ?? Date()
  }
  static func label(
    _ key: String, zone: String, language: Language, template: String = "d MMMM yyyy"
  ) -> String {
    let formatter = FormatterCache.shared.date("label|\(template)|\(zone)|\(language.rawValue)") {
      let formatter = DateFormatter()
      formatter.calendar = calendar(zone)
      formatter.timeZone = formatter.calendar.timeZone
      formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
      formatter.setLocalizedDateFormatFromTemplate(template)
      return formatter
    }
    return formatter.string(from: date(key, zone: zone))
  }
  nonisolated(unsafe) private static let fractionalISO: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  nonisolated(unsafe) private static let plainISO = ISO8601DateFormatter()
  static func instant(_ value: String?) -> Date? {
    guard let value else { return nil }
    return fractionalISO.date(from: value) ?? plainISO.date(from: value)
  }
  static func time(_ date: Date, zone: String) -> String {
    let formatter = FormatterCache.shared.date("time|\(zone)") {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: zone)
      formatter.dateFormat = "HH:mm"
      return formatter
    }
    return formatter.string(from: date)
  }
  static func clock(_ value: String?) -> String {
    guard let value, let minutes = TaskSchedule.timeMinutes(value) else { return "—" }
    let hours = minutes / 60
    return
      "\(hours % 12 == 0 ? 12 : hours % 12):\(String(format: "%02d", minutes % 60)) \(hours < 12 ? "AM" : "PM")"
  }
}

struct DateKeyPicker: View {
  let title: String
  @Binding var value: String
  let zone: String
  var body: some View {
    DatePicker(
      title,
      selection: Binding(
        get: { FeatureDate.date(value, zone: zone) },
        set: { value = HabitSchedule.dateKey($0, timeZone: zone) }
      ), displayedComponents: .date
    )
    .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
    .environment(\.calendar, FeatureDate.calendar(zone))
  }
}

enum FinanceDisplay {
  static func money(_ value: Int, currency: FinanceCurrency, language: Language) -> String {
    let fraction = value % 100 == 0 ? 0 : 2
    let formatter = FormatterCache.shared.number(
      "\(language.rawValue)|\(currency.rawValue)|\(fraction)"
    ) {
      let formatter = NumberFormatter()
      formatter.locale = Locale(identifier: language == .ru ? "ru_KZ" : "en_US")
      formatter.numberStyle = .currency
      formatter.currencyCode = currency.rawValue
      formatter.minimumFractionDigits = fraction
      formatter.maximumFractionDigits = 2
      return formatter
    }
    return formatter.string(from: NSNumber(value: Double(value) / 100))
      ?? "\(value / 100) \(currency.rawValue)"
  }
  static func decimal(_ minor: Int?) -> String {
    guard let minor else { return "" }
    return "\(minor / 100).\(String(format: "%02d", minor % 100))"
  }
  static func minor(_ input: String) -> Int? {
    let normalized = input.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
    guard normalized.range(of: #"^\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil else {
      return nil
    }
    let parts = normalized.split(separator: ".")
    guard let units = Int(parts[0]), units <= 10_000_000_000 else { return nil }
    let cents =
      parts.count == 2 ? Int(parts[1].padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0 : 0
    let result = units * 100 + cents
    return result <= 1_000_000_000_000 ? result : nil
  }
  static func title(_ kind: FinanceEntryKind, language: Language) -> String {
    let ru = language == .ru
    switch kind {
    case .account: return ru ? "Основной счёт" : "Main account"
    case .income: return ru ? "Доход" : "Income"
    case .expense: return ru ? "Расход" : "Expense"
    case .deposit: return ru ? "Депозит" : "Deposit"
    case .stock: return ru ? "Акции" : "Stocks"
    case .transfer: return ru ? "Перевод" : "Transfer"
    }
  }
  static func symbol(_ kind: FinanceEntryKind) -> String {
    switch kind {
    case .account: "wallet.pass"
    case .income: "arrow.down.left"
    case .expense: "arrow.up.right"
    case .deposit: "building.columns"
    case .stock: "chart.line.uptrend.xyaxis"
    case .transfer: "arrow.left.arrow.right"
    }
  }
}
