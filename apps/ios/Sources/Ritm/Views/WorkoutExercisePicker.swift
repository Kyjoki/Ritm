import RitmCore
import SwiftUI

/// `.sheet.tall`: pick an exercise by search and muscle group, or create the owner's own from
/// the search text. Exercises in `used` are shown dimmed.
struct WorkoutExercisePicker: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let title: String
  let used: Set<String>
  let usedNote: String
  let onPick: (WorkoutExercise) -> Void
  @State private var query = ""
  @State private var muscle: WorkoutMuscle?

  private var exercises: [WorkoutExercise] {
    WorkoutCatalog.search(
      query, muscle: muscle, custom: store.workouts.library.customExercises, language: store.language)
  }

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).ritmFont(19, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
        .padding(.horizontal, 4).padding(.bottom, 10)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 10) {
        RitmSymbol("magnifyingglass").font(.system(size: 18)).foregroundStyle(RitmTheme.muted)
        TextField(store.text("Поиск", "Search"), text: $query)
          .ritmFont(15.5).foregroundStyle(RitmTheme.text)
          .submitLabel(.search).autocorrectionDisabled()
      }
      .padding(.horizontal, 14).frame(height: 46)
      .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
      chips
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(exercises) { exercise in row(exercise) }
          if exercises.isEmpty { empty }
        }
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .padding(.horizontal, 16).padding(.top, 22)
    .background(RitmTheme.background)
    .presentationDetents([.large])
    .ritmSheetGrabber()
  }

  /// `.gchips`: «Все» and the muscle groups.
  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        chip(store.text("Все", "All"), selected: muscle == nil) { muscle = nil }
        ForEach(WorkoutMuscle.allCases, id: \.self) { group in
          chip(group.title(language: store.language), selected: muscle == group) { muscle = group }
        }
      }
      .padding(.vertical, 12)
    }
  }

  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).ritmFont(13, weight: .semibold)
        .foregroundStyle(selected ? RitmTheme.ctaInk : RitmTheme.muted)
        .padding(.horizontal, 14).frame(height: 32)
        .background {
          if selected {
            Capsule().fill(RitmTheme.ctaGradient)
          } else {
            Capsule().fill(WorkoutPalette.inset)
              .overlay { Capsule().strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
          }
        }
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle())
    .padding(.vertical, -6)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func row(_ exercise: WorkoutExercise) -> some View {
    let taken = used.contains(exercise.id)
    return Button {
      onPick(exercise)
      dismiss()
    } label: {
      HStack(spacing: 10) {
        Text(exercise.name).ritmFont(15, weight: .medium).foregroundStyle(RitmTheme.text)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 8)
        if taken {
          Text(usedNote).ritmFont(11).foregroundStyle(RitmTheme.muted)
        } else if let group = exercise.muscle {
          WorkoutMuscleChip(muscle: group)
        }
      }
      .padding(.horizontal, 6)
      .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
      .opacity(taken ? 0.5 : 1)
    }
    .buttonStyle(.plain)
    .disabled(taken)
  }

  @ViewBuilder private var empty: some View {
    VStack(spacing: 12) {
      Text(store.text("Ничего не найдено", "Nothing found")).ritmFont(14).foregroundStyle(RitmTheme.muted)
      if trimmedQuery.count >= 2 {
        Button(action: create) {
          Text(store.text("Создать «\(trimmedQuery)»", "Create “\(trimmedQuery)”"))
            .ritmFont(13.5, weight: .bold)
        }
        .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
      }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 40)
  }

  private func create() {
    guard let exercise = store.workouts.createExercise(named: trimmedQuery, muscle: muscle) else { return }
    guard !used.contains(exercise.id) else {
      store.toasts.show(store.text("Это упражнение уже есть.", "This exercise is already there."))
      return
    }
    onPick(exercise)
    dismiss()
  }
}
