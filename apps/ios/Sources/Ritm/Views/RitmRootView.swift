import Observation
import RitmCore
import SwiftUI
import UIKit

@MainActor @Observable
final class RitmNavigation {
  var section: RitmSection = .day { didSet { visited.insert(section) } }
  private(set) var visited: Set<RitmSection> = [.day]
  var assistantPrompt: String?
  var habitCelebration: String?
}
enum RitmSection: String, CaseIterable, Hashable {
  case day, calendar, habits, finance, assistant, settings
  var symbol: String {
    switch self {
    case .day: "square.grid.2x2"
    case .calendar: "calendar"
    case .habits: "checklist"
    case .assistant: "sparkles"
    case .finance: "wallet.pass"
    case .settings: "slider.horizontal.3"
    }
  }
  /// Pages whose header scrolls with the content, as on the web. The other pages still keep
  /// their actions in the navigation bar, so their header stays pinned for now.
  var embedsHeader: Bool { [.day, .habits, .settings].contains(self) }
  /// Tabs shown in the bottom bar, left to right; the last slot is «Ещё».
  static let barSections: [RitmSection] = [.day, .calendar, .habits, .finance]
  /// Pages reached through the «Ещё» panel.
  static let moreSections: [RitmSection] = [.assistant, .settings]
}
struct RitmRootView: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.colorScheme) private var scheme
  @State private var navigation = RitmNavigation()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingMore = false
  private var visitedSections: [RitmSection] {
    RitmSection.allCases.filter { navigation.visited.contains($0) }
  }

  private var preferredScheme: ColorScheme? {
    switch store.theme {
    case .dark: .dark
    case .light: .light
    case .system: nil
    }
  }

  var body: some View {
    Group {
      if store.isSignedIn {
        ZStack {
          ZStack {
            ForEach(visitedSections, id: \.self) { section in
              // The web switches pages instantly; only the nav indicator moves.
              NavigationStack { sectionView(section) }
                .opacity(navigation.section == section ? 1 : 0)
                .allowsHitTesting(navigation.section == section)
                .accessibilityHidden(navigation.section != section)
                .environment(\.ritmPageActive, navigation.section == section)
                .zIndex(navigation.section == section ? 1 : 0)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
          }
          // The pinned header is a top inset with its own backdrop: pages scroll under it, but
          // never show crisp content behind the logo and the buttons.
          .safeAreaInset(edge: .top, spacing: 0) {
            if !navigation.section.embedsHeader {
              RitmShellHeader()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) { RitmHeaderBackdrop() }
            }
          }
          .background { RitmBackground() }
          .safeAreaInset(edge: .bottom, spacing: 0) {
            RitmNavigationBar(
              sections: RitmSection.barSections, current: navigation.section,
              select: selectTab, toggleMore: toggleMore)
          }
          FinanceNotificationOverlay(openNotice: openNotice, openSettings: openNotificationSettings)
            .zIndex(1)
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
        .environment(navigation)
      } else {
        LoginView()
      }
    }
    .tint(RitmTheme.accentColor)
    .foregroundStyle(RitmTheme.text)
    .preferredColorScheme(preferredScheme)
    .environment(\.locale, Locale(identifier: store.language.rawValue))
    .onChange(of: store.notices.isOpen) { _, isOpen in
      if isOpen { setMore(false) }
    }
    .onChange(of: navigation.section) { _, _ in
      setMore(false)
      store.notices.closePopover()
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
    navigation.section = .settings
  }

  @ViewBuilder private func sectionView(_ section: RitmSection) -> some View {
    switch section {
    case .day: DayView()
    case .calendar: CalendarView()
    case .habits: HabitsView()
    case .assistant: AssistantView()
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
    case .finance: store.text("Финансы", "Finance")
    case .settings: store.text("Настройки", "Settings")
    }
  }
}

/// The 44 pt glass tile behind the header's icon buttons (theme toggle, notification bell).
struct RitmHeaderIconBackground: View {
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 13, style: .circular)
    shape
      .fill(
        RitmTheme.linear(
          [.init(color: RitmTheme.glassRaised, location: 0),
           .init(color: RitmTheme.panel, location: 1)], cssAngle: 150))
      .overlay { shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
      .shadow(color: Color(rgb: 0x583882, opacity: 0.11), radius: 10, y: 6)
  }
}

/// Web `.app-header`: 62 pt, 29 pt brand mark, wordmark, the finance bell and the 44 pt theme
/// toggle. Day, Habits and Settings embed this same header, so they all get the same bell.
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

  private var toggleFrameReader: some View {
    GeometryReader { proxy in
      let frame = proxy.frame(in: .global)
      Color.clear
        .onAppear { record(frame) }
        .onChange(of: frame) { _, value in record(value) }
        .onChange(of: pageActive) { _, _ in record(frame) }
    }
  }

  /// Pages kept alive behind the active one must not move the origin.
  private func record(_ frame: CGRect) {
    guard pageActive else { return }
    toggleFrame.frame = frame
  }

  var body: some View {
    HStack(spacing: 8) {
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
        .shadow(color: Color(rgb: 0xB98DEB, opacity: 0.13), radius: 12)
        .accessibilityHidden(true)
      Text("Ritm")
        .ritmText(.brand)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      FinanceBellButton()
      Button(action: switchTheme) {
        Image(systemName: showingDark ? "sun.max" : "moon")
          .font(.system(size: 18))
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 44, height: 44)
          .background { RitmHeaderIconBackground() }
      }
      .buttonStyle(RitmPressStyle(scale: 0.9))
      .background { toggleFrameReader }
      .disabled(store.pendingTheme != nil)
      .accessibilityLabel(store.text("Переключить тему", "Switch appearance"))
    }
    .frame(height: 62)
  }
}

/// Last known frame of a view in window coordinates. Deliberately not observed: it moves with
/// scrolling and is only read at the moment of a tap.
@MainActor final class RitmFrameBox {
  var frame: CGRect = .zero
}

/// The pinned header's own backdrop: a bar gradient from the theme background over an
/// ultra-thin material, fading out below the bar, so content scrolling underneath never shows
/// crisp text behind the logo and the buttons (MOTION.md §7). It reaches up under the status bar.
private struct RitmHeaderBackdrop: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  private static let fade: CGFloat = 18

  var body: some View {
    ZStack {
      if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
      LinearGradient(
        colors: [
          RitmTheme.background.opacity(reduceTransparency ? 1 : 0.94),
          RitmTheme.background.opacity(reduceTransparency ? 1 : 0.8),
        ], startPoint: .top, endPoint: .bottom)
    }
    .mask {
      VStack(spacing: 0) {
        Rectangle()
        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
          .frame(height: Self.fade)
      }
    }
    .padding(.bottom, -Self.fade)
    .ignoresSafeArea(edges: .top)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// Motion of the bottom bar (prototype shell.html): the indicator slides in 0.28 s on
/// cubic-bezier(.2, .8, .2, 1); the «Ещё» panel inflates out of its icon in 0.30 s with a tiny
/// overshoot (cubic-bezier(.34, 1.32, .5, 1), about 3 %) and shrinks back in 0.18 s without one.
private enum RitmMore {
  static let slide = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
  static let inflate = Animation.timingCurve(0.34, 1.32, 0.5, 1, duration: 0.30)
  static let deflate = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)
  static let reduced = Animation.easeOut(duration: 0.12)
  /// Scale of the panel at the moment it leaves the icon.
  static let seed: CGFloat = 0.35
  /// Delay between neighbouring tiles when the panel opens.
  static let stagger = 0.04
}

/// Bounds of the «Ещё» slot in the bar, so the panel can be anchored right above it.
private struct RitmMoreAnchorKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}

/// Prototype bottom navigation: an icon-only glass capsule with four section slots and «Ещё»,
/// and one 56 × 42 indicator that slides between the slots.
private struct RitmNavigationBar: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  let sections: [RitmSection]
  let current: RitmSection
  let select: (RitmSection) -> Void
  let toggleMore: () -> Void

  private var moreSelected: Bool { RitmSection.moreSections.contains(current) }
  private var slotCount: Int { sections.count + 1 }
  private var selectedIndex: Int { sections.firstIndex(of: current) ?? sections.count }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(sections, id: \.self) { section in
        item(title: section.title(store), symbol: section.symbol, selected: current == section) {
          select(section)
        }
      }
      item(
        title: store.text("Ещё", "More"), symbol: "ellipsis", selected: moreSelected,
        value: moreSelected ? current.title(store) : "", action: toggleMore
      )
      .anchorPreference(key: RitmMoreAnchorKey.self, value: .bounds) { $0 }
    }
    .background {
      GeometryReader { proxy in
        let slot = proxy.size.width / CGFloat(slotCount)
        activeIndicator
          .frame(width: 56, height: 42)
          .frame(width: slot, height: proxy.size.height)
          .offset(x: slot * CGFloat(selectedIndex))
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .animation(reduceMotion ? nil : RitmMore.slide, value: selectedIndex)
    .padding(6)
    .background { capsule }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }

  private var capsule: some View {
    Capsule()
      .fill(reduceTransparency ? AnyShapeStyle(RitmTheme.panel) : AnyShapeStyle(.ultraThinMaterial))
      .overlay {
        if !reduceTransparency {
          Capsule().fill(
            RitmTheme.linear(
              [
                .init(
                  color: Color(
                    light: 0xFFFCFF, dark: 0x3B2D51, lightOpacity: 0.82, darkOpacity: 0.85),
                  location: 0),
                .init(
                  color: Color(
                    light: 0xE1D3F4, dark: 0x1F182D, lightOpacity: 0.65, darkOpacity: 0.76),
                  location: 1),
              ], cssAngle: 150))
          Capsule().fill(
            RitmTheme.linear(
              [.init(color: .white.opacity(0.16), location: 0), .init(color: .clear, location: 0.42)],
              cssAngle: 175))
        }
      }
      .overlay {
        Capsule().strokeBorder(
          contrast == .increased
            ? RitmTheme.text
            : Color(light: 0xFFFFFF, dark: 0xE5D3FC, lightOpacity: 0.76, darkOpacity: 0.3),
          lineWidth: 1)
      }
      .shadow(color: Color(rgb: 0x2C1848, opacity: 0.2), radius: 15, y: 12)
  }

  private func item(
    title: String, symbol: String, selected: Bool, value: String = "", action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .regular))
        .modifier(RitmIconSettle(active: selected))
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(
          contrast == .increased
            ? RitmTheme.text
            : selected
              ? Color(light: 0x643B96, dark: 0xE2CAFF) : Color(light: 0x645275, dark: 0xC1B3D4)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.92))
    .accessibilityLabel(title)
    .accessibilityValue(value)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var activeIndicator: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
    return shape
      .fill(
        RitmTheme.linear(
          [
            .init(
              color: Color(light: 0xA574DF, dark: 0xC299F1, lightOpacity: 0.24, darkOpacity: 0.28),
              location: 0),
            .init(
              color: Color(light: 0xC1A4E8, dark: 0x805CB1, lightOpacity: 0.14, darkOpacity: 0.2),
              location: 1),
          ], cssAngle: 145)
      )
      .overlay {
        shape.strokeBorder(
          Color(light: 0xFFFFFF, dark: 0xE5CDFF, lightOpacity: 0.64, darkOpacity: 0.24),
          lineWidth: 1)
      }
      .shadow(color: Color(rgb: 0x553086, opacity: 0.12), radius: 6, y: 4)
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

/// Speech-bubble outline: a rounded rectangle whose bottom edge carries a small tail at `tailX`.
private struct RitmBubble: Shape {
  static let tailHeight: CGFloat = 7
  static let radius: CGFloat = 22
  let tailX: CGFloat

  func path(in rect: CGRect) -> Path {
    let r = Self.radius
    let half = Self.tailHeight
    let bodyBottom = rect.maxY - Self.tailHeight
    let x = min(max(tailX, rect.minX + r + half), rect.maxX - r - half)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
      tangent2End: CGPoint(x: rect.maxX, y: bodyBottom), radius: r)
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: bodyBottom),
      tangent2End: CGPoint(x: x + half, y: bodyBottom), radius: r)
    path.addLine(to: CGPoint(x: x + half, y: bodyBottom))
    path.addLine(to: CGPoint(x: x, y: rect.maxY))
    path.addLine(to: CGPoint(x: x - half, y: bodyBottom))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: bodyBottom),
      tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.minY),
      tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
    path.closeSubpath()
    return path
  }
}

/// «Ещё»: a compact panel above the bar, its tail pointing at the «Ещё» slot. It stays in the
/// tree and animates (scale + fade from the tail) so it can also close smoothly.
private struct RitmMorePanel: View {
  private static let tileWidth: CGFloat = 108
  private static let padding: CGFloat = 10
  private static let spacing: CGFloat = 8
  private static let panelWidth = tileWidth * 2 + spacing + padding * 2

  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let isOpen: Bool
  let current: RitmSection
  let anchor: CGRect
  let container: CGSize
  let choose: (RitmSection) -> Void
  let dismiss: () -> Void

  private var barTop: CGFloat { anchor.minY - 6 }
  private var edgeInset: CGFloat { 16 }
  /// Tail position inside the panel, measured from its leading edge.
  private var tailX: CGFloat { Self.panelWidth - (container.width - edgeInset - anchor.midX) }
  /// Where the bubble actually draws its tail tip (it keeps clear of the rounded corners).
  private var tipX: CGFloat {
    let margin = RitmBubble.radius + RitmBubble.tailHeight
    return min(max(tailX, margin), Self.panelWidth - margin)
  }
  /// From the tail tip (the panel's bottom point) to the centre of the «Ещё» icon. Scaling the
  /// panel about the tip and shifting it by `(1 - scale)` of this vector is the same as scaling
  /// it about the icon, so the panel grows out of the icon without knowing its own height.
  private var inflateShift: CGSize {
    let leading = container.width - edgeInset - Self.panelWidth
    return CGSize(width: anchor.midX - (leading + tipX), height: anchor.midY - (barTop - 8))
  }

  private func tileMotion(_ index: Int) -> Animation? {
    guard !reduceMotion else { return nil }
    return isOpen
      ? Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)
        .delay(RitmMore.stagger * Double(index + 1))
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
        .padding(.bottom, max(0, container.height - barTop + 8))
    }
    .frame(width: container.width, height: container.height)
  }

  private var panel: some View {
    let scale = reduceMotion || isOpen ? 1 : RitmMore.seed
    return HStack(spacing: Self.spacing) {
      ForEach(Array(RitmSection.moreSections.enumerated()), id: \.element) { index, section in
        tile(section, index: index)
      }
    }
    .padding(Self.padding)
    .padding(.bottom, RitmBubble.tailHeight)
    .background {
      let bubble = RitmBubble(tailX: tailX)
      bubble.fill(RitmTheme.glassDense)
        .overlay { bubble.stroke(RitmTheme.panelBorder, lineWidth: 1) }
        .shadow(color: Color(rgb: 0x1A0D2D, opacity: 0.3), radius: 24, y: 12)
    }
    .scaleEffect(scale, anchor: UnitPoint(x: tipX / Self.panelWidth, y: 1))
    .offset(
      x: (1 - scale) * inflateShift.width, y: (1 - scale) * inflateShift.height)
    .opacity(isOpen ? 1 : 0)
    .allowsHitTesting(isOpen)
    .accessibilityHidden(!isOpen)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, dismiss)
  }

  private func tile(_ section: RitmSection, index: Int) -> some View {
    let selected = section == current
    let shown = reduceMotion || isOpen
    return Button {
      choose(section)
    } label: {
      VStack(spacing: 6) {
        Image(systemName: section.symbol)
          .font(.system(size: 22))
          .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
        Text(section.title(store))
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.text)
      .padding(.vertical, 8).padding(.horizontal, 6)
      .frame(width: Self.tileWidth)
      .frame(minHeight: 72)
      .background {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        shape.fill(selected ? RitmTheme.soft : RitmTheme.panel)
          .overlay {
            shape.strokeBorder(selected ? RitmTheme.accentColor : RitmTheme.line, lineWidth: 1)
          }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.95))
    .opacity(shown ? 1 : 0)
    .scaleEffect(shown ? 1 : 0.88)
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
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: store.timeZone)
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
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
        Image(systemName: "checkmark.circle")
        Text(store.text("Обновлено", "Updated") + " " + clock(date))
      } else {
        Image(systemName: "arrow.triangle.2.circlepath")
        Text(store.text("Ожидаем обновления", "Waiting to refresh"))
      }
    }
    .ritmText(.cardCaption).foregroundStyle(RitmTheme.muted).accessibilityElement(children: .combine)
  }
}
