import Foundation
import RitmCore
import RitmSystem
import UserNotifications
import WidgetKit

enum SystemSection: Equatable, Sendable { case day, calendar, habits, finance, workouts }
struct SystemNavigationRequest: Equatable {
  let id = UUID()
  let section: SystemSection
}

/// Only the app writes this small projection. The extension has no network client or credential.
@MainActor final class WidgetSnapshotPublisher {
  private var last: DayWidgetSnapshot?
  func publish(_ snapshot: DayWidgetSnapshot) {
    if let last, snapshot.hasSameContent(as: last) { return }
    guard WidgetSnapshotStore.write(snapshot) else { return }
    last = snapshot
    WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind)
  }
  func clear() {
    last = nil
    WidgetSnapshotStore.clear()
    WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind)
  }
}

/// One retained delegate for foreground presentation and notification taps. Payloads contain
/// navigation only: a notification cannot perform a purchase, habit tick or server mutation.
final class SystemNotificationBridge: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  private let receive: @MainActor @Sendable ([String: String]) -> Void
  init(receive: @escaping @MainActor @Sendable ([String: String]) -> Void) { self.receive = receive }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification, withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void) {
    let rest = notification.request.identifier.hasPrefix(RestNotificationPlanner.identifierPrefix)
    completionHandler(rest ? [] : [.banner, .list, .sound])
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let strings = response.notification.request.content.userInfo.reduce(into: [String: String]()) {
      if let key = $1.key as? String, let value = $1.value as? String { $0[key] = value }
    }
    Task { @MainActor in self.receive(strings) }
    completionHandler()
  }
}
