import RitmCore
import SwiftUI
import UIKit

/// The workout in progress: a snapshot of the program, set by set. The elapsed time comes from
/// the stored start timestamp, the rest timer sits above the bar, and the whole state is saved on
/// every change so the workout survives the app being closed.
struct WorkoutActiveView: View {
  @Environment(RitmStore.self) private var store
  let go: (WorkoutScreen) -> Void
  @State private var swapping: WorkoutSwapTarget?
  @State private var confirmingFinish = false
  @State private var confirmingCancel = false

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    WorkoutPage(
      title: store.text("Тренировка", "Workout"),
      action: {
        WorkoutHeaderButton(symbol: "chevron.left", label: store.text("К программам", "To programs")) {
          go(.home)
        }
      },
      bar: { WorkoutRestBar() },
      content: {
        if let session = workouts.session { content(session) }
      }
    )
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(store.text("Готово", "Done")) {
          UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
      }
    }
    .sheet(item: $swapping) { target in swapPicker(target.id) }
    .confirmationDialog(
      store.text("Завершить тренировку?", "Finish the workout?"), isPresented: $confirmingFinish,
      titleVisibility: .visible
    ) {
      Button(store.text("Завершить", "Finish")) { finish() }
      Button(store.text("Продолжить тренировку", "Keep going"), role: .cancel) {}
    } message: {
      let left = (workouts.session?.totalSets ?? 0) - (workouts.session?.doneSets ?? 0)
      Text(
        store.text(
          "Невыполненных подходов: \(left). В историю попадут только отмеченные.",
          "Sets not done: \(left). Only ticked sets go to the history."))
    }
    .confirmationDialog(
      store.text("Отменить тренировку?", "Cancel the workout?"), isPresented: $confirmingCancel,
      titleVisibility: .visible
    ) {
      Button(store.text("Отменить тренировку", "Cancel workout"), role: .destructive) {
        workouts.cancelWorkout()
        store.toasts.show(store.text("Тренировка отменена", "Workout cancelled"))
      }
      Button(store.text("Продолжить тренировку", "Keep going"), role: .cancel) {}
    } message: {
      Text(
        store.text(
          "Введённые значения будут потеряны, в историю ничего не попадёт.",
          "What you entered will be lost and nothing goes to the history."))
    }
  }

  private func content(_ session: WorkoutSession) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      stats(session).ritmPageReveal(index: 0)
      ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
        WorkoutExerciseCard(itemID: item.id, replace: { swapping = WorkoutSwapTarget(id: item.id) })
          .ritmPageReveal(index: min(index + 1, 7))
      }
      VStack(spacing: 10) {
        Button(store.text("Завершить тренировку", "Finish workout")) { tryFinish(session) }
          .buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
        Button(store.text("Отменить тренировку", "Cancel workout")) { confirmingCancel = true }
          .buttonStyle(WorkoutDangerButtonStyle())
      }
      .padding(.top, 4)
    }
  }

  private func stats(_ session: WorkoutSession) -> some View {
    RitmCard(padding: 14, radius: 22) {
      HStack(alignment: .top, spacing: 8) {
        stat(store.text("Программа", "Program")) {
          Text(session.programName).ritmFont(15, weight: .semibold).foregroundStyle(RitmTheme.text)
        }
        stat(store.text("Выполнено", "Done")) {
          HStack(spacing: 0) {
            RitmCountText(session.doneSets) { "\($0)" }
            Text(store.text(" из ", " of ") + "\(session.totalSets)")
          }
          .ritmFont(15, weight: .semibold).foregroundStyle(RitmTheme.text)
        }
        stat(store.text("Время", "Time")) {
          TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            Text(WorkoutClock.elapsed(from: session.startedAt, now: context.date))
              .ritmFont(15, weight: .semibold).monospacedDigit().foregroundStyle(RitmTheme.text)
          }
        }
      }
    }
  }

  private func stat<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).ritmFont(11).foregroundStyle(RitmTheme.muted)
      value()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func tryFinish(_ session: WorkoutSession) {
    if session.doneSets == 0 {
      store.toasts.show(
        store.text("Отметьте хотя бы один выполненный подход", "Tick at least one set first"))
    } else if session.doneSets < session.totalSets {
      confirmingFinish = true
    } else {
      finish()
    }
  }

  private func finish() {
    if workouts.finishWorkout() {
      store.toasts.show(store.text("Тренировка сохранена в историю", "Workout saved to the history"))
    }
  }

  @ViewBuilder private func swapPicker(_ itemID: String) -> some View {
    let used = Set(workouts.session?.items.map(\.exerciseID) ?? [])
    WorkoutExercisePicker(
      title: store.text("Заменить упражнение", "Replace exercise"), used: used,
      usedNote: store.text("уже в тренировке", "already in the workout"),
      createLabel: store.text("Создать и заменить", "Create and replace")
    ) { exercise in
      workouts.replaceExercise(item: itemID, with: exercise)
      store.toasts.show(store.text("Упражнение заменено: «\(exercise.name)»", "Exercise replaced: “\(exercise.name)”"))
    }
  }
}

/// The exercise of the workout being replaced; `Identifiable` so a sheet can be tied to it.
private struct WorkoutSwapTarget: Identifiable {
  let id: String
}

// MARK: - Exercise card

private struct WorkoutExerciseCard: View {
  @Environment(RitmStore.self) private var store
  let itemID: String
  let replace: () -> Void

  var body: some View {
    if let item = store.workouts.item(itemID) {
      VStack(alignment: .leading, spacing: 4) {
        header(item)
        columnTitles
        ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
          WorkoutSetRow(itemID: itemID, setID: set.id, index: index)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        Button {
          withAnimation(RitmMotion.easeOut(0.25)) { store.workouts.addSet(item: itemID) }
        } label: {
          Label(store.text("Подход", "Set"), systemImage: "plus")
            .ritmFont(12.5, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
            .frame(minHeight: 44).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .disabled(item.sets.count >= WorkoutSessionItem.maxSets)
        .accessibilityLabel(store.text("Добавить подход", "Add a set"))
      }
      .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
      .background { RitmPanelBackground(radius: 22) }
    }
  }

  private func header(_ item: WorkoutSessionItem) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(item.name).ritmFont(16, weight: .semibold).foregroundStyle(RitmTheme.text)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text(lastTime(item)).ritmFont(11.5).foregroundStyle(RitmTheme.muted)
      }
      Spacer(minLength: 4)
      WorkoutIconButton(
        symbol: "arrow.left.arrow.right",
        label: store.text("Заменить упражнение «\(item.name)»", "Replace exercise “\(item.name)”"),
        action: replace)
    }
    .padding(.leading, 4)
  }

  private func lastTime(_ item: WorkoutSessionItem) -> String {
    guard let previous = item.previous else {
      return store.text("Раньше не выполнялось", "Not done before")
    }
    return store.text("Последний раз: ", "Last time: ")
      + WorkoutText.date(previous.date, language: store.language)
  }

  private var columnTitles: some View {
    WorkoutSetColumns(
      number: { Text("№") }, previous: { Text(store.text("Прошлый раз", "Last time")) },
      weight: { Text(store.text("кг", "kg")) }, reps: { Text(store.text("повт.", "reps")) },
      tick: { Color.clear }, remove: { Color.clear })
    .ritmFont(10.5).foregroundStyle(RitmTheme.muted)
    .frame(minHeight: 20)
    .accessibilityHidden(true)
  }
}

/// The six columns of a set row: number, last time, weight, reps, tick, remove.
private struct WorkoutSetColumns<Number: View, Previous: View, Weight: View, Reps: View, Tick: View, Remove: View>: View {
  @ScaledMetric(relativeTo: .body) private var weightWidth: CGFloat = 58
  @ScaledMetric(relativeTo: .body) private var repsWidth: CGFloat = 50
  let number: Number
  let previous: Previous
  let weight: Weight
  let reps: Reps
  let tick: Tick
  let remove: Remove

  init(
    @ViewBuilder number: () -> Number, @ViewBuilder previous: () -> Previous,
    @ViewBuilder weight: () -> Weight, @ViewBuilder reps: () -> Reps,
    @ViewBuilder tick: () -> Tick, @ViewBuilder remove: () -> Remove
  ) {
    self.number = number()
    self.previous = previous()
    self.weight = weight()
    self.reps = reps()
    self.tick = tick()
    self.remove = remove()
  }

  var body: some View {
    HStack(spacing: 4) {
      number.frame(width: 20)
      previous.frame(maxWidth: .infinity, alignment: .leading)
      weight.frame(width: weightWidth)
      reps.frame(width: repsWidth)
      tick.frame(width: 44)
      remove.frame(width: 40)
    }
  }
}

// MARK: - Set row

private struct WorkoutSetRow: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let itemID: String
  let setID: String
  let index: Int

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    if let item = workouts.item(itemID), let set = workouts.set(item: itemID, set: setID) {
      let previous = item.previous?.set(at: index)
      WorkoutSetColumns(
        number: {
          Text("\(index + 1)").ritmFont(12).monospacedDigit().foregroundStyle(RitmTheme.muted)
        },
        previous: { previousColumn(previous, set: set) },
        weight: {
          field(
            placeholder: previous.map { WorkoutFormat.weight($0.weight, comma: store.language == .ru) }
              ?? store.text("кг", "kg"),
            text: Binding(
              get: { workouts.set(item: itemID, set: setID)?.weight ?? "" },
              set: { workouts.typeWeight($0, item: itemID, set: setID) }),
            keyboard: .decimalPad, done: set.done,
            invalid: !WorkoutNumber.isBlank(set.weight) && WorkoutNumber.normalizedWeight(set.weight) == nil,
            label: store.text("Вес в килограммах, подход \(index + 1)", "Weight in kilograms, set \(index + 1)"))
        },
        reps: {
          field(
            placeholder: previous.map { String($0.reps) } ?? store.text("повт.", "reps"),
            text: Binding(
              get: { workouts.set(item: itemID, set: setID)?.reps ?? "" },
              set: { workouts.typeReps($0, item: itemID, set: setID) }),
            keyboard: .numberPad, done: set.done,
            invalid: !WorkoutNumber.isBlank(set.reps) && WorkoutNumber.reps(set.reps) == nil,
            label: store.text("Повторы, подход \(index + 1)", "Reps, set \(index + 1)"))
        },
        tick: { tick(set) }, remove: { remove(item, set) })
      .frame(minHeight: 52)
    }
  }

  private func previousColumn(_ previous: WorkoutResultSet?, set: WorkoutSet) -> some View {
    let russian = store.language == .ru
    let delta = WorkoutDelta.make(set: set, previous: previous).map {
      WorkoutFormat.delta(
        $0, comma: russian, kg: russian ? "кг" : "kg", reps: russian ? "повт." : "reps",
        same: store.text("= как в прошлый раз", "= same as last time"))
    }
    return VStack(alignment: .leading, spacing: 0) {
      Text(previous.map { "\(WorkoutFormat.weight($0.weight, comma: russian)) × \($0.reps)" } ?? "—")
        .ritmFont(11.5).monospacedDigit().foregroundStyle(RitmTheme.muted)
      if let delta {
        Text(delta).ritmFont(10.5, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
          .minimumScaleFactor(0.75)
          .transition(.opacity)
      }
    }
    .lineLimit(1)
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.2), value: delta)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      (previous.map {
        store.text("Прошлый раз: ", "Last time: ") + "\(WorkoutFormat.weight($0.weight, comma: russian)) × \($0.reps)"
      } ?? store.text("Прошлый раз: нет", "Last time: none")) + (delta.map { ", " + $0 } ?? ""))
  }

  private func field(
    placeholder: String, text: Binding<String>, keyboard: UIKeyboardType, done: Bool, invalid: Bool,
    label: String
  ) -> some View {
    TextField(placeholder, text: text)
      .keyboardType(keyboard)
      .multilineTextAlignment(.center)
      .autocorrectionDisabled()
      .ritmFont(15, weight: .semibold)
      .monospacedDigit()
      .foregroundStyle(invalid ? RitmTheme.danger : done ? RitmTheme.muted : RitmTheme.text)
      .disabled(done)
      .frame(minHeight: 44)
      .background(done ? RitmTheme.soft : RitmTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .circular))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .circular)
          .strokeBorder(invalid ? RitmTheme.danger : done ? Color.clear : RitmTheme.line, lineWidth: 1)
      }
      .accessibilityLabel(label)
  }

  private func tick(_ set: WorkoutSet) -> some View {
    Button {
      toggle()
    } label: {
      Image(systemName: "checkmark")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(set.done ? RitmTheme.ctaInk : Color.clear)
        .frame(width: 40, height: 40)
        .background {
          Circle().fill(set.done ? AnyShapeStyle(RitmTheme.ctaGradient) : AnyShapeStyle(RitmTheme.field))
        }
        .overlay { Circle().strokeBorder(set.done ? Color.clear : RitmTheme.line, lineWidth: 1.5) }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .accessibilityLabel(store.text("Подход \(index + 1) выполнен", "Set \(index + 1) done"))
    .accessibilityValue(set.done ? store.text("да", "yes") : store.text("нет", "no"))
    .accessibilityAddTraits(.isToggle)
  }

  @ViewBuilder private func remove(_ item: WorkoutSessionItem, _ set: WorkoutSet) -> some View {
    if set.done {
      Color.clear
    } else {
      Button {
        withAnimation(reduceMotion ? nil : RitmMotion.easeOut(0.2)) {
          workouts.removeSet(item: itemID, set: setID)
        }
      } label: {
        Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 40, height: 44).contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.92))
      .disabled(item.sets.count <= 1).opacity(item.sets.count <= 1 ? 0.3 : 1)
      .accessibilityLabel(store.text("Удалить подход \(index + 1)", "Delete set \(index + 1)"))
    }
  }

  private func toggle() {
    switch workouts.toggleSet(item: itemID, set: setID) {
    case .done:
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .needsWeight:
      store.toasts.show(store.text("Укажите вес, затем отметьте подход", "Enter the weight, then tick the set"))
    case .needsReps:
      store.toasts.show(store.text("Укажите повторы, затем отметьте подход", "Enter the reps, then tick the set"))
    case .undone, .missing:
      break
    }
  }
}

// MARK: - Rest timer

/// The rest timer pinned above the bar. It shows `endDate - now`, never a negative number, and
/// at zero only a soft glow appears (steady under Reduce Motion). No sound, no notification.
private struct WorkoutRestBar: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    let rest = workouts.rest
    TimelineView(.animation(minimumInterval: 0.25, paused: rest.endDate == nil)) { context in
      bar(rest: rest, now: context.date)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
    .padding(.top, 4)
    .frame(maxWidth: 700)
    .frame(maxWidth: .infinity)
  }

  private func bar(rest: RestTimer, now: Date) -> some View {
    let phase = rest.phase(now: now)
    let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    return VStack(spacing: 6) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 0) {
          Text(label(phase)).ritmFont(11).foregroundStyle(RitmTheme.muted)
          Text(WorkoutClock.rest(remaining: rest.remaining(now: now)))
            .ritmFont(28, weight: .semibold, tracking: -0.04).monospacedDigit()
            .foregroundStyle(phase == .finished ? RitmTheme.accentColor : RitmTheme.text)
        }
        .accessibilityElement(children: .combine)
        Spacer(minLength: 4)
        RitmGlassGroup(spacing: 6) {
          HStack(spacing: 6) {
            Button {
              workouts.toggleRest()
            } label: {
              Image(systemName: phase == .running ? "pause.fill" : "play.fill")
                .font(.system(size: 17)).foregroundStyle(RitmTheme.ctaInk)
                .frame(width: 44, height: 44)
                .ritmGlass(in: Circle(), prominent: true, interactive: true)
                .contentShape(Circle())
            }
            .buttonStyle(RitmGlassButtonStyle())
            .accessibilityLabel(
              phase == .running ? store.text("Пауза", "Pause") : store.text("Запустить отдых", "Start rest"))
            Button {
              workouts.resetRest()
            } label: {
              Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 16)).foregroundStyle(RitmTheme.accentColor)
                .frame(width: 44, height: 44)
                .ritmGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
            }
            .buttonStyle(RitmGlassButtonStyle())
            .accessibilityLabel(store.text("Сбросить таймер", "Reset timer"))
            Button {
              workouts.extendRest()
            } label: {
              Text(store.text("+15\u{00A0}с", "+15\u{00A0}s"))
                .ritmFont(12.5, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
                .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
                .ritmGlass(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(RitmGlassButtonStyle())
            .accessibilityLabel(store.text("Добавить 15 секунд", "Add 15 seconds"))
          }
        }
      }
      RitmSegmentedControl(
        label: store.text("Время отдыха", "Rest time"), values: RestTimer.presets,
        title: { store.text("\(Int($0))\u{00A0}с", "\(Int($0))\u{00A0}s") },
        selection: Binding(get: { workouts.rest.preset }, set: { workouts.setRestPreset($0) }),
        fontSize: 12)
    }
    .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
    .background(RitmTheme.glassDense.opacity(0.55), in: shape)
    .ritmGlass(in: shape)
    .overlay {
      if phase == .finished {
        shape.strokeBorder(RitmTheme.accentColor, lineWidth: 2)
          .opacity(glow(rest: rest, now: now))
          .allowsHitTesting(false)
      }
    }
  }

  private func label(_ phase: RestTimer.Phase) -> String {
    switch phase {
    case .idle: store.text("Отдых", "Rest")
    case .running: store.text("Идёт отдых", "Resting")
    case .paused: store.text("Пауза", "Paused")
    case .finished: store.text("Отдых окончен", "Rest is over")
    }
  }

  /// Three soft pulses after the rest ends, then a steady glow; steady from the start under
  /// Reduce Motion.
  private func glow(rest: RestTimer, now: Date) -> Double {
    guard !reduceMotion, let end = rest.endDate else { return 0.85 }
    let since = now.timeIntervalSince(end)
    guard since < 3.3 else { return 0.85 }
    return 0.4 + 0.6 * abs(sin(since * .pi / 1.1))
  }
}
