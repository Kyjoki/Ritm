import Foundation

/// Why a settings change is held back instead of being sent.
public enum SettingsIssue: Equatable, Hashable, Sendable {
  case emptyName, nameTooLong, invalidEmail, workDayOrder, unknownTimeZone

  public func message(_ language: Language) -> String {
    let ru = language == .ru
    switch self {
    case .emptyName:
      return ru
        ? "Введи имя, которым к тебе будет обращаться помощник."
        : "Enter the name the assistant should use for you."
    case .nameTooLong: return ru ? "Имя не длиннее 60 символов." : "The name is at most 60 characters."
    case .invalidEmail: return ru ? "Проверь адрес почты." : "Check the email address."
    case .workDayOrder:
      return ru
        ? "Конец рабочего дня должен быть позже начала." : "The workday must end after it starts."
    case .unknownTimeZone: return ru ? "Неизвестный часовой пояс." : "Unknown time zone."
    }
  }
}

/// The part of a patch that may be sent, what was held back, and which fields are to blame.
public struct SettingsCheck: Equatable, Sendable {
  public let valid: AccountSettingsPatch
  public let issues: [SettingsIssue]
  public let invalidFields: Set<SettingsField>
}

/// The rules the server enforces (`settingsPatchSchema`, `updateSettings`), applied before a
/// change leaves the phone, so an invalid value is never sent.
public enum SettingsValidator {
  public static let nameLimit = 60
  public static let emailLimit = 254

  /// `draft` is the whole settings object the patch belongs to: the workday is judged as a pair.
  public static func check(_ patch: AccountSettingsPatch, in draft: AccountSettings)
    -> SettingsCheck
  {
    var valid = patch
    var issues: [SettingsIssue] = []
    var invalid: Set<SettingsField> = []
    func reject(_ issue: SettingsIssue, _ fields: Set<SettingsField>) {
      if !issues.contains(issue) { issues.append(issue) }
      invalid.formUnion(fields)
    }
    if let name = patch.displayName {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        reject(.emptyName, [.displayName])
      } else if trimmed.count > nameLimit {
        reject(.nameTooLong, [.displayName])
      } else {
        valid.displayName = trimmed
      }
    }
    if let email = patch.email {
      let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || isPlausibleEmail(trimmed) {
        valid.email = trimmed
      } else {
        reject(.invalidEmail, [.email])
      }
    }
    if let zone = patch.timeZone, TimeZone(identifier: zone) == nil {
      reject(.unknownTimeZone, [.timeZone])
    }
    if patch.workDayStart != nil || patch.workDayEnd != nil,
      !WorkDayBounds.isValid(start: draft.workDayStart, end: draft.workDayEnd)
    {
      reject(.workDayOrder, [.workDayStart, .workDayEnd])
    }
    return SettingsCheck(
      valid: valid.removing(invalid), issues: issues, invalidFields: invalid)
  }

  /// `z.email()` in spirit: one `@`, a dotted domain, no spaces.
  static func isPlausibleEmail(_ value: String) -> Bool {
    guard value.count <= emailLimit, !value.contains(where: \.isWhitespace) else { return false }
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return false }
    let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
    return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty } && (labels.last?.count ?? 0) >= 2
  }
}

/// The working day as a pair of "HH:mm" strings that always satisfies start < end.
public enum WorkDayBounds {
  /// Moving one end past the other drags the other end an hour along, as the prototype does.
  public static let dragMinutes = 60

  public static func isValid(start: String, end: String) -> Bool {
    guard let from = TaskSchedule.timeMinutes(start), let to = TaskSchedule.timeMinutes(end)
    else { return false }
    return from < to
  }

  public static func settingStart(_ time: String, start: String, end: String)
    -> (start: String, end: String)
  {
    guard let minute = TaskSchedule.timeMinutes(time) else { return (start, end) }
    let newStart = min(minute, 1438)
    let currentEnd = TaskSchedule.timeMinutes(end) ?? 1439
    let newEnd = newStart >= currentEnd ? min(1439, newStart + dragMinutes) : currentEnd
    return (TaskSchedule.minuteTime(newStart), TaskSchedule.minuteTime(newEnd))
  }

  public static func settingEnd(_ time: String, start: String, end: String)
    -> (start: String, end: String)
  {
    guard let minute = TaskSchedule.timeMinutes(time) else { return (start, end) }
    let newEnd = max(minute, 1)
    let currentStart = TaskSchedule.timeMinutes(start) ?? 0
    let newStart = newEnd <= currentStart ? max(0, newEnd - dragMinutes) : currentStart
    return (TaskSchedule.minuteTime(newStart), TaskSchedule.minuteTime(newEnd))
  }
}
