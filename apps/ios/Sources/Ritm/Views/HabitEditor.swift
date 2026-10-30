import RitmCore
import SwiftUI

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
    if result != nil {
      store.toasts.show(
        habit == nil
          ? store.text("Привычка добавлена", "Habit added")
          : store.text("Привычка сохранена", "Habit saved"))
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
