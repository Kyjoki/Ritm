import Foundation

/// One day of the week strip on «Тренировки» (Monday first).
public struct WorkoutWeekDay: Equatable, Sendable {
  public let key: String
  /// 0 = Monday … 6 = Sunday.
  public let index: Int
  public let isDone: Bool
  public let isToday: Bool
}

/// The ring and strip of the hero card: «N/M на неделе».
public struct WorkoutWeek: Equatable, Sendable {
  public let days: [WorkoutWeekDay]
  public let done: Int
  public let goal: Int
  /// The linked habit's title; `nil` when the numbers come from workouts.
  public let habitTitle: String?

  public var progress: Double { goal > 0 ? min(1, Double(done) / Double(goal)) : 0 }
}

public enum WorkoutStats {
  /// Workouts per week when no habit is linked.
  public static let fallbackGoal = 4

  /// The Monday of the week that contains `key`.
  public static func monday(of key: String) -> String? {
    guard let weekday = HabitSchedule.weekday(key) else { return nil }
    return HabitSchedule.addDays(to: key, days: -((weekday + 6) % 7))
  }

  private static func weekKeys(containing key: String) -> [String] {
    guard let start = monday(of: key) else { return [] }
    return (0..<7).compactMap { HabitSchedule.addDays(to: start, days: $0) }
  }

  /// Days with a finished workout, in the owner's time zone.
  public static func workoutDays(_ history: WorkoutHistory, timeZone: String) -> Set<String> {
    Set(history.records.map { HabitSchedule.dateKey($0.endedAt, timeZone: timeZone) })
  }

  /// With a linked habit: M is the number of days that week the habit is scheduled, N the days it
  /// is complete, the strip its days. Without one: workout days, out of 4.
  public static func week(habit: Habit?, history: WorkoutHistory, today: String, timeZone: String)
    -> WorkoutWeek
  {
    let keys = weekKeys(containing: today)
    let loggedDays = habit == nil ? workoutDays(history, timeZone: timeZone) : []
    let days = keys.enumerated().map { index, key in
      let done = habit.map { HabitSchedule.isComplete($0, on: key) } ?? loggedDays.contains(key)
      return WorkoutWeekDay(key: key, index: index, isDone: done, isToday: key == today)
    }
    let goal = habit.map(weeklyGoal) ?? fallbackGoal
    return WorkoutWeek(
      days: days, done: days.filter(\.isDone).count, goal: goal, habitTitle: habit?.title)
  }

  /// How many days a week the habit is planned: the weekdays of its current schedule (all seven
  /// when it has none), the same plan the Habits screen counts. Never below 1.
  public static func weeklyGoal(_ habit: Habit) -> Int {
    let today = habit.periods?.last?.weekdays ?? habit.weekdays ?? HabitSchedule.allWeekdays
    return max(1, Set(today).count)
  }

  /// The strip of a linked habit that is not loaded yet: no numbers, nothing done.
  public static func pendingWeek(today: String) -> WorkoutWeek {
    let days = weekKeys(containing: today).enumerated().map {
      WorkoutWeekDay(key: $0.element, index: $0.offset, isDone: false, isToday: $0.element == today)
    }
    return WorkoutWeek(days: days, done: 0, goal: 0, habitTitle: nil)
  }

  /// Kilograms lifted in the week that starts on `monday`.
  public static func volume(_ history: WorkoutHistory, weekStarting monday: String, timeZone: String)
    -> Double
  {
    let keys = Set(weekKeys(containing: monday))
    return history.records
      .filter { keys.contains(HabitSchedule.dateKey($0.endedAt, timeZone: timeZone)) }
      .reduce(0) { $0 + $1.volume }
  }

  /// This week's volume and its change against the whole last week (`nil` without a last week).
  public static func volumeTrend(_ history: WorkoutHistory, today: String, timeZone: String)
    -> (volume: Double, percent: Int?)
  {
    guard let start = monday(of: today), let previous = HabitSchedule.addDays(to: start, days: -7)
    else { return (0, nil) }
    let current = volume(history, weekStarting: start, timeZone: timeZone)
    let last = volume(history, weekStarting: previous, timeZone: timeZone)
    guard last > 0 else { return (current, nil) }
    return (current, Int(((current - last) / last * 100).rounded()))
  }

  /// Weeks in a row with at least one workout; this week counts once it has one.
  public static func streakWeeks(_ history: WorkoutHistory, today: String, timeZone: String) -> Int {
    guard var week = monday(of: today) else { return 0 }
    let mondays = Set(workoutDays(history, timeZone: timeZone).compactMap(monday(of:)))
    if !mondays.contains(week) {
      guard let previous = HabitSchedule.addDays(to: week, days: -7) else { return 0 }
      week = previous
    }
    var count = 0
    while mondays.contains(week) {
      count += 1
      guard let previous = HabitSchedule.addDays(to: week, days: -7) else { break }
      week = previous
    }
    return count
  }
}
