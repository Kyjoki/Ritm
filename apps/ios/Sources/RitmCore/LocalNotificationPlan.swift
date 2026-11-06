import Foundation

/// Navigation only. A notification never claims to complete a server task or book a purchase.
public enum LocalNotificationDestination: Equatable, Sendable {
  case day
  case task(id: String, date: String)
  case googleEvent(id: String, calendarID: String, date: String)
  case wallet(id: String)
  case workout(id: String)

  public static let userInfoKey = "ritm.destination"
  public static let accountEpochUserInfoKey = "ritm.accountEpoch"

  public var url: URL {
    var parts = URLComponents()
    parts.scheme = "ritm"
    parts.host = "open"
    switch self {
    case .day: parts.path = "/day"
    case .task(let id, let date):
      parts.path = "/task"
      parts.queryItems = [.init(name: "id", value: id), .init(name: "date", value: date)]
    case .googleEvent(let id, let calendarID, let date):
      parts.path = "/event"
      parts.queryItems = [
        .init(name: "id", value: id), .init(name: "calendar", value: calendarID),
        .init(name: "date", value: date),
      ]
    case .wallet(let id):
      parts.path = "/wallet"
      parts.queryItems = [.init(name: "id", value: id)]
    case .workout(let id):
      parts.path = "/workout"
      parts.queryItems = [.init(name: "id", value: id)]
    }
    return parts.url!
  }

  public init?(url: URL) {
    guard url.absoluteString.utf8.count <= 4096,
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme?.lowercased() == "ritm", parts.host?.lowercased() == "open",
      parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil
    else { return nil }
    let items = parts.queryItems ?? []
    // Duplicate parameters and extra parameters are not alternative instructions.
    guard Set(items.map(\.name)).count == items.count else { return nil }
    func value(_ name: String) -> String? {
      guard let value = items.first(where: { $0.name == name })?.value,
        !value.isEmpty, value.utf8.count <= 512,
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { return nil }
      return value
    }
    switch parts.path {
    case "/day":
      guard items.isEmpty else { return nil }
      self = .day
    case "/task":
      guard items.count == 2, let id = value("id"), let date = value("date"),
        HabitSchedule.isValidDate(date)
      else { return nil }
      self = .task(id: id, date: date)
    case "/event":
      guard items.count == 3, let id = value("id"), let calendar = value("calendar"),
        let date = value("date"), HabitSchedule.isValidDate(date)
      else { return nil }
      self = .googleEvent(id: id, calendarID: calendar, date: date)
    case "/wallet":
      guard items.count == 1, let id = value("id") else { return nil }
      self = .wallet(id: id)
    case "/workout":
      guard items.count == 1, let id = value("id") else { return nil }
      self = .workout(id: id)
    default: return nil
    }
  }
}

public enum LocalNotificationNamespace {
  public static let account = "ritm.account."
  public static let reminders = account + "reminder."
  public static let wallet = account + "wallet."

  /// Earlier native reminders used this exact shape. Do not sweep arbitrary "ritm:" requests.
  public static func isLegacyReminder(_ identifier: String) -> Bool {
    let parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
    return parts.count >= 4 && parts[0] == "ritm" && Int(parts[1]) != nil
      && (parts[2] == "task" || parts[2] == "brief")
  }

  /// Stable across processes; unlike Swift Hasher this can be used for system request IDs.
  public static func key(_ parts: String...) -> String { key(parts) }

  public static func key(_ parts: [String]) -> String {
    var value: UInt64 = 0xcbf2_9ce4_8422_2325
    // Length-prefixing avoids collisions between different component boundaries.
    for part in parts {
      for byte in "\(part.utf8.count):\(part)".utf8 {
        value ^= UInt64(byte)
        value = value &* 0x0000_0100_0000_01b3
      }
    }
    return String(value, radix: 16)
  }
}

/// A logical notification. The reconciler assigns a unique physical request ID to each add.
public struct LocalNotificationPlan: Equatable, Sendable {
  public let identifier: String
  /// nil is an immediate, one-off notice, never a repeating trigger.
  public let fireDate: Date?
  public let title: String
  public let body: String
  public let threadIdentifier: String
  public let categoryIdentifier: String
  public let destination: LocalNotificationDestination
  public let expiresAt: Date?
  /// An opaque account-epoch tag, never a server credential.
  public let accountEpoch: String?

  public init(
    identifier: String, fireDate: Date?, title: String, body: String, threadIdentifier: String,
    categoryIdentifier: String, destination: LocalNotificationDestination, expiresAt: Date? = nil,
    accountEpoch: String? = nil
  ) {
    self.identifier = identifier
    self.fireDate = fireDate
    self.title = title
    self.body = body
    self.threadIdentifier = threadIdentifier
    self.categoryIdentifier = categoryIdentifier
    self.destination = destination
    self.expiresAt = expiresAt
    self.accountEpoch = accountEpoch
  }
}

public enum LocalNotificationPlanner {
  public static let leadChoices = [0, 5, 10, 15, 30, 60]
  /// Leave room for the active workout, wallet arrivals, and future system features.
  public static let maximumReminders = 48
  public static let horizon: TimeInterval = 48 * 60 * 60

  public static func plans(
    snapshot: Bootstrap, events: [GoogleCalendarEvent] = [], calendarReady: Bool = false,
    calendarPartial: Bool = false, leadMinutes: Int = 15, accountEpoch: String = "current",
    until expiry: Date, now: Date, limit: Int = maximumReminders
  ) -> [LocalNotificationPlan] {
    guard snapshot.settings.notifications, expiry > now,
      leadChoices.contains(leadMinutes), let zone = TimeZone(identifier: snapshot.settings.timeZone)
    else { return [] }
    let end = min(expiry, now.addingTimeInterval(horizon))
    let ru = snapshot.settings.language == .ru
    let epoch = LocalNotificationNamespace.key(accountEpoch)
    var wanted: [String: LocalNotificationPlan] = [:]
    let today = HabitSchedule.dateKey(now, timeZone: zone.identifier)
    // 48 absolute hours can touch four civil dates during a fall-back transition.
    for offset in 0...3 {
      guard let day = HabitSchedule.addDays(to: today, days: offset) else { continue }
      let occurrences = TaskSchedule.dayOccurrences(
        snapshot.tasks, date: day, language: snapshot.settings.language)
      for entry in occurrences where !entry.completed && entry.date == day {
        guard let time = entry.task.time,
          let start = localInstant(day: day, time: time, zone: zone)
        else { continue }
        let fire = start.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fire > now, fire < end else { continue }
        let identifier = LocalNotificationNamespace.reminders
          + "\(epoch).task." + LocalNotificationNamespace.key(entry.task.id, day)
        let finish = (1...1440).contains(entry.task.duration)
          ? start.addingTimeInterval(Double(entry.task.duration) * 60) : nil
        wanted[identifier] = LocalNotificationPlan(
          identifier: identifier, fireDate: fire, title: entry.task.title,
          body: NotificationTimeFormatting.range(start: start, end: finish, timeZone: zone,
            language: snapshot.settings.language, relativeTo: fire),
          threadIdentifier: "ritm.reminders", categoryIdentifier: "RITM_TASK_REMINDER",
          destination: .task(id: entry.task.id, date: day), expiresAt: expiry, accountEpoch: epoch)
      }
      if snapshot.settings.dailyBriefing,
        let fire = localInstant(day: day, time: snapshot.settings.workDayStart, zone: zone),
        fire > now, fire < end
      {
        let identifier = LocalNotificationNamespace.reminders + "\(epoch).brief.\(day)"
        wanted[identifier] = LocalNotificationPlan(
          identifier: identifier, fireDate: fire,
          title: ru ? "Ritm · Ваш день" : "Ritm · Your day",
          // Calendar fetches may cover only today. Do not present a partial task count as a total.
          body: ru ? "Откройте «Мой день», чтобы посмотреть план." : "Open My day to see your plan.",
          threadIdentifier: "ritm.brief", categoryIdentifier: "RITM_DAILY_BRIEF",
          destination: .day, expiresAt: expiry, accountEpoch: epoch)
      }
    }
    // An unavailable or partial snapshot is not authority for future Calendar reminders.
    if calendarReady && !calendarPartial {
      for event in events {
        let representsTask = event.taskLink == true || event.googleTask != nil
          || event.taskUnavailableReason != nil
        if representsTask && event.googleTask?.status != "needsAction" { continue }
        guard !event.allDay, let start = CalendarEventPolicy.instant(event.start.dateTime),
          let finish = CalendarEventPolicy.instant(event.end.dateTime), finish > start
        else { continue }
        let fire = start.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fire > now, fire < end else { continue }
        let identifier = LocalNotificationNamespace.reminders
          + "\(epoch).google." + LocalNotificationNamespace.key(event.calendarId, event.id)
        wanted[identifier] = LocalNotificationPlan(
          identifier: identifier, fireDate: fire, title: event.title,
          body: NotificationTimeFormatting.range(start: start, end: finish, timeZone: zone,
            language: snapshot.settings.language, relativeTo: fire),
          threadIdentifier: "ritm.reminders", categoryIdentifier: "RITM_GOOGLE_REMINDER",
          destination: .googleEvent(
            id: event.id, calendarID: event.calendarId,
            date: HabitSchedule.dateKey(start, timeZone: zone.identifier)), expiresAt: expiry,
          accountEpoch: epoch)
      }
    }
    return Array(wanted.values.sorted {
      ($0.fireDate ?? .distantPast, $0.identifier) < ($1.fireDate ?? .distantPast, $1.identifier)
    }.prefix(max(0, min(maximumReminders, limit))))
  }

  /// Reject nonexistent and ambiguous wall times instead of inventing an instant around DST.
  static func localInstant(day: String, time: String, zone: TimeZone) -> Date? {
    guard HabitSchedule.isValidDate(day), let minute = TaskSchedule.timeMinutes(time) else {
      return nil
    }
    let date = day.split(separator: "-").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = zone
    let parts = DateComponents(
      year: date[0], month: date[1], day: date[2], hour: minute / 60, minute: minute % 60,
      second: 0)
    guard let instant = calendar.date(from: parts) else { return nil }
    let checked = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
    guard checked.year == parts.year, checked.month == parts.month, checked.day == parts.day,
      checked.hour == parts.hour, checked.minute == parts.minute, checked.second == 0,
      !CalendarEventPolicy.isAmbiguous(instant, zone: zone)
    else { return nil }
    return instant
  }
}

public enum WalletNotificationPlanner {
  public static let maximumNotices = 12

  public static func plan(
    purchase: WalletPurchase, language: Language, accountEpoch: String, until expiry: Date? = nil
  ) -> LocalNotificationPlan? {
    guard !purchase.isTest else { return nil }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
    formatter.minimumFractionDigits = purchase.amountMinor.isMultiple(of: 100) ? 0 : 2
    formatter.maximumFractionDigits = 2
    let amount = formatter.string(from: NSDecimalNumber(value: purchase.amountMinor).dividing(by: 100))
      ?? String(format: "%.2f", Double(purchase.amountMinor) / 100)
    return LocalNotificationPlan(
      identifier: LocalNotificationNamespace.wallet
        + LocalNotificationNamespace.key(accountEpoch) + "."
        + LocalNotificationNamespace.key(purchase.id),
      fireDate: nil,
      title: language == .ru ? "Новая покупка" : "New purchase",
      body: "\(purchase.merchant) · \(amount) \(purchase.currency.rawValue)\n"
        + (language == .ru ? "Откройте Ritm, чтобы подтвердить." : "Open Ritm to confirm."),
      threadIdentifier: "ritm.wallet", categoryIdentifier: "RITM_WALLET_PURCHASE",
      destination: .wallet(id: purchase.id), expiresAt: expiry,
      accountEpoch: LocalNotificationNamespace.key(accountEpoch))
  }
}
