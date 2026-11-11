import RitmCore
import SwiftUI

/// The side menu of the calendar, copied from the approved prototype A (`.drawer`): the brand
/// block, the five views, the calendars with coloured checkboxes, the undated tasks, the hour
/// format and the settings rows. Sizes are the prototype's: a 300 pt panel, 12 pt side padding,
/// 42 pt view rows with 14 pt corners, 40 pt calendar rows, 12 pt section captions.
struct CalendarDrawer: View {
  let mode: CalendarViewMode
  @Binding var hourFormat: CalendarHourFormat
  let sources: [CalendarSource]
  let hidden: Set<String>
  let undatedCount: Int
  let timeZoneLabel: String
  let googleState: String
  let topPadding: CGFloat
  let bottomPadding: CGFloat
  let onSelect: (CalendarViewMode) -> Void
  let onToggle: (String) -> Void
  let onUndated: () -> Void
  let onTimeZone: () -> Void
  let onGoogle: () -> Void
  @Environment(RitmStore.self) private var store

  static let width: CGFloat = 300

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        brand
        ForEach(CalendarViewMode.allCases, id: \.self) { value in viewRow(value) }
        caption(store.text("Мои календари", "My calendars"))
        calendars
        caption(store.text("Без даты", "No date"))
        iconRow(
          icon: RitmIcon(.checklist).font(.system(size: 20)),
          title: store.text("Твой темп", "Your pace"), value: "\(undatedCount)", height: 42,
          action: onUndated)
        caption(store.text("Формат часов", "Hour format"))
        CalendarHourSegment(selection: $hourFormat).padding(.horizontal, 6)
        caption(store.text("Настройки", "Settings"))
        iconRow(
          icon: RitmIcon(.globe).font(.system(size: 20)),
          title: store.text("Часовой пояс", "Time zone"), value: timeZoneLabel, height: 40,
          action: onTimeZone)
        iconRow(icon: googleTile, title: "Google Calendar", value: googleState, height: 40, action: onGoogle)
      }
      .padding(.horizontal, 12)
      .padding(.top, topPadding)
      .padding(.bottom, bottomPadding)
    }
    .scrollIndicators(.hidden)
    .frame(width: Self.width)
    .frame(maxHeight: .infinity)
    .background(RitmTheme.glassDense, in: Self.shape)
    .overlay { Self.shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
    .shadow(color: RitmTheme.panelShadow, radius: 20, x: 6)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
  }

  /// Right corners 28 pt, as `border-radius: 0 28px 28px 0`.
  private static var shape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
  }

  // MARK: Brand and views

  private var brand: some View {
    HStack(spacing: 10) {
      Text("Р")
        .ritmFont(16, weight: .heavy)
        .foregroundStyle(Color(rgb: 0x34234C))
        .frame(width: 32, height: 32)
        .background(
          RitmTheme.linear(
            [.init(color: Color(rgb: 0xE5D7FF), location: 0), .init(color: Color(rgb: 0xC4ABEB), location: 1)],
            cssAngle: 130),
          in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .accessibilityHidden(true)
      Text(store.text("Календарь", "Calendar"))
        .ritmFont(20, weight: .bold, tracking: -0.04)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
    }
    .padding(.horizontal, 10)
    .padding(.bottom, 8)
  }

  /// `.drawer h3`: 12 pt, 650, muted, 12 pt above and 4 pt below.
  private func caption(_ text: String) -> some View {
    Text(text)
      .ritmFont(12, weight: .semibold, tracking: 0.02)
      .foregroundStyle(RitmTheme.muted)
      .padding(.leading, 10)
      .padding(.top, 12)
      .padding(.bottom, 4)
      .accessibilityAddTraits(.isHeader)
  }

  private func viewRow(_ value: CalendarViewMode) -> some View {
    let selected = value == mode
    return Button {
      onSelect(value)
    } label: {
      HStack(spacing: 14) {
        RitmSymbol(Self.symbol(value))
          .font(.system(size: 20))
          .frame(width: 22)
          .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
        Text(Self.title(value, store))
          .ritmFont(15, weight: .medium)
          .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.text)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .background(
        selected ? RitmTheme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  // MARK: Calendars

  @ViewBuilder private var calendars: some View {
    if sources.isEmpty {
      Text(store.text("Календарей пока нет", "No calendars yet"))
        .ritmFont(13).foregroundStyle(RitmTheme.muted)
        .padding(.horizontal, 14).frame(minHeight: 40, alignment: .leading)
    } else {
      ForEach(sources) { source in calendarRow(source) }
    }
  }

  private func calendarRow(_ source: CalendarSource) -> some View {
    let checked = !hidden.contains(source.id)
    let color = CalendarPalette.solid(source.colorId)
    let origin = source.isRitm ? store.text("Ритм", "Ritm") : "Google"
    return Button {
      onToggle(source.id)
    } label: {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(checked ? color : Color.clear)
          if checked {
            RitmSymbol("checkmark").font(.system(size: 11, weight: .heavy))
              .foregroundStyle(CalendarPalette.ink(source.colorId))
          } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(color, lineWidth: 2)
          }
        }
        .frame(width: 20, height: 20)
        Text(source.name)
          .ritmFont(15, weight: .medium)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 4)
        Text(origin).ritmFont(12).foregroundStyle(RitmTheme.muted)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(source.name + ", " + origin)
    .accessibilityValue(checked ? store.text("Показан", "Shown") : store.text("Скрыт", "Hidden"))
  }

  // MARK: Rows with an icon and a value

  private func iconRow(
    icon: some View, title: String, value: String, height: CGFloat, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        icon.frame(width: 22).foregroundStyle(RitmTheme.muted)
        Text(title).ritmFont(15, weight: .medium).foregroundStyle(RitmTheme.text).lineLimit(1)
        Spacer(minLength: 4)
        Text(value).ritmFont(12).foregroundStyle(RitmTheme.muted).lineLimit(1)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(title + ", " + value)
  }

  /// `.src.g`: a white 22 pt tile with the blue «G».
  private var googleTile: some View {
    Text("G")
      .ritmFont(12, weight: .heavy)
      .foregroundStyle(Color(rgb: 0x4285F4))
      .frame(width: 22, height: 22)
      .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
  }

  static func title(_ value: CalendarViewMode, _ store: RitmStore) -> String {
    switch value {
    case .schedule: store.text("Расписание", "Schedule")
    case .day: store.text("День", "Day")
    case .threeDays: store.text("3 дня", "3 days")
    case .week: store.text("Неделя", "Week")
    case .month: store.text("Месяц", "Month")
    }
  }

  private static func symbol(_ value: CalendarViewMode) -> String {
    switch value {
    case .schedule: "list.bullet"
    case .day: "calendar.day.timeline.left"
    case .threeDays: "rectangle.split.3x1"
    case .week: "calendar"
    case .month: "square.grid.3x3"
    }
  }
}

/// `.seg.full`: the pill with «24 часа» and «12 часов (AM/PM)». The track is the inset glass
/// with a hairline, the chosen option a raised pill with the accent label and a faint accent rim.
struct CalendarHourSegment: View {
  @Binding var selection: CalendarHourFormat
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      ForEach(CalendarHourFormat.allCases, id: \.self) { value in option(value) }
    }
    .padding(3)
    .background(Color(light: 0xEBE2F8, dark: 0x1E162B, lightOpacity: 0.62, darkOpacity: 0.7), in: Capsule())
    .overlay { Capsule().strokeBorder(RitmTheme.line, lineWidth: 1) }
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.2), value: selection)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Формат часов", "Hour format"))
  }

  private func option(_ value: CalendarHourFormat) -> some View {
    let selected = value == selection
    return Button {
      selection = value
    } label: {
      Text(title(value))
        .ritmFont(12.5, weight: .semibold)
        .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background {
          if selected {
            Capsule().fill(RitmTheme.glassRaised)
              .overlay { Capsule().strokeBorder(RitmTheme.accentColor.opacity(0.22), lineWidth: 1) }
              .shadow(color: RitmTheme.panelShadow, radius: 5, y: 2)
          }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func title(_ value: CalendarHourFormat) -> String {
    switch value {
    case .h24: store.text("24 часа", "24 hours")
    case .h12: store.text("12 часов (AM/PM)", "12 hours (AM/PM)")
    }
  }
}
