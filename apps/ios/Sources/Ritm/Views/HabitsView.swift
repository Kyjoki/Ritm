import Charts
import RitmCore
import SwiftUI

struct HabitsView: View {
  @Environment(RitmNavigation.self) private var navigation
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingCreate = false
  @State private var showingArchive = false
  @State private var editingHabit: Habit?
  @State private var period = 0
  @State private var anchor = ""
  @State private var visible = false
  @State private var chartsIntroduced = false
  @State private var selectedAnalysisDay: String?
  private var scoped: [Habit] { store.habits.filter { ($0.archived == true) == showingArchive } }
  private var dates: [String] {
    let day = anchor.isEmpty ? store.today : anchor
    if period == 0 { return HabitSchedule.week(containing: day) }
    let calendar = FeatureDate.calendar("UTC")
    guard let range = calendar.range(of: .day, in: .month, for: FeatureDate.date(day, zone: "UTC"))
    else { return [] }
    return range.map { String(day.prefix(7)) + String(format: "-%02d", $0) }
  }
  private var summary: HabitDaySummary {
    HabitSchedule.periodSummary(scoped, dates: dates, today: store.today)
  }
  private var todaySummary: HabitDaySummary { HabitSchedule.daySummary(scoped, on: store.today) }
  private var comparisonText: String? {
    guard let first = dates.first, let previousEnd = HabitSchedule.addDays(to: first, days: -1)
    else { return nil }
    let previous =
      period == 0
      ? HabitSchedule.week(containing: previousEnd)
      : TaskSchedule.monthDates(containing: previousEnd)
    let available = dates.filter { $0 <= store.today }
    let length = min(available.count, previous.count)
    guard
      let current = HabitSchedule.periodSummary(
        scoped, dates: Array(available.prefix(length)), today: store.today
      ).percent,
      let old = HabitSchedule.periodSummary(
        scoped, dates: Array(previous.prefix(length)), today: store.today
      ).percent
    else { return nil }
    let difference = current - old
    return (difference > 0 ? "+" : "") + "\(difference) "
      + store.text(
        "п.п. к такому же отрезку прошлого периода",
        "pp versus the same portion of the previous period")
  }
  private var consistencyText: String? {
    let past = dates.filter { $0 < store.today }
    let ranked = scoped.compactMap { habit -> (Habit, Int, Int)? in
      let summary = HabitSchedule.periodSummary([habit], dates: past, today: store.today)
      return summary.planned >= 3 ? (habit, summary.completed, summary.planned) : nil
    }.sorted {
      Double($0.1) / Double($0.2) == Double($1.1) / Double($1.2)
        ? $0.1 > $1.1 : Double($0.1) / Double($0.2) > Double($1.1) / Double($1.2)
    }
    guard let value = ranked.first else { return nil }
    return store.text("Самая устойчивая привычка: ", "Most consistent habit: ") + value.0.title
      + " · \(value.1)/\(value.2)"
  }
  private var missedWeekday: String? {
    let values = (0..<7).compactMap { weekday -> (Int, Int, Int)? in
      let relevant = dates.filter { $0 < store.today && HabitSchedule.weekday($0) == weekday }
      let summary = HabitSchedule.periodSummary(scoped, dates: relevant, today: store.today)
      return summary.planned >= 2 ? (weekday, summary.completed, summary.planned) : nil
    }.sorted { Double($0.1) / Double($0.2) < Double($1.1) / Double($1.2) }
    guard let value = values.first, value.1 < value.2 else { return nil }
    return store.text("Чаще пропускается: ", "Most often missed: ")
      + weekdayName(value.0, russian: store.language == .ru)
  }
  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          RitmShellHeader().padding(.bottom, -18)
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
              Text(store.text("RITM · Ежедневные привычки", "RITM · Daily habits")).font(
                .caption.weight(.semibold)
              ).foregroundStyle(.tint)
              Text(store.text("Привычки", "Habits")).font(.largeTitle.bold())
              Text(
                store.text(
                  "Маленькие действия складываются в устойчивый ритм.",
                  "Small actions build a lasting rhythm.")
              ).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
              showingCreate = true
            } label: {
              Image(systemName: "plus").font(.title2).frame(width: 48, height: 48)
            }
            .background(RitmTheme.lavender.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
            .buttonStyle(RitmPressStyle()).disabled(!store.canWrite)
            .accessibilityLabel(store.text("Создать привычку", "Create habit"))
          }
          SyncStatusView()
          if let message = navigation.habitCelebration {
            HStack {
              Label(message, systemImage: "sparkles").font(.subheadline)
              Spacer()
              Button {
                navigation.habitCelebration = nil
              } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
              }.accessibilityLabel(store.text("Закрыть достижение", "Dismiss achievement"))
            }.padding(12).background(
              RitmTheme.lavender.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
          }
          if let error = store.errorMessage { RitmErrorBanner(message: error) }
          MutationRecoveryView()
          if store.bootstrap != nil { analytics }
          HStack {
            Text(
              showingArchive
                ? store.text("Архив привычек", "Archived habits")
                : store.text("Ваши привычки", "Your habits")
            ).font(.title3.bold())
            Spacer()
            Button {
              showingArchive.toggle()
            } label: {
              Label(
                showingArchive ? store.text("Активные", "Active") : store.text("Архив", "Archive"),
                systemImage: showingArchive ? "checklist" : "archivebox"
              ).font(.subheadline).frame(minHeight: 44)
            }.buttonStyle(RitmPressStyle())
          }
          if scoped.isEmpty {
            RitmCard {
              RitmEmptyState(
                symbol: showingArchive ? "archivebox" : "leaf",
                title: showingArchive
                  ? store.text("Архив пуст", "Archive is empty")
                  : store.text("Начните с одной привычки", "Start with one habit"),
                message: showingArchive
                  ? store.text(
                    "Здесь можно восстановить привычку и посмотреть её историю.",
                    "Restore a habit and review its history here.")
                  : store.text(
                    "Выберите действие, дни недели и цель. Прогресс появится после ваших отметок.",
                    "Choose an action, weekdays and a target. Your marks will build the progress."))
            }
          }
          ForEach(scoped) { habit in
            HabitDetailCard(habit: habit, dates: dates, onEdit: { editingHabit = habit })
          }
          RitmPageFooter()
        }.padding(.horizontal, 16).padding(.bottom, 28).frame(maxWidth: 700)
          .frame(maxWidth: .infinity)
      }.refreshable { await store.refresh() }
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { visible = navigation.section == .habits }.onDisappear { visible = false }
    .onChange(of: navigation.section) { _, value in visible = value == .habits }
    .onChange(of: visible, initial: true) { _, value in
      if value && !chartsIntroduced { chartsIntroduced = true }
    }
    .sheet(isPresented: $showingCreate) { HabitEditor() }
    .sheet(item: $editingHabit) { HabitEditor(habit: $0) }
    .sheet(
      isPresented: Binding(
        get: { selectedAnalysisDay != nil }, set: { if !$0 { selectedAnalysisDay = nil } })
    ) { HabitDayReview(habits: scoped, date: selectedAnalysisDay ?? store.today) }
    .onChange(of: period) { _, _ in anchor = "" }
  }
  private var analytics: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 20) {
        Text(
          showingArchive
            ? store.text("История архивных привычек", "Archived habit history")
            : store.text("История активных привычек", "Active habit history")
        ).font(.caption).foregroundStyle(.secondary)
        Text(store.text("Прогресс привычек", "Habit progress")).font(.title2.bold())
        HStack(spacing: 10) {
          Picker(store.text("Период", "Period"), selection: $period) {
            Text(store.text("Неделя", "Week")).tag(0)
            Text(store.text("Месяц", "Month")).tag(1)
          }.pickerStyle(.segmented)
          Button {
            shift(-1)
          } label: {
            Image(systemName: "chevron.left").frame(width: 44, height: 44)
          }.accessibilityLabel(store.text("Предыдущий период", "Previous period"))
          Button {
            shift(1)
          } label: {
            Image(systemName: "chevron.right").frame(width: 44, height: 44)
          }.disabled((dates.last ?? store.today) >= store.today).accessibilityLabel(
            store.text("Следующий период", "Next period"))
        }.buttonStyle(RitmPressStyle())
        Text(periodLabel).font(.subheadline).foregroundStyle(.secondary)
        HabitProgressArc(percent: summary.percent, animate: visible).frame(height: 155).padding(
          .top, 8)
        if let comparisonText { Text(comparisonText).font(.caption).foregroundStyle(.secondary) }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { metrics }
          VStack(spacing: 8) { metrics }
        }
        Divider()
        Text(store.text("Выполнение по дням", "Daily completion")).font(.headline)
        Chart(dates, id: \.self) { day in
          let daily = HabitSchedule.daySummary(scoped, on: day, today: store.today)
          BarMark(
            x: .value("Date", day), y: .value("Percent", chartsIntroduced ? daily.percent ?? 0 : 0)
          )
          .foregroundStyle(
            day == store.today ? RitmTheme.lavender : RitmTheme.lavender.opacity(0.48)
          ).cornerRadius(4)
          .accessibilityLabel(dateLabel(day)).accessibilityValue(
            daily.planned > 0
              ? "\(daily.completed) / \(daily.planned)"
              : store.text("Не запланировано", "Not scheduled"))
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
          AxisMarks(values: [0, 50, 100]) {
            AxisValueLabel()
            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
          }
        }
        .chartXAxis {
          AxisMarks(
            values: dates.enumerated().filter { period == 0 || $0.offset % 5 == 0 }.map(\.element)
          ) { value in
            if let key = value.as(String.self) {
              AxisValueLabel { Text(String(Int(key.suffix(2)) ?? 0)).font(.caption2) }
            }
          }
        }
        .frame(height: 140).animation(
          visible && !reduceMotion ? .easeInOut(duration: 0.35) : nil, value: store.habits
        )
        .animation(
          visible && !reduceMotion ? .easeOut(duration: 0.4) : nil, value: chartsIntroduced)
        Text(store.text("Регулярность", "Consistency")).font(.headline)
        ScrollView(.horizontal) {
          LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 7), spacing: 6
          ) {
            ForEach(dates, id: \.self) { date in
              let daily = HabitSchedule.daySummary(scoped, on: date, today: store.today)
              Button {
                selectedAnalysisDay = date
              } label: {
                VStack(spacing: 3) {
                  Text(String(Int(date.suffix(2)) ?? 0)).font(.caption.weight(.medium))
                  Text(daily.planned > 0 ? "\(daily.completed)/\(daily.planned)" : "—").font(
                    .system(size: 9))
                }.frame(maxWidth: .infinity, minHeight: 44)
                  .background(
                    RitmTheme.lavender.opacity(
                      daily.planned == 0 ? 0.04 : 0.10 + Double(daily.percent ?? 0) * 0.004),
                    in: RoundedRectangle(cornerRadius: 9))
              }.buttonStyle(RitmPressStyle())
                .accessibilityLabel(dateLabel(date))
                .accessibilityValue(
                  daily.planned > 0
                    ? "\(daily.completed) / \(daily.planned)"
                    : store.text("Не запланировано", "Not scheduled"))
            }
          }
        }.scrollIndicators(.hidden)
        if let consistencyText { Text(consistencyText).font(.caption).foregroundStyle(.tint) }
        if let missedWeekday { Text(missedWeekday).font(.caption).foregroundStyle(.secondary) }
        if consistencyText == nil && missedWeekday == nil && comparisonText == nil {
          Text(
            store.text(
              "Истории пока мало для выводов. Продолжайте отмечать привычки.",
              "There is not enough history for insights yet. Keep marking your habits.")
          ).font(.caption).foregroundStyle(.secondary)
        }
        Text(
          store.text(
            "Проценты учитывают только запланированные дни, не позднее сегодняшнего.",
            "Percentages include only scheduled days up to today.")
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  @ViewBuilder private var metrics: some View {
    HabitMetric(
      title: store.text("Сегодня выполнено", "Done today"),
      value: "\(todaySummary.completed) / \(todaySummary.planned)")
    HabitMetric(
      title: store.text("Текущая серия", "Current streak"),
      value: "\(scoped.map { HabitSchedule.streak($0, today: store.today) }.max() ?? 0) "
        + store.text("дн.", "days"))
    HabitMetric(
      title: store.text("Лучшая серия", "Best streak"),
      value: "\(scoped.map { HabitSchedule.bestStreak($0, today: store.today) }.max() ?? 0) "
        + store.text("дн.", "days"))
  }
  private var periodLabel: String {
    guard let first = dates.first, let last = dates.last else { return "" }
    return dateLabel(first) + " – " + dateLabel(last)
  }
  private func dateLabel(_ date: String) -> String {
    FeatureDate.label(date, zone: store.timeZone, language: store.language, template: "d MMM")
  }
  private func shift(_ direction: Int) {
    let current = anchor.isEmpty ? store.today : anchor
    if period == 0 {
      anchor = HabitSchedule.addDays(to: current, days: 7 * direction) ?? current
    } else if let shifted = FeatureDate.calendar("UTC").date(
      byAdding: .month, value: direction, to: FeatureDate.date(current, zone: "UTC"))
    {
      anchor = HabitSchedule.dateKey(shifted, timeZone: "UTC")
    }
  }
}
struct HabitProgressArc: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let percent: Int?
  var animate = true
  @State private var displayed: CGFloat = 0
  @State private var introduced = false
  var body: some View {
    ZStack(alignment: .bottom) {
      HalfArc().stroke(
        RitmTheme.lavender.opacity(0.13), style: StrokeStyle(lineWidth: 16, lineCap: .round))
      HalfArc().trim(from: 0, to: displayed).stroke(
        RitmTheme.lavender.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
      VStack(spacing: 4) {
        Text(percent.map { "\($0)%" } ?? "—").font(
          .system(.largeTitle, design: .rounded).weight(.bold)
        ).monospacedDigit()
        Text(store.text("выполнено за период", "completed in period")).font(.caption)
          .foregroundStyle(.secondary)
      }.padding(.bottom, 4)
    }.padding(.horizontal, 22).accessibilityElement(children: .combine)
      .onAppear { if animate { update() } }
      .onChange(of: animate) { _, active in if active && !introduced { update() } }
      .onChange(of: percent) { _, _ in update() }
  }
  private func update() {
    withAnimation(animate && !reduceMotion ? .spring(response: 0.55, dampingFraction: 1) : nil) {
      displayed = CGFloat(percent ?? 0) / 100
      introduced = true
    }
  }
}
private struct HalfArc: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addArc(
      center: CGPoint(x: rect.midX, y: rect.maxY), radius: min(rect.width / 2, rect.height),
      startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
    return path
  }
}
private struct HabitMetric: View {
  let title: String
  let value: String
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
      Text(value).font(.title3.bold()).monospacedDigit().fixedSize(
        horizontal: true, vertical: false)
    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
      .background(RitmTheme.lavender.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
      .overlay(
        RoundedRectangle(cornerRadius: 15).strokeBorder(
          RitmTheme.lavender.opacity(0.16), lineWidth: 1))
  }
}
private struct HabitDetailCard: View {
  @Environment(RitmNavigation.self) private var navigation
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let habit: Habit
  let dates: [String]
  let onEdit: () -> Void
  @State private var progressDate: String?
  @State private var deleteConfirmation = false
  private var complete: Bool { HabitSchedule.isComplete(habit, on: store.today) }
  var body: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top) {
          Image(systemName: habitSymbol(habit.icon)).font(.title3).foregroundStyle(.tint).frame(
            width: 44, height: 44
          ).background(RitmTheme.lavender.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
          VStack(alignment: .leading, spacing: 5) {
            Text(habit.title).font(.headline).textSelection(.enabled)
            Text(
              store.text("Серия: ", "Streak: ")
                + "\(HabitSchedule.streak(habit, today: store.today))"
            ).font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading)
          Menu {
            Button(store.text("Редактировать", "Edit"), systemImage: "pencil", action: onEdit)
            Button(store.text("История отметок", "Mark history"), systemImage: "calendar") {
              progressDate = store.today
            }
            Button(
              habit.archived == true
                ? store.text("Восстановить", "Restore") : store.text("В архив", "Archive"),
              systemImage: "archivebox"
            ) {
              var input = habit.input
              input.archived = habit.archived != true
              Task {
                _ = await store.write {
                  try await $0.updateHabit(
                    id: habit.id, habit: input, expectedUpdatedAt: habit.updatedAt)
                }
              }
            }
            Button(
              store.text("Удалить навсегда", "Delete permanently"), systemImage: "trash",
              role: .destructive
            ) { deleteConfirmation = true }
          } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
          }
          .disabled(!store.canWrite).accessibilityLabel(
            store.text("Действия с привычкой", "Habit actions"))
        }
        ScrollView(.horizontal) {
          HStack(spacing: 4) {
            ForEach(dates, id: \.self) { date in
              HabitDayButton(habit: habit, date: date) { progressDate = date }
            }
          }
        }.scrollIndicators(.hidden)
        if habit.archived != true {
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
              Text(store.habitProgressText(habit)).font(.subheadline.weight(.semibold))
              if let target = habit.target {
                ProgressView(
                  value: min(
                    Double(HabitSchedule.progress(habit, on: store.today)) / Double(max(target, 1)),
                    1)
                ).tint(RitmTheme.lavender)
                  .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25), value: habit.progressByDate)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if habit.target != nil {
              Button {
                progressDate = store.today
              } label: {
                Image(systemName: "plusminus").frame(width: 48, height: 48)
              }
              .disabled(
                !store.canWrite
                  || !HabitSchedule.canMark(habit, on: store.today, today: store.today)
              ).accessibilityLabel(store.text("Изменить количество", "Change quantity"))
            } else {
              Button {
                Task { await toggle() }
              } label: {
                Image(systemName: complete ? "checkmark.circle.fill" : "circle").font(
                  .system(size: 30)
                ).frame(width: 48, height: 48)
              }.disabled(
                !store.canWrite
                  || !HabitSchedule.canMark(habit, on: store.today, today: store.today)
              )
              .accessibilityLabel(
                complete
                  ? store.text("Отменить выполнение", "Mark incomplete")
                  : store.text("Выполнить сегодня", "Complete today"))
            }
          }.buttonStyle(RitmPressStyle())
        }
        if !(habit.achievements ?? []).isEmpty {
          Label(
            (habit.achievements ?? []).sorted().map(String.init).joined(separator: " · ")
              + store.text(" дней", " days"), systemImage: "medal"
          ).font(.caption).foregroundStyle(.tint)
        }
      }
    }
    .sensoryFeedback(.success, trigger: complete) { _, new in new }
    .sheet(
      isPresented: Binding(get: { progressDate != nil }, set: { if !$0 { progressDate = nil } })
    ) { HabitProgressEditor(habit: habit, initialDate: progressDate ?? store.today) }
    .confirmationDialog(
      store.text("Удалить привычку и её историю?", "Delete this habit and its history?"),
      isPresented: $deleteConfirmation, titleVisibility: .visible
    ) {
      Button(store.text("Удалить навсегда", "Delete permanently"), role: .destructive) {
        Task {
          _ = await store.performMutation {
            try await $0.deleteHabit(id: habit.id, expectedUpdatedAt: habit.updatedAt)
          }
        }
      }
    }
  }
  private func toggle() async {
    if let updated = await store.write({
      try await $0.setHabitDay(
        id: habit.id, date: store.today, completed: !complete, expectedUpdatedAt: habit.updatedAt)
    }) {
      announceHabitAchievement(
        previous: habit, updated: updated, store: store, navigation: navigation)
    }
  }

}
struct HabitDayButton: View {
  @Environment(RitmStore.self) private var store
  @ScaledMetric(relativeTo: .caption) private var scaledHeight: CGFloat = 58
  let habit: Habit
  let date: String
  var height: CGFloat? = nil
  let onTap: () -> Void
  private var completed: Bool { HabitSchedule.isComplete(habit, on: date) }
  private var scheduled: Bool { HabitSchedule.isScheduled(habit, on: date) }
  var body: some View {
    Button(action: onTap) {
      VStack(spacing: 7) {
        Text(String(Int(date.suffix(2)) ?? 0)).font(.caption2)
        Image(
          systemName: completed ? "checkmark.circle.fill" : scheduled ? "circle" : "minus.circle"
        ).font(.system(size: 23)).opacity(scheduled ? 1 : 0.28)
      }.frame(width: 44, height: height ?? scaledHeight)
        .background(
          date == store.today ? RitmTheme.lavender.opacity(0.12) : .clear,
          in: RoundedRectangle(cornerRadius: 11)
        ).contentShape(Rectangle())
    }.buttonStyle(RitmPressStyle()).disabled(
      !store.canWrite || !HabitSchedule.canMark(habit, on: date, today: store.today)
    )
    .accessibilityLabel(
      habit.title + ", " + FeatureDate.label(date, zone: store.timeZone, language: store.language)
    )
    .accessibilityValue(
      completed
        ? store.text("Выполнено", "Completed")
        : scheduled
          ? store.text("Не выполнено", "Incomplete")
          : store.text("Не запланировано", "Not scheduled"))
  }
}
struct HabitWeeklyGrid: View {
  @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 58
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @State private var anchor = ""
  @State private var selected: Habit?
  @State private var selectedDate = ""
  private var days: [String] {
    HabitSchedule.week(containing: anchor.isEmpty ? store.today : anchor)
  }
  private var active: [Habit] { store.habits.filter { $0.archived != true } }
  var body: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text(store.text("Привычки на неделю", "Habits this week")).font(.headline)
          Spacer()
          Button {
            navigation.section = .habits
          } label: {
            Image(systemName: "arrow.up.right").frame(width: 44, height: 44)
          }.accessibilityLabel(store.text("Все привычки", "All habits"))
        }
        HStack {
          Button {
            shift(-7)
          } label: {
            Image(systemName: "chevron.left").frame(width: 44, height: 44)
          }.accessibilityLabel(store.text("Предыдущая неделя", "Previous week"))
          Text(
            days.first.map {
              FeatureDate.label(
                $0, zone: store.timeZone, language: store.language, template: "d MMM")
            } ?? ""
          ).font(.subheadline)
          Text("–")
          Text(
            days.last.map {
              FeatureDate.label(
                $0, zone: store.timeZone, language: store.language, template: "d MMM")
            } ?? ""
          ).font(.subheadline)
          Spacer(minLength: 0)
          Button {
            shift(7)
          } label: {
            Image(systemName: "chevron.right").frame(width: 44, height: 44)
          }.disabled((days.last ?? store.today) >= store.today).accessibilityLabel(
            store.text("Следующая неделя", "Next week"))
        }.buttonStyle(RitmPressStyle())
        if active.isEmpty {
          Text(
            store.text(
              "Добавьте привычку, чтобы видеть ритм недели.",
              "Add a habit to see your weekly rhythm.")
          ).font(.subheadline).foregroundStyle(.secondary)
        } else {
          HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
              Text(store.text("Привычки", "Habits")).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
              ForEach(active) { habit in
                HStack(spacing: 7) {
                  Image(systemName: habitSymbol(habit.icon)).foregroundStyle(.tint)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(habit.title).font(.caption.weight(.semibold)).lineLimit(2)
                    Text(
                      store.text("Серия: ", "Streak: ")
                        + "\(HabitSchedule.streak(habit, today: store.today))"
                    ).font(.system(size: 10)).foregroundStyle(.secondary)
                  }
                }.frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading).overlay(
                  alignment: .bottom
                ) { Divider() }
              }
            }.frame(width: 120)
            ScrollView(.horizontal) {
              VStack(spacing: 0) {
                HStack(spacing: 4) {
                  ForEach(days, id: \.self) { date in
                    Text(
                      FeatureDate.label(
                        date, zone: store.timeZone, language: store.language, template: "EE")
                    ).font(.caption2).frame(width: 44, height: 25)
                  }
                }
                ForEach(active) { habit in
                  HStack(spacing: 4) {
                    ForEach(days, id: \.self) { date in
                      HabitDayButton(habit: habit, date: date, height: rowHeight) {
                        selectedDate = date
                        selected = habit
                      }
                    }
                  }.overlay(alignment: .bottom) { Divider() }
                }
              }
            }.scrollIndicators(.hidden)
          }
        }
      }
    }.sheet(item: $selected) { HabitProgressEditor(habit: $0, initialDate: selectedDate) }
  }
  private func shift(_ days: Int) {
    anchor =
      HabitSchedule.addDays(to: anchor.isEmpty ? store.today : anchor, days: days) ?? store.today
  }
}
struct HabitEditor: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let habit: Habit?
  @State private var title: String
  @State private var icon: HabitIcon
  @State private var weekdays: Set<Int>
  @State private var quantitative: Bool
  @State private var target: String
  @State private var unit: String
  @State private var busy = false
  init(habit: Habit? = nil) {
    self.habit = habit
    _title = State(initialValue: habit?.title ?? "")
    _icon = State(initialValue: habit?.icon ?? .sparkles)
    _weekdays = State(initialValue: Set(habit?.weekdays ?? Array(0...6)))
    _quantitative = State(initialValue: habit?.target != nil)
    _target = State(initialValue: String(habit?.target ?? 1))
    _unit = State(initialValue: habit?.unit ?? "")
  }
  private var valid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf16.count <= 80
      && !weekdays.isEmpty && unit.utf16.count <= 24
      && (!quantitative || (1...10_000).contains(Int(target) ?? 0))
  }
  var body: some View {
    NavigationStack {
      Form {
        Section(store.text("Название", "Name")) {
          TextField(
            store.text("Например, чтение", "For example, reading"), text: $title, axis: .vertical
          ).lineLimit(2...4)
          Text("\(title.utf16.count) / 80").font(.caption).foregroundStyle(
            title.utf16.count > 80 ? Color.red : Color.secondary)
        }
        Section(store.text("Значок", "Icon")) {
          ScrollView(.horizontal) {
            HStack {
              ForEach(HabitIcon.allCases, id: \.self) { value in
                Button {
                  icon = value
                } label: {
                  Image(systemName: habitSymbol(value)).frame(width: 44, height: 44).background(
                    icon == value ? RitmTheme.lavender.opacity(0.23) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel(value.rawValue).accessibilityAddTraits(
                  icon == value ? .isSelected : [])
              }
            }
          }.scrollIndicators(.hidden)
        }
        Section(store.text("Дни недели", "Weekdays")) {
          ForEach(0..<7) { day in
            Toggle(
              weekdayName(day, russian: store.language == .ru),
              isOn: Binding(
                get: { weekdays.contains(day) },
                set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
          }
          if weekdays.isEmpty {
            Text(store.text("Выберите хотя бы один день.", "Choose at least one day."))
              .foregroundStyle(.red)
          }
        }
        Section {
          Toggle(store.text("Количественная цель", "Quantity target"), isOn: $quantitative)
          if quantitative {
            TextField(store.text("Цель (1–10000)", "Target (1–10000)"), text: $target).keyboardType(
              .numberPad)
            TextField(
              store.text("Единица: минуты, стаканы…", "Unit: minutes, glasses…"), text: $unit)
          }
        } footer: {
          Text(
            store.text(
              "Изменение расписания не переписывает прошлые отметки.",
              "Schedule changes preserve historical marks."))
        }
        if let message = store.errorMessage { Section { RitmErrorBanner(message: message) } }
        if store.uncertainWrite {
          Section {
            Button(store.text("Закрыть и проверить список", "Close and check list")) {
              dismiss()
            }
          }
        }
      }.scrollDismissesKeyboard(.interactively)
        .navigationTitle(
          habit == nil
            ? store.text("Новая привычка", "New habit")
            : store.text("Изменить привычку", "Edit habit")
        ).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(store.text("Отмена", "Cancel")) { dismiss() }.disabled(busy)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(store.text("Сохранить", "Save")) { Task { await save() } }.disabled(
              !valid || busy || !store.canWrite)
          }
        }.interactiveDismissDisabled(busy)
    }
  }
  private func save() async {
    busy = true
    defer { busy = false }
    let input = HabitInput(
      title: title.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon,
      weekdays: weekdays.sorted(), target: quantitative ? Int(target) : nil,
      unit: quantitative ? unit.trimmingCharacters(in: .whitespacesAndNewlines) : "",
      archived: habit?.archived ?? false)
    let result: Habit?
    if let habit {
      result = await store.write {
        try await $0.updateHabit(id: habit.id, habit: input, expectedUpdatedAt: habit.updatedAt)
      }
    } else {
      result = await store.write { try await $0.createHabit(input) }
    }
    if result != nil { dismiss() }
  }
}
struct HabitProgressEditor: View {
  @Environment(RitmNavigation.self) private var navigation
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let habit: Habit
  @State private var date: String
  @State private var count: String
  @State private var busy = false
  init(habit: Habit, initialDate: String) {
    self.habit = habit
    _date = State(initialValue: initialDate)
    _count = State(initialValue: String(HabitSchedule.progress(habit, on: initialDate)))
  }
  private var current: Habit { store.habits.first(where: { $0.id == habit.id }) ?? habit }
  private var valid: Bool {
    HabitSchedule.canMark(current, on: date, today: store.today)
      && (0...HabitSchedule.target(current)).contains(Int(count) ?? -1)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(current.title).font(.headline).textSelection(.enabled)
          DateKeyPicker(title: store.text("Дата", "Date"), value: $date, zone: store.timeZone)
        }
        Section {
          if current.target != nil {
            TextField(store.text("Количество", "Quantity"), text: $count).keyboardType(.numberPad)
            Text(
              store.text("Цель: ", "Target: ")
                + "\(HabitSchedule.target(current)) \(current.unit ?? "")"
            ).foregroundStyle(.secondary)
            HStack {
              Button(store.text("Выполнить цель", "Complete target")) {
                count = String(HabitSchedule.target(current))
              }.frame(minHeight: 44)
              Spacer()
              Button(store.text("Сбросить", "Reset")) { count = "0" }.frame(minHeight: 44)
            }
            Stepper(
              store.text("Изменить количество", "Adjust quantity"),
              value: Binding(get: { Int(count) ?? 0 }, set: { count = String($0) }),
              in: 0...HabitSchedule.target(current))
          } else {
            Toggle(
              store.text("Выполнено", "Completed"),
              isOn: Binding(get: { (Int(count) ?? 0) > 0 }, set: { count = $0 ? "1" : "0" }))
          }
          if !HabitSchedule.canMark(current, on: date, today: store.today) {
            Text(
              store.text(
                "В этот день отметка недоступна: проверьте расписание, дату и архив.",
                "This day cannot be marked. Check the schedule, date and archive.")
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
        if let error = store.errorMessage { Section { RitmErrorBanner(message: error) } }
        if store.uncertainWrite { Section { MutationRecoveryView() } }
      }
      .onChange(of: date) { _, value in count = String(HabitSchedule.progress(current, on: value)) }
      .navigationTitle(store.text("Отметка привычки", "Habit mark")).navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Отмена", "Cancel")) { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(store.text("Сохранить", "Save")) { Task { await save() } }.disabled(
            !store.canWrite || busy || !valid)
        }
      }.interactiveDismissDisabled(busy)
    }
  }
  private func save() async {
    guard let value = Int(count) else { return }
    busy = true
    defer { busy = false }
    let latest = current
    let result = await store.write {
      try await $0.setHabitProgress(
        id: latest.id, date: date, count: value, expectedUpdatedAt: latest.updatedAt)
    }
    if let result {
      announceHabitAchievement(
        previous: latest, updated: result, store: store, navigation: navigation)
      dismiss()
    }
  }
}
func habitSymbol(_ icon: HabitIcon?) -> String {
  switch icon ?? .sparkles {
  case .sparkles: "sparkles"
  case .book: "book"
  case .activity: "waveform.path.ecg"
  case .droplet: "drop"
  case .moon: "moon"
  case .target: "target"
  }
}
private func weekdayName(_ day: Int, russian: Bool) -> String {
  (russian
    ? ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"]
    : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"])[day]
}
private struct HabitDayReview: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let habits: [Habit]
  let date: String
  @State private var selected: Habit?
  private var planned: [Habit] { habits.filter { HabitSchedule.isScheduled($0, on: date) } }
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(FeatureDate.label(date, zone: store.timeZone, language: store.language)).font(
            .headline)
          let summary = HabitSchedule.daySummary(habits, on: date, today: store.today)
          Text(
            date > store.today
              ? store.text("Будущий день", "Future day")
              : "\(summary.completed) / \(summary.planned)"
          ).foregroundStyle(.secondary)
        }
        ForEach(planned) { habit in
          Button {
            selected = habit
          } label: {
            HStack {
              Image(
                systemName: HabitSchedule.isComplete(habit, on: date)
                  ? "checkmark.circle.fill" : "circle")
              VStack(alignment: .leading, spacing: 4) {
                Text(habit.title)
                Text(
                  "\(HabitSchedule.progress(habit, on: date)) / \(HabitSchedule.target(habit)) \(habit.unit ?? "")"
                ).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if HabitSchedule.canMark(habit, on: date, today: store.today) {
                Image(systemName: "pencil").font(.caption)
              }
            }.frame(minHeight: 44)
          }.disabled(!HabitSchedule.canMark(habit, on: date, today: store.today))
        }
        if planned.isEmpty {
          Text(
            store.text(
              "На эту дату привычки не запланированы.", "No habits are scheduled on this date.")
          ).foregroundStyle(.secondary)
        }
      }
      .navigationTitle(store.text("Привычки за день", "Habits for this day"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(store.text("Готово", "Done")) { dismiss() }
        }
      }
      .sheet(item: $selected) { HabitProgressEditor(habit: $0, initialDate: date) }
    }
  }
}
@MainActor private func announceHabitAchievement(
  previous: Habit, updated: Habit, store: RitmStore, navigation: RitmNavigation
) {
  let added = Set(updated.achievements ?? []).subtracting(previous.achievements ?? [])
  guard let milestone = added.max() else { return }
  navigation.habitCelebration =
    updated.title + store.text(": достижение ", ": achievement of ") + "\(milestone) "
    + store.text("дней", "days")
}
