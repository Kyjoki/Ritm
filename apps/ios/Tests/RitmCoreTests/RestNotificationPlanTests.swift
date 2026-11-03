import XCTest

@testable import RitmCore

final class RestNotificationPlanTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 3_000_000)

  private func state(rest: RestTimer, done: Int = 1) -> SharedWorkoutState {
    let sets = (0..<3).map { WorkoutSet(id: "s\($0)", weight: "80", reps: "5", done: $0 < done) }
    let bench = WorkoutSessionItem(id: "i", exerciseID: "bench", name: "Жим лёжа", previous: nil, sets: sets)
    let session = WorkoutSession(id: "w1", programID: "p", programName: "Грудь", startedAt: t0, items: [bench])
    return SharedWorkoutState(session: session, rest: rest)
  }

  private func running(_ now: Date) -> RestTimer {
    var rest = RestTimer()
    rest.start(now: now)
    return rest
  }

  func testRunningRestFiresAtTheAbsoluteEndWithTheNextSet() throws {
    let plan = try XCTUnwrap(
      RestNotificationPlanner.plan(state: state(rest: running(t0)), privacy: false, russian: true, now: t0.addingTimeInterval(5)))
    XCTAssertEqual(plan.fireDate, t0.addingTimeInterval(180))
    XCTAssertEqual(plan.identifier, "ritm.workout.rest.w1")
    XCTAssertEqual(plan.title, "Отдых закончился")
    XCTAssertEqual(plan.body, "Дальше: Жим лёжа · подход 2/3 · 80 кг × 5")
  }

  func testPrivacyRemovesWeights() throws {
    let plan = try XCTUnwrap(
      RestNotificationPlanner.plan(state: state(rest: running(t0)), privacy: true, russian: false, now: t0))
    XCTAssertEqual(plan.body, "Next: Жим лёжа · set 2/3 · 5 reps")
    XCTAssertFalse(plan.body.contains("80"))
  }

  func testExtendMovesTheFireDate() throws {
    var rest = running(t0)
    rest.extend(now: t0.addingTimeInterval(10), by: 30)
    let plan = try XCTUnwrap(RestNotificationPlanner.plan(state: state(rest: rest), privacy: false, russian: true, now: t0.addingTimeInterval(10)))
    XCTAssertEqual(plan.fireDate, t0.addingTimeInterval(210))
  }

  func testNothingWhenSkippedPausedFinishedOrAllDone() {
    let now = t0.addingTimeInterval(5)
    var skipped = running(t0)
    skipped.skip()
    var paused = running(t0)
    paused.pause(now: now)
    XCTAssertNil(RestNotificationPlanner.plan(state: state(rest: skipped), privacy: false, russian: true, now: now))
    XCTAssertNil(RestNotificationPlanner.plan(state: state(rest: paused), privacy: false, russian: true, now: now))
    XCTAssertNil(RestNotificationPlanner.plan(state: state(rest: running(t0)), privacy: false, russian: true, now: t0.addingTimeInterval(185)))
    XCTAssertNil(RestNotificationPlanner.plan(state: state(rest: running(t0), done: 3), privacy: false, russian: true, now: now))
    XCTAssertNil(RestNotificationPlanner.plan(state: SharedWorkoutState(), privacy: false, russian: true, now: now))
  }
}
