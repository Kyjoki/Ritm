import Foundation

/// One calendar day of the operation history: the label parts for the date gutter and the
/// operations of that day in the order they were given.
public struct FinanceHistoryDay: Equatable, Identifiable, Sendable {
  /// `yyyy-MM-dd`; empty for operations that carry no valid date.
  public let dateKey: String
  /// «Сегодня», «Вчера», otherwise «30 окт, чт» (the year follows the month when not current).
  public let label: String
  /// «30»; empty without a date.
  public let dayNumber: String
  /// «окт», or «окт 2025» when the year is not the current one; empty without a date.
  public let month: String
  /// «чт»; empty without a date.
  public let weekday: String
  /// «Сегодня» or «Вчера» for those two days, else nil.
  public let relative: String?
  public let entries: [FinanceEntry]

  public var id: String { dateKey }
}

/// Which operations the full history shows.
public enum FinanceHistoryFilter: String, CaseIterable, Sendable {
  case all, expense, income, transfer

  public func apply(_ entries: [FinanceEntry]) -> [FinanceEntry] {
    switch self {
    case .all: entries
    case .expense: entries.filter { $0.type == .expense }
    case .income: entries.filter { $0.type == .income }
    case .transfer: entries.filter { $0.type == .transfer }
    }
  }
}

/// Groups operations by day for the dated history. Pure: the caller supplies today's key.
public enum FinanceHistoryGrouping {
  private static let russianMonths = [
    "янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек",
  ]
  private static let englishMonths = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]
  /// Sunday first, matching `HabitSchedule.weekday`.
  private static let russianWeekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
  private static let englishWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

  /// Days newest first; inside a day the operations keep the order of `entries`. Operations
  /// without a valid date (`date`, else `asOf`) form a last group.
  public static func group(_ entries: [FinanceEntry], today: String, language: Language)
    -> [FinanceHistoryDay]
  {
    var order: [String] = []
    var buckets: [String: [FinanceEntry]] = [:]
    for entry in entries {
      let raw = entry.date ?? entry.asOf ?? ""
      let key = HabitSchedule.isValidDate(raw) ? raw : ""
      if buckets[key] == nil { order.append(key) }
      buckets[key, default: []].append(entry)
    }
    let dated = order.filter { !$0.isEmpty }.sorted(by: >)
    let keys = order.contains("") ? dated + [""] : dated
    return keys.map { day(key: $0, entries: buckets[$0] ?? [], today: today, language: language) }
  }

  private static func day(key: String, entries: [FinanceEntry], today: String, language: Language)
    -> FinanceHistoryDay
  {
    let isRussian = language == .ru
    guard HabitSchedule.isValidDate(key) else {
      return FinanceHistoryDay(
        dateKey: "", label: isRussian ? "Без даты" : "No date", dayNumber: "", month: "",
        weekday: "", relative: nil, entries: entries)
    }
    let parts = key.split(separator: "-")
    let monthIndex = (Int(parts[1]) ?? 1) - 1
    let months = isRussian ? russianMonths : englishMonths
    let weekdays = isRussian ? russianWeekdays : englishWeekdays
    let number = String(Int(parts[2]) ?? 1)
    let showsYear = HabitSchedule.isValidDate(today) && key.prefix(4) != today.prefix(4)
    let month = months[monthIndex] + (showsYear ? " " + parts[0] : "")
    let weekday = weekdays[HabitSchedule.weekday(key) ?? 0]
    var relative: String?
    if key == today {
      relative = isRussian ? "Сегодня" : "Today"
    } else if HabitSchedule.isValidDate(today), key == HabitSchedule.addDays(to: today, days: -1) {
      relative = isRussian ? "Вчера" : "Yesterday"
    }
    return FinanceHistoryDay(
      dateKey: key, label: relative ?? "\(number) \(month), \(weekday)", dayNumber: number,
      month: month, weekday: weekday, relative: relative, entries: entries)
  }
}
