import Foundation
import XCTest

@testable import RitmCore

final class ModelsTests: XCTestCase {
  func testBootstrapDecodesExistingWireShapeAndOptionalLegacyTaskFields() throws {
    let json = """
      {"tasks":[{"id":"task-id","title":"Дело","description":"","date":null,"time":null,
      "duration":30,"priority":"normal","repeat":"none","kind":"task","completed":false,
      "completedDates":[],"createdAt":"2026-10-28T08:00:00Z","updatedAt":"2026-10-28T08:00:00Z"}],
      "settings":{"displayName":"Owner","email":"owner@example.invalid","theme":"dark","sidebar":"dark",
      "language":"ru","timeZone":"Asia/Qyzylorda","notifications":true,"dailyBriefing":false,
      "workDayStart":"09:00","workDayEnd":"18:00"},"conversations":[],
      "aiStatus":{"configured":false,"model":"","source":"none"}}
      """
    let value = try JSONDecoder().decode(Bootstrap.self, from: Data(json.utf8))
    XCTAssertEqual(value.tasks.count, 1)
    XCTAssertNil(value.tasks[0].date)
    XCTAssertNil(value.tasks[0].calendarEntry)
    XCTAssertEqual(value.settings.timeZone, "Asia/Qyzylorda")
    XCTAssertEqual(value.settings.theme, .dark)
  }

  func testTaskInputEncodesRequiredNullDatesAndDoesNotInjectExpectedVersion() throws {
    let data = try JSONEncoder().encode(TaskInput(title: "Дело"))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertTrue(object["date"] is NSNull)
    XCTAssertTrue(object["time"] is NSNull)
    XCTAssertEqual(object["calendarEntry"] as? Bool, false)
    XCTAssertEqual(object["repeat"] as? String, "none")
    XCTAssertNil(object["expectedUpdatedAt"])
  }

  func testHabitDecodesOldShapeWithoutOptionalFields() throws {
    let json = """
      {"id":"habit-id","title":"Чтение","startDate":"2026-10-25","completedDates":["2026-10-28"],
      "createdAt":"2026-10-25T08:00:00Z","updatedAt":"2026-10-28T08:00:00Z"}
      """
    let habit = try JSONDecoder().decode(Habit.self, from: Data(json.utf8))
    XCTAssertEqual(HabitSchedule.target(habit), 1)
    XCTAssertTrue(HabitSchedule.isComplete(habit, on: "2026-10-28"))
  }

  func testGoogleAllDayAndTimedBoundariesRemainDistinct() throws {
    let json = """
      {"events":[{"id":"google-id","source":"google","calendarId":"primary","title":"Событие",
      "description":"","etag":"etag-1","start":{"date":"2026-10-28"},"end":{"date":"2026-10-29"},
      "timeZone":"Asia/Qyzylorda","allDay":true,"busy":true,"readOnly":false}],
      "from":"2026-10-28","to":"2026-10-29","timeZone":"Asia/Qyzylorda","fetchedAt":"2026-10-28T08:00:00Z",
      "partial":true,"tasks":{"status":"permission_required","message":"Reconnect"}}
      """
    let result = try JSONDecoder().decode(GoogleCalendarResult.self, from: Data(json.utf8))
    XCTAssertEqual(result.events[0].start.date, "2026-10-28")
    XCTAssertNil(result.events[0].start.dateTime)
    XCTAssertTrue(result.partial)
    XCTAssertEqual(result.tasks?.status, "permission_required")
    let boundary = try JSONDecoder().decode(
      CalendarBoundary.self,
      from: Data(#"{"dateTime":"2026-10-28T09:00:00+05:00"}"#.utf8))
    XCTAssertEqual(boundary.dateTime, "2026-10-28T09:00:00+05:00")
    XCTAssertNil(boundary.date)
  }
}
