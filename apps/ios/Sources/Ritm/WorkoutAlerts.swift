import Foundation
import Observation
import RitmCore

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

  func sync(session: WorkoutSession?, rest: RestTimer, now: Date = Date()) {
    lastSession = session
    lastRest = rest
    let state = SharedWorkoutState(session: session, rest: rest)
    let plan = RestNotificationPlanner.plan(
      state: state, privacy: settings.hidesWeights, russian: language() == .ru, now: now)
    notifications.apply(plan, enabled: settings.notifiesRestEnd)
    liveActivity.sync(
      content: LiveActivityContent.make(from: state, privacy: settings.hidesWeights, now: now),
      enabled: settings.showsLiveActivity)
  }

  /// After a setting changed: the same workout, re-evaluated.
  func resync(now: Date = Date()) { sync(session: lastSession, rest: lastRest, now: now) }
}
