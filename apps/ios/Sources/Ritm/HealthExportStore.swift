import Foundation
import Observation
import RitmCore

/// «Apple Здоровье»: the export of finished workouts, kept apart from the Ritm journal.
///
/// The ledger is JSON in Application Support (atomic, versioned, tolerant decoding), so a
/// relaunch never writes the same workout twice. The workout itself is already saved in
/// `WorkoutStore` before `exportIfEnabled` is called; a HealthKit denial or failure only changes
/// the ledger here and never touches the journal. Nothing is sent to the Ritm server.
@MainActor @Observable
final class HealthExportStore {
  private static let switchKey = "ritm.health.saveToHealth"

  private(set) var ledger = HealthExportLedger()
  /// Write status only, refreshed on demand. Read access is never inferred.
  private(set) var shareStatus = HealthShareStatus.notDetermined

  var saveToHealth: Bool {
    didSet {
      guard saveToHealth != oldValue else { return }
      UserDefaults.standard.set(saveToHealth, forKey: Self.switchKey)
      coordinator.isEnabled = saveToHealth
    }
  }

  @ObservationIgnored private let coordinator: HealthExportCoordinator
  @ObservationIgnored private let fileURL: URL

  init(
    writer: any HealthWorkoutWriting = makeHealthWriter(),
    fileURL: URL = HealthExportStore.defaultFileURL()
  ) {
    self.fileURL = fileURL
    let enabled = UserDefaults.standard.bool(forKey: Self.switchKey)
    saveToHealth = enabled
    let loaded = Self.load(fileURL)
    ledger = loaded
    coordinator = HealthExportCoordinator(
      writer: writer, ledger: loaded, isEnabled: enabled, persist: { Self.write($0, to: fileURL) })
    coordinator.onChange = { [weak self] in
      guard let self else { return }
      self.ledger = self.coordinator.ledger
    }
  }

  // MARK: Reading

  func status(of workoutID: String) -> HealthExportStatus { ledger.status(of: workoutID) }
  func canRetry(_ workoutID: String) -> Bool { coordinator.canRetry(workoutID) }
  var lastAttempt: HealthExportRecord? { _ = ledger; return coordinator.lastAttempt }
  func recent(limit: Int) -> [HealthExportRecord] { _ = ledger; return coordinator.recent(limit: limit) }
  var hasRetryable: Bool { _ = ledger; return ledger.records.contains { coordinator.canRetry($0.workoutID) } }

  // MARK: Actions

  func refreshStatus() async { shareStatus = await coordinator.shareStatus() }

  /// The «Подключить» tap: the only place that asks iOS for access.
  func connect() async { shareStatus = await coordinator.connect() }

  /// Called after the workout is already in the Ritm journal.
  func exportIfEnabled(_ record: WorkoutRecord) {
    guard saveToHealth else { return }
    Task { await coordinator.exportIfEnabled(record) }
  }

  func retry(_ workoutID: String) { Task { await coordinator.retry(workoutID) } }
  func retryAllFailed() { Task { await coordinator.retryAllFailed() } }

  func reconcileOnLaunch() {
    Task {
      await coordinator.reconcileOnLaunch()
      await refreshStatus()
    }
  }

  // MARK: File

  private static func defaultFileURL() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Ritm", isDirectory: true)
      .appendingPathComponent("health-export.json")
  }

  private static func load(_ url: URL) -> HealthExportLedger {
    guard let data = try? Data(contentsOf: url) else { return HealthExportLedger() }
    do {
      return try WorkoutCoding.decoder().decode(HealthExportLedger.self, from: data)
    } catch {
      // Not valid JSON: keep the bytes instead of overwriting them.
      let aside = url.appendingPathExtension("damaged")
      try? FileManager.default.removeItem(at: aside)
      try? FileManager.default.moveItem(at: url, to: aside)
      return HealthExportLedger()
    }
  }

  private static func write(_ ledger: HealthExportLedger, to url: URL) {
    // A failed write leaves the previous file; the next change writes again.
    guard let data = try? WorkoutCoding.encoder().encode(ledger) else { return }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
