import RitmCore
import SwiftUI

/// The hour grid of the day, 3-day and week views (CalendarPage.tsx `.cal-mobile-week`, now with
/// one, three or seven columns): the full width of the screen, 56 pt per hour, a 40 pt time
/// column, vertical separators inside the hours only, overlaps side by side (or behind a per-day
/// button in the narrow week), swipe to change the period and a long press that lifts an entry
/// to move it (CalendarWeekDrag.swift). The hour grid is the only vertical scroll; the rows above
/// it stay put. Below midnight the lines carry on for two hours and down to the screen's bottom
/// edge, behind the tab bar, as in Google Calendar.
///
/// Equatable: the page redraws for many small things, the grid only when its days, data or
/// scroll target change.
struct CalendarWeekGrid: View, Equatable {
  let days: [String]
  let dayModel: CalendarDayModel
  let generation: Int
  let today: String
  let timeZoneLabel: String
  let jumpToNow: Int
  /// Why an entry cannot be moved, or nil when it can.
  let dragBlock: (DayOccurrence) -> String?
  let onOpen: (DayOccurrence) -> Void
  let onPick: (String, [DayOccurrence]) -> Void
  let onAdd: (String, Int) -> Void
  let onSelectDay: (String) -> Void
  let onMove: (DayOccurrence, String, Int) async -> Void
  /// One period forward (1) or back (-1).
  let onStep: (Int) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.calendarHourFormat) private var format
  @State private var swipeOffset: CGFloat = 0
  @State private var sliding = false
  @State private var model = WeekDragModel()

  private let hour = CGFloat(CalendarPlan.hourHeight)
  private let timeColumn = CGFloat(CalendarPlan.timeColumn)
  /// Empty hours under midnight, before the bottom inset (the tab bar's room) is added.
  private let tailHours: CGFloat = 2

  nonisolated static func == (left: CalendarWeekGrid, right: CalendarWeekGrid) -> Bool {
    left.days == right.days && left.generation == right.generation && left.today == right.today
      && left.timeZoneLabel == right.timeZoneLabel && left.jumpToNow == right.jumpToNow
  }

  var body: some View {
    GeometryReader { proxy in
      let column = max(1, (proxy.size.width - timeColumn) / CGFloat(max(1, days.count)))
      let bottomInset = proxy.safeAreaInsets.bottom
      VStack(spacing: 0) {
        CalendarGridHeader(
          days: days, model: dayModel, generation: generation, today: today,
          timeZoneLabel: timeZoneLabel, column: column, swipeOffset: swipeOffset,
          canSelectDay: days.count > 1, onSelectDay: onSelectDay, onOpen: onOpen, onPick: onPick)
        grid(column: column, width: proxy.size.width, bottomInset: bottomInset)
      }
    }
  }

  // MARK: Hours

  /// The scroll content's height: the 24 hours, the tail, and the room of the tab bar.
  private func contentHeight(bottomInset: CGFloat) -> CGFloat {
    24 * hour + tailHours * hour + bottomInset
  }

  private func grid(column: CGFloat, width: CGFloat, bottomInset: CGFloat) -> some View {
    let height = contentHeight(bottomInset: bottomInset)
    return GeometryReader { viewport in
      ScrollViewReader { reader in
        ScrollView {
          HStack(alignment: .top, spacing: 0) {
            hourColumn(height: height)
            dayArea(column: column, height: height)
          }
          .overlay(alignment: .topLeading) {
            CalendarDragLayer(model: model, days: days, column: column)
          }
          .background {
            CalendarGridTouches(
              model: model,
              makeEnv: {
                environment(
                  reader: reader, column: column,
                  viewport: CGSize(
                    width: viewport.size.width, height: viewport.size.height - bottomInset))
              },
              swipeLimit: width * 0.4,
              onSwipeChange: { if !sliding { swipeOffset = $0 } },
              onSwipeEnd: { dx, dy, elapsed in
                finishSwipe(dx: dx, dy: dy, elapsed: elapsed, width: width)
              })
          }
        }
        // The offset the drag model needs, read from the scroll view itself: no per-frame
        // geometry reader or preference inside the content.
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: {
          _, offset in model.offset = offset
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(model.active)
        .overlay { CalendarEdgeCue(model: model) }
        .task(id: model.liftedKey) { await autoScroll() }
        .onChange(of: model.active) { _, active in
          // A swipe that began before the lift is dropped.
          if active { settle() }
        }
        .onDisappear { model.reset() }
        .onAppear {
          reader.scrollTo("hour-\(CalendarPlan.initialHour)", anchor: .top)
        }
        .onChange(of: jumpToNow) { _, _ in
          let target = max(0, (store.minuteOfDay - 120) / 60)
          withAnimation(reduceMotion ? nil : RitmMotion.ease(0.3)) {
            reader.scrollTo("hour-\(target)", anchor: .top)
          }
        }
      }
    }
    // The lines run on behind the floating tab bar instead of stopping above it.
    .ignoresSafeArea(.container, edges: .bottom)
  }

  /// The hour labels, centred on their lines (none at midnight); the clear `hour-N` rows are the
  /// anchors the grid scrolls to, and the `slot-N` rows the anchors auto-scroll moves to.
  private func hourColumn(height: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      VStack(spacing: 0) {
        ForEach(0..<24, id: \.self) { value in
          Color.clear.frame(width: 1, height: hour).id("hour-\(value)")
        }
      }
      ForEach(1..<24, id: \.self) { value in
        Text(format.hourLabel(value))
          .ritmFont(10, weight: .medium)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(width: timeColumn - 4, height: 14, alignment: .trailing)
          .offset(y: CGFloat(value) * hour - 7)
      }
    }
    .frame(width: timeColumn, height: height, alignment: .topLeading)
    .overlay(alignment: .top) {
      VStack(spacing: 0) {
        ForEach(0..<WeekDragModel.slotCount, id: \.self) { slot in
          Color.clear
            .frame(width: 1, height: hour / CGFloat(WeekDragModel.slotsPerHour))
            .id("slot-\(slot)")
        }
      }
      .allowsHitTesting(false)
    }
    .accessibilityHidden(true)
  }

  /// The columns with their separators, clipped to their own width so the slide of a period
  /// change never covers the time column.
  private func dayArea(column: CGFloat, height: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      CalendarGridLines(hour: hour, column: column, columns: days.count, vertical: false)
        .stroke(RitmTheme.line, lineWidth: 1)
      CalendarGridLines(hour: hour, column: column, columns: days.count, vertical: true)
        .stroke(RitmTheme.line.opacity(0.75), lineWidth: 1)
      HStack(spacing: 0) {
        ForEach(days, id: \.self) { day in dayColumn(day, column: column, height: height) }
      }
    }
    .offset(x: swipeOffset)
    .frame(width: column * CGFloat(days.count), height: height, alignment: .topLeading)
    .clipped()
  }

  private func dayColumn(_ day: String, column: CGFloat, height: CGFloat) -> some View {
    CalendarDayColumn(
      day: day, placed: dayModel.layout(day), column: column, height: height,
      isToday: day == today, liftedKey: model.liftedKey, generation: generation,
      hint: { entry in
        dragBlock(entry)
          ?? store.text(
            "Удерживайте и перетащите запись на другое время или день.",
            "Hold and drag the entry to another time or day.")
      },
      onOpen: { entry in if model.tapsAllowed { onOpen(entry) } },
      onTap: { point in tapped(day, column: column, at: point) },
      onAddMorning: { onAdd(day, 540) }
    )
    .equatable()
  }

  private func tapped(_ day: String, column: CGFloat, at point: CGPoint) {
    guard model.tapsAllowed else { return }
    if let hit = CalendarPlan.entry(
      at: Double(point.x), y: Double(point.y), in: dayModel.layout(day), column: Double(column),
      hourHeight: Double(hour))
    {
      onOpen(hit.entry)
    } else {
      onAdd(day, min(1410, max(0, Int(point.y / (hour / 2)) * 30)))
    }
  }

  // MARK: Lift and move

  /// Every finger event carries what the model needs, built from the current days.
  private func environment(
    reader: ScrollViewProxy, column: CGFloat, viewport: CGSize
  ) -> WeekDragEnv {
    let days = days
    return WeekDragEnv(
      column: column, viewport: viewport, days: days.count, reduceMotion: reduceMotion,
      resolve: { content in resolve(content, column: column) },
      dayKey: { days.indices.contains($0) ? days[$0] : nil },
      scrollTo: { reader.scrollTo($0, anchor: .top) },
      switchWeek: onStep,
      showHint: { store.toasts.show($0) },
      move: onMove)
  }

  /// The entry under a point of the grid content, or why it cannot be moved.
  private func resolve(_ content: CGPoint, column: CGFloat) -> WeekDragResolution {
    let x = content.x - timeColumn
    guard x >= 0 else { return .none }
    let index = Int(x / column)
    guard days.indices.contains(index) else { return .none }
    guard
      let hit = CalendarPlan.entry(
        at: Double(x - CGFloat(index) * column), y: Double(content.y),
        in: dayModel.layout(days[index]), column: Double(column), hourHeight: Double(hour))
    else { return .none }
    if let reason = dragBlock(hit.entry) { return .blocked(reason) }
    return .entry(
      WeekDragCandidate(
        entry: hit.entry,
        frame: CalendarPlan.entryFrame(hit, column: Double(column), hourHeight: Double(hour)),
        dayIndex: index))
  }

  /// Edge auto-scroll and the period dwell run on a 60 Hz loop while an entry is lifted.
  private func autoScroll() async {
    guard model.liftedKey != nil else { return }
    let clock = ContinuousClock()
    var last = clock.now
    while !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(16))
      let now = clock.now
      let elapsed = last.duration(to: now)
      last = now
      model.tick(dt: Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds))
    }
  }

  // MARK: Swipe between periods

  /// A deliberate horizontal swipe slides to the next or previous period; anything else settles
  /// the columns back.
  private func finishSwipe(dx: CGFloat, dy: CGFloat, elapsed: TimeInterval, width: CGFloat) {
    let direction = model.active ? 0 : CalendarPlan.weekSwipe(dx: dx, dy: dy, elapsed: elapsed, width: width)
    guard direction != 0, !sliding else {
      if !sliding { settle() }
      return
    }
    sliding = true
    Task { @MainActor in
      await CalendarSlide.run(
        direction: direction, width: width - timeColumn, reduceMotion: reduceMotion,
        offset: $swipeOffset
      ) { onStep(direction) }
      sliding = false
    }
  }

  private func settle() {
    withAnimation(reduceMotion ? nil : RitmMotion.easeOut(0.22)) { swipeOffset = 0 }
  }
}
