import Foundation

// Commands that come from OUTSIDE the app (a Live Activity button / App Intent later) and change
// the active workout. A pure reducer: no actors, no clock of its own, no side effects, so races
// and duplicates are decided here and can be tested on Linux.

public enum RestCommand: Equatable, Sendable {
  /// «+30 с»: moves the absolute end date of the rest (or starts a rest of just that length).
  case extend(seconds: TimeInterval)
  /// «Пропустить»: ends the rest. Never ticks a set.
  case skip
  /// «Подход выполнен»: ticks the next unfinished set and starts the rest.
  case confirmNextSet
}

public enum WorkoutPhase: String, Codable, Equatable, Sendable {
  case set, rest, paused, allDone
}

/// What the app and the outside world share about the active workout.
public struct SharedWorkoutState: Codable, Equatable, Sendable {
  /// Counts applied changes. A command carries the version it was made for.
  public var version: Int
  public var session: WorkoutSession?
  public var rest: RestTimer
  /// When the last confirm was applied: a second confirm right after it is a double tap.
  public var lastConfirmAt: Date?

  public init(
    version: Int = 0, session: WorkoutSession? = nil, rest: RestTimer = RestTimer(),
    lastConfirmAt: Date? = nil
  ) {
    self.version = version
    self.session = session
    self.rest = rest
    self.lastConfirmAt = lastConfirmAt
  }

  public init(_ active: WorkoutActiveState, version: Int = 0) {
    self.init(version: version, session: active.session, rest: active.rest)
  }

  public var activeState: WorkoutActiveState { WorkoutActiveState(session: session, rest: rest) }

  public var sessionID: String? { session?.id }

  /// Indexes of the first unfinished set; `nil` when every set is done (or there is no workout).
  public var current: (exercise: Int, set: Int)? {
    guard let session else { return nil }
    for (e, item) in session.items.enumerated() {
      if let s = item.sets.firstIndex(where: { !$0.done }) { return (e, s) }
    }
    return nil
  }

  public var currentExerciseIndex: Int? { current?.exercise }
  public var currentSetIndex: Int? { current?.set }

  public func phase(now: Date) -> WorkoutPhase {
    guard session != nil, current != nil else { return .allDone }
    switch rest.phase(now: now) {
    case .running: return .rest
    case .paused: return .paused
    case .idle, .finished: return .set
    }
  }
}

public enum RestCommandRejection: String, Equatable, Sendable {
  case invalidSeconds, needsWeight, needsReps, allSetsDone
}

public enum RestCommandOutcome: Equatable, Sendable {
  case applied
  /// The command was made for an older state; nothing changed.
  case ignoredStale
  /// The same action just happened (a double tap); nothing changed.
  case ignoredDuplicate
  case ignoredNoWorkout
  /// Skip with no rest to skip.
  case ignoredNothingToDo
  case rejected(RestCommandRejection)
}

public enum RestCommandReducer {
  public static let maxExtension: TimeInterval = 600
  /// A confirm this soon after the previous one is a double tap, not a second set.
  public static let confirmDebounce: TimeInterval = 2

  /// Applies one command. `expectedVersion` is the version the sender saw (`nil` when it did not
  /// look). Only an applied command bumps the version, so of two commands made for the same
  /// version only the first one can win.
  public static func apply(
    command: RestCommand, to state: SharedWorkoutState, now: Date, expectedVersion: Int?
  ) -> (state: SharedWorkoutState, outcome: RestCommandOutcome) {
    if let expectedVersion, expectedVersion != state.version { return (state, .ignoredStale) }
    guard state.session != nil else { return (state, .ignoredNoWorkout) }

    var next = state
    let outcome: RestCommandOutcome
    switch command {
    case .extend(let seconds): outcome = extend(seconds, in: &next, now: now)
    case .skip: outcome = skip(&next, now: now)
    case .confirmNextSet: outcome = confirm(&next, now: now)
    }
    guard outcome == .applied else { return (state, outcome) }
    next.version = state.version + 1
    return (next, .applied)
  }

  private static func extend(_ seconds: TimeInterval, in state: inout SharedWorkoutState, now: Date)
    -> RestCommandOutcome
  {
    guard seconds.isFinite, seconds > 0 else { return .rejected(.invalidSeconds) }
    state.rest.extend(now: now, by: min(seconds, maxExtension))
    return .applied
  }

  private static func skip(_ state: inout SharedWorkoutState, now: Date) -> RestCommandOutcome {
    switch state.rest.phase(now: now) {
    case .running, .paused:
      state.rest.skip()
      return .applied
    case .idle, .finished:
      guard state.rest.endDate != nil else { return .ignoredNothingToDo }
      state.rest.skip()
      return .applied
    }
  }

  private static func confirm(_ state: inout SharedWorkoutState, now: Date) -> RestCommandOutcome {
    if let last = state.lastConfirmAt, abs(now.timeIntervalSince(last)) < confirmDebounce {
      return .ignoredDuplicate
    }
    guard let position = state.current, var session = state.session else {
      return .rejected(.allSetsDone)
    }
    let item = session.items[position.exercise]
    let setID = item.sets[position.set].id
    var result = WorkoutSessionItem.TickResult.missing
    session.update(item.id) { result = $0.toggle(setID: setID) }
    switch result {
    case .done: break
    case .needsWeight: return .rejected(.needsWeight)
    case .needsReps: return .rejected(.needsReps)
    case .undone, .missing: return .ignoredNothingToDo
    }
    state.session = session
    state.lastConfirmAt = now
    // The last set ends the workout's work: no rest after it.
    if state.current == nil {
      state.rest.reset()
    } else {
      state.rest.restart(now: now, seconds: TimeInterval(item.restSeconds))
    }
    return .applied
  }
}

extension SharedWorkoutState {
  public func applying(
    _ command: RestCommand, now: Date, expectedVersion: Int?
  ) -> (state: SharedWorkoutState, outcome: RestCommandOutcome) {
    RestCommandReducer.apply(command: command, to: self, now: now, expectedVersion: expectedVersion)
  }
}

/// The spec's free function form.
public func apply(
  command: RestCommand, to state: SharedWorkoutState, now: Date, expectedVersion: Int?
) -> (state: SharedWorkoutState, outcome: RestCommandOutcome) {
  RestCommandReducer.apply(command: command, to: state, now: now, expectedVersion: expectedVersion)
}
