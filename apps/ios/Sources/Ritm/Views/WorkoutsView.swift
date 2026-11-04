import RitmCore
import SwiftUI

/// The screens of «Тренировки»: home, a program, the editor, the workout in progress, the
/// summary after it, and the whole history.
enum WorkoutScreen: Hashable {
  case home
  case history
  case program(String)
  /// The program editor; `isNew` for a program that does not exist until «Сохранить».
  case editor(id: String, isNew: Bool)
  case active
  case summary

  /// Where «Назад» and «Отмена» lead from here.
  var parent: WorkoutScreen {
    switch self {
    case .editor(let id, let isNew): isNew ? .home : .program(id)
    default: .home
    }
  }
}

/// «Тренировки»: a personal gym log, kept on this iPhone (see `WorkoutStore`).
struct WorkoutsView: View {
  @Environment(RitmStore.self) private var store
  @State private var screen: WorkoutScreen = .home
  @State private var resumed = false
  @State private var replacing: String?
  @State private var finished: WorkoutRecord?

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    ZStack {
      RitmBackground()
      Group {
        switch screen {
        case .home: WorkoutHomeView(go: go, start: start)
        case .history: WorkoutHistoryView(go: go)
        case .program(let id): WorkoutProgramView(programID: id, go: go, start: start)
        case .editor(let id, let isNew): WorkoutEditorView(programID: id, isNew: isNew, go: go)
        case .active: WorkoutActiveView(go: go, finished: { finished = $0 })
        case .summary: WorkoutSummaryView(record: finished, go: go)
        }
      }
      .id(screen)
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      // An unfinished workout is picked up again where it was left.
      guard !resumed else { return }
      resumed = true
      if workouts.session != nil { screen = .active }
    }
    .onChange(of: workouts.session == nil) { _, ended in
      if ended, screen == .active, finished == nil { screen = .home }
    }
    .alert(
      store.text("Завершить текущую и начать новую?", "Finish this workout and start a new one?"),
      isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })
    ) {
      Button(store.text("Завершить и начать", "Finish and start")) {
        if let id = replacing { replaceAndStart(id) }
        replacing = nil
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) { replacing = nil }
    } message: {
      Text(
        store.text(
          "Тренировка «\(workouts.session?.programName ?? "")» будет сохранена в истории",
          "“\(workouts.session?.programName ?? "")” will be saved to the history"))
    }
  }

  private func go(_ next: WorkoutScreen) {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    if next != .summary { finished = nil }
    screen = next
  }

  /// «Начать тренировку»: opens the running workout when it is this program's, asks before
  /// replacing another one, otherwise starts.
  private func start(_ programID: String) {
    if let session = workouts.session {
      if session.programID == programID { go(.active) } else { replacing = programID }
      return
    }
    begin(programID)
  }

  private func begin(_ programID: String) {
    switch workouts.startWorkout(programID: programID, language: store.language) {
    case .started, .alreadyActive: go(.active)
    case .empty:
      store.toasts.show(
        store.text(
          "Добавьте в программу хотя бы одно упражнение", "Add at least one exercise to the program"))
    }
  }

  /// The current workout goes to the history (or is dropped when nothing was ticked).
  private func replaceAndStart(_ programID: String) {
    if workouts.finishWorkout() == nil { workouts.cancelWorkout() }
    begin(programID)
  }
}

// MARK: - Page

/// A page of the section: the shell header, the screen's own heading, then the content. A rest
/// that is running floats above the navigation bar on every screen; `bar` (the «Начать
/// тренировку» button) sits under it.
struct WorkoutPage<Header: View, Bar: View, Content: View>: View {
  @Environment(RitmStore.self) private var store
  @State private var shellInset: CGFloat = 0
  let header: Header
  let bar: Bar
  let content: Content
  private let hasBar: Bool

  init(
    @ViewBuilder header: () -> Header, @ViewBuilder bar: () -> Bar,
    @ViewBuilder content: () -> Content
  ) {
    self.header = header()
    self.bar = bar()
    self.content = content()
    hasBar = Bar.self != EmptyView.self
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        RitmShellHeader()
        header
        if store.workouts.saveFailed {
          RitmErrorBanner(
            message: store.text(
              "Не удалось сохранить тренировки на iPhone. Проверьте свободное место.",
              "Could not save workouts on this iPhone. Check the free space.")
          )
          .padding(.bottom, 16)
        }
        if store.workoutSync.failing {
          Text(
            store.text(
              "Не удаётся синхронизировать тренировки. Всё сохранено на iPhone, попробуем снова.",
              "Can't sync workouts right now. Everything is saved on this iPhone; we'll retry.")
          )
          .ritmText(.body).foregroundStyle(RitmTheme.muted)
          .padding(.bottom, 12)
        }
        content
        WorkoutRestSpacer()
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 28)
      .frame(maxWidth: 700)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .refreshable { await store.workoutSync.syncNow() }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      // The bar's lower edge sits 102 pt above the screen edge, clear of the floating navigation
      // bar, whatever room the shell already reserves (`shellInset`).
      let lift = max(0, Self.barClearance - shellInset)
      VStack(spacing: 0) {
        WorkoutRestCapsule(bottomPadding: hasBar ? 8 : lift)
        if hasBar { bar.padding(.bottom, lift) }
      }
    }
    // Outside the inset above: the bottom room the shell reserves for its navigation bar.
    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { shellInset = $0 }
  }

  /// 102 pt from the screen edge minus the 8 pt the bar keeps under itself.
  private static var barClearance: CGFloat { 94 }
}

extension WorkoutPage where Bar == EmptyView {
  init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
    self.init(header: header, bar: { EmptyView() }, content: content)
  }
}

/// `.ibtn`: the round glass button of a heading (back, settings, menu); 38 or 44 pt.
struct WorkoutRoundButton: View {
  let symbol: String
  let label: String
  var size: CGFloat = 38
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RitmSymbol(symbol)
        .font(.system(size: size * 0.5))
        .foregroundStyle(RitmTheme.text)
        .frame(width: size, height: size)
        .ritmGlass(in: Circle(), interactive: true)
        .contentShape(Circle())
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(label)
  }
}

/// `.sh`: a section title with an optional link on the right.
struct WorkoutSectionHeader: View {
  let title: String
  var link: String?
  var action: () -> Void = {}

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).ritmFont(17, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      if let link {
        Button(action: action) {
          Text(link).ritmFont(13, weight: .medium).foregroundStyle(RitmTheme.accentColor)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 2)
    .padding(.top, 10)
  }
}

/// `.empty`: a centred muted line for a list without items.
struct WorkoutEmptyText: View {
  let text: String

  var body: some View {
    Text(text)
      .ritmFont(12.5).foregroundStyle(RitmTheme.muted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 8).padding(.vertical, 18)
  }
}

/// `--income`: the green of a gain against the last workout.
enum WorkoutColors {
  static var income: Color { Color(light: 0x2A7F66, dark: 0x86D4B6) }
  /// The ink on a done tick, `#0f2a20`.
  static var onIncome: Color { Color(rgb: 0x0F2A20) }
}

enum WorkoutText {
  /// «3 упражнения»: the Russian plural forms, English singular and plural.
  static func exercises(_ count: Int, russian: Bool) -> String {
    guard russian else { return "\(count) " + (count == 1 ? "exercise" : "exercises") }
    return "\(count) " + plural(count, "упражнение", "упражнения", "упражнений")
  }

  static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let hundred = n % 100
    let unit = n % 10
    if hundred > 10 && hundred < 15 { return many }
    if unit == 1 { return one }
    if unit > 1 && unit < 5 { return few }
    return many
  }

  private static let formatters = DateFormatterCache()

  /// «2 ноября» (with the year when asked).
  static func date(_ date: Date, language: Language, year: Bool = false) -> String {
    formatters.string(date, language: language, template: year ? "d MMMM y" : "d MMMM")
  }

  /// «3 нояб.».
  static func shortDate(_ date: Date, language: Language) -> String {
    formatters.string(date, language: language, template: "d MMM")
  }

  /// «Сегодня», «Вчера», otherwise «2 ноября».
  static func relativeDay(_ date: Date, today: String, timeZone: String, language: Language) -> String {
    let key = HabitSchedule.dateKey(date, timeZone: timeZone)
    if key == today { return language == .ru ? "Сегодня" : "Today" }
    if key == HabitSchedule.addDays(to: today, days: -1) { return language == .ru ? "Вчера" : "Yesterday" }
    return Self.date(date, language: language)
  }

  /// «52 мин» or «1 ч 05 мин».
  static func duration(_ seconds: TimeInterval, russian: Bool) -> String {
    let minutes = max(1, Int((seconds / 60).rounded()))
    let hours = minutes / 60
    let rest = minutes % 60
    let h = russian ? "ч" : "h"
    let m = russian ? "мин" : "min"
    return hours > 0
      ? "\(hours)\u{00A0}\(h) \(String(format: "%02d", rest))\u{00A0}\(m)" : "\(minutes)\u{00A0}\(m)"
  }

  static func kilograms(_ value: Double, russian: Bool) -> String {
    "\(grouped(value, russian: russian))\u{00A0}" + (russian ? "кг" : "kg")
  }

  private static let ruGrouping = groupingFormatter("ru_RU")
  private static let enGrouping = groupingFormatter("en_US")

  private static func groupingFormatter(_ id: String) -> NumberFormatter {
    let f = NumberFormatter()
    f.locale = Locale(identifier: id)
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return f
  }

  static func grouped(_ value: Double, russian: Bool) -> String {
    (russian ? ruGrouping : enGrouping).string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
  }
}

/// Date formatters are costly to build; one per language and style, made on first use.
private final class DateFormatterCache: @unchecked Sendable {
  private let lock = NSLock()
  private var formatters: [String: DateFormatter] = [:]

  func string(_ date: Date, language: Language, template: String) -> String {
    let key = "\(language.rawValue)-\(template)"
    lock.lock()
    defer { lock.unlock() }
    let formatter: DateFormatter
    if let cached = formatters[key] {
      formatter = cached
    } else {
      formatter = DateFormatter()
      formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
      formatter.setLocalizedDateFormatFromTemplate(template)
      formatters[key] = formatter
    }
    return formatter.string(from: date)
  }
}
