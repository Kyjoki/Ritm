import Foundation

/// How far ahead the calendar reads Google, so that a swipe between periods never waits for the
/// network and never swaps the data while the page slides.
///
/// Three nested ranges around the visible period:
/// - `fetchRange` (the neighbouring periods): the least the page needs to draw a swipe;
/// - `warmRange` (two periods each way): what should be there once the phone is idle;
/// - `loadRange`: what one read actually loads, wider than both, so a read is needed only after
///   a few swipes in the same direction. The server accepts at most 93 days per read.
extension CalendarViewMode {
  /// Periods read on each side of the visible one by a single read of the hour grid (a week: 77 days).
  public static let loadPeriods = 5
  /// Periods that should be loaded on each side when nothing else is going on.
  public static let warmPeriods = 2

  /// The range one Google read loads for the page.
  public func loadRange(anchor: String, scheduleDays: Int = CalendarViewMode.scheduleInitialDays)
    -> (from: String, to: String)
  {
    if self == .month { return monthLoadRange(anchor: anchor) }
    guard isTimeGrid else { return fetchRange(anchor: anchor, scheduleDays: scheduleDays) }
    return padded(anchor: anchor, periods: Self.loadPeriods, floor: 14)
  }

  /// The days that should be loaded once the page is idle.
  public func warmRange(anchor: String, scheduleDays: Int = CalendarViewMode.scheduleInitialDays)
    -> (from: String, to: String)
  {
    guard isTimeGrid else { return fetchRange(anchor: anchor, scheduleDays: scheduleDays) }
    return padded(anchor: anchor, periods: Self.warmPeriods, floor: 6)
  }

  /// The month: from 31 days before its first day to 31 days after its last, at most 31 + 62 = 93
  /// days, the most the server reads at once. That holds the whole 6-week grid (it reaches at most
  /// 6 days before and 13 after the month) and both neighbouring months, so a swipe to either
  /// one finds all its days, its grid included, already read.
  public static let monthPad = 31

  private func monthLoadRange(anchor: String) -> (from: String, to: String) {
    let dates = TaskSchedule.monthDates(containing: anchor)
    let first = dates.first ?? anchor
    let last = dates.last ?? anchor
    return (
      HabitSchedule.addDays(to: first, days: -Self.monthPad) ?? first,
      HabitSchedule.addDays(to: last, days: 1 + Self.monthPad) ?? last
    )
  }

  private func padded(anchor: String, periods: Int, floor: Int) -> (from: String, to: String) {
    let days = visibleDays(anchor: anchor)
    let first = days.first ?? anchor
    let count = days.count
    let pad = max(count * periods, floor)
    return (
      HabitSchedule.addDays(to: first, days: -pad) ?? first,
      HabitSchedule.addDays(to: first, days: count + pad) ?? first
    )
  }

  /// What the page does about its data after the period changed.
  public enum ReadDecision: Sendable, Equatable {
    /// Everything it may need soon is already read.
    case none
    /// The neighbours are missing: read now.
    case now
    /// The visible period and its neighbours are read, but not what lies further: read quietly
    /// once the page has been left alone for a moment, without a spinner.
    case whenIdle
  }

  public func readDecision(
    anchor: String, scheduleDays: Int = CalendarViewMode.scheduleInitialDays,
    read: (from: String, to: String)?
  ) -> ReadDecision {
    if !Self.covers(read, fetchRange(anchor: anchor, scheduleDays: scheduleDays)) { return .now }
    if !Self.covers(read, warmRange(anchor: anchor, scheduleDays: scheduleDays)) { return .whenIdle }
    return .none
  }
}
