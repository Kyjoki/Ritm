import Foundation

/// What the server's documents turn into on this iPhone.
public struct WorkoutSyncApplied: Equatable, Sendable {
  public var library: WorkoutLibrary
  public var history: WorkoutHistory
  public var bests: WorkoutBests
  public var settings: WorkoutSettings
}

/// Maps the native programs, finished workouts, records and settings to server documents and back.
///
/// - program doc: the Codable `WorkoutProgram` plus `order` (its place in the list) and
///   `exercises` (the owner's own exercises it uses, so another device can show their names);
/// - session doc: the Codable `WorkoutRecord`;
/// - record doc: the Codable `WorkoutBest` (id `rec-<exercise>`, `deleted` for a removed record);
/// - settings doc: the Codable `WorkoutSettings` under the single id `workouts`; absent while
///   everything is at its default.
/// Ids are the native UUIDs, which already satisfy the server rule; anything that does not is
/// left out of the sync and stays on this iPhone only.
public enum WorkoutSyncCodec {
  public static func documents(
    library: WorkoutLibrary, history: WorkoutHistory, bests: WorkoutBests = WorkoutBests(),
    settings: WorkoutSettings = WorkoutSettings()
  ) -> [WorkoutDocKind: [String: JSONValue]] {
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
    var records: [String: JSONValue] = [:]
    for best in bests.items where WorkoutSyncRules.isValidID(best.id) {
      if let value = JSONValue.encoding(best) { records[best.id] = value }
    }
    var settingsDocs: [String: JSONValue] = [:]
    if !settings.isDefault, let value = JSONValue.encoding(settings) {
      settingsDocs[WorkoutSettings.docID] = value
    }
    return [
      .programs: programs, .sessions: sessions, .records: records, .settings: settingsDocs,
    ]
  }

  /// Whether the doc can be turned back into a native model (used to refuse unreadable docs).
  public static func isReadable(kind: WorkoutDocKind, id: String, data: JSONValue) -> Bool {
    switch kind {
    case .programs: return program(id: id, data: data) != nil
    case .sessions: return record(id: id, data: data) != nil
    case .records: return best(data: data) != nil
    case .settings: return id == WorkoutSettings.docID && data.decoded(WorkoutSettings.self) != nil
    }
  }

  static func program(id: String, data: JSONValue) -> WorkoutProgram? {
    guard case .object(var object) = data else { return nil }
    object["id"] = .string(id)
    return JSONValue.object(object).decoded(WorkoutProgram.self)
  }

  /// A program doc that carries `muscle` for an exercise this iPhone already knows is the newer
  /// word on its group (`null` clears it); an exercise without the key is from an older build.
  private static func applyGroups(of data: JSONValue, to library: inout WorkoutLibrary) {
    guard case .array(let items)? = data.objectValue?["exercises"] else { return }
    for item in items {
      guard case .object(let fields) = item, case .string(let id)? = fields["id"],
        let raw = fields["muscle"]
      else { continue }
      if raw == .null {
        library.setMuscle(nil, ofExercise: id)
      } else if let group = raw.decoded(WorkoutMuscle.self) {
        library.setMuscle(group, ofExercise: id)
      }
    }
  }

  static func record(id: String, data: JSONValue) -> WorkoutRecord? {
    guard case .object(var object) = data else { return nil }
    object["id"] = .string(id)
    return JSONValue.object(object).decoded(WorkoutRecord.self)
  }

  static func best(data: JSONValue) -> WorkoutBest? {
    data.decoded(WorkoutBest.self)
  }

  /// Applies inbound changes (`nil` removes) to the local files. Programs end up ordered by
  /// `order` (ties by id); history stays newest first. Unreadable docs are skipped.
  public static func apply(
    _ changes: [WorkoutDocKind: [String: JSONValue?]], library: WorkoutLibrary,
    history: WorkoutHistory, bests: WorkoutBests = WorkoutBests(),
    settings: WorkoutSettings = WorkoutSettings()
  ) -> WorkoutSyncApplied {
    var library = library
    var history = history
    var bests = bests
    var settings = settings

    if let inbound = changes[.programs], !inbound.isEmpty {
      var ranked: [(order: Double, program: WorkoutProgram)] = library.programs.enumerated()
        .map { (Double($0.offset), $0.element) }
      for (id, change) in inbound {
        ranked.removeAll { $0.program.id == id }
        guard let value = change, let program = program(id: id, data: value) else { continue }
        ranked.append((value.objectValue?["order"]?.numberValue ?? .greatestFiniteMagnitude, program))
        let extra = value.objectValue?["exercises"]?.decoded([WorkoutExercise].self) ?? []
        applyGroups(of: value, to: &library)
        let known = Set(library.customExercises.map(\.id))
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

    if let inbound = changes[.records], !inbound.isEmpty {
      for (id, change) in inbound {
        bests.items.removeAll { $0.id == id }
        if let value = change, let best = best(data: value), best.id == id { bests.items.append(best) }
      }
      bests.items.sort { $0.id < $1.id }
    }

    if let inbound = changes[.settings], let change = inbound[WorkoutSettings.docID] {
      settings = change?.decoded(WorkoutSettings.self) ?? WorkoutSettings()
    }
    return WorkoutSyncApplied(library: library, history: history, bests: bests, settings: settings)
  }
}
