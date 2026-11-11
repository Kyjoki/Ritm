import RitmCore
import SwiftUI

/// «Месяц»: six rows of seven days filling the room above the bottom bar, each cell with the day
/// number and up to a few solid mini bars (`+N` when more do not fit). A tap opens that day; a
/// horizontal swipe slides to the next or previous month.
struct CalendarMonthView: View {
  let selected: String
  let today: String
  let entries: (String) -> [DayOccurrence]
  let onSelect: (String) -> Void
  /// One month forward (1) or back (-1).
  let onStep: (Int) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var offset: CGFloat = 0
  @State private var sliding = false
  @State private var touchStart: Date?

  private static let weekdayRow: CGFloat = 26
  private static let bottomClearance: CGFloat = 84
  private static let barHeight: CGFloat = 14
  private static let barSpacing: CGFloat = 2

  private var weekdays: [String] {
    store.language == .ru
      ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  }

  var body: some View {
    GeometryReader { proxy in
      let rowHeight = max(
        44, (proxy.size.height - Self.weekdayRow - Self.bottomClearance) / 6)
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          ForEach(weekdays, id: \.self) { day in
            Text(day).ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.muted)
              .frame(maxWidth: .infinity)
          }
        }
        .frame(height: Self.weekdayRow)
        .accessibilityHidden(true)
        weeks(rowHeight: rowHeight)
          .offset(x: offset)
          .frame(width: proxy.size.width)
          .clipped()
          .simultaneousGesture(swipe(width: proxy.size.width))
        Spacer(minLength: 0)
      }
    }
  }

  private func weeks(rowHeight: CGFloat) -> some View {
    let days = CalendarPlan.monthDays(containing: selected)
    return VStack(spacing: 0) {
      if days.count == 42 {
        ForEach(0..<6, id: \.self) { row in
          HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
              cell(days[row * 7 + column], rowHeight: rowHeight, column: column)
            }
          }
        }
      }
    }
  }

  private func cell(_ day: String, rowHeight: CGFloat, column: Int) -> some View {
    let dayEntries = entries(day)
    let inMonth = day.prefix(7) == selected.prefix(7)
    let limit = max(1, Int((rowHeight - 30) / (Self.barHeight + Self.barSpacing)))
    let bars = CalendarPlan.monthBars(dayEntries, limit: limit)
    return Button {
      onSelect(day)
    } label: {
      VStack(spacing: Self.barSpacing) {
        number(day)
        ForEach(bars.shown) { entry in
          CalendarChip(entry: entry, fontSize: 10, height: Self.barHeight)
        }
        if bars.more > 0 {
          Text("+\(bars.more)").ritmFont(10, weight: .semibold).foregroundStyle(RitmTheme.muted)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 1)
      .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .top)
      .background(day == today ? RitmTheme.accentColor.opacity(0.07) : Color.clear)
      .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
      .overlay(alignment: .leading) {
        if column > 0 { Rectangle().fill(RitmTheme.line.opacity(0.75)).frame(width: 1) }
      }
      .opacity(inMonth ? 1 : 0.42)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "d MMMM")
        + store.text(", записей: \(dayEntries.count). Открыть день", ", entries: \(dayEntries.count). Open day"))
  }

  private func number(_ day: String) -> some View {
    let isToday = day == today
    return Text("\(Int(day.suffix(2)) ?? 0)")
      .ritmFont(13, weight: isToday ? .bold : .semibold)
      .monospacedDigit()
      .foregroundStyle(isToday ? RitmTheme.accentInk : RitmTheme.text)
      .frame(minWidth: 24, minHeight: 24)
      .background {
        if isToday {
          Circle().fill(RitmTheme.accentColor)
        } else if day == selected {
          Circle().strokeBorder(RitmTheme.accentColor, lineWidth: 1.5)
        }
      }
      .padding(.vertical, 2)
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
