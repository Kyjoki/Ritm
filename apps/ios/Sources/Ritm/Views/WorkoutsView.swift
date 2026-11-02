import RitmCore
import SwiftUI

/// The screens of «Тренировки»: programs, the program editor, the active workout and the history.
enum WorkoutScreen: Hashable {
  case home
  case history
  case editor(String)
  case active
}

/// «Тренировки»: a personal gym log, kept on this iPhone only (see `WorkoutStore`).
struct WorkoutsView: View {
  @Environment(RitmStore.self) private var store
  @State private var screen: WorkoutScreen = .home
  @State private var resumed = false

  private var workouts: WorkoutStore { store.workouts }

  var body: some View {
    ZStack {
      RitmBackground()
      Group {
        switch screen {
        case .home: WorkoutHomeView(go: go)
        case .history: WorkoutHistoryView(go: go)
        case .editor(let id): WorkoutEditorView(programID: id, go: go)
        case .active: WorkoutActiveView(go: go)
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
      if ended, screen == .active { screen = .home }
    }
  }

  private func go(_ next: WorkoutScreen) {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    screen = next
  }
}

// MARK: - Shared pieces

/// A page of the section: the shell header, the heading with its action, then the content. The
/// active workout adds the rest timer as a bottom inset above the navigation bar.
struct WorkoutPage<Action: View, Bar: View, Content: View>: View {
  @Environment(RitmStore.self) private var store
  let title: String
  let action: Action
  let bar: Bar
  let content: Content

  init(
    title: String, @ViewBuilder action: () -> Action, @ViewBuilder bar: () -> Bar,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.action = action()
    self.bar = bar()
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        RitmShellHeader()
        RitmPageHeading(title: title) { action }
        if store.workouts.saveFailed {
          RitmErrorBanner(
            message: store.text(
              "Не удалось сохранить тренировки на iPhone. Проверьте свободное место.",
              "Could not save workouts on this iPhone. Check the free space.")
          )
          .padding(.bottom, 16)
        }
        content
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 28)
      .frame(maxWidth: 700)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
  }
}

extension WorkoutPage where Bar == EmptyView {
  init(
    title: String, @ViewBuilder action: () -> Action, @ViewBuilder content: () -> Content
  ) {
    self.init(title: title, action: action, bar: { EmptyView() }, content: content)
  }
}

/// The 44 pt glass circle beside a page title.
struct WorkoutHeaderButton: View {
  let symbol: String
  let label: String
  var prominent = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 19))
        .foregroundStyle(prominent ? RitmTheme.ctaInk : RitmTheme.accentColor)
        .frame(width: 44, height: 44)
        .ritmGlass(in: Circle(), prominent: prominent, interactive: true)
        .contentShape(Circle())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(label)
  }
}

/// A square 44 pt icon button on a calm card (edit, delete, move).
struct WorkoutIconButton: View {
  let symbol: String
  let label: String
  var tint: Color = RitmTheme.muted
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(tint)
        .frame(width: 44, height: 44)
        .background(RitmTheme.soft.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .circular))
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.94))
    .accessibilityLabel(label)
  }
}

/// A section label above a list ("Программы"); it can carry a link on the right.
struct WorkoutSectionLabel: View {
  let title: String
  var link: String?
  var action: () -> Void = {}

  var body: some View {
    HStack {
      Text(title).ritmText(.cardTitle).foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      if let link {
        Button(action: action) {
          Text(link).ritmFont(12.5, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .frame(minHeight: 44)
  }
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

  static func date(_ date: Date, language: Language, year: Bool = false) -> String {
    let locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
    var style = Date.FormatStyle(date: .omitted, time: .omitted).locale(locale)
    style = year ? style.day().month(.abbreviated).year() : style.day().month(.abbreviated)
    return date.formatted(style)
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
    let grouped = Int(value.rounded()).formatted(
      .number.grouping(.automatic).locale(Locale(identifier: russian ? "ru_RU" : "en_US")))
    return "\(grouped)\u{00A0}" + (russian ? "кг" : "kg")
  }
}

/// The secondary glass capsule with a danger label (cancel the workout).
struct WorkoutDangerButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmText(.button)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(RitmTheme.danger)
      .ritmGlass(in: Capsule(), interactive: true)
      .opacity(isEnabled ? 1 : 0.6)
      .environment(\.ritmGlassPressed, configuration.isPressed)
  }
}
