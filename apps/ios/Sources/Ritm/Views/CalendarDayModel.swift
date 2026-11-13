import Foundation
import Observation
import RitmCore

/// The calendar page's reading of the days, kept between redraws. The page redraws for every
/// small change (a spinner, a sheet, a swipe), and the work behind a day (instants, zones, the
/// overlap layout, the month's cells) is far too heavy to repeat each time. This is not
/// observed: it changes only when the page hands it new data (`sync`), which bumps `generation`.
///
/// Every day carries a `stamp` that changes only when what the day shows changes. After new data
/// arrives a day is read again, but when it comes out the same as before it keeps its stamp, so
/// the views drawn from that stamp do not draw it again: a Google read that only added events
/// further away costs the visible week nothing. The days the page will need next (the
/// neighbouring weeks) are read ahead on a background thread (`prewarm`) and copied in.
@MainActor
final class CalendarDayModel {
  private var tasks: [RitmTask] = []
  private var events: [GoogleCalendarEvent] = []
  private var zone = ""
  private var language = Language.ru
  private var hidden: Set<String> = []
  private var cache = CalendarDayCache()
  private var months: [String: [[CalendarMonthCell]]] = [:]
  private var warming: Set<String> = []
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
    cache.invalidate()
    months = [:]
    warming = []
    generation += 1
    return generation
  }

  /// Reads the days that are not cached yet in one go.
  func prepare(_ requested: [String]) {
    let missing = cache.missing(requested)
    guard !missing.isEmpty else { return }
    cache.ingest(
      CalendarDayCompute.compute(
        tasks: tasks, events: events, hidden: hidden, dates: missing, timeZone: zone,
        language: language))
  }

  /// Reads days ahead of need on a background thread and copies the result in, unless the data
  /// changed meanwhile. The page keeps working while it runs: a day it needs earlier is simply
  /// read on the spot.
  func prewarm(_ requested: [String]) async {
    let missing = cache.missing(requested).filter { !warming.contains($0) }
    guard !missing.isEmpty else { return }
    warming.formUnion(missing)
    let ticket = generation
    let (tasks, events, hidden, zone, language) = (tasks, events, hidden, zone, language)
    let read = await Task.detached(priority: .utility) {
      CalendarDayCompute.compute(
        tasks: tasks, events: events, hidden: hidden, dates: missing, timeZone: zone,
        language: language)
    }.value
    guard ticket == generation else { return }
    warming.subtract(missing)
    cache.ingest(read)
  }

  private func entry(_ day: String) -> CalendarDayCache.Entry? {
    if cache.entry(day) == nil { prepare([day]) }
    return cache.entry(day)
  }

  func entries(_ day: String) -> [DayOccurrence] { entry(day)?.data.entries ?? [] }

  /// The overlap lanes of a day, worked out with the day.
  func layout(_ day: String) -> [PlacedOccurrence] { entry(day)?.data.placed ?? [] }

  /// The stamps of `requested`, reading the missing days in one go.
  func stamps(_ requested: [String]) -> [Int] {
    prepare(requested)
    return requested.map { cache.entry($0)?.stamp ?? 0 }
  }

  /// The six rows of the month cells around `anchor`, cached per look.
  func monthRows(anchor: String, today: String, selected: String, limit: Int) -> [[CalendarMonthCell]] {
    let key = "\(anchor.prefix(7))|\(today)|\(selected)|\(limit)"
    if let rows = months[key] { return rows }
    prepare(CalendarPlan.monthDays(containing: anchor))
    let rows = CalendarPlan.monthRows(
      anchor: anchor, today: today, selected: selected, limit: limit, stamp: generation
    ) { cache.entry($0)?.data.entries ?? [] }
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
