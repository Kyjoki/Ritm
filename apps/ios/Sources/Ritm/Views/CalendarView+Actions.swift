import RitmCore
import SwiftUI

// What the calendar page does: add, open, move, step through periods, read Google.

extension CalendarView {
  /// `addEntry`: a slot gives a time (60 minutes by default), the «+» button an all-day event.
  func addEntry(_ day: String, time: String? = nil, duration: Int = 60) {
    guard connected else {
      store.errorMessage = store.text(
        "Подключи Google Calendar в настройках, чтобы добавить запись.",
        "Connect Google Calendar in Settings to add an entry.")
      navigation.section = .settings
      return
    }
    let bounded = time.flatMap(TaskSchedule.timeMinutes).map { min(duration, 1440 - $0) } ?? duration
    sheet = CalendarSheet(draft: CalendarDraft(date: day, time: time, duration: bounded))
  }

  func open(_ entry: DayOccurrence) {
    if let event = entry.event {
      sheet = CalendarSheet(event: event)
    } else if let task = entry.task?.task {
      sheet = CalendarSheet(task: task)
    }
  }

  /// One period forward (1) or back (-1): a day, three days, a week or a month.
  func step(_ amount: Int) {
    date = mode.stepped(anchor: selected, by: amount)
  }

  /// «Сегодня»: today's period, and in the hour grid the hours around now.
  func goToday() {
    date = store.today
    if mode.isTimeGrid { nowJump += 1 }
  }

  func refreshGoogle() async {
    await store.refresh()
    await reload()
  }

  /// A view picked in the side menu. The page switches at once, with no animation of its tree
  /// (the month and the grid are heavy to move); the menu closes on its own animation.
  func choose(_ value: CalendarViewMode) {
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant) { mode = value }
    setDrawer(false)
  }

  /// The UTC offset in the corner above the time column: «UTC+5».
  var timeZoneLabel: String {
    let seconds = FeatureDate.calendar(store.timeZone).timeZone.secondsFromGMT(
      for: FeatureDate.date(selected, zone: store.timeZone))
    let minutes = abs(seconds / 60)
    return "UTC" + (seconds >= 0 ? "+" : "-") + String(minutes / 60)
      + (minutes % 60 == 0 ? "" : String(format: ":%02d", minutes % 60))
  }

  // MARK: Moving entries

  /// `canDragEntry`, with the reason: a whole, editable Google event that is not a task, or a
  /// timed one-off Ritm task. Everything else stays put and says why when it is held.
  func dragBlock(_ entry: DayOccurrence) -> String? {
    if let reason = movePolicy(entry) { return reason }
    guard store.canWrite else {
      return store.text(
        "Сейчас нельзя сохранять изменения. Подожди и попробуй ещё раз.",
        "Changes cannot be saved right now. Wait a moment and try again.")
    }
    return nil
  }

  func movePolicy(_ entry: DayOccurrence) -> String? {
    guard entry.start != nil, !entry.allDay else { return Self.notMovable(store) }
    if entry.continued {
      return store.text(
        "Продолжение записи с прошлого дня переносится вместе с основной записью.",
        "The part that continues from yesterday moves with the main entry.")
    }
    if let event = entry.event { return eventMovePolicy(event) }
    if let task = entry.task?.task { return taskMovePolicy(task, entry) }
    return Self.notMovable(store)
  }

  private func eventMovePolicy(_ event: GoogleCalendarEvent) -> String? {
    if event.googleTask != nil || event.taskLink == true {
      return store.text(
        "Задачи Google переносятся в Google Tasks. Открой запись, чтобы изменить её.",
        "Google tasks are moved in Google Tasks. Open the entry to change it.")
    }
    if event.readOnly {
      return store.text(
        "Это событие только для просмотра: перенести его нельзя.",
        "This event is view-only and cannot be moved.")
    }
    if !CalendarEventPolicy.canEdit(event, timeZone: store.timeZone) {
      return store.text(
        "Это событие нельзя перенести здесь: оно повторяется, идёт несколько дней или меняет часы. Открой его, чтобы изменить.",
        "This event cannot be moved here: it repeats, spans days or crosses a clock change. Open it to edit.")
    }
    return nil
  }

  private func taskMovePolicy(_ task: RitmTask, _ entry: DayOccurrence) -> String? {
    if task.repeat != .none {
      return store.text(
        "Повторяющуюся задачу нельзя перенести отдельно: изменится вся серия. Открой её, чтобы изменить.",
        "A repeating task cannot be moved on its own: the whole series would change. Open it to edit.")
    }
    if entry.completed {
      return store.text("Выполненную задачу нельзя перенести.", "A completed task cannot be moved.")
    }
    if let start = entry.start, start + task.duration > 1440 {
      return store.text(
        "Задача заканчивается после полуночи: перенести её можно только через редактор.",
        "The task ends after midnight: move it from the editor.")
    }
    return nil
  }

  static func notMovable(_ store: RitmStore) -> String {
    store.text("Эту запись нельзя перенести.", "This entry cannot be moved.")
  }

  /// `onGoogleMove`: saved at once with the same duration, no confirmation. A Ritm task keeps its
  /// duration too. An ETag conflict or a failed write is reported by `store.write`, and the
  /// reload below shows the server's version.
  func move(_ entry: DayOccurrence, to day: String, minute: Int) async {
    guard movePolicy(entry) == nil else {
      store.errorMessage = store.text(
        "Эту запись нельзя перетащить. Открой её для просмотра.",
        "This entry cannot be dragged. Open it to view it.")
      return
    }
    let time = TaskSchedule.minuteTime(minute)
    var saved = false
    if let event = entry.event, var input = CalendarEventPolicy.draft(event, timeZone: store.timeZone) {
      input.date = day
      input.time = time
      saved = await store.write { try await $0.updateGoogleEvent(id: event.id, event: input, etag: event.etag) } != nil
    } else if let task = entry.task?.task {
      let patch = TaskPatch(date: .value(day), time: .value(time))
      saved = await store.write { try await $0.updateTask(id: task.id, patch: patch) } != nil
    }
    if saved {
      store.toasts.show(store.text("Перенесено", "Moved"))
    } else if store.errorMessage == nil {
      store.errorMessage = store.text(
        "Не удалось перенести запись. Попробуй ещё раз.", "Could not move the entry. Try again.")
    }
    await reload()
  }

  // MARK: Reading Google

  /// Reads Google only when the page needs days that were not read yet: switching between the
  /// views, or a swipe inside the neighbours already read, costs no request.
  func reloadIfNeeded() async {
    if CalendarViewMode.covers(fetchedRange, range) { return }
    await reload()
  }

  func reload() async {
    guard navigation.section == .calendar else { return }
    let ticket = UUID()
    readID = ticket
    loading = true
    defer { if ticket == readID { loading = false } }
    let (from, to) = range
    let currentStatus = await store.read { try await $0.googleStatus() }
    guard ticket == readID, !Task.isCancelled else { return }
    if let currentStatus, currentStatus != status { status = currentStatus }
    guard currentStatus?.status == .connected else {
      if currentStatus != nil {
        events = []
        partial = false
        failed = false
        fetchedRange = (from, to)
      } else {
        failed = true
      }
      return
    }
    let zone = store.timeZone
    let result = await store.read { try await $0.googleEvents(from: from, to: to, timeZone: zone) }
    guard ticket == readID, !Task.isCancelled else { return }
    if let result {
      if events != result.events { events = result.events }
      if partial != result.partial { partial = result.partial }
      if fetchedAt != result.fetchedAt { fetchedAt = result.fetchedAt }
      if failed { failed = false }
      fetchedRange = (from, to)
      if filter.remember(result.events) { CalendarFilterStore.save(filter, email: email) }
    } else {
      failed = true
    }
  }

  /// The days the search reads: the last 30 days and the next 180, fetched once per search.
  func searchDays() async -> [(date: String, entries: [DayOccurrence])] {
    let first = HabitSchedule.addDays(to: store.today, days: -30) ?? store.today
    let last = HabitSchedule.addDays(to: store.today, days: 180) ?? store.today
    var fetched: [GoogleCalendarEvent] = []
    if connected {
      let zone = store.timeZone
      let result = await store.read { try await $0.googleEvents(from: first, to: last, timeZone: zone) }
      fetched = result?.events ?? []
    }
    let dates = (0..<210).compactMap { HabitSchedule.addDays(to: first, days: $0) }
    let read = DayPlan.occurrencesByDay(
      tasks: CalendarSources.visible(store.bootstrap?.tasks ?? [], hidden: filter.hidden),
      events: CalendarSources.visible(fetched, hidden: filter.hidden), dates: dates,
      timeZone: store.timeZone, language: store.language)
    return dates.map { (date: $0, entries: read[$0] ?? []) }
  }
}
