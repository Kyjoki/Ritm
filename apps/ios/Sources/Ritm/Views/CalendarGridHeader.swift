import RitmCore
import SwiftUI

/// The rows above the hours: weekday and date, the overlap buttons and the all-day chips. Only a
/// hairline under the block separates it from the hours; the day separators are drawn by the
/// hour grid itself, never here. The day cells are pages of the same strip as the hours and slide with
/// them, the time column with the UTC label stays put. The cells are a separate, equatable view:
/// a swipe moves them without building them again.
struct CalendarGridHeader: View {
  let window: CalendarPagerWindow
  let pager: CalendarPagerPosition
  let model: CalendarDayModel
  let today: String
  let timeZoneLabel: String
  let column: CGFloat
  let canSelectDay: Bool
  let onSelectDay: (String) -> Void
  let onOpen: (DayOccurrence) -> Void
  let onPick: (String, [DayOccurrence]) -> Void

  private let timeColumn = CGFloat(CalendarPlan.timeColumn)
  static let dayRowHeight: CGFloat = 56

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      // A fixed height: with `maxHeight: .infinity` the label took all the free vertical space
      // and pushed the all-day row far below the dates.
      Text(timeZoneLabel)
        .ritmFont(9.5, weight: .semibold)
        .foregroundStyle(RitmTheme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.leading, 4)
        .padding(.bottom, 6)
        .frame(width: timeColumn, height: Self.dayRowHeight, alignment: .bottomLeading)
      CalendarPageStrip(position: pager, window: window) { cells(slot: $0) }
      .frame(width: column * CGFloat(window.currentDays.count), alignment: .leading)
      .clipped()
    }
    .padding(.bottom, 4)
    .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
  }

  private func cells(slot: Int) -> some View {
    let days = window.days(slot: slot)
    return CalendarHeaderCells(
      days: days, model: model, stamps: model.stamps(days), today: today, column: column,
      canSelectDay: canSelectDay, onSelectDay: onSelectDay, onOpen: onOpen, onPick: onPick
    )
    .equatable()
  }
}

/// The weekday and date cells, the overlap buttons and the all-day chips of the visible days.
struct CalendarHeaderCells: View, Equatable {
  let days: [String]
  let model: CalendarDayModel
  let stamps: [Int]
  let today: String
  let column: CGFloat
  let canSelectDay: Bool
  let onSelectDay: (String) -> Void
  let onOpen: (DayOccurrence) -> Void
  let onPick: (String, [DayOccurrence]) -> Void
  @Environment(RitmStore.self) private var store

  /// Under this column width side-by-side lanes are too thin to read: the day gets an overlap
  /// button that opens the list instead.
  private static let narrowColumn: CGFloat = 90

  nonisolated static func == (left: CalendarHeaderCells, right: CalendarHeaderCells) -> Bool {
    left.days == right.days && left.stamps == right.stamps && left.today == right.today
      && left.column == right.column && left.canSelectDay == right.canSelectDay
  }

  private var overlaps: [String: [DayOccurrence]] {
    guard column < Self.narrowColumn else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: days.map { day in
        (day, CalendarPlan.overlapGroups(model.entries(day)).filter { $0.count > 1 }.flatMap { $0 })
      })
  }

  var body: some View {
    let overlapMap = overlaps
    let chips = days.map { day in model.entries(day).filter { $0.start == nil } }
    VStack(spacing: 0) {
      HStack(spacing: 0) { ForEach(days, id: \.self) { dayCell($0) } }
        .frame(height: CalendarGridHeader.dayRowHeight)
      if overlapMap.values.contains(where: { !$0.isEmpty }) {
        overlapRow(overlapMap).padding(.top, 2)
      }
      if chips.contains(where: { !$0.isEmpty }) { allDayRow(chips) }
    }
  }

  // MARK: Weekday and date

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
      .frame(width: column, height: CalendarGridHeader.dayRowHeight, alignment: .center)
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
  @ViewBuilder private func allDayRow(_ chips: [[DayOccurrence]]) -> some View {
    let rows = chips.map(\.count).max() ?? 0
    let content = HStack(alignment: .top, spacing: 0) {
      ForEach(Array(chips.enumerated()), id: \.offset) { _, list in chipColumn(list) }
    }
    if 4 + CGFloat(rows) * 22 > 96 {
      ScrollView { content }.frame(height: 96)
    } else {
      content
    }
  }

  private func chipColumn(_ list: [DayOccurrence]) -> some View {
    VStack(spacing: 2) {
      ForEach(list) { entry in
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
