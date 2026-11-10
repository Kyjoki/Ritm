import RitmCore
import SwiftUI

// The sheets that change the running workout: the menu, the list of exercises (reorder, add,
// open) and the options of one exercise (sets, reps, rest, replace, remove). They change this
// workout only; the program is touched only by the question at the finish.

// MARK: - Menu

enum WorkoutMenuAction {
  case exercises, addAfterCurrent, addAtEnd, replaceCurrent, removeCurrent, finish, cancel
}

/// `⋮`: the exercises of the workout, then finishing or cancelling it.
struct WorkoutMenuSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let canRemove: Bool
  let perform: (WorkoutMenuAction) -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 2) {
        row("list.bullet", store.text("Упражнения и порядок", "Exercises and order"), .exercises)
        row("plus", store.text("Добавить после текущего", "Add after this one"), .addAfterCurrent)
        row("plus", store.text("Добавить в конец", "Add at the end"), .addAtEnd)
        row("arrow.left.arrow.right", store.text("Заменить текущее", "Replace this one"), .replaceCurrent)
        row("minus.circle", store.text("Убрать текущее", "Remove this one"), .removeCurrent, enabled: canRemove)
        Rectangle().fill(RitmTheme.line).frame(height: 1).padding(.vertical, 6)
        row("checkmark", store.text("Завершить тренировку", "Finish workout"), .finish)
        row("trash", store.text("Отменить тренировку", "Cancel workout"), .cancel, danger: true)
        Button { dismiss() } label: {
          Text(store.text("Закрыть", "Close")).ritmFont(16, weight: .semibold)
            .foregroundStyle(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(RitmPressStyle())
        .padding(.top, 6)
      }
      .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 20)
    }
    .background(RitmTheme.background)
    .presentationDetents([.medium, .large])
    .ritmSheetGrabber()
  }

  private func row(
    _ symbol: String, _ title: String, _ action: WorkoutMenuAction, danger: Bool = false,
    enabled: Bool = true
  ) -> some View {
    Button { perform(action) } label: {
      HStack(spacing: 12) {
        RitmSymbol(symbol).font(.system(size: 21)).frame(width: 26)
        Text(title).ritmFont(16, weight: .semibold).multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      }
      .foregroundStyle(danger ? RitmTheme.danger : RitmTheme.text)
      .padding(.horizontal, 14).frame(minHeight: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .disabled(!enabled).opacity(enabled ? 1 : 0.4)
  }
}

// MARK: - Exercises

/// `.xl`: every exercise with its progress; tap to open it, hold the grip to drag it to another
/// place, «Добавить» for one more, the sliders for its sets, reps and rest.
struct WorkoutExercisesSheet: View {
  @Environment(RitmStore.self) private var store
  let current: Int
  let open: (Int) -> Void
  let add: () -> Void
  let options: (String) -> Void
  let move: (Int, Int) -> Void
  @State private var dragging = false

  private var items: [WorkoutSessionItem] { store.workouts.session?.items ?? [] }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 8) {
          Text(store.text("Упражнения", "Exercises")).ritmFont(19, weight: .bold, tracking: -0.03)
            .foregroundStyle(RitmTheme.text)
            .accessibilityAddTraits(.isHeader)
          Spacer(minLength: 8)
          Button(action: add) {
            HStack(spacing: 6) {
              RitmSymbol("plus").font(.system(size: 15, weight: .semibold))
              Text(store.text("Добавить", "Add")).ritmFont(13.5, weight: .bold)
            }
            .foregroundStyle(RitmTheme.accentColor)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .ritmGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
          }
          .buttonStyle(RitmGlassButtonStyle())
          .accessibilityLabel(store.text("Добавить упражнение", "Add an exercise"))
        }
        .padding(.horizontal, 4).padding(.bottom, 10)
        WorkoutReorderList(
          items: items, spacing: 6, cornerRadius: 18, handleSize: 18, isDragging: $dragging,
          onMove: move
        ) { item, handle in
          row(item, handle: handle)
        }
        Text(store.text("Удерживайте ⠿, чтобы переставить упражнение.", "Hold ⠿ to move an exercise."))
          .ritmFont(12).foregroundStyle(RitmTheme.muted)
          .padding(.horizontal, 4).padding(.top, 12)
      }
      .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)
    }
    .background(RitmTheme.background)
    .presentationDetents([.medium, .large])
    .interactiveDismissDisabled(dragging)
    .ritmSheetGrabber()
  }

  private func row(_ item: WorkoutSessionItem, handle: WorkoutDragHandle) -> some View {
    let index = items.firstIndex { $0.id == item.id } ?? 0
    let full = !item.sets.isEmpty && item.doneCount == item.sets.count
    let isCurrent = index == current
    let progress =
      item.isOnlyInLog
      ? store.text("\(item.doneCount) выполнено, остаётся в журнале", "\(item.doneCount) done, kept in the log")
      : store.text("\(item.doneCount) из \(item.sets.count) подходов", "\(item.doneCount) of \(item.sets.count) sets")
    return HStack(spacing: 0) {
      handle
      Button { open(index) } label: {
        HStack(spacing: 10) {
          Group {
            if full {
              RitmSymbol("checkmark").font(.system(size: 15, weight: .bold))
            } else {
              Text("\(index + 1)").ritmFont(13, weight: .bold)
            }
          }
          .foregroundStyle(full ? WorkoutColors.income : RitmTheme.muted)
          .frame(width: 32, height: 32)
          .background(
            full ? WorkoutPalette.incomeSoft : WorkoutPalette.inset,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
          VStack(alignment: .leading, spacing: 0) {
            Text(item.name).ritmFont(14.5, weight: .semibold, tracking: -0.02)
              .foregroundStyle(RitmTheme.text).multilineTextAlignment(.leading)
            HStack(spacing: 6) {
              if let muscle = store.workouts.library.muscle(of: item.exerciseID) {
                WorkoutMuscleChip(muscle: muscle)
              }
              Text(progress).ritmFont(11.5).foregroundStyle(RitmTheme.muted)
                .multilineTextAlignment(.leading)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          if isCurrent {
            Text(store.text("Сейчас", "Now")).ritmFont(12, weight: .bold).foregroundStyle(RitmTheme.accentColor)
          }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      Button { options(item.id) } label: {
        RitmSymbol("slider.horizontal.3").font(.system(size: 17)).foregroundStyle(RitmTheme.accentColor)
          .frame(width: 44, height: 44).contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.92))
      .accessibilityLabel(store.text("Изменить «\(item.name)»", "Edit “\(item.name)”"))
    }
    .padding(.trailing, 4)
    .background {
      RitmPanelBackground(radius: 18)
    }
    .overlay {
      if isCurrent {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(RitmTheme.accentColor, lineWidth: 1.5).allowsHitTesting(false)
      }
    }
  }
}

// MARK: - One exercise

/// The plan of one exercise in this workout: sets, reps and rest, and replacing or removing it.
struct WorkoutExerciseOptionsSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let itemID: String
  let canRemove: Bool
  let replace: () -> Void
  let remove: () -> Void

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    ScrollView {
      if let item = workouts.item(itemID) {
        VStack(alignment: .leading, spacing: 0) {
          Text(item.name).ritmFont(19, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
          HStack(spacing: 8) {
            if let muscle = workouts.library.muscle(of: item.exerciseID) { WorkoutMuscleChip(muscle: muscle) }
            Text(store.text("выполнено \(item.doneCount) из \(item.sets.count)", "done \(item.doneCount) of \(item.sets.count)"))
              .ritmFont(12).foregroundStyle(RitmTheme.muted)
          }
          .padding(.horizontal, 4)
          Text(store.text("План на эту тренировку", "Plan for this workout").uppercased())
            .ritmFont(12, weight: .semibold, tracking: 0.06).foregroundStyle(RitmTheme.muted)
            .padding(.horizontal, 4).padding(.top, 20).padding(.bottom, 8)
          steppers(item)
          Text(
            store.text(
              "Это меняет только текущую тренировку. В конце можно сохранить изменения в программу.",
              "This changes the current workout only. At the end you can save the changes to the program.")
          )
          .ritmFont(12).foregroundStyle(RitmTheme.muted).padding(.horizontal, 4).padding(.top, 10)
          actionButton(
            symbol: "arrow.left.arrow.right", title: store.text("Заменить упражнение", "Replace exercise"),
            danger: false, action: replace
          )
          .padding(.top, 16)
          actionButton(
            symbol: "minus.circle", title: store.text("Убрать из тренировки", "Remove from the workout"),
            danger: true, action: remove
          )
          .disabled(!canRemove).opacity(canRemove ? 1 : 0.4)
          .padding(.top, 8)
          Button { dismiss() } label: { Text(store.text("Готово", "Done")).ritmFont(16, weight: .bold) }
            .buttonStyle(RitmPrimaryButtonStyle(minHeight: 52))
            .padding(.top, 14)
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)
      }
    }
    .background(RitmTheme.background)
    .presentationDetents([.medium, .large])
    .ritmSheetGrabber()
  }

  /// Three tiles side by side, one under another when the text is large.
  private func steppers(_ item: WorkoutSessionItem) -> some View {
    let sets = tile(item, .sets, title: store.text("Подходы", "Sets"), value: "\(item.sets.count)")
    let reps = tile(item, .reps, title: store.text("Повторы", "Reps"), value: "\(item.plannedReps)")
    let rest = tile(
      item, .rest, title: store.text("Отдых", "Rest"),
      value: "\(item.restSeconds)" + store.text(" с", " s"))
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { sets; reps; rest }
      VStack(spacing: 8) { sets; reps; rest }
    }
  }

  private func tile(
    _ item: WorkoutSessionItem, _ field: WorkoutProgramDraft.Field, title: String, value: String
  ) -> some View {
    WorkoutPlanStepper(
      title: title, value: value, canDecrease: item.canStep(field, direction: -1),
      canIncrease: item.canStep(field, direction: 1),
      step: { direction in
        withAnimation(RitmMotion.easeOut(0.2)) { workouts.step(field, direction: direction, item: itemID) }
      })
  }

  private func actionButton(symbol: String, title: String, danger: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 8) {
        RitmSymbol(symbol).font(.system(size: 18))
        Text(title).ritmFont(14.5, weight: .bold)
      }
      .foregroundStyle(danger ? RitmTheme.danger : RitmTheme.accentColor)
      .frame(maxWidth: .infinity, minHeight: 50)
      .ritmGlass(in: Capsule(), interactive: true)
      .contentShape(Capsule())
    }
    .buttonStyle(RitmGlassButtonStyle())
  }
}

/// A caption, `−`, the value and `+`: the stepper of one plan value.
struct WorkoutPlanStepper: View {
  let title: String
  let value: String
  let canDecrease: Bool
  let canIncrease: Bool
  let step: (Int) -> Void

  var body: some View {
    VStack(spacing: 4) {
      Text(title).ritmFont(10.5, weight: .semibold).foregroundStyle(RitmTheme.muted)
      HStack(spacing: 0) {
        button("−", enabled: canDecrease, label: title + " −") { step(-1) }
        Text(value).ritmFont(15, weight: .bold).monospacedDigit().foregroundStyle(RitmTheme.text)
          .frame(maxWidth: .infinity).minimumScaleFactor(0.8).lineLimit(1)
        button("+", enabled: canIncrease, label: title + " +") { step(1) }
      }
      .padding(3)
      .background(WorkoutPalette.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
  }

  private func button(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(symbol).ritmFont(18, weight: .bold).foregroundStyle(RitmTheme.accentColor)
        .frame(width: 40, height: 44)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .disabled(!enabled).opacity(enabled ? 1 : 0.35)
    .accessibilityLabel(label)
  }
}
