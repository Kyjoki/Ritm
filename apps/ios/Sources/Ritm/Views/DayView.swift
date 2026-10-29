import RitmCore
import SwiftUI

/// «Мой день»: src/components/DashboardPage.tsx as it lays out at 390 px.
struct DayView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @State private var showingEventCreate = false
  @State private var selectedTask: RitmTask?
  @State private var selectedOccurrence: String?
  @State private var selectedEvent: GoogleCalendarEvent?
  @State private var tomorrow = false
  @State private var tomorrowEvents: [GoogleCalendarEvent] = []
  @State private var tomorrowLoaded = false
  @State private var tomorrowKey = ""
  @State private var tomorrowFailed = false
  @State private var visible = false

  private var tasks: [RitmTask] { store.bootstrap?.tasks ?? [] }
  private var now: Int { store.minuteOfDay }
  private var taskDate: String {
    tomorrow ? HabitSchedule.addDays(to: store.today, days: 1) ?? store.today : store.today
  }

  /// Today's calendar entries from Ritm and Google, as the schedule and the cards see them.
  private var combined: [DayOccurrence] {
    DayPlan.occurrences(
      tasks: tasks, events: store.todayEvents, date: store.today, timeZone: store.timeZone,
      language: store.language)
  }

  private var workStart: Int {
    TaskSchedule.timeMinutes(store.bootstrap?.settings.workDayStart ?? "09:00") ?? 540
  }
  private var workEnd: Int {
    TaskSchedule.timeMinutes(store.bootstrap?.settings.workDayEnd ?? "18:00") ?? 1080
  }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          RitmShellHeader()
          heading
          notices
          if store.bootstrap == nil {
            loadingCard
          } else {
            content
          }
          RitmPageFooter()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .refreshable {
        await store.refresh()
        await loadTomorrow()
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { visible = navigation.section == .day }
    .onDisappear { visible = false }
    .onChange(of: navigation.section) { _, value in
      visible = value == .day
      if visible { Task { await loadTomorrow() } }
    }
    .task(id: taskDate) { await loadTomorrow() }
    .onChange(of: store.lastSyncedAt) { _, _ in if visible { Task { await loadTomorrow() } } }
    .sheet(isPresented: $showingEventCreate) { CalendarEventEditor(initialDate: store.today) }
    .sheet(item: $selectedTask) {
      NativeTaskEditor(task: $0, initialDate: taskDate, occurrenceDate: selectedOccurrence)
    }
    .sheet(item: $selectedEvent) { CalendarEventDetail(event: $0) }
  }

  private var heading: some View {
    let hour = FeatureDate.calendar(store.timeZone).component(.hour, from: store.now)
    let name =
      store.bootstrap?.settings.displayName.split(separator: " ").first.map(String.init) ?? ""
    let greeting = DayPlan.greeting(hour: hour, language: store.language)
    return RitmPageHeading(
      eyebrow: store.todayLabel + " · " + store.text("Мой день", "My day"),
      title: name.isEmpty ? greeting : greeting + ", " + name,
      description: store.text(
        "Ваши дела. Ваш темп. Один ясный план.", "Your tasks. Your pace. One clear plan.")
    ) {
      RitmIconCTA(symbol: "plus.circle", label: store.text("Добавить запись", "Add entry")) {
        addEntry()
      }
    }
  }

  @ViewBuilder private var notices: some View {
    if store.isOffline { SyncStatusView().padding(.bottom, 12) }
    if let message = store.errorMessage { RitmErrorBanner(message: message).padding(.bottom, 12) }
    if store.uncertainWrite { MutationRecoveryView().padding(.bottom, 12) }
  }

  private var loadingCard: some View {
    RitmCard {
      if store.isLoading {
        ProgressView(store.text("Загружаем ваш день…", "Loading your day…"))
      } else {
        RitmEmptyState(
          symbol: "arrow.triangle.2.circlepath",
          title: store.text("День пока недоступен", "Your day is unavailable"),
          message: store.text("Потяните вниз, чтобы повторить.", "Pull down to try again."))
      }
    }
  }

  private var content: some View {
    let entries = combined
    let today = DayTaskSummary(
      tasks: tasks, events: store.todayEvents, date: store.today, timeZone: store.timeZone,
      language: store.language)
    return VStack(alignment: .leading, spacing: 0) {
      VStack(spacing: 12) {
        progressCard(entries, today: today)
        focusCard(entries)
        DayAssistantCard {
          ask(
            store.text(
              "Спланируй мой день с учётом приоритетов и свободного времени.",
              "Plan my day around my priorities and available time."))
        }
      }
      .padding(.bottom, 14)
      VStack(spacing: 12) {
        DayTasksPanel(
          tomorrow: $tomorrow, date: taskDate, summary: tomorrow ? listSummary : today,
          pending: listPending, uncertain: listUncertain,
          onOpenTask: openTask, onOpenEvent: { selectedEvent = $0 },
          onCalendar: { navigation.section = .calendar },
          onSettings: { navigation.section = .settings },
          onGoogleChanged: { await loadTomorrow() })
        DaySchedulePanel(
          entries: entries, onOpen: open, onCalendar: { navigation.section = .calendar },
          onAsk: ask, onOpenTask: { openTask($0, nil) })
      }
      DayHabitsCard().padding(.top, 17)
      bottomLine(today)
      DayAssistantDock { ask(nil) }.padding(.top, 17)
    }
  }

  /// The task list for tomorrow uses the separately loaded Google events of that day.
  private var listSummary: DayTaskSummary {
    DayTaskSummary(
      tasks: tasks, events: tomorrowKey == taskDate ? tomorrowEvents : [], date: taskDate,
      timeZone: store.timeZone, language: store.language)
  }
  private var tomorrowMissing: Bool {
    tomorrow && store.googleConnected && tomorrowKey != taskDate
  }
  /// A failed tomorrow read leaves the list «not checked» instead of loading forever.
  private var listPending: Bool { store.googlePending || (tomorrowMissing && !tomorrowFailed) }
  private var listUncertain: Bool {
    store.googleUncertain || tomorrowMissing
      || (tomorrow && store.googleConnected && !tomorrowLoaded)
  }

  private func progressCard(_ entries: [DayOccurrence], today: DayTaskSummary) -> some View {
    let pending = store.googlePending
    let uncertain = store.googleUncertain
    let free = DayPlan.freeMinutes(entries, workStart: workStart, workEnd: workEnd, now: now)
    let value: String
    let caption: String
    if today.unknown > 0 {
      value = "—"
      caption = store.text("Статус Google Tasks не проверен", "Google Tasks status not checked")
    } else if pending && today.count == 0 {
      value = "…"
      caption = store.text("Загружаем задачи", "Loading tasks")
    } else if today.count > 0 {
      value = store.text("\(today.completed) из \(today.count)", "\(today.completed) of \(today.count)")
      caption = store.text("задач выполнено", "tasks completed")
    } else if uncertain {
      value = "—"
      caption = store.text("Данные Google не проверены", "Google data not checked")
    } else {
      value = store.text("Нет задач", "No tasks")
      caption = store.text("на сегодня", "for today")
    }
    let footnote: String
    if uncertain {
      footnote = store.text("Уточняем расписание Google", "Checking Google’s schedule")
    } else if free > 0 {
      let duration = DayPlan.durationText(free, language: store.language)
      footnote = store.text("Свободно \(duration)", "\(duration) free")
    } else if now >= workEnd {
      footnote = store.text("Рабочий день завершён", "Your workday is over")
    } else {
      footnote = store.text("Всё время уже в плане", "Your time is fully scheduled")
    }
    return DayProgressCard(
      progress: today.count > 0 && today.unknown == 0
        ? Double(today.completed) / Double(today.count) : 0,
      value: value, caption: caption, rhythm: DayPlan.rhythm(entries), footnote: footnote)
  }

  private func focusCard(_ entries: [DayOccurrence]) -> some View {
    let upcoming = DayPlan.upcoming(entries, now: now)
    let uncertain = store.googleUncertain
    let eyebrow: String
    if let start = upcoming?.start, start <= now {
      eyebrow = store.text("Сейчас в плане", "Happening now")
    } else if uncertain {
      eyebrow = store.text("Ближайшая известная запись", "Next known entry")
    } else {
      eyebrow = store.text("Ближайшее событие", "Next event")
    }
    let time: String
    let name: String
    let meta: String
    if let upcoming, let start = upcoming.start {
      time = DayPlan.clock(start)
      name = upcoming.title
      let source: String
      if upcoming.event != nil {
        source = "Google Calendar"
      } else if upcoming.task?.task.kind == .event {
        source = store.text("Событие", "Event")
      } else {
        source = store.text("Задача", "Task")
      }
      meta = DayPlan.durationText(upcoming.duration, language: store.language) + " · " + source
    } else {
      if store.googlePending && entries.isEmpty {
        time = store.text("Проверяем…", "Checking…")
      } else if uncertain {
        time = store.text("Нет данных", "No data")
      } else {
        time = store.text("Без спешки", "Take your time")
      }
      name =
        uncertain
        ? store.text("События Google пока не загружены", "Google events have not loaded yet")
        : store.text("Впереди свободное время", "Free time ahead")
      meta = store.text("Открыть календарь", "Open calendar")
    }
    return DayFocusCard(eyebrow: eyebrow, time: time, name: name, meta: meta) {
      if let upcoming { open(upcoming) } else { navigation.section = .calendar }
    }
  }

  private func bottomLine(_ today: DayTaskSummary) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label {
        Text(
          today.count > 0 && today.completed == today.count
            ? store.text("Все дела завершены. Можно выдохнуть.", "Everything is done. Take a breath.")
            : store.text(
              "Следуйте своему темпу — всё важное перед вами.",
              "Go at your own pace — everything important is here."))
      } icon: {
        Image(systemName: "checklist").font(.system(size: 12))
      }
      .ritmFont(10, lineSpacing: 5)
      .foregroundStyle(RitmTheme.muted)
      Button {
        ask(
          store.text(
            "Найди свободное время в моём расписании на сегодня.",
            "Find free time in my schedule today."))
      } label: {
        Label(store.text("Найти свободное время", "Find free time"), systemImage: "clock")
      }
      .buttonStyle(RitmTextButtonStyle())
    }
    .padding(.top, 15)
  }

  // MARK: - Actions

  /// The web «+» opens a Google event for today at 09:00, 30 minutes, and needs Google.
  private func addEntry() {
    guard store.googleConnected else {
      store.errorMessage = store.text(
        "Подключи Google Calendar в настройках, чтобы добавить запись.",
        "Connect Google Calendar in Settings to add an entry.")
      navigation.section = .settings
      return
    }
    showingEventCreate = true
  }

  private func ask(_ prompt: String?) {
    navigation.assistantPrompt = prompt
    navigation.section = .assistant
  }

  private func openTask(_ task: RitmTask, _ occurrence: String?) {
    selectedOccurrence = occurrence ?? task.date
    selectedTask = task
  }

  private func open(_ entry: DayOccurrence) {
    if let event = entry.event {
      selectedEvent = event
    } else if let item = entry.task {
      openTask(item.task, item.date)
    }
  }

  private func loadTomorrow() async {
    guard tomorrow, navigation.section == .day, store.googleConnected else { return }
    let date = taskDate
    let zone = store.timeZone
    let result = await store.read {
      try await $0.googleEvents(
        from: date, to: HabitSchedule.addDays(to: date, days: 1) ?? date, timeZone: zone)
    }
    guard date == taskDate else { return }
    guard let result else {
      tomorrowFailed = true
      return
    }
    tomorrowFailed = false
    tomorrowEvents = result.events
    tomorrowLoaded = !result.partial
    tomorrowKey = date
  }
}

