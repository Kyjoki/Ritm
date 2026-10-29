import RitmCore
import SwiftUI

/// `.habit-card` on a phone: identity and actions, streak line, the week of marks, today's
/// action or counter, and the 3 / 7 / 14 / 30 awards.
struct HabitCard: View {
  let habit: Habit
  let today: String
  let busy: Bool
  let isRecord: Bool
  let onEdit: () -> Void
  let onArchive: () -> Void
  let onDelete: () -> Void
  let onProgress: (String, Int) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var archived: Bool { habit.archived == true }
  private var best: Int { HabitSchedule.bestStreak(habit, today: today) }
  private var scheduledToday: Bool { HabitSchedule.isScheduled(habit, on: today) }
  private var doneToday: Bool { HabitSchedule.isComplete(habit, on: today) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      head
      meta.padding(.top, 13).padding(.bottom, 4)
      if !archived {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(HabitSchedule.week(containing: today), id: \.self) { day in dayButton(day) }
          }
          .frame(minWidth: 366)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 18)
        bottom.padding(.top, 16)
      }
      awards
    }
    .padding(.vertical, 17)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { RitmPanelBackground() }
  }

  private var head: some View {
    HStack(alignment: .top, spacing: 12) {
      HStack(spacing: 13) {
        Image(systemName: habitSymbol(habit.icon))
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 42, height: 42)
          .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 13, style: .circular))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(habit.title)
            .ritmFont(15, weight: .semibold, lineSpacing: 3)
            .foregroundStyle(RitmTheme.text)
            .accessibilityAddTraits(.isHeader)
          Text(schedule).ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
      }
      Spacer(minLength: 0)
      HStack(spacing: 3) {
        HabitIconButton(
          symbol: "pencil",
          label: store.text("Редактировать привычку ", "Edit habit ") + habit.title, action: onEdit)
        HabitIconButton(
          symbol: archived ? "arrow.counterclockwise" : "archivebox",
          label: (archived
            ? store.text("Восстановить привычку ", "Restore habit ")
            : store.text("Архивировать привычку ", "Archive habit ")) + habit.title,
          action: onArchive
        )
        .disabled(busy)
        if archived {
          HabitIconButton(
            symbol: "trash", label: store.text("Удалить привычку ", "Delete habit ") + habit.title,
            action: onDelete)
        }
      }
    }
  }

  private var schedule: String {
    guard let weekdays = habit.weekdays, weekdays.count < 7 else {
      return store.text("Каждый день", "Every day")
    }
    // 25 October 2026 is a Sunday, the web's reference week.
    return weekdays.compactMap { HabitSchedule.addDays(to: "2026-10-25", days: $0) }
      .map { FeatureDate.label($0, zone: "UTC", language: store.language, template: "EEE") }
      .joined(separator: " · ")
  }

  private var meta: some View {
    let next = HabitsPlan.nextMilestone(habit, best: best)
    return HStack(spacing: 20) {
      HStack(spacing: 5) {
        Image(systemName: "flame").font(.system(size: 13)).foregroundStyle(RitmTheme.accentColor)
        metaCount(store.text("Серия", "Streak"), HabitSchedule.streak(habit, today: today))
      }
      .scaleEffect(isRecord && !reduceMotion ? 1.08 : 1, anchor: .leading)
      .animation(reduceMotion ? nil : RitmMotion.ease(0.42), value: isRecord)
      metaCount(store.text("Рекорд", "Record"), best)
      if let next {
        metaCount(store.text("Следующая цель", "Next goal"), next)
      }
    }
    .ritmFont(11)
    .foregroundStyle(RitmTheme.muted)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
  }

  /// «Серия: 5»: the label stays muted, the number counts up in the text colour.
  private func metaCount(_ title: String, _ value: Int) -> some View {
    HStack(spacing: 0) {
      Text(title + ": ")
      RitmCountText(value) { "\($0)" }.foregroundStyle(RitmTheme.text)
    }
  }

  private func dayButton(_ day: String) -> some View {
    let status = HabitsPlan.dayStatus(habit, on: day, today: today)
    let done = status == .done
    let canMark = HabitSchedule.canMark(habit, on: day, today: today)
    let label = FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEE d MMMM")
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    return Button {
      onProgress(day, done ? 0 : HabitSchedule.target(habit))
    } label: {
      VStack(spacing: 4) {
        Text(FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEE"))
          .ritmFont(10)
          .foregroundStyle(RitmTheme.muted)
        Text("\(Int(day.suffix(2)) ?? 0)").ritmFont(14, weight: .bold).foregroundStyle(RitmTheme.text)
        ZStack {
          Circle()
            .fill(done ? RitmTheme.accentColor : Color.clear)
            .overlay {
              Circle().strokeBorder(
                done ? RitmTheme.accentColor : status == .rest ? Color.clear : RitmTheme.line, lineWidth: 1)
            }
          if done {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(RitmTheme.accentInk)
          } else if status == .rest {
            Text("–").ritmFont(13, weight: .bold).foregroundStyle(RitmTheme.muted)
          }
        }
        .frame(width: 18, height: 18)
      }
      .padding(.vertical, 7)
      .padding(.horizontal, 2)
      .frame(maxWidth: .infinity, minHeight: 68)
      .frame(minWidth: 44)
      .background(status == .rest ? Color.clear : done ? HabitStyle.chosen : HabitStyle.tile, in: shape)
      .overlay { shape.strokeBorder(done ? HabitStyle.chosenBorder : RitmTheme.panelBorder, lineWidth: 1) }
      .overlay {
        if day == today { shape.inset(by: 3).strokeBorder(RitmTheme.accentColor, lineWidth: 2) }
      }
      .opacity(status == .future || status == .before ? 0.42 : status == .rest ? 0.55 : 1)
      .contentShape(shape)
    }
    .buttonStyle(RitmPressStyle(scale: 0.96))
    .disabled(!canMark || busy || !store.canWrite)
    .accessibilityLabel(
      (done
        ? store.text("Снять отметку \(habit.title) за \(label)", "Undo \(habit.title) on \(label)")
        : store.text("Отметить \(habit.title) за \(label)", "Mark \(habit.title) on \(label)")) + ". "
        + statusText(status, done: done))
    .accessibilityAddTraits(done ? .isSelected : [])
  }

  private func statusText(_ status: HabitsPlan.DayStatus, done: Bool) -> String {
    switch status {
    case .future: store.text("Будущий день", "Future day")
    case .rest: store.text("Не запланировано", "Rest day")
    case .before: store.text("До начала", "Before start")
    case .done, .pending: done ? store.text("Выполнено", "Completed") : store.text("Запланировано", "Scheduled")
    }
  }

  private var bottom: some View {
    let progress = HabitSchedule.progress(habit, on: today)
    return HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(scheduledToday ? store.text("Прогресс сегодня", "Today's progress") : store.text("Сегодня выходной", "Rest day today"))
          .ritmFont(11)
          .foregroundStyle(RitmTheme.muted)
        if scheduledToday {
          progressText(progress)
            .ritmFont(12, weight: .bold)
            .foregroundStyle(RitmTheme.text)
        }
      }
      Spacer(minLength: 0)
      if scheduledToday {
        if habit.target != nil {
          HabitStepper(habit: habit, today: today, busy: busy, onSave: { onProgress(today, $0) })
        } else {
          markButton(doneToday ? store.text("Отменить", "Undo") : store.text("Выполнить", "Complete")) {
            onProgress(today, doneToday ? 0 : 1)
          }
        }
      }
    }
  }

  /// «3 / 8 стаканов»: the recorded count runs up to the new value.
  @ViewBuilder private func progressText(_ progress: Int) -> some View {
    if let target = habit.target {
      let unit = (habit.unit ?? "").isEmpty ? "" : " " + (habit.unit ?? "")
      RitmCountText(progress) { "\($0) / \(target)" + unit }
    } else {
      Text(doneToday ? store.text("Выполнено", "Completed") : store.text("Ещё не выполнено", "Not done yet"))
    }
  }

  private func markButton(_ title: String, action: @escaping () -> Void) -> some View {
    Group {
      if doneToday {
        Button(action: action) { Label(title, systemImage: "checkmark") }
          .buttonStyle(RitmSecondaryButtonStyle())
      } else {
        Button(action: action) { Label(title, systemImage: "checkmark").padding(.horizontal, 4) }
          .buttonStyle(RitmPrimaryButtonStyle())
          .fixedSize()
      }
    }
    .disabled(busy || !store.canWrite)
  }

  private var awards: some View {
    let earned = HabitsPlan.awards(habit, best: best)
    return HStack(spacing: 6) {
      ForEach(HabitSchedule.milestones, id: \.self) { milestone in
        let won = earned.contains(milestone)
        HStack(spacing: 3) {
          Image(systemName: "flame").font(.system(size: 11))
          Text("\(milestone)")
        }
        .ritmFont(10)
        .foregroundStyle(won ? RitmTheme.accentColor : RitmTheme.muted)
        .padding(.vertical, 4)
        .padding(.horizontal, 7)
        .background(won ? HabitStyle.chosen : HabitStyle.tile, in: RoundedRectangle(cornerRadius: 8, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .circular)
            .strokeBorder(won ? HabitStyle.chosenBorder : RitmTheme.panelBorder, lineWidth: 1)
        }
        .accessibilityLabel(
          store.text("\(milestone) дней подряд", "\(milestone) days in a row")
            + (won ? store.text(", получено", ", earned") : ""))
      }
    }
    .padding(.top, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.panelBorder).frame(height: 1) }
    .padding(.top, 17)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Достижения", "Achievements"))
  }
}

/// `HabitProgressEditor`: − value +, Save when edited, complete or undo the goal, and reset.
private struct HabitStepper: View {
  let habit: Habit
  let today: String
  let busy: Bool
  let onSave: (Int) -> Void
  @Environment(RitmStore.self) private var store
  @State private var draft = ""

  private var progress: Int { HabitSchedule.progress(habit, on: today) }
  private var target: Int { HabitSchedule.target(habit) }
  private var value: Int? { Int(draft.trimmingCharacters(in: .whitespaces)) }
  private var valid: Bool { value.map { (0...target).contains($0) } ?? false }
  private var done: Bool { HabitSchedule.isComplete(habit, on: today) }

  var body: some View {
    HStack(spacing: 7) {
      HStack(spacing: 0) {
        stepButton("minus", store.text("Уменьшить прогресс ", "Decrease progress ")) { onSave((value ?? progress) - 1) }
          .disabled(busy || !valid || (value ?? 0) <= 0)
        TextField("", text: $draft)
          .keyboardType(.numberPad)
          .multilineTextAlignment(.center)
          .ritmFont(12, weight: .bold)
          .foregroundStyle(RitmTheme.text)
          .frame(width: 54, height: 44)
          .accessibilityLabel(store.text("Введите прогресс ", "Enter progress ") + habit.title)
        stepButton("plus", store.text("Увеличить прогресс ", "Increase progress ")) { onSave((value ?? progress) + 1) }
          .disabled(busy || !valid || (value ?? target) >= target)
      }
      .background(HabitStyle.tile, in: RoundedRectangle(cornerRadius: 10, style: .circular))
      .overlay { RoundedRectangle(cornerRadius: 10, style: .circular).strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
      if valid, let value, value != progress {
        Button(store.text("Сохранить", "Save")) { onSave(value) }
          .buttonStyle(RitmPrimaryButtonStyle())
          .fixedSize()
          .disabled(busy)
      }
      Button {
        onSave(done ? 0 : target)
      } label: {
        Label(done ? store.text("Отменить", "Undo") : store.text("Выполнить цель", "Complete goal"), systemImage: "checkmark")
      }
      .buttonStyle(RitmSecondaryButtonStyle())
      .disabled(busy)
      if progress > 0 {
        HabitIconButton(symbol: "arrow.counterclockwise", label: store.text("Сбросить прогресс ", "Reset progress ") + habit.title) {
          onSave(0)
        }
        .disabled(busy)
      }
    }
    .onAppear { draft = String(progress) }
    .onChange(of: progress) { _, value in draft = String(value) }
  }

  private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(label + habit.title)
  }
}
