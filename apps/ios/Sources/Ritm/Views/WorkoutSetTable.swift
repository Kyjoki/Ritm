import RitmCore
import SwiftUI
import UIKit

/// The field of a set the stepper edits.
enum WorkoutSetField: Hashable { case weight, reps }

/// The set whose value the ±2,5 stepper changes.
struct WorkoutSetSelection: Equatable {
  var itemID: String
  var setID: String
  var field: WorkoutSetField
}

/// `.w1-card`: one exercise of the workout as a table of sets: № · last time · kg · reps · tick.
/// The first set that is not done is the active row; the stepper under the table changes the
/// selected value by 2,5 kg or one rep. Rows are cheap views of one set each, no geometry reads.
///
/// Equatable on what the card shows (the exercise, its muscle, the chosen cell): it takes the
/// exercise as a value instead of reading the store, so a card that did not change is not built
/// again when another one is edited, when the clock ticks or when the page moves to a neighbour.
struct WorkoutExerciseCard: View, Equatable {
  @Environment(RitmStore.self) private var store
  let item: WorkoutSessionItem
  let muscle: WorkoutMuscle?
  /// The cell of THIS exercise the stepper is bound to; `nil` while none was chosen.
  let selection: WorkoutSetSelection?
  let select: (WorkoutSetSelection?) -> Void
  let ticked: (WorkoutSessionItem.TickResult) -> Void
  /// Opens the sheet that changes this exercise in the running workout.
  let options: () -> Void

  nonisolated static func == (left: WorkoutExerciseCard, right: WorkoutExerciseCard) -> Bool {
    left.item == right.item && left.muscle == right.muscle && left.selection == right.selection
  }

  private var workouts: WorkoutStore { store.workouts }
  private var itemID: String { item.id }

  var body: some View {
    let model = WorkoutCardModel.make(item: item, comma: store.language == .ru)
    VStack(alignment: .leading, spacing: 0) {
      header(model)
      if let muscle {
        WorkoutMuscleChip(muscle: muscle).padding(.horizontal, 6).padding(.bottom, 10)
      }
      columnTitles
      ForEach(model.rows) { row in
        WorkoutSetRow(
          itemID: itemID, row: row, pickedField: pickedField(of: row), select: select, ticked: ticked
        )
        .equatable()
      }
      if let chosen = effectiveSelection(model) { stepper(chosen) }
      setCountButtons(model)
    }
    .padding(.top, 14).padding(.bottom, 10).padding(.horizontal, 10)
    .background { RitmPanelBackground(radius: 22) }
  }

  private func pickedField(of row: WorkoutCardModel.Row) -> WorkoutSetField? {
    selection?.setID == row.set.id ? selection?.field : nil
  }

  private func header(_ model: WorkoutCardModel) -> some View {
    HStack(alignment: .center, spacing: 8) {
      Text(item.name).ritmFont(19, weight: .bold, tracking: -0.04).foregroundStyle(RitmTheme.text)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
      Text("\(model.doneCount)/\(model.rows.count)")
        .ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.muted).monospacedDigit()
      Button(action: options) {
        RitmSymbol("slider.horizontal.3").font(.system(size: 17))
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 44, height: 44).contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.92))
      .padding(.vertical, -8).padding(.trailing, -6)
      .accessibilityLabel(store.text("Изменить упражнение в этой тренировке", "Edit the exercise in this workout"))
    }
    .padding(.horizontal, 6).padding(.bottom, 10)
  }

  /// «− Подход» removes the last set that is not done, «+ Подход» adds one.
  private func setCountButtons(_ model: WorkoutCardModel) -> some View {
    HStack(spacing: 8) {
      setCountButton(
        symbol: "minus", title: store.text("Подход", "Set"), enabled: model.canRemoveSet,
        label: store.text("Убрать последний невыполненный подход", "Remove the last unfinished set")
      ) { workouts.removeLastOpenSet(item: itemID) }
      setCountButton(
        symbol: "plus", title: store.text("Подход", "Set"),
        enabled: model.canAddSet,
        label: store.text("Добавить подход", "Add a set")
      ) { workouts.addSet(item: itemID) }
    }
    .padding(.horizontal, 4).padding(.top, 6)
  }

  private func setCountButton(
    symbol: String, title: String, enabled: Bool, label: String, action: @escaping () -> Void
  ) -> some View {
    Button {
      withAnimation(RitmMotion.easeOut(0.25)) { action() }
    } label: {
      HStack(spacing: 6) {
        RitmSymbol(symbol).font(.system(size: 15))
        Text(title).ritmFont(13, weight: .semibold)
      }
      .foregroundStyle(RitmTheme.accentColor)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .disabled(!enabled).opacity(enabled ? 1 : 0.4)
    .accessibilityLabel(label)
  }

  private var columnTitles: some View {
    WorkoutSetColumns(
      number: { Text("№") }, previous: { Text(store.text("Прошлый раз", "Last time")) },
      weight: { Text(store.text("кг", "kg")) }, reps: { Text(store.text("повт.", "reps")) },
      tick: { Color.clear }
    )
    .ritmFont(10.5, weight: .semibold, tracking: 0.04)
    .textCase(.uppercase)
    .foregroundStyle(RitmTheme.muted)
    .frame(height: 22)
    .accessibilityHidden(true)
  }

  /// The chosen value, or the leading set's weight while nothing was chosen.
  private func effectiveSelection(_ model: WorkoutCardModel) -> WorkoutSetSelection? {
    if let selection, selection.itemID == itemID, model.rows.contains(where: { $0.set.id == selection.setID }) {
      return selection
    }
    return model.leadingSetID.map { WorkoutSetSelection(itemID: itemID, setID: $0, field: .weight) }
  }

  /// `.w1-st`: − value + for the selected cell.
  private func stepper(_ chosen: WorkoutSetSelection) -> some View {
    let russian = store.language == .ru
    let set = item.sets.first { $0.id == chosen.setID }
    let isWeight = chosen.field == .weight
    let step = isWeight ? WorkoutStepper.weightStep : 1
    let stepText = isWeight ? WorkoutFormat.weight(step, comma: russian) : "1"
    let text = (isWeight ? set?.weight : set?.reps) ?? ""
    let shown = text.isEmpty ? "0" : text
    let locked = set?.done ?? true
    return HStack {
      stepButton("−" + stepText, locked: locked) { change(chosen, by: -step) }
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(shown).ritmFont(18, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
          .monospacedDigit()
        Text(isWeight ? (russian ? "кг" : "kg") : (russian ? "повт." : "reps"))
          .ritmFont(12).foregroundStyle(RitmTheme.muted)
      }
      .frame(maxWidth: .infinity)
      stepButton("+" + stepText, locked: locked) { change(chosen, by: step) }
    }
    .padding(6)
    .background(WorkoutPalette.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
    .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 2)
  }

  private func stepButton(_ title: String, locked: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).ritmFont(14, weight: .bold).foregroundStyle(RitmTheme.accentColor)
        .frame(minWidth: 84, minHeight: 44)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.94))
    .disabled(locked).opacity(locked ? 0.4 : 1)
  }

  private func change(_ chosen: WorkoutSetSelection, by delta: Double) {
    guard let set = item.sets.first(where: { $0.id == chosen.setID }), !set.done else { return }
    select(chosen)
    switch chosen.field {
    case .weight:
      workouts.typeWeight(
        WorkoutStepper.weight(set.weight, delta: delta, comma: store.language == .ru), item: itemID,
        set: set.id)
    case .reps:
      workouts.typeReps(WorkoutStepper.reps(set.reps, delta: Int(delta)), item: itemID, set: set.id)
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }
}
