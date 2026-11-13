import Foundation

/// What the redesigned calendar draws: saturated entry colours with a readable ink, the bars of a
/// month cell and the search over entries.
extension CalendarPlan {
  /// Google's own event colours for the colour IDs, a custom `#rrggbb` as is, nil for the accent.
  /// Unlike `entryHex` these are the full-strength swatches the solid blocks are filled with.
  public static func solidHex(_ id: String?) -> String? {
    guard let id else { return nil }
    if isHexColor(id) { return id.dropFirst().lowercased() }
    return solidColors[id]
  }

  /// `#rrggbb`, checked byte by byte: this runs for every block on every redraw, and a regular
  /// expression is compiled each time it is used this way.
  static func isHexColor(_ id: String) -> Bool {
    let bytes = id.utf8
    guard bytes.count == 7, bytes.first == 35 else { return false }
    return bytes.dropFirst().allSatisfy {
      (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
    }
  }

  private static let solidColors = [
    "1": "7986cb", "2": "33b679", "3": "8e24aa", "4": "e67c73", "5": "f6bf26", "6": "f4511e",
    "7": "039be5", "8": "616161", "9": "3f51b5", "10": "0b8043", "11": "d50000",
  ]

  /// WCAG relative luminance of `rrggbb`, 0 for anything unreadable.
  public static func luminance(hex: String) -> Double {
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return 0 }
    func channel(_ shift: UInt32) -> Double {
      let part = Double((value >> shift) & 255) / 255
      return part <= 0.03928 ? part / 12.92 : pow((part + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
  }

  /// White text stays on every saturated block unless its contrast would drop below 2.2: only
  /// the yellows and limes then take the dark ink.
  public static func prefersDarkInk(hex: String) -> Bool {
    1.05 / (luminance(hex: hex) + 0.05) < 2.2
  }

  /// The bars one month cell draws: all-day and untimed entries first, then by start, at most
  /// `limit` rows. When more do not fit, the last row is the «+N» counter: `more` entries hide
  /// behind it and `shown` has `limit - 1` entries.
  public static func monthBars(_ entries: [DayOccurrence], limit: Int)
    -> (shown: [DayOccurrence], more: Int)
  {
    let ordered = entries.stableSorted { left, right in
      let leftUntimed = left.start == nil || left.allDay
      let rightUntimed = right.start == nil || right.allDay
      if leftUntimed != rightUntimed { return leftUntimed }
      return (left.start ?? 0) < (right.start ?? 0)
    }
    guard limit > 0 else { return ([], ordered.count) }
    guard ordered.count > limit else { return (ordered, 0) }
    let shown = Array(ordered.prefix(limit - 1))
    return (shown, ordered.count - shown.count)
  }
}

/// One day's entry, for the search list.
public struct CalendarSearchHit: Sendable, Equatable, Identifiable {
  public let date: String
  public let entry: DayOccurrence
  public var id: String { entry.key }
}

public enum CalendarSearch {
  /// Lower case with «ё» read as «е», so a query typed either way finds both.
  public static func normalized(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "ё", with: "е")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The entries of `days` (date, entries) whose title contains `query`, earliest first. A part
  /// that only continues an entry from the previous day is skipped. An empty query finds nothing.
  public static func hits(
    in days: [(date: String, entries: [DayOccurrence])], query: String, limit: Int = 25
  ) -> [CalendarSearchHit] {
    let needle = normalized(query)
    guard !needle.isEmpty, limit > 0 else { return [] }
    var result: [CalendarSearchHit] = []
    for day in days.sorted(by: { $0.date < $1.date }) {
      let matching = day.entries.filter {
        !$0.continued && normalized($0.title).contains(needle)
      }
      for entry in matching.stableSorted(by: { ($0.start ?? -1) < ($1.start ?? -1) }) {
        result.append(CalendarSearchHit(date: day.date, entry: entry))
        if result.count == limit { return result }
      }
    }
    return result
  }
}
