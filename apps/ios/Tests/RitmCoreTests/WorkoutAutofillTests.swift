import XCTest

@testable import RitmCore

final class WorkoutAutofillTests: XCTestCase {
  private func item(sets count: Int = 4, weights: [String]? = nil) -> WorkoutSessionItem {
    let sets = (0..<count).map { WorkoutSet(id: "s\($0)", weight: weights?[$0] ?? "", reps: "") }
    return WorkoutSessionItem(id: "i", exerciseID: "e", name: "Жим", previous: nil, sets: sets)
  }

  // MARK: parsing

  func testWeightAcceptsDotCommaAndHalfTypedInput() {
    XCTAssertEqual(WorkoutNumber.weight("62,5"), 62.5)
    XCTAssertEqual(WorkoutNumber.weight("62.5"), 62.5)
    XCTAssertEqual(WorkoutNumber.weight("22,"), 22)
    XCTAssertEqual(WorkoutNumber.weight(".5"), 0.5)
    XCTAssertEqual(WorkoutNumber.weight("0"), 0)
    XCTAssertEqual(WorkoutNumber.normalizedWeight("22,"), "22")
    XCTAssertEqual(WorkoutNumber.normalizedWeight("2,50"), "2,50")
  }

  func testWeightRejectsGarbage() {
    for bad in ["", ".", ",", "2.5.", "1,2,3", "12345", "2,555", "abc", "-5", "2 5"] {
      XCTAssertNil(WorkoutNumber.weight(bad), bad)
    }
  }

  func testRepsMustBeAPositiveInteger() {
    XCTAssertEqual(WorkoutNumber.reps("12"), 12)
    XCTAssertNil(WorkoutNumber.reps("0"))
    XCTAssertNil(WorkoutNumber.reps("1,5"))
    XCTAssertNil(WorkoutNumber.reps(""))
    XCTAssertNil(WorkoutNumber.reps("1000"))
  }

  // MARK: shared weight

  func testWeightTypedInSetOneFillsTheOtherUnfinishedSetsAtOnce() {
    var exercise = item()
    exercise.typeWeight("6", setID: "s0")
    XCTAssertEqual(exercise.sets.map(\.weight), ["6", "6", "6", "6"])
    exercise.typeWeight("60", setID: "s0")
    XCTAssertEqual(exercise.sets.map(\.weight), ["60", "60", "60", "60"])
    XCTAssertEqual(exercise.sharedWeight, "60")
    XCTAssertEqual(exercise.sets.map(\.reps), ["", "", "", ""])
    XCTAssertTrue(exercise.sets.allSatisfy { !$0.done })
  }

  func testPrefilledHistoryValuesAreReplacedBySharedFill() {
    var exercise = item(weights: ["50", "50", "52,5", "55"])
    exercise.typeWeight("60", setID: "s0")
    XCTAssertEqual(exercise.sets.map(\.weight), ["60", "60", "60", "60"])
  }

  func testIndividuallyEditedWeightStaysIndividual() {
    var exercise = item()
    exercise.typeWeight("60", setID: "s0")
    exercise.typeWeight("65", setID: "s2")
    exercise.typeWeight("70", setID: "s0")
    XCTAssertEqual(exercise.sets.map(\.weight), ["70", "70", "65", "70"])
  }

  func testClearingAnEditedFieldLetsItFollowAgainAtTheNextTyping() {
    var exercise = item()
    exercise.typeWeight("60", setID: "s0")
    exercise.typeWeight("65", setID: "s2")
    exercise.typeWeight("", setID: "s2")
    XCTAssertFalse(exercise.sets[2].edited)
    exercise.typeWeight("70", setID: "s0")
    XCTAssertEqual(exercise.sets.map(\.weight), ["70", "70", "70", "70"])
  }

  func testDoneSetsAreNeverOverwritten() {
    var exercise = item()
    exercise.typeWeight("60", setID: "s0")
    exercise.typeReps("10", setID: "s1")
    XCTAssertEqual(exercise.toggle(setID: "s1"), .done)
    exercise.typeWeight("70", setID: "s0")
    XCTAssertEqual(exercise.sets.map(\.weight), ["70", "60", "70", "70"])
    exercise.typeWeight("99", setID: "s1")
    XCTAssertEqual(exercise.sets[1].weight, "60")
  }

  func testWhenSetOneIsDoneTheFirstUnfinishedSetLeads() {
    var exercise = item(sets: 3)
    exercise.typeWeight("60", setID: "s0")
    exercise.typeReps("8", setID: "s0")
    XCTAssertEqual(exercise.toggle(setID: "s0"), .done)
    exercise.typeWeight("62,5", setID: "s1")
    XCTAssertEqual(exercise.sets.map(\.weight), ["60", "62,5", "62,5"])
    XCTAssertEqual(exercise.sets[1].edited, false)
  }

  func testIntermediateInvalidInputNeverCorruptsOtherValues() {
    var exercise = item()
    exercise.typeWeight("22", setID: "s0")
    for typed in [".", "", "22,5,", "abc"] {
      exercise.typeWeight(typed, setID: "s0")
      XCTAssertEqual(exercise.sets.map(\.weight).dropFirst(), ["22", "22", "22"], typed)
      XCTAssertEqual(exercise.sets[0].weight, typed)
      XCTAssertEqual(exercise.sharedWeight, "22")
    }
    exercise.typeWeight("22,", setID: "s0")
    XCTAssertEqual(exercise.sets[0].weight, "22,")
    XCTAssertEqual(exercise.sets[1].weight, "22")
    exercise.typeWeight("22,5", setID: "s0")
    XCTAssertEqual(exercise.sets.map(\.weight), ["22,5", "22,5", "22,5", "22,5"])
  }

  func testNewSetTakesTheLastSharedWeightAndNoReps() {
    var exercise = item(sets: 2)
    exercise.typeWeight("60", setID: "s0")
    exercise.typeReps("10", setID: "s0")
    XCTAssertTrue(exercise.addSet(id: "n"))
    XCTAssertEqual(exercise.sets.last?.weight, "60")
    XCTAssertEqual(exercise.sets.last?.reps, "")
    XCTAssertEqual(exercise.sets.last?.done, false)
  }

  func testNewSetBeforeAnythingWasTypedCopiesTheLastSetWeight() {
    var exercise = item(sets: 2, weights: ["50", "52,5"])
    exercise.addSet(id: "n")
    XCTAssertEqual(exercise.sets.last?.weight, "52,5")
  }

  func testOtherExercisesAreUntouched() {
    var first = item()
    let second = item(weights: ["30", "30", "30", "30"])
    first.typeWeight("60", setID: "s0")
    XCTAssertEqual(second.sets.map(\.weight), ["30", "30", "30", "30"])
  }

  // MARK: ticking, adding, removing

  func testTickNeedsWeightAndRepsAndCanBeUndoneAndRedone() {
    var exercise = item(sets: 2)
    XCTAssertEqual(exercise.toggle(setID: "s0"), .needsWeight)
    exercise.typeWeight("60,", setID: "s0")
    XCTAssertEqual(exercise.toggle(setID: "s0"), .needsReps)
    exercise.typeReps("10", setID: "s0")
    XCTAssertEqual(exercise.toggle(setID: "s0"), .done)
    XCTAssertEqual(exercise.sets[0].weight, "60")
    XCTAssertEqual(exercise.toggle(setID: "s0"), .undone)
    exercise.typeWeight("62,5", setID: "s0")
    XCTAssertEqual(exercise.toggle(setID: "s0"), .done)
    XCTAssertEqual(exercise.sets[0].weight, "62,5")
    XCTAssertEqual(exercise.toggle(setID: "nope"), .missing)
  }

  func testAFilledButUntickedSetIsNotDone() {
    let exercise = item(sets: 3, weights: ["50", "50", "50"])
    XCTAssertEqual(exercise.doneCount, 0)
  }

  func testCompletedSetCannotBeRemovedAndTheLastSetStays() {
    var exercise = item(sets: 2)
    exercise.typeWeight("60", setID: "s0")
    exercise.typeReps("10", setID: "s0")
    _ = exercise.toggle(setID: "s0")
    XCTAssertFalse(exercise.removeSet(setID: "s0"))
    XCTAssertTrue(exercise.removeSet(setID: "s1"))
    XCTAssertFalse(exercise.removeSet(setID: "s0"))
    XCTAssertEqual(exercise.sets.count, 1)
  }

  func testSetCountIsCapped() {
    var exercise = item(sets: WorkoutSessionItem.maxSets)
    XCTAssertFalse(exercise.addSet())
  }

  // MARK: delta

  func testDeltaComparesWithTheSameSetLastTime() {
    let done = WorkoutSet(id: "a", weight: "62,5", reps: "9", done: true)
    let delta = WorkoutDelta.make(set: done, previous: WorkoutResultSet(weight: 60, reps: 10))
    XCTAssertEqual(delta, WorkoutDelta(weight: 2.5, reps: -1))
    XCTAssertEqual(
      WorkoutFormat.delta(delta!, comma: true, kg: "кг", reps: "повт.", same: "="),
      "+2,5\u{00A0}кг · −1\u{00A0}повт.")
    XCTAssertEqual(
      WorkoutDelta.make(set: done, previous: WorkoutResultSet(weight: 62.5, reps: 9))?.isZero, true)
    XCTAssertNil(WorkoutDelta.make(set: WorkoutSet(id: "b", weight: "60", reps: "9"), previous: .init(weight: 60, reps: 9)))
    XCTAssertNil(WorkoutDelta.make(set: done, previous: nil))
  }

  func testWeightFormatting() {
    XCTAssertEqual(WorkoutFormat.weight(60), "60")
    XCTAssertEqual(WorkoutFormat.weight(62.5, comma: true), "62,5")
    XCTAssertEqual(WorkoutFormat.weight(62.25), "62.25")
  }
}
