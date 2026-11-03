import Foundation

// Background sync of «Тренировки» with the server. Local-first: the app always reads and writes
// its own files; this file holds the PURE rules (state, reconcile, merge) and the engine that
// drives a `WorkoutSyncRemote`. The active workout and the rest timer are never synced.

// MARK: - JSON

/// Any JSON value; the `data` of a server document.
public enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let v) = self { return v }
    return nil
  }
  public var stringValue: String? {
    if case .string(let v) = self { return v }
    return nil
  }
  public var numberValue: Double? {
    if case .number(let v) = self { return v }
    return nil
  }

  /// The value of any Encodable, normalised exactly like a server round trip.
  public static func encoding<T: Encodable>(_ value: T) -> JSONValue? {
    guard let data = try? WorkoutCoding.encoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  public func decoded<T: Decodable>(_ type: T.Type) -> T? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return try? WorkoutCoding.decoder().decode(T.self, from: data)
  }
}

// MARK: - Documents and the remote

public enum WorkoutDocKind: String, Codable, Sendable, CaseIterable {
  case programs, sessions
}

public struct WorkoutDoc: Codable, Equatable, Sendable {
  public let id: String
  public let updatedAt: String
  public let data: JSONValue
  public init(id: String, updatedAt: String, data: JSONValue) {
    self.id = id
    self.updatedAt = updatedAt
    self.data = data
  }
}

public struct WorkoutServerSnapshot: Codable, Equatable, Sendable {
  public let programs: [WorkoutDoc]
  public let sessions: [WorkoutDoc]
  public init(programs: [WorkoutDoc], sessions: [WorkoutDoc]) {
    self.programs = programs
    self.sessions = sessions
  }
}

public protocol WorkoutSyncRemote: Sendable {
  func fetchWorkouts() async throws -> WorkoutServerSnapshot
  func putWorkoutDoc(kind: WorkoutDocKind, id: String, data: JSONValue, expectedUpdatedAt: String?)
    async throws -> WorkoutDoc
  func deleteWorkoutDoc(kind: WorkoutDocKind, id: String, expectedUpdatedAt: String) async throws
}

public enum WorkoutSyncRules {
  /// The server accepts 1–64 characters of letters, digits, `_` and `-`.
  public static func isValidID(_ id: String) -> Bool {
    guard (1...64).contains(id.utf8.count) else { return false }
    return id.utf8.allSatisfy {
      ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45
        || $0 == 95
    }
  }
}

// MARK: - State

public struct WorkoutSyncEntry: Codable, Equatable, Sendable {
  public var id: String
  /// The server version this entry was last known at; `nil` until it is created there.
  public var serverUpdatedAt: String?
  /// The last known content: the local edit while `dirty`, otherwise the server's.
  public var data: JSONValue
  public var dirty: Bool
  /// A tombstone: deleted locally, kept until the server DELETE succeeds.
  public var deleted: Bool

  public init(
    id: String, serverUpdatedAt: String?, data: JSONValue, dirty: Bool, deleted: Bool = false
  ) {
    self.id = id
    self.serverUpdatedAt = serverUpdatedAt
    self.data = data
    self.dirty = dirty
    self.deleted = deleted
  }
}

public struct WorkoutSyncState: Codable, Equatable, Sendable {
  public static let version = 1

  /// The server this state belongs to; another server starts from scratch.
  public var serverKey: String
  public var programs: [String: WorkoutSyncEntry] = [:]
  public var sessions: [String: WorkoutSyncEntry] = [:]

  public init(serverKey: String) { self.serverKey = serverKey }

  public subscript(kind: WorkoutDocKind) -> [String: WorkoutSyncEntry] {
    get { kind == .programs ? programs : sessions }
    set {
      if kind == .programs { programs = newValue } else { sessions = newValue }
    }
  }

  /// Live (not deleted) content by id: what the local files should hold.
  public func view(_ kind: WorkoutDocKind) -> [String: JSONValue] {
    self[kind].filter { !$0.value.deleted }.mapValues(\.data)
  }

  public var hasPending: Bool {
    WorkoutDocKind.allCases.contains { kind in self[kind].values.contains { $0.dirty } }
  }

  /// Takes the local files as they are now: edits become dirty, new docs are added, vanished
  /// docs become tombstones (or are dropped if the server never saw them).
  public mutating func reconcile(local: [WorkoutDocKind: [String: JSONValue]]) {
    for kind in WorkoutDocKind.allCases {
      let current = local[kind] ?? [:]
      var entries = self[kind]
      for (id, var entry) in entries where current[id] == nil && !entry.deleted {
        if entry.serverUpdatedAt == nil {
          entries[id] = nil
        } else {
          entry.deleted = true
          entry.dirty = true
          entries[id] = entry
        }
      }
      for (id, data) in current {
        if var entry = entries[id] {
          if entry.deleted {
            entry.deleted = false
            entry.data = data
            entry.dirty = true
            entries[id] = entry
          } else if entry.data != data {
            entry.data = data
            entry.dirty = true
            entries[id] = entry
          }
        } else {
          entries[id] = WorkoutSyncEntry(
            id: id, serverUpdatedAt: nil, data: data, dirty: true)
        }
      }
      self[kind] = entries
    }
  }

  /// Applies a server snapshot. A clean local doc is replaced when the server version differs;
  /// new server docs are added; dirty docs and tombstones are never overwritten (this device
  /// wins); clean docs missing on the server were deleted elsewhere and are removed.
  public mutating func merge(server: WorkoutServerSnapshot) {
    for kind in WorkoutDocKind.allCases {
      let docs = kind == .programs ? server.programs : server.sessions
      var entries = self[kind]
      var seen = Set<String>()
      for doc in docs {
        seen.insert(doc.id)
        if var entry = entries[doc.id] {
          if entry.dirty || entry.deleted { continue }
          if entry.serverUpdatedAt != doc.updatedAt {
            entry.serverUpdatedAt = doc.updatedAt
            entry.data = doc.data
            entries[doc.id] = entry
          }
        } else {
          entries[doc.id] = WorkoutSyncEntry(
            id: doc.id, serverUpdatedAt: doc.updatedAt, data: doc.data, dirty: false)
        }
      }
      for (id, entry) in entries where !seen.contains(id) && !entry.dirty && !entry.deleted {
        entries[id] = nil
      }
      self[kind] = entries
    }
  }

  /// What a finished sync changed in the local files, minus anything the owner edited while it
  /// ran (those edits win). `accepts` lets the caller refuse content it cannot read; a refused
  /// inbound doc is dropped from the state too, so it is never mistaken for a local deletion.
  /// In `changes`, a `nil` value means "remove this doc locally".
  public static func integrate(
    before: WorkoutSyncState, after: WorkoutSyncState,
    localNow: [WorkoutDocKind: [String: JSONValue]],
    accepts: (WorkoutDocKind, String, JSONValue) -> Bool = { _, _, _ in true }
  ) -> (state: WorkoutSyncState, changes: [WorkoutDocKind: [String: JSONValue?]]) {
    var state = after
    var changes: [WorkoutDocKind: [String: JSONValue?]] = [:]
    var local = localNow
    for kind in WorkoutDocKind.allCases {
      let was = before.view(kind)
      let now = after.view(kind)
      var kindChanges: [String: JSONValue?] = [:]
      for id in Set(was.keys).union(now.keys) where was[id] != now[id] {
        guard (localNow[kind] ?? [:])[id] == was[id] else { continue }  // edited meanwhile
        if let value = now[id], !accepts(kind, id, value) {
          state[kind][id] = before[kind][id]
          continue
        }
        kindChanges[id] = .some(now[id])
        local[kind, default: [:]][id] = now[id]
      }
      changes[kind] = kindChanges
    }
    state.reconcile(local: local)
    return (state, changes)
  }
}

// MARK: - Engine

public struct WorkoutSyncOutcome: Sendable {
  public var state: WorkoutSyncState
  /// The first problem met; `nil` when everything went through.
  public var failure: (any Error)?
  /// The server has no workout sync yet (GET answered 404/405/500/501); nothing was pushed.
  public var unsupported = false
}

public enum WorkoutSyncEngine {
  /// One pass: push edits, push deletions, then pull and merge. Progress is kept even when a
  /// later step fails. Per-document client errors (4xx) skip that doc; anything else stops.
  public static func run(state initial: WorkoutSyncState, remote: any WorkoutSyncRemote) async
    -> WorkoutSyncOutcome
  {
    var state = initial
    var failure: (any Error)?
    // Probe first: a server without the routes (not deployed yet) must stay untouched and quiet.
    do {
      _ = try await remote.fetchWorkouts()
    } catch let error as APIError where WorkoutSyncEngine.isUnsupported(error) {
      return WorkoutSyncOutcome(state: state, failure: nil, unsupported: true)
    } catch {
      return WorkoutSyncOutcome(state: state, failure: error)
    }
    do {
      for kind in WorkoutDocKind.allCases {
        for id in state[kind].keys.sorted() {
          guard let entry = state[kind][id], entry.dirty else { continue }
          do {
            if entry.deleted {
              try await pushDelete(kind, entry, remote: remote, state: &state)
            } else {
              try await pushEdit(kind, entry, remote: remote, state: &state)
            }
          } catch let error as APIError where isSkippable(error) {
            if failure == nil { failure = error }
          }
        }
      }
      let snapshot = try await remote.fetchWorkouts()
      state.merge(server: snapshot)
    } catch {
      if failure == nil { failure = error }
    }
    return WorkoutSyncOutcome(state: state, failure: failure)
  }

  /// Route missing / not implemented / tables not migrated yet.
  public static func isUnsupported(_ error: APIError) -> Bool {
    [404, 405, 500, 501].contains(error.status)
  }

  private static func isSkippable(_ error: APIError) -> Bool {
    (400..<500).contains(error.status) && ![401, 408, 429].contains(error.status)
  }

  private static func pushEdit(
    _ kind: WorkoutDocKind, _ entry: WorkoutSyncEntry, remote: any WorkoutSyncRemote,
    state: inout WorkoutSyncState
  ) async throws {
    var expected = entry.serverUpdatedAt
    var retried = false
    while true {
      do {
        let doc = try await remote.putWorkoutDoc(
          kind: kind, id: entry.id, data: entry.data, expectedUpdatedAt: expected)
        state[kind][entry.id]?.serverUpdatedAt = doc.updatedAt
        state[kind][entry.id]?.dirty = false
        return
      } catch let error as APIError where (error.isConflict || error.status == 404) && !retried {
        // This device's edit wins: retry once against whatever the server holds now
        // (`nil` creates the doc again if it is gone).
        retried = true
        expected = error.currentUpdatedAt
      }
    }
  }

  private static func pushDelete(
    _ kind: WorkoutDocKind, _ entry: WorkoutSyncEntry, remote: any WorkoutSyncRemote,
    state: inout WorkoutSyncState
  ) async throws {
    guard var expected = entry.serverUpdatedAt else {
      state[kind][entry.id] = nil
      return
    }
    var retried = false
    while true {
      do {
        try await remote.deleteWorkoutDoc(kind: kind, id: entry.id, expectedUpdatedAt: expected)
        state[kind][entry.id] = nil
        return
      } catch let error as APIError where error.status == 404 {
        state[kind][entry.id] = nil
        return
      } catch let error as APIError where error.isConflict && !retried {
        guard let current = error.currentUpdatedAt else { throw error }
        retried = true
        expected = current
      }
    }
  }
}
