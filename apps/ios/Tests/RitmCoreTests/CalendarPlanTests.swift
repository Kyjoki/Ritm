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

  func testDragTargetKeepsTheGrabPointAndSnapsToQuarterHours() {
    // 7 columns of 50 pt after a 40 pt time column, 48 pt per hour.
    func target(_ x: Double, _ y: Double, grab: Double = 10, duration: Int = 60) -> CalendarPlan.DragTarget {
      CalendarPlan.dragTarget(
        x: x, y: y, grabY: grab, column: 50, timeColumn: 40, days: 7, hourHeight: 48,
        duration: duration)
    }
    // Card top at 9:00 is y = 432; a finger 10 pt below it is at 442.
    XCTAssertEqual(target(65, 442), CalendarPlan.DragTarget(dayIndex: 0, minutes: 540))
    XCTAssertEqual(target(165, 442 + 12), CalendarPlan.DragTarget(dayIndex: 2, minutes: 555), "12 pt = 15 min")
    XCTAssertEqual(target(165, 442 + 5), CalendarPlan.DragTarget(dayIndex: 2, minutes: 540), "snaps back under 7.5 min")
    XCTAssertEqual(target(5, -50).dayIndex, 0, "left of the grid stays on the first day")
    XCTAssertEqual(target(5, -50).minutes, 0)
    XCTAssertEqual(target(900, 5000).dayIndex, 6, "right of the grid stays on the last day")
    XCTAssertEqual(target(900, 5000, duration: 90).minutes, 1350, "ends by midnight")
  }

  func testEntryHitTestUsesTheLaneFrames() {
    let placed = CalendarPlan.layout([entry("a", 540, 600), entry("b", 560, 620), entry("c", 700, 710)])
    let a = CalendarPlan.entryFrame(placed.first { $0.entry.key == "a" }!, column: 100, hourHeight: 48)
    XCTAssertEqual(a.x, 1)
    XCTAssertEqual(a.width, 48, "two lanes share 100 pt, minus 2")
    XCTAssertEqual(a.y, 434)
    XCTAssertEqual(
      CalendarPlan.entry(at: 20, y: 440, in: placed, column: 100, hourHeight: 48)?.entry.key, "a")
    XCTAssertEqual(
      CalendarPlan.entry(at: 80, y: 480, in: placed, column: 100, hourHeight: 48)?.entry.key, "b")
    XCTAssertNil(CalendarPlan.entry(at: 20, y: 100, in: placed, column: 100, hourHeight: 48))
    let short = CalendarPlan.entryFrame(placed.first { $0.entry.key == "c" }!, column: 100, hourHeight: 48)
    XCTAssertEqual(short.height, 22, "short entries keep a 22 pt hit area")
  }

  func testDragEdgesAndAutoScroll() {
    XCTAssertEqual(CalendarPlan.dragWeekEdge(x: 10, width: 390), -1)
    XCTAssertEqual(CalendarPlan.dragWeekEdge(x: 380, width: 390), 1)
    XCTAssertEqual(CalendarPlan.dragWeekEdge(x: 200, width: 390), 0)
    XCTAssertEqual(CalendarPlan.dragScrollSpeed(y: 300, height: 600), 0)
    XCTAssertLessThan(CalendarPlan.dragScrollSpeed(y: 20, height: 600), 0)
    XCTAssertGreaterThan(CalendarPlan.dragScrollSpeed(y: 590, height: 600), 0)
    XCTAssertEqual(CalendarPlan.dragScrollSpeed(y: -30, height: 600), -CalendarPlan.dragScrollMaxSpeed)
    XCTAssertLessThan(
      abs(CalendarPlan.dragScrollSpeed(y: 50, height: 600)),
      abs(CalendarPlan.dragScrollSpeed(y: 10, height: 600)), "faster nearer the edge")
    XCTAssertEqual(CalendarPlan.dragScrollSpeed(y: 10, height: 80), 0, "a tiny viewport never scrolls")
  }

  func testReleaseOutsideTheGridCancels() {
    XCTAssertTrue(CalendarPlan.isInside(x: 100, y: 100, width: 390, height: 500))
    XCTAssertFalse(CalendarPlan.isInside(x: 100, y: -4, width: 390, height: 500))
    XCTAssertFalse(CalendarPlan.isInside(x: 400, y: 100, width: 390, height: 500))
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
