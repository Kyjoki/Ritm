import Foundation
import RitmCore
import UserNotifications

/// Device-local reminders, not remote push. Scheduling needs an explicit system
/// grant and stops at the authenticated session's expiry; no persistent poller.
@MainActor
final class LocalNotifications {
  private let center = UNUserNotificationCenter.current()
  private var revision = 0

  func requestPermission() async -> Bool {
    do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) } catch {
      return false
    }
  }

  func clear() {
    revision += 1
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
  }

  func update(snapshot: Bootstrap, until expiry: Date, now: Date) async {
    revision += 1
    let ticket = revision
    let authorization = await center.notificationSettings()
    guard ticket == revision else { return }
    guard snapshot.settings.notifications,
      authorization.authorizationStatus == .authorized
        || authorization.authorizationStatus == .provisional
    else {
      center.removeAllPendingNotificationRequests()
      return
    }
    let zone = TimeZone(identifier: snapshot.settings.timeZone) ?? TimeZone(secondsFromGMT: 0)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let day = HabitSchedule.dateKey(now, timeZone: zone.identifier)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    let ru = snapshot.settings.language == .ru
    var requests: [UNNotificationRequest] = []
    for offset in 0...1 {
      guard let date = HabitSchedule.addDays(to: day, days: offset) else { continue }
      let occurrences = TaskSchedule.dayOccurrences(
        snapshot.tasks, date: date, language: snapshot.settings.language)
      for occurrence in occurrences where !occurrence.completed && occurrence.date == date {
        guard let time = occurrence.task.time,
          let start = formatter.date(from: "\(date) \(time)")
        else { continue }
        let fire = start.addingTimeInterval(-15 * 60)
        guard fire > now, fire < expiry else { continue }
        let content = UNMutableNotificationContent()
        content.title = ru ? "Ritm · Через 15 минут" : "Ritm · In 15 minutes"
        content.body = occurrence.task.title
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
          dateMatching: calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .timeZone], from: fire), repeats: false)
        requests.append(
          UNNotificationRequest(
            identifier: "ritm:\(ticket):task:\(occurrence.task.id):\(date)", content: content,
            trigger: trigger))
      }
      if snapshot.settings.dailyBriefing,
        let fire = formatter.date(from: "\(date) \(snapshot.settings.workDayStart)"), fire > now,
        fire < expiry
      {
        let content = UNMutableNotificationContent()
        content.title = ru ? "Ritm · Ваш день" : "Ritm · Your day"
        let count = occurrences.filter { !$0.completed }.count
        content.body =
          ru
          ? "В плане на сегодня: \(count). Откройте «Мой день»."
          : "Planned today: \(count). Open My day."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
          dateMatching: calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .timeZone], from: fire), repeats: false)
        requests.append(
          UNNotificationRequest(
            identifier: "ritm:\(ticket):brief:\(date)", content: content, trigger: trigger))
      }
    }
    guard ticket == revision else { return }
    center.removeAllPendingNotificationRequests()
    for request in requests.prefix(60) {
      guard ticket == revision else { return }
      try? await center.add(request)
      if ticket != revision {
        // An async add may finish after logout or a newer snapshot. Its
        // generation-specific ID cannot remove the replacement request.
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        return
      }
    }
  }
}
