import Foundation
import RitmCore

public enum WorkoutActionPolicy {
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
    case .finishWorkout:
      // Finishing a journal record keeps the existing in-app confirmation flow.
      return (state, .ignoredNothingToDo)
    }
    return RestCommandReducer.apply(command: command, to: state, now: now, expectedVersion: state.version)
  }
}
