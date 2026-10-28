import Foundation

public struct HabitDaySummary: Sendable, Equatable {
  public let planned: Int
  public let completed: Int
  /// No scheduled opportunities means no percentage, not a failed day.
  public let progress: Int?
  public var scheduled: Int { planned }
  public var percent: Int? { progress }

  public init(planned: Int, completed: Int) {
    self.planned = planned
    self.completed = completed
    self.progress = planned > 0 ? Int((Double(completed) / Double(planned) * 100).rounded()) : nil
  }
}

/// Port of shared/habit-schedule.ts and src/features/habit-utils.ts.
/// Calendar-day arithmetic uses UTC after the owner's time zone has produced a date key.
/// This prevents device-zone and daylight-saving shifts from changing a habit's day.
public enum HabitSchedule {
  public static let milestones = [3, 7, 14, 30]
  public static let allWeekdays = Array(0...6)

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  public static func dateKey(_ date: Date = Date(), timeZone: String) -> String {
    var ownerCalendar = calendar
    // A corrupt or no-longer-supported zone must not silently use the device's zone.
    ownerCalendar.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!
    let parts = ownerCalendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }

  public static func isValidDate(_ key: String) -> Bool { parsedDate(key) != nil }

  private static func parsedDate(_ key: String) -> Date? {
    guard key.utf8.count == 10 else { return nil }
    let parts = key.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
      let year = Int(parts[0]), year >= 1, let month = Int(parts[1]), let day = Int(parts[2]),
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    else { return nil }
    let roundtrip = calendar.dateComponents([.year, .month, .day], from: date)
    guard roundtrip.year == year, roundtrip.month == month, roundtrip.day == day else { return nil }
    return date
  }

  public static func addDays(to key: String, days: Int) -> String? {
    guard let date = parsedDate(key),
      let shifted = calendar.date(byAdding: .day, value: days, to: date)
    else { return nil }
    return dateKey(shifted, timeZone: "UTC")
  }

  /// Sunday = 0, matching the persisted web schedule.
  public static func weekday(_ key: String) -> Int? {
    guard let date = parsedDate(key) else { return nil }
    return calendar.component(.weekday, from: date) - 1
  }

  public static func week(containing key: String) -> [String] {
    guard let day = weekday(key), let sunday = addDays(to: key, days: -day) else { return [] }
    return (0..<7).compactMap { addDays(to: sunday, days: $0) }
  }

  public static func period(_ habit: Habit, on date: String) -> HabitPeriod? {
    guard let periods = habit.periods, !periods.isEmpty else {
      return HabitPeriod(
        from: habit.startDate, weekdays: habit.weekdays ?? allWeekdays,
        archived: habit.archived ?? false)
    }
    return periods.reversed().first { $0.from <= date }
  }

  public static func isScheduled(_ habit: Habit, on date: String) -> Bool {
    guard date >= habit.startDate, let weekday = weekday(date), let period = period(habit, on: date)
    else { return false }
    return !period.archived && period.weekdays.contains(weekday)
  }

  public static func canMark(_ habit: Habit, on date: String, today: String) -> Bool {
    guard habit.archived != true, date <= today, let weekday = weekday(date) else { return false }
    if date >= habit.startDate { return isScheduled(habit, on: date) }
    let firstPeriod = habit.periods?.first
    return !(firstPeriod?.archived ?? false)
      && (firstPeriod?.weekdays ?? habit.weekdays ?? allWeekdays).contains(weekday)
  }

  public static func target(_ habit: Habit) -> Int { habit.target ?? 1 }

  public static func progress(_ habit: Habit, on date: String) -> Int {
    habit.progressByDate?[date] ?? (habit.completedDates.contains(date) ? target(habit) : 0)
  }

  public static func isComplete(_ habit: Habit, on date: String) -> Bool {
    // Completion is authoritative history. A later target change must not rewrite that history.
    isScheduled(habit, on: date) && habit.completedDates.contains(date)
  }

  public static func daySummary(_ habits: [Habit], on date: String, today: String? = nil)
    -> HabitDaySummary
  {
    if let today, date > today { return HabitDaySummary(planned: 0, completed: 0) }
    let scheduled = habits.filter { isScheduled($0, on: date) }
    return HabitDaySummary(
      planned: scheduled.count,
      completed: scheduled.filter { isComplete($0, on: date) }.count)
  }

  public static func periodSummary(_ habits: [Habit], dates: [String], today: String? = nil)
    -> HabitDaySummary
  {
    let summaries = dates.map { daySummary(habits, on: $0, today: today) }
    return HabitDaySummary(
      planned: summaries.reduce(0) { $0 + $1.planned },
      completed: summaries.reduce(0) { $0 + $1.completed })
  }

  public static func streak(_ habit: Habit, today: String) -> Int {
    guard isValidDate(today), isValidDate(habit.startDate) else { return 0 }
    var day = today
    while day >= habit.startDate && !isScheduled(habit, on: day) {
      if period(habit, on: day)?.archived ?? true { return 0 }
      guard let previous = addDays(to: day, days: -1) else { return 0 }
      day = previous
    }
    if day == today && !isComplete(habit, on: day) {
      guard let previous = addDays(to: day, days: -1) else { return 0 }
      day = previous
    }
    while day >= habit.startDate && !isScheduled(habit, on: day) {
      if period(habit, on: day)?.archived ?? true { return 0 }
      guard let previous = addDays(to: day, days: -1) else { return 0 }
      day = previous
    }
    var count = 0
    while day >= habit.startDate {
      if period(habit, on: day)?.archived ?? true { break }
      if isScheduled(habit, on: day) {
        if !isComplete(habit, on: day) { break }
        count += 1
      }
      guard let previous = addDays(to: day, days: -1) else { break }
      day = previous
    }
    return count
  }

  public static func bestStreak(_ habit: Habit, today: String) -> Int {
    guard isValidDate(today), isValidDate(habit.startDate) else { return 0 }
    var best = 0
    var current = 0
    var day = habit.startDate
    while day <= today {
      if period(habit, on: day)?.archived ?? true {
        current = 0
      } else if isScheduled(habit, on: day) {
        current = isComplete(habit, on: day) ? current + 1 : 0
        best = max(best, current)
      }
      guard let next = addDays(to: day, days: 1), next > day else { break }
      day = next
    }
    return best
  }
}
