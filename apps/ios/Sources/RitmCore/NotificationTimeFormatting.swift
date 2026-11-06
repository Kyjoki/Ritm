import Foundation

/// Compact Calendar-style text. The account's zone controls the clocks; the app's calendar
/// screens keep their own display preferences. This never changes the notification deadline.
enum NotificationTimeFormatting {
  static func range(start: Date, end: Date?, timeZone: TimeZone, language: Language,
    relativeTo reference: Date? = nil) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    func clock(_ date: Date) -> String {
      let parts = calendar.dateComponents([.hour, .minute], from: date)
      return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    let otherStartDay = reference.map { !calendar.isDate(start, inSameDayAs: $0) } ?? false
    func dateLabel(_ date: Date, end: Date) -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_GB")
      formatter.calendar = calendar
      formatter.timeZone = timeZone
      let year = calendar.component(.year, from: start)
      let needsYear = calendar.component(.year, from: end) != year
        || reference.map { calendar.component(.year, from: $0) != year } == true
      formatter.dateFormat = needsYear ? "d MMM yyyy" : "d MMM"
      return formatter.string(from: date)
    }
    guard let end, end > start else {
      return (otherStartDay ? dateLabel(start, end: start) + ", " : "") + clock(start)
    }
    let crossesOffset = timeZone.secondsFromGMT(for: start) != timeZone.secondsFromGMT(for: end)
    func time(_ date: Date) -> String {
      clock(date) + (crossesOffset ? " " + offset(timeZone.secondsFromGMT(for: date)) : "")
    }
    if calendar.isDate(start, inSameDayAs: end) {
      return (otherStartDay ? dateLabel(start, end: end) + ", " : "") + "\(time(start))–\(time(end))"
    }

    // A multi-day event must not look like a short event with the same pair of clock times.
    return "\(dateLabel(start, end: end)), \(time(start))–\(dateLabel(end, end: end)), \(time(end))"
  }

  private static func offset(_ seconds: Int) -> String {
    let minutes = abs(seconds) / 60
    return "UTC" + (seconds >= 0 ? "+" : "-") + String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }
}
