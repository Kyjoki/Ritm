import Foundation
import RitmCore

public enum WorkoutActionPolicy {
  public static func requiredInput(in state: SharedWorkoutState) -> WorkoutInputField? {
    guard let session = state.session, let position = state.current else { return nil }
    let set = session.items[position.exercise].sets[position.set]
    if WorkoutNumber.normalizedWeight(set.weight) == nil || WorkoutNumber.weight(set.weight) == nil {
      return .weight
    }
    return WorkoutNumber.reps(set.reps) == nil ? .reps : nil
  }

  /// A stale or foreign card cannot focus a different workout. Opening input never mutates it.
  public static func inputTarget(_ request: WorkoutActionRequest,
    displayed: WorkoutActivityState?, state: SharedWorkoutState) -> WorkoutInputTarget? {
    guard request.action == .editSet || request.action == .confirmSet,
      let displayed, request.matches(displayed), state.sessionID == request.workoutID,
      let session = state.session, let position = state.current,
      let field = requiredInput(in: state) else { return nil }
    let item = session.items[position.exercise]
    guard item.sets[position.set].id == request.setID else { return nil }
    return WorkoutInputTarget(workoutID: session.id, itemID: item.id,
      setID: request.setID, field: field)
  }

  /// Validation is repeated against the live journal, not just against what the card showed.
  public static func apply(_ request: WorkoutActionRequest, displayed: WorkoutActivityState?,
    state: SharedWorkoutState, now: Date) -> (state: SharedWorkoutState, outcome: RestCommandOutcome) {
    guard let displayed, request.matches(displayed), state.sessionID == request.workoutID,
      let session = state.session, let position = state.current,
      session.items[position.exercise].sets[position.set].id == request.setID
    else { return (state, .ignoredStale) }
    let command: RestCommand
    switch request.action {
    case .confirmSet:
      guard state.phase(now: now) == .set else { return (state, .ignoredNothingToDo) }
      command = .confirmNextSet
    case .extendRest:
      guard state.rest.endDate != nil || state.rest.pausedRemaining != nil else {
        return (state, .ignoredNothingToDo)
      }
      command = .extend(seconds: RestTimer.extensionStep)
    case .skipRest: command = .skip
    case .editSet, .finishWorkout:
      // Finishing a journal record keeps the existing in-app confirmation flow.
      return (state, .ignoredNothingToDo)
    }
    return RestCommandReducer.apply(command: command, to: state, now: now, expectedVersion: state.version)
  }
}
