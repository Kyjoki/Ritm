import RitmCore
import SwiftUI
import UIKit

/// The workout in progress («Таблица подходов»): the header with the clock, a strip of all the
/// exercises, one exercise at a time as a table of sets, and the way to the next. The elapsed time
/// comes from the stored start timestamp and the whole state is saved on every change, so the
/// workout survives the app being closed. Leaving the screen keeps it running.
struct WorkoutActiveView: View {
  /// A workout younger than this can be dropped with one tap on «Отменить».
  private static let quickCancelWindow: TimeInterval = 120

  private static let haptic = UIImpactFeedbackGenerator(style: .light)

  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let go: (WorkoutScreen) -> Void
  let finished: (WorkoutRecord) -> Void
  @State private var current = 0
  @State private var forward = true
  @State private var selection: WorkoutSetSelection?
  @State private var sheet: Sheet?
  @State private var confirmingFinish = false
  @State private var confirmingCancel = false
  /// «Сохранить изменения в программе?», asked when the workout differs from its program.
  @State private var savingProgram = false
  /// An exercise with done sets that is about to be replaced or removed: asked first.
  @State private var replacingItem: String?
  @State private var removingItem: String?

  fileprivate enum Sheet: Identifiable, Equatable {
    case menu, exercises
    case options(String)
    case pick(Pick)

    var id: String {
      switch self {
      case .menu: "menu"
      case .exercises: "exercises"
      case .options(let id): "options-" + id
      case .pick(let pick): "pick-" + pick.id
      }
    }
  }

  /// Why the exercise picker is open.
  fileprivate enum Pick: Equatable {
    case add(after: Int?)
    case replace(String)

    var id: String {
      switch self {
      case .add(let after): "add-\(after ?? -1)"
      case .replace(let id): "replace-" + id
      }
    }

    var isReplace: Bool {
      if case .replace = self { return true }
      return false
    }
  }

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    WorkoutPage(
      header: { if let session = workouts.session { header(session) } },
      content: { if let session = workouts.session { content(session) } }
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
    .onAppear { current = firstOpen(workouts.session) }
    .onChange(of: workouts.systemInput?.id, initial: true) { _, _ in
      guard let request = workouts.systemInput, let session = workouts.session,
        request.target.workoutID == session.id,
        let index = session.items.firstIndex(where: { $0.id == request.target.itemID }) else { return }
      sheet = nil
      confirmingFinish = false
      confirmingCancel = false
      savingProgram = false
      replacingItem = nil
      removingItem = nil
      show(index)
      selection = WorkoutSetSelection(itemID: request.target.itemID, setID: request.target.setID,
        field: request.target.field == .weight ? .weight : .reps)
    }
    .sheet(item: $sheet) { sheet in sheetContent(sheet) }
    .alert(
      store.text("Завершить тренировку?", "Finish the workout?"), isPresented: $confirmingFinish
    ) {
      Button(store.text("Завершить", "Finish")) {
        if workouts.programChange == nil { finish(saving: false) } else { later { savingProgram = true } }
      }
      Button(store.text("Продолжить тренировку", "Keep going"), role: .cancel) {}
    } message: {
      let left = (workouts.session?.totalSets ?? 0) - (workouts.session?.doneSets ?? 0)
      Text(
        store.text(
          "Невыполненных подходов: \(left). В историю попадут только отмеченные.",
          "Sets not done: \(left). Only ticked sets go to the history."))
    }
    .confirmationDialog(
      store.text("Сохранить изменения в программе?", "Save the changes to the program?"),
      isPresented: $savingProgram, titleVisibility: .visible
    ) {
      Button(store.text("Сохранить в программу", "Save to the program")) { finish(saving: true) }
      Button(store.text("Только в этой тренировке", "Only in this workout")) { finish(saving: false) }
      Button(store.text("Продолжить тренировку", "Keep going"), role: .cancel) {}
    } message: {
      Text(changeSummary)
    }
    .alert(
      store.text("Заменить упражнение?", "Replace the exercise?"),
      isPresented: Binding(get: { replacingItem != nil }, set: { if !$0 { replacingItem = nil } })
    ) {
      Button(store.text("Выбрать замену", "Choose a replacement")) {
        if let id = replacingItem { later { sheet = .pick(.replace(id)) } }
        replacingItem = nil
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) { replacingItem = nil }
    } message: {
      let done = replacingItem.flatMap { workouts.item($0)?.doneCount } ?? 0
      Text(
        store.text(
          "Выполненных подходов: \(done). Они останутся в этой тренировке под прежним упражнением, у нового подходы начнутся заново.",
          "Sets done: \(done). They stay in this workout under the old exercise; the new one starts its sets again."))
    }
    .alert(
      store.text("Убрать упражнение?", "Remove the exercise?"),
      isPresented: Binding(get: { removingItem != nil }, set: { if !$0 { removingItem = nil } })
    ) {
      Button(store.text("Убрать", "Remove"), role: .destructive) {
        if let id = removingItem { remove(id) }
        removingItem = nil
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) { removingItem = nil }
    } message: {
      let done = removingItem.flatMap { workouts.item($0)?.doneCount } ?? 0
      Text(
        store.text(
          "Выполненных подходов: \(done). Они не попадут в историю.",
          "Sets done: \(done). They will not go to the history."))
    }
    .alert(
      store.text("Отменить тренировку?", "Cancel the workout?"), isPresented: $confirmingCancel
    ) {
      Button(store.text("Отменить тренировку", "Cancel workout"), role: .destructive) {
        workouts.cancelWorkout()
        store.toasts.show(store.text("Тренировка отменена", "Workout cancelled"))
      }
      Button(store.text("Продолжить", "Keep going"), role: .cancel) {}
    } message: {
      Text(store.text("Тренировка не сохранится", "The workout will not be saved"))
    }
  }

  // MARK: Header

  private func header(_ session: WorkoutSession) -> some View {
    VStack(spacing: 6) {
      HStack(spacing: 10) {
        WorkoutRoundButton(
          symbol: "chevron.left", label: store.text("К программам, тренировка продолжается", "Back, the workout keeps running")
        ) { go(.home) }
        VStack(spacing: 0) {
          Text(session.programName).ritmFont(16, weight: .bold, tracking: -0.03)
            .foregroundStyle(RitmTheme.text).lineLimit(1)
          clock(session)
        }
        .frame(maxWidth: .infinity)
        WorkoutRoundButton(symbol: "ellipsis", label: store.text("Меню тренировки", "Workout menu")) {
          sheet = .menu
        }
      }
      .padding(.bottom, 4)
      segments(session)
    }
    .padding(.bottom, 10)
  }

  /// «mm:ss · Отменить»: the quick cancel lives only for the first two minutes.
  private func clock(_ session: WorkoutSession) -> some View {
    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
      HStack(spacing: 4) {
        Text(WorkoutClock.elapsed(from: session.startedAt, now: context.date)).monospacedDigit()
        if context.date.timeIntervalSince(session.startedAt) < Self.quickCancelWindow {
          Text("·")
          Button(store.text("Отменить", "Cancel")) { confirmingCancel = true }
            .ritmFont(12.5, weight: .bold).foregroundStyle(RitmTheme.accentColor)
            .underline()
            .frame(minHeight: 44)
        }
      }
      .ritmFont(12.5).foregroundStyle(RitmTheme.muted)
    }
    .frame(height: 20)
  }

  /// `.w-seg`: one bar per exercise, filled by its done sets; tap to jump.
  private func segments(_ session: WorkoutSession) -> some View {
    HStack(spacing: 5) {
      ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
        let share = item.sets.isEmpty ? 0 : Double(item.doneCount) / Double(item.sets.count)
        Button {
          show(index)
        } label: {
          Capsule().fill(RitmTheme.ringTrack)
            .frame(height: 6)
            .overlay(alignment: .leading) {
              Capsule()
                .fill(share >= 1 ? AnyShapeStyle(WorkoutColors.income) : AnyShapeStyle(WorkoutPalette.progressGradient))
                .scaleEffect(x: max(share, 0.0001), anchor: .leading)
                .animation(reduceMotion ? nil : RitmMotion.easeOut(0.4), value: share)
            }
            .overlay {
              if index == current { Capsule().strokeBorder(RitmTheme.accentColor, lineWidth: 1.5).padding(-1.5) }
            }
            .scaleEffect(y: index == current ? 1.5 : 1)
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.text("Упражнение \(index + 1)", "Exercise \(index + 1)"))
        .accessibilityValue("\(item.doneCount) / \(item.sets.count)")
      }
    }
    .padding(.horizontal, 4)
  }

  // MARK: Content

  private func content(_ session: WorkoutSession) -> some View {
    let index = min(current, max(0, session.items.count - 1))
    let all = session.items.allSatisfy { $0.sets.allSatisfy(\.done) }
    return VStack(spacing: 0) {
      if session.items.indices.contains(index) {
        WorkoutExerciseCard(
          itemID: session.items[index].id, selection: $selection,
          ticked: { ticked($0, session: session) },
          options: { sheet = .options(session.items[index].id) }
        )
        .id(session.items[index].id)
        .transition(
          reduceMotion
            ? .opacity
            : .asymmetric(
              insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
              removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        .simultaneousGesture(swipe(count: session.items.count))
      }
      nav(session, index: index)
      Button {
        tryFinish(session)
      } label: {
        Text(store.text("Завершить тренировку", "Finish workout"))
          .ritmFont(14.5, weight: .bold)
          .foregroundStyle(all ? RitmTheme.ctaInk : RitmTheme.accentColor)
          .frame(maxWidth: .infinity, minHeight: 50)
          .ritmGlass(in: Capsule(), prominent: all, interactive: true)
          .contentShape(Capsule())
      }
      .buttonStyle(RitmGlassButtonStyle())
      .padding(.top, 12)
    }
    .clipped()
  }

  private func nav(_ session: WorkoutSession, index: Int) -> some View {
    HStack(spacing: 10) {
      WorkoutRoundButton(symbol: "chevron.left", label: store.text("Предыдущее упражнение", "Previous exercise"), size: 46) {
        show(index - 1)
      }
      .disabled(index == 0).opacity(index == 0 ? 0.35 : 1)
      Button {
        sheet = .exercises
      } label: {
        HStack(spacing: 8) {
          RitmSymbol("list.bullet").font(.system(size: 18)).foregroundStyle(RitmTheme.accentColor)
          Text(store.text("Упражнения · \(index + 1) из \(session.items.count)", "Exercises · \(index + 1) of \(session.items.count)"))
            .ritmFont(14, weight: .semibold).foregroundStyle(RitmTheme.text).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .ritmGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
      }
      .buttonStyle(RitmGlassButtonStyle())
      WorkoutRoundButton(symbol: "chevron.right", label: store.text("Следующее упражнение", "Next exercise"), size: 46) {
        show(index + 1)
      }
      .disabled(index >= session.items.count - 1).opacity(index >= session.items.count - 1 ? 0.35 : 1)
    }
    .padding(.top, 12)
  }

  /// A horizontal swipe changes the exercise; a vertical one still scrolls the page.
  private func swipe(count: Int) -> some Gesture {
    DragGesture(minimumDistance: 24).onEnded { value in
      let dx = value.translation.width
      guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
      show(dx < 0 ? current + 1 : current - 1)
    }
  }

  // MARK: Actions

  private func show(_ index: Int) {
    guard let count = workouts.session?.items.count, (0..<count).contains(index), index != current else { return }
    forward = index > current
    selection = nil
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.38)) { current = index }
  }

  private func firstOpen(_ session: WorkoutSession?) -> Int {
    session?.items.firstIndex { $0.sets.contains { !$0.done } } ?? 0
  }

  private func ticked(_ result: WorkoutSessionItem.TickResult, session: WorkoutSession) {
    switch result {
    case .done:
      Self.haptic.impactOccurred()
      // The last set of an exercise moves on to the next one after a beat, so the tick and the
      // progress bar are seen first.
      let at = current
      if let item = workouts.session?.items[safe: at], item.sets.allSatisfy(\.done) {
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(350))
          let allDone = workouts.session?.items[safe: at]?.sets.allSatisfy(\.done) == true
          if current == at, allDone { show(at + 1) }
        }
      }
    case .needsWeight:
      store.toasts.show(store.text("Укажите вес, затем отметьте подход", "Enter the weight, then tick the set"))
    case .needsReps:
      store.toasts.show(store.text("Укажите повторы, затем отметьте подход", "Enter the reps, then tick the set"))
    case .undone, .missing:
      break
    }
  }

  private func tryFinish(_ session: WorkoutSession) {
    if session.doneSets == 0 {
      store.toasts.show(
        store.text("Отметьте хотя бы один выполненный подход", "Tick at least one set first"))
    } else if session.doneSets < session.totalSets {
      confirmingFinish = true
    } else if workouts.programChange != nil {
      savingProgram = true
    } else {
      finish(saving: false)
    }
  }

  private func finish(saving: Bool) {
    sheet = nil
    guard let record = workouts.finishWorkout(savingToProgram: saving) else { return }
    if saving { store.toasts.show(store.text("Программа обновлена", "Program updated")) }
    finished(record)
    go(.summary)
  }

  /// What the workout changed in its program, for the question at the finish.
  private var changeSummary: String {
    guard let change = workouts.programChange else { return "" }
    var parts: [String] = []
    if change.added > 0 { parts.append(store.text("добавлено \(change.added)", "added \(change.added)")) }
    if change.removed > 0 { parts.append(store.text("убрано \(change.removed)", "removed \(change.removed)")) }
    if change.modified > 0 { parts.append(store.text("изменено \(change.modified)", "changed \(change.modified)")) }
    if change.reordered { parts.append(store.text("новый порядок", "new order")) }
    let name = workouts.session?.programName ?? ""
    let list = parts.joined(separator: ", ")
    return store.text("Программа «\(name)»: \(list).", "Program “\(name)”: \(list).")
  }

  /// Lets an alert finish closing before the next presentation starts.
  private func later(_ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(350))
      work()
    }
  }

  // MARK: Editing the exercises

  @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
    switch sheet {
    case .menu:
      WorkoutMenuSheet(canRemove: (workouts.session?.items.count ?? 0) > 1) { menu($0) }
    case .exercises:
      WorkoutExercisesSheet(
        current: current,
        open: { index in
          self.sheet = nil
          show(index)
        },
        add: { self.sheet = .pick(.add(after: nil)) },
        options: { self.sheet = .options($0) },
        move: moveExercise)
    case .options(let id):
      WorkoutExerciseOptionsSheet(
        itemID: id, canRemove: (workouts.session?.items.count ?? 0) > 1,
        replace: { startReplace(id) }, remove: { startRemove(id) })
    case .pick(let pick):
      WorkoutExercisePicker(
        title: pick.isReplace
          ? store.text("Заменить упражнение", "Replace exercise")
          : store.text("Добавить упражнение", "Add exercise"),
        used: Set((workouts.session?.items ?? []).map(\.exerciseID)),
        usedNote: store.text("уже в тренировке", "already in the workout")
      ) { picked(pick, $0) }
    }
  }

  private var currentItemID: String? { workouts.session?.items[safe: current]?.id }

  private func menu(_ action: WorkoutMenuAction) {
    switch action {
    case .exercises: sheet = .exercises
    case .addAfterCurrent: sheet = .pick(.add(after: current))
    case .addAtEnd: sheet = .pick(.add(after: nil))
    case .replaceCurrent: if let id = currentItemID { startReplace(id) }
    case .removeCurrent: if let id = currentItemID { startRemove(id) }
    case .finish:
      sheet = nil
      if let session = workouts.session { tryFinish(session) }
    case .cancel:
      sheet = nil
      confirmingCancel = true
    }
  }

  /// An exercise with done sets asks first; they stay in the log under the old exercise.
  private func startReplace(_ id: String) {
    if workouts.session?.hasDoneSets(id) == true {
      sheet = nil
      replacingItem = id
    } else {
      sheet = .pick(.replace(id))
    }
  }

  private func startRemove(_ id: String) {
    sheet = nil
    if workouts.session?.hasDoneSets(id) == true {
      removingItem = id
    } else {
      remove(id)
    }
  }

  private func remove(_ id: String) {
    keepingCurrent {
      withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.3)) {
        workouts.removeExercise(item: id)
      }
    }
  }

  private func picked(_ pick: Pick, _ exercise: WorkoutExercise) {
    let id: String?
    switch pick {
    case .add(let after): id = workouts.addExercise(exercise, after: after)
    case .replace(let itemID): id = workouts.replaceExercise(item: itemID, with: exercise)
    }
    guard let id else {
      store.toasts.show(
        store.text("Это упражнение уже есть в тренировке.", "This exercise is already in the workout."))
      return
    }
    selection = nil
    if let index = workouts.session?.items.firstIndex(where: { $0.id == id }) { show(index) }
  }

  private func moveExercise(from: Int, to: Int) {
    keepingCurrent { workouts.moveExercise(from: from, to: to) }
  }

  /// Runs a change of the exercise list and keeps the same exercise on screen.
  private func keepingCurrent(_ change: () -> Void) {
    let id = currentItemID
    change()
    guard let items = workouts.session?.items else { return }
    if let id, let index = items.firstIndex(where: { $0.id == id }) {
      current = index
    } else {
      current = min(current, max(0, items.count - 1))
    }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
