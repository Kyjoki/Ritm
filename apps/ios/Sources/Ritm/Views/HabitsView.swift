import RitmCore
import SwiftUI

/// Surfaces shared by the habits page (visual-refresh.css `.ritm-glass` habit rules).
enum HabitStyle {
  /// Day tiles, heat cells, the stepper and award chips.
  static var tile: Color { RitmTheme.mix(RitmTheme.soft, 0.09, into: RitmTheme.glassRaised) }
  /// A done day, a partly done heat cell, an earned award.
  static var chosen: Color { RitmTheme.mix(RitmTheme.accentColor, 0.19, into: RitmTheme.glassRaised) }
  static var chosenBorder: Color {
    RitmTheme.mix(RitmTheme.accentColor, 0.68, into: RitmTheme.panelBorder)
  }
}

private struct HabitEditTarget: Identifiable {
  let habit: Habit?
  var id: String { habit?.id ?? "create" }
}

/// «Привычки»: src/features/HabitsPage.tsx at 390 px.
struct HabitsView: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var editing: HabitEditTarget?
  @State private var deleting: Habit?
  @State private var showArchived = false
  @State private var month = false
  @State private var offset = 0
  @State private var selectedDay: String?
  @State private var busyID: String?
  @State private var celebration: String?
  @State private var recordID: String?

  private var today: String { store.today }
  private var visible: [Habit] { store.habits.filter { ($0.archived == true) == showArchived } }
  private var archivedCount: Int { store.habits.filter { $0.archived == true }.count }
  private var dates: [String] { HabitsPlan.periodDates(today: today, month: month, offset: offset) }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          RitmShellHeader()
          heading
          if let message = store.errorMessage {
            RitmErrorBanner(message: message).padding(.bottom, 16)
          }
          MutationRecoveryView()
          if store.bootstrap == nil {
            HStack(spacing: 9) {
              ProgressView().tint(RitmTheme.accentColor)
              Text(store.text("Загружаем…", "Loading…"))
            }
            .ritmFont(12)
            .foregroundStyle(RitmTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 145)
            .background { RitmPanelBackground() }
          } else {
            HabitsAnalytics(
              habits: visible, archived: showArchived, month: $month, offset: $offset,
              selectedDay: $selectedDay)
              .ritmPageReveal(index: 0)
            listHeading.ritmPageReveal(index: 1)
            list
          }
          RitmPageFooter()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .refreshable { await store.refresh() }
      .scrollDismissesKeyboard(.interactively)
      if let celebration { celebrationToast(celebration) }
    }
    .toolbar(.hidden, for: .navigationBar)
    .sheet(item: $editing) { target in HabitEditor(habit: target.habit) }
    .confirmationDialog(
      store.text("Удалить привычку?", "Delete habit?"),
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible
    ) {
      Button(store.text("Удалить привычку", "Delete habit"), role: .destructive) {
        Task { await remove() }
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(store.text("История отметок этой привычки будет удалена.", "This habit's history will be deleted."))
    }
  }

  // MARK: Heading and list

  /// On a phone the web stacks the title and puts the 44 pt «+» under it.
  private var heading: some View {
    VStack(alignment: .leading, spacing: 0) {
      RitmPageHeading(title: store.text("Привычки", "Habits"))
        .padding(.bottom, -20)
      RitmIconCTA(symbol: "plus", label: store.text("Новая привычка", "New habit")) {
        store.errorMessage = nil
        editing = HabitEditTarget(habit: nil)
      }
      .padding(.top, 14)
    }
    .padding(.bottom, 24)
  }

  private var listHeading: some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(store.text("Ваши действия", "Your actions")).ritmFont(10, weight: .medium)
          .foregroundStyle(RitmTheme.muted)
        Text(showArchived ? store.text("Архив", "Archive") : store.text("Мои привычки", "My habits"))
          .ritmFont(20, weight: .semibold, tracking: -0.035)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
      }
      Spacer(minLength: 0)
      Button {
        showArchived.toggle()
        selectedDay = nil
      } label: {
        Label {
          Text(
            showArchived
              ? store.text("К активным", "Back to active")
                + (archivedCount > 0 ? " (\(archivedCount))" : "")
              : store.text("Архив", "Archive"))
        } icon: {
          Image(systemName: showArchived ? "arrow.counterclockwise" : "archivebox")
            .font(.system(size: 14))
        }
        .ritmFont(11, weight: .semibold)
        .padding(.horizontal, 10)
      }
      .buttonStyle(RitmSecondaryButtonStyle())
    }
    .padding(.top, 28)
    .padding(.bottom, 14)
  }

  @ViewBuilder private var list: some View {
    if visible.isEmpty {
      VStack(spacing: 9) {
        Text(showArchived ? store.text("Архив пуст", "The archive is empty") : store.text("Пока нет привычек", "No habits yet"))
          .ritmFont(16, weight: .semibold)
          .foregroundStyle(RitmTheme.text)
        Text(
          showArchived
            ? store.text("Здесь появятся сохранённые привычки.", "Saved habits will appear here.")
            : store.text(
              "Добавьте первую привычку, которую хотите повторять каждый день.",
              "Add the first habit you want to repeat every day.")
        )
        .ritmFont(12, lineSpacing: 4)
        .foregroundStyle(RitmTheme.muted)
      }
      .multilineTextAlignment(.center)
      .padding(24)
      .frame(maxWidth: .infinity, minHeight: 145)
      .background { RitmPanelBackground(raised: true) }
      .ritmPageReveal(index: 2)
    } else {
      VStack(spacing: 13) {
        ForEach(Array(visible.enumerated()), id: \.element.id) { index, habit in
          HabitCard(
            habit: habit, today: today, busy: busyID != nil, isRecord: recordID == habit.id,
            onEdit: {
              store.errorMessage = nil
              editing = HabitEditTarget(habit: habit)
            },
            onArchive: { Task { await setArchived(habit, !(habit.archived ?? false)) } },
            onDelete: { deleting = habit },
            onProgress: { day, count in Task { await setProgress(habit, day: day, count: count) } }
          )
          .ritmPageReveal(index: 2 + index)
        }
      }
    }
  }

  private func celebrationToast(_ text: String) -> some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: "sparkles").font(.system(size: 16))
    }
    .ritmFont(13, weight: .bold)
    .foregroundStyle(RitmTheme.accentColor)
    .padding(.vertical, 13)
    .padding(.horizontal, 17)
    .background(RitmTheme.glassRaised.opacity(0.5), in: Capsule())
    .ritmGlass(in: Capsule())
    .padding(16)
    .transition(.opacity.combined(with: .move(edge: .bottom)))
    .accessibilityAddTraits(.isStaticText)
  }

  // MARK: Writes

  private func setProgress(_ habit: Habit, day: String, count: Int) async {
    guard busyID == nil, HabitSchedule.canMark(habit, on: day, today: today) else { return }
    let target = HabitSchedule.target(habit)
    let next = max(0, min(target, count))
    let wasComplete = HabitSchedule.isComplete(habit, on: day)
    busyID = habit.id
    defer { busyID = nil }
    let saved = await store.write { client -> Habit in
      if habit.target == nil {
        return try await client.setHabitDay(
          id: habit.id, date: day, completed: next > 0, expectedUpdatedAt: habit.updatedAt)
      }
      return try await client.setHabitProgress(
        id: habit.id, date: day, count: next, expectedUpdatedAt: habit.updatedAt)
    }
    guard let saved, !wasComplete, next >= target else { return }
    if HabitSchedule.bestStreak(saved, today: today) > HabitSchedule.bestStreak(habit, today: today) {
      flashRecord(habit.id)
    }
    if let milestone = HabitsPlan.newMilestone(previous: habit, updated: saved) {
      celebrate(
        store.text(
          "\(habit.title): достижение \(milestone) дней", "\(habit.title): \(milestone)-day achievement"))
    }
  }

  private func setArchived(_ habit: Habit, _ archived: Bool) async {
    guard busyID == nil else { return }
    busyID = habit.id
    defer { busyID = nil }
    var input = habit.input
    input.archived = archived
    _ = await store.write {
      try await $0.updateHabit(id: habit.id, habit: input, expectedUpdatedAt: habit.updatedAt)
    }
  }

  private func remove() async {
    guard let habit = deleting, busyID == nil else { return }
    busyID = habit.id
    defer {
      busyID = nil
      deleting = nil
    }
    _ = await store.performMutation {
      try await $0.deleteHabit(id: habit.id, expectedUpdatedAt: habit.updatedAt)
    }
  }

  private func flashRecord(_ id: String) {
    recordID = id
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(1050))
      if recordID == id { recordID = nil }
    }
  }

  private func celebrate(_ text: String) {
    withAnimation(reduceMotion ? nil : RitmMotion.ease(0.33)) { celebration = text }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(2600))
      guard celebration == text else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { celebration = nil }
    }
  }
}

private struct HabitDayEntry: Identifiable {
  let day: String
  let summary: HabitDaySummary
  var id: String { day }
}

/// `.habits-analytics`: the period switch, gauge, KPIs, daily bars, heatmap and insights.
private struct HabitsAnalytics: View {
  let habits: [Habit]
  let archived: Bool
  @Binding var month: Bool
  @Binding var offset: Int
  @Binding var selectedDay: String?
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var today: String { store.today }
  private var dates: [String] { HabitsPlan.periodDates(today: today, month: month, offset: offset) }
  private var daily: [HabitDayEntry] {
    dates.map { HabitDayEntry(day: $0, summary: HabitSchedule.daySummary(habits, on: $0, today: today)) }
  }

  var body: some View {
    let totals = HabitSchedule.periodSummary(habits, dates: dates, today: today)
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 5) {
          Text(
            archived
              ? store.text("История архивных привычек", "Archived habit history")
              : store.text("История активных привычек", "Active habit history")
          )
          .ritmFont(10, weight: .medium)
          .foregroundStyle(RitmTheme.muted)
          Text(store.text("Прогресс привычек", "Habit progress"))
            .ritmFont(20, weight: .semibold, tracking: -0.035)
            .foregroundStyle(RitmTheme.text)
            .accessibilityAddTraits(.isHeader)
        }
        controls
      }
      Text(periodLabel).ritmFont(12).foregroundStyle(RitmTheme.muted).padding(.top, 5)
      HabitGauge(percent: totals.progress, key: "\(archived)-\(month)-\(offset)")
        .frame(width: 210, height: 127)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
      kpis.padding(.top, 4)
      if totals.planned > 0 {
        graphs
        if let selectedDay, let entry = daily.first(where: { $0.day == selectedDay }) {
          Text(describe(entry.day, entry.summary, template: "EEEE d MMMM"))
            .ritmFont(12)
            .foregroundStyle(RitmTheme.accentColor)
            .padding(.top, 12)
        }
        insights
      } else {
        HStack(spacing: 15) {
          Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(RitmTheme.accentColor)
          Text(store.text("Нет запланированных привычек", "No habits scheduled")).ritmFont(13)
            .foregroundStyle(RitmTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { RitmPanelBackground() }
  }

  private var periodLabel: String {
    guard let first = dates.first else { return "" }
    if month {
      return FeatureDate.label(first, zone: store.timeZone, language: store.language, template: "LLLL yyyy")
    }
    return FeatureDate.label(first, zone: store.timeZone, language: store.language, template: "d MMM") + " – "
      + FeatureDate.label(dates.last ?? first, zone: store.timeZone, language: store.language, template: "d MMM")
  }

  /// Switching the period also returns to the current one and clears the selected day.
  private var periodBinding: Binding<Bool> {
    Binding(
      get: { month },
      set: { value in
        month = value
        offset = 0
        selectedDay = nil
      })
  }

  private var controls: some View {
    HStack(spacing: 6) {
      RitmSegmentedControl(
        label: store.text("Период аналитики", "Analytics period"), values: [false, true],
        title: { $0 ? store.text("Месяц", "Month") : store.text("Неделя", "Week") },
        selection: periodBinding, fontSize: 12, fillsWidth: false
      )
      .padding(.trailing, 5)
      HabitIconButton(symbol: "chevron.left", label: store.text("Предыдущий период", "Previous period")) {
        offset -= 1
        selectedDay = nil
      }
      HabitIconButton(symbol: "chevron.right", label: store.text("Следующий период", "Next period")) {
        offset += 1
        selectedDay = nil
      }
      .disabled(offset == 0)
    }
  }

  private var kpis: some View {
    let todaySummary = HabitSchedule.daySummary(habits, on: today, today: today)
    let current = habits.map { HabitSchedule.streak($0, today: today) }.max() ?? 0
    let best = habits.map { HabitSchedule.bestStreak($0, today: today) }.max() ?? 0
    let days = store.text(" дн.", " d")
    return HStack(spacing: 8) {
      if todaySummary.planned > 0 {
        kpi(store.text("Сегодня выполнено", "Done today"), count: todaySummary.completed, suffix: " / \(todaySummary.planned)")
      } else {
        kpi(store.text("Сегодня выполнено", "Done today"), empty: store.text("Нет запланированных привычек", "No habits scheduled"))
      }
      kpi(store.text("Текущая серия", "Current streak"), count: current, suffix: days)
      kpi(store.text("Лучшая серия", "Best streak"), count: best, suffix: days)
    }
  }

  private func kpi(_ title: String, count: Int? = nil, suffix: String = "", empty: String? = nil)
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).ritmFont(10).foregroundStyle(RitmTheme.muted)
      if let empty {
        Text(empty).ritmFont(12, weight: .medium, lineSpacing: 3).foregroundStyle(RitmTheme.muted)
      } else if let count {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          RitmCountText(count) { "\($0)" }.foregroundStyle(RitmTheme.text)
          Text(suffix).foregroundStyle(RitmTheme.muted)
        }
        .ritmFont(22, weight: .semibold, tracking: -0.04)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      }
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    .background(RitmTheme.glassRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 15, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 15, style: .circular).strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }

  private var graphs: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 13) {
        Text(store.text("Выполнение по дням", "Completion by day"))
          .ritmFont(13, weight: .semibold, tracking: -0.01)
          .foregroundStyle(RitmTheme.text)
        if month {
          ScrollView(.horizontal) { bars.frame(width: CGFloat(daily.count) * 49) }
            .scrollIndicators(.hidden)
        } else {
          bars
        }
      }
      VStack(alignment: .leading, spacing: 13) {
        Text(store.text("Регулярность", "Consistency"))
          .ritmFont(13, weight: .semibold, tracking: -0.01)
          .foregroundStyle(RitmTheme.text)
        heatmap
        HStack(spacing: 5) {
          Spacer()
          Text(store.text("Меньше", "Less"))
          ForEach(0..<3, id: \.self) { level in
            RoundedRectangle(cornerRadius: 3, style: .circular)
              .fill(level == 0 ? HabitStyle.tile : level == 1 ? HabitStyle.chosen : RitmTheme.accentColor)
              .overlay {
                RoundedRectangle(cornerRadius: 3, style: .circular)
                  .strokeBorder(level == 0 ? RitmTheme.panelBorder : RitmTheme.accentColor, lineWidth: 1)
              }
              .frame(width: 11, height: 11)
          }
          Text(store.text("Больше", "More"))
        }
        .ritmFont(10)
        .foregroundStyle(RitmTheme.muted)
        .accessibilityHidden(true)
      }
    }
    .padding(.top, 22)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.panelBorder).frame(height: 1) }
    .padding(.top, 17)
  }

  private var bars: some View {
    // Bars grow from the baseline once per period; ticking a habit only moves the bar it changes.
    RitmDrawGate(key: dates) { drawn in barsRow(drawn: drawn) }
  }

  private func barsRow(drawn: Bool) -> some View {
    HStack(alignment: .bottom, spacing: month ? 5 : 8) {
      ForEach(Array(daily.enumerated()), id: \.element.id) { index, entry in
        Button {
          selectedDay = entry.day
        } label: {
          VStack(spacing: 8) {
            GeometryReader { proxy in
              VStack(spacing: 0) {
                Spacer(minLength: 0)
                UnevenRoundedRectangle(
                  topLeadingRadius: 6, bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                  topTrailingRadius: 6, style: .circular
                )
                .fill(RitmTheme.accentColor)
                .frame(
                  height: drawn ? proxy.size.height * CGFloat(entry.summary.progress ?? 0) / 100 : 0
                )
                .animation(reduceMotion ? nil : RitmMotion.barGrow(index: index), value: drawn)
                .animation(
                  reduceMotion ? nil : RitmMotion.easeOut(RitmMotion.countChange),
                  value: entry.summary.progress)
              }
            }
            .frame(height: 111)
            .background(
              RitmTheme.mix(RitmTheme.soft, 0.78, into: RitmTheme.glassRaised),
              in: UnevenRoundedRectangle(
                topLeadingRadius: 6, bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                topTrailingRadius: 6, style: .circular)
            )
            .clipShape(
              UnevenRoundedRectangle(
                topLeadingRadius: 6, bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                topTrailingRadius: 6, style: .circular)
            )
            .padding(2)
            .overlay {
              if selectedDay == entry.day {
                RoundedRectangle(cornerRadius: 8, style: .circular).strokeBorder(RitmTheme.accentColor, lineWidth: 2)
              }
            }
            Text("\(Int(entry.day.suffix(2)) ?? 0)").ritmFont(10).foregroundStyle(RitmTheme.muted)
          }
          .frame(maxWidth: .infinity, minHeight: 135)
          .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.97))
        .accessibilityLabel(describe(entry.day, entry.summary, template: "EEE d MMM"))
      }
    }
  }

  private var heatmap: some View {
    let lead = dates.first.flatMap(HabitSchedule.weekday) ?? 0
    let columns = Array(repeating: GridItem(.fixed(44), spacing: 5), count: 7)
    return ScrollView(.horizontal) {
      RitmDrawGate(key: dates) { drawn in
        LazyVGrid(columns: columns, spacing: 5) {
          ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 44) }
          ForEach(Array(daily.enumerated()), id: \.element.id) { index, entry in
            heatCell(entry.day, entry.summary)
              .opacity(drawn ? 1 : 0)
              .scaleEffect(drawn ? 1 : 0.8)
              .animation(
                reduceMotion
                  ? nil : RitmMotion.easeOut(0.3).delay(Double(min(index, 24)) * 0.015),
                value: drawn)
          }
        }
        .padding(2)
      }
    }
    .scrollIndicators(.hidden)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Календарь выполнения", "Completion calendar"))
  }

  private func heatCell(_ day: String, _ summary: HabitDaySummary) -> some View {
    let level = HabitsPlan.heatLevel(summary, day: day, today: today)
    let selected = selectedDay == day
    let fill: Color
    let ink: Color
    switch level {
    case .full:
      fill = RitmTheme.accentColor
      ink = RitmTheme.accentInk
    case .some:
      fill = HabitStyle.chosen
      ink = RitmTheme.accentColor
    default:
      fill = HabitStyle.tile
      ink = RitmTheme.muted
    }
    let border = selected || level == .full || level == .some ? HabitStyle.chosenBorder : RitmTheme.panelBorder
    return Button {
      selectedDay = day
    } label: {
      Text("\(Int(day.suffix(2)) ?? 0)")
        .ritmFont(10)
        .foregroundStyle(ink)
        .frame(width: 44, height: 44)
        .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .circular))
        .overlay { RoundedRectangle(cornerRadius: 7, style: .circular).strokeBorder(border, lineWidth: 1) }
        .shadow(color: level == .full ? Color(rgb: 0x764DB7, opacity: 0.14) : .clear, radius: 7, y: 5)
        .opacity(level == .future || level == .none ? 0.45 : 1)
        .offset(y: selected ? -2 : 0)
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .accessibilityLabel(describe(day, summary, template: "EEE d MMM"))
  }

  @ViewBuilder private var insights: some View {
    let steady = HabitsPlan.steadiest(habits, dates: dates, today: today)
    let weak = HabitsPlan.weakestWeekday(habits, dates: dates, today: today)
    let change = HabitsPlan.comparison(habits, today: today, month: month, offset: offset)
    VStack(alignment: .leading, spacing: 8) {
      if let steady {
        insight("sparkles", store.text("Самая стабильная: ", "Steadiest: ") + "\(steady.habit.title) (\(steady.percent)%)")
      }
      if let weak, let day = dates.first(where: { HabitSchedule.weekday($0) == weak }) {
        insight(
          "target",
          store.text("Чаще пропускается: ", "Most often missed: ")
            + FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEEE"))
      }
      if let change {
        let delta = change.current - change.previous
        insight(
          "waveform.path.ecg",
          store.text("К прошлому периоду: ", "Versus the last period: ") + (delta > 0 ? "+" : "")
            + "\(delta) " + store.text("п. п.", "pp"))
      }
      if steady == nil && weak == nil && change == nil {
        Text(
          store.text(
            "Истории пока мало для выводов. Продолжайте отмечать привычки.",
            "There is not enough history yet. Keep marking your habits.")
        )
        .ritmFont(11, lineSpacing: 3)
        .foregroundStyle(RitmTheme.muted)
      }
    }
    .padding(.top, 17)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.panelBorder).frame(height: 1) }
    .padding(.top, 21)
  }

  private func insight(_ symbol: String, _ text: String) -> some View {
    HStack(spacing: 7) {
      Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(RitmTheme.accentColor)
        .accessibilityHidden(true)
      Text(text).ritmFont(11).foregroundStyle(RitmTheme.muted)
    }
  }

  private func describe(_ day: String, _ summary: HabitDaySummary, template: String) -> String {
    let label = FeatureDate.label(day, zone: store.timeZone, language: store.language, template: template)
    if day > today { return label + ". " + store.text("Будущий день", "Future day") }
    if summary.planned > 0 {
      return store.text(
        "\(label): \(summary.completed) из \(summary.planned)", "\(label): \(summary.completed) of \(summary.planned)")
    }
    return label + ". " + store.text("Нет запланированных привычек", "No habits scheduled")
  }
}

/// `.habits-gauge`: a half ring with the period's completion share.
private struct HabitGauge: View {
  let percent: Int?
  /// Identifies the period: the arc sweeps in again only when it changes.
  let key: String
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .bottom) {
      HabitArc().stroke(RitmTheme.ringTrack, style: StrokeStyle(lineWidth: 13, lineCap: .round))
      RitmDrawGate(key: key) { drawn in
        HabitArc()
          .trim(from: 0, to: drawn ? CGFloat(percent ?? 0) / 100 : 0)
          .stroke(RitmTheme.accentColor, style: StrokeStyle(lineWidth: 13, lineCap: .round))
          .shadow(color: Color(rgb: 0x7F4EC0, opacity: 0.16), radius: 5)
          .animation(reduceMotion ? nil : RitmMotion.sweep, value: drawn)
          .animation(
            reduceMotion ? nil : RitmMotion.easeOut(RitmMotion.countChange), value: percent)
      }
      VStack(spacing: 1) {
        percentText
          .ritmFont(37, weight: .bold, tracking: -0.065)
          .foregroundStyle(RitmTheme.text)
          .monospacedDigit()
        Text(
          percent == nil
            ? store.text("Нет запланированных привычек", "No habits scheduled")
            : store.text("выполнено за период", "done this period")
        )
        .ritmFont(11)
        .foregroundStyle(RitmTheme.muted)
      }
      .padding(.bottom, 4)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      percent.map { store.text("Выполнено \($0) процентов", "\($0) percent done") }
        ?? store.text("Нет запланированных привычек", "No habits scheduled"))
  }

  @ViewBuilder private var percentText: some View {
    if let percent {
      RitmCountText(percent) { "\($0)%" }
    } else {
      Text("—")
    }
  }
}

/// `M 12 92 A 78 78 0 0 1 168 92` in a 180 × 104 box, fitted into the top 111 pt.
private struct HabitArc: Shape {
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width / 180, 111 / 104)
    let originX = rect.midX - 90 * scale
    var path = Path()
    path.addArc(
      center: CGPoint(x: originX + 90 * scale, y: 92 * scale), radius: 78 * scale,
      startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
    return path
  }
}

struct HabitIconButton: View {
  let symbol: String
  let label: String
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(RitmTheme.muted)
        .frame(width: 44, height: 44)
        .ritmGlass(in: Circle(), interactive: true)
        .contentShape(Circle())
        .opacity(isEnabled ? 1 : 0.45)
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(label)
  }
}
