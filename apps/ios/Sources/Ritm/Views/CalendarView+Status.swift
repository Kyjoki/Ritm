import RitmCore
import SwiftUI

// The Google sync state of the calendar page: the title for the menu and the banner that appears
// only when something needs attention.

extension CalendarView {
  var connected: Bool { status?.status == .connected }
  var needsReauth: Bool { status?.status == .reauthRequired }
  var uncertain: Bool {
    (loading && fetchedAt == nil) || failed || partial || needsReauth || (connected && fetchedAt == nil)
  }
  var warning: Bool { failed || partial || needsReauth }

  var statusTitle: String {
    if loading && fetchedAt == nil { return store.text("Загружаем Google Calendar…", "Loading Google Calendar…") }
    if failed { return store.text("Google Calendar требует внимания", "Google Calendar needs attention") }
    if needsReauth { return store.text("Подключи Google Calendar заново", "Reconnect Google Calendar") }
    if partial { return store.text("Загружена часть событий Google", "Some Google events loaded") }
    if connected { return store.text("Календарь синхронизирован", "Calendar synced") }
    return store.text("Google Calendar пока не подключён", "Google Calendar is not connected yet")
  }

  var statusMessage: String {
    if failed {
      return store.text(
        "Не удалось обновить события. Показанные события могут быть неактуальны.",
        "Could not refresh events. The events shown may be out of date.")
    }
    if partial {
      return store.text(
        "Часть событий не загружена. Свободное время нужно уточнить в Google Calendar.",
        "Some events did not load. Check free time in Google Calendar.")
    }
    return store.text(
      "Разрешение нужно обновить в настройках.", "The permission needs to be renewed in Settings.")
  }

  var fetchedLabel: String? {
    guard let fetchedAt, let instant = FeatureDate.instant(fetchedAt) else { return nil }
    let key = HabitSchedule.dateKey(instant, timeZone: store.timeZone)
    let time = FeatureDate.time(instant, zone: store.timeZone)
    return FeatureDate.label(key, zone: store.timeZone, language: store.language, template: "d MMM")
      + " · " + FeatureDate.clock(time)
  }

  /// `.cal-sync-footer` with a warning: what is wrong and the refresh or settings action.
  var warningStatus: some View {
    HStack(alignment: .top, spacing: 5) {
      RitmSymbol("exclamationmark.circle")
        .font(.system(size: 15))
        .foregroundStyle(RitmTheme.accentColor)
        .padding(.top, 2)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(statusTitle).ritmFont(13, weight: .semibold).foregroundStyle(RitmTheme.text)
        Text(statusMessage).ritmFont(11, lineSpacing: 6).foregroundStyle(RitmTheme.muted)
        if let fetched = fetchedLabel {
          Text(store.text("Последнее обновление: ", "Last updated: ") + fetched)
            .ritmFont(10)
            .foregroundStyle(RitmTheme.muted)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if connected || failed {
        Button {
          Task { await refreshGoogle() }
        } label: {
          Label { Text(store.text("Обновить", "Refresh")) } icon: { RitmIcon(.refreshCalendar) }
        }
        .buttonStyle(CalendarSecondaryStyle())
        .disabled(loading)
      } else {
        Button {
          navigation.section = .settings
        } label: {
          HStack(spacing: 4) {
            Text(store.text("Настройки", "Settings"))
            RitmIcon(.rightIcon).font(.system(size: 12, weight: .semibold))
          }
        }
        .buttonStyle(RitmTextButtonStyle())
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .frame(minHeight: 38)
    .background(
      RitmTheme.mix(RitmTheme.soft, 0.6, into: RitmTheme.panel),
      in: RoundedRectangle(cornerRadius: 10, style: .circular)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .circular)
        .strokeBorder(RitmTheme.mix(RitmTheme.accentColor, 0.4, into: RitmTheme.line), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }
}

/// The calendar's secondary buttons: Liquid Glass, accent label, 44 pt tall.
struct CalendarSecondaryStyle: ButtonStyle {
  var square = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmFont(14, weight: .semibold)
      .lineLimit(1)
      .foregroundStyle(RitmTheme.accentColor)
      .padding(.horizontal, square ? 0 : 12)
      .frame(minWidth: 44, minHeight: 44)
      .frame(width: square ? 44 : nil)
      .ritmGlass(in: Capsule(), interactive: true)
      .opacity(isEnabled ? 1 : 0.6)
      .environment(\.ritmGlassPressed, configuration.isPressed)
  }
}
