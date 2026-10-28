import Foundation
import XCTest

@testable import RitmCore

final class CalendarEventPolicyTests: XCTestCase {
  private func timed(_ start: String, _ end: String) -> GoogleCalendarEvent {
    GoogleCalendarEvent(
      id: "event-1", title: "Planning", description: "Keep this detail", etag: "v1",
      start: .init(dateTime: start), end: .init(dateTime: end),
      timeZone: "UTC", readOnly: false, colorId: "3")
  }

  func testDraftUsesAccountZoneAndPreservesContentWithoutChangingDuration() throws {
    let event = timed("2026-10-29T18:00:00.000Z", "2026-10-29T19:00:00.000Z")
    let draft = try XCTUnwrap(CalendarEventPolicy.draft(event, timeZone: "Asia/Qyzylorda"))
    XCTAssertEqual(draft.date, "2026-10-29")
    XCTAssertEqual(draft.time, "23:00")
    XCTAssertEqual(draft.duration, 60)
    XCTAssertEqual(draft.title, event.title)
    XCTAssertEqual(draft.description, event.description)
    XCTAssertEqual(draft.colorId, "3")
    XCTAssertFalse(CalendarEventPolicy.hasClockChange(event, timeZone: "Asia/Qyzylorda"))
  }

  private func encodedKeys(_ input: GoogleEventInput) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
  }

  func testDraftOmitsColorSoMovesKeepTheProviderColor() throws {
    let event = timed("2026-10-29T18:00:00.000Z", "2026-10-29T19:00:00.000Z")
    var moved = try XCTUnwrap(CalendarEventPolicy.draft(event, timeZone: "UTC"))
    moved.date = "2026-10-30"
    let body = try encodedKeys(moved)
    XCTAssertFalse(body.keys.contains("colorId"), "an unchanged color must not be sent")
    XCTAssertEqual(body["date"] as? String, "2026-10-30")
  }

  func testChangedOrClearedColorIsSentAndNewEventsSendTheirColor() throws {
    let event = timed("2026-10-29T18:00:00.000Z", "2026-10-29T19:00:00.000Z")
    var recolored = try XCTUnwrap(CalendarEventPolicy.draft(event, timeZone: "UTC"))
    recolored.colorId = "5"
    recolored.preservesProviderColor = false
    XCTAssertEqual(try encodedKeys(recolored)["colorId"] as? String, "5")
    recolored.colorId = nil
    XCTAssertTrue(try encodedKeys(recolored)["colorId"] is NSNull)
    let created = GoogleEventInput(title: "New", date: "2026-10-29", time: "09:00")
    XCTAssertTrue(try encodedKeys(created)["colorId"] is NSNull)
  }

  func testMultiDayEventsStayReadOnlyButMidnightEndRoundTrips() {
    XCTAssertTrue(
      CalendarEventPolicy.canEdit(
        timed("2026-10-29T23:00:00Z", "2026-10-30T00:00:00Z"), timeZone: "UTC"))
    XCTAssertFalse(
      CalendarEventPolicy.canEdit(
        timed("2026-10-29T23:00:00Z", "2026-10-30T00:05:00Z"), timeZone: "UTC"))
    var allDay = GoogleCalendarEvent(
      id: "all-day", title: "Day", start: .init(date: "2026-10-29"),
      end: .init(date: "2026-10-30"), timeZone: "UTC", allDay: true, readOnly: false)
    XCTAssertTrue(CalendarEventPolicy.canEdit(allDay, timeZone: "America/Los_Angeles"))
    XCTAssertEqual(
      CalendarEventPolicy.draft(allDay, timeZone: "America/Los_Angeles")?.date, "2026-10-29")
    allDay.end.date = "2026-10-31"
    XCTAssertNil(CalendarEventPolicy.draft(allDay, timeZone: "UTC"))
  }

  func testDSTCrossingAndRepeatedHourAreProtected() {
    let spring = timed("2026-03-08T01:30:00-05:00", "2026-03-08T03:30:00-04:00")
    let fall = timed("2026-11-01T01:45:00-04:00", "2026-11-01T01:15:00-05:00")
    let repeatedHour = timed("2026-11-01T01:10:00-05:00", "2026-11-01T01:30:00-05:00")
    for event in [spring, fall, repeatedHour] {
      XCTAssertTrue(CalendarEventPolicy.hasClockChange(event, timeZone: "America/New_York"))
      XCTAssertFalse(CalendarEventPolicy.canEdit(event, timeZone: "America/New_York"))
      XCTAssertNil(CalendarEventPolicy.draft(event, timeZone: "America/New_York"))
    }
    // The protection follows the account zone, not the source event label.
    XCTAssertTrue(CalendarEventPolicy.canEdit(fall, timeZone: "UTC"))
  }

  func testHalfHourDSTAndInvalidIntervalsAreProtected() {
    let halfHour = timed("2026-04-05T01:35:00+10:30", "2026-04-05T01:45:00+10:30")
    XCTAssertTrue(CalendarEventPolicy.hasClockChange(halfHour, timeZone: "Australia/Lord_Howe"))
    XCTAssertFalse(CalendarEventPolicy.canEdit(halfHour, timeZone: "Australia/Lord_Howe"))
    for event in [
      timed("invalid", "invalid"),
      timed("2026-10-29T09:00:00Z", "2026-10-29T08:00:00Z"),
      timed("2026-10-29T09:00:30Z", "2026-10-29T10:00:30Z"),
      timed("2026-10-29T09:00:00Z", "2026-10-29T09:04:00Z"),
      timed("2026-10-29T09:00:00Z", "2026-10-29T22:00:00Z"),
    ] {
      XCTAssertFalse(CalendarEventPolicy.canEdit(event, timeZone: "UTC"))
    }
    var event = timed("2026-10-29T09:00:00Z", "2026-10-29T10:00:00Z")
    XCTAssertFalse(CalendarEventPolicy.canEdit(event, timeZone: "invalid/zone"))
    event.taskLink = true
    XCTAssertFalse(CalendarEventPolicy.canEdit(event, timeZone: "UTC"))
    event.taskLink = nil
    event.readOnly = true
    XCTAssertFalse(CalendarEventPolicy.canEdit(event, timeZone: "UTC"))
  }
}
