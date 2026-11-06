import Foundation
import XCTest

@testable import RitmCore

final class LocalNotificationPlanTests: XCTestCase {
  private func instant(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  private func snapshot(
    _ tasks: [RitmTask], zone: String = "UTC", language: Language = .ru, briefing: Bool = false
  ) -> Bootstrap {
    Bootstrap(
      tasks: tasks,
      settings: AccountSettings(
        language: language, timeZone: zone, notifications: true, dailyBriefing: briefing))
  }

  private func event(
    _ id: String, start: String = "2026-11-06T12:00:00Z",
    end: String = "2026-11-06T13:00:00Z", task: GoogleTaskCompletion? = nil,
    taskLink: Bool? = nil
  ) -> GoogleCalendarEvent {
    GoogleCalendarEvent(
      id: id, title: id, start: .init(dateTime: start), end: .init(dateTime: end),
      timeZone: "UTC", taskLink: taskLink, googleTask: task)
  }

  func testTimedTasksUseAccountZoneSelectedLeadAndLanguage() throws {
    let task = RitmTask(id: "t", title: "My original title", date: "2026-11-06", time: "10:00")
    let now = instant("2026-11-06T03:00:00Z")
    let plans = LocalNotificationPlanner.plans(
      snapshot: snapshot([task], zone: "Asia/Qyzylorda", language: .en),
      leadMinutes: 30, accountEpoch: "a", until: now.addingTimeInterval(86_400), now: now)
    let plan = try XCTUnwrap(plans.first)
    XCTAssertEqual(plans.count, 1)
    XCTAssertEqual(plan.fireDate, instant("2026-11-06T04:30:00Z"))
    XCTAssertEqual(plan.title, task.title)
    XCTAssertEqual(plan.body, "10:00–10:30")
    XCTAssertEqual(plan.destination, .task(id: "t", date: "2026-11-06"))
    XCTAssertEqual(plan.expiresAt, now.addingTimeInterval(86_400))
    XCTAssertEqual(plan.accountEpoch, LocalNotificationNamespace.key("a"))
  }

  func testRecurrenceCompletionDateOnlyAndMidnightContinuation() {
    let now = instant("2026-11-06T00:01:00Z")
    let tasks = [
      RitmTask(id: "done", title: "Done", date: "2026-11-06", time: "12:00", completed: true),
      RitmTask(id: "date", title: "Date only", date: "2026-11-06"),
      RitmTask(
        id: "daily", title: "Daily", date: "2026-11-05", time: "12:00", repeat: .daily,
        completedDates: ["2026-11-06"]),
      RitmTask(id: "overnight", title: "Already started", date: "2026-11-05", time: "23:30", duration: 120),
    ]
    let plans = LocalNotificationPlanner.plans(
      snapshot: snapshot(tasks), until: now.addingTimeInterval(48 * 3600), now: now)
    XCTAssertEqual(plans.count, 1)
    XCTAssertEqual(plans.first?.destination, .task(id: "daily", date: "2026-11-07"))
  }

  func testGoogleOnlyUsesKnownTimedUnfinishedEntriesAndDedupesInstances() {
    let now = instant("2026-11-06T08:00:00Z")
    var done = GoogleTaskCompletion(
      taskListId: "l", id: "done", etag: "e", status: "completed", connectionId: "c")
    let complete = event("done", task: done)
    done.status = "needsAction"
    let todo = event("todo", task: done)
    var allDay = event("all-day")
    allDay.allDay = true
    allDay.start = .init(date: "2026-11-06")
    allDay.end = .init(date: "2026-11-07")
    var dateOnly = event("date-only")
    dateOnly.start = .init(date: "2026-11-06")
    let ordinary = event("ordinary")
    let unknown = event("unknown", taskLink: true)
    let invalidStatus = event("bad-status", task: GoogleTaskCompletion(
      taskListId: "l", id: "bad", etag: "e", status: "unknown", connectionId: "c"))
    let plans = LocalNotificationPlanner.plans(
      snapshot: snapshot([]), events: [complete, todo, allDay, dateOnly, ordinary, unknown, invalidStatus, ordinary],
      calendarReady: true, until: now.addingTimeInterval(86_400), now: now)
    XCTAssertEqual(plans.count, 2)
    XCTAssertEqual(Set(plans.map(\.title)), ["todo", "ordinary"])
    XCTAssertTrue(LocalNotificationPlanner.plans(
      snapshot: snapshot([]), events: [ordinary], calendarReady: true, calendarPartial: true,
      until: now.addingTimeInterval(86_400), now: now).isEmpty)
    XCTAssertTrue(LocalNotificationPlanner.plans(
      snapshot: snapshot([]), events: [ordinary], until: now.addingTimeInterval(86_400), now: now).isEmpty)
  }

  func testGoogleKeepsAbsoluteTimeAcrossAccountZoneAndRecurrenceInstances() throws {
    let now = instant("2026-11-06T00:00:00Z")
    let first = event("instance-a", start: "2026-11-06T10:00:00+09:00", end: "2026-11-06T11:00:00+09:00")
    let second = event("instance-b", start: "2026-11-07T10:00:00+09:00", end: "2026-11-07T11:00:00+09:00")
    let plans = LocalNotificationPlanner.plans(
      snapshot: snapshot([], zone: "America/New_York"), events: [second, first], calendarReady: true,
      leadMinutes: 0, until: now.addingTimeInterval(48 * 3600), now: now)
    XCTAssertEqual(plans.count, 2)
    XCTAssertEqual(plans.first?.fireDate, instant("2026-11-06T01:00:00Z"))
    XCTAssertEqual(plans.first?.destination, .googleEvent(id: "instance-a", calendarID: "primary", date: "2026-11-05"))
    XCTAssertNotEqual(plans.first?.identifier, plans.last?.identifier)
  }

  func testInvalidAndElapsedSchedulesNeverBecomeNotifications() {
    let now = instant("2026-11-06T12:00:00Z")
    let tasks = [
      RitmTask(id: "past", title: "Past", date: "2026-11-06", time: "12:05"),
      RitmTask(id: "invalid", title: "Invalid", date: "2026-11-06", time: "25:00"),
      RitmTask(id: "future", title: "Beyond horizon", date: "2026-11-09", time: "12:00"),
    ]
    let source = snapshot(tasks)
    XCTAssertTrue(LocalNotificationPlanner.plans(
      snapshot: source, until: now.addingTimeInterval(7 * 86_400), now: now).isEmpty)
    XCTAssertTrue(LocalNotificationPlanner.plans(snapshot: source, until: now, now: now).isEmpty)
    XCTAssertTrue(LocalNotificationPlanner.plans(
      snapshot: source, leadMinutes: 17, until: now.addingTimeInterval(86_400), now: now).isEmpty)
    XCTAssertTrue(LocalNotificationPlanner.plans(
      snapshot: snapshot(tasks, zone: "invalid/zone"), until: now.addingTimeInterval(86_400), now: now).isEmpty)
    var off = snapshot([RitmTask(id: "ok", title: "Future", date: "2026-11-06", time: "16:00")])
    off.settings.notifications = false
    XCTAssertTrue(LocalNotificationPlanner.plans(
      snapshot: off, until: now.addingTimeInterval(86_400), now: now).isEmpty)
  }

  func testLimitKeepsEarliestRemindersAndReservesOtherNamespaces() {
    let now = instant("2026-11-06T00:00:00Z")
    let tasks = (0..<70).reversed().map {
      RitmTask(
        id: "t\($0)", title: "\($0)", date: "2026-11-06",
        time: TaskSchedule.minuteTime(60 + $0 * 5))
    }
    let plans = LocalNotificationPlanner.plans(
      snapshot: snapshot(tasks), until: now.addingTimeInterval(86_400), now: now)
    XCTAssertEqual(plans.count, 48)
    XCTAssertEqual(plans.first?.title, "0")
    XCTAssertEqual(plans.last?.title, "47")
    XCTAssertEqual(plans.map(\.fireDate), plans.map(\.fireDate).sorted { $0! < $1! })
  }

  func testAmbiguousAndNonexistentLocalDSTTimesAreSkippedButGoogleInstantsRemain() {
    for day in ["2026-03-08", "2026-11-01"] {
      let now = instant("\(day)T00:00:00Z")
      let wall = day == "2026-03-08" ? "02:30" : "01:30"
      let task = RitmTask(id: "dst", title: "Ambiguous", date: day, time: wall)
      XCTAssertTrue(LocalNotificationPlanner.plans(
        snapshot: snapshot([task], zone: "America/New_York"),
        until: now.addingTimeInterval(86_400), now: now).isEmpty)
    }
    let now = instant("2026-11-01T00:00:00Z")
    let plans = LocalNotificationPlanner.plans(
      snapshot: snapshot([], zone: "America/New_York"),
      events: [
        event("first", start: "2026-11-01T01:30:00-04:00", end: "2026-11-01T01:45:00-04:00"),
        event("second", start: "2026-11-01T01:30:00-05:00", end: "2026-11-01T01:45:00-05:00"),
      ], calendarReady: true, until: now.addingTimeInterval(86_400), now: now)
    XCTAssertEqual(plans.count, 2)
    XCTAssertEqual(plans[1].fireDate!.timeIntervalSince(plans[0].fireDate!), 3600)
  }

  func testEpochSeparatesAccountsAndBriefingDoesNotClaimPartialTotals() {
    let now = instant("2026-11-06T08:00:00Z")
    let source = snapshot([], briefing: true)
    let first = LocalNotificationPlanner.plans(
      snapshot: source, accountEpoch: "first", until: now.addingTimeInterval(3600 * 2), now: now)
    let second = LocalNotificationPlanner.plans(
      snapshot: source, accountEpoch: "second", until: now.addingTimeInterval(3600 * 2), now: now)
    XCTAssertEqual(first.count, 1)
    XCTAssertNotEqual(first.first?.identifier, second.first?.identifier)
    XCTAssertEqual(first.first?.destination, .day)
    XCTAssertFalse(first[0].body.contains("0"))
  }

  func testGoogleTestUsesExactCalendarTitleAndAccountClockRangeWithoutChangingItsSchedule() throws {
    let now = instant("2026-11-06T16:00:00Z")
    let expiry = now.addingTimeInterval(86_400)
    let value = event("Test", start: "2026-11-06T22:45:00+05:00", end: "2026-11-06T23:45:00+05:00")
    let epoch = LocalNotificationNamespace.key("calendar-format")
    for language in Language.allCases {
      let plans = LocalNotificationPlanner.plans(
        snapshot: snapshot([], zone: "Asia/Qyzylorda", language: language), events: [value],
        calendarReady: true, leadMinutes: 30, accountEpoch: "calendar-format", until: expiry, now: now)
      let plan = try XCTUnwrap(plans.first)
      XCTAssertEqual(plans.count, 1)
      XCTAssertEqual(plan.title, "Test")
      XCTAssertEqual(plan.body, "22:45–23:45")
      XCTAssertEqual(plan.fireDate, instant("2026-11-06T17:15:00Z"))
      XCTAssertEqual(plan.identifier, LocalNotificationNamespace.reminders
        + "\(epoch).google." + LocalNotificationNamespace.key("primary", "Test"))
      XCTAssertEqual(plan.destination, .googleEvent(id: "Test", calendarID: "primary", date: "2026-11-06"))
      XCTAssertEqual(plan.threadIdentifier, "ritm.reminders")
      XCTAssertEqual(plan.categoryIdentifier, "RITM_GOOGLE_REMINDER")
      XCTAssertEqual(plan.expiresAt, expiry)
      XCTAssertEqual(plan.accountEpoch, epoch)
    }
  }

  func testTimedTaskKeepsItsOriginalTitleAndDurationInTwentyFourHourTextForBothLanguages() throws {
    let now = instant("2026-11-06T08:00:00Z")
    let task = RitmTask(id: "lesson", title: "Dr. Иванов — Gym 2×10", date: "2026-11-06",
      time: "14:05", duration: 90)
    for language in Language.allCases {
      for lead in [0, 30, 60] {
        let plan = try XCTUnwrap(LocalNotificationPlanner.plans(
          snapshot: snapshot([task], language: language), leadMinutes: lead,
          accountEpoch: "task-format", until: now.addingTimeInterval(86_400), now: now).first)
        XCTAssertEqual(plan.title, task.title)
        XCTAssertEqual(plan.body, "14:05–15:35")
        XCTAssertEqual(plan.fireDate, instant("2026-11-06T14:05:00Z").addingTimeInterval(-Double(lead) * 60))
        XCTAssertEqual(plan.identifier, LocalNotificationNamespace.reminders
          + LocalNotificationNamespace.key("task-format") + ".task."
          + LocalNotificationNamespace.key("lesson", "2026-11-06"))
        XCTAssertEqual(plan.destination, .task(id: "lesson", date: "2026-11-06"))
        XCTAssertEqual(plan.categoryIdentifier, "RITM_TASK_REMINDER")
      }
    }
  }

  func testGoogleSourceOffsetIsConvertedToTheAccountZoneForTextAndRoute() throws {
    let now = instant("2026-11-06T14:00:00Z")
    var value = event("tokyo", start: "2026-11-07T01:45:00+09:00", end: "2026-11-07T02:30:00+09:00")
    value.title = "東京 lesson"
    value.timeZone = "Asia/Tokyo"
    let plan = try XCTUnwrap(LocalNotificationPlanner.plans(
      snapshot: snapshot([], zone: "Asia/Qyzylorda", language: .en), events: [value],
      calendarReady: true, leadMinutes: 15, until: now.addingTimeInterval(86_400), now: now).first)
    XCTAssertEqual(plan.title, "東京 lesson")
    XCTAssertEqual(plan.body, "21:45–22:30")
    XCTAssertEqual(plan.fireDate, instant("2026-11-06T16:30:00Z"))
    XCTAssertEqual(plan.destination, .googleEvent(id: "tokyo", calendarID: "primary", date: "2026-11-06"))
  }

  private func assertOvernightNovemberRange(
    _ body: String, language: Language, startTime: String, endTime: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let sides = body.split(separator: "–", omittingEmptySubsequences: false)
    XCTAssertEqual(sides.count, 2, body, file: file, line: line)
    guard sides.count == 2 else { return }
    let month = language == .ru ? "ноя" : "nov"
    for (index, day, time) in [(0, "6", startTime), (1, "7", endTime)] {
      let label = String(sides[index])
      XCTAssertTrue(label.contains(time), body, file: file, line: line)
      XCTAssertTrue(label.lowercased().contains(month), body, file: file, line: line)
      // CLDR versions differ in month punctuation; verify the actual civil day separately.
      XCTAssertNotNil(label.range(of: "(?<![0-9])\(day)(?![0-9])", options: .regularExpression),
        body, file: file, line: line)
    }
  }

  func testOvernightGoogleRangeShowsBothLocalDatesInTheSelectedLanguage() throws {
    let now = instant("2026-11-06T16:00:00Z")
    let value = event("overnight", start: "2026-11-06T18:30:00Z", end: "2026-11-06T20:15:00Z")
    for language in Language.allCases {
      let plan = try XCTUnwrap(LocalNotificationPlanner.plans(
        snapshot: snapshot([], zone: "Asia/Qyzylorda", language: language), events: [value],
        calendarReady: true, leadMinutes: 30, until: now.addingTimeInterval(86_400), now: now).first)
      assertOvernightNovemberRange(plan.body, language: language, startTime: "23:30", endTime: "01:15")
      XCTAssertEqual(plan.fireDate, instant("2026-11-06T18:00:00Z"))
      XCTAssertEqual(plan.destination, .googleEvent(id: "overnight", calendarID: "primary", date: "2026-11-06"))
    }
  }

  func testTimedTaskDurationAcrossMidnightShowsBothDatesInsteadOfClippingToTheDay() throws {
    let now = instant("2026-11-06T16:00:00Z")
    let task = RitmTask(id: "overnight", title: "Night work", date: "2026-11-06", time: "23:45", duration: 90)
    for language in Language.allCases {
      let plan = try XCTUnwrap(LocalNotificationPlanner.plans(
        snapshot: snapshot([task], zone: "Asia/Qyzylorda", language: language), leadMinutes: 30,
        until: now.addingTimeInterval(86_400), now: now).first)
      assertOvernightNovemberRange(plan.body, language: language, startTime: "23:45", endTime: "01:15")
      XCTAssertEqual(plan.title, task.title)
      XCTAssertEqual(plan.fireDate, instant("2026-11-06T18:15:00Z"))
      XCTAssertEqual(plan.destination, .task(id: "overnight", date: "2026-11-06"))
    }
  }

  func testGoogleRangeMarksBothUtcOffsetsAcrossADaylightSavingClockChange() throws {
    let now = instant("2026-11-01T03:00:00Z")
    let value = event("fallback", start: "2026-11-01T01:15:00-04:00", end: "2026-11-01T01:45:00-05:00")
    for language in Language.allCases {
      let plan = try XCTUnwrap(LocalNotificationPlanner.plans(
        snapshot: snapshot([], zone: "America/New_York", language: language), events: [value],
        calendarReady: true, leadMinutes: 30, until: now.addingTimeInterval(86_400), now: now).first)
      XCTAssertTrue(plan.body.contains("01:15 UTC-04:00"), plan.body)
      XCTAssertTrue(plan.body.contains("01:45 UTC-05:00"), plan.body)
      XCTAssertLessThan(try XCTUnwrap(plan.body.range(of: "UTC-04:00")).lowerBound,
        try XCTUnwrap(plan.body.range(of: "UTC-05:00")).lowerBound)
      XCTAssertEqual(plan.fireDate, instant("2026-11-01T04:45:00Z"))
      XCTAssertEqual(plan.destination, .googleEvent(id: "fallback", calendarID: "primary", date: "2026-11-01"))
    }
  }

  func testInvalidTaskDurationShowsOnlyStartAndKeepsTheSameDeadlineAndIdentity() throws {
    let now = instant("2026-11-06T08:00:00Z")
    for duration in [0, -30, 1441] {
      let task = RitmTask(id: "invalid-duration", title: "Original title", date: "2026-11-06",
        time: "14:00", duration: duration)
      let plan = try XCTUnwrap(LocalNotificationPlanner.plans(
        snapshot: snapshot([task]), leadMinutes: 30, until: now.addingTimeInterval(86_400), now: now).first)
      XCTAssertEqual(plan.title, task.title)
      XCTAssertEqual(plan.body, "14:00")
      XCTAssertEqual(plan.fireDate, instant("2026-11-06T13:30:00Z"))
      XCTAssertEqual(plan.identifier, LocalNotificationNamespace.reminders
        + LocalNotificationNamespace.key("current") + ".task."
        + LocalNotificationNamespace.key("invalid-duration", "2026-11-06"))
      XCTAssertEqual(plan.destination, .task(id: "invalid-duration", date: "2026-11-06"))
    }
  }

  func testGoogleInvalidOrReversedIntervalStillCannotBecomeANotification() {
    let now = instant("2026-11-06T08:00:00Z")
    for (start, end) in [
      ("invalid", "2026-11-06T13:00:00Z"),
      ("2026-11-06T12:00:00Z", "invalid"),
      ("2026-11-06T12:00:00Z", "2026-11-06T12:00:00Z"),
      ("2026-11-06T12:00:00Z", "2026-11-06T11:00:00Z"),
    ] {
      XCTAssertTrue(LocalNotificationPlanner.plans(
        snapshot: snapshot([]), events: [event("invalid", start: start, end: end)], calendarReady: true,
        until: now.addingTimeInterval(86_400), now: now).isEmpty)
    }
  }

  func testEarlyReminderForANextDayGoogleEventIncludesTheEventDate() throws {
    let now = instant("2026-11-06T18:00:00Z") // 23:00 in the account zone.
    let value = event("after-midnight", start: "2026-11-07T00:15:00+05:00", end: "2026-11-07T01:15:00+05:00")
    for language in Language.allCases {
      let plan = try XCTUnwrap(LocalNotificationPlanner.plans(
        snapshot: snapshot([], zone: "Asia/Qyzylorda", language: language), events: [value],
        calendarReady: true, leadMinutes: 30, until: now.addingTimeInterval(86_400), now: now).first)
      XCTAssertEqual(plan.title, value.title)
      XCTAssertTrue(plan.body.contains("00:15–01:15"), plan.body)
      XCTAssertTrue(plan.body.lowercased().contains(language == .ru ? "ноя" : "nov"), plan.body)
      XCTAssertNotNil(plan.body.range(of: "(?<![0-9])7(?![0-9])", options: .regularExpression), plan.body)
      XCTAssertEqual(plan.fireDate, instant("2026-11-06T18:45:00Z"))
      XCTAssertEqual(plan.destination,
        .googleEvent(id: "after-midnight", calendarID: "primary", date: "2026-11-07"))
    }
  }

  func testWalletUsesOnlyRealPurchaseAndDoesNotExposeCard() throws {
    let real = WalletPurchase(
      id: "w1", merchant: "Magnum", amountMinor: 1_432_000, currency: .KZT,
      card: "•••• 1234", date: "2026-11-06", receivedAt: "2026-11-06T12:00:00Z")
    let plan = try XCTUnwrap(WalletNotificationPlanner.plan(
      purchase: real, language: .ru, accountEpoch: "account"))
    XCTAssertNil(plan.fireDate)
    XCTAssertEqual(plan.destination, .wallet(id: "w1"))
    XCTAssertTrue(plan.body.contains("Magnum"))
    XCTAssertTrue(plan.body.contains("KZT"))
    XCTAssertFalse(plan.body.contains("1234"))
    let test = WalletPurchase(
      id: "test", merchant: WalletLink.testMerchant, amountMinor: 100_000, currency: .KZT,
      card: WalletLink.testCard, date: "2026-11-06", receivedAt: "")
    XCTAssertNil(WalletNotificationPlanner.plan(purchase: test, language: .en, accountEpoch: "account"))
  }

  func testRoutesRoundTripAndRejectUntrustedShapes() {
    let routes: [LocalNotificationDestination] = [
      .day, .task(id: "a/b&title=ignored", date: "2026-11-06"),
      .googleEvent(id: "a#b", calendarID: "primary", date: "2026-11-06"),
      .wallet(id: "w1"), .workout(id: "workout"),
    ]
    for route in routes { XCTAssertEqual(LocalNotificationDestination(url: route.url), route) }
    for raw in [
      "https://open/day", "ritm://add?amount=10&merchant=test", "ritm://open/day?id=x",
      "ritm://open/task?id=a&id=b&date=2026-11-06", "ritm://open/task?id=a&date=2026-02-30",
      "ritm://user@open/day", "ritm://open:80/day", "ritm://open/day#ignored",
      "ritm://open/wallet?id=%0A",
    ] {
      XCTAssertNil(LocalNotificationDestination(url: URL(string: raw)!), raw)
    }
    XCTAssertTrue(LocalNotificationNamespace.isLegacyReminder("ritm:2:task:id:2026-11-06"))
    XCTAssertFalse(LocalNotificationNamespace.isLegacyReminder("ritm:external:feature"))
    XCTAssertFalse(LocalNotificationNamespace.isLegacyReminder("ritm.workout.rest.w1"))
  }
}
