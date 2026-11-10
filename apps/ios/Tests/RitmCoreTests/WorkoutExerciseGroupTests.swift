import XCTest

@testable import RitmCore

final class WorkoutExerciseGroupTests: XCTestCase {
  private func library() -> WorkoutLibrary {
    var library = WorkoutLibrary(
      customExercises: [
        WorkoutExercise(id: "custom.a", name: "Махи"),
        WorkoutExercise(id: "custom.b", name: "Тяга широкая", muscle: .back),
      ])
    library.addProgram(name: "День", id: "p1")
    library.addItem(to: "p1", exerciseID: "custom.a", sets: 3, id: "i1")
    return library
  }

  func testOldCustomExerciseWithoutGroupDecodes() throws {
    let data = Data(#"{"id":"custom.x","name":"Старое"}"#.utf8)
    let exercise = try WorkoutCoding.decoder().decode(WorkoutExercise.self, from: data)
    XCTAssertEqual(exercise.name, "Старое")
    XCTAssertNil(exercise.muscle)
    let unknown = Data(#"{"id":"custom.y","name":"Новое","muscle":"wings"}"#.utf8)
    XCTAssertNil(try WorkoutCoding.decoder().decode(WorkoutExercise.self, from: unknown).muscle)
  }

  func testAssigningAndClearingTheGroupOfACustomExercise() {
    var lib = library()
    XCTAssertTrue(lib.setMuscle(.shoulders, ofExercise: "custom.a"))
    XCTAssertEqual(lib.muscle(of: "custom.a"), .shoulders)
    XCTAssertEqual(lib.customExercises.count, 2)
    XCTAssertEqual(lib.program("p1")?.items.first?.exerciseID, "custom.a")
    XCTAssertTrue(lib.setMuscle(nil, ofExercise: "custom.a"))
    XCTAssertNil(lib.muscle(of: "custom.a"))
  }

  func testBuiltInExerciseGroupIsReadOnlyAndUnknownIDIsIgnored() {
    var lib = library()
    XCTAssertFalse(lib.setMuscle(.legs, ofExercise: WorkoutCatalog.builtinID("bench")))
    XCTAssertEqual(lib.muscle(of: WorkoutCatalog.builtinID("bench")), .chest)
    XCTAssertFalse(lib.setMuscle(.legs, ofExercise: "custom.none"))
  }

  func testNewExerciseKeepsItsChosenGroup() {
    var lib = library()
    let made = lib.createExercise(named: "Пуловер", muscle: .chest, id: "n")
    XCTAssertEqual(made?.muscle, .chest)
    let found = WorkoutCatalog.search(
      "пул", filter: .group(.chest), custom: lib.customExercises, language: .ru)
    XCTAssertEqual(found.map(\.id), ["custom.n"])
  }

  func testNoGroupFilterFindsOnlyUngroupedExercises() {
    var lib = library()
    let none = WorkoutCatalog.search("", filter: .none, custom: lib.customExercises, language: .ru)
    XCTAssertEqual(none.map(\.id), ["custom.a"])
    XCTAssertTrue(WorkoutCatalog.hasUngrouped(custom: lib.customExercises))
    let back = WorkoutCatalog.search("", filter: .group(.back), custom: lib.customExercises, language: .ru)
    XCTAssertTrue(back.contains { $0.id == "custom.b" })
    XCTAssertFalse(back.contains { $0.id == "custom.a" })
    let all = WorkoutCatalog.search("", filter: .any, custom: lib.customExercises, language: .ru)
    XCTAssertEqual(all.count, WorkoutCatalog.builtin(language: .ru).count + 2)
    lib.setMuscle(.shoulders, ofExercise: "custom.a")
    XCTAssertFalse(WorkoutCatalog.hasUngrouped(custom: lib.customExercises))
    XCTAssertTrue(
      WorkoutCatalog.search("", filter: .none, custom: lib.customExercises, language: .ru).isEmpty)
    XCTAssertEqual(
      WorkoutCatalog.search("махи", filter: .group(.shoulders), custom: lib.customExercises, language: .ru)
        .map(\.id), ["builtin.lateral", "custom.a"])
  }

  func testGroupTravelsInTheProgramDocAndAClearedGroupIsSynced() throws {
    var lib = library()
    lib.setMuscle(.shoulders, ofExercise: "custom.a")
    let docs = WorkoutSyncCodec.documents(library: lib, history: WorkoutHistory())
    let doc = try XCTUnwrap(docs[.programs]?["p1"])
    let carried = try XCTUnwrap(doc.objectValue?["exercises"]?.decoded([WorkoutExercise].self))
    XCTAssertEqual(carried.first?.muscle, .shoulders)

    // Another device that knew the exercise without a group takes the new one.
    var other = library()
    other.programs = []
    var applied = WorkoutSyncCodec.apply(
      [.programs: ["p1": .some(doc)]], library: other, history: WorkoutHistory())
    XCTAssertEqual(applied.library.muscle(of: "custom.a"), .shoulders)

    // Clearing the group is written as null and clears it there too.
    lib.setMuscle(nil, ofExercise: "custom.a")
    let cleared = try XCTUnwrap(
      WorkoutSyncCodec.documents(library: lib, history: WorkoutHistory())[.programs]?["p1"])
    applied = WorkoutSyncCodec.apply(
      [.programs: ["p1": .some(cleared)]], library: applied.library, history: WorkoutHistory())
    XCTAssertNil(applied.library.muscle(of: "custom.a"))
  }

  func testProgramDocFromAnOlderBuildKeepsTheLocalGroup() throws {
    var lib = library()
    lib.setMuscle(.shoulders, ofExercise: "custom.a")
    var doc = try XCTUnwrap(
      WorkoutSyncCodec.documents(library: lib, history: WorkoutHistory())[.programs]?["p1"]
        .flatMap { $0.objectValue })
    doc["exercises"] = .array([.object(["id": .string("custom.a"), "name": .string("Махи")])])
    let applied = WorkoutSyncCodec.apply(
      [.programs: ["p1": .some(.object(doc))]], library: lib, history: WorkoutHistory())
    XCTAssertEqual(applied.library.muscle(of: "custom.a"), .shoulders)
  }
}
