import RitmCore
import SwiftUI
import UIKit

/// The five columns of a row: № (28), last time (flexible), kg (64), reps (54), tick (42).
struct WorkoutSetColumns<Number: View, Previous: View, Weight: View, Reps: View, Tick: View>: View {
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

/// One set of the table. Equatable on what it shows (the row, the chosen field): typing in one
/// set, ticking it or moving between exercises builds only the rows that really changed, and
/// every closure it calls is left out of the comparison.
struct WorkoutSetRow: View, Equatable {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  let itemID: String
  let row: WorkoutCardModel.Row
  /// The field of this set the ± stepper is bound to, `nil` when another set is chosen.
  let pickedField: WorkoutSetField?
  let select: (WorkoutSetSelection?) -> Void
  let ticked: (WorkoutSessionItem.TickResult) -> Void
  @FocusState private var focus: WorkoutSetField?
  @State private var inputFocusWork: Task<Void, Never>?

  nonisolated static func == (left: WorkoutSetRow, right: WorkoutSetRow) -> Bool {
    left.itemID == right.itemID && left.row == right.row && left.pickedField == right.pickedField
  }

  private var workouts: WorkoutStore { store.workouts }
  private var set: WorkoutSet { row.set }
  private var isActive: Bool { row.isActive }

  var body: some View {
    WorkoutSetColumns(
      number: {
        Text("\(row.index + 1)").ritmFont(14, weight: .bold).monospacedDigit()
          .foregroundStyle(set.done ? WorkoutColors.income : isActive ? RitmTheme.accentColor : RitmTheme.muted)
      },
      previous: {
        Text(row.previousText).ritmFont(13).monospacedDigit().foregroundStyle(RitmTheme.muted).lineLimit(1)
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
      if let field { select(WorkoutSetSelection(itemID: itemID, setID: set.id, field: field)) }
    }
    .onChange(of: workouts.systemInput?.id, initial: true) { _, _ in
      focusSystemInput()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { focusSystemInput() }
      else { inputFocusWork?.cancel() }
    }
    .onDisappear { inputFocusWork?.cancel() }
    .accessibilityElement(children: .contain)
  }

  private var rowFill: Color {
    return set.done ? WorkoutPalette.incomeSoft : isActive ? RitmTheme.soft : .clear
  }

  private func focusSystemInput() {
    inputFocusWork?.cancel()
    guard scenePhase == .active, let request = workouts.systemInput,
      request.target.workoutID == workouts.session?.id,
      request.target.itemID == itemID, request.target.setID == set.id, !set.done else { return }
    inputFocusWork = Task { @MainActor in
      // The slide between exercises lasts 0.38 s. Let it and any sheet dismissal finish before
      // asking iOS for the keyboard; this work is cancelled when the row disappears.
      do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
      guard !Task.isCancelled, scenePhase == .active, workouts.systemInput?.id == request.id,
        workouts.session?.id == request.target.workoutID,
        workouts.set(item: itemID, set: set.id)?.done == false else { return }
      focus = request.target.field == .weight ? .weight : .reps
      workouts.consumeSystemInput(request.id)
    }
  }

  @ViewBuilder
  private func field(_ kind: WorkoutSetField, text: String, keyboard: UIKeyboardType) -> some View {
    let russian = store.language == .ru
    let picked = pickedField == kind
    let invalid =
      !WorkoutNumber.isBlank(text)
      && (kind == .weight ? WorkoutNumber.normalizedWeight(text) == nil : WorkoutNumber.reps(text) == nil)
    let label =
      kind == .weight
      ? store.text("Вес в килограммах, подход \(row.index + 1)", "Weight in kilograms, set \(row.index + 1)")
      : store.text("Повторы, подход \(row.index + 1)", "Reps, set \(row.index + 1)")
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
      select(nil)
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
    .accessibilityLabel(store.text("Подход \(row.index + 1) выполнен", "Set \(row.index + 1) done"))
    .accessibilityValue(set.done ? store.text("да", "yes") : store.text("нет", "no"))
    .accessibilityAddTraits(.isToggle)
  }
}
