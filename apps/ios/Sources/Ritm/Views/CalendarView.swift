import RitmCore
import SwiftUI

private enum NativeCalendarMode: String, CaseIterable { case day, week, month }

private struct CalendarSheet: Identifiable {
  let id = UUID()
  var event: GoogleCalendarEvent?
  var task: RitmTask?
  var draft: CalendarDraft?
}

private struct CalendarDraft {
  let date: String
  let time: String?
  let duration: Int
}

private struct CalendarPick: Identifiable {
  let date: String
  let keys: [String]
  var id: String { date + keys.joined() }
}

/// «Календарь» as the mobile web shows it (src/features/CalendarPage.tsx at 390 px).
struct CalendarView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var date = ""
  @State private var mode: NativeCalendarMode = .week
  @State private var events: [GoogleCalendarEvent] = []
  @State private var status: GoogleCalendarStatus?
  @State private var partial = false
  @State private var loading = false
  @State private var failed = false
  @State private var fetchedAt: String?
  @State private var readID = UUID()
  @State private var sheet: CalendarSheet?
  @State private var pick: CalendarPick?
  @State private var backlogOpen = false
  @State private var nowJump = 0
  @State private var dragging = false

  private var selected: String { date.isEmpty ? store.today : date }
  private var weekDays: [String] { HabitSchedule.week(containing: selected) }
  private var periodDays: [String] { mode == .week ? weekDays : [selected] }
  /// `calendarRange`: the Google read covers the visible period.
  private var range: (from: String, to: String) {
    switch mode {
    case .day: return (selected, HabitSchedule.addDays(to: selected, days: 1) ?? selected)
    case .week:
      let start = weekDays.first ?? selected
      return (start, HabitSchedule.addDays(to: start, days: 7) ?? start)
    case .month:
      let start = CalendarPlan.monthDays(containing: selected).first ?? selected
      return (start, HabitSchedule.addDays(to: start, days: 42) ?? start)
    }
  }
  private var connected: Bool { status?.status == .connected }
  private var needsReauth: Bool { status?.status == .reauthRequired }
  private var uncertain: Bool {
    (loading && fetchedAt == nil) || failed || partial || needsReauth || (connected && fetchedAt == nil)
  }
  private var warning: Bool { failed || partial || needsReauth }
  private var undatedTasks: [RitmTask] {
    (store.bootstrap?.tasks ?? []).filter { $0.date == nil && !$0.completed }
  }

  private func entries(_ day: String) -> [DayOccurrence] {
    DayPlan.occurrences(
      tasks: store.bootstrap?.tasks ?? [], events: events, date: day, timeZone: store.timeZone, language: store.language)
  }

  var body: some View {
    ZStack {
      RitmBackground()
      VStack(spacing: 0) {
        toolbar.padding(.horizontal, 12).ritmPageReveal(index: 0)
        GeometryReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 4) {
              if let message = store.errorMessage {
                RitmErrorBanner(message: message).padding(.bottom, 8)
              }
              MutationRecoveryView()
              panel.frame(height: max(320, proxy.size.height - 8)).ritmPageReveal(index: 1)
              secondary.ritmPageReveal(index: 2)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
          }
          .scrollIndicators(.hidden)
          .scrollDisabled(dragging)
          .refreshable {
            await store.refresh()
            await reload()
          }
        }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task(id: range.from + range.to) { await reload() }
    .onChange(of: navigation.section) { _, section in
      if section == .calendar { Task { await reload() } }
    }
    .onChange(of: store.lastSyncedAt) { _, _ in
      if navigation.section == .calendar { Task { await reload() } }
    }
    .sheet(item: $sheet) { route in
      if let event = route.event {
        CalendarEventDetail(event: event) { await reload() }
      } else if let task = route.task {
        NativeTaskEditor(task: task, initialDate: selected, occurrenceDate: nil) { await reload() }
      } else if let draft = route.draft {
        CalendarEventEditor(
          initialDate: draft.date, initialTime: draft.time, initialDuration: draft.duration
        ) { await reload() }
      }
    }
    .sheet(item: $pick) { value in
      CalendarOverlapPicker(
        date: value.date, entries: entries(value.date).filter { value.keys.contains($0.key) }
      ) { entry in open(entry) }
      .presentationDetents([.medium, .large])
    }
  }

  // MARK: Toolbar

  private var toolbar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(store.text("Календарь", "Calendar"))
          .ritmFont(21, weight: .bold, tracking: -0.045)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
        Button {
          addEntry(selected)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
            Text(store.text("Добавить запись", "Add entry")).lineLimit(1)
          }
          .ritmFont(14, weight: .semibold)
          .foregroundStyle(RitmTheme.ctaInk)
          .padding(.horizontal, 14)
          .frame(minHeight: 44)
          .ritmGlass(in: Capsule(), prominent: true, interactive: true)
          .contentShape(Capsule())
        }
        .buttonStyle(RitmGlassButtonStyle())
      }
      HStack(spacing: 5) {
        iconButton("chevron.left", store.text("Предыдущий период", "Previous period")) { shift(-1) }
        Text(periodLabel)
          .ritmFont(13, weight: .semibold, tracking: -0.025)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity)
          .accessibilityAddTraits(.updatesFrequently)
        iconButton("chevron.right", store.text("Следующий период", "Next period")) { shift(1) }
        Button(store.text("Сегодня", "Today")) { date = store.today }
          .buttonStyle(CalendarSecondaryStyle())
        if mode == .week {
          Button {
            date = store.today
            nowJump += 1
          } label: {
            Image(systemName: "clock").font(.system(size: 17))
          }
          .buttonStyle(CalendarSecondaryStyle(square: true))
          .accessibilityLabel(store.text("Показать текущее время", "Show the current time"))
        }
      }
      HStack(spacing: 8) {
        segment
        if !warning && (status != nil || loading) { compactStatus }
      }
      if warning { warningStatus }
    }
    .padding(.top, 10)
    .padding(.bottom, 10)
  }

  private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(RitmTheme.muted)
        .frame(width: 44, height: 44)
        .ritmGlass(in: Circle(), interactive: true)
        .contentShape(Circle())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(label)
  }

  private var segment: some View {
    RitmSegmentedControl(
      label: store.text("Вид календаря", "Calendar view"), values: NativeCalendarMode.allCases,
      title: modeTitle, selection: $mode, fontSize: 14)
  }

  /// `.cal-sync-footer` without a warning: an icon and the refresh or settings action.
  private var compactStatus: some View {
    HStack(spacing: 5) {
      Group {
        if loading {
          ProgressView().controlSize(.small).tint(RitmTheme.accentColor)
        } else {
          Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(RitmTheme.accentColor)
        }
      }
      .frame(width: 18)
      .accessibilityLabel(statusTitle)
      if connected {
        Button {
          Task { await refreshGoogle() }
        } label: {
          Image(systemName: "arrow.clockwise").font(.system(size: 16))
        }
        .buttonStyle(CalendarSecondaryStyle(square: true))
        .disabled(loading)
        .accessibilityLabel(store.text("Обновить", "Refresh"))
      } else {
        settingsLink
      }
    }
  }

  private var warningStatus: some View {
    HStack(alignment: .top, spacing: 5) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 15))
        .foregroundStyle(RitmTheme.accentColor)
        .padding(.top, 2)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(statusTitle).ritmFont(13, weight: .semibold).foregroundStyle(RitmTheme.text)
        Text(statusMessage).ritmFont(11, lineSpacing: 6).foregroundStyle(RitmTheme.muted)
        if let fetched = fetchedLabel {
          Text(store.text("Последнее обновление: ", "Last updated: ") + fetched)
            .ritmFont(10)
            .foregroundStyle(RitmTheme.muted)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if connected || failed {
        Button {
          Task { await refreshGoogle() }
        } label: {
          Label(store.text("Обновить", "Refresh"), systemImage: "arrow.clockwise")
        }
        .buttonStyle(CalendarSecondaryStyle())
        .disabled(loading)
      } else {
        settingsLink
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .frame(minHeight: 38)
    .background(
      RitmTheme.mix(RitmTheme.soft, 0.6, into: RitmTheme.panel),
      in: RoundedRectangle(cornerRadius: 10, style: .circular)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .circular)
        .strokeBorder(RitmTheme.mix(RitmTheme.accentColor, 0.4, into: RitmTheme.line), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private var settingsLink: some View {
    Button {
      navigation.section = .settings
    } label: {
      HStack(spacing: 4) {
        Text(store.text("Настройки", "Settings"))
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
      }
    }
    .buttonStyle(RitmTextButtonStyle())
  }

  private var statusTitle: String {
    if loading && fetchedAt == nil { return store.text("Загружаем Google Calendar…", "Loading Google Calendar…") }
    if failed { return store.text("Google Calendar требует внимания", "Google Calendar needs attention") }
    if needsReauth { return store.text("Подключи Google Calendar заново", "Reconnect Google Calendar") }
    if partial { return store.text("Загружена часть событий Google", "Some Google events loaded") }
    if connected { return store.text("Календарь синхронизирован", "Calendar synced") }
    return store.text("Google Calendar пока не подключён", "Google Calendar is not connected yet")
  }

  private var statusMessage: String {
    if failed {
      return store.text(
        "Не удалось обновить события. Показанные события могут быть неактуальны.",
        "Could not refresh events. The events shown may be out of date.")
    }
    if partial {
      return store.text(
        "Часть событий не загружена. Свободное время нужно уточнить в Google Calendar.",
        "Some events did not load. Check free time in Google Calendar.")
    }
    return store.text(
      "Разрешение нужно обновить в настройках.", "The permission needs to be renewed in Settings.")
  }

  private var fetchedLabel: String? {
    guard let fetchedAt, let instant = FeatureDate.instant(fetchedAt) else { return nil }
    let key = HabitSchedule.dateKey(instant, timeZone: store.timeZone)
    let time = FeatureDate.time(instant, zone: store.timeZone)
    return FeatureDate.label(key, zone: store.timeZone, language: store.language, template: "d MMM")
      + " · " + FeatureDate.clock(time)
  }

  private func modeTitle(_ value: NativeCalendarMode) -> String {
    switch value {
    case .day: store.text("День", "Day")
    case .week: store.text("Неделя", "Week")
    case .month: store.text("Месяц", "Month")
    }
  }

  private var periodLabel: String {
    let label: String
    switch mode {
    case .month:
      label = FeatureDate.label(selected, zone: store.timeZone, language: store.language, template: "LLLL yyyy")
    case .day:
      label = FeatureDate.label(selected, zone: store.timeZone, language: store.language, template: "EEE d MMMM")
    case .week:
      let first = weekDays.first ?? selected
      let last = weekDays.last ?? selected
      label =
        FeatureDate.label(first, zone: store.timeZone, language: store.language, template: "d MMM")
        + " — "
        + FeatureDate.label(last, zone: store.timeZone, language: store.language, template: "d MMM yyyy")
    }
    return CalendarText.capitalizedWords(label)
  }

  // MARK: Panel

  @ViewBuilder private var panel: some View {
    switch mode {
    case .week:
      CalendarWeekGrid(
        days: weekDays,
        entries: Dictionary(uniqueKeysWithValues: weekDays.map { ($0, entries($0)) }),
        today: store.today, timeZoneLabel: timeZoneLabel, jumpToNow: nowJump,
        dragBlock: dragBlock, onOpen: open,
        onPick: { day, group in pick = CalendarPick(date: day, keys: group.map(\.key)) },
        onAdd: { day, minute in addEntry(day, time: TaskSchedule.minuteTime(minute)) },
        onSelectDay: { day in
          date = day
          mode = .day
        },
        onMove: { entry, day, minute in await move(entry, to: day, minute: minute) },
        onDragActive: { dragging = $0 },
        onSwipe: shift
      )
      .padding(.top, 7)
      .padding(.horizontal, 3)
      .background { RitmPanelBackground(radius: 20) }
      .padding(.horizontal, -4)
    case .day:
      CalendarAgenda(
        date: selected, entries: entries(selected), uncertain: uncertain, googleConnected: connected,
        onOpen: open, onAdd: { day, time, duration in addEntry(day, time: time, duration: duration) }
      )
      .background { RitmPanelBackground() }
    case .month:
      CalendarMonthGrid(selected: selected, today: store.today, entries: entries) { day in
        date = day
        mode = .day
      }
      .background { RitmPanelBackground() }
    }
  }

  /// `.cal-secondary`: «Твой темп · Без даты (N)», collapsed under the calendar.
  private var secondary: some View {
    VStack(alignment: .leading, spacing: 13) {
      Button {
        withAnimation(reduceMotion ? nil : RitmMotion.ease(0.2)) { backlogOpen.toggle() }
      } label: {
        HStack {
          Text(
            store.text("Твой темп", "Your pace") + " · " + store.text("Без даты", "No date")
              + " (\(undatedTasks.count))")
          Spacer()
          Image(systemName: "chevron.down")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RitmTheme.accentColor)
            .rotationEffect(.degrees(backlogOpen ? 180 : 0))
        }
        .ritmFont(12)
        .foregroundStyle(RitmTheme.muted)
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
        .background(RitmTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(backlogOpen ? .isSelected : [])
      if backlogOpen {
        if mode != .week { paceCard }
        backlogCard
      }
    }
  }

  private var paceCard: some View {
    let count =
      mode == .month ? entries(selected).count : periodDays.reduce(0) { $0 + entries($1).count }
    return RitmCard(padding: 20) {
      VStack(alignment: .leading, spacing: 13) {
        HStack {
          Label(store.text("Твой темп", "Your pace"), systemImage: "sparkles")
            .ritmFont(14, weight: .semibold, tracking: -0.02)
            .foregroundStyle(RitmTheme.text)
          Spacer()
          Text(store.text("Выбранный день", "Selected day")).ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
        Group {
          if count > 0 {
            Text(
              (uncertain ? store.text("Показано", "Shown") : store.text("В плане", "Planned"))
                + " \(count) " + CalendarPlan.recordWord(count, language: store.language)
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
          Text("\(undatedTasks.count)").ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
        if undatedTasks.isEmpty {
          Text(
            store.text(
              "Все дела уже нашли своё место в расписании.", "Everything already has its place.")
          )
          .ritmFont(13, lineSpacing: 8)
          .foregroundStyle(RitmTheme.muted)
          .padding(.vertical, 13)
        }
        ForEach(undatedTasks.prefix(4)) { task in
          Button {
            sheet = CalendarSheet(task: task)
          } label: {
            HStack(spacing: 10) {
              Text(task.title).ritmFont(12).multilineTextAlignment(.leading)
              Spacer(minLength: 0)
              Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(RitmTheme.muted)
                .accessibilityHidden(true)
            }
            .foregroundStyle(RitmTheme.text)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(RitmPressStyle(scale: 0.97))
          .overlay(alignment: .bottom) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
        }
        if undatedTasks.count > 4 {
          Text(
            store.text(
              "Ещё \(undatedTasks.count - 4) в разделе «Мой день»",
              "\(undatedTasks.count - 4) more in My day")
          )
          .ritmFont(10)
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 10)
        }
      }
    }
  }

  // MARK: Actions

  /// `addEntry`: a slot gives a time (60 minutes by default), the main button an all-day event.
  private func addEntry(_ day: String, time: String? = nil, duration: Int = 60) {
    guard connected else {
      store.errorMessage = store.text(
        "Подключи Google Calendar в настройках, чтобы добавить запись.",
        "Connect Google Calendar in Settings to add an entry.")
      navigation.section = .settings
      return
    }
    let bounded = time.flatMap(TaskSchedule.timeMinutes).map { min(duration, 1440 - $0) } ?? duration
    sheet = CalendarSheet(draft: CalendarDraft(date: day, time: time, duration: bounded))
  }

  private func open(_ entry: DayOccurrence) {
    if let event = entry.event {
      sheet = CalendarSheet(event: event)
    } else if let task = entry.task?.task {
      sheet = CalendarSheet(task: task)
    }
  }

  /// `canDragEntry`, with the reason: a whole, editable Google event that is not a task, or a
  /// timed one-off Ritm task. Everything else stays put and says why when it is held.
  private func dragBlock(_ entry: DayOccurrence) -> String? {
    if let reason = movePolicy(entry) { return reason }
    guard store.canWrite else {
      return store.text(
        "Сейчас нельзя сохранять изменения. Подожди и попробуй ещё раз.",
        "Changes cannot be saved right now. Wait a moment and try again.")
    }
    return nil
  }

  private func movePolicy(_ entry: DayOccurrence) -> String? {
    guard entry.start != nil, !entry.allDay else { return Self.notMovable(store) }
    if entry.continued {
      return store.text(
        "Продолжение записи с прошлого дня переносится вместе с основной записью.",
        "The part that continues from yesterday moves with the main entry.")
    }
    if let event = entry.event {
      if event.googleTask != nil || event.taskLink == true {
        return store.text(
          "Задачи Google переносятся в Google Tasks. Открой запись, чтобы изменить её.",
          "Google tasks are moved in Google Tasks. Open the entry to change it.")
      }
      if event.readOnly {
        return store.text(
          "Это событие только для просмотра: перенести его нельзя.",
          "This event is view-only and cannot be moved.")
      }
      if !CalendarEventPolicy.canEdit(event, timeZone: store.timeZone) {
        return store.text(
          "Это событие нельзя перенести здесь: оно повторяется, идёт несколько дней или меняет часы. Открой его, чтобы изменить.",
          "This event cannot be moved here: it repeats, spans days or crosses a clock change. Open it to edit.")
      }
      return nil
    }
    if let task = entry.task?.task {
      if task.repeat != .none {
        return store.text(
          "Повторяющуюся задачу нельзя перенести отдельно: изменится вся серия. Открой её, чтобы изменить.",
          "A repeating task cannot be moved on its own: the whole series would change. Open it to edit.")
      }
      if entry.completed {
        return store.text(
          "Выполненную задачу нельзя перенести.", "A completed task cannot be moved.")
      }
      if let start = entry.start, start + task.duration > 1440 {
        return store.text(
          "Задача заканчивается после полуночи: перенести её можно только через редактор.",
          "The task ends after midnight: move it from the editor.")
      }
      return nil
    }
    return Self.notMovable(store)
  }

  private static func notMovable(_ store: RitmStore) -> String {
    store.text("Эту запись нельзя перенести.", "This entry cannot be moved.")
  }

  /// `onGoogleMove`: saved at once with the same duration, no confirmation. A Ritm task keeps its
  /// duration too. An ETag conflict or a failed write is reported by `store.write`, and the
  /// reload below shows the server's version.
  private func move(_ entry: DayOccurrence, to day: String, minute: Int) async {
    guard movePolicy(entry) == nil else {
      store.errorMessage = store.text(
        "Эту запись нельзя перетащить. Открой её для просмотра.",
        "This entry cannot be dragged. Open it to view it.")
      return
    }
    let time = TaskSchedule.minuteTime(minute)
    var saved = false
    if let event = entry.event, var input = CalendarEventPolicy.draft(event, timeZone: store.timeZone) {
      input.date = day
      input.time = time
      saved = await store.write { try await $0.updateGoogleEvent(id: event.id, event: input, etag: event.etag) } != nil
    } else if let task = entry.task?.task {
      let patch = TaskPatch(date: .value(day), time: .value(time))
      saved = await store.write { try await $0.updateTask(id: task.id, patch: patch) } != nil
    }
    if saved {
      store.toasts.show(store.text("Перенесено", "Moved"))
    } else if store.errorMessage == nil {
      store.errorMessage = store.text(
        "Не удалось перенести запись. Попробуй ещё раз.", "Could not move the entry. Try again.")
    }
    await reload()
  }

  private func shift(_ amount: Int) {
    let next =
      mode == .month
      ? TaskSchedule.addMonths(to: selected, months: amount)
      : HabitSchedule.addDays(to: selected, days: amount * (mode == .week ? 7 : 1))
    if let next { date = next }
  }

  private func refreshGoogle() async {
    await store.refresh()
    await reload()
  }

  private var timeZoneLabel: String {
    let seconds = FeatureDate.calendar(store.timeZone).timeZone.secondsFromGMT(
      for: FeatureDate.date(selected, zone: store.timeZone))
    let minutes = abs(seconds / 60)
    return "UTC" + (seconds >= 0 ? "+" : "-") + String(minutes / 60)
      + (minutes % 60 == 0 ? "" : String(format: ":%02d", minutes % 60))
  }

  private func reload() async {
    guard navigation.section == .calendar else { return }
    let ticket = UUID()
    readID = ticket
    loading = true
    defer { if ticket == readID { loading = false } }
    let (from, to) = range
    let currentStatus = await store.read { try await $0.googleStatus() }
    guard ticket == readID, !Task.isCancelled else { return }
    if let currentStatus { status = currentStatus }
    guard currentStatus?.status == .connected else {
      if currentStatus != nil {
        events = []
        partial = false
        failed = false
      } else {
        failed = true
      }
      return
    }
    let zone = store.timeZone
    let result = await store.read { try await $0.googleEvents(from: from, to: to, timeZone: zone) }
    guard ticket == readID, !Task.isCancelled else { return }
    if let result {
      events = result.events
      partial = result.partial
      fetchedAt = result.fetchedAt
      failed = false
    } else {
      failed = true
    }
  }
}

/// The calendar's secondary buttons: Liquid Glass, accent label, 44 pt tall.
private struct CalendarSecondaryStyle: ButtonStyle {
  var square = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmFont(14, weight: .semibold)
      .lineLimit(1)
      .foregroundStyle(RitmTheme.accentColor)
      .padding(.horizontal, square ? 0 : 12)
      .frame(minWidth: 44, minHeight: 44)
      .frame(width: square ? 44 : nil)
      .ritmGlass(in: Capsule(), interactive: true)
      .opacity(isEnabled ? 1 : 0.6)
      .environment(\.ritmGlassPressed, configuration.isPressed)
  }
}
