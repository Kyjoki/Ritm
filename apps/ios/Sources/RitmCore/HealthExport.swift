import Foundation

// «Здоровье»: the Apple Health export of a COMPLETED workout, as pure values (no HealthKit here).
//
// The app maps `HealthWorkoutPayload` to one HKWorkout. Only the activity kind, the start, the end
// and the active duration leave the app: no calories, no weights, no exercise details. The ledger
// is Codable and persisted, so a relaunch never writes the same workout twice, and a failed or
// uncertain write never loses the workout itself (it stays in the history untouched).

public enum HealthActivityKind: String, Codable, Equatable, Sendable {
  /// The app maps this to HKWorkoutActivityType.traditionalStrengthTraining.
  case traditionalStrengthTraining
}

public enum HealthExportFailure: String, Codable, Equatable, Sendable {
  case notAuthorized, healthUnavailable, dataProtected, saveFailed, unknown
}

public enum HealthExportStatus: Codable, Equatable, Sendable {
  case notRequested
  case pending
  case saving
  case saved(healthKitUUID: String?, at: Date)
  case failed(reason: HealthExportFailure, retryable: Bool, at: Date)
  /// A write whose outcome is unknown (the app died or the call never answered).
  case uncertain(at: Date)
}

/// What is written to Health for one workout.
public struct HealthWorkoutPayload: Codable, Equatable, Sendable {
  public static let syncIdentifierPrefix = "app.ritm.workout."
  public static let currentSyncVersion = 1

  public let workoutID: String
  public let activity: HealthActivityKind
  public let start: Date
  public let end: Date
  /// Time actually spent training: end - start without paused time, never negative.
  public let activeDuration: TimeInterval
  /// Stable per workout: Health finds a sample by it instead of duplicating.
  public let syncIdentifier: String
  public let syncVersion: Int

  public init(
    workoutID: String, activity: HealthActivityKind = .traditionalStrengthTraining, start: Date,
    end: Date, activeDuration: TimeInterval, syncVersion: Int = HealthWorkoutPayload.currentSyncVersion
  ) {
    self.workoutID = workoutID
    self.activity = activity
    self.start = start
    self.end = end
    self.activeDuration = activeDuration
    self.syncIdentifier = Self.syncIdentifier(for: workoutID)
    self.syncVersion = syncVersion
  }

  public static func syncIdentifier(for workoutID: String) -> String { syncIdentifierPrefix + workoutID }

  /// `nil` for a record that cannot be a workout (empty id, end not after start). `pausedSeconds`
  /// is the paused time the app tracked; today a workout has no pause of its own, so it is 0.
  public init?(record: WorkoutRecord, pausedSeconds: TimeInterval = 0) {
    guard !record.id.isEmpty, record.endedAt > record.startedAt else { return nil }
    let total = record.endedAt.timeIntervalSince(record.startedAt)
    let paused = pausedSeconds.isFinite ? min(max(0, pausedSeconds), total) : 0
    self.init(
      workoutID: record.id, start: record.startedAt, end: record.endedAt,
      activeDuration: max(0, total - paused))
  }
}

/// The export state of one workout, keyed by the local workout id.
public struct HealthExportRecord: Codable, Equatable, Identifiable, Sendable {
  public var id: String { workoutID }
  public let workoutID: String
  public let payload: HealthWorkoutPayload
  public var status: HealthExportStatus
  public var attempts: Int
  /// The outcome of the last finished attempt (saved, failed or uncertain).
  public var lastResult: HealthExportStatus?
  public let enqueuedAt: Date

  public init(
    payload: HealthWorkoutPayload, status: HealthExportStatus = .pending, attempts: Int = 0,
    lastResult: HealthExportStatus? = nil, enqueuedAt: Date
  ) {
    self.workoutID = payload.workoutID
    self.payload = payload
    self.status = status
    self.attempts = attempts
    self.lastResult = lastResult
    self.enqueuedAt = enqueuedAt
  }
}

/// All export records. Every change returns a new ledger; the old value is never touched.
public struct HealthExportLedger: Codable, Equatable, Sendable {
  public static let version = 1

  public private(set) var records: [HealthExportRecord]

  public init(records: [HealthExportRecord] = []) { self.records = records }

  private enum CodingKeys: String, CodingKey { case version, records }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    records = c.workoutLossy(HealthExportRecord.self, .records)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(Self.version, forKey: .version)
    try c.encode(records, forKey: .records)
  }

  public func record(_ workoutID: String) -> HealthExportRecord? {
    records.first { $0.workoutID == workoutID }
  }

  public func status(of workoutID: String) -> HealthExportStatus {
    record(workoutID)?.status ?? .notRequested
  }

  // MARK: Queue

  /// Idempotent by workout id: a second enqueue of the same workout changes nothing.
  public func enqueue(_ payload: HealthWorkoutPayload, now: Date) -> HealthExportLedger {
    guard record(payload.workoutID) == nil else { return self }
    return HealthExportLedger(records: records + [HealthExportRecord(payload: payload, enqueuedAt: now)])
  }

  /// A finished workout. Cancelled or unfinished ones have no record and are never exported.
  public func enqueue(_ record: WorkoutRecord, pausedSeconds: TimeInterval = 0, now: Date) -> HealthExportLedger {
    guard let payload = HealthWorkoutPayload(record: record, pausedSeconds: pausedSeconds) else { return self }
    return enqueue(payload, now: now)
  }

  /// The workout a session produces when finished; a session with nothing ticked exports nothing.
  public func enqueue(
    finishing session: WorkoutSession, at end: Date, pausedSeconds: TimeInterval = 0
  ) -> HealthExportLedger {
    guard let record = session.finished(at: end) else { return self }
    return enqueue(record, pausedSeconds: pausedSeconds, now: end)
  }

  // MARK: Attempts

  /// Starts a write. Refused (payload `nil`, ledger unchanged) while another write of the same
  /// workout runs, after it is saved, while an uncertain write is unresolved, or after a failure
  /// that cannot be retried.
  public func begin(_ workoutID: String) -> (ledger: HealthExportLedger, payload: HealthWorkoutPayload?) {
    guard let current = record(workoutID), current.canBegin else { return (self, nil) }
    let next = updating(workoutID) {
      $0.status = .saving
      $0.attempts += 1
    }
    return (next, current.payload)
  }

  public func markSaved(_ workoutID: String, healthKitUUID: String?, at date: Date) -> HealthExportLedger {
    finishing(workoutID, .saved(healthKitUUID: healthKitUUID, at: date))
  }

  public func markFailed(
    _ workoutID: String, reason: HealthExportFailure, retryable: Bool, at date: Date
  ) -> HealthExportLedger {
    finishing(workoutID, .failed(reason: reason, retryable: retryable, at: date))
  }

  public func markUncertain(_ workoutID: String, at date: Date) -> HealthExportLedger {
    finishing(workoutID, .uncertain(at: date))
  }

  /// An uncertain write is resolved by looking for a sample with the same sync identifier, never
  /// by writing again: found means saved, not found means pending again (safe to write once more).
  public func resolveUncertain(
    _ workoutID: String, foundExistingByIdentifier found: Bool, healthKitUUID: String? = nil, at date: Date
  ) -> HealthExportLedger {
    guard case .uncertain = record(workoutID)?.status else { return self }
    return updating(workoutID) {
      if found {
        let saved = HealthExportStatus.saved(healthKitUUID: healthKitUUID, at: date)
        $0.status = saved
        $0.lastResult = saved
      } else {
        $0.status = .pending
      }
    }
  }

  /// After a relaunch a `saving` record means the app died during the write: its outcome is
  /// unknown, so it becomes uncertain (and is resolved by identifier, not rewritten blindly).
  public func recoveringAfterLaunch(at date: Date) -> HealthExportLedger {
    HealthExportLedger(
      records: records.map { item in
        guard item.status == .saving else { return item }
        var copy = item
        copy.status = .uncertain(at: date)
        copy.lastResult = copy.status
        return copy
      })
  }

  /// Workouts that may be written now: waiting, or failed in a way worth retrying. Oldest first.
  public func retryable() -> [HealthExportRecord] {
    records.filter(\.canBegin).sorted { ($0.enqueuedAt, $0.workoutID) < ($1.enqueuedAt, $1.workoutID) }
  }

  /// Uncertain ones, to be resolved by a lookup of their sync identifier.
  public func uncertain() -> [HealthExportRecord] {
    records.filter { if case .uncertain = $0.status { return true } else { return false } }
  }

  // MARK: Helpers

  private func finishing(_ workoutID: String, _ status: HealthExportStatus) -> HealthExportLedger {
    guard record(workoutID)?.status == .saving else { return self }
    return updating(workoutID) {
      $0.status = status
      $0.lastResult = status
    }
  }

  private func updating(_ workoutID: String, _ change: (inout HealthExportRecord) -> Void) -> HealthExportLedger {
    HealthExportLedger(
      records: records.map { item in
        guard item.workoutID == workoutID else { return item }
        var copy = item
        change(&copy)
        return copy
      })
  }
}

extension HealthExportRecord {
  /// Waiting, or failed in a way worth retrying.
  fileprivate var canBegin: Bool {
    switch status {
    case .pending, .failed(_, true, _): return true
    default: return false
    }
  }
}
