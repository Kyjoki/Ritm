import Foundation

public struct GoogleOAuthSetup: Codable, Sendable, Equatable {
  public var configured: Bool
  public var source: String
  public var clientId: String
  public var hasClientSecret: Bool
  public var redirectUri: String?
  public init(
    configured: Bool, source: String, clientId: String, hasClientSecret: Bool, redirectUri: String?
  ) {
    self.configured = configured
    self.source = source
    self.clientId = clientId
    self.hasClientSecret = hasClientSecret
    self.redirectUri = redirectUri
  }
}

public struct GoogleOAuthSetupInput: Encodable, Sendable {
  public var clientId: String
  public var clientSecret: String?
  public init(clientId: String, clientSecret: String? = nil) {
    self.clientId = clientId
    self.clientSecret = clientSecret
  }
}

public struct GoogleAuthorization: Codable, Sendable, Equatable {
  public var authorizationUrl: String
  public init(authorizationUrl: String) { self.authorizationUrl = authorizationUrl }
}

public struct GoogleEventInput: Codable, Sendable, Equatable {
  public var title: String
  public var description: String
  public var date: String
  public var time: String?
  public var duration: Int
  public var allDay: Bool
  public var colorId: String?
  public var `repeat`: TaskRepeat?
  /// When true, `colorId` is left out of the body so Google keeps the event's current color.
  /// Edits and moves must not resend an unchanged color (AGENTS.md); the web does the same.
  public var preservesProviderColor: Bool
  public init(
    title: String, description: String = "", date: String, time: String? = nil,
    duration: Int = 30, allDay: Bool = false, colorId: String? = nil,
    `repeat` recurrence: TaskRepeat? = nil, preservesProviderColor: Bool = false
  ) {
    self.title = title
    self.description = description
    self.date = date
    self.time = time
    self.duration = duration
    self.allDay = allDay
    self.colorId = colorId
    self.repeat = recurrence
    self.preservesProviderColor = preservesProviderColor
  }
  private enum CodingKeys: String, CodingKey {
    case title, description, date, time, duration, allDay, colorId, `repeat`
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      title: try values.decode(String.self, forKey: .title),
      description: try values.decodeIfPresent(String.self, forKey: .description) ?? "",
      date: try values.decode(String.self, forKey: .date),
      time: try values.decodeIfPresent(String.self, forKey: .time),
      duration: try values.decode(Int.self, forKey: .duration),
      allDay: try values.decode(Bool.self, forKey: .allDay),
      colorId: try values.decodeIfPresent(String.self, forKey: .colorId),
      repeat: try values.decodeIfPresent(TaskRepeat.self, forKey: .repeat),
      preservesProviderColor: !values.contains(.colorId))
  }
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(title, forKey: .title)
    try values.encode(description, forKey: .description)
    try values.encode(date, forKey: .date)
    try values.encode(time, forKey: .time)
    try values.encode(duration, forKey: .duration)
    try values.encode(allDay, forKey: .allDay)
    if !preservesProviderColor { try values.encode(colorId, forKey: .colorId) }
    try values.encodeIfPresent(self.repeat, forKey: .repeat)
  }
}

public struct GoogleTransferResult: Codable, Sendable, Equatable {
  public var event: GoogleCalendarEvent
  public var transferredTaskId: String
  public init(event: GoogleCalendarEvent, transferredTaskId: String) {
    self.event = event
    self.transferredTaskId = transferredTaskId
  }
}

public struct TelegramAccount: Codable, Sendable, Equatable {
  public var username: String?
  public var firstName: String
  public init(username: String? = nil, firstName: String) {
    self.username = username
    self.firstName = firstName
  }
}

public struct TelegramReminders: Codable, Sendable, Equatable {
  public var enabled: Bool
  public var leadMinutes: Int
  public var timeZone: String
  public var ready: Bool
  public var schedulerActive: Bool
  public var googleConnected: Bool
  /// Unix milliseconds, as returned by the existing API.
  public var lastRunAt: Double?
  public var problem: String?
  public init(
    enabled: Bool, leadMinutes: Int, timeZone: String, ready: Bool, schedulerActive: Bool,
    googleConnected: Bool, lastRunAt: Double? = nil, problem: String? = nil
  ) {
    self.enabled = enabled
    self.leadMinutes = leadMinutes
    self.timeZone = timeZone
    self.ready = ready
    self.schedulerActive = schedulerActive
    self.googleConnected = googleConnected
    self.lastRunAt = lastRunAt
    self.problem = problem
  }
}

public struct TelegramStatus: Codable, Sendable, Equatable {
  public var configured: Bool
  public var linked: Bool
  public var botUsername: String?
  public var account: TelegramAccount?
  public var pairingUrl: String?
  /// Unix milliseconds, not seconds.
  public var pairingExpiresAt: Double?
  public var reminders: TelegramReminders?
  public init(
    configured: Bool, linked: Bool, botUsername: String? = nil, account: TelegramAccount? = nil,
    pairingUrl: String? = nil, pairingExpiresAt: Double? = nil, reminders: TelegramReminders? = nil
  ) {
    self.configured = configured
    self.linked = linked
    self.botUsername = botUsername
    self.account = account
    self.pairingUrl = pairingUrl
    self.pairingExpiresAt = pairingExpiresAt
    self.reminders = reminders
  }
}
