import Foundation

public enum Theme: String, Codable, Sendable, CaseIterable { case light, dark, system }
public enum Language: String, Codable, Sendable, CaseIterable { case ru, en }
public enum Priority: String, Codable, Sendable, CaseIterable { case low, normal, high }
public enum TaskRepeat: String, Codable, Sendable, CaseIterable {
  case none, daily, weekly, monthly
}
public enum TaskKind: String, Codable, Sendable, CaseIterable { case task, event }
public enum HabitIcon: String, Codable, Sendable, CaseIterable {
  case sparkles, book, activity, droplet, moon, target
}

/// The server stores date-only values in the owner's calendar, never the device's time zone.
public struct RitmTask: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var title: String
  public var description: String
  public var date: String?
  public var time: String?
  public var duration: Int
  public var priority: Priority
  public var `repeat`: TaskRepeat
  public var kind: TaskKind
  public var completed: Bool
  public var calendarEntry: Bool?
  public var colorId: String?
  public var completedDates: [String]
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String, title: String, description: String = "", date: String? = nil,
    time: String? = nil, duration: Int = 30, priority: Priority = .normal,
    `repeat` recurrence: TaskRepeat = .none, kind: TaskKind = .task,
    completed: Bool = false, calendarEntry: Bool? = false, colorId: String? = nil,
    completedDates: [String] = [], createdAt: String = "", updatedAt: String = ""
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.date = date
    self.time = time
    self.duration = duration
    self.priority = priority
    self.repeat = recurrence
    self.kind = kind
    self.completed = completed
    self.calendarEntry = calendarEntry
    self.colorId = colorId
    self.completedDates = completedDates
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public func isComplete(on date: String) -> Bool {
    self.repeat == .none ? completed : completedDates.contains(date)
  }

  public var input: TaskInput {
    TaskInput(
      title: title, description: description, date: date, time: time, duration: duration,
      priority: priority, repeat: self.repeat, kind: kind, completed: completed,
      calendarEntry: calendarEntry, colorId: colorId)
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, description, date, time, duration, priority, `repeat`, kind, completed
    case calendarEntry, colorId, completedDates, createdAt, updatedAt
  }

  public func encode(to encoder: any Encoder) throws {
    // Restore requires the same nullable schedule fields as creation.
    try input.encode(to: encoder)
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(completedDates, forKey: .completedDates)
    try values.encode(createdAt, forKey: .createdAt)
    try values.encode(updatedAt, forKey: .updatedAt)
  }
}

public struct TaskInput: Codable, Sendable, Equatable {
  public var title: String
  public var description: String
  public var date: String?
  public var time: String?
  public var duration: Int
  public var priority: Priority
  public var `repeat`: TaskRepeat
  public var kind: TaskKind
  public var completed: Bool
  public var calendarEntry: Bool?
  public var colorId: String?

  public init(
    title: String, description: String = "", date: String? = nil, time: String? = nil,
    duration: Int = 30, priority: Priority = .normal, `repeat` recurrence: TaskRepeat = .none,
    kind: TaskKind = .task, completed: Bool = false,
    calendarEntry: Bool? = false, colorId: String? = nil
  ) {
    self.title = title
    self.description = description
    self.date = date
    self.time = time
    self.duration = duration
    self.priority = priority
    self.repeat = recurrence
    self.kind = kind
    self.completed = completed
    self.calendarEntry = calendarEntry
    self.colorId = colorId
  }

  private enum CodingKeys: String, CodingKey {
    case title, description, date, time, duration, priority, `repeat`, kind, completed
    case calendarEntry, colorId
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(title, forKey: .title)
    try values.encode(description, forKey: .description)
    // These two keys are required and nullable in the strict server schema.
    try values.encode(date, forKey: .date)
    try values.encode(time, forKey: .time)
    try values.encode(duration, forKey: .duration)
    try values.encode(priority, forKey: .priority)
    try values.encode(self.repeat, forKey: .repeat)
    try values.encode(kind, forKey: .kind)
    try values.encode(completed, forKey: .completed)
    try values.encodeIfPresent(calendarEntry, forKey: .calendarEntry)
    try values.encode(colorId, forKey: .colorId)
  }
}

public struct HabitInput: Codable, Sendable, Equatable {
  public var title: String
  public var icon: HabitIcon?
  public var weekdays: [Int]?
  public var target: Int?
  public var unit: String?
  public var archived: Bool?

  public init(
    title: String, icon: HabitIcon? = .sparkles, weekdays: [Int]? = nil,
    target: Int? = nil, unit: String? = nil, archived: Bool? = false
  ) {
    self.title = title
    self.icon = icon
    self.weekdays = weekdays
    self.target = target
    self.unit = unit
    self.archived = archived
  }

  private enum CodingKeys: String, CodingKey { case title, icon, weekdays, target, unit, archived }
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(title, forKey: .title)
    try values.encodeIfPresent(icon, forKey: .icon)
    try values.encodeIfPresent(weekdays, forKey: .weekdays)
    // PATCH merges fields: null explicitly changes a quantitative habit back to one tap.
    try values.encode(target, forKey: .target)
    try values.encodeIfPresent(unit, forKey: .unit)
    try values.encodeIfPresent(archived, forKey: .archived)
  }
}

public struct HabitPeriod: Codable, Sendable, Equatable {
  public var from: String
  public var weekdays: [Int]
  public var archived: Bool

  public init(from: String, weekdays: [Int], archived: Bool = false) {
    self.from = from
    self.weekdays = weekdays
    self.archived = archived
  }
}

public struct Habit: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var title: String
  public var icon: HabitIcon?
  public var weekdays: [Int]?
  public var target: Int?
  public var unit: String?
  public var archived: Bool?
  public var startDate: String
  public var completedDates: [String]
  public var progressByDate: [String: Int]?
  public var periods: [HabitPeriod]?
  public var achievements: [Int]?
  public var createdAt: String
  public var updatedAt: String

  public var input: HabitInput {
    HabitInput(
      title: title, icon: icon, weekdays: weekdays, target: target, unit: unit, archived: archived)
  }

  public init(
    id: String, title: String, icon: HabitIcon? = .sparkles,
    weekdays: [Int]? = nil, target: Int? = nil, unit: String? = nil,
    archived: Bool? = false, startDate: String, completedDates: [String] = [],
    progressByDate: [String: Int]? = nil, periods: [HabitPeriod]? = nil,
    achievements: [Int]? = nil, createdAt: String = "", updatedAt: String = ""
  ) {
    self.id = id
    self.title = title
    self.icon = icon
    self.weekdays = weekdays
    self.target = target
    self.unit = unit
    self.archived = archived
    self.startDate = startDate
    self.completedDates = completedDates
    self.progressByDate = progressByDate
    self.periods = periods
    self.achievements = achievements
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct AccountSettings: Codable, Sendable, Equatable {
  public var displayName: String
  public var email: String
  public var theme: Theme
  public var sidebar: String
  public var language: Language
  public var timeZone: String
  public var notifications: Bool
  public var dailyBriefing: Bool
  public var workDayStart: String
  public var workDayEnd: String

  public init(
    displayName: String = "", email: String = "", theme: Theme = .system,
    sidebar: String = "dark", language: Language = .ru,
    timeZone: String = "Asia/Qyzylorda", notifications: Bool = false,
    dailyBriefing: Bool = false, workDayStart: String = "09:00", workDayEnd: String = "18:00"
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
}

public struct Session: Codable, Sendable, Equatable {
  public var authenticated: Bool
  public var requiresLogin: Bool
  public init(authenticated: Bool, requiresLogin: Bool) {
    self.authenticated = authenticated
    self.requiresLogin = requiresLogin
  }
}

public struct AIStatus: Codable, Sendable, Equatable {
  public var configured: Bool
  public var model: String
  public var source: String
  public init(configured: Bool = false, model: String = "", source: String = "none") {
    self.configured = configured
    self.model = model
    self.source = source
  }
}

public struct Conversation: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var title: String
  public var messages: [ChatMessage]
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String, title: String, messages: [ChatMessage] = [], createdAt: String = "",
    updatedAt: String = ""
  ) {
    self.id = id
    self.title = title
    self.messages = messages
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var role: String
  public var text: String
  public var createdAt: String
  public var proposals: [ScheduleProposal]
  public var steps: [String]
  public var ideaReview: IdeaReviewReport?

  public init(
    id: String, role: String, text: String, createdAt: String = "",
    proposals: [ScheduleProposal] = [], steps: [String] = [], ideaReview: IdeaReviewReport? = nil
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.createdAt = createdAt
    self.proposals = proposals
    self.steps = steps
    self.ideaReview = ideaReview
  }
}

public struct Bootstrap: Codable, Sendable, Equatable {
  public var tasks: [RitmTask]
  public var settings: AccountSettings
  public var conversations: [Conversation]
  public var aiStatus: AIStatus

  public init(
    tasks: [RitmTask] = [], settings: AccountSettings = .init(),
    conversations: [Conversation] = [], aiStatus: AIStatus = .init()
  ) {
    self.tasks = tasks
    self.settings = settings
    self.conversations = conversations
    self.aiStatus = aiStatus
  }
}

public enum GoogleConnectionState: String, Codable, Sendable {
  case unconfigured, disconnected, connected
  case reauthRequired = "reauth_required"
}

public struct GoogleCalendarStatus: Codable, Sendable, Equatable {
  public var configured: Bool
  public var status: GoogleConnectionState
  public var mode: String
  public var calendarId: String
  public var lastFetchedAt: String?
  public var extendedColors: Bool?
  public var tasksEnabled: Bool?

  public init(
    configured: Bool = false, status: GoogleConnectionState = .unconfigured,
    mode: String = "readwrite", calendarId: String = "primary", lastFetchedAt: String? = nil,
    extendedColors: Bool? = nil, tasksEnabled: Bool? = nil
  ) {
    self.configured = configured
    self.status = status
    self.mode = mode
    self.calendarId = calendarId
    self.lastFetchedAt = lastFetchedAt
    self.extendedColors = extendedColors
    self.tasksEnabled = tasksEnabled
  }
}

public struct CalendarBoundary: Codable, Sendable, Equatable {
  public var date: String?
  public var dateTime: String?
  public init(date: String? = nil, dateTime: String? = nil) {
    self.date = date
    self.dateTime = dateTime
  }
}

public struct GoogleTaskCompletion: Codable, Sendable, Equatable {
  public var taskListId: String
  public var id: String
  public var etag: String
  public var status: String
  public var completed: String?
  public var connectionId: String
  public init(
    taskListId: String, id: String, etag: String, status: String,
    completed: String? = nil, connectionId: String
  ) {
    self.taskListId = taskListId
    self.id = id
    self.etag = etag
    self.status = status
    self.completed = completed
    self.connectionId = connectionId
  }
}

public struct GoogleCalendarEvent: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var source: String
  public var calendarId: String
  public var title: String
  public var description: String
  public var etag: String
  public var start: CalendarBoundary
  public var end: CalendarBoundary
  public var timeZone: String
  public var allDay: Bool
  public var busy: Bool
  public var readOnly: Bool
  public var colorId: String?
  public var recurring: Bool?
  public var readOnlyReason: String?
  public var taskLink: Bool?
  public var taskUnavailableReason: String?
  public var googleTask: GoogleTaskCompletion?

  public init(
    id: String, title: String, description: String = "", etag: String = "",
    start: CalendarBoundary, end: CalendarBoundary, timeZone: String,
    allDay: Bool = false, busy: Bool = true, readOnly: Bool = true,
    source: String = "google", calendarId: String = "primary", colorId: String? = nil,
    recurring: Bool? = nil, readOnlyReason: String? = nil, taskLink: Bool? = nil,
    taskUnavailableReason: String? = nil, googleTask: GoogleTaskCompletion? = nil
  ) {
    self.id = id
    self.source = source
    self.calendarId = calendarId
    self.title = title
    self.description = description
    self.etag = etag
    self.start = start
    self.end = end
    self.timeZone = timeZone
    self.allDay = allDay
    self.busy = busy
    self.readOnly = readOnly
    self.colorId = colorId
    self.recurring = recurring
    self.readOnlyReason = readOnlyReason
    self.taskLink = taskLink
    self.taskUnavailableReason = taskUnavailableReason
    self.googleTask = googleTask
  }
}

public struct GoogleTasksStatus: Codable, Sendable, Equatable {
  public var status: String
  public var message: String?
  public init(status: String, message: String? = nil) {
    self.status = status
    self.message = message
  }
}

public struct GoogleCalendarResult: Codable, Sendable, Equatable {
  public var events: [GoogleCalendarEvent]
  public var from: String
  public var to: String
  public var timeZone: String
  public var fetchedAt: String
  public var partial: Bool
  public var tasks: GoogleTasksStatus?

  public init(
    events: [GoogleCalendarEvent], from: String, to: String, timeZone: String,
    fetchedAt: String, partial: Bool = false, tasks: GoogleTasksStatus? = nil
  ) {
    self.events = events
    self.from = from
    self.to = to
    self.timeZone = timeZone
    self.fetchedAt = fetchedAt
    self.partial = partial
    self.tasks = tasks
  }
}
