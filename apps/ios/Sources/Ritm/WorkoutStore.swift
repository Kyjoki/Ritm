import Foundation
import Observation
import RitmCore
import UIKit

/// The training log of «Тренировки»: programs, history and the workout in progress.
///
/// It lives ONLY on this iPhone, as JSON files in Application Support. The Ritm server has no
/// workout model and nothing here is sent to it, to the assistant or to any AI request. It is
/// deliberately NOT cleared by sign-out or by a server switch: that is the owner's own training
/// log, not account data that the server holds, so leaving an account must not erase it.
///
/// Files (each carries a `version`, and decoding tolerates missing or damaged parts):
/// - `programs.json`: programs and the owner's own exercises;
/// - `history.json`: completed workouts, newest first;
/// - `session.json`: the unfinished workout and its rest timer, written on every change
///   (debounced) so a killed app resumes it.
/// Writes are atomic. A file that cannot be read at all is moved aside, never overwritten.
@MainActor @Observable
final class WorkoutStore {
  enum StartResult { case started, alreadyActive, empty }

  enum File: String, CaseIterable {
    case programs, history, session
    var name: String { rawValue + ".json" }
  }

  private(set) var library: WorkoutLibrary
  private(set) var history: WorkoutHistory
  private(set) var session: WorkoutSession?
  private(set) var rest: RestTimer
  /// True while the last attempt to write a file failed.
  private(set) var saveFailed = false
  /// What the running workout shows outside the app (rest notification, lock-screen card).
  @ObservationIgnored let alerts = WorkoutAlerts()
  /// Called with each completed workout, only after it is saved in the journal (never on cancel).
  @ObservationIgnored var onWorkoutFinished: ((WorkoutRecord) -> Void)?

  @ObservationIgnored private let directory: URL
  @ObservationIgnored private var dirty: Set<File> = []
  @ObservationIgnored private var saveTasks: [File: Task<Void, Never>] = [:]
  @ObservationIgnored private var observer: NSObjectProtocol?  // lives as long as the store

  private static let saveDelay: Duration = .milliseconds(300)

  init(directory: URL = WorkoutStore.defaultDirectory()) {
    self.directory = directory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    library = Self.load(WorkoutLibrary.self, .programs, in: directory) ?? WorkoutLibrary()
    history = Self.load(WorkoutHistory.self, .history, in: directory) ?? WorkoutHistory()
    let active = Self.load(WorkoutActiveState.self, .session, in: directory)
    session = active?.session
    rest = active?.rest ?? RestTimer()
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.flush() }
    }
  }

  private static func defaultDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Ritm", isDirectory: true)
      .appendingPathComponent("Workouts", isDirectory: true)
  }

  // MARK: - Reading

  func program(_ id: String) -> WorkoutProgram? { library.program(id) }

  func exerciseName(_ id: String, language: Language) -> String {
    library.exerciseName(id, language: language)
  }

  func allExercises(language: Language) -> [WorkoutExercise] {
    WorkoutCatalog.all(custom: library.customExercises, language: language)
  }

  func item(_ itemID: String) -> WorkoutSessionItem? { session?.item(itemID) }

  func set(item itemID: String, set setID: String) -> WorkoutSet? {
    item(itemID)?.sets.first { $0.id == setID }
  }

  // MARK: - Programs

  @discardableResult
  func addProgram(name: String) -> String {
    let id = mutateLibrary { $0.addProgram(name: name) }
    return id
  }

  func renameProgram(_ id: String, to name: String) {
    mutateLibrary { $0.renameProgram(id, to: name) }
  }

  @discardableResult
  func duplicateProgram(_ id: String, suffix: String) -> String? {
    mutateLibrary { $0.duplicateProgram(id, suffix: suffix) }
  }

  func deleteProgram(_ id: String) { mutateLibrary { $0.deleteProgram(id) } }

  func moveProgram(from: Int, to: Int) { mutateLibrary { $0.moveProgram(from: from, to: to) } }

  @discardableResult
  func addItem(to programID: String, exerciseID: String) -> Bool {
    mutateLibrary { $0.addItem(to: programID, exerciseID: exerciseID) }
  }

  func removeItem(_ itemID: String, from programID: String) {
    mutateLibrary { $0.removeItem(itemID, from: programID) }
  }

  @discardableResult
  func replaceItem(_ itemID: String, in programID: String, with exerciseID: String) -> Bool {
    mutateLibrary { $0.replaceItem(itemID, in: programID, with: exerciseID) }
  }

  func setPlannedSets(_ count: Int, item itemID: String, in programID: String) {
    mutateLibrary { $0.setPlannedSets(count, item: itemID, in: programID) }
  }

  func moveItem(in programID: String, from: Int, to: Int) {
    mutateLibrary { $0.moveItem(in: programID, from: from, to: to) }
  }

  func createExercise(named name: String) -> WorkoutExercise? {
    mutateLibrary { $0.createExercise(named: name) }
  }

  @discardableResult
  private func mutateLibrary<T>(_ change: (inout WorkoutLibrary) -> T) -> T {
    var next = library
    let result = change(&next)
    if next != library {
      library = next
      scheduleSave(.programs)
    }
    return result
  }

  // MARK: - Active workout

  func startWorkout(programID: String, language: Language, now: Date = Date()) -> StartResult {
    guard session == nil else { return .alreadyActive }
    guard let program = library.program(programID),
      let started = WorkoutSession.start(
        program: program, library: library, history: history, language: language, now: now)
    else { return .empty }
    session = started
    rest = RestTimer(preset: rest.preset)
    scheduleSave(.session)
    flush(.session)
    syncAlerts(now: now)
    return .started
  }

  func typeWeight(_ text: String, item itemID: String, set setID: String) {
    mutateSession { $0.update(itemID) { $0.typeWeight(text, setID: setID) } }
  }

  func typeReps(_ text: String, item itemID: String, set setID: String) {
    mutateSession { $0.update(itemID) { $0.typeReps(text, setID: setID) } }
  }

  /// Ticks or unticks a set. A tick starts the rest timer.
  @discardableResult
  func toggleSet(item itemID: String, set setID: String, now: Date = Date()) -> WorkoutSessionItem.TickResult {
    var result = WorkoutSessionItem.TickResult.missing
    mutateSession(syncing: false) { $0.update(itemID) { result = $0.toggle(setID: setID) } }
    if result == .done {
      rest.restart(now: now)
      scheduleSave(.session)
    }
    syncAlerts(now: now)
    return result
  }

  func addSet(item itemID: String) {
    mutateSession { $0.update(itemID) { $0.addSet() } }
  }

  func removeSet(item itemID: String, set setID: String) {
    mutateSession { $0.update(itemID) { $0.removeSet(setID: setID) } }
  }

  func replaceExercise(item itemID: String, with exercise: WorkoutExercise) {
    let snapshot = history
    mutateSession {
      $0.replaceExercise(itemID, with: exercise.id, name: exercise.name, history: snapshot)
    }
  }

  /// Saves the ticked sets to the history and ends the workout. `false` when nothing was ticked.
  @discardableResult
  func finishWorkout(now: Date = Date()) -> Bool {
    guard let current = session, let record = current.finished(at: now) else { return false }
    history = WorkoutHistory(records: [record] + history.records)
    session = nil
    rest.reset()
    scheduleSave(.history)
    scheduleSave(.session)
    flush()
    syncAlerts(now: now)
    onWorkoutFinished?(record)  // after the journal is on disk; may export to Apple Health
    return true
  }

  func cancelWorkout() {
    guard session != nil else { return }
    session = nil
    rest.reset()
    scheduleSave(.session)
    flush()
    syncAlerts()
  }

  private func mutateSession(syncing: Bool = true, _ change: (inout WorkoutSession) -> Void) {
    guard var next = session else { return }
    change(&next)
    guard next != session else { return }
    session = next
    scheduleSave(.session)
    if syncing { syncAlerts() }
  }

  // MARK: - Rest timer

  func toggleRest(now: Date = Date()) {
    switch rest.phase(now: now) {
    case .running: rest.pause(now: now)
    case .idle, .paused, .finished: rest.start(now: now)
    }
    scheduleSave(.session)
    syncAlerts(now: now)
  }

  func resetRest() {
    rest.reset()
    scheduleSave(.session)
    syncAlerts()
  }

  func extendRest(now: Date = Date()) {
    rest.extend(now: now)
    scheduleSave(.session)
    syncAlerts(now: now)
  }

  func setRestPreset(_ value: TimeInterval, now: Date = Date()) {
    rest.setPreset(value, now: now)
    scheduleSave(.session)
    syncAlerts(now: now)
  }

  /// Hands the workout to the end-of-rest notification and the lock-screen card. They only
  /// derive from it; a failure there never touches the journal.
  func syncAlerts(now: Date = Date()) { alerts.sync(session: session, rest: rest, now: now) }

  // MARK: - Files

  private static func load<T: Decodable>(_ type: T.Type, _ file: File, in directory: URL) -> T? {
    let url = directory.appendingPathComponent(file.name)
    guard let data = try? Data(contentsOf: url) else { return nil }
    do {
      return try WorkoutCoding.decoder().decode(T.self, from: data)
    } catch {
      // Not valid JSON at all: keep the bytes for recovery instead of overwriting them.
      let aside = directory.appendingPathComponent(file.name + ".damaged")
      try? FileManager.default.removeItem(at: aside)
      try? FileManager.default.moveItem(at: url, to: aside)
      return nil
    }
  }

  private func scheduleSave(_ file: File) {
    dirty.insert(file)
    saveTasks[file]?.cancel()
    saveTasks[file] = Task { [weak self] in
      try? await Task.sleep(for: Self.saveDelay)
      guard !Task.isCancelled else { return }
      self?.flush(file)
    }
  }

  /// Writes what is still waiting (all files, or one). Called when the app is about to leave the
  /// foreground and after steps that must not be lost.
  func flush(_ only: File? = nil) {
    for file in File.allCases where dirty.contains(file) && (only == nil || only == file) {
      saveTasks[file]?.cancel()
      saveTasks[file] = nil
      write(file)
    }
  }

  private func write(_ file: File) {
    do {
      let encoder = WorkoutCoding.encoder()
      let data: Data
      switch file {
      case .programs: data = try encoder.encode(library)
      case .history: data = try encoder.encode(history)
      case .session: data = try encoder.encode(WorkoutActiveState(session: session, rest: rest))
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(
        to: directory.appendingPathComponent(file.name),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      dirty.remove(file)
      saveFailed = false
    } catch {
      saveFailed = true
    }
  }
}
