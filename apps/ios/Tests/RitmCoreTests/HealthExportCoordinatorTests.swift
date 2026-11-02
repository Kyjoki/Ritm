import XCTest

@testable import RitmCore

/// A scripted writer: results are popped per call; `gate` can hold a save open.
private actor FakeWriter: HealthWorkoutWriting {
  var status: HealthShareStatus = .allowed
  var saveResults: [Result<String?, Error>] = []
  var existing: [String: String] = [:]
  var lookupFails = false
  private(set) var saveCalls: [String] = []
  private(set) var lookups = 0
  private var gate: CheckedContinuation<Void, Never>?
  var holdSaves = false

  func configure(
    status: HealthShareStatus? = nil, saves: [Result<String?, Error>]? = nil,
    existing: [String: String]? = nil, lookupFails: Bool? = nil, hold: Bool? = nil
  ) {
    if let status { self.status = status }
    if let saves { saveResults = saves }
    if let existing { self.existing = existing }
    if let lookupFails { self.lookupFails = lookupFails }
    if let hold { holdSaves = hold }
  }

  func release() { gate?.resume(); gate = nil; holdSaves = false }

  func requestShareAuthorization() async -> HealthShareStatus { status }
  func shareStatus() async -> HealthShareStatus { status }

  func save(_ payload: HealthWorkoutPayload) async throws -> String? {
    saveCalls.append(payload.workoutID)
    if holdSaves { await withCheckedContinuation { gate = $0 } }
    guard !saveResults.isEmpty else { return "uuid-\(payload.workoutID)" }
    return try saveResults.removeFirst().get()
  }

  func findExisting(syncIdentifier: String) async throws -> String? {
    lookups += 1
    if lookupFails { throw HealthWriteError.failure(.unknown, retryable: true) }
    return existing[syncIdentifier]
  }
}

@MainActor
final class HealthExportCoordinatorTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_000_000)

  private func record(_ id: String = "w1", seconds: TimeInterval = 3_600) -> WorkoutRecord {
    WorkoutRecord(id: id, programID: "p", programName: "Грудь", startedAt: t0, endedAt: t0.addingTimeInterval(seconds), exercises: [])
  }

  private func make(
    _ writer: FakeWriter, enabled: Bool = true, ledger: HealthExportLedger = HealthExportLedger()
  ) -> (HealthExportCoordinator, Saved) {
    let saved = Saved()
    let coordinator = HealthExportCoordinator(
      writer: writer, ledger: ledger, isEnabled: enabled, persist: { saved.values.append($0) }, now: { Date(timeIntervalSince1970: 2_000_000) })
    return (coordinator, saved)
  }

  final class Saved { var values: [HealthExportLedger] = [] }

  func testFinishedWorkoutIsSavedOnceAndPersisted() async {
    let writer = FakeWriter()
    let (coordinator, saved) = make(writer)
    await coordinator.exportIfEnabled(record())
    guard case .saved(let uuid, _) = coordinator.status(of: "w1") else { return XCTFail("not saved") }
    XCTAssertEqual(uuid, "uuid-w1")
    let calls = await writer.saveCalls
    XCTAssertEqual(calls, ["w1"])
    XCTAssertEqual(saved.values.last, coordinator.ledger)
  }

  func testSwitchOffExportsNothing() async {
    let writer = FakeWriter()
    let (coordinator, _) = make(writer, enabled: false)
    await coordinator.exportIfEnabled(record())
    XCTAssertTrue(coordinator.ledger.records.isEmpty)
    let calls = await writer.saveCalls
    XCTAssertTrue(calls.isEmpty)
  }

  func testRecordThatIsNotAWorkoutIsNeverExported() async {
    let writer = FakeWriter()
    let (coordinator, _) = make(writer)
    await coordinator.exportIfEnabled(record(seconds: 0))
    XCTAssertTrue(coordinator.ledger.records.isEmpty)
    let calls = await writer.saveCalls
    XCTAssertTrue(calls.isEmpty)
  }

  func testDoubleCallMakesOneWrite() async {
    let writer = FakeWriter()
    await writer.configure(hold: true)
    let (coordinator, _) = make(writer)
    let first = Task { await coordinator.exportIfEnabled(record()) }
    let second = Task { await coordinator.exportIfEnabled(record()) }
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(50))
    await writer.release()
    await first.value
    await second.value
    let calls = await writer.saveCalls
    XCTAssertEqual(calls, ["w1"])
    XCTAssertEqual(coordinator.ledger.records.count, 1)
  }

  func testDeniedAccessFailsRetryablyWithoutWritingAndKeepsRecord() async {
    let writer = FakeWriter()
    await writer.configure(status: .denied)
    let (coordinator, _) = make(writer)
    await coordinator.exportIfEnabled(record())
    guard case .failed(.notAuthorized, true, _) = coordinator.status(of: "w1") else { return XCTFail("\(coordinator.status(of: "w1"))") }
    let calls = await writer.saveCalls
    XCTAssertTrue(calls.isEmpty)
    XCTAssertTrue(coordinator.canRetry("w1"))
  }

  func testUnavailableHealthFailsForGoodAndCannotRetry() async {
    let (coordinator, _) = make(FakeWriter())
    let unavailable = HealthExportCoordinator(writer: HealthUnavailableWriter(), isEnabled: true)
    await unavailable.exportIfEnabled(record())
    guard case .failed(.healthUnavailable, false, _) = unavailable.status(of: "w1") else { return XCTFail() }
    XCTAssertFalse(unavailable.canRetry("w1"))
    _ = coordinator
  }

  func testSaveFailureThenRetrySucceeds() async {
    let writer = FakeWriter()
    await writer.configure(saves: [.failure(HealthWriteError.failure(.saveFailed, retryable: true))])
    let (coordinator, _) = make(writer)
    await coordinator.exportIfEnabled(record())
    XCTAssertTrue(coordinator.canRetry("w1"))
    await coordinator.retry("w1")
    guard case .saved = coordinator.status(of: "w1") else { return XCTFail() }
    let calls = await writer.saveCalls
    XCTAssertEqual(calls.count, 2)
  }

  func testConnectRetriesOnlyAuthorizationFailures() async {
    let writer = FakeWriter()
    await writer.configure(status: .denied)
    let (coordinator, _) = make(writer)
    await coordinator.exportIfEnabled(record())
    await writer.configure(status: .allowed)
    let status = await coordinator.connect()
    XCTAssertEqual(status, .allowed)
    guard case .saved = coordinator.status(of: "w1") else { return XCTFail() }
  }

  func testRelaunchAfterInterruptedWriteLooksUpInsteadOfWriting() async throws {
    let payload = try XCTUnwrap(HealthWorkoutPayload(record: record()))
    let began = HealthExportLedger().enqueue(payload, now: t0).begin("w1").ledger
    let writer = FakeWriter()
    await writer.configure(existing: [payload.syncIdentifier: "found-uuid"])
    let (coordinator, _) = make(writer, ledger: began)
    await coordinator.reconcileOnLaunch()
    guard case .saved("found-uuid", _) = coordinator.status(of: "w1") else { return XCTFail("\(coordinator.status(of: "w1"))") }
    let calls = await writer.saveCalls
    XCTAssertTrue(calls.isEmpty)
  }

  func testRelaunchWhenSampleIsMissingWritesExactlyOnce() async throws {
    let payload = try XCTUnwrap(HealthWorkoutPayload(record: record()))
    let began = HealthExportLedger().enqueue(payload, now: t0).begin("w1").ledger
    let writer = FakeWriter()
    let (coordinator, _) = make(writer, ledger: began)
    await coordinator.reconcileOnLaunch()
    guard case .saved = coordinator.status(of: "w1") else { return XCTFail() }
    let calls = await writer.saveCalls
    XCTAssertEqual(calls, ["w1"])
  }

  func testFailedLookupKeepsRecordUncertainAndNeverWrites() async throws {
    let payload = try XCTUnwrap(HealthWorkoutPayload(record: record()))
    let began = HealthExportLedger().enqueue(payload, now: t0).begin("w1").ledger
    let writer = FakeWriter()
    await writer.configure(lookupFails: true)
    let (coordinator, _) = make(writer, ledger: began)
    await coordinator.reconcileOnLaunch()
    guard case .uncertain = coordinator.status(of: "w1") else { return XCTFail() }
    let calls = await writer.saveCalls
    XCTAssertTrue(calls.isEmpty)
    XCTAssertTrue(coordinator.canRetry("w1"))
  }

  func testUnknownOutcomeIsResolvedByLookup() async {
    let writer = FakeWriter()
    await writer.configure(
      saves: [.failure(HealthWriteError.outcomeUnknown)], existing: [HealthWorkoutPayload.syncIdentifier(for: "w1"): "u"])
    let (coordinator, _) = make(writer)
    await coordinator.exportIfEnabled(record())
    guard case .saved("u", _) = coordinator.status(of: "w1") else { return XCTFail("\(coordinator.status(of: "w1"))") }
    let calls = await writer.saveCalls
    XCTAssertEqual(calls.count, 1)
  }

  func testSavedWorkoutIsNotWrittenAgainByRetry() async {
    let writer = FakeWriter()
    let (coordinator, _) = make(writer)
    await coordinator.exportIfEnabled(record())
    await coordinator.retry("w1")
    await coordinator.retryAllFailed()
    let calls = await writer.saveCalls
    XCTAssertEqual(calls.count, 1)
  }

  func testLastAttemptIsTheNewestOutcome() async {
    let writer = FakeWriter()
    let (coordinator, _) = make(writer)
    XCTAssertNil(coordinator.lastAttempt)
    await coordinator.exportIfEnabled(record("a"))
    await coordinator.exportIfEnabled(record("b"))
    XCTAssertNotNil(coordinator.lastAttempt)
    XCTAssertEqual(coordinator.recent(limit: 1).first?.workoutID, "b")
  }
}
