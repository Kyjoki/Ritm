import Foundation

/// The full timestamp Shortcuts can give for a payment (`at=`): ISO 8601, `2026-10-30 14:05:09`,
/// `30.10.2026, 14:05`, `30 октября 2026 г. в 14:05:09`, `October 30, 2026 at 2:05 PM`. The wall
/// clock time as written is kept; a time zone suffix is ignored. It only tells two purchases of the
/// same day apart, so it goes into the purchase id.
enum WalletTimestamp {
  struct Parts: Equatable, Sendable {
    /// YYYY-MM-DD.
    let date: String
    /// HH:mm:ss, nil when the text has no time.
    let time: String?
  }

  static let maxLength = 40

  /// `YYYY-MM-DD HH:mm:ss` when the text has a date and a time; otherwise the cleaned text, cut to
  /// `maxLength` characters.
  static func normalise(_ text: String) -> String {
    if let parts = parts(text), let time = parts.time { return "\(parts.date) \(time)" }
    return WalletText.clean(text, limit: maxLength)
  }

  static func parts(_ text: String) -> Parts? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    for shape in shapes {
      guard let groups = captures(shape.pattern, in: value) else { continue }
      if let parts = shape.build(groups) { return parts }
    }
    return nil
  }

  // MARK: - Shapes

  private struct Shape: Sendable {
    let pattern: String
    let build: @Sendable ([String?]) -> Parts?
  }

  private static let clock = #"(?:[T,\s]+(?:в\s+|at\s+)?(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*([AaPp][Mm])?"#

  /// Groups 1...3 are the date, 4...7 the optional hour, minute, second and AM/PM.
  private static let shapes: [Shape] = [
    Shape(pattern: #"^(\d{4})-(\d{2})-(\d{2})"# + clock) { g in
      make(year: g[0], month: g[1], day: g[2], clock: Array(g[3...]))
    },
    Shape(pattern: #"^(\d{1,2})[./](\d{1,2})[./](\d{4})"# + clock) { g in
      make(year: g[2], month: g[1], day: g[0], clock: Array(g[3...]))
    },
    Shape(pattern: #"^(\d{1,2})\s+(\p{L}+)\.?,?\s+(\d{4})(?:\s*г\.?)?"# + clock) { g in
      make(year: g[2], month: monthNumber(g[1]), day: g[0], clock: Array(g[3...]))
    },
    Shape(pattern: #"^(\p{L}+)\.?\s+(\d{1,2}),?\s+(\d{4})"# + clock) { g in
      make(year: g[2], month: monthNumber(g[0]), day: g[1], clock: Array(g[3...]))
    },
  ]

  private static let months: [String: Int] = [
    "янв": 1, "фев": 2, "мар": 3, "апр": 4, "мая": 5, "май": 5, "июн": 6, "июл": 7, "авг": 8,
    "сен": 9, "окт": 10, "ноя": 11, "дек": 12,
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9,
    "oct": 10, "nov": 11, "dec": 12,
  ]

  private static func monthNumber(_ name: String?) -> String? {
    guard let name, let number = months[String(name.lowercased().prefix(3))] else { return nil }
    return String(number)
  }

  private static func make(
    year: String?, month: String?, day: String?, clock: [String?]
  ) -> Parts? {
    guard let year = year.flatMap({ Int($0) }), let month = month.flatMap({ Int($0) }),
      let day = day.flatMap({ Int($0) }),
      let date = WalletDate.format(year: year, month: month, day: day)
    else { return nil }
    guard let hourText = clock.first ?? nil else { return Parts(date: date, time: nil) }
    guard var hour = Int(hourText), let minute = clock[1].flatMap({ Int($0) }),
      (0...59).contains(minute)
    else { return nil }
    let second = clock[2].flatMap { Int($0) } ?? 0
    if let meridiem = (clock[3] ?? nil)?.lowercased() {
      guard (1...12).contains(hour) else { return nil }
      hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
    }
    guard (0...23).contains(hour), (0...59).contains(second) else { return nil }
    return Parts(date: date, time: String(format: "%02d:%02d:%02d", hour, minute, second))
  }

  /// Capture groups of the first match (nil for a group that did not take part).
  private static func captures(_ pattern: String, in text: String) -> [String?]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return (1..<match.numberOfRanges).map { index in
      let range = match.range(at: index)
      guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
        return nil
      }
      return String(text[swiftRange])
    }
  }
}
