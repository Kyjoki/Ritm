import RitmCore
import SwiftUI

/// The two things docked above the bottom bar: the undated-tasks chip on the left and the «+»
/// button on the right. They float over the hour grid, which scrolls clear of them.
struct CalendarFloatingButtons: View {
  let undatedCount: Int
  let onAdd: () -> Void
  let onUndated: () -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    HStack(alignment: .bottom, spacing: 12) {
      if undatedCount > 0 { chip }
      Spacer(minLength: 0)
      addButton
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 12)
  }

  private var chip: some View {
    Button(action: onUndated) {
      HStack(spacing: 8) {
        RitmIcon(.checklist).font(.system(size: 18)).accessibilityHidden(true)
        Text(store.text("Без даты", "No date")).ritmFont(14, weight: .semibold).lineLimit(1)
        Text("\(undatedCount)")
          .ritmFont(14, weight: .bold)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.accentColor)
      }
      .foregroundStyle(RitmTheme.text)
      .padding(.horizontal, 16)
      .frame(minHeight: 48)
      .ritmFloatingGlass(in: Capsule(), interactive: true)
      .contentShape(Capsule())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(store.text("Без даты: \(undatedCount)", "No date: \(undatedCount)"))
  }

  private var addButton: some View {
    Button(action: onAdd) {
      RitmSymbol("plus")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(RitmTheme.ctaInk)
        .frame(width: 58, height: 58)
        .ritmGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), prominent: true, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(store.text("Добавить запись", "Add entry"))
  }
}

/// «Твой темп · Без даты»: the pace note and the tasks that have no date yet, in a sheet.
struct CalendarBacklogSheet: View {
  let tasks: [RitmTask]
  let plannedCount: Int
  let uncertain: Bool
  let onOpen: (RitmTask) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 13) {
          paceCard
          backlogCard
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
      }
    }
  }

  private var paceCard: some View {
    RitmCard(padding: 20) {
      VStack(alignment: .leading, spacing: 13) {
        HStack {
          Label { Text(store.text("Твой темп", "Your pace")) } icon: { RitmSymbol("sparkles") }
            .ritmFont(14, weight: .semibold, tracking: -0.02)
            .foregroundStyle(RitmTheme.text)
          Spacer()
          Text(store.text("Выбранный период", "Selected period")).ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
        Group {
          if plannedCount > 0 {
            Text(
              (uncertain ? store.text("Показано", "Shown") : store.text("В плане", "Planned"))
                + " \(plannedCount) " + CalendarPlan.recordWord(plannedCount, language: store.language)
                + store.text(". Оставь немного времени для себя.", ". Leave some time for yourself."))
          } else if uncertain {
            Text(store.text("Обновляем расписание. Дождись синхронизации.", "Updating the schedule. Wait for sync."))
          } else {
            Text(
              store.text(
                "Пока всё свободно. Начни с одного важного дела.",
                "Everything is free for now. Start with one important thing."))
          }
        }
        .ritmFont(13, lineSpacing: 8)
        .foregroundStyle(RitmTheme.muted)
        Text(
          store.text(
            "При редактировании повторения изменится только выбранная запись.",
            "Editing a repeat changes only the selected entry.")
        )
        .ritmFont(10)
        .foregroundStyle(RitmTheme.muted)
      }
    }
  }

  private var backlogCard: some View {
    RitmCard(padding: 20) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(store.text("Без даты", "No date"))
            .ritmFont(14, weight: .semibold, tracking: -0.02)
            .foregroundStyle(RitmTheme.text)
          Spacer()
          Text("\(tasks.count)").ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
        if tasks.isEmpty {
          Text(
            store.text(
              "Все дела уже нашли своё место в расписании.", "Everything already has its place.")
          )
          .ritmFont(13, lineSpacing: 8)
          .foregroundStyle(RitmTheme.muted)
          .padding(.vertical, 13)
        }
        ForEach(tasks.prefix(4)) { task in row(task) }
        if tasks.count > 4 {
          Text(
            store.text(
              "Ещё \(tasks.count - 4) в разделе «Мой день»",
              "\(tasks.count - 4) more in My day")
          )
          .ritmFont(10)
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 10)
        }
      }
    }
  }

  private func row(_ task: RitmTask) -> some View {
    Button {
      onOpen(task)
    } label: {
      HStack(spacing: 10) {
        Text(task.title).ritmFont(12).multilineTextAlignment(.leading)
        Spacer(minLength: 0)
        RitmIcon(.rightIcon).font(.system(size: 13)).foregroundStyle(RitmTheme.muted)
          .accessibilityHidden(true)
      }
      .foregroundStyle(RitmTheme.text)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
  }
}
