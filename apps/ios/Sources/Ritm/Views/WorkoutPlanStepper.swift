import RitmCore
import SwiftUI
import UIKit

/// The sets, reps and rest of one exercise as three rows in one well: the name on the left, on the
/// right «−  value  +». Used by the options of an exercise in the running workout and by the
/// program editor, so both read the same. The value is big and is never cut off: when the text is
/// so large that a row does not fit on one line, the name moves above the stepper.
struct WorkoutPlanSteppers: View {
  @Environment(RitmStore.self) private var store
  let sets: Int
  let reps: Int
  let rest: Int
  /// Whether a step in the direction (+1 / −1) stays inside the range of the field.
  let canStep: (WorkoutProgramDraft.Field, Int) -> Bool
  /// Takes the step; `false` when it was out of range, which also ends a hold on a button.
  let step: (WorkoutProgramDraft.Field, Int) -> Bool

  var body: some View {
    let russian = store.language == .ru
    VStack(spacing: 0) {
      row(.sets, title: store.text("Подходы", "Sets"), display: "\(sets)", spoken: "\(sets)")
      separator
      row(.reps, title: store.text("Повторы", "Reps"), display: "\(reps)", spoken: "\(reps)")
      separator
      row(
        .rest, title: store.text("Отдых", "Rest"), display: WorkoutFormat.restClock(seconds: rest),
        spoken: WorkoutFormat.restSpoken(seconds: rest, russian: russian))
    }
    .background(WorkoutPalette.inset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(WorkoutPalette.stroke, lineWidth: 1)
    }
  }

  private var separator: some View {
    Rectangle().fill(RitmTheme.line).frame(height: 1).padding(.horizontal, 14)
  }

  private func row(_ field: WorkoutProgramDraft.Field, title: String, display: String, spoken: String)
    -> some View
  {
    WorkoutPlanStepperRow(
      title: title, display: display, spoken: spoken, canDecrease: canStep(field, -1),
      canIncrease: canStep(field, 1), step: { step(field, $0) })
  }
}

/// One plan value: «Подходы    −  3  +».
struct WorkoutPlanStepperRow: View {
  let title: String
  /// What is printed between the buttons: «3», «10», «3:00».
  let display: String
  /// What VoiceOver says: «3», «2 мин 30 с».
  let spoken: String
  let canDecrease: Bool
  let canIncrease: Bool
  /// Takes a step of +1 / −1; `false` when it was out of range.
  let step: (Int) -> Bool

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        caption.fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 8)
        control
      }
      VStack(alignment: .leading, spacing: 8) {
        caption.fixedSize(horizontal: false, vertical: true)
        control.frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 8)
    .frame(minHeight: 60)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(spoken)
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: _ = step(1)
      case .decrement: _ = step(-1)
      @unknown default: break
      }
    }
  }

  private var caption: some View {
    Text(title).ritmFont(16, weight: .semibold).foregroundStyle(RitmTheme.text)
  }

  private var control: some View {
    HStack(spacing: 6) {
      WorkoutStepHoldButton(symbol: "minus", enabled: canDecrease, label: title + " −") { step(-1) }
      Text(display)
        .ritmFont(21, weight: .semibold).monospacedDigit().foregroundStyle(RitmTheme.text)
        .contentTransition(.numericText())
        .lineLimit(1).fixedSize()
        .frame(minWidth: 64)
      WorkoutStepHoldButton(symbol: "plus", enabled: canIncrease, label: title + " +") { step(1) }
    }
  }
}

/// A 44 pt round `−` or `+`: a tap steps once, holding it repeats and speeds up until the end of
/// the range or the finger lifts. The step is taken when the finger lifts, so a scroll that
/// starts on the button does not change the value; moving the finger more than a few points
/// cancels the press.
private struct WorkoutStepHoldButton: View {
  private static let feedback = UISelectionFeedbackGenerator()
  private static let holdDelay: Duration = .milliseconds(450)
  private static let slowGap = 150
  private static let fastGap = 55
  private static let slop: CGFloat = 12

  let symbol: String
  let enabled: Bool
  let label: String
  /// Takes one step; `false` when it did nothing.
  let action: () -> Bool
  @GestureState private var pressed = false
  @State private var repeating = false
  @State private var cancelled = false
  @State private var holdTask: Task<Void, Never>?

  var body: some View {
    RitmSymbol(symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(RitmTheme.accentColor)
      .frame(width: 44, height: 44)
      .background(RitmTheme.soft, in: Circle())
      .overlay { Circle().strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
      .scaleEffect(pressed ? 0.92 : 1)
      .animation(RitmMotion.easeOut(0.12), value: pressed)
      .opacity(enabled ? 1 : 0.35)
      .contentShape(Circle())
      .gesture(hold, including: enabled ? .all : .subviews)
      .onChange(of: pressed) { _, isPressed in
        if isPressed { begin() } else { stop() }
      }
      .onDisappear { stop() }
      .accessibilityLabel(label)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { if enabled { _ = action() } }
  }

  private var hold: some Gesture {
    DragGesture(minimumDistance: 0)
      .updating($pressed) { _, state, _ in state = true }
      .onChanged { value in
        if moved(value.translation) {
          cancelled = true
          holdTask?.cancel()
        }
      }
      .onEnded { value in
        let isTap = !cancelled && !repeating && !moved(value.translation)
        if isTap { fire() }
      }
  }

  private func moved(_ translation: CGSize) -> Bool {
    hypot(translation.width, translation.height) > Self.slop
  }

  private func begin() {
    cancelled = false
    repeating = false
    holdTask?.cancel()
    holdTask = Task { @MainActor in
      try? await Task.sleep(for: Self.holdDelay)
      guard !Task.isCancelled else { return }
      repeating = true
      var gap = Self.slowGap
      while !Task.isCancelled {
        guard fire() else { return }
        try? await Task.sleep(for: .milliseconds(gap))
        gap = max(Self.fastGap, gap - 12)
      }
    }
  }

  private func stop() {
    holdTask?.cancel()
    holdTask = nil
    repeating = false
  }

  @discardableResult
  private func fire() -> Bool {
    let changed = action()
    if changed { Self.feedback.selectionChanged() }
    return changed
  }
}
