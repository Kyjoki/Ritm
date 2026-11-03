import Foundation

/// Maps the native programs and finished workouts to server documents and back.
///
/// - program doc: the Codable `WorkoutProgram` plus `order` (its place in the list) and
///   `exercises` (the owner's own exercises it uses, so another device can show their names);
/// - session doc: the Codable `WorkoutRecord`.
/// Ids are the native UUIDs, which already satisfy the server rule; anything that does not is
/// left out of the sync and stays on this iPhone only.
public enum WorkoutSyncCodec {
  public static func documents(library: WorkoutLibrary, history: WorkoutHistory)
    -> [WorkoutDocKind: [String: JSONValue]]
  {
    var programs: [String: JSONValue] = [:]
    for (index, program) in library.programs.enumerated()
    where WorkoutSyncRules.isValidID(program.id) {
      guard case .object(var object)? = JSONValue.encoding(program) else { continue }
      object["order"] = .number(Double(index))
      let used = Set(program.items.map(\.exerciseID))
      let custom = library.customExercises.filter { used.contains($0.id) }
      object["exercises"] = JSONValue.encoding(custom) ?? .array([])
      programs[program.id] = .object(object)
    }
    var sessions: [String: JSONValue] = [:]
    for record in history.records where WorkoutSyncRules.isValidID(record.id) {
      if let value = JSONValue.encoding(record) { sessions[record.id] = value }
    }
    return [.programs: programs, .sessions: sessions]
  }

  /// Whether the doc can be turned back into a native model (used to refuse unreadable docs).
  public static func isReadable(kind: WorkoutDocKind, id: String, data: JSONValue) -> Bool {
    switch kind {
    case .programs: return program(id: id, data: data) != nil
    case .sessions: return record(id: id, data: data) != nil
    }
  }

  static func program(id: String, data: JSONValue) -> WorkoutProgram? {
    guard case .object(var object) = data else { return nil }
    object["id"] = .string(id)
    return JSONValue.object(object).decoded(WorkoutProgram.self)
  }

  static func record(id: String, data: JSONValue) -> WorkoutRecord? {
    guard case .object(var object) = data else { return nil }
    object["id"] = .string(id)
    return JSONValue.object(object).decoded(WorkoutRecord.self)
  }

  /// Applies inbound changes (`nil` removes) to the local files. Programs end up ordered by
  /// `order` (ties by id); history stays newest first. Unreadable docs are skipped.
  public static func apply(
    _ changes: [WorkoutDocKind: [String: JSONValue?]], library: WorkoutLibrary,
    history: WorkoutHistory
  ) -> (library: WorkoutLibrary, history: WorkoutHistory) {
    var library = library
    var history = history

    if let inbound = changes[.programs], !inbound.isEmpty {
      var ranked: [(order: Double, program: WorkoutProgram)] = library.programs.enumerated()
        .map { (Double($0.offset), $0.element) }
      for (id, change) in inbound {
        ranked.removeAll { $0.program.id == id }
        guard let value = change, let program = program(id: id, data: value) else { continue }
        ranked.append((value.objectValue?["order"]?.numberValue ?? .greatestFiniteMagnitude, program))
        let known = Set(library.customExercises.map(\.id))
        let extra = value.objectValue?["exercises"]?.decoded([WorkoutExercise].self) ?? []
        library.customExercises += extra.filter { !known.contains($0.id) }
        if !extra.isEmpty {
          var seen = Set<String>()
          library.customExercises = library.customExercises.filter { seen.insert($0.id).inserted }
        }
      }
      ranked.sort { ($0.order, $0.program.id) < ($1.order, $1.program.id) }
      library.programs = ranked.map(\.program)
    }

    if let inbound = changes[.sessions], !inbound.isEmpty {
      var records = history.records
      for (id, change) in inbound {
        records.removeAll { $0.id == id }
        if let value = change, let record = record(id: id, data: value) { records.append(record) }
      }
      records.sort { ($0.endedAt, $1.id) > ($1.endedAt, $0.id) }
      history = WorkoutHistory(records: records)
    }
    return (library, history)
  }
}
