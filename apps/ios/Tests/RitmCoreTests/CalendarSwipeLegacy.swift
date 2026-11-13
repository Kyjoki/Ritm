import Foundation

@testable import RitmCore

/// The way the calendar read instants and wall-clock times before the swipe pass: a Foundation
/// formatter and a `Calendar` for every call. Kept here, unchanged, as the reference the integer
/// arithmetic of `CalendarInstants` and the one-pass reading of `DayPlan` are compared with, and
/// as the baseline of the timing checks.
enum CalendarSwipeLegacy {
  static func instant(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  static func calendar(_ zone: TimeZone) -> Calendar {
    var result = Calendar(identifier: .gregorian)
    result.locale = Locale(identifier: "en_US_POSIX")
    result.timeZone = zone
    return result
  }

  static func isAmbiguous(_ instant: Date, zone: TimeZone) -> Bool {
    let calendar = calendar(zone)
    let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    let current = calendar.dateComponents(components, from: instant)
    for offset in [-120, -90, -60, -30, -15, 15, 30, 60, 90, 120] {
      let other = instant.addingTimeInterval(Double(offset * 60))
      if calendar.dateComponents(components, from: other) == current { return true }
    }
    return false
  }

  struct Wall {
    let date: String
    let minute: Int
    let seconds: Int
  }

  static func wall(_ instant: Date, zone: TimeZone) -> Wall {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = zone
    let parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: instant)
    let hour = parts.hour ?? 0
    let minute = parts.minute ?? 0
    return Wall(
      date: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
      minute: hour * 60 + minute, seconds: (hour * 60 + minute) * 60 + (parts.second ?? 0))
  }

  static func wallMinutes(_ value: Wall) -> Int? {
    let parts = value.date.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard
      let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else { return nil }
    return Int(day.timeIntervalSince1970 / 60) + value.minute
  }

  /// `wallSpan` of the old batch reading: what it computed for every event of every call.
  static func wallSpan(_ event: GoogleCalendarEvent, zone: TimeZone) -> (first: String, last: String)? {
    if event.allDay {
      guard let start = event.start.date, let end = event.end.date else { return nil }
      return (start, end)
    }
    guard let startInstant = instant(event.start.dateTime),
      let endInstant = instant(event.end.dateTime), endInstant > startInstant
    else { return nil }
    return (wall(startInstant, zone: zone).date, wall(endInstant, zone: zone).date)
  }

  static func timedOccurrence(_ event: GoogleCalendarEvent, date: String, zone: TimeZone)
    -> DayOccurrence?
  {
    guard let startInstant = instant(event.start.dateTime),
      let endInstant = instant(event.end.dateTime), endInstant > startInstant
    else { return nil }
    let start = wall(startInstant, zone: zone)
    let end = wall(endInstant, zone: zone)
    if start.date > date || end.date < date || (end.date == date && end.seconds == 0) {
      return nil
    }
    let continued = start.date < date
    let startMinute = continued ? 0 : start.seconds / 60
    let endMinute = end.date > date ? 1440 : (end.seconds + 59) / 60
    let exact = endInstant.timeIntervalSince(startInstant) / 60
    let wallDuration = (wallMinutes(end) ?? 0) - (wallMinutes(start) ?? 0)
    let clockChange =
      abs(Double(wallDuration) - exact) >= 1 || isAmbiguous(startInstant, zone: zone)
      || isAmbiguous(endInstant, zone: zone)
    let drawnEnd = min(
      1440,
      max(startMinute + 1, endMinute > startMinute ? endMinute : startMinute + Int(exact.rounded(.up))))
    return DayOccurrence(
      key: "google:\(event.calendarId):\(event.id):\(date)", date: date, title: event.title,
      start: startMinute, end: drawnEnd, completed: event.googleTask?.status == "completed",
      allDay: false, busy: event.busy, continued: continued, duration: Int(exact.rounded()),
      startLabel: continued ? DayPlan.clock(0) : DayPlan.clock(start.minute),
      endLabel: end.date > date ? DayPlan.clock(1440) : DayPlan.clock(end.minute),
      clockChange: clockChange, source: .google(event))
  }

  /// The old per-call cost of a batch: every event's span read again, as `prepare` did for each
  /// single day of a week it was asked for one by one.
  static func spansCost(_ events: [GoogleCalendarEvent], zone: TimeZone) -> Int {
    events.reduce(0) { $0 + (wallSpan($1, zone: zone) == nil ? 0 : 1) }
  }

  /// The old `TaskSchedule.occursOn`.
  static func occursOn(_ task: RitmTask, date target: String) -> Bool {
    func date(_ key: String) -> Date? {
      guard HabitSchedule.isValidDate(key) else { return nil }
      let parts = key.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3 else { return nil }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      calendar.locale = Locale(identifier: "en_US_POSIX")
      return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
    var calendar: Calendar {
      var value = Calendar(identifier: .gregorian)
      value.timeZone = TimeZone(secondsFromGMT: 0)!
      value.locale = Locale(identifier: "en_US_POSIX")
      return value
    }
    guard let originKey = task.date, originKey <= target, let origin = date(originKey),
      let targetDate = date(target)
    else { return false }
    switch task.repeat {
    case .none: return originKey == target
    case .daily: return true
    case .weekly:
      return calendar.component(.weekday, from: origin) == calendar.component(.weekday, from: targetDate)
    case .monthly:
      return calendar.component(.day, from: origin) == calendar.component(.day, from: targetDate)
    }
  }
}
