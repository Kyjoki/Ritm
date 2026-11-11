import RitmCore
import SwiftUI

/// The hour grid of the day, 3-day and week views (CalendarPage.tsx `.cal-mobile-week`, now with
/// one, three or seven columns): the full width of the screen, 56 pt per hour, a 40 pt time
/// column, vertical separators inside the hours only, overlaps side by side (or behind a per-day
/// button in the narrow week), swipe to change the period and a long press that lifts an entry
/// to move it (CalendarWeekDrag.swift). The hour grid is the only vertical scroll; the rows above
/// it stay put.
struct CalendarWeekGrid: View {
  let days: [String]
  let entries: [String: [DayOccurrence]]
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
  /// The room under the last hour, so it scrolls clear of the «+» button and the undated chip.
  private let bottomClearance: CGFloat = 88

  var body: some View {
    GeometryReader { proxy in
      let column = max(1, (proxy.size.width - timeColumn) / CGFloat(max(1, days.count)))
      VStack(spacing: 0) {
        CalendarGridHeader(
          days: days, entries: entries, today: today, timeZoneLabel: timeZoneLabel,
          column: column, swipeOffset: swipeOffset, canSelectDay: days.count > 1,
          onSelectDay: onSelectDay, onOpen: onOpen, onPick: onPick)
        grid(column: column, width: proxy.size.width)
      }
    }
  }

  // MARK: Hours

  private func grid(column: CGFloat, width: CGFloat) -> some View {
    GeometryReader { viewport in
      ScrollViewReader { reader in
        ScrollView {
          HStack(alignment: .top, spacing: 0) {
            hourColumn
            dayArea(column: column)
          }
          .overlay(alignment: .topLeading) {
            CalendarDragLayer(model: model, days: days, column: column)
          }
          .background {
            CalendarGridTouches(
              model: model,
              makeEnv: { environment(reader: reader, column: column, viewport: viewport.size) },
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
        .contentMargins(.bottom, bottomClearance, for: .scrollContent)
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
  }

  /// The hour labels, centred on their lines (none at midnight); the clear `hour-N` rows are the
  /// anchors the grid scrolls to, and the `slot-N` rows the anchors auto-scroll moves to.
  private var hourColumn: some View {
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
    .frame(width: timeColumn, height: 24 * hour, alignment: .topLeading)
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
  private func dayArea(column: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      CalendarGridLines(hour: hour, column: column, columns: days.count, vertical: false)
        .stroke(RitmTheme.line, lineWidth: 1)
      CalendarGridLines(hour: hour, column: column, columns: days.count, vertical: true)
        .stroke(RitmTheme.line.opacity(0.75), lineWidth: 1)
      HStack(spacing: 0) {
        ForEach(days, id: \.self) { day in dayColumn(day, column: column) }
      }
    }
    .offset(x: swipeOffset)
    .frame(width: column * CGFloat(days.count), height: 24 * hour, alignment: .topLeading)
    .clipped()
  }

  /// One day's column. A single tap handler decides by position: a tap on a block opens it, a
  /// tap on empty space adds an entry there (the blocks themselves take no touches, so the two
  /// can never both fire).
  private func dayColumn(_ day: String, column: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      (day == today ? RitmTheme.soft.opacity(0.34) : Color.clear)
      ForEach(CalendarPlan.layout(entries[day] ?? [])) { placed in
        CalendarGridEvent(
          placed: placed, column: column, hour: hour,
          lifted: model.liftedKey == placed.entry.key,
          hint: dragBlock(placed.entry)
            ?? store.text(
              "Удерживайте и перетащите запись на другое время или день.",
              "Hold and drag the entry to another time or day."),
          onOpen: { if model.tapsAllowed { onOpen(placed.entry) } })
      }
      if day == today { nowLine }
    }
    .frame(width: column, height: 24 * hour)
    .contentShape(Rectangle())
    .gesture(SpatialTapGesture().onEnded { value in tapped(day, column: column, at: value.location) })
    .accessibilityElement(children: .contain)
    .accessibilityLabel(FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEEE d MMMM"))
    .accessibilityAction(named: store.text("Добавить запись в 9 AM", "Add an entry at 9 AM")) {
      onAdd(day, 540)
    }
  }

  private var nowLine: some View {
    TimelineView(.everyMinute) { context in
      let minute = FeatureDate.calendar(store.timeZone).dateComponents([.hour, .minute], from: context.date)
      CalendarNowLine()
        .offset(y: CGFloat((minute.hour ?? 0) * 60 + (minute.minute ?? 0)) / 60 * hour - 1)
    }
    .allowsHitTesting(false)
  }

  private func tapped(_ day: String, column: CGFloat, at point: CGPoint) {
    guard model.tapsAllowed else { return }
    let placed = CalendarPlan.layout(entries[day] ?? [])
    if let hit = CalendarPlan.entry(
      at: Double(point.x), y: Double(point.y), in: placed, column: Double(column),
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
    let placed = CalendarPlan.layout(entries[days[index]] ?? [])
    guard
      let hit = CalendarPlan.entry(
        at: Double(x - CGFloat(index) * column), y: Double(content.y), in: placed,
        column: Double(column), hourHeight: Double(hour))
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

/// Whole-hour lines across the columns, or the separators between them.
private struct CalendarGridLines: Shape {
  let hour: CGFloat
  let column: CGFloat
  let columns: Int
  let vertical: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    if vertical {
      for index in 0..<max(1, columns) {
        let x = CGFloat(index) * column + 0.5
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: rect.height))
      }
    } else {
      for index in 1..<24 {
        let y = CGFloat(index) * hour + 0.5
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: rect.width, y: y))
      }
    }
    return path
  }
}

/// `.cal-now-line`: a 2 pt accent line with a dot at its start.
private struct CalendarNowLine: View {
  var body: some View {
    Rectangle()
      .fill(RitmTheme.danger)
      .frame(height: 2)
      .overlay(alignment: .leading) {
        Circle().fill(RitmTheme.danger).frame(width: 10, height: 10).offset(x: -5)
      }
      .accessibilityHidden(true)
  }
}
