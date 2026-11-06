import Foundation
import XCTest

@testable import RitmCore
@testable import RitmSystem

/// Regressions at the app/extension boundary: real schedule math, bounded private projections,
/// absolute clocks and stale-command protection. These run without WidgetKit or an iPhone.
final class SystemSurfacesTests: XCTestCase {
  private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

  private func snapshot(
    now: Date, habits: [Habit] = [], tasks: [RitmTask] = [],
    events: [GoogleCalendarEvent] = [], zone: String = "Asia/Qyzylorda",
    expires: Date? = nil, calendar: WidgetCalendarState = .ready
  ) -> DayWidgetSnapshot {
    DayWidgetSnapshot.make(
      account: Bootstrap(tasks: tasks, settings: .init(language: .ru, timeZone: zone)),
      habits: habits, events: events, calendarState: calendar,
      contextID: "account-epoch", expires: expires ?? now.addingTimeInterval(48 * 3_600), now: now)
  }

  private func weeklyHabits(gym: [String], ielts: [String]) -> [Habit] {
    [Habit(id: "gym", title: "Gym", weekdays: [1, 2, 6], startDate: "2026-10-25",
           completedDates: gym),
     Habit(id: "ielts", title: "IELTS", weekdays: [0, 2, 5, 6], startDate: "2026-10-25",
           completedDates: ielts)]
  }

  func testMondayWidgetCountsOnlyGymOneOfOne() {
    let value = snapshot(now: instant("2026-10-26T06:00:00Z"),
                         habits: weeklyHabits(gym: ["2026-10-26"], ielts: []))
    XCTAssertEqual(value.habitsPlanned, 1)
    XCTAssertEqual(value.habitsCompleted, 1)
    XCTAssertEqual(value.habits.map(\.id), ["gym"])
    XCTAssertTrue(value.habits[0].completed)
  }

  func testTuesdayCountsOneOfTwoThenTwoOfTwoAndUndo() {
    let now = instant("2026-10-27T06:00:00Z")
    let one = snapshot(now: now, habits: weeklyHabits(gym: ["2026-10-27"], ielts: []))
    XCTAssertEqual(one.habitsPlanned, 2)
    XCTAssertEqual(one.habitsCompleted, 1)
    let two = snapshot(now: now, habits: weeklyHabits(gym: ["2026-10-27"], ielts: ["2026-10-27"]))
    XCTAssertEqual(two.habitsPlanned, 2)
    XCTAssertEqual(two.habitsCompleted, 2)
    let undone = snapshot(now: now, habits: weeklyHabits(gym: [], ielts: ["2026-10-27"]))
    XCTAssertEqual(undone.habitsCompleted, 1)
    XCTAssertFalse(two.hasSameContent(as: undone))
  }

  func testSundayIsWeekdayZeroAndEmptyDayRemainsNeutral() {
    let sunday = snapshot(now: instant("2026-10-25T06:00:00Z"),
      habits: weeklyHabits(gym: [], ielts: ["2026-10-25"]))
    XCTAssertEqual(sunday.habitsPlanned, 1)
    XCTAssertEqual(sunday.habitsCompleted, 1)
    XCTAssertEqual(sunday.habits.first?.id, "ielts")
    let wednesday = snapshot(now: instant("2026-10-28T06:00:00Z"),
      habits: weeklyHabits(gym: [], ielts: []))
    XCTAssertEqual(wednesday.habitsPlanned, 0)
    XCTAssertEqual(wednesday.habitsCompleted, 0)
    XCTAssertTrue(wednesday.habits.isEmpty)
  }

  func testScheduleHistoryCreationAndArchiveRemainAuthoritative() {
    let now = instant("2026-10-26T06:00:00Z")
    let future = Habit(id: "future", title: "Not created yet", startDate: "2026-11-01")
    let archived = Habit(id: "old", title: "Archived", weekdays: [1], archived: true,
      startDate: "2026-10-01", completedDates: ["2026-10-26"], periods: [
        .init(from: "2026-10-01", weekdays: [1]),
        .init(from: "2026-10-26", weekdays: [1], archived: true),
      ])
    let value = snapshot(now: now, habits: [future, archived])
    XCTAssertEqual(value.habitsPlanned, 0)
    XCTAssertEqual(value.habitsCompleted, 0)
  }

  func testCountedHabitUsesConfirmedCompletionInsteadOfGuessingFromProgress() {
    let now = instant("2026-10-26T06:00:00Z")
    var water = Habit(id: "water", title: "Water", target: 8, startDate: "2026-10-01",
                      progressByDate: ["2026-10-26": 8])
    let pending = snapshot(now: now, habits: [water])
    XCTAssertEqual(pending.habitsCompleted, 0)
    XCTAssertEqual(pending.habits.first?.progress, 8)
    water.completedDates = ["2026-10-26"]
    XCTAssertEqual(snapshot(now: now, habits: [water]).habitsCompleted, 1)
  }

  func testProjectionUsesOwnerDateAndExpiresAtOwnerMidnight() {
    let now = instant("2026-10-26T20:30:00Z") // Tuesday 01:30 in Qyzylorda.
    let value = snapshot(now: now, habits: weeklyHabits(gym: ["2026-10-27"], ielts: []))
    XCTAssertEqual(value.date, "2026-10-27")
    XCTAssertEqual(value.habitsPlanned, 2)
    XCTAssertEqual(value.validUntil, instant("2026-10-27T19:00:00Z"))
    XCTAssertTrue(value.isValid(at: value.validUntil.addingTimeInterval(-1)))
    XCTAssertFalse(value.isValid(at: value.validUntil))
    XCTAssertFalse(value.isValid(at: instant("2026-10-28T06:00:00Z")))
  }

  func testSessionExpiryBeatsMidnightAndDstUsesCalendarArithmetic() {
    let now = instant("2026-11-01T04:30:00Z") // 00:30 before New York's fall-back.
    let day = snapshot(now: now, zone: "America/New_York")
    XCTAssertEqual(day.validUntil, instant("2026-11-02T05:00:00Z"))
    let short = snapshot(now: now, zone: "America/New_York", expires: now.addingTimeInterval(90))
    XCTAssertEqual(short.validUntil, now.addingTimeInterval(90))
    XCTAssertFalse(short.isValid(at: now.addingTimeInterval(91)))
  }

  func testGoogleUnknownTaskIsNotPresentedAsConfirmedComplete() {
    let now = instant("2026-10-26T06:00:00Z")
    let event = GoogleCalendarEvent(id: "unknown", title: "Google task",
      start: .init(dateTime: "2026-10-26T12:00:00+05:00"),
      end: .init(dateTime: "2026-10-26T12:30:00+05:00"), timeZone: "Asia/Qyzylorda",
      taskLink: true)
    let value = snapshot(now: now, events: [event], calendar: .partial)
    XCTAssertEqual(value.tasksTotal, 1)
    XCTAssertEqual(value.tasksCompleted, 0)
    XCTAssertEqual(value.tasksUnknown, 1)
    XCTAssertNil(value.tasks.first?.completed)
    XCTAssertEqual(value.calendarState, .partial)
  }

  func testTimelineAdvancesCurrentAndNextEventAndEndsAtExpiry() {
    let now = instant("2026-10-26T06:00:00Z")
    let first = GoogleCalendarEvent(id: "1", title: "Current",
      start: .init(dateTime: "2026-10-26T10:00:00+05:00"),
      end: .init(dateTime: "2026-10-26T11:30:00+05:00"), timeZone: "Asia/Qyzylorda")
    let second = GoogleCalendarEvent(id: "2", title: "Next",
      start: .init(dateTime: "2026-10-26T13:00:00+05:00"),
      end: .init(dateTime: "2026-10-26T14:00:00+05:00"), timeZone: "Asia/Qyzylorda")
    let allDay = GoogleCalendarEvent(id: "all", title: "All day",
      start: .init(date: "2026-10-26"), end: .init(date: "2026-10-27"),
      timeZone: "Asia/Qyzylorda", allDay: true)
    let value = snapshot(now: now, events: [second, allDay, first])
    XCTAssertEqual(value.events.count, 2)
    XCTAssertEqual(value.nextEvent(at: now)?.id, "1")
    XCTAssertEqual(value.nextEvent(at: instant("2026-10-26T06:30:00Z"))?.id, "2")
    XCTAssertNil(value.nextEvent(at: instant("2026-10-26T09:00:00Z")))
    let timeline = value.timelineDates(after: now)
    XCTAssertEqual(timeline.first, now)
    XCTAssertEqual(timeline.last, value.validUntil)
    XCTAssertEqual(timeline, timeline.sorted())
    XCTAssertEqual(Set(timeline).count, timeline.count)
    XCTAssertFalse(timeline.contains(instant("2026-10-26T05:00:00Z")))
  }

  func testUnchangedPollDoesNotRequestAnotherWidgetReload() {
    let now = instant("2026-10-26T06:00:00Z")
    let before = snapshot(now: now, habits: weeklyHabits(gym: [], ielts: []))
    let after = snapshot(now: now.addingTimeInterval(30), habits: weeklyHabits(gym: [], ielts: []))
    XCTAssertNotEqual(before.generatedAt, after.generatedAt)
    XCTAssertTrue(before.hasSameContent(as: after))
  }

  func testWidgetSerializationExcludesAccountAndConversationSecrets() throws {
    let now = instant("2026-10-26T06:00:00Z")
    let account = Bootstrap(
      tasks: [.init(id: "t", title: "Visible task", description: "private-description",
                    date: "2026-10-26")],
      settings: .init(displayName: "private-name", email: "private-email@example.com"),
      conversations: [.init(id: "c", title: "private-conversation", messages: [
        .init(id: "m", role: "user", text: "private-message"),
      ])])
    let value = DayWidgetSnapshot.make(account: account, habits: [], events: [],
      calendarState: .unavailable, contextID: "opaque-epoch", expires: now.addingTimeInterval(300), now: now)
    let data = try JSONEncoder().encode(value)
    let encoded = String(decoding: data, as: UTF8.self)
    for secret in ["private-name", "private-email", "private-description", "private-conversation", "private-message"] {
      XCTAssertFalse(encoded.contains(secret), secret)
    }
    XCTAssertTrue(encoded.contains("Visible task"))
    XCTAssertEqual(try JSONDecoder().decode(DayWidgetSnapshot.self, from: data), value)
    XCTAssertLessThan(data.count, WidgetSnapshotStore.maximumBytes)
  }

  func testProjectionBoundsVisibleRowsAndLongTitles() {
    let now = instant("2026-10-26T06:00:00Z")
    let title = String(repeating: "x", count: 10_000)
    let tasks = (0..<100).map { RitmTask(id: "t\($0)", title: title, date: "2026-10-26") }
    let habits = (0..<100).map { Habit(id: "h\($0)", title: title, startDate: "2026-10-01") }
    let value = snapshot(now: now, habits: habits, tasks: tasks)
    XCTAssertEqual(value.tasks.count, 3)
    XCTAssertEqual(value.habits.count, 3)
    XCTAssertEqual(value.tasksTotal, 100)
    XCTAssertEqual(value.habitsPlanned, 100)
    XCTAssertTrue(value.tasks.allSatisfy { $0.title.count <= 256 })
    XCTAssertTrue(value.habits.allSatisfy { $0.title.count <= 256 })
  }

  func testAppGroupProjectionRoundTripAndCorruptFileIsRejected() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let value = snapshot(now: instant("2026-10-26T06:00:00Z"))
    XCTAssertTrue(WidgetSnapshotStore.write(value, in: directory))
    XCTAssertEqual(WidgetSnapshotStore.read(in: directory), value)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let file = try XCTUnwrap(files.first)
    try Data("not-json".utf8).write(to: file)
    XCTAssertNil(WidgetSnapshotStore.read(in: directory))
    try Data(repeating: 0x20, count: WidgetSnapshotStore.maximumBytes + 1).write(to: file)
    XCTAssertNil(WidgetSnapshotStore.read(in: directory))
  }

  func testCorruptCountAndSchemaCannotBecomeAValidWidgetSnapshot() throws {
    let now = instant("2026-10-26T06:00:00Z")
    let value = snapshot(now: now)
    let original = try JSONEncoder().encode(value)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
    for (key, invalid) in [("schemaVersion", -1), ("tasksCompleted", -1),
                           ("tasksTotal", -1), ("tasksUnknown", 1), ("habitsCompleted", 1)] {
      var changed = json
      changed[key] = invalid
      let decoded = try JSONDecoder().decode(DayWidgetSnapshot.self,
        from: JSONSerialization.data(withJSONObject: changed))
      XCTAssertFalse(decoded.isValid(at: now), key)
    }
    json["timeZone"] = "Invalid/Zone"
    let invalidZone = try JSONDecoder().decode(DayWidgetSnapshot.self,
      from: JSONSerialization.data(withJSONObject: json))
    XCTAssertFalse(invalidZone.isValid(at: now))
  }

  private func workoutState() -> SharedWorkoutState {
    let first = WorkoutSessionItem(id: "first", exerciseID: "bench", name: "Bench", previous: nil,
      sets: [.init(id: "a", weight: "62.5", reps: "10")], restSeconds: 90)
    let second = WorkoutSessionItem(id: "second", exerciseID: "row", name: "Row", previous: nil,
      sets: [.init(id: "b", weight: "50", reps: "12"), .init(id: "c", weight: "50", reps: "12")],
      restSeconds: 120)
    return SharedWorkoutState(session: .init(id: "workout", programID: "program", programName: "A",
      startedAt: instant("2026-10-26T06:00:00Z"), items: [first, second]))
  }

  private func card(_ state: SharedWorkoutState, now: Date, revision: String = UUID().uuidString)
    -> WorkoutActivityState {
    let session = state.session!
    let current = state.current
    return WorkoutActivityState(
      content: LiveActivityContent.make(from: state, privacy: false, now: now)!,
      startedAt: session.startedAt, exerciseNumber: (current?.exercise ?? session.items.count - 1) + 1,
      exerciseTotal: session.items.count,
      setID: current.map { session.items[$0.exercise].sets[$0.set].id } ?? "finished",
      revision: revision, language: .en)
  }

  func testActionRequestRoundTripsAndRejectsMalformedOrAmbiguousLinks() throws {
    let state = workoutState()
    let display = card(state, now: state.session!.startedAt)
    let request = display.request(.confirmSet)
    XCTAssertEqual(WorkoutActionRequest(rawValue: request.rawValue), request)
    XCTAssertEqual(WorkoutActionRequest(url: request.url), request)
    XCTAssertNil(WorkoutActionRequest(rawValue: String(repeating: "a", count: 4_097)))
    XCTAssertNil(WorkoutActionRequest(rawValue: "not-base64"))
    XCTAssertNil(WorkoutActionRequest(url: URL(string: "https://workout-action?request=\(request.rawValue)")!))
    var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
    parts.queryItems?.append(.init(name: "request", value: request.rawValue))
    XCTAssertNil(WorkoutActionRequest(url: parts.url!))
    let badRevision = WorkoutActionRequest(workoutID: "workout", setID: "a",
                                           revision: "not-a-uuid", action: .confirmSet)
    XCTAssertNil(WorkoutActionRequest(rawValue: badRevision.rawValue))
  }

  func testLastSetAdvancesExerciseAndUsesFinishedExercisesOwnRest() {
    let state = workoutState()
    let now = state.session!.startedAt
    let display = card(state, now: now)
    let result = WorkoutActionPolicy.apply(display.request(.confirmSet), displayed: display,
                                           state: state, now: now)
    XCTAssertEqual(result.outcome, .applied)
    XCTAssertEqual(result.state.currentExerciseIndex, 1)
    XCTAssertEqual(result.state.currentSetIndex, 0)
    XCTAssertEqual(result.state.session?.doneSets, 1)
    XCTAssertEqual(result.state.rest.remaining(now: now), 90)
    XCTAssertEqual(card(result.state, now: now).exerciseNumber, 2)
  }

  func testRepeatedCommandAndOldWorkoutCannotChangeNewRevision() {
    let state = workoutState()
    let now = state.session!.startedAt
    let original = card(state, now: now)
    let request = original.request(.confirmSet)
    let accepted = WorkoutActionPolicy.apply(request, displayed: original, state: state, now: now)
    let newCard = card(accepted.state, now: now)
    let replay = WorkoutActionPolicy.apply(request, displayed: newCard, state: accepted.state, now: now)
    XCTAssertEqual(replay.outcome, .ignoredStale)
    XCTAssertEqual(replay.state, accepted.state)
    let foreign = WorkoutActionRequest(workoutID: "other", setID: original.setID,
                                         revision: original.revision, action: .confirmSet)
    XCTAssertEqual(WorkoutActionPolicy.apply(foreign, displayed: original, state: state, now: now).outcome,
                   .ignoredStale)
  }

  func testRestCannotConfirmSetBeforeDeadlineButCanAfterSuspension() {
    var state = workoutState()
    let now = state.session!.startedAt
    state.rest.restart(now: now, seconds: 90)
    let display = card(state, now: now)
    let early = WorkoutActionPolicy.apply(display.request(.confirmSet), displayed: display,
      state: state, now: now.addingTimeInterval(89))
    XCTAssertEqual(early.outcome, .ignoredNothingToDo)
    XCTAssertEqual(early.state.session?.doneSets, 0)
    let late = WorkoutActionPolicy.apply(display.request(.confirmSet), displayed: display,
      state: state, now: now.addingTimeInterval(91))
    XCTAssertEqual(late.outcome, .applied)
    XCTAssertEqual(late.state.session?.doneSets, 1)
  }

  func testExtendAndSkipNeverMarkASetAndReplayCannotAddMoreTime() {
    var state = workoutState()
    let now = state.session!.startedAt
    state.rest.start(now: now)
    let display = card(state, now: now)
    let extended = WorkoutActionPolicy.apply(display.request(.extendRest), displayed: display,
      state: state, now: now)
    XCTAssertEqual(extended.outcome, .applied)
    XCTAssertEqual(extended.state.rest.remaining(now: now), 195)
    XCTAssertEqual(extended.state.session?.doneSets, 0)
    let updated = card(extended.state, now: now)
    let replay = WorkoutActionPolicy.apply(display.request(.extendRest), displayed: updated,
      state: extended.state, now: now)
    XCTAssertEqual(replay.outcome, .ignoredStale)
    let skipped = WorkoutActionPolicy.apply(updated.request(.skipRest), displayed: updated,
      state: extended.state, now: now)
    XCTAssertEqual(skipped.outcome, .applied)
    XCTAssertEqual(skipped.state.rest.phase(now: now), .idle)
    XCTAssertEqual(skipped.state.session?.doneSets, 0)
  }

  func testAllSetsFinishWithoutExtraRestOrSilentJournalCompletion() {
    var state = workoutState()
    let started = state.session!.startedAt
    for index in 0..<3 {
      let now = started.addingTimeInterval(Double(index * 200))
      let display = card(state, now: now)
      let result = WorkoutActionPolicy.apply(display.request(.confirmSet), displayed: display,
        state: state, now: now)
      XCTAssertEqual(result.outcome, .applied)
      state = result.state
    }
    XCTAssertNil(state.current)
    XCTAssertEqual(state.session?.doneSets, 3)
    XCTAssertNil(state.rest.endDate)
    XCTAssertEqual(state.phase(now: started.addingTimeInterval(600)), .allDone)
    let display = card(state, now: started.addingTimeInterval(600))
    let finish = WorkoutActionPolicy.apply(display.request(.finishWorkout), displayed: display,
      state: state, now: started.addingTimeInterval(600))
    XCTAssertNotEqual(finish.outcome, .applied)
    XCTAssertNotNil(finish.state.session)
  }

  @MainActor
  func testAccountContextSurvivesANewDefaultsInstanceForColdLaunch() async throws {
    let suite = "Ritm.SystemSurfacesTests." + UUID().uuidString
    let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { firstDefaults.removePersistentDomain(forName: suite) }
    let original = AccountSurfaceContext.current(defaults: firstDefaults)
    XCTAssertNotNil(UUID(uuidString: original))
    XCTAssertEqual(AccountSurfaceContext.current(defaults: firstDefaults), original)

    let coldLaunchDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    XCTAssertEqual(AccountSurfaceContext.current(defaults: coldLaunchDefaults), original)
    XCTAssertEqual(firstDefaults.persistentDomain(forName: suite)?.count, 1)
  }

  @MainActor
  func testAccountRotationImmediatelyInvalidatesMarkerButPreservesLocalWorkoutRevision() async throws {
    let suite = "Ritm.SystemSurfacesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let digest = Data(repeating: 0xA1, count: 32)
    let localWorkout = WorkoutSurfaceRevision.current(fingerprint: digest, defaults: defaults)
    let signedIn = AccountSurfaceContext.current(defaults: defaults)
    let signedOut = AccountSurfaceContext.rotate(defaults: defaults)
    XCTAssertNotEqual(signedOut, signedIn)
    XCTAssertEqual(AccountSurfaceContext.current(defaults: defaults), signedOut)
    let serverChanged = AccountSurfaceContext.rotate(defaults: defaults)
    XCTAssertNotEqual(serverChanged, signedOut)
    XCTAssertNotEqual(serverChanged, signedIn)
    XCTAssertEqual(WorkoutSurfaceRevision.current(fingerprint: digest, defaults: defaults), localWorkout)
  }

  @MainActor
  func testMalformedAccountMarkerIsReplacedWithAnOpaqueUUID() async throws {
    let suite = "Ritm.SystemSurfacesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "ritm.account.surface-context.v1"
    defaults.set("not-a-uuid", forKey: key)
    let recovered = AccountSurfaceContext.current(defaults: defaults)
    XCTAssertNotNil(UUID(uuidString: recovered))
    XCTAssertEqual(defaults.string(forKey: key), recovered)
    defaults.set(Data([1, 2, 3]), forKey: key)
    let recoveredFromWrongType = AccountSurfaceContext.current(defaults: defaults)
    XCTAssertNotNil(UUID(uuidString: recoveredFromWrongType))
    XCTAssertNotEqual(recoveredFromWrongType, recovered)
  }

  @MainActor
  func testWorkoutRevisionSurvivesColdLoadWhenDurableFingerprintIsUnchanged() async throws {
    let suite = "Ritm.SystemSurfacesTests." + UUID().uuidString
    let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { firstDefaults.removePersistentDomain(forName: suite) }
    let digest = Data(repeating: 0xB2, count: 32)
    let revision = WorkoutSurfaceRevision.current(fingerprint: digest, defaults: firstDefaults)
    XCTAssertNotNil(UUID(uuidString: revision))
    XCTAssertEqual(WorkoutSurfaceRevision.current(fingerprint: digest, defaults: firstDefaults), revision)
    let coldLaunchDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    XCTAssertEqual(WorkoutSurfaceRevision.current(fingerprint: digest, defaults: coldLaunchDefaults), revision)
    XCTAssertEqual(firstDefaults.data(forKey: "ritm.workout.surface-revision.v1.digest"), digest)
  }

  @MainActor
  func testChangedWorkoutFingerprintInvalidatesOldRevisionAndCannotResurrectIt() async throws {
    let suite = "Ritm.SystemSurfacesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let before = Data(repeating: 0xC3, count: 32)
    let after = Data(repeating: 0xD4, count: 32)
    let original = WorkoutSurfaceRevision.current(fingerprint: before, defaults: defaults)
    let changed = WorkoutSurfaceRevision.current(fingerprint: after, defaults: defaults)
    XCTAssertNotEqual(changed, original)
    XCTAssertEqual(WorkoutSurfaceRevision.current(fingerprint: after, defaults: defaults), changed)
    // Undoing a journal edit must not make a stale command from before that edit valid again.
    let reverted = WorkoutSurfaceRevision.current(fingerprint: before, defaults: defaults)
    XCTAssertNotEqual(reverted, original)
    XCTAssertNotEqual(reverted, changed)
  }

  @MainActor
  func testMalformedWorkoutDefaultsRecoverWithoutCopyingThePrivateJournal() async throws {
    let suite = "Ritm.SystemSurfacesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "ritm.workout.surface-revision.v1"
    let digest = Data(repeating: 0xE5, count: 32)
    defaults.set("bad-revision", forKey: key)
    defaults.set(digest, forKey: key + ".digest")
    let recovered = WorkoutSurfaceRevision.current(fingerprint: digest, defaults: defaults)
    XCTAssertNotNil(UUID(uuidString: recovered))
    defaults.set("bad-digest-type", forKey: key + ".digest")
    let recoveredDigest = WorkoutSurfaceRevision.current(fingerprint: digest, defaults: defaults)
    XCTAssertNotEqual(recoveredDigest, recovered)
    XCTAssertNotNil(UUID(uuidString: recoveredDigest))
    let domain = try XCTUnwrap(defaults.persistentDomain(forName: suite))
    XCTAssertEqual(Set(domain.keys), Set([key, key + ".digest"]))
    XCTAssertEqual(domain[key] as? String, recoveredDigest)
    XCTAssertEqual(domain[key + ".digest"] as? Data, digest)
  }
}
