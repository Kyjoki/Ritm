import Foundation
import XCTest

@testable import RitmCore

// Records, the weekly ring, the habit link, the program draft and the sync of records/settings.

private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func workout(
  _ id: String, _ end: String, _ sets: [(String, String, Double, Int)]
) -> WorkoutRecord {
  var byExercise: [(String, String, [WorkoutResultSet])] = []
  for (exerciseID, name, weight, reps) in sets {
    if let index = byExercise.firstIndex(where: { $0.0 == exerciseID }) {
      byExercise[index].2.append(WorkoutResultSet(weight: weight, reps: reps))
    } else {
      byExercise.append((exerciseID, name, [WorkoutResultSet(weight: weight, reps: reps)]))
    }
  }
  return WorkoutRecord(
    id: id, programID: "p", programName: "P", startedAt: at(end).addingTimeInterval(-3000),
    endedAt: at(end),
    exercises: byExercise.map { WorkoutRecordExercise(exerciseID: $0.0, name: $0.1, sets: $0.2) })
}

private let bench = "builtin.bench"
private let squat = "builtin.squat"

final class WorkoutRecordsTests: XCTestCase {
  func testRecordIsTheHeaviestSetOfEachExercise() {
    let history = WorkoutHistory(records: [
      workout("b", "2026-11-03T10:00:00Z", [(bench, "Жим", 80, 5), (bench, "Жим", 70, 10)]),
      workout("a", "2026-10-30T10:00:00Z", [(bench, "Жим", 75, 8), (squat, "Присед", 100, 5)]),
    ])
    let cards = WorkoutRecords.resolve(history: history, bests: WorkoutBests())
    XCTAssertEqual(cards.map(\.exerciseID), [bench, squat])  // newest record first
    XCTAssertEqual(cards[0].weight, 80)
    XCTAssertEqual(cards[0].reps, 5)
    XCTAssertEqual(cards[1].weight, 100)
  }

  func testEqualLiftKeepsTheFirstDayAndMoreRepsWin() {
    let history = WorkoutHistory(records: [
      workout("late", "2026-11-03T10:00:00Z", [(bench, "Жим", 80, 5)]),
      workout("early", "2026-10-01T10:00:00Z", [(bench, "Жим", 80, 5)]),
    ])
    XCTAssertEqual(WorkoutRecords.derived(from: history)[bench]?.date, at("2026-10-01T10:00:00Z"))
    let more = WorkoutHistory(records: [
      workout("x", "2026-11-03T10:00:00Z", [(bench, "Жим", 80, 6)]),
      workout("y", "2026-10-01T10:00:00Z", [(bench, "Жим", 80, 5)]),
    ])
    XCTAssertEqual(WorkoutRecords.derived(from: more)[bench]?.reps, 6)
  }

  func testBodyweightSetsAreNotRecords() {
    let history = WorkoutHistory(records: [workout("a", "2026-11-03T10:00:00Z", [("builtin.pullup", "Подтягивания", 0, 12)])])
    XCTAssertTrue(WorkoutRecords.resolve(history: history, bests: WorkoutBests()).isEmpty)
  }

  func testManualEditOverridesHistoryEvenWhenLower() {
    let history = WorkoutHistory(records: [workout("a", "2026-11-03T10:00:00Z", [(bench, "Жим", 80, 5)])])
    var bests = WorkoutBests()
    bests.upsert(WorkoutBest(exerciseID: bench, name: "Жим", weight: 75, reps: 3, date: at("2026-11-04T08:00:00Z")))
    let cards = WorkoutRecords.resolve(history: history, bests: bests)
    XCTAssertEqual(cards.count, 1)
    XCTAssertEqual(cards[0].weight, 75)
    XCTAssertEqual(cards[0].reps, 3)
    XCTAssertTrue(cards[0].isStored)
  }

  func testManualRecordForAnExerciseWithoutHistoryIsShown() {
    var bests = WorkoutBests()
    bests.upsert(WorkoutBest(exerciseID: squat, name: "Присед", weight: 110, reps: 3, date: at("2026-10-30T08:00:00Z")))
    XCTAssertEqual(WorkoutRecords.resolve(history: WorkoutHistory(), bests: bests).map(\.weight), [110])
  }

  func testDeletionHidesTheDerivedRecord() {
    let history = WorkoutHistory(records: [workout("a", "2026-11-03T10:00:00Z", [(bench, "Жим", 80, 5)])])
    var bests = WorkoutBests()
    bests.remove(exerciseID: bench, name: "Жим", now: at("2026-11-04T08:00:00Z"))
    XCTAssertTrue(WorkoutRecords.resolve(history: history, bests: bests).isEmpty)
  }

  func testFinishedWorkoutThatBeatsTheRecordStoresItAndReportsIt() {
    let old = workout("a", "2026-11-01T10:00:00Z", [(bench, "Жим", 80, 5)])
    let before = WorkoutRecords.resolve(history: WorkoutHistory(records: [old]), bests: WorkoutBests())
    let finished = workout("b", "2026-11-04T10:00:00Z", [(bench, "Жим", 82.5, 4), (bench, "Жим", 60, 12)])
    let result = WorkoutRecords.updates(finished: finished, before: before, bests: WorkoutBests())
    XCTAssertEqual(result.beats.map(\.weight), [82.5])
    XCTAssertEqual(result.beats.first?.previousWeight, 80)
    XCTAssertEqual(result.bests.item(for: bench)?.weight, 82.5)
    XCTAssertEqual(result.bests.item(for: bench)?.date, at("2026-11-04T10:00:00Z"))
    // With the workout in the history the card now shows the new record.
    let after = WorkoutRecords.resolve(
      history: WorkoutHistory(records: [finished, old]), bests: result.bests)
    XCTAssertEqual(after.first?.weight, 82.5)
  }

  func testNoBeatWhenNotHeavierOrWhenThereWasNoRecord() {
    let old = workout("a", "2026-11-01T10:00:00Z", [(bench, "Жим", 80, 5)])
    let before = WorkoutRecords.resolve(history: WorkoutHistory(records: [old]), bests: WorkoutBests())
    let same = workout("b", "2026-11-04T10:00:00Z", [(bench, "Жим", 80, 8), (squat, "Присед", 100, 5)])
    let result = WorkoutRecords.updates(finished: same, before: before, bests: WorkoutBests())
    XCTAssertTrue(result.beats.isEmpty)
    XCTAssertTrue(result.bests.items.isEmpty)
  }

  func testDeletedRecordComesBackQuietlyAfterANewLift() {
    var bests = WorkoutBests()
    bests.remove(exerciseID: bench, name: "Жим", now: at("2026-11-02T08:00:00Z"))
    let finished = workout("b", "2026-11-04T10:00:00Z", [(bench, "Жим", 50, 8)])
    let result = WorkoutRecords.updates(finished: finished, before: [], bests: bests)
    XCTAssertTrue(result.beats.isEmpty)
    XCTAssertEqual(result.bests.item(for: bench)?.deleted, false)
    XCTAssertEqual(result.bests.item(for: bench)?.weight, 50)
  }

  func testRecordDocIDsAreValidForTheServer() {
    XCTAssertEqual(WorkoutRecords.docID("builtin.bench"), "rec-builtin-bench")
    let custom = "custom." + WorkoutID.make()
    XCTAssertTrue(WorkoutSyncRules.isValidID(WorkoutRecords.docID(custom)))
  }
}

final class WorkoutWeekTests: XCTestCase {
  // 2026-11-04 is a Wednesday; the week is 2 … 8 November.
  private let today = "2026-11-04"

  private func habit(
    weekdays: [Int]? = nil, done: [String] = [], target: Int? = nil, archived: Bool = false
  ) -> Habit {
    Habit(
      id: "gym", title: "Gym", weekdays: weekdays, target: target, archived: archived,
      startDate: "2026-09-01", completedDates: done)
  }

  func testRingUsesTheHabitsWeeklyTargetAndDoneDays() {
    let week = WorkoutStats.week(
      habit: habit(weekdays: [1, 2, 3, 4, 5], done: ["2026-11-02", "2026-11-04"]),
      history: WorkoutHistory(), today: today, timeZone: "UTC")
    XCTAssertEqual(week.goal, 5)
    XCTAssertEqual(week.done, 2)
    XCTAssertEqual(week.habitTitle, "Gym")
    XCTAssertEqual(week.days.map(\.isDone), [true, false, true, false, false, false, false])
    XCTAssertEqual(week.days.first(where: \.isToday)?.index, 2)
    XCTAssertEqual(week.days.first?.key, "2026-11-02")
    XCTAssertEqual(week.progress, 0.4, accuracy: 0.001)
  }

  func testHabitPlannedThreeDaysAWeekHasAGoalOfThree() {
    // Mon, Wed, Fri; created on Tuesday, so a count of this week's scheduled days would say 2.
    var gym = habit(weekdays: [1, 3, 5], done: ["2026-11-02", "2026-11-04"])
    gym.startDate = "2026-11-03"
    let week = WorkoutStats.week(habit: gym, history: WorkoutHistory(), today: today, timeZone: "UTC")
    XCTAssertEqual(week.goal, 3)
    XCTAssertEqual(WorkoutStats.weeklyGoal(habit(weekdays: [1, 3, 5])), 3)
    XCTAssertEqual(WorkoutStats.pendingWeek(today: today).goal, 0)
  }

  func testEverydayHabitHasAGoalOfSevenAndIgnoresOtherWeeks() {
    let week = WorkoutStats.week(
      habit: habit(done: ["2026-11-01", "2026-11-03", "2026-11-09"]), history: WorkoutHistory(),
      today: today, timeZone: "UTC")
    XCTAssertEqual(week.goal, 7)
    XCTAssertEqual(week.done, 1)  // only the 3rd lies in this week
  }

  func testWithoutAHabitTheRingCountsWorkoutDaysOutOfFour() {
    let history = WorkoutHistory(records: [
      workout("a", "2026-11-03T10:00:00Z", [(bench, "Жим", 80, 5)]),
      workout("b", "2026-11-03T18:00:00Z", [(squat, "Присед", 100, 5)]),  // same day
      workout("c", "2026-11-04T07:00:00Z", [(bench, "Жим", 80, 5)]),
      workout("old", "2026-10-30T07:00:00Z", [(bench, "Жим", 80, 5)]),
    ])
    let week = WorkoutStats.week(habit: nil, history: history, today: today, timeZone: "UTC")
    XCTAssertEqual(week.goal, 4)
    XCTAssertEqual(week.done, 2)
    XCTAssertNil(week.habitTitle)
    XCTAssertEqual(week.days.map(\.isDone), [false, true, true, false, false, false, false])
  }

  func testVolumeTrendAgainstLastWeek() {
    let history = WorkoutHistory(records: [
      workout("now", "2026-11-03T10:00:00Z", [(bench, "Жим", 100, 10)]),  // 1000
      workout("last", "2026-10-28T10:00:00Z", [(bench, "Жим", 100, 8)]),  // 800 (week of 26 Oct)
    ])
    let trend = WorkoutStats.volumeTrend(history, today: today, timeZone: "UTC")
    XCTAssertEqual(trend.volume, 1000)
    XCTAssertEqual(trend.percent, 25)
    let none = WorkoutStats.volumeTrend(
      WorkoutHistory(records: [history.records[0]]), today: today, timeZone: "UTC")
    XCTAssertNil(none.percent)
  }

  func testStreakCountsWeeksInARowAndSurvivesAnEmptyCurrentWeek() {
    let history = WorkoutHistory(records: [
      workout("w0", "2026-10-28T10:00:00Z", [(bench, "Жим", 80, 5)]),  // 26 Oct week
      workout("w1", "2026-10-21T10:00:00Z", [(bench, "Жим", 80, 5)]),  // 19 Oct week
      workout("w3", "2026-10-07T10:00:00Z", [(bench, "Жим", 80, 5)]),  // gap before it
    ])
    XCTAssertEqual(WorkoutStats.streakWeeks(history, today: today, timeZone: "UTC"), 2)
    let withCurrent = WorkoutHistory(
      records: [workout("c", "2026-11-03T10:00:00Z", [(bench, "Жим", 80, 5)])] + history.records)
    XCTAssertEqual(WorkoutStats.streakWeeks(withCurrent, today: today, timeZone: "UTC"), 3)
    XCTAssertEqual(WorkoutStats.streakWeeks(WorkoutHistory(), today: today, timeZone: "UTC"), 0)
  }
}

final class WorkoutHabitLinkTests: XCTestCase {
  private let today = "2026-11-04"
  private func habit(done: [String] = [], target: Int? = nil, progress: [String: Int]? = nil) -> Habit {
    Habit(
      id: "gym", title: "Gym", target: target, startDate: "2026-09-01", completedDates: done,
      progressByDate: progress)
  }

  func testTicksOnceForTheLinkedHabitOnAFreshDay() {
    let settings = WorkoutSettings(linkedHabitID: "gym")
    XCTAssertTrue(WorkoutHabitLink.shouldTick(habit: habit(), settings: settings, today: today))
  }

  func testDoesNotTickTwiceInADay() {
    let settings = WorkoutSettings(linkedHabitID: "gym", lastTickedDay: today)
    XCTAssertFalse(WorkoutHabitLink.shouldTick(habit: habit(), settings: settings, today: today))
    let yesterday = WorkoutSettings(linkedHabitID: "gym", lastTickedDay: "2026-11-03")
    XCTAssertTrue(WorkoutHabitLink.shouldTick(habit: habit(), settings: yesterday, today: today))
  }

  func testDoesNotTickAnAlreadyCompleteOrMissingOrUnlinkedHabit() {
    let settings = WorkoutSettings(linkedHabitID: "gym")
    XCTAssertFalse(WorkoutHabitLink.shouldTick(habit: habit(done: [today]), settings: settings, today: today))
    XCTAssertFalse(WorkoutHabitLink.shouldTick(habit: nil, settings: settings, today: today))
    XCTAssertFalse(WorkoutHabitLink.shouldTick(habit: habit(), settings: WorkoutSettings(), today: today))
    XCTAssertFalse(
      WorkoutHabitLink.shouldTick(
        habit: habit(), settings: WorkoutSettings(linkedHabitID: "other"), today: today))
  }

  func testCountedHabitStillBelowItsTargetIsTicked() {
    let settings = WorkoutSettings(linkedHabitID: "gym")
    XCTAssertTrue(
      WorkoutHabitLink.shouldTick(
        habit: habit(target: 2, progress: [today: 1]), settings: settings, today: today))
    XCTAssertFalse(
      WorkoutHabitLink.shouldTick(
        habit: habit(target: 2, progress: [today: 2]), settings: settings, today: today))
  }
}

final class WorkoutDraftTests: XCTestCase {
  func testNewExerciseGetsThreeSetsOfTenAndRestOfThreeMinutes() {
    var draft = WorkoutProgramDraft(name: "Грудь")
    XCTAssertFalse(draft.canSave)
    XCTAssertTrue(draft.add(exerciseID: bench, id: "i1"))
    XCTAssertFalse(draft.add(exerciseID: bench, id: "i2"))
    XCTAssertEqual(draft.items.first?.sets, 3)
    XCTAssertEqual(draft.items.first?.reps, 10)
    XCTAssertEqual(draft.items.first?.restSeconds, 180)
    XCTAssertTrue(draft.canSave)
  }

  func testStepsStopAtTheRangeEnds() {
    var draft = WorkoutProgramDraft(name: "A")
    draft.add(exerciseID: bench, id: "i1")
    draft.step("i1", .rest, direction: 1)
    XCTAssertEqual(draft.value("i1", .rest), 195)
    for _ in 0..<80 { draft.step("i1", .rest, direction: -1) }
    XCTAssertEqual(draft.value("i1", .rest), 15)
    XCTAssertFalse(draft.canStep("i1", .rest, direction: -1))
    for _ in 0..<20 { draft.step("i1", .sets, direction: 1) }
    XCTAssertEqual(draft.value("i1", .sets), 10)
    for _ in 0..<20 { draft.step("i1", .reps, direction: -1) }
    XCTAssertEqual(draft.value("i1", .reps), 1)
  }

  func testSaveAddsOrReplacesAndKeepsTheColour() {
    var library = WorkoutLibrary()
    var draft = WorkoutProgramDraft(name: "  Грудь   и спина ", colorIndex: 4)
    XCTAssertFalse(library.save(draft, as: "p1"))
    draft.add(exerciseID: bench, id: "i1")
    draft.add(exerciseID: squat, id: "i2")
    XCTAssertTrue(library.save(draft, as: "p1"))
    XCTAssertEqual(library.programs.map(\.name), ["Грудь и спина"])
    XCTAssertEqual(library.programs[0].colorIndex, 4)
    draft.move(from: 1, to: 0)
    draft.remove("i1")
    draft.colorIndex = 2
    XCTAssertTrue(library.save(draft, as: "p1"))
    XCTAssertEqual(library.programs.count, 1)
    XCTAssertEqual(library.programs[0].items.map(\.exerciseID), [squat])
    XCTAssertEqual(library.programs[0].colorIndex, 2)
  }

  func testOlderProgramsReadWithDefaults() throws {
    let json = #"{"id":"p","name":"Old","items":[{"id":"i","exerciseID":"builtin.bench","sets":4}]}"#
    let program = try WorkoutCoding.decoder().decode(WorkoutProgram.self, from: Data(json.utf8))
    XCTAssertEqual(program.colorIndex, 0)
    XCTAssertEqual(program.items[0].sets, 4)
    XCTAssertEqual(program.items[0].reps, 10)
    XCTAssertEqual(program.items[0].restSeconds, 180)
  }

  func testStartedWorkoutCarriesRepsAndRestOfTheProgram() {
    var library = WorkoutLibrary()
    var draft = WorkoutProgramDraft(name: "A")
    draft.add(exerciseID: bench, id: "i1")
    draft.step("i1", .reps, direction: -1)
    draft.step("i1", .rest, direction: 1)
    library.save(draft, as: "p1")
    let session = WorkoutSession.start(
      program: library.programs[0], library: library, history: WorkoutHistory(), language: .ru,
      now: at("2026-11-04T10:00:00Z"))
    XCTAssertEqual(session?.items[0].restSeconds, 195)
    XCTAssertEqual(session?.items[0].sets.map(\.reps), ["9", "9", "9"])
  }

  func testStepperKeepsWeightsAndRepsInRange() {
    XCTAssertEqual(WorkoutStepper.weight("80", delta: 2.5, comma: true), "82,5")
    XCTAssertEqual(WorkoutStepper.weight("1", delta: -2.5, comma: true), "0")
    XCTAssertEqual(WorkoutStepper.weight("", delta: 2.5, comma: false), "2.5")
    XCTAssertEqual(WorkoutStepper.reps("8", delta: 1), "9")
    XCTAssertEqual(WorkoutStepper.reps("1", delta: -1), "1")
  }

  func testRestTimerKeepsTheExercisesOwnLengthForTheRing() {
    var timer = RestTimer()
    let t0 = at("2026-11-04T10:00:00Z")
    XCTAssertEqual(timer.totalLength, 180)
    timer.restart(now: t0, seconds: 90)
    XCTAssertEqual(timer.remaining(now: t0), 90)
    XCTAssertEqual(timer.totalLength, 90)
    timer.extend(now: t0.addingTimeInterval(10))
    XCTAssertEqual(timer.totalLength, 105)
    XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(10)), 95)
    timer.reset()
    XCTAssertEqual(timer.totalLength, 180)
    let restored = try? WorkoutCoding.decoder().decode(
      RestTimer.self, from: WorkoutCoding.encoder().encode(timer))
    XCTAssertEqual(restored, timer)
  }
}

// MARK: - Sync of records and settings

private actor ExtrasRemote: WorkoutSyncRemote {
  let supportsExtras: Bool
  var docs: [WorkoutDocKind: [String: WorkoutDoc]] = [:]
  var puts: [WorkoutDocKind] = []
  var clock = 0

  init(supportsExtras: Bool) { self.supportsExtras = supportsExtras }

  func seed(_ kind: WorkoutDocKind, _ id: String, _ data: JSONValue) {
    clock += 1
    docs[kind, default: [:]][id] = WorkoutDoc(id: id, updatedAt: "2026-11-04T10:00:\(String(format: "%02d", clock)).000Z", data: data)
  }

  func fetchWorkouts() async throws -> WorkoutServerSnapshot {
    func list(_ kind: WorkoutDocKind) -> [WorkoutDoc] { (docs[kind] ?? [:]).values.sorted { $0.id < $1.id } }
    return WorkoutServerSnapshot(
      programs: list(.programs), sessions: list(.sessions),
      records: supportsExtras ? list(.records) : nil,
      settings: supportsExtras ? list(.settings) : nil)
  }

  func putWorkoutDoc(kind: WorkoutDocKind, id: String, data: JSONValue, expectedUpdatedAt: String?)
    async throws -> WorkoutDoc
  {
    puts.append(kind)
    seed(kind, id, data)
    return docs[kind]![id]!
  }

  func deleteWorkoutDoc(kind: WorkoutDocKind, id: String, expectedUpdatedAt: String) async throws {
    docs[kind]?[id] = nil
  }
}

final class WorkoutExtrasSyncTests: XCTestCase {
  private func localDocs() -> [WorkoutDocKind: [String: JSONValue]] {
    var bests = WorkoutBests()
    bests.upsert(WorkoutBest(exerciseID: bench, name: "Жим", weight: 82.5, reps: 4, date: at("2026-11-04T10:00:00Z")))
    return WorkoutSyncCodec.documents(
      library: WorkoutLibrary(programs: [WorkoutProgram(id: "p1", name: "A")]),
      history: WorkoutHistory(), bests: bests, settings: WorkoutSettings(linkedHabitID: "gym"))
  }

  func testDocumentsIncludeRecordsAndSettingsAndDropDefaultSettings() {
    let docs = localDocs()
    XCTAssertEqual(Set(docs[.records]!.keys), ["rec-builtin-bench"])
    XCTAssertEqual(docs[.settings]?[WorkoutSettings.docID]?.objectValue?["linkedHabitID"]?.stringValue, "gym")
    let empty = WorkoutSyncCodec.documents(library: WorkoutLibrary(), history: WorkoutHistory())
    XCTAssertTrue(empty[.settings]!.isEmpty)
    XCTAssertTrue(empty[.records]!.isEmpty)
  }

  func testNewServerGetsRecordsAndSettingsPushed() async {
    let remote = ExtrasRemote(supportsExtras: true)
    var state = WorkoutSyncState(serverKey: "s")
    state.reconcile(local: localDocs())
    let outcome = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNil(outcome.failure)
    XCTAssertTrue(outcome.state.extrasSupported)
    XCTAssertFalse(outcome.state.hasPending)
    let puts = await remote.puts
    XCTAssertTrue(puts.contains(.records))
    XCTAssertTrue(puts.contains(.settings))
    XCTAssertNotNil(outcome.state.records["rec-builtin-bench"]?.serverUpdatedAt)
  }

  func testOldServerKeepsRecordsAndSettingsLocalAndQuiet() async {
    let remote = ExtrasRemote(supportsExtras: false)
    var state = WorkoutSyncState(serverKey: "s")
    state.reconcile(local: localDocs())
    let outcome = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNil(outcome.failure)
    XCTAssertFalse(outcome.unsupported)
    XCTAssertFalse(outcome.state.extrasSupported)
    let puts = await remote.puts
    XCTAssertEqual(Set(puts), [.programs])  // the program still syncs; the extras never leave
    // Still waiting locally, but not counted as pending, so no retry loop and no error.
    XCTAssertTrue(outcome.state.records["rec-builtin-bench"]?.dirty ?? false)
    XCTAssertFalse(outcome.state.hasPending)
    // A later pass against a newer server sends them.
    let upgraded = ExtrasRemote(supportsExtras: true)
    let later = await WorkoutSyncEngine.run(state: outcome.state, remote: upgraded)
    XCTAssertTrue(later.state.extrasSupported)
    let laterPuts = await upgraded.puts
    XCTAssertTrue(laterPuts.contains(.records))
  }

  func testOldServerDoesNotWipeLocalRecordsOnMerge() async {
    let remote = ExtrasRemote(supportsExtras: false)
    var state = WorkoutSyncState(serverKey: "s")
    state.records["rec-builtin-bench"] = WorkoutSyncEntry(
      id: "rec-builtin-bench", serverUpdatedAt: "U1", data: .object([:]), dirty: false)
    let outcome = await WorkoutSyncEngine.run(state: state, remote: remote)
    XCTAssertNotNil(outcome.state.records["rec-builtin-bench"])  // not seen as deleted elsewhere
  }

  func testInboundRecordsAndSettingsAreApplied() async {
    let remote = ExtrasRemote(supportsExtras: true)
    let best = WorkoutBest(exerciseID: squat, name: "Присед", weight: 110, reps: 3, date: at("2026-10-30T08:00:00Z"))
    await remote.seed(.records, best.id, JSONValue.encoding(best)!)
    await remote.seed(.settings, WorkoutSettings.docID, JSONValue.encoding(WorkoutSettings(linkedHabitID: "gym"))!)
    var state = WorkoutSyncState(serverKey: "s")
    state.reconcile(local: WorkoutSyncCodec.documents(library: WorkoutLibrary(), history: WorkoutHistory()))
    let before = state
    let outcome = await WorkoutSyncEngine.run(state: before, remote: remote)
    let merged = WorkoutSyncState.integrate(
      before: before, after: outcome.state,
      localNow: WorkoutSyncCodec.documents(library: WorkoutLibrary(), history: WorkoutHistory()),
      accepts: { WorkoutSyncCodec.isReadable(kind: $0, id: $1, data: $2) })
    let applied = WorkoutSyncCodec.apply(
      merged.changes, library: WorkoutLibrary(), history: WorkoutHistory())
    XCTAssertEqual(applied.bests.items.map(\.exerciseID), [squat])
    XCTAssertEqual(applied.bests.items.first?.weight, 110)
    XCTAssertEqual(applied.settings.linkedHabitID, "gym")
  }

  func testRemovingSettingsDocResetsThem() {
    let applied = WorkoutSyncCodec.apply(
      [.settings: [WorkoutSettings.docID: .none]], library: WorkoutLibrary(), history: WorkoutHistory(),
      settings: WorkoutSettings(linkedHabitID: "gym"))
    XCTAssertTrue(applied.settings.isDefault)
  }

  func testSyncStateSavedBeforeTheNewKindsStillLoads() throws {
    let legacy = #"{"serverKey":"s","programs":{},"sessions":{}}"#
    let state = try JSONDecoder().decode(WorkoutSyncState.self, from: Data(legacy.utf8))
    XCTAssertEqual(state.serverKey, "s")
    XCTAssertTrue(state.records.isEmpty)
    XCTAssertFalse(state.extrasSupported)
    let again = try JSONDecoder().decode(WorkoutSyncState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(again, state)
  }

  func testSnapshotWithoutNewKeysIsAnOlderServer() throws {
    let old = #"{"programs":[],"sessions":[]}"#
    let snapshot = try JSONDecoder().decode(WorkoutServerSnapshot.self, from: Data(old.utf8))
    XCTAssertFalse(snapshot.supportsExtras)
    let new = #"{"programs":[],"sessions":[],"records":[],"settings":[]}"#
    XCTAssertTrue(try JSONDecoder().decode(WorkoutServerSnapshot.self, from: Data(new.utf8)).supportsExtras)
  }
}
