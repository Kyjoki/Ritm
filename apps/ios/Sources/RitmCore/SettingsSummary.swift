import Foundation

/// The time zones the list offers (SettingsPage.tsx `TIME_ZONES`), with names in both languages.
public enum SettingsTimeZones {
  public struct Zone: Equatable, Sendable {
    public let id: String
    public let nameRU: String
    public let nameEN: String

    public func name(_ language: Language) -> String { language == .ru ? nameRU : nameEN }

    /// The part before the first comma: «Алматы, Астана» is shown as «Алматы» in a row.
    public func city(_ language: Language) -> String {
      String(name(language).split(separator: ",").first ?? "").trimmingCharacters(in: .whitespaces)
    }
  }

  public static let all: [Zone] = [
    Zone(id: "Asia/Qyzylorda", nameRU: "Кызылорда", nameEN: "Qyzylorda"),
    Zone(id: "Asia/Almaty", nameRU: "Алматы, Астана", nameEN: "Almaty, Astana"),
    Zone(id: "Europe/Moscow", nameRU: "Москва", nameEN: "Moscow"),
    Zone(id: "Europe/Kyiv", nameRU: "Киев", nameEN: "Kyiv"),
    Zone(id: "Europe/Minsk", nameRU: "Минск", nameEN: "Minsk"),
    Zone(id: "Asia/Tashkent", nameRU: "Ташкент", nameEN: "Tashkent"),
    Zone(id: "Asia/Bishkek", nameRU: "Бишкек", nameEN: "Bishkek"),
    Zone(id: "Europe/Berlin", nameRU: "Берлин", nameEN: "Berlin"),
    Zone(id: "Europe/London", nameRU: "Лондон", nameEN: "London"),
    Zone(id: "America/New_York", nameRU: "Нью-Йорк", nameEN: "New York"),
    Zone(id: "UTC", nameRU: "Всемирное время", nameEN: "Coordinated Universal Time"),
  ]

  /// The list, with the account's own zone first when it is not one of them.
  public static func zones(including current: String) -> [Zone] {
    if all.contains(where: { $0.id == current }) { return all }
    return [Zone(id: current, nameRU: current, nameEN: current)] + all
  }

  public static func zone(_ id: String) -> Zone {
    all.first { $0.id == id } ?? Zone(id: id, nameRU: id, nameEN: id)
  }

  /// «UTC+5», «UTC+5:30», «UTC−5» (a real minus), «UTC» for the zone named UTC.
  public static func offsetLabel(_ id: String, at date: Date) -> String {
    guard id != "UTC" else { return "UTC" }
    let seconds = TimeZone(identifier: id)?.secondsFromGMT(for: date) ?? 0
    let minutes = abs(seconds) / 60
    let sign = seconds < 0 ? "\u{2212}" : "+"
    let clock = minutes % 60 == 0
      ? "\(minutes / 60)" : "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    return "UTC" + sign + clock
  }

  /// «Алматы · UTC+5»: the row value.
  public static func rowValue(_ id: String, language: Language, at date: Date) -> String {
    if id == "UTC" { return "UTC" }
    return "\(zone(id).city(language)) · \(offsetLabel(id, at: date))"
  }
}

/// The colour of the small status dot in front of a value.
public enum SettingsTone: Equatable, Sendable { case none, ok, warn, error }

/// A trailing value of a settings row and the dot before it.
public struct SettingsTrailing: Equatable, Sendable {
  public let text: String
  public let tone: SettingsTone
  public init(_ text: String, _ tone: SettingsTone = .none) {
    self.text = text
    self.tone = tone
  }
}

/// What the rows of the main settings list say on their right, worked out from plain facts so it
/// can be tested without a screen. Every function takes the language and returns both parts.
public enum SettingsSummary {
  private static func pick(_ language: Language, _ ru: String, _ en: String) -> String {
    language == .ru ? ru : en
  }

  /// «09:00–21:00»
  public static func dayRange(start: String, end: String) -> String { "\(start)\u{2013}\(end)" }

  public static func languageName(_ language: Language) -> String {
    language == .ru ? "Русский" : "English"
  }

  public static func themeName(_ theme: Theme, _ language: Language) -> String {
    switch theme {
    case .light: pick(language, "Светлая", "Light")
    case .dark: pick(language, "Тёмная", "Dark")
    case .system: pick(language, "Системная", "System")
    }
  }

  /// How many of the two reminder switches are on, for a collapsed summary.
  public static func notificationsOn(_ settings: AccountSettings) -> Int {
    [settings.notifications, settings.dailyBriefing].filter { $0 }.count
  }

  public static func phonePermission(granted: Bool?, _ language: Language) -> SettingsTrailing {
    switch granted {
    case .some(true): SettingsTrailing(pick(language, "Разрешены", "Allowed"), .ok)
    case .some(false): SettingsTrailing(pick(language, "Выключены", "Off"), .warn)
    case .none: SettingsTrailing(pick(language, "Не выбрано", "Not chosen"), .none)
    }
  }

  public static func google(
    status: GoogleCalendarStatus?, setup: GoogleOAuthSetup?, _ language: Language
  ) -> SettingsTrailing {
    guard let status else { return SettingsTrailing(pick(language, "Не загружено", "Not loaded")) }
    let configured = setup?.configured ?? status.configured
    switch status.status {
    case .connected: return SettingsTrailing(pick(language, "Подключён", "Connected"), .ok)
    case .reauthRequired:
      return SettingsTrailing(pick(language, "Переподключить", "Reconnect"), .warn)
    default:
      return configured
        ? SettingsTrailing(pick(language, "Не подключён", "Not connected"))
        : SettingsTrailing(pick(language, "Нужен клиент", "Client needed"), .warn)
    }
  }

  public static func telegram(_ status: TelegramStatus?, _ language: Language) -> SettingsTrailing {
    guard let status else { return SettingsTrailing(pick(language, "Не загружено", "Not loaded")) }
    if status.linked { return SettingsTrailing(pick(language, "Подключён", "Connected"), .ok) }
    return status.configured
      ? SettingsTrailing(pick(language, "Чат не привязан", "Chat not linked"), .warn)
      : SettingsTrailing(pick(language, "Не подключён", "Not connected"))
  }

  public static func openAI(_ status: AIStatus?, _ language: Language) -> SettingsTrailing {
    guard let status else { return SettingsTrailing(pick(language, "Не загружено", "Not loaded")) }
    if status.configured {
      let managed = status.source == "environment"
      return SettingsTrailing(
        managed ? pick(language, "На сервере", "On server") : pick(language, "Ключ задан", "Key set"),
        .ok)
    }
    return SettingsTrailing(pick(language, "Нет ключа", "No key"))
  }

  /// `nil` while the server has not answered (or has no security endpoints).
  public static func security(totpEnabled: Bool?, _ language: Language) -> SettingsTrailing? {
    guard let totpEnabled else { return nil }
    return totpEnabled
      ? SettingsTrailing(pick(language, "2FA включена", "2FA on"), .ok)
      : SettingsTrailing(pick(language, "2FA выключена", "2FA off"), .warn)
  }

  public static func sessions(_ count: Int, _ language: Language) -> String {
    guard language == .ru else { return "\(count) " + (count == 1 ? "session" : "sessions") }
    return "\(count) " + plural(count, "сеанс", "сеанса", "сеансов")
  }

  /// Russian plural forms: 1 сеанс, 2 сеанса, 5 сеансов, 11 сеансов, 21 сеанс.
  public static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let mod10 = n % 10
    let mod100 = n % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if (2...4).contains(mod10) && !(10..<20).contains(mod100) { return few }
    return many
  }
}
