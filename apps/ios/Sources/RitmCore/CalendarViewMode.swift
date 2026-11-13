import Foundation

/// The title of the calendar page: the month name and, outside the current year, the year.
public struct CalendarTitle: Sendable, Equatable {
  public let month: String
  public let year: Int?
  public var text: String { year.map { "\(month) \($0)" } ?? month }
}

/// The five looks of the calendar page, switched from the side menu. The week starts on Sunday.
public enum CalendarViewMode: String, CaseIterable, Sendable, Equatable {
  case schedule, day, threeDays, week, month

  /// Every app launch opens on the week. The view used last is deliberately not remembered.
  public static let launch: CalendarViewMode = .week

  /// How many days the agenda reads at first, and how many a «Ещё» tap adds.
  public static let scheduleInitialDays = 42
  public static let scheduleStepDays = 28

  /// Columns of the hour grid; nil for the agenda and the month.
  public var dayCount: Int? {
    switch self {
    case .day: 1
    case .threeDays: 3
    case .week: 7
    case .schedule, .month: nil
    }
  }

  public var isTimeGrid: Bool { dayCount != nil }

  /// The columns of the hour grid for `anchor`: the Sunday-first week containing it, or the
  /// anchor day with the days that follow it. Empty for the agenda and the month.
  public func visibleDays(anchor: String) -> [String] {
    guard let count = dayCount else { return [] }
    if self == .week {
      let week = HabitSchedule.week(containing: anchor)
      return week.isEmpty ? [anchor] : week
    }
    return (0..<count).compactMap { HabitSchedule.addDays(to: anchor, days: $0) }
  }

  /// The anchor one period further (`amount` > 0) or earlier: a day, three days, a week or a month.
  public func stepped(anchor: String, by amount: Int) -> String {
    switch self {
    case .month:
      return TaskSchedule.addMonths(to: anchor, months: amount) ?? anchor
    case .schedule:
      return HabitSchedule.addDays(to: anchor, days: amount * 7) ?? anchor
    case .day, .threeDays, .week:
      return HabitSchedule.addDays(to: anchor, days: amount * (dayCount ?? 1)) ?? anchor
    }
  }

  /// The least the page needs, `from` included and `to` excluded: the hour grid also covers the
  /// neighbouring periods, so a swipe lands on events that are already loaded; the month needs its
  /// own days.
  public func fetchRange(anchor: String, scheduleDays: Int = CalendarViewMode.scheduleInitialDays)
    -> (from: String, to: String)
  {
    switch self {
    case .schedule:
      return (anchor, HabitSchedule.addDays(to: anchor, days: scheduleDays) ?? anchor)
    case .month:
      // The days of the month itself. The grid around it (6 weeks) is read by `loadRange`, which
      // stays within the 93 days the server accepts per read, so three whole grids do not fit.
      let dates = TaskSchedule.monthDates(containing: anchor)
      let first = dates.first ?? anchor
      let last = dates.last ?? anchor
      return (first, HabitSchedule.addDays(to: last, days: 1) ?? last)
    case .day, .threeDays, .week:
      let days = visibleDays(anchor: anchor)
      let first = days.first ?? anchor
      let count = days.count
      let pad = max(count, 3)
      return (
        HabitSchedule.addDays(to: first, days: -pad) ?? first,
        HabitSchedule.addDays(to: first, days: count + pad) ?? first
      )
    }
  }

  /// The day a new entry starts on: today when it is on screen, otherwise the chosen day.
  public func focusDay(anchor: String, today: String) -> String {
    let days = visibleDays(anchor: anchor)
    return days.contains(today) ? today : anchor
  }

  /// True when what was already read (`from` included, `to` excluded) holds everything `needed`
  /// asks for, so changing the view does not need another Google read.
  public static func covers(
    _ read: (from: String, to: String)?, _ needed: (from: String, to: String)
  ) -> Bool {
    guard let read else { return false }
    return read.from <= needed.from && read.to >= needed.to
  }

  /// The day whose month names the page: the middle of the visible days.
  public func titleDay(anchor: String) -> String {
    let days = visibleDays(anchor: anchor)
    return days.isEmpty ? anchor : days[days.count / 2]
  }

  /// «Ноябрь», or «Ноябрь 2027» when the period is not in the current year.
  public func title(anchor: String, today: String, language: Language) -> CalendarTitle {
    let day = titleDay(anchor: anchor)
    let parts = day.split(separator: "-").compactMap { Int($0) }
    let todayYear = today.split(separator: "-").first.flatMap { Int($0) }
    guard parts.count >= 2, (1...12).contains(parts[1]) else {
      return CalendarTitle(month: "", year: nil)
    }
    let names = language == .ru ? Self.monthsRu : Self.monthsEn
    return CalendarTitle(
      month: names[parts[1] - 1], year: parts[0] == todayYear ? nil : parts[0])
  }

  private static let monthsRu = [
    "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
    "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь",
  ]
  private static let monthsEn = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ]
}

/// The hour labels and times of the grid: 24-hour by default, 12-hour on request.
public enum CalendarHourFormat: String, CaseIterable, Sendable, Equatable {
  case h24, h12

  public static let `default`: CalendarHourFormat = .h24

  /// The label of a whole hour in the grid's time column: «09:00» or «9AM».
  public func hourLabel(_ hour: Int) -> String {
    switch self {
    case .h24: String(format: "%02d:00", ((hour % 24) + 24) % 24)
    case .h12: CalendarPlan.hourLabel(hour)
    }
  }

  /// A time of day in minutes: «09:30» or «9:30 AM».
  public func clock(_ minutes: Int) -> String {
    switch self {
    case .h24:
      let value = ((minutes % 1440) + 1440) % 1440
      return String(format: "%02d:%02d", value / 60, value % 60)
    case .h12:
      return DayPlan.clock(minutes)
    }
  }

  /// The start or the end of an entry, from the exact minutes in 24-hour mode (an entry that
  /// crosses a clock change keeps the label the server gave it in 12-hour mode).
  public func entryTime(_ entry: DayOccurrence, start: Bool) -> String {
    let minutes = start ? entry.start : entry.end
    switch self {
    case .h24:
      guard let minutes else { return "" }
      return clock(minutes)
    case .h12:
      return CalendarPlan.entryTime(entry, start: start)
    }
  }

  /// «09:30–10:30» or «9:30–10:30 AM».
  public func entryRange(_ entry: DayOccurrence) -> String {
    entryTime(entry, start: true) + "–" + entryTime(entry, start: false)
  }
}
