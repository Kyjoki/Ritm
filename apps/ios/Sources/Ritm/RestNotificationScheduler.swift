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
  func pendingIdentifiers() async -> [String]
  func deliveredIdentifiers() async -> [String]
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
    guard plan.fireDate > Date() else { throw RestSchedulingError.elapsed }
    let content = UNMutableNotificationContent()
    content.title = plan.title
    content.body = plan.body
    content.sound = .default
    content.threadIdentifier = "ritm.workout.rest"
    content.categoryIdentifier = "RITM_WORKOUT_REST"
    let prefix = RestNotificationPlanner.identifierPrefix
    let logicalID = plan.identifier.components(separatedBy: ".request.").dropLast().joined(separator: ".request.")
    let original = logicalID.isEmpty ? plan.identifier : logicalID
    if original.hasPrefix(prefix) {
      let destination = LocalNotificationDestination.workout(id: String(original.dropFirst(prefix.count)))
      content.userInfo = [LocalNotificationDestination.userInfoKey: destination.url.absoluteString]
    }
    let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second, .timeZone]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: calendar.dateComponents(parts, from: plan.fireDate), repeats: false)
    try await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
  }

  func remove(identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func pendingIdentifiers() async -> [String] {
    await center.pendingNotificationRequests().map(\.identifier)
  }
  func deliveredIdentifiers() async -> [String] {
    await center.deliveredNotifications().map(\.request.identifier)
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
  @ObservationIgnored private let reconciler: LocalNotificationReconciler
  @ObservationIgnored private var hasApplied = false
  @ObservationIgnored private var work: Task<Void, Never>?

  init(center: RestNotificationCenter? = nil) {
    let center = center ?? SystemRestNotificationCenter()
    self.center = center
    reconciler = LocalNotificationReconciler(
      driver: LocalNotificationDriver(
        pendingIdentifiers: { await center.pendingIdentifiers() },
        deliveredIdentifiers: { await center.deliveredIdentifiers() },
        add: { plan, requestID in
          guard let fireDate = plan.fireDate else { return }
          try await center.add(RestNotificationPlan(
            identifier: requestID, fireDate: fireDate, title: plan.title, body: plan.body))
        },
        removePending: { center.remove(identifiers: $0) },
        removeDelivered: { center.remove(identifiers: $0) }),
      owns: { $0.hasPrefix(RestNotificationPlanner.identifierPrefix) })
  }

  func refreshPermission() async {
    let ticket = revision
    let fresh = await center.permission()
    guard ticket == revision else { return }
    permission = fresh
    if permission != .allowed {
      revision &+= 1
      scheduled = nil
      reconciler.clear()
    }
  }

  /// Called when the owner turns the switch on.
  @discardableResult
  func requestPermission() async -> Bool {
    _ = await center.requestPermission()
    await refreshPermission()
    return permission == .allowed
  }

  /// App Intents wait for permission checks and OS submission before returning to the system.
  func flush() async {
    await work?.value
    await reconciler.flush()
  }

  /// Makes the pending notification match `plan`. `nil` (or a switch that is off) cancels it.
  func apply(_ plan: RestNotificationPlan?, enabled: Bool) {
    let wanted = enabled ? plan : nil
    guard !hasApplied || wanted != scheduled else { return }
    hasApplied = true
    revision += 1
    let ticket = revision
    scheduled = wanted
    // Invalidate an older add before the permission read suspends.
    work?.cancel()
    work = nil
    reconciler.clear()
    guard let wanted else {
      return
    }
    work = Task { [weak self] in
      guard let self else { return }
      let state = await center.permission()
      guard ticket == revision else { return }
      permission = state
      guard state == .allowed else {
        // Not allowed (yet): forget the plan so it is tried again once the owner allows it.
        scheduled = nil
        return
      }
      let plan = LocalNotificationPlan(
        identifier: wanted.identifier, fireDate: wanted.fireDate, title: wanted.title, body: wanted.body,
        threadIdentifier: "ritm.workout.rest", categoryIdentifier: "RITM_WORKOUT_REST",
        destination: .workout(id: String(wanted.identifier.dropFirst(RestNotificationPlanner.identifierPrefix.count))))
      let accepted = await reconciler.replace([plan])
      if ticket == revision && !accepted.contains(plan.identifier) { scheduled = nil }
    }
  }
}

private enum RestSchedulingError: Error { case elapsed }
