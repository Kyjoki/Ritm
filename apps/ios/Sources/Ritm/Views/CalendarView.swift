import RitmCore
import SwiftUI

struct CalendarSheet: Identifiable {
  let id = UUID()
  var event: GoogleCalendarEvent?
  var task: RitmTask?
  var draft: CalendarDraft?
  /// The «Без даты» list, opened from the chip above the bottom bar.
  var backlog = false
}

struct CalendarDraft {
  let date: String
  let time: String?
  let duration: Int
}

struct CalendarPick: Identifiable {
  let date: String
  let keys: [String]
  var id: String { date + keys.joined() }
}

/// «Календарь» in the manner of Google Calendar on a phone (prototype A): a slim top bar, the
/// time grid or list below it, a «+» button and the undated-tasks chip above the bottom bar, and
/// a side menu that switches between the schedule, one day, three days, the week and the month.
/// The page opens on the week every time: the view used last is not remembered.
struct CalendarView: View {
  @Environment(RitmStore.self) var store
  @Environment(RitmNavigation.self) var navigation
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @AppStorage("ritm.calendar.hourFormat") private var storedHourFormat = CalendarHourFormat.default.rawValue
  @State var date = ""
  @State var mode = CalendarViewMode.launch
  @State var scheduleDays = CalendarViewMode.scheduleInitialDays
  @State var events: [GoogleCalendarEvent] = []
  @State var status: GoogleCalendarStatus?
  @State var partial = false
  @State var loading = false
  @State var failed = false
  @State var fetchedAt: String?
  @State var readID = UUID()
  @State var sheet: CalendarSheet?
  @State var pick: CalendarPick?
  @State var nowJump = 0
  @State var drawerOpen = false
  @State var miniOpen = false
  @State var searchOpen = false

  var selected: String { date.isEmpty ? store.today : date }
  var gridDays: [String] { mode.visibleDays(anchor: selected) }
  /// `calendarRange`: the Google read covers the visible period and its neighbours.
  var range: (from: String, to: String) { mode.fetchRange(anchor: selected, scheduleDays: scheduleDays) }
  var hourFormat: CalendarHourFormat { CalendarHourFormat(rawValue: storedHourFormat) ?? .default }
  var undatedTasks: [RitmTask] {
    (store.bootstrap?.tasks ?? []).filter { $0.date == nil && !$0.completed }
  }

  func entries(_ day: String) -> [DayOccurrence] {
    DayPlan.occurrences(
      tasks: store.bootstrap?.tasks ?? [], events: events, date: day, timeZone: store.timeZone, language: store.language)
  }

  var body: some View {
    ZStack {
      RitmBackground()
      VStack(spacing: 0) {
        topBar.padding(.horizontal, 4).ritmPageReveal(index: 0)
        notices
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .animation(reduceMotion ? nil : RitmMotion.ease(0.2), value: mode)
          .ritmPageReveal(index: 1)
      }
      CalendarFloatingButtons(
        undatedCount: undatedTasks.count,
        onAdd: { addEntry(mode.focusDay(anchor: selected, today: store.today)) },
        onUndated: { sheet = CalendarSheet(backlog: true) }
      )
      .frame(maxHeight: .infinity, alignment: .bottom)
      .ritmPageReveal(index: 2)
      overlays
    }
    .environment(\.calendarHourFormat, hourFormat)
    .toolbar(.hidden, for: .navigationBar)
    .task(id: range.from + range.to) { await reload() }
    .onChange(of: navigation.section) { _, section in
      if section == .calendar { Task { await reload() } }
    }
    .onChange(of: store.lastSyncedAt) { _, _ in
      if navigation.section == .calendar { Task { await reload() } }
    }
    .onChange(of: mode) { _, _ in scheduleDays = CalendarViewMode.scheduleInitialDays }
    .sheet(item: $sheet) { route in sheetContent(route) }
    .sheet(item: $pick) { value in
      CalendarOverlapPicker(
        date: value.date, entries: entries(value.date).filter { value.keys.contains($0.key) }
      ) { entry in open(entry) }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $searchOpen) {
      CalendarSearchSheet(load: searchDays, onPick: pickSearchHit)
    }
  }

  // MARK: Pieces

  private var topBar: some View {
    CalendarTopBar(
      title: mode.title(anchor: selected, today: store.today, language: store.language).text,
      miniOpen: miniOpen,
      todayNumber: Int(store.today.suffix(2)) ?? 1,
      initial: initial, loading: loading, attention: warning, connected: connected,
      onMenu: { setDrawer(true) },
      onTitle: { setMini(!miniOpen) },
      onSearch: { searchOpen = true },
      onToday: goToday,
      onRefresh: { Task { await refreshGoogle() } },
      onSettings: { navigation.section = .settings })
  }

  private var initial: String {
    let name = (store.bootstrap?.settings.displayName ?? "").trimmingCharacters(in: .whitespaces)
    return name.first.map { String($0).uppercased() } ?? "Р"
  }

  @ViewBuilder private var notices: some View {
    if let message = store.errorMessage {
      RitmErrorBanner(message: message).padding(.horizontal, 12).padding(.bottom, 8)
    }
    MutationRecoveryView().padding(.horizontal, 12)
    if warning { warningStatus.padding(.horizontal, 12).padding(.bottom, 6) }
  }

  @ViewBuilder private var content: some View {
    switch mode {
    case .day, .threeDays, .week: grid
    case .month:
      CalendarMonthView(
        selected: selected, today: store.today, entries: entries(_:),
        onSelect: { day in
          date = day
          mode = .day
        },
        onStep: step)
    case .schedule:
      CalendarSchedule(
        days: (0..<scheduleDays).compactMap { HabitSchedule.addDays(to: selected, days: $0) },
        selected: selected, today: store.today, entries: entries(_:), uncertain: uncertain,
        googleConnected: connected, onOpen: open,
        onAddFree: { day, time, duration in addEntry(day, time: time, duration: duration) },
        onMore: { scheduleDays += CalendarViewMode.scheduleStepDays },
        onRefresh: refreshGoogle)
    }
  }

  private var grid: some View {
    let days = gridDays
    return CalendarWeekGrid(
      days: days,
      entries: Dictionary(uniqueKeysWithValues: days.map { ($0, entries($0)) }),
      today: store.today, timeZoneLabel: timeZoneLabel, jumpToNow: nowJump,
      dragBlock: dragBlock, onOpen: open,
      onPick: { day, group in pick = CalendarPick(date: day, keys: group.map(\.key)) },
      onAdd: { day, minute in addEntry(day, time: TaskSchedule.minuteTime(minute)) },
      onSelectDay: { day in
        date = day
        mode = .day
      },
      onMove: { entry, day, minute in await move(entry, to: day, minute: minute) },
      onStep: step)
  }

  // MARK: Overlays: mini-month and side menu

  @ViewBuilder private var overlays: some View {
    if miniOpen {
      ZStack(alignment: .topLeading) {
        Color.clear.contentShape(Rectangle()).onTapGesture { setMini(false) }
        CalendarMiniMonth(selected: selected, today: store.today, onPick: pickDay)
          .padding(.top, CalendarTopBar.height + 2)
          .padding(.horizontal, 12)
          .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
      }
    }
    if drawerOpen {
      CalendarDrawer(
        mode: mode, hourFormat: hourFormatBinding, undatedCount: undatedTasks.count,
        statusTitle: statusTitle, connected: connected, loading: loading,
        onSelect: choose,
        onUndated: {
          setDrawer(false)
          sheet = CalendarSheet(backlog: true)
        },
        onRefresh: { Task { await refreshGoogle() } },
        onSettings: { navigation.section = .settings },
        onClose: { setDrawer(false) })
    }
  }

  private var hourFormatBinding: Binding<CalendarHourFormat> {
    Binding(get: { hourFormat }, set: { storedHourFormat = $0.rawValue })
  }

  private func setDrawer(_ open: Bool) {
    if open { miniOpen = false }
    withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.ease(0.34)) { drawerOpen = open }
  }

  private func setMini(_ open: Bool) {
    withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.inflate()) { miniOpen = open }
  }

  /// A day chosen in the mini-month: the month view opens that day, the others jump to it.
  private func pickDay(_ day: String) {
    date = day
    if mode == .month { mode = .day }
    setMini(false)
  }

  private func pickSearchHit(_ hit: CalendarSearchHit) {
    searchOpen = false
    date = hit.date
    if mode == .month { mode = .day }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(450))
      open(hit.entry)
    }
  }

  // MARK: Sheets

  @ViewBuilder private func sheetContent(_ route: CalendarSheet) -> some View {
    if let event = route.event {
      CalendarEventDetail(event: event) { await reload() }
    } else if let task = route.task {
      NativeTaskEditor(task: task, initialDate: selected, occurrenceDate: nil) { await reload() }
    } else if let draft = route.draft {
      CalendarEventEditor(
        initialDate: draft.date, initialTime: draft.time, initialDuration: draft.duration
      ) { await reload() }
    } else {
      CalendarBacklogSheet(
        tasks: undatedTasks, plannedCount: plannedCount, uncertain: uncertain
      ) { task in sheet = CalendarSheet(task: task) }
      .presentationDetents([.medium, .large])
    }
  }

  /// How many entries the pace note counts: the visible days, or the chosen day in the month and
  /// the schedule.
  private var plannedCount: Int {
    switch mode {
    case .month, .schedule: entries(selected).count
    case .day, .threeDays, .week: gridDays.reduce(0) { $0 + entries($1).count }
    }
  }
}
