import Foundation

// The Live Activity of an active workout, as pure values. ActivityKit is only fed what this file
// decides: a small content value, and whether it really changed (never "every second": the rest
// countdown runs on the absolute `restEndDate`, drawn by the system).

public struct LiveActivityContent: Codable, Hashable, Sendable {
  /// How long a card without a running rest stays fresh after the workout started.
  public static let idleStaleInterval: TimeInterval = 6 * 3_600
  /// Extra time after the rest end before the card counts as stale.
  public static let restStaleGrace: TimeInterval = 30

  public let workoutID: String
  public let programName: String
  public let exerciseName: String
  /// 1-based number of the current set inside its exercise, and how many the exercise has.
  public let setNumber: Int
  public let setTotal: Int
  /// PLANNED values (what the set is pre-filled with), never shown as done. `nil` when hidden or
  /// not valid.
  public let plannedWeight: String?
  public let plannedReps: Int?
  public let phase: WorkoutPhase
  /// Absolute end of the running rest; the countdown is drawn from it.
  public let restEndDate: Date?
  /// Whole seconds left of a paused rest (it does not change while paused).
  public let pausedRestSeconds: Int?
  public let hidesWeights: Bool
  public let staleDate: Date

  public init(
    workoutID: String, programName: String, exerciseName: String, setNumber: Int, setTotal: Int,
    plannedWeight: String?, plannedReps: Int?, phase: WorkoutPhase, restEndDate: Date?,
    pausedRestSeconds: Int?, hidesWeights: Bool, staleDate: Date
  ) {
    self.workoutID = workoutID
    self.programName = programName
    self.exerciseName = exerciseName
    self.setNumber = setNumber
    self.setTotal = setTotal
    self.plannedWeight = plannedWeight
    self.plannedReps = plannedReps
    self.phase = phase
    self.restEndDate = restEndDate
    self.pausedRestSeconds = pausedRestSeconds
    self.hidesWeights = hidesWeights
    self.staleDate = staleDate
  }

  /// «Подход 3/3»
  public var setLabel: String { "Подход \(setNumber)/\(setTotal)" }

  /// Everything except the stale date, which moves with the clock and must not cause an update.
  private var visible: LiveActivityContent {
    LiveActivityContent(
      workoutID: workoutID, programName: programName, exerciseName: exerciseName, setNumber: setNumber,
      setTotal: setTotal, plannedWeight: plannedWeight, plannedReps: plannedReps, phase: phase,
      restEndDate: restEndDate, pausedRestSeconds: pausedRestSeconds, hidesWeights: hidesWeights,
      staleDate: .distantPast)
  }

  /// `nil` when there is no workout to show. A finished-all workout still yields a card
  /// (phase `allDone`) until the app ends it.
  public static func make(
    from state: SharedWorkoutState, privacy: Bool, now: Date
  ) -> LiveActivityContent? {
    guard let session = state.session, !session.items.isEmpty else { return nil }
    let phase = state.phase(now: now)
    let position = state.current ?? lastPosition(session)
    guard let position else { return nil }
    let item = session.items[position.exercise]
    let set = item.sets[position.set]

    let weight = privacy ? nil : WorkoutNumber.normalizedWeight(set.weight)
    let reps = WorkoutNumber.reps(set.reps)

    var restEnd: Date?
    var paused: Int?
    switch phase {
    case .rest: restEnd = state.rest.endDate
    case .paused: paused = Int(state.rest.remaining(now: now).rounded(.up))
    case .set, .allDone: break
    }
    let stale = restEnd.map { $0.addingTimeInterval(restStaleGrace) }
      ?? session.startedAt.addingTimeInterval(idleStaleInterval)

    return LiveActivityContent(
      workoutID: session.id, programName: session.programName, exerciseName: item.name,
      setNumber: position.set + 1, setTotal: item.sets.count,
      plannedWeight: phase == .allDone ? nil : weight, plannedReps: phase == .allDone ? nil : reps,
      phase: phase, restEndDate: restEnd, pausedRestSeconds: paused, hidesWeights: privacy,
      staleDate: max(stale, now))
  }

  /// Convenience for a session and its rest timer.
  public static func make(
    from session: WorkoutSession?, rest: RestTimer, privacy: Bool, now: Date
  ) -> LiveActivityContent? {
    make(from: SharedWorkoutState(session: session, rest: rest), privacy: privacy, now: now)
  }

  private static func lastPosition(_ session: WorkoutSession) -> (exercise: Int, set: Int)? {
    guard let e = session.items.lastIndex(where: { !$0.sets.isEmpty }) else { return nil }
    return (e, session.items[e].sets.count - 1)
  }

  /// True only when something the card shows changed. The stale date alone never counts.
  public static func shouldUpdate(old: LiveActivityContent?, new: LiveActivityContent?) -> Bool {
    switch (old, new) {
    case (nil, nil): return false
    case (nil, _), (_, nil): return true
    case (let old?, let new?): return old.visible != new.visible
    }
  }
}

public enum LiveActivityDecision: Equatable, Sendable {
  case none
  case start(workoutID: String)
  case update(workoutID: String)
  case end(workoutID: String)
  /// An activity of another workout is still around: end it, then start the new one.
  case replace(ending: String, starting: String)
}

public enum LiveActivityLifecycle {
  /// What to do with ActivityKit.
  /// - `content`: what the active workout should show now (`nil` when there is no workout).
  /// - `existing`: the content last pushed to the activity that is alive (`nil` when none).
  /// - `enabled`: the owner's setting and the system permission for Live Activities.
  public static func decide(
    content: LiveActivityContent?, existing: LiveActivityContent?, enabled: Bool
  ) -> LiveActivityDecision {
    guard let content, enabled else {
      // No workout (or Live Activities off): never leave a ghost card behind.
      return existing.map { .end(workoutID: $0.workoutID) } ?? .none
    }
    guard let existing else { return .start(workoutID: content.workoutID) }
    guard existing.workoutID == content.workoutID else {
      return .replace(ending: existing.workoutID, starting: content.workoutID)
    }
    return LiveActivityContent.shouldUpdate(old: existing, new: content)
      ? .update(workoutID: content.workoutID) : .none
  }
}
