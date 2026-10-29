import XCTest

@testable import RitmCore

final class MotionTimingTests: XCTestCase {
  func testFirstCountStartsAtThirtyFivePercentOfTheFinalValue() {
    XCTAssertEqual(CountInterpolation.start(final: 1000, previous: nil), 350, accuracy: 0.0001)
    XCTAssertEqual(CountInterpolation.start(final: -200, previous: nil), -70, accuracy: 0.0001)
    XCTAssertEqual(CountInterpolation.start(final: 0, previous: nil), 0)
  }

  func testChangeStartsFromThePreviousValue() {
    XCTAssertEqual(CountInterpolation.start(final: 900, previous: 400), 400)
    XCTAssertEqual(CountInterpolation.start(final: 5, previous: 0), 0)
  }

  func testNonFinitePreviousFallsBackToTheShare() {
    XCTAssertEqual(CountInterpolation.start(final: 100, previous: .nan), 35, accuracy: 0.0001)
  }

  func testDurationsFollowTheSpec() {
    XCTAssertEqual(CountInterpolation.duration(isFirst: true), 0.6)
    XCTAssertEqual(CountInterpolation.duration(isFirst: false), 0.45)
  }

  func testUnchangedOrInvalidValuesNeverAnimate() {
    XCTAssertFalse(CountInterpolation.shouldAnimate(from: 10, to: 10))
    XCTAssertFalse(CountInterpolation.shouldAnimate(from: 0, to: .infinity))
    XCTAssertFalse(CountInterpolation.shouldAnimate(from: .nan, to: 3))
    XCTAssertTrue(CountInterpolation.shouldAnimate(from: 3.5, to: 10))
  }

  func testEaseOutCubicRunsFastThenSettlesExactlyOnTheFinalValue() {
    XCTAssertEqual(CountInterpolation.easeOutCubic(0), 0)
    XCTAssertEqual(CountInterpolation.easeOutCubic(1), 1)
    XCTAssertEqual(CountInterpolation.easeOutCubic(0.5), 0.875, accuracy: 0.0001)
    XCTAssertEqual(CountInterpolation.easeOutCubic(-1), 0)
    XCTAssertEqual(CountInterpolation.easeOutCubic(3), 1)
  }

  func testValueInterpolatesBetweenTheEnds() {
    XCTAssertEqual(CountInterpolation.value(from: 350, to: 1000, progress: 0), 350)
    XCTAssertEqual(CountInterpolation.value(from: 350, to: 1000, progress: 1), 1000)
    XCTAssertEqual(CountInterpolation.value(from: 100, to: 0, progress: 0.5), 12.5, accuracy: 0.0001)
  }

  func testStaggerIsFortyFiveMillisecondsAndCapsAtEight() {
    XCTAssertEqual(MotionStagger.delay(index: 0), 0)
    XCTAssertEqual(MotionStagger.delay(index: 1), 0.045, accuracy: 0.0001)
    XCTAssertEqual(MotionStagger.delay(index: 7), 0.315, accuracy: 0.0001)
    XCTAssertEqual(MotionStagger.delay(index: 8), MotionStagger.delay(index: 7))
    XCTAssertEqual(MotionStagger.delay(index: 40), MotionStagger.delay(index: 7))
    XCTAssertEqual(MotionStagger.delay(index: -3), 0)
  }
}
