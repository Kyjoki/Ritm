import Foundation

/// The analytics and day states of the habits page (src/features/HabitsPage.tsx).
public enum HabitsPlan {
  public enum DayStatus: Sendable, Equatable { case before, future, done, pending, rest }
  public enum HeatLevel: Sendable, Equatable { case future, none, full, some, empty }

  /// `periodDates`: the week around today or a whole calendar month, `offset` periods away.
  public static func periodDates(today: String, month: Bool, offset: Int) -> [String] {
    if !month {
      return HabitSchedule.week(containing: HabitSchedule.addDays(to: today, days: offset * 7) ?? today)
    }
    guard let start = TaskSchedule.startOfMonth(today),
      let first = TaskSchedule.addMonths(to: start, months: offset)
    else { return [] }
    return TaskSchedule.monthDates(containing: first)
  }

  public static func dayStatus(_ habit: Habit, on day: String, today: String) -> DayStatus {
    let canMark = HabitSchedule.canMark(habit, on: day, today: today)
    if day < habit.startDate && !canMark { return .before }
    if day > today { return .future }
    guard HabitSchedule.isScheduled(habit, on: day) || canMark else { return .rest }
    return HabitSchedule.isComplete(habit, on: day) ? .done : .pending
  }

  public static func heatLevel(_ summary: HabitDaySummary, day: String, today: String) -> HeatLevel {
    if day > today { return .future }
    guard summary.planned > 0 else { return .none }
    if summary.completed == summary.planned { return .full }
    return summary.completed > 0 ? .some : .empty
  }

  /// «Самая стабильная»: the best completion share among habits planned at least three times
  /// on the past days of the period.
  public static func steadiest(_ habits: [Habit], dates: [String], today: String)
    -> (habit: Habit, percent: Int)?
  {
    let past = dates.filter { $0 < today }
    let rated = habits.map { habit in
      (habit, HabitSchedule.periodSummary([habit], dates: past))
    }
    .filter { $0.1.planned >= 3 }
    let best = rated.stableSorted { a, b in
      let left = Double(a.1.completed) / Double(a.1.planned)
      let right = Double(b.1.completed) / Double(b.1.planned)
      return left != right ? left > right : a.1.completed > b.1.completed
    }.first
    guard let best else { return nil }
    return (best.0, Int((Double(best.1.completed) / Double(best.1.planned) * 100).rounded()))
  }

  /// «Чаще пропускается»: the weekday with the lowest share among those planned twice or more;
  /// nil when nothing was missed.
  public static func weakestWeekday(_ habits: [Habit], dates: [String], today: String) -> Int? {
    let days = dates.filter { $0 < today }
    let rows = (0..<7).map { weekday -> (weekday: Int, planned: Int, completed: Int) in
      let summaries = days.filter { HabitSchedule.weekday($0) == weekday }
        .map { HabitSchedule.daySummary(habits, on: $0, today: today) }
      return (
        weekday, summaries.reduce(0) { $0 + $1.planned }, summaries.reduce(0) { $0 + $1.completed }
      )
    }
    .filter { $0.planned >= 2 }
    let weakest = rows.stableSorted {
      Double($0.completed) / Double($0.planned) < Double($1.completed) / Double($1.planned)
    }.first
    guard let weakest, weakest.completed < weakest.planned else { return nil }
    return weakest.weekday
  }

  /// «К прошлому периоду»: the elapsed days of this period against as many days of the last one.
  public static func comparison(_ habits: [Habit], today: String, month: Bool, offset: Int)
    -> (current: Int, previous: Int)?
  {
    let dates = periodDates(today: today, month: month, offset: offset)
    guard let first = dates.first, let before = HabitSchedule.addDays(to: first, days: -1) else {
      return nil
    }
    let available = dates.filter { $0 <= today }
    let previousDates = periodDates(today: before, month: month, offset: 0)
    let length = min(available.count, previousDates.count)
    let current = HabitSchedule.periodSummary(habits, dates: Array(available.prefix(length)), today: today)
    let previous = HabitSchedule.periodSummary(
      habits, dates: Array(previousDates.prefix(length)), today: today)
    guard let now = current.progress, let then = previous.progress else { return nil }
    return (now, then)
  }

  public static func awards(_ habit: Habit, best: Int) -> [Int] {
    habit.achievements ?? HabitSchedule.milestones.filter { best >= $0 }
  }

  public static func nextMilestone(_ habit: Habit, best: Int) -> Int? {
    let earned = awards(habit, best: best)
    return HabitSchedule.milestones.first { !earned.contains($0) }
  }

  /// The smallest milestone the server granted with this mark, for the celebration.
  public static func newMilestone(previous: Habit, updated: Habit) -> Int? {
    HabitSchedule.milestones.first {
      (updated.achievements ?? []).contains($0) && !(previous.achievements ?? []).contains($0)
    }
  }
}
