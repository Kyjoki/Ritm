import Foundation

// The local «Отдых закончился» notification as a pure value: when it fires and what it says.
// The app only hands this to UserNotifications; whether to schedule at all is decided here.

public struct RestNotificationPlan: Equatable, Sendable {
  public let identifier: String
  /// The absolute end of the running rest.
  public let fireDate: Date
  public let title: String
  public let body: String

  public init(identifier: String, fireDate: Date, title: String, body: String) {
    self.identifier = identifier
    self.fireDate = fireDate
    self.title = title
    self.body = body
  }
}

public enum RestNotificationPlanner {
  public static let identifierPrefix = "ritm.workout.rest."

  /// One stable identifier per workout, so scheduling again replaces the pending request.
  public static func identifier(workoutID: String) -> String { identifierPrefix + workoutID }

  /// `nil` when nothing should be pending: no workout, no running rest, the rest is already over,
  /// or no set is left to do. `privacy` drops weights from the text (it is shown on a lock screen).
  public static func plan(
    state: SharedWorkoutState, privacy: Bool, russian: Bool, now: Date
  ) -> RestNotificationPlan? {
    guard let session = state.session, state.phase(now: now) == .rest,
      let end = state.rest.endDate, end > now,
      let content = LiveActivityContent.make(from: state, privacy: privacy, now: now)
    else { return nil }
    let set = russian ? "подход" : "set"
    var body = "\(russian ? "Дальше" : "Next"): \(content.exerciseName) · \(set) \(content.setNumber)/\(content.setTotal)"
    if let load = load(content, russian: russian) { body += " · \(load)" }
    return RestNotificationPlan(
      identifier: identifier(workoutID: session.id), fireDate: end,
      title: russian ? "Отдых закончился" : "Rest is over", body: body)
  }

  private static func load(_ content: LiveActivityContent, russian: Bool) -> String? {
    let kg = russian ? "кг" : "kg"
    switch (content.plannedWeight, content.plannedReps) {
    case (let weight?, let reps?): return "\(weight) \(kg) × \(reps)"
    case (let weight?, nil): return "\(weight) \(kg)"
    case (nil, let reps?): return "\(reps) \(russian ? "повт." : "reps")"
    case (nil, nil): return nil
    }
  }
}
