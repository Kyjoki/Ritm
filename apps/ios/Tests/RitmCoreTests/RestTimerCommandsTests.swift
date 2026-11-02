import XCTest

@testable import RitmCore

final class RestTimerCommandsTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 2_000_000)

  private func state(
    filled: Bool = true, version: Int = 0, rest: RestTimer = RestTimer(), sets: Int = 2
  ) -> SharedWorkoutState {
    let list = (0..<sets).map {
      WorkoutSet(id: "s\($0)", weight: filled ? "80" : "", reps: filled ? "5" : "")
    }
    let item = WorkoutSessionItem(id: "i", exerciseID: "bench", name: "Жим", previous: nil, sets: list)
    let session = WorkoutSession(id: "w", programID: "p", programName: "Грудь", startedAt: t0, items: [item])
    return SharedWorkoutState(version: version, session: session, rest: rest)
  }

  private func doneCount(_ s: SharedWorkoutState) -> Int { s.session?.doneSets ?? -1 }

  func testConfirmTicksNextSetAndStartsRestWithThePreset() {
    var rest = RestTimer()
    rest.setPreset(120, now: t0)
    let result = state(rest: rest).applying(.confirmNextSet, now: t0, expectedVersion: 0)
    XCTAssertEqual(result.outcome, .applied)
    XCTAssertEqual(doneCount(result.state), 1)
    XCTAssertEqual(result.state.rest.endDate, t0.addingTimeInterval(120))
    XCTAssertEqual(result.state.version, 1)
    XCTAssertEqual(result.state.phase(now: t0), .rest)
    XCTAssertEqual(result.state.currentSetIndex, 1)
  }

  func testConfirmNeedsWeightAndRepsAndChangesNothing() {
    let empty = state(filled: false)
    let result = empty.applying(.confirmNextSet, now: t0, expectedVersion: 0)
    XCTAssertEqual(result.outcome, .rejected(.needsWeight))
    XCTAssertEqual(result.state, empty)

    var noReps = state()
    noReps.session?.update("i") { $0.typeReps("", setID: "s0") }
    XCTAssertEqual(noReps.applying(.confirmNextSet, now: t0, expectedVersion: 0).outcome, .rejected(.needsReps))
  }

  func testRapidDoubleConfirmTicksOnlyOnce() {
    let first = state().applying(.confirmNextSet, now: t0, expectedVersion: 0)
    // Same version again (a race) and the fresh version a moment later (a double tap).
    XCTAssertEqual(first.state.applying(.confirmNextSet, now: t0, expectedVersion: 0).outcome, .ignoredStale)
    let second = first.state.applying(.confirmNextSet, now: t0.addingTimeInterval(0.4), expectedVersion: 1)
    XCTAssertEqual(second.outcome, .ignoredDuplicate)
    XCTAssertEqual(doneCount(second.state), 1)
    XCTAssertEqual(second.state.version, 1)
    // A deliberate confirm later ticks the next set.
    let later = first.state.applying(.confirmNextSet, now: t0.addingTimeInterval(30), expectedVersion: 1)
    XCTAssertEqual(later.outcome, .applied)
    XCTAssertEqual(doneCount(later.state), 2)
  }

  func testLastSetEndsWithoutARest() {
    let one = state(sets: 1)
    let result = one.applying(.confirmNextSet, now: t0, expectedVersion: nil)
    XCTAssertEqual(result.outcome, .applied)
    XCTAssertNil(result.state.rest.endDate)
    XCTAssertEqual(result.state.phase(now: t0), .allDone)
    XCTAssertNil(result.state.current)
    XCTAssertEqual(
      result.state.applying(.confirmNextSet, now: t0.addingTimeInterval(60), expectedVersion: nil).outcome,
      .rejected(.allSetsDone))
  }

  func testStaleVersionIsIgnoredSafely() {
    let current = state(version: 5)
    let result = current.applying(.extend(seconds: 30), now: t0, expectedVersion: 4)
    XCTAssertEqual(result.outcome, .ignoredStale)
    XCTAssertEqual(result.state, current)
  }

  func testTwoCommandsForTheSameVersionOnlyOneWins() {
    let base = state()
    let first = base.applying(.extend(seconds: 30), now: t0, expectedVersion: 0)
    let second = first.state.applying(.skip, now: t0, expectedVersion: 0)
    XCTAssertEqual(first.outcome, .applied)
    XCTAssertEqual(second.outcome, .ignoredStale)
    XCTAssertEqual(second.state, first.state)
  }

  func testExtendMovesTheAbsoluteEndDate() {
    var rest = RestTimer()
    rest.start(now: t0)
    let result = state(rest: rest).applying(.extend(seconds: 30), now: t0.addingTimeInterval(10), expectedVersion: 0)
    XCTAssertEqual(result.outcome, .applied)
    XCTAssertEqual(result.state.rest.endDate, t0.addingTimeInterval(120))
    XCTAssertEqual(result.state.rest.remaining(now: t0.addingTimeInterval(10)), 110, accuracy: 0.001)
  }

  func testExtendWithoutARestStartsOneAndNeverGoesNegative() {
    let result = state().applying(.extend(seconds: 30), now: t0, expectedVersion: 0)
    XCTAssertEqual(result.state.rest.remaining(now: t0), 30, accuracy: 0.001)
    XCTAssertEqual(result.state.rest.remaining(now: t0.addingTimeInterval(9_999)), 0)
  }

  func testExtendRejectsNonsenseAndCapsHugeValues() {
    for bad in [0, -30, .nan, .infinity] as [TimeInterval] {
      let base = state()
      let result = base.applying(.extend(seconds: bad), now: t0, expectedVersion: 0)
      XCTAssertEqual(result.outcome, .rejected(.invalidSeconds))
      XCTAssertEqual(result.state, base)
    }
    let big = state().applying(.extend(seconds: 100_000), now: t0, expectedVersion: 0)
    XCTAssertEqual(big.state.rest.remaining(now: t0), RestCommandReducer.maxExtension, accuracy: 0.001)
  }

  func testExtendKeepsAPausedRestPaused() {
    var rest = RestTimer()
    rest.start(now: t0)
    rest.pause(now: t0.addingTimeInterval(30))
    let result = state(rest: rest).applying(.extend(seconds: 30), now: t0.addingTimeInterval(500), expectedVersion: 0)
    XCTAssertEqual(result.state.phase(now: t0.addingTimeInterval(500)), .paused)
    XCTAssertEqual(result.state.rest.remaining(now: t0.addingTimeInterval(500)), 90, accuracy: 0.001)
  }

  func testSkipEndsTheRestAndNeverTicksASet() {
    var rest = RestTimer()
    rest.start(now: t0)
    let before = state(rest: rest)
    let result = before.applying(.skip, now: t0.addingTimeInterval(5), expectedVersion: 0)
    XCTAssertEqual(result.outcome, .applied)
    XCTAssertNil(result.state.rest.endDate)
    XCTAssertEqual(doneCount(result.state), 0)
    XCTAssertEqual(result.state.session, before.session)
    XCTAssertEqual(result.state.phase(now: t0), .set)
  }

  func testSkipWithoutARestDoesNothing() {
    let base = state()
    let result = base.applying(.skip, now: t0, expectedVersion: 0)
    XCTAssertEqual(result.outcome, .ignoredNothingToDo)
    XCTAssertEqual(result.state, base)
    XCTAssertEqual(doneCount(result.state), 0)
  }

  func testNoWorkoutIgnoresEverything() {
    let none = SharedWorkoutState()
    for command in [RestCommand.skip, .confirmNextSet, .extend(seconds: 30)] {
      let result = apply(command: command, to: none, now: t0, expectedVersion: 0)
      XCTAssertEqual(result.outcome, .ignoredNoWorkout)
      XCTAssertEqual(result.state, none)
    }
  }

  func testStateRoundTripsThroughJSON() throws {
    let result = state().applying(.confirmNextSet, now: t0, expectedVersion: 0).state
    let data = try WorkoutCoding.encoder().encode(result)
    XCTAssertEqual(try WorkoutCoding.decoder().decode(SharedWorkoutState.self, from: data), result)
  }

  func testPhaseFollowsTheRestTimer() {
    var rest = RestTimer()
    rest.start(now: t0)
    XCTAssertEqual(state(rest: rest).phase(now: t0), .rest)
    XCTAssertEqual(state(rest: rest).phase(now: t0.addingTimeInterval(500)), .set)
    rest.pause(now: t0.addingTimeInterval(10))
    XCTAssertEqual(state(rest: rest).phase(now: t0.addingTimeInterval(20)), .paused)
  }
}
