import Foundation

/// One displayed entry of a day, from a Ritm task or a Google event, as the web builds it in
/// src/features/google-occurrences.ts. Times are wall-clock minutes in the account zone.
public struct DayOccurrence: Sendable, Equatable, Identifiable {
  public enum Source: Sendable, Equatable {
    case ritm(TaskOccurrence)
    case google(GoogleCalendarEvent)
  }

  public var key: String
  /// The displayed day, independent from the original start of the entry.
  public var date: String
  public var title: String
  public var start: Int?
  public var end: Int?
  public var completed: Bool
  public var allDay: Bool
  public var busy: Bool
  public var continued: Bool
  public var duration: Int
  public var startLabel: String?
  public var endLabel: String?
  public var clockChange: Bool
  public var source: Source
  public var id: String { key }

  public var task: TaskOccurrence? {
    switch source {
    case .ritm(let occurrence): return occurrence
    case .google: return nil
    }
  }

  public var event: GoogleCalendarEvent? {
    switch source {
    case .ritm: return nil
    case .google(let event): return event
    }
  }

  public var colorId: String? { task?.task.colorId ?? event?.colorId }
}

/// Task counts of one day: Ritm tasks plus Google entries that are tasks (DashboardPage.tsx).
public struct DayTaskSummary: Sendable, Equatable {
  public let entries: [TaskOccurrence]
  public let googleTodos: [DayOccurrence]

  public init(
    tasks: [RitmTask], events: [GoogleCalendarEvent], date: String, timeZone: String,
    language: Language
  ) {
    entries = TaskSchedule.dayOccurrences(
      tasks.filter { $0.kind == .task }, date: date, language: language
    ).stableSorted { Self.precedes($0.completed, $0.start, $1.completed, $1.start) }
    googleTodos = DayPlan.occurrences(
      tasks: [], events: events, date: date, timeZone: timeZone, language: language
    )
    .filter { $0.event?.taskLink == true || $0.event?.googleTask != nil }
    .stableSorted { Self.precedes($0.completed, $0.start, $1.completed, $1.start) }
  }

  public var count: Int { entries.count + googleTodos.count }
  public var completed: Int {
    entries.filter(\.completed).count
      + googleTodos.filter { $0.event?.googleTask?.status == "completed" }.count
  }
  /// Google entries whose task status the server could not confirm.
  public var unknown: Int { googleTodos.filter { $0.event?.googleTask == nil }.count }

  /// Open entries first, then by start time; entries without a time go last.
  private static func precedes(_ done: Bool, _ start: Int?, _ otherDone: Bool, _ otherStart: Int?)
    -> Bool
  {
    (done ? 1 : 0, start ?? 1441) < (otherDone ? 1 : 0, otherStart ?? 1441)
  }
}

extension Array {
  /// `Array.prototype.sort` is stable; Swift's `sorted` is not, so ties keep their order here.
  func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
    enumerated()
      .sorted { lhs, rhs in
        if areInIncreasingOrder(lhs.element, rhs.element) { return true }
        if areInIncreasingOrder(rhs.element, lhs.element) { return false }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }
}

/// Calculations behind «Мой день» (src/components/DashboardPage.tsx, src/lib/date.ts).
public enum DayPlan {
  /// `formatTime`: the web always shows a 12-hour clock.
  public static func clock(_ minutes: Int, compact: Bool = false) -> String {
    let normalized = ((minutes % 1440) + 1440) % 1440
    let hour = normalized / 60
    let minute = normalized % 60
    let minuteLabel = compact && minute == 0 ? "" : String(format: ":%02d", minute)
    return "\(hour % 12 == 0 ? 12 : hour % 12)\(minuteLabel) \(hour < 12 ? "AM" : "PM")"
  }

  /// `durationText`.
  public static func durationText(_ minutes: Int, language: Language) -> String {
    let english = language == .en
    var parts: [String] = []
    if minutes / 60 > 0 { parts.append("\(minutes / 60) " + (english ? "h" : "ч")) }
    if minutes % 60 > 0 { parts.append("\(minutes % 60) " + (english ? "min" : "мин")) }
    if parts.isEmpty { return english ? "0 min" : "0 мин" }
    return parts.joined(separator: " ")
  }

  /// `greeting`, with the web's English strings (night reads as evening).
  public static func greeting(hour: Int, language: Language) -> String {
    let english = language == .en
    if hour < 6 { return english ? "Good evening" : "Доброй ночи" }
    if hour < 12 { return english ? "Good morning" : "Доброе утро" }
    if hour < 18 { return english ? "Good afternoon" : "Добрый день" }
    return english ? "Good evening" : "Добрый вечер"
  }

  /// The task counter next to «Задачи на сегодня» (`Intl.PluralRules`).
  public static func taskCount(_ count: Int, language: Language) -> String {
    guard language == .ru else { return "\(count) \(count == 1 ? "task" : "tasks")" }
    let lastTwo = count % 100
    let last = count % 10
    let word =
      last == 1 && lastTwo != 11
      ? "задача" : (2...4).contains(last) && !(12...14).contains(lastTwo) ? "задачи" : "задач"
    return "\(count) \(word)"
  }

  public static func googleOccurrences(
    _ events: [GoogleCalendarEvent], date: String, timeZone: String
  ) -> [DayOccurrence] {
    guard let zone = TimeZone(identifier: timeZone) else { return [] }
    return events.compactMap { event in
      if event.allDay { return allDayOccurrence(event, date: date) }
      guard let span = timedSpan(event, zone: zone) else { return nil }
      return timedOccurrence(
        event, date: date, span: span, startDate: span.start.date, endDate: span.end.date)
    }
  }

  /// `occurrences` for many days at once, with the same result as calling it day by day. Each
  /// event's instants, wall-clock span and clock-change check are worked out once, so a day only
  /// builds the entries of the events that touch it. Reading a week day by day repeated that work
  /// for every event and every day, and it was the main cost of changing the period.
  public static func occurrencesByDay(
    tasks: [RitmTask], events: [GoogleCalendarEvent], dates: [String], timeZone: String,
    language: Language
  ) -> [String: [DayOccurrence]] {
    let google = googleByDay(events, dates: dates, timeZone: timeZone)
    var result: [String: [DayOccurrence]] = [:]
    for date in dates {
      result[date] = merged(tasks: tasks, google: google[date] ?? [], date: date, language: language)
    }
    return result
  }

  /// The Google entries of each of `dates`, in the order of `events`.
  private static func googleByDay(
    _ events: [GoogleCalendarEvent], dates: [String], timeZone: String
  ) -> [String: [DayOccurrence]] {
    guard let zone = TimeZone(identifier: timeZone) else { return [:] }
    var result: [String: [DayOccurrence]] = [:]
    for event in events {
      if event.allDay {
        guard let first = event.start.date, let last = event.end.date else { continue }
        for date in dates where date >= first && date <= last {
          if let entry = allDayOccurrence(event, date: date) { result[date, default: []].append(entry) }
        }
        continue
      }
      guard let span = timedSpan(event, zone: zone) else { continue }
      let startDate = span.start.date
      let endDate = span.end.date
      for date in dates where date >= startDate && date <= endDate {
        if let entry = timedOccurrence(
          event, date: date, span: span, startDate: startDate, endDate: endDate)
        {
          result[date, default: []].append(entry)
        }
      }
    }
    return result
  }

  /// Ritm calendar entries and Google events of one day; quick tasks stay out of the calendar.
  public static func occurrences(
    tasks: [RitmTask], events: [GoogleCalendarEvent], date: String, timeZone: String,
    language: Language
  ) -> [DayOccurrence] {
    merged(
      tasks: tasks, google: googleOccurrences(events, date: date, timeZone: timeZone), date: date,
      language: language)
  }

  private static func merged(
    tasks: [RitmTask], google: [DayOccurrence], date: String, language: Language
  ) -> [DayOccurrence] {
    let local = TaskSchedule.dayOccurrences(
      tasks.filter { $0.calendarEntry != false }, date: date, language: language
    ).map { entry in
      DayOccurrence(
        key: "ritm:\(entry.key)", date: date, title: entry.task.title, start: entry.start,
        end: entry.end, completed: entry.completed, allDay: false,
        busy: !entry.completed && entry.start != nil, continued: entry.key.hasSuffix(":continued"),
        duration: entry.task.duration, startLabel: nil, endLabel: nil, clockChange: false,
        source: .ritm(entry))
    }
    let locale = Locale(identifier: language.rawValue)
    return (local + google).sorted { a, b in
      if a.allDay != b.allDay { return a.allDay }
      if (a.start ?? 1441) != (b.start ?? 1441) { return (a.start ?? 1441) < (b.start ?? 1441) }
      let order = a.title.compare(b.title, options: [], locale: locale)
      return order == .orderedSame ? a.key < b.key : order == .orderedAscending
    }
  }

  /// Free minutes left in the workday. A busy all-day entry fills the whole workday.
  public static func freeMinutes(
    _ entries: [DayOccurrence], workStart: Int, workEnd: Int, now: Int
  ) -> Int {
    let intervals =
      entries
      .filter(\.busy)
      .map { entry in
        (
          max(workStart, entry.allDay ? workStart : (entry.start ?? workEnd), now),
          min(workEnd, entry.allDay ? workEnd : (entry.end ?? workStart))
        )
      }
      .filter { $0.1 > $0.0 }
      .sorted { $0.0 < $1.0 }
    var occupied = 0
    var covered = max(workStart, now)
    for (start, end) in intervals {
      occupied += max(0, end - max(start, covered))
      covered = max(covered, end)
    }
    return max(0, workEnd - max(workStart, now) - occupied)
  }

  /// Share of each hour from 9 AM to 9 PM covered by timed entries, capped at one.
  public static func rhythm(_ entries: [DayOccurrence]) -> [Double] {
    let timed = entries.compactMap { entry -> (Int, Int)? in
      guard let start = entry.start, let end = entry.end else { return nil }
      return (start, end)
    }
    return (0..<13).map { index in
      let start = (index + 9) * 60
      let busy = timed.reduce(0) { $0 + max(0, min($1.1, start + 60) - max($1.0, start)) }
      return min(1, Double(busy) / 60)
    }
  }

  /// The entry the focus card shows: the earliest unfinished timed entry that has not ended.
  public static func upcoming(_ entries: [DayOccurrence], now: Int) -> DayOccurrence? {
    entries
      .filter { entry in
        guard entry.start != nil, let end = entry.end else { return false }
        return !entry.completed && end > now
      }
      .min { ($0.start ?? 0) < ($1.start ?? 0) }
  }

  // MARK: - Google segments

  /// What one timed event needs on every day it touches, worked out once.
  private struct TimedSpan {
    let startInstant: Date
    let endInstant: Date
    let start: CalendarInstants.Wall
    let end: CalendarInstants.Wall
    let exact: Double
    let clockChange: Bool
  }

  private static func timedSpan(_ event: GoogleCalendarEvent, zone: TimeZone) -> TimedSpan? {
    guard let startInstant = CalendarEventPolicy.instant(event.start.dateTime),
      let endInstant = CalendarEventPolicy.instant(event.end.dateTime), endInstant > startInstant
    else { return nil }
    let start = CalendarInstants.wall(startInstant, zone: zone)
    let end = CalendarInstants.wall(endInstant, zone: zone)
    let exact = endInstant.timeIntervalSince(startInstant) / 60
    let wallDuration = end.epochMinutes - start.epochMinutes
    let clockChange =
      abs(Double(wallDuration) - exact) >= 1
      || CalendarEventPolicy.isAmbiguous(startInstant, zone: zone)
      || CalendarEventPolicy.isAmbiguous(endInstant, zone: zone)
    return TimedSpan(
      startInstant: startInstant, endInstant: endInstant, start: start, end: end, exact: exact,
      clockChange: clockChange)
  }

  private static func allDayOccurrence(_ event: GoogleCalendarEvent, date: String)
    -> DayOccurrence?
  {
    // Google all-day end dates are exclusive and never shift with the time zone.
    guard let start = event.start.date, let end = event.end.date, date >= start, date < end else {
      return nil
    }
    return DayOccurrence(
      key: "google:\(event.calendarId):\(event.id):\(date)", date: date, title: event.title,
      start: nil, end: nil, completed: event.googleTask?.status == "completed", allDay: true,
      busy: event.busy, continued: start < date, duration: 1440, startLabel: nil, endLabel: nil,
      clockChange: false, source: .google(event))
  }

  private static func timedOccurrence(
    _ event: GoogleCalendarEvent, date: String, span: TimedSpan, startDate: String, endDate: String
  ) -> DayOccurrence? {
    let start = span.start
    let end = span.end
    if startDate > date || endDate < date || (endDate == date && end.secondOfDay == 0) {
      return nil
    }
    let continued = startDate < date
    let startMinute = continued ? 0 : start.secondOfDay / 60
    let endMinute = endDate > date ? 1440 : (end.secondOfDay + 59) / 60
    // A backward clock change may put the wall-clock end before the start. Draw a positive
    // segment while keeping the actual endpoint labels.
    let drawnEnd = min(
      1440,
      max(
        startMinute + 1,
        endMinute > startMinute ? endMinute : startMinute + Int(span.exact.rounded(.up))))
    return DayOccurrence(
      key: "google:\(event.calendarId):\(event.id):\(date)", date: date, title: event.title,
      start: startMinute, end: drawnEnd, completed: event.googleTask?.status == "completed",
      allDay: false, busy: event.busy, continued: continued, duration: Int(span.exact.rounded()),
      startLabel: continued ? clock(0) : clock(start.minute),
      endLabel: endDate > date ? clock(1440) : clock(end.minute), clockChange: span.clockChange,
      source: .google(event))
  }
}
