import Foundation
import XCTest

@testable import RitmCore

private actor FakeRemote: WorkoutSyncRemote {
  var programs: [String: WorkoutDoc] = [:]
  var sessions: [String: WorkoutDoc] = [:]
  var clock = 0
  var puts: [(String, String?)] = []
  var failFetch = false

  func seed(_ kind: WorkoutDocKind, _ id: String, _ data: JSONValue) {
    clock += 1
    let doc = WorkoutDoc(id: id, updatedAt: "U\(clock)", data: data)
    if kind == .programs { programs[id] = doc } else { sessions[id] = doc }
  }
  func setFailFetch(_ value: Bool) { failFetch = value }

  func fetchWorkouts() async throws -> WorkoutServerSnapshot {
    if failFetch { throw APIError(message: "net", code: "NETWORK") }
    return WorkoutServerSnapshot(
      programs: programs.values.sorted { $0.id < $1.id },
      sessions: sessions.values.sorted { $0.id < $1.id })
  }

  func putWorkoutDoc(kind: WorkoutDocKind, id: String, data: JSONValue, expectedUpdatedAt: String?)
    async throws -> WorkoutDoc
  {
    puts.append((id, expectedUpdatedAt))
    let existing = kind == .programs ? programs[id] : sessions[id]
    if existing == nil, expectedUpdatedAt != nil {
      throw APIError(message: "missing", status: 404)
    }
    if existing?.updatedAt != expectedUpdatedAt {
      throw APIError(message: "conflict", status: 409, currentUpdatedAt: existing?.updatedAt)
    }
    seed(kind, id, data)
    return kind == .programs ? programs[id]! : sessions[id]!
  }

  func deleteWorkoutDoc(kind: WorkoutDocKind, id: String, expectedUpdatedAt: String) async throws {
    guard let existing = kind == .programs ? programs[id] : sessions[id] else {
      throw APIError(message: "missing", status: 404)
    }
    if existing.updatedAt != expectedUpdatedAt {
      throw APIError(message: "conflict", status: 409, currentUpdatedAt: existing.updatedAt)
    }
    if kind == .programs { programs[id] = nil } else { sessions[id] = nil }
  }
}

private actor FailingRemote: WorkoutSyncRemote {
  func fetchWorkouts() async throws -> WorkoutServerSnapshot {
    throw APIError(message: "net", code: "NETWORK")
  }
  func putWorkoutDoc(kind: WorkoutDocKind, id: String, data: JSONValue, expectedUpdatedAt: String?)
    async throws -> WorkoutDoc
  { throw APIError(message: "net", code: "NETWORK") }
  func deleteWorkoutDoc(kind: WorkoutDocKind, id: String, expectedUpdatedAt: String) async throws {
    throw APIError(message: "net", code: "NETWORK")
  }
}

private actor UnsupportedRemote: WorkoutSyncRemote {
  let status: Int
  var writes = 0
  init(status: Int) { self.status = status }
  func fetchWorkouts() async throws -> WorkoutServerSnapshot {
    throw APIError(message: "no route", status: status)
  }
  func putWorkoutDoc(kind: WorkoutDocKind, id: String, data: JSONValue, expectedUpdatedAt: String?)
    async throws -> WorkoutDoc
  {
    writes += 1
    throw APIError(message: "no route", status: status)
  }
  func deleteWorkoutDoc(kind: WorkoutDocKind, id: String, expectedUpdatedAt: String) async throws {
    writes += 1
  }
}

private actor RejectingRemote: WorkoutSyncRemote {
  let rejected: String
  init(rejected: String) { self.rejected = rejected }
  func fetchWorkouts() async throws -> WorkoutServerSnapshot {
    WorkoutServerSnapshot(programs: [], sessions: [])
  }
  func putWorkoutDoc(kind: WorkoutDocKind, id: String, data: JSONValue, expectedUpdatedAt: String?)
    async throws -> WorkoutDoc
  {
    if id == rejected { throw APIError(message: "too big", status: 413) }
    return WorkoutDoc(id: id, updatedAt: "U", data: data)
  }
  func deleteWorkoutDoc(kind: WorkoutDocKind, id: String, expectedUpdatedAt: String) async throws {}
}

private func obj(_ name: String) -> JSONValue { .object(["name": .string(name)]) }

private func local(_ programs: [String: JSONValue] = [:], _ sessions: [String: JSONValue] = [:])
  -> [WorkoutDocKind: [String: JSONValue]]
{ [.programs: programs, .sessions: sessions] }

private func snapshot(_ programs: [WorkoutDoc] = [], _ sessions: [WorkoutDoc] = [])
  -> WorkoutServerSnapshot
{ WorkoutServerSnapshot(programs: programs, sessions: sessions) }

private func entry(_ id: String, _ updated: String?, _ name: String, dirty: Bool, deleted: Bool = false)
  -> WorkoutSyncEntry
{ WorkoutSyncEntry(id: id, serverUpdatedAt: updated, data: obj(name), dirty: dirty, deleted: deleted) }

final class WorkoutSyncTests: XCTestCase {
  // MARK: reconcile

  func testFirstReconcileMarksEverythingLocalDirtyAndNew() {
    var state = WorkoutSyncState(serverKey: "s")
    state.reconcile(local: local(["a": obj("A")], ["r": obj("R")]))
    XCTAssertEqual(state.programs["a"], entry("a", nil, "A", dirty: true))
    XCTAssertTrue(state.sessions["r"]!.dirty)
    XCTAssertTrue(state.hasPending)
  }

  func testReconcileTurnsRemovalIntoTombstoneOnlyWhenServerKnowsTheDoc() {
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["known"] = entry("known", "U1", "K", dirty: false)
    state.programs["fresh"] = entry("fresh", nil, "F", dirty: true)
    state.reconcile(local: local())
    XCTAssertEqual(state.programs["known"]?.deleted, true)
    XCTAssertEqual(state.programs["known"]?.dirty, true)
    XCTAssertNil(state.programs["fresh"])
    XCTAssertTrue(state.view(.programs).isEmpty)
  }

  func testReconcileMarksOnlyChangedDocsDirty() {
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["a"] = entry("a", "U1", "A", dirty: false)
    state.programs["b"] = entry("b", "U2", "B", dirty: false)
    state.reconcile(local: local(["a": obj("A"), "b": obj("B2")]))
    XCTAssertFalse(state.programs["a"]!.dirty)
    XCTAssertTrue(state.programs["b"]!.dirty)
    XCTAssertEqual(state.programs["b"]?.serverUpdatedAt, "U2")
  }

  // MARK: merge

  func testMergeReplacesCleanDocWhenServerVersionDiffersAndKeepsDirty() {
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["clean"] = entry("clean", "U1", "old", dirty: false)
    state.programs["same"] = entry("same", "U1", "keep", dirty: false)
    state.programs["dirty"] = entry("dirty", "U1", "mine", dirty: true)
    state.merge(
      server: snapshot([
        WorkoutDoc(id: "clean", updatedAt: "U2", data: obj("new")),
        WorkoutDoc(id: "same", updatedAt: "U1", data: obj("ignored")),
        WorkoutDoc(id: "dirty", updatedAt: "U2", data: obj("theirs")),
        WorkoutDoc(id: "added", updatedAt: "U3", data: obj("added")),
      ]))
    XCTAssertEqual(state.programs["clean"]?.data, obj("new"))
    XCTAssertEqual(state.programs["clean"]?.serverUpdatedAt, "U2")
    XCTAssertEqual(state.programs["same"]?.data, obj("keep"))
    XCTAssertEqual(state.programs["dirty"]?.data, obj("mine"))
    XCTAssertEqual(state.programs["added"]?.dirty, false)
  }

  func testMergeRemovesCleanDocsMissingOnServerButNotDirtyOnes() {
    var state = WorkoutSyncState(serverKey: "s")
    state.sessions["gone"] = entry("gone", "U1", "g", dirty: false)
    state.sessions["edited"] = entry("edited", "U1", "e", dirty: true)
    state.merge(server: snapshot())
    XCTAssertNil(state.sessions["gone"])
    XCTAssertNotNil(state.sessions["edited"])
  }

  func testMergeDoesNotResurrectTombstones() {
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["t"] = entry("t", "U1", "t", dirty: true, deleted: true)
    state.merge(server: snapshot([WorkoutDoc(id: "t", updatedAt: "U2", data: obj("srv"))]))
    XCTAssertEqual(state.programs["t"]?.deleted, true)
    XCTAssertTrue(state.view(.programs).isEmpty)
  }

  // MARK: engine

  func testFirstSyncUploadsEverythingThenSecondSyncIsQuiet() async throws {
    let remote = FakeRemote()
    var state = WorkoutSyncState(serverKey: "s")
    state.reconcile(local: local(["a": obj("A")], ["r": obj("R")]))
    let first = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNil(first.failure)
    XCTAssertFalse(first.state.hasPending)
    let putCount = await remote.puts.count
    XCTAssertEqual(putCount, 2)
    let again = await WorkoutSyncEngine.run(state: first.state, remote: remote)
    let putsAfter = await remote.puts.count
    XCTAssertEqual(putsAfter, 2)
    XCTAssertEqual(again.state, first.state)
  }

  func testPushUsesExpectedVersionAndPullBringsServerDocs() async throws {
    let remote = FakeRemote()
    await remote.seed(.programs, "a", obj("A0"))
    await remote.seed(.sessions, "other", obj("web"))
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["a"] = entry("a", "U1", "A1", dirty: true)
    let result = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNil(result.failure)
    let puts = await remote.puts
    XCTAssertEqual(puts.first?.1, "U1")
    XCTAssertEqual(result.state.sessions["other"]?.data, obj("web"))
    XCTAssertEqual(result.state.programs["a"]?.data, obj("A1"))
  }

  func testConflictKeepsLocalEditAndRetriesOnceWithCurrentVersion() async throws {
    let remote = FakeRemote()
    await remote.seed(.programs, "a", obj("A0"))  // U1
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["a"] = entry("a", "stale", "mine", dirty: true)
    let result = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNil(result.failure)
    let stored = await remote.programs["a"]?.data
    XCTAssertEqual(stored, obj("mine"))
    let puts = await remote.puts
    XCTAssertEqual(puts.count, 2)
    XCTAssertEqual(puts[1].1, "U1")
    XCTAssertFalse(result.state.hasPending)
  }

  func testPutOfDocDeletedElsewhereRecreatesItAfter404() async throws {
    let remote = FakeRemote()
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["a"] = entry("a", "U9", "mine", dirty: true)
    let result = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNil(result.failure)
    let stored = await remote.programs["a"]?.data
    XCTAssertEqual(stored, obj("mine"))
    let puts = await remote.puts
    XCTAssertNil(puts.last?.1)
  }

  func testTombstoneIsKeptUntilDeleteSucceeds() async throws {
    var stuck = WorkoutSyncState(serverKey: "s")
    stuck.sessions["x"] = entry("x", "U1", "X", dirty: true, deleted: true)
    let kept = await WorkoutSyncEngine.run(state: stuck, remote: FailingRemote())
    XCTAssertNotNil(kept.failure)
    XCTAssertEqual(kept.state.sessions["x"]?.deleted, true)

    let remote = FakeRemote()
    await remote.seed(.sessions, "x", obj("X"))
    let done = await WorkoutSyncEngine.run(state: stuck, remote: remote)
    XCTAssertNil(done.failure)
    XCTAssertNil(done.state.sessions["x"])
    let left = await remote.sessions.count
    XCTAssertEqual(left, 0)
  }

  func testOfflineProbeKeepsEditsPending() async throws {
    let remote = FakeRemote()
    await remote.setFailFetch(true)
    var state = WorkoutSyncState(serverKey: "s")
    state.reconcile(local: local(["a": obj("A")]))
    let result = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNotNil(result.failure)
    XCTAssertTrue(result.state.programs["a"]!.dirty)  // nothing lost, retried later
  }

  func testDeleteConflictRetriesWithCurrentVersionAnd404CountsAsDone() async throws {
    let remote = FakeRemote()
    await remote.seed(.programs, "a", obj("A"))
    await remote.seed(.programs, "a", obj("A2"))  // U2
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["a"] = entry("a", "U1", "A", dirty: true, deleted: true)
    state.programs["b"] = entry("b", "U1", "B", dirty: true, deleted: true)
    let result = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNil(result.failure)
    XCTAssertTrue(result.state.programs.isEmpty)
    let left = await remote.programs.count
    XCTAssertEqual(left, 0)
  }

  func testDocDeletedElsewhereDisappearsLocallyAfterSync() async throws {
    var state = WorkoutSyncState(serverKey: "s")
    state.programs["a"] = entry("a", "U1", "A", dirty: false)
    let result = await WorkoutSyncEngine.run(state: state, remote: FakeRemote())
    XCTAssertTrue(result.state.view(.programs).isEmpty)
  }

  func testServerWithoutWorkoutRoutesIsUnsupportedAndNothingIsPushed() async throws {
    for status in [404, 405, 500, 501] {
      let remote = UnsupportedRemote(status: status)
      var state = WorkoutSyncState(serverKey: "s")
      state.reconcile(local: local(["a": obj("A")]))
      let result = await WorkoutSyncEngine.run(state: state, remote: remote)
      XCTAssertTrue(result.unsupported, "status \(status)")
      XCTAssertNil(result.failure)
      XCTAssertEqual(result.state, state)
      let writes = await remote.writes
      XCTAssertEqual(writes, 0)
    }
    let other = await WorkoutSyncEngine.run(
      state: WorkoutSyncState(serverKey: "s"), remote: UnsupportedRemote(status: 503))
    XCTAssertFalse(other.unsupported)
    XCTAssertNotNil(other.failure)
  }

  func testClientErrorOnOneDocSkipsItButSyncsTheRest() async throws {
    var state = WorkoutSyncState(serverKey: "s")
    state.reconcile(local: local(["bad": obj("B"), "good": obj("G")]))
    let result = await WorkoutSyncEngine.run(state: state, remote: RejectingRemote(rejected: "bad"))
    XCTAssertNotNil(result.failure)
    XCTAssertEqual(result.state.programs["bad"]?.dirty, true)
    XCTAssertNotEqual(result.state.programs["good"]?.dirty, true)
  }

  // MARK: integrate

  func testIntegrateAppliesInboundChangesButKeepsEditsMadeDuringSync() {
    var before = WorkoutSyncState(serverKey: "s")
    before.programs["a"] = entry("a", "U1", "A", dirty: false)
    before.programs["b"] = entry("b", "U1", "B", dirty: false)
    before.programs["c"] = entry("c", "U1", "C", dirty: false)
    var after = before
    after.merge(
      server: snapshot([
        WorkoutDoc(id: "a", updatedAt: "U2", data: obj("A-srv")),
        WorkoutDoc(id: "b", updatedAt: "U2", data: obj("B-srv")),
        WorkoutDoc(id: "n", updatedAt: "U2", data: obj("N")),
      ]))  // c was deleted elsewhere
    // Meanwhile the owner edited b locally and added d.
    let now = local(["a": obj("A"), "b": obj("B-mine"), "c": obj("C"), "d": obj("D")])
    let result = WorkoutSyncState.integrate(before: before, after: after, localNow: now)
    let changes = result.changes[.programs]!
    XCTAssertEqual(changes["a"], .some(obj("A-srv")))
    XCTAssertEqual(changes["n"], .some(obj("N")))
    XCTAssertTrue(changes["c"] != nil && changes["c"]! == nil)
    XCTAssertNil(changes["b"])
    XCTAssertNil(changes["d"])
    XCTAssertEqual(result.state.programs["b"]?.data, obj("B-mine"))
    XCTAssertEqual(result.state.programs["b"]?.dirty, true)
    XCTAssertEqual(result.state.programs["d"]?.dirty, true)
    XCTAssertEqual(result.state.programs["a"]?.dirty, false)
  }

  func testIntegrateDropsUnreadableInboundDocInsteadOfDeletingItOnTheServer() {
    let before = WorkoutSyncState(serverKey: "s")
    var after = before
    after.merge(server: snapshot([WorkoutDoc(id: "w", updatedAt: "U1", data: .string("junk"))]))
    let result = WorkoutSyncState.integrate(
      before: before, after: after, localNow: local(),
      accepts: { WorkoutSyncCodec.isReadable(kind: $0, id: $1, data: $2) })
    XCTAssertNil(result.state.programs["w"])
    XCTAssertTrue(result.changes[.programs]!.isEmpty)
    XCTAssertFalse(result.state.hasPending)
  }

  // MARK: codec

  func testCodecRoundTripsProgramsWithOrderAndCustomExercisesAndHistory() throws {
    let custom = WorkoutExercise(id: "ex-1", name: "Мой жим")
    let library = WorkoutLibrary(
      customExercises: [custom, WorkoutExercise(id: "ex-2", name: "unused")],
      programs: [
        WorkoutProgram(
          id: "p-2", name: "Second",
          items: [WorkoutProgramItem(id: "i1", exerciseID: "ex-1", sets: 4)]),
        WorkoutProgram(id: "p-1", name: "First"),
        WorkoutProgram(id: "bad id!", name: "Local only"),
      ])
    let record = WorkoutRecord(
      id: "r-1", programID: "p-1", programName: "First",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      endedAt: Date(timeIntervalSince1970: 1_700_003_600),
      exercises: [
        WorkoutRecordExercise(
          exerciseID: "ex-1", name: "x", sets: [WorkoutResultSet(weight: 82.5, reps: 5)])
      ])
    let docs = WorkoutSyncCodec.documents(
      library: library, history: WorkoutHistory(records: [record]))
    XCTAssertEqual(Set(docs[.programs]!.keys), ["p-1", "p-2"])
    XCTAssertEqual(docs[.programs]!["p-2"]!.objectValue?["order"], .number(0))
    XCTAssertEqual(docs[.programs]!["p-1"]!.objectValue?["order"], .number(1))
    // A fresh device receives everything.
    var changes: [WorkoutDocKind: [String: JSONValue?]] = [.programs: [:], .sessions: [:]]
    for (id, value) in docs[.programs]! { changes[.programs]![id] = .some(value) }
    for (id, value) in docs[.sessions]! { changes[.sessions]![id] = .some(value) }
    let applied = WorkoutSyncCodec.apply(
      changes, library: WorkoutLibrary(), history: WorkoutHistory())
    XCTAssertEqual(applied.library.programs.map(\.id), ["p-2", "p-1"])
    XCTAssertEqual(applied.library.programs.first?.items.first?.sets, 4)
    XCTAssertEqual(applied.library.customExercises, [custom])
    XCTAssertEqual(applied.history.records, [record])
    // Reconciling the result against the same docs changes nothing.
    var state = WorkoutSyncState(serverKey: "s")
    state.merge(
      server: snapshot(
        docs[.programs]!.map { WorkoutDoc(id: $0.key, updatedAt: "U", data: $0.value) },
        docs[.sessions]!.map { WorkoutDoc(id: $0.key, updatedAt: "U", data: $0.value) }))
    state.reconcile(
      local: WorkoutSyncCodec.documents(library: applied.library, history: applied.history))
    XCTAssertFalse(state.hasPending)
  }

  func testApplyRemovesDeletedDocsAndSortsHistoryNewestFirst() {
    func record(_ id: String, _ end: TimeInterval) -> WorkoutRecord {
      WorkoutRecord(
        id: id, programID: "p", programName: "P",
        startedAt: Date(timeIntervalSince1970: end - 60),
        endedAt: Date(timeIntervalSince1970: end), exercises: [])
    }
    let library = WorkoutLibrary(programs: [
      WorkoutProgram(id: "keep", name: "K"), WorkoutProgram(id: "drop", name: "D"),
    ])
    let history = WorkoutHistory(records: [record("old", 100)])
    let newer: JSONValue? = JSONValue.encoding(record("new", 200))
    let removed: JSONValue? = nil
    let applied = WorkoutSyncCodec.apply(
      [.programs: ["drop": removed], .sessions: ["new": newer]],
      library: library, history: history)
    XCTAssertEqual(applied.library.programs.map(\.id), ["keep"])
    XCTAssertEqual(applied.history.records.map(\.id), ["new", "old"])
  }

  func testIDRuleMatchesServerContract() {
    XCTAssertTrue(WorkoutSyncRules.isValidID(UUID().uuidString))
    XCTAssertTrue(WorkoutSyncRules.isValidID("a_B-9"))
    XCTAssertFalse(WorkoutSyncRules.isValidID(""))
    XCTAssertFalse(WorkoutSyncRules.isValidID(String(repeating: "a", count: 65)))
    XCTAssertFalse(WorkoutSyncRules.isValidID("a/b"))
  }

  func testStateSurvivesJSONRoundTrip() throws {
    var state = WorkoutSyncState(serverKey: "host")
    state.reconcile(
      local: local(
        ["a": obj("A")], ["r": .object(["n": .number(2.5), "t": .bool(true), "z": .null])]))
    let data = try JSONEncoder().encode(state)
    XCTAssertEqual(try JSONDecoder().decode(WorkoutSyncState.self, from: data), state)
  }
}

// MARK: - APIClient encoding / decoding

@MainActor
final class WorkoutAPITests: XCTestCase {
  private func credential() -> SessionCredential {
    SessionCredential(
      name: "__Host-ritm_session", value: "header.payload.signature",
      expires: Date().addingTimeInterval(3600))
  }

  func testWorkoutPutSendsDataAndNullExpectedVersionForCreate() async throws {
    let transport = StubTransport([
      StubReply(json: #"{"id":"p-1","updatedAt":"2026-10-28T10:00:00.000Z","data":{"name":"A"}}"#)
    ])
    let client = try APIClient(transport: transport)
    try await client.restoreCredential(credential())
    let doc = try await client.putWorkoutDoc(
      kind: .programs, id: "p-1", data: obj("A"), expectedUpdatedAt: nil)
    XCTAssertEqual(doc.updatedAt, "2026-10-28T10:00:00.000Z")
    XCTAssertEqual(doc.data, obj("A"))
    let sent = await transport.requests()
    let request = try XCTUnwrap(sent.first)
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.url?.path, "/api/workouts/programs/p-1")
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertTrue(object["expectedUpdatedAt"] is NSNull)
    XCTAssertEqual((object["data"] as? [String: Any])?["name"] as? String, "A")
  }

  func testWorkoutConflictCarriesCurrentVersionAndDeleteUsesQueryAnd204() async throws {
    let transport = StubTransport([
      StubReply(
        status: 409,
        json: #"{"error":"Изменено","current":{"id":"s_1","updatedAt":"V2","data":{}}}"#),
      StubReply(status: 204, json: ""),
    ])
    let client = try APIClient(transport: transport)
    try await client.restoreCredential(credential())
    do {
      _ = try await client.putWorkoutDoc(
        kind: .sessions, id: "s_1", data: .object([:]), expectedUpdatedAt: "V1")
      XCTFail("Expected conflict")
    } catch let error as APIError {
      XCTAssertTrue(error.isConflict)
      XCTAssertEqual(error.currentUpdatedAt, "V2")
    }
    try await client.deleteWorkoutDoc(kind: .sessions, id: "s_1", expectedUpdatedAt: "V2")
    let requests = await transport.requests()
    XCTAssertEqual(requests[1].httpMethod, "DELETE")
    XCTAssertEqual(requests[1].url?.path, "/api/workouts/sessions/s_1")
    XCTAssertTrue(requests[1].url?.query?.contains("expectedUpdatedAt=V2") == true)
    XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "application/json")
  }

  func testFetchWorkoutsDecodesBothCollectionsAndRejectsInvalidIDs() async throws {
    let transport = StubTransport([
      StubReply(json: #"{"programs":[{"id":"a","updatedAt":"U","data":{"n":1}}],"sessions":[]}"#)
    ])
    let client = try APIClient(transport: transport)
    try await client.restoreCredential(credential())
    let snapshot = try await client.fetchWorkouts()
    XCTAssertEqual(snapshot.programs.map(\.id), ["a"])
    XCTAssertTrue(snapshot.sessions.isEmpty)
    do {
      _ = try await client.putWorkoutDoc(
        kind: .programs, id: "../x", data: .object([:]), expectedUpdatedAt: nil)
      XCTFail("Expected invalid id")
    } catch let error as APIError {
      XCTAssertEqual(error.status, 400)
    }
    let count = await transport.requests().count
    XCTAssertEqual(count, 1)
  }
}
