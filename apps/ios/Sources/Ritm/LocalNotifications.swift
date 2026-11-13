import Foundation
import RitmCore
import UserNotifications

/// Device-local notifications. Permission comes only from the explicit settings action.
@MainActor
final class LocalNotifications {
  private let center: UNUserNotificationCenter
  private let reminders: LocalNotificationReconciler
  private let wallet: LocalNotificationReconciler
  private var updateRevision = 0
  private var accountRevision = 0
  private var accountEpoch: String?
  private var accountEnabled = false
  private var walletPlans: [String: LocalNotificationPlan] = [:]
  private var walletOrder: [String] = []
  private var dismissedWalletIDs: Set<String> = []

  init() {
    let center = UNUserNotificationCenter.current()
    self.center = center
    let driver = LocalNotificationDriver(
      pendingIdentifiers: { await center.pendingNotificationRequests().map(\.identifier) },
      deliveredIdentifiers: { await center.deliveredNotifications().map(\.request.identifier) },
      add: { plan, requestID in
        try await Self.add(plan, requestID: requestID, to: center)
      },
      removePending: { center.removePendingNotificationRequests(withIdentifiers: $0) },
      removeDelivered: { center.removeDeliveredNotifications(withIdentifiers: $0) })
    reminders = LocalNotificationReconciler(
      driver: driver,
      owns: {
        $0.hasPrefix(LocalNotificationNamespace.reminders)
          || LocalNotificationNamespace.isLegacyReminder($0)
      })
    wallet = LocalNotificationReconciler(
      driver: driver, owns: { $0.hasPrefix(LocalNotificationNamespace.wallet) })
  }

  /// Called only from the existing opt-in, never from update or app launch.
  func requestPermission() async -> Bool {
    do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) } catch {
      return false
    }
  }

  /// Invalidates adds immediately. Workout rest and other namespaces survive.
  func clear() {
    updateRevision &+= 1
    accountRevision &+= 1
    accountEpoch = nil
    accountEnabled = false
    walletPlans = [:]
    walletOrder = []
    dismissedWalletIDs = []
    reminders.clear()
    wallet.clear()
  }

  /// Prefer this from the asynchronous account invalidation hook.
  func clearAndWait() async {
    clear()
    await reminders.flush()
    await wallet.flush()
  }

  func update(
    snapshot: Bootstrap, events: [GoogleCalendarEvent] = [], calendarReady: Bool = false,
    calendarPartial: Bool = false, leadMinutes: Int = 15, accountEpoch: String = "current",
    until expiry: Date, now: Date
  ) async {
    if self.accountEpoch != accountEpoch {
      clear()
      self.accountEpoch = accountEpoch
    }
    if accountEnabled && !snapshot.settings.notifications {
      clear()
      self.accountEpoch = accountEpoch
    }
    accountEnabled = snapshot.settings.notifications && expiry > now
    updateRevision &+= 1
    let ticket = updateRevision
    guard accountEnabled else {
      accountRevision &+= 1
      walletPlans = [:]
      walletOrder = []
      reminders.clear()
      wallet.clear()
      return
    }
    let authorization = await center.notificationSettings()
    guard ticket == updateRevision else { return }
    guard Self.isAllowed(authorization.authorizationStatus) else {
      accountRevision &+= 1
      walletPlans = [:]
      walletOrder = []
      reminders.clear()
      wallet.clear()
      return
    }
    let plans = LocalNotificationPlanner.plans(
      snapshot: snapshot, events: events, calendarReady: calendarReady,
      calendarPartial: calendarPartial, leadMinutes: leadMinutes, accountEpoch: accountEpoch,
      until: expiry, now: now)
    await reminders.replace(plans)
  }

  /// Only genuinely new imports belong here. update must first apply the saved account opt-in;
  /// permission granted for workout alerts alone is insufficient. No test purchase is sent.
  @discardableResult
  func notifyWallet(
    purchases: [WalletPurchase], language: Language, accountEpoch: String, until expiry: Date,
    now: Date = Date()
  ) async -> [String] {
    guard accountEnabled, self.accountEpoch == accountEpoch, now < expiry else { return [] }
    let ticket = accountRevision
    let authorization = await center.notificationSettings()
    guard ticket == accountRevision, accountEnabled, self.accountEpoch == accountEpoch, Date() < expiry,
      Self.isAllowed(authorization.authorizationStatus)
    else { return [] }
    var logicalToPurchase: [String: String] = [:]
    for purchase in purchases {
      guard !dismissedWalletIDs.contains(purchase.id) else { continue }
      guard let plan = WalletNotificationPlanner.plan(
        purchase: purchase, language: language, accountEpoch: accountEpoch, until: expiry)
      else { continue }
      if walletPlans[plan.identifier] == nil { walletOrder.append(plan.identifier) }
      walletPlans[plan.identifier] = plan
      logicalToPurchase[plan.identifier] = purchase.id
    }
    // A file can contain months of history. Bound the tray and the number of immediate banners.
    while walletOrder.count > WalletNotificationPlanner.maximumNotices {
      walletPlans.removeValue(forKey: walletOrder.removeFirst())
    }
    let accepted = await wallet.replace(walletOrder.compactMap { walletPlans[$0] })
    guard ticket == accountRevision, self.accountEpoch == accountEpoch else { return [] }
    return accepted.compactMap { logicalToPurchase[$0] }.sorted()
  }

  /// Confirm/skip removes only those purchases, including notices from an earlier process.
  func removeWallet(ids: [String]) {
    guard let epoch = accountEpoch, !ids.isEmpty else { return }
    dismissedWalletIDs.formUnion(ids)
    let base = LocalNotificationNamespace.wallet + LocalNotificationNamespace.key(epoch) + "."
    let logicalIDs = Set(ids.map { base + LocalNotificationNamespace.key($0) })
    walletOrder.removeAll { logicalIDs.contains($0) }
    for identifier in logicalIDs { walletPlans.removeValue(forKey: identifier) }
    wallet.setPlans(walletOrder.compactMap { walletPlans[$0] })
    Task {
      let pending = await center.pendingNotificationRequests().map(\.identifier)
      let delivered = await center.deliveredNotifications().map(\.request.identifier)
      func matches(_ identifier: String) -> Bool {
        logicalIDs.contains { identifier == $0 || identifier.hasPrefix($0 + ".request.") }
      }
      center.removePendingNotificationRequests(withIdentifiers: pending.filter(matches))
      center.removeDeliveredNotifications(withIdentifiers: delivered.filter(matches))
    }
  }

  /// The root coordinator owns UNUserNotificationCenter.delegate and consumes this destination.
  static func destination(
    from userInfo: [AnyHashable: Any], accountEpoch: String? = nil
  ) -> LocalNotificationDestination? {
    guard let raw = userInfo[LocalNotificationDestination.userInfoKey] as? String,
      let url = URL(string: raw), let destination = LocalNotificationDestination(url: url)
    else { return nil }
    if let accountEpoch {
      // Workout data is device-local and deliberately survives account invalidation.
      if case .workout = destination { return destination }
      guard userInfo[LocalNotificationDestination.accountEpochUserInfoKey] as? String
        == LocalNotificationNamespace.key(accountEpoch)
      else { return nil }
    }
    return destination
  }

  static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
    status == .authorized || status == .provisional || status == .ephemeral
  }

  static func add(
    _ plan: LocalNotificationPlan, requestID: String, to center: UNUserNotificationCenter
  ) async throws {
    if let expiry = plan.expiresAt, expiry <= Date() { throw NotificationSchedulingError.elapsed }
    let content = UNMutableNotificationContent()
    content.title = plan.title
    content.body = plan.body
    content.sound = .default
    content.threadIdentifier = plan.threadIdentifier
    content.categoryIdentifier = plan.categoryIdentifier
    content.userInfo = [LocalNotificationDestination.userInfoKey: plan.destination.url.absoluteString]
    if let epoch = plan.accountEpoch {
      content.userInfo[LocalNotificationDestination.accountEpochUserInfoKey] = epoch
    }
    let trigger: UNNotificationTrigger?
    if let date = plan.fireDate {
      // Use an absolute instant; changing the device zone must not move an account reminder.
      guard date > Date() else { throw NotificationSchedulingError.elapsed }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      let components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second, .timeZone], from: date)
      trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    } else {
      trigger = nil
    }
    try await center.add(UNNotificationRequest(
      identifier: requestID, content: content, trigger: trigger))
  }
}

private enum NotificationSchedulingError: Error { case elapsed }
