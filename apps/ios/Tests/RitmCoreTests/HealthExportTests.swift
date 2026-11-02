import XCTest

@testable import RitmCore

final class HealthExportTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_000_000)
  private var t1: Date { t0.addingTimeInterval(3_600) }

  private func record(id: String = "w1", start: Date? = nil, end: Date? = nil) -> WorkoutRecord {
    WorkoutRecord(
      id: id, programID: "p", programName: "Грудь", startedAt: start ?? t0, endedAt: end ?? t1,
      exercises: [WorkoutRecordExercise(exerciseID: "bench", name: "Жим", sets: [WorkoutResultSet(weight: 80, reps: 5)])])
  }

  private func ledger(_ ids: String...) -> HealthExportLedger {
    ids.reduce(HealthExportLedger()) { $0.enqueue(record(id: $1), now: t0) }
  }

  func testPayloadHasStableIdentifierAndNoDetails() throws {
    let payload = try XCTUnwrap(HealthWorkoutPayload(record: record()))
    XCTAssertEqual(payload.syncIdentifier, "app.ritm.workout.w1")
    XCTAssertEqual(payload.syncVersion, 1)
    XCTAssertEqual(payload.activity, .traditionalStrengthTraining)
    let json = String(decoding: try WorkoutCoding.encoder().encode(payload), as: UTF8.self)
    XCTAssertFalse(json.contains("Жим"))
    XCTAssertFalse(json.contains("weight"))
    XCTAssertFalse(json.lowercased().contains("calor"))
  }

  func testActiveDurationSubtractsPausesAndNeverGoesNegative() throws {
    XCTAssertEqual(try XCTUnwrap(HealthWorkoutPayload(record: record())).activeDuration, 3_600)
    XCTAssertEqual(try XCTUnwrap(HealthWorkoutPayload(record: record(), pausedSeconds: 600)).activeDuration, 3_000)
    XCTAssertEqual(try XCTUnwrap(HealthWorkoutPayload(record: record(), pausedSeconds: 99_999)).activeDuration, 0)
    XCTAssertEqual(try XCTUnwrap(HealthWorkoutPayload(record: record(), pausedSeconds: -5)).activeDuration, 3_600)
    XCTAssertEqual(try XCTUnwrap(HealthWorkoutPayload(record: record(), pausedSeconds: .nan)).activeDuration, 3_600)
  }

  func testRecordWithoutPositiveDurationHasNoPayload() {
    XCTAssertNil(HealthWorkoutPayload(record: record(start: t1, end: t0)))
    XCTAssertNil(HealthWorkoutPayload(record: record(id: "")))
    XCTAssertTrue(HealthExportLedger().enqueue(record(start: t1, end: t0), now: t0).records.isEmpty)
  }

  func testEnqueueIsIdempotent() {
    let once = ledger("w1")
    XCTAssertEqual(once.enqueue(record(), now: t1), once)
    XCTAssertEqual(once.records.count, 1)
    XCTAssertEqual(once.status(of: "w1"), .pending)
    XCTAssertEqual(once.status(of: "other"), .notRequested)
  }

  func testDoubleTapBeginsOnlyOnce() {
    let first = ledger("w1").begin("w1")
    XCTAssertNotNil(first.payload)
    XCTAssertEqual(first.ledger.status(of: "w1"), .saving)
    let second = first.ledger.begin("w1")
    XCTAssertNil(second.payload)
    XCTAssertEqual(second.ledger, first.ledger)
    XCTAssertEqual(first.ledger.record("w1")?.attempts, 1)
  }

  func testSavedWorkoutIsNeverWrittenAgain() {
    let saved = ledger("w1").begin("w1").ledger.markSaved("w1", healthKitUUID: "U", at: t1)
    XCTAssertEqual(saved.status(of: "w1"), .saved(healthKitUUID: "U", at: t1))
    XCTAssertNil(saved.begin("w1").payload)
    XCTAssertTrue(saved.retryable().isEmpty)
  }

  func testFailureKeepsTheWorkoutAndCanBeRetried() {
    var l = ledger("w1").begin("w1").ledger
    l = l.markFailed("w1", reason: .dataProtected, retryable: true, at: t1)
    XCTAssertEqual(l.retryable().map(\.workoutID), ["w1"])
    XCTAssertEqual(l.record("w1")?.payload.workoutID, "w1")
    let again = l.begin("w1")
    XCTAssertNotNil(again.payload)
    XCTAssertEqual(again.ledger.record("w1")?.attempts, 2)
    XCTAssertEqual(again.ledger.record("w1")?.lastResult, .failed(reason: .dataProtected, retryable: true, at: t1))
  }

  func testNonRetryableFailureIsNotRetried() {
    let l = ledger("w1").begin("w1").ledger.markFailed("w1", reason: .notAuthorized, retryable: false, at: t1)
    XCTAssertTrue(l.retryable().isEmpty)
    XCTAssertNil(l.begin("w1").payload)
  }

  func testResultsOnlyApplyToARunningWrite() {
    let pending = ledger("w1")
    XCTAssertEqual(pending.markSaved("w1", healthKitUUID: nil, at: t1), pending)
    XCTAssertEqual(pending.markFailed("w1", reason: .unknown, retryable: true, at: t1), pending)
    XCTAssertEqual(pending.markUncertain("w1", at: t1), pending)
  }

  func testUncertainIsResolvedByIdentifierNotByWritingAgain() {
    let uncertain = ledger("w1").begin("w1").ledger.markUncertain("w1", at: t1)
    XCTAssertNil(uncertain.begin("w1").payload)
    XCTAssertTrue(uncertain.retryable().isEmpty)
    XCTAssertEqual(uncertain.uncertain().count, 1)

    let found = uncertain.resolveUncertain("w1", foundExistingByIdentifier: true, healthKitUUID: "U", at: t1)
    XCTAssertEqual(found.status(of: "w1"), .saved(healthKitUUID: "U", at: t1))
    XCTAssertNil(found.begin("w1").payload)

    let missing = uncertain.resolveUncertain("w1", foundExistingByIdentifier: false, at: t1)
    XCTAssertEqual(missing.status(of: "w1"), .pending)
    XCTAssertNotNil(missing.begin("w1").payload)
    XCTAssertEqual(missing.resolveUncertain("w1", foundExistingByIdentifier: true, at: t1), missing)
  }

  func testRelaunchKeepsTheLedgerAndTurnsASavingWriteIntoUncertain() throws {
    let saving = ledger("w1", "w2").begin("w1").ledger
    let data = try WorkoutCoding.encoder().encode(saving)
    let restored = try WorkoutCoding.decoder().decode(HealthExportLedger.self, from: data)
    XCTAssertEqual(restored, saving)
    XCTAssertNil(restored.begin("w1").payload)

    let recovered = restored.recoveringAfterLaunch(at: t1)
    XCTAssertEqual(recovered.status(of: "w1"), .uncertain(at: t1))
    XCTAssertEqual(recovered.status(of: "w2"), .pending)
    XCTAssertEqual(recovered.enqueue(record(id: "w1"), now: t1), recovered)
  }

  func testStatusesRoundTripThroughJSON() throws {
    let all: [HealthExportStatus] = [
      .notRequested, .pending, .saving, .saved(healthKitUUID: nil, at: t0),
      .failed(reason: .healthUnavailable, retryable: false, at: t1), .uncertain(at: t1),
    ]
    for status in all {
      let data = try WorkoutCoding.encoder().encode(status)
      XCTAssertEqual(try WorkoutCoding.decoder().decode(HealthExportStatus.self, from: data), status)
    }
  }

  func testCancelledOrUnfinishedWorkoutIsNeverExported() {
    let session = WorkoutSession(
      id: "s1", programID: "p", programName: "Грудь", startedAt: t0,
      items: [
        WorkoutSessionItem(
          id: "i", exerciseID: "bench", name: "Жим", previous: nil,
          sets: [WorkoutSet(id: "a", weight: "80", reps: "5")])
      ])
    XCTAssertTrue(HealthExportLedger().enqueue(finishing: session, at: t1).records.isEmpty)

    var done = session
    done.update("i") { _ = $0.toggle(setID: "a") }
    let exported = HealthExportLedger().enqueue(finishing: done, at: t1)
    XCTAssertEqual(exported.records.map(\.workoutID), ["s1"])
    XCTAssertEqual(exported.records.first?.payload.end, t1)
  }

  func testRetryableIsOldestFirstAndImmutableUpdatesLeaveTheOldValue() {
    let a = HealthExportLedger().enqueue(record(id: "b"), now: t1).enqueue(record(id: "a"), now: t0)
    XCTAssertEqual(a.retryable().map(\.workoutID), ["a", "b"])
    let started = a.begin("a").ledger
    XCTAssertEqual(a.status(of: "a"), .pending)
    XCTAssertEqual(started.status(of: "a"), .saving)
  }

  func testUnreadableRecordsAreDroppedNotFatal() throws {
    let json = #"{"version":1,"records":[{"bogus":true}]}"#
    let l = try WorkoutCoding.decoder().decode(HealthExportLedger.self, from: Data(json.utf8))
    XCTAssertTrue(l.records.isEmpty)
  }
}
