import Charts

import RitmCore

import SwiftUI

struct DayView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingCreate = false
  @State private var showingEventCreate = false
  @State private var selectedTask: RitmTask?
  @State private var selectedOccurrence: String?
  @State private var selectedEvent: GoogleCalendarEvent?
  @State private var taskDay = 0
  @State private var quickTitle = ""
  @State private var tomorrowEvents: [GoogleCalendarEvent] = []
  @State private var tomorrowLoaded = false
  @State private var tomorrowKey = ""
  @State private var visible = false
  private var tasks: [RitmTask] { store.bootstrap?.tasks ?? [] }
  private var selectedDate: String {
    taskDay == 0 ? store.today : HabitSchedule.addDays(to: store.today, days: 1) ?? store.today
  }
  private var occurrences: [TaskOccurrence] {
    TaskSchedule.dayOccurrences(tasks, date: selectedDate, language: store.language).filter {
      $0.task.kind == .task
    }
  }
  private var todayOccurrences: [TaskOccurrence] {
    TaskSchedule.dayOccurrences(tasks, date: store.today, language: store.language)
  }
  private var googleTasks: [GoogleCalendarEvent] {
    store.todayEvents.filter { eventIsToday($0) && ($0.taskLink == true || $0.googleTask != nil) }
  }
  private var selectedGoogleTasks: [GoogleCalendarEvent] {
    (taskDay == 0
      ? store.todayEvents.filter(eventIsToday) : tomorrowKey == selectedDate ? tomorrowEvents : [])
      .filter { $0.taskLink == true || $0.googleTask != nil }
  }
  private var progressUnknown: Bool { googleTasks.contains { $0.googleTask == nil } }
  private var todayTaskOccurrences: [TaskOccurrence] {
    todayOccurrences.filter { $0.task.kind == .task }
  }
  private var completedCount: Int {
    todayTaskOccurrences.filter(\.completed).count
      + googleTasks.filter { $0.googleTask?.status == "completed" }.count
  }
  private var taskCount: Int { todayTaskOccurrences.count + googleTasks.count }
  private var progress: Double {
    taskCount == 0 || progressUnknown ? 0 : Double(completedCount) / Double(taskCount)
  }
  private var currentMinute: Int {
    let calendar = FeatureDate.calendar(store.timeZone)
    return calendar.component(.hour, from: store.now) * 60
      + calendar.component(.minute, from: store.now)
  }
  private var scheduleEntries: [DayScheduleEntry] {
    let local = todayOccurrences.filter { $0.task.calendarEntry != false }.map { item in
      DayScheduleEntry(
        id: item.key, title: item.task.title, start: item.start, end: item.end,
        completed: item.completed, busy: !item.completed && item.start != nil, local: item,
        google: nil,
        timeLabel: item.start.map {
          FeatureDate.clock(TaskSchedule.minuteTime($0))
            + (item.end.map { " – " + FeatureDate.clock(TaskSchedule.minuteTime($0)) } ?? "")
            + (item.end == 1440 ? store.text(" · следующий день", " · next day") : "")
        } ?? store.text("Без времени", "No time"))
    }
    let google = store.todayEvents.compactMap { event -> DayScheduleEntry? in
      guard eventIsToday(event) else { return nil }
      let range = eventRange(event)
      guard event.allDay || range != nil else { return nil }
      return DayScheduleEntry(
        id: event.id, title: event.title, start: range?.0, end: range?.1,
        completed: event.googleTask?.status == "completed", busy: event.busy, local: nil,
        google: event,
        timeLabel: store.eventTimeText(event) + " · Google")
    }
    return (local + google).sorted {
      ($0.start ?? -1) == ($1.start ?? -1) ? $0.id < $1.id : ($0.start ?? -1) < ($1.start ?? -1)
    }
  }
  private var upcoming: DayScheduleEntry? {
    scheduleEntries.first { !$0.completed && $0.start != nil && ($0.end ?? -1) > currentMinute }
  }
  private func eventIsToday(_ event: GoogleCalendarEvent) -> Bool {
    if event.allDay {
      return (event.start.date ?? "9999") <= store.today && (event.end.date ?? "0000") > store.today
    }
    guard let start = FeatureDate.instant(event.start.dateTime),
      let end = FeatureDate.instant(event.end.dateTime), end > start
    else { return false }
    let calendar = FeatureDate.calendar(store.timeZone)
    let lower = calendar.startOfDay(for: store.now)
    guard let upper = calendar.date(byAdding: .day, value: 1, to: lower) else { return false }
    return start < upper && end > lower
  }
  private func eventRange(_ event: GoogleCalendarEvent) -> (Int, Int)? {
    guard !event.allDay, let start = FeatureDate.instant(event.start.dateTime),
      let end = FeatureDate.instant(event.end.dateTime)
    else { return nil }
    let calendar = FeatureDate.calendar(store.timeZone)
    func wallMinute(_ date: Date) -> Int {
      let key = HabitSchedule.dateKey(date, timeZone: store.timeZone)
      if key < store.today { return 0 }
      if key > store.today { return 1440 }
      return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
    let lower = wallMinute(start)
    let upper = wallMinute(end)
    // During a repeated DST hour preserve positive duration rather than reversing the interval.
    return (
      lower,
      upper > lower ? upper : min(1440, lower + max(1, Int(end.timeIntervalSince(start) / 60)))
    )
  }
  private func open(_ entry: DayScheduleEntry) {
    if let event = entry.google {
      selectedEvent = event
    } else if let item = entry.local {
      selectedOccurrence = item.date
      selectedTask = item.task
    }
  }
  private var workStart: Int {
    TaskSchedule.timeMinutes(store.bootstrap?.settings.workDayStart ?? "09:00") ?? 540
  }
  private var workEnd: Int {
    TaskSchedule.timeMinutes(store.bootstrap?.settings.workDayEnd ?? "18:00") ?? 1080
  }
  private var busyIntervals: [(Int, Int)] {
    scheduleEntries.filter { $0.busy && !$0.completed }.map { ($0.start ?? 0, $0.end ?? 1440) }
  }
  private var freeMinutes: Int {
    let calendar = FeatureDate.calendar(store.timeZone)
    let current =
      calendar.component(.hour, from: store.now) * 60 + calendar.component(.minute, from: store.now)
    let lower = max(workStart, current)
    guard lower < workEnd else { return 0 }
    var occupied = Set<Int>()
    for (start, end) in busyIntervals where end > start {
      let a = max(lower, start)
      let b = min(workEnd, end)
      if a < b { occupied.formUnion(a..<b) }
    }
    return max(0, workEnd - lower - occupied.count)
  }
  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          RitmShellHeader().padding(.bottom, -16)
          header
          SyncStatusView()
          if let message = store.errorMessage { RitmErrorBanner(message: message) }
          MutationRecoveryView()
          if store.bootstrap == nil {
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
          } else {
            progressCard
            upcomingCard
            assistantCard
            tasksCard
            scheduleCard
            HabitWeeklyGrid()
          }
          RitmPageFooter()
        }.padding(.horizontal, 16).padding(.bottom, 28).frame(maxWidth: 700)
          .frame(maxWidth: .infinity)
      }.refreshable {
        await store.refresh()
        await loadTomorrow()
      }.scrollDismissesKeyboard(.interactively)
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { visible = navigation.section == .day }.onDisappear { visible = false }
    .onChange(of: navigation.section) { _, value in
      visible = value == .day
      if visible { Task { await loadTomorrow() } }
    }
    .task(id: selectedDate) { await loadTomorrow() }
    .onChange(of: store.lastSyncedAt) { _, _ in if visible { Task { await loadTomorrow() } } }
    .sheet(isPresented: $showingCreate) { NativeTaskEditor(initialDate: selectedDate) }
    .sheet(isPresented: $showingEventCreate) { CalendarEventEditor(initialDate: store.today) }
    .sheet(item: $selectedTask) {
      NativeTaskEditor(task: $0, initialDate: selectedDate, occurrenceDate: selectedOccurrence)
    }
    .sheet(item: $selectedEvent) { CalendarEventDetail(event: $0) }
  }
  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(store.todayLabel + store.text(" · Мой день", " · My day")).font(
        .caption.weight(.semibold)
      ).foregroundStyle(.tint)
      HStack(alignment: .top) {
        Text(greeting).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 4)
        Menu {
          Button(store.text("Задача", "Task"), systemImage: "checklist") { showingCreate = true }
          Button(store.text("Событие Google", "Google event"), systemImage: "calendar.badge.plus") {
            showingEventCreate = true
          }
        } label: {
          Image(systemName: "plus.circle").font(.title2).frame(width: 48, height: 48).background(
            RitmTheme.lavender.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!store.canWrite).accessibilityLabel(store.text("Добавить запись", "Add entry"))
      }
      Text(
        store.text(
          "Ваши дела. Ваш темп. Один ясный план.", "Your tasks. Your pace. One clear plan.")
      ).font(.subheadline).foregroundStyle(.secondary)
    }
  }
  private var greeting: String {
    let hour = FeatureDate.calendar(store.timeZone).component(.hour, from: store.now)
    let base =
      hour < 12
      ? store.text("Доброе утро", "Good morning")
      : hour < 18
        ? store.text("Добрый день", "Good afternoon") : store.text("Добрый вечер", "Good evening")
    let name =
      store.bootstrap?.settings.displayName.split(separator: " ").first.map(String.init) ?? ""
    return base + (name.isEmpty ? "" : ", " + name)
  }
  private var progressCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 18) {
        Text(store.text("Твой прогресс", "Your progress")).font(.subheadline).foregroundStyle(
          .secondary)
        HStack(spacing: 18) {
          ZStack {
            Circle().stroke(RitmTheme.lavender.opacity(0.14), lineWidth: 7)
            Circle().trim(from: 0, to: progress).stroke(
              RitmTheme.lavender, style: StrokeStyle(lineWidth: 7, lineCap: .round)
            ).rotationEffect(.degrees(-90))
              .animation(
                visible && !reduceMotion ? .easeInOut(duration: 0.3) : nil, value: progress)
            Image(
              systemName: taskCount > 0 && completedCount == taskCount && !progressUnknown
                ? "checkmark" : "sparkles"
            ).font(.title2).foregroundStyle(.tint)
          }.frame(width: 64, height: 64).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 6) {
            Text(
              progressUnknown
                ? "—" : "\(completedCount) " + store.text("из ", "of ") + "\(taskCount)"
            ).font(.title.bold()).monospacedDigit()
            Text(
              progressUnknown
                ? store.text("Уточняем статус Google Tasks", "Checking Google Tasks status")
                : store.text("задач выполнено", "tasks complete")
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
        Chart(9..<22, id: \.self) { hour in
          let busy = busyIntervals.reduce(into: Set<Int>()) { value, range in
            let a = max(hour * 60, range.0)
            let b = min((hour + 1) * 60, range.1)
            if a < b { value.formUnion(a..<b) }
          }.count
          AreaMark(x: .value("Hour", hour), y: .value("Busy minutes", busy)).foregroundStyle(
            RitmTheme.lavender.opacity(0.12))
          LineMark(x: .value("Hour", hour), y: .value("Busy minutes", busy)).foregroundStyle(
            RitmTheme.lavender
          ).lineStyle(StrokeStyle(lineWidth: 2))
        }.chartYScale(domain: 0...60).chartYAxis(.hidden)
          .chartXAxis {
            AxisMarks(values: [9, 15, 21]) { value in
              if let hour = value.as(Int.self) {
                AxisValueLabel(hour == 9 ? "9 AM" : hour == 15 ? "3 PM" : "9 PM")
              }
            }
          }
          .frame(height: 70).accessibilityLabel(
            store.text("Занятые минуты по часам", "Busy minutes by hour"))
        Text(
          !store.calendarReady || store.calendarPartial
            ? store.calendarStatusText
            : freeMinutes > 0
              ? store.text(
                "Свободно до конца рабочего дня: ", "Free until the end of your workday: ")
                + "\(freeMinutes / 60) " + store.text("ч ", "h ") + "\(freeMinutes % 60) "
                + store.text("мин", "min")
              : store.text(
                "Рабочий день завершён или занят", "Your workday has ended or is fully booked")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var upcomingCard: some View {
    Button {
      if let upcoming { open(upcoming) } else { navigation.section = .calendar }
    } label: {
      VStack(alignment: .leading, spacing: 16) {
        Text(store.text("Ближайшее событие", "Next event")).font(.caption.weight(.semibold))
        Text(
          upcoming?.title
            ?? (!store.calendarReady || store.calendarPartial
              ? store.text("Расписание", "Schedule") : store.text("Без спешки", "No rush"))
        ).font(.title.bold()).multilineTextAlignment(.leading)
        Text(
          upcoming?.timeLabel
            ?? (store.calendarReady && !store.calendarPartial
              ? store.text("Впереди свободное время", "There is free time ahead")
              : store.calendarStatusText)
        ).font(.subheadline).multilineTextAlignment(.leading)
        HStack {
          Text(store.text("Открыть календарь", "Open calendar")).font(.caption)
          Spacer()
          Image(systemName: "arrow.up.right")
        }.padding(.top, 16)
      }.padding(20).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
        .background(
          LinearGradient(
            colors: [
              Color(red: 0.34, green: 0.21, blue: 0.52), Color(red: 0.55, green: 0.37, blue: 0.74),
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
          in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.22), lineWidth: 1))
    }.buttonStyle(RitmPressStyle())
  }
  private var assistantCard: some View {
    RitmCard(delay: 0.08) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
          Circle().stroke(RitmTheme.lavender.gradient, lineWidth: 6).frame(width: 30, height: 30)
          Text(store.text("Помощник Ritm", "Ritm assistant")).font(.headline)
        }
        Text(
          store.text(
            "Поможет собрать удобный план и оставить время для себя.",
            "Build a comfortable plan and leave time for yourself.")
        ).font(.subheadline).foregroundStyle(.secondary)
        Button {
          navigation.assistantPrompt = store.text(
            "Помоги спланировать мой день с учётом задач и расписания.",
            "Help me plan my day around my tasks and schedule.")
          navigation.section = .assistant
        } label: {
          Label(store.text("Спланировать день", "Plan my day"), systemImage: "arrow.up.right").font(
            .subheadline
          ).frame(minHeight: 44)
        }.buttonStyle(.bordered)
      }
    }
  }
  private var tasksCard: some View {
    RitmCard(delay: 0.12) {
      VStack(alignment: .leading, spacing: 14) {
        Text(store.text("Задачи на день", "Daily tasks")).font(.title3.bold())
        Picker(store.text("День задач", "Task day"), selection: $taskDay) {
          Text(store.text("Сегодня", "Today")).tag(0)
          Text(store.text("Завтра", "Tomorrow")).tag(1)
        }.pickerStyle(.segmented)
        HStack(spacing: 8) {
          TextField(
            store.text("Что нужно сделать?", "What needs to be done?"), text: $quickTitle,
            axis: .vertical
          ).lineLimit(1...3).textFieldStyle(.roundedBorder)
          Button {
            Task { await createQuickTask() }
          } label: {
            Image(systemName: "plus.circle").font(.title2).frame(width: 44, height: 44)
          }
          .disabled(
            !store.canWrite || quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || quickTitle.utf16.count > 160
          )
          .accessibilityLabel(store.text("Добавить задачу", "Add task"))
        }
        Text(
          store.text(
            "Быстрая задача сохраняется в списке, без записи в календаре.",
            "Quick tasks stay in your list without adding a calendar event.")
        ).font(.caption).foregroundStyle(.secondary)
        ForEach(occurrences) { occurrence in
          HStack(alignment: .top, spacing: 8) {
            Button {
              Task { await toggle(occurrence) }
            } label: {
              Image(systemName: occurrence.completed ? "checkmark.circle.fill" : "circle").font(
                .system(size: 24)
              ).frame(width: 44, height: 44)
            }.buttonStyle(RitmPressStyle()).disabled(!store.canWrite)
              .accessibilityLabel(
                occurrence.completed
                  ? store.text("Отменить выполнение: ", "Mark incomplete: ") + occurrence.task.title
                  : store.text("Выполнить: ", "Complete: ") + occurrence.task.title)
            Button {
              selectedOccurrence = occurrence.date
              selectedTask = occurrence.task
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Text(occurrence.task.title).font(.subheadline.weight(.semibold)).strikethrough(
                  occurrence.completed
                ).multilineTextAlignment(.leading)
                Text(taskMeta(occurrence.task)).font(.caption).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).foregroundStyle(
                .primary)
            }.buttonStyle(RitmPressStyle())
          }
          Divider().opacity(0.5)
        }
        ForEach(selectedGoogleTasks) { event in
          HStack(spacing: 8) {
            Button {
              Task {
                _ = await store.write {
                  try await $0.completeGoogleTask(
                    event: event, completed: event.googleTask?.status != "completed")
                }
                await loadTomorrow()
              }
            } label: {
              Image(
                systemName: event.googleTask?.status == "completed"
                  ? "checkmark.circle.fill"
                  : event.googleTask == nil ? "questionmark.circle" : "circle"
              ).font(.system(size: 24)).frame(width: 44, height: 44)
            }
            .disabled(!store.canWrite || event.googleTask == nil).accessibilityLabel(event.title)
            Button {
              selectedEvent = event
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(
                  .leading)
                Text(
                  event.googleTask == nil
                    ? store.text("Статус Google Tasks неизвестен", "Google Tasks status is unknown")
                    : "Google Tasks"
                ).font(.caption).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).foregroundStyle(
                .primary)
            }
          }.buttonStyle(RitmPressStyle())
        }
        if taskDay == 1 && (!tomorrowLoaded || tomorrowKey != selectedDate) {
          Text(
            store.text(
              "Расписание Google на завтра пока не загружено.",
              "Tomorrow's Google schedule is not loaded yet.")
          ).font(.caption).foregroundStyle(.secondary)
        }
        if occurrences.isEmpty && selectedGoogleTasks.isEmpty {
          Text(store.text("В списке пока нет задач.", "No tasks in this list yet.")).font(
            .subheadline
          ).foregroundStyle(.secondary).padding(.vertical, 10)
        }
      }
    }
  }
  private var scheduleCard: some View {
    RitmCard(delay: 0.16) {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text(store.text("Расписание", "Schedule")).font(.title3.bold())
          Spacer()
          Button {
            navigation.section = .calendar
          } label: {
            Label(store.text("Сегодня", "Today"), systemImage: "arrow.up.right").font(.caption)
              .frame(minHeight: 44)
          }
        }
        if !store.calendarStatusText.isEmpty {
          Text(store.calendarStatusText).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(scheduleEntries) { entry in
          Button {
            open(entry)
          } label: {
            VStack(alignment: .leading, spacing: 5) {
              Text(entry.title).font(.subheadline.weight(.medium)).strikethrough(entry.completed)
              Text(entry.timeLabel).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
              .background(
                CalendarPalette.color(entry.local?.task.colorId ?? entry.google?.colorId).opacity(
                  0.18), in: RoundedRectangle(cornerRadius: 14)
              ).foregroundStyle(.primary)
          }.buttonStyle(RitmPressStyle())
        }
        if scheduleEntries.isEmpty {
          Text(
            store.calendarReady && !store.calendarPartial
              ? store.text("Свободное расписание", "Your schedule is clear")
              : store.text("Уточняем расписание", "Checking your schedule")
          ).foregroundStyle(.secondary).font(.subheadline)
          Button(store.text("Найти удобное время", "Find a good time")) {
            navigation.assistantPrompt = store.text(
              "Найди свободное время в моём расписании на сегодня.",
              "Find free time in my schedule today.")
            navigation.section = .assistant
          }.frame(minHeight: 44)
        }
        Divider()
        backlog(
          title: store.text("Без даты", "Undated"),
          items: tasks.filter { $0.date == nil && !$0.completed })
        backlog(
          title: store.text("Просрочено", "Overdue"),
          items: tasks.filter {
            $0.repeat == .none && $0.date != nil && $0.date! < store.today && !$0.completed
          })
      }
    }
  }
  @ViewBuilder private func backlog(title: String, items: [RitmTask]) -> some View {
    Text(title + " · \(items.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    if items.isEmpty {
      Text(store.text("Всё в порядке", "All clear")).font(.caption).foregroundStyle(.secondary)
    }
    ForEach(items) { task in
      Button {
        selectedOccurrence = task.date
        selectedTask = task
      } label: {
        Text(task.title).font(.subheadline).multilineTextAlignment(.leading).frame(
          maxWidth: .infinity, minHeight: 44, alignment: .leading)
      }.buttonStyle(RitmPressStyle())
    }
  }
  private func taskMeta(_ task: RitmTask) -> String {
    let priority =
      task.priority == .high
      ? store.text("Высокий приоритет", "High priority")
      : task.priority == .low
        ? store.text("Низкий приоритет", "Low priority")
        : store.text("Обычный приоритет", "Normal priority")
    return (task.time.map { FeatureDate.clock($0) + " · " } ?? "") + priority
      + (task.repeat == .none ? "" : " · ↻")
  }
  private func createQuickTask() async {
    let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title.utf16.count <= 160 else { return }
    let input = TaskInput(title: title, date: selectedDate, calendarEntry: false)
    if await store.write({ try await $0.createTask(input) }) != nil { quickTitle = "" }
  }
  private func toggle(_ item: TaskOccurrence) async {
    _ = await store.write {
      try await $0.setTaskCompleted(
        id: item.task.id, completed: !item.completed,
        occurrenceDate: item.task.repeat == .none ? nil : item.date)
    }
  }
  private func loadTomorrow() async {
    guard taskDay == 1, navigation.section == .day else { return }
    let date = selectedDate
    let zone = store.timeZone
    let result = await store.read {
      try await $0.googleEvents(
        from: date, to: HabitSchedule.addDays(to: date, days: 1) ?? date, timeZone: zone)
    }
    guard date == selectedDate else { return }
    if let result {
      tomorrowEvents = result.events
      tomorrowLoaded = !result.partial
      tomorrowKey = date
    }
  }
}
private struct DayScheduleEntry: Identifiable {
  let id: String
  let title: String
  let start: Int?
  let end: Int?
  let completed: Bool
  let busy: Bool
  let local: TaskOccurrence?
  let google: GoogleCalendarEvent?
  let timeLabel: String
}
