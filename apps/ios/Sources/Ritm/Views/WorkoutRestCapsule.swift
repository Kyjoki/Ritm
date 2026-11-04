import RitmCore
import SwiftUI

/// Ticks once a second while a rest runs and once more after it ends, then stops: an idle or
/// finished timer costs no frames.
struct WorkoutRestSchedule: TimelineSchedule {
  let end: Date?

  func entries(from start: Date, mode: Mode) -> some Sequence<Date> {
    let last = end.map { max(start, $0).addingTimeInterval(0.3) } ?? start
    return sequence(first: start) { date in
      let next = date.addingTimeInterval(1)
      return next <= last ? next : nil
    }
  }
}

/// `.w1-cap`: the rest capsule that floats above the navigation bar while a workout is running,
/// on every screen of the section: a ring, the time left, «+15 с» and «Пропустить». It shows
/// `endDate - now`, so it is right after the app was away, and it vanishes when the rest ends.
struct WorkoutRestCapsule: View {
  @Environment(RitmStore.self) private var store
  let bottomPadding: CGFloat

  var body: some View {
    let workouts = store.workouts
    let rest = workouts.rest
    if workouts.session != nil, rest.endDate != nil || rest.phase(now: Date()) == .paused {
      TimelineView(WorkoutRestSchedule(end: rest.endDate)) { context in
        let phase = rest.phase(now: context.date)
        if phase == .running || phase == .paused {
          capsule(rest: rest, now: context.date, phase: phase)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
      }
    }
  }

  private func capsule(rest: RestTimer, now: Date, phase: RestTimer.Phase) -> some View {
    let remaining = rest.remaining(now: now)
    let russian = store.language == .ru
    return HStack(spacing: 8) {
      WorkoutRing(
        progress: remaining / max(1, rest.totalLength), lineWidth: 4.6, tint: RitmTheme.accentColor
      )
      .frame(width: 38, height: 38)
      VStack(alignment: .leading, spacing: 0) {
        Text(mmss(remaining))
          .ritmFont(19, weight: .bold, tracking: -0.04).monospacedDigit()
          .foregroundStyle(RitmTheme.text)
        Text(phase == .paused ? store.text("Пауза", "Paused") : store.text("Отдых", "Rest"))
          .ritmFont(11).foregroundStyle(RitmTheme.muted)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      Button {
        store.workouts.extendRest()
      } label: {
        Text(russian ? "+15\u{00A0}с" : "+15\u{00A0}s")
          .ritmFont(12.5, weight: .bold).foregroundStyle(RitmTheme.accentColor)
          .padding(.horizontal, 13).frame(height: 36)
          .background(RitmTheme.soft, in: Capsule())
          .overlay { Capsule().strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
          .frame(minHeight: 44)
          .contentShape(Capsule())
      }
      .buttonStyle(RitmPressStyle())
      .accessibilityLabel(store.text("Добавить 15 секунд", "Add 15 seconds"))
      Button {
        store.workouts.resetRest()
      } label: {
        Text(store.text("Пропустить", "Skip"))
          .ritmFont(12.5, weight: .bold).foregroundStyle(RitmTheme.ctaInk)
          .padding(.horizontal, 13).frame(height: 36)
          .ritmGlass(in: Capsule(), prominent: true)
          .frame(minHeight: 44)
          .contentShape(Capsule())
      }
      .buttonStyle(RitmPressStyle())
    }
    .padding(.leading, 9).padding(.trailing, 7).padding(.vertical, 7)
    // A flat surface, not live glass: the capsule redraws every second and a blur behind it
    // made every tick stutter.
    .background(RitmTheme.glassDense, in: Capsule())
    .overlay { Capsule().strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
    .shadow(color: RitmTheme.panelShadow, radius: 8, y: 4)
    .animation(.linear(duration: 1), value: Int(remaining.rounded(.up)))
  }

  private func mmss(_ remaining: TimeInterval) -> String {
    let total = Int(max(0, remaining).rounded(.up))
    return "\(total / 60):" + String(format: "%02d", total % 60)
  }
}

/// Room at the end of a page for the capsule while it is visible, so it never covers the last
/// button; it collapses when the rest ends.
struct WorkoutRestSpacer: View {
  @Environment(RitmStore.self) private var store
  /// The capsule (52 pt) and the gap above the navigation bar.
  static let height: CGFloat = 72

  var body: some View {
    let workouts = store.workouts
    let rest = workouts.rest
    if workouts.session != nil, rest.endDate != nil || rest.phase(now: Date()) == .paused {
      TimelineView(WorkoutRestSchedule(end: rest.endDate)) { context in
        let phase = rest.phase(now: context.date)
        Color.clear.frame(height: phase == .running || phase == .paused ? Self.height : 0)
      }
    }
  }
}
