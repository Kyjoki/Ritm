import XCTest

@testable import RitmCore

final class WorkoutPlanTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
  private var counter = 0
  private func nextID() -> String {
    counter += 1
    return "id\(counter)"
  }

  private func library() -> WorkoutLibrary {
    var library = WorkoutLibrary()
    library.addProgram(name: "Грудь", id: "p1")
    library.addProgram(name: "Спина", id: "p2")
    library.addProgram(name: "Ноги", id: "p3")
    library.addItem(to: "p1", exerciseID: WorkoutCatalog.builtinID("bench"), sets: 3, id: "a")
    library.addItem(to: "p1", exerciseID: WorkoutCatalog.builtinID("fly"), sets: 2, id: "b")
    library.addItem(to: "p2", exerciseID: WorkoutCatalog.builtinID("bench"), sets: 3, id: "c")
    return library
  }

  private func record(
    _ id: String, program: String, at date: Date, exercise: String, sets: [(Double, Int)]
  ) -> WorkoutRecord {
    WorkoutRecord(
      id: id, programID: program, programName: program, startedAt: date.addingTimeInterval(-3_000),
      endedAt: date,
      exercises: [
        WorkoutRecordExercise(
          exerciseID: exercise, name: "x", sets: sets.map { WorkoutResultSet(weight: $0.0, reps: $0.1) })
      ])
  }

  // MARK: programs

  func testReorderingProgramsAndExercises() {
    var lib = library()
    lib.moveProgram(from: 2, to: 0)
    XCTAssertEqual(lib.programs.map(\.id), ["p3", "p1", "p2"])
    lib.moveItem(in: "p1", from: 0, to: 1)
    XCTAssertEqual(lib.program("p1")?.items.map(\.id), ["b", "a"])
    lib.moveItem(in: "p1", from: 5, to: 0)
    XCTAssertEqual(lib.program("p1")?.items.map(\.id), ["b", "a"])
  }

  func testDuplicateIsIndependentAndRightAfterTheOriginal() {
    var lib = library()
    let copy = lib.duplicateProgram("p1", suffix: " (копия)", makeID: nextID)
    XCTAssertEqual(lib.programs.map(\.id), ["p1", copy, "p2", "p3"].compactMap { $0 })
    lib.setPlannedSets(9, item: "a", in: "p1")
    XCTAssertEqual(lib.program(copy ?? "")?.items.first?.sets, 3)
    XCTAssertEqual(lib.program(copy ?? "")?.name, "Грудь (копия)")
    XCTAssertNotEqual(lib.program(copy ?? "")?.items.first?.id, "a")
  }

  func testExercisesAreUniquePerProgramAndSetsAreClamped() {
    var lib = library()
    XCTAssertFalse(lib.addItem(to: "p1", exerciseID: WorkoutCatalog.builtinID("bench")))
    lib.setPlannedSets(99, item: "a", in: "p1")
    XCTAssertEqual(lib.program("p1")?.items.first?.sets, 10)
    lib.setPlannedSets(0, item: "a", in: "p1")
    XCTAssertEqual(lib.program("p1")?.items.first?.sets, 1)
  }

  func testReplaceKeepsPlaceAndSetsAndRemoveDeletes() {
    var lib = library()
    XCTAssertTrue(lib.replaceItem("a", in: "p1", with: WorkoutCatalog.builtinID("squat")))
    XCTAssertEqual(lib.program("p1")?.items.first?.exerciseID, "builtin.squat")
    XCTAssertEqual(lib.program("p1")?.items.first?.sets, 3)
    XCTAssertFalse(lib.replaceItem("a", in: "p1", with: WorkoutCatalog.builtinID("fly")))
    lib.removeItem("b", from: "p1")
    XCTAssertEqual(lib.program("p1")?.items.count, 1)
    lib.deleteProgram("p1")
    XCTAssertNil(lib.program("p1"))
  }

  func testCustomExerciseIsCreatedOnceAndValidated() {
    var lib = library()
    XCTAssertNil(lib.createExercise(named: " a "))
    let made = lib.createExercise(named: "  Тяга   гантели ", id: "z")
    XCTAssertEqual(made?.name, "Тяга гантели")
    XCTAssertEqual(made?.id, "custom.z")
    XCTAssertEqual(lib.createExercise(named: "тяга гантели")?.id, "custom.z")
    XCTAssertEqual(lib.createExercise(named: "bench press")?.id, WorkoutCatalog.builtinID("bench"))
    XCTAssertEqual(lib.customExercises.count, 1)
    XCTAssertEqual(lib.exerciseName("custom.z", language: .en), "Тяга гантели")
  }

  // MARK: last time

  func testLastResultIsPerExerciseIdFromTheNewestCompletedWorkout() {
    let history = WorkoutHistory(records: [
      record("r1", program: "p1", at: t0, exercise: "builtin.bench", sets: [(60, 10)]),
      record("r2", program: "p2", at: t0.addingTimeInterval(86_400), exercise: "builtin.bench", sets: [(65, 8), (65, 7)]),
      record("r3", program: "p2", at: t0.addingTimeInterval(172_800), exercise: "builtin.fly", sets: [(14, 12)]),
    ])
    let last = history.lastResult(exerciseID: "builtin.bench")
    XCTAssertEqual(last?.date, t0.addingTimeInterval(86_400))
    XCTAssertEqual(last?.sets, [WorkoutResultSet(weight: 65, reps: 8), WorkoutResultSet(weight: 65, reps: 7)])
    XCTAssertNil(history.lastResult(exerciseID: "builtin.squat"))
  }

  // MARK: session

  func testStartIsASnapshotAndPrefillIsNeverDone() {
    var lib = library()
    let history = WorkoutHistory(records: [
      record("r1", program: "p2", at: t0, exercise: "builtin.bench", sets: [(60, 10), (62.5, 8)])
    ])
    let session = WorkoutSession.start(
      program: lib.program("p1")!, library: lib, history: history, language: .ru, now: t0, makeID: nextID)
    XCTAssertEqual(session?.items.count, 2)
    let bench = session?.items[0]
    XCTAssertEqual(bench?.name, "Жим лёжа")
    XCTAssertEqual(bench?.sets.map(\.weight), ["60", "62.5", "62.5"])
    XCTAssertEqual(bench?.sets.map(\.reps), ["10", "8", "8"])
    XCTAssertTrue(bench?.sets.allSatisfy { !$0.done } ?? false)
    XCTAssertNotNil(bench?.previous)
    XCTAssertNil(session?.items[1].previous)
    lib.removeItem("a", from: "p1")
    lib.moveItem(in: "p1", from: 0, to: 0)
    XCTAssertEqual(session?.items.count, 2, "editing the program never changes a started workout")
    XCTAssertNil(
      WorkoutSession.start(
        program: WorkoutProgram(id: "x", name: "", items: []), library: lib, history: history,
        language: .ru, now: t0))
  }

  private func startedSession() -> WorkoutSession {
    let lib = library()
    var session = WorkoutSession.start(
      program: lib.program("p1")!, library: lib, history: WorkoutHistory(), language: .en, now: t0,
      makeID: nextID)!
    session.update(session.items[0].id) {
      $0.typeWeight("60", setID: $0.sets[0].id)
      $0.typeReps("10", setID: $0.sets[0].id)
      _ = $0.toggle(setID: $0.sets[0].id)
    }
    return session
  }

  func testReplacingAnExerciseKeepsDoneSetsUnderTheOldOne() {
    var session = startedSession()
    let oldID = session.items[0].id
    let history = WorkoutHistory(records: [
      record("r1", program: "p9", at: t0, exercise: "builtin.squat", sets: [(100, 5)])
    ])
    session.replaceExercise(oldID, with: "builtin.squat", name: "Squat", history: history, makeID: nextID)
    XCTAssertEqual(session.items.count, 3)
    XCTAssertEqual(session.items[0].exerciseID, "builtin.bench")
    XCTAssertEqual(session.items[0].sets.count, 1)
    XCTAssertTrue(session.items[0].sets[0].done)
    XCTAssertEqual(session.items[1].exerciseID, "builtin.squat")
    XCTAssertEqual(session.items[1].sets.count, 2)
    XCTAssertEqual(session.items[1].previous?.sets.first?.weight, 100)
    XCTAssertTrue(session.items[1].sets.allSatisfy { !$0.done })
  }

  func testReplacingWithNothingDoneSwapsInPlaceAndRefusesDuplicates() {
    let lib = library()
    var session = WorkoutSession.start(
      program: lib.program("p1")!, library: lib, history: WorkoutHistory(), language: .en, now: t0,
      makeID: nextID)!
    let id = session.items[0].id
    session.replaceExercise(id, with: "builtin.fly", name: "Fly", history: WorkoutHistory(), makeID: nextID)
    XCTAssertEqual(session.items.count, 2, "fly is already in the workout")
    session.replaceExercise(id, with: "builtin.squat", name: "Squat", history: WorkoutHistory(), makeID: nextID)
    XCTAssertEqual(session.items.map(\.exerciseID), ["builtin.squat", "builtin.fly"])
    XCTAssertEqual(session.items[0].sets.count, 3)
  }

  func testFinishStoresOnlyDoneSetsAndTheRealDuration() {
    let session = startedSession()
    let end = t0.addingTimeInterval(3_725)
    let record = session.finished(at: end)
    XCTAssertEqual(record?.exercises.count, 1)
    XCTAssertEqual(record?.exercises[0].sets, [WorkoutResultSet(weight: 60, reps: 10)])
    XCTAssertEqual(record?.duration, 3_725)
    XCTAssertEqual(record?.volume, 600)
    let lib = library()
    let empty = WorkoutSession.start(
      program: lib.program("p1")!, library: lib, history: WorkoutHistory(), language: .en, now: t0)!
    XCTAssertNil(empty.finished(at: end))
  }

  // MARK: persistence

  func testActiveStateRoundTripsAndToleratesDamage() throws {
    var state = WorkoutActiveState(session: startedSession(), rest: RestTimer(preset: 120))
    state.rest.start(now: t0)
    let data = try WorkoutCoding.encoder().encode(state)
    let back = try WorkoutCoding.decoder().decode(WorkoutActiveState.self, from: data)
    XCTAssertEqual(back, state)

    let damaged = Data(
      #"{"version":99,"programs":[{"id":"p","name":"A","items":[{"exerciseID":"e","sets":"x"},5,{"id":"q"}]},"junk",{"name":"no id"}],"extra":1}"#.utf8)
    let lib = try WorkoutCoding.decoder().decode(WorkoutLibrary.self, from: damaged)
    XCTAssertEqual(lib.programs.count, 1)
    XCTAssertEqual(lib.programs[0].items.count, 1)
    XCTAssertEqual(lib.programs[0].items[0].sets, 3)

    let empty = try WorkoutCoding.decoder().decode(WorkoutHistory.self, from: Data("{}".utf8))
    XCTAssertTrue(empty.records.isEmpty)
    let noSession = try WorkoutCoding.decoder().decode(WorkoutActiveState.self, from: Data("{}".utf8))
    XCTAssertNil(noSession.session)
  }
}
