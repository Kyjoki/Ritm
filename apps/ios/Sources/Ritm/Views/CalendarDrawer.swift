import RitmCore
import SwiftUI

/// The side menu of the calendar (prototype A, `.drawer`): the five views, the undated tasks,
/// the 24/12-hour switch and the Google status. It slides in from the left over a dimmed page.
struct CalendarDrawer: View {
  let mode: CalendarViewMode
  @Binding var hourFormat: CalendarHourFormat
  let undatedCount: Int
  let statusTitle: String
  let connected: Bool
  let loading: Bool
  let onSelect: (CalendarViewMode) -> Void
  let onUndated: () -> Void
  let onRefresh: () -> Void
  let onSettings: () -> Void
  let onClose: () -> Void
  @Environment(RitmStore.self) private var store

  private static let width: CGFloat = 300

  var body: some View {
    ZStack(alignment: .leading) {
      Button(action: onClose) {
        RitmTheme.scrim.ignoresSafeArea().contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(store.text("Закрыть меню", "Close the menu"))
      .transition(.opacity)
      panel.transition(.move(edge: .leading))
    }
  }

  private var panel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(store.text("Календарь", "Calendar"))
          .ritmFont(20, weight: .bold, tracking: -0.04)
          .foregroundStyle(RitmTheme.text)
          .padding(.horizontal, 10)
          .padding(.bottom, 8)
          .accessibilityAddTraits(.isHeader)
        ForEach(CalendarViewMode.allCases, id: \.self) { value in viewRow(value) }
        heading(store.text("Без даты", "No date"))
        undatedRow
        heading(store.text("Формат часов", "Hour format"))
        RitmSegmentedControl(
          label: store.text("Формат часов", "Hour format"), values: CalendarHourFormat.allCases,
          title: { $0 == .h24 ? store.text("24 ч", "24 h") : store.text("12 ч", "12 h") },
          selection: $hourFormat, fontSize: 14
        )
        .padding(.horizontal, 6)
        heading("Google Calendar")
        googleRow
      }
      .padding(.horizontal, 12)
      .padding(.top, 16)
      .padding(.bottom, 24)
    }
    .scrollIndicators(.hidden)
    .frame(width: Self.width)
    .frame(maxHeight: .infinity)
    .background(
      RitmTheme.panel,
      in: UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
    )
    .overlay {
      UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
        .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
    }
    .shadow(color: RitmTheme.panelShadow, radius: 24, x: 8)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
  }

  private func heading(_ text: String) -> some View {
    Text(text)
      .ritmFont(12, weight: .semibold)
      .foregroundStyle(RitmTheme.muted)
      .padding(.horizontal, 10)
      .padding(.top, 18)
      .padding(.bottom, 6)
      .accessibilityAddTraits(.isHeader)
  }

  private func viewRow(_ value: CalendarViewMode) -> some View {
    let selected = value == mode
    return Button {
      onSelect(value)
    } label: {
      HStack(spacing: 14) {
        RitmSymbol(Self.symbol(value))
          .font(.system(size: 19))
          .frame(width: 24)
          .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
        Text(Self.title(value, store))
          .ritmFont(15, weight: .medium)
          .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.text)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      .background(
        selected ? RitmTheme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var undatedRow: some View {
    Button(action: onUndated) {
      HStack(spacing: 14) {
        RitmIcon(.checklist).font(.system(size: 19)).frame(width: 24).foregroundStyle(RitmTheme.muted)
        Text(store.text("Твой темп", "Your pace"))
          .ritmFont(15, weight: .medium)
          .foregroundStyle(RitmTheme.text)
        Spacer(minLength: 0)
        Text("\(undatedCount)").ritmFont(13).foregroundStyle(RitmTheme.muted).monospacedDigit()
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(
      store.text("Твой темп, без даты: \(undatedCount)", "Your pace, no date: \(undatedCount)"))
  }

  private var googleRow: some View {
    HStack(spacing: 10) {
      Group {
        if loading {
          ProgressView().controlSize(.small).tint(RitmTheme.accentColor)
        } else {
          RitmIcon(.calCalendar).font(.system(size: 19)).foregroundStyle(RitmTheme.accentColor)
        }
      }
      .frame(width: 24)
      Text(statusTitle).ritmFont(13).foregroundStyle(RitmTheme.text).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      if connected {
        Button(action: onRefresh) {
          RitmIcon(.refreshCalendar).font(.system(size: 18)).foregroundStyle(RitmTheme.accentColor)
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.9))
        .disabled(loading)
        .accessibilityLabel(store.text("Обновить", "Refresh"))
      } else {
        Button(action: onSettings) {
          Text(store.text("Настройки", "Settings")).ritmFont(13, weight: .semibold)
            .foregroundStyle(RitmTheme.accentColor)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.96))
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 46)
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
