import RitmCore
import SwiftUI

/// The habit sheet (`HabitEditor`): name, icon, weekdays, an optional numeric goal, Cancel / Save.
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
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          nameField
          iconField
          weekdayField
          goalField
          if let message = store.errorMessage { RitmErrorBanner(message: message) }
          if store.uncertainWrite {
            Button(store.text("Закрыть и проверить список", "Close and check list")) { dismiss() }
              .buttonStyle(HabitCapsuleStyle())
          }
          buttons
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
    }
    .presentationDetents([.large])
    .ritmSheetGrabber()
    .presentationCornerRadius(22)
    .interactiveDismissDisabled(busy)
  }

  // MARK: Blocks

  private var header: some View {
    HStack(alignment: .center) {
      Text(
        habit == nil
          ? store.text("Новая привычка", "New habit") : store.text("Изменить привычку", "Edit habit")
      )
      .ritmFont(20, weight: .semibold, tracking: -0.045)
      .foregroundStyle(RitmTheme.text)
      .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 12)
      HabitIconButton(symbol: "xmark", label: store.text("Закрыть", "Close")) { dismiss() }
        .disabled(busy)
    }
    .padding(.top, 20)
  }

  private var nameField: some View {
    let tooLong = title.utf16.count > 80
    return section(store.text("Название", "Name")) {
      VStack(alignment: .leading, spacing: 0) {
        TextField(
          store.text("Например, чтение", "For example, reading"), text: $title, axis: .vertical
        )
        .lineLimit(2...4)
        .ritmFont(14)
        .foregroundStyle(RitmTheme.text)
        .padding(12)
        Text("\(title.utf16.count) / 80")
          .ritmFont(11)
          .foregroundStyle(tooLong ? RitmTheme.danger : RitmTheme.muted)
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
      }
      .habitBox()
    }
  }

  private var iconField: some View {
    section(store.text("Значок", "Icon")) {
      ScrollView(.horizontal) {
        HStack(spacing: 4) {
          ForEach(HabitIcon.allCases, id: \.self) { value in
            Button {
              icon = value
            } label: {
              RitmSymbol(habitSymbol(value))
                .font(.system(size: 20))
                .foregroundStyle(icon == value ? RitmTheme.accentColor : RitmTheme.text)
                .frame(width: 44, height: 44)
                .background(
                  icon == value ? RitmTheme.accentColor.opacity(0.23) : .clear,
                  in: RoundedRectangle(cornerRadius: 10, style: .circular))
            }
            .buttonStyle(RitmPressStyle())
            .accessibilityLabel(value.rawValue)
            .accessibilityAddTraits(icon == value ? .isSelected : [])
          }
        }
        .padding(4)
      }
      .scrollIndicators(.hidden)
      .habitBox()
    }
  }

  private var weekdayField: some View {
    VStack(alignment: .leading, spacing: 0) {
      section(store.text("Дни недели", "Weekdays")) {
        VStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { day in
            if day > 0 { divider }
            switchRow(
              weekdayName(day, russian: store.language == .ru),
              isOn: Binding(
                get: { weekdays.contains(day) },
                set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
          }
        }
        .habitBox()
      }
      if weekdays.isEmpty {
        Text(store.text("Выберите хотя бы один день.", "Choose at least one day."))
          .ritmFont(12)
          .foregroundStyle(RitmTheme.danger)
          .padding(.top, 6)
          .padding(.horizontal, 2)
      }
    }
  }

  private var goalField: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(spacing: 0) {
        switchRow(store.text("Количественная цель", "Quantity target"), isOn: $quantitative)
        if quantitative {
          TextField(store.text("Цель (1–10000)", "Target (1–10000)"), text: $target)
            .keyboardType(.numberPad)
            .ritmFont(14)
            .foregroundStyle(RitmTheme.text)
            .padding(12)
          divider
          TextField(
            store.text("Единица: минуты, стаканы…", "Unit: minutes, glasses…"), text: $unit
          )
          .ritmFont(14)
          .foregroundStyle(RitmTheme.text)
          .padding(12)
        }
      }
      .habitBox()
      Text(
        store.text(
          "Изменение расписания не переписывает прошлые отметки.",
          "Schedule changes preserve historical marks."
        )
      )
      .ritmFont(12)
      .foregroundStyle(RitmTheme.muted)
      .padding(.top, 8)
      .padding(.horizontal, 2)
    }
  }

  private var buttons: some View {
    HStack(spacing: 10) {
      Button(store.text("Отмена", "Cancel")) { dismiss() }
        .buttonStyle(HabitCapsuleStyle())
        .frame(maxWidth: .infinity)
        .disabled(busy)
      Button(store.text("Сохранить", "Save")) { Task { await save() } }
        .buttonStyle(HabitCapsuleStyle(prominent: true))
        .frame(maxWidth: .infinity)
        .disabled(!valid || busy || !store.canWrite)
    }
  }

  // MARK: Pieces

  /// `.sf-l`: the small uppercase label above a box.
  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .ritmFont(11, weight: .semibold, tracking: 0.05)
        .textCase(.uppercase)
        .foregroundStyle(RitmTheme.muted)
      content()
    }
  }

  private var divider: some View {
    Rectangle().fill(RitmTheme.line).frame(height: 1)
  }

  /// `.sf-row`: a 46 pt row with a label and a switch.
  private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
      Text(title).ritmFont(14).foregroundStyle(RitmTheme.text)
    }
    .tint(RitmTheme.accentColor)
    .padding(.horizontal, 14)
    .frame(minHeight: 46)
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

extension View {
  /// `.sf-box`: a 14 pt rounded field surface with a hairline.
  fileprivate func habitBox() -> some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    return background(RitmTheme.field, in: shape)
      .overlay { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
      .clipShape(shape)
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
