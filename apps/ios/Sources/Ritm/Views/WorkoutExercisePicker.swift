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
  @State private var filter: WorkoutMuscleFilter = .any
  /// The group of the exercise being created; the chip row above it can pre-fill it.
  @State private var newGroup: WorkoutMuscle?
  @State private var tagging: WorkoutExercise?

  private var custom: [WorkoutExercise] { store.workouts.library.customExercises }

  private var exercises: [WorkoutExercise] {
    WorkoutCatalog.search(query, filter: filter, custom: custom, language: store.language)
  }

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

  /// «Создать» is offered for a name of 2+ characters that no exercise already has.
  private var canCreate: Bool {
    trimmedQuery.count >= 2
      && !WorkoutCatalog.all(custom: custom, language: store.language)
        .contains { $0.name.lowercased() == trimmedQuery.lowercased() }
  }

  private var hasUngrouped: Bool { WorkoutCatalog.hasUngrouped(custom: custom) }

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
          if canCreate { creator }
        }
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .sheet(item: $tagging) { WorkoutMuscleSheet(exercise: $0) }
    .onChange(of: filter) { _, next in if case .group(let group) = next { newGroup = group } }
    .padding(.horizontal, 16).padding(.top, 22)
    .background(RitmTheme.background)
    .presentationDetents([.large])
    .ritmSheetGrabber()
  }

  /// `.gchips`: «Все» and the muscle groups.
  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        chip(store.text("Все", "All"), selected: filter == .any) { filter = .any }
        ForEach(WorkoutMuscle.allCases, id: \.self) { group in
          chip(group.title(language: store.language), selected: filter == .group(group)) {
            filter = .group(group)
          }
        }
        if hasUngrouped || filter == .none {
          chip(store.text("Без группы", "No group"), selected: filter == .none) { filter = .none }
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
    let isCustom = custom.contains { $0.id == exercise.id }
    return HStack(spacing: 4) {
      Button {
        onPick(exercise)
        dismiss()
      } label: {
        Text(exercise.name).ritmFont(15, weight: .medium).foregroundStyle(RitmTheme.text)
          .multilineTextAlignment(.leading)
          .padding(.leading, 6)
          .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
          .contentShape(Rectangle())
          .opacity(taken ? 0.5 : 1)
      }
      .buttonStyle(.plain)
      .disabled(taken)
      trailing(exercise, taken: taken, isCustom: isCustom)
    }
    .padding(.trailing, 6)
    .frame(maxWidth: .infinity, minHeight: 50)
    .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
    .contextMenu {
      if isCustom {
        Button { tagging = exercise } label: {
          Label(store.text("Группа мышц…", "Muscle group…"), systemImage: "tag")
        }
      }
    }
  }

  /// The muscle chip (tap it to change the group of an own exercise), «＋ группа» for an own
  /// exercise without one, or the «уже в …» note.
  @ViewBuilder private func trailing(_ exercise: WorkoutExercise, taken: Bool, isCustom: Bool) -> some View {
    if taken {
      Text(usedNote).ritmFont(11).foregroundStyle(RitmTheme.muted).opacity(0.5)
    }
    if let group = exercise.muscle {
      if isCustom {
        Button { tagging = exercise } label: {
          WorkoutMuscleChip(muscle: group).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.text("Группа мышц: \(group.title(language: store.language))", "Muscle group: \(group.title(language: store.language))"))
      } else if !taken {
        WorkoutMuscleChip(muscle: group)
      }
    } else if isCustom {
      Button { tagging = exercise } label: {
        Text(store.text("＋ группа", "+ group")).ritmFont(11.5, weight: .semibold)
          .foregroundStyle(RitmTheme.accentColor)
          .padding(.horizontal, 10).frame(height: 24)
          .overlay { Capsule().strokeBorder(RitmTheme.accentColor.opacity(0.5), lineWidth: 1) }
          .frame(minHeight: 44).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(store.text("Выбрать группу мышц для «\(exercise.name)»", "Choose a muscle group for “\(exercise.name)”"))
    }
  }

  @ViewBuilder private var empty: some View {
    Text(store.text("Ничего не найдено", "Nothing found")).ritmFont(14).foregroundStyle(RitmTheme.muted)
      .frame(maxWidth: .infinity).padding(.vertical, 28)
  }

  /// «Создать «…»»: the new name with an optional single-choice group.
  private var creator: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(store.text("Своё упражнение · группа мышц", "Your own exercise · muscle group").uppercased())
        .ritmFont(11.5, weight: .semibold, tracking: 0.06).foregroundStyle(RitmTheme.muted)
        .padding(.horizontal, 4)
      WorkoutMuscleChoiceRow(selection: $newGroup)
      Button(action: create) {
        Text(store.text("Создать «\(trimmedQuery)»", "Create “\(trimmedQuery)”"))
          .ritmFont(13.5, weight: .bold)
      }
      .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
      .padding(.top, 4)
      if newGroup == nil {
        Text(store.text("Без группы упражнение не найдётся по фильтрам, группу можно выбрать позже.", "Without a group it will not show under the group chips; you can choose one later."))
          .ritmFont(11.5).foregroundStyle(RitmTheme.muted).padding(.horizontal, 4)
      }
    }
    .padding(.vertical, 18)
  }

  private func create() {
    guard let exercise = store.workouts.createExercise(named: trimmedQuery, muscle: newGroup) else { return }
    guard !used.contains(exercise.id) else {
      store.toasts.show(store.text("Это упражнение уже есть.", "This exercise is already there."))
      return
    }
    onPick(exercise)
    dismiss()
  }
}
