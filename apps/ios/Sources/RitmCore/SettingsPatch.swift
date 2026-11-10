import Foundation

/// One field of the account settings, so the autosave can say which changes are waiting.
public enum SettingsField: CaseIterable, Hashable, Sendable {
  case displayName, email, theme, sidebar, language, timeZone, notifications, dailyBriefing
  case workDayStart, workDayEnd
}

/// A partial `PATCH /api/settings` body: only the fields that changed are encoded, so a value
/// this device never touched can never overwrite a newer one on the server.
public struct AccountSettingsPatch: Codable, Equatable, Sendable {
  public var displayName: String?
  public var email: String?
  public var theme: Theme?
  public var sidebar: String?
  public var language: Language?
  public var timeZone: String?
  public var notifications: Bool?
  public var dailyBriefing: Bool?
  public var workDayStart: String?
  public var workDayEnd: String?

  public init(
    displayName: String? = nil, email: String? = nil, theme: Theme? = nil, sidebar: String? = nil,
    language: Language? = nil, timeZone: String? = nil, notifications: Bool? = nil,
    dailyBriefing: Bool? = nil, workDayStart: String? = nil, workDayEnd: String? = nil
  ) {
    self.displayName = displayName
    self.email = email
    self.theme = theme
    self.sidebar = sidebar
    self.language = language
    self.timeZone = timeZone
    self.notifications = notifications
    self.dailyBriefing = dailyBriefing
    self.workDayStart = workDayStart
    self.workDayEnd = workDayEnd
  }

  public var fields: Set<SettingsField> {
    var result: Set<SettingsField> = []
    if displayName != nil { result.insert(.displayName) }
    if email != nil { result.insert(.email) }
    if theme != nil { result.insert(.theme) }
    if sidebar != nil { result.insert(.sidebar) }
    if language != nil { result.insert(.language) }
    if timeZone != nil { result.insert(.timeZone) }
    if notifications != nil { result.insert(.notifications) }
    if dailyBriefing != nil { result.insert(.dailyBriefing) }
    if workDayStart != nil { result.insert(.workDayStart) }
    if workDayEnd != nil { result.insert(.workDayEnd) }
    return result
  }

  public var isEmpty: Bool { fields.isEmpty }

  /// The patch with `newer` laid over it: a field set in both takes the newer value.
  public func overlaid(by newer: AccountSettingsPatch) -> AccountSettingsPatch {
    var result = self
    if let value = newer.displayName { result.displayName = value }
    if let value = newer.email { result.email = value }
    if let value = newer.theme { result.theme = value }
    if let value = newer.sidebar { result.sidebar = value }
    if let value = newer.language { result.language = value }
    if let value = newer.timeZone { result.timeZone = value }
    if let value = newer.notifications { result.notifications = value }
    if let value = newer.dailyBriefing { result.dailyBriefing = value }
    if let value = newer.workDayStart { result.workDayStart = value }
    if let value = newer.workDayEnd { result.workDayEnd = value }
    return result
  }

  /// The settings with every field of this patch replaced.
  public func applied(to settings: AccountSettings) -> AccountSettings {
    var result = settings
    if let value = displayName { result.displayName = value }
    if let value = email { result.email = value }
    if let value = theme { result.theme = value }
    if let value = sidebar { result.sidebar = value }
    if let value = language { result.language = value }
    if let value = timeZone { result.timeZone = value }
    if let value = notifications { result.notifications = value }
    if let value = dailyBriefing { result.dailyBriefing = value }
    if let value = workDayStart { result.workDayStart = value }
    if let value = workDayEnd { result.workDayEnd = value }
    return result
  }

  /// The values `settings` holds for `fields`.
  public static func snapshot(of settings: AccountSettings, fields: Set<SettingsField>)
    -> AccountSettingsPatch
  {
    func pick<Value>(_ field: SettingsField, _ value: Value) -> Value? {
      fields.contains(field) ? value : nil
    }
    return AccountSettingsPatch(
      displayName: pick(.displayName, settings.displayName), email: pick(.email, settings.email),
      theme: pick(.theme, settings.theme), sidebar: pick(.sidebar, settings.sidebar),
      language: pick(.language, settings.language), timeZone: pick(.timeZone, settings.timeZone),
      notifications: pick(.notifications, settings.notifications),
      dailyBriefing: pick(.dailyBriefing, settings.dailyBriefing),
      workDayStart: pick(.workDayStart, settings.workDayStart),
      workDayEnd: pick(.workDayEnd, settings.workDayEnd))
  }

  /// The fields where `new` differs from `base`.
  public static func diff(from base: AccountSettings, to new: AccountSettings)
    -> AccountSettingsPatch
  {
    var changed: Set<SettingsField> = []
    for field in SettingsField.allCases
    where snapshot(of: base, fields: [field]) != snapshot(of: new, fields: [field]) {
      changed.insert(field)
    }
    return snapshot(of: new, fields: changed)
  }

  /// Only the given fields.
  public func keeping(_ kept: Set<SettingsField>) -> AccountSettingsPatch {
    Self.snapshot(of: applied(to: AccountSettings()), fields: fields.intersection(kept))
  }

  /// Everything except the given fields.
  public func removing(_ removed: Set<SettingsField>) -> AccountSettingsPatch {
    keeping(fields.subtracting(removed))
  }
}
