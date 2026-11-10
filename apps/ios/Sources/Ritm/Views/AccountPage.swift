import RitmCore
import SwiftUI

/// Where the theme reveal grows from: the selected appearance button when it is on screen.
/// Frames are in window coordinates and only read at the moment of a tap.
@MainActor private final class SettingsRevealFrames {
  var buttons: [String: CGRect] = [:]
}

/// A theme reveal armed by a tap, started once the app really switches colour scheme.
private struct ThemeRevealRequest {
  let origin: CGPoint
  let expires: Date
}

/// Inputs that decide when the one-shot scroll to the notifications group can run.
private struct NotificationScrollTrigger: Equatable {
  let requested: Bool
  let ready: Bool
  let onSettings: Bool
}

/// «Настройки», variant «Список»: a large title that collapses into the top bar, the profile
/// row and inset groups of rows; every detail is a pushed page. Nothing here has a Save button:
/// each change is sent by itself (`SettingsModel`) and confirmed by a small «Сохранено».
/// Creates the page with the account's settings already in hand, so the first frame shows them.
struct AccountView: View {
  @Environment(RitmStore.self) private var store

  var body: some View { AccountContent(initial: store.bootstrap?.settings) }
}

private struct AccountContent: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.ritmPageActive) private var pageActive
  @State private var model: SettingsModel
  @State private var revealFrames = SettingsRevealFrames()
  @State private var themeReveal: ThemeRevealRequest?
  @State private var scrollTick = 0
  @State private var collapsed = false
  private static let notificationsAnchor = "settings-notifications"
  /// How far the page scrolls before the large title is gone and the bar title takes over.
  private static let collapseOffset: CGFloat = 80

  init(initial: AccountSettings?) {
    _model = State(initialValue: SettingsModel(initial: initial))
  }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            RitmShellHeader()
            if let message = store.errorMessage { RitmErrorBanner(message: message).padding(.bottom, 12) }
            MutationRecoveryView()
            content
            RitmPageFooter()
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 28)
          .frame(maxWidth: 700)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
          geometry.contentOffset.y + geometry.contentInsets.top > Self.collapseOffset
        } action: { _, isCollapsed in
          collapsed = isCollapsed
        }
        .refreshable {
          await store.refresh()
          await model.loadIntegrations()
          await store.security.load(using: store)
        }
        .task(id: scrollTrigger) { await awaitNotificationsScroll() }
        .onChange(of: scrollTick) { _, _ in
          withAnimation(reduceMotion ? nil : RitmMotion.easeInOut(0.5)) {
            proxy.scrollTo(Self.notificationsAnchor, anchor: .top)
          }
        }
      }
      collapsedBar
      SettingsSavedToast()
    }
    .environment(model)
    .toolbar(.hidden, for: .navigationBar)
    .navigationTitle(store.text("Настройки", "Settings"))
    .navigationDestination(for: SettingsRoute.self) { route in
      SettingsDestination(route: route).environment(model)
    }
    .modifier(lifecycle)
  }

  @ViewBuilder private var content: some View {
    if !store.isSignedIn {
      RitmPageHeading(title: store.text("Настройки", "Settings"))
      VStack(spacing: 14) {
        LoginCard().ritmPageReveal(index: 0)
        ServerAddressCard().ritmPageReveal(index: 1)
      }
    } else if model.loaded {
      largeTitle
      SettingsMainList(
        onTheme: chooseTheme, themeFrame: { revealFrames.buttons[$0] = $1 },
        notificationsAnchor: Self.notificationsAnchor)
    } else {
      largeTitle
      HStack(spacing: 9) {
        ProgressView().tint(RitmTheme.accentColor)
        Text(store.text("Загружаем…", "Loading…"))
      }
      .ritmFont(12)
      .foregroundStyle(RitmTheme.muted)
      .frame(maxWidth: .infinity, minHeight: 145)
      .background { RitmPanelBackground() }
    }
  }

  // MARK: Title

  /// `.a-t`: 32 pt, weight 700, 6 pt above and 14 pt below.
  private var largeTitle: some View {
    Text(store.text("Настройки", "Settings"))
      .ritmFont(32, weight: .bold, tracking: -0.05)
      .foregroundStyle(RitmTheme.text)
      .padding(.horizontal, 4)
      .padding(.top, 6)
      .padding(.bottom, 14)
      .accessibilityAddTraits(.isHeader)
  }

  /// `.a-bar`: the small centred title that fades in once the large one has scrolled away.
  private var collapsedBar: some View {
    Text(store.text("Настройки", "Settings"))
      .ritmFont(17, weight: .bold, tracking: -0.035)
      .foregroundStyle(RitmTheme.text)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(alignment: .top) { RitmScrollEdge(side: .top) }
      .frame(maxHeight: .infinity, alignment: .top)
      .opacity(collapsed && store.isSignedIn ? 1 : 0)
      .offset(y: collapsed || reduceMotion ? 0 : 4)
      .animation(reduceMotion ? nil : RitmMotion.easeOut(0.2), value: collapsed)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  // MARK: Lifecycle

  private var lifecycle: SettingsLifecycle {
    SettingsLifecycle(
      model: model, onSettings: navigation.section == .settings,
      themeChanged: { startThemeReveal() }, scheme: scheme)
  }

  // MARK: Theme reveal

  /// A different effective theme switches the whole app, so it gets the same circular reveal as
  /// the top-bar toggle. The snapshot of the old look is taken when the scheme actually changes
  /// (`startThemeReveal`), which is right after the tap, because the theme shows at once.
  private func chooseTheme(_ theme: Theme) {
    guard theme != model.draft.theme else { return }
    armThemeReveal(for: theme)
    model.setTheme(theme)
  }

  private func armThemeReveal(for theme: Theme) {
    let toDark = theme == .system ? RitmThemeReveal.systemIsDark : theme == .dark
    guard toDark != (scheme == .dark) else {
      themeReveal = nil
      return
    }
    let bounds = RitmThemeReveal.windowBounds
    let button = revealFrames.buttons[theme.rawValue]
    let anchor = button.flatMap { bounds.contains($0) ? $0 : nil }
    let origin = anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: bounds.midX, y: bounds.maxY - 120)
    themeReveal = ThemeRevealRequest(origin: origin, expires: Date().addingTimeInterval(10))
  }

  private func startThemeReveal() {
    guard let request = themeReveal else { return }
    themeReveal = nil
    guard request.expires > Date() else { return }
    RitmThemeReveal.run(origin: request.origin, reduceMotion: reduceMotion) {}
  }

  // MARK: Scroll to notifications

  private var scrollTrigger: NotificationScrollTrigger {
    NotificationScrollTrigger(
      requested: navigation.scrollToNotifications, ready: model.loaded,
      onSettings: navigation.section == .settings)
  }

  /// «Настройки уведомлений» in the bell popover: once the page is shown and its groups exist,
  /// wait for the reveal to lay out, then scroll once.
  private func awaitNotificationsScroll() async {
    let trigger = scrollTrigger
    guard trigger.requested, trigger.ready, trigger.onSettings else { return }
    try? await Task.sleep(for: .milliseconds(350))
    guard !Task.isCancelled, navigation.scrollToNotifications else { return }
    navigation.scrollToNotifications = false
    scrollTick += 1
  }
}

/// What keeps the model in step with the app: the first copy of the settings, refreshes, the
/// phone's notification permission, a changed theme, and sending what is waiting when the page
/// is left or the app goes to the background.
private struct SettingsLifecycle: ViewModifier {
  let model: SettingsModel
  let onSettings: Bool
  let themeChanged: () -> Void
  let scheme: ColorScheme
  @Environment(RitmStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      .onAppear {
        model.store = store
        model.sync(with: store.bootstrap?.settings)
      }
      .onChange(of: store.bootstrap?.settings) { _, settings in model.sync(with: settings) }
      .task(id: onSettings) {
        guard onSettings else { return }
        await model.loadIntegrations()
        await store.security.load(using: store)
        await model.refreshPhonePermission()
      }
      .onChange(of: store.isSignedIn) { _, signedIn in
        if signedIn {
          model.sync(with: store.bootstrap?.settings)
          Task { await store.security.load(using: store) }
        } else {
          model.reset()
        }
      }
      .onChange(of: store.lastSyncedAt) { _, _ in
        if onSettings { Task { await model.loadIntegrations() } }
      }
      .onChange(of: scheme) { _, _ in themeChanged() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await model.refreshPhonePermission() } }
        if phase == .background { Task { await model.settle() } }
      }
      .onDisappear { Task { await model.settle() } }
  }
}
