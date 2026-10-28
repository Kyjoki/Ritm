import Foundation

/// Only expose the simple event editor when it can round-trip the original
/// interval in the account time zone without losing dates or DST information.
public enum CalendarEventPolicy {
  public static func hasClockChange(_ event: GoogleCalendarEvent, timeZone: String) -> Bool {
    guard !event.allDay, let zone = TimeZone(identifier: timeZone),
      let start = instant(event.start.dateTime), let end = instant(event.end.dateTime), end > start
    else { return false }
    return zone.secondsFromGMT(for: start) != zone.secondsFromGMT(for: end)
      || isAmbiguous(start, zone: zone) || isAmbiguous(end, zone: zone)
  }

  public static func canEdit(_ event: GoogleCalendarEvent, timeZone: String) -> Bool {
    guard !event.readOnly, event.taskLink != true, let zone = TimeZone(identifier: timeZone) else {
      return false
    }
    if event.allDay {
      guard let start = event.start.date, HabitSchedule.isValidDate(start) else { return false }
      return event.end.date == HabitSchedule.addDays(to: start, days: 1)
    }
    guard let start = instant(event.start.dateTime), let end = instant(event.end.dateTime) else {
      return false
    }
    let duration = end.timeIntervalSince(start) / 60
    guard duration >= 5, duration <= 720, duration.rounded() == duration else { return false }
    let calendar = calendar(zone)
    guard calendar.component(.second, from: start) == 0, calendar.component(.second, from: end) == 0
    else { return false }
    let startKey = HabitSchedule.dateKey(start, timeZone: timeZone)
    let endKey = HabitSchedule.dateKey(end, timeZone: timeZone)
    guard
      startKey == endKey
        || (endKey == HabitSchedule.addDays(to: startKey, days: 1)
          && time(end, zone: zone) == "00:00")
    else { return false }
    guard zone.secondsFromGMT(for: start) == zone.secondsFromGMT(for: end) else { return false }
    return !isAmbiguous(start, zone: zone) && !isAmbiguous(end, zone: zone)
  }

  public static func draft(_ event: GoogleCalendarEvent, timeZone: String) -> GoogleEventInput? {
    guard canEdit(event, timeZone: timeZone), let zone = TimeZone(identifier: timeZone) else {
      return nil
    }
    if event.allDay, let date = event.start.date {
      return GoogleEventInput(
        title: event.title, description: event.description, date: date,
        duration: 60, allDay: true, colorId: event.colorId, preservesProviderColor: true)
    }
    guard let start = instant(event.start.dateTime), let end = instant(event.end.dateTime) else {
      return nil
    }
    return GoogleEventInput(
      title: event.title, description: event.description,
      date: HabitSchedule.dateKey(start, timeZone: timeZone), time: time(start, zone: zone),
      duration: Int(end.timeIntervalSince(start) / 60), allDay: false, colorId: event.colorId,
      preservesProviderColor: true)
  }

  private static func calendar(_ zone: TimeZone) -> Calendar {
    var result = Calendar(identifier: .gregorian)
    result.locale = Locale(identifier: "en_US_POSIX")
    result.timeZone = zone
    return result
  }

  private static func time(_ date: Date, zone: TimeZone) -> String {
    let parts = calendar(zone).dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }

  private static func instant(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private static func isAmbiguous(_ instant: Date, zone: TimeZone) -> Bool {
    let calendar = calendar(zone)
    let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    let current = calendar.dateComponents(components, from: instant)
    // Matches the web editor, including thirty-minute DST regions.
    for offset in [-120, -90, -60, -30, -15, 15, 30, 60, 90, 120] {
      let other = instant.addingTimeInterval(Double(offset * 60))
      if calendar.dateComponents(components, from: other) == current { return true }
    }
    return false
  }
}
