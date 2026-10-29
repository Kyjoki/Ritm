import RitmCore
import SwiftUI

/// Shared wording of calendar entries (CalendarPage.tsx `occurrenceLabel`, `AgendaEntry`).
enum CalendarText {
  /// CSS `text-transform: capitalize`.
  static func capitalizedWords(_ value: String) -> String {
    value.split(separator: " ", omittingEmptySubsequences: false)
      .map { word in word.prefix(1).uppercased() + word.dropFirst() }
      .joined(separator: " ")
  }

  /// Google Tasks show their state before the title.
  static func marker(_ entry: DayOccurrence) -> String {
    guard entry.event?.googleTask != nil else { return "" }
    return entry.completed ? "✓ " : "○ "
  }

  @MainActor static func occurrenceLabel(_ entry: DayOccurrence, store: RitmStore) -> String {
    let time: String
    if entry.allDay {
      time = store.text("Весь день", "All day")
    } else if let start = entry.start {
      time = (entry.startLabel ?? DayPlan.clock(start)) + "–"
        + (entry.endLabel ?? DayPlan.clock(entry.end ?? start))
    } else {
      time = store.text("Без времени", "No time")
    }
    var label = entry.title + ", " + time + (entry.event != nil ? ", Google Calendar" : ", Ritm")
    if entry.completed { label += store.text(", выполнено", ", completed") }
    if entry.event?.readOnly == true { label += store.text(", только просмотр", ", view only") }
    if entry.clockChange { label += store.text(", перевод часов", ", clock change") }
    return label
  }

  /// `durationLabel`: like durationText, but zero minutes read as nothing.
  static func durationLabel(_ minutes: Int, language: Language) -> String {
    minutes <= 0 ? "" : DayPlan.durationText(minutes, language: language)
  }
}

/// «День» on a phone: the agenda list with free windows (`.cal-mobile-agenda`).
struct CalendarAgenda: View {
  let date: String
  let entries: [DayOccurrence]
  let uncertain: Bool
  let googleConnected: Bool
  let onOpen: (DayOccurrence) -> Void
  let onAdd: (String, String?, Int) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Text(
            CalendarText.capitalizedWords(
              FeatureDate.label(
                date, zone: store.timeZone, language: store.language, template: "EEEE d MMMM"))
          )
          .ritmFont(13, weight: .semibold, tracking: -0.02)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
          Spacer(minLength: 0)
          Text(store.text("Записей: \(entries.count)", "Entries: \(entries.count)"))
            .ritmFont(11)
            .foregroundStyle(RitmTheme.muted)
        }
        if entries.isEmpty {
          VStack(spacing: 4) {
            Image(systemName: "calendar")
              .font(.system(size: 22))
              .foregroundStyle(RitmTheme.accentColor.opacity(0.7))
              .accessibilityHidden(true)
            Text(
              uncertain
                ? store.text("В Ritm на этот день пока нет планов", "No plans in Ritm for this day yet")
                : store.text("На этот день пока нет планов", "No plans for this day yet")
            )
            .ritmFont(12)
            .foregroundStyle(RitmTheme.muted)
          }
          .frame(maxWidth: .infinity)
          .padding(.top, 24)
          .padding(.bottom, 12)
        } else {
          ForEach(entries) { row($0) }
        }
        let free = uncertain ? [] : Array(CalendarPlan.freeIntervals(entries).prefix(2))
        if !free.isEmpty {
          VStack(spacing: 8) {
            ForEach(free, id: \.start) { interval in
              Button {
                onAdd(
                  date, TaskSchedule.minuteTime(interval.start), min(60, interval.end - interval.start))
              } label: {
                Label {
                  Text(
                    (googleConnected
                      ? store.text("Свободно", "Free") : store.text("Свободно в Ritm", "Free in Ritm"))
                      + " " + DayPlan.clock(interval.start, compact: true) + "–"
                      + DayPlan.clock(interval.end, compact: true))
                } icon: {
                  Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                }
                .ritmFont(12)
                .foregroundStyle(RitmTheme.accentColor)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 11, style: .circular))
                .overlay {
                  RoundedRectangle(cornerRadius: 11, style: .circular)
                    .strokeBorder(
                      RitmTheme.mix(RitmTheme.accentColor, 0.45, into: RitmTheme.line),
                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
              }
              .buttonStyle(RitmPressStyle(scale: 0.97))
            }
          }
          .padding(.top, 14)
        }
        Button {
          onAdd(date, nil, 60)
        } label: {
          Label(store.text("Добавить запись", "Add entry"), systemImage: "plus")
            .ritmFont(12, weight: .medium)
            .foregroundStyle(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.97))
        .padding(.top, 6)
      }
      .padding(19)
    }
  }

  private func row(_ entry: DayOccurrence) -> some View {
    let google = entry.event != nil
    var details: String
    if google {
      details = "Google Calendar"
    } else if entry.task?.task.kind == .event {
      details = store.text("Событие Ritm", "Ritm event")
    } else {
      details = store.text("Задача Ritm", "Ritm task")
    }
    details +=
      " · "
      + (entry.allDay
        ? store.text("Весь день", "All day")
        : CalendarText.durationLabel(entry.duration, language: store.language))
    if entry.continued { details += store.text(" · Продолжение", " · Continued") }
    if entry.clockChange { details += store.text(" · Перевод часов", " · Clock change") }
    if entry.event?.readOnly == true { details += store.text(" · Просмотр", " · View only") }
    if google && !entry.busy { details += store.text(" · Время свободно", " · Shown as free") }
    return Button {
      onOpen(entry)
    } label: {
      HStack(spacing: 12) {
        Group {
          if entry.start == nil {
            Image(systemName: "clock").font(.system(size: 16))
          } else {
            Text(CalendarPlan.entryTime(entry, start: true)).ritmFont(12).monospacedDigit()
          }
        }
        .frame(width: 70, alignment: .leading)
        VStack(alignment: .leading, spacing: 3) {
          Text(CalendarText.marker(entry) + entry.title)
            .ritmFont(13, weight: .medium, lineSpacing: 3)
            .multilineTextAlignment(.leading)
          Text(details).ritmFont(10, lineSpacing: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: entry.completed ? "checkmark" : "chevron.right")
          .font(.system(size: 14, weight: .medium))
          .accessibilityHidden(true)
      }
      .foregroundStyle(RitmTheme.text)
      .padding(.vertical, 16)
      .padding(.leading, google ? 10 : 0)
      .padding(.trailing, 4)
      .background {
        Rectangle().fill(CalendarPalette.entryFill(entry.colorId))
          .overlay(alignment: .leading) {
            if google { Rectangle().fill(CalendarPalette.entryBorder(entry.colorId)).frame(width: 2) }
          }
      }
      .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .accessibilityLabel(CalendarText.occurrenceLabel(entry, store: store))
  }
}

/// «Месяц» on a phone: 42 cells with up to three coloured dots (`.cal-month-panel`).
struct CalendarMonthGrid: View {
  let selected: String
  let today: String
  let entries: (String) -> [DayOccurrence]
  let onSelect: (String) -> Void
  @Environment(RitmStore.self) private var store

  private var weekdays: [String] {
    store.language == .ru
      ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  }

  var body: some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    ScrollView {
      LazyVGrid(columns: columns, spacing: 4) {
        ForEach(weekdays, id: \.self) { day in
          Text(day).ritmFont(10).foregroundStyle(RitmTheme.muted).frame(height: 20)
        }
        ForEach(CalendarPlan.monthDays(containing: selected), id: \.self) { day in
          cell(day)
        }
      }
      .padding(.vertical, 14)
      .padding(.horizontal, 10)
    }
  }

  private func cell(_ day: String) -> some View {
    let dayEntries = entries(day)
    let currentMonth = day.prefix(7) == selected.prefix(7)
    let isToday = day == today
    let shape = RoundedRectangle(cornerRadius: 9, style: .circular)
    return Button {
      onSelect(day)
    } label: {
      VStack(spacing: 0) {
        Text("\(Int(day.suffix(2)) ?? 0)")
          .ritmFont(14, weight: isToday ? .bold : .regular)
          .foregroundStyle(isToday ? RitmTheme.accentColor : currentMonth ? RitmTheme.text : RitmTheme.muted)
          .frame(minWidth: 24, minHeight: 25)
          .padding(.vertical, 9)
          .frame(maxWidth: .infinity, minHeight: 49)
        HStack(spacing: 3) {
          ForEach(dayEntries.prefix(3)) { entry in
            Circle().fill(CalendarPalette.entryBorder(entry.colorId)).frame(width: 4, height: 4)
          }
        }
        .frame(height: 4)
        .padding(.bottom, 8)
      }
      .frame(maxWidth: .infinity, minHeight: 61)
      .background(
        isToday
          ? RitmTheme.mix(RitmTheme.soft, 0.6, into: RitmTheme.panel)
          : currentMonth ? RitmTheme.panel : RitmTheme.background,
        in: shape
      )
      .overlay {
        shape.strokeBorder(
          isToday ? RitmTheme.mix(RitmTheme.accentColor, 0.4, into: RitmTheme.line) : RitmTheme.line,
          lineWidth: 1)
      }
      .contentShape(shape)
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .accessibilityLabel(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "d MMMM")
        + store.text(", записей: \(dayEntries.count). Открыть день", ", entries: \(dayEntries.count). Open day"))
  }
}

/// The list behind the overlap button (`.cal-event-picker`).
struct CalendarOverlapPicker: View {
  let date: String
  let entries: [DayOccurrence]
  let onOpen: (DayOccurrence) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            CalendarText.capitalizedWords(
              FeatureDate.label(
                date, zone: store.timeZone, language: store.language, template: "EEEE d MMMM"))
              + store.text(
                ". Выбери запись, чтобы посмотреть подробности или изменить её.",
                ". Choose an entry to see its details or change it.")
          )
          .ritmFont(13, lineSpacing: 6)
          .foregroundStyle(RitmTheme.muted)
          .padding(.vertical, 8)
          if entries.isEmpty {
            Text(
              store.text(
                "Эти события уже изменились. Закрой список и выбери запись в обновлённом календаре.",
                "These events have changed. Close the list and choose an entry in the updated calendar.")
            )
            .ritmFont(13, lineSpacing: 6)
            .foregroundStyle(RitmTheme.muted)
          }
          ForEach(entries) { entry in
            Button {
              dismiss()
              onOpen(entry)
            } label: {
              HStack(spacing: 12) {
                Circle().fill(CalendarPalette.entryBorder(entry.colorId)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 5) {
                  Text(entry.title).ritmFont(14, weight: .semibold, lineSpacing: 4)
                    .foregroundStyle(RitmTheme.text)
                    .multilineTextAlignment(.leading)
                  Text(time(entry)).ritmFont(12).foregroundStyle(RitmTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(RitmTheme.muted)
                  .accessibilityHidden(true)
              }
              .padding(.vertical, 13)
              .padding(.horizontal, 12)
              .frame(minHeight: 64)
              .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .circular))
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
              }
            }
            .buttonStyle(RitmPressStyle(scale: 0.97))
            .accessibilityLabel(CalendarText.occurrenceLabel(entry, store: store))
          }
        }
        .padding(20)
      }
      .background(RitmTheme.background)
      .navigationTitle(store.text("Пересекающиеся события", "Overlapping events"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Закрыть список", "Close list")) { dismiss() }
        }
      }
    }
  }

  private func time(_ entry: DayOccurrence) -> String {
    let value =
      entry.allDay
      ? store.text("Весь день", "All day")
      : entry.start == nil
        ? store.text("Без времени", "No time")
        : CalendarPlan.entryTime(entry, start: true) + "–" + CalendarPlan.entryTime(entry, start: false)
    return value + (entry.event?.readOnly == true ? store.text(" · Только просмотр", " · View only") : "")
  }
}
