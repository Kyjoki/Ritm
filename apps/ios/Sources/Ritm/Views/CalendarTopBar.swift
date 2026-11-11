import RitmCore
import SwiftUI

/// The slim bar of the calendar page (prototype A, `.tb`): the menu, the month title that opens
/// the mini-month, search, «Сегодня», the notification bell and the avatar that holds refresh.
/// 48 pt tall; the hour grid takes everything below it.
struct CalendarTopBar: View {
  let title: String
  /// Read here, not by the page: the chevron turns without the page redrawing.
  let chrome: CalendarChrome
  let todayNumber: Int
  let initial: String
  let loading: Bool
  let attention: Bool
  let connected: Bool
  let onMenu: () -> Void
  let onTitle: () -> Void
  let onSearch: () -> Void
  let onToday: () -> Void
  let onRefresh: () -> Void
  let onSettings: () -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let height: CGFloat = 48

  private var miniOpen: Bool { chrome.miniOpen }

  var body: some View {
    HStack(spacing: 0) {
      iconButton("line.3.horizontal", store.text("Меню календаря", "Calendar menu"), action: onMenu)
      titleButton
      Spacer(minLength: 4)
      iconButton("magnifyingglass", store.text("Поиск", "Search"), action: onSearch)
      todayButton
      FinanceBellButton(plain: true)
      avatarMenu
    }
    .frame(height: Self.height)
  }

  private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      RitmSymbol(symbol)
        .font(.system(size: 21))
        .foregroundStyle(RitmTheme.text)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.9))
    .accessibilityLabel(label)
  }

  /// «Ноябрь ▾»: a tap opens the mini-month under it.
  private var titleButton: some View {
    Button(action: onTitle) {
      HStack(spacing: 4) {
        Text(title)
          .ritmFont(21, weight: .bold, tracking: -0.045)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        RitmSymbol("chevron.down")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
          .rotationEffect(.degrees(miniOpen ? 180 : 0))
          .animation(reduceMotion ? nil : RitmMotion.ease(0.3), value: miniOpen)
      }
      .padding(.horizontal, 8)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.96))
    .accessibilityLabel(store.text("Выбор даты", "Choose a date"))
    .accessibilityValue(title)
    .accessibilityAddTraits(.isHeader)
  }

  /// The calendar glyph with today's number in it.
  private var todayButton: some View {
    Button(action: onToday) {
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(RitmTheme.text, lineWidth: 1.6)
          .frame(width: 22, height: 22)
        Text("\(todayNumber)")
          .ritmFont(11, weight: .bold)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.text)
      }
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.9))
    .accessibilityLabel(store.text("Сегодня", "Today"))
  }

  /// The avatar: the account's initial; its menu refreshes Google or opens its settings. A dot on
  /// it says the data may be out of date.
  private var avatarMenu: some View {
    Menu {
      Button(action: onRefresh) {
        Label(store.text("Обновить", "Refresh"), systemImage: "arrow.clockwise")
      }
      .disabled(loading || !connected)
      Button(action: onSettings) {
        Label(store.text("Настройки Google", "Google settings"), systemImage: "gearshape")
      }
    } label: {
      ZStack {
        Circle().fill(RitmTheme.ctaGradient)
        if loading {
          ProgressView().controlSize(.small).tint(RitmTheme.ctaInk)
        } else {
          Text(initial).ritmFont(14, weight: .bold).foregroundStyle(RitmTheme.ctaInk)
        }
      }
      .frame(width: 32, height: 32)
      .overlay(alignment: .topTrailing) {
        if attention {
          Circle().fill(RitmTheme.danger).frame(width: 10, height: 10)
            .overlay { Circle().strokeBorder(RitmTheme.background, lineWidth: 2) }
            .offset(x: 2, y: -2)
        }
      }
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
    }
    .accessibilityLabel(
      attention
        ? store.text("Google Calendar требует внимания", "Google Calendar needs attention")
        : store.text("Профиль и обновление", "Profile and refresh"))
  }
}

/// The mini-month under the title: a month of days to jump to, with its own previous and next.
struct CalendarMiniMonth: View {
  let selected: String
  let today: String
  let onPick: (String) -> Void
  @Environment(RitmStore.self) private var store
  @State private var month: String

  init(selected: String, today: String, onPick: @escaping (String) -> Void) {
    self.selected = selected
    self.today = today
    self.onPick = onPick
    _month = State(initialValue: TaskSchedule.startOfMonth(selected) ?? selected)
  }

  private var weekdays: [String] {
    store.language == .ru
      ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  }

  var body: some View {
    VStack(spacing: 4) {
      header
      HStack(spacing: 0) {
        ForEach(weekdays, id: \.self) { day in
          Text(day).ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.muted)
            .frame(maxWidth: .infinity)
        }
      }
      .accessibilityHidden(true)
      let days = CalendarPlan.monthDays(containing: month)
      if days.count == 42 {
        ForEach(0..<6, id: \.self) { row in
          HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in cell(days[row * 7 + column]) }
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: 340)
    .background(RitmTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
    }
    .shadow(color: RitmTheme.panelShadow, radius: 24, y: 10)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
  }

  private var header: some View {
    HStack(spacing: 0) {
      arrow("chevron.left", store.text("Предыдущий месяц", "Previous month"), -1)
      Text(
        CalendarText.capitalizedWords(
          FeatureDate.label(month, zone: store.timeZone, language: store.language, template: "LLLL yyyy"))
      )
      .ritmFont(15, weight: .semibold)
      .foregroundStyle(RitmTheme.text)
      .frame(maxWidth: .infinity)
      .accessibilityAddTraits(.isHeader)
      arrow("chevron.right", store.text("Следующий месяц", "Next month"), 1)
    }
  }

  private func arrow(_ symbol: String, _ label: String, _ amount: Int) -> some View {
    Button {
      month = TaskSchedule.addMonths(to: month, months: amount) ?? month
    } label: {
      RitmSymbol(symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(RitmTheme.muted)
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.9))
    .accessibilityLabel(label)
  }

  private func cell(_ day: String) -> some View {
    let isToday = day == today
    let inMonth = day.prefix(7) == month.prefix(7)
    return Button {
      onPick(day)
    } label: {
      Text("\(Int(day.suffix(2)) ?? 0)")
        .ritmFont(15, weight: isToday ? .bold : .regular)
        .monospacedDigit()
        .foregroundStyle(isToday ? RitmTheme.accentInk : inMonth ? RitmTheme.text : RitmTheme.muted.opacity(0.6))
        .frame(width: 36, height: 36)
        .background {
          if isToday {
            Circle().fill(RitmTheme.accentColor)
          } else if day == selected {
            Circle().strokeBorder(RitmTheme.accentColor, lineWidth: 1.5)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .accessibilityLabel(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "d MMMM")
        + (isToday ? store.text(", сегодня", ", today") : ""))
  }
}
