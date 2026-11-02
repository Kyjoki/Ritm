import Foundation

// «Здоровье»: the logic that drives `HealthExportLedger` against a writer, with no HealthKit in it.
// The app supplies a HealthKit-backed `HealthWorkoutWriting`; tests supply a fake.
//
// Rules this type guarantees:
// - the workout is already in the Ritm journal before `exportIfEnabled` is called, and nothing
//   here can remove or block it: a denial or failure only changes the ledger;
// - only finished workouts are ever enqueued (a cancelled one never reaches this type);
// - `begin` is a synchronous lock on the main actor, so two concurrent calls make ONE write;
// - an unknown outcome is resolved by looking the sync identifier up, never by writing blindly.

/// What the app can say about WRITE access to workouts. Read access is never inferred.
public enum HealthShareStatus: Equatable, Sendable {
  case unavailable, notDetermined, allowed, denied
}

public enum HealthWriteError: Error, Equatable, Sendable {
  case failure(HealthExportFailure, retryable: Bool)
  /// The call ended without a clear answer (for example no saved workout came back).
  case outcomeUnknown
}

public protocol HealthWorkoutWriting: Sendable {
  /// Asks for permission to SHARE workouts only (no read types); returns the resulting status.
  func requestShareAuthorization() async -> HealthShareStatus
  /// Write status of workouts only.
  func shareStatus() async -> HealthShareStatus
  /// Writes one workout; returns the Health sample UUID when known.
  func save(_ payload: HealthWorkoutPayload) async throws -> String?
  /// The UUID of this app's own sample with that sync identifier, `nil` when there is none.
  func findExisting(syncIdentifier: String) async throws -> String?
}

/// Used where HealthKit does not exist: every export fails once, not retryably.
public struct HealthUnavailableWriter: HealthWorkoutWriting {
  public init() {}
  public func requestShareAuthorization() async -> HealthShareStatus { .unavailable }
  public func shareStatus() async -> HealthShareStatus { .unavailable }
  public func save(_ payload: HealthWorkoutPayload) async throws -> String? {
    throw HealthWriteError.failure(.healthUnavailable, retryable: false)
  }
  public func findExisting(syncIdentifier: String) async throws -> String? { nil }
}

@MainActor
public final class HealthExportCoordinator {
  public private(set) var ledger: HealthExportLedger {
    didSet {
      guard ledger != oldValue else { return }
      persist(ledger)
      onChange?()
    }
  }
  /// The owner's switch: new finished workouts are exported only while it is on.
  public var isEnabled: Bool
  public var onChange: (() -> Void)?

  private let writer: any HealthWorkoutWriting
  private let persist: (HealthExportLedger) -> Void
  private let now: () -> Date

  public init(
    writer: any HealthWorkoutWriting, ledger: HealthExportLedger = HealthExportLedger(),
    isEnabled: Bool = false, persist: @escaping (HealthExportLedger) -> Void = { _ in },
    now: @escaping () -> Date = { Date() }
  ) {
    self.writer = writer
    self.ledger = ledger
    self.isEnabled = isEnabled
    self.persist = persist
    self.now = now
  }

  // MARK: Authorization

  public func shareStatus() async -> HealthShareStatus { await writer.shareStatus() }

  /// Only ever called from a tap. After access is granted, writes that failed for lack of it
  /// are retried while the switch is on.
  @discardableResult
  public func connect() async -> HealthShareStatus {
    let status = await writer.requestShareAuthorization()
    if status == .allowed, isEnabled { await retryAllFailed(onlyReason: .notAuthorized) }
    return status
  }

  // MARK: Export

  /// Called AFTER the workout is durably saved in the journal. Does nothing while the switch is
  /// off or for a record that cannot be a workout.
  public func exportIfEnabled(_ record: WorkoutRecord) async {
    guard isEnabled else { return }
    ledger = ledger.enqueue(record, now: now())
    await run(record.id)
  }

  /// Relaunch: an interrupted write becomes uncertain and is resolved by lookup; workouts that
  /// were queued but never started are written once (only while the switch is on).
  public func reconcileOnLaunch() async {
    ledger = ledger.recoveringAfterLaunch(at: now())
    for item in ledger.uncertain() { await resolve(item.workoutID) }
    guard isEnabled else { return }
    for item in ledger.retryable() where item.status == .pending { await run(item.workoutID) }
  }

  /// The «Повторить» action for one workout.
  public func retry(_ workoutID: String) async {
    await resolve(workoutID)
    await run(workoutID)
  }

  public func retryAllFailed() async { await retryAllFailed(onlyReason: nil) }

  private func retryAllFailed(onlyReason: HealthExportFailure?) async {
    for item in ledger.records where needsAttention(item, reason: onlyReason) {
      await retry(item.workoutID)
    }
  }

  // MARK: Reading

  public func status(of workoutID: String) -> HealthExportStatus { ledger.status(of: workoutID) }

  /// Failed (retryable) or uncertain: the «Повторить» button is shown for these.
  public func canRetry(_ workoutID: String) -> Bool {
    guard let record = ledger.record(workoutID) else { return false }
    return needsAttention(record, reason: nil)
  }

  /// The record whose last finished attempt is the newest.
  public var lastAttempt: HealthExportRecord? {
    ledger.records.compactMap { record -> (HealthExportRecord, Date)? in
      guard let date = record.lastResult?.finishedAt else { return nil }
      return (record, date)
    }.max { $0.1 < $1.1 }?.0
  }

  /// Newest first, for a short list of recent exports.
  public func recent(limit: Int) -> [HealthExportRecord] {
    Array(ledger.records.sorted { ($0.enqueuedAt, $0.workoutID) > ($1.enqueuedAt, $1.workoutID) }.prefix(max(0, limit)))
  }

  // MARK: Steps

  private func needsAttention(_ record: HealthExportRecord, reason: HealthExportFailure?) -> Bool {
    switch record.status {
    case .failed(let why, let retryable, _): return retryable && (reason == nil || reason == why)
    case .uncertain: return reason == nil
    default: return false
    }
  }

  private func run(_ workoutID: String) async {
    let started = ledger.begin(workoutID)
    guard let payload = started.payload else { return }
    ledger = started.ledger
    switch await writer.shareStatus() {
    case .unavailable: fail(workoutID, .healthUnavailable, retryable: false)
    case .notDetermined, .denied: fail(workoutID, .notAuthorized, retryable: true)
    case .allowed: await write(payload)
    }
  }

  private func write(_ payload: HealthWorkoutPayload) async {
    let id = payload.workoutID
    do {
      let uuid = try await writer.save(payload)
      ledger = ledger.markSaved(id, healthKitUUID: uuid, at: now())
    } catch HealthWriteError.failure(let reason, let retryable) {
      fail(id, reason, retryable: retryable)
    } catch is CancellationError {
      ledger = ledger.markUncertain(id, at: now())
    } catch HealthWriteError.outcomeUnknown {
      ledger = ledger.markUncertain(id, at: now())
      await resolve(id)
    } catch {
      fail(id, .saveFailed, retryable: true)
    }
  }

  private func fail(_ workoutID: String, _ reason: HealthExportFailure, retryable: Bool) {
    ledger = ledger.markFailed(workoutID, reason: reason, retryable: retryable, at: now())
  }

  private func resolve(_ workoutID: String) async {
    guard case .uncertain = ledger.status(of: workoutID) else { return }
    do {
      let found = try await writer.findExisting(syncIdentifier: HealthWorkoutPayload.syncIdentifier(for: workoutID))
      ledger = ledger.resolveUncertain(
        workoutID, foundExistingByIdentifier: found != nil, healthKitUUID: found, at: now())
    } catch {
      // The lookup failed too: it stays uncertain and is tried again later.
    }
  }
}

extension HealthExportStatus {
  /// When a finished attempt ended; `nil` for states that are not an outcome.
  public var finishedAt: Date? {
    switch self {
    case .saved(_, let at), .failed(_, _, let at), .uncertain(let at): return at
    case .notRequested, .pending, .saving: return nil
    }
  }
}
