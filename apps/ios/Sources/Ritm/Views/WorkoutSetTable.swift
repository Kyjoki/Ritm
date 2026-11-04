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
struct WorkoutExerciseCard: View {
  @Environment(RitmStore.self) private var store
  let itemID: String
  @Binding var selection: WorkoutSetSelection?
  let ticked: (WorkoutSessionItem.TickResult) -> Void

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    if let item = workouts.item(itemID) {
      let active = item.sets.firstIndex { !$0.done }
      VStack(alignment: .leading, spacing: 0) {
        header(item)
        if let muscle = workouts.library.muscle(of: item.exerciseID) {
          WorkoutMuscleChip(muscle: muscle).padding(.horizontal, 6).padding(.bottom, 10)
        }
        columnTitles
        ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
          WorkoutSetRow(
            itemID: itemID, set: set, index: index, isActive: index == active,
            previous: item.previous?.set(at: index), selection: $selection, ticked: ticked)
        }
        if let chosen = effectiveSelection(item, active: active) { stepper(item, chosen) }
        Button {
          withAnimation(RitmMotion.easeOut(0.25)) { workouts.addSet(item: itemID) }
        } label: {
          HStack(spacing: 6) {
            RitmSymbol("plus").font(.system(size: 15))
            Text(store.text("Подход", "Set")).ritmFont(13, weight: .semibold)
          }
          .foregroundStyle(RitmTheme.accentColor)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .padding(.horizontal, 4).padding(.top, 6)
        .disabled(item.sets.count >= WorkoutSessionItem.maxSets)
        .accessibilityLabel(store.text("Добавить подход", "Add a set"))
      }
      .padding(.top, 14).padding(.bottom, 10).padding(.horizontal, 10)
      .background { RitmPanelBackground(radius: 22) }
    }
  }

  private func header(_ item: WorkoutSessionItem) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(item.name).ritmFont(19, weight: .bold, tracking: -0.04).foregroundStyle(RitmTheme.text)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
      Text("\(item.doneCount)/\(item.sets.count)")
        .ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.muted).monospacedDigit()
    }
    .padding(.horizontal, 6).padding(.bottom, 10)
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
  private func effectiveSelection(_ item: WorkoutSessionItem, active: Int?) -> WorkoutSetSelection? {
    if let selection, selection.itemID == itemID, item.sets.contains(where: { $0.id == selection.setID }) {
      return selection
    }
    let target = active.map { item.sets[$0] } ?? item.sets.last
    return target.map { WorkoutSetSelection(itemID: itemID, setID: $0.id, field: .weight) }
  }

  /// `.w1-st`: − value + for the selected cell.
  private func stepper(_ item: WorkoutSessionItem, _ chosen: WorkoutSetSelection) -> some View {
    let russian = store.language == .ru
    let set = item.sets.first { $0.id == chosen.setID }
    let isWeight = chosen.field == .weight
    let step = isWeight ? WorkoutStepper.weightStep : 1
    let stepText = isWeight ? WorkoutFormat.weight(step, comma: russian) : "1"
    let text = (isWeight ? set?.weight : set?.reps) ?? ""
    let shown = text.isEmpty ? "0" : text
    let locked = set?.done ?? true
    return HStack {
      stepButton("−" + stepText, locked: locked) { change(item, chosen, by: -step) }
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(shown).ritmFont(18, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
          .monospacedDigit()
        Text(isWeight ? (russian ? "кг" : "kg") : (russian ? "повт." : "reps"))
          .ritmFont(12).foregroundStyle(RitmTheme.muted)
      }
      .frame(maxWidth: .infinity)
      stepButton("+" + stepText, locked: locked) { change(item, chosen, by: step) }
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

  private func change(_ item: WorkoutSessionItem, _ chosen: WorkoutSetSelection, by delta: Double) {
    guard let set = item.sets.first(where: { $0.id == chosen.setID }), !set.done else { return }
    selection = chosen
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

/// The five columns of a row: № (28), last time (flexible), kg (64), reps (54), tick (42).
private struct WorkoutSetColumns<Number: View, Previous: View, Weight: View, Reps: View, Tick: View>: View {
  let number: Number
  let previous: Previous
  let weight: Weight
  let reps: Reps
  let tick: Tick

  init(
    @ViewBuilder number: () -> Number, @ViewBuilder previous: () -> Previous,
    @ViewBuilder weight: () -> Weight, @ViewBuilder reps: () -> Reps, @ViewBuilder tick: () -> Tick
  ) {
    self.number = number()
    self.previous = previous()
    self.weight = weight()
    self.reps = reps()
    self.tick = tick()
  }

  var body: some View {
    HStack(spacing: 4) {
      number.frame(width: 28)
      previous.frame(maxWidth: .infinity)
      weight.frame(width: 64)
      reps.frame(width: 54)
      tick.frame(width: 42)
    }
    .padding(.horizontal, 4)
  }
}

// MARK: - Row

private struct WorkoutSetRow: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let itemID: String
  let set: WorkoutSet
  let index: Int
  let isActive: Bool
  let previous: WorkoutResultSet?
  @Binding var selection: WorkoutSetSelection?
  let ticked: (WorkoutSessionItem.TickResult) -> Void
  @FocusState private var focus: WorkoutSetField?

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    let russian = store.language == .ru
    WorkoutSetColumns(
      number: {
        Text("\(index + 1)").ritmFont(14, weight: .bold).monospacedDigit()
          .foregroundStyle(set.done ? WorkoutColors.income : isActive ? RitmTheme.accentColor : RitmTheme.muted)
      },
      previous: {
        Text(
          previous.map { "\(WorkoutFormat.weight($0.weight, comma: russian)) × \($0.reps)" } ?? "—"
        )
        .ritmFont(13).monospacedDigit().foregroundStyle(RitmTheme.muted).lineLimit(1)
      },
      weight: { field(.weight, text: set.weight, keyboard: .decimalPad) },
      reps: { field(.reps, text: set.reps, keyboard: .numberPad) },
      tick: { tick }
    )
    .frame(height: 50)
    .background(rowFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      if isActive && !set.done {
        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(RitmTheme.accentColor, lineWidth: 1.5)
      }
    }
    .padding(.top, 4)
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.25), value: set.done)
    .onChange(of: focus) { _, field in
      if let field { selection = WorkoutSetSelection(itemID: itemID, setID: set.id, field: field) }
    }
    .accessibilityElement(children: .contain)
  }

  private var rowFill: Color {
    return set.done ? WorkoutPalette.incomeSoft : isActive ? RitmTheme.soft : .clear
  }

  private var isSelected: Bool { selection?.setID == set.id }

  @ViewBuilder
  private func field(_ kind: WorkoutSetField, text: String, keyboard: UIKeyboardType) -> some View {
    let russian = store.language == .ru
    let picked = isSelected && selection?.field == kind
    let invalid =
      !WorkoutNumber.isBlank(text)
      && (kind == .weight ? WorkoutNumber.normalizedWeight(text) == nil : WorkoutNumber.reps(text) == nil)
    let label =
      kind == .weight
      ? store.text("Вес в килограммах, подход \(index + 1)", "Weight in kilograms, set \(index + 1)")
      : store.text("Повторы, подход \(index + 1)", "Reps, set \(index + 1)")
    Group {
      if set.done {
        Text(text.isEmpty ? "—" : text).foregroundStyle(WorkoutColors.income)
      } else {
        TextField(
          text: Binding(
            get: { text },
            set: {
              if kind == .weight {
                workouts.typeWeight($0, item: itemID, set: set.id)
              } else {
                workouts.typeReps($0, item: itemID, set: set.id)
              }
            }),
          prompt: Text(kind == .weight ? (russian ? "кг" : "kg") : (russian ? "повт." : "reps"))
            .foregroundStyle(RitmTheme.muted.opacity(0.5))
        ) { Text(label) }
        .keyboardType(keyboard)
        .focused($focus, equals: kind)
        .autocorrectionDisabled()
        .foregroundStyle(invalid ? RitmTheme.danger : RitmTheme.text)
      }
    }
    .ritmFont(17, weight: .bold, tracking: -0.02).monospacedDigit()
    .multilineTextAlignment(.center)
    .frame(height: 36)
    .background(
      picked || (isActive && !set.done) ? RitmTheme.field : Color.clear,
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .overlay {
      if picked && !set.done {
        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(RitmTheme.accentColor, lineWidth: 2)
      } else if isActive && !set.done {
        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(RitmTheme.line, lineWidth: 1)
      }
    }
    .accessibilityLabel(label)
  }

  private var tick: some View {
    Button {
      selection = nil
      ticked(workouts.toggleSet(item: itemID, set: set.id))
    } label: {
      RitmSymbol("checkmark")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(set.done ? WorkoutColors.onIncome : isActive ? RitmTheme.ctaInk : Color.clear)
        .frame(width: 36, height: 36)
        .background {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
              set.done
                ? AnyShapeStyle(WorkoutColors.income)
                : isActive ? AnyShapeStyle(RitmTheme.ctaGradient) : AnyShapeStyle(RitmTheme.soft))
        }
        .overlay {
          if !set.done && !isActive {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WorkoutPalette.stroke, lineWidth: 1)
          }
        }
        .frame(width: 42, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .accessibilityLabel(store.text("Подход \(index + 1) выполнен", "Set \(index + 1) done"))
    .accessibilityValue(set.done ? store.text("да", "yes") : store.text("нет", "no"))
    .accessibilityAddTraits(.isToggle)
  }
}
