import Foundation
import Observation
import RitmCore

/// Keeps the workout log in step with the server in the background.
///
/// The files on this iPhone stay the source the UI reads, so everything works offline and
/// instantly; this only mirrors them (see `WorkoutSyncEngine` for the rules). One pass runs at a
/// time. A failed pass is retried silently with growing delays; `failing` turns on only after
/// several failures in a row, for a small status line. Signed out means no sync at all.
@MainActor @Observable
final class WorkoutSyncCoordinator {
  struct Link {
    let remote: any WorkoutSyncRemote
    /// Identifies the server and account; another one starts a fresh sync state.
    let serverKey: String
  }

  /// True after repeated failures; cleared by the next successful pass.
  private(set) var failing = false

  @ObservationIgnored private var workouts: WorkoutStore?
  @ObservationIgnored private var currentLink: (() -> Link?)?
  @ObservationIgnored private var state: WorkoutSyncState?
  @ObservationIgnored private var running = false
  @ObservationIgnored private var rerun = false
  @ObservationIgnored private var failures = 0
  @ObservationIgnored private var unsupportedUntil: Date?
  @ObservationIgnored private var debounce: Task<Void, Never>?
  @ObservationIgnored private var retry: Task<Void, Never>?

  private static let debounceDelay: Duration = .seconds(2)
  private static let persistentAfter = 3
  private static let maxBackoff = 300.0
  /// While the server has no workout sync, look again this rarely (and on start/foreground).
  private static let unsupportedRecheck = 30.0 * 60

  func configure(workouts: WorkoutStore, link: @escaping () -> Link?) {
    self.workouts = workouts
    currentLink = link
    workouts.onSyncableChange = { [weak self] in self?.localChanged() }
  }

  /// A local edit: sync shortly after the last one.
  func localChanged() {
    guard currentLink?() != nil else { return }
    debounce?.cancel()
    debounce = Task { [weak self] in
      try? await Task.sleep(for: Self.debounceDelay)
      guard !Task.isCancelled else { return }
      await self?.syncNow(force: false)
    }
  }

  /// App start, foreground: sync without waiting for it.
  func request() { Task { await syncNow() } }

  /// Pull-to-refresh: returns when the pass is over. Never throws. Local edits pass
  /// `force: false` so they do not hammer a server that has no workout sync yet.
  func syncNow(force: Bool = true) async {
    guard !running else {
      rerun = true
      return
    }
    guard currentLink?() != nil else { return }
    if let until = unsupportedUntil, !force, Date() < until { return }
    running = true
    defer { running = false }
    repeat {
      rerun = false
      await pass()
    } while rerun && failures == 0
  }

  /// Sign-out: forget the sync bookkeeping (the local log stays) so another account starts clean.
  func reset() {
    debounce?.cancel()
    retry?.cancel()
    state = nil
    unsupportedUntil = nil
    failures = 0
    failing = false
    if let url = stateURL { try? FileManager.default.removeItem(at: url) }
  }

  // MARK: - One pass

  private func pass() async {
    guard let workouts, let link = currentLink?() else { return }
    var before = loadState(serverKey: link.serverKey)
    before.reconcile(local: workouts.syncDocuments())
    let outcome = await WorkoutSyncEngine.run(state: before, remote: link.remote)
    // Signed out or switched server while the pass ran: drop its result.
    guard currentLink?()?.serverKey == link.serverKey else { return }
    let merged = WorkoutSyncState.integrate(
      before: before, after: outcome.state, localNow: workouts.syncDocuments(),
      accepts: { WorkoutSyncCodec.isReadable(kind: $0, id: $1, data: $2) })
    workouts.applySyncChanges(merged.changes)
    state = merged.state
    persist()
    if outcome.unsupported {
      markUnsupported()
      return
    }
    unsupportedUntil = nil
    finish(outcome.failure, hasPending: merged.state.hasPending)
  }

  /// Quiet state: no status line, no retries beyond one look every 30 minutes.
  private func markUnsupported() {
    failures = 0
    failing = false
    unsupportedUntil = Date().addingTimeInterval(Self.unsupportedRecheck)
    retry?.cancel()
    retry = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.unsupportedRecheck))
      guard !Task.isCancelled else { return }
      await self?.syncNow()
    }
  }

  private func finish(_ failure: (any Error)?, hasPending: Bool) {
    guard let failure else {
      failures = 0
      failing = false
      retry?.cancel()
      if hasPending { rerun = true }  // edits made while the pass ran
      return
    }
    if failure is CancellationError { return }
    if let api = failure as? APIError, api.requiresAuthentication { return }
    failures += 1
    failing = failures >= Self.persistentAfter
    let delay = min(5 * pow(3, Double(failures - 1)), Self.maxBackoff)
    retry?.cancel()
    retry = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      await self?.syncNow()
    }
  }

  // MARK: - Bookkeeping file

  private var stateURL: URL? { workouts?.syncDirectory.appendingPathComponent("sync.json") }

  private func loadState(serverKey: String) -> WorkoutSyncState {
    if let state, state.serverKey == serverKey { return state }
    if let url = stateURL, let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode(WorkoutSyncState.self, from: data),
      saved.serverKey == serverKey
    {
      state = saved
      return saved
    }
    return WorkoutSyncState(serverKey: serverKey)
  }

  private func persist() {
    guard let state, let url = stateURL, let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
