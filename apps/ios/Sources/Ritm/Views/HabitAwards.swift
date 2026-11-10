import RitmCore
import SwiftUI

/// «Награды»: a horizontal row of chips, one per earned achievement of 7 days or more
/// («7 дней подряд · IELTS · 9 нояб.»), and a dashed one for the goal that is closest.
struct HabitAwardsRow: View {
  let awards: [HabitAward]
  let goal: HabitGoal?
  let onOpen: (String) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    if awards.isEmpty && goal == nil {
      Text(
        store.text(
          "Награда появится, когда серия дойдёт до 7 дней.",
          "An award appears when a streak reaches 7 days.")
      )
      .ritmFont(12, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      .padding(.horizontal, 2)
    } else {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 10) {
          ForEach(awards) { award in earnedChip(award) }
          if let goal { goalChip(goal) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)
      .scrollClipDisabled()
      .padding(.horizontal, -16)
    }
  }

  private func earnedChip(_ award: HabitAward) -> some View {
    let tint = HabitPalette.tint(for: award.habitID)
    let date = HabitDates.label(
      award.day, zone: store.timeZone, language: store.language, template: "d MMM")
    return Button {
      onOpen(award.habitID)
    } label: {
      chip(
        symbol: "medal", title: HabitSheetText.streakTitle(award.level, language: store.language),
        note: award.title + " · " + date, tint: tint, dashed: false)
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(
      HabitSheetText.streakTitle(award.level, language: store.language) + ", " + award.title + ", " + date)
  }

  private func goalChip(_ goal: HabitGoal) -> some View {
    Button {
      onOpen(goal.habitID)
    } label: {
      chip(
        symbol: "target",
        title: store.text("\(goal.level) дней · \(goal.title)", "\(goal.level) days · \(goal.title)"),
        note: store.text("ещё \(goal.remaining)", "\(goal.remaining) to go"),
        tint: nil, dashed: true)
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(
      store.text(
        "Следующая цель: \(goal.level) дней, \(goal.title), ещё \(goal.remaining)",
        "Next goal: \(goal.level) days, \(goal.title), \(goal.remaining) to go"))
  }

  private func chip(symbol: String, title: String, note: String, tint: HabitTint?, dashed: Bool)
    -> some View
  {
    HStack(spacing: 10) {
      RitmSymbol(symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(tint?.base ?? RitmTheme.accentColor)
        .frame(width: 34, height: 34)
        .background {
          if let tint {
            Circle().fill(tint.tile)
          }
        }
        .overlay {
          Circle().strokeBorder(tint?.tileRim ?? RitmTheme.line, lineWidth: 1)
        }
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .ritmFont(13, weight: .semibold, tracking: -0.02)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
        Text(note).ritmFont(11.5).foregroundStyle(RitmTheme.muted).lineLimit(1)
      }
    }
    .padding(.vertical, 8)
    .padding(.leading, 8)
    .padding(.trailing, 16)
    .background { if !dashed { Capsule().fill(HabitPalette.surface) } }
    .overlay {
      if dashed {
        Capsule().strokeBorder(
          RitmTheme.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      } else {
        Capsule().strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
      }
    }
    .contentShape(Capsule())
  }
}

/// `.arch`: «Архив · 2 ›» opens the archived habits, each with a «Вернуть» button; an archived
/// habit can also be deleted for good.
struct HabitArchiveBlock: View {
  let habits: [Habit]
  @Binding var open: Bool
  let busy: Bool
  let onRestore: (Habit) -> Void
  let onDelete: (Habit) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        open.toggle()
      } label: {
        HStack(spacing: 4) {
          Text(store.text("Архив · \(habits.count)", "Archive · \(habits.count)"))
          RitmSymbol(open ? "chevron.down" : "chevron.right").font(.system(size: 13, weight: .semibold))
        }
        .ritmFont(13, weight: .semibold, tracking: -0.01)
        .foregroundStyle(RitmTheme.accentColor)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      .accessibilityAddTraits(.isHeader)
      .accessibilityValue(open ? store.text("развёрнут", "expanded") : store.text("свёрнут", "collapsed"))
      if open {
        VStack(spacing: 8) {
          ForEach(habits) { habit in row(habit) }
        }
        .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.3), value: open)
  }

  private func row(_ habit: Habit) -> some View {
    let tint = HabitPalette.tint(for: habit.id)
    let record = HabitStatsCache.shared.stats(for: habit, today: store.today).best
    return HStack(spacing: 12) {
      RitmSymbol(habitSymbol(habit.icon))
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(tint.base)
        .frame(width: 38, height: 38)
        .background(tint.tile, in: RoundedRectangle(cornerRadius: 12, style: .circular))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(habit.title)
          .ritmFont(14, weight: .semibold, tracking: -0.02)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
        Text(store.text("В архиве · рекорд \(record) дн.", "Archived · best \(record) d"))
          .ritmFont(11.5).foregroundStyle(RitmTheme.muted).lineLimit(1)
      }
      Spacer(minLength: 0)
      HabitIconButton(
        symbol: "trash", label: store.text("Удалить привычку ", "Delete habit ") + habit.title
      ) { onDelete(habit) }
      .disabled(busy)
      Button {
        onRestore(habit)
      } label: {
        HStack(spacing: 6) {
          RitmSymbol("arrow.counterclockwise").font(.system(size: 15))
          Text(store.text("Вернуть", "Restore"))
        }
      }
      .buttonStyle(HabitCapsuleStyle(horizontal: 14))
      .disabled(busy)
      .accessibilityLabel(store.text("Восстановить привычку ", "Restore habit ") + habit.title)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
    .background(HabitPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .circular).strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
    }
  }
}
