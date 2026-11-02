import RitmCore
import SwiftUI

/// Where the exercise picker was opened from, and what a choice does.
enum WorkoutPickerMode: Identifiable, Equatable {
  case add
  case replace(String)

  var id: String {
    switch self {
    case .add: "add"
    case .replace(let item): "replace-" + item
    }
  }
}

/// The program editor: name, order of programs, duplicate and delete, and the exercise cards
/// (planned sets, replace, reorder, delete). Editing never touches a started workout or history.
struct WorkoutEditorView: View {
  @Environment(RitmStore.self) private var store
  let programID: String
  let go: (WorkoutScreen) -> Void
  @State private var picker: WorkoutPickerMode?
  @State private var deletingItem: String?
  @State private var deletingProgram = false
  @State private var name = ""
  @State private var loaded = false
  @FocusState private var nameFocused: Bool

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    WorkoutPage(
      title: store.text("Программа", "Program"),
      action: {
        WorkoutHeaderButton(
          symbol: "chevron.left", label: store.text("Назад к программам", "Back to programs")
        ) { close() }
      },
      content: {
        if let program = workouts.program(programID) {
          content(program)
        }
      }
    )
    .onAppear {
      guard !loaded else { return }
      loaded = true
      name = workouts.program(programID)?.name ?? ""
    }
    .onChange(of: workouts.program(programID) == nil) { _, gone in
      if gone { go(.home) }
    }
    .sheet(item: $picker) { mode in pickerSheet(for: mode) }
    .confirmationDialog(
      store.text("Удалить программу?", "Delete program?"), isPresented: $deletingProgram,
      titleVisibility: .visible
    ) {
      Button(store.text("Удалить программу", "Delete program"), role: .destructive) {
        workouts.deleteProgram(programID)
        store.toasts.show(store.text("Программа удалена", "Program deleted"))
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(
        store.text(
          "История выполненных тренировок не изменится.", "Finished workouts stay in the history."))
    }
    .confirmationDialog(
      store.text("Удалить упражнение?", "Delete exercise?"),
      isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } }),
      titleVisibility: .visible
    ) {
      Button(store.text("Удалить упражнение", "Delete exercise"), role: .destructive) {
        if let item = deletingItem {
          withAnimation(RitmMotion.easeOut(0.24)) { workouts.removeItem(item, from: programID) }
          store.toasts.show(store.text("Упражнение удалено из программы", "Exercise removed from the program"))
        }
        deletingItem = nil
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) { deletingItem = nil }
    } message: {
      Text(
        store.text(
          "История выполненных тренировок не изменится.", "Finished workouts stay in the history."))
    }
  }

  // MARK: Content

  private func content(_ program: WorkoutProgram) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      header(program).ritmPageReveal(index: 0)
      if program.items.isEmpty {
        Text(store.text("В программе пока нет упражнений", "No exercises in this program yet"))
          .ritmText(.body).foregroundStyle(RitmTheme.muted)
          .frame(maxWidth: .infinity, minHeight: 72)
          .background { RitmPanelBackground(radius: 20) }
          .ritmPageReveal(index: 1)
      } else {
        WorkoutReorderList(
          items: program.items, spacing: 10,
          onMove: { workouts.moveItem(in: programID, from: $0, to: $1) }
        ) { item, handle in
          let index = program.items.firstIndex { $0.id == item.id } ?? 0
          exerciseCard(item, index: index, count: program.items.count, handle: handle)
        }
        .ritmPageReveal(index: 1)
      }
      Button {
        picker = .add
      } label: {
        Label(store.text("Добавить упражнение", "Add exercise"), systemImage: "plus")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
      .ritmPageReveal(index: 2)
    }
  }

  private func header(_ program: WorkoutProgram) -> some View {
    let index = workouts.library.programs.firstIndex { $0.id == program.id } ?? 0
    let count = workouts.library.programs.count
    return RitmCard(padding: 14, radius: 22) {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(store.text("Название программы", "Program name"))
            .ritmFont(11.5, weight: .medium).foregroundStyle(RitmTheme.muted)
          TextField(store.text("Название", "Name"), text: $name)
            .focused($nameFocused)
            .submitLabel(.done)
            .onSubmit { commitName() }
            .onChange(of: name) { _, value in
              let limited = String(value.prefix(WorkoutProgram.nameLimit))
              if limited != value { name = limited }
              workouts.renameProgram(programID, to: limited)
            }
            .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
            .ritmFont(16, weight: .semibold)
            .foregroundStyle(RitmTheme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .circular))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
            }
        }
        HStack(spacing: 6) {
          WorkoutIconButton(symbol: "arrow.up", label: store.text("Переместить программу выше", "Move program up")) {
            moveProgram(index, by: -1)
          }
          .disabled(index == 0).opacity(index == 0 ? 0.35 : 1)
          WorkoutIconButton(symbol: "arrow.down", label: store.text("Переместить программу ниже", "Move program down")) {
            moveProgram(index, by: 1)
          }
          .disabled(index >= count - 1).opacity(index >= count - 1 ? 0.35 : 1)
          Button {
            duplicate()
          } label: {
            Text(store.text("Дублировать", "Duplicate")).frame(maxWidth: .infinity)
          }
          .buttonStyle(RitmSecondaryButtonStyle())
          WorkoutIconButton(
            symbol: "trash", label: store.text("Удалить программу", "Delete program"), tint: RitmTheme.danger
          ) { deletingProgram = true }
        }
      }
    }
  }

  private func exerciseCard(
    _ item: WorkoutProgramItem, index: Int, count: Int, handle: WorkoutDragHandle
  ) -> some View {
    let title = workouts.exerciseName(item.exerciseID, language: store.language)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        handle.padding(.leading, -6)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).ritmFont(15, weight: .semibold).foregroundStyle(RitmTheme.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(store.text("Подходов: \(item.sets)", "Sets: \(item.sets)"))
            .ritmFont(11.5).foregroundStyle(RitmTheme.muted)
        }
        Spacer(minLength: 4)
        WorkoutIconButton(
          symbol: "trash", label: store.text("Удалить упражнение «\(title)»", "Delete exercise “\(title)”"),
          tint: RitmTheme.danger
        ) { deletingItem = item.id }
      }
      HStack(spacing: 6) {
        stepper(item)
        Button {
          picker = .replace(item.id)
        } label: {
          Label(store.text("Заменить", "Replace"), systemImage: "arrow.left.arrow.right")
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(RitmSecondaryButtonStyle())
        .accessibilityLabel(store.text("Заменить упражнение «\(title)»", "Replace exercise “\(title)”"))
        WorkoutIconButton(symbol: "arrow.up", label: store.text("Переместить выше", "Move up")) {
          moveItem(index, by: -1)
        }
        .disabled(index == 0).opacity(index == 0 ? 0.35 : 1)
        WorkoutIconButton(symbol: "arrow.down", label: store.text("Переместить ниже", "Move down")) {
          moveItem(index, by: 1)
        }
        .disabled(index >= count - 1).opacity(index >= count - 1 ? 0.35 : 1)
      }
    }
    .padding(12)
    .background { RitmPanelBackground(radius: 22) }
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: store.text("Вверх", "Move up")) { moveItem(index, by: -1) }
    .accessibilityAction(named: store.text("Вниз", "Move down")) { moveItem(index, by: 1) }
  }

  private func stepper(_ item: WorkoutProgramItem) -> some View {
    HStack(spacing: 0) {
      stepButton("minus", store.text("Меньше подходов", "Fewer sets"), enabled: item.sets > WorkoutProgramItem.setRange.lowerBound) {
        workouts.setPlannedSets(item.sets - 1, item: item.id, in: programID)
      }
      Text("\(item.sets)").ritmFont(15, weight: .semibold).monospacedDigit()
        .frame(minWidth: 22).foregroundStyle(RitmTheme.text)
        .accessibilityLabel(store.text("Подходов: \(item.sets)", "Sets: \(item.sets)"))
      stepButton("plus", store.text("Больше подходов", "More sets"), enabled: item.sets < WorkoutProgramItem.setRange.upperBound) {
        workouts.setPlannedSets(item.sets + 1, item: item.id, in: programID)
      }
    }
    .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .circular))
    .overlay { RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
  }

  private func stepButton(
    _ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .disabled(!enabled).opacity(enabled ? 1 : 0.35)
    .accessibilityLabel(label)
  }

  // MARK: Actions

  private func moveItem(_ index: Int, by delta: Int) {
    guard let program = workouts.program(programID), program.items.indices.contains(index + delta) else { return }
    withAnimation(RitmMotion.easeOut(0.22)) { workouts.moveItem(in: programID, from: index, to: index + delta) }
  }

  private func moveProgram(_ index: Int, by delta: Int) {
    guard workouts.library.programs.indices.contains(index + delta) else { return }
    withAnimation(RitmMotion.easeOut(0.22)) { workouts.moveProgram(from: index, to: index + delta) }
  }

  private func duplicate() {
    commitName()
    if workouts.duplicateProgram(programID, suffix: store.text(" (копия)", " (copy)")) != nil {
      store.toasts.show(store.text("Программа продублирована", "Program duplicated"))
      go(.home)
    }
  }

  /// An empty name is replaced by a numbered one when the field is left.
  private func commitName() {
    guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let number = (workouts.library.programs.firstIndex { $0.id == programID } ?? 0) + 1
    name = store.text("Программа \(number)", "Program \(number)")
    workouts.renameProgram(programID, to: name)
  }

  private func close() {
    commitName()
    go(.home)
  }

  @ViewBuilder private func pickerSheet(for mode: WorkoutPickerMode) -> some View {
    let used = Set(workouts.program(programID)?.items.map(\.exerciseID) ?? [])
    switch mode {
    case .add:
      WorkoutExercisePicker(
        title: store.text("Добавить упражнение", "Add exercise"), used: used,
        usedNote: store.text("уже в программе", "already in the program"),
        createLabel: store.text("Создать и добавить", "Create and add")
      ) { exercise in
        withAnimation(RitmMotion.easeOut(0.24)) { _ = workouts.addItem(to: programID, exerciseID: exercise.id) }
        store.toasts.show(store.text("Упражнение добавлено", "Exercise added"))
      }
    case .replace(let itemID):
      WorkoutExercisePicker(
        title: store.text("Заменить упражнение", "Replace exercise"), used: used,
        usedNote: store.text("уже в программе", "already in the program"),
        createLabel: store.text("Создать и заменить", "Create and replace")
      ) { exercise in
        _ = workouts.replaceItem(itemID, in: programID, with: exercise.id)
        store.toasts.show(store.text("Упражнение заменено", "Exercise replaced"))
      }
    }
  }
}
