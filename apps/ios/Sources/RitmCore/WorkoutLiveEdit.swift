import Foundation

// Editing the program DURING a workout. Everything here changes the running workout only (a
// copy of the program); the program itself changes only when the owner agrees at the finish.

// MARK: - One exercise of the running workout

extension WorkoutSessionItem {
  /// Fewest sets the exercise can have: the done ones stay, and there is always one.
  public var minSets: Int { max(1, doneCount) }

  /// What the exercise looks like as a program item (values clamped to the program's ranges).
  public var plan: WorkoutProgramItem {
    WorkoutProgramItem(
      id: id, exerciseID: exerciseID, sets: sets.count, reps: plannedReps, restSeconds: restSeconds)
  }

  /// A replaced exercise that only holds the sets done before it was replaced.
  public var isOnlyInLog: Bool { keptForLog && sets.allSatisfy(\.done) }

  public func value(_ field: WorkoutProgramDraft.Field) -> Int {
    switch field {
    case .sets: sets.count
    case .reps: plannedReps
    case .rest: restSeconds
    }
  }

  /// Whether one more step up (`+1`) or down (`-1`) stays inside the field's range.
  public func canStep(_ field: WorkoutProgramDraft.Field, direction: Int) -> Bool {
    Self.allowedRange(field, minSets: minSets).contains(value(field) + direction * Self.stepSize(field))
  }

  /// +1 / −1 step of sets (1), reps (1) or rest (15 s), stopping at the range ends. Sets never
  /// drop below the done ones; a step down removes the last set that is not done.
  public mutating func step(
    _ field: WorkoutProgramDraft.Field, direction: Int, makeID: () -> String = WorkoutID.make
  ) {
    guard canStep(field, direction: direction) else { return }
    let next = value(field) + direction * Self.stepSize(field)
    switch field {
    case .sets: setPlannedSets(next, makeID: makeID)
    case .reps: setPlannedReps(next)
    case .rest: setRest(next)
    }
  }

  /// Sets the number of sets: new ones follow the shared weight, removed ones are the last that
  /// are not done.
  public mutating func setPlannedSets(_ count: Int, makeID: () -> String = WorkoutID.make) {
    let target = min(max(count, minSets), Self.maxSets)
    while sets.count < target { addSet(id: makeID()) }
    while sets.count > target, removeLastOpenSet() {}
  }

  /// The reps target; the sets that are not done take it at once.
  public mutating func setPlannedReps(_ reps: Int) {
    let range = WorkoutProgramItem.repsRange
    plannedReps = min(max(reps, range.lowerBound), range.upperBound)
    for index in sets.indices where !sets[index].done { sets[index].reps = String(plannedReps) }
  }

  public mutating func setRest(_ seconds: Int) {
    let range = WorkoutProgramItem.restRange
    restSeconds = min(max(seconds, range.lowerBound), range.upperBound)
  }

  /// Removes the last set that is not done. The last remaining set stays.
  @discardableResult
  public mutating func removeLastOpenSet() -> Bool {
    guard let last = sets.last(where: { !$0.done }) else { return false }
    return removeSet(setID: last.id)
  }

  private static func allowedRange(_ field: WorkoutProgramDraft.Field, minSets: Int) -> ClosedRange<Int> {
    switch field {
    case .sets: minSets...maxSets
    case .reps: WorkoutProgramItem.repsRange
    case .rest: WorkoutProgramItem.restRange
    }
  }

  private static func stepSize(_ field: WorkoutProgramDraft.Field) -> Int {
    field == .rest ? WorkoutProgramItem.restStep : 1
  }
}

// MARK: - The list of exercises

extension WorkoutSession {
  /// Adds an exercise at the end, or right after position `index`. A new exercise gets 3 sets of
  /// 10 and the default rest, like in the editor, and shows its own last results. Returns the new
  /// item's id, `nil` when the exercise is already in the workout.
  @discardableResult
  public mutating func addExercise(
    _ exerciseID: String, name: String, history: WorkoutHistory, after index: Int? = nil,
    makeID: () -> String = WorkoutID.make
  ) -> String? {
    guard !items.contains(where: { $0.exerciseID == exerciseID }) else { return nil }
    let item = WorkoutSessionItem.make(
      exerciseID: exerciseID, name: name, setCount: 3, history: history,
      plannedReps: WorkoutProgramItem.defaultReps, makeID: makeID)
    let position = index.map { min(max($0 + 1, 0), items.count) } ?? items.count
    items.insert(item, at: position)
    return item.id
  }

  /// Removes an exercise with whatever was done in it. A workout keeps at least one exercise.
  @discardableResult
  public mutating func removeExercise(_ itemID: String) -> Bool {
    guard items.count > 1, let index = items.firstIndex(where: { $0.id == itemID }) else { return false }
    items.remove(at: index)
    return true
  }

  public mutating func moveExercise(from: Int, to: Int) {
    items = WorkoutOrder.moving(items, from: from, to: to)
  }

  public func hasDoneSets(_ itemID: String) -> Bool { (item(itemID)?.doneCount ?? 0) > 0 }

  /// The exercises of the workout as a program would list them.
  public var programItems: [WorkoutProgramItem] {
    items.filter { !$0.isOnlyInLog }.map(\.plan)
  }
}

// MARK: - Difference from the saved program

/// What the running workout changed against its program, for «Сохранить изменения в программе?».
public struct WorkoutProgramChange: Equatable, Sendable {
  public var added: Int
  public var removed: Int
  /// Exercises in both, with other sets, reps or rest.
  public var modified: Int
  public var reordered: Bool

  public var isEmpty: Bool { added == 0 && removed == 0 && modified == 0 && !reordered }
}

extension WorkoutSession {
  /// `nil` when the workout still matches `program` (exercises, order, sets, reps and rest).
  public func change(from program: WorkoutProgram) -> WorkoutProgramChange? {
    let mine = programItems
    guard !mine.isEmpty else { return nil }
    let theirs = program.items
    let mineIDs = Set(mine.map(\.exerciseID))
    let theirIDs = Set(theirs.map(\.exerciseID))
    let modified = mine.filter { item in
      theirs.first { $0.exerciseID == item.exerciseID }.map {
        $0.sets != item.sets || $0.reps != item.reps || $0.restSeconds != item.restSeconds
      } ?? false
    }.count
    let common = mineIDs.intersection(theirIDs)
    let change = WorkoutProgramChange(
      added: mineIDs.subtracting(theirIDs).count, removed: theirIDs.subtracting(mineIDs).count,
      modified: modified,
      reordered: mine.map(\.exerciseID).filter(common.contains)
        != theirs.map(\.exerciseID).filter(common.contains))
    return change.isEmpty ? nil : change
  }

  /// The program as the workout now has it; its id, name and colour stay.
  public func applied(to program: WorkoutProgram) -> WorkoutProgram {
    let mine = programItems
    guard !mine.isEmpty else { return program }
    let items = mine.map { item -> WorkoutProgramItem in
      let existing = program.items.first { $0.exerciseID == item.exerciseID }
      return WorkoutProgramItem(
        id: existing?.id ?? item.id, exerciseID: item.exerciseID, sets: item.sets, reps: item.reps,
        restSeconds: item.restSeconds)
    }
    return WorkoutProgram(
      id: program.id, name: program.name, items: items, colorIndex: program.colorIndex)
  }
}

extension WorkoutLibrary {
  /// «Сохранить в программу»: writes the running workout's exercises into its program.
  @discardableResult
  public mutating func saveChanges(of session: WorkoutSession) -> Bool {
    guard let index = programs.firstIndex(where: { $0.id == session.programID }),
      session.change(from: programs[index]) != nil
    else { return false }
    programs[index] = session.applied(to: programs[index])
    return true
  }
}

// MARK: - A finished workout: best sets and records

extension WorkoutRecordExercise {
  /// Weight moved in this exercise, kg × reps.
  public var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
}

extension WorkoutRecord {
  public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

extension WorkoutRecords {
  /// The index of the best set: the heaviest, then the one with more reps; the first on a tie.
  /// Bodyweight sets (0 kg) compete by reps.
  public static func bestSetIndex(_ sets: [WorkoutResultSet]) -> Int? {
    var best: Int?
    for index in sets.indices {
      guard let current = best else {
        best = index
        continue
      }
      if (sets[index].weight, sets[index].reps) > (sets[current].weight, sets[current].reps) {
        best = index
      }
    }
    return best
  }

  /// The sets that were a personal record when this workout was done, by exercise id: the best
  /// set of the exercise, when it was heavier than anything lifted in earlier workouts. An
  /// exercise done for the first time has nothing to beat, so it gets no mark.
  public static func recordSets(in record: WorkoutRecord, history: WorkoutHistory) -> [String: Int] {
    let earlier = history.records.filter { $0.id != record.id && $0.endedAt < record.endedAt }
    var result: [String: Int] = [:]
    for exercise in record.exercises {
      guard let index = bestSetIndex(exercise.sets), exercise.sets[index].weight > 0 else { continue }
      let before =
        earlier.flatMap(\.exercises)
        .filter { $0.exerciseID == exercise.exerciseID }
        .flatMap(\.sets).map(\.weight).max() ?? 0
      if before > 0, exercise.sets[index].weight > before { result[exercise.exerciseID] = index }
    }
    return result
  }
}
