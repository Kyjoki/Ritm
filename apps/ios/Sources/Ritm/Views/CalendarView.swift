import RitmCore
import SwiftUI

private enum NativeCalendarMode: String, CaseIterable { case day, week, month }
private struct CalendarItem: Identifiable {
  let id: String
  let title: String
  let date: String
  let start: Int?
  let end: Int?
  let task: RitmTask?
  let event: GoogleCalendarEvent?
  let completed: Bool
  var clockChange = false
  var intervalLabel: String? = nil
  var color: Color { CalendarPalette.color(task?.colorId ?? event?.colorId) }
}
private struct CalendarSheet: Identifiable {
  let id = UUID()
  let item: CalendarItem?
  let newEvent: Bool
}
private struct CalendarMove: Identifiable {
  let id = UUID()
  let item: CalendarItem
  let date: String
  let minute: Int
  var duration: Int? = nil
}

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
  @State private var readID = UUID()
  @State private var sheet: CalendarSheet?
  @State private var moving: CalendarMove?
  @State private var chooseDate = false
  @State private var didAutoScroll = false
  @State private var clockJump = 0

  private var selected: String { date.isEmpty ? store.today : date }
  private var days: [String] {
    switch mode {
    case .day: return [selected]
    case .week: return HabitSchedule.week(containing: selected)
    case .month:
      let dates = TaskSchedule.monthDates(containing: selected)
      guard let first = dates.first, let last = dates.last,
        let start = HabitSchedule.week(containing: first).first,
        let end = HabitSchedule.week(containing: last).last
      else { return dates }
      var values = [start]
      while let next = HabitSchedule.addDays(to: values.last!, days: 1), next <= end {
        values.append(next)
      }
      return values
    }
  }
  private var rangeKey: String { (days.first ?? selected) + "/" + (days.last ?? selected) }
  private var calendarTasks: [RitmTask] {
    (store.bootstrap?.tasks ?? []).filter { $0.calendarEntry != false }
  }
  private var quickTasks: [RitmTask] {
    (store.bootstrap?.tasks ?? []).filter {
      $0.calendarEntry == false && ($0.date == nil || TaskSchedule.occursOn($0, date: selected))
    }
  }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollViewReader { proxy in
        VStack(spacing: 0) {
          header.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              if let message = store.errorMessage { RitmErrorBanner(message: message) }
              MutationRecoveryView()
              if let status, status.status != .connected {
                RitmCard {
                  VStack(alignment: .leading, spacing: 10) {
                    Text(
                      store.text("Google Calendar не подключён", "Google Calendar is not connected")
                    )
                    .font(.headline)
                    Button(store.text("Открыть настройки", "Open settings")) {
                      navigation.section = .settings
                    }.frame(minHeight: 44)
                  }
                }
              }
              if partial {
                Label(
                  store.text(
                    "Показаны не все события. Обновите календарь.",
                    "Some events are unavailable. Refresh the calendar."),
                  systemImage: "exclamationmark.triangle"
                ).font(.caption).foregroundStyle(.secondary)
              }
              if loading {
                ProgressView().frame(maxWidth: .infinity).accessibilityLabel(
                  store.text("Обновление календаря", "Refreshing calendar"))
              }
              if mode == .month {
                monthGrid
                agenda(selected)
              } else {
                timeline
              }
              quickTasksCard
              Text(
                store.text(
                  "Перетащите редактируемую запись на время и подтвердите перенос. Защищённые и повторяющиеся события Google доступны для просмотра.",
                  "Drag an editable entry onto a time and confirm the move. Protected and recurring Google entries remain read-only."
                )
              )
              .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
          }.refreshable {
            await store.refresh()
            await reload()
          }
        }
        .task {
          // Run only once when the retained calendar screen is first laid out.
          // Background refreshes must not reset the owner's scroll position.
          await Task.yield()
          guard !didAutoScroll, navigation.section == .calendar, mode != .month else { return }
          didAutoScroll = true
          scrollToCurrentHour(proxy, animated: false)
        }
        .onChange(of: clockJump) { _, _ in
          Task {
            await Task.yield()
            scrollToCurrentHour(proxy, animated: true)
          }
        }
        .onChange(of: mode) { previous, next in
          if previous == .month && next != .month {
            Task {
              await Task.yield()
              scrollToCurrentHour(proxy, animated: false)
            }
          }
        }
      }
    }
    .navigationTitle(store.text("Календарь", "Calendar"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          date = store.today
          if mode == .month { mode = .day }
          clockJump += 1
        } label: {
          Image(systemName: "clock").frame(width: 44, height: 44)
        }
        .accessibilityLabel(store.text("Перейти к текущему часу", "Jump to the current hour"))
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button(
            store.text("Событие Google Calendar", "Google Calendar event"),
            systemImage: "calendar.badge.plus"
          ) { sheet = CalendarSheet(item: nil, newEvent: true) }.disabled(
            status?.status != .connected)
          Button(store.text("Задача Ritm", "Ritm task"), systemImage: "checkmark.circle") {
            sheet = CalendarSheet(item: nil, newEvent: false)
          }
        } label: {
          Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(store.text("Добавить запись", "Add entry")).disabled(!store.canWrite)
      }
    }
    .task(id: rangeKey) { await reload() }
    .onChange(of: navigation.section) { _, section in
      if section == .calendar { Task { await reload() } }
    }
    .onChange(of: store.lastSyncedAt) { _, _ in
      if navigation.section == .calendar { Task { await reload() } }
    }
    .sheet(item: $sheet) { route in
      if let event = route.item?.event {
        CalendarEventDetail(event: event) { await reload() }
      } else if route.newEvent {
        CalendarEventEditor(initialDate: selected) { await reload() }
      } else {
        NativeTaskEditor(
          task: route.item?.task, initialDate: selected, occurrenceDate: route.item?.date
        ) { await reload() }
      }
    }
    .sheet(isPresented: $chooseDate) {
      NavigationStack {
        DatePicker(
          store.text("Дата", "Date"),
          selection: Binding(
            get: { FeatureDate.date(selected, zone: store.timeZone) },
            set: { date = HabitSchedule.dateKey($0, timeZone: store.timeZone) }),
          displayedComponents: .date
        )
        .datePickerStyle(.graphical).padding().environment(
          \.timeZone, TimeZone(identifier: store.timeZone) ?? .current
        )
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(store.text("Готово", "Done")) { chooseDate = false }
          }
        }
      }.presentationDetents([.medium, .large])
    }
    .confirmationDialog(
      store.text(
        moving?.duration == nil ? "Перенести запись?" : "Изменить длительность?",
        moving?.duration == nil ? "Move this entry?" : "Change duration?"),
      isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }),
      titleVisibility: .visible
    ) {
      if let move = moving {
        Button(store.text("Подтвердить", "Confirm")) { Task { await commitMove(move) } }
        Button(store.text("Отмена", "Cancel"), role: .cancel) {}
      }
    } message: {
      if let move = moving {
        Text(
          move.item.title + "\n"
            + FeatureDate.label(move.date, zone: store.timeZone, language: store.language) + ", "
            + FeatureDate.clock(TaskSchedule.minuteTime(move.minute))
            + (move.duration.map { " · \($0) " + store.text("мин", "min") } ?? ""))
      }
    }
  }

  private var header: some View {
    VStack(spacing: 12) {
      HStack {
        Button {
          shift(-1)
        } label: {
          Image(systemName: "chevron.left").frame(width: 44, height: 44)
        }.accessibilityLabel(store.text("Назад", "Previous"))
        Button {
          chooseDate = true
        } label: {
          Text(
            FeatureDate.label(
              selected, zone: store.timeZone, language: store.language,
              template: mode == .month ? "LLLL yyyy" : "d MMM yyyy")
          )
          .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }
        Button {
          shift(1)
        } label: {
          Image(systemName: "chevron.right").frame(width: 44, height: 44)
        }.accessibilityLabel(store.text("Вперёд", "Next"))
        Button(store.text("Сегодня", "Today")) { date = store.today }.frame(minHeight: 44)
      }
      Picker(store.text("Вид календаря", "Calendar view"), selection: $mode) {
        Text(store.text("День", "Day")).tag(NativeCalendarMode.day)
        Text(store.text("Неделя", "Week")).tag(NativeCalendarMode.week)
        Text(store.text("Месяц", "Month")).tag(NativeCalendarMode.month)
      }.pickerStyle(.segmented)
    }.buttonStyle(RitmPressStyle())
  }

  private var monthGrid: some View {
    RitmCard {
      VStack(spacing: 8) {
        HStack {
          ForEach(
            store.language == .ru
              ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
              : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self
          ) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        }
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4
        ) {
          ForEach(days, id: \.self) { key in
            Button {
              date = key
            } label: {
              VStack(spacing: 5) {
                Text(String(Int(key.suffix(2)) ?? 0)).font(
                  .subheadline.weight(key == selected ? .bold : .regular))
                HStack(spacing: 2) {
                  ForEach(Array(items(key).prefix(3))) { item in
                    Circle().fill(item.color).frame(width: 4, height: 4)
                  }
                }.frame(height: 5)
              }.frame(maxWidth: .infinity, minHeight: 48)
                .background(
                  key == selected ? RitmTheme.lavender.opacity(0.24) : .clear,
                  in: RoundedRectangle(cornerRadius: 13)
                )
                .overlay {
                  if key == store.today {
                    RoundedRectangle(cornerRadius: 13).stroke(RitmTheme.lavender, lineWidth: 1)
                  }
                }
                .opacity(key.prefix(7) == selected.prefix(7) ? 1 : 0.45)
            }.buttonStyle(RitmPressStyle())
              .accessibilityLabel(
                FeatureDate.label(key, zone: store.timeZone, language: store.language)
                  + ", \(items(key).count) " + store.text("записей", "entries")
              )
              .accessibilityAddTraits(key == selected ? .isSelected : [])
          }
        }
      }
    }
  }

  private var timeline: some View {
    GeometryReader { geometry in
      HStack(alignment: .top, spacing: 1) {
        VStack(spacing: 0) {
          Text(timeZoneLabel).font(.caption2).frame(width: 48, height: 90)
          ForEach(0..<24, id: \.self) { hour in
            Text(FeatureDate.clock(TaskSchedule.minuteTime(hour * 60))).font(.caption2)
              .foregroundStyle(.secondary).frame(width: 48, height: 64, alignment: .topTrailing)
              .id("calendar-hour-\(hour)")
          }
        }
        ScrollViewReader { horizontal in
          ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 1) {
              ForEach(days, id: \.self) { key in
                timelineColumn(key, width: mode == .day ? max(200, geometry.size.width - 52) : 156)
                  .id("calendar-day-\(key)")
              }
            }
          }.scrollIndicators(.visible)
            .task(id: selected) {
              await Task.yield()
              guard navigation.section == .calendar else { return }
              horizontal.scrollTo("calendar-day-\(selected)", anchor: .leading)
            }
        }
      }
    }.frame(height: 90 + 24 * 64)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
      .overlay {
        RoundedRectangle(cornerRadius: 24).strokeBorder(
          RitmTheme.lavender.opacity(0.16), lineWidth: 1)
      }
  }
  private func timelineColumn(_ key: String, width: CGFloat) -> some View {
    let all = items(key)
    let timed = all.filter { $0.start != nil }
    return VStack(spacing: 0) {
      VStack(spacing: 4) {
        Button {
          date = key
          mode = .day
        } label: {
          Text(
            FeatureDate.label(
              key, zone: store.timeZone, language: store.language, template: "EEE d")
          )
          .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
        }
        Menu {
          ForEach(all.filter { $0.start == nil }) { item in Button(item.title) { open(item) } }
        } label: {
          Text(store.text("Без времени: ", "Untimed: ") + "\(all.filter { $0.start == nil }.count)")
            .font(.caption).frame(height: 36)
        }
      }.frame(height: 90)
      ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
          ForEach(0..<24, id: \.self) { hour in
            Rectangle().fill(.clear).frame(height: 64)
              .overlay(alignment: .top) {
                Rectangle().fill(.secondary.opacity(0.15)).frame(height: 0.5)
              }
              .contentShape(Rectangle())
              .dropDestination(for: String.self) { identifiers, location in
                guard let identifier = identifiers.first,
                  let item = days.flatMap({ items($0) }).first(where: { $0.id == identifier }),
                  canMove(item)
                else { return false }
                let quarter = min(3, max(0, Int((location.y / 64 * 4).rounded(.down))))
                moving = CalendarMove(item: item, date: key, minute: hour * 60 + quarter * 15)
                return true
              }
          }
        }
        ForEach(timed) { item in
          let lane = laneFor(item, among: timed)
          let lanes = laneCount(item, among: timed)
          let itemWidth = max(36, (width - 6) / CGFloat(lanes))
          let height = max(30, CGFloat((item.end ?? 0) - (item.start ?? 0)) / 60 * 64 - 2)
          draggableItem(item)
            .frame(width: itemWidth - 2, height: height, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
              if canMove(item), itemWidth >= 74, height >= 50 {
                CalendarResizeGrip(
                  duration: item.task?.duration ?? item.event.flatMap {
                    CalendarEventPolicy.draft($0, timeZone: store.timeZone)?.duration
                  } ?? 60, start: item.start ?? 0
                ) { duration in
                  moving = CalendarMove(
                    item: item, date: item.date, minute: item.start ?? 0, duration: duration)
                }
              }
            }
            .offset(x: 3 + CGFloat(lane) * itemWidth, y: CGFloat(item.start ?? 0) / 60 * 64)
        }
      }.frame(width: width, height: 24 * 64)
    }.frame(width: width)
      .background(key == store.today ? RitmTheme.lavender.opacity(0.07) : .clear)
  }
  private func eventButton(_ item: CalendarItem) -> some View {
    Button {
      open(item)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title).font(.caption.weight(.semibold)).strikethrough(item.completed)
        Text(
          item.intervalLabel ?? item.start.map { FeatureDate.clock(TaskSchedule.minuteTime($0)) }
            ?? store.text("Весь день", "All day")
        ).font(.caption2)
        if item.clockChange {
          Label(store.text("Перевод часов", "Clock change"), systemImage: "clock.arrow.circlepath")
            .font(.caption2)
        }
      }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(item.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
          RoundedRectangle(cornerRadius: 9).strokeBorder(item.color.opacity(0.6), lineWidth: 1)
        }
        .clipped()
    }.buttonStyle(.plain).accessibilityLabel(
      item.title + ", "
        + (item.intervalLabel ?? item.start.map { FeatureDate.clock(TaskSchedule.minuteTime($0)) }
          ?? store.text("Без времени", "Untimed"))
        + (item.clockChange ? store.text(", перевод часов", ", clock change") : ""))
  }
  @ViewBuilder private func draggableItem(_ item: CalendarItem) -> some View {
    if canMove(item) { eventButton(item).draggable(item.id) } else { eventButton(item) }
  }
  // Interval graph coloring: overlapping events occupy separate equal lanes.
  private func assignments(_ values: [CalendarItem]) -> [String: Int] {
    var ends: [Int] = []
    var result: [String: Int] = [:]
    for item in values.sorted(by: { ($0.start ?? 0, $0.id) < ($1.start ?? 0, $1.id) }) {
      let lane = ends.firstIndex { $0 <= (item.start ?? 0) } ?? ends.count
      if lane == ends.count { ends.append(item.end ?? 0) } else { ends[lane] = item.end ?? 0 }
      result[item.id] = lane
    }
    return result
  }
  private func laneFor(_ item: CalendarItem, among values: [CalendarItem]) -> Int {
    assignments(values)[item.id] ?? 0
  }
  private func laneCount(_ item: CalendarItem, among values: [CalendarItem]) -> Int {
    let lanes = assignments(values)
    var lower = item.start ?? 0
    var upper = item.end ?? 0
    var changed = true
    while changed {
      changed = false
      for value in values where (value.start ?? 0) < upper && (value.end ?? 0) > lower {
        let nextLower = min(lower, value.start ?? 0)
        let nextUpper = max(upper, value.end ?? 0)
        if nextLower != lower || nextUpper != upper {
          changed = true
          lower = nextLower
          upper = nextUpper
        }
      }
    }
    let cluster = values.filter { ($0.start ?? 0) < upper && ($0.end ?? 0) > lower }
    return (cluster.compactMap { lanes[$0.id] }.max() ?? 0) + 1
  }
  private func agenda(_ key: String) -> some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(FeatureDate.label(key, zone: store.timeZone, language: store.language)).font(.headline)
        if items(key).isEmpty {
          Text(store.text("Нет записей на эту дату", "No entries on this date")).foregroundStyle(
            .secondary)
        }
        ForEach(items(key)) { item in
          Button {
            open(item)
          } label: {
            HStack(alignment: .top) {
              Circle().fill(item.color).frame(width: 8, height: 8).padding(.top, 5)
              VStack(alignment: .leading, spacing: 5) {
                Text(item.title).strikethrough(item.completed)
                Text(
                  item.intervalLabel ?? item.start.map {
                    FeatureDate.clock(TaskSchedule.minuteTime($0))
                  } ?? store.text("Без времени", "Untimed")
                ).font(.caption).foregroundStyle(.secondary)
                if item.clockChange {
                  Label(
                    store.text("Перевод часов", "Clock change"),
                    systemImage: "clock.arrow.circlepath"
                  ).font(.caption)
                }
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption)
            }.frame(minHeight: 44)
          }.buttonStyle(.plain)
        }
      }
    }
  }
  private var quickTasksCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(store.text("Задачи Ritm", "Ritm tasks")).font(.headline)
        if quickTasks.isEmpty {
          Text(store.text("Задач на выбранный день нет.", "No tasks for this day."))
            .foregroundStyle(.secondary)
        }
        ForEach(quickTasks) { task in
          HStack {
            Button {
              Task {
                _ = await store.write {
                  try await $0.setTaskCompleted(
                    id: task.id, completed: !task.isComplete(on: selected),
                    occurrenceDate: task.repeat == .none ? nil : selected)
                }
              }
            } label: {
              Image(systemName: task.isComplete(on: selected) ? "checkmark.circle.fill" : "circle")
                .frame(width: 44, height: 44)
            }.disabled(!store.canWrite)
            Button {
              sheet = CalendarSheet(
                item: CalendarItem(
                  id: task.id, title: task.title, date: selected, start: nil, end: nil, task: task,
                  event: nil, completed: task.isComplete(on: selected)), newEvent: false)
            } label: {
              VStack(alignment: .leading) {
                Text(task.title).strikethrough(task.isComplete(on: selected))
                if task.date == nil {
                  Text(store.text("Без даты", "No date")).font(.caption).foregroundStyle(.secondary)
                }
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
          }
        }
      }
    }
  }
  private func items(_ key: String) -> [CalendarItem] {
    var result = TaskSchedule.dayOccurrences(calendarTasks, date: key, language: store.language).map
    { occurrence in
      CalendarItem(
        id: "task:" + occurrence.key, title: occurrence.task.title, date: occurrence.date,
        start: occurrence.start, end: occurrence.end, task: occurrence.task, event: nil,
        completed: occurrence.completed)
    }
    let calendar = FeatureDate.calendar(store.timeZone)
    let dayStart = calendar.startOfDay(for: FeatureDate.date(key, zone: store.timeZone))
    guard let nextStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
      return result
    }
    for event in events {
      if event.allDay {
        guard let first = event.start.date, let end = event.end.date, key >= first, key < end else {
          continue
        }
        result.append(
          CalendarItem(
            id: "google:\(event.id):\(key)", title: event.title, date: key, start: nil, end: nil,
            task: nil, event: event, completed: event.googleTask?.status == "completed"))
      } else if let start = FeatureDate.instant(event.start.dateTime),
        let end = FeatureDate.instant(event.end.dateTime), start < nextStart, end > dayStart
      {
        let begin =
          start <= dayStart
          ? 0 : TaskSchedule.timeMinutes(FeatureDate.time(start, zone: store.timeZone)) ?? 0
        let finish =
          end >= nextStart
          ? 1440
          : (TaskSchedule.timeMinutes(FeatureDate.time(end, zone: store.timeZone)) ?? 1440)
            + (calendar.component(.second, from: end) > 0 ? 1 : 0)
        let actualDuration = Int(ceil(end.timeIntervalSince(start) / 60))
        let drawnEnd = min(1440, max(begin + 1, finish > begin ? finish : begin + actualDuration))
        result.append(
          CalendarItem(
            id: "google:\(event.id):\(key)", title: event.title, date: key, start: begin,
            end: drawnEnd, task: nil, event: event,
            completed: event.googleTask?.status == "completed",
            clockChange: CalendarEventPolicy.hasClockChange(event, timeZone: store.timeZone),
            intervalLabel: store.eventTimeText(event)))
      }
    }
    return result.sorted { ($0.start ?? -1, $0.title) < ($1.start ?? -1, $1.title) }
  }
  private func open(_ item: CalendarItem) { sheet = CalendarSheet(item: item, newEvent: false) }
  private func scrollToCurrentHour(_ proxy: ScrollViewProxy, animated: Bool) {
    guard navigation.section == .calendar, mode != .month else { return }
    let hour = FeatureDate.calendar(store.timeZone).component(.hour, from: Date())
    withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.25) : nil) {
      proxy.scrollTo("calendar-hour-\(hour)", anchor: .top)
    }
  }
  private var timeZoneLabel: String {
    let seconds = FeatureDate.calendar(store.timeZone).timeZone.secondsFromGMT(
      for: FeatureDate.date(selected, zone: store.timeZone))
    let minutes = abs(seconds / 60)
    return "UTC" + (seconds >= 0 ? "+" : "−") + String(minutes / 60)
      + (minutes % 60 == 0 ? "" : String(format: ":%02d", minutes % 60))
  }
  private func canMove(_ item: CalendarItem) -> Bool {
    guard store.canWrite else { return false }
    if let event = item.event {
      return CalendarEventPolicy.canEdit(event, timeZone: store.timeZone) && !event.allDay
    }
    return item.task?.repeat == TaskRepeat.none && item.start != nil
  }
  private func commitMove(_ move: CalendarMove) async {
    let duration =
      move.duration ?? move.item.task?.duration ?? move.item.event.flatMap {
        CalendarEventPolicy.draft($0, timeZone: store.timeZone)?.duration
      } ?? 60
    guard move.minute + duration <= 1440 else {
      store.errorMessage = store.text(
        "Запись должна завершиться до полуночи.", "The entry must end by midnight.")
      moving = nil
      return
    }
    if let event = move.item.event,
      var input = CalendarEventPolicy.draft(event, timeZone: store.timeZone)
    {
      input.date = move.date
      input.time = TaskSchedule.minuteTime(move.minute)
      input.duration = duration
      if await store.write({
        try await $0.updateGoogleEvent(id: event.id, event: input, etag: event.etag)
      }) != nil {
        await reload()
      }
    } else if let task = move.item.task, task.repeat == .none {
      let patch = TaskPatch(
        date: .value(move.date), time: .value(TaskSchedule.minuteTime(move.minute)),
        duration: move.duration)
      if await store.write({ try await $0.updateTask(id: task.id, patch: patch) }) != nil {
        await reload()
      }
    }
    moving = nil
  }
  private func shift(_ amount: Int) {
    let next =
      mode == .month
      ? TaskSchedule.addMonths(to: selected, months: amount)
      : HabitSchedule.addDays(to: selected, days: amount * (mode == .week ? 7 : 1))
    if let next { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { date = next } }
  }
  private func reload() async {
    guard navigation.section == .calendar else { return }
    let ticket = UUID()
    readID = ticket
    loading = true
    let first = days.first ?? selected
    let last = HabitSchedule.addDays(to: days.last ?? selected, days: 1) ?? selected
    let currentStatus = await store.read { try await $0.googleStatus() }
    guard ticket == readID, !Task.isCancelled else { return }
    if let currentStatus { status = currentStatus }
    if currentStatus?.status == .connected {
      let result = await store.read {
        try await $0.googleEvents(from: first, to: last, timeZone: store.timeZone)
      }
      guard ticket == readID, !Task.isCancelled else { return }
      if let result {
        events = result.events
        partial = result.partial
      }
    } else if currentStatus != nil {
      events = []
      partial = false
    }
    loading = false
  }
}

private struct CalendarResizeGrip: View {
  @Environment(RitmStore.self) private var store
  let duration: Int
  let start: Int
  let onResize: (Int) -> Void
  @GestureState private var translation: CGSize = .zero
  private func updated(_ height: CGFloat) -> Int {
    let delta = Int((height / 64 * 60 / 5).rounded()) * 5
    return min(min(720, 1440 - start), max(5, duration + delta))
  }
  var body: some View {
    VStack(spacing: 3) {
      if translation != .zero {
        Text("\(updated(translation.height))").font(.caption2.bold()).monospacedDigit()
      }
      Capsule().fill(.primary.opacity(0.65)).frame(width: 22, height: 3)
    }
    .frame(width: 44, height: 44)
    .contentShape(Rectangle())
    .highPriorityGesture(
      DragGesture(minimumDistance: 8)
        .updating($translation) { value, state, _ in state = value.translation }
        .onEnded { value in
          let result = updated(value.translation.height)
          if result != duration { onResize(result) }
        }
    )
    .accessibilityElement()
    .accessibilityLabel(store.text("Изменить длительность", "Change duration"))
    .accessibilityValue("\(duration) " + store.text("минут", "minutes"))
    .accessibilityAdjustableAction { direction in
      let delta: Int
      switch direction {
      case .increment: delta = 5
      case .decrement: delta = -5
      @unknown default: return
      }
      let value = min(min(720, 1440 - start), max(5, duration + delta))
      if value != duration { onResize(value) }
    }
  }
}
