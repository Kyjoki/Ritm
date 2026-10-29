import Foundation
import XCTest

@testable import RitmCore

/// Mirrors CalendarPage.tsx, google-occurrences.ts, mobile-calendar-groups.ts, calendar-swipe.ts,
/// calendar-drag.ts and shared/calendar-colors.ts.
final class CalendarPlanTests: XCTestCase {
  private func entry(_ key: String, _ start: Int?, _ end: Int?, busy: Bool = true, allDay: Bool = false)
    -> DayOccurrence
  {
    let event = GoogleCalendarEvent(
      id: key, title: key, start: .init(date: "2026-10-29"), end: .init(date: "2026-10-30"),
      timeZone: "UTC", allDay: allDay, busy: busy)
    return DayOccurrence(
      key: key, date: "2026-10-29", title: key, start: start, end: end, completed: false,
      allDay: allDay, busy: busy, continued: false, duration: (end ?? 0) - (start ?? 0),
      startLabel: nil, endLabel: nil, clockChange: false, source: .google(event))
  }

  func testLayoutSharesLanesWithinAnOverlapGroupOnly() {
    let placed = CalendarPlan.layout([
      entry("a", 540, 600), entry("b", 560, 620), entry("c", 600, 660), entry("d", 700, 720),
    ])
    let byKey = Dictionary(uniqueKeysWithValues: placed.map { ($0.entry.key, $0) })
    XCTAssertEqual(byKey["a"]?.lane, 0)
    XCTAssertEqual(byKey["b"]?.lane, 1)
    XCTAssertEqual(byKey["c"]?.lane, 0, "c starts when a ends, so it reuses lane 0")
    XCTAssertEqual(byKey["a"]?.lanes, 2)
    XCTAssertEqual(byKey["c"]?.lanes, 2)
    XCTAssertEqual(byKey["d"]?.lanes, 1)
  }

  func testMobileGroupsJoinOverlapsButNotTouchingEntries() {
    let groups = CalendarPlan.overlapGroups([
      entry("a", 540, 600), entry("b", 590, 630), entry("c", 630, 660), entry("all", nil, nil, allDay: true),
    ])
    XCTAssertEqual(groups.map { $0.map(\.key) }, [["a", "b"], ["c"]])
  }

  func testFreeIntervalsBetweenEightAndEight() {
    let free = CalendarPlan.freeIntervals([entry("a", 600, 660), entry("idle", 700, 800, busy: false)])
    XCTAssertEqual(free.map(\.start), [480, 660])
    XCTAssertEqual(free.map(\.end), [600, 1200])
    XCTAssertTrue(CalendarPlan.freeIntervals([entry("trip", nil, nil, allDay: true)]).isEmpty)
    // Gaps shorter than 30 minutes are not offered.
    XCTAssertEqual(CalendarPlan.freeIntervals([entry("a", 495, 1100)]).map(\.start), [1100])
    XCTAssertTrue(CalendarPlan.freeIntervals([entry("a", 500, 1190)]).isEmpty)
  }

  func testWeekSwipeNeedsADeliberateHorizontalGesture() {
    XCTAssertEqual(CalendarPlan.weekSwipe(dx: -80, dy: 10, elapsed: 0.3, width: 366), 1)
    XCTAssertEqual(CalendarPlan.weekSwipe(dx: 80, dy: 10, elapsed: 0.3, width: 366), -1)
    XCTAssertEqual(CalendarPlan.weekSwipe(dx: 40, dy: 5, elapsed: 0.05, width: 366), -1, "a fast flick")
    XCTAssertEqual(CalendarPlan.weekSwipe(dx: 40, dy: 5, elapsed: 0.5, width: 366), 0)
    XCTAssertEqual(CalendarPlan.weekSwipe(dx: 90, dy: 60, elapsed: 0.3, width: 366), 0, "too diagonal")
    XCTAssertEqual(CalendarPlan.weekSwipe(dx: 90, dy: 0, elapsed: 1.3, width: 366), 0, "too slow")
  }

  func testDragSnapsToQuarterHoursAndStaysInTheDay() {
    XCTAssertEqual(CalendarPlan.snappedStart(rawMinutes: 547, duration: 60), 540)
    XCTAssertEqual(CalendarPlan.snappedStart(rawMinutes: 553, duration: 60), 555)
    XCTAssertEqual(CalendarPlan.snappedStart(rawMinutes: -20, duration: 60), 0)
    XCTAssertEqual(CalendarPlan.snappedStart(rawMinutes: 1430, duration: 50), 1380)
  }

  func testMonthHasFortyTwoDaysFromTheSundayBeforeTheFirst() {
    let days = CalendarPlan.monthDays(containing: "2026-10-29")
    XCTAssertEqual(days.count, 42)
    XCTAssertEqual(days.first, "2026-09-27")
    XCTAssertEqual(days.last, "2026-11-07")
  }

  func testLabelsMatchTheWeb() {
    XCTAssertEqual(CalendarPlan.hourLabel(0), "12AM")
    XCTAssertEqual(CalendarPlan.hourLabel(13), "1PM")
    XCTAssertEqual(CalendarPlan.compactLabel("9:00 AM"), "9 AM")
    XCTAssertEqual(CalendarPlan.compactLabel("9:30 AM"), "9:30 AM")
    XCTAssertEqual(CalendarPlan.recordWord(1, language: .ru), "запись")
    XCTAssertEqual(CalendarPlan.recordWord(3, language: .ru), "записи")
    XCTAssertEqual(CalendarPlan.recordWord(11, language: .ru), "записей")
    XCTAssertEqual(CalendarPlan.recordWord(2, language: .en), "entries")
  }

  func testEntryColoursUseTheSoftPaletteForGoogleIDs() {
    XCTAssertEqual(CalendarPlan.entryHex("4"), "d38a8a")
    XCTAssertEqual(CalendarPlan.entryHex("11"), "c85d55")
    XCTAssertEqual(CalendarPlan.entryHex("#3F51B5"), "3f51b5")
    XCTAssertNil(CalendarPlan.entryHex(nil), "no colour falls back to the accent")
    XCTAssertNil(CalendarPlan.entryHex("unknown"))
  }
}
