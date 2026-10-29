import RitmCore
import SwiftUI

/// The week timetable on a phone (CalendarPage.tsx with `.cal-mobile-week`): seven columns across
/// the screen, 48 pt per hour, a 40 pt time column, overlaps behind a per-day button, swipe to
/// change week and long-press-drag to move editable Google events.
struct CalendarWeekGrid: View {
  let days: [String]
  let entries: [String: [DayOccurrence]]
  let today: String
  let timeZoneLabel: String
  let jumpToNow: Int
  let canDrag: (DayOccurrence) -> Bool
  let onOpen: (DayOccurrence) -> Void
  let onPick: (String, [DayOccurrence]) -> Void
  let onAdd: (String, Int) -> Void
  let onSelectDay: (String) -> Void
  let onMove: (DayOccurrence, String, Int) -> Void
  let onSwipe: (Int) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var swipeOffset: CGFloat = 0
  @State private var swipeStart: Date?
  @State private var swipeCancelled = false
  @State private var draggingEvent = false

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

  private func grid(column: CGFloat, width: CGFloat) -> some View {
    ScrollViewReader { reader in
      ScrollView {
        HStack(alignment: .top, spacing: 0) {
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
          .accessibilityHidden(true)
          ForEach(Array(days.enumerated()), id: \.element) { index, day in
            dayColumn(day, index: index, column: column)
          }
        }
        .offset(x: swipeOffset)
      }
      .scrollIndicators(.hidden)
      .simultaneousGesture(swipe(width: width))
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

  private func dayColumn(_ day: String, index: Int, column: CGFloat) -> some View {
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
          placed: placed, column: column, hour: hour, draggable: canDrag(placed.entry),
          onOpen: { onOpen(placed.entry) },
          onDragging: { draggingEvent = $0 },
          onDrop: { translation in drop(placed, from: index, translation: translation, column: column) })
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

  private func drop(_ placed: PlacedOccurrence, from index: Int, translation: CGSize, column: CGFloat) {
    let target = max(0, min(days.count - 1, index + Int((translation.width / column).rounded())))
    let raw = Double(placed.start) + Double(translation.height / hour) * 60
    let minute = CalendarPlan.snappedStart(rawMinutes: raw, duration: placed.end - placed.start)
    guard target != index || minute != placed.start else { return }
    onMove(placed.entry, days[target], minute)
  }

  /// A deliberate horizontal swipe changes the week; vertical scrolling is left alone.
  private func swipe(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        guard !draggingEvent, !swipeCancelled else { return }
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
        guard !draggingEvent, !swipeCancelled, let start = swipeStart else { return }
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

/// `.cal-grid-event` in the mobile week.
private struct CalendarGridEvent: View {
  let placed: PlacedOccurrence
  let column: CGFloat
  let hour: CGFloat
  let draggable: Bool
  let onOpen: () -> Void
  let onDragging: (Bool) -> Void
  let onDrop: (CGSize) -> Void
  @Environment(RitmStore.self) private var store
  @GestureState private var drag: CGSize?

  private var entry: DayOccurrence { placed.entry }
  private var duration: Int { placed.end - placed.start }
  private var tiny: Bool { duration < 45 }

  var body: some View {
    let width = max(1, column / CGFloat(placed.lanes) - 2)
    let height = max(22, CGFloat(duration) / 60 * hour - 4)
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
    .overlay(alignment: .bottomLeading) {
      if let drag {
        Text(DayPlan.clock(previewStart(drag)))
          .ritmFont(10, weight: .semibold)
          .foregroundStyle(RitmTheme.accentInk)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(RitmTheme.accentColor, in: Capsule())
          .fixedSize()
          .offset(y: 20)
      }
    }
    .shadow(color: drag == nil ? .clear : RitmTheme.panelShadow, radius: 10, y: 6)
    .offset(
      x: CGFloat(placed.lane) * column / CGFloat(placed.lanes) + 1 + (drag?.width ?? 0),
      y: CGFloat(placed.start) / 60 * hour + 2 + (drag?.height ?? 0)
    )
    .zIndex(drag == nil ? 1 : 10)
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
    .gesture(moveGesture, including: draggable ? .all : .subviews)
    .onChange(of: drag != nil) { _, active in onDragging(active) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(CalendarText.occurrenceLabel(entry, store: store))
    .accessibilityHint(
      draggable
        ? store.text(
          "Удерживайте и перетащите запись на другое время или день.",
          "Hold and drag the entry to another time or day.") : "")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onOpen)
  }

  private var time: String {
    CalendarPlan.entryTime(entry, start: true) + "–" + CalendarPlan.entryTime(entry, start: false)
      + (entry.clockChange ? store.text(" · Перевод часов", " · Clock change") : "")
  }

  private func previewStart(_ translation: CGSize) -> Int {
    CalendarPlan.snappedStart(
      rawMinutes: Double(placed.start) + Double(translation.height / hour) * 60, duration: duration)
  }

  /// Hold for 280 ms, then drag; the move is saved on release, as on the web.
  private var moveGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.28)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .updating($drag) { value, state, _ in
        if case .second(true, let movement) = value { state = movement?.translation ?? .zero }
      }
      .onEnded { value in
        if case .second(true, let movement?) = value { onDrop(movement.translation) }
      }
  }
}
