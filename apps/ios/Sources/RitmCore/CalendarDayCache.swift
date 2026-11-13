import Foundation

/// The days the hour grid has read, each with a `stamp` that changes only when what the day shows
/// changes. When the data is replaced the old days are kept aside; a day that is read again and
/// comes out the same takes its old entry back, stamp included, so the views drawn from the stamp
/// do not draw it again. A Google read that only added events far from the visible week then
/// costs the visible week nothing.
public struct CalendarDayCache: Sendable {
  public struct Entry: Sendable, Equatable {
    public let data: CalendarDayData
    public let stamp: Int
  }

  private var days: [String: Entry] = [:]
  /// The days of the data before the last `invalidate`, kept only for the comparison.
  private var stale: [String: Entry] = [:]
  private var lastStamp = 0

  public init() {}

  /// The data changed: every day has to be read again.
  public mutating func invalidate() {
    if !days.isEmpty { stale = days }
    days = [:]
  }

  public func entry(_ day: String) -> Entry? { days[day] }

  /// The days of `requested` that are not read yet.
  public func missing(_ requested: [String]) -> [String] { requested.filter { days[$0] == nil } }

  /// Takes in freshly read days. Days already held are kept as they are.
  public mutating func ingest(_ read: [String: CalendarDayData]) {
    for (day, data) in read where days[day] == nil {
      if let old = stale[day], old.data.entries == data.entries {
        days[day] = old
      } else {
        lastStamp += 1
        days[day] = Entry(data: data, stamp: lastStamp)
      }
    }
  }
}
