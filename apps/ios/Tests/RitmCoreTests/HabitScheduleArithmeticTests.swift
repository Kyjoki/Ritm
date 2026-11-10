import Foundation
import XCTest

@testable import RitmCore

/// The integer calendar arithmetic of `HabitSchedule` against Foundation's Gregorian calendar.
final class HabitScheduleArithmeticTests: XCTestCase {
  private var reference: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func key(_ date: Date) -> String {
    let parts = reference.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }

  func testWeekdayAndAddDaysMatchFoundationAcrossTwoCenturies() throws {
    let calendar = reference
    var date = try XCTUnwrap(calendar.date(from: DateComponents(year: 1900, month: 1, day: 1, hour: 12)))
    let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 12, day: 31, hour: 12)))
    var checked = 0
    while date < end {
      let text = key(date)
      XCTAssertEqual(HabitSchedule.weekday(text), calendar.component(.weekday, from: date) - 1, text)
      let shifted = try XCTUnwrap(calendar.date(byAdding: .day, value: 37, to: date))
      XCTAssertEqual(HabitSchedule.addDays(to: text, days: 37), key(shifted), text)
      let back = try XCTUnwrap(calendar.date(byAdding: .day, value: -400, to: date))
      XCTAssertEqual(HabitSchedule.addDays(to: text, days: -400), key(back), text)
      date = try XCTUnwrap(calendar.date(byAdding: .day, value: 11, to: date))
      checked += 1
    }
    XCTAssertGreaterThan(checked, 6000)
  }

  func testLeapDaysAndMonthEnds() {
    XCTAssertEqual(HabitSchedule.addDays(to: "2028-02-28", days: 1), "2028-02-29")
    XCTAssertEqual(HabitSchedule.addDays(to: "2100-02-28", days: 1), "2100-03-01")
    XCTAssertEqual(HabitSchedule.addDays(to: "2000-02-28", days: 1), "2000-02-29")
    XCTAssertEqual(HabitSchedule.addDays(to: "2026-12-31", days: 1), "2027-01-01")
    XCTAssertEqual(HabitSchedule.addDays(to: "2027-01-01", days: -1), "2026-12-31")
    XCTAssertEqual(HabitSchedule.addDays(to: "2026-11-30", days: 0), "2026-11-30")
    XCTAssertFalse(HabitSchedule.isValidDate("2100-02-29"))
    XCTAssertTrue(HabitSchedule.isValidDate("2000-02-29"))
    XCTAssertFalse(HabitSchedule.isValidDate("2026-04-31"))
  }

  func testMalformedKeysAreRejected() {
    for bad in ["", "2026-11-1", "2026/11/01", "26-11-2026", "2026-11-001", "2026-00-10", "2026-11-00", "0000-01-01", "2026-1a-01", "٢٠٢٦-11-01"] {
      XCTAssertFalse(HabitSchedule.isValidDate(bad), bad)
      XCTAssertNil(HabitSchedule.weekday(bad), bad)
      XCTAssertNil(HabitSchedule.addDays(to: bad, days: 1), bad)
    }
  }

  func testWeeksStartOnSunday() {
    XCTAssertEqual(HabitSchedule.weekday("2026-11-08"), 0)
    XCTAssertEqual(HabitSchedule.week(containing: "2026-11-14").first, "2026-11-08")
    XCTAssertEqual(HabitSchedule.week(containing: "2026-11-08").last, "2026-11-14")
    XCTAssertEqual(HabitSchedule.week(containing: "2026-11-11").count, 7)
  }
}
