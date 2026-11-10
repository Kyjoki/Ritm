import RitmCore
import SwiftUI

/// One muscle group to choose from: the tint of the muscle chip, filled when chosen.
struct WorkoutMuscleChoiceChip: View {
  let title: String
  var tint: Color?
  let selected: Bool
  let action: () -> Void

  var body: some View {
    let color = tint ?? RitmTheme.accentColor
    Button(action: action) {
      Text(title).ritmFont(13, weight: .semibold)
        .foregroundStyle(selected ? RitmTheme.mix(color, 0.72, into: RitmTheme.text) : RitmTheme.muted)
        .padding(.horizontal, 14).frame(height: 32)
        .background {
          Capsule().fill(selected ? color.opacity(0.26) : WorkoutPalette.inset)
            .overlay { Capsule().strokeBorder(selected ? color : WorkoutPalette.stroke, lineWidth: 1) }
        }
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle())
    .padding(.vertical, -6)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// A single choice of the group of a new exercise; tapping the chosen one clears it.
struct WorkoutMuscleChoiceRow: View {
  @Environment(RitmStore.self) private var store
  @Binding var selection: WorkoutMuscle?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(WorkoutMuscle.allCases, id: \.self) { group in
          WorkoutMuscleChoiceChip(
            title: group.title(language: store.language), tint: WorkoutPalette.color(group),
            selected: selection == group
          ) { selection = selection == group ? nil : group }
        }
      }
      .padding(.vertical, 6)
    }
  }
}

/// «Группа мышц…»: pick, change or clear the group of an exercise the owner created. It is
/// written to the exercise itself, so programs, the running workout, history and records all
/// show it.
struct WorkoutMuscleSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let exercise: WorkoutExercise

  private var current: WorkoutMuscle? {
    store.workouts.library.customExercises.first { $0.id == exercise.id }?.muscle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(exercise.name).ritmFont(19, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
      Text(store.text("Группа мышц", "Muscle group").uppercased())
        .ritmFont(12, weight: .semibold, tracking: 0.06).foregroundStyle(RitmTheme.muted)
        .padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 10)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
        ForEach(WorkoutMuscle.allCases, id: \.self) { group in
          WorkoutMuscleChoiceChip(
            title: group.title(language: store.language), tint: WorkoutPalette.color(group),
            selected: current == group
          ) { set(group) }
        }
        WorkoutMuscleChoiceChip(
          title: store.text("Без группы", "No group"), selected: current == nil
        ) { set(nil) }
      }
      Text(
        store.text(
          "Группа сохраняется в самом упражнении: она появится в программах, тренировке и истории.",
          "The group is saved on the exercise itself: it shows in programs, the workout and history."))
        .ritmFont(12).foregroundStyle(RitmTheme.muted)
        .padding(.horizontal, 4).padding(.top, 16)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RitmTheme.background)
    .presentationDetents([.medium])
    .ritmSheetGrabber()
  }

  private func set(_ group: WorkoutMuscle?) {
    store.workouts.setExerciseMuscle(group, ofExercise: exercise.id)
    dismiss()
  }
}
