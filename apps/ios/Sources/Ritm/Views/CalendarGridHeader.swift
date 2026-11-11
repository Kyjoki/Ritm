import RitmCore
import SwiftUI

/// The rows above the hours: weekday and date, the overlap buttons and the all-day chips. Only a
/// hairline under the block separates it from the hours; the day separators are drawn by the
/// hour grid itself, never here. Every row's day cells slide with `swipeOffset`, the time column
/// stays put.
struct CalendarGridHeader: View {
  let days: [String]
  let entries: [String: [DayOccurrence]]
  let today: String
  let timeZoneLabel: String
  let column: CGFloat
  let swipeOffset: CGFloat
  let canSelectDay: Bool
  let onSelectDay: (String) -> Void
  let onOpen: (DayOccurrence) -> Void
  let onPick: (String, [DayOccurrence]) -> Void
  @Environment(RitmStore.self) private var store

  private let timeColumn = CGFloat(CalendarPlan.timeColumn)
  /// Under this column width side-by-side lanes are too thin to read: the day gets an overlap
  /// button that opens the list instead.
  private static let narrowColumn: CGFloat = 90

  private var overlaps: [String: [DayOccurrence]] {
    guard column < Self.narrowColumn else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: days.map { day in
        (day, CalendarPlan.overlapGroups(entries[day] ?? []).filter { $0.count > 1 }.flatMap { $0 })
      })
  }

  private func untimed(_ day: String) -> [DayOccurrence] {
    (entries[day] ?? []).filter { $0.start == nil }
  }

  var body: some View {
    let overlapMap = overlaps
    VStack(spacing: 0) {
      dayRow
      if overlapMap.values.contains(where: { !$0.isEmpty }) { overlapRow(overlapMap) }
      if days.contains(where: { !untimed($0).isEmpty }) { allDayRow }
    }
    .padding(.bottom, 4)
    .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
  }

  /// A row of day cells next to the fixed time column, sliding with the swipe.
  private func row<Cells: View>(
    gutter: some View, @ViewBuilder cells: () -> Cells
  ) -> some View {
    HStack(alignment: .top, spacing: 0) {
      gutter.frame(width: timeColumn)
      cells()
        .offset(x: swipeOffset)
        .frame(width: column * CGFloat(days.count), alignment: .leading)
        .clipped()
    }
  }

  // MARK: Weekday and date

  private var dayRow: some View {
    row(
      gutter: Text(timeZoneLabel)
        .ritmFont(9.5, weight: .semibold)
        .foregroundStyle(RitmTheme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, 6)
    ) {
      HStack(spacing: 0) { ForEach(days, id: \.self) { dayCell($0) } }
    }
    .frame(minHeight: 56)
  }

  private func dayCell(_ day: String) -> some View {
    let isToday = day == today
    return Button {
      onSelectDay(day)
    } label: {
      VStack(spacing: 2) {
        Text(weekday(day))
          .ritmFont(11, weight: .semibold)
          .foregroundStyle(isToday ? RitmTheme.accentColor : RitmTheme.muted)
        Text("\(Int(day.suffix(2)) ?? 0)")
          .ritmFont(17, weight: isToday ? .bold : .medium, tracking: -0.04)
          .foregroundStyle(isToday ? RitmTheme.accentInk : RitmTheme.text)
          .frame(width: 30, height: 30)
          .background {
            if isToday { Circle().fill(RitmTheme.accentColor) }
          }
      }
      .frame(width: column, height: 56, alignment: .center)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .disabled(!canSelectDay)
    .accessibilityLabel(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEEE d MMMM")
        + (isToday ? store.text(", сегодня", ", today") : ""))
    .accessibilityHint(canSelectDay ? store.text("Открыть день", "Open the day") : "")
  }

  private func weekday(_ day: String) -> String {
    CalendarText.capitalizedWords(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEE"))
  }

  // MARK: Overlaps

  private func overlapRow(_ groups: [String: [DayOccurrence]]) -> some View {
    row(gutter: Color.clear.frame(height: 1)) {
      HStack(spacing: 0) {
        ForEach(days, id: \.self) { day in
          let group = groups[day] ?? []
          if group.isEmpty {
            Color.clear.frame(width: column, height: 28)
          } else {
            overlapButton(day, group)
          }
        }
      }
    }
    .padding(.top, 2)
  }

  private func overlapButton(_ day: String, _ group: [DayOccurrence]) -> some View {
    Button {
      onPick(day, group)
    } label: {
      HStack(spacing: 3) {
        RitmSymbol("square.stack").font(.system(size: 10)).accessibilityHidden(true)
        Text("\(group.count)").ritmFont(11, weight: .semibold)
      }
      .foregroundStyle(RitmTheme.accentColor)
      .frame(width: max(1, column - 6), height: 24)
      .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .frame(width: column, height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .frame(width: column, height: 28)
    .accessibilityLabel(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "d MMMM")
        + ": \(group.count) " + CalendarPlan.recordWord(group.count, language: store.language)
        + store.text(" с пересечением. Выбрать событие", " overlapping. Choose an event"))
  }

  // MARK: All-day chips

  /// Scrolls once it would grow past 96 pt, as `.cal-all-day` does.
  @ViewBuilder private var allDayRow: some View {
    let rows = days.map { untimed($0).count }.max() ?? 0
    let content = row(gutter: Color.clear.frame(height: 1)) {
      HStack(alignment: .top, spacing: 0) { ForEach(days, id: \.self) { chips($0) } }
    }
    if 4 + CGFloat(rows) * 22 > 96 {
      ScrollView { content }.frame(height: 96)
    } else {
      content
    }
  }

  private func chips(_ day: String) -> some View {
    VStack(spacing: 2) {
      ForEach(untimed(day)) { entry in
        Button {
          onOpen(entry)
        } label: {
          CalendarChip(entry: entry)
        }
        .buttonStyle(RitmPressStyle())
        .accessibilityLabel(CalendarText.occurrenceLabel(entry, store: store))
      }
    }
    .padding(.horizontal, 2)
    .frame(width: column, alignment: .top)
  }
}
