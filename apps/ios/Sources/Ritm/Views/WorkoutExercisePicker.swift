import RitmCore
import SwiftUI

/// Choose an exercise from the catalog or create the owner's own. Used by the program editor
/// (add, replace) and by an active workout (replace). Exercises in `used` are shown dimmed.
struct WorkoutExercisePicker: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let title: String
  let used: Set<String>
  let usedNote: String
  let createLabel: String
  let onPick: (WorkoutExercise) -> Void
  @State private var query = ""
  @State private var newName = ""
  @State private var error: String?

  private var exercises: [WorkoutExercise] {
    let all = store.workouts.allExercises(language: store.language)
    let key = query.trimmingCharacters(in: .whitespaces).lowercased()
    return key.isEmpty ? all : all.filter { $0.name.lowercased().contains(key) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(title).ritmText(.sectionTitle).foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button(store.text("Закрыть", "Close")) { dismiss() }
          .buttonStyle(RitmTextButtonStyle(size: 13))
      }
      .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          field(store.text("Найти упражнение", "Search exercises"), text: $query, search: true)
          LazyVStack(spacing: 0) {
            ForEach(exercises) { exercise in row(exercise) }
          }
          VStack(alignment: .leading, spacing: 8) {
            Text(store.text("Своё упражнение", "Your own exercise"))
              .ritmFont(12, weight: .medium).foregroundStyle(RitmTheme.muted)
            field(
              store.text("Например, Тяга гантели в наклоне", "For example, One-arm dumbbell row"),
              text: $newName, search: false)
            Button(createLabel, action: create).buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
            if let error {
              Text(error).ritmText(.body).foregroundStyle(RitmTheme.danger)
                .accessibilityAddTraits(.updatesFrequently)
            }
          }
          .padding(.top, 8)
        }
        .padding(.horizontal, 20).padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .background(RitmTheme.background)
    .presentationDetents([.large])
  }

  private func field(_ placeholder: String, text: Binding<String>, search: Bool) -> some View {
    TextField(placeholder, text: text)
      .ritmFont(14)
      .foregroundStyle(RitmTheme.text)
      .submitLabel(search ? .search : .done)
      .autocorrectionDisabled()
      .padding(.horizontal, 12)
      .frame(minHeight: 46)
      .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .circular))
      .overlay { RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
  }

  private func row(_ exercise: WorkoutExercise) -> some View {
    let taken = used.contains(exercise.id)
    return Button {
      onPick(exercise)
      dismiss()
    } label: {
      HStack(spacing: 8) {
        Text(exercise.name).ritmFont(14, weight: .medium).foregroundStyle(RitmTheme.text)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 8)
        if taken { Text(usedNote).ritmFont(11).foregroundStyle(RitmTheme.muted) }
      }
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .contentShape(Rectangle())
      .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
      .opacity(taken ? 0.5 : 1)
    }
    .buttonStyle(.plain)
    .disabled(taken)
  }

  private func create() {
    guard let exercise = store.workouts.createExercise(named: newName) else {
      error = store.text("Введите название, минимум 2 символа.", "Enter a name of at least 2 characters.")
      return
    }
    guard !used.contains(exercise.id) else {
      error = store.text("Это упражнение уже есть.", "This exercise is already there.")
      return
    }
    onPick(exercise)
    dismiss()
  }
}
