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
  @State private var shellInset: CGFloat = 0
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
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 28)
      .frame(maxWidth: 700)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .refreshable { await store.workoutSync.syncNow() }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      // `.wk-tw { bottom: 102px }`: the bar's lower edge sits 102 pt above the screen edge, clear
      // of the floating navigation bar, whatever room the shell already reserves (`shellInset`).
      if Bar.self != EmptyView.self {
        bar.padding(.bottom, max(0, Self.barClearance - shellInset))
      }
    }
    // Outside the inset above: the bottom room the shell reserves for its navigation bar.
    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { shellInset = $0 }
  }

  /// 102 pt from the screen edge minus the 8 pt the bar keeps under itself.
  private static var barClearance: CGFloat { 94 }
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
      RitmSymbol(symbol)
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

/// `.wk-ibtn`: a 44 pt raised tile (radius 14, hairline border) for edit, delete, move and swap.
struct WorkoutIconButton: View {
  let symbol: String
  let label: String
  var tint: Color = RitmTheme.muted
  var size: CGFloat = 17
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      RitmSymbol(symbol)
        .font(.system(size: size, weight: .medium))
        .foregroundStyle(tint)
        .frame(width: 44, height: 44)
        .background(RitmTheme.glassRaised, in: RoundedRectangle(cornerRadius: 14, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.35)
    }
    .buttonStyle(RitmPressStyle(scale: 0.94))
    .accessibilityLabel(label)
  }
}

/// `.wk-rep`: the 44 pt raised rounded-rectangle text button of the editor («Заменить»).
struct WorkoutRaisedButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmFont(12, weight: .semibold)
      .foregroundStyle(RitmTheme.accentColor)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .frame(minHeight: 44)
      .background(RitmTheme.glassRaised, in: RoundedRectangle(cornerRadius: 14, style: .circular))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
      }
      .opacity(isEnabled ? 1 : 0.35)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: configuration.isPressed)
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
}

extension View {
  /// The label of a `.btn`: 12.5 pt, weight 650 (Inter's bold face).
  func workoutButtonFont() -> some View {
    ritmFont(12.5, weight: .bold)
  }
}

/// A section label above a list ("Программы"); it can carry a link on the right.
struct WorkoutSectionLabel: View {
  let title: String
  var link: String?
  var action: () -> Void = {}

  var body: some View {
    HStack {
      Text(title).ritmFont(16, weight: .semibold, tracking: -0.035).foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      if let link {
        Button(action: action) {
          Text(link).ritmFont(12.5, weight: .bold).foregroundStyle(RitmTheme.accentColor)
            .padding(.horizontal, 4)
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
      .workoutButtonFont()
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(RitmTheme.danger)
      .ritmGlass(in: Capsule(), interactive: true)
      .opacity(isEnabled ? 1 : 0.6)
      .environment(\.ritmGlassPressed, configuration.isPressed)
  }
}
