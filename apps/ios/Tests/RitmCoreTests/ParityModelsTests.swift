import Foundation
import XCTest

@testable import RitmCore

final class ParityModelsTests: XCTestCase {
  func testPatchDistinguishesClearedFromUnchangedFields() throws {
    let data = try JSONEncoder().encode(
      TaskPatch(date: .null, time: .value("09:30"), colorId: .null))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertTrue(object["date"] is NSNull)
    XCTAssertTrue(object["colorId"] is NSNull)
    XCTAssertEqual(object["time"] as? String, "09:30")
    XCTAssertNil(object["title"])
    XCTAssertNil(object["completed"])
  }

  func testRestoreAndAllDayEventEncodeRequiredNullFields() throws {
    let taskData = try JSONEncoder().encode(RitmTask(id: "id", title: "Undated"))
    let task = try XCTUnwrap(JSONSerialization.jsonObject(with: taskData) as? [String: Any])
    XCTAssertTrue(task["date"] is NSNull)
    XCTAssertTrue(task["time"] is NSNull)
    XCTAssertEqual(task["id"] as? String, "id")
    XCTAssertNotNil(task["completedDates"])
    let eventData = try JSONEncoder().encode(
      GoogleEventInput(title: "All day", date: "2026-10-29", allDay: true))
    let event = try XCTUnwrap(JSONSerialization.jsonObject(with: eventData) as? [String: Any])
    XCTAssertTrue(event["time"] is NSNull)
    let habitData = try JSONEncoder().encode(HabitInput(title: "One tap", target: nil))
    let habit = try XCTUnwrap(JSONSerialization.jsonObject(with: habitData) as? [String: Any])
    XCTAssertTrue(habit["target"] is NSNull)
  }

  func testFinanceUnionEncodesOnlySelectedCaseAndRejectsMissingFields() throws {
    let input = FinanceEntryInput(
      type: .expense, note: "Lunch", amountMinor: 125050,
      valueMinor: 999, date: "2026-10-29", asOf: "2026-01-01", name: "Stale form value",
      category: "Food")
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
    XCTAssertEqual(
      Set(object.keys), ["type", "currency", "note", "amountMinor", "date", "category"])
    XCTAssertEqual(object["amountMinor"] as? Int, 125050)
    XCTAssertThrowsError(
      try JSONEncoder().encode(FinanceEntryInput(type: .transfer, amountMinor: 100)))
  }

  func testFinanceStockDecodesAndRoundTripsFlatWireShape() throws {
    let json =
      #"{"id":"stock-id","type":"stock","name":"Shares","valueMinor":12300,"currency":"KZT","asOf":"2026-10-29","note":"","exchange":"KASE","ticker":"TEST","quantity":3,"unitPriceMinor":4100,"purchasePriceMinor":3900,"createdAt":"2026-10-29T01:00:00Z","updatedAt":"2026-10-29T01:00:00Z"}"#
    let entry = try JSONDecoder().decode(FinanceEntry.self, from: Data(json.utf8))
    XCTAssertEqual(entry.quantity, 3)
    XCTAssertEqual(entry.input.unitPriceMinor, 4100)
    XCTAssertEqual(entry.type, .stock)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    XCTAssertNil(object["input"])
    XCTAssertEqual(object["id"] as? String, "stock-id")
    XCTAssertEqual(object["quantity"] as? Int, 3)
  }

  func testFullAssistantReplyPreservesProposalsAndIdeaDiscussion() throws {
    let json = """
      {"id":"conversation","title":"Idea","createdAt":"2026-10-29T01:00:00Z","updatedAt":"2026-10-29T01:00:00Z",
      "messages":[{"id":"message","role":"assistant","text":"Review","createdAt":"2026-10-29T01:00:00Z","steps":["Test"],
      "proposals":[{"id":"proposal","taskId":"task","title":"Move","before":{"date":null,"time":null,"duration":30},
      "after":{"date":"2026-10-30","time":"10:00","duration":30},"reason":"Free slot","status":"pending","taskUpdatedAt":"version"}],
      "ideaReview":{"version":1,"model":"model","experts":[{"id":"value","verdict":"needs_testing","summary":"Validate",
      "strengths":["Useful"],"concerns":["Unknown demand"],"assumptions":["Customers pay"],"firstTest":"Interview"}],
      "synthesis":{"verdict":"needs_testing","summary":"Test demand","agreements":["Interview"],"disagreements":[],"questions":["Who pays?"],"nextSteps":["Pilot"]},
      "discussion":{"round":2,"parentMessageId":"parent","rootMessageId":"root","changes":["Evidence"],"verdictChanges":[{"id":"value","before":"weak","after":"needs_testing"}]}}}]}
      """
    let conversation = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
    let message = try XCTUnwrap(conversation.messages.first)
    XCTAssertEqual(message.proposals.first?.status, .pending)
    XCTAssertNil(message.proposals.first?.before.date)
    XCTAssertEqual(message.ideaReview?.discussion?.round, 2)
    XCTAssertEqual(message.ideaReview?.experts.first?.id, .value)
    XCTAssertEqual(message.ideaReview?.discussion?.verdictChanges.first?.after, .needsTesting)
    XCTAssertEqual(
      try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conversation)),
      conversation)
  }

  func testTelegramMillisecondsAndReadinessDecodeWithoutInventedConnection() throws {
    let json =
      #"{"configured":true,"linked":false,"pairingUrl":"https://t.me/example?start=fixture","pairingExpiresAt":1793235600000,"reminders":{"enabled":true,"leadMinutes":15,"timeZone":"Asia/Qyzylorda","ready":false,"schedulerActive":false,"googleConnected":false,"lastRunAt":null,"problem":"Not connected"}}"#
    let status = try JSONDecoder().decode(TelegramStatus.self, from: Data(json.utf8))
    XCTAssertFalse(status.linked)
    XCTAssertEqual(status.pairingExpiresAt, 1_793_235_600_000)
    XCTAssertEqual(status.reminders?.ready, false)
    XCTAssertNil(status.reminders?.lastRunAt)
  }
}
