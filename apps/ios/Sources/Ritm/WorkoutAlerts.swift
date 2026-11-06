import Foundation
import Observation
import RitmCore
import RitmSystem
import CryptoKit

/// Everything a running workout shows OUTSIDE the app: the end-of-rest notification and the
/// lock-screen card. It is fed the workout after every change and only derives from it; it never
/// writes to the journal, and a failure here never blocks a workout.
@MainActor @Observable
final class WorkoutAlerts {
  let settings = WorkoutAlertSettings()
  let notifications = RestNotificationScheduler()
  let liveActivity = LiveActivityManager()
  /// The app language, for the text of the notification.
  @ObservationIgnored var language: () -> Language = { .ru }

  @ObservationIgnored private var lastSession: WorkoutSession?
  @ObservationIgnored private var lastRest = RestTimer()
  @ObservationIgnored private(set) var activityState: WorkoutActivityState?
  @ObservationIgnored private var revision = UUID().uuidString
  @ObservationIgnored private var previousSession: WorkoutSession?
  @ObservationIgnored private var previousRest = RestTimer()

  func sync(session: WorkoutSession?, rest: RestTimer, now: Date = Date()) {
    let state = prepareAction(session: session, rest: rest, now: now)
    let plan = RestNotificationPlanner.plan(
      state: state, privacy: settings.hidesWeights, russian: language() == .ru, now: now)
    notifications.apply(plan, enabled: settings.notifiesRestEnd)
    liveActivity.sync(content: activityState, enabled: settings.showsLiveActivity)
  }

  /// Validate a lock-screen command against the current journal without publishing an
  /// intermediate card or cancelling/recreating its notification before the command applies.
  @discardableResult
  func prepareAction(session: WorkoutSession?, rest: RestTimer, now: Date = Date()) -> SharedWorkoutState {
    lastSession = session
    lastRest = rest
    let state = SharedWorkoutState(session: session, rest: rest)
    // A command belongs to this exact journal revision, not just a set number. Completing a
    // set in the app also invalidates old lock-screen taps. No per-second state writes.
    if session != previousSession || rest != previousRest {
      revision = persistedRevision(for: state.activeState)
      previousSession = session
      previousRest = rest
    }
    if let session, let content = LiveActivityContent.make(
      from: state, privacy: settings.hidesWeights, now: now) {
      let position = state.current
      let exercise = position?.exercise ?? max(0, session.items.count - 1)
      let setID = position.map { session.items[$0.exercise].sets[$0.set].id } ?? "finished"
      activityState = WorkoutActivityState(content: content, startedAt: session.startedAt,
        exerciseNumber: exercise + 1, exerciseTotal: session.items.count, setID: setID,
        revision: revision, language: language(), requiredInput: WorkoutActionPolicy.requiredInput(in: state))
    } else { activityState = nil }
    return state
  }

  /// After a setting changed: the same workout, re-evaluated.
  func resync(now: Date = Date()) { sync(session: lastSession, rest: lastRest, now: now) }

  /// Keep an unchanged, durable workout's command revision across a cold app launch. The
  /// fingerprint contains no credentials and cannot restore the journal; only its UUID is
  /// sent to the lock screen. A mismatch (including an interrupted save) fails closed.
  private func persistedRevision(for value: WorkoutActiveState) -> String {
    guard let bytes = try? WorkoutSurfaceRevision.fingerprintMaterial(for: value) else {
      return UUID().uuidString
    }
    let digest = Data(SHA256.hash(data: bytes))
    return WorkoutSurfaceRevision.current(fingerprint: digest)
  }
}
