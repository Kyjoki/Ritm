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

/// The list behind the overlap button (`.cal-event-picker`).
struct CalendarOverlapPicker: View {
  let date: String
  let entries: [DayOccurrence]
  let onOpen: (DayOccurrence) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.calendarHourFormat) private var format

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
                RitmIcon(.rightIcon).foregroundStyle(RitmTheme.muted)
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
        : format.entryRange(entry)
    return value + (entry.event?.readOnly == true ? store.text(" · Только просмотр", " · View only") : "")
  }
}
