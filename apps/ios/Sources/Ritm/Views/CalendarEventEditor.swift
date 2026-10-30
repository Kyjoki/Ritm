import RitmCore
import SwiftUI

struct CalendarEventDetail: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var event: GoogleCalendarEvent
  @State private var editingEvent: GoogleCalendarEvent?
  @State private var busy = false
  @State private var missing = false
  @State private var readID = UUID()
  let onSave: (() async -> Void)?

  init(event: GoogleCalendarEvent, onSave: (() async -> Void)? = nil) {
    _event = State(initialValue: event)
    self.onSave = onSave
  }
  var body: some View {
    NavigationStack {
      ZStack {
        RitmBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text(event.title).font(.largeTitle.bold()).textSelection(.enabled)
            Label(store.eventTimeText(event), systemImage: "clock").foregroundStyle(.secondary)
            Text(dateDescription).font(.subheadline)
            if CalendarEventPolicy.hasClockChange(event, timeZone: store.timeZone) {
              Label(
                store.text(
                  "Событие пересекает перевод часов или неоднозначное местное время. Показано фактическое время начала и окончания.",
                  "This event crosses a clock change or ambiguous local time. The actual start and end times are shown."
                ), systemImage: "clock.arrow.circlepath"
              ).font(.caption).foregroundStyle(.secondary)
            }
            if let message = store.errorMessage { RitmErrorBanner(message: message) }
            MutationRecoveryView()
            if missing {
              RitmErrorBanner(
                message: store.text(
                  "Событие удалено или перемещено на другую дату. Обновите календарь и откройте его заново.",
                  "This event was deleted or moved to another date. Refresh the calendar and reopen it."
                ))
            }
            if !event.description.isEmpty {
              RitmCard { Text(event.description).textSelection(.enabled) }
            }
            if let task = event.googleTask {
              Button {
                Task {
                  busy = true
                  let result = await store.write {
                    try await $0.completeGoogleTask(
                      event: event, completed: task.status != "completed")
                  }
                  busy = false
                  if let result {
                    event = result
                    await onSave?()
                  }
                }
              } label: {
                Label(
                  store.text(
                    task.status == "completed" ? "Вернуть в работу" : "Выполнено",
                    task.status == "completed" ? "Mark incomplete" : "Mark complete"),
                  systemImage: task.status == "completed"
                    ? "arrow.uturn.backward" : "checkmark.circle")
              }.buttonStyle(RitmPrimaryButtonStyle()).disabled(!store.canWrite || busy || missing)
            }
            if !CalendarEventPolicy.canEdit(event, timeZone: store.timeZone) {
              Label(
                event.taskUnavailableReason ?? event.readOnlyReason
                  ?? store.text(
                    "Событие доступно для просмотра. Дату и время можно изменить в Google Calendar.",
                    "This event is read-only. Edit its date and time in Google Calendar."),
                systemImage: "lock"
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
            Link(
              store.text("Открыть Google Calendar", "Open Google Calendar"),
              destination: URL(string: "https://calendar.google.com/calendar/u/0/r")!
            )
            .frame(minHeight: 44)
          }.padding(20)
        }
      }
      .navigationTitle(store.text("Событие", "Event")).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Готово", "Done")) { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          if CalendarEventPolicy.canEdit(event, timeZone: store.timeZone) {
            Button(store.text("Изменить", "Edit")) { editingEvent = event }.disabled(
              !store.canWrite || busy || missing)
          }
        }
      }
      .sheet(item: $editingEvent) { snapshot in
        // Hold the original ETag while editing; a refresh must not silently
        // authorize overwriting another device's changes with an old draft.
        CalendarEventEditor(event: snapshot, initialDate: store.today) {
          await onSave?()
          dismiss()
        }
      }
      .task { await refreshEvent() }
      .onChange(of: store.lastSyncedAt) { _, _ in Task { await refreshEvent() } }
    }
  }
  private var dateDescription: String {
    if let date = event.start.date {
      let start = FeatureDate.label(date, zone: store.timeZone, language: store.language)
      if let end = event.end.date, let last = HabitSchedule.addDays(to: end, days: -1), last != date
      {
        return start + " – "
          + FeatureDate.label(last, zone: store.timeZone, language: store.language)
      }
      return start
    }
    guard let start = FeatureDate.instant(event.start.dateTime),
      let end = FeatureDate.instant(event.end.dateTime)
    else { return "—" }
    return instantDescription(start) + " → " + instantDescription(end)
  }
  private func instantDescription(_ instant: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: store.timeZone)
    formatter.dateFormat =
      FeatureDate.calendar(store.timeZone).component(.second, from: instant) == 0
      ? "h:mm a" : "h:mm:ss a"
    return FeatureDate.label(
      HabitSchedule.dateKey(instant, timeZone: store.timeZone), zone: store.timeZone,
      language: store.language) + ", " + formatter.string(from: instant)
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
    NavigationStack {
      Form {
        if let validation { Section { RitmErrorBanner(message: validation) } }
        if let error = store.errorMessage { Section { RitmErrorBanner(message: error) } }
        Section {
          if event == nil && store.uncertainWrite {
            Button(store.text("Закрыть и проверить список", "Close and check the list")) {
              dismiss()
            }
            .disabled(busy)
          } else {
            MutationRecoveryView()
          }
        }
        Section {
          TextField(store.text("Название", "Title"), text: $title, axis: .vertical).lineLimit(1...4)
          TextField(store.text("Описание", "Description"), text: $details, axis: .vertical)
            .lineLimit(3...8)
          DateKeyPicker(title: store.text("Дата", "Date"), value: $date, zone: store.timeZone)
          Toggle(store.text("Весь день", "All day"), isOn: $allDay)
          if !allDay {
            TextField(store.text("Время HH:mm", "Time HH:mm"), text: $time).keyboardType(
              .numbersAndPunctuation)
            Stepper(
              store.text("Длительность: ", "Duration: ") + "\(duration) "
                + store.text("мин", "min"), value: $duration, in: 5...720, step: 5)
          }
          if event == nil {
            Picker(store.text("Повтор", "Repeat"), selection: $recurrence) {
              Text(store.text("Не повторять", "Never")).tag(TaskRepeat.none)
              Text(store.text("Каждый день", "Daily")).tag(TaskRepeat.daily)
              Text(store.text("Каждую неделю", "Weekly")).tag(TaskRepeat.weekly)
              Text(store.text("Каждый месяц", "Monthly")).tag(TaskRepeat.monthly)
            }
          }
        } footer: {
          Text(
            store.text(
              "Запись сохраняется в основном Google Calendar. Часовой пояс: ",
              "Saved to your primary Google Calendar. Time zone: ") + store.timeZone)
        }
        Section(store.text("Цвет", "Color")) {
          CalendarColorPicker(colorID: $colorID, extended: extendedColors)
        }
        if event != nil {
          Section {
            Button(store.text("Удалить событие", "Delete event"), role: .destructive) {
              confirmDelete = true
            }.disabled(!store.canWrite || busy)
          }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(
        store.text(
          event == nil ? "Новое событие" : "Изменить событие",
          event == nil ? "New event" : "Edit event")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Отмена", "Cancel")) { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(store.text("Сохранить", "Save")) { Task { await save() } }.disabled(
            !store.canWrite || busy || !initialized)
        }
      }
      .interactiveDismissDisabled(busy)
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
