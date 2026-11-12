import Foundation
import XCTest

@testable import RitmCore

/// The running-workout screen lagged when moving between exercises: every render rebuilt lists of
/// exercises to find a muscle, formatted every row again and built the next card while it slid.
/// These tests pin the pure parts that now carry that work: the muscle lookup, the card model
/// the table is compared by, the window of alive cards and the rest clock of the plan steppers.
final class WorkoutScreenPerformanceTests: XCTestCase {
  private let bench = WorkoutCatalog.builtinID("bench")

  private func item(sets: [WorkoutSet], previous: [WorkoutResultSet]? = nil) -> WorkoutSessionItem {
    WorkoutSessionItem(
      id: "i1", exerciseID: bench, name: "Жим лёжа",
      previous: previous.map { WorkoutPrevious(date: Date(timeIntervalSince1970: 0), sets: $0) },
      sets: sets)
  }

  private func sets(_ count: Int, done: Int = 0) -> [WorkoutSet] {
    (0..<count).map { WorkoutSet(id: "s\($0)", weight: "60", reps: "10", done: $0 < done) }
  }

  // MARK: Muscle lookup

  func testMuscleOfBuiltinAndCustomExercises() {
    let custom = [WorkoutExercise(id: "custom.1", name: "Мой", muscle: .abs)]
    XCTAssertEqual(WorkoutCatalog.muscle(of: bench, custom: custom), .chest)
    XCTAssertEqual(WorkoutCatalog.muscle(of: WorkoutCatalog.builtinID("pushdown"), custom: []), .triceps)
    XCTAssertEqual(WorkoutCatalog.muscle(of: "custom.1", custom: custom), .abs)
    XCTAssertNil(WorkoutCatalog.muscle(of: "custom.1", custom: []))
    XCTAssertNil(WorkoutCatalog.muscle(of: "nope", custom: custom))
  }

  func testEveryBuiltinExerciseKeepsItsMuscle() {
    for exercise in WorkoutCatalog.builtin(language: .ru) {
      XCTAssertEqual(WorkoutCatalog.muscle(of: exercise.id, custom: []), exercise.muscle)
    }
  }

  // MARK: Card model

  func testCardModelFormatsRowsOnce() {
    let previous = [WorkoutResultSet(weight: 62.5, reps: 8), WorkoutResultSet(weight: 60, reps: 10)]
    let model = WorkoutCardModel.make(item: item(sets: sets(3, done: 1), previous: previous), comma: true)
    XCTAssertEqual(model.rows.map(\.previousText), ["62,5 × 8", "60 × 10", "—"])
    XCTAssertEqual(model.activeIndex, 1)
    XCTAssertEqual(model.rows.map(\.isActive), [false, true, false])
    XCTAssertEqual(model.doneCount, 1)
    XCTAssertEqual(model.leadingSetID, "s1")
    XCTAssertTrue(model.canRemoveSet)
    XCTAssertTrue(model.canAddSet)
  }

  func testCardModelDotSeparatorAndNoHistory() {
    let model = WorkoutCardModel.make(
      item: item(sets: sets(1), previous: [WorkoutResultSet(weight: 62.5, reps: 8)]), comma: false)
    XCTAssertEqual(model.rows.map(\.previousText), ["62.5 × 8"])
    let none = WorkoutCardModel.make(item: item(sets: sets(2)), comma: true)
    XCTAssertEqual(none.rows.map(\.previousText), ["—", "—"])
    XCTAssertFalse(WorkoutCardModel.make(item: item(sets: sets(1)), comma: true).canRemoveSet)
  }

  func testCardModelOfFinishedExerciseLeadsWithTheLastSet() {
    let model = WorkoutCardModel.make(item: item(sets: sets(3, done: 3)), comma: true)
    XCTAssertNil(model.activeIndex)
    XCTAssertEqual(model.leadingSetID, "s2")
    XCTAssertFalse(model.canRemoveSet)
    XCTAssertEqual(model.doneCount, 3)
  }

  func testCardModelLimitsAddingSets() {
    let full = WorkoutCardModel.make(
      item: item(sets: sets(WorkoutSessionItem.maxSets)), comma: true)
    XCTAssertFalse(full.canAddSet)
  }

  func testEqualItemsGiveEqualModelsAndAnEditChangesThem() {
    let base = item(sets: sets(3))
    XCTAssertEqual(WorkoutCardModel.make(item: base, comma: true), WorkoutCardModel.make(item: base, comma: true))
    var typed = base
    typed.sets[0].weight = "62,5"
    XCTAssertNotEqual(WorkoutCardModel.make(item: base, comma: true), WorkoutCardModel.make(item: typed, comma: true))
  }

  /// A loose ceiling, not a benchmark: 12 sets worked out 2000 times (more renders than a long
  /// workout has) must stay far below a frame budget per render.
  func testCardModelIsCheapEnoughForEveryRender() {
    let heavy = item(
      sets: sets(12, done: 4),
      previous: (0..<12).map { WorkoutResultSet(weight: 60 + Double($0) * 2.5, reps: 8) })
    let start = Date()
    var total = 0
    for _ in 0..<2000 { total += WorkoutCardModel.make(item: heavy, comma: true).rows.count }
    XCTAssertEqual(total, 24_000)
    XCTAssertLessThan(Date().timeIntervalSince(start), 5)
  }

  // MARK: Pager window

  func testWindowStartsWithTheCurrentCardOnly() {
    let window = WorkoutPagerWindow(current: 2)
    XCTAssertEqual(window.indices(count: 5), [2])
  }

  func testSettledWindowHoldsBothNeighbours() {
    var window = WorkoutPagerWindow(current: 2)
    window.settle()
    XCTAssertEqual(window.indices(count: 5), [1, 2, 3])
    var edge = WorkoutPagerWindow(current: 0)
    edge.settle()
    XCTAssertEqual(edge.indices(count: 5), [0, 1])
    var last = WorkoutPagerWindow(current: 4)
    last.settle()
    XCTAssertEqual(last.indices(count: 5), [3, 4])
  }

  func testSlideKeepsTheOldCardAndBuildsNoNewNeighbour() {
    var window = WorkoutPagerWindow(current: 1)
    window.settle()
    window.move(to: 2, reduceMotion: false)
    XCTAssertFalse(window.fade)
    XCTAssertEqual(window.previous, 1)
    // Cards 1 and 2 already exist; card 3 waits for the move to settle.
    XCTAssertEqual(window.indices(count: 5), [1, 2])
    window.settle()
    XCTAssertEqual(window.indices(count: 5), [1, 2, 3])
  }

  func testFarMoveAndReducedMotionCrossFade() {
    var far = WorkoutPagerWindow(current: 0)
    far.settle()
    far.move(to: 3, reduceMotion: false)
    XCTAssertTrue(far.fade)
    XCTAssertEqual(far.indices(count: 5), [3])
    var reduced = WorkoutPagerWindow(current: 0)
    reduced.move(to: 1, reduceMotion: true)
    XCTAssertTrue(reduced.fade)
    XCTAssertEqual(reduced.indices(count: 5), [1])
  }

  func testMoveToTheSameOrInvalidCardChangesNothing() {
    var window = WorkoutPagerWindow(current: 1)
    window.settle()
    let before = window
    window.move(to: 1, reduceMotion: false)
    window.move(to: -1, reduceMotion: false)
    XCTAssertEqual(window, before)
  }

  func testWindowFollowsAShrinkingWorkout() {
    var window = WorkoutPagerWindow(current: 4)
    window.settle()
    XCTAssertEqual(window.indices(count: 3), [1, 2])
    XCTAssertEqual(window.indices(count: 0), [])
  }

  func testResetDropsEverythingButTheCurrentCard() {
    var window = WorkoutPagerWindow(current: 1)
    window.settle()
    window.move(to: 2, reduceMotion: false)
    window.reset(to: 0)
    XCTAssertEqual(window.indices(count: 3), [0])
    XCTAssertNil(window.previous)
  }

  // MARK: Rest as the steppers show it

  func testRestClock() {
    XCTAssertEqual(WorkoutFormat.restClock(seconds: 180), "3:00")
    XCTAssertEqual(WorkoutFormat.restClock(seconds: 45), "0:45")
    XCTAssertEqual(WorkoutFormat.restClock(seconds: 15), "0:15")
    XCTAssertEqual(WorkoutFormat.restClock(seconds: 905), "15:05")
    XCTAssertEqual(WorkoutFormat.restClock(seconds: 900), "15:00")
    XCTAssertEqual(WorkoutFormat.restClock(seconds: -5), "0:00")
  }

  func testRestSpoken() {
    XCTAssertEqual(WorkoutFormat.restSpoken(seconds: 180, russian: true), "3 мин")
    XCTAssertEqual(WorkoutFormat.restSpoken(seconds: 45, russian: true), "45 с")
    XCTAssertEqual(WorkoutFormat.restSpoken(seconds: 150, russian: true), "2 мин 30 с")
    XCTAssertEqual(WorkoutFormat.restSpoken(seconds: 150, russian: false), "2 min 30 s")
  }
}
