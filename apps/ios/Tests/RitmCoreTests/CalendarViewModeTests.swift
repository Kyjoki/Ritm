import Foundation
import XCTest

@testable import RitmCore

/// The view modes of the redesigned calendar page (Google-style): ranges, stepping, title text,
/// the 24/12-hour labels, saturated colours, month bars and search.
final class CalendarViewModeTests: XCTestCase {
  // 2026-11-11 is a Wednesday; the week starts on Sunday 2026-11-08.
  private let today = "2026-11-11"

  private func entry(
    _ key: String, _ start: Int?, _ end: Int?, title: String? = nil, allDay: Bool = false,
    continued: Bool = false
  ) -> DayOccurrence {
    let event = GoogleCalendarEvent(
      id: key, title: title ?? key, start: .init(date: "2026-11-11"), end: .init(date: "2026-11-12"),
      timeZone: "UTC", allDay: allDay)
    return DayOccurrence(
      key: key, date: "2026-11-11", title: title ?? key, start: start, end: end, completed: false,
      allDay: allDay, busy: true, continued: continued, duration: (end ?? 0) - (start ?? 0),
      startLabel: nil, endLabel: nil, clockChange: false, source: .google(event))
  }

  func testEveryLaunchOpensOnTheWeek() {
    XCTAssertEqual(CalendarViewMode.launch, .week)
    XCTAssertEqual(
      CalendarViewMode.allCases, [.schedule, .day, .threeDays, .week, .month])
  }

  func testVisibleDaysForOneThreeAndSevenDays() {
    XCTAssertEqual(CalendarViewMode.day.visibleDays(anchor: today), ["2026-11-11"])
    XCTAssertEqual(
      CalendarViewMode.threeDays.visibleDays(anchor: today), ["2026-11-11", "2026-11-12", "2026-11-13"])
    XCTAssertEqual(
      CalendarViewMode.week.visibleDays(anchor: today).first, "2026-11-08", "the week starts on Sunday")
    XCTAssertEqual(CalendarViewMode.week.visibleDays(anchor: today).last, "2026-11-14")
    XCTAssertEqual(CalendarViewMode.week.visibleDays(anchor: "2026-11-08").first, "2026-11-08")
    XCTAssertEqual(CalendarViewMode.week.visibleDays(anchor: "2026-11-14").first, "2026-11-08")
    XCTAssertTrue(CalendarViewMode.month.visibleDays(anchor: today).isEmpty)
    XCTAssertTrue(CalendarViewMode.schedule.visibleDays(anchor: today).isEmpty)
  }

  func testThreeDaysCrossTheMonthEnd() {
    XCTAssertEqual(
      CalendarViewMode.threeDays.visibleDays(anchor: "2026-11-30"), ["2026-11-30", "2026-12-01", "2026-12-02"])
  }

  func testSteppingMovesByThePeriod() {
    XCTAssertEqual(CalendarViewMode.day.stepped(anchor: today, by: 1), "2026-11-12")
    XCTAssertEqual(CalendarViewMode.day.stepped(anchor: today, by: -1), "2026-11-10")
    XCTAssertEqual(CalendarViewMode.threeDays.stepped(anchor: today, by: 1), "2026-11-14")
    XCTAssertEqual(CalendarViewMode.threeDays.stepped(anchor: today, by: -1), "2026-11-08")
    XCTAssertEqual(CalendarViewMode.week.stepped(anchor: today, by: 1), "2026-11-18")
    XCTAssertEqual(CalendarViewMode.week.stepped(anchor: today, by: -2), "2026-10-28")
    XCTAssertEqual(CalendarViewMode.month.stepped(anchor: today, by: 1), "2026-12-11")
    XCTAssertEqual(CalendarViewMode.month.stepped(anchor: "2026-01-31", by: 1).prefix(7), "2026-02")
    XCTAssertEqual(CalendarViewMode.month.stepped(anchor: today, by: -11), "2025-12-11")
    XCTAssertEqual(CalendarViewMode.schedule.stepped(anchor: today, by: 1), "2026-11-18")
  }

  func testANewEntryStartsTodayWhenItIsOnScreen() {
    XCTAssertEqual(CalendarViewMode.week.focusDay(anchor: "2026-11-09", today: today), today)
    XCTAssertEqual(CalendarViewMode.week.focusDay(anchor: "2026-11-20", today: today), "2026-11-20")
    XCTAssertEqual(CalendarViewMode.threeDays.focusDay(anchor: "2026-11-10", today: today), today)
    XCTAssertEqual(CalendarViewMode.threeDays.focusDay(anchor: "2026-11-12", today: today), "2026-11-12")
    XCTAssertEqual(CalendarViewMode.day.focusDay(anchor: "2026-11-12", today: today), "2026-11-12")
    XCTAssertEqual(CalendarViewMode.month.focusDay(anchor: "2026-11-20", today: today), "2026-11-20")
  }

  func testFetchRangeCoversTheNeighbouringPeriods() {
    let week = CalendarViewMode.week.fetchRange(anchor: today)
    XCTAssertEqual(week.from, "2026-11-01")
    XCTAssertEqual(week.to, "2026-11-22")
    let day = CalendarViewMode.day.fetchRange(anchor: today)
    XCTAssertEqual(day.from, "2026-11-08")
    XCTAssertEqual(day.to, "2026-11-15")
    let three = CalendarViewMode.threeDays.fetchRange(anchor: today)
    XCTAssertEqual(three.from, "2026-11-08")
    XCTAssertEqual(three.to, "2026-11-17")
    let month = CalendarViewMode.month.fetchRange(anchor: today)
    XCTAssertEqual(month.from, "2026-09-27", "the grid of October starts on that Sunday")
    XCTAssertEqual(month.to, "2027-01-10", "the grid of December ends on 2027-01-09")
    let schedule = CalendarViewMode.schedule.fetchRange(anchor: today)
    XCTAssertEqual(schedule.from, today)
    XCTAssertEqual(schedule.to, "2026-12-23")
    XCTAssertEqual(CalendarViewMode.schedule.fetchRange(anchor: today, scheduleDays: 70).to, "2027-01-20")
  }

  func testTitleIsTheMonthOfTheMiddleDay() {
    XCTAssertEqual(CalendarViewMode.week.title(anchor: today, today: today, language: .ru).text, "Ноябрь")
    XCTAssertEqual(
      CalendarViewMode.week.title(anchor: today, today: today, language: .en).text, "November")
    // Sunday 29 Nov: the week's middle day is Wednesday 2 Dec.
    XCTAssertEqual(
      CalendarViewMode.week.title(anchor: "2026-11-29", today: today, language: .ru).month, "Декабрь")
    XCTAssertEqual(
      CalendarViewMode.threeDays.title(anchor: "2026-11-30", today: today, language: .ru).month, "Декабрь")
    XCTAssertEqual(
      CalendarViewMode.day.title(anchor: "2026-11-30", today: today, language: .ru).month, "Ноябрь")
    XCTAssertEqual(
      CalendarViewMode.month.title(anchor: "2027-02-10", today: today, language: .ru).text, "Февраль 2027")
    XCTAssertEqual(
      CalendarViewMode.schedule.title(anchor: "2025-05-01", today: today, language: .en).text, "May 2025")
    XCTAssertEqual(CalendarViewMode.day.title(anchor: "oops", today: today, language: .ru).text, "")
  }

  func testHoursAreTwentyFourHourByDefault() {
    XCTAssertEqual(CalendarHourFormat.default, .h24)
    XCTAssertEqual(CalendarHourFormat.h24.hourLabel(0), "00:00")
    XCTAssertEqual(CalendarHourFormat.h24.hourLabel(9), "09:00")
    XCTAssertEqual(CalendarHourFormat.h24.hourLabel(13), "13:00")
    XCTAssertEqual(CalendarHourFormat.h12.hourLabel(0), "12AM")
    XCTAssertEqual(CalendarHourFormat.h12.hourLabel(13), "1PM")
    XCTAssertEqual(CalendarHourFormat.h24.clock(570), "09:30")
    XCTAssertEqual(CalendarHourFormat.h24.clock(1440 + 60), "01:00")
    XCTAssertEqual(CalendarHourFormat.h12.clock(570), "9:30 AM")
  }

  func testEntryTimesFollowTheHourFormat() {
    let block = entry("a", 570, 630)
    XCTAssertEqual(CalendarHourFormat.h24.entryRange(block), "09:30–10:30")
    XCTAssertEqual(CalendarHourFormat.h12.entryRange(block), "9:30 AM–10:30 AM")
    let whole = entry("b", 540, 600)
    XCTAssertEqual(CalendarHourFormat.h12.entryRange(whole), "9 AM–10 AM")
    XCTAssertEqual(CalendarHourFormat.h24.entryTime(entry("c", nil, nil), start: true), "")
  }

  func testSolidColoursAreGoogleSwatchesAndKeepAReadableInk() {
    XCTAssertEqual(CalendarPlan.solidHex("11"), "d50000")
    XCTAssertEqual(CalendarPlan.solidHex("#AbCdEf"), "abcdef")
    XCTAssertNil(CalendarPlan.solidHex(nil))
    XCTAssertNil(CalendarPlan.solidHex("99"))
    XCTAssertTrue(CalendarPlan.prefersDarkInk(hex: "f6bf26"), "yellow takes dark text")
    XCTAssertTrue(CalendarPlan.prefersDarkInk(hex: "c0ca33"))
    XCTAssertFalse(CalendarPlan.prefersDarkInk(hex: "3f51b5"))
    XCTAssertFalse(CalendarPlan.prefersDarkInk(hex: "d50000"))
    XCTAssertFalse(CalendarPlan.prefersDarkInk(hex: "33b679"), "greens keep white text")
    XCTAssertEqual(CalendarPlan.luminance(hex: "ffffff"), 1, accuracy: 0.001)
    XCTAssertEqual(CalendarPlan.luminance(hex: "zz"), 0)
  }

  func testMonthBarsListUntimedFirstAndCountTheRest() {
    let few = CalendarPlan.monthBars([entry("late", 900, 960), entry("all", nil, nil, allDay: true)], limit: 3)
    XCTAssertEqual(few.shown.map(\.key), ["all", "late"])
    XCTAssertEqual(few.more, 0)
    let many = CalendarPlan.monthBars(
      [entry("c", 900, 960), entry("b", 600, 660), entry("all", nil, nil, allDay: true),
       entry("d", 1000, 1060), entry("a", 500, 560)],
      limit: 3)
    XCTAssertEqual(many.shown.map(\.key), ["all", "a"])
    XCTAssertEqual(many.more, 3)
    let exact = CalendarPlan.monthBars([entry("a", 1, 2), entry("b", 3, 4), entry("c", 5, 6)], limit: 3)
    XCTAssertEqual(exact.shown.count, 3)
    XCTAssertEqual(exact.more, 0)
    XCTAssertEqual(CalendarPlan.monthBars([entry("a", 1, 2)], limit: 0).more, 1)
  }

  func testSearchFindsTitlesAcrossDaysInOrder() {
    let days: [(date: String, entries: [DayOccurrence])] = [
      ("2026-11-12", [entry("x", 600, 660, title: "Спортзал")]),
      ("2026-11-11", [
        entry("y", 900, 960, title: "Ёлка у друзей"), entry("z", 500, 560, title: "Ёлки-палки"),
        entry("w", 100, 200, title: "Ёлка", continued: true),
      ]),
    ]
    let found = CalendarSearch.hits(in: days, query: "  ЕЛКА ")
    XCTAssertEqual(found.map(\.entry.key), ["y"], "ё and е match, a continued part is skipped")
    XCTAssertEqual(CalendarSearch.hits(in: days, query: "ел").map(\.entry.key), ["z", "y"])
    XCTAssertEqual(CalendarSearch.hits(in: days, query: "зал").first?.date, "2026-11-12")
    XCTAssertTrue(CalendarSearch.hits(in: days, query: "   ").isEmpty)
    XCTAssertEqual(CalendarSearch.hits(in: days, query: "ел", limit: 1).count, 1)
  }
}
