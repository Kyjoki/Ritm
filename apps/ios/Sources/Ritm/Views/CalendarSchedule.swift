import RitmCore
import SwiftUI

/// «Расписание»: the agenda list. Each day with entries (and today and the chosen day, even when
/// empty) is a section: the weekday and date on the left, a solid block per entry on the right.
/// The chosen day also offers its free windows (`.cal-mobile-agenda`).
struct CalendarSchedule: View {
  let days: [String]
  let selected: String
  let today: String
  let entries: (String) -> [DayOccurrence]
  let uncertain: Bool
  let googleConnected: Bool
  let onOpen: (DayOccurrence) -> Void
  let onAddFree: (String, String, Int) -> Void
  let onMore: () -> Void
  let onRefresh: () async -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.calendarHourFormat) private var format

  var body: some View {
    let rows = days.map { (day: $0, entries: entries($0)) }
      .filter { $0.day == today || $0.day == selected || !$0.entries.isEmpty }
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.day) { index, row in
          section(row.day, row.entries, first: index == 0)
        }
        Button(action: onMore) {
          Text(store.text("Показать ещё 4 недели", "Show 4 more weeks"))
            .ritmFont(13, weight: .medium)
            .foregroundStyle(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.97))
        .padding(.top, 8)
      }
      .padding(.bottom, 96)
    }
    .id(selected)
    .scrollIndicators(.hidden)
    .refreshable { await onRefresh() }
  }

  // MARK: Day sections

  private func section(_ day: String, _ list: [DayOccurrence], first: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      dateColumn(day)
      VStack(spacing: 6) {
        ForEach(list) { row($0) }
        if list.isEmpty {
          Text(
            uncertain
              ? store.text("В Ritm на этот день пока нет планов", "No plans in Ritm for this day yet")
              : store.text("На этот день пока нет планов", "No plans for this day yet")
          )
          .ritmFont(12)
          .foregroundStyle(RitmTheme.muted)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        if day == selected && !uncertain { freeWindows(day, list) }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .overlay(alignment: .top) {
      if !first { Rectangle().fill(RitmTheme.line).frame(height: 1) }
    }
  }

  private func dateColumn(_ day: String) -> some View {
    let isToday = day == today
    return VStack(spacing: 2) {
      Text(
        CalendarText.capitalizedWords(
          FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEE"))
      )
      .ritmFont(11, weight: .semibold)
      .foregroundStyle(isToday ? RitmTheme.accentColor : RitmTheme.muted)
      Text("\(Int(day.suffix(2)) ?? 0)")
        .ritmFont(20, weight: isToday ? .bold : .semibold, tracking: -0.04)
        .foregroundStyle(isToday ? RitmTheme.accentInk : RitmTheme.text)
        .frame(width: 38, height: 38)
        .background {
          if isToday { Circle().fill(RitmTheme.accentColor) }
        }
    }
    .frame(width: 44)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEEE d MMMM")
        + (isToday ? store.text(", сегодня", ", today") : ""))
    .accessibilityAddTraits(.isHeader)
  }

  private func row(_ entry: DayOccurrence) -> some View {
    Button {
      onOpen(entry)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(CalendarText.marker(entry) + entry.title)
          .ritmFont(14, weight: .semibold)
          .multilineTextAlignment(.leading)
          .strikethrough(entry.completed)
        Text(details(entry)).ritmFont(12).lineLimit(1).opacity(0.92)
      }
      .foregroundStyle(CalendarPalette.ink(entry.colorId))
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .background(
        CalendarPalette.solid(entry.colorId), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .opacity(entry.completed ? 0.6 : 1)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(CalendarText.occurrenceLabel(entry, store: store))
  }

  private func details(_ entry: DayOccurrence) -> String {
    let time =
      entry.allDay
      ? store.text("Весь день", "All day")
      : entry.start == nil ? store.text("Без времени", "No time") : format.entryRange(entry)
    let source = entry.event != nil ? "Google Calendar" : store.text("Ритм", "Ritm")
    var text = time + " · " + source
    if entry.continued { text += store.text(" · Продолжение", " · Continued") }
    if entry.clockChange { text += store.text(" · Перевод часов", " · Clock change") }
    if entry.event?.readOnly == true { text += store.text(" · Просмотр", " · View only") }
    return text
  }

  // MARK: Free windows

  @ViewBuilder private func freeWindows(_ day: String, _ list: [DayOccurrence]) -> some View {
    ForEach(Array(CalendarPlan.freeIntervals(list).prefix(2)), id: \.start) { interval in
      Button {
        onAddFree(day, TaskSchedule.minuteTime(interval.start), min(60, interval.end - interval.start))
      } label: {
        Label {
          Text(
            (googleConnected
              ? store.text("Свободно", "Free") : store.text("Свободно в Ritm", "Free in Ritm"))
              + " " + format.clock(interval.start) + "–" + format.clock(interval.end))
        } icon: {
          RitmSymbol("plus").font(.system(size: 14, weight: .medium))
        }
        .ritmFont(12)
        .foregroundStyle(RitmTheme.accentColor)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(
              RitmTheme.mix(RitmTheme.accentColor, 0.45, into: RitmTheme.line),
              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
      }
      .buttonStyle(RitmPressStyle(scale: 0.97))
    }
  }
}
