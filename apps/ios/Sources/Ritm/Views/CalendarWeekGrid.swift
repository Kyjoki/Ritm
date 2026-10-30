import RitmCore
import SwiftUI

/// The week timetable on a phone (CalendarPage.tsx with `.cal-mobile-week`): seven columns across
/// the screen, 48 pt per hour, a 40 pt time column, overlaps behind a per-day button, swipe to
/// change week and a long press that lifts an entry to move it (CalendarWeekDrag.swift).
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
  let onDragActive: (Bool) -> Void
  let onSwipe: (Int) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var swipeOffset: CGFloat = 0
  @State private var swipeStart: Date?
  @State private var swipeCancelled = false
  @State private var model = WeekDragModel()
  @GestureState private var touching = false

  private let hour = CGFloat(CalendarPlan.hourHeight)
  private let timeColumn = CGFloat(CalendarPlan.timeColumn)

  private var overlaps: [String: [DayOccurrence]] {
    Dictionary(
      uniqueKeysWithValues: days.map { day in
        (day, CalendarPlan.overlapGroups(entries[day] ?? []).filter { $0.count > 1 }.flatMap { $0 })
      })
  }
  private var hasUntimed: Bool { days.contains { (entries[$0] ?? []).contains { $0.start == nil } } }

  var body: some View {
    GeometryReader { proxy in
      let column = max(1, (proxy.size.width - timeColumn) / CGFloat(max(1, days.count)))
      VStack(spacing: 0) {
        header(column: column)
        if overlaps.values.contains(where: { !$0.isEmpty }) { overlapRow(column: column) }
        if hasUntimed { allDayRow(column: column) }
        grid(column: column, width: proxy.size.width)
      }
    }
  }

  // MARK: Rows above the hours

  private func header(column: CGFloat) -> some View {
    HStack(spacing: 0) {
      Text(timeZoneLabel)
        .ritmFont(10)
        .foregroundStyle(RitmTheme.muted)
        .frame(width: timeColumn, alignment: .leading)
      ForEach(days, id: \.self) { day in
        Button {
          onSelectDay(day)
        } label: {
          VStack(spacing: 0) {
            Text(weekday(day)).ritmFont(10).foregroundStyle(RitmTheme.muted)
            Text("\(Int(day.suffix(2)) ?? 0)")
              .ritmFont(17, weight: .medium, tracking: -0.05)
              .foregroundStyle(day == today ? RitmTheme.accentColor : RitmTheme.text)
              .frame(width: 26, height: 26)
              .background {
                if day == today { Circle().fill(RitmTheme.soft) }
              }
          }
          .frame(width: column)
          .frame(minHeight: 43)
          .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .accessibilityLabel(
          store.text("Показать ", "Show ")
            + FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "d MMMM"))
      }
    }
    .padding(.bottom, 2)
    .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
  }

  private func overlapRow(column: CGFloat) -> some View {
    HStack(spacing: 0) {
      Image(systemName: "square.stack")
        .font(.system(size: 12))
        .foregroundStyle(RitmTheme.muted)
        .frame(width: timeColumn)
        .accessibilityHidden(true)
      ForEach(days, id: \.self) { day in
        let group = overlaps[day] ?? []
        if group.isEmpty {
          Color.clear.frame(width: column, height: 32)
        } else {
          Button {
            onPick(day, group)
          } label: {
            HStack(spacing: 3) {
              Image(systemName: "square.stack").font(.system(size: 10)).accessibilityHidden(true)
              Text("\(group.count)").ritmFont(11, weight: .semibold)
            }
            .foregroundStyle(RitmTheme.accentColor)
            .frame(width: max(1, column - 4), height: 32)
            .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 8, style: .circular))
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
            }
            .frame(width: column, height: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(RitmPressStyle())
          .padding(.vertical, -6)
          .accessibilityLabel(
            FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "d MMMM")
              + ": \(group.count) " + CalendarPlan.recordWord(group.count, language: store.language)
              + store.text(" с пересечением. Выбрать событие", " overlapping. Choose an event"))
        }
      }
    }
    .padding(.bottom, 4)
    .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
  }

  /// `.cal-all-day` scrolls once it would grow past 96 pt.
  @ViewBuilder private func allDayRow(column: CGFloat) -> some View {
    let rows = days.map { day in (entries[day] ?? []).filter { $0.start == nil }.count }.max() ?? 0
    Group {
      if 22 + CGFloat(rows) * 22 > 96 {
        ScrollView { allDayContent(column: column) }.frame(height: 96)
      } else {
        allDayContent(column: column)
      }
    }
    .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
  }

  private func allDayContent(column: CGFloat) -> some View {
      HStack(alignment: .top, spacing: 0) {
        Text(store.text("Весь день / без времени", "All day / untimed"))
          .ritmFont(10, lineSpacing: 2)
          .foregroundStyle(RitmTheme.muted)
          .frame(width: timeColumn, alignment: .leading)
          .padding(.top, 5)
        ForEach(days, id: \.self) { day in
          VStack(spacing: 3) {
            ForEach((entries[day] ?? []).filter { $0.start == nil }) { entry in
              Button {
                onOpen(entry)
              } label: {
                Text(entry.title)
                  .ritmFont(10)
                  .lineLimit(1)
                  .foregroundStyle(RitmTheme.text)
                  .padding(3)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background { CalendarEntrySurface(colorID: entry.colorId, radius: 5) }
              }
              .buttonStyle(RitmPressStyle())
              .accessibilityLabel(CalendarText.occurrenceLabel(entry, store: store))
            }
          }
          .padding(.horizontal, 4)
          .frame(width: column, alignment: .top)
        }
      }
      .padding(.vertical, 11)
  }

  // MARK: Hours

  private static let viewportSpace = "weekViewport"

  private func grid(column: CGFloat, width: CGFloat) -> some View {
    GeometryReader { viewport in
      ScrollViewReader { reader in
        ScrollView {
          HStack(alignment: .top, spacing: 0) {
            hourColumn
            ForEach(days, id: \.self) { day in
              dayColumn(day, column: column)
            }
          }
          .offset(x: swipeOffset)
          .background {
            GeometryReader { content in
              Color.clear.preference(
                key: WeekScrollOffsetKey.self,
                value: -content.frame(in: .named(Self.viewportSpace)).minY)
            }
          }
          .overlay(alignment: .topLeading) {
            CalendarDragLayer(model: model, days: days, column: column)
          }
          .simultaneousGesture(
            lift(reader: reader, column: column, viewport: viewport.size))
        }
        .coordinateSpace(name: Self.viewportSpace)
        .onPreferenceChange(WeekScrollOffsetKey.self) { model.offset = max(0, $0) }
        .scrollIndicators(.hidden)
        .scrollDisabled(model.active)
        .overlay { CalendarEdgeCue(model: model) }
        .simultaneousGesture(swipe(width: width))
        .task(id: model.liftedKey) { await autoScroll() }
        .onChange(of: touching) { _, held in
          if !held { model.pressInterrupted() }
        }
        .onChange(of: model.active) { _, active in
          if active {
            // A swipe that began before the lift is dropped; `model.active` keeps new ones out.
            swipeStart = nil
            settle()
          }
          onDragActive(active)
        }
        .onDisappear {
          model.reset()
          onDragActive(false)
        }
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

  /// The hour labels; the clear `slot-N` rows over them are the anchors auto-scroll moves to.
  private var hourColumn: some View {
    VStack(spacing: 0) {
      ForEach(0..<24, id: \.self) { value in
        Text(CalendarPlan.hourLabel(value))
          .ritmFont(10)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 3)
          .frame(width: timeColumn, height: hour, alignment: .topLeading)
          .id("hour-\(value)")
      }
    }
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

  private func dayColumn(_ day: String, column: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      (day == today ? RitmTheme.soft.opacity(0.34) : Color.clear)
      CalendarSlotLines(hour: hour).stroke(RitmTheme.line.opacity(0.5), lineWidth: 1)
      CalendarSlotLines(hour: hour, wholeHours: true).stroke(RitmTheme.line, lineWidth: 1)
      // `.cal-free-slot`: a tap on an empty half hour adds an entry there.
      Color.clear
        .contentShape(Rectangle())
        .gesture(
          SpatialTapGesture().onEnded { value in
            onAdd(day, min(1410, max(0, Int(value.location.y / (hour / 2)) * 30)))
          })
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
      if day == today {
        TimelineView(.everyMinute) { context in
          let minute = FeatureDate.calendar(store.timeZone).dateComponents([.hour, .minute], from: context.date)
          CalendarNowLine()
            .offset(y: CGFloat((minute.hour ?? 0) * 60 + (minute.minute ?? 0)) / 60 * hour - 1)
        }
        .allowsHitTesting(false)
      }
    }
    .frame(width: column, height: 24 * hour)
    .overlay(alignment: .leading) { Rectangle().fill(RitmTheme.line).frame(width: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEEE d MMMM"))
    .accessibilityAction(named: store.text("Добавить запись в 9 AM", "Add an entry at 9 AM")) {
      onAdd(day, 540)
    }
  }

  // MARK: Lift and move

  /// Every finger event carries what the model needs, built from the current week.
  private func environment(
    reader: ScrollViewProxy, column: CGFloat, viewport: CGSize
  ) -> WeekDragEnv {
    let days = days
    return WeekDragEnv(
      column: column, viewport: viewport, days: days.count, reduceMotion: reduceMotion,
      resolve: { content in resolve(content, column: column) },
      dayKey: { days.indices.contains($0) ? days[$0] : nil },
      scrollTo: { reader.scrollTo($0, anchor: .top) },
      switchWeek: onSwipe,
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

  /// A hold for 0.35 s lifts the entry under the finger. Until then a finger that moves is a
  /// scroll or a week swipe, and while an entry is lifted both are switched off.
  private func lift(reader: ScrollViewProxy, column: CGFloat, viewport: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.viewportSpace))
      .updating($touching) { _, state, _ in state = true }
      .onChanged { value in
        model.pressMoved(
          to: value.location, env: environment(reader: reader, column: column, viewport: viewport))
      }
      .onEnded { value in
        model.pressEnded(
          at: value.location, env: environment(reader: reader, column: column, viewport: viewport))
      }
  }

  /// Edge auto-scroll and the week dwell run on a 60 Hz loop while an entry is lifted.
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

  /// A deliberate horizontal swipe changes the week; vertical scrolling is left alone.
  private func swipe(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        guard !model.active, !swipeCancelled else { return }
        if swipeStart == nil { swipeStart = value.time }
        let dx = value.translation.width
        let dy = value.translation.height
        if abs(dy) > 12 && abs(dy) > abs(dx) * 1.2 {
          swipeCancelled = true
          settle()
          return
        }
        if abs(dx) > 8 && abs(dx) > abs(dy) * 1.2 {
          let limit = width * 0.4
          swipeOffset = max(-limit, min(limit, dx))
        }
      }
      .onEnded { value in
        defer {
          swipeStart = nil
          swipeCancelled = false
          settle()
        }
        guard !model.active, !swipeCancelled, let start = swipeStart else { return }
        let direction = CalendarPlan.weekSwipe(
          dx: value.translation.width, dy: value.translation.height,
          elapsed: value.time.timeIntervalSince(start), width: width)
        if direction != 0 { onSwipe(direction) }
      }
  }

  private func settle() {
    withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) {
      swipeOffset = 0
    }
  }

  private func weekday(_ day: String) -> String {
    CalendarText.capitalizedWords(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEE"))
  }
}

/// Half-hour lines: whole hours in the line colour, half hours lighter.
private struct CalendarSlotLines: Shape {
  let hour: CGFloat
  var wholeHours = false

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for index in 0..<48 where (index % 2 == 0) == wholeHours {
      let y = CGFloat(index) * hour / 2 + 0.5
      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: rect.width, y: y))
    }
    return path
  }
}

/// `.cal-now-line`: a 2 pt accent line with an 8 pt dot at its start.
private struct CalendarNowLine: View {
  var body: some View {
    Rectangle()
      .fill(RitmTheme.accentColor)
      .frame(height: 2)
      .overlay(alignment: .leading) {
        Circle().fill(RitmTheme.accentColor).frame(width: 8, height: 8).offset(x: -4)
      }
      .accessibilityHidden(true)
  }
}

/// An entry's tinted surface with the 2 pt bar on its leading edge.
struct CalendarEntrySurface: View {
  let colorID: String?
  var radius: CGFloat = 4
  var outlined = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
    shape
      .fill(CalendarPalette.entryFill(colorID))
      .overlay(alignment: .leading) {
        Rectangle().fill(CalendarPalette.entryBorder(colorID)).frame(width: 2)
      }
      .clipShape(shape)
      .overlay {
        if outlined { shape.strokeBorder(CalendarPalette.entryBorder(colorID), lineWidth: 1) }
      }
  }
}

/// The offset of the grid content inside its scroll view, read to turn a finger position into a
/// time slot and to know how far auto-scroll may go.
private struct WeekScrollOffsetKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The card of one entry in the week grid: title and time on the tinted surface. It has no
/// position and no gestures, so the lifted copy under the finger looks the same.
struct CalendarEventCard: View {
  let entry: DayOccurrence
  let width: CGFloat
  let height: CGFloat
  @Environment(RitmStore.self) private var store

  private var tiny: Bool { (entry.end ?? 0) - (entry.start ?? 0) < 45 }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(CalendarText.marker(entry) + entry.title)
        .ritmFont(tiny ? 12 : 11, weight: .semibold)
        .lineLimit(1)
        .strikethrough(entry.completed)
      if !tiny {
        Text(time)
          .ritmFont(10)
          .monospacedDigit()
          .lineLimit(1)
      }
    }
    .foregroundStyle(RitmTheme.text)
    .padding(.vertical, tiny ? 2 : 4)
    .padding(.horizontal, tiny ? 5 : 2)
    .padding(.leading, 2)
    .frame(width: width, height: height, alignment: .topLeading)
    .background { CalendarEntrySurface(colorID: entry.colorId, outlined: true) }
  }

  private var time: String {
    CalendarPlan.entryTime(entry, start: true) + "–" + CalendarPlan.entryTime(entry, start: false)
      + (entry.clockChange ? store.text(" · Перевод часов", " · Clock change") : "")
  }
}

/// `.cal-grid-event` in the mobile week: a tap opens the entry; the hold that lifts it is
/// handled by the grid, which also dims this card while its copy is in the air.
private struct CalendarGridEvent: View {
  let placed: PlacedOccurrence
  let column: CGFloat
  let hour: CGFloat
  let lifted: Bool
  let hint: String
  let onOpen: () -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    let frame = CalendarPlan.entryFrame(placed, column: Double(column), hourHeight: Double(hour))
    CalendarEventCard(
      entry: placed.entry, width: CGFloat(frame.width), height: CGFloat(frame.height)
    )
    .opacity(lifted ? 0.3 : 1)
    .offset(x: CGFloat(frame.x), y: CGFloat(frame.y))
    .zIndex(1)
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(CalendarText.occurrenceLabel(placed.entry, store: store))
    .accessibilityHint(hint)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onOpen)
  }
}
