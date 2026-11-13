import Foundation

/// Instants and wall-clock times for the day grid, worked out with plain integer arithmetic.
///
/// Reading a day of Google events used to create an `ISO8601DateFormatter` for every instant, a
/// `Calendar` for every wall-clock conversion and eleven more `dateComponents` calls for every
/// clock-change check, for every event on every redraw of a week. Those objects are slow to build
/// on a phone and were the bulk of the stall when the calendar changed its period. Everything
/// here allocates nothing and gives the same answers (the tests compare it with the Foundation
/// calls on many instants and zones).
enum CalendarInstants {
  /// A wall-clock time: the day as a number (days since 1970-01-01) and the second of that day.
  struct Wall: Equatable {
    let dayNumber: Int
    let secondOfDay: Int

    var minute: Int { secondOfDay / 60 }
    /// Wall-clock minutes since the epoch, ignoring the zone offset (the web's `…Z` trick).
    var epochMinutes: Int { dayNumber * 1440 + minute }
    /// `yyyy-MM-dd`.
    var date: String {
      HabitSchedule.key(forDays: dayNumber) ?? {
        let parts = HabitSchedule.civilFromDays(dayNumber)
        return String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
      }()
    }
  }

  // MARK: Reading an instant

  /// `2026-11-13T09:30:00+05:00`, `…00Z` or with fractional seconds. Anything unusual goes to the
  /// Foundation formatter, which is slow to build but is only asked for odd values.
  static func parse(_ value: String) -> Date? {
    var copy = value
    if let fast = copy.withUTF8({ parseFast($0) }) { return fast }
    return parseWithFormatter(value)
  }

  private static func parseWithFormatter(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private static func parseFast(_ bytes: UnsafeBufferPointer<UInt8>) -> Date? {
    guard bytes.count >= 20, bytes[4] == 45, bytes[7] == 45, bytes[10] == 84, bytes[13] == 58,
      bytes[16] == 58,
      let year = number(bytes, 0, 4), let month = number(bytes, 5, 2),
      let day = number(bytes, 8, 2), let hour = number(bytes, 11, 2),
      let minute = number(bytes, 14, 2), let second = number(bytes, 17, 2),
      year >= 1, (1...12).contains(month), day >= 1,
      day <= HabitSchedule.daysInMonth(year, month), hour < 24, minute < 60, second < 60
    else { return nil }
    var position = 19
    var fraction = 0.0
    if bytes[position] == 46 {
      var scale = 0.1
      position += 1
      let digitsFrom = position
      while position < bytes.count, (48...57).contains(bytes[position]) {
        fraction += Double(bytes[position] - 48) * scale
        scale /= 10
        position += 1
      }
      guard position > digitsFrom else { return nil }
    }
    guard let offset = zoneOffset(bytes, from: position) else { return nil }
    let days = HabitSchedule.daysFromCivil(year, month, day)
    let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
    return Date(timeIntervalSince1970: Double(seconds) + fraction)
  }

  /// `Z` or `±hh:mm` that ends the text; the offset in seconds.
  private static func zoneOffset(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
    guard start < bytes.count else { return nil }
    if bytes[start] == 90 { return start + 1 == bytes.count ? 0 : nil }
    guard start + 6 == bytes.count, bytes[start] == 43 || bytes[start] == 45,
      bytes[start + 3] == 58, let hours = number(bytes, start + 1, 2),
      let minutes = number(bytes, start + 4, 2), hours < 24, minutes < 60
    else { return nil }
    let seconds = hours * 3600 + minutes * 60
    return bytes[start] == 45 ? -seconds : seconds
  }

  private static func number(_ bytes: UnsafeBufferPointer<UInt8>, _ from: Int, _ count: Int) -> Int? {
    var result = 0
    for index in from..<(from + count) {
      let byte = bytes[index]
      guard (48...57).contains(byte) else { return nil }
      result = result * 10 + Int(byte - 48)
    }
    return result
  }

  // MARK: Wall-clock time

  /// The wall-clock time of `instant` in `zone`.
  static func wall(_ instant: Date, zone: TimeZone) -> Wall {
    let local = Int(instant.timeIntervalSince1970.rounded(.down)) + zone.secondsFromGMT(for: instant)
    let day = local >= 0 ? local / 86_400 : -((-local + 86_399) / 86_400)
    return Wall(dayNumber: day, secondOfDay: local - day * 86_400)
  }

  /// True when the same wall-clock time also occurs a short step away (a clock change makes the
  /// hour twice), tested the way the web editor does: at steps of up to two hours.
  static func isAmbiguous(_ instant: Date, zone: TimeZone) -> Bool {
    let current = zone.secondsFromGMT(for: instant)
    for minutes in [-120, -90, -60, -30, -15, 15, 30, 60, 90, 120] {
      let step = minutes * 60
      // Equal wall-clock times: `instant + step + offset(there) == instant + offset(here)`.
      if step + zone.secondsFromGMT(for: instant.addingTimeInterval(Double(step))) == current {
        return true
      }
    }
    return false
  }
}
