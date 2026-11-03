import XCTest

@testable import RitmCore

final class WorkoutRestTimerTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_000_000)

  func testIdleShowsThePreset() {
    let timer = RestTimer()
    XCTAssertEqual(timer.phase(now: t0), .idle)
    XCTAssertEqual(timer.remaining(now: t0), 180)
  }

  func testRunningUsesAnAbsoluteEndDate() {
    var timer = RestTimer()
    timer.start(now: t0)
    XCTAssertEqual(timer.endDate, t0.addingTimeInterval(180))
    XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(30)), 150, accuracy: 0.001)
    // Hours later (the app was suspended): no negative values, finished.
    XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(7_200)), 0)
    XCTAssertEqual(timer.phase(now: t0.addingTimeInterval(7_200)), .finished)
  }

  func testPauseAndResumeKeepTheRemainingTime() {
    var timer = RestTimer()
    timer.start(now: t0)
    timer.pause(now: t0.addingTimeInterval(40))
    XCTAssertEqual(timer.phase(now: t0.addingTimeInterval(500)), .paused)
    XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(500)), 140, accuracy: 0.001)
    timer.start(now: t0.addingTimeInterval(500))
    XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(510)), 130, accuracy: 0.001)
  }

  func testExtendAddsFifteenSecondsInEveryPhase() {
    var running = RestTimer()
    running.start(now: t0)
    running.extend(now: t0.addingTimeInterval(10))
    XCTAssertEqual(running.remaining(now: t0.addingTimeInterval(10)), 185, accuracy: 0.001)

    var paused = RestTimer()
    paused.start(now: t0)
    paused.pause(now: t0.addingTimeInterval(30))
    paused.extend(now: t0.addingTimeInterval(31))
    XCTAssertEqual(paused.remaining(now: t0.addingTimeInterval(99)), 165, accuracy: 0.001)

    var idle = RestTimer()
    idle.extend(now: t0)
    XCTAssertEqual(idle.phase(now: t0), .running)
    XCTAssertEqual(idle.remaining(now: t0), 15, accuracy: 0.001)
  }

  func testSkipAndResetReturnToIdleAtThePreset() {
    var timer = RestTimer(preset: 120)
    timer.start(now: t0)
    timer.skip()
    XCTAssertEqual(timer.phase(now: t0), .idle)
    XCTAssertEqual(timer.remaining(now: t0), 120)
    timer.start(now: t0)
    timer.pause(now: t0.addingTimeInterval(5))
    timer.reset()
    XCTAssertEqual(timer.phase(now: t0), .idle)
  }

  func testRestartAlwaysStartsAFullRest() {
    var timer = RestTimer()
    timer.start(now: t0)
    timer.restart(now: t0.addingTimeInterval(50))
    XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(50)), 180, accuracy: 0.001)
    timer.pause(now: t0.addingTimeInterval(60))
    timer.restart(now: t0.addingTimeInterval(70))
    XCTAssertEqual(timer.phase(now: t0.addingTimeInterval(70)), .running)
  }

  func testPresetsAreFixedAndChangingOneRestartsARunningRest() {
    var timer = RestTimer()
    timer.setPreset(45, now: t0)
    XCTAssertEqual(timer.preset, 180)
    timer.start(now: t0)
    timer.setPreset(180, now: t0.addingTimeInterval(20))
    XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(20)), 180, accuracy: 0.001)
    XCTAssertEqual(RestTimer.presets, [60, 90, 120, 180])
  }

  func testRoundTripThroughJSONKeepsTheState() throws {
    var timer = RestTimer(preset: 60)
    timer.start(now: t0)
    let data = try WorkoutCoding.encoder().encode(timer)
    let back = try WorkoutCoding.decoder().decode(RestTimer.self, from: data)
    XCTAssertEqual(back.remaining(now: t0.addingTimeInterval(20)), 40, accuracy: 0.001)
    let garbage = try WorkoutCoding.decoder().decode(RestTimer.self, from: Data(#"{"preset":7}"#.utf8))
    XCTAssertEqual(garbage.preset, 180)
  }

  func testClockFormats() {
    XCTAssertEqual(WorkoutClock.format(seconds: 0), "00:00")
    XCTAssertEqual(WorkoutClock.format(seconds: 65), "01:05")
    XCTAssertEqual(WorkoutClock.format(seconds: 3_725), "1:02:05")
    XCTAssertEqual(WorkoutClock.elapsed(from: t0, now: t0.addingTimeInterval(125.9)), "02:05")
    XCTAssertEqual(WorkoutClock.elapsed(from: t0, now: t0.addingTimeInterval(-5)), "00:00")
    XCTAssertEqual(WorkoutClock.rest(remaining: 1.2), "00:02")
    XCTAssertEqual(WorkoutClock.rest(remaining: -3), "00:00")
  }
}
