import RitmCore
import SwiftUI

struct NativeTaskEditor: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let task: RitmTask?
  let initialDate: String?
  let occurrenceDate: String?
  let onSave: (() async -> Void)?
  @State private var title = ""
  @State private var details = ""
  @State private var dated = false
  @State private var date = ""
  @State private var timed = false
  @State private var time = "09:00"
  @State private var duration = 30
  @State private var priority: Priority = .normal
  @State private var recurrence: TaskRepeat = .none
  @State private var kind: TaskKind = .task
  @State private var colorID = ""
  @State private var completed = false
  @State private var busy = false
  @State private var validation: String?
  @State private var confirmDelete = false
  @State private var confirmTransfer = false
  @State private var deleted: RitmTask?

  init(
    task: RitmTask? = nil, initialDate: String? = nil, occurrenceDate: String? = nil,
    onSave: (() async -> Void)? = nil
  ) {
    self.task = task
    self.initialDate = initialDate
    self.occurrenceDate = occurrenceDate
    self.onSave = onSave
    _title = State(initialValue: task?.title ?? "")
    _details = State(initialValue: task?.description ?? "")
    _dated = State(initialValue: task?.date != nil || initialDate != nil)
    _date = State(initialValue: task?.date ?? initialDate ?? "")
    _timed = State(initialValue: task?.time != nil)
    _time = State(initialValue: task?.time ?? "09:00")
    _duration = State(initialValue: task?.duration ?? 30)
    _priority = State(initialValue: task?.priority ?? .normal)
    _recurrence = State(initialValue: task?.repeat ?? .none)
    _kind = State(initialValue: task?.kind ?? .task)
    _colorID = State(initialValue: task?.colorId ?? "")
    _completed = State(initialValue: task?.completed ?? false)
  }
  var body: some View {
    NavigationStack {
      Form {
        if let validation { Section { RitmErrorBanner(message: validation) } }
        if let error = store.errorMessage { Section { RitmErrorBanner(message: error) } }
        Section {
          if task == nil && store.uncertainWrite {
            Button(store.text("Закрыть и проверить список", "Close and check the list")) {
              dismiss()
            }
            .disabled(busy)
          } else {
            MutationRecoveryView()
          }
        }
        if let deleted {
          Section {
            Label(store.text("Задача удалена", "Task deleted"), systemImage: "trash")
            Button(store.text("Восстановить", "Restore")) {
              Task {
                busy = true
                let restored = await store.write { try await $0.restoreTask(deleted) }
                busy = false
                if restored != nil {
                  self.deleted = nil
                  await onSave?()
                  dismiss()
                }
              }
            }.disabled(!store.canWrite || busy)
          }
        } else {
          Section {
            TextField(store.text("Название", "Title"), text: $title, axis: .vertical).lineLimit(
              1...4)
            TextField(store.text("Описание", "Description"), text: $details, axis: .vertical)
              .lineLimit(3...8)
            Picker(store.text("Тип", "Type"), selection: $kind) {
              Text(store.text("Задача", "Task")).tag(TaskKind.task)
              Text(store.text("Событие", "Event")).tag(TaskKind.event)
            }
            Picker(store.text("Приоритет", "Priority"), selection: $priority) {
              Text(store.text("Низкий", "Low")).tag(Priority.low)
              Text(store.text("Обычный", "Normal")).tag(Priority.normal)
              Text(store.text("Высокий", "High")).tag(Priority.high)
            }
          }
          Section(store.text("Расписание", "Schedule")) {
            Toggle(store.text("Назначить дату", "Set date"), isOn: $dated)
            if dated {
              DateKeyPicker(title: store.text("Дата", "Date"), value: $date, zone: store.timeZone)
              Toggle(store.text("Указать время", "Set time"), isOn: $timed)
              if timed { TextField("HH:mm", text: $time).keyboardType(.numbersAndPunctuation) }
              Stepper(
                store.text("Длительность: ", "Duration: ") + "\(duration) "
                  + store.text("мин", "min"), value: $duration, in: 5...720, step: 5)
              Picker(store.text("Повтор", "Repeat"), selection: $recurrence) { recurrenceOptions }
            }
            if task != nil && task?.repeat != TaskRepeat.none {
              Text(
                store.text(
                  "Изменение расписания относится ко всей серии. Отметка выполнения — к выбранной дате.",
                  "Schedule edits affect the series. Completion applies to the selected date.")
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
          Section(store.text("Цвет", "Color")) { CalendarColorPicker(colorID: $colorID) }
          if let task {
            Section {
              Button(
                task.isComplete(on: occurrenceDate ?? task.date ?? store.today)
                  ? store.text("Вернуть в работу", "Mark incomplete")
                  : store.text("Отметить выполненной", "Mark complete")
              ) {
                Task {
                  busy = true
                  let result = await store.write {
                    try await $0.setTaskCompleted(
                      id: task.id,
                      completed: !task.isComplete(on: occurrenceDate ?? task.date ?? store.today),
                      occurrenceDate: task.repeat == .none
                        ? nil : occurrenceDate ?? task.date ?? store.today)
                  }
                  busy = false
                  if result != nil {
                    await onSave?()
                    dismiss()
                  }
                }
              }.disabled(!store.canWrite || busy)
              if task.calendarEntry != false && task.date != nil && !task.completed
                && task.completedDates.isEmpty
              {
                Button(store.text("Перенести в Google Calendar", "Move to Google Calendar")) {
                  confirmTransfer = true
                }.disabled(!store.canWrite || busy)
              }
              Button(store.text("Удалить задачу", "Delete task"), role: .destructive) {
                confirmDelete = true
              }.disabled(!store.canWrite || busy)
            }
          }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(
        store.text(task == nil ? "Новая задача" : "Задача", task == nil ? "New task" : "Task")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Закрыть", "Close")) { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          if deleted == nil {
            Button(store.text("Сохранить", "Save")) { Task { await save() } }.disabled(
              !store.canWrite || busy)
          }
        }
      }
      .interactiveDismissDisabled(busy)
      .task { if date.isEmpty { date = store.today } }
      .confirmationDialog(
        store.text("Удалить задачу?", "Delete task?"), isPresented: $confirmDelete,
        titleVisibility: .visible
      ) {
        Button(store.text("Удалить", "Delete"), role: .destructive) {
          guard let task else { return }
          Task {
            busy = true
            deleted = await store.write { try await $0.deleteTask(id: task.id) }
            busy = false
            if deleted != nil {
              store.toasts.show(store.text("Задача удалена", "Task deleted"))
              await onSave?()
            }
          }
        }
      } message: {
        Text(
          task?.repeat != TaskRepeat.none && task != nil
            ? store.text(
              "Будет удалена вся серия с историей выполнения. После удаления здесь можно нажать «Восстановить».",
              "The entire series and its completion history will be deleted. You can restore it here after deletion."
            )
            : store.text(
              "После удаления здесь можно нажать «Восстановить».",
              "You can restore the task here after deletion."))
      }
      .confirmationDialog(
        store.text("Перенести запись в Google?", "Move this entry to Google?"),
        isPresented: $confirmTransfer, titleVisibility: .visible
      ) {
        Button(store.text("Перенести", "Move")) {
          guard let task else { return }
          Task {
            busy = true
            let result = await store.write { try await $0.transferTaskToGoogle(id: task.id) }
            busy = false
            if result != nil {
              await onSave?()
              dismiss()
            }
          }
        }
      } message: {
        Text(
          store.text(
            "После успешного переноса локальная запись будет заменена событием Google.",
            "After a successful transfer the local entry is replaced by a Google event."))
      }
    }
  }
  private var recurrenceOptions: some View {
    Group {
      Text(store.text("Не повторять", "Never")).tag(TaskRepeat.none)
      Text(store.text("Каждый день", "Daily")).tag(TaskRepeat.daily)
      Text(store.text("Каждую неделю", "Weekly")).tag(TaskRepeat.weekly)
      Text(store.text("Каждый месяц", "Monthly")).tag(TaskRepeat.monthly)
    }
  }
  private func save() async {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title.utf16.count <= 160, details.utf16.count <= 4000,
      !dated || HabitSchedule.isValidDate(date),
      !dated || !timed || (TaskSchedule.timeMinutes(time).map { $0 + duration <= 1440 } == true)
    else {
      validation = store.text(
        "Проверьте название (до 160 символов), описание (до 4000), дату и время HH:mm. Запись должна завершиться до полуночи.",
        "Check the title (160 characters), description (4000), date and HH:mm time. The entry must end by midnight."
      )
      return
    }
    validation = nil
    busy = true
    let input = TaskInput(
      title: title, description: details, date: dated ? date : nil,
      time: dated && timed ? time : nil,
      duration: duration, priority: priority, repeat: dated ? recurrence : .none, kind: kind,
      completed: dated && recurrence != .none ? false : completed,
      calendarEntry: kind == .event ? true : (task == nil ? false : task?.calendarEntry),
      colorId: colorID.isEmpty ? nil : colorID)
    let result = await store.write { client in
      if let task {
        let patch = TaskPatch(
          title: input.title, description: input.description,
          date: input.date.map(NullableField.value) ?? .null,
          time: input.time.map(NullableField.value) ?? .null,
          duration: input.duration, priority: input.priority, repeat: input.repeat,
          kind: input.kind, completed: input.completed, calendarEntry: input.calendarEntry,
          colorId: input.colorId.map(NullableField.value) ?? .null)
        return try await client.updateTask(id: task.id, patch: patch)
      }
      return try await client.createTask(input)
    }
    busy = false
    if result != nil {
      store.toasts.show(
        task == nil && input.date != nil
          ? store.text("Запись добавлена в календарь", "Entry added to calendar")
          : store.text("Задача сохранена", "Task saved"))
      await onSave?()
      dismiss()
    }
  }
}
