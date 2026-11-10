import XCTest

@testable import RitmCore

final class WorkoutLiveEditTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
  private let bench = WorkoutCatalog.builtinID("bench")
  private let fly = WorkoutCatalog.builtinID("fly")
  private let squat = WorkoutCatalog.builtinID("squat")
  private let row = WorkoutCatalog.builtinID("row")
  private var counter = 0

  private func nextID() -> String {
    counter += 1
    return "id\(counter)"
  }

  private func library() -> WorkoutLibrary {
    var library = WorkoutLibrary()
    library.addProgram(name: "Грудь", id: "p1")
    library.addItem(to: "p1", exerciseID: bench, sets: 3, id: "a")
    library.addItem(to: "p1", exerciseID: fly, sets: 2, id: "b")
    return library
  }

  private func started() -> WorkoutSession {
    let lib = library()
    return WorkoutSession.start(
      program: lib.program("p1")!, library: lib, history: WorkoutHistory(), language: .en, now: t0,
      makeID: nextID)!
  }

  private func tick(_ session: inout WorkoutSession, item index: Int, set: Int = 0) {
    session.update(session.items[index].id) {
      $0.typeWeight("60", setID: $0.sets[set].id)
      $0.typeReps("10", setID: $0.sets[set].id)
      _ = $0.toggle(setID: $0.sets[set].id)
    }
  }

  // MARK: exercises

  func testAddingAnExerciseAtTheEndOrAfterTheCurrentOne() {
    var session = started()
    let last = session.addExercise(squat, name: "Squat", history: WorkoutHistory(), makeID: nextID)
    XCTAssertEqual(session.items.map(\.exerciseID), [bench, fly, squat])
    XCTAssertEqual(session.items[2].id, last)
    XCTAssertEqual(session.items[2].sets.count, 3)
    XCTAssertEqual(session.items[2].plannedReps, 10)
    XCTAssertEqual(session.items[2].restSeconds, WorkoutProgramItem.defaultRest)
    session.addExercise(row, name: "Row", history: WorkoutHistory(), after: 0, makeID: nextID)
    XCTAssertEqual(session.items.map(\.exerciseID), [bench, row, fly, squat])
    XCTAssertNil(session.addExercise(row, name: "Row", history: WorkoutHistory(), makeID: nextID))
    XCTAssertEqual(session.items.count, 4)
  }

  func testAddedExerciseShowsItsLastResult() {
    var session = started()
    let past = WorkoutHistory(records: [
      WorkoutRecord(
        id: "r", programID: "x", programName: "x", startedAt: t0, endedAt: t0,
        exercises: [
          WorkoutRecordExercise(exerciseID: squat, name: "Squat", sets: [WorkoutResultSet(weight: 100, reps: 5)])
        ])
    ])
    session.addExercise(squat, name: "Squat", history: past, makeID: nextID)
    XCTAssertEqual(session.items[2].previous?.sets.first?.weight, 100)
    XCTAssertEqual(session.items[2].sets[0].weight, "100")
  }

  func testRemovingAnExerciseKeepsAtLeastOne() {
    var session = started()
    XCTAssertTrue(session.removeExercise(session.items[0].id))
    XCTAssertEqual(session.items.map(\.exerciseID), [fly])
    XCTAssertFalse(session.removeExercise(session.items[0].id))
    XCTAssertFalse(session.removeExercise("nope"))
    XCTAssertEqual(session.items.count, 1)
  }

  func testRemovingAnExerciseDropsItsDoneSetsFromTheLog() {
    var session = started()
    tick(&session, item: 0)
    XCTAssertTrue(session.hasDoneSets(session.items[0].id))
    session.removeExercise(session.items[0].id)
    XCTAssertNil(session.finished(at: t0.addingTimeInterval(60)))
    XCTAssertEqual(session.doneSets, 0)
  }

  func testReorderingExercises() {
    var session = started()
    session.addExercise(squat, name: "Squat", history: WorkoutHistory(), makeID: nextID)
    session.moveExercise(from: 2, to: 0)
    XCTAssertEqual(session.items.map(\.exerciseID), [squat, bench, fly])
    session.moveExercise(from: 9, to: 0)
    XCTAssertEqual(session.items.map(\.exerciseID), [squat, bench, fly])
  }

  func testReplacingKeepsPositionAndResetsTheSets() {
    var session = started()
    let old = session.items[1]
    let id = session.replaceExercise(old.id, with: squat, name: "Squat", history: WorkoutHistory(), makeID: nextID)
    XCTAssertEqual(session.items.map(\.exerciseID), [bench, squat])
    XCTAssertEqual(session.items[1].id, id)
    XCTAssertEqual(session.items[1].sets.count, old.sets.count)
    XCTAssertEqual(session.items[1].plannedReps, old.plannedReps)
    XCTAssertEqual(session.items[1].restSeconds, old.restSeconds)
    XCTAssertFalse(session.items[1].keptForLog)
  }

  // MARK: sets, reps, rest

  func testSetCountStepsAndNeverGoesBelowDoneSets() {
    var session = started()
    tick(&session, item: 0)
    tick(&session, item: 0, set: 1)
    session.update(session.items[0].id) { item in
      XCTAssertTrue(item.canStep(.sets, direction: -1))
      item.step(.sets, direction: -1)
      XCTAssertEqual(item.sets.count, 2)
      XCTAssertEqual(item.doneCount, 2)
      XCTAssertFalse(item.canStep(.sets, direction: -1), "the done sets stay")
      item.step(.sets, direction: -1)
      XCTAssertEqual(item.sets.count, 2)
      item.step(.sets, direction: 1, makeID: nextID)
      XCTAssertEqual(item.sets.count, 3)
      XCTAssertFalse(item.sets[2].done)
    }
  }

  func testSetCountStopsAtTheMaximum() {
    var item = started().items[0]
    item.setPlannedSets(50, makeID: nextID)
    XCTAssertEqual(item.sets.count, WorkoutSessionItem.maxSets)
    XCTAssertFalse(item.canStep(.sets, direction: 1))
    item.setPlannedSets(0)
    XCTAssertEqual(item.sets.count, 1)
  }

  func testRemovingTheLastOpenSetSkipsDoneOnes() {
    var session = started()
    tick(&session, item: 0, set: 0)
    var item = session.items[0]
    XCTAssertTrue(item.removeLastOpenSet())
    XCTAssertTrue(item.removeLastOpenSet())
    XCTAssertEqual(item.sets.count, 1)
    XCTAssertFalse(item.removeLastOpenSet(), "only the done set is left")
    XCTAssertTrue(item.sets[0].done)
  }

  func testRepsTargetUpdatesOnlySetsThatAreNotDone() {
    var session = started()
    tick(&session, item: 0)
    session.update(session.items[0].id) { item in
      item.step(.reps, direction: 1)
      XCTAssertEqual(item.plannedReps, 11)
      XCTAssertEqual(item.sets[0].reps, "10", "a done set keeps its value")
      XCTAssertEqual(item.sets[1].reps, "11")
      item.setPlannedReps(500)
      XCTAssertEqual(item.plannedReps, 99)
      item.setPlannedReps(0)
      XCTAssertEqual(item.plannedReps, 1)
      XCTAssertFalse(item.canStep(.reps, direction: -1))
    }
  }

  func testRestStepsByFifteenSecondsWithinTheRange() {
    var item = started().items[0]
    item.step(.rest, direction: 1)
    XCTAssertEqual(item.restSeconds, 195)
    item.setRest(10_000)
    XCTAssertEqual(item.restSeconds, 900)
    XCTAssertFalse(item.canStep(.rest, direction: 1))
    item.setRest(1)
    XCTAssertEqual(item.restSeconds, 15)
    XCTAssertFalse(item.canStep(.rest, direction: -1))
  }

  // MARK: difference from the program

  func testAFreshWorkoutMatchesItsProgram() {
    let session = started()
    XCTAssertNil(session.change(from: library().program("p1")!))
  }

  func testChangesAgainstTheProgramAreCounted() {
    let program = library().program("p1")!
    var session = started()
    session.update(session.items[0].id) { $0.step(.rest, direction: 1) }
    XCTAssertEqual(session.change(from: program), WorkoutProgramChange(added: 0, removed: 0, modified: 1, reordered: false))
    session.moveExercise(from: 1, to: 0)
    XCTAssertEqual(session.change(from: program)?.reordered, true)
    session.addExercise(squat, name: "Squat", history: WorkoutHistory(), makeID: nextID)
    XCTAssertEqual(session.change(from: program)?.added, 1)
    session.removeExercise(session.items.first { $0.exerciseID == fly }!.id)
    XCTAssertEqual(session.change(from: program)?.removed, 1)
  }

  func testAddingASetCountsAsAChangeAndUndoingItDoesNot() {
    let program = library().program("p1")!
    var session = started()
    session.update(session.items[0].id) { $0.step(.sets, direction: 1, makeID: nextID) }
    XCTAssertEqual(session.change(from: program)?.modified, 1)
    session.update(session.items[0].id) { $0.step(.sets, direction: -1) }
    XCTAssertNil(session.change(from: program))
  }

  func testSwappingTheOrderBackMatchesAgain() {
    let program = library().program("p1")!
    var session = started()
    session.moveExercise(from: 0, to: 1)
    XCTAssertNotNil(session.change(from: program))
    session.moveExercise(from: 0, to: 1)
    XCTAssertNil(session.change(from: program))
  }

  func testAReplacementWithDoneSetsLeavesTheOldOneOutOfTheProgram() {
    let program = library().program("p1")!
    var session = started()
    tick(&session, item: 0)
    session.replaceExercise(
      session.items[0].id, with: squat, name: "Squat", history: WorkoutHistory(), makeID: nextID)
    XCTAssertEqual(session.items.map(\.exerciseID), [bench, squat, fly])
    XCTAssertEqual(session.programItems.map(\.exerciseID), [squat, fly])
    XCTAssertEqual(session.change(from: program)?.added, 1)
    XCTAssertEqual(session.change(from: program)?.removed, 1)
    XCTAssertEqual(session.finished(at: t0.addingTimeInterval(60))?.exercises.map(\.exerciseID), [bench])
  }

  func testApplyingKeepsNameColourAndIdsOfSurvivingItems() {
    var lib = library()
    lib.programs[0].colorIndex = 3
    var session = started()
    session.update(session.items[1].id) { $0.step(.reps, direction: -1) }
    session.addExercise(squat, name: "Squat", history: WorkoutHistory(), makeID: nextID)
    session.moveExercise(from: 2, to: 0)
    XCTAssertTrue(lib.saveChanges(of: session))
    let saved = lib.program("p1")!
    XCTAssertEqual(saved.name, "Грудь")
    XCTAssertEqual(saved.colorIndex, 3)
    XCTAssertEqual(saved.items.map(\.exerciseID), [squat, bench, fly])
    XCTAssertEqual(saved.items[1].id, "a")
    XCTAssertEqual(saved.items[2].id, "b")
    XCTAssertEqual(saved.items[2].reps, 9)
    XCTAssertEqual(saved.items[0].sets, 3)
    XCTAssertNil(session.change(from: saved), "the program now matches the workout")
    XCTAssertFalse(lib.saveChanges(of: session), "nothing left to save")
  }

  func testSavingForAnUnknownProgramDoesNothing() {
    var lib = WorkoutLibrary()
    XCTAssertFalse(lib.saveChanges(of: started()))
    XCTAssertTrue(lib.programs.isEmpty)
  }

  func testEditedSessionSurvivesEncodingAndOldFilesStillLoad() throws {
    var session = started()
    session.update(session.items[0].id) {
      $0.step(.reps, direction: 2)
      $0.step(.rest, direction: -1)
    }
    session.addExercise(squat, name: "Squat", history: WorkoutHistory(), makeID: nextID)
    let data = try WorkoutCoding.encoder().encode(WorkoutActiveState(session: session))
    let loaded = try WorkoutCoding.decoder().decode(WorkoutActiveState.self, from: data)
    XCTAssertEqual(loaded.session, session)

    let old = #"{"id":"i","exerciseID":"builtin.bench","name":"B","restSeconds":120,"sets":[{"id":"s","reps":"8"}]}"#
    let item = try WorkoutCoding.decoder().decode(WorkoutSessionItem.self, from: Data(old.utf8))
    XCTAssertEqual(item.plannedReps, 8)
    XCTAssertFalse(item.keptForLog)
  }

  // MARK: best sets and records

  private func record(_ id: String, at date: Date, sets: [(Double, Int)], exercise: String? = nil) -> WorkoutRecord {
    WorkoutRecord(
      id: id, programID: "p1", programName: "Up 2", startedAt: date.addingTimeInterval(-2_700), endedAt: date,
      exercises: [
        WorkoutRecordExercise(
          exerciseID: exercise ?? bench, name: "Bench",
          sets: sets.map { WorkoutResultSet(weight: $0.0, reps: $0.1) })
      ])
  }

  func testBestSetIsTheHeaviestThenTheMostRepsAndTheFirstOnATie() {
    let sets = [(60.0, 10), (70, 5), (70, 8), (70, 8), (65, 12)].map { WorkoutResultSet(weight: $0.0, reps: $0.1) }
    XCTAssertEqual(WorkoutRecords.bestSetIndex(sets), 2)
    XCTAssertNil(WorkoutRecords.bestSetIndex([]))
    let bodyweight = [(0.0, 8), (0, 12), (0, 10)].map { WorkoutResultSet(weight: $0.0, reps: $0.1) }
    XCTAssertEqual(WorkoutRecords.bestSetIndex(bodyweight), 1)
  }

  func testVolumeAndSetCountOfARecord() {
    let finished = record("r", at: t0, sets: [(60, 10), (62.5, 8)])
    XCTAssertEqual(finished.exercises[0].volume, 1_100)
    XCTAssertEqual(finished.setCount, 2)
  }

  func testRecordSetIsTheBestSetWhenHeavierThanAllEarlierWorkouts() {
    let old = record("old", at: t0, sets: [(80, 5)])
    let now = record("now", at: t0.addingTimeInterval(86_400), sets: [(70, 8), (85, 3), (82.5, 5)])
    let history = WorkoutHistory(records: [now, old])
    XCTAssertEqual(WorkoutRecords.recordSets(in: now, history: history), [bench: 1])
    XCTAssertTrue(WorkoutRecords.recordSets(in: old, history: history).isEmpty, "a first lift has nothing to beat")
  }

  func testNoRecordWhenNotHeavierOrWhenALaterWorkoutIsHeavier() {
    let first = record("1", at: t0, sets: [(90, 3)])
    let tie = record("2", at: t0.addingTimeInterval(1_000), sets: [(90, 5)])
    let later = record("3", at: t0.addingTimeInterval(2_000), sets: [(100, 1)])
    let history = WorkoutHistory(records: [later, tie, first])
    XCTAssertTrue(WorkoutRecords.recordSets(in: tie, history: history).isEmpty, "equal weight is not a record")
    XCTAssertEqual(WorkoutRecords.recordSets(in: later, history: history), [bench: 0])
    XCTAssertTrue(WorkoutRecords.recordSets(in: first, history: history).isEmpty)
  }

  func testRecordsAreJudgedPerExercise() {
    let other = record("o", at: t0, sets: [(200, 1)], exercise: squat)
    let now = record("n", at: t0.addingTimeInterval(500), sets: [(60, 5)])
    let history = WorkoutHistory(records: [now, other])
    XCTAssertTrue(WorkoutRecords.recordSets(in: now, history: history).isEmpty)
  }

  func testBodyweightSetsAreNeverRecords() {
    let a = record("a", at: t0, sets: [(0, 10)])
    let b = record("b", at: t0.addingTimeInterval(500), sets: [(0, 15)])
    XCTAssertTrue(WorkoutRecords.recordSets(in: b, history: WorkoutHistory(records: [b, a])).isEmpty)
  }
}
