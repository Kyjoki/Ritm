import Foundation

/// One cell of the month view, ready to draw: the day, its flags and the few bars it shows.
/// Two cells are equal when they would draw the same, so an unchanged cell is not drawn again;
/// `stamp` is the generation of the entries it was built from.
public struct CalendarMonthCell: Sendable, Equatable, Identifiable {
  public let day: String
  public let number: Int
  public let inMonth: Bool
  public let isToday: Bool
  public let isSelected: Bool
  public let bars: [DayOccurrence]
  public let more: Int
  public let total: Int
  public let stamp: Int
  public var id: String { day }

  public static func == (left: CalendarMonthCell, right: CalendarMonthCell) -> Bool {
    left.day == right.day && left.stamp == right.stamp && left.inMonth == right.inMonth
      && left.isToday == right.isToday && left.isSelected == right.isSelected
      && left.more == right.more && left.total == right.total
  }
}

extension CalendarPlan {
  /// The six rows of seven cells of the month containing `anchor`, Sunday first. `entries` is
  /// asked once per day; each cell keeps at most `limit` rows of bars (see `monthBars`).
  public static func monthRows(
    anchor: String, today: String, selected: String, limit: Int, stamp: Int,
    entries: (String) -> [DayOccurrence]
  ) -> [[CalendarMonthCell]] {
    let days = monthDays(containing: anchor)
    guard days.count == 42 else { return [] }
    let month = anchor.prefix(7)
    let cells = days.map { day -> CalendarMonthCell in
      let list = entries(day)
      let bars = monthBars(list, limit: limit)
      return CalendarMonthCell(
        day: day, number: Int(day.suffix(2)) ?? 0, inMonth: day.prefix(7) == month,
        isToday: day == today, isSelected: day == selected, bars: bars.shown, more: bars.more,
        total: list.count, stamp: stamp)
    }
    return (0..<6).map { Array(cells[$0 * 7..<$0 * 7 + 7]) }
  }
}
