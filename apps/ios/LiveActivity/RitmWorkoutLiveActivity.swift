import ActivityKit
import RitmCore
import RitmSystem
import SwiftUI
import WidgetKit
#if RITM_INTERACTIVE
import AppIntents
#endif

/// The workout owns the data. The system draws the absolute countdown, without per-second
/// timeline entries or background execution in the app.
struct RitmWorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RitmWorkoutAttributes.self) { context in
      WorkoutLockScreenCard(state: context.state, stale: context.isStale)
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(.primary)
        .widgetURL(URL(string: "ritm://open/workout"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            RitmSystemMark(size: 18)
            Text(context.state.content.exerciseName)
              .font(.system(size: 13, weight: .semibold)).lineLimit(2)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          WorkoutPhaseMetric(state: context.state,
                             restExpired: context.isStale && context.state.content.phase == .rest)
            .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            .frame(maxWidth: 90, alignment: .trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 8) {
            HStack {
              Text(context.state.setLabel)
              Spacer()
              WorkoutPrescription(state: context.state)
            }
            .font(.system(size: 11))
            WorkoutActions(state: context.state, restExpired: context.isStale && context.state.content.phase == .rest)
          }
        }
      } compactLeading: {
        RitmSystemMark(size: 17)
      } compactTrailing: {
        WorkoutPhaseMetric(state: context.state,
                           restExpired: context.isStale && context.state.content.phase == .rest)
          .font(.system(size: 12, weight: .semibold).monospacedDigit())
          .frame(maxWidth: 54)
      } minimal: {
        RitmSystemMark(size: 18)
      }
      .widgetURL(URL(string: "ritm://open/workout"))
      .keylineTint(.white.opacity(0.65))
    }
  }
}

private struct WorkoutLockScreenCard: View {
  let state: WorkoutActivityState
  let stale: Bool
  @Environment(\.colorScheme) private var colorScheme
  private var restExpired: Bool { stale && state.content.phase == .rest }

  var body: some View {
    VStack(spacing: 5) {
      HStack(spacing: 7) {
        RitmSystemMark(size: 18)
        Text(state.content.exerciseName)
          .font(.system(size: 13, weight: .semibold))
          .tracking(-0.2).lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("\(state.exerciseNumber) / \(state.exerciseTotal)")
          .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
          .fixedSize()
      }
      .frame(height: 28)

      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 0) {
          Text(restExpired ? state.text("Отдых закончен", "Rest finished") : state.phaseTitle)
            .font(.system(size: 9, weight: .medium)).lineLimit(1)
          WorkoutPhaseMetric(state: state, restExpired: restExpired)
            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            .tracking(-1).lineLimit(1).minimumScaleFactor(0.8)
            .contentTransition(.numericText())
        }
        .frame(width: 94, height: 46, alignment: .leading)
        .padding(.leading, 10)
        .background(.primary.opacity(colorScheme == .dark ? 0.13 : 0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)

        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text(state.content.phase == .allDone
                 ? state.text("Все подходы выполнены", "All sets complete")
                 : state.content.hidesWeights
                 ? state.text("Повторения", "Planned reps")
                 : state.text("Рабочий вес", "Planned load"))
            Spacer(minLength: 4)
            if state.content.phase != .allDone {
              Text("\(state.content.setNumber)/\(state.content.setTotal)").monospacedDigit()
            }
          }
          .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
          WorkoutPrescription(state: state)
            .font(.system(size: 17, weight: .semibold)).tracking(-0.45)
            .lineLimit(1).minimumScaleFactor(0.8)
          WorkoutSetProgress(state: state)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      }
      .frame(height: 46)

      WorkoutActions(state: state, restExpired: restExpired)
    }
    .padding(.horizontal, 14)
    .frame(height: 158)
    .background(.ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5)
    }
    .accessibilityLabel(state.text("Тренировка Ritm", "Ritm workout"))
    .accessibilityValue(restExpired
      ? state.text("Отдых закончен", "Rest finished") : stale
      ? state.text("Откройте Ritm для актуальных данных", "Open Ritm to refresh") : "")
  }
}

private struct WorkoutPhaseMetric: View {
  let state: WorkoutActivityState
  var restExpired = false
  var body: some View {
    if restExpired {
      Text(state.text("Готово", "Ready"))
    } else if let end = state.content.restEndDate {
      Text(timerInterval: state.startedAt...max(end, state.startedAt),
           countsDown: true, showsHours: false)
    } else if let paused = state.content.pausedRestSeconds {
      Text(WorkoutClock.format(seconds: paused))
    } else if state.content.phase == .allDone {
      Image(systemName: "checkmark")
    } else {
      Text("\(state.content.setNumber) / \(state.content.setTotal)")
    }
  }
}

private struct WorkoutPrescription: View {
  let state: WorkoutActivityState
  var body: some View {
    if state.content.phase == .allDone {
      Text(state.text("Готово", "Done"))
    } else if state.content.hidesWeights {
      if let reps = state.content.plannedReps {
        Text("\(reps) " + state.text("повт.", "reps"))
      } else {
        Text(state.text("Вес скрыт", "Load hidden")).foregroundStyle(.secondary)
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        if let weight = state.content.plannedWeight {
          Text(weight)
          Text(state.text("кг", "kg"))
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        if let reps = state.content.plannedReps {
          if state.content.plannedWeight != nil { Text("×") }
          Text("\(reps)")
        }
        if state.content.plannedWeight == nil && state.content.plannedReps == nil {
          Text(state.text("Заполните в Ritm", "Enter in Ritm"))
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      .monospacedDigit()
    }
  }
}

private struct WorkoutSetProgress: View {
  let state: WorkoutActivityState
  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<min(state.content.setTotal, 12), id: \.self) { index in
        let done = state.content.phase == .allDone || index + 1 < state.content.setNumber
        let current = index + 1 == state.content.setNumber
        VStack(spacing: 1) {
          if done {
            Image(systemName: "checkmark").font(.system(size: 7, weight: .bold))
          } else {
            Text("\(index + 1)").font(.system(size: 7, weight: current ? .semibold : .regular))
          }
          Capsule().fill(.primary.opacity(done || current ? 0.85 : 0.16)).frame(height: 2)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(done || current ? .primary : .secondary)
      }
    }
    .frame(height: 10)
    .accessibilityHidden(true)
  }
}

private struct WorkoutActions: View {
  let state: WorkoutActivityState
  var restExpired = false
  private var primary: WorkoutSystemAction {
    if restExpired { return .confirmSet }
    switch state.content.phase {
    case .rest, .paused: return .skipRest
    case .set: return .confirmSet
    case .allDone: return .finishWorkout
    }
  }
  private var primaryLabel: String {
    if restExpired { return state.text("Подход выполнен", "Complete set") }
    switch state.content.phase {
    case .rest, .paused: return state.text("Пропустить", "Skip rest")
    case .set: return state.text("Подход выполнен", "Complete set")
    case .allDone: return state.text("Завершить тренировку", "Finish workout")
    }
  }
  var body: some View {
    HStack(spacing: 7) {
      if !restExpired && (state.content.phase == .rest || state.content.phase == .paused) {
        action(.extendRest) {
          Text(state.text("+15 с", "+15 s")).frame(minWidth: 43, maxHeight: .infinity)
        }
        .frame(width: 65)
        .background(.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityLabel(state.text("Добавить 15 секунд отдыха", "Add 15 seconds of rest"))
      }
      action(primary) {
        HStack(spacing: 7) {
          if restExpired || state.content.phase == .set || state.content.phase == .allDone {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
          }
          Text(primaryLabel).lineLimit(1).minimumScaleFactor(0.8)
          if !restExpired && (state.content.phase == .rest || state.content.phase == .paused) {
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 12)
      }
      .frame(maxWidth: .infinity)
      .background(.primary.opacity(0.12),
                  in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
    .font(.system(size: 11, weight: .semibold)).frame(height: 44).buttonStyle(.plain)
  }

  @ViewBuilder
  private func action<Label: View>(
    _ action: WorkoutSystemAction, @ViewBuilder label: () -> Label
  ) -> some View {
    // Finishing is reviewed in the app. The ordinary build opens it for the same guarded action;
    // the verified App Intents mode can perform set/rest commands without foregrounding it.
    #if RITM_INTERACTIVE
    if action != .finishWorkout {
      Button(intent: RitmWorkoutActionIntent(request: state.request(action).rawValue)) { label() }
    } else {
      Link(destination: state.actionURL(action)) { label() }
    }
    #else
    Link(destination: state.actionURL(action)) { label() }
    #endif
  }
}

private extension WorkoutActivityState {
  func text(_ ru: String, _ en: String) -> String { language == .ru ? ru : en }
  var setLabel: String {
    text("Подход \(content.setNumber)/\(content.setTotal)",
         "Set \(content.setNumber)/\(content.setTotal)")
  }
  var phaseTitle: String {
    switch content.phase {
    case .rest: return text("Отдых", "Rest")
    case .paused: return text("Пауза", "Paused")
    case .set: return text("Подход", "Set")
    case .allDone: return text("Выполнено", "Complete")
    }
  }
}
