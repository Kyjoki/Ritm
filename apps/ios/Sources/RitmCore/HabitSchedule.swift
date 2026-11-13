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

  public static func isValidDate(_ key: String) -> Bool { civilDays(key) != nil }

  /// `yyyy-MM-dd` as a day number (days since 1970-01-01), nil for anything that is not a real
  /// calendar day. Plain integer arithmetic: habit streaks and heatmaps ask for thousands of
  /// these, so there is no `Calendar` and no formatting per call.
  private static func civilDays(_ key: String) -> Int? {
    guard key.utf8.count == 10 else { return nil }
    var digits = [Int](repeating: 0, count: 8)
    var position = 0
    var filled = 0
    for byte in key.utf8 {
      defer { position += 1 }
      if position == 4 || position == 7 {
        guard byte == 45 else { return nil }
        continue
      }
      guard (48...57).contains(byte) else { return nil }
      digits[filled] = Int(byte) - 48
      filled += 1
    }
    let year = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3]
    let month = digits[4] * 10 + digits[5]
    let day = digits[6] * 10 + digits[7]
    guard year >= 1, (1...12).contains(month), day >= 1, day <= daysInMonth(year, month) else {
      return nil
    }
    return daysFromCivil(year, month, day)
  }

  static func daysInMonth(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  /// Howard Hinnant's `days_from_civil` for the proleptic Gregorian calendar.
  static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  /// The inverse of `daysFromCivil` (`civil_from_days`).
  static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shifted = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shifted + 2) / 5 + 1
    let month = shifted < 10 ? shifted + 3 : shifted - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year, month, day)
  }

  static func key(forDays days: Int) -> String? {
    let parts = civilFromDays(days)
    guard (1...9999).contains(parts.year) else { return nil }
    let year = String(parts.year)
    return String(repeating: "0", count: 4 - year.count) + year + "-" + twoDigits(parts.month)
      + "-" + twoDigits(parts.day)
  }

  private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

  public static func addDays(to key: String, days: Int) -> String? {
    guard let day = civilDays(key) else { return nil }
    return Self.key(forDays: day + days)
  }

  /// Sunday = 0, matching the persisted web schedule.
  public static func weekday(_ key: String) -> Int? {
    guard let day = civilDays(key) else { return nil }
    // 1970-01-01 was a Thursday.
    return ((day % 7) + 7 + 4) % 7
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
