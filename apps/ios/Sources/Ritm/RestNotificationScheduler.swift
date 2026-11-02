import Foundation
import Observation
import RitmCore
import UserNotifications

/// What the scheduler needs from UserNotifications, so a fake can stand in for it.
@MainActor
protocol RestNotificationCenter: AnyObject {
  func permission() async -> RestNotificationPermission
  func requestPermission() async -> Bool
  func add(_ plan: RestNotificationPlan) async throws
  func remove(identifiers: [String])
}

enum RestNotificationPermission: Equatable {
  case notDetermined, denied, allowed
}

@MainActor
final class SystemRestNotificationCenter: RestNotificationCenter {
  private let center = UNUserNotificationCenter.current()
  /// The delegate is held weakly by the center, so it is kept here.
  private let presenter = RestNotificationPresenter()

  init() {
    // Do not take over a delegate that someone else already set.
    if center.delegate == nil { center.delegate = presenter }
  }

  func permission() async -> RestNotificationPermission {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral: return .allowed
    case .denied: return .denied
    case .notDetermined: return .notDetermined
    @unknown default: return .denied
    }
  }

  func requestPermission() async -> Bool {
    do { return try await center.requestAuthorization(options: [.alert, .sound]) } catch { return false }
  }

  func add(_ plan: RestNotificationPlan) async throws {
    let content = UNMutableNotificationContent()
    content.title = plan.title
    content.body = plan.body
    content.sound = .default
    content.threadIdentifier = "ritm.workout.rest"
    let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: Calendar.current.dateComponents(parts, from: plan.fireDate), repeats: false)
    // The same identifier replaces a pending request, so a moved end date never leaves a second one.
    try await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
  }

  func remove(identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

/// While Ritm is in the foreground the screen already shows the end of the rest: the system
/// notification then makes no banner and no sound, so there is no duplicate cue.
final class RestNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let isRest = notification.request.identifier.hasPrefix(RestNotificationPlanner.identifierPrefix)
    return isRest ? [] : [.banner, .sound]
  }
}

/// Keeps exactly one pending «Отдых закончился» notification in line with the rest timer.
/// Permission is requested only from the settings switch, never at launch, and a denied or
/// missing permission only means nothing is scheduled: the workout journal never depends on it.
@MainActor @Observable
final class RestNotificationScheduler {
  private(set) var permission: RestNotificationPermission = .notDetermined

  @ObservationIgnored private let center: RestNotificationCenter
  @ObservationIgnored private var scheduled: RestNotificationPlan?
  @ObservationIgnored private var revision = 0

  init(center: RestNotificationCenter? = nil) {
    self.center = center ?? SystemRestNotificationCenter()
  }

  func refreshPermission() async { permission = await center.permission() }

  /// Called when the owner turns the switch on.
  @discardableResult
  func requestPermission() async -> Bool {
    _ = await center.requestPermission()
    await refreshPermission()
    return permission == .allowed
  }

  /// Makes the pending notification match `plan`. `nil` (or a switch that is off) cancels it.
  func apply(_ plan: RestNotificationPlan?, enabled: Bool) {
    let wanted = enabled ? plan : nil
    guard wanted != scheduled else { return }
    revision += 1
    let ticket = revision
    let previous = scheduled
    scheduled = wanted
    guard let wanted else {
      if let previous { center.remove(identifiers: [previous.identifier]) }
      return
    }
    Task { [weak self] in
      guard let self else { return }
      let state = await center.permission()
      guard ticket == revision else { return }
      permission = state
      guard state == .allowed else {
        // Not allowed (yet): forget the plan so it is tried again once the owner allows it.
        scheduled = nil
        return
      }
      do { try await center.add(wanted) } catch {
        // Could not schedule: forget it so the next change tries again; the journal is unaffected.
        if ticket == revision { scheduled = nil }
      }
    }
  }
}
