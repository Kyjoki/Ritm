import RitmCore
import SwiftUI

/// The analytics of one habit (`.hs-sheet`): identity, Week / Month, the streak ring with the
/// record and the share, the week or the month with the 20-week heat map, the chosen day's
/// control, «Достижения», their history, and Изменить / В архив.
struct HabitSheet: View {
  let habitID: String
  let today: String
  let onProgress: (String, String, Int) -> Void
  let onArchive: (Habit) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var month: Bool
  @State private var offset: Int
  @State private var selected: String
  @State private var editing: Habit?
  @State private var direction: CGFloat = 0

  init(
    habitID: String, today: String, month: Bool, offset: Int, day: String,
    onProgress: @escaping (String, String, Int) -> Void, onArchive: @escaping (Habit) -> Void
  ) {
    self.habitID = habitID
    self.today = today
    self.onProgress = onProgress
    self.onArchive = onArchive
    _month = State(initialValue: month)
    _offset = State(initialValue: offset)
    _selected = State(initialValue: day)
  }

  private var habit: Habit? { store.habits.first { $0.id == habitID } }
  private var dates: [String] { HabitsPlan.periodDates(today: today, month: month, offset: offset) }

  var body: some View {
    ZStack {
      RitmBackground()
      if let habit {
        ScrollView {
          content(habit)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
    }
    .presentationDetents([.large])
    .ritmSheetGrabber()
    .presentationCornerRadius(30)
    .sheet(item: $editing) { HabitEditor(habit: $0) }
    // A habit deleted elsewhere closes its sheet.
    .onChange(of: habit == nil) { _, gone in if gone { dismiss() } }
  }

  private func content(_ habit: Habit) -> some View {
    let tint = HabitPalette.tint(for: habit.id)
    let stats = HabitStatsCache.shared.stats(for: habit, today: today)
    let dates = self.dates
    let period = HabitAnalytics.periodStats(habit, dates: dates, today: today)
    return VStack(alignment: .leading, spacing: 0) {
      header(habit, tint: tint)
      periodControls(habit, dates: dates)
      VStack(alignment: .leading, spacing: 12) {
        statPanel(stats: stats, period: period, tint: tint)
        summary(habit, period: period).padding(.horizontal, 4)
        charts(habit, dates: dates, tint: tint)
          .habitSwap(key: "\(month)-\(offset)", direction: direction)
        control(habit, tint: tint)
        achievements(habit, stats: stats)
        history(stats: stats)
        actions(habit)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 34)
  }

  // MARK: Identity and period

  private func header(_ habit: Habit, tint: HabitTint) -> some View {
    HStack(spacing: 12) {
      RitmSymbol(habitSymbol(habit.icon))
        .font(.system(size: 25, weight: .medium))
        .foregroundStyle(tint.base)
        .frame(width: 50, height: 50)
        .background(tint.tile, in: RoundedRectangle(cornerRadius: 16, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .circular).strokeBorder(tint.tileRim, lineWidth: 1)
        }
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(habit.title)
          .ritmFont(21, weight: .semibold, tracking: -0.05)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(2)
          .accessibilityAddTraits(.isHeader)
        Text(HabitCard.schedule(habit, language: store.language))
          .ritmFont(12.5)
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
        if store.workouts.settings.linkedHabitID == habit.id { HabitLinkBadge() }
      }
      Spacer(minLength: 8)
      HabitIconButton(symbol: "xmark", label: store.text("Закрыть", "Close")) { dismiss() }
    }
    .padding(.top, 8)
    .padding(.bottom, 14)
  }

  private func periodControls(_ habit: Habit, dates: [String]) -> some View {
    let canGoBack = (dates.first ?? "") > habit.startDate
    return VStack(spacing: 8) {
      RitmSegmentedControl(
        label: store.text("Период", "Period"), values: [false, true],
        title: { $0 ? store.text("Месяц", "Month") : store.text("Неделя", "Week") },
        selection: Binding(get: { month }, set: switchPeriod), fontSize: 12.5)
      HStack(spacing: 4) {
        HabitArrowButton(
          symbol: "chevron.left",
          label: month ? store.text("Предыдущий месяц", "Previous month") : store.text("Предыдущая неделя", "Previous week")
        ) { step(-1) }
        .disabled(!canGoBack)
        Text(
          HabitDates.periodLabel(
            dates, month: month, zone: store.timeZone, language: store.language)
        )
        .ritmFont(14.5, weight: .semibold, tracking: -0.02)
        .foregroundStyle(RitmTheme.text)
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        HabitArrowButton(
          symbol: "chevron.right",
          label: month ? store.text("Следующий месяц", "Next month") : store.text("Следующая неделя", "Next week")
        ) { step(1) }
        .disabled(offset >= 0)
      }
    }
    .padding(.bottom, 12)
  }

  private func switchPeriod(_ value: Bool) {
    guard value != month else { return }
    direction = 0
    month = value
    offset = 0
    selected = HabitAnalytics.defaultDay(in: dates, today: today) ?? today
  }

  private func step(_ delta: Int) {
    direction = CGFloat(delta)
    offset = min(0, offset + delta)
    selected = HabitAnalytics.defaultDay(in: dates, today: today) ?? today
  }

  // MARK: Numbers

  private func statPanel(stats: HabitStats, period: HabitPeriodStats, tint: HabitTint) -> some View {
    let next = HabitAnalytics.nextGoal(streak: stats.streak)
    return HStack(spacing: 16) {
      HabitProgressRing(
        fraction: next.map { Double(stats.streak) / Double($0) } ?? 1, size: 76, lineWidth: 8,
        arc: tint.base, key: "sheet"
      ) {
        VStack(spacing: 2) {
          RitmCountText(stats.streak) { "\($0)" }
            .ritmFont(26, weight: .semibold, tracking: -0.05)
            .foregroundStyle(RitmTheme.text)
          Text(store.text("дн.", "d")).ritmFont(10.5, weight: .medium).foregroundStyle(RitmTheme.muted)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(store.text("Серия: \(stats.streak)", "Streak: \(stats.streak)"))
      HStack(alignment: .top, spacing: 6) {
        figure(stats.best, suffix: "", label: store.text("рекорд, дн.", "best, days"))
        figure(
          period.percent, suffix: "%",
          label: month ? store.text("за месяц", "this month") : store.text("за неделю", "this week"))
        if let next {
          figure(
            next - stats.streak, suffix: "",
            label: store.text("до цели · \(next)", "to goal · \(next)"))
        } else {
          VStack(alignment: .leading, spacing: 2) {
            Text("—").ritmFont(20, weight: .semibold).foregroundStyle(RitmTheme.text)
            Text(store.text("все цели", "all goals")).ritmFont(11).foregroundStyle(RitmTheme.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tint.panel, in: RoundedRectangle(cornerRadius: 24, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .circular).strokeBorder(tint.panelBorder, lineWidth: 1)
    }
  }

  private func figure(_ value: Int, suffix: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 0) {
        RitmCountText(value) { "\($0)" }
        Text(suffix)
      }
      .ritmFont(20, weight: .semibold, tracking: -0.04)
      .foregroundStyle(RitmTheme.text)
      Text(label).ritmFont(11).foregroundStyle(RitmTheme.muted).lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func summary(_ habit: Habit, period: HabitPeriodStats) -> some View {
    let text: Text
    if period.planned == 0 {
      text = Text(store.text("В этом периоде нет дней по расписанию.", "No scheduled days in this period."))
    } else if habit.target != nil {
      let unit = (habit.unit ?? "").isEmpty ? "" : " " + (habit.unit ?? "")
      text = habitRichText(
        [
          (store.text("Цель достигнута ", "Goal met on "), false),
          (store.text("\(period.completed) из \(period.planned)", "\(period.completed) of \(period.planned)"), true),
          (store.text(" дней · в среднем ", " days · on average "), false),
          (habitNumber(period.average) + unit, true),
          (store.text(" в день", " a day"), false),
        ], emphasis: RitmTheme.text)
    } else {
      text = habitRichText(
        [
          (store.text("Выполнено ", "Done on "), false),
          (store.text("\(period.completed) из \(period.planned)", "\(period.completed) of \(period.planned)"), true),
          (store.text(" дней по расписанию", " scheduled days"), false),
        ], emphasis: RitmTheme.text)
    }
    return text.ritmFont(12, lineSpacing: 2).foregroundStyle(RitmTheme.muted)
  }

  // MARK: Days

  @ViewBuilder private func charts(_ habit: Habit, dates: [String], tint: HabitTint) -> some View {
    let counted = habit.target != nil
    let unitCaption =
      counted ? (habit.unit ?? "") + store.text(" за день", " a day") : store.text("по дням", "by day")
    if month {
      HabitSheetCard(title: store.text("Календарь месяца", "Month calendar"), caption: unitCaption) {
        HabitSheetMonth(
          habit: habit, dates: dates, selected: selected, today: today, tint: tint,
          onSelect: { selected = $0 })
        HabitSheetLegend(counted: counted, tint: tint)
        HabitSheetReadout(habit: habit, day: selected, today: today, tint: tint)
      }
      HabitSheetCard(title: store.text("Тепловая карта", "Heat map"), caption: store.text("20 недель", "20 weeks")) {
        HabitSheetHeat(habit: habit, selected: selected, today: today, tint: tint, onSelect: { selected = $0 })
        HabitSheetLegend(counted: counted, tint: tint)
        HabitSheetReadout(habit: habit, day: selected, today: today, tint: tint)
      }
    } else {
      HabitSheetCard(title: store.text("Неделя", "Week"), caption: unitCaption) {
        HabitSheetWeek(
          habit: habit, dates: dates, selected: selected, today: today, tint: tint,
          onSelect: { selected = $0 })
        HabitSheetLegend(counted: counted, tint: tint)
        HabitSheetReadout(habit: habit, day: selected, today: today, tint: tint)
      }
    }
  }

  /// The chosen day's control: the counter, or Выполнить / Выполнено.
  @ViewBuilder private func control(_ habit: Habit, tint: HabitTint) -> some View {
    let markable = HabitSchedule.canMark(habit, on: selected, today: today)
    let done = markable && HabitSchedule.isComplete(habit, on: selected)
    Group {
      if !markable {
        Text(selected > today ? store.text("Ещё не наступил", "Not yet") : store.text("Не по расписанию", "Not scheduled"))
          .ritmFont(14, weight: .semibold)
          .foregroundStyle(RitmTheme.muted)
          .frame(maxWidth: .infinity, minHeight: 46)
          .overlay { Capsule().strokeBorder(RitmTheme.line, lineWidth: 1) }
      } else if habit.target != nil {
        HabitCounter(
          habit: habit, day: selected, tint: tint, busy: false, large: true,
          onProgress: { day, count in onProgress(habit.id, day, count) })
      } else {
        HabitDoneButton(
          done: done, tint: tint, busy: false, canWrite: store.canWrite, height: 46,
          action: { onProgress(habit.id, selected, done ? 0 : 1) })
      }
    }
    .padding(.vertical, 2)
  }

  // MARK: Achievements

  private func achievements(_ habit: Habit, stats: HabitStats) -> some View {
    let earned = HabitAnalytics.earnedLevels(habit, best: stats.best)
    let upcoming = HabitAnalytics.nextUnearned(best: stats.best, earned: earned)
    let next = HabitAnalytics.nextGoal(streak: stats.streak)
    return HabitSheetCard(title: store.text("Достижения", "Achievements"), caption: store.text("дней подряд", "days in a row")) {
      HStack(spacing: 6) {
        ForEach(HabitAnalytics.achievementLevels, id: \.self) { level in
          levelChip(level, earned: earned.contains(level), upcoming: level == upcoming)
        }
      }
      .padding(.top, 2)
      Group {
        if let next {
          Text(
            store.text(
              "Следующая — \(next) дн. подряд, осталось \(next - stats.streak).",
              "Next: \(next) days in a row, \(next - stats.streak) to go."))
        } else {
          Text(store.text("Все достижения получены.", "All achievements earned."))
        }
      }
      .ritmFont(12, lineSpacing: 2)
      .foregroundStyle(RitmTheme.muted)
    }
  }

  private func levelChip(_ level: Int, earned: Bool, upcoming: Bool) -> some View {
    HStack(spacing: 3) {
      if earned { RitmSymbol("checkmark").font(.system(size: 12, weight: .bold)) }
      Text("\(level)").ritmFont(12.5, weight: .semibold).monospacedDigit()
    }
    .foregroundStyle(earned ? RitmTheme.accentColor : upcoming ? RitmTheme.text : RitmTheme.muted)
    .frame(maxWidth: .infinity, minHeight: 32)
    .background {
      if earned {
        Capsule().fill(RitmTheme.mix(RitmTheme.accentColor, 0.2, into: RitmTheme.panel))
      } else if upcoming {
        Capsule().strokeBorder(RitmTheme.accentColor.opacity(0.6), lineWidth: 1)
      } else {
        Capsule().strokeBorder(RitmTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      HabitSheetText.streakTitle(level, language: store.language)
        + (earned ? store.text(", получено", ", earned") : ""))
  }

  private func history(stats: HabitStats) -> some View {
    let next = HabitAnalytics.nextGoal(streak: stats.streak)
    let total = HabitAnalytics.achievementLevels.count
    return HabitSheetCard(
      title: store.text("История достижений", "Achievement history"),
      caption: store.text("\(stats.events.count) из \(total)", "\(stats.events.count) of \(total)")
    ) {
      if next == nil && stats.events.isEmpty {
        Text(store.text("Пока нет достижений.", "No achievements yet."))
          .ritmFont(12).foregroundStyle(RitmTheme.muted)
      }
      VStack(alignment: .leading, spacing: 14) {
        if let next {
          historyRow(
            symbol: "target", title: HabitSheetText.streakTitle(next, language: store.language),
            note: store.text("осталось \(next - stats.streak)", "\(next - stats.streak) to go"),
            upcoming: true)
        }
        ForEach(stats.events, id: \.level) { event in
          historyRow(
            symbol: "medal", title: HabitSheetText.streakTitle(event.level, language: store.language),
            note: HabitDates.label(
              event.day, zone: store.timeZone, language: store.language, template: "d MMM"),
            upcoming: false)
        }
      }
      .overlay(alignment: .topLeading) {
        // The line that joins the milestones.
        Rectangle().fill(RitmTheme.line).frame(width: 2).padding(.vertical, 14).padding(.leading, 13)
      }
    }
  }

  private func historyRow(symbol: String, title: String, note: String, upcoming: Bool) -> some View {
    let tint = HabitPalette.tint(for: habitID)
    return HStack(spacing: 12) {
      RitmSymbol(symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(upcoming ? RitmTheme.muted : tint.base)
        .frame(width: 28, height: 28)
        .background {
          Circle().fill(RitmTheme.panel)
          Circle().fill(upcoming ? Color.clear : tint.tile)
        }
        .overlay { Circle().strokeBorder(upcoming ? RitmTheme.line : tint.tileRim, lineWidth: 1) }
      VStack(alignment: .leading, spacing: 0) {
        Text(title).ritmFont(13, weight: .semibold, tracking: -0.02)
          .foregroundStyle(upcoming ? RitmTheme.muted : RitmTheme.text)
        Text(note).ritmFont(11.5).foregroundStyle(RitmTheme.muted)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: Actions

  private func actions(_ habit: Habit) -> some View {
    HStack(spacing: 10) {
      Button {
        store.errorMessage = nil
        editing = habit
      } label: {
        HStack(spacing: 6) {
          RitmSymbol("pencil").font(.system(size: 15))
          Text(store.text("Изменить", "Edit"))
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(HabitCapsuleStyle(fontSize: 13, minHeight: 46))
      Button {
        onArchive(habit)
        dismiss()
      } label: {
        HStack(spacing: 6) {
          RitmSymbol("archivebox").font(.system(size: 15))
          Text(store.text("В архив", "Archive"))
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(HabitCapsuleStyle(fontSize: 13, minHeight: 46))
    }
    .padding(.top, 2)
  }
}
