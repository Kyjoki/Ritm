import RitmCore
import SwiftUI

// «Задачи» and «Расписание» on «Мой день» (DashboardPage.tsx .day-work-grid), stacked as on a
// phone: app.css .tasks-panel/.schedule-panel at max-width 760 px.

private struct DayPanelSurface: ViewModifier {
  var reveal: Int

  func body(content: Content) -> some View {
    content
      .padding(.vertical, 19)
      .padding(.horizontal, 17)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background { RitmPanelBackground() }
      .ritmPageReveal(index: reveal)
  }
}

private struct DayDivider: View {
  var body: some View { Rectangle().fill(RitmTheme.line).frame(height: 1) }
}

/// `.sd-chk i`: a 20 pt rounded square that fills with the accent when done.
private struct DayCheckbox: View {
  let done: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: 6, style: .circular)
      .fill(done ? RitmTheme.accentColor : Color.clear)
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .circular)
          .strokeBorder(done ? RitmTheme.accentColor : Color(rgb: 0x89729F), lineWidth: 1.5)
      }
      .overlay {
        if done {
          RitmSymbol("checkmark")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(RitmTheme.accentInk)
        }
      }
      .frame(width: 20, height: 20)
  }
}

/// `.sd-add button` / `.sd-wb i`: a bordered rounded square on the raised glass fill, no live glass.
struct DaySquareButtonLabel: View {
  let symbol: String
  var size: CGFloat = 44
  var radius: CGFloat = 13
  var iconSize: CGFloat = 20
  var weight: Font.Weight = .light
  var tint: Color = RitmTheme.accentColor

  var body: some View {
    RitmSymbol(symbol)
      .font(.system(size: iconSize, weight: weight))
      .foregroundStyle(tint)
      .frame(width: size, height: size)
      .background {
        RoundedRectangle(cornerRadius: radius, style: .circular)
          .fill(RitmTheme.glassRaised)
          .overlay {
            RoundedRectangle(cornerRadius: radius, style: .circular)
              .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
          }
      }
  }
}

struct DayTasksPanel: View {
  @Binding var tomorrow: Bool
  let date: String
  let summary: DayTaskSummary
  let pending: Bool
  let uncertain: Bool
  let onOpenTask: (RitmTask, String?) -> Void
  let onOpenEvent: (GoogleCalendarEvent) -> Void
  let onCalendar: () -> Void
  let onSettings: () -> Void
  let onGoogleChanged: () async -> Void
  @Environment(RitmStore.self) private var store
  @State private var quickTitle = ""
  @State private var quickBusy = false
  @State private var quickError: String?
  @State private var busyTasks: Set<String> = []
  @State private var busyGoogle: Set<String> = []

  private var trimmedTitle: String { quickTitle.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Text(
          tomorrow
            ? store.text("Задачи на завтра", "Tomorrow’s tasks")
            : store.text("Задачи на сегодня", "Today’s tasks")
        )
        .ritmFont(15, weight: .semibold, tracking: -0.025)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
        counterText.ritmFont(10).foregroundStyle(RitmTheme.muted)
      }
      .padding(.bottom, 14)
      dayPicker.padding(.bottom, 14)
      quickAdd
      Text(
        store.text(
          "Только в списке задач — без записи в календаре.", "Task list only — no calendar entry.")
      )
      .ritmFont(11, lineSpacing: 4)
      .foregroundStyle(RitmTheme.muted)
      .padding(.top, 8)
      if let quickError { RitmErrorBanner(message: quickError).padding(.top, 8) }
      list
      permission
    }
    .modifier(DayPanelSurface(reveal: 3))
  }

  /// «3 из 5» counts its first number; the other states are plain text.
  @ViewBuilder private var counterText: some View {
    if summary.unknown > 0 {
      Text(DayPlan.taskCount(summary.count, language: store.language))
    } else if pending && summary.count == 0 {
      Text(store.text("Загружаем…", "Loading…"))
    } else if uncertain && summary.count == 0 {
      Text(store.text("Не проверено", "Not checked"))
    } else {
      let total = summary.count
      RitmCountText(summary.completed) { done in
        store.text("\(done) из \(total)", "\(done) of \(total)")
      }
    }
  }

  // MARK: Day switch and quick add

  /// `.dashboard-task-days`: Сегодня / Завтра.
  private var dayPicker: some View {
    RitmSegmentedControl(
      label: store.text("День для списка задач", "Task list day"), values: [false, true],
      title: { $0 ? store.text("Завтра", "Tomorrow") : store.text("Сегодня", "Today") },
      selection: $tomorrow, fontSize: 13)
  }

  private var quickAdd: some View {
    HStack(spacing: 8) {
      TextField(
        "", text: $quickTitle,
        prompt: Text(
          tomorrow
            ? store.text("Что нужно сделать завтра?", "What needs to get done tomorrow?")
            : store.text("Что нужно сделать сегодня?", "What needs to get done today?")
        ).foregroundColor(RitmTheme.muted)
      )
      .ritmFont(13)
      .foregroundStyle(RitmTheme.text)
      .submitLabel(.done)
      .onSubmit { Task { await addQuickTask() } }
      .onChange(of: quickTitle) { _, value in
        // `maxLength={160}` counts UTF-16 code units.
        var limited = value
        while limited.utf16.count > 160 { limited.removeLast() }
        if limited != value { quickTitle = limited }
      }
      .disabled(quickBusy)
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
      .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .circular))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .circular)
          .strokeBorder(RitmTheme.line, lineWidth: 1)
      }
      .accessibilityLabel(
        tomorrow
          ? store.text("Новая задача на завтра", "New task for tomorrow")
          : store.text("Новая задача на сегодня", "New task for today"))
      Button {
        Task { await addQuickTask() }
      } label: {
        if quickBusy {
          ProgressView().tint(RitmTheme.accentColor).frame(width: 44, height: 44)
        } else {
          DaySquareButtonLabel(symbol: "plus.circle")
        }
      }
      .buttonStyle(RitmPressStyle())
      .opacity(quickBusy || trimmedTitle.isEmpty || !store.canWrite ? 0.5 : 1)
      .disabled(quickBusy || trimmedTitle.isEmpty || !store.canWrite)
      .accessibilityLabel(
        tomorrow
          ? store.text("Добавить задачу на завтра", "Add task for tomorrow")
          : store.text("Добавить задачу на сегодня", "Add task for today"))
    }
  }

  // MARK: List

  @ViewBuilder private var list: some View {
    if summary.count > 0 {
      VStack(spacing: 0) {
        ForEach(summary.googleTodos) { googleRow($0) }
        ForEach(summary.entries) { taskRow($0) }
      }
      .padding(.top, 16)
    } else if uncertain {
      emptyState(
        icon: nil,
        title: pending
          ? store.text("Загружаем задачи", "Loading tasks")
          : store.text("Задачи Google пока недоступны", "Google tasks are currently unavailable"),
        message: pending
          ? (tomorrow
            ? store.text("Проверяем задачи на завтра.", "Checking tomorrow’s tasks.")
            : store.text("Проверяем задачи на сегодня.", "Checking today’s tasks."))
          : store.text(
            "Личные задачи можно добавить ниже. Подключение Google проверь в календаре.",
            "You can add personal tasks below. Check the Google connection in Calendar."),
        showCalendar: !pending)
    } else {
      emptyState(
        icon: "plus.circle",
        title: tomorrow
          ? store.text("Пока нет задач на завтра", "No tasks for tomorrow yet")
          : store.text("Пока нет задач на сегодня", "No tasks for today yet"),
        message: store.text(
          "Добавьте первое дело ниже. Встречи и занятия — в расписании справа.",
          "Add your first task below. Meetings and classes are in the schedule."),
        showCalendar: false)
    }
  }

  private func emptyState(icon: String?, title: String, message: String, showCalendar: Bool)
    -> some View
  {
    VStack(spacing: 12) {
      if let icon {
        RitmSymbol(icon).font(.system(size: 30, weight: .light))
          .foregroundStyle(RitmTheme.accentColor)
      } else if pending {
        ProgressView().controlSize(.large).tint(RitmTheme.accentColor)
      } else {
        RitmSymbol("exclamationmark.circle")
          .font(.system(size: 26))
          .foregroundStyle(RitmTheme.accentColor)
      }
      Text(title).ritmFont(15, weight: .semibold).foregroundStyle(RitmTheme.text)
      Text(message).ritmFont(12, lineSpacing: 4).foregroundStyle(RitmTheme.muted)
      if showCalendar {
        Button(store.text("Открыть календарь", "Open calendar"), action: onCalendar)
          .buttonStyle(RitmTextButtonStyle())
      }
    }
    .multilineTextAlignment(.center)
    .padding(24)
    .frame(maxWidth: .infinity, minHeight: 220)
    .accessibilityElement(children: .contain)
  }

  private func taskRow(_ item: TaskOccurrence) -> some View {
    let busy = busyTasks.contains(item.task.id)
    return HStack(spacing: 4) {
      Button {
        Task { await toggle(item) }
      } label: {
        Group {
          if busy { ProgressView().tint(RitmTheme.accentColor) } else { DayCheckbox(done: item.completed) }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.9))
      .disabled(busy || !store.canWrite)
      .accessibilityLabel(
        (item.completed
          ? store.text("Вернуть в план", "Return to plan") : store.text("Выполнить", "Complete"))
          + ": " + item.task.title)
      .accessibilityAddTraits(item.completed ? .isSelected : [])
      Button {
        onOpenTask(item.task, item.date)
      } label: {
        rowCopy(title: item.task.title, meta: meta(item.task), done: item.completed)
      }
      .buttonStyle(RitmPressStyle())
      if let start = item.start {
        Text(DayPlan.clock(start)).ritmFont(10).foregroundStyle(RitmTheme.muted).fixedSize()
      }
    }
    .modifier(DayTaskRowFrame())
  }

  private func googleRow(_ entry: DayOccurrence) -> some View {
    let event = entry.event
    let complete = event?.googleTask?.status == "completed"
    let busy = event.map { busyGoogle.contains($0.id) } ?? false
    let checkable = event?.googleTask != nil
    var meta = "Google Tasks"
    if complete { meta += store.text(" · Выполнено", " · Completed") }
    if !checkable {
      meta +=
        " · "
        + (event?.taskUnavailableReason
          ?? store.text("Статус пока недоступен", "Status currently unavailable"))
    }
    let checkLabel: String
    if !checkable {
      checkLabel = store.text("Открыть задачу: ", "Open task: ") + entry.title
    } else if complete {
      checkLabel = store.text("Вернуть в задачи", "Mark incomplete") + ": " + entry.title
    } else {
      checkLabel = store.text("Выполнить", "Complete") + ": " + entry.title
    }
    return HStack(spacing: 4) {
      Button {
        guard let event else { return }
        if checkable { Task { await toggleGoogle(event) } } else { onOpenEvent(event) }
      } label: {
        Group {
          if busy {
            ProgressView().tint(RitmTheme.accentColor)
          } else if checkable {
            DayCheckbox(done: complete)
          } else {
            RitmSymbol("checklist").font(.system(size: 17)).foregroundStyle(RitmTheme.muted)
          }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.9))
      .disabled(busy || (checkable && !store.canWrite))
      .accessibilityLabel(checkLabel)
      Button {
        if let event { onOpenEvent(event) }
      } label: {
        rowCopy(title: entry.title, meta: meta, done: complete)
      }
      .buttonStyle(RitmPressStyle())
      Text(entry.start.map { DayPlan.clock($0, compact: true) } ?? store.text("Весь день", "All day"))
        .ritmFont(10)
        .foregroundStyle(RitmTheme.muted)
        .fixedSize()
    }
    .modifier(DayTaskRowFrame())
  }

  private func rowCopy(title: String, meta: String, done: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .ritmFont(12, weight: .medium, lineSpacing: 3)
        .strikethrough(done)
        .foregroundStyle(done ? RitmTheme.muted : RitmTheme.text)
      Text(meta).ritmFont(10, lineSpacing: 3).foregroundStyle(RitmTheme.muted)
    }
    .multilineTextAlignment(.leading)
    .padding(.vertical, 7)
    .padding(.trailing, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func meta(_ task: RitmTask) -> String {
    var value =
      task.calendarEntry == false
      ? store.text("Личная задача", "Personal task") : store.text("Задача", "Task")
    switch task.priority {
    case .high: value += store.text(" · Высокий приоритет", " · High priority")
    case .low: value += store.text(" · Низкий приоритет", " · Low priority")
    case .normal: value += store.text(" · Обычный приоритет", " · Normal priority")
    }
    if task.time != nil { value += " · " + DayPlan.durationText(task.duration, language: store.language) }
    if task.repeat != .none { value += store.text(" · Повторяется", " · Repeats") }
    return value
  }

  @ViewBuilder private var permission: some View {
    if let message = store.googleTasks?.message {
      VStack(alignment: .leading, spacing: 0) {
        DayDivider()
        Text(message)
          .ritmFont(11, lineSpacing: 4)
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 12)
        // Web OAuth starts here; on iPhone the Google connection lives in Settings.
        if store.googleStatus?.tasksEnabled != true {
          Button(action: onSettings) {
            Label { Text(store.text("Подключить Google Tasks", "Connect Google Tasks")) } icon: { RitmSymbol("checkmark.circle") }
          }
          .buttonStyle(RitmTextButtonStyle())
        }
      }
      .padding(.top, 12)
    }
  }

  // MARK: Actions

  private func addQuickTask() async {
    let title = trimmedTitle
    guard !title.isEmpty, !quickBusy else { return }
    quickBusy = true
    quickError = nil
    let input = TaskInput(title: title, date: date, calendarEntry: false)
    let created = await store.write { try await $0.createTask(input) }
    quickBusy = false
    if created != nil {
      quickTitle = ""
    } else if let message = store.errorMessage {
      // Shown next to the field, like the web form.
      quickError = message
      store.errorMessage = nil
    }
  }

  private func toggle(_ item: TaskOccurrence) async {
    busyTasks.insert(item.task.id)
    _ = await store.write {
      try await $0.setTaskCompleted(
        id: item.task.id, completed: !item.completed,
        occurrenceDate: item.task.repeat == .none ? nil : item.date)
    }
    busyTasks.remove(item.task.id)
  }

  private func toggleGoogle(_ event: GoogleCalendarEvent) async {
    guard !busyGoogle.contains(event.id) else { return }
    busyGoogle.insert(event.id)
    _ = await store.write {
      try await $0.completeGoogleTask(event: event, completed: event.googleTask?.status != "completed")
    }
    busyGoogle.remove(event.id)
    await onGoogleChanged()
  }
}

/// `.task-row` on a phone: a hairline above, 12 pt vertical padding, at least 76 pt tall.
private struct DayTaskRowFrame: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.vertical, 12)
      .frame(minHeight: 76)
      .overlay(alignment: .top) { DayDivider() }
  }
}

struct DaySchedulePanel: View {
  let entries: [DayOccurrence]
  let onOpen: (DayOccurrence) -> Void
  let onCalendar: () -> Void
  let onAsk: (String?) -> Void
  let onOpenTask: (RitmTask) -> Void
  @Environment(RitmStore.self) private var store
  @State private var expanded: Set<String> = []

  private var tasks: [RitmTask] { store.bootstrap?.tasks ?? [] }

  var body: some View {
    let timed = entries.filter { $0.start != nil && $0.end != nil }
    return VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(store.text("Расписание", "Schedule"))
          .ritmFont(15, weight: .semibold, tracking: -0.025)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button(action: onCalendar) {
          HStack(spacing: 6) {
            Text(store.text("Сегодня", "Today"))
            RitmSymbol("arrow.up.right").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
          }
        }
        .buttonStyle(RitmTextButtonStyle())
      }
      .padding(.bottom, 6)
      if timed.isEmpty {
        emptySchedule
      } else {
        ForEach(timed.prefix(6)) { row($0) }
        if timed.count > 6 {
          Button(
            store.text("Ещё \(timed.count - 6) в календаре", "\(timed.count - 6) more in the calendar"),
            action: onCalendar
          )
          .buttonStyle(RitmTextButtonStyle())
        }
      }
      ForEach(entries.filter(\.allDay)) { entry in
        Button {
          onOpen(entry)
        } label: {
          Text(store.text("Весь день", "All day") + " · \(entry.title) · Google")
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(RitmTextButtonStyle())
      }
      if store.googleUncertain {
        Text(
          store.text(
            "Google Calendar ещё не проверен. Открой календарь, чтобы обновить события.",
            "Google Calendar has not been checked yet. Open the calendar to refresh events.")
        )
        .ritmFont(11, lineSpacing: 4)
        .foregroundStyle(RitmTheme.muted)
      }
      backlogGrid
    }
    .modifier(DayPanelSurface(reveal: 4))
  }

  private var emptySchedule: some View {
    VStack(spacing: 12) {
      RitmSymbol("calendar").font(.system(size: 24))
      Text(
        store.googleUncertain
          ? store.text("Уточняем расписание", "Checking your schedule")
          : store.text("Свободное расписание", "Open schedule")
      )
      .ritmFont(12)
      Button {
        onAsk(
          store.text(
            "Найди свободное время в моём расписании на сегодня.",
            "Find free time in my schedule today."))
      } label: {
        Label { Text(store.text("Найти удобное время", "Find a good time")) } icon: { RitmSymbol("clock") }
      }
      .buttonStyle(RitmTextButtonStyle())
    }
    .foregroundStyle(RitmTheme.muted)
    .frame(maxWidth: .infinity, minHeight: 220)
  }

  private func row(_ entry: DayOccurrence) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Text(entry.start.map { DayPlan.clock($0) } ?? "")
        .ritmFont(10)
        .foregroundStyle(RitmTheme.muted)
        .frame(width: 46, alignment: .leading)
        .padding(.top, 13)
      Button {
        onOpen(entry)
      } label: {
        VStack(alignment: .leading, spacing: 5) {
          Text(entry.title)
            .ritmFont(11, weight: .medium, lineSpacing: 3)
            .strikethrough(entry.completed)
            .foregroundStyle(entry.completed ? RitmTheme.muted : RitmTheme.text)
          Text(interval(entry)).ritmFont(10).foregroundStyle(RitmTheme.muted)
        }
        .multilineTextAlignment(.leading)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
        .background { DayEventSurface(color: CalendarPalette.entryColor(entry.colorId)) }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .circular))
      }
      .buttonStyle(RitmPressStyle())
    }
    .padding(.bottom, 12)
  }

  private func interval(_ entry: DayOccurrence) -> String {
    if entry.completed { return store.text("Завершено", "Completed") }
    let start = entry.startLabel ?? DayPlan.clock(entry.start ?? 0)
    let end = entry.endLabel ?? DayPlan.clock(entry.end ?? 0)
    var value = start + "–" + end
    if entry.end == 1440 { value += store.text(" · следующий день", " · next day") }
    if entry.event != nil { value += " · Google" }
    return value
  }

  private var backlogGrid: some View {
    HStack(alignment: .top, spacing: 12) {
      backlog(
        store.text("Без даты", "No date"), key: "undated",
        items: tasks.filter { $0.date == nil && !$0.completed })
      backlog(
        store.text("Просрочено", "Overdue"), key: "overdue",
        items: tasks.filter { task in
          guard let date = task.date else { return false }
          return date < store.today && !task.completed && task.repeat == .none
        })
    }
    .padding(.top, 17)
    .overlay(alignment: .top) { DayDivider() }
    .padding(.top, 18)
  }

  private func backlog(_ title: String, key: String, items: [RitmTask]) -> some View {
    let open = expanded.contains(key)
    return VStack(alignment: .leading, spacing: 0) {
      Text(items.isEmpty ? title : "\(title) · \(items.count)")
        .ritmFont(10, weight: .medium)
        .foregroundStyle(RitmTheme.muted)
      if items.isEmpty {
        Text(store.text("Всё в порядке", "All clear"))
          .ritmFont(11)
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 8)
      }
      ForEach(open ? items : Array(items.prefix(3))) { task in
        Button {
          onOpenTask(task)
        } label: {
          Text(task.title)
            .ritmFont(11, weight: .medium, lineSpacing: 5)
            .foregroundStyle(RitmTheme.text)
            .multilineTextAlignment(.leading)
            .padding(.top, 7)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
      }
      if items.count > 3 {
        Button {
          expanded.formSymmetricDifference([key])
        } label: {
          Text(
            open
              ? store.text("Свернуть", "Collapse")
              : store.text("Показать все \(items.count)", "Show all \(items.count)")
          )
          .underline()
        }
        .buttonStyle(RitmTextButtonStyle())
        .accessibilityAddTraits(open ? .isSelected : [])
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// `.schedule-event`: the entry colour mixed into the panel, with a 2 pt bar on the left.
private struct DayEventSurface: View {
  let color: Color

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    shape
      .fill(RitmTheme.mix(color, 0.24, into: RitmTheme.panel))
      .overlay(alignment: .leading) {
        Rectangle().fill(RitmTheme.mix(color, 0.76, into: RitmTheme.panel)).frame(width: 2)
      }
      .clipShape(shape)
  }
}
