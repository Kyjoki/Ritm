import RitmCore
import SwiftUI

/// Streaks, records and achievement days of each habit, walked once and remembered until that
/// habit (or the day) changes. A tick changes one habit, so only its entry is recomputed; the
/// optimistic copy keeps the old `updatedAt`, so entries are matched by the whole habit.
@MainActor
final class HabitStatsCache {
  static let shared = HabitStatsCache()
  private var entries: [String: (habit: Habit, today: String, stats: HabitStats)] = [:]

  func stats(for habit: Habit, today: String) -> HabitStats {
    if let entry = entries[habit.id], entry.today == today, entry.habit == habit {
      return entry.stats
    }
    let stats = HabitAnalytics.stats(habit, today: today)
    entries[habit.id] = (habit, today, stats)
    return stats
  }

  /// Forget habits that no longer exist.
  func keep(_ ids: Set<String>) {
    if entries.keys.contains(where: { !ids.contains($0) }) {
      entries = entries.filter { ids.contains($0.key) }
    }
  }
}

/// What the analytics card shows for one period, computed from the habits that are shown.
struct HabitOverview: Equatable {
  let dates: [String]
  /// One summary per date of `dates`.
  let days: [HabitDaySummary]
  let planned: Int
  let completed: Int
  /// nil when nothing was scheduled in the period.
  let percent: Int?
  let streak: Int
  let record: Int
  let best: HabitRate?
  let worst: HabitRate?
  let trend: Int?

  static func make(habits: [Habit], today: String, month: Bool, offset: Int) -> HabitOverview {
    let dates = HabitsPlan.periodDates(today: today, month: month, offset: offset)
    let days = dates.map { HabitSchedule.daySummary(habits, on: $0, today: today) }
    let planned = days.reduce(0) { $0 + $1.planned }
    let completed = days.reduce(0) { $0 + $1.completed }
    let end = dates.last { $0 <= today } ?? dates.first ?? today
    let good = HabitAnalytics.goodDayStreaks(habits, end: end, today: today)
    let ranked = HabitAnalytics.bestAndWorst(HabitAnalytics.rates(habits, dates: dates, today: today))
    return HabitOverview(
      dates: dates, days: days, planned: planned, completed: completed,
      percent: planned > 0 ? Int((Double(completed) / Double(planned) * 100).rounded()) : nil,
      streak: good.current, record: good.best, best: ranked.best, worst: ranked.worst,
      trend: HabitAnalytics.trend(habits, today: today, month: month, offset: offset))
  }
}

/// Remembers the last overview: the page body runs for unrelated reasons (a toast, a banner)
/// and must not redo the period walk each time.
@MainActor
final class HabitOverviewCache {
  private struct Key: Equatable {
    let habits: [Habit]
    let today: String
    let month: Bool
    let offset: Int
  }
  private var key: Key?
  private var value: HabitOverview?

  func overview(habits: [Habit], today: String, month: Bool, offset: Int) -> HabitOverview {
    let next = Key(habits: habits, today: today, month: month, offset: offset)
    if let value, key == next { return value }
    let made = HabitOverview.make(habits: habits, today: today, month: month, offset: offset)
    key = next
    value = made
    return made
  }
}
