import RitmCore
import SwiftUI

/// Search over the entries of the last month and the next six: Google events and Ritm tasks by
/// title. The days are read once when the sheet opens, then every keystroke filters them.
struct CalendarSearchSheet: View {
  let load: () async -> [(date: String, entries: [DayOccurrence])]
  let onPick: (CalendarSearchHit) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.calendarHourFormat) private var format
  @State private var query = ""
  @State private var days: [(date: String, entries: [DayOccurrence])] = []
  @State private var loaded = false
  @FocusState private var focused: Bool

  private var hits: [CalendarSearchHit] { CalendarSearch.hits(in: days, query: query) }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        field
        results
      }
      .background(RitmTheme.background)
      .navigationTitle(store.text("Поиск", "Search"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Закрыть", "Close")) { dismiss() }
        }
      }
    }
    .task {
      days = await load()
      loaded = true
    }
    .onAppear { focused = true }
  }

  private var field: some View {
    HStack(spacing: 10) {
      RitmSymbol("magnifyingglass").font(.system(size: 17)).foregroundStyle(RitmTheme.muted)
      TextField(store.text("Поиск по календарю", "Search the calendar"), text: $query)
        .ritmFont(16)
        .focused($focused)
        .submitLabel(.search)
        .autocorrectionDisabled()
        .accessibilityLabel(store.text("Поиск", "Search"))
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          RitmSymbol("xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RitmTheme.muted)
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.9))
        .accessibilityLabel(store.text("Очистить", "Clear"))
      }
    }
    .padding(.leading, 14)
    .padding(.trailing, 4)
    .frame(minHeight: 48)
    .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
    .padding(16)
  }

  @ViewBuilder private var results: some View {
    let found = hits
    if query.trimmingCharacters(in: .whitespaces).isEmpty {
      note(store.text("Начни вводить название записи", "Start typing an entry title"))
    } else if !loaded {
      ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
      Spacer(minLength: 0)
    } else if found.isEmpty {
      note(store.text("Ничего не найдено", "Nothing found"))
    } else {
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(found) { hit in row(hit) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
    }
  }

  private func note(_ text: String) -> some View {
    VStack {
      Text(text).ritmFont(13).foregroundStyle(RitmTheme.muted).padding(.top, 32)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }

  private func row(_ hit: CalendarSearchHit) -> some View {
    let entry = hit.entry
    let when =
      CalendarText.capitalizedWords(
        FeatureDate.label(hit.date, zone: store.timeZone, language: store.language, template: "EEE d MMM"))
      + " · "
      + (entry.allDay
        ? store.text("Весь день", "All day")
        : entry.start == nil ? store.text("Без времени", "No time") : format.entryRange(entry))
    return Button {
      onPick(hit)
    } label: {
      HStack(spacing: 12) {
        Circle().fill(CalendarPalette.solid(entry.colorId)).frame(width: 12, height: 12)
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.title).ritmFont(14, weight: .semibold).foregroundStyle(RitmTheme.text)
            .multilineTextAlignment(.leading)
          Text(when).ritmFont(12).foregroundStyle(RitmTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(minHeight: 56)
      .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(entry.title + ", " + when)
  }
}
