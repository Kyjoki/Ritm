import RitmCore
import SwiftUI

/// Tapping an existing Google event: an editable event that opens straight in the editor, or, for
/// an entry that cannot be edited here (a read-only calendar, someone else's event, a Google
/// task), the same sheet layout with the fields shown but not editable and only «Закрыть».
struct CalendarEventDetail: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  /// The event as tapped: the editor keeps its ETag, a refresh must not swap it underneath.
  private let original: GoogleCalendarEvent
  @State private var event: GoogleCalendarEvent
  @State private var busy = false
  @State private var missing = false
  @State private var readID = UUID()
  let onSave: (() async -> Void)?

  init(event: GoogleCalendarEvent, onSave: (() async -> Void)? = nil) {
    original = event
    _event = State(initialValue: event)
    self.onSave = onSave
  }

  var body: some View {
    if CalendarEventPolicy.canEdit(original, timeZone: store.timeZone) {
      CalendarEventEditor(event: original, initialDate: store.today, onSave: onSave)
    } else {
      readOnly
    }
  }

  // MARK: Read-only sheet

  private var readOnly: some View {
    CalendarSheetFrame(
      title: store.text("Событие", "Event"), detents: [.medium, .large], busy: busy
    ) {
      if let message = store.errorMessage { RitmErrorBanner(message: message) }
      MutationRecoveryView()
      if missing {
        RitmErrorBanner(
          message: store.text(
            "Событие удалено или перемещено на другую дату. Обновите календарь и откройте его заново.",
            "This event was deleted or moved to another date. Refresh the calendar and reopen it."
          ))
      }
      CalendarSheetField(store.text("Название", "Title")) {
        shown(Text(event.title).textSelection(.enabled))
      }
      if !event.description.isEmpty {
        CalendarSheetField(store.text("Описание", "Description")) {
          shown(Text(event.description).textSelection(.enabled), minHeight: 76)
        }
      }
      CalendarSheetField(store.text("Дата", "Date")) {
        shown(Text(dateText).monospacedDigit(), icon: .calCalendar)
      }
      if let range = timeRange {
        HStack(alignment: .top, spacing: 10) {
          CalendarSheetField(store.text("Начало", "Start")) {
            shown(Text(range.start).monospacedDigit(), icon: .clock)
          }
          CalendarSheetField(store.text("Конец", "End")) {
            shown(Text(range.end).monospacedDigit(), icon: .clock)
          }
        }
      } else {
        CalendarSheetNote(text: store.text("Весь день", "All day"))
      }
      if let task = event.googleTask {
        CalendarSwitchRow(
          title: store.text("Выполнено", "Done"),
          isOn: Binding(
            get: { task.status == "completed" },
            set: { done in complete(done) })
        )
        .disabled(!store.canWrite || busy || missing)
      }
      if CalendarEventPolicy.hasClockChange(event, timeZone: store.timeZone) {
        CalendarSheetNote(
          text: store.text(
            "Событие пересекает перевод часов или неоднозначное местное время. Показано фактическое время начала и окончания.",
            "This event crosses a clock change or ambiguous local time. The actual start and end times are shown."
          ))
      }
      HStack(alignment: .top, spacing: 8) {
        RitmIcon(.lockCalendar).font(.system(size: 16))
        Text(
          event.taskUnavailableReason ?? event.readOnlyReason
            ?? store.text(
              "Событие доступно для просмотра. Дату и время можно изменить в Google Calendar.",
              "This event is read-only. Edit its date and time in Google Calendar."))
      }
      .ritmFont(13, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      Link(destination: URL(string: "https://calendar.google.com/calendar/u/0/r")!) {
        Text(store.text("Открыть Google Calendar", "Open Google Calendar"))
          .ritmFont(14, weight: .medium)
          .foregroundStyle(RitmTheme.accentColor)
          .frame(minHeight: 44, alignment: .leading)
      }
      Button(store.text("Закрыть", "Close")) { dismiss() }
        .buttonStyle(CalendarSheetButtonStyle())
        .disabled(busy)
    }
    .task { await refreshEvent() }
    .onChange(of: store.lastSyncedAt) { _, _ in Task { await refreshEvent() } }
  }

  /// An input-looking box that only shows a value.
  private func shown<Content: View>(
    _ content: Content, icon: RitmIconName? = nil, minHeight: CGFloat = 44
  ) -> some View {
    HStack(alignment: .top) {
      content.frame(maxWidth: .infinity, alignment: .leading)
      if let icon { RitmIcon(icon).font(.system(size: 16)).foregroundStyle(RitmTheme.text) }
    }
    .calendarInput(minHeight: minHeight)
    .opacity(0.8)
  }

  private func complete(_ done: Bool) {
    Task {
      busy = true
      let result = await store.write {
        try await $0.completeGoogleTask(event: event, completed: done)
      }
      busy = false
      if let result {
        event = result
        await onSave?()
      }
    }
  }

  /// «dd.mm.yyyy» of the event's first day.
  private var dateText: String {
    let key =
      event.start.date
      ?? FeatureDate.instant(event.start.dateTime).map {
        HabitSchedule.dateKey($0, timeZone: store.timeZone)
      } ?? ""
    let parts = key.split(separator: "-")
    return parts.count == 3 ? "\(parts[2]).\(parts[1]).\(parts[0])" : "—"
  }

  /// Start and end clock times of a timed event; nil for an all-day one.
  private var timeRange: (start: String, end: String)? {
    guard let start = FeatureDate.instant(event.start.dateTime),
      let end = FeatureDate.instant(event.end.dateTime)
    else { return nil }
    return (
      FeatureDate.time(start, zone: store.timeZone), FeatureDate.time(end, zone: store.timeZone)
    )
  }

  private func refreshEvent() async {
    let ticket = UUID()
    readID = ticket
    let first =
      event.start.date ?? FeatureDate.instant(event.start.dateTime).map {
        HabitSchedule.dateKey($0, timeZone: store.timeZone)
      } ?? store.today
    guard let until = HabitSchedule.addDays(to: first, days: 1) else { return }
    let result = await store.read {
      try await $0.googleEvents(from: first, to: until, timeZone: store.timeZone)
    }
    guard ticket == readID, let result, !Task.isCancelled else { return }
    if let refreshed = result.events.first(where: {
      $0.id == event.id && $0.calendarId == event.calendarId
    }) {
      event = refreshed
      missing = false
    } else if !result.partial {
      missing = true
    }
  }
}

struct CalendarEventEditor: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let event: GoogleCalendarEvent?
  let initialDate: String
  let onSave: (() async -> Void)?
  @State private var title = ""
  @State private var details = ""
  @State private var date = ""
  @State private var time = "09:00"
  @State private var allDay = false
  /// GoogleEventDialog starts a new entry at 30 minutes.
  @State private var duration = 30
  @State private var recurrence: TaskRepeat = .none
  @State private var colorID = ""
  @State private var extendedColors = false
  @State private var initialized = false
  @State private var busy = false
  @State private var confirmDelete = false
  @State private var validation: String?
  @State private var requestID = UUID().uuidString
  @State private var previousInput: GoogleEventInput?

  /// A new entry starts at `initialTime`; nil makes it an all-day event, as on the web.
  let initialTime: String?
  let initialDuration: Int

  init(
    event: GoogleCalendarEvent? = nil, initialDate: String, initialTime: String? = "09:00",
    initialDuration: Int = 30, onSave: (() async -> Void)? = nil
  ) {
    self.event = event
    self.initialDate = initialDate
    self.initialTime = initialTime
    self.initialDuration = initialDuration
    self.onSave = onSave
  }
  var body: some View {
    CalendarSheetFrame(
      title: store.text(
        event == nil ? "Новое событие" : "Изменить событие",
        event == nil ? "New event" : "Edit event"),
      busy: busy
    ) {
      if let validation { CalendarSheetError(message: validation) }
      if let error = store.errorMessage { RitmErrorBanner(message: error) }
      if event == nil && store.uncertainWrite {
        Button(store.text("Закрыть и проверить список", "Close and check the list")) { dismiss() }
          .buttonStyle(CalendarSheetButtonStyle())
          .disabled(busy)
      } else {
        MutationRecoveryView()
      }
      CalendarSheetField(store.text("Название", "Title")) {
        CalendarTextInput(placeholder: store.text("Название", "Title"), text: $title)
      }
      CalendarSheetField(store.text("Описание", "Description")) {
        CalendarTextInput(
          placeholder: store.text("Описание", "Description"), text: $details, lines: 3...8,
          minHeight: 76)
      }
      CalendarSheetField(store.text("Дата", "Date")) {
        CalendarDateField(value: $date, zone: store.timeZone)
      }
      CalendarSwitchRow(title: store.text("Весь день", "All day"), isOn: $allDay)
      if !allDay {
        VStack(alignment: .leading, spacing: 16) {
          CalendarTimeRange(start: $time, duration: $duration)
          RitmDurationStepper(duration: $duration)
        }
      }
      if event == nil {
        CalendarSheetField(store.text("Повтор", "Repeat")) {
          CalendarSelect(
            options: [
              (TaskRepeat.none, store.text("Не повторять", "Never")),
              (TaskRepeat.daily, store.text("Каждый день", "Daily")),
              (TaskRepeat.weekly, store.text("Каждую неделю", "Weekly")),
              (TaskRepeat.monthly, store.text("Каждый месяц", "Monthly")),
            ], selection: $recurrence)
        }
      }
      CalendarSheetNote(
        text: store.text(
          "Запись сохраняется в основном Google Calendar. Часовой пояс: ",
          "Saved to your primary Google Calendar. Time zone: ") + store.timeZone)
      VStack(alignment: .leading, spacing: 4) {
        Text(store.text("Цвет", "Color")).ritmFont(12).foregroundStyle(RitmTheme.muted)
        CalendarColorPicker(colorID: $colorID, extended: extendedColors)
      }
      if event != nil {
        Button(store.text("Удалить событие", "Delete event")) { confirmDelete = true }
          .buttonStyle(CalendarSheetButtonStyle(kind: .danger))
          .disabled(!store.canWrite || busy)
      }
      CalendarSheetButtons(
        cancelTitle: store.text("Отмена", "Cancel"), saveTitle: store.text("Сохранить", "Save"),
        canSave: store.canWrite && !busy && initialized,
        cancel: { dismiss() }, save: { Task { await save() } })
    }
    .task {
      guard !initialized else { return }
      date = initialDate
      if event == nil {
        time = initialTime ?? "09:00"
        allDay = initialTime == nil
        duration = initialDuration
      }
      if let event {
        guard let draft = CalendarEventPolicy.draft(event, timeZone: store.timeZone) else {
          validation = store.text(
            "Эту запись безопаснее изменить в Google Calendar.",
            "Please edit this protected entry in Google Calendar.")
          return
        }
        title = draft.title
        details = draft.description
        date = draft.date
        time = draft.time ?? "09:00"
        duration = draft.duration
        allDay = draft.allDay
        colorID = event.colorId ?? ""
      }
      if let status = await store.read({ try await $0.googleStatus() }) {
        extendedColors = status.extendedColors == true
      }
      initialized = true
    }
    .confirmationDialog(
      store.text("Удалить событие из Google Calendar?", "Delete this Google Calendar event?"),
      isPresented: $confirmDelete, titleVisibility: .visible
    ) {
      Button(store.text("Удалить", "Delete"), role: .destructive) {
        guard let event else { return }
        Task {
          busy = true
          let success = await store.performMutation {
            try await $0.deleteGoogleEvent(id: event.id, etag: event.etag)
          }
          busy = false
          if success {
            store.toasts.show(store.text("Событие удалено", "Event deleted"))
            await onSave?()
            dismiss()
          }
        }
      }
    }
  }
  private func save() async {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title.utf16.count <= 160, details.utf16.count <= 4000,
      HabitSchedule.isValidDate(date),
      allDay || TaskSchedule.timeMinutes(time).map({ $0 + duration <= 1440 }) == true
    else {
      validation = store.text(
        "Проверьте название, дату и время HH:mm. Событие должно завершиться до полуночи.",
        "Check the title, date and HH:mm time. The event must end by midnight.")
      return
    }
    if let event, !CalendarEventPolicy.canEdit(event, timeZone: store.timeZone) { return }
    let input = GoogleEventInput(
      title: title, description: details, date: date,
      time: allDay ? nil : time, duration: allDay ? 60 : duration, allDay: allDay,
      colorId: colorID.isEmpty ? nil : colorID, repeat: event == nil ? recurrence : nil,
      preservesProviderColor: event.map { colorID == ($0.colorId ?? "") } ?? false)
    if previousInput != input {
      requestID = UUID().uuidString
      previousInput = input
    }
    validation = nil
    busy = true
    let result = await store.write { client in
      if let event {
        return try await client.updateGoogleEvent(id: event.id, event: input, etag: event.etag)
      }
      return try await client.createGoogleEvent(event: input, requestId: requestID)
    }
    busy = false
    if result != nil {
      store.toasts.show(
        event == nil
          ? store.text("Событие добавлено", "Event added")
          : store.text("Событие сохранено", "Event saved"))
      await onSave?()
      dismiss()
    }
  }
}
