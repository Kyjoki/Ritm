import ActivityKit
import RitmCore
import SwiftUI
import WidgetKit

// The lock-screen card of an active workout. It is drawn from `LiveActivityContent` only: it has
// no data of its own, no buttons (those need App Intents, which xtool cannot build yet) and
// nothing here is ever shown as a DONE value: the weight and reps are the PLANNED ones.

private enum RitmCardStyle {
  /// Ritm purple (RitmTheme.accentColor, dark variant, which reads on the dark card).
  static let accent = Color(red: 0xB9 / 255, green: 0x9C / 255, blue: 0xEB / 255)
  static let background = Color(red: 0x1B / 255, green: 0x14 / 255, blue: 0x2B / 255)
  static let deepLink = URL(string: "ritm://workout")!
}

struct RitmWorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RitmWorkoutAttributes.self) { context in
      LockScreenCard(content: context.state)
        .activityBackgroundTint(RitmCardStyle.background)
        .activitySystemActionForegroundColor(RitmCardStyle.accent)
        .widgetURL(RitmCardStyle.deepLink)
    } dynamicIsland: { context in
      // The owner's iPhone 13 has no Dynamic Island; this is the minimum for newer phones.
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.exerciseName).font(.caption.weight(.semibold)).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          PhaseClock(content: context.state).font(.title3.monospacedDigit())
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.setLabel).font(.caption).foregroundStyle(.secondary)
        }
      } compactLeading: {
        Image(systemName: "dumbbell.fill").foregroundStyle(RitmCardStyle.accent)
      } compactTrailing: {
        PhaseClock(content: context.state).font(.caption.monospacedDigit()).frame(maxWidth: 48)
      } minimal: {
        Image(systemName: "dumbbell.fill").foregroundStyle(RitmCardStyle.accent)
      }
      .widgetURL(RitmCardStyle.deepLink)
      .keylineTint(RitmCardStyle.accent)
    }
  }
}

/// The big countdown: drawn by the system from the absolute end date, never updated per second.
private struct PhaseClock: View {
  let content: LiveActivityContent

  var body: some View {
    if let end = content.restEndDate {
      Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
        .multilineTextAlignment(.trailing)
    } else if let paused = content.pausedRestSeconds {
      Text(WorkoutClock.format(seconds: paused))
    } else {
      Text("—")
    }
  }
}

private struct LockScreenCard: View {
  let content: LiveActivityContent

  private var phaseTitle: String {
    switch content.phase {
    case .rest: return "Отдых"
    case .paused: return "Пауза"
    case .set: return "Подход"
    case .allDone: return "Все подходы выполнены"
    }
  }

  /// «80 кг × 5», planned. Nothing when weights are hidden and there are no reps.
  private var planned: String? {
    guard content.phase != .allDone else { return nil }
    switch (content.plannedWeight, content.plannedReps) {
    case (let weight?, let reps?): return "План: \(weight) кг × \(reps)"
    case (let weight?, nil): return "План: \(weight) кг"
    case (nil, let reps?): return "План: \(reps) повт."
    case (nil, nil): return nil
    }
  }

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(phaseTitle.uppercased())
          .font(.caption2.weight(.semibold))
          .foregroundStyle(RitmCardStyle.accent)
        Text(content.exerciseName)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(1)
        if content.phase != .allDone {
          Text(content.setLabel).font(.subheadline).foregroundStyle(.white.opacity(0.8))
        }
        if let planned {
          Text(planned).font(.footnote).foregroundStyle(.white.opacity(0.65))
        }
      }
      Spacer(minLength: 8)
      if content.phase == .rest || content.phase == .paused {
        PhaseClock(content: content)
          .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(.white)
          .frame(maxWidth: 110, alignment: .trailing)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}
