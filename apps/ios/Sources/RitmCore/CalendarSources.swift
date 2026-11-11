import Foundation

/// A calendar the side menu can show or hide: a Google calendar (by its id) or one kind of Ritm
/// entry. The id is what the hidden set stores.
public struct CalendarSource: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let colorId: String?
  public let isRitm: Bool
}

/// What the user chose to hide, and the Google calendars seen so far (so a hidden calendar keeps
/// its row even while none of its events is in the loaded range). Stored on the phone.
public struct CalendarFilter: Codable, Sendable, Equatable {
  public var hidden: Set<String> = []
  /// Google calendar id to the colour ID of its events ("" for none).
  public var known: [String: String] = [:]

  public init(hidden: Set<String> = [], known: [String: String] = [:]) {
    self.hidden = hidden
    self.known = known
  }

  public mutating func toggle(_ id: String) {
    if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
  }

  /// Notes the calendars of `events`; true when anything new was learned.
  @discardableResult
  public mutating func remember(_ events: [GoogleCalendarEvent]) -> Bool {
    var changed = false
    for event in events {
      let color = event.colorId ?? ""
      if let current = known[event.calendarId] {
        if current.isEmpty && !color.isEmpty {
          known[event.calendarId] = color
          changed = true
        }
      } else {
        known[event.calendarId] = color
        changed = true
      }
    }
    return changed
  }
}

public enum CalendarSources {
  public static func key(_ event: GoogleCalendarEvent) -> String { "g:" + event.calendarId }
  public static func key(_ task: RitmTask) -> String { task.kind == .event ? ritmEvents : ritmTasks }
  public static let ritmTasks = "r:task"
  public static let ritmEvents = "r:event"

  /// The best name there is for a Google calendar: the API gives only its id, so the main one is
  /// recognised by `primary` or the account's e-mail, the holiday and birthday ones by their
  /// well-known ids, an e-mail-like id is shown as is and the rest are numbered.
  public static func name(calendarId: String, email: String, language: Language, ordinal: Int)
    -> String
  {
    let russian = language == .ru
    let id = calendarId.lowercased()
    if id == "primary" || (!email.isEmpty && id == email.lowercased()) {
      return russian ? "Основной календарь" : "Main calendar"
    }
    if id.contains("#holiday@") { return russian ? "Праздники" : "Holidays" }
    if id.contains("#contacts@") || id.contains("addressbook#") {
      return russian ? "Дни рождения" : "Birthdays"
    }
    if id.contains("@"), !id.hasSuffix("group.calendar.google.com"),
      !id.hasSuffix("group.v.calendar.google.com")
    {
      return calendarId
    }
    return (russian ? "Календарь " : "Calendar ") + String(ordinal)
  }

  /// The menu's list: the Google calendars (the main one first) and the kinds of Ritm entry that
  /// exist, each with the colour of its entries.
  public static func list(
    events: [GoogleCalendarEvent], tasks: [RitmTask], filter: CalendarFilter, email: String,
    language: Language
  ) -> [CalendarSource] {
    var colors = filter.known
    for event in events where (colors[event.calendarId] ?? "").isEmpty {
      colors[event.calendarId] = event.colorId ?? ""
    }
    let ids = colors.keys.sorted { left, right in
      let leftMain = isMain(left, email: email)
      let rightMain = isMain(right, email: email)
      return leftMain != rightMain ? leftMain : left < right
    }
    var google: [CalendarSource] = []
    for (index, id) in ids.enumerated() {
      let color = colors[id] ?? ""
      google.append(
        CalendarSource(
          id: "g:" + id,
          name: name(calendarId: id, email: email, language: language, ordinal: index + 1),
          colorId: color.isEmpty ? nil : color, isRitm: false))
    }
    let entries = tasks.filter { $0.calendarEntry != false }
    var ritm: [CalendarSource] = []
    if let first = entries.first(where: { $0.kind == .task }) {
      ritm.append(
        CalendarSource(
          id: ritmTasks, name: language == .ru ? "Задачи" : "Tasks", colorId: first.colorId,
          isRitm: true))
    }
    if let first = entries.first(where: { $0.kind == .event }) {
      ritm.append(
        CalendarSource(
          id: ritmEvents, name: language == .ru ? "События" : "Events", colorId: first.colorId,
          isRitm: true))
    }
    return google + ritm
  }

  private static func isMain(_ id: String, email: String) -> Bool {
    id == "primary" || (!email.isEmpty && id.lowercased() == email.lowercased())
  }

  /// The events and tasks left after the hidden calendars are taken out. Only ever applied to
  /// what is drawn: the loaded data itself is never filtered.
  public static func visible(_ events: [GoogleCalendarEvent], hidden: Set<String>)
    -> [GoogleCalendarEvent]
  {
    hidden.isEmpty ? events : events.filter { !hidden.contains(key($0)) }
  }

  public static func visible(_ tasks: [RitmTask], hidden: Set<String>) -> [RitmTask] {
    hidden.isEmpty ? tasks : tasks.filter { !hidden.contains(key($0)) }
  }

  /// True when the list has calendars and every one of them is hidden.
  public static func allHidden(_ sources: [CalendarSource], hidden: Set<String>) -> Bool {
    !sources.isEmpty && sources.allSatisfy { hidden.contains($0.id) }
  }
}
