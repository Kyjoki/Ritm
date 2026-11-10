import RitmCore
import SwiftUI

private struct HabitEditTarget: Identifiable {
  let habit: Habit?
  var id: String { habit?.id ?? "create" }
}

/// Which habit's analytics is open and which period and day the page was showing.
private struct HabitDetailTarget: Identifiable {
  let id: String
  let month: Bool
  let offset: Int
  let day: String
}

/// «Привычки»: the analytics card on top, the chosen day as a list of coloured cards, the
/// archive and «Награды».
struct HabitsView: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var editing: HabitEditTarget?
  @State private var detail: HabitDetailTarget?
  @State private var deleting: Habit?
  @State private var archiveOpen = false
  @State private var month = false
  @State private var offset = 0
  @State private var selectedDay: String?
  @State private var busyID: String?
  @State private var celebration: String?
  @State private var recordID: String?
  @State private var overviewCache = HabitOverviewCache()

  private var today: String { store.today }

  var body: some View {
    let active = store.habits.filter { $0.archived != true }
    let archived = store.habits.filter { $0.archived == true }
    return ZStack(alignment: .bottomTrailing) {
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
            loading
          } else {
            page(active: active, archived: archived)
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
    .onChange(of: store.habits.count) { _, _ in
      HabitStatsCache.shared.keep(Set(store.habits.map(\.id)))
    }
    .sheet(item: $editing) { target in HabitEditor(habit: target.habit) }
    .sheet(item: $detail) { target in
      HabitSheet(
        habitID: target.id, today: today, month: target.month, offset: target.offset,
        day: target.day,
        onProgress: { id, day, count in Task { await setProgress(id: id, day: day, count: count) } },
        onArchive: { habit in Task { await setArchived(habit, true) } })
    }
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

  // MARK: Page

  /// The title on the left and the 44 pt «+» on the right, with today's date under the title.
  private var heading: some View {
    VStack(alignment: .leading, spacing: 0) {
      RitmPageHeading(title: store.text("Привычки", "Habits"), gap: 2) {
        RitmIconCTA(symbol: "plus", label: store.text("Новая привычка", "New habit")) {
          store.errorMessage = nil
          editing = HabitEditTarget(habit: nil)
        }
      }
      Text(store.todayLabel.habitCapitalized)
        .ritmFont(13)
        .foregroundStyle(RitmTheme.muted)
        .padding(.bottom, 16)
    }
  }

  private var loading: some View {
    HStack(spacing: 9) {
      ProgressView().tint(RitmTheme.accentColor)
      Text(store.text("Загружаем…", "Loading…"))
    }
    .ritmFont(12)
    .foregroundStyle(RitmTheme.muted)
    .frame(maxWidth: .infinity, minHeight: 145)
    .background { RitmPanelBackground() }
  }

  @ViewBuilder private func page(active: [Habit], archived: [Habit]) -> some View {
    if active.isEmpty {
      emptyState(hasArchive: !archived.isEmpty).ritmPageReveal(index: 0)
    } else {
      let dates = HabitsPlan.periodDates(today: today, month: month, offset: offset)
      let day = effectiveDay(dates)
      let overview = overviewCache.overview(
        habits: active, today: today, month: month, offset: offset)
      let earliest = active.map(\.startDate).min() ?? today
      HabitsTopCard(
        overview: overview, month: month, offset: offset, selectedDay: day, today: today,
        canGoBack: (dates.first ?? "") > earliest,
        onMonth: { value in
          month = value
          offset = 0
          selectedDay = nil
        },
        onStep: { delta in
          offset = min(0, offset + delta)
          selectedDay = nil
        },
        onSelect: { selectedDay = $0 }
      )
      .ritmPageReveal(index: 0)
      dayHeading(active, day: day).ritmPageReveal(index: 1)
      list(active, day: day)
    }
    if !archived.isEmpty {
      HabitArchiveBlock(
        habits: archived, open: $archiveOpen, busy: busyID != nil,
        onRestore: { habit in Task { await setArchived(habit, false) } },
        onDelete: { deleting = $0 }
      )
      .padding(.top, 14)
    }
    if !active.isEmpty { awards(active) }
  }

  private func effectiveDay(_ dates: [String]) -> String {
    if let selectedDay, dates.contains(selectedDay) { return selectedDay }
    return HabitAnalytics.defaultDay(in: dates, today: today) ?? today
  }

  private func emptyState(hasArchive: Bool) -> some View {
    VStack(spacing: 9) {
      Text(store.text("Пока нет привычек", "No habits yet"))
        .ritmFont(16, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
      Text(
        hasArchive
          ? store.text(
            "Все привычки в архиве. Верните одну из них или добавьте новую.",
            "Every habit is archived. Restore one or add a new one.")
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
  }

  // MARK: Day list

  /// «Сегодня» or «Пятница, 6 нояб.» with how many of that day's habits are done.
  private func dayHeading(_ habits: [Habit], day: String) -> some View {
    let summary = HabitSchedule.daySummary(habits, on: day, today: today)
    let title =
      day == today
      ? store.text("Сегодня", "Today")
      : HabitDates.label(day, zone: store.timeZone, language: store.language, template: "EEEE, d MMM")
        .habitCapitalized
    return HStack(alignment: .firstTextBaseline) {
      Text(title)
        .ritmFont(18, weight: .semibold, tracking: -0.04)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
        .habitSwap(key: day)
      Spacer(minLength: 8)
      if summary.planned > 0 {
        HStack(spacing: 4) {
          RitmCountText(summary.completed) { "\($0)" }
          Text(store.text("из \(summary.planned)", "of \(summary.planned)"))
        }
        .ritmFont(12.5)
        .foregroundStyle(RitmTheme.muted)
        .accessibilityElement(children: .combine)
      }
    }
    .padding(.top, 20)
    .padding(.horizontal, 2)
    .padding(.bottom, 10)
  }

  /// The habits of the chosen day first, then the rest (their footer says «Не по расписанию»).
  @ViewBuilder private func list(_ habits: [Habit], day: String) -> some View {
    let linked = store.workouts.settings.linkedHabitID
    let ordered = habits.filter { isListed($0, on: day) } + habits.filter { !isListed($0, on: day) }
    // Cards compare by habit data only (`HabitCard ==`), so picking a day in the analytics
    // card rebuilds just the week strips that move.
    LazyVStack(spacing: 10) {
      ForEach(Array(ordered.enumerated()), id: \.element.id) { index, habit in
        HabitCard(
          habit: habit, day: day, today: today, busy: busyID != nil, isRecord: recordID == habit.id,
          isLinked: linked == habit.id, language: store.language,
          onOpen: {
            store.errorMessage = nil
            detail = HabitDetailTarget(id: habit.id, month: month, offset: offset, day: day)
          },
          onProgress: { tappedDay, count in
            Task { await setProgress(id: habit.id, day: tappedDay, count: count) }
          }
        )
        .equatable()
        .ritmPageReveal(index: 2 + index)
      }
    }
    .habitSwap(key: day)
  }

  private func isListed(_ habit: Habit, on day: String) -> Bool {
    HabitSchedule.isScheduled(habit, on: day) || HabitSchedule.canMark(habit, on: day, today: today)
  }

  // MARK: Awards

  private func awards(_ habits: [Habit]) -> some View {
    let sources = habits.map {
      (id: $0.id, title: $0.title, stats: HabitStatsCache.shared.stats(for: $0, today: today))
    }
    return VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Награды", "Awards"))
        .ritmFont(18, weight: .semibold, tracking: -0.04)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, 22)
        .padding(.horizontal, 2)
        .padding(.bottom, 10)
      HabitAwardsRow(
        awards: HabitAnalytics.awards(sources), goal: HabitAnalytics.closestGoal(sources),
        onOpen: { id in
          detail = HabitDetailTarget(
            id: id, month: month, offset: offset,
            day: effectiveDay(HabitsPlan.periodDates(today: today, month: month, offset: offset)))
        })
    }
    .ritmPageReveal(index: 8)
  }

  private func celebrationToast(_ text: String) -> some View {
    Label {
      Text(text)
    } icon: {
      RitmSymbol("sparkles").font(.system(size: 16))
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

  private func setProgress(id: String, day: String, count: Int) async {
    guard let habit = store.habits.first(where: { $0.id == id }) else { return }
    // The store shows the tick at once and sends it in the background; only the celebration
    // waits for the server's confirmation.
    guard HabitSchedule.canMark(habit, on: day, today: today),
      let tick = await store.tickHabit(id: habit.id, date: day, count: count),
      !HabitSchedule.isComplete(tick.before, on: day), HabitSchedule.isComplete(tick.after, on: day)
    else { return }
    let before = HabitSchedule.bestStreak(tick.before, today: today)
    let after = HabitSchedule.bestStreak(tick.after, today: today)
    if after > before { flashRecord(habit.id) }
    let level =
      HabitAnalytics.crossedLevel(bestBefore: before, bestAfter: after)
      ?? HabitsPlan.newMilestone(previous: tick.before, updated: tick.after)
    if let level {
      celebrate(
        store.text(
          "\(habit.title): достижение \(level) дней", "\(habit.title): \(level)-day achievement"))
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
