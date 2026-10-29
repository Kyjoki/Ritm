import Foundation
import XCTest

@testable import RitmCore

/// Mirrors src/features/google-occurrences.ts and the DashboardPage calculations.
final class DayPlanTests: XCTestCase {
  private let zone = "Asia/Qyzylorda"  // UTC+5, no clock changes.

  private func timed(
    _ id: String, _ start: String, _ end: String, title: String? = nil, busy: Bool = true
  ) -> GoogleCalendarEvent {
    GoogleCalendarEvent(
      id: id, title: title ?? id, start: .init(dateTime: start), end: .init(dateTime: end),
      timeZone: "UTC", busy: busy)
  }

  private func allDay(_ id: String, _ start: String, _ end: String, busy: Bool = true)
    -> GoogleCalendarEvent
  {
    GoogleCalendarEvent(
      id: id, title: id, start: .init(date: start), end: .init(date: end), timeZone: "UTC",
      allDay: true, busy: busy)
  }

  func testClockMatchesTheWebFormatter() {
    XCTAssertEqual(DayPlan.clock(0), "12:00 AM")
    XCTAssertEqual(DayPlan.clock(780), "1:00 PM")
    XCTAssertEqual(DayPlan.clock(1440), "12:00 AM")
    XCTAssertEqual(DayPlan.clock(540, compact: true), "9 AM")
    XCTAssertEqual(DayPlan.clock(545, compact: true), "9:05 AM")
  }

  func testDurationTextMatchesTheWebFormatter() {
    XCTAssertEqual(DayPlan.durationText(90, language: .ru), "1 ч 30 мин")
    XCTAssertEqual(DayPlan.durationText(60, language: .ru), "1 ч")
    XCTAssertEqual(DayPlan.durationText(0, language: .ru), "0 мин")
    XCTAssertEqual(DayPlan.durationText(45, language: .en), "45 min")
    XCTAssertEqual(DayPlan.durationText(125, language: .en), "2 h 5 min")
  }

  func testTimedEventEndingAtMidnightBelongsToItsStartDay() throws {
    let event = timed("late", "2026-10-29T18:00:00Z", "2026-10-29T19:00:00Z")
    let entry = try XCTUnwrap(
      DayPlan.googleOccurrences([event], date: "2026-10-29", timeZone: zone).first)
    XCTAssertEqual(entry.start, 1380)
    XCTAssertEqual(entry.end, 1440)
    XCTAssertEqual(entry.duration, 60)
    XCTAssertEqual(entry.startLabel, "11:00 PM")
    XCTAssertEqual(entry.endLabel, "12:00 AM")
    XCTAssertEqual(entry.key, "google:primary:late:2026-10-29")
    XCTAssertFalse(entry.continued)
    XCTAssertTrue(DayPlan.googleOccurrences([event], date: "2026-10-30", timeZone: zone).isEmpty)
  }

  func testOvernightEventContinuesOnTheNextDay() throws {
    // 22:00 – 02:00 in the account zone.
    let event = timed("night", "2026-10-29T17:00:00Z", "2026-10-29T21:00:00Z")
    let first = try XCTUnwrap(
      DayPlan.googleOccurrences([event], date: "2026-10-29", timeZone: zone).first)
    XCTAssertEqual(first.start, 1320)
    XCTAssertEqual(first.end, 1440)
    XCTAssertEqual(first.endLabel, "12:00 AM")
    let second = try XCTUnwrap(
      DayPlan.googleOccurrences([event], date: "2026-10-30", timeZone: zone).first)
    XCTAssertTrue(second.continued)
    XCTAssertEqual(second.start, 0)
    XCTAssertEqual(second.end, 120)
    XCTAssertEqual(second.startLabel, "12:00 AM")
    XCTAssertEqual(second.endLabel, "2:00 AM")
  }

  func testAllDayEndIsExclusiveAndIgnoresTheZone() {
    let event = allDay("trip", "2026-10-29", "2026-10-31")
    XCTAssertEqual(
      DayPlan.googleOccurrences([event], date: "2026-10-30", timeZone: "Pacific/Kiritimati").count,
      1)
    XCTAssertTrue(DayPlan.googleOccurrences([event], date: "2026-10-31", timeZone: zone).isEmpty)
    XCTAssertTrue(
      DayPlan.googleOccurrences([event], date: "2026-10-29", timeZone: zone).first?.allDay == true)
  }

  func testCombinedSkipsQuickTasksAndSortsAllDayFirstThenByStart() {
    let tasks = [
      RitmTask(id: "quick", title: "Quick", date: "2026-10-29", calendarEntry: false),
      RitmTask(
        id: "lunch", title: "Lunch", date: "2026-10-29", time: "13:00", duration: 60,
        calendarEntry: nil),
      RitmTask(
        id: "done", title: "Done", date: "2026-10-29", time: "08:00", completed: true,
        calendarEntry: true),
    ]
    let events = [
      timed("standup", "2026-10-29T05:00:00Z", "2026-10-29T05:30:00Z", title: "Standup"),
      allDay("holiday", "2026-10-29", "2026-10-30"),
    ]
    let entries = DayPlan.occurrences(
      tasks: tasks, events: events, date: "2026-10-29", timeZone: zone, language: .en)
    XCTAssertEqual(entries.map(\.title), ["holiday", "Done", "Standup", "Lunch"])
    XCTAssertEqual(entries.first { $0.title == "Lunch" }?.busy, true)
    XCTAssertEqual(entries.first { $0.title == "Done" }?.busy, false, "completed tasks are free")
    XCTAssertEqual(entries.first { $0.title == "Lunch" }?.key, "ritm:lunch:2026-10-29")
  }

  func testFreeTimeCountsOverlapsOnceAndStartsNow() {
    let events = [
      timed("a", "2026-10-29T05:00:00Z", "2026-10-29T06:00:00Z"),  // 10:00 – 11:00
      timed("b", "2026-10-29T05:30:00Z", "2026-10-29T07:00:00Z"),  // 10:30 – 12:00
      timed("free", "2026-10-29T08:00:00Z", "2026-10-29T09:00:00Z", busy: false),
    ]
    let entries = DayPlan.occurrences(
      tasks: [], events: events, date: "2026-10-29", timeZone: zone, language: .ru)
    // Workday 09:00 – 18:00, now 09:30: 510 minutes left, 120 of them busy.
    XCTAssertEqual(DayPlan.freeMinutes(entries, workStart: 540, workEnd: 1080, now: 570), 390)
    XCTAssertEqual(DayPlan.freeMinutes(entries, workStart: 540, workEnd: 1080, now: 1100), 0)
  }

  func testBusyAllDayEventFillsTheWorkday() {
    let entries = DayPlan.occurrences(
      tasks: [], events: [allDay("offsite", "2026-10-29", "2026-10-30")], date: "2026-10-29",
      timeZone: zone, language: .ru)
    XCTAssertEqual(DayPlan.freeMinutes(entries, workStart: 540, workEnd: 1080, now: 0), 0)
  }

  func testRhythmCoversNineToNineAndCapsEachHour() {
    let events = [
      timed("a", "2026-10-29T04:00:00Z", "2026-10-29T05:00:00Z"),  // 09:00 – 10:00
      timed("b", "2026-10-29T04:00:00Z", "2026-10-29T04:30:00Z"),  // overlaps a
      timed("c", "2026-10-29T10:30:00Z", "2026-10-29T11:00:00Z"),  // 15:30 – 16:00
    ]
    let entries = DayPlan.occurrences(
      tasks: [], events: events, date: "2026-10-29", timeZone: zone, language: .ru)
    let rhythm = DayPlan.rhythm(entries)
    XCTAssertEqual(rhythm.count, 13)
    XCTAssertEqual(rhythm[0], 1)
    XCTAssertEqual(rhythm[1], 0)
    XCTAssertEqual(rhythm[6], 0.5)
  }

  func testUpcomingSkipsCompletedAndFinishedEntries() {
    let tasks = [
      RitmTask(
        id: "past", title: "Past", date: "2026-10-29", time: "09:00", calendarEntry: true),
      RitmTask(
        id: "done", title: "Done", date: "2026-10-29", time: "11:00", completed: true,
        calendarEntry: true),
      RitmTask(
        id: "next", title: "Next", date: "2026-10-29", time: "12:00", calendarEntry: true),
    ]
    let entries = DayPlan.occurrences(
      tasks: tasks, events: [], date: "2026-10-29", timeZone: zone, language: .ru)
    XCTAssertEqual(DayPlan.upcoming(entries, now: 600)?.title, "Next")
    XCTAssertNil(DayPlan.upcoming(entries, now: 800))
  }

  func testTaskSummaryPutsOpenTasksFirstAndKeepsTiesStable() {
    let tasks = [
      RitmTask(id: "b", title: "B", date: "2026-10-29"),
      RitmTask(id: "a", title: "A", date: "2026-10-29"),
      RitmTask(id: "done", title: "Done", date: "2026-10-29", time: "08:00", completed: true),
      RitmTask(id: "timed", title: "Timed", date: "2026-10-29", time: "10:00"),
      RitmTask(id: "event", title: "Event", date: "2026-10-29", kind: .event),
    ]
    let summary = DayTaskSummary(
      tasks: tasks, events: [], date: "2026-10-29", timeZone: zone, language: .en)
    // Untimed entries keep the title order of dayOccurrences; events are not tasks.
    XCTAssertEqual(summary.entries.map(\.task.id), ["timed", "a", "b", "done"])
    XCTAssertEqual(summary.count, 4)
    XCTAssertEqual(summary.completed, 1)
  }

  func testTaskSummaryCountsGoogleTasksAndUnconfirmedStatus() {
    var linked = timed("linked", "2026-10-29T05:00:00Z", "2026-10-29T05:30:00Z")
    linked.taskLink = true
    var checked = timed("checked", "2026-10-29T06:00:00Z", "2026-10-29T06:30:00Z")
    checked.googleTask = GoogleTaskCompletion(
      taskListId: "list", id: "t", etag: "e", status: "completed", connectionId: "c")
    let meeting = timed("meeting", "2026-10-29T07:00:00Z", "2026-10-29T08:00:00Z")
    let summary = DayTaskSummary(
      tasks: [], events: [linked, checked, meeting], date: "2026-10-29", timeZone: zone,
      language: .ru)
    XCTAssertEqual(summary.googleTodos.map(\.title), ["linked", "checked"])
    XCTAssertEqual(summary.count, 2)
    XCTAssertEqual(summary.completed, 1)
    XCTAssertEqual(summary.unknown, 1, "a linked task without a confirmed status")
  }

  func testGreetingIncludesNight() {
    XCTAssertEqual(DayPlan.greeting(hour: 3, language: .ru), "Доброй ночи")
    XCTAssertEqual(DayPlan.greeting(hour: 3, language: .en), "Good evening")
    XCTAssertEqual(DayPlan.greeting(hour: 9, language: .ru), "Доброе утро")
    XCTAssertEqual(DayPlan.greeting(hour: 12, language: .en), "Good afternoon")
    XCTAssertEqual(DayPlan.greeting(hour: 18, language: .ru), "Добрый вечер")
  }

  func testTaskCountUsesRussianPlurals() {
    XCTAssertEqual(DayPlan.taskCount(1, language: .ru), "1 задача")
    XCTAssertEqual(DayPlan.taskCount(3, language: .ru), "3 задачи")
    XCTAssertEqual(DayPlan.taskCount(5, language: .ru), "5 задач")
    XCTAssertEqual(DayPlan.taskCount(21, language: .ru), "21 задача")
    XCTAssertEqual(DayPlan.taskCount(12, language: .ru), "12 задач")
    XCTAssertEqual(DayPlan.taskCount(1, language: .en), "1 task")
    XCTAssertEqual(DayPlan.taskCount(2, language: .en), "2 tasks")
  }
}
