import Foundation
import XCTest

@testable import RitmCore

/// The month used to freeze the app: every day re-read every event, parsing instants and building
/// calendars each time. These tests pin the batch reading to the old per-day result and keep an
/// eye on how long a month takes; the filter of the side menu is covered here too.
final class CalendarPerformanceTests: XCTestCase {
  private let zone = "Asia/Qyzylorda"
  private let firstDay = "2026-11-01"

  private func dates(_ count: Int) -> [String] {
    (0..<count).compactMap { HabitSchedule.addDays(to: firstDay, days: $0) }
  }

  private func timed(_ index: Int, day: Int, hour: Int, hours: Int, calendar: String = "primary")
    -> GoogleCalendarEvent
  {
    let date = HabitSchedule.addDays(to: firstDay, days: day) ?? firstDay
    let start = String(format: "%@T%02d:00:00+05:00", date, hour)
    let end = String(format: "%@T%02d:30:00+05:00", date, min(23, hour + hours))
    return GoogleCalendarEvent(
      id: "e\(index)", title: "Event \(index)", start: .init(dateTime: start), end: .init(dateTime: end),
      timeZone: zone, calendarId: calendar, colorId: String(index % 11 + 1))
  }

  /// 40 events per week-and-a-half: a busy month of 6 weeks, a few all-day and multi-day ones.
  private func busyMonth(_ count: Int = 240) -> [GoogleCalendarEvent] {
    var result = (0..<count).map { timed($0, day: $0 % 42, hour: 8 + $0 % 12, hours: 1 + $0 % 3) }
    result.append(
      GoogleCalendarEvent(
        id: "trip", title: "Trip", start: .init(date: "2026-11-10"), end: .init(date: "2026-11-13"),
        timeZone: zone, allDay: true))
    result.append(
      GoogleCalendarEvent(
        id: "night", title: "Night", start: .init(dateTime: "2026-11-11T22:00:00+05:00"),
        end: .init(dateTime: "2026-11-12T02:00:00+05:00"), timeZone: zone))
    return result
  }

  private func tasks() -> [RitmTask] {
    (0..<20).map {
      RitmTask(
        id: "t\($0)", title: "Task \($0)", date: HabitSchedule.addDays(to: firstDay, days: $0 * 2),
        time: "09:00", duration: 45, kind: $0 % 2 == 0 ? .task : .event, calendarEntry: true)
    }
  }

  func testBatchReadingMatchesReadingDayByDay() {
    let events = busyMonth(80)
    let days = dates(42)
    let batch = DayPlan.occurrencesByDay(
      tasks: tasks(), events: events, dates: days, timeZone: zone, language: .ru)
    XCTAssertEqual(batch.count, 42)
    for day in days {
      let single = DayPlan.occurrences(
        tasks: tasks(), events: events, date: day, timeZone: zone, language: .ru)
      XCTAssertEqual(batch[day], single, "day \(day)")
    }
    XCTAssertEqual(batch["2026-11-12"]?.contains { $0.title == "Night" }, true, "the part after midnight")
    XCTAssertEqual(batch["2026-11-12"]?.contains { $0.title == "Trip" }, true, "an all-day span")
    XCTAssertEqual(batch["2026-11-13"]?.contains { $0.title == "Trip" }, false, "the end day is exclusive")
  }

  func testBatchReadingOfABusyMonthIsFast() {
    let events = busyMonth()
    let list = tasks()
    let days = dates(42)
    let clock = ContinuousClock()
    var batch: [String: [DayOccurrence]] = [:]
    let batchTime = clock.measure {
      batch = DayPlan.occurrencesByDay(
        tasks: list, events: events, dates: days, timeZone: zone, language: .ru)
    }
    let dayByDay = clock.measure {
      for day in days.prefix(14) {
        _ = DayPlan.occurrences(tasks: list, events: events, date: day, timeZone: zone, language: .ru)
      }
    }
    XCTAssertGreaterThan(batch.values.reduce(0) { $0 + $1.count }, 200)
    // The old way cost this much for a third of the month; the whole month in one go must not
    // cost more than that (it is several times cheaper), and stay far below a frame budget cap.
    XCTAssertLessThan(batchTime, dayByDay * 2 + .milliseconds(5), "batch \(batchTime) vs 14 days \(dayByDay)")
    XCTAssertLessThan(batchTime, .milliseconds(400), "batch \(batchTime)")
    print("calendar perf: 42 days batch \(batchTime), 14 days one by one \(dayByDay)")
  }

  func testMonthRowsHaveSixWeeksAndLimitTheBars() {
    let batch = DayPlan.occurrencesByDay(
      tasks: tasks(), events: busyMonth(), dates: CalendarPlan.monthDays(containing: "2026-11-11"),
      timeZone: zone, language: .ru)
    let rows = CalendarPlan.monthRows(
      anchor: "2026-11-11", today: "2026-11-11", selected: "2026-11-15", limit: 3, stamp: 7
    ) { batch[$0] ?? [] }
    XCTAssertEqual(rows.count, 6)
    XCTAssertTrue(rows.allSatisfy { $0.count == 7 })
    XCTAssertEqual(rows[0][0].day, "2026-11-01", "November 2026 starts on a Sunday")
    XCTAssertTrue(rows.joined().allSatisfy { $0.bars.count <= 3 })
    XCTAssertEqual(rows.joined().filter(\.isToday).map(\.day), ["2026-11-11"])
    XCTAssertEqual(rows.joined().filter(\.isSelected).map(\.day), ["2026-11-15"])
    XCTAssertEqual(rows[5].filter { !$0.inMonth }.count, 7, "the last row is December")
    let busy = rows.joined().first { $0.total > 3 }
    XCTAssertNotNil(busy)
    XCTAssertEqual((busy?.bars.count ?? 0) + (busy?.more ?? 0), busy?.total, "bars plus the counter cover the day")
  }

  func testBuildingMonthCellsTakesMilliseconds() {
    let batch = DayPlan.occurrencesByDay(
      tasks: tasks(), events: busyMonth(240), dates: CalendarPlan.monthDays(containing: "2026-11-11"),
      timeZone: zone, language: .ru)
    let clock = ContinuousClock()
    var rows: [[CalendarMonthCell]] = []
    let elapsed = clock.measure {
      for _ in 0..<10 {
        rows = CalendarPlan.monthRows(
          anchor: "2026-11-11", today: "2026-11-11", selected: "2026-11-11", limit: 4, stamp: 1
        ) { batch[$0] ?? [] }
      }
    }
    XCTAssertEqual(rows.count, 6)
    XCTAssertLessThan(elapsed / 10, .milliseconds(25), "per build \(elapsed / 10)")
    print("calendar perf: month cells per build \(elapsed / 10)")
  }

  func testMonthCellsAreEqualUntilTheirDataChanges() {
    func cell(stamp: Int, today: Bool = false) -> CalendarMonthCell {
      CalendarMonthCell(
        day: "2026-11-11", number: 11, inMonth: true, isToday: today, isSelected: false, bars: [],
        more: 0, total: 0, stamp: stamp)
    }
    XCTAssertEqual(cell(stamp: 1), cell(stamp: 1))
    XCTAssertNotEqual(cell(stamp: 1), cell(stamp: 2))
    XCTAssertNotEqual(cell(stamp: 1), cell(stamp: 1, today: true))
  }

  func testRangeCoverage() {
    let week = CalendarViewMode.week.fetchRange(anchor: "2026-11-11")
    XCTAssertTrue(CalendarViewMode.covers(week, CalendarViewMode.day.fetchRange(anchor: "2026-11-11")))
    XCTAssertTrue(CalendarViewMode.covers(week, week))
    XCTAssertFalse(CalendarViewMode.covers(week, CalendarViewMode.week.fetchRange(anchor: "2026-11-18")))
    XCTAssertFalse(CalendarViewMode.covers(nil, week))
    XCTAssertFalse(
      CalendarViewMode.covers(week, CalendarViewMode.month.fetchRange(anchor: "2026-11-11")),
      "the month reads further than the week")
    let month = CalendarViewMode.month.fetchRange(anchor: "2026-11-11")
    XCTAssertTrue(CalendarViewMode.covers(month, CalendarViewMode.week.fetchRange(anchor: "2026-11-11")))
  }

  // MARK: Calendars in the side menu

  func testCalendarNamesUseTheBestLabelThereIs() {
    func name(_ id: String, _ ordinal: Int = 1, _ language: Language = .ru) -> String {
      CalendarSources.name(calendarId: id, email: "me@mail.com", language: language, ordinal: ordinal)
    }
    XCTAssertEqual(name("primary"), "Основной календарь")
    XCTAssertEqual(name("ME@mail.com"), "Основной календарь")
    XCTAssertEqual(name("primary", 1, .en), "Main calendar")
    XCTAssertEqual(name("ru.russian#holiday@group.v.calendar.google.com"), "Праздники")
    XCTAssertEqual(name("addressbook#contacts@group.v.calendar.google.com"), "Дни рождения")
    XCTAssertEqual(name("gym@club.org"), "gym@club.org")
    XCTAssertEqual(name("abc123@group.calendar.google.com", 3), "Календарь 3")
  }

  func testTheListHasGoogleCalendarsThenRitmKinds() {
    let events = [
      timed(1, day: 0, hour: 9, hours: 1, calendar: "gym@club.org"), timed(2, day: 1, hour: 9, hours: 1),
    ]
    let list = CalendarSources.list(
      events: events, tasks: tasks(), filter: CalendarFilter(), email: "me@mail.com", language: .ru)
    XCTAssertEqual(list.map(\.id), ["g:primary", "g:gym@club.org", "r:task", "r:event"])
    XCTAssertEqual(list.map(\.isRitm), [false, false, true, true])
    XCTAssertEqual(list.first?.name, "Основной календарь")
    XCTAssertNotNil(list.first?.colorId)
    XCTAssertEqual(list[2].name, "Задачи")
    // No Ritm event: no row for it.
    let onlyTasks = tasks().filter { $0.kind == .task }
    XCTAssertEqual(
      CalendarSources.list(events: [], tasks: onlyTasks, filter: CalendarFilter(), email: "", language: .ru)
        .map(\.id), ["r:task"])
    XCTAssertTrue(
      CalendarSources.list(events: [], tasks: [], filter: CalendarFilter(), email: "", language: .ru).isEmpty)
  }

  func testAHiddenCalendarKeepsItsRowAndIsOnlyFilteredFromWhatIsDrawn() {
    var filter = CalendarFilter()
    let events = [timed(1, day: 0, hour: 9, hours: 1, calendar: "gym@club.org"), timed(2, day: 1, hour: 9, hours: 1)]
    XCTAssertTrue(filter.remember(events))
    XCTAssertFalse(filter.remember(events), "nothing new the second time")
    filter.toggle("g:gym@club.org")
    // The calendar has no event in the loaded range now, but its row stays.
    let list = CalendarSources.list(
      events: [events[1]], tasks: [], filter: filter, email: "", language: .ru)
    XCTAssertEqual(list.map(\.id), ["g:primary", "g:gym@club.org"], "the main one first")
    XCTAssertEqual(CalendarSources.visible(events, hidden: filter.hidden).map(\.id), ["e2"])
    XCTAssertEqual(events.count, 2, "the loaded events are untouched")
    filter.toggle("g:gym@club.org")
    XCTAssertEqual(CalendarSources.visible(events, hidden: filter.hidden).count, 2)
    XCTAssertEqual(CalendarSources.visible(tasks(), hidden: ["r:task"]).filter { $0.kind == .task }.count, 0)
    XCTAssertEqual(CalendarSources.visible(tasks(), hidden: ["r:task"]).count, 10)
  }

  func testEverythingHiddenIsDetectedAndTheFilterSurvivesStorage() throws {
    let list = CalendarSources.list(
      events: [timed(1, day: 0, hour: 9, hours: 1)], tasks: tasks(), filter: CalendarFilter(), email: "",
      language: .ru)
    XCTAssertFalse(CalendarSources.allHidden(list, hidden: ["g:primary"]))
    XCTAssertTrue(CalendarSources.allHidden(list, hidden: Set(list.map(\.id))))
    XCTAssertFalse(CalendarSources.allHidden([], hidden: []), "nothing to hide is not everything hidden")
    var filter = CalendarFilter(hidden: ["g:primary", "r:task"], known: ["primary": "9"])
    filter.toggle("r:event")
    let stored = try JSONEncoder().encode(filter)
    XCTAssertEqual(try JSONDecoder().decode(CalendarFilter.self, from: stored), filter)
  }
}
