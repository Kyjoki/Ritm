import Foundation

// Personal records («Рекорды»): the best weight per exercise.
//
// A record is DERIVED from the finished workouts. The owner can also correct one by hand (a
// «best» doc with the exercise, kg, reps and date) or delete it (a «best» doc with `deleted`):
// that doc overrides what the history says for that exercise, and it is synced like a program.
// A finished workout that beats the current record writes such a doc, so the new record sticks
// and reaches the other devices.

/// A manual record, or the tombstone of a deleted one. One per exercise.
public struct WorkoutBest: Codable, Equatable, Identifiable, Sendable {
  public var id: String { WorkoutRecords.docID(exerciseID) }
  public var exerciseID: String
  public var name: String
  public var weight: Double
  public var reps: Int
  public var date: Date
  /// The owner removed the record: nothing is shown for this exercise until a heavier lift.
  public var deleted: Bool

  public init(
    exerciseID: String, name: String, weight: Double, reps: Int, date: Date, deleted: Bool = false
  ) {
    self.exerciseID = exerciseID
    self.name = name
    self.weight = weight
    self.reps = reps
    self.date = date
    self.deleted = deleted
  }

  private enum CodingKeys: String, CodingKey { case exerciseID, name, weight, reps, date, deleted }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      exerciseID: try c.decode(String.self, forKey: .exerciseID), name: c.workoutValue(.name, ""),
      weight: c.workoutValue(.weight, 0), reps: c.workoutValue(.reps, 1),
      date: c.workoutValue(.date, Date(timeIntervalSince1970: 0)),
      deleted: c.workoutValue(.deleted, false))
  }
}

/// The file `records.json`.
public struct WorkoutBests: Codable, Equatable, Sendable {
  public static let version = 1

  public var items: [WorkoutBest]

  public init(items: [WorkoutBest] = []) { self.items = items }

  private enum CodingKeys: String, CodingKey { case version, items }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    items = c.workoutLossy(WorkoutBest.self, .items)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(Self.version, forKey: .version)
    try c.encode(items, forKey: .items)
  }

  public func item(for exerciseID: String) -> WorkoutBest? {
    items.first { $0.exerciseID == exerciseID }
  }

  /// Sets the record of an exercise by hand (replacing any earlier doc for it).
  public mutating func upsert(_ best: WorkoutBest) {
    items.removeAll { $0.exerciseID == best.exerciseID }
    items.append(best)
  }

  /// Deletes the record of an exercise: a tombstone, so the history cannot bring it back.
  public mutating func remove(exerciseID: String, name: String, now: Date) {
    upsert(
      WorkoutBest(exerciseID: exerciseID, name: name, weight: 0, reps: 1, date: now, deleted: true))
  }
}

/// A record as the cards show it.
public struct WorkoutRecordCard: Equatable, Identifiable, Sendable {
  public var id: String { exerciseID }
  public let exerciseID: String
  public let name: String
  public let weight: Double
  public let reps: Int
  public let date: Date
  /// Set by the owner (or by a workout that beat the old one), not just derived.
  public let isStored: Bool

  public init(
    exerciseID: String, name: String, weight: Double, reps: Int, date: Date, isStored: Bool = false
  ) {
    self.exerciseID = exerciseID
    self.name = name
    self.weight = weight
    self.reps = reps
    self.date = date
    self.isStored = isStored
  }
}

/// A new record set by a finished workout.
public struct WorkoutRecordBeat: Equatable, Sendable {
  public let exerciseID: String
  public let name: String
  public let weight: Double
  public let reps: Int
  public let previousWeight: Double
}

public enum WorkoutRecords {
  /// The doc id of an exercise's record: `rec-` and the exercise id with `.` turned into `-`
  /// (the server accepts letters, digits, `_` and `-`).
  public static func docID(_ exerciseID: String) -> String {
    "rec-" + String(exerciseID.map { $0 == "." ? "-" : $0 })
  }

  /// The heaviest set of every exercise in the history (more reps, then the earlier day, break a
  /// tie). Bodyweight sets (0 kg) are not records.
  public static func derived(from history: WorkoutHistory) -> [String: WorkoutRecordCard] {
    var best: [String: WorkoutRecordCard] = [:]
    // Oldest first, so an equal lift later on never replaces the day it was first done.
    for record in history.records.sorted(by: { $0.endedAt < $1.endedAt }) {
      for exercise in record.exercises {
        guard let top = heaviest(exercise.sets) else { continue }
        if let current = best[exercise.exerciseID],
          (top.weight, top.reps) <= (current.weight, current.reps)
        {
          continue
        }
        best[exercise.exerciseID] = WorkoutRecordCard(
          exerciseID: exercise.exerciseID, name: exercise.name, weight: top.weight, reps: top.reps,
          date: record.endedAt)
      }
    }
    return best
  }

  /// The records to show, newest first: what the history says, with the owner's docs on top
  /// (a changed record replaces it, a deleted one hides it).
  public static func resolve(history: WorkoutHistory, bests: WorkoutBests) -> [WorkoutRecordCard] {
    var cards = derived(from: history)
    for item in bests.items {
      if item.deleted {
        cards[item.exerciseID] = nil
      } else if item.weight > 0 {
        cards[item.exerciseID] = WorkoutRecordCard(
          exerciseID: item.exerciseID, name: item.name, weight: item.weight, reps: item.reps,
          date: item.date, isStored: true)
      }
    }
    return cards.values.sorted { ($0.date, $1.name) > ($1.date, $0.name) }
  }

  /// What finishing `finished` changes: the exercises where it beats the current record
  /// (`before` is what was shown before it was saved), and the docs to store for them. A record
  /// the owner deleted comes back quietly when a workout lifts again.
  public static func updates(
    finished: WorkoutRecord, before: [WorkoutRecordCard], bests: WorkoutBests
  ) -> (bests: WorkoutBests, beats: [WorkoutRecordBeat]) {
    var next = bests
    var beats: [WorkoutRecordBeat] = []
    for exercise in finished.exercises {
      guard let top = heaviest(exercise.sets) else { continue }
      let entry = WorkoutBest(
        exerciseID: exercise.exerciseID, name: exercise.name, weight: top.weight, reps: top.reps,
        date: finished.endedAt)
      if let current = before.first(where: { $0.exerciseID == exercise.exerciseID }) {
        guard top.weight > current.weight else { continue }
        next.upsert(entry)
        beats.append(
          WorkoutRecordBeat(
            exerciseID: entry.exerciseID, name: entry.name, weight: entry.weight, reps: entry.reps,
            previousWeight: current.weight))
      } else if bests.item(for: exercise.exerciseID)?.deleted == true {
        next.upsert(entry)
      }
    }
    return (next, beats)
  }

  private static func heaviest(_ sets: [WorkoutResultSet]) -> WorkoutResultSet? {
    sets.filter { $0.weight > 0 }.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
  }
}
