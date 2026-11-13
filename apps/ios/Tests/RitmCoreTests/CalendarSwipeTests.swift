import Foundation
import XCTest

@testable import RitmCore

/// Changing the week of the calendar froze the phone: a week was read one day at a time, and each
/// read parsed every event's instants with a new formatter, built calendars for every wall-clock
/// conversion, and then the same happened again when the network answer arrived. These tests pin
/// the fast arithmetic to the Foundation answers it replaces, pin the rules of the page window and
/// of the read-ahead, and keep an eye on the cost of a week.
final class CalendarSwipeTests: XCTestCase {
  private let zones = [
    "UTC", "Asia/Qyzylorda", "Europe/Berlin", "America/New_York", "Asia/Kolkata",
    "Australia/Lord_Howe", "America/St_Johns",
  ]

  // MARK: Instants

  func testFastInstantMatchesTheFormatter() {
    let values = [
      "2026-11-13T09:30:00+05:00", "2026-11-13T09:30:00Z", "2026-11-13T09:30:00.250Z",
      "2026-11-13T09:30:00.5-03:30", "2026-02-28T23:59:59+14:00", "2024-02-29T00:00:00-12:00",
      "1999-12-31T23:59:59Z", "2026-03-29T01:59:59+00:00", "2026-10-25T02:30:00+02:00",
    ]
    for value in values {
      let fast = CalendarInstants.parse(value)
      let reference = CalendarSwipeLegacy.instant(value)
      XCTAssertNotNil(fast, value)
      XCTAssertEqual(
        fast?.timeIntervalSince1970 ?? 0, reference?.timeIntervalSince1970 ?? 1, accuracy: 0.001, value)
    }
  }

  func testInstantsTheFastPathRefusesStillGoThroughTheFormatter() {
    // The formatter decides these: whatever it says, the answer must be the same.
    let values = [
      "", "2026-11-13", "2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-11-13T25:00:00Z",
      "2026-11-13T09:30:00", "2026-11-13T09:30:00+0500", "2026-11-13 09:30:00Z",
      "2026-11-13T09:30:00.Z", "garbage", "2026-11-13T09:30:00+05:00 ",
    ]
    for value in values {
      let got = CalendarInstants.parse(value)
      let reference = CalendarSwipeLegacy.instant(value)
      XCTAssertEqual(got == nil, reference == nil, "«\(value)»")
      if let got, let reference {
        XCTAssertEqual(got.timeIntervalSince1970, reference.timeIntervalSince1970, accuracy: 0.001, value)
      }
    }
    XCTAssertNil(CalendarEventPolicy.instant(nil))
  }

  // MARK: Wall-clock time and clock changes

  private func instants() -> [Date] {
    // Every 37 minutes over a year, so the clock changes of every zone are crossed, plus the
    // exact moments around the Berlin changes.
    let start = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01
    var result = (0..<(365 * 24 * 60 / 37)).map { start.addingTimeInterval(Double($0) * 37 * 60) }
    for base in [1_774_746_000.0, 1_792_886_400.0] {  // around 2026-03-29 and 2026-10-25 in Berlin
      for step in -150...150 { result.append(Date(timeIntervalSince1970: base + Double(step) * 60)) }
    }
    return result
  }

  func testWallTimeMatchesCalendarInEveryZone() {
    let all = instants()
    for name in zones {
      guard let zone = TimeZone(identifier: name) else { continue }
      for instant in all {
        let fast = CalendarInstants.wall(instant, zone: zone)
        let reference = CalendarSwipeLegacy.wall(instant, zone: zone)
        XCTAssertEqual(fast.date, reference.date, "\(name) \(instant)")
        XCTAssertEqual(fast.minute, reference.minute, "\(name) \(instant)")
        XCTAssertEqual(fast.secondOfDay, reference.seconds, "\(name) \(instant)")
        XCTAssertEqual(fast.epochMinutes, CalendarSwipeLegacy.wallMinutes(reference), "\(name) \(instant)")
      }
    }
  }

  func testAmbiguousHoursMatchTheCalendarCheck() {
    let all = instants()
    var ambiguous = 0
    for name in zones {
      guard let zone = TimeZone(identifier: name) else { continue }
      for instant in all {
        let fast = CalendarEventPolicy.isAmbiguous(instant, zone: zone)
        if fast { ambiguous += 1 }
        XCTAssertEqual(fast, CalendarSwipeLegacy.isAmbiguous(instant, zone: zone), "\(name) \(instant)")
      }
    }
    XCTAssertGreaterThan(ambiguous, 50, "the repeated hours of the clock changes were met")
  }

  // MARK: Reading a day

  private func event(
    _ id: String, _ start: String, _ end: String, zone: String = "Europe/Berlin"
  ) -> GoogleCalendarEvent {
    GoogleCalendarEvent(
      id: id, title: "Event \(id)", start: .init(dateTime: start), end: .init(dateTime: end),
      timeZone: zone, calendarId: "primary", colorId: "3")
  }

  func testReadingADayGivesTheOldAnswerAcrossClockChanges() {
    let events = [
      event("a", "2026-10-25T01:30:00+02:00", "2026-10-25T03:30:00+01:00"),
      event("b", "2026-10-25T02:30:00+02:00", "2026-10-25T02:45:00+02:00"),
      event("c", "2026-10-25T02:30:00+01:00", "2026-10-25T03:15:00+01:00"),
      event("d", "2026-03-29T01:30:00+01:00", "2026-03-29T03:30:00+02:00"),
      event("e", "2026-10-24T23:00:00+02:00", "2026-10-25T01:00:00+02:00"),
      event("f", "2026-10-25T22:00:00+01:00", "2026-10-26T01:00:00+01:00"),
      event("g", "2026-10-25T10:00:00.250+01:00", "2026-10-25T11:00:00+01:00"),
      event("h", "2026-10-25T00:00:00+02:00", "2026-10-25T00:00:00+02:00"),
      event("i", "oops", "2026-10-25T00:00:00+02:00"),
    ]
    let zone = TimeZone(identifier: "Europe/Berlin")!
    for day in ["2026-03-28", "2026-03-29", "2026-10-24", "2026-10-25", "2026-10-26"] {
      let expected = events.compactMap { CalendarSwipeLegacy.timedOccurrence($0, date: day, zone: zone) }
      let got = DayPlan.googleOccurrences(events, date: day, timeZone: "Europe/Berlin")
      XCTAssertEqual(got, expected, day)
    }
    let flagged = DayPlan.googleOccurrences(events, date: "2026-10-25", timeZone: "Europe/Berlin")
    XCTAssertTrue(flagged.contains { $0.clockChange }, "the repeated hour is still flagged")
  }

  func testBatchReadingGivesTheOldAnswerForAWeekInEveryZone() {
    for name in zones {
      guard let zone = TimeZone(identifier: name) else { continue }
      let events = (0..<60).map { index -> GoogleCalendarEvent in
        let day = HabitSchedule.addDays(to: "2026-10-22", days: index % 7) ?? "2026-10-22"
        let hour = index % 22
        return event(
          "e\(index)", "\(day)T\(String(format: "%02d", hour)):15:00Z",
          "\(day)T\(String(format: "%02d", min(23, hour + 1 + index % 3))):45:00Z", zone: name)
      }
      let days = (0..<9).compactMap { HabitSchedule.addDays(to: "2026-10-21", days: $0) }
      let batch = DayPlan.occurrencesByDay(tasks: [], events: events, dates: days, timeZone: name, language: .en)
      for day in days {
        let expected = events.compactMap { CalendarSwipeLegacy.timedOccurrence($0, date: day, zone: zone) }
        let got = (batch[day] ?? []).filter { $0.event != nil }
        XCTAssertEqual(Set(got.map(\.key)), Set(expected.map(\.key)), "\(name) \(day)")
        for entry in expected {
          XCTAssertEqual(got.first { $0.key == entry.key }, entry, "\(name) \(entry.key)")
        }
      }
    }
  }

  func testRepeatingTasksOccurWhereTheyDidBefore() {
    let origins = ["2026-01-31", "2026-02-28", "2026-11-13", "2024-02-29", "2026-12-31", "oops"]
    let kinds: [TaskRepeat] = [.none, .daily, .weekly, .monthly]
    for origin in origins {
      for kind in kinds {
        let task = RitmTask(id: "t", title: "T", date: origin, time: "09:00", repeat: kind)
        for offset in 0..<130 {
          let day = HabitSchedule.addDays(to: "2026-01-20", days: offset * 3) ?? ""
          XCTAssertEqual(
            TaskSchedule.occursOn(task, date: day), CalendarSwipeLegacy.occursOn(task, date: day),
            "\(origin) \(kind) \(day)")
        }
      }
    }
    let undated = RitmTask(id: "u", title: "U", date: nil, repeat: .daily)
    XCTAssertFalse(TaskSchedule.occursOn(undated, date: "2026-11-13"))
  }

  func testColourIDsAreReadWithoutARegularExpression() {
    XCTAssertEqual(CalendarPlan.solidHex("#A1b2C3"), "a1b2c3")
    XCTAssertEqual(CalendarPlan.entryHex("#a1b2c3"), "a1b2c3")
    XCTAssertNil(CalendarPlan.solidHex("#a1b2c"))
    XCTAssertNil(CalendarPlan.solidHex("#a1b2cz"))
    XCTAssertNil(CalendarPlan.solidHex("#a1b2c3d"))
    XCTAssertEqual(CalendarPlan.solidHex("5"), "f6bf26")
    XCTAssertNil(CalendarPlan.solidHex(nil))
  }

  // MARK: Reading ahead

  private func busyWeek() -> (events: [GoogleCalendarEvent], tasks: [RitmTask]) {
    let events = (0..<150).map { index -> GoogleCalendarEvent in
      let day = HabitSchedule.addDays(to: "2026-10-18", days: index % 21) ?? "2026-10-18"
      let hour = 7 + index % 14
      return event(
        "e\(index)", "\(day)T\(String(format: "%02d", hour)):00:00+05:00",
        "\(day)T\(String(format: "%02d", hour + 1)):00:00+05:00", zone: "Asia/Qyzylorda")
    }
    let tasks = (0..<200).map { index -> RitmTask in
      RitmTask(
        id: "t\(index)", title: "Task \(index)",
        date: HabitSchedule.addDays(to: "2026-09-01", days: index % 70), time: "10:00",
        duration: 30, repeat: [.none, .daily, .weekly, .monthly][index % 4], kind: .event,
        calendarEntry: true)
    }
    return (events, tasks)
  }

  func testComputingDaysAheadEqualsReadingThemAndLaysThemOut() {
    let (events, tasks) = busyWeek()
    let days = (0..<7).compactMap { HabitSchedule.addDays(to: "2026-11-08", days: $0) }
    let computed = CalendarDayCompute.compute(
      tasks: tasks, events: events, hidden: [], dates: days, timeZone: "Asia/Qyzylorda", language: .ru)
    let read = DayPlan.occurrencesByDay(
      tasks: tasks, events: events, dates: days, timeZone: "Asia/Qyzylorda", language: .ru)
    for day in days {
      XCTAssertEqual(computed[day]?.entries, read[day])
      XCTAssertEqual(computed[day]?.placed, CalendarPlan.layout(read[day] ?? []))
    }
    XCTAssertTrue(CalendarDayCompute.compute(
      tasks: tasks, events: events, hidden: [], dates: [], timeZone: "UTC", language: .ru).isEmpty)
    let hidden = CalendarDayCompute.compute(
      tasks: tasks, events: events, hidden: [CalendarSources.ritmEvents, "g:primary"], dates: days,
      timeZone: "Asia/Qyzylorda", language: .ru)
    XCTAssertTrue(hidden.values.allSatisfy { $0.entries.isEmpty }, "hidden calendars are left out")
  }

  func testAWeekOfABusyPlannerReadsFasterThanBefore() {
    let (events, tasks) = busyWeek()
    let name = "Asia/Qyzylorda"
    let zone = TimeZone(identifier: name)!
    let days = (0..<7).compactMap { HabitSchedule.addDays(to: "2026-11-08", days: $0) }
    let clock = ContinuousClock()
    // The old model read the week one day at a time: for each day, every event's span, then the
    // events of that day, and every task tested with calendars built for each test.
    let before = clock.measure {
      for day in days {
        _ = CalendarSwipeLegacy.spansCost(events, zone: zone)
        _ = events.compactMap { CalendarSwipeLegacy.timedOccurrence($0, date: day, zone: zone) }
        _ = tasks.filter { CalendarSwipeLegacy.occursOn($0, date: day) }
      }
    }
    var computed: [String: CalendarDayData] = [:]
    let after = clock.measure {
      computed = CalendarDayCompute.compute(
        tasks: tasks, events: events, hidden: [], dates: days, timeZone: name, language: .ru)
    }
    XCTAssertGreaterThan(computed.values.reduce(0) { $0 + $1.entries.count }, 100)
    XCTAssertLessThan(after * 4, before, "a week now \(after), the old way \(before)")
    print("calendar swipe perf: a week read \(after); the same work the old way \(before)")
  }

  func testPageWindowAndLayoutsOfThreeWeeksFitAFrameOrTwo() {
    // What a quick swipe builds when it cannot use the background read: three weeks at once.
    let (events, tasks) = busyWeek()
    let window = CalendarPagerWindow(
      mode: .week, days: CalendarViewMode.week.visibleDays(anchor: "2026-11-11"))
    var warm = window
    warm.warmUp()
    let days = warm.slots.flatMap { warm.days(slot: $0) }
    XCTAssertEqual(days.count, 21)
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      _ = CalendarDayCompute.compute(
        tasks: tasks, events: events, hidden: [], dates: days, timeZone: "Asia/Qyzylorda",
        language: .ru)
    }
    XCTAssertLessThan(elapsed, .milliseconds(250), "three weeks \(elapsed)")
    print("calendar swipe perf: three weeks read \(elapsed)")
  }

  // MARK: Day cache and stamps

  private func data(_ title: String, day: String = "2026-11-11") -> CalendarDayData {
    let entry = DayOccurrence(
      key: "k:\(title)", date: day, title: title, start: 540, end: 600, completed: false,
      allDay: false, busy: true, continued: false, duration: 60, startLabel: nil, endLabel: nil,
      clockChange: false,
      source: .google(event(title, "\(day)T09:00:00+05:00", "\(day)T10:00:00+05:00", zone: "UTC")))
    return CalendarDayData(entries: [entry], placed: CalendarPlan.layout([entry]))
  }

  func testADayThatComesOutTheSameKeepsItsStamp() {
    var cache = CalendarDayCache()
    cache.ingest(["2026-11-11": data("a"), "2026-11-12": data("b", day: "2026-11-12")])
    let first = cache.entry("2026-11-11")?.stamp
    let second = cache.entry("2026-11-12")?.stamp
    XCTAssertNotNil(first)
    XCTAssertNotEqual(first, second)

    cache.invalidate()
    XCTAssertNil(cache.entry("2026-11-11"))
    XCTAssertEqual(cache.missing(["2026-11-11", "2026-11-12"]).count, 2)
    cache.ingest(["2026-11-11": data("a"), "2026-11-12": data("changed", day: "2026-11-12")])
    XCTAssertEqual(cache.entry("2026-11-11")?.stamp, first, "unchanged: nothing to draw again")
    XCTAssertNotEqual(cache.entry("2026-11-12")?.stamp, second, "changed: drawn again")
  }

  func testIngestingNeverReplacesADayThatWasRead() {
    var cache = CalendarDayCache()
    cache.ingest(["2026-11-11": data("a")])
    let stamp = cache.entry("2026-11-11")?.stamp
    cache.ingest(["2026-11-11": data("late result of a background read")])
    XCTAssertEqual(cache.entry("2026-11-11")?.stamp, stamp)
    XCTAssertEqual(cache.entry("2026-11-11")?.data.entries.first?.title, "a")
  }

  func testStampsSurviveTwoChangesInARow() {
    var cache = CalendarDayCache()
    cache.ingest(["2026-11-11": data("a")])
    let stamp = cache.entry("2026-11-11")?.stamp
    cache.invalidate()
    cache.invalidate()
    cache.ingest(["2026-11-11": data("a")])
    XCTAssertEqual(cache.entry("2026-11-11")?.stamp, stamp)
  }

  // MARK: Page window

  private func week(_ anchor: String = "2026-11-11") -> CalendarPagerWindow {
    CalendarPagerWindow(mode: .week, days: CalendarViewMode.week.visibleDays(anchor: anchor))
  }

  func testTheFirstFrameBuildsOnlyTheVisiblePeriod() {
    let window = week()
    XCTAssertEqual(window.slots, [0])
    XCTAssertFalse(window.warm)
    XCTAssertEqual(window.currentDays.first, "2026-11-08")
    XCTAssertEqual(window.currentDays.count, 7)
  }

  func testWarmingBuildsBothNeighbours() {
    var window = week()
    window.warmUp()
    XCTAssertEqual(window.slots, [-1, 0, 1])
    XCTAssertEqual(window.days(slot: -1).first, "2026-11-01")
    XCTAssertEqual(window.days(slot: 1).first, "2026-11-15")
    XCTAssertFalse(window.needsWarmUp(direction: 1))
    XCTAssertFalse(window.needsWarmUp(direction: -1))
  }

  func testAMoveKeepsThePageItCameFromAndBuildsTheNextOneLater() {
    var window = week()
    window.warmUp()
    window.commit(direction: 1)
    XCTAssertEqual(window.slot, 1)
    XCTAssertEqual(window.slots, [0, 1], "the way back is alive, the way ahead is not yet")
    XCTAssertEqual(window.currentDays.first, "2026-11-15")
    XCTAssertTrue(window.needsWarmUp(direction: 1))
    XCTAssertFalse(window.needsWarmUp(direction: -1))
    window.warmUp()
    XCTAssertEqual(window.slots, [0, 1, 2])
    window.commit(direction: -1)
    window.commit(direction: -1)
    XCTAssertEqual(window.slot, -1)
    XCTAssertEqual(window.currentDays.first, "2026-11-01")
    XCTAssertEqual(window.slots, [-1, 0], "only the page that was just left stays")
  }

  func testPagesKeepTheirSlotWhenTheWindowMoves() {
    var window = week()
    window.warmUp()
    let nextWeek = window.days(slot: 1)
    window.commit(direction: 1)
    XCTAssertEqual(window.days(slot: 1), nextWeek, "a slot never changes its days")
    XCTAssertEqual(window.currentDays, nextWeek)
  }

  func testDaysChosenFromOutsideStartANewWindowWithoutMovingTheStrip() {
    var window = week()
    window.warmUp()
    window.commit(direction: 1)
    window.warmUp()
    let same = window.aligned(mode: .week, days: window.currentDays)
    XCTAssertEqual(same, window, "a swipe's own change is recognised")

    let today = window.aligned(mode: .week, days: CalendarViewMode.week.visibleDays(anchor: "2026-12-30"))
    XCTAssertEqual(today.epoch, window.epoch + 1)
    XCTAssertEqual(today.slot, window.slot, "the strip stays where it is: nothing to slide")
    XCTAssertEqual(today.slots, [today.slot])
    XCTAssertEqual(today.currentDays.first, "2026-12-27")

    let three = window.aligned(mode: .threeDays, days: CalendarViewMode.threeDays.visibleDays(anchor: "2026-11-11"))
    XCTAssertEqual(three.currentDays, ["2026-11-11", "2026-11-12", "2026-11-13"])
    XCTAssertEqual(three.days(slot: three.slot + 1), ["2026-11-14", "2026-11-15", "2026-11-16"])
    XCTAssertEqual(three.days(slot: three.slot - 1), ["2026-11-08", "2026-11-09", "2026-11-10"])
  }

  func testTheDayViewWalksOneDayAtATime() {
    var window = CalendarPagerWindow(mode: .day, days: ["2026-11-30"])
    window.warmUp()
    XCTAssertEqual(window.days(slot: 1), ["2026-12-01"])
    XCTAssertEqual(window.days(slot: -1), ["2026-11-29"])
  }

  func testWhatIsPreparedAheadStartsWithTheNearestDays() {
    var window = week()
    window.warmUp()
    let days = window.daysToPrepare()
    XCTAssertEqual(days.count, 35)
    XCTAssertEqual(Array(days.prefix(7)), window.currentDays)
    XCTAssertEqual(Set(days).count, days.count, "no day twice")
    XCTAssertEqual(days.last, window.days(slot: -2).last)
  }

  // MARK: Reading Google ahead

  func testOneReadCoversSeveralSwipesAndStaysWithinWhatTheServerAccepts() {
    for mode in [CalendarViewMode.day, .threeDays, .week] {
      let load = mode.loadRange(anchor: "2026-11-11")
      let span = days(from: load.from, to: load.to)
      XCTAssertLessThanOrEqual(span, 93, "\(mode) reads \(span) days")
      XCTAssertTrue(CalendarViewMode.covers(load, mode.warmRange(anchor: "2026-11-11")))
      XCTAssertTrue(CalendarViewMode.covers(mode.warmRange(anchor: "2026-11-11"), mode.fetchRange(anchor: "2026-11-11")))
    }
    // The week: the periods a few swipes away are inside the first read.
    let load = CalendarViewMode.week.loadRange(anchor: "2026-11-11")
    XCTAssertEqual(load.from, "2026-10-04")
    XCTAssertEqual(load.to, "2026-12-20")
  }

  private func days(from: String, to: String) -> Int {
    var count = 0
    var day = from
    while day < to, count < 400 {
      day = HabitSchedule.addDays(to: day, days: 1) ?? to
      count += 1
    }
    return count
  }

  func testSwipingInsideTheReadNeverAsksForAnotherReadUntilItRunsLow() {
    let mode = CalendarViewMode.week
    var anchor = "2026-11-11"
    let read = mode.loadRange(anchor: anchor)
    XCTAssertEqual(mode.readDecision(anchor: anchor, read: nil), .now)
    XCTAssertEqual(mode.readDecision(anchor: anchor, read: read), .none)
    var decisions: [CalendarViewMode.ReadDecision] = []
    for _ in 0..<5 {
      anchor = mode.stepped(anchor: anchor, by: 1)
      decisions.append(mode.readDecision(anchor: anchor, read: read))
    }
    XCTAssertEqual(decisions, [.none, .none, .none, .whenIdle, .now])
    // Going back is the same story from the other side.
    anchor = "2026-11-11"
    decisions = []
    for _ in 0..<5 {
      anchor = mode.stepped(anchor: anchor, by: -1)
      decisions.append(mode.readDecision(anchor: anchor, read: read))
    }
    XCTAssertEqual(decisions.first, CalendarViewMode.ReadDecision.none)
    XCTAssertEqual(decisions.last, .now)
  }

  func testTheMonthReadStaysWithinTheServerCapAndSwipesInsideItReadNothing() {
    let anchors = (1...24).map { String(format: "%04d-%02d-15", 2026 + ($0 - 1) / 12, ($0 - 1) % 12 + 1) }
    for anchor in anchors + ["2027-05-31", "2026-08-01", "2026-03-31"] {
      let load = CalendarViewMode.month.loadRange(anchor: anchor)
      XCTAssertLessThanOrEqual(days(from: load.from, to: load.to), 93, anchor)
      XCTAssertTrue(CalendarViewMode.covers(load, CalendarViewMode.month.fetchRange(anchor: anchor)))
      XCTAssertTrue(
        CalendarPlan.monthDays(containing: anchor).allSatisfy { $0 >= load.from && $0 < load.to },
        "the whole grid is read: " + anchor)
      for step in [-1, 1] {
        let next = CalendarViewMode.month.stepped(anchor: anchor, by: step)
        XCTAssertEqual(
          CalendarViewMode.month.readDecision(anchor: next, read: load), .none, anchor + " (step)")
      }
    }
    let load = CalendarViewMode.month.loadRange(anchor: "2026-11-11")
    XCTAssertEqual(CalendarViewMode.month.readDecision(anchor: "2026-11-11", read: nil), .now)
    XCTAssertEqual(CalendarViewMode.month.readDecision(anchor: "2027-03-11", read: load), .now)
  }

  func testTheScheduleKeepsItsOwnRange() {
    let read = CalendarViewMode.schedule.fetchRange(anchor: "2026-11-11")
    XCTAssertEqual(CalendarViewMode.schedule.loadRange(anchor: "2026-11-11").to, read.to)
    XCTAssertEqual(CalendarViewMode.schedule.readDecision(anchor: "2026-11-11", read: read), .none)
    XCTAssertEqual(
      CalendarViewMode.schedule.readDecision(anchor: "2026-11-11", scheduleDays: 70, read: read), .now)
  }

  func testAFarJumpNeedsARead() {
    let read = CalendarViewMode.week.loadRange(anchor: "2026-11-11")
    XCTAssertEqual(CalendarViewMode.week.readDecision(anchor: "2027-03-01", read: read), .now)
    XCTAssertEqual(CalendarViewMode.day.readDecision(anchor: "2026-11-12", read: read), .none)
  }

  func testTheSwipeStepsOfThePagerAndOfThePageAgree() {
    for mode in [CalendarViewMode.day, .threeDays, .week] {
      var window = CalendarPagerWindow(mode: mode, days: mode.visibleDays(anchor: "2026-11-11"))
      var anchor = "2026-11-11"
      for step in [1, 1, -1, 1, 1, 1, -1, -1] {
        window.commit(direction: step)
        anchor = mode.stepped(anchor: anchor, by: step)
        XCTAssertEqual(window.currentDays, mode.visibleDays(anchor: anchor), "\(mode)")
      }
    }
  }
}
