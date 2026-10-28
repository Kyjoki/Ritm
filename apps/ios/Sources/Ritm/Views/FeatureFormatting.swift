import Foundation
import RitmCore
import SwiftUI

/// Date-only fields are interpreted in the account's calendar, not the phone's zone.
enum FeatureDate {
  static func calendar(_ zone: String) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
    value.firstWeekday = 1
    return value
  }
  static func date(_ key: String, zone: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar(zone)
    formatter.timeZone = formatter.calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: key + " 12:00") ?? Date()
  }
  static func label(
    _ key: String, zone: String, language: Language, template: String = "d MMMM yyyy"
  ) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar(zone)
    formatter.timeZone = formatter.calendar.timeZone
    formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date(key, zone: zone))
  }
  static func instant(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
  static func time(_ date: Date, zone: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: zone)
    formatter.dateFormat = "HH:mm"
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
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: language == .ru ? "ru_KZ" : "en_US")
    formatter.numberStyle = .currency
    formatter.currencyCode = currency.rawValue
    formatter.minimumFractionDigits = value % 100 == 0 ? 0 : 2
    formatter.maximumFractionDigits = 2
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
