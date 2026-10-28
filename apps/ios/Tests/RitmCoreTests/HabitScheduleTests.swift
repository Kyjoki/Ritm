import Foundation
import XCTest

@testable import RitmCore

final class HabitScheduleTests: XCTestCase {
  func testOneScheduledCompletedHabitIsOneOfOneAndOneHundredPercent() {
    let habits = [
      Habit(id: "daily", title: "Чтение", startDate: "2026-10-25", completedDates: ["2026-10-28"]),
      Habit(id: "friday", title: "Бег", weekdays: [5], startDate: "2026-10-25"),
      Habit(id: "future", title: "Будущая", startDate: "2026-11-01"),
    ]
    let result = HabitSchedule.daySummary(habits, on: "2026-10-28")
    XCTAssertEqual(result.planned, 1)
    XCTAssertEqual(result.completed, 1)
    XCTAssertEqual(result.progress, 100)
  }

  func testNoScheduledOpportunitiesHasNoPercentage() {
    let habit = Habit(id: "1", title: "Бег", weekdays: [5], startDate: "2026-10-25")
    XCTAssertNil(HabitSchedule.daySummary([habit], on: "2026-10-28").progress)
    XCTAssertNil(HabitSchedule.daySummary([habit], on: "2026-10-30", today: "2026-10-28").progress)
  }

  func testScheduleHistoryAndArchiveApplyOnlyFromTheirEffectiveDate() {
    let habit = Habit(
      id: "1", title: "История", weekdays: [5], archived: true,
      startDate: "2026-10-01", completedDates: ["2026-10-05", "2026-10-16"],
      periods: [
        HabitPeriod(from: "2026-10-01", weekdays: [1]),
        HabitPeriod(from: "2026-10-10", weekdays: [5]),
        HabitPeriod(from: "2026-10-20", weekdays: [5], archived: true),
      ])
    XCTAssertTrue(HabitSchedule.isComplete(habit, on: "2026-10-05"))
    XCTAssertFalse(HabitSchedule.isScheduled(habit, on: "2026-10-12"))
    XCTAssertTrue(HabitSchedule.isComplete(habit, on: "2026-10-16"))
    XCTAssertFalse(HabitSchedule.isScheduled(habit, on: "2026-10-23"))
    XCTAssertFalse(HabitSchedule.isScheduled(habit, on: "2026-09-28"))
    XCTAssertEqual(HabitSchedule.streak(habit, today: "2026-10-23"), 0)
  }

  func testLegacyCompletionAndCounterHaveIndependentAuthoritativeHistory() {
    var habit = Habit(
      id: "1", title: "Вода", target: 8, startDate: "2026-10-25",
      completedDates: ["2026-10-27"], progressByDate: ["2026-10-28": 8])
    XCTAssertEqual(HabitSchedule.progress(habit, on: "2026-10-27"), 8)
    XCTAssertTrue(HabitSchedule.isComplete(habit, on: "2026-10-27"))
    XCTAssertFalse(HabitSchedule.isComplete(habit, on: "2026-10-28"))
    habit.target = 12
    XCTAssertTrue(HabitSchedule.isComplete(habit, on: "2026-10-27"))
  }

  func testStreakSkipsNonScheduledDaysAndAllowsTodayStillPending() {
    let habit = Habit(
      id: "1", title: "Бег", weekdays: [1, 3, 5], startDate: "2026-10-19",
      completedDates: ["2026-10-19", "2026-10-21", "2026-10-23", "2026-10-26"])
    XCTAssertEqual(HabitSchedule.streak(habit, today: "2026-10-28"), 4)
    XCTAssertEqual(HabitSchedule.streak(habit, today: "2026-10-29"), 0)
    XCTAssertEqual(HabitSchedule.bestStreak(habit, today: "2026-10-29"), 4)
  }

  func testOwnerTimeZoneAndCalendarArithmeticAcrossDST() throws {
    let moment = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-27T20:30:00Z"))
    XCTAssertEqual(HabitSchedule.dateKey(moment, timeZone: "Asia/Qyzylorda"), "2026-10-28")
    XCTAssertEqual(HabitSchedule.dateKey(moment, timeZone: "America/New_York"), "2026-10-27")
    XCTAssertEqual(HabitSchedule.addDays(to: "2026-11-01", days: 1), "2026-11-02")
    XCTAssertEqual(
      HabitSchedule.week(containing: "2026-10-28"),
      [
        "2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30",
        "2026-10-31",
      ])
    XCTAssertFalse(HabitSchedule.isValidDate("2026-02-29"))
    XCTAssertTrue(HabitSchedule.isValidDate("2028-02-29"))
    XCTAssertNil(HabitSchedule.weekday("2026-13-01"))
    XCTAssertNil(HabitSchedule.addDays(to: "2026-1-01", days: 1))
  }

  func testMarkingBeforeCreationMatchesFirstPeriodButRejectsFutureAndArchived() {
    var habit = Habit(id: "1", title: "Бег", weekdays: [1], startDate: "2026-10-28")
    XCTAssertTrue(HabitSchedule.canMark(habit, on: "2026-10-26", today: "2026-10-28"))
    XCTAssertFalse(HabitSchedule.canMark(habit, on: "2026-11-02", today: "2026-10-28"))
    habit.archived = true
    XCTAssertFalse(HabitSchedule.canMark(habit, on: "2026-10-26", today: "2026-10-28"))
  }
}
