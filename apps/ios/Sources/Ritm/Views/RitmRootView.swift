import Observation
import RitmCore
import SwiftUI
import UIKit

@MainActor @Observable
final class RitmNavigation {
  /// The app opens on the calendar: it is the page used most often.
  var section: RitmSection = .calendar {
    didSet { if section != oldValue { leaving = oldValue } }
  }
  /// The page being left: it stays alive, fading on top of the new one, for the length of the
  /// exit. Set together with `section`, so the old page never leaves the tree in between.
  var leaving: RitmSection?
  var assistantPrompt: String?
  var habitCelebration: String?
  /// One-shot: set by «Настройки уведомлений» in the bell popover, consumed by Settings once it
  /// has scrolled to the notifications card.
  var scrollToNotifications = false
}
enum RitmSection: String, CaseIterable, Hashable {
  case day, calendar, habits, finance, assistant, workouts, settings
  /// The prototype glyph of the section (bottom bar and «Ещё» panel).
  var icon: RitmIconName {
    switch self {
    case .day: .grid
    case .calendar: .cal
    case .habits: .habit
    case .assistant: .ai
    case .workouts: .dumbbell
    case .finance: .wallet
    case .settings: .sliders
    }
  }
  var symbol: String {
    switch self {
    case .day: "square.grid.2x2"
    case .calendar: "calendar"
    case .habits: "checkmark.circle"
    case .assistant: "sparkles"
    case .workouts: "dumbbell"
    case .finance: "wallet.pass"
    case .settings: "slider.horizontal.3"
    }
  }
  /// Pages that bring their own header, so the shell's big one is not drawn above them: the
  /// calendar's slim bar, and the pages whose header scrolls with the content, as on the web. The
  /// other pages still keep their actions in the navigation bar, so their header stays pinned.
  var embedsHeader: Bool { [.day, .calendar, .habits, .workouts, .settings].contains(self) }
  /// Tabs shown in the bottom bar, left to right; the last slot is «Ещё».
  static let barSections: [RitmSection] = [.day, .calendar, .habits, .finance]
  /// Pages reached through the «Ещё» panel.
  static let moreSections: [RitmSection] = [.assistant, .workouts, .settings]
}
struct RitmRootView: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.colorScheme) private var scheme
  @State private var navigation = RitmNavigation()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingMore = false
  @State private var leaveTask: Task<Void, Never>?
  /// Measured once from the screen: the heading's `cqw` size and the bar's distance from the edge.
  @State private var screenWidth: CGFloat = 390
  @State private var safeBottom: CGFloat = 34
  /// Only the current page and the one still fading out are alive: a page that is not on screen
  /// must not re-render on every store change. Page-local state (an open day/week/month mode, a
  /// half-typed assistant message) starts fresh on each visit.
  private var renderedSections: [RitmSection] {
    RitmSection.allCases.filter { $0 == navigation.section || $0 == navigation.leaving }
  }

  private var preferredScheme: ColorScheme? {
    switch store.theme {
    case .dark: .dark
    case .light: .light
    case .system: nil
    }
  }

  var body: some View {
    ZStack {
      ZStack {
        ForEach(renderedSections, id: \.self) { section in
          // The incoming page appears at once and plays its own reveal; the outgoing one
          // fades for 0.12 s (MOTION.md §2) on top, then leaves the tree.
          NavigationStack { sectionView(section) }
            .modifier(RitmPageSwap(active: navigation.section == section))
            .allowsHitTesting(navigation.section == section)
            .accessibilityHidden(navigation.section != section)
            .environment(\.ritmPageActive, navigation.section == section || navigation.leaving == section)
            .zIndex(pageLayer(section))
            .toolbarBackground(.hidden, for: .navigationBar)
        }
      }
      // Every page draws its own background; this only fills the frame while pages swap.
      .background(RitmTheme.background)
      .overlay(alignment: .bottom) {
        // The bar floats 22 pt above the screen edge (`.nav { bottom: 22px }`), over the home
        // indicator's area. It reserves no room itself: each page does (`sectionView`), because
        // the navigation stack around a page does not pass an inset set outside it to its scroll view.
        RitmNavigationBar(
          sections: RitmSection.barSections, current: navigation.section,
          select: selectTab, toggleMore: toggleMore
        )
        .offset(y: safeBottom - 14)
        .background(alignment: .bottom) {
          RitmScrollEdge(side: .bottom, bottomInset: safeBottom)
        }
      }
      FinanceNotificationOverlay(openNotice: openNotice, openSettings: openNotificationSettings)
        .zIndex(1)
      RitmToastOverlay()
        .zIndex(2)
    }
    .overlayPreferenceValue(RitmMoreAnchorKey.self) { anchor in
      GeometryReader { proxy in
        if let anchor {
          RitmMorePanel(
            isOpen: showingMore, current: navigation.section, anchor: proxy[anchor],
            container: proxy.size, choose: selectTab, dismiss: { setMore(false) })
        }
      }
    }
    .onGeometryChange(for: CGSize.self) { proxy in
      CGSize(width: proxy.size.width, height: proxy.safeAreaInsets.bottom)
    } action: { value in
      screenWidth = value.width
      safeBottom = value.height
    }
    .environment(\.ritmScreenWidth, screenWidth)
    .environment(navigation)
    .tint(RitmTheme.accentColor)
    .foregroundStyle(RitmTheme.text)
    .preferredColorScheme(preferredScheme)
    .environment(\.locale, Locale(identifier: store.language.rawValue))
    .onChange(of: store.notices.isOpen) { _, isOpen in
      if isOpen { setMore(false) }
    }
    .onChange(of: store.wallet.showRequest) { _, _ in
      navigation.section = .finance
    }
    .onChange(of: store.systemNavigation, initial: true) { _, request in
      guard let request else { return }
      switch request.section {
      case .day: navigation.section = .day
      case .calendar: navigation.section = .calendar
      case .habits: navigation.section = .habits
      case .finance: navigation.section = .finance
      case .workouts: navigation.section = .workouts
      }
      store.systemNavigation = nil
    }
    .onChange(of: navigation.section) { _, _ in
      beginLeaving()
      setMore(false)
      store.notices.closePopover()
      if navigation.section != .workouts || store.workouts.systemInput == nil {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      }
    }
  }

  /// What sits above a page's content. The pinned header (calendar, finance, assistant) and the
  /// sign-in reminder are a top inset of the page itself, because the navigation stack around
  /// each page does not pass an inset set outside it on to the scroll view; pages that scroll
  /// their own header get the reminder alone. The backdrop keeps content soft beneath the inset.
  @ViewBuilder private func pageTopInset(_ section: RitmSection) -> some View {
    let reminder = store.startupFinished && !store.isSignedIn && section != .settings
    if !section.embedsHeader || reminder {
      VStack(spacing: 0) {
        if !section.embedsHeader { RitmShellHeader() }
        if reminder {
          RitmSignInBanner()
            .padding(.top, section.embedsHeader ? 6 : 0)
            .padding(.bottom, 8)
        }
      }
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity)
      .background(alignment: .top) { RitmScrollEdge(side: .top) }
    } else {
      // A page that scrolls its own header away still softens under the status bar.
      Color.clear.frame(height: 0).background(alignment: .top) { RitmScrollEdge(side: .top) }
    }
  }

  private func pageLayer(_ section: RitmSection) -> Double {
    section == navigation.section ? 1 : section == navigation.leaving ? 2 : 0
  }

  private func beginLeaving() {
    leaveTask?.cancel()
    leaveTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(RitmMotion.pageExit + 0.04))
      guard !Task.isCancelled else { return }
      navigation.leaving = nil
    }
  }

  private func setMore(_ open: Bool) {
    guard showingMore != open else { return }
    let motion = reduceMotion ? RitmMore.reduced : open ? RitmMore.inflate : RitmMore.deflate
    withAnimation(motion) { showingMore = open }
  }

  private func toggleMore() {
    if !showingMore { store.notices.closePopover() }
    setMore(!showingMore)
  }

  private func selectTab(_ section: RitmSection) {
    setMore(false)
    navigation.section = section
  }

  /// A tapped notice or banner: mark it read and land on its card in Finance.
  private func openNotice(_ notice: FinanceNotice) {
    store.notices.markRead(notice.id)
    store.notices.closePopover()
    store.notices.dismissBanner()
    if let cardID = notice.cardID {
      store.financeFocus = FinanceFocus(cardID: cardID, entryID: notice.id)
    }
    navigation.section = .finance
  }

  private func openNotificationSettings() {
    store.notices.closePopover()
    navigation.scrollToNotifications = true
    navigation.section = .settings
  }

  /// Distance from the screen edge to where a page's scroll content must end: the bar's top is
  /// 86 pt above the edge, the 16 pt gap makes it 102. The home indicator's safe area already
  /// supplies part of it.
  private static let contentClearance: CGFloat = 102

  @ViewBuilder private func sectionView(_ section: RitmSection) -> some View {
    pageContent(section)
      .safeAreaInset(edge: .top, spacing: 0) { pageTopInset(section) }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Color.clear.frame(height: max(0, Self.contentClearance - safeBottom))
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
  }

  @ViewBuilder private func pageContent(_ section: RitmSection) -> some View {
    switch section {
    case .day: DayView()
    case .calendar: CalendarView()
    case .habits: HabitsView()
    case .assistant: AssistantView()
    case .workouts: WorkoutsView()
    case .finance: FinanceView()
    case .settings: AccountView()
    }
  }
}

extension RitmSection {
  @MainActor func title(_ store: RitmStore) -> String {
    switch self {
    case .day: store.text("Мой день", "My day")
    case .calendar: store.text("Календарь", "Calendar")
    case .habits: store.text("Привычки", "Habits")
    case .assistant: store.text("ИИ-помощник", "AI assistant")
    case .workouts: store.text("Тренировки", "Workouts")
    case .finance: store.text("Финансы", "Finance")
    case .settings: store.text("Настройки", "Settings")
    }
  }
}

/// Prototype `.topbar`: a 56 pt row (below the status bar), 29 pt brand mark, wordmark, the
/// finance bell and the 44 pt theme toggle, 20 pt from the screen edges (the pages bring 16 pt,
/// the header adds 4). Day, Habits and Settings embed this same header, so they all get the
/// same bell.
struct RitmShellHeader: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.ritmPageActive) private var pageActive
  @State private var toggleFrame = RitmFrameBox()

  private var showingDark: Bool {
    store.theme == .system ? scheme == .dark : store.theme == .dark
  }

  /// Snapshot the screen with the old theme, switch, and let a circle from the button reveal it.
  private func switchTheme() {
    let dark = showingDark
    let frame = toggleFrame.frame
    let origin = frame == .zero ? CGPoint(x: 360, y: 80) : CGPoint(x: frame.midX, y: frame.midY)
    RitmThemeReveal.run(origin: origin, reduceMotion: reduceMotion) {
      Task { await store.toggleTheme(showingDark: dark) }
    }
  }

  var body: some View {
    HStack(spacing: 10) {
      RitmMark()
        .fill(Color(rgb: 0x34234C))
        .frame(width: 18, height: 18)
        .frame(width: 29, height: 29)
        .background(
          RitmTheme.linear(
            [.init(color: Color(rgb: 0xE5D7FF), location: 0),
             .init(color: Color(rgb: 0xC4ABEB), location: 1)], cssAngle: 130),
          in: RoundedRectangle(cornerRadius: 10, style: .circular)
        )
        .shadow(color: Color(rgb: 0xB98DEB, opacity: 0.13), radius: 6)
        .accessibilityHidden(true)
      Text("Ritm")
        .ritmText(.brand)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      // Not a GlassEffectContainer: it would clip the bell's badge at the button's edge.
      Group {
        HStack(spacing: 8) {
          FinanceBellButton()
          Button(action: switchTheme) {
            RitmIcon(showingDark ? .sun : .moon)
              .font(.system(size: 20))
              .foregroundStyle(RitmTheme.muted)
              .frame(width: 44, height: 44)
              .ritmFloatingGlass(in: Circle(), interactive: true)
              .contentShape(Circle())
          }
          .buttonStyle(RitmGlassButtonStyle())
          .ritmFrameReader(active: pageActive) { toggleFrame.frame = $0 }
          .disabled(store.pendingTheme != nil)
          .accessibilityLabel(store.text("Переключить тему", "Switch appearance"))
        }
      }
    }
    .padding(.horizontal, 4)
    .frame(height: 56)
  }
}

/// Page switch: appearing is instant; leaving fades over 0.12 s with a 4 pt lift (easeIn).
/// Reduce Motion: a plain fade without the lift.
private struct RitmPageSwap: ViewModifier {
  let active: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let lift: CGFloat = -4

  private var exit: Animation {
    reduceMotion
      ? RitmMotion.reducedFade
      : .timingCurve(0.42, 0, 1, 1, duration: RitmMotion.pageExit)
  }

  func body(content: Content) -> some View {
    content
      .opacity(active ? 1 : 0)
      .offset(y: active || reduceMotion ? 0 : Self.lift)
      .animation(active ? nil : exit, value: active)
  }
}

extension View {
  /// Reports the view's frame in window coordinates whenever it moves, while `active`. A page
  /// that is only fading out must not move a shared origin. It does not rebuild any view while
  /// the page scrolls: only `record` runs.
  func ritmFrameReader(active: Bool, record: @escaping (CGRect) -> Void) -> some View {
    onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
      if active { record(frame) }
    }
  }
}

/// Last known frame of a view in window coordinates. Deliberately not observed: it moves with
/// scrolling and is only read at the moment of a tap.
@MainActor final class RitmFrameBox {
  var frame: CGRect = .zero
}

/// Motion of the bottom bar (prototype shell.html + glass.css): the indicator slides in 0.5 s on
/// `cubic-bezier(.2, .9, .25, 1.12)`; the «Ещё» panel inflates out of its icon in 0.30 s with a
/// tiny overshoot (`cubic-bezier(.34, 1.32, .5, 1)`, about 3 %) and shrinks back in 0.18 s
/// without one.
private enum RitmMore {
  static let slide = Animation.timingCurve(0.2, 0.9, 0.25, 1.12, duration: 0.5)
  static let inflate = Animation.timingCurve(0.34, 1.32, 0.5, 1, duration: 0.30)
  static let deflate = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)
  static let reduced = Animation.easeOut(duration: 0.12)
  /// Scale of the panel at the moment it leaves the icon.
  static let seed: CGFloat = 0.35
  /// Tile `n` starts `n * 40 ms + 70 ms` after the panel does.
  static let stagger = 0.04
  static let firstTile = 0.07
}

/// Bounds of the «Ещё» slot in the bar, so the panel can be anchored right above it.
private struct RitmMoreAnchorKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}

/// Prototype bottom navigation (`.nav`): an icon-only glass capsule with four section slots and
/// «Ещё», 6 pt padding, 52 pt slots, and one 56 × 42 indicator that slides between the slots.
private struct RitmNavigationBar: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  let sections: [RitmSection]
  let current: RitmSection
  let select: (RitmSection) -> Void
  let toggleMore: () -> Void

  private var moreSelected: Bool { RitmSection.moreSections.contains(current) }
  private var slotCount: Int { sections.count + 1 }
  private var selectedIndex: Int { sections.firstIndex(of: current) ?? sections.count }

  var body: some View {
    bar
      .padding(.horizontal, 16)
      .padding(.bottom, 8)
  }

  private var bar: some View {
    HStack(spacing: 0) {
      ForEach(sections, id: \.self) { section in
        item(title: section.title(store), icon: section.icon, selected: current == section) {
          select(section)
        }
      }
      item(
        title: store.text("Ещё", "More"), icon: .dots, selected: moreSelected,
        value: moreSelected ? current.title(store) : "", action: toggleMore
      )
      .anchorPreference(key: RitmMoreAnchorKey.self, value: .bounds) { $0 }
    }
    .background {
      GeometryReader { proxy in
        let slot = proxy.size.width / CGFloat(slotCount)
        RitmNavThumb()
          .frame(width: 56, height: 42)
          .frame(width: slot, height: proxy.size.height)
          .offset(x: slot * CGFloat(selectedIndex))
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .animation(reduceMotion ? nil : RitmMore.slide, value: selectedIndex)
    .padding(6)
    .ritmFloatingGlass(in: Capsule())
  }

  private func item(
    title: String, icon: RitmIconName, selected: Bool, value: String = "", action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      RitmIcon(icon)
        .font(.system(size: 23))
        .modifier(RitmIconSettle(active: selected))
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(
          contrast == .increased
            ? RitmTheme.text : selected ? RitmTheme.navActiveInk : RitmTheme.navInk
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .accessibilityLabel(title)
    .accessibilityValue(value)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// `.nav-pill::before`: a drop of glass under the active icon. A plain fill (the accent at 22 %
/// over the thumb tint, lit from above) with a hairline rim and a short shadow: no second blur.
private struct RitmNavThumb: View {
  var body: some View {
    let shape = Capsule()
    let base = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.92, darkOpacity: 0.15)
    shape
      .fill(
        LinearGradient(
          colors: [RitmTheme.mix(RitmTheme.accentColor, 0.22, into: base), base],
          startPoint: .top, endPoint: .bottom)
      )
      .overlay {
        shape.strokeBorder(
          Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.5, darkOpacity: 0.09),
          lineWidth: 1)
      }
      .shadow(
        color: Color(light: 0x553086, dark: 0x000000, lightOpacity: 0.12, darkOpacity: 0.3),
        radius: 5, y: 3)
  }
}

/// The active nav icon settles from .88 to 1 over 210 ms.
private struct RitmIconSettle: ViewModifier {
  let active: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var scale: CGFloat = 1

  func body(content: Content) -> some View {
    content
      .scaleEffect(scale)
      .onChange(of: active) { _, isActive in
        guard isActive, !reduceMotion else { return }
        scale = 0.88
        Task { @MainActor in withAnimation(RitmMotion.ease(0.21)) { scale = 1 } }
      }
  }
}

/// «Ещё» (`.more-pop`): a compact glass panel 12 pt above the bar, right-aligned 16 pt from the
/// edge, with one 100 × 72 tile per section. It stays in the tree and animates (scale + fade
/// from the «Ещё» icon) so it can also close smoothly.
private struct RitmMorePanel: View {
  private static let tileWidth: CGFloat = 100
  private static let padding: CGFloat = 10
  private static let spacing: CGFloat = 8
  private static let radius: CGFloat = 22
  private static let panelWidth =
    tileWidth * CGFloat(RitmSection.moreSections.count)
    + spacing * CGFloat(RitmSection.moreSections.count - 1) + padding * 2

  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let isOpen: Bool
  let current: RitmSection
  let anchor: CGRect
  let container: CGSize
  let choose: (RitmSection) -> Void
  let dismiss: () -> Void

  /// Top of the bar: the slot sits in the bar's 6 pt padding.
  private var barTop: CGFloat { anchor.minY - 6 }
  private var edgeInset: CGFloat { 16 }
  private var panelLeft: CGFloat { container.width - edgeInset - Self.panelWidth }
  /// The panel's bottom edge, 12 pt above the bar.
  private var panelBottom: CGFloat { barTop - 12 }
  /// The icon's centre inside the panel's width (`transform-origin`).
  private var originX: CGFloat { min(max(anchor.midX - panelLeft, 0), Self.panelWidth) }
  /// Scaling the panel about its bottom edge at the icon's x and shifting it by `(1 - scale)` of
  /// the way down to the icon is the same as scaling it about the icon, so the panel grows out of
  /// the icon without knowing its own height.
  private var inflateShift: CGSize {
    CGSize(width: anchor.midX - (panelLeft + originX), height: anchor.midY - panelBottom)
  }

  private func tileMotion(_ index: Int) -> Animation? {
    guard !reduceMotion else { return nil }
    return isOpen
      ? Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)
        .delay(RitmMore.firstTile + RitmMore.stagger * Double(index))
      : RitmMore.deflate
  }

  var body: some View {
    ZStack(alignment: .top) {
      if isOpen {
        // Taps above the bar close the panel; the bar itself stays live.
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture(perform: dismiss)
          .frame(maxWidth: .infinity)
          .frame(height: max(0, barTop))
          .accessibilityElement()
          .accessibilityLabel(store.text("Закрыть", "Close"))
          .accessibilityAddTraits(.isButton)
      }
      panel
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, edgeInset)
        .padding(.bottom, max(0, container.height - panelBottom))
    }
    .frame(width: container.width, height: container.height)
  }

  private var panel: some View {
    let scale = reduceMotion || isOpen ? 1 : RitmMore.seed
    let shape = RoundedRectangle(cornerRadius: Self.radius, style: .circular)
    return HStack(spacing: Self.spacing) {
      ForEach(Array(RitmSection.moreSections.enumerated()), id: \.element) { index, section in
        tile(section, index: index)
      }
    }
    .padding(Self.padding)
    // A dense under-layer keeps the labels readable on any content behind the glass.
    .background(RitmTheme.glassDense.opacity(0.55), in: shape)
    .ritmFloatingGlass(in: shape)
    .scaleEffect(scale, anchor: UnitPoint(x: originX / Self.panelWidth, y: 1))
    .offset(x: (1 - scale) * inflateShift.width, y: (1 - scale) * inflateShift.height)
    .opacity(isOpen ? 1 : 0)
    .allowsHitTesting(isOpen)
    .accessibilityHidden(!isOpen)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, dismiss)
  }

  /// `.more-tile`: 100 × 72, radius 16, hairline border on a translucent tile; the current
  /// section is the soft accent tile with an accent border.
  private func tile(_ section: RitmSection, index: Int) -> some View {
    let selected = section == current
    let shown = reduceMotion || isOpen
    let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
    return Button {
      choose(section)
    } label: {
      VStack(spacing: 6) {
        RitmIcon(section.icon)
          .font(.system(size: 24))
          .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
        Text(section.title(store))
          .ritmFont(11.5, weight: .semibold)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.text)
      .padding(.vertical, 8).padding(.horizontal, 6)
      .frame(width: Self.tileWidth)
      .frame(minHeight: 72)
      .background(selected ? RitmTheme.soft : RitmTheme.glassTile, in: shape)
      .overlay {
        shape.strokeBorder(selected ? RitmTheme.accentColor : RitmTheme.glassHair, lineWidth: 1)
      }
      .contentShape(shape)
    }
    .buttonStyle(RitmPressStyle(scale: 0.95))
    .opacity(shown ? 1 : 0)
    .offset(y: shown ? 0 : 6)
    .scaleEffect(shown ? 1 : 0.92)
    .animation(tileMotion(index), value: isOpen)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

struct MutationRecoveryView: View {
  @Environment(RitmStore.self) private var store
  var body: some View {
    if store.uncertainWrite {
      VStack(alignment: .leading, spacing: 10) {
        Text(
          store.text(
            "Предыдущая операция могла сохраниться. Проверьте данные перед повтором.",
            "The previous action may have been saved. Check your data before trying again.")
        )
        .ritmText(.body).foregroundStyle(RitmTheme.muted)
        Button {
          Task { await store.refresh() }
        } label: {
          Label(store.text("Обновить данные", "Refresh data"), systemImage: "arrow.clockwise")
            .frame(minHeight: 44)
        }.disabled(store.isLoading || store.isMutating)
        Button {
          store.acknowledgeUncertainWrite()
        } label: {
          Text(store.text("Я проверил данные", "I have checked the data")).frame(minHeight: 44)
        }
      }
    }
  }
}
struct SyncStatusView: View {
  @Environment(RitmStore.self) private var store

  /// Times use AM/PM in both languages (AGENTS.md).
  private func clock(_ date: Date) -> String {
    FormatterCache.shared.clock(date, zone: store.timeZone)
  }

  var body: some View {
    HStack(spacing: 8) {
      if store.isLoading || store.isMutating {
        ProgressView().controlSize(.small)
        Text(
          store.isMutating
            ? store.text("Сохраняем…", "Saving…") : store.text("Обновляем…", "Refreshing…"))
      } else if store.isOffline {
        Image(systemName: "wifi.slash")
        Text(
          store.text(
            "Нет связи · данные могут быть устаревшими", "Offline · data may be out of date"))
      } else if let date = store.lastSyncedAt {
        RitmIcon(.ok)
        Text(store.text("Обновлено", "Updated") + " " + clock(date))
      } else {
        RitmIcon(.refresh)
        Text(store.text("Ожидаем обновления", "Waiting to refresh"))
      }
    }
    .ritmText(.cardCaption).foregroundStyle(RitmTheme.muted).accessibilityElement(children: .combine)
  }
}
