import Foundation
import RitmCore

public struct WidgetTaskRow: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let completed: Bool?
  public let destination: URL
}
public struct WidgetHabitRow: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let icon: HabitIcon
  public let progress: Int
  public let target: Int
  public let completed: Bool
  public let destination: URL
}
public struct WidgetEventRow: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let start: Date
  public let end: Date
  public let timeLabel: String
  public let destination: URL
}
public enum WidgetCalendarState: String, Codable, Sendable { case ready, partial, unavailable }

/// Read-only, bounded projection. No email, API session, conversations or financial information.
/// Midnight expires the whole projection; yesterday's habits can never be ticked as today's.
public struct DayWidgetSnapshot: Codable, Equatable, Sendable {
  public static let schema = 1
  public let schemaVersion: Int
  public let contextID: String
  public let generatedAt: Date
  public let validUntil: Date
  public let date: String
  public let timeZone: String
  public let language: Language
  public let calendarState: WidgetCalendarState
  public let tasksCompleted: Int
  public let tasksTotal: Int
  public let tasksUnknown: Int
  public let habitsCompleted: Int
  public let habitsPlanned: Int
  public let tasks: [WidgetTaskRow]
  public let habits: [WidgetHabitRow]
  public let events: [WidgetEventRow]
  public var openURL: URL { URL(string: "ritm://open/day")! }
  public func isValid(at now: Date) -> Bool {
    schemaVersion == Self.schema && generatedAt <= now.addingTimeInterval(60)
      && validUntil > now && !contextID.isEmpty
      && TimeZone(identifier: timeZone) != nil && HabitSchedule.isValidDate(date)
      && date == HabitSchedule.dateKey(now, timeZone: timeZone)
      && tasks.count <= 3 && habits.count <= 3 && events.count <= 48
      && tasksCompleted >= 0 && tasksCompleted <= tasksTotal
      && tasksUnknown >= 0 && tasksUnknown <= tasksTotal - tasksCompleted
      && habitsCompleted >= 0 && habitsCompleted <= habitsPlanned
      && tasks.allSatisfy { $0.title.count <= 256 && $0.id.count <= 512 && valid($0.destination) }
      && habits.allSatisfy { $0.title.count <= 256 && $0.id.count <= 512 && $0.target > 0
        && $0.progress >= 0 && valid($0.destination) }
      && events.allSatisfy { $0.title.count <= 256 && $0.id.count <= 512 && $0.end > $0.start
        && valid($0.destination) }
  }
  private func valid(_ url: URL) -> Bool {
    ["ritm://open/day", "ritm://open/habits", "ritm://open/calendar"].contains(url.absoluteString)
  }
  public func nextEvent(at now: Date) -> WidgetEventRow? {
    events.first { $0.end > now }
  }
  /// System timelines advance the next event without JavaScript, polling or a running app.
  public func timelineDates(after now: Date) -> [Date] {
    Array(Set([now, validUntil] + events.flatMap { [$0.start, $0.end] }
      .filter { $0 > now && $0 < validUntil })).sorted()
  }

  public static func make(account: Bootstrap, habits: [Habit], events: [GoogleCalendarEvent],
    calendarState: WidgetCalendarState, contextID: String, expires: Date, now: Date) -> Self {
    let settings = account.settings
    let day = HabitSchedule.dateKey(now, timeZone: settings.timeZone)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: settings.timeZone) ?? .gmt
    let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    let summary = DayTaskSummary(tasks: account.tasks, events: events, date: day,
      timeZone: settings.timeZone, language: settings.language)
    var taskRows = summary.entries.map {
      WidgetTaskRow(id: $0.task.id, title: clipped($0.task.title), completed: $0.completed,
        destination: URL(string: "ritm://open/day")!)
    }
    taskRows += summary.googleTodos.map {
      WidgetTaskRow(id: $0.key, title: clipped($0.title),
        completed: $0.event?.googleTask.map { $0.status == "completed" },
        destination: URL(string: "ritm://open/day")!)
    }
    taskRows.sort { ($0.completed == true ? 1 : 0) < ($1.completed == true ? 1 : 0) }
    let planned = habits.filter { HabitSchedule.isScheduled($0, on: day) }
    let habitRows = planned.prefix(3).map { habit in
      WidgetHabitRow(id: habit.id, title: clipped(habit.title), icon: habit.icon ?? .sparkles,
        progress: HabitSchedule.progress(habit, on: day), target: HabitSchedule.target(habit),
        completed: HabitSchedule.isComplete(habit, on: day), destination: URL(string: "ritm://open/habits")!)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func instant(_ string: String?) -> Date? {
      guard let string else { return nil }
      return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
    let clock = DateFormatter(); clock.locale = Locale(identifier: "en_US_POSIX")
    clock.timeZone = calendar.timeZone; clock.dateFormat = "h:mm a"
    let eventRows: [WidgetEventRow] = events.compactMap { event in
      guard !event.allDay, let start = instant(event.start.dateTime),
        let end = instant(event.end.dateTime), end > now, start < midnight,
        event.googleTask?.status != "completed" else { return nil }
      return WidgetEventRow(id: event.id, title: clipped(event.title), start: start, end: end,
        timeLabel: clock.string(from: start), destination: URL(string: "ritm://open/calendar")!)
    }.sorted { $0.start < $1.start }
    return Self(schemaVersion: schema, contextID: contextID, generatedAt: now,
      validUntil: min(expires, midnight), date: day, timeZone: settings.timeZone,
      language: settings.language, calendarState: calendarState,
      tasksCompleted: summary.completed, tasksTotal: summary.count, tasksUnknown: summary.unknown,
      habitsCompleted: planned.filter { HabitSchedule.isComplete($0, on: day) }.count,
      habitsPlanned: planned.count, tasks: Array(taskRows.prefix(3)), habits: Array(habitRows),
      events: Array(eventRows.prefix(48)))
  }

  private static func clipped(_ string: String) -> String { String(string.prefix(256)) }

  /// Avoid a widget reload for an unchanged 30-second poll. The session-expiry boundary matters.
  public func hasSameContent(as other: Self) -> Bool {
    contextID == other.contextID && validUntil == other.validUntil && date == other.date
      && timeZone == other.timeZone && language == other.language && calendarState == other.calendarState
      && tasksCompleted == other.tasksCompleted && tasksTotal == other.tasksTotal
      && tasksUnknown == other.tasksUnknown && habitsCompleted == other.habitsCompleted
      && habitsPlanned == other.habitsPlanned && tasks == other.tasks && habits == other.habits
      && events == other.events
  }
}
