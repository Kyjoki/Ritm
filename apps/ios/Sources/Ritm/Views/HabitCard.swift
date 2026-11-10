import RitmCore
import SwiftUI

/// `.l2-c`: one habit in the list as a glass card tinted in its own colour. The icon and the
/// name open the habit's analytics, then the week strip of the selected day, then the footer: a
/// soft «Выполнить» or, for a counted habit, a progress line with − value / goal +.
struct HabitCard: View, Equatable {
  let habit: Habit
  /// The day the page is showing; the strip is its week.
  let day: String
  let today: String
  let busy: Bool
  let isRecord: Bool
  let isLinked: Bool
  let language: Language
  let onOpen: () -> Void
  let onProgress: (String, Int) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Cards compare by what they draw, so picking a day elsewhere or an unrelated change on the
  /// page does not rebuild the ones that look the same.
  nonisolated static func == (lhs: HabitCard, rhs: HabitCard) -> Bool {
    lhs.habit == rhs.habit && lhs.day == rhs.day && lhs.today == rhs.today && lhs.busy == rhs.busy
      && lhs.isRecord == rhs.isRecord && lhs.isLinked == rhs.isLinked
      && lhs.language == rhs.language
  }

  var body: some View {
    let stats = HabitStatsCache.shared.stats(for: habit, today: today)
    let tint = HabitPalette.tint(for: habit.id)
    let markable = HabitSchedule.canMark(habit, on: day, today: today)
    let done = markable && HabitSchedule.isComplete(habit, on: day)
    return VStack(alignment: .leading, spacing: 11) {
      header(stats: stats, tint: tint, done: done)
      HabitWeekStrip(
        habit: habit, day: day, today: today, tint: tint, busy: busy,
        onToggle: { tapped in
          let complete = HabitSchedule.isComplete(habit, on: tapped)
          onProgress(tapped, complete ? 0 : HabitSchedule.target(habit))
        })
      footer(tint: tint, markable: markable, done: done)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { cardBackground(tint: tint, done: done) }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: done)
  }

  private func cardBackground(tint: HabitTint, done: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 24, style: .circular)
    return ZStack {
      shape.fill(done ? tint.doneCard : HabitPalette.surface)
        .shadow(color: RitmTheme.panelShadow, radius: 11, y: 7)
      shape.strokeBorder(done ? tint.doneBorder : RitmTheme.panelBorder, lineWidth: 1)
    }
  }

  // MARK: Header

  private func header(stats: HabitStats, tint: HabitTint, done: Bool) -> some View {
    HStack(spacing: 11) {
      Button(action: onOpen) {
        HStack(spacing: 11) {
          RitmSymbol(habitSymbol(habit.icon))
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(tint.base)
            .frame(width: 44, height: 44)
            .background(tint.tile, in: RoundedRectangle(cornerRadius: 14, style: .circular))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(tint.tileRim, lineWidth: 1)
            }
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text(habit.title)
              .ritmFont(16, weight: .semibold, tracking: -0.035)
              .foregroundStyle(RitmTheme.text)
              .lineLimit(1)
            HStack(spacing: 8) {
              flame(stats.streak)
              if isLinked { HabitLinkBadge() } else { weekText }
            }
            .ritmFont(12)
            .foregroundStyle(RitmTheme.muted)
          }
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      .accessibilityLabel(store.text("Открыть привычку ", "Open habit ") + habit.title)
      .accessibilityHint(store.text("Аналитика привычки", "Habit analytics"))
      if done {
        RitmSymbol("checkmark")
          .font(.system(size: 14, weight: .heavy))
          .foregroundStyle(HabitPalette.ink)
          .frame(width: 26, height: 26)
          .background(tint.base, in: Circle())
          .transition(.opacity)
          .accessibilityLabel(store.text("Выполнено", "Done"))
      }
    }
  }

  /// A flame with the current streak; it swells when this tick set a record.
  private func flame(_ streak: Int) -> some View {
    HStack(spacing: 3) {
      RitmSymbol("flame").font(.system(size: 14, weight: .semibold)).foregroundStyle(HabitPalette.flame)
      RitmCountText(streak) { "\($0)" }
        .ritmFont(12.5, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
    }
    .scaleEffect(isRecord && !reduceMotion ? 1.08 : 1, anchor: .leading)
    .animation(reduceMotion ? nil : RitmMotion.ease(0.42), value: isRecord)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(store.text("Серия: \(streak)", "Streak: \(streak)"))
  }

  /// «2 из 3 на неделе»; a week with nothing scheduled yet shows the schedule instead.
  @ViewBuilder private var weekText: some View {
    let count = HabitAnalytics.weekCount(habit, containing: day, today: today)
    if count.planned > 0 {
      HStack(spacing: 0) {
        RitmCountText(count.completed) { "\($0)" }.foregroundStyle(RitmTheme.text).fontWeight(.semibold)
        Text(store.text(" из \(count.planned) на неделе", " of \(count.planned) this week"))
      }
      .lineLimit(1)
    } else {
      Text(HabitCard.schedule(habit, language: language)).lineLimit(1)
    }
  }

  /// «Пн Ср Пт · 2 000 мл», «Каждый день».
  static func schedule(_ habit: Habit, language: Language) -> String {
    let days = (habit.weekdays ?? HabitSchedule.allWeekdays).sorted()
    var text =
      days.count >= 7
      ? (language == .ru ? "Каждый день" : "Every day")
      : days.map { HabitWeekdays.short($0, language: language) }.joined(separator: " ")
    if let target = habit.target {
      let unit = (habit.unit ?? "").isEmpty ? "" : " " + (habit.unit ?? "")
      text += " · " + habitNumber(target) + unit
    }
    return text
  }

  // MARK: Footer

  @ViewBuilder private func footer(tint: HabitTint, markable: Bool, done: Bool) -> some View {
    if !markable {
      Text(day > today ? store.text("Ещё не наступил", "Not yet") : store.text("Не по расписанию", "Not scheduled"))
        .ritmFont(13.5, weight: .semibold)
        .foregroundStyle(RitmTheme.muted)
        .frame(maxWidth: .infinity, minHeight: 42)
        .overlay { Capsule().strokeBorder(RitmTheme.line, lineWidth: 1) }
    } else if habit.target != nil {
      HabitCounter(habit: habit, day: day, tint: tint, busy: busy, onProgress: onProgress)
    } else {
      HabitDoneButton(
        done: done, tint: tint, busy: busy, canWrite: store.canWrite, height: 42,
        action: { onProgress(day, done ? 0 : 1) })
    }
  }
}

/// `.l2-do`: the full-width soft pill; once done it reads «Выполнено» on a deeper tint.
struct HabitDoneButton: View {
  let done: Bool
  let tint: HabitTint
  let busy: Bool
  let canWrite: Bool
  let height: CGFloat
  let action: () -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        if done {
          RitmSymbol("checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(tint.base)
            .transition(.opacity)
        }
        Text(done ? store.text("Выполнено", "Done") : store.text("Выполнить", "Complete"))
          .ritmFont(13.5, weight: .semibold, tracking: -0.01)
          .foregroundStyle(RitmTheme.text)
      }
      .frame(maxWidth: .infinity, minHeight: height)
      .background(done ? tint.buttonDone : tint.button, in: Capsule())
      .overlay { Capsule().strokeBorder(tint.buttonRim, lineWidth: 1) }
      .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .disabled(busy || !canWrite)
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.25), value: done)
    .accessibilityAddTraits(done ? .isSelected : [])
  }
}

/// `.qs.wide` with a progress line: − value / goal +. The value is a button: a tap types an exact
/// number. Every tap is an instant optimistic tick (`store.tickHabit`).
struct HabitCounter: View {
  let habit: Habit
  let day: String
  let tint: HabitTint
  let busy: Bool
  var large = false
  let onProgress: (String, Int) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var typing = false
  @State private var draft = ""

  private var progress: Int { HabitSchedule.progress(habit, on: day) }
  private var target: Int { HabitSchedule.target(habit) }
  private var step: Int { HabitAnalytics.step(target: target, unit: habit.unit) }
  private var unit: String { (habit.unit ?? "").isEmpty ? "" : " " + (habit.unit ?? "") }
  private var enabled: Bool { !busy && store.canWrite }

  var body: some View {
    VStack(spacing: 9) {
      if !large { bar }
      HStack(spacing: 8) {
        stepButton("minus", store.text("Меньше", "Less"), prominent: false) {
          onProgress(day, max(0, progress - step))
        }
        .disabled(!enabled || progress <= 0)
        Button {
          draft = String(progress)
          typing = true
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            RitmCountText(progress) { habitNumber($0) }
              .ritmFont(large ? 20 : 17, weight: .semibold, tracking: -0.04)
              .foregroundStyle(RitmTheme.text)
            Text("/ " + habitNumber(target) + unit)
              .ritmFont(12)
              .foregroundStyle(RitmTheme.muted)
          }
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .frame(maxWidth: .infinity, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(
          habit.title + ": " + habitNumber(progress) + " / " + habitNumber(target) + unit)
        .accessibilityHint(store.text("Ввести число", "Enter a number"))
        stepButton("plus", store.text("Больше", "More"), prominent: true) {
          onProgress(day, min(target, progress + step))
        }
        .disabled(!enabled || progress >= target)
      }
    }
    .alert(habit.title, isPresented: $typing) {
      TextField(store.text("Прогресс", "Progress"), text: $draft)
        .keyboardType(.numberPad)
      Button(store.text("Сохранить", "Save")) {
        if let value = Int(draft.trimmingCharacters(in: .whitespaces)), (0...target).contains(value) {
          onProgress(day, value)
        }
      }
      Button(store.text("Цель: ", "Goal: ") + habitNumber(target)) { onProgress(day, target) }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(store.text("От 0 до \(habitNumber(target))", "From 0 to \(habitNumber(target))"))
    }
  }

  /// `.pbar`: a 4 pt line that grows from the left on first sight and eases to new values.
  private var bar: some View {
    let fraction = HabitAnalytics.fraction(habit, on: day)
    return RitmDrawGate(key: habit.id) { drawn in
      Capsule()
        .fill(RitmTheme.ringTrack)
        .frame(height: 4)
        .overlay(alignment: .leading) {
          Capsule().fill(tint.base)
            .scaleEffect(x: drawn ? max(fraction, 0.001) : 0.001, anchor: .leading)
            .animation(reduceMotion ? nil : RitmMotion.easeOut(0.5), value: drawn)
            .animation(reduceMotion ? nil : RitmMotion.easeOut(0.4), value: fraction)
        }
        .clipShape(Capsule())
    }
    .accessibilityHidden(true)
  }

  private func stepButton(
    _ symbol: String, _ label: String, prominent: Bool, action: @escaping () -> Void
  ) -> some View {
    let size: CGFloat = large ? 44 : 40
    return Button(action: action) {
      RitmSymbol(symbol)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(prominent ? RitmTheme.ctaInk : RitmTheme.accentColor)
        .frame(width: size, height: size)
        .background {
          if prominent {
            Circle().fill(RitmTheme.ctaGradient)
          } else {
            Circle().fill(RitmTheme.glassRaised)
              .overlay { Circle().strokeBorder(RitmTheme.line, lineWidth: 1) }
          }
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.9))
    .accessibilityLabel(label + " " + habitNumber(step) + unit)
  }
}

/// `.l2-wk`: Вс…Сб of the selected day's week. Each tile marks or clears that day; today has a
/// ring, a tile of another day is marked with a double ring when it is the selected one.
struct HabitWeekStrip: View {
  let habit: Habit
  let day: String
  let today: String
  let tint: HabitTint
  let busy: Bool
  let onToggle: (String) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 5) {
      ForEach(HabitSchedule.week(containing: day), id: \.self) { tile($0) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Неделя: ", "Week: ") + habit.title)
  }

  private func tile(_ date: String) -> some View {
    let state = HabitAnalytics.dayState(habit, on: date, today: today)
    let canMark = HabitSchedule.canMark(habit, on: date, today: today)
    let weekday = HabitSchedule.weekday(date) ?? 0
    return VStack(spacing: 4) {
      Text(HabitWeekdays.short(weekday, language: store.language))
        .ritmFont(10, weight: date == today ? .bold : .semibold)
        .foregroundStyle(date == today ? RitmTheme.accentColor : RitmTheme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Button {
        onToggle(date)
      } label: {
        HabitDayTile(
          content: .number(Int(date.suffix(2)) ?? 0), state: state,
          fraction: HabitAnalytics.fraction(habit, on: date), tint: tint,
          isToday: date == today, isSelected: date == day && date != today, radius: 12
        )
        .frame(height: 38)
      }
      .buttonStyle(RitmPressStyle())
      .disabled(!canMark || busy || !store.canWrite)
      .accessibilityLabel(accessibilityLabel(date, state: state))
      .accessibilityAddTraits(state == .done ? .isSelected : [])
    }
  }

  private func accessibilityLabel(_ date: String, state: HabitDayState) -> String {
    let name = HabitDates.label(
      date, zone: store.timeZone, language: store.language, template: "EEEE, d MMMM")
    let status: String
    switch state {
    case .future: status = store.text("Ещё не наступил", "Not yet")
    case .off: status = store.text("Не по расписанию", "Not scheduled")
    case .done: status = store.text("Выполнено", "Done")
    case .part: status = store.text("Выполнено частично", "Partly done")
    case .miss: status = store.text("Не выполнено", "Not done")
    }
    return name.habitCapitalized + ", " + status
  }
}

/// What a day tile shows: the day number, or only the mark (a check when done, a dot when missed).
enum HabitTileContent { case number(Int), mark }

/// `.dc`: a rounded day tile in the habit's colour: filled when done, filled up to the share of
/// the goal when partly done, plain when missed, dashed when the day is not scheduled.
struct HabitDayTile: View {
  let content: HabitTileContent
  let state: HabitDayState
  let fraction: Double
  let tint: HabitTint
  let isToday: Bool
  let isSelected: Bool
  let radius: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
    label
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { fill(shape) }
      .overlay { border(shape) }
      .opacity(state == .off ? 0.5 : state == .future ? 0.55 : 1)
      .overlay {
        if isToday { shape.inset(by: -3).stroke(RitmTheme.accentColor, lineWidth: 2) }
        if isSelected {
          shape.inset(by: -1).stroke(RitmTheme.panel, lineWidth: 2)
          shape.inset(by: -3).stroke(RitmTheme.accentColor.opacity(0.7), lineWidth: 2)
        }
      }
      .contentShape(shape)
  }

  @ViewBuilder private var label: some View {
    switch content {
    case .number(let number):
      Text("\(number)")
        .ritmFont(12.5, weight: .semibold)
        .monospacedDigit()
        .foregroundStyle(state == .done ? HabitPalette.ink : RitmTheme.text)
    case .mark:
      if state == .done {
        RitmSymbol("checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(HabitPalette.ink)
      } else if state == .miss {
        Circle().fill(RitmTheme.muted.opacity(0.55)).frame(width: 5, height: 5)
      }
    }
  }

  @ViewBuilder private func fill(_ shape: RoundedRectangle) -> some View {
    switch state {
    case .done:
      shape.fill(tint.base)
    case .part:
      shape.fill(HabitPalette.tile)
        .overlay(alignment: .bottom) {
          Rectangle().fill(tint.partFill)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .scaleEffect(y: max(0.05, fraction), anchor: .bottom)
        }
        .clipShape(shape)
    case .miss:
      shape.fill(HabitPalette.tile)
    case .off, .future:
      Color.clear
    }
  }

  @ViewBuilder private func border(_ shape: RoundedRectangle) -> some View {
    switch state {
    case .done: EmptyView()
    case .part: shape.strokeBorder(tint.partBorder, lineWidth: 1)
    case .miss: shape.strokeBorder(tint.tileBorder, lineWidth: 1)
    case .off:
      shape.strokeBorder(RitmTheme.line.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    case .future: shape.strokeBorder(RitmTheme.line.opacity(0.55), lineWidth: 1)
    }
  }
}
