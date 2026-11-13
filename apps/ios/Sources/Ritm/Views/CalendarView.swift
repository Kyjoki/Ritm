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
///
/// This body runs for every small change (a spinner, a sheet, a swipe), so it does no real work:
/// the days are read once per change of data by `CalendarDayModel`, the grid, the month and their
/// cells are equatable and skip unchanged redraws, and the two overlays keep their state in
/// `CalendarChrome`, which this body never reads.
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
  /// The days the last Google read covered: changing the view inside them reads nothing again.
  @State var fetchedRange: (from: String, to: String)?
  @State var readID = UUID()
  @State var sheet: CalendarSheet?
  @State var pick: CalendarPick?
  @State var nowJump = 0
  @State var searchOpen = false
  @State var filter = CalendarFilter()
  @State var dayModel = CalendarDayModel()
  /// Where the hour grid's pages are while a finger drags or a slide runs. This body never reads it.
  @State var pager = CalendarPagerPosition()
  @State var chrome = CalendarChrome()

  var selected: String { date.isEmpty ? store.today : date }
  var gridDays: [String] { mode.visibleDays(anchor: selected) }
  /// `calendarRange`: the least the page needs, the visible period and its neighbours.
  var range: (from: String, to: String) { mode.fetchRange(anchor: selected, scheduleDays: scheduleDays) }
  /// What one Google read loads: in the hour grid several periods each way, so a swipe seldom
  /// needs a read at all.
  var readRange: (from: String, to: String) { mode.loadRange(anchor: selected, scheduleDays: scheduleDays) }
  var hourFormat: CalendarHourFormat { CalendarHourFormat(rawValue: storedHourFormat) ?? .default }
  var email: String { store.bootstrap?.settings.email ?? "" }
  var undatedTasks: [RitmTask] {
    (store.bootstrap?.tasks ?? []).filter { $0.date == nil && !$0.completed }
  }

  func entries(_ day: String) -> [DayOccurrence] { dayModel.entries(day) }

  /// The menu's calendars: the Google ones seen so far and the kinds of Ritm entry.
  func sources() -> [CalendarSource] {
    CalendarSources.list(
      events: events, tasks: store.bootstrap?.tasks ?? [], filter: filter, email: email,
      language: store.language)
  }

  var body: some View {
    let generation = dayModel.sync(
      tasks: store.bootstrap?.tasks ?? [], events: events, zone: store.timeZone,
      language: store.language, hidden: filter.hidden)
    ZStack {
      RitmBackground()
      VStack(spacing: 0) {
        topBar.padding(.horizontal, 4).ritmPageReveal(index: 0)
        notices
        content(generation)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .overlay(alignment: .top) { hiddenNote }
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
    .task(id: email) { filter = CalendarFilterStore.load(email: email) }
    .task(id: range.from + range.to) { await reloadIfNeeded() }
    .onChange(of: navigation.section) { _, section in
      if section == .calendar { Task { await reload() } }
    }
    .onChange(of: store.lastSyncedAt) { _, _ in
      if navigation.section == .calendar { Task { await reload() } }
    }
    .onChange(of: mode) { _, _ in
      if scheduleDays != CalendarViewMode.scheduleInitialDays {
        scheduleDays = CalendarViewMode.scheduleInitialDays
      }
    }
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
      chrome: chrome,
      todayNumber: Int(store.today.suffix(2)) ?? 1,
      initial: initial, loading: loading, attention: warning, connected: connected,
      onMenu: { setDrawer(true) },
      onTitle: { setMini(!chrome.miniOpen) },
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

  /// One line when every calendar is hidden, with the way back.
  @ViewBuilder private var hiddenNote: some View {
    if !filter.hidden.isEmpty && CalendarSources.allHidden(sources(), hidden: filter.hidden) {
      HStack(spacing: 8) {
        Text(store.text("Все календари скрыты", "All calendars are hidden"))
          .ritmFont(13).foregroundStyle(RitmTheme.muted)
        Button(store.text("Показать все", "Show all")) { showAllSources() }
          .ritmFont(13, weight: .semibold)
          .foregroundStyle(RitmTheme.accentColor)
          .frame(minHeight: 44)
      }
      .padding(.horizontal, 16)
      .background(RitmTheme.panel, in: Capsule())
      .overlay { Capsule().strokeBorder(RitmTheme.line, lineWidth: 1) }
      .padding(.top, 70)
    }
  }

  @ViewBuilder private func content(_ generation: Int) -> some View {
    switch mode {
    case .day, .threeDays, .week: grid(generation)
    case .month:
      CalendarMonthView(
        dayModel: dayModel, generation: generation, selected: selected, today: store.today,
        onSelect: { day in
          date = day
          mode = .day
        },
        onStep: step
      )
      .equatable()
    case .schedule: schedule
    }
  }

  private func grid(_ generation: Int) -> some View {
    CalendarWeekGrid(
      days: gridDays, mode: mode, dayModel: dayModel, generation: generation, today: store.today,
      timeZoneLabel: timeZoneLabel, jumpToNow: nowJump, pager: pager,
      dragBlock: dragBlock, onOpen: open,
      onPick: { day, group in pick = CalendarPick(date: day, keys: group.map(\.key)) },
      onAdd: { day, minute in addEntry(day, time: TaskSchedule.minuteTime(minute)) },
      onSelectDay: { day in
        date = day
        mode = .day
      },
      onMove: { entry, day, minute in await move(entry, to: day, minute: minute) },
      onStep: step
    )
    .equatable()
  }

  private var schedule: some View {
    let days = (0..<scheduleDays).compactMap { HabitSchedule.addDays(to: selected, days: $0) }
    dayModel.prepare(days)
    return CalendarSchedule(
      days: days, selected: selected, today: store.today, entries: entries(_:), uncertain: uncertain,
      googleConnected: connected, onOpen: open,
      onAddFree: { day, time, duration in addEntry(day, time: time, duration: duration) },
      onMore: { scheduleDays += CalendarViewMode.scheduleStepDays },
      onRefresh: refreshGoogle)
  }

  // MARK: Overlays: mini-month and side menu

  private var overlays: some View {
    CalendarOverlays(
      chrome: chrome, selected: selected, today: store.today, onPickDay: pickDay,
      onCloseMini: { setMini(false) }, onCloseDrawer: { setDrawer(false) },
      closeLabel: store.text("Закрыть меню", "Close the menu"),
      makeDrawer: drawer)
  }

  private func drawer(top: CGFloat, bottom: CGFloat) -> CalendarDrawer {
    CalendarDrawer(
      mode: mode, hourFormat: hourFormatBinding, sources: sources(), hidden: filter.hidden,
      undatedCount: undatedTasks.count, timeZoneLabel: timeZoneLabel, googleState: googleState,
      topPadding: top, bottomPadding: bottom,
      onSelect: choose, onToggle: toggleSource,
      onUndated: {
        setDrawer(false)
        sheet = CalendarSheet(backlog: true)
      },
      onTimeZone: {
        setDrawer(false)
        navigation.section = .settings
      },
      onGoogle: {
        if connected {
          Task { await refreshGoogle() }
        } else {
          setDrawer(false)
          navigation.section = .settings
        }
      })
  }

  private var hourFormatBinding: Binding<CalendarHourFormat> {
    Binding(get: { hourFormat }, set: { storedHourFormat = $0.rawValue })
  }

  func setDrawer(_ open: Bool) {
    if open { chrome.miniOpen = false }
    withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(open ? 0.34 : 0.26)) {
      chrome.drawerOpen = open
    }
  }

  private func setMini(_ open: Bool) {
    withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.inflate()) { chrome.miniOpen = open }
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

  func toggleSource(_ id: String) {
    filter.toggle(id)
    CalendarFilterStore.save(filter, email: email)
  }

  func showAllSources() {
    filter.hidden = []
    CalendarFilterStore.save(filter, email: email)
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
