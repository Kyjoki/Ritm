import RitmCore
import SwiftUI

/// The softened «Верх 1» tokens (`--t1-*`): a deep violet-indigo card with lavender glass inside.
@MainActor
enum HabitTop {
  /// `--t1-w`: the lavender every inner layer is a share of.
  static func lavender(_ opacity: Double) -> Color {
    Color(light: 0x6042A8, dark: 0xBEA8EE, lightOpacity: opacity, darkOpacity: opacity)
  }
  static let ink = Color(light: 0x2A2045, dark: 0xE8E1F5)
  static let inkSoft = Color(
    light: 0x2A2045, dark: 0xE8E1F5, lightOpacity: 0.68, darkOpacity: 0.68)
  /// `--t1-arc`.
  static let arc = Color(light: 0x6848B2, dark: 0xBEA8EE, lightOpacity: 0.8, darkOpacity: 0.78)
  static let stroke = Color(light: 0x6848B2, dark: 0xBEA8EE, lightOpacity: 0.18, darkOpacity: 0.17)
  static let glass = Color(light: 0xFFFFFF, dark: 0x0A061A, lightOpacity: 0.52, darkOpacity: 0.3)
  static let glassBorder = Color(
    light: 0x6848B2, dark: 0xBEA8EE, lightOpacity: 0.15, darkOpacity: 0.13)
  static let track = Color(light: 0x6042A8, dark: 0xBEA8EE, lightOpacity: 0.17, darkOpacity: 0.17)
  static let segment = Color(light: 0x6848B2, dark: 0x0A061A, lightOpacity: 0.09, darkOpacity: 0.32)
  /// `--t1-onfill`: the number on the strongest month cell.
  static let onFill = Color(light: 0xFFFFFF, dark: 0x1D1535)
  static let shadow = Color(light: 0x4A2B82, dark: 0x080418, lightOpacity: 0.42, darkOpacity: 0.75)

  /// `--t1-bg`, 145°.
  static var background: LinearGradient {
    RitmTheme.linear(
      [
        .init(color: Color(light: 0xE9E2F6, dark: 0x2A2050), location: 0),
        .init(color: Color(light: 0xDFD9F3, dark: 0x342F68), location: 0.58),
        .init(color: Color(light: 0xD5D6F1, dark: 0x3D3B72), location: 1),
      ], cssAngle: 145)
  }

  /// `--t1-sheen`: a soft light in the top-right corner.
  static var sheen: RadialGradient {
    RadialGradient(
      colors: [
        Color(light: 0xFFFFFF, dark: 0xBEA8F0, lightOpacity: 0.5, darkOpacity: 0.1), .clear,
      ], center: .topTrailing, startRadius: 0, endRadius: 190)
  }
}

/// «Верх 1»: the analytics card at the top of the habits page. Week / month switch, the period
/// arrows, the ring with the period's share, three chips, the count with the trend and the day
/// strip (week) or the mini month (month). Tapping a day chooses it for the list below.
struct HabitsTopCard: View {
  let overview: HabitOverview
  let month: Bool
  let offset: Int
  let selectedDay: String
  let today: String
  let canGoBack: Bool
  let onMonth: (Bool) -> Void
  let onStep: (Int) -> Void
  let onSelect: (String) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var direction: CGFloat = 0

  private var periodKey: String { "\(month)-\(offset)" }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HabitSoftSegment(
        label: store.text("Период аналитики", "Analytics period"),
        titles: (store.text("Неделя", "Week"), store.text("Месяц", "Month")),
        isSecond: month,
        onChange: { value in
          direction = 0
          onMonth(value)
        })
      nav
      VStack(alignment: .leading, spacing: 12) {
        main
        caption
        if month { monthGrid } else { weekStrip }
      }
      .habitSwap(key: periodKey, direction: direction)
    }
    .padding(.top, 14)
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(HabitTop.ink)
    .background { cardBackground }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Статистика привычек", "Habit statistics"))
  }

  private var cardBackground: some View {
    let shape = RoundedRectangle(cornerRadius: 30, style: .circular)
    return ZStack {
      shape.fill(HabitTop.background)
        .shadow(color: HabitTop.shadow, radius: 15, y: 16)
      shape.fill(HabitTop.sheen)
      shape.strokeBorder(HabitTop.stroke, lineWidth: 1)
    }
  }

  // MARK: Period

  private var nav: some View {
    HStack(spacing: 4) {
      HabitArrowButton(
        symbol: "chevron.left",
        label: month
          ? store.text("Предыдущий месяц", "Previous month")
          : store.text("Предыдущая неделя", "Previous week"),
        ink: HabitTop.inkSoft, fill: HabitTop.lavender(0.1), rim: HabitTop.lavender(0.26)
      ) {
        direction = -1
        onStep(-1)
      }
      .disabled(!canGoBack)
      Text(periodLabel)
        .ritmFont(14.5, weight: .semibold, tracking: -0.02)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(.isHeader)
      HabitArrowButton(
        symbol: "chevron.right",
        label: month
          ? store.text("Следующий месяц", "Next month") : store.text("Следующая неделя", "Next week"),
        ink: HabitTop.inkSoft, fill: HabitTop.lavender(0.1), rim: HabitTop.lavender(0.26)
      ) {
        direction = 1
        onStep(1)
      }
      .disabled(offset >= 0)
    }
  }

  private var periodLabel: String {
    HabitDates.periodLabel(
      overview.dates, month: month, zone: store.timeZone, language: store.language)
  }

  private func label(_ day: String, _ template: String) -> String {
    HabitDates.label(day, zone: store.timeZone, language: store.language, template: template)
  }

  // MARK: Ring and chips

  private var main: some View {
    HStack(spacing: 14) {
      ring
      VStack(spacing: 6) {
        chip(
          "flame", store.text("Серия", "Streak"),
          value: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
              HStack(spacing: 0) {
                RitmCountText(overview.streak) { "\($0)" }
                Text(" " + store.text("дн.", "d"))
              }
              HStack(spacing: 0) {
                Text(store.text("рекорд ", "best "))
                RitmCountText(overview.record) { "\($0)" }
              }
              .ritmFont(12, weight: .semibold)
              .opacity(0.8)
            }
          })
        chip(
          "arrow.up", store.text("Лучшая привычка", "Best habit"),
          value: { rateValue(overview.best) })
        chip(
          "arrow.down", store.text("Слабая привычка", "Weakest habit"),
          value: { rateValue(overview.worst) })
      }
    }
  }

  private var ring: some View {
    let percent = overview.percent
    return HabitProgressRing(
      fraction: Double(percent ?? 0) / 100, size: 128, lineWidth: 12, track: HabitTop.track,
      arc: HabitTop.arc, glow: HabitTop.lavender(0.2), key: "top"
    ) {
      VStack(spacing: 6) {
        if let percent {
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            RitmCountText(percent) { "\($0)" }
              .ritmFont(34, weight: .semibold, tracking: -0.06)
            Text("%").ritmFont(16, weight: .semibold).opacity(0.72)
          }
        } else {
          Text("—").ritmFont(34, weight: .semibold)
        }
        Text(month ? store.text("за месяц", "this month") : store.text("за неделю", "this week"))
          .ritmFont(11)
          .foregroundStyle(HabitTop.inkSoft)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      percent.map {
        store.text("Выполнено \($0) процентов", "\($0) percent done")
      } ?? store.text("Нет запланированных привычек", "No habits scheduled"))
  }

  @ViewBuilder private func rateValue(_ rate: HabitRate?) -> some View {
    if let rate {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(rate.title).lineLimit(1).truncationMode(.tail).layoutPriority(0)
        HStack(spacing: 0) {
          RitmCountText(rate.percent) { "\($0)" }
          Text("%")
        }
        .ritmFont(12, weight: .semibold)
        .opacity(0.8)
        .layoutPriority(1)
      }
    } else {
      Text("—")
    }
  }

  private func chip<Value: View>(
    _ symbol: String, _ title: String, @ViewBuilder value: () -> Value
  ) -> some View {
    HStack(spacing: 9) {
      RitmSymbol(symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(HabitTop.arc)
        .frame(width: 26, height: 26)
        .background(HabitTop.lavender(0.16), in: RoundedRectangle(cornerRadius: 9, style: .circular))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        Text(title).ritmFont(10.5).foregroundStyle(HabitTop.inkSoft).lineLimit(1)
        value()
          .ritmFont(13.5, weight: .semibold, tracking: -0.025)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
    .padding(.leading, 7)
    .padding(.trailing, 10)
    .background(HabitTop.glass, in: RoundedRectangle(cornerRadius: 16, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .circular)
        .strokeBorder(HabitTop.glassBorder, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: Caption

  private var caption: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      HStack(spacing: 4) {
        RitmCountText(overview.completed) { "\($0)" }
          .ritmFont(12, weight: .semibold).foregroundStyle(HabitTop.ink)
        Text(store.text("из", "of"))
        RitmCountText(overview.planned) { "\($0)" }
          .ritmFont(12, weight: .semibold).foregroundStyle(HabitTop.ink)
        Text(store.text("отметок", "marks"))
      }
      Spacer(minLength: 0)
      if let trend = overview.trend {
        HStack(spacing: 4) {
          RitmSymbol(trend >= 0 ? "arrow.up.right" : "arrow.down")
            .font(.system(size: 13, weight: .semibold))
          HStack(spacing: 0) {
            Text(trend >= 0 ? "+" : "−")
            RitmCountText(abs(trend)) { "\($0)" }
            Text("% " + (month
              ? store.text("к прошлому месяцу", "vs last month")
              : store.text("к прошлой неделе", "vs last week")))
          }
        }
        .foregroundStyle(HabitTop.ink)
        .accessibilityElement(children: .combine)
      }
    }
    .ritmFont(12)
    .foregroundStyle(HabitTop.inkSoft)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
  }

  // MARK: Week strip

  private var weekStrip: some View {
    HStack(spacing: 5) {
      ForEach(Array(overview.dates.enumerated()), id: \.element) { index, day in
        weekDay(day, summary: overview.days[index])
      }
    }
  }

  private func weekDay(_ day: String, summary: HabitDaySummary) -> some View {
    let future = day > today
    let selected = day == selectedDay
    let weekday = HabitSchedule.weekday(day) ?? 0
    let share = summary.planned > 0 ? Double(summary.completed) / Double(summary.planned) : 0
    let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
    return Button {
      direction = 0
      onSelect(day)
    } label: {
      VStack(spacing: 3) {
        Text(HabitWeekdays.short(weekday, language: store.language))
          .ritmFont(10.5, weight: day == today ? .bold : .semibold)
          .opacity(day == today ? 1 : 0.72)
        Text("\(Int(day.suffix(2)) ?? 0)")
          .ritmFont(15, weight: .semibold, tracking: -0.03)
          .monospacedDigit()
          .underline(day == today, color: HabitTop.arc)
        miniRing(share, visible: !future && summary.planned > 0)
      }
      .foregroundStyle(HabitTop.ink)
      .padding(.top, 7)
      .padding(.bottom, 6)
      .frame(maxWidth: .infinity)
      .background(HabitTop.lavender(selected ? 0.2 : 0.07), in: shape)
      .overlay { shape.strokeBorder(HabitTop.lavender(selected ? 0.55 : 0.16), lineWidth: 1) }
      .opacity(future ? 0.42 : 1)
      .contentShape(shape)
    }
    .buttonStyle(RitmPressStyle(scale: 0.94))
    .disabled(future)
    .accessibilityLabel(dayDescription(day, summary: summary))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func miniRing(_ share: Double, visible: Bool) -> some View {
    ZStack {
      Circle().stroke(HabitTop.ink.opacity(0.2), lineWidth: 3)
      if visible && share > 0 {
        Circle()
          .trim(from: 0, to: share)
          .stroke(HabitTop.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(reduceMotion ? nil : RitmMotion.easeOut(RitmMotion.countChange), value: share)
      }
    }
    .padding(1.5)
    .frame(width: 20, height: 20)
    .accessibilityHidden(true)
  }

  private func dayDescription(_ day: String, summary: HabitDaySummary) -> String {
    let name = label(day, "EEEE, d MMMM").habitCapitalized + (day == today ? store.text(", сегодня", ", today") : "")
    if day > today { return name + ". " + store.text("Ещё не наступил", "Not yet") }
    return name + ": " + store.text("\(summary.completed) из \(summary.planned)", "\(summary.completed) of \(summary.planned)")
  }

  // MARK: Month

  private var monthGrid: some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    let lead = overview.dates.first.flatMap(HabitSchedule.weekday) ?? 0
    return VStack(alignment: .leading, spacing: 8) {
      LazyVGrid(columns: columns, spacing: 4) {
        ForEach(0..<7, id: \.self) { weekday in
          Text(HabitWeekdays.short(weekday, language: store.language))
            .ritmFont(10, weight: .semibold)
            .foregroundStyle(HabitTop.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 27) }
        ForEach(Array(overview.dates.enumerated()), id: \.element) { index, day in
          monthCell(day, summary: overview.days[index])
        }
      }
      legend
    }
  }

  private static let levelOpacity: [Double] = [0.07, 0.15, 0.27, 0.46, 0.72]

  private func monthCell(_ day: String, summary: HabitDaySummary) -> some View {
    let future = day > today
    let idle = !future && summary.planned == 0
    let level = HabitAnalytics.intensity(summary)
    let selected = day == selectedDay
    let shape = RoundedRectangle(cornerRadius: 9, style: .circular)
    return Button {
      direction = 0
      onSelect(day)
    } label: {
      Text("\(Int(day.suffix(2)) ?? 0)")
        .ritmFont(11.5, weight: .semibold)
        .monospacedDigit()
        .underline(day == today, color: HabitTop.arc)
        .foregroundStyle(level == 4 && !future && !idle ? HabitTop.onFill : HabitTop.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 27)
        .background {
          if future {
            Color.clear
          } else if idle {
            shape.strokeBorder(HabitTop.lavender(0.2), lineWidth: 1)
          } else {
            shape.fill(HabitTop.lavender(Self.levelOpacity[level]))
          }
        }
        .opacity(future ? 0.45 : idle ? 0.6 : 1)
        .overlay {
          if selected { shape.inset(by: -2).stroke(HabitTop.arc, lineWidth: 2) }
        }
        .contentShape(shape)
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .disabled(future)
    .accessibilityLabel(dayDescription(day, summary: summary))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var legend: some View {
    HStack(spacing: 3) {
      Spacer(minLength: 0)
      Text(store.text("меньше", "less")).padding(.trailing, 3)
      ForEach(0..<5, id: \.self) { level in
        RoundedRectangle(cornerRadius: 3, style: .circular)
          .fill(HabitTop.lavender(Self.levelOpacity[level]))
          .frame(width: 11, height: 11)
      }
      Text(store.text("больше", "more")).padding(.leading, 3)
    }
    .ritmFont(10)
    .foregroundStyle(HabitTop.inkSoft)
    .accessibilityHidden(true)
  }
}

/// `.t1 .seg`: a two-option switch with a soft lavender thumb instead of the violet one.
struct HabitSoftSegment: View {
  let label: String
  let titles: (String, String)
  let isSecond: Bool
  let onChange: (Bool) -> Void
  @Namespace private var thumb
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      option(titles.0, selected: !isSecond, value: false)
      option(titles.1, selected: isSecond, value: true)
    }
    .padding(3)
    .background(HabitTop.segment, in: Capsule())
    .overlay { Capsule().strokeBorder(HabitTop.stroke, lineWidth: 1) }
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.2), value: isSecond)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  private func option(_ title: String, selected: Bool, value: Bool) -> some View {
    Button {
      guard !selected else { return }
      onChange(value)
    } label: {
      Text(title)
        .ritmFont(12.5, weight: .semibold, tracking: -0.01)
        .foregroundStyle(selected ? HabitTop.ink : HabitTop.inkSoft)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background {
          if selected {
            Capsule()
              .fill(HabitTop.lavender(0.2))
              .overlay { Capsule().strokeBorder(HabitTop.lavender(0.38), lineWidth: 1) }
              .matchedGeometryEffect(id: "thumb", in: thumb)
          }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
