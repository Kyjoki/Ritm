import RitmCore
import SwiftUI

// «Настройки тренировок» and the record editor: the two sheets of the home screen.

// MARK: - Settings

/// `.sheet` «Настройки тренировок»: which habit a finished workout ticks (or none).
struct WorkoutSettingsSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  private var habits: [Habit] { store.habits.filter { $0.archived != true } }
  private var linked: String? { store.workouts.settings.linkedHabitID }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 4) {
        Text(store.text("Настройки тренировок", "Workout settings"))
          .ritmFont(19, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
          .padding(.horizontal, 4).padding(.bottom, 8)
          .accessibilityAddTraits(.isHeader)
        Text(store.text("Связь с привычкой", "Habit link").uppercased())
          .ritmFont(12, weight: .semibold, tracking: 0.06).foregroundStyle(RitmTheme.muted)
          .padding(.horizontal, 4).padding(.bottom, 6)
        ForEach(habits) { habit in
          option(
            icon: habitSymbol(habit.icon), title: habit.title, note: weeklyNote(habit),
            selected: linked == habit.id
          ) { store.workouts.setLinkedHabit(habit.id) }
        }
        option(
          icon: "xmark", title: store.text("Без привычки", "No habit"),
          note: store.text("Тренировки не отмечают привычки", "Workouts do not tick habits"),
          selected: linked == nil || !habits.contains { $0.id == linked }
        ) { store.workouts.setLinkedHabit(nil) }
        Text(
          store.text(
            "Завершённая тренировка один раз в день отмечает выбранную привычку. Кольцо недели показывает её дни.",
            "A finished workout ticks the chosen habit once a day. The weekly ring shows its days.")
        )
        .ritmFont(12).foregroundStyle(RitmTheme.muted).padding(.horizontal, 4).padding(.top, 8)
        Button { dismiss() } label: {
          Text(store.text("Готово", "Done")).ritmFont(16, weight: .bold)
        }
        .buttonStyle(RitmPrimaryButtonStyle(minHeight: 52))
        .padding(.top, 14)
      }
      .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)
    }
    .background(RitmTheme.background)
    .presentationDetents([.medium, .large])
    .ritmSheetGrabber()
  }

  private func weeklyNote(_ habit: Habit) -> String {
    let days = (habit.weekdays ?? HabitSchedule.allWeekdays).count
    return store.text(
      "\(days) " + WorkoutText.plural(days, "день", "дня", "дней") + " в неделю",
      "\(days) " + (days == 1 ? "day" : "days") + " a week")
  }

  private func option(
    icon: String, title: String, note: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        RitmSymbol(icon).font(.system(size: 16)).foregroundStyle(RitmTheme.muted)
          .frame(width: 32, height: 32)
          .background(WorkoutPalette.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        VStack(alignment: .leading, spacing: 0) {
          Text(title).ritmFont(14.5, weight: .semibold, tracking: -0.02).foregroundStyle(RitmTheme.text)
          Text(note).ritmFont(11.5).foregroundStyle(RitmTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if selected {
          RitmSymbol("checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(RitmTheme.accentColor)
        }
      }
      .padding(.horizontal, 12).padding(.vertical, 10)
      .frame(minHeight: 52)
      .background {
        if selected {
          RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RitmTheme.soft)
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RitmTheme.accentColor, lineWidth: 1.5) }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

// MARK: - Record

/// `.sheet.rs`: a record's exercise, weight, reps and date; «Сохранить», and «Удалить рекорд» for
/// an existing one. A manual edit overrides what the history says for that exercise.
struct WorkoutRecordSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let target: WorkoutRecordTarget
  @State private var exerciseID = WorkoutCatalog.builtinID("bench")
  @State private var weightText = "60"
  @State private var repsText = "5"
  @State private var date = Date()
  @State private var loaded = false
  @State private var deleting = false

  private var russian: Bool { store.language == .ru }
  private var exercises: [WorkoutExercise] { store.workouts.allExercises(language: store.language) }
  private var exerciseName: String { exercises.first { $0.id == exerciseID }?.name ?? "" }
  private var weight: Double? { WorkoutNumber.weight(weightText).flatMap { $0 > 0 ? $0 : nil } }
  private var reps: Int? { WorkoutNumber.reps(repsText) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(target.card == nil ? store.text("Новый рекорд", "New record") : store.text("Рекорд", "Record"))
          .ritmFont(19, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
          .padding(.horizontal, 4).padding(.bottom, 4)
          .accessibilityAddTraits(.isHeader)
        label(store.text("Упражнение", "Exercise"))
        exercisePicker
        label(store.text("Вес, кг", "Weight, kg"))
        stepRow(
          text: $weightText, minus: "−2,5", plus: "+2,5", keyboard: .decimalPad,
          minusAction: { weightText = WorkoutStepper.weight(weightText, delta: -2.5, comma: russian) },
          plusAction: { weightText = WorkoutStepper.weight(weightText, delta: 2.5, comma: russian) })
        label(store.text("Повторы", "Reps"))
        stepRow(
          text: $repsText, minus: "−1", plus: "+1", keyboard: .numberPad,
          minusAction: { repsText = WorkoutStepper.reps(repsText, delta: -1) },
          plusAction: { repsText = WorkoutStepper.reps(repsText, delta: 1) })
        label(store.text("Дата", "Date"))
        DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
          .labelsHidden()
          .environment(\.locale, Locale(identifier: russian ? "ru_RU" : "en_US"))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12).frame(height: 52)
          .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
        Button(action: save) {
          Text(store.text("Сохранить", "Save")).ritmFont(16, weight: .bold)
        }
        .buttonStyle(RitmPrimaryButtonStyle(minHeight: 52))
        .disabled(weight == nil || reps == nil)
        .padding(.top, 16)
        if target.card != nil {
          Button { deleting = true } label: {
            HStack(spacing: 8) {
              RitmSymbol("trash").font(.system(size: 18))
              Text(store.text("Удалить рекорд", "Delete record")).ritmFont(14.5, weight: .bold)
            }
            .foregroundStyle(RitmTheme.danger)
            .frame(maxWidth: .infinity, minHeight: 50)
            .ritmGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
          }
          .buttonStyle(RitmGlassButtonStyle())
          .padding(.top, 8)
        }
      }
      .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(RitmTheme.background)
    .presentationDetents([.large])
    .ritmSheetGrabber()
    .onAppear(perform: load)
    .alert(store.text("Удалить рекорд?", "Delete the record?"), isPresented: $deleting) {
      Button(store.text("Удалить", "Delete"), role: .destructive) {
        if let card = target.card { store.workouts.deleteRecord(exerciseID: card.exerciseID, name: card.name) }
        dismiss()
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    }
  }

  private func load() {
    guard !loaded else { return }
    loaded = true
    guard let card = target.card else { return }
    exerciseID = card.exerciseID
    weightText = WorkoutFormat.weight(card.weight, comma: russian)
    repsText = String(card.reps)
    date = card.date
  }

  private func label(_ text: String) -> some View {
    Text(text.uppercased()).ritmFont(12, weight: .semibold, tracking: 0.06)
      .foregroundStyle(RitmTheme.muted)
      .padding(.horizontal, 4).padding(.top, 18).padding(.bottom, 8)
  }

  private var exercisePicker: some View {
    Menu {
      Picker(store.text("Упражнение", "Exercise"), selection: $exerciseID) {
        ForEach(exercises) { Text($0.name).tag($0.id) }
      }
    } label: {
      HStack {
        Text(exerciseName).ritmFont(17, weight: .semibold, tracking: -0.02).foregroundStyle(RitmTheme.text)
          .lineLimit(1)
        Spacer(minLength: 8)
        RitmSymbol("chevron.up.chevron.down").font(.system(size: 14)).foregroundStyle(RitmTheme.muted)
      }
      .padding(.horizontal, 16).frame(height: 52)
      .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
      .contentShape(Rectangle())
    }
  }

  /// `.nstep`: a step button, the typed value and the opposite step button.
  private func stepRow(
    text: Binding<String>, minus: String, plus: String, keyboard: UIKeyboardType,
    minusAction: @escaping () -> Void, plusAction: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 8) {
      stepButton(minus, action: minusAction)
      TextField("", text: text)
        .keyboardType(keyboard)
        .multilineTextAlignment(.center)
        .ritmFont(17, weight: .semibold).monospacedDigit().foregroundStyle(RitmTheme.text)
        .frame(height: 52)
        .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
      stepButton(plus, action: plusAction)
    }
  }

  private func stepButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).ritmFont(15, weight: .bold).foregroundStyle(RitmTheme.accentColor)
        .frame(width: 72, height: 52)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.94))
  }

  private func save() {
    guard let weight, let reps else { return }
    // Moving a record to another exercise removes it from the old one.
    if let card = target.card, card.exerciseID != exerciseID {
      store.workouts.deleteRecord(exerciseID: card.exerciseID, name: card.name)
    }
    store.workouts.saveRecord(
      exerciseID: exerciseID, name: exerciseName, weight: weight, reps: reps, date: date)
    dismiss()
  }
}
