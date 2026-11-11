import Foundation
import Observation
import RitmCore

/// The calendar page's reading of the days, kept between redraws. The page redraws for every
/// small change (a spinner, a sheet, a swipe), and the work behind a day (instants, zones, the
/// overlap layout, the month's cells) is far too heavy to repeat each time. This is not
/// observed: it changes only when the page hands it new data (`sync`), which bumps `generation`
/// so the views that drew the old data know to draw again.
@MainActor
final class CalendarDayModel {
  private var tasks: [RitmTask] = []
  private var events: [GoogleCalendarEvent] = []
  private var zone = ""
  private var language = Language.ru
  private var hidden: Set<String> = []
  private var byDay: [String: [DayOccurrence]] = [:]
  private var placedByDay: [String: [PlacedOccurrence]] = [:]
  private var months: [String: [[CalendarMonthCell]]] = [:]
  private(set) var generation = 0

  /// Hands over the data the page shows. Nothing is redone when it is the same as before (equal
  /// arrays of the same storage compare at once); otherwise the caches are dropped.
  @discardableResult
  func sync(
    tasks: [RitmTask], events: [GoogleCalendarEvent], zone: String, language: Language,
    hidden: Set<String>
  ) -> Int {
    guard tasks != self.tasks || events != self.events || zone != self.zone
      || language != self.language || hidden != self.hidden
    else { return generation }
    self.tasks = tasks
    self.events = events
    self.zone = zone
    self.language = language
    self.hidden = hidden
    byDay = [:]
    placedByDay = [:]
    months = [:]
    generation += 1
    return generation
  }

  /// Reads the days that are not cached yet in one go.
  func prepare(_ days: [String]) {
    let missing = days.filter { byDay[$0] == nil }
    guard !missing.isEmpty else { return }
    let read = DayPlan.occurrencesByDay(
      tasks: CalendarSources.visible(tasks, hidden: hidden),
      events: CalendarSources.visible(events, hidden: hidden), dates: missing, timeZone: zone,
      language: language)
    byDay.merge(read) { _, new in new }
  }

  func entries(_ day: String) -> [DayOccurrence] {
    if byDay[day] == nil { prepare([day]) }
    return byDay[day] ?? []
  }

  /// The overlap lanes of a day, worked out once per generation.
  func layout(_ day: String) -> [PlacedOccurrence] {
    if let placed = placedByDay[day] { return placed }
    let placed = CalendarPlan.layout(entries(day))
    placedByDay[day] = placed
    return placed
  }

  /// The six rows of the month cells around `anchor`, cached per look.
  func monthRows(anchor: String, today: String, selected: String, limit: Int) -> [[CalendarMonthCell]] {
    let key = "\(anchor.prefix(7))|\(today)|\(selected)|\(limit)"
    if let rows = months[key] { return rows }
    prepare(CalendarPlan.monthDays(containing: anchor))
    let rows = CalendarPlan.monthRows(
      anchor: anchor, today: today, selected: selected, limit: limit, stamp: generation
    ) { byDay[$0] ?? [] }
    months[key] = rows
    return rows
  }
}

/// Which of the page's two overlays are open. Only the views that draw an overlay read it, so
/// opening the side menu or the mini-month redraws those and nothing else: the grid behind them
/// is not touched.
@MainActor @Observable
final class CalendarChrome {
  var drawerOpen = false
  var miniOpen = false
}

/// The hidden calendars of the side menu, kept on the phone per account.
enum CalendarFilterStore {
  private static func key(_ email: String) -> String { "ritm.calendar.filter." + email.lowercased() }

  static func load(email: String) -> CalendarFilter {
    guard let data = UserDefaults.standard.data(forKey: key(email)),
      let filter = try? JSONDecoder().decode(CalendarFilter.self, from: data)
    else { return CalendarFilter() }
    return filter
  }

  static func save(_ filter: CalendarFilter, email: String) {
    guard let data = try? JSONEncoder().encode(filter) else { return }
    UserDefaults.standard.set(data, forKey: key(email))
  }
}
