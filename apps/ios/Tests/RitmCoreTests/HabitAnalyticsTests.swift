import Foundation
import XCTest

@testable import RitmCore

/// The numbers behind the redesigned habits page (Sunday weeks, «Верх 1» card, awards).
final class HabitAnalyticsTests: XCTestCase {
  private let today = "2026-11-11"  // Wednesday

  private func daily(_ id: String, done: [String] = [], start: String = "2026-11-01") -> Habit {
    Habit(id: id, title: id.capitalized, startDate: start, completedDates: done)
  }

  private func days(from first: String, count: Int) -> [String] {
    (0..<count).compactMap { HabitSchedule.addDays(to: first, days: $0) }
  }

  // MARK: Palette

  func testAccentIndexIsStableAndInsideThePalette() {
    XCTAssertEqual(HabitAnalytics.accentIndex(for: "habit-1"), 1)
    XCTAssertEqual(HabitAnalytics.accentIndex(for: "gym"), 0)
    XCTAssertEqual(HabitAnalytics.accentIndex(for: "ielts"), 2)
    XCTAssertEqual(HabitAnalytics.accentIndex(for: "reading"), 5)
    let ids = (0..<60).map { "id-\($0)" }
    let indexes = Set(ids.map(HabitAnalytics.accentIndex))
    XCTAssertTrue(indexes.allSatisfy { (0..<HabitAnalytics.accentCount).contains($0) })
    XCTAssertGreaterThanOrEqual(indexes.count, 5)
  }

  // MARK: Period

  func testPeriodPercentCountsScheduledMarksUpToToday() {
    let habit = daily("a", done: ["2026-11-08", "2026-11-09", "2026-11-10"])
    let week = HabitsPlan.periodDates(today: today, month: false, offset: 0)
    XCTAssertEqual(week.first, "2026-11-08")
    // Sun, Mon, Tue and Wed are lived: 3 of 4.
    XCTAssertEqual(HabitAnalytics.periodPercent([habit], dates: week, today: today), 75)
    let none = Habit(id: "b", title: "B", weekdays: [6], startDate: "2026-11-01")
    XCTAssertNil(HabitAnalytics.periodPercent([none], dates: Array(week.prefix(4)), today: today))
  }

  func testBestAndWorstHabitOfAPeriod() {
    let strong = daily("strong", done: ["2026-11-08", "2026-11-09", "2026-11-10"])
    let weak = daily("weak", done: ["2026-11-08"])
    let idle = Habit(id: "idle", title: "Idle", weekdays: [6], startDate: "2026-11-01")
    let week = HabitsPlan.periodDates(today: today, month: false, offset: 0)
    let rates = HabitAnalytics.rates([strong, weak, idle], dates: week, today: today)
    XCTAssertEqual(rates.map(\.habitID), ["strong", "weak"])
    let result = HabitAnalytics.bestAndWorst(rates)
    XCTAssertEqual(result.best?.habitID, "strong")
    XCTAssertEqual(result.best?.percent, 75)
    XCTAssertEqual(result.worst?.habitID, "weak")
    XCTAssertEqual(result.worst?.percent, 25)
  }

  func testWeakHabitIsMissingWhenItWouldBeTheBestOneOrThereIsNothing() {
    let same = [
      HabitRate(habitID: "a", title: "A", planned: 4, completed: 2),
      HabitRate(habitID: "b", title: "B", planned: 2, completed: 1),
    ]
    let tie = HabitAnalytics.bestAndWorst(same)
    XCTAssertEqual(tie.best?.habitID, "a")  // more marks wins the tie
    XCTAssertNil(tie.worst)
    let single = HabitAnalytics.bestAndWorst([same[0]])
    XCTAssertEqual(single.best?.habitID, "a")
    XCTAssertNil(single.worst)
    let empty = HabitAnalytics.bestAndWorst([])
    XCTAssertNil(empty.best)
    XCTAssertNil(empty.worst)
  }

  func testWorstTieKeepsTheHabitWithMoreScheduledMarks() {
    let rates = [
      HabitRate(habitID: "top", title: "Top", planned: 4, completed: 4),
      HabitRate(habitID: "few", title: "Few", planned: 2, completed: 0),
      HabitRate(habitID: "many", title: "Many", planned: 6, completed: 0),
    ]
    XCTAssertEqual(HabitAnalytics.bestAndWorst(rates).worst?.habitID, "many")
  }

  func testTrendAgainstThePreviousPeriod() {
    // Previous week 1–7 Nov: 4 of 7 (57 %); this week: 3 of 4 (75 %).
    let habit = daily(
      "a", done: ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-08", "2026-11-09", "2026-11-10"])
    XCTAssertEqual(HabitAnalytics.trend([habit], today: today, month: false, offset: 0), 18)
    // A habit that started this week has nothing to compare with.
    let fresh = daily("f", done: ["2026-11-08"], start: "2026-11-08")
    XCTAssertNil(HabitAnalytics.trend([fresh], today: today, month: false, offset: 0))
    // The month: October had no marks of this habit (it started on 1 Nov).
    XCTAssertNil(HabitAnalytics.trend([habit], today: today, month: true, offset: 0))
  }

  func testTrendCanBeNegative() {
    let habit = daily("a", done: days(from: "2026-11-01", count: 7))
    // 7 of 7 before, 0 of 4 now.
    XCTAssertEqual(HabitAnalytics.trend([habit], today: today, month: false, offset: 0), -100)
  }

  func testDefaultDayIsTodayOrTheLastLivedDay() {
    let week = HabitsPlan.periodDates(today: today, month: false, offset: 0)
    XCTAssertEqual(HabitAnalytics.defaultDay(in: week, today: today), today)
    let before = HabitsPlan.periodDates(today: today, month: false, offset: -1)
    XCTAssertEqual(HabitAnalytics.defaultDay(in: before, today: today), "2026-11-07")
    XCTAssertNil(HabitAnalytics.defaultDay(in: [], today: today))
  }

  // MARK: Heat

  func testIntensityIsInQuartersAndZeroWhenNothingWasDone() {
    func level(_ planned: Int, _ done: Int) -> Int {
      HabitAnalytics.intensity(HabitDaySummary(planned: planned, completed: done))
    }
    XCTAssertEqual(level(0, 0), 0)
    XCTAssertEqual(level(4, 0), 0)
    XCTAssertEqual(level(4, 1), 1)
    XCTAssertEqual(level(3, 1), 2)
    XCTAssertEqual(level(4, 2), 2)
    XCTAssertEqual(level(4, 3), 3)
    XCTAssertEqual(level(4, 4), 4)
  }

  func testGoodDaysNeedSixtyPercentAndTodayStaysOpen() {
    let doneTogether = days(from: "2026-11-06", count: 5)  // 6th to 10th
    let a = daily("a", done: doneTogether)
    let b = daily("b", done: doneTogether)
    XCTAssertEqual(HabitAnalytics.isGoodDay([a, b], on: "2026-11-07"), true)
    XCTAssertEqual(HabitAnalytics.isGoodDay([a, b], on: "2026-11-03"), false)
    XCTAssertNil(HabitAnalytics.isGoodDay([Habit(id: "x", title: "X", weekdays: [6], startDate: "2026-11-01")], on: today))
    let streaks = HabitAnalytics.goodDayStreaks([a, b], end: today, today: today)
    XCTAssertEqual(streaks.current, 5)
    XCTAssertEqual(streaks.best, 5)
    // Looking at an older period ends the run on its last day.
    let earlier = HabitAnalytics.goodDayStreaks([a, b], end: "2026-11-08", today: today)
    XCTAssertEqual(earlier.current, 3)
    XCTAssertEqual(earlier.best, 3)
  }

  func testThreeOfFiveHabitsIsAGoodDayAndTwoOfFiveIsNot() {
    let habits = (0..<5).map { index in
      daily("h\(index)", done: index < 3 ? ["2026-11-10"] : [])
    }
    XCTAssertEqual(HabitAnalytics.isGoodDay(habits, on: "2026-11-10"), true)
    let fewer = (0..<5).map { index in
      daily("h\(index)", done: index < 2 ? ["2026-11-10"] : [])
    }
    XCTAssertEqual(HabitAnalytics.isGoodDay(fewer, on: "2026-11-10"), false)
  }

  func testAMissedYesterdayBreaksTheStreakButAnOpenTodayDoesNot() {
    let habit = daily("a", done: ["2026-11-07", "2026-11-08", "2026-11-09"])
    XCTAssertEqual(HabitAnalytics.goodDayStreaks([habit], end: today, today: today).current, 0)
    let fine = daily("a", done: ["2026-11-08", "2026-11-09", "2026-11-10"])
    let streaks = HabitAnalytics.goodDayStreaks([fine], end: today, today: today)
    XCTAssertEqual(streaks.current, 3)
    XCTAssertEqual(streaks.best, 3)
  }

  // MARK: One habit

  func testDayStateAndFractionOfACountedHabit() {
    let habit = Habit(
      id: "w", title: "Water", weekdays: [1, 2, 3], target: 8, startDate: "2026-11-01",
      completedDates: ["2026-11-09"], progressByDate: ["2026-11-09": 8, "2026-11-10": 3])
    XCTAssertEqual(HabitAnalytics.dayState(habit, on: "2026-11-09", today: today), .done)
    XCTAssertEqual(HabitAnalytics.dayState(habit, on: "2026-11-10", today: today), .part)
    XCTAssertEqual(HabitAnalytics.fraction(habit, on: "2026-11-10"), 0.375, accuracy: 0.0001)
    XCTAssertEqual(HabitAnalytics.dayState(habit, on: "2026-11-11", today: today), .miss)
    XCTAssertEqual(HabitAnalytics.dayState(habit, on: "2026-11-12", today: today), .future)
    XCTAssertEqual(HabitAnalytics.dayState(habit, on: "2026-11-08", today: today), .off)
    XCTAssertEqual(HabitAnalytics.fraction(habit, on: "2026-11-09"), 1)
  }

  func testWeekCountIsMarksOverScheduledDaysUpToToday() {
    let gym = Habit(
      id: "gym", title: "Gym", weekdays: [1, 3, 5], startDate: "2026-11-01",
      completedDates: ["2026-11-09"])
    var count = HabitAnalytics.weekCount(gym, containing: "2026-11-12", today: today)
    XCTAssertEqual(count.planned, 2)  // Monday and Wednesday; Friday is still ahead
    XCTAssertEqual(count.completed, 1)
    var ticked = gym
    ticked.completedDates.append("2026-11-11")
    count = HabitAnalytics.weekCount(ticked, containing: today, today: today)
    XCTAssertEqual(count.completed, 2)
    // The week before is complete: Monday, Wednesday and Friday.
    XCTAssertEqual(HabitAnalytics.weekCount(gym, containing: "2026-11-04", today: today).planned, 3)
  }

  func testPeriodStatsAverageAndShare() {
    let water = Habit(
      id: "w", title: "Water", target: 2000, startDate: "2026-11-01",
      completedDates: ["2026-11-08"], progressByDate: ["2026-11-08": 2000, "2026-11-09": 1000])
    let stats = HabitAnalytics.periodStats(
      water, dates: HabitSchedule.week(containing: today), today: today)
    XCTAssertEqual(stats.planned, 4)
    XCTAssertEqual(stats.completed, 1)
    XCTAssertEqual(stats.percent, 25)
    XCTAssertEqual(stats.total, 3000)
    XCTAssertEqual(stats.average, 750)
  }

  func testStatsFindTheLastDayEachLevelWasReached() {
    let run = days(from: "2026-11-01", count: 4) + days(from: "2026-11-06", count: 5)
    let habit = daily("a", done: run)
    let stats = HabitAnalytics.stats(habit, today: today)
    XCTAssertEqual(stats.best, 5)
    XCTAssertEqual(stats.streak, 5)
    XCTAssertEqual(stats.events, [AchievementEvent(level: 3, day: "2026-11-08")])
    XCTAssertEqual(stats.best, HabitSchedule.bestStreak(habit, today: today))
    XCTAssertEqual(stats.streak, HabitSchedule.streak(habit, today: today))
  }

  func testStatsListLevelsNewestFirstAndAgreeWithBestStreak() {
    let habit = daily("a", start: "2026-10-01")
    var long = habit
    long.completedDates = days(from: "2026-10-01", count: 40)
    let stats = HabitAnalytics.stats(long, today: "2026-11-09")
    XCTAssertEqual(stats.best, 40)
    XCTAssertEqual(stats.events.map(\.level), [30, 14, 7, 3])
    XCTAssertEqual(stats.events.first?.day, "2026-10-30")
    XCTAssertEqual(stats.best, HabitSchedule.bestStreak(long, today: "2026-11-09"))
    // 60 and 100 days arrive later.
    long.completedDates = days(from: "2026-10-01", count: 100)
    let late = HabitAnalytics.stats(long, today: "2027-01-31")
    XCTAssertEqual(late.events.first, AchievementEvent(level: 100, day: "2027-01-08"))
    XCTAssertEqual(late.events.map(\.level), [100, 60, 30, 14, 7, 3])
  }

  func testAnArchivedStretchResetsTheRun() {
    let habit = Habit(
      id: "a", title: "A", archived: false, startDate: "2026-11-01",
      completedDates: days(from: "2026-11-01", count: 8),
      periods: [
        HabitPeriod(from: "2026-11-01", weekdays: Array(0...6)),
        HabitPeriod(from: "2026-11-05", weekdays: Array(0...6), archived: true),
        HabitPeriod(from: "2026-11-07", weekdays: Array(0...6)),
      ])
    let stats = HabitAnalytics.stats(habit, today: today)
    XCTAssertEqual(stats.best, HabitSchedule.bestStreak(habit, today: today))
  }

  func testEarnedLevelsCombineTheRecordAndTheServer() {
    var habit = daily("a")
    habit.achievements = [100]
    XCTAssertEqual(HabitAnalytics.earnedLevels(habit, best: 8), [3, 7, 100])
    habit.achievements = nil
    XCTAssertEqual(HabitAnalytics.earnedLevels(habit, best: 0), [])
    XCTAssertEqual(HabitAnalytics.earnedLevels(habit, best: 100), Set(HabitAnalytics.achievementLevels))
  }

  func testNextGoalsAndCrossedLevels() {
    XCTAssertEqual(HabitAnalytics.nextGoal(streak: 0), 3)
    XCTAssertEqual(HabitAnalytics.nextGoal(streak: 7), 14)
    XCTAssertEqual(HabitAnalytics.nextGoal(streak: 59), 60)
    XCTAssertNil(HabitAnalytics.nextGoal(streak: 100))
    XCTAssertEqual(HabitAnalytics.nextUnearned(best: 8, earned: [3, 7]), 14)
    XCTAssertEqual(HabitAnalytics.nextUnearned(best: 8, earned: [3, 7, 14]), 30)
    XCTAssertEqual(HabitAnalytics.crossedLevel(bestBefore: 6, bestAfter: 7), 7)
    XCTAssertNil(HabitAnalytics.crossedLevel(bestBefore: 7, bestAfter: 7))
    XCTAssertEqual(HabitAnalytics.crossedLevel(bestBefore: 2, bestAfter: 40), 3)
  }

  // MARK: Awards

  func testAwardsListTheNewestSevenDayAchievementsAcrossHabits() {
    let ielts = HabitStats(
      streak: 5, best: 14,
      events: [AchievementEvent(level: 14, day: "2026-11-09"), AchievementEvent(level: 3, day: "2026-10-01")])
    let gym = HabitStats(
      streak: 2, best: 7,
      events: [AchievementEvent(level: 7, day: "2026-11-02"), AchievementEvent(level: 3, day: "2026-10-28")])
    let awards = HabitAnalytics.awards([("ielts", "IELTS", ielts), ("gym", "Gym", gym)])
    XCTAssertEqual(awards.map(\.id), ["ielts#14", "gym#7"])
    XCTAssertEqual(awards.first?.day, "2026-11-09")
    XCTAssertEqual(HabitAnalytics.awards([("ielts", "IELTS", ielts), ("gym", "Gym", gym)], limit: 1).count, 1)
    XCTAssertTrue(HabitAnalytics.awards([]).isEmpty)
  }

  func testTheClosestGoalIsTheHabitWithTheFewestDaysLeft() {
    func source(_ id: String, _ streak: Int) -> (id: String, title: String, stats: HabitStats) {
      (id, id.uppercased(), HabitStats(streak: streak, best: streak, events: []))
    }
    let goal = HabitAnalytics.closestGoal([source("a", 5), source("b", 12), source("c", 29)])
    XCTAssertEqual(goal, HabitGoal(habitID: "c", title: "C", level: 30, remaining: 1))
    // A tie keeps the first habit.
    XCTAssertEqual(HabitAnalytics.closestGoal([source("a", 5), source("b", 12)])?.habitID, "a")
    XCTAssertNil(HabitAnalytics.closestGoal([source("a", 100)]))
    XCTAssertNil(HabitAnalytics.closestGoal([]))
  }

  // MARK: Counter step

  func testCounterStepFollowsTheGoal() {
    XCTAssertEqual(HabitAnalytics.step(target: 2000, unit: "мл"), 250)
    XCTAssertEqual(HabitAnalytics.step(target: 8, unit: "стаканов"), 1)
    XCTAssertEqual(HabitAnalytics.step(target: 1, unit: nil), 1)
    XCTAssertEqual(HabitAnalytics.step(target: 100, unit: "стр."), 10)
    XCTAssertEqual(HabitAnalytics.step(target: 30, unit: "мин"), 2)
    XCTAssertEqual(HabitAnalytics.step(target: 10_000, unit: "шагов"), 1000)
  }
}
