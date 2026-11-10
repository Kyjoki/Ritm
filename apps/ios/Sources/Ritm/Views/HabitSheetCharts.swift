import RitmCore
import SwiftUI

// The three ways the habit sheet shows a habit's days: the week (`.wk7`), the month calendar
// (`.cal`) and the 20-week heat map (`.mh`), with their legend and the one-line readout of the
// chosen day. All of them take the habit and compute each day's state once per render.

/// `.pnl.hs-card`: a calm panel inside the sheet.
struct HabitSheetCard<Content: View>: View {
  let title: String
  var caption: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .ritmFont(14.5, weight: .semibold, tracking: -0.03)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 8)
        if let caption {
          Text(caption).ritmFont(11.5).foregroundStyle(RitmTheme.muted)
        }
      }
      content
    }
    .padding(.top, 14)
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RitmTheme.panel, in: RoundedRectangle(cornerRadius: 22, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .circular)
        .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
    }
  }
}

/// `.wk7`: the seven days of the week with their amounts.
struct HabitSheetWeek: View {
  let habit: Habit
  let dates: [String]
  let selected: String
  let today: String
  let tint: HabitTint
  let onSelect: (String) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      ForEach(dates, id: \.self) { cell($0) }
    }
    .accessibilityElement(children: .contain)
  }

  private func cell(_ date: String) -> some View {
    let state = HabitAnalytics.dayState(habit, on: date, today: today)
    let counted = habit.target != nil
    let amount =
      counted && [.done, .part, .miss].contains(state)
      ? habitNumber(HabitSchedule.progress(habit, on: date)) : ""
    let weekday = HabitSchedule.weekday(date) ?? 0
    return Button {
      onSelect(date)
    } label: {
      VStack(spacing: 3) {
        Text(HabitWeekdays.short(weekday, language: store.language))
          .ritmFont(10.5, weight: .semibold)
          .foregroundStyle(date == today ? RitmTheme.accentColor : RitmTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text("\(Int(date.suffix(2)) ?? 0)")
          .ritmFont(12.5, weight: .semibold)
          .monospacedDigit()
          .foregroundStyle(date == today ? RitmTheme.accentColor : RitmTheme.text)
        HabitDayTile(
          content: .mark, state: state, fraction: HabitAnalytics.fraction(habit, on: date),
          tint: tint, isToday: false, isSelected: date == selected, radius: 13
        )
        .frame(height: 46)
        Text(amount)
          .ritmFont(10.5)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(minHeight: 13)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .disabled(state == .future)
    .accessibilityLabel(HabitSheetText.dayLabel(habit, date, state: state, store: store))
    .accessibilityAddTraits(date == selected ? .isSelected : [])
  }
}

/// `.cal`: the month as a calendar, Sunday first.
struct HabitSheetMonth: View {
  let habit: Habit
  let dates: [String]
  let selected: String
  let today: String
  let tint: HabitTint
  let onSelect: (String) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    let lead = dates.first.flatMap(HabitSchedule.weekday) ?? 0
    LazyVGrid(columns: columns, spacing: 4) {
      ForEach(0..<7, id: \.self) { weekday in
        Text(HabitWeekdays.short(weekday, language: store.language))
          .ritmFont(10.5, weight: .semibold)
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 36) }
      ForEach(dates, id: \.self) { date in
        let state = HabitAnalytics.dayState(habit, on: date, today: today)
        Button {
          onSelect(date)
        } label: {
          HabitDayTile(
            content: .number(Int(date.suffix(2)) ?? 0), state: state,
            fraction: HabitAnalytics.fraction(habit, on: date), tint: tint,
            isToday: date == today, isSelected: date == selected, radius: 11
          )
          .frame(height: 36)
        }
        .buttonStyle(RitmPressStyle())
        .disabled(state == .future)
        .accessibilityLabel(HabitSheetText.dayLabel(habit, date, state: state, store: store))
        .accessibilityAddTraits(date == selected ? .isSelected : [])
      }
    }
  }
}

/// `.mh`: the last 20 weeks, a column per week from Sunday to Saturday, the newest on the right.
struct HabitSheetHeat: View {
  let habit: Habit
  let selected: String
  let today: String
  let tint: HabitTint
  let onSelect: (String) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    let first =
      HabitSchedule.addDays(to: HabitSchedule.week(containing: today).first ?? today, days: -19 * 7)
      ?? today
    let weeks = (0..<20).compactMap { HabitSchedule.addDays(to: first, days: $0 * 7) }
    VStack(spacing: 6) {
      HStack(alignment: .top, spacing: 3) {
        ForEach(weeks, id: \.self) { start in
          VStack(spacing: 3) {
            ForEach(HabitSchedule.week(containing: start), id: \.self) { cell($0) }
          }
        }
      }
      HStack {
        Text(HabitDates.label(first, zone: store.timeZone, language: store.language, template: "d MMM"))
        Spacer()
        Text(store.text("сегодня", "today"))
      }
      .ritmFont(10.5)
      .foregroundStyle(RitmTheme.muted)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(store.text("Последние 20 недель", "The last 20 weeks"))
  }

  private func cell(_ date: String) -> some View {
    let state = HabitAnalytics.dayState(habit, on: date, today: today)
    let shape = RoundedRectangle(cornerRadius: 4, style: .circular)
    let color: Color
    switch state {
    case .done: color = tint.base
    case .part:
      color = tint.base.opacity(0.22 + HabitAnalytics.fraction(habit, on: date) * 0.5)
    case .miss: color = RitmTheme.muted.opacity(0.24)
    case .off, .future: color = RitmTheme.line.opacity(0.2)
    }
    return shape.fill(color)
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        if date == selected { shape.inset(by: -1).stroke(RitmTheme.accentColor, lineWidth: 2) }
      }
      .contentShape(Rectangle())
      .onTapGesture { if state != .future { onSelect(date) } }
  }
}

/// `.hs-leg`: what the cell colours mean.
struct HabitSheetLegend: View {
  let counted: Bool
  let tint: HabitTint
  @Environment(RitmStore.self) private var store

  var body: some View {
    HStack(spacing: 10) {
      item(RitmTheme.line.opacity(0.4), store.text("нет", "none"))
      if counted {
        item(tint.base.opacity(0.47), store.text("часть цели", "part of the goal"))
        item(tint.base, store.text("цель выполнена", "goal met"))
      } else {
        item(tint.base, store.text("выполнено", "done"))
      }
      Spacer(minLength: 0)
    }
    .ritmFont(10.5)
    .foregroundStyle(RitmTheme.muted)
    .accessibilityHidden(true)
  }

  private func item(_ color: Color, _ title: String) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 3, style: .circular).fill(color).frame(width: 11, height: 11)
      Text(title)
    }
  }
}

/// `.hs-cap`: «Пятница, 6 нояб.» and what happened that day.
struct HabitSheetReadout: View {
  let habit: Habit
  let day: String
  let today: String
  let tint: HabitTint
  @Environment(RitmStore.self) private var store

  var body: some View {
    let state = HabitAnalytics.dayState(habit, on: day, today: today)
    HStack(spacing: 10) {
      Text(
        HabitDates.label(
          day, zone: store.timeZone, language: store.language, template: "EEEE, d MMM"
        ).habitCapitalized
      )
      .ritmFont(13, weight: .semibold, tracking: -0.02)
      .foregroundStyle(RitmTheme.text)
      .lineLimit(1)
      Spacer(minLength: 0)
      value(state)
        .ritmFont(12.5)
        .foregroundStyle(RitmTheme.muted)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
    .background(tint.panel, in: RoundedRectangle(cornerRadius: 16, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .circular).strokeBorder(tint.panelBorder, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }

  private func value(_ state: HabitDayState) -> Text {
    switch state {
    case .future: return Text(store.text("Ещё не наступил", "Not yet"))
    case .off: return Text(store.text("Не по расписанию", "Not scheduled"))
    default:
      if let target = habit.target {
        let unit = (habit.unit ?? "").isEmpty ? "" : " " + (habit.unit ?? "")
        return Text(
          "\(habitNumber(HabitSchedule.progress(habit, on: day))) / \(habitNumber(target))\(unit)")
      }
      return Text(state == .done ? store.text("Выполнено", "Done") : store.text("Не выполнено", "Not done"))
    }
  }
}

enum HabitSheetText {
  /// «Пятница, 6 нояб., выполнено» for a day cell.
  @MainActor
  static func dayLabel(_ habit: Habit, _ day: String, state: HabitDayState, store: RitmStore)
    -> String
  {
    let name = HabitDates.label(
      day, zone: store.timeZone, language: store.language, template: "EEEE, d MMM"
    ).habitCapitalized
    let status: String
    switch state {
    case .future: status = store.text("ещё не наступил", "not yet")
    case .off: status = store.text("не по расписанию", "not scheduled")
    case .done: status = store.text("выполнено", "done")
    case .part:
      status =
        store.text("выполнено частично, ", "partly done, ")
        + habitNumber(HabitSchedule.progress(habit, on: day))
    case .miss: status = store.text("не выполнено", "not done")
    }
    return name + ", " + status
  }

  /// «7 дней подряд», «3 дня подряд».
  static func streakTitle(_ level: Int, language: Language) -> String {
    language == .ru
      ? "\(level) \(level == 3 ? "дня" : "дней") подряд" : "\(level) days in a row"
  }
}
