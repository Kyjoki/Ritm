import RitmCore
import SwiftUI

/// What one bar of the strip needs: the exercise and how many of its sets are done.
struct WorkoutStripSegment: Equatable, Identifiable {
  let id: String
  let done: Int
  let total: Int

  var share: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// `.w-seg`: one bar per exercise, filled by its done sets; tap to jump. Equatable on the bars and
/// the current one, so typing a weight or the ticking clock never rebuilds the strip.
struct WorkoutProgressStrip: View, Equatable {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let segments: [WorkoutStripSegment]
  let current: Int
  let select: (Int) -> Void

  nonisolated static func == (left: WorkoutProgressStrip, right: WorkoutProgressStrip) -> Bool {
    left.segments == right.segments && left.current == right.current
  }

  var body: some View {
    HStack(spacing: 5) {
      ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
        Button {
          select(index)
        } label: {
          bar(segment, isCurrent: index == current)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.text("Упражнение \(index + 1)", "Exercise \(index + 1)"))
        .accessibilityValue("\(segment.done) / \(segment.total)")
      }
    }
    .padding(.horizontal, 4)
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.25), value: current)
  }

  private func bar(_ segment: WorkoutStripSegment, isCurrent: Bool) -> some View {
    let share = segment.share
    return Capsule().fill(RitmTheme.ringTrack)
      .frame(height: 6)
      .overlay(alignment: .leading) {
        Capsule()
          .fill(share >= 1 ? AnyShapeStyle(WorkoutColors.income) : AnyShapeStyle(WorkoutPalette.progressGradient))
          .scaleEffect(x: max(share, 0.0001), anchor: .leading)
          .animation(reduceMotion ? nil : RitmMotion.easeOut(0.4), value: share)
      }
      .overlay {
        if isCurrent { Capsule().strokeBorder(RitmTheme.accentColor, lineWidth: 1.5).padding(-1.5) }
      }
      .scaleEffect(y: isCurrent ? 1.5 : 1)
      .frame(maxWidth: .infinity, minHeight: 22)
      .contentShape(Rectangle())
  }
}

/// «mm:ss · Отменить»: the elapsed time of the workout. The quick cancel lives only for the first
/// two minutes. It owns its one-second timeline, so the tick redraws this label and nothing else.
struct WorkoutElapsedClock: View, Equatable {
  /// A workout younger than this can be dropped with one tap on «Отменить».
  static let quickCancelWindow: TimeInterval = 120

  @Environment(RitmStore.self) private var store
  let startedAt: Date
  let cancel: () -> Void

  nonisolated static func == (left: WorkoutElapsedClock, right: WorkoutElapsedClock) -> Bool {
    left.startedAt == right.startedAt
  }

  var body: some View {
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
      HStack(spacing: 4) {
        Text(WorkoutClock.elapsed(from: startedAt, now: context.date)).monospacedDigit()
        if context.date.timeIntervalSince(startedAt) < Self.quickCancelWindow {
          Text("·")
          Button(store.text("Отменить", "Cancel"), action: cancel)
            .ritmFont(12.5, weight: .bold).foregroundStyle(RitmTheme.accentColor)
            .underline()
            .frame(minHeight: 44)
        }
      }
      .ritmFont(12.5).foregroundStyle(RitmTheme.muted)
    }
    .frame(height: 20)
  }
}
