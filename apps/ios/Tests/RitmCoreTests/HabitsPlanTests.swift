import Foundation
import XCTest

@testable import RitmCore

/// Mirrors the calculations in src/features/HabitsPage.tsx.
final class HabitsPlanTests: XCTestCase {
  private let today = "2026-10-29"  // Thursday

  func testPeriodDatesForWeeksAndCalendarMonths() {
    XCTAssertEqual(HabitsPlan.periodDates(today: today, month: false, offset: 0).first, "2026-10-25")
    XCTAssertEqual(HabitsPlan.periodDates(today: today, month: false, offset: -1).last, "2026-10-24")
    let october = HabitsPlan.periodDates(today: today, month: true, offset: 0)
    XCTAssertEqual(october.count, 31)
    XCTAssertEqual(october.first, "2026-10-01")
    let february = HabitsPlan.periodDates(today: "2026-03-31", month: true, offset: -1)
    XCTAssertEqual(february.first, "2026-02-01")
    XCTAssertEqual(february.last, "2026-02-28")
    XCTAssertEqual(HabitsPlan.periodDates(today: "2026-01-15", month: true, offset: -1).first, "2025-12-01")
  }

  func testDayStatusFollowsTheWebOrder() {
    let habit = Habit(
      id: "h", title: "Run", weekdays: [1, 3, 4], startDate: "2026-10-26",
      completedDates: ["2026-10-28"])
    XCTAssertEqual(HabitsPlan.dayStatus(habit, on: "2026-10-28", today: today), .done)
    XCTAssertEqual(HabitsPlan.dayStatus(habit, on: "2026-10-29", today: today), .pending)
    XCTAssertEqual(HabitsPlan.dayStatus(habit, on: "2026-10-27", today: today), .rest)
    XCTAssertEqual(HabitsPlan.dayStatus(habit, on: "2026-10-30", today: today), .future)
    XCTAssertEqual(HabitsPlan.dayStatus(habit, on: "2026-10-24", today: today), .before)
    // Before the start a scheduled weekday can still be marked.
    XCTAssertEqual(HabitsPlan.dayStatus(habit, on: "2026-10-21", today: today), .pending)
  }

  func testHeatLevels() {
    XCTAssertEqual(HabitsPlan.heatLevel(HabitDaySummary(planned: 2, completed: 2), day: "2026-10-28", today: today), .full)
    XCTAssertEqual(HabitsPlan.heatLevel(HabitDaySummary(planned: 2, completed: 1), day: "2026-10-28", today: today), .some)
    XCTAssertEqual(HabitsPlan.heatLevel(HabitDaySummary(planned: 2, completed: 0), day: "2026-10-28", today: today), .empty)
    XCTAssertEqual(HabitsPlan.heatLevel(HabitDaySummary(planned: 0, completed: 0), day: "2026-10-28", today: today), .none)
    XCTAssertEqual(HabitsPlan.heatLevel(HabitDaySummary(planned: 1, completed: 0), day: "2026-10-30", today: today), .future)
  }

  func testInsightsPickTheSteadiestHabitAndTheWeakestWeekday() {
    let steady = Habit(
      id: "steady", title: "Read", startDate: "2026-10-01",
      completedDates: ["2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28"])
    let shaky = Habit(id: "shaky", title: "Run", startDate: "2026-10-01", completedDates: ["2026-10-26"])
    let dates = HabitsPlan.periodDates(today: today, month: false, offset: 0)
    let stable = HabitsPlan.steadiest([steady, shaky], dates: dates, today: today)
    XCTAssertEqual(stable?.habit.id, "steady")
    XCTAssertEqual(stable?.percent, 100)
    // Sunday 25th: 1 of 2, Monday: 2 of 2, Tuesday: 1 of 2, Wednesday: 1 of 2.
    XCTAssertEqual(HabitsPlan.weakestWeekday([steady, shaky], dates: dates, today: today), 0)
  }

  func testComparisonUsesTheSameNumberOfDaysOfThePreviousPeriod() {
    let habit = Habit(
      id: "h", title: "Read", startDate: "2026-10-01",
      completedDates: ["2026-10-18", "2026-10-19", "2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28"])
    let result = HabitsPlan.comparison([habit], today: today, month: false, offset: 0)
    // Five days so far this week (25–29): 4 of 5 = 80 %; first five of last week: 2 of 5 = 40 %.
    XCTAssertEqual(result?.current, 80)
    XCTAssertEqual(result?.previous, 40)
  }

  func testAwardsAndTheNextMilestone() {
    var habit = Habit(id: "h", title: "Read", startDate: "2026-10-01")
    XCTAssertEqual(HabitsPlan.awards(habit, best: 8), [3, 7])
    XCTAssertEqual(HabitsPlan.nextMilestone(habit, best: 8), 14)
    habit.achievements = [3]
    XCTAssertEqual(HabitsPlan.awards(habit, best: 8), [3], "stored achievements win")
    var updated = habit
    updated.achievements = [3, 7, 14]
    XCTAssertEqual(HabitsPlan.newMilestone(previous: habit, updated: updated), 7)
    XCTAssertNil(HabitsPlan.newMilestone(previous: updated, updated: updated))
  }
}
