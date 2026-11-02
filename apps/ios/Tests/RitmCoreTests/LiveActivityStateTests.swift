import XCTest

@testable import RitmCore

final class LiveActivityStateTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 3_000_000)

  private func state(rest: RestTimer = RestTimer(), done: Int = 0, id: String = "w") -> SharedWorkoutState {
    let sets = (0..<3).map { WorkoutSet(id: "s\($0)", weight: "80", reps: "5", done: $0 < done) }
    let bench = WorkoutSessionItem(id: "i", exerciseID: "bench", name: "Жим лёжа", previous: nil, sets: sets)
    let session = WorkoutSession(id: id, programID: "p", programName: "Грудь", startedAt: t0, items: [bench])
    return SharedWorkoutState(session: session, rest: rest)
  }

  private func content(_ s: SharedWorkoutState, privacy: Bool = false, now: Date? = nil) -> LiveActivityContent {
    LiveActivityContent.make(from: s, privacy: privacy, now: now ?? t0)!
  }

  func testSetPhaseShowsPlannedValuesAndLabel() {
    let c = content(state(done: 2))
    XCTAssertEqual(c.setLabel, "Подход 3/3")
    XCTAssertEqual(c.phase, .set)
    XCTAssertEqual(c.plannedWeight, "80")
    XCTAssertEqual(c.plannedReps, 5)
    XCTAssertEqual(c.exerciseName, "Жим лёжа")
    XCTAssertEqual(c.programName, "Грудь")
    XCTAssertNil(c.restEndDate)
  }

  func testRestPhaseCarriesTheAbsoluteEndDateAndTheNextSet() {
    var rest = RestTimer()
    rest.start(now: t0)
    let c = content(state(rest: rest, done: 1), now: t0.addingTimeInterval(10))
    XCTAssertEqual(c.phase, .rest)
    XCTAssertEqual(c.restEndDate, t0.addingTimeInterval(90))
    XCTAssertEqual(c.setNumber, 2)
    XCTAssertEqual(c.staleDate, t0.addingTimeInterval(90 + LiveActivityContent.restStaleGrace))
  }

  func testPausedRestKeepsStaticRemaining() {
    var rest = RestTimer()
    rest.start(now: t0)
    rest.pause(now: t0.addingTimeInterval(30))
    let c = content(state(rest: rest), now: t0.addingTimeInterval(400))
    XCTAssertEqual(c.phase, .paused)
    XCTAssertNil(c.restEndDate)
    XCTAssertEqual(c.pausedRestSeconds, 60)
  }

  func testPrivacyHidesWeights() {
    let c = content(state(), privacy: true)
    XCTAssertNil(c.plannedWeight)
    XCTAssertTrue(c.hidesWeights)
    XCTAssertEqual(c.plannedReps, 5)
    let json = String(decoding: try! WorkoutCoding.encoder().encode(c), as: UTF8.self)
    XCTAssertFalse(json.contains("\"80\""))
  }

  func testBlankSetHasNoPlannedValues() {
    var s = state()
    s.session?.update("i") { $0.sets[0] = WorkoutSet(id: "s0") }
    let c = content(s)
    XCTAssertNil(c.plannedWeight)
    XCTAssertNil(c.plannedReps)
  }

  func testAllDoneCardHasNoPlannedValues() {
    let c = content(state(done: 3))
    XCTAssertEqual(c.phase, .allDone)
    XCTAssertEqual(c.setNumber, 3)
    XCTAssertNil(c.plannedWeight)
    XCTAssertNil(c.plannedReps)
  }

  func testNoWorkoutMeansNoContent() {
    XCTAssertNil(LiveActivityContent.make(from: SharedWorkoutState(), privacy: false, now: t0))
    XCTAssertNil(LiveActivityContent.make(from: nil, rest: RestTimer(), privacy: false, now: t0))
  }

  func testShouldUpdateIgnoresTimeAndStaleDateButSeesRealChanges() {
    let a = content(state(), now: t0)
    let sameLater = content(state(), now: t0.addingTimeInterval(7_200))
    XCTAssertFalse(LiveActivityContent.shouldUpdate(old: a, new: sameLater))
    XCTAssertFalse(LiveActivityContent.shouldUpdate(old: nil, new: nil))
    XCTAssertTrue(LiveActivityContent.shouldUpdate(old: nil, new: a))
    XCTAssertTrue(LiveActivityContent.shouldUpdate(old: a, new: content(state(done: 1))))
    XCTAssertTrue(LiveActivityContent.shouldUpdate(old: a, new: content(state(), privacy: true)))
    var rest = RestTimer()
    rest.start(now: t0)
    XCTAssertTrue(LiveActivityContent.shouldUpdate(old: a, new: content(state(rest: rest))))
  }

  func testSecondsOfARunningRestNeverTriggerUpdates() {
    var rest = RestTimer()
    rest.start(now: t0)
    let s = state(rest: rest)
    let first = content(s, now: t0.addingTimeInterval(1))
    for second in 2...60 {
      XCTAssertFalse(
        LiveActivityContent.shouldUpdate(old: first, new: content(s, now: t0.addingTimeInterval(Double(second)))))
    }
  }

  func testContentRoundTripsAndIsSmall() throws {
    let c = content(state())
    let data = try WorkoutCoding.encoder().encode(c)
    XCTAssertEqual(try WorkoutCoding.decoder().decode(LiveActivityContent.self, from: data), c)
    XCTAssertLessThan(data.count, 1_024)
  }

  func testLifecycleStartsOnceAndReusesTheActivity() {
    let c = content(state())
    XCTAssertEqual(LiveActivityLifecycle.decide(content: c, existing: nil, enabled: true), .start(workoutID: "w"))
    XCTAssertEqual(LiveActivityLifecycle.decide(content: c, existing: c, enabled: true), .none)
    let next = content(state(done: 1))
    XCTAssertEqual(LiveActivityLifecycle.decide(content: next, existing: c, enabled: true), .update(workoutID: "w"))
  }

  func testLifecycleDoesNotStartWhenDisabled() {
    let c = content(state())
    XCTAssertEqual(LiveActivityLifecycle.decide(content: c, existing: nil, enabled: false), .none)
    XCTAssertEqual(LiveActivityLifecycle.decide(content: c, existing: c, enabled: false), .end(workoutID: "w"))
  }

  func testLifecycleEndsOnFinishOrCancelAndLeavesNoGhost() {
    let c = content(state())
    XCTAssertEqual(LiveActivityLifecycle.decide(content: nil, existing: c, enabled: true), .end(workoutID: "w"))
    XCTAssertEqual(LiveActivityLifecycle.decide(content: nil, existing: nil, enabled: true), .none)
  }

  func testLifecycleReplacesAnActivityOfAnotherWorkout() {
    let old = content(state(id: "old"))
    let new = content(state(id: "new"))
    XCTAssertEqual(
      LiveActivityLifecycle.decide(content: new, existing: old, enabled: true),
      .replace(ending: "old", starting: "new"))
  }
}
