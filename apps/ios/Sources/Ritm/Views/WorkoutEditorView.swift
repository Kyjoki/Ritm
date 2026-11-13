import RitmCore
import SwiftUI

/// The program editor, also for a new program: name, colour, exercises with sets, reps and rest,
/// «Сохранить» / «Отмена». Everything is a draft until «Сохранить»; editing never touches a
/// started workout or the history.
struct WorkoutEditorView: View {
  @Environment(RitmStore.self) private var store
  let programID: String
  let isNew: Bool
  let go: (WorkoutScreen) -> Void
  @State private var draft = WorkoutProgramDraft()
  @State private var loaded = false
  @State private var picking = false
  @State private var deleting = false

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    WorkoutPage(
      header: { topBar },
      content: {
        VStack(alignment: .leading, spacing: 0) {
          label(store.text("Название", "Name"))
          TextField(store.text("Название программы", "Program name"), text: $draft.name)
            .ritmFont(17, weight: .semibold, tracking: -0.02).foregroundStyle(RitmTheme.text)
            .submitLabel(.done)
            .onChange(of: draft.name) { _, value in
              if value.count > WorkoutProgram.nameLimit {
                draft.name = String(value.prefix(WorkoutProgram.nameLimit))
              }
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1) }
          label(store.text("Цвет", "Colour"))
          swatches
          label(store.text("Упражнения · \(draft.items.count)", "Exercises · \(draft.items.count)"))
          exercisesList
          Button {
            picking = true
          } label: {
            HStack(spacing: 8) {
              RitmSymbol("plus").font(.system(size: 18))
              Text(store.text("Добавить упражнение", "Add exercise")).ritmFont(14.5, weight: .bold)
            }
            .foregroundStyle(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, minHeight: 50)
            .ritmGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
          }
          .buttonStyle(RitmGlassButtonStyle())
          .padding(.top, 10)
          if !isNew {
            Button {
              deleting = true
            } label: {
              HStack(spacing: 8) {
                RitmSymbol("trash").font(.system(size: 18))
                Text(store.text("Удалить программу", "Delete program")).ritmFont(14.5, weight: .bold)
              }
              .foregroundStyle(RitmTheme.danger)
              .frame(maxWidth: .infinity, minHeight: 50)
              .ritmGlass(in: Capsule(), interactive: true)
              .contentShape(Capsule())
            }
            .buttonStyle(RitmGlassButtonStyle())
            .padding(.top, 10)
          }
        }
      }
    )
    .onAppear(perform: load)
    .sheet(isPresented: $picking) {
      WorkoutExercisePicker(
        title: store.text("Добавить упражнение", "Add exercise"),
        used: Set(draft.items.map(\.exerciseID)),
        usedNote: store.text("уже в программе", "already in the program")
      ) { exercise in
        withAnimation(RitmMotion.easeOut(0.24)) { _ = draft.add(exerciseID: exercise.id) }
      }
    }
    .alert(store.text("Удалить программу?", "Delete program?"), isPresented: $deleting) {
      Button(store.text("Удалить", "Delete"), role: .destructive) {
        workouts.deleteProgram(programID)
        store.toasts.show(store.text("Программа удалена", "Program deleted"))
        go(.home)
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(
        store.text(
          "Программа будет удалена. История выполненных тренировок не изменится.",
          "The program will be deleted. Finished workouts stay in the history."))
    }
  }

  private func load() {
    guard !loaded else { return }
    loaded = true
    if let program = workouts.program(programID) {
      draft = WorkoutProgramDraft(program: program)
    } else {
      draft = WorkoutProgramDraft(colorIndex: workouts.library.programs.count % WorkoutProgram.colorCount)
    }
  }

  // MARK: Pieces

  private var topBar: some View {
    HStack {
      Button(store.text("Отмена", "Cancel")) { go(isNew ? .home : .program(programID)) }
        .ritmFont(15, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(isNew ? store.text("Новая программа", "New program") : store.text("Изменить", "Edit"))
        .ritmFont(16, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Button(action: save) {
        Text(store.text("Сохранить", "Save")).ritmFont(13.5, weight: .bold)
          .foregroundStyle(RitmTheme.ctaInk)
          .padding(.horizontal, 16).frame(height: 38)
          .ritmGlass(in: Capsule(), prominent: true, interactive: true)
          .frame(minHeight: 44)
          .contentShape(Capsule())
      }
      .buttonStyle(RitmGlassButtonStyle())
      .disabled(!draft.canSave).opacity(draft.canSave ? 1 : 0.4)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.bottom, 4)
  }

  private func label(_ text: String) -> some View {
    Text(text.uppercased()).ritmFont(12, weight: .semibold, tracking: 0.06)
      .foregroundStyle(RitmTheme.muted)
      .padding(.horizontal, 4).padding(.top, 18).padding(.bottom, 8)
  }

  /// `.sws`: the six gradients of the program card.
  private var swatches: some View {
    HStack(spacing: 10) {
      ForEach(0..<WorkoutProgram.colorCount, id: \.self) { index in
        let selected = draft.colorIndex == index
        Button {
          draft.colorIndex = index
        } label: {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(WorkoutPalette.gradient(index))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1) }
            .frame(width: 42, height: 42)
            .padding(4)
            .overlay {
              if selected {
                RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(RitmTheme.accentColor, lineWidth: 2)
              }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.92))
        .padding(-4)
        .accessibilityLabel(store.text("Цвет \(index + 1)", "Colour \(index + 1)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }

  @ViewBuilder private var exercisesList: some View {
    if draft.items.isEmpty {
      WorkoutEmptyText(text: store.text("В программе пока нет упражнений.", "No exercises in this program yet."))
    } else {
      WorkoutReorderList(
        items: draft.items, spacing: 8, cornerRadius: 20, handleSize: 20,
        onMove: { draft.move(from: $0, to: $1) }
      ) { item, handle in
        row(item, handle: handle)
      }
    }
  }

  /// `.ed-row`: grip, name and muscle, ×; below it the sets, reps and rest steppers.
  private func row(_ item: WorkoutProgramItem, handle: WorkoutDragHandle) -> some View {
    let name = workouts.exerciseName(item.exerciseID, language: store.language)
    return VStack(spacing: 8) {
      HStack(spacing: 8) {
        handle
        VStack(alignment: .leading, spacing: 4) {
          Text(name).ritmFont(14.5, weight: .semibold, tracking: -0.02).foregroundStyle(RitmTheme.text)
            .fixedSize(horizontal: false, vertical: true)
          if let muscle = workouts.library.muscle(of: item.exerciseID) { WorkoutMuscleChip(muscle: muscle) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          withAnimation(RitmMotion.easeOut(0.24)) { draft.remove(item.id) }
        } label: {
          RitmSymbol("xmark").font(.system(size: 18)).foregroundStyle(RitmTheme.muted)
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.92))
        .accessibilityLabel(store.text("Удалить упражнение «\(name)»", "Remove exercise “\(name)”"))
      }
      WorkoutPlanSteppers(
        sets: item.sets, reps: item.reps, rest: item.restSeconds,
        canStep: { draft.canStep(item.id, $0, direction: $1) },
        step: { field, direction in
          guard draft.canStep(item.id, field, direction: direction) else { return false }
          draft.step(item.id, field, direction: direction)
          return true
        }
      )
      .padding(.horizontal, 4)
    }
    .padding(.leading, 4).padding(.trailing, 4).padding(.vertical, 6)
    .padding(.bottom, 4)
    .background { RitmPanelBackground(radius: 20) }
  }

  private func save() {
    guard workouts.saveProgram(draft, as: programID) else { return }
    store.toasts.show(store.text("Программа сохранена", "Program saved"))
    go(isNew ? .home : .program(programID))
  }
}
