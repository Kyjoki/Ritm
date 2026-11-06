import Foundation
import Observation
import RitmCore
import RitmSystem

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the lock-screen card of the active workout.
///
/// The card is drawn by the embedded widget extension. Without it the manager never calls ActivityKit and only
/// reports `.extensionMissing`; if ActivityKit refuses a request the error is swallowed into
/// `.failed`. Either way the workout is never blocked and no ghost card is left behind.
@MainActor @Observable
final class LiveActivityManager {
  enum Status: Equatable {
    /// Nothing to show (switch off, or no workout).
    case idle
    case running
    case systemDisabled
    case extensionMissing
    case unsupported
    case failed(String)
  }

  private(set) var status: Status = .idle

  @ObservationIgnored private var lastContent: WorkoutActivityState?
  @ObservationIgnored private var failedWorkoutID: String?
  @ObservationIgnored private var work: Task<Void, Never>?

  /// True only when the app bundle really contains a WidgetKit extension.
  static var extensionInstalled: Bool {
    guard let plugins = Bundle.main.builtInPlugInsURL,
      let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
    else { return false }
    return items.contains { url in
      guard url.pathExtension == "appex", let bundle = Bundle(url: url),
        let info = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
      else { return false }
      return info["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
    }
  }

  /// What iOS Settings say about Live Activities for this app.
  static var systemAllowsActivities: Bool {
    #if canImport(ActivityKit)
    return ActivityAuthorizationInfo().areActivitiesEnabled
    #else
    return false
    #endif
  }

  /// Brings the card in line with `content` (`nil`: no workout). Calls are serialised, and
  /// ActivityKit is only touched when `LiveActivityLifecycle` says something really changed.
  func sync(content: WorkoutActivityState?, enabled: Bool) {
    if !enabled || content == nil { failedWorkoutID = nil }
    let previous = work
    work = Task { [weak self] in
      await previous?.value
      await self?.perform(content: content, enabled: enabled)
    }
  }

  /// A background App Intent waits until its ActivityKit write has really been submitted.
  func flush() async { await work?.value }

  private func perform(content: WorkoutActivityState?, enabled: Bool) async {
    #if canImport(ActivityKit)
    guard Self.extensionInstalled else {
      status = enabled && content != nil ? .extensionMissing : .idle
      return
    }
    // A new process has no lastContent. The system can still hold an earlier card.
    guard enabled, content != nil else { await endAll(); status = .idle; return }
    let allowed = ActivityAuthorizationInfo().areActivitiesEnabled
    guard allowed else { await endAll(); status = .systemDisabled; return }
    adoptExisting(for: content)
    var decision = LiveActivityLifecycle.decide(
      content: content?.content, existing: lastContent?.content, enabled: enabled && allowed)
    if decision == .none, enabled && allowed, let content, let lastContent,
      content.revision != lastContent.revision || content.language != lastContent.language {
      decision = .update(workoutID: content.workoutID)
    }
    if enabled && content != nil && !allowed {
      status = .systemDisabled
    } else if content == nil || !enabled {
      status = .idle
    }
    switch decision {
    case .none: break
    case .start:
      if let content { await start(content) }
    case .update:
      if let content { await update(content) }
    case .end: await endAll()
    case .replace:
      await endAll()
      if let content { await start(content) }
    }
    #else
    status = enabled && content != nil ? .unsupported : .idle
    #endif
  }

  #if canImport(ActivityKit)
  // ActivityKit's Activity is not Sendable, so every call that touches one lives in a nonisolated
  // helper that looks the activity up itself; only Sendable values cross the boundary.

  /// After a relaunch the system may still hold the card: reuse the one of this workout.
  private func adoptExisting(for content: WorkoutActivityState?) {
    guard lastContent == nil, let workoutID = content?.workoutID,
      let state = Self.stateOfActivity(workoutID: workoutID)
    else { return }
    lastContent = state
    status = .running
  }

  private func start(_ content: WorkoutActivityState) async {
    guard failedWorkoutID != content.workoutID else { return }
    // A card of another workout (a ghost) goes first, so only one card ever exists.
    await Self.endActivities(except: content.workoutID)
    if Self.stateOfActivity(workoutID: content.workoutID) != nil {
      lastContent = content
      status = .running
      return
    }
    do {
      try Self.request(content)
      lastContent = content
      status = .running
    } catch {
      failedWorkoutID = content.workoutID
      lastContent = nil
      status = .failed(error.localizedDescription)
    }
  }

  private func update(_ content: WorkoutActivityState) async {
    if await Self.updateActivity(content) {
      lastContent = content
    } else {
      lastContent = nil
      await start(content)
    }
  }

  private func endAll() async {
    await Self.endActivities(except: nil)
    lastContent = nil
    if status == .running { status = .idle }
  }

  private nonisolated static func stateOfActivity(workoutID: String) -> WorkoutActivityState? {
    Activity<RitmWorkoutAttributes>.activities
      .first { $0.attributes.workoutID == workoutID }?.content.state
  }

  private nonisolated static func request(_ content: WorkoutActivityState) throws {
    _ = try Activity.request(
      attributes: RitmWorkoutAttributes(workoutID: content.workoutID, startedAt: content.startedAt),
      content: ActivityContent(state: content, staleDate: content.staleDate), pushType: nil)
  }

  /// `false` when this workout has no activity to update.
  private nonisolated static func updateActivity(_ content: WorkoutActivityState) async -> Bool {
    guard let activity = Activity<RitmWorkoutAttributes>.activities
      .first(where: { $0.attributes.workoutID == content.workoutID })
    else { return false }
    await activity.update(ActivityContent(state: content, staleDate: content.staleDate))
    return true
  }

  private nonisolated static func endActivities(except keep: String?) async {
    for activity in Activity<RitmWorkoutAttributes>.activities where activity.attributes.workoutID != keep {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
  #endif
}
