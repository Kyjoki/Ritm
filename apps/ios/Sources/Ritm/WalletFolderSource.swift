import Foundation
import Observation
import RitmCore

/// The Files folder the owner picked for the Shortcuts «Транзакция» automation. Ritm only ever
/// reads `purchases.txt` from it (never writes or deletes). The folder is remembered as a
/// security-scoped bookmark in UserDefaults; the file's contents are not stored anywhere here.
@MainActor @Observable
final class WalletFolderSource {
  enum Status: Equatable {
    case notChosen
    /// Folder chosen, nothing wrong known yet.
    case ready
    case fileMissing
    /// iCloud has not delivered the file yet; the next read retries.
    case downloading
    /// The bookmark no longer opens the folder: the owner must pick it again.
    case needsRepick
    case failed(String)
  }

  /// What the last successful read of the file found.
  struct Summary: Codable, Equatable {
    var date: Date
    var added: Int
    var duplicates: Int
    var skipped: Int
    var overflow: Int
  }

  /// What a read returns to the store.
  enum Outcome {
    /// Nothing to do: no folder, a read already running, or the file did not change.
    case idle
    case contents(String, modified: Date?)
    /// The state is in `status`.
    case unavailable
  }

  private enum Key {
    static let bookmark = "ritm.wallet.folder.bookmark.v1"
    static let name = "ritm.wallet.folder.name.v1"
    static let modified = "ritm.wallet.folder.modified.v1"
    static let summary = "ritm.wallet.folder.summary.v1"
  }

  private(set) var status: Status
  /// For display only.
  private(set) var folderName: String?
  private(set) var lastImport: Summary?
  private(set) var isReading = false
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var bookmark: Data?
  @ObservationIgnored private var lastModified: Date?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    bookmark = defaults.data(forKey: Key.bookmark)
    folderName = defaults.string(forKey: Key.name)
    lastModified = (defaults.object(forKey: Key.modified) as? Double)
      .map(Date.init(timeIntervalSince1970:))
    lastImport = defaults.data(forKey: Key.summary)
      .flatMap { try? JSONDecoder().decode(Summary.self, from: $0) }
    status = defaults.data(forKey: Key.bookmark) == nil ? .notChosen : .ready
  }

  var isChosen: Bool { bookmark != nil }

  /// The picker returned a folder: keep it and forget everything about the previous one.
  func choose(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try url.bookmarkData()
      store(bookmark: data)
      folderName = url.lastPathComponent
      defaults.set(folderName, forKey: Key.name)
      forgetImportState()
      status = .ready
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  /// Forgets the folder (sign-out, server switch, «Забыть папку»). The file itself is untouched.
  func disconnect() {
    bookmark = nil
    folderName = nil
    for key in [Key.bookmark, Key.name] { defaults.removeObject(forKey: key) }
    forgetImportState()
    status = .notChosen
  }

  /// Reads the file when the folder is chosen and (unless `force`) the file changed since the last
  /// successful import. Blocking file work and the iCloud wait run off the main actor.
  func read(force: Bool) async -> Outcome {
    guard let current = bookmark, !isReading else { return .idle }
    isReading = true
    defer { isReading = false }
    let known = force ? nil : lastModified
    let result = await Task.detached {
      await WalletFileReader.read(bookmark: current, lastModified: known)
    }.value
    guard isChosen, bookmark == current else { return .idle }
    if let renewed = result.renewedBookmark { store(bookmark: renewed) }
    if let name = result.folderName, name != folderName {
      folderName = name
      defaults.set(name, forKey: Key.name)
    }
    switch result.kind {
    case .contents(let text):
      status = .ready
      return .contents(text, modified: result.modified)
    case .unchanged:
      status = .ready
      return .idle
    case .fileMissing:
      status = .fileMissing
    case .downloading:
      status = .downloading
    case .needsRepick:
      status = .needsRepick
    case .failed(let detail):
      status = .failed(detail)
    }
    return .unavailable
  }

  /// Called after the parsed file went into the inbox. The modification date is kept only when
  /// every new purchase fit, so a full inbox does not hide the rest of the file next time.
  func recordImport(_ summary: Summary, modified: Date?) {
    lastImport = summary
    if let data = try? JSONEncoder().encode(summary) { defaults.set(data, forKey: Key.summary) }
    if summary.overflow == 0, let modified {
      lastModified = modified
      defaults.set(modified.timeIntervalSince1970, forKey: Key.modified)
    } else {
      forgetModified()
    }
  }

  // MARK: - Private

  private func store(bookmark data: Data) {
    bookmark = data
    defaults.set(data, forKey: Key.bookmark)
  }

  private func forgetImportState() {
    lastImport = nil
    defaults.removeObject(forKey: Key.summary)
    forgetModified()
  }

  private func forgetModified() {
    lastModified = nil
    defaults.removeObject(forKey: Key.modified)
  }
}

// MARK: - File access

/// Everything that touches the file system, away from the main actor.
enum WalletFileReader {
  struct ReadResult: Sendable {
    enum Kind: Sendable {
      case contents(String)
      case unchanged, fileMissing, downloading, needsRepick
      case failed(String)
    }
    var kind: Kind
    var modified: Date?
    var folderName: String?
    var renewedBookmark: Data?
  }

  /// A year of purchases is far below this; a bigger file is read from its tail.
  static let tailBytes = 1_000_000
  static let downloadPolls = 16
  static let downloadPollInterval: Duration = .milliseconds(500)

  static func read(bookmark: Data, lastModified: Date?) async -> ReadResult {
    var stale = false
    let folder: URL
    do {
      folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
    } catch {
      return ReadResult(kind: .needsRepick)
    }
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

    var result = ReadResult(kind: .fileMissing, folderName: folder.lastPathComponent)
    if stale {
      guard let renewed = try? folder.bookmarkData() else { return ReadResult(kind: .needsRepick) }
      result.renewedBookmark = renewed
    }
    // Every purchases file counts: Shortcuts starts «purchases 2.txt» when it cannot reach the
    // original, and both keep lines that were never imported. Duplicate lines are dropped later.
    var present: [URL] = []
    var waiting = false
    for file in candidateFiles(in: folder) {
      switch await availability(of: file, in: folder) {
      case .missing: continue
      case .downloading: waiting = true
      case .present: present.append(file)
      }
    }
    guard !present.isEmpty else {
      result.kind = waiting ? .downloading : .fileMissing
      return result
    }
    result.modified = present.compactMap(modificationDate(of:)).max()
    if let lastModified, result.modified == lastModified {
      result.kind = .unchanged
      return result
    }
    var texts: [String] = []
    var failure: ReadResult.Kind?
    for file in present {
      switch load(file) {
      case .contents(let text): texts.append(text)
      case .fileMissing: continue
      case let other: failure = failure ?? other
      }
    }
    if texts.isEmpty {
      result.kind = failure ?? .fileMissing
    } else {
      result.kind = .contents(texts.joined(separator: "\n"))
    }
    return result
  }

  /// The purchases files in the folder, including iCloud placeholders («.name.icloud») of files
  /// that are not downloaded yet, oldest name first so the original comes before its copies.
  private static func candidateFiles(in folder: URL) -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    var seen = Set<String>()
    var files: [URL] = []
    for raw in names {
      var name = raw
      if name.hasPrefix("."), name.hasSuffix(".icloud") {
        name = String(name.dropFirst().dropLast(".icloud".count))
      }
      guard WalletFileImport.isPurchasesFileName(name), seen.insert(name.lowercased()).inserted
      else { continue }
      files.append(folder.appendingPathComponent(name, isDirectory: false))
    }
    return files.sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }

  // MARK: iCloud

  private enum Availability { case present, missing, downloading }

  /// A file that iCloud has not downloaded yet is asked for and awaited for a few seconds.
  private static func availability(of file: URL, in folder: URL) async -> Availability {
    if isDownloaded(file) { return .present }
    let placeholder = folder.appendingPathComponent(
      "." + file.lastPathComponent + ".icloud", isDirectory: false)
    let exists = (try? file.checkResourceIsReachable()) ?? false
    let hasPlaceholder = (try? placeholder.checkResourceIsReachable()) ?? false
    guard exists || hasPlaceholder else { return .missing }
    try? FileManager.default.startDownloadingUbiquitousItem(at: file)
    for _ in 0..<downloadPolls {
      try? await Task.sleep(for: downloadPollInterval)
      if isDownloaded(file) { return .present }
    }
    return .downloading
  }

  /// Local files, and iCloud files whose newest version is on this iPhone.
  private static func isDownloaded(_ file: URL) -> Bool {
    guard (try? file.checkResourceIsReachable()) == true else { return false }
    let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
    guard let values = try? file.resourceValues(forKeys: keys),
      values.isUbiquitousItem == true
    else { return true }
    return values.ubiquitousItemDownloadingStatus == .current
  }

  private static func modificationDate(of file: URL) -> Date? {
    try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  // MARK: Coordinated read

  private static func load(_ file: URL) -> ReadResult.Kind {
    var coordinationError: NSError?
    var loaded: ReadResult.Kind = .failed("")
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: file, options: [], error: &coordinationError
    ) { url in
      do {
        loaded = .contents(decode(try readData(at: url)))
      } catch let error as NSError where error.code == NSFileReadNoSuchFileError
        || error.code == NSFileNoSuchFileError
      {
        loaded = .fileMissing
      } catch {
        loaded = .failed(error.localizedDescription)
      }
    }
    if let coordinationError { return .failed(coordinationError.localizedDescription) }
    return loaded
  }

  /// The whole file, or only its last megabyte without the first (cut) line.
  private static func readData(at url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    guard size > UInt64(tailBytes) else {
      try handle.seek(toOffset: 0)
      return try handle.readToEnd() ?? Data()
    }
    try handle.seek(toOffset: size - UInt64(tailBytes))
    let tail = try handle.readToEnd() ?? Data()
    guard let newline = tail.firstIndex(of: 0x0A) else { return tail }
    return tail.suffix(from: tail.index(after: newline))
  }

  private static func decode(_ data: Data) -> String {
    let utf16Marks: [[UInt8]] = [[0xFF, 0xFE], [0xFE, 0xFF]]
    if utf16Marks.contains(Array(data.prefix(2))), let text = String(data: data, encoding: .utf16) {
      return text
    }
    return String(decoding: data, as: UTF8.self)
  }
}

// MARK: - Store wiring

extension RitmStore {
  /// Reads `purchases.txt` and puts new purchases into the inbox. Runs at launch, when the app
  /// becomes active and on pull-to-refresh in Finance. `userInitiated` (the settings button and
  /// the refresh) rereads an unchanged file and says so when nothing is new.
  func importWalletFile(userInitiated: Bool = false) async {
    guard isSignedIn, !isMutating else { return }
    let epoch = accountEpoch
    guard case .contents(let contents, let modified) = await walletFolder.read(force: userInitiated)
      , epoch == accountEpoch, isSignedIn
    else { return }
    let parsed = WalletFileImport.parse(
      text: contents, today: HabitSchedule.dateKey(Date(), timeZone: timeZone),
      receivedAt: ISO8601DateFormatter().string(from: Date()))
    let receipt = wallet.receive(file: parsed.purchases)
    walletFolder.recordImport(
      WalletFolderSource.Summary(
        date: Date(), added: receipt.added, duplicates: receipt.duplicates,
        skipped: parsed.skipped, overflow: receipt.overflow),
      modified: modified)
    if receipt.added > 0 {
      toasts.show(text("Новые покупки: \(receipt.added)", "New purchases: \(receipt.added)"))
    } else if receipt.overflow > 0 {
      toasts.show(
        text(
          "Список покупок полон. Подтвердите часть, остальные подтянутся позже.",
          "The purchase list is full. Confirm some; the rest will follow."))
    } else if userInitiated {
      toasts.show(text("Новых покупок нет", "No new purchases"))
    }
  }
}
