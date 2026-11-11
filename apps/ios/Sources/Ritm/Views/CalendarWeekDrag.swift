import RitmCore
import SwiftUI
import UIKit

// Moving an entry in the week grid: hold ~0.35 s to lift it, drag across days and time slots
// (15-minute snapping, auto-scroll at the top and bottom, week switch after a dwell at a side
// edge), release to save, release outside the grid to cancel. The pure rules live in
// RitmCore/CalendarPlan.swift; this file owns the gesture state.

/// The entry under the finger, resolved by the grid when the hold fires.
struct WeekDragCandidate {
  let entry: DayOccurrence
  let frame: CalendarPlan.EntryFrame
  let dayIndex: Int
}

enum WeekDragResolution {
  case none
  /// An entry that must stay where it is; the text says why.
  case blocked(String)
  case entry(WeekDragCandidate)
}

/// What the model needs from the grid. Rebuilt on every gesture event, so it is never stale.
struct WeekDragEnv {
  var column: CGFloat
  var viewport: CGSize
  var days: Int
  var reduceMotion: Bool
  /// A point of the grid content (time column included) to the entry under it.
  var resolve: (CGPoint) -> WeekDragResolution
  var dayKey: (Int) -> String?
  var scrollTo: (String) -> Void
  var switchWeek: (Int) -> Void
  var showHint: (String) -> Void
  var move: (DayOccurrence, String, Int) async -> Void
}

/// A lifted entry. `point` is the finger in viewport coordinates, `scrollOffset` how far the grid
/// is scrolled, so `point.y + scrollOffset` is the finger in content coordinates.
struct WeekDrag {
  let entry: DayOccurrence
  let duration: Int
  let width: CGFloat
  let height: CGFloat
  let grabX: CGFloat
  let grabY: CGFloat
  var point: CGPoint
  var scrollOffset: CGFloat
  var target: CalendarPlan.DragTarget
  var inside: Bool
  var edge: Int
}

/// A released entry waiting for the server; it stays drawn at its new place.
struct WeekSettling {
  let entry: DayOccurrence
  let day: String
  let minutes: Int
  let width: CGFloat
  let height: CGFloat
}

@MainActor @Observable
final class WeekDragModel {
  // Observed: changes at lift and release only, except `drag`, which only the drag layer reads.
  private(set) var drag: WeekDrag?
  private(set) var settling: WeekSettling?
  private(set) var liftedKey: String?
  /// Lifted or saving: the grids stop scrolling under the finger.
  private(set) var active = false

  // Never observed.
  @ObservationIgnored var offset: CGFloat = 0
  @ObservationIgnored private var lastSlot = -1
  @ObservationIgnored private var env: WeekDragEnv?
  @ObservationIgnored private var pressing = false
  @ObservationIgnored private var origin = CGPoint.zero
  @ObservationIgnored private var holdTask: Task<Void, Never>?
  @ObservationIgnored private var scrollPosition = 0.0
  @ObservationIgnored private var edgeSince: Date?
  @ObservationIgnored private var suppressTapUntil = Date.distantPast

  private let hour = CalendarPlan.hourHeight
  private let timeColumn = CalendarPlan.timeColumn
  /// Eight scroll anchors per hour (`slot-N` ids in the hour column).
  static let slotsPerHour = 8
  static var slotCount: Int { 24 * slotsPerHour }
  /// A tap right after a lift or release must not open the entry.
  var tapsAllowed: Bool { Date() >= suppressTapUntil }

  // MARK: Finger events

  /// The long-press recogniser of CalendarGridTouches fired: lift the entry under the finger now.
  func pressBegan(at point: CGPoint, env: WeekDragEnv) {
    self.env = env
    holdTask?.cancel()
    pressing = true
    origin = point
    lift()
  }

  func pressMoved(to point: CGPoint, env: WeekDragEnv) {
    self.env = env
    if var current = drag {
      current.point = point
      drag = aimed(current, env: env)
      return
    }
    guard settling == nil else { return }
    if !pressing {
      pressing = true
      origin = point
      holdTask?.cancel()
      holdTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(CalendarPlan.dragHold))
        guard !Task.isCancelled else { return }
        self?.lift()
      }
      return
    }
    if hypot(point.x - origin.x, point.y - origin.y) > CalendarPlan.dragHoldSlop {
      holdTask?.cancel()  // the finger is scrolling or swiping
    }
  }

  func pressEnded(at point: CGPoint, env: WeekDragEnv) {
    self.env = env
    holdTask?.cancel()
    pressing = false
    guard var current = drag else { return }
    current.point = point
    release(aimed(current, env: env), env: env)
  }

  /// The touch ended without `pressEnded` (the system took it away): cancel a lifted entry.
  func pressInterrupted() {
    holdTask?.cancel()
    pressing = false
    guard drag != nil else { return }
    Task { @MainActor [weak self] in
      // A normal release has already cleared `drag`; only a lost touch gets here with it set.
      try? await Task.sleep(for: .milliseconds(80))
      guard let self, self.drag != nil, !self.pressing else { return }
      self.cancel()
    }
  }

  func reset() {
    holdTask?.cancel()
    pressing = false
    drag = nil
    settling = nil
    liftedKey = nil
    active = false
  }

  // MARK: Lift

  private func lift() {
    guard drag == nil, settling == nil, pressing, let env else { return }
    let content = CGPoint(x: origin.x, y: origin.y + offset)
    switch env.resolve(content) {
    case .none:
      return
    case .blocked(let reason):
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      env.showHint(reason)
      suppressTapUntil = Date().addingTimeInterval(0.4)
    case .entry(let found):
      let left = timeColumn + Double(found.dayIndex) * Double(env.column) + found.frame.x
      let duration = (found.entry.end ?? 0) - (found.entry.start ?? 0)
      let lifted = WeekDrag(
        entry: found.entry, duration: duration, width: CGFloat(found.frame.width),
        height: CGFloat(found.frame.height), grabX: content.x - CGFloat(left),
        grabY: content.y - CGFloat(found.frame.y), point: origin, scrollOffset: offset,
        target: CalendarPlan.DragTarget(dayIndex: found.dayIndex, minutes: found.entry.start ?? 0),
        inside: true, edge: 0)
      scrollPosition = Double(offset)
      lastSlot = -1
      edgeSince = nil
      suppressTapUntil = Date().addingTimeInterval(0.6)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      withAnimation(env.reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.18)) {
        drag = lifted
        liftedKey = found.entry.key
        active = true
      }
    }
  }

  // MARK: Aim, auto-scroll, week switch

  private func aimed(_ drag: WeekDrag, env: WeekDragEnv) -> WeekDrag {
    var next = drag
    next.scrollOffset = offset
    next.target = CalendarPlan.dragTarget(
      x: Double(drag.point.x), y: Double(drag.point.y + offset), grabY: Double(drag.grabY),
      column: Double(env.column), timeColumn: timeColumn, days: env.days, hourHeight: hour,
      duration: drag.duration)
    next.inside = CalendarPlan.isInside(
      x: Double(drag.point.x), y: Double(drag.point.y), width: Double(env.viewport.width),
      height: Double(env.viewport.height))
    next.edge =
      next.inside
      ? CalendarPlan.dragWeekEdge(x: Double(drag.point.x), width: Double(env.viewport.width)) : 0
    return next
  }

  /// Called about 60 times a second while an entry is lifted.
  func tick(dt: Double) {
    guard let current = drag, let env else { return }
    let speed =
      current.inside
      ? CalendarPlan.dragScrollSpeed(y: Double(current.point.y), height: Double(env.viewport.height))
      : 0
    if speed != 0 {
      let limit = max(0, 24 * hour - Double(env.viewport.height))
      scrollPosition = min(limit, max(0, scrollPosition + speed * dt))
      let slot = Int(scrollPosition / (hour / Double(Self.slotsPerHour)))
      if slot != lastSlot {
        lastSlot = slot
        env.scrollTo("slot-\(min(Self.slotCount - 1, slot))")
      }
    } else {
      scrollPosition = Double(offset)
      lastSlot = -1
    }
    let next = aimed(current, env: env)
    dwell(next.edge, env: env)
    drag = next
  }

  /// A short dwell at a side edge switches the week, and again after another dwell.
  private func dwell(_ edge: Int, env: WeekDragEnv) {
    guard edge != 0 else {
      edgeSince = nil
      return
    }
    guard let since = edgeSince else {
      edgeSince = Date()
      return
    }
    if Date().timeIntervalSince(since) >= CalendarPlan.dragWeekDwell {
      edgeSince = Date()
      UISelectionFeedbackGenerator().selectionChanged()
      env.switchWeek(edge)
    }
  }

  // MARK: Release

  private func release(_ final: WeekDrag, env: WeekDragEnv) {
    suppressTapUntil = Date().addingTimeInterval(0.4)
    let entry = final.entry
    guard final.inside, let day = env.dayKey(final.target.dayIndex),
      day != entry.date || final.target.minutes != entry.start
    else {
      cancel(haptic: !final.inside)
      return
    }
    let minutes = final.target.minutes
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    drag = nil
    settling = WeekSettling(
      entry: entry, day: day, minutes: minutes, width: final.width, height: final.height)
    Task { @MainActor [weak self] in
      await env.move(entry, day, minutes)
      guard let self else { return }
      withAnimation(env.reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.18)) {
        self.settling = nil
        self.liftedKey = nil
        self.active = false
      }
    }
  }

  private func cancel(haptic: Bool = true) {
    if haptic { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    withAnimation((env?.reduceMotion ?? false) ? RitmMotion.reducedFade : RitmMotion.easeOut(0.18)) {
      drag = nil
      liftedKey = nil
      active = false
    }
  }
}

// MARK: - Drawing

/// The lifted card under the finger and the dashed drop preview with its time label.
struct CalendarDragLayer: View {
  let model: WeekDragModel
  let days: [String]
  let column: CGFloat
  @Environment(RitmStore.self) private var store
  @Environment(\.calendarHourFormat) private var format
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let hour = CGFloat(CalendarPlan.hourHeight)
  private let timeColumn = CGFloat(CalendarPlan.timeColumn)

  var body: some View {
    ZStack(alignment: .topLeading) {
      if let settling = model.settling, let index = days.firstIndex(of: settling.day) {
        CalendarEventCard(entry: settling.entry, width: settling.width, height: settling.height)
          .opacity(0.85)
          .offset(
            x: timeColumn + CGFloat(index) * column + 1,
            y: CGFloat(settling.minutes) / 60 * hour + 2)
      }
      if let drag = model.drag {
        if drag.inside { preview(drag) }
        ghost(drag)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func preview(_ drag: WeekDrag) -> some View {
    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    let above = drag.target.minutes >= 30
    return shape
      .fill(RitmTheme.accentColor.opacity(0.14))
      .overlay {
        shape.strokeBorder(
          RitmTheme.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
      }
      .frame(width: column - 2, height: drag.height)
      .overlay(alignment: days.count > 3 && drag.target.dayIndex >= days.count - 3 ? .topTrailing : .topLeading) {
        timeLabel(drag)
          .offset(y: above ? -24 : drag.height + 4)
      }
      .offset(
        x: timeColumn + CGFloat(drag.target.dayIndex) * column + 1,
        y: CGFloat(drag.target.minutes) / 60 * hour + 2
      )
      .animation(reduceMotion ? nil : RitmMotion.easeOut(0.12), value: drag.target)
  }

  private func timeLabel(_ drag: WeekDrag) -> some View {
    let day = days.indices.contains(drag.target.dayIndex) ? days[drag.target.dayIndex] : ""
    let weekday = CalendarText.capitalizedWords(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEE"))
    let end = drag.target.minutes + drag.duration
    return Text(
      weekday + " · " + format.clock(drag.target.minutes) + "–" + format.clock(end)
    )
    .ritmFont(11, weight: .semibold)
    .monospacedDigit()
    .foregroundStyle(RitmTheme.accentInk)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(RitmTheme.accentColor, in: Capsule())
    .fixedSize()
  }

  private func ghost(_ drag: WeekDrag) -> some View {
    CalendarEventCard(entry: drag.entry, width: drag.width, height: drag.height)
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(RitmTheme.accentColor.opacity(0.7), lineWidth: 1.5)
      }
      .scaleEffect(reduceMotion ? 1 : 1.06)
      .shadow(color: Color.black.opacity(0.28), radius: 12, y: 8)
      .opacity(drag.inside ? 1 : 0.5)
      .overlay(alignment: .top) {
        if !drag.inside {
          Text(store.text("Отмена", "Cancel"))
            .ritmFont(11, weight: .semibold)
            .foregroundStyle(RitmTheme.accentInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RitmTheme.danger, in: Capsule())
            .fixedSize()
            .offset(y: -24)
        }
      }
      .offset(
        x: drag.point.x - drag.grabX, y: drag.point.y + drag.scrollOffset - drag.grabY
      )
      .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
      .zIndex(2)
  }
}

/// A soft accent band on the side edge the finger dwells at, before the week switches.
struct CalendarEdgeCue: View {
  let model: WeekDragModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let edge = model.drag?.edge ?? 0
    HStack(spacing: 0) {
      band(.leading).opacity(edge < 0 ? 1 : 0)
      Spacer(minLength: 0)
      band(.trailing).opacity(edge > 0 ? 1 : 0)
    }
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.15), value: edge)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func band(_ side: Edge) -> some View {
    LinearGradient(
      colors: [RitmTheme.accentColor.opacity(0.32), RitmTheme.accentColor.opacity(0)],
      startPoint: side == .leading ? .leading : .trailing,
      endPoint: side == .leading ? .trailing : .leading
    )
    .frame(width: CGFloat(CalendarPlan.dragWeekEdgeInset) + 12)
  }
}
