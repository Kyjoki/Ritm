import Foundation
import RitmCore

/// Small, public system-surface value. It never carries credentials or the rest of the account.
public struct WorkoutActivityState: Codable, Hashable, Sendable {
  public let content: LiveActivityContent
  public let startedAt: Date
  public let exerciseNumber: Int
  public let exerciseTotal: Int
  public let setID: String
  public let revision: String
  public let language: Language
  /// Readiness comes from the journal, even when load is hidden for privacy.
  public let requiredInput: WorkoutInputField?

  public init(content: LiveActivityContent, startedAt: Date, exerciseNumber: Int,
    exerciseTotal: Int, setID: String, revision: String, language: Language,
    requiredInput: WorkoutInputField? = nil) {
    self.content = content
    self.startedAt = startedAt
    self.exerciseNumber = exerciseNumber
    self.exerciseTotal = exerciseTotal
    self.setID = setID
    self.revision = revision
    self.language = language
    self.requiredInput = requiredInput
  }

  public func request(_ action: WorkoutSystemAction) -> WorkoutActionRequest {
    .init(workoutID: content.workoutID, setID: setID, revision: revision, action: action)
  }
  public func actionURL(_ action: WorkoutSystemAction) -> URL {
    request(action).url
  }
  public var openURL: URL { URL(string: "ritm://open/workout")! }
  public var staleDate: Date { content.restEndDate ?? content.staleDate }
  public var workoutID: String { content.workoutID }
}

public enum WorkoutSystemAction: String, Codable, Sendable {
  case extendRest, skipRest, confirmSet, editSet, finishWorkout
}

public enum WorkoutInputField: String, Codable, Hashable, Sendable { case weight, reps }

/// A validated navigation target, never a request to tick or change a set.
public struct WorkoutInputTarget: Equatable, Sendable {
  public let workoutID: String
  public let itemID: String
  public let setID: String
  public let field: WorkoutInputField
}

/// A revision-bound command, never an unguarded toggle. Replayed and stale links are rejected.
public struct WorkoutActionRequest: Codable, Equatable, Sendable {
  public let workoutID: String
  public let setID: String
  public let revision: String
  public let action: WorkoutSystemAction
  public init(workoutID: String, setID: String, revision: String, action: WorkoutSystemAction) {
    self.workoutID = workoutID; self.setID = setID; self.revision = revision; self.action = action
  }
  public var rawValue: String {
    (try? JSONEncoder().encode(self).base64EncodedString()) ?? ""
  }
  public init?(rawValue: String) {
    guard rawValue.utf8.count <= 4096, let bytes = Data(base64Encoded: rawValue),
      let value = try? JSONDecoder().decode(Self.self, from: bytes),
      !value.workoutID.isEmpty, value.workoutID.count <= 128, value.setID.count <= 128,
      UUID(uuidString: value.revision) != nil else { return nil }
    self = value
  }
  public var url: URL {
    var parts = URLComponents(); parts.scheme = "ritm"; parts.host = "workout-action"
    parts.queryItems = [.init(name: "request", value: rawValue)]
    return parts.url!
  }
  public init?(url: URL) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme?.lowercased() == "ritm", parts.host == "workout-action",
      parts.path.isEmpty, parts.user == nil, parts.password == nil, parts.port == nil,
      parts.fragment == nil, parts.queryItems?.count == 1,
      let value = parts.queryItems?.first, value.name == "request", let raw = value.value
    else { return nil }
    self.init(rawValue: raw)
  }
  public func matches(_ state: WorkoutActivityState) -> Bool {
    workoutID == state.workoutID && setID == state.setID && revision == state.revision
  }
}

#if canImport(ActivityKit)
import ActivityKit

/// The app and extension MUST link this exact module-qualified attributes type.
public struct RitmWorkoutAttributes: ActivityAttributes {
  public typealias ContentState = WorkoutActivityState
  public let workoutID: String
  public let startedAt: Date
  public init(workoutID: String, startedAt: Date) { self.workoutID = workoutID; self.startedAt = startedAt }
}
#endif

#if canImport(AppIntents) && RITM_INTERACTIVE
import AppIntents

@MainActor public enum WorkoutIntentRouter {
  public static var perform: ((WorkoutActionRequest) async throws -> Void)?
}

/// LiveActivityIntent executes in the main application process, on its existing workout store.
public struct RitmWorkoutActionIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Workout action"
  public static let openAppWhenRun: Bool = false
  public static let isDiscoverable: Bool = false
  @Parameter(title: "Request") public var request: String
  public init() {}
  public init(request: String) { self.request = request }
  public func perform() async throws -> some IntentResult {
    guard let value = WorkoutActionRequest(rawValue: request) else { throw WorkoutIntentFailure.invalid }
    try await Self.dispatch(value)
    return .result()
  }
  @MainActor private static func dispatch(_ request: WorkoutActionRequest) async throws {
    guard let handler = WorkoutIntentRouter.perform else { throw WorkoutIntentFailure.unavailable }
    try await handler(request)
  }
}
public enum WorkoutIntentFailure: LocalizedError {
  case invalid, unavailable, stale
  public var errorDescription: String? {
    let ru = Locale.preferredLanguages.first?.hasPrefix("ru") == true
    switch self {
    case .invalid: return ru ? "Не удалось прочитать действие." : "Could not read the action."
    case .unavailable: return ru ? "Откройте Ritm для продолжения тренировки." : "Open Ritm to continue the workout."
    case .stale: return ru ? "Проверьте текущий подход в Ritm." : "Check the current set in Ritm."
    }
  }
}
#endif
