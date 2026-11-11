import RitmCore
import SwiftUI

/// «Месяц»: six rows of seven days filling the room above the bottom bar, each cell with the day
/// number and up to a few solid mini bars (`+N` when more do not fit). A tap opens that day; a
/// horizontal swipe slides to the next or previous month.
///
/// Light by construction: the cells come ready from `CalendarDayModel` (read once per data
/// change, never inside this body), the only measuring is the one geometry reader for the row
/// height, and every cell is an equatable view, so a swipe or a changed day redraws only the
/// cells whose data changed.
struct CalendarMonthView: View, Equatable {
  let dayModel: CalendarDayModel
  let generation: Int
  let selected: String
  let today: String
  let onSelect: (String) -> Void
  /// One month forward (1) or back (-1).
  let onStep: (Int) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(RitmStore.self) private var store
  @State private var offset: CGFloat = 0
  @State private var sliding = false
  @State private var touchStart: Date?

  private static let weekdayRow: CGFloat = 26
  private static let bottomClearance: CGFloat = 84
  private static let barHeight: CGFloat = 14
  private static let barSpacing: CGFloat = 2

  nonisolated static func == (left: CalendarMonthView, right: CalendarMonthView) -> Bool {
    left.generation == right.generation && left.selected == right.selected && left.today == right.today
  }

  private var weekdays: [String] {
    store.language == .ru
      ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  }

  var body: some View {
    GeometryReader { proxy in
      let rowHeight = max(
        44, (proxy.size.height - Self.weekdayRow - Self.bottomClearance) / 6)
      let limit = max(1, Int((rowHeight - 30) / (Self.barHeight + Self.barSpacing)))
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          ForEach(weekdays, id: \.self) { day in
            Text(day).ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.muted)
              .frame(maxWidth: .infinity)
          }
        }
        .frame(height: Self.weekdayRow)
        .accessibilityHidden(true)
        weeks(
          dayModel.monthRows(anchor: selected, today: today, selected: selected, limit: limit),
          rowHeight: rowHeight
        )
        .offset(x: offset)
        .frame(width: proxy.size.width)
        .clipped()
        .simultaneousGesture(swipe(width: proxy.size.width))
        Spacer(minLength: 0)
      }
    }
  }

  private func weeks(_ rows: [[CalendarMonthCell]], rowHeight: CGFloat) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 0) {
          ForEach(Array(row.enumerated()), id: \.element.id) { column, cell in
            CalendarMonthCellView(
              cell: cell, column: column, rowHeight: rowHeight, onSelect: onSelect
            )
            .equatable()
          }
        }
      }
    }
  }

  // MARK: Swipe between months

  private func swipe(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 16)
      .onChanged { value in
        guard !sliding, abs(value.translation.width) > abs(value.translation.height) else { return }
        if touchStart == nil { touchStart = Date() }
        offset = max(-width * 0.4, min(width * 0.4, value.translation.width))
      }
      .onEnded { value in
        let elapsed = Date().timeIntervalSince(touchStart ?? Date())
        touchStart = nil
        let direction = CalendarPlan.weekSwipe(
          dx: value.translation.width, dy: value.translation.height, elapsed: elapsed, width: width)
        guard direction != 0, !sliding else {
          withAnimation(reduceMotion ? nil : RitmMotion.easeOut(0.22)) { offset = 0 }
          return
        }
        sliding = true
        Task { @MainActor in
          await CalendarSlide.run(
            direction: direction, width: width, reduceMotion: reduceMotion, offset: $offset
          ) { onStep(direction) }
          sliding = false
        }
      }
  }
}

/// One day of the month: its number, mini bars and the «+N» counter. Drawn again only when its
/// own data changes.
struct CalendarMonthCellView: View, Equatable {
  let cell: CalendarMonthCell
  let column: Int
  let rowHeight: CGFloat
  let onSelect: (String) -> Void
  @Environment(RitmStore.self) private var store

  private static let barHeight: CGFloat = 14
  private static let barSpacing: CGFloat = 2

  nonisolated static func == (left: CalendarMonthCellView, right: CalendarMonthCellView) -> Bool {
    left.cell == right.cell && left.rowHeight == right.rowHeight
  }

  var body: some View {
    Button {
      onSelect(cell.day)
    } label: {
      VStack(spacing: Self.barSpacing) {
        number
        ForEach(cell.bars) { entry in
          CalendarChip(entry: entry, fontSize: 10, height: Self.barHeight)
        }
        if cell.more > 0 {
          Text("+\(cell.more)").ritmFont(10, weight: .semibold).foregroundStyle(RitmTheme.muted)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 1)
      .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .top)
      .background(cell.isToday ? RitmTheme.accentColor.opacity(0.07) : Color.clear)
      .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
      .overlay(alignment: .leading) {
        if column > 0 { Rectangle().fill(RitmTheme.line.opacity(0.75)).frame(width: 1) }
      }
      .opacity(cell.inMonth ? 1 : 0.42)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(
      FeatureDate.label(cell.day, zone: store.timeZone, language: store.language, template: "d MMMM")
        + store.text(
          ", записей: \(cell.total). Открыть день", ", entries: \(cell.total). Open day"))
  }

  private var number: some View {
    Text("\(cell.number)")
      .ritmFont(13, weight: cell.isToday ? .bold : .semibold)
      .monospacedDigit()
      .foregroundStyle(cell.isToday ? RitmTheme.accentInk : RitmTheme.text)
      .frame(minWidth: 24, minHeight: 24)
      .background {
        if cell.isToday {
          Circle().fill(RitmTheme.accentColor)
        } else if cell.isSelected {
          Circle().strokeBorder(RitmTheme.accentColor, lineWidth: 1.5)
        }
      }
      .padding(.vertical, 2)
  }
}
