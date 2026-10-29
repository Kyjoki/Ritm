import Foundation

/// An entry placed in its overlap group: `lane` of `lanes` equal columns.
public struct PlacedOccurrence: Sendable, Equatable, Identifiable {
  public let entry: DayOccurrence
  public let start: Int
  public let end: Int
  public let lane: Int
  public let lanes: Int
  public var id: String { entry.key }
}

public struct FreeInterval: Sendable, Equatable {
  public let start: Int
  public let end: Int
}

/// Rules behind the calendar screen (CalendarPage.tsx and its helpers).
public enum CalendarPlan {
  /// `CALENDAR_GRID_METRICS.mobile`.
  public static let hourHeight = 48.0
  public static let timeColumn = 40.0
  public static let initialHour = 9

  /// `layoutCalendarOccurrences`: overlapping timed entries share equal lanes.
  public static func layout(_ entries: [DayOccurrence]) -> [PlacedOccurrence] {
    let timed = entries.compactMap { entry -> (DayOccurrence, Int, Int)? in
      guard let start = entry.start, let end = entry.end else { return nil }
      return (entry, start, end)
    }
    .stableSorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 > $1.2 }
    var result: [PlacedOccurrence] = []
    var group: [(DayOccurrence, Int, Int, Int)] = []
    var laneEnds: [Int] = []
    var groupEnd = -1
    func finish() {
      result += group.map {
        PlacedOccurrence(entry: $0.0, start: $0.1, end: $0.2, lane: $0.3, lanes: laneEnds.count)
      }
      group = []
      laneEnds = []
      groupEnd = -1
    }
    for (entry, start, end) in timed {
      if !group.isEmpty && start >= groupEnd { finish() }
      let lane = laneEnds.firstIndex { $0 <= start } ?? laneEnds.count
      if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
      group.append((entry, start, end, lane))
      groupEnd = max(groupEnd, end)
    }
    finish()
    return result
  }

  /// `mobileCalendarGroups`: connected overlaps form one group; touching entries stay apart.
  public static func overlapGroups(_ entries: [DayOccurrence]) -> [[DayOccurrence]] {
    let timed = entries.filter { !$0.allDay && $0.start != nil && $0.end != nil }
      .stableSorted { a, b in
        if a.start != b.start { return (a.start ?? 0) < (b.start ?? 0) }
        if a.end != b.end { return (a.end ?? 0) < (b.end ?? 0) }
        return a.key < b.key
      }
    var groups: [[DayOccurrence]] = []
    var groupEnd = 0
    for entry in timed {
      let start = entry.start ?? 0
      let end = entry.end ?? 0
      if !groups.isEmpty && start < groupEnd {
        groups[groups.count - 1].append(entry)
        groupEnd = max(groupEnd, end)
      } else {
        groups.append([entry])
        groupEnd = end
      }
    }
    return groups
  }

  /// Free windows of at least 30 minutes between 8 AM and 8 PM; a busy all-day entry leaves none.
  public static func freeIntervals(_ entries: [DayOccurrence]) -> [FreeInterval] {
    if entries.contains(where: { $0.allDay && $0.busy }) { return [] }
    var cursor = 8 * 60
    var intervals: [FreeInterval] = []
    for entry in entries {
      guard entry.busy, let start = entry.start, let end = entry.end else { continue }
      let from = max(8 * 60, start)
      if from - cursor >= 30 { intervals.append(FreeInterval(start: cursor, end: min(from, 20 * 60))) }
      cursor = max(cursor, end)
      if cursor >= 20 * 60 { break }
    }
    if cursor < 20 * 60 { intervals.append(FreeInterval(start: cursor, end: 20 * 60)) }
    return intervals.filter { $0.end - $0.start >= 30 }
  }

  /// `calendarWeekSwipe`: 1 for the next week, -1 for the previous one, 0 for anything else.
  public static func weekSwipe(dx: Double, dy: Double, elapsed: TimeInterval, width: Double) -> Int {
    let milliseconds = elapsed * 1000
    let farEnough = abs(dx) >= max(56, width * 0.16)
    let flick = abs(dx) >= 32 && abs(dx / max(milliseconds, 1)) >= 0.55
    guard milliseconds >= 0, milliseconds <= 1200, farEnough || flick, abs(dx) >= abs(dy) * 1.8
    else { return 0 }
    return dx < 0 ? 1 : -1
  }

  /// `calendarDragTarget`: starts snap to 15 minutes and the entry must end by midnight.
  public static func snappedStart(rawMinutes: Double, duration: Int) -> Int {
    let latest = max(0, (1440 - duration) / 15 * 15)
    let snapped = Int((rawMinutes / 15).rounded()) * 15
    return max(0, min(latest, snapped))
  }

  /// 42 days from the Sunday on or before the first of the month.
  public static func monthDays(containing date: String) -> [String] {
    guard let first = TaskSchedule.startOfMonth(date),
      let sunday = HabitSchedule.week(containing: first).first
    else { return [] }
    return (0..<42).compactMap { HabitSchedule.addDays(to: sunday, days: $0) }
  }

  /// The hour column: "9AM".
  public static func hourLabel(_ hour: Int) -> String {
    DayPlan.clock(hour * 60, compact: true).replacingOccurrences(of: " ", with: "")
  }

  /// `entryTime`: a whole hour drops its minutes ("9:00 AM" → "9 AM").
  public static func compactLabel(_ label: String) -> String {
    label.replacingOccurrences(of: #":00(?=\s[AP]M$)"#, with: "", options: .regularExpression)
  }

  public static func entryTime(_ entry: DayOccurrence, start: Bool) -> String {
    let label = start ? entry.startLabel : entry.endLabel
    if let label { return compactLabel(label) }
    return DayPlan.clock((start ? entry.start : entry.end) ?? 0, compact: true)
  }

  /// `recordWord`.
  public static func recordWord(_ count: Int, language: Language) -> String {
    guard language == .ru else { return count == 1 ? "entry" : "entries" }
    let lastTwo = count % 100
    let last = count % 10
    if last == 1 && lastTwo != 11 { return "запись" }
    if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "записи" }
    return "записей"
  }

  /// `shared/calendar-colors.ts`: Google colour IDs use Ritm's softened swatches, a custom
  /// colour is used as is, and nil means the accent colour.
  public static func entryHex(_ id: String?) -> String? {
    guard let id else { return nil }
    if id.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil {
      return id.dropFirst().lowercased()
    }
    return softColors[id]
  }

  private static let softColors = [
    "1": "8586c9", "2": "68ab92", "3": "a77bb8", "4": "d38a8a", "5": "c8a84c", "6": "cf8a61",
    "7": "659daf", "8": "8a8580", "9": "5862b5", "10": "63a377", "11": "c85d55",
  ]
}
