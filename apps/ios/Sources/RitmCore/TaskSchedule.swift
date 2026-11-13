import Foundation

public struct TaskOccurrence: Sendable, Equatable, Identifiable {
  public var task: RitmTask
  /// The original occurrence date, including a continued segment after midnight.
  public var date: String
  public var start: Int?
  public var end: Int?
  public var key: String
  public var completed: Bool
  public var id: String { key }
  public init(task: RitmTask, date: String, start: Int?, end: Int?, key: String, completed: Bool) {
    self.task = task
    self.date = date
    self.start = start
    self.end = end
    self.key = key
    self.completed = completed
  }
}

/// Domain rules from src/features/calendar-utils.ts; caller decides whether to include quick tasks.
public enum TaskSchedule {
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }

  private static func date(_ key: String) -> Date? {
    guard HabitSchedule.isValidDate(key) else { return nil }
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(
      from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
  }

  public static func timeMinutes(_ time: String) -> Int? {
    let parts = time.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      parts.allSatisfy({ $0.count == 2 && $0.utf8.allSatisfy { (48...57).contains($0) } }),
      let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour),
      (0...59).contains(minute)
    else { return nil }
    return hour * 60 + minute
  }

  public static func minuteTime(_ minute: Int) -> String {
    let normalized = ((minute % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", normalized / 60, normalized % 60)
  }

  /// Plain day arithmetic (no `Calendar` per call): a week of a busy planner asks this for every
  /// task on every day it draws.
  public static func occursOn(_ task: RitmTask, date target: String) -> Bool {
    guard let originKey = task.date, originKey <= target, HabitSchedule.isValidDate(originKey),
      HabitSchedule.isValidDate(target)
    else { return false }
    switch task.repeat {
    case .none: return originKey == target
    case .daily: return true
    case .weekly: return HabitSchedule.weekday(originKey) == HabitSchedule.weekday(target)
    case .monthly: return originKey.suffix(2) == target.suffix(2)
    }
  }

  public static func dayOccurrences(_ tasks: [RitmTask], date: String, language: Language = .ru)
    -> [TaskOccurrence]
  {
    guard HabitSchedule.isValidDate(date) else { return [] }
    var result: [TaskOccurrence] = []
    for task in tasks {
      if occursOn(task, date: date) {
        let start = task.time.flatMap(timeMinutes)
        result.append(
          TaskOccurrence(
            task: task, date: date, start: start,
            end: start.map { min(1440, $0 + task.duration) }, key: "\(task.id):\(date)",
            completed: task.isComplete(on: date)))
      }
      if let time = task.time, let start = timeMinutes(time),
        let previous = HabitSchedule.addDays(to: date, days: -1)
      {
        let overflow = start + task.duration - 1440
        if overflow > 0 && occursOn(task, date: previous) {
          result.append(
            TaskOccurrence(
              task: task, date: previous, start: 0, end: min(1440, overflow),
              key: "\(task.id):\(previous):continued", completed: task.isComplete(on: previous)))
        }
      }
    }
    return result.sorted {
      if ($0.start ?? 1441) != ($1.start ?? 1441) { return ($0.start ?? 1441) < ($1.start ?? 1441) }
      return $0.task.title.compare(
        $1.task.title, options: [], locale: Locale(identifier: language.rawValue))
        == .orderedAscending
    }
  }

  public static func addMonths(to key: String, months: Int) -> String? {
    guard let date = date(key),
      let target = calendar.date(byAdding: .month, value: months, to: date)
    else { return nil }
    return HabitSchedule.dateKey(target, timeZone: "UTC")
  }

  public static func startOfMonth(_ key: String) -> String? {
    guard let date = date(key) else { return nil }
    var components = calendar.dateComponents([.year, .month], from: date)
    components.day = 1
    components.hour = 12
    guard let start = calendar.date(from: components) else { return nil }
    return HabitSchedule.dateKey(start, timeZone: "UTC")
  }

  /// Actual days of the month; a calendar UI can pad this with adjacent weeks separately.
  public static func monthDates(containing key: String) -> [String] {
    guard let start = startOfMonth(key), let date = date(start),
      let range = calendar.range(of: .day, in: .month, for: date)
    else { return [] }
    return range.compactMap { HabitSchedule.addDays(to: start, days: $0 - 1) }
  }
}
