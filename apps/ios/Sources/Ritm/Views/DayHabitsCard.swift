import RitmCore
import SwiftUI

/// «Привычки на неделю» on «Мой день» (src/components/DashboardHabits.tsx, dashboard-habits.css
/// at max-width 760 px). A tap marks the whole day at once, as on the web.
struct DayHabitsCard: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @State private var weekOffset = 0
  @State private var busyID: String?

  private static let nameWidth: CGFloat = 148
  private static let dayWidth: CGFloat = 44

  private var days: [String] {
    HabitSchedule.week(
      containing: HabitSchedule.addDays(to: store.today, days: weekOffset * 7) ?? store.today)
  }
  private var active: [Habit] { store.habits.filter { $0.archived != true } }

  /// `color-mix(in srgb, var(--panel) 94%, var(--accent))`.
  private var surface: Color { Color(light: 0xF7F5FB, dark: 0x261F36) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      heading
      actions.padding(.top, 12)
      if active.isEmpty {
        empty
      } else {
        matrix.padding(.top, 15)
      }
    }
    .padding(.top, 19)
    .padding(.horizontal, 16)
    .padding(.bottom, 15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      let shape = RoundedRectangle(cornerRadius: 23, style: .circular)
      shape.fill(surface)
        .overlay(alignment: .top) {
          // `radial-gradient(ellipse 70% 30px at 50% 0, var(--glass-wash), transparent)`.
          EllipticalGradient(
            colors: [Color(light: 0xFFFFFF, dark: 0xDABDFF, lightOpacity: 0.34, darkOpacity: 0.045), .clear],
            center: .top, startRadiusFraction: 0, endRadiusFraction: 0.5
          )
          .frame(height: 60)
          .scaleEffect(x: 1.4, y: 1, anchor: .top)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
        .shadow(color: RitmTheme.panelShadow, radius: 11, y: 7)
    }
    .ritmPageReveal(index: 5)
  }

  private var heading: some View {
    let summary = HabitSchedule.daySummary(store.habits, on: store.today, today: store.today)
    return VStack(alignment: .leading, spacing: 5) {
      Text(store.text("Привычки на неделю", "Weekly habits"))
        .ritmFont(10, weight: .medium)
        .foregroundStyle(RitmTheme.muted)
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(store.text("Привычки", "Habits"))
          .ritmFont(18, weight: .semibold, tracking: -0.025)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        todaySummary(summary)
          .ritmFont(11, weight: .medium)
          .foregroundStyle(RitmTheme.muted)
      }
    }
  }

  /// «2/4 за сегодня»: the completed count runs up, the rest is static.
  @ViewBuilder private func todaySummary(_ summary: HabitDaySummary) -> some View {
    if summary.planned > 0 {
      let planned = summary.planned
      RitmCountText(summary.completed) { done in
        "\(done)/\(planned) " + store.text("за сегодня", "today")
      }
    } else {
      Text(store.text("Нет запланированных привычек", "No habits scheduled"))
    }
  }

  private var actions: some View {
    HStack(spacing: 12) {
      Text(
        label(days.first, template: "d MMM") + " – " + label(days.last, template: "d MMM")
      )
      .ritmFont(11)
      .foregroundStyle(RitmTheme.muted)
      .lineLimit(1)
      .fixedSize()
      HStack(spacing: 0) {
        weekButton("chevron.left", store.text("Предыдущая неделя", "Previous week")) {
          weekOffset -= 1
        }
        weekButton("chevron.right", store.text("Следующая неделя", "Next week")) {
          weekOffset = min(0, weekOffset + 1)
        }
        .disabled(weekOffset == 0)
        .opacity(weekOffset == 0 ? 0.45 : 1)
      }
      Spacer(minLength: 0)
      Button {
        navigation.section = .habits
      } label: {
        HStack(spacing: 4) {
          Text(store.text("Все привычки", "All habits"))
          Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
        }
      }
      .buttonStyle(RitmTextButtonStyle())
    }
  }

  /// A 32 pt `.icon-button` with a 44 pt touch area; the extra space overlaps its neighbours.
  private func weekButton(_ symbol: String, _ label: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(RitmTheme.muted)
        .frame(width: 32, height: 32)
        .background(RitmTheme.glassRaised, in: RoundedRectangle(cornerRadius: 10, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .circular)
            .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .padding(.horizontal, -6)
    .padding(.trailing, 12)
    .accessibilityLabel(label)
  }

  private var empty: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) { emptyCopy; Spacer(minLength: 0); emptyAction }
      VStack(alignment: .leading, spacing: 12) { emptyCopy; emptyAction }
    }
    .frame(minHeight: 70)
  }

  private var emptyCopy: some View {
    Text(store.text("Привычек пока нет — добавьте первую.", "No habits yet — add the first one."))
      .ritmFont(12)
      .foregroundStyle(RitmTheme.muted)
  }

  private var emptyAction: some View {
    Button {
      navigation.section = .habits
    } label: {
      HStack(spacing: 8) {
        Text(store.text("Добавить привычку", "Add habit"))
        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
      }
    }
    .buttonStyle(RitmSecondaryButtonStyle())
  }

  // MARK: Matrix

  /// Names stay pinned while the seven days scroll underneath, as with `position: sticky`.
  /// Each row takes the height its name needs; the day cells follow those heights.
  private var matrix: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Привычки", "Habits"))
        .ritmFont(11)
        .foregroundStyle(RitmTheme.muted)
        .frame(height: 38)
      ForEach(active) { habit in
        nameCell(habit)
          .background {
            GeometryReader { proxy in
              Color.clear.preference(key: HabitRowHeights.self, value: [habit.id: proxy.size.height])
            }
          }
      }
    }
    .frame(width: Self.nameWidth, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlayPreferenceValue(HabitRowHeights.self) { heights in
      ScrollView(.horizontal) {
        VStack(spacing: 0) {
          HStack(spacing: 0) { ForEach(days, id: \.self) { dateHeader($0) } }
          ForEach(active) { habit in
            HStack(spacing: 0) {
              ForEach(days, id: \.self) { date in
                dayCell(habit, date: date, height: heights[habit.id] ?? 52)
              }
            }
          }
        }
      }
      .scrollIndicators(.hidden)
      .padding(.leading, Self.nameWidth)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(store.text("Привычки на неделю", "Weekly habits"))
    }
  }

  private func nameCell(_ habit: Habit) -> some View {
    HStack(spacing: 10) {
      Image(systemName: habitSymbol(habit.icon))
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 32, height: 32)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 10, style: .circular))
      VStack(alignment: .leading, spacing: 3) {
        Text(habit.title)
          .ritmFont(12, weight: .semibold, lineSpacing: 2)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(2)
        Text(streakLine(habit))
          .ritmFont(10)
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .padding(.vertical, 6)
    .padding(.trailing, 10)
    .frame(width: Self.nameWidth, alignment: .leading)
    .frame(minHeight: 52)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
    .accessibilityElement(children: .combine)
  }

  private func streakLine(_ habit: Habit) -> String {
    var value =
      store.text("Серия", "Streak") + ": \(HabitSchedule.streak(habit, today: store.today))"
    if let target = habit.target {
      let count = HabitSchedule.progress(habit, on: store.today)
      let unit = habit.unit ?? ""
      value += " · " + store.text("Прогресс \(count) из \(target) \(unit)", "Progress \(count) of \(target) \(unit)")
    }
    return value
  }

  private func dateHeader(_ date: String) -> some View {
    let today = date == store.today
    return VStack(spacing: 0) {
      Text(label(date, template: "EEE")).ritmFont(10)
      Text("\(Int(date.suffix(2)) ?? 0)")
        .ritmFont(11, weight: .bold)
        .foregroundStyle(today ? RitmTheme.accentColor : RitmTheme.text)
    }
    .foregroundStyle(today ? RitmTheme.accentColor : RitmTheme.muted)
    .frame(width: Self.dayWidth)
    .frame(minHeight: 38)
    .background {
      if today {
        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .circular)
          .fill(RitmTheme.soft)
      }
    }
    .accessibilityHidden(true)
  }

  private func dayCell(_ habit: Habit, date: String, height: CGFloat) -> some View {
    let done = HabitSchedule.isComplete(habit, on: date)
    let future = date > store.today
    let available = HabitSchedule.canMark(habit, on: date, today: store.today)
    let scheduled = HabitSchedule.daySummary([habit], on: date).planned > 0
    let off = !scheduled && !available
    let dateLabel = label(date, template: "d MMMM")
    let state: String
    if done {
      state = store.text("Выполнено", "Completed")
    } else if future {
      state = store.text("Будущий день", "Future day")
    } else if date < habit.startDate && !available {
      state = store.text("До начала привычки", "Before habit start")
    } else if available {
      state = store.text("Запланировано", "Scheduled")
    } else {
      state = store.text("Не запланировано", "Rest day")
    }
    let action =
      done
      ? store.text("Снять выполнение \(habit.title) за \(dateLabel)", "Undo \(habit.title) on \(dateLabel)")
      : store.text(
        "Отметить выполнение \(habit.title) за \(dateLabel)", "Complete \(habit.title) on \(dateLabel)")
    return Button {
      Task { await toggle(habit, date: date) }
    } label: {
      HabitMark(done: done, off: off, future: future)
        .frame(width: Self.dayWidth, height: height)
        .background(date == store.today ? RitmTheme.soft : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.9))
    .disabled(!available || busyID == habit.id || !store.canWrite)
    .accessibilityLabel(available ? "\(action). \(state)" : "\(habit.title): \(dateLabel). \(state)")
    .accessibilityAddTraits(available && done ? .isSelected : [])
  }

  private func label(_ date: String?, template: String) -> String {
    guard let date else { return "" }
    return FeatureDate.label(date, zone: store.timeZone, language: store.language, template: template)
  }

  /// A completed day goes back to zero; otherwise the whole target is recorded at once.
  private func toggle(_ habit: Habit, date: String) async {
    guard busyID == nil else { return }
    let latest = store.habits.first { $0.id == habit.id } ?? habit
    let count = HabitSchedule.isComplete(latest, on: date) ? 0 : HabitSchedule.target(latest)
    busyID = habit.id
    _ = await store.write {
      try await $0.setHabitProgress(
        id: latest.id, date: date, count: count, expectedUpdatedAt: latest.updatedAt)
    }
    busyID = nil
  }
}

/// `.dashboard-habits-mark`: a 28 pt ring; filled when done, dashed on a rest day.
private struct HabitMark: View {
  let done: Bool
  let off: Bool
  let future: Bool

  var body: some View {
    Circle()
      .fill(done ? RitmTheme.accentColor : RitmTheme.panel)
      .overlay {
        Circle().strokeBorder(
          done ? RitmTheme.accentColor : off || future ? RitmTheme.line : RitmTheme.accentColor,
          style: StrokeStyle(lineWidth: 2, dash: off && !done ? [4, 3] : []))
      }
      .overlay {
        if done {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(RitmTheme.accentInk)
        }
      }
      .frame(width: 28, height: 28)
      .opacity(done ? 1 : off ? 0.72 : future ? 0.66 : 1)
  }
}

private struct HabitRowHeights: PreferenceKey {
  static let defaultValue: [String: CGFloat] = [:]
  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue()) { max($0, $1) }
  }
}
