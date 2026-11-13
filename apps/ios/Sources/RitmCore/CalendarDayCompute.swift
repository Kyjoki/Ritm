import Foundation

/// One day of the grid, ready to draw: its entries and their overlap lanes.
public struct CalendarDayData: Sendable, Equatable {
  public let entries: [DayOccurrence]
  public let placed: [PlacedOccurrence]
}

/// The whole reading of some days as one pure function of plain values, so the calendar page can
/// run it off the main actor for the neighbouring weeks while the phone is idle and only copy the
/// result in. Nothing here touches the UI or any shared state.
public enum CalendarDayCompute {
  public static func compute(
    tasks: [RitmTask], events: [GoogleCalendarEvent], hidden: Set<String>, dates: [String],
    timeZone: String, language: Language
  ) -> [String: CalendarDayData] {
    guard !dates.isEmpty else { return [:] }
    let read = DayPlan.occurrencesByDay(
      tasks: CalendarSources.visible(tasks, hidden: hidden),
      events: CalendarSources.visible(events, hidden: hidden), dates: dates, timeZone: timeZone,
      language: language)
    return read.mapValues { CalendarDayData(entries: $0, placed: CalendarPlan.layout($0)) }
  }
}
