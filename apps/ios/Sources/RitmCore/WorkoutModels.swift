import Foundation

// «Тренировки»: the models of the training log.
//
// This data is LOCAL to the iPhone. The Ritm server has no workout model and none of these types
// is ever sent to it, to the assistant or to any AI request. Signing out or switching the server
// does not delete it: it is the owner's training log, not account data held by the server.

public enum WorkoutID {
  public static func make() -> String { UUID().uuidString }
}

// MARK: - Tolerant decoding

private struct WorkoutSkip: Decodable {
  init(from decoder: Decoder) throws {}
}

extension KeyedDecodingContainer {
  /// A value that falls back to `fallback` when the key is missing or has the wrong shape, so a
  /// file written by another version never makes the whole log unreadable.
  func workoutValue<T: Decodable>(_ key: Key, _ fallback: T) -> T {
    (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
  }

  /// An array that drops the elements it cannot read instead of failing as a whole.
  func workoutLossy<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
    guard var list = try? nestedUnkeyedContainer(forKey: key) else { return [] }
    var result: [T] = []
    while !list.isAtEnd {
      if let element = try? list.decode(T.self) {
        result.append(element)
      } else {
        _ = try? list.decode(WorkoutSkip.self)
      }
    }
    return result
  }
}

public enum WorkoutCoding {
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

// MARK: - Exercises and programs

/// An exercise the owner created. Built-in ones live in `WorkoutCatalog`.
public struct WorkoutExercise: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public var name: String
  /// The muscle group of an exercise the owner created; built-in ones get it from the catalog.
  public var muscle: WorkoutMuscle?

  public init(id: String, name: String, muscle: WorkoutMuscle? = nil) {
    self.id = id
    self.name = name
    self.muscle = muscle
  }

  private enum CodingKeys: String, CodingKey { case id, name, muscle }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id), name: c.workoutValue(.name, ""),
      muscle: try? c.decodeIfPresent(WorkoutMuscle.self, forKey: .muscle))
  }
}

public struct WorkoutProgramItem: Codable, Equatable, Identifiable, Sendable {
  public static let setRange = 1...10
  public static let repsRange = 1...99
  public static let restRange = 15...900
  public static let restStep = 15
  public static let defaultReps = 10
  /// What a new exercise rests between sets.
  public static let defaultRest = 180

  public let id: String
  public var exerciseID: String
  public var sets: Int
  public var reps: Int
  /// Rest after a set of this exercise, in seconds.
  public var restSeconds: Int

  public init(
    id: String, exerciseID: String, sets: Int, reps: Int = WorkoutProgramItem.defaultReps,
    restSeconds: Int = WorkoutProgramItem.defaultRest
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.sets = Self.clamp(sets, Self.setRange)
    self.reps = Self.clamp(reps, Self.repsRange)
    self.restSeconds = Self.clamp(restSeconds, Self.restRange)
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: c.workoutValue(.id, WorkoutID.make()), exerciseID: try c.decode(String.self, forKey: .exerciseID),
      sets: c.workoutValue(.sets, 3), reps: c.workoutValue(.reps, Self.defaultReps),
      restSeconds: c.workoutValue(.restSeconds, Self.defaultRest))
  }

  private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
  }
}

public struct WorkoutProgram: Codable, Equatable, Identifiable, Sendable {
  public static let nameLimit = 40
  /// How many colours a program card can have (the gradient palette of the cards).
  public static let colorCount = 6

  public let id: String
  public var name: String
  public var items: [WorkoutProgramItem]
  /// Index of the card gradient, `0..<colorCount`.
  public var colorIndex: Int

  public init(id: String, name: String, items: [WorkoutProgramItem] = [], colorIndex: Int = 0) {
    self.id = id
    self.name = name
    self.items = items
    self.colorIndex = min(max(colorIndex, 0), Self.colorCount - 1)
  }

  private enum CodingKeys: String, CodingKey { case id, name, items, colorIndex }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id), name: c.workoutValue(.name, ""),
      items: c.workoutLossy(WorkoutProgramItem.self, .items),
      colorIndex: c.workoutValue(.colorIndex, 0))
  }

  public var totalSets: Int { items.reduce(0) { $0 + $1.sets } }
  /// «≈ 35 мин»: about four minutes a set and three to get started.
  public var estimatedMinutes: Int { totalSets * 4 + 3 }
}

/// Programs and the owner's own exercises: the file `programs.json`.
public struct WorkoutLibrary: Codable, Equatable, Sendable {
  public static let version = 1

  public var customExercises: [WorkoutExercise]
  public var programs: [WorkoutProgram]

  public init(customExercises: [WorkoutExercise] = [], programs: [WorkoutProgram] = []) {
    self.customExercises = customExercises
    self.programs = programs
  }

  private enum CodingKeys: String, CodingKey { case version, customExercises, programs }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      customExercises: c.workoutLossy(WorkoutExercise.self, .customExercises),
      programs: c.workoutLossy(WorkoutProgram.self, .programs))
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(Self.version, forKey: .version)
    try c.encode(customExercises, forKey: .customExercises)
    try c.encode(programs, forKey: .programs)
  }
}

// MARK: - Results (history and «last time»)

public struct WorkoutResultSet: Codable, Equatable, Sendable {
  public var weight: Double
  public var reps: Int

  public init(weight: Double, reps: Int) {
    self.weight = weight
    self.reps = reps
  }
}

public struct WorkoutRecordExercise: Codable, Equatable, Identifiable, Sendable {
  public var id: String { exerciseID }
  public let exerciseID: String
  public var name: String
  public var sets: [WorkoutResultSet]

  public init(exerciseID: String, name: String, sets: [WorkoutResultSet]) {
    self.exerciseID = exerciseID
    self.name = name
    self.sets = sets
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      exerciseID: try c.decode(String.self, forKey: .exerciseID), name: c.workoutValue(.name, ""),
      sets: c.workoutLossy(WorkoutResultSet.self, .sets))
  }
}

/// One COMPLETED workout. History never changes when a program is edited afterwards.
public struct WorkoutRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var programID: String
  public var programName: String
  public var startedAt: Date
  public var endedAt: Date
  public var exercises: [WorkoutRecordExercise]

  public init(
    id: String, programID: String, programName: String, startedAt: Date, endedAt: Date,
    exercises: [WorkoutRecordExercise]
  ) {
    self.id = id
    self.programID = programID
    self.programName = programName
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.exercises = exercises
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let ended = try c.decode(Date.self, forKey: .endedAt)
    self.init(
      id: try c.decode(String.self, forKey: .id), programID: c.workoutValue(.programID, ""),
      programName: c.workoutValue(.programName, ""), startedAt: c.workoutValue(.startedAt, ended),
      endedAt: ended, exercises: c.workoutLossy(WorkoutRecordExercise.self, .exercises))
  }

  /// The real time the workout took, from the stored start to the moment it was finished.
  public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

  /// Total weight moved, kg × reps.
  public var volume: Double {
    exercises.reduce(0) { total, exercise in
      total + exercise.sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
  }
}

/// The file `history.json`.
public struct WorkoutHistory: Codable, Equatable, Sendable {
  public static let version = 1

  /// Newest first.
  public var records: [WorkoutRecord]

  public init(records: [WorkoutRecord] = []) { self.records = records }

  private enum CodingKeys: String, CodingKey { case version, records }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    records = c.workoutLossy(WorkoutRecord.self, .records)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(Self.version, forKey: .version)
    try c.encode(records, forKey: .records)
  }

  /// The last time THIS exercise was done in a completed workout, whichever program it was in.
  /// Matched by the stable exercise id only; unfinished sessions are not in the history at all.
  public func lastResult(exerciseID: String) -> WorkoutPrevious? {
    var best: (date: Date, sets: [WorkoutResultSet])?
    for record in records {
      guard let exercise = record.exercises.first(where: { $0.exerciseID == exerciseID && !$0.sets.isEmpty })
      else { continue }
      if best == nil || record.endedAt > best!.date { best = (record.endedAt, exercise.sets) }
    }
    return best.map { WorkoutPrevious(date: $0.date, sets: $0.sets) }
  }
}

/// What the exercise looked like the last time it was done.
public struct WorkoutPrevious: Codable, Equatable, Sendable {
  public var date: Date
  public var sets: [WorkoutResultSet]

  public init(date: Date, sets: [WorkoutResultSet]) {
    self.date = date
    self.sets = sets
  }

  /// The set to compare with: the same position, or nothing when it did not exist then.
  public func set(at index: Int) -> WorkoutResultSet? {
    sets.indices.contains(index) ? sets[index] : nil
  }
}

// MARK: - Active workout

/// One row of an active workout. The weight and reps are kept as typed text so a half-typed
/// «2,» is never lost; `edited` marks a weight the owner set for this set alone.
public struct WorkoutSet: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var weight: String
  public var reps: String
  public var done: Bool
  public var edited: Bool

  public init(id: String, weight: String = "", reps: String = "", done: Bool = false, edited: Bool = false) {
    self.id = id
    self.weight = weight
    self.reps = reps
    self.done = done
    self.edited = edited
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id), weight: c.workoutValue(.weight, ""),
      reps: c.workoutValue(.reps, ""), done: c.workoutValue(.done, false),
      edited: c.workoutValue(.edited, false))
  }
}

public struct WorkoutSessionItem: Codable, Equatable, Identifiable, Sendable {
  public static let maxSets = 12

  public let id: String
  public var exerciseID: String
  public var name: String
  public var previous: WorkoutPrevious?
  /// The weight typed in the leading set; new sets start with it.
  public var sharedWeight: String
  public var sets: [WorkoutSet]
  /// The rest after a set, copied from the program when the workout starts.
  public var restSeconds: Int

  public init(
    id: String, exerciseID: String, name: String, previous: WorkoutPrevious?,
    sharedWeight: String = "", sets: [WorkoutSet], restSeconds: Int = WorkoutProgramItem.defaultRest
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.name = name
    self.previous = previous
    self.sharedWeight = sharedWeight
    self.sets = sets
    self.restSeconds = restSeconds
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id), exerciseID: try c.decode(String.self, forKey: .exerciseID),
      name: c.workoutValue(.name, ""), previous: try? c.decodeIfPresent(WorkoutPrevious.self, forKey: .previous),
      sharedWeight: c.workoutValue(.sharedWeight, ""), sets: c.workoutLossy(WorkoutSet.self, .sets),
      restSeconds: c.workoutValue(.restSeconds, WorkoutProgramItem.defaultRest))
  }

  public var doneCount: Int { sets.filter(\.done).count }
}

/// A SNAPSHOT of a program taken when the workout starts: editing the program afterwards never
/// reorders or changes a workout that is already running.
public struct WorkoutSession: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var programID: String
  public var programName: String
  /// A stored timestamp, not a counter: the elapsed time survives a relaunch.
  public var startedAt: Date
  public var items: [WorkoutSessionItem]

  public init(
    id: String, programID: String, programName: String, startedAt: Date, items: [WorkoutSessionItem]
  ) {
    self.id = id
    self.programID = programID
    self.programName = programName
    self.startedAt = startedAt
    self.items = items
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id), programID: c.workoutValue(.programID, ""),
      programName: c.workoutValue(.programName, ""), startedAt: try c.decode(Date.self, forKey: .startedAt),
      items: c.workoutLossy(WorkoutSessionItem.self, .items))
  }

  public var totalSets: Int { items.reduce(0) { $0 + $1.sets.count } }
  public var doneSets: Int { items.reduce(0) { $0 + $1.doneCount } }
}

/// The file `session.json`: the unfinished workout and its rest timer, written on every change
/// so the app can pick it up again after it was closed.
public struct WorkoutActiveState: Codable, Equatable, Sendable {
  public static let version = 1

  public var session: WorkoutSession?
  public var rest: RestTimer

  public init(session: WorkoutSession? = nil, rest: RestTimer = RestTimer()) {
    self.session = session
    self.rest = rest
  }

  private enum CodingKeys: String, CodingKey { case version, session, rest }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    session = try? c.decodeIfPresent(WorkoutSession.self, forKey: .session)
    rest = c.workoutValue(.rest, RestTimer())
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(Self.version, forKey: .version)
    try c.encodeIfPresent(session, forKey: .session)
    try c.encode(rest, forKey: .rest)
  }
}
