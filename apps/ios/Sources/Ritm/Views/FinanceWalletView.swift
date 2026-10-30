import RitmCore
import SwiftUI

/// Motion of the card stack, from the owner's reference video: `timingCurve(0.2, 0.8, 0.2, 1)`.
enum FinanceMotion {
  static func curve(_ duration: Double) -> Animation {
    .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
  }
  static var open: Animation { curve(0.48) }
  static var close: Animation { curve(0.42) }
  static var snap: Animation { curve(0.34) }
  /// Delay between neighbouring cards when the stack fans out.
  static let stagger = 0.035
}

/// Where one card sits: its centre in the wallet area, its scale and opacity.
struct FinanceCardPlacement {
  let x: CGFloat
  let y: CGFloat
  let scale: CGFloat
  let opacity: Double
}

/// Pure geometry of the wallet. Every card has the same 85.6 : 54 face at the stack size; the
/// carousel only scales it, so a card is never stretched.
struct FinanceWalletMetrics {
  static let ratio: CGFloat = 54 / 85.6
  static let strip: CGFloat = 44
  static let maxStrips = 3
  static let topInset: CGFloat = 6
  static let bottomInset: CGFloat = 16
  static let neighbourScale: CGFloat = 0.92
  static let gap: CGFloat = 12
  static let depthScale: CGFloat = 0.045

  let width: CGFloat
  let count: Int

  var cardWidth: CGFloat { max(220, width - 32) }
  var cardHeight: CGFloat { cardWidth * Self.ratio }
  var strips: Int { min(max(count - 1, 0), Self.maxStrips) }
  var carouselWidth: CGFloat { min(300, cardWidth * 0.84) }
  var carouselScale: CGFloat { carouselWidth / cardWidth }
  /// Distance between the centres of the selected card and its neighbour.
  var pitch: CGFloat { carouselWidth * (1 + Self.neighbourScale) / 2 + Self.gap }
  var stackedHeight: CGFloat {
    Self.topInset + CGFloat(strips) * Self.strip + cardHeight + Self.bottomInset
  }
  var expandedHeight: CGFloat { Self.topInset + carouselWidth * Self.ratio + Self.bottomInset }

  func height(expanded: Bool) -> CGFloat { expanded ? expandedHeight : stackedHeight }

  /// `drag` is the live horizontal finger offset; the fractional card position follows it, so
  /// scale and spacing change continuously while dragging.
  func place(index: Int, selected: Int, expanded: Bool, drag: CGFloat) -> FinanceCardPlacement {
    if expanded {
      let offset = CGFloat(index - selected) + drag / pitch
      let near = min(1, abs(offset))
      return FinanceCardPlacement(
        x: width / 2 + offset * pitch,
        y: Self.topInset + carouselWidth * Self.ratio / 2,
        scale: carouselScale * (1 - (1 - Self.neighbourScale) * near),
        opacity: 1)
    }
    let depth = min(index, strips)
    let scale = 1 - Self.depthScale * CGFloat(depth)
    let top = Self.topInset + CGFloat(strips - depth) * Self.strip
    return FinanceCardPlacement(
      x: width / 2, y: top + cardHeight * scale / 2, scale: scale,
      opacity: index > strips ? 0 : 1)
  }
}

// MARK: - Card face

struct FinanceCardStyle {
  let colors: [Color]
  let glow: Color
  let symbol: String

  /// A card's gradient stops, the same in light and dark (the card is a dark object on both
  /// backgrounds). Colours follow the prototype tokens `--k-*`; the glow is their light tint.
  private static func palette(_ theme: FinanceCardTheme) -> (UInt32, UInt32, UInt32, UInt32) {
    switch theme {
    case .violet: (0x55309F, 0x6D46C2, 0x8860DA, 0xDDB9FF)
    case .indigo: (0x263891, 0x4058BD, 0x5E78E0, 0xBCC8FF)
    case .plum: (0x66217F, 0x96418F, 0xBB5FA8, 0xF0B8F2)
    case .teal: (0x08505A, 0x1C7D6E, 0x2C9580, 0xA8F0E0)
    case .graphite: (0x232F48, 0x44588A, 0x6279AE, 0xB9C7E8)
    case .rose: (0x7D1F45, 0xAE3F6B, 0xCF6A8F, 0xFFC0D4)
    case .sand: (0x6B4A22, 0x97702F, 0xB88B49, 0xF2D9A8)
    case .forest: (0x123F28, 0x236A46, 0x388A5C, 0xB0EBC6)
    }
  }

  private static func symbol(_ kind: FinanceCard.Kind) -> String {
    switch kind {
    case .account: "wallet.pass"
    case .deposit: "building.columns"
    case .stocks: "chart.line.uptrend.xyaxis"
    }
  }

  static func style(theme: FinanceCardTheme, kind: FinanceCard.Kind) -> FinanceCardStyle {
    let p = palette(theme)
    return FinanceCardStyle(
      colors: [Color(rgb: p.0), Color(rgb: p.1), Color(rgb: p.2)], glow: Color(rgb: p.3),
      symbol: symbol(kind))
  }

  /// The swatch and mini-preview fill: the card gradient at the prototype's 140 degrees.
  var gradient: LinearGradient {
    RitmTheme.linear(
      [
        .init(color: colors[0], location: 0), .init(color: colors[1], location: 0.6),
        .init(color: colors[2], location: 1),
      ], cssAngle: 140)
  }
}

private struct FinanceCardWave: Shape {
  let variant: Int
  let closed: Bool

  func path(in rect: CGRect) -> Path {
    let w = rect.width
    let h = rect.height
    var path = Path()
    if variant == 0 {
      path.move(to: CGPoint(x: 0, y: h * 0.96))
      path.addCurve(
        to: CGPoint(x: w, y: h * 0.26), control1: CGPoint(x: w * 0.42, y: h * 1.04),
        control2: CGPoint(x: w * 0.62, y: h * 0.42))
    } else {
      path.move(to: CGPoint(x: 0, y: h * 1.1))
      path.addCurve(
        to: CGPoint(x: w, y: h * 0.64), control1: CGPoint(x: w * 0.36, y: h * 1.06),
        control2: CGPoint(x: w * 0.7, y: h * 0.8))
    }
    if closed {
      path.addLine(to: CGPoint(x: w, y: h))
      path.addLine(to: CGPoint(x: 0, y: h))
      path.closeSubpath()
    }
    return path
  }
}

/// One card: gradient, soft wave lines, name, balance and an icon tile. `compact` is the stacked
/// strip (name and balance on one line); `selected` adds the glow and the check badge.
struct FinanceCardFace: View {
  let name: String
  let balance: String
  let caption: String
  let style: FinanceCardStyle
  let compact: Bool
  let selected: Bool
  let width: CGFloat

  private let ink = Color(rgb: 0xF8F3FF)
  private let label = Color(rgb: 0xE1D3EE)

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    ZStack(alignment: .topLeading) {
      shape.fill(
        RitmTheme.linear(
          [
            .init(color: style.colors[0], location: 0),
            .init(color: style.colors[1], location: 0.64),
            .init(color: style.colors[2], location: 1),
          ], cssAngle: 139))
      CornerGlow(color: style.glow.opacity(0.32), x: 0.94, y: 0, reach: 0.5)
      FinanceCardWave(variant: 0, closed: true).fill(Color.white.opacity(0.05))
      FinanceCardWave(variant: 1, closed: true).fill(Color.white.opacity(0.06))
      FinanceCardWave(variant: 0, closed: false).stroke(Color.white.opacity(0.2), lineWidth: 1.2)
      FinanceCardWave(variant: 1, closed: false).stroke(Color.white.opacity(0.14), lineWidth: 1)
      content
    }
    .frame(width: width, height: width * FinanceWalletMetrics.ratio)
    .clipShape(shape)
    .overlay { shape.strokeBorder(Color(rgb: 0xDABCFC, opacity: 0.32), lineWidth: 1) }
    .overlay(alignment: .topTrailing) { badge }
    .shadow(
      color: selected ? style.glow.opacity(0.5) : Color(rgb: 0x1A0D2D, opacity: 0.24),
      radius: selected ? 20 : 10, y: selected ? 10 : 6)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(name)
          .ritmFont(15, weight: .medium)
          .foregroundStyle(label)
          .lineLimit(1)
          .padding(.trailing, compact ? 0 : 40)
        Spacer(minLength: 0)
        Text(balance)
          .ritmFont(15, weight: .semibold)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .opacity(compact ? 1 : 0)
      }
      Text(balance)
        .ritmFont(32, weight: .semibold, tracking: -0.055)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.top, 8)
        .opacity(compact ? 0 : 1)
      Spacer(minLength: 0)
      HStack(alignment: .bottom) {
        Image(systemName: style.symbol)
          .font(.system(size: 22, weight: .regular))
          .frame(width: 52, height: 52)
          .background(Circle().fill(Color.white.opacity(0.13)))
        Spacer(minLength: 8)
        Text(caption).ritmFont(11, weight: .medium).foregroundStyle(label).lineLimit(1)
      }
    }
    .foregroundStyle(ink)
    .padding(.horizontal, 20)
    .padding(.top, 14)
    .padding(.bottom, 18)
  }

  private var badge: some View {
    Image(systemName: "checkmark")
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(ink)
      .frame(width: 30, height: 30)
      .background(Circle().fill(Color.white.opacity(0.2)))
      .overlay { Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1) }
      .padding(14)
      .opacity(selected ? 1 : 0)
      .scaleEffect(selected ? 1 : 0.6)
  }
}

// MARK: - Wallet

private enum FinanceDragLock { case open, horizontal, vertical }

/// The Apple-Wallet-style stack that opens into a horizontal carousel. One `ForEach` over the
/// cards with stable ids: each card's centre, scale and opacity are computed from the state
/// (stacked or expanded, selected index, live drag), so there are no clones to hide afterwards.
struct FinanceWalletView: View {
  /// In the owner's order.
  let cards: [FinanceCard]
  /// Card id -> theme, resolved by the caller from the default order.
  let themes: [String: FinanceCardTheme]
  let format: FinanceFormat
  @Binding var expanded: Bool
  @Binding var selectedID: String
  /// True while a horizontal drag owns the touch, so the page can stop scrolling.
  @Binding var dragging: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var width: CGFloat = 390
  @State private var drag: CGFloat = 0
  @State private var lock: FinanceDragLock = .open
  @GestureState private var touching = false
  /// Set once a drag has been recognised and cleared shortly after the finger lifts, so the
  /// release of a drag is never taken for a tap on a card.
  @State private var dragMoved = false
  @State private var hintSeen = UserDefaults.standard.bool(forKey: FinanceWalletView.hintKey)

  /// The caption under the dots disappears for good after the first collapse.
  private static let hintKey = "ritm.finance.collapseHintSeen"

  private var selectedIndex: Int {
    cards.firstIndex(where: { $0.id == selectedID }) ?? 0
  }

  var body: some View {
    let metrics = FinanceWalletMetrics(width: width, count: cards.count)
    let selected = selectedIndex
    return VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
          cardView(card, index: index, selected: selected, metrics: metrics)
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(height: metrics.height(expanded: expanded), alignment: .topLeading)
      .clipped()
      .background { widthProbe }
      .contentShape(Rectangle())
      .simultaneousGesture(swipe(metrics, selected: selected))
      footer
    }
    .sensoryFeedback(.selection, trigger: selectedID)
    .onChange(of: touching) { _, isTouching in
      guard !isTouching else { return }
      // A cancelled drag never reaches onEnded; a finished one has already reset the lock.
      Task { @MainActor in
        clearDragMark()
        guard lock != .open else { return }
        lock = .open
        dragging = false
        withAnimation(reduceMotion ? nil : FinanceMotion.snap) { drag = 0 }
      }
    }
    .onChange(of: expanded) { was, now in
      // The first collapse teaches the gesture; the caption stays away afterwards.
      guard was, !now, !hintSeen else { return }
      hintSeen = true
      UserDefaults.standard.set(true, forKey: Self.hintKey)
    }
  }

  /// A drag that just ended must not also count as a tap: the mark outlives the lift by a beat.
  private func clearDragMark() {
    guard dragMoved else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      dragMoved = false
    }
  }

  private var widthProbe: some View {
    GeometryReader { proxy in
      Color.clear
        .onAppear { if proxy.size.width > 0 { width = proxy.size.width } }
        .onChange(of: proxy.size.width) { _, value in if value > 0 { width = value } }
    }
  }

  // MARK: Cards

  private func balanceText(_ card: FinanceCard) -> String {
    card.balanceMinor.map { format.money($0, card.currency) } ?? "—"
  }

  private func caption(_ card: FinanceCard) -> String {
    switch card.kind {
    case .account: card.currency.rawValue
    case .deposit: format.text("Депозит", "Deposit") + " · " + card.currency.rawValue
    case .stocks: format.text("Портфель", "Portfolio") + " · " + card.currency.rawValue
    }
  }

  /// The stack fans out from the chosen card (35 ms per step) and folds back in reverse.
  private func moveAnimation(index: Int, selected: Int) -> Animation {
    let step = Double(min(abs(index - selected), 3))
    if expanded {
      let delay = FinanceMotion.stagger * step
      return FinanceMotion.curve(0.48 - delay).delay(delay)
    }
    let delay = 0.03 * (3 - step)
    return FinanceMotion.curve(0.42 - delay).delay(delay)
  }

  private func cardView(
    _ card: FinanceCard, index: Int, selected: Int, metrics: FinanceWalletMetrics
  ) -> some View {
    let place = metrics.place(index: index, selected: selected, expanded: expanded, drag: drag)
    let current = expanded && index == selected
    let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    return FinanceCardFace(
      name: format.name(card), balance: balanceText(card), caption: caption(card),
      style: FinanceCardStyle.style(theme: themes[card.id] ?? .violet, kind: card.kind),
      compact: !expanded && index > 0, selected: current, width: metrics.cardWidth
    )
    .contentShape(shape)
    .onTapGesture { tap(index) }
    .scaleEffect(place.scale)
    .offset(
      x: place.x - metrics.cardWidth / 2, y: place.y - metrics.cardHeight / 2
    )
    .opacity(place.opacity)
    .allowsHitTesting(place.opacity > 0.01)
    .zIndex(Double(cards.count - index))
    .animation(reduceMotion ? nil : moveAnimation(index: index, selected: selected), value: expanded)
    .animation(reduceMotion ? nil : FinanceMotion.snap, value: cards.map(\.id))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(format.name(card) + ", " + balanceText(card))
    .accessibilityHint(tapHint(index: index))
    .accessibilityAction(named: Text(tapHint(index: index))) { tap(index, fromGesture: false) }
    .accessibilityAddTraits(current ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
    .accessibilityHidden(place.opacity < 0.01)
  }

  /// What a tap on this card does: open the stack, collapse it, or move the carousel here.
  private func tapHint(index: Int) -> String {
    guard expanded else { return format.text("Раскрыть карты", "Open the cards") }
    return index == selectedIndex
      ? format.text("Свернуть карты", "Collapse the cards")
      : format.text("Выбрать счёт", "Select account")
  }

  /// Stacked: any card opens the carousel on itself. Carousel: the centred card collapses it,
  /// a neighbour moves to the centre without collapsing. The release of a drag is not a tap.
  private func tap(_ index: Int, fromGesture: Bool = true) {
    guard cards.indices.contains(index), !(fromGesture && dragMoved) else { return }
    if expanded {
      if index == selectedIndex {
        withAnimation(reduceMotion ? nil : FinanceMotion.close) { expanded = false }
      } else {
        snap(to: index)
      }
    } else {
      withAnimation(reduceMotion ? nil : FinanceMotion.open) {
        selectedID = cards[index].id
        expanded = true
      }
    }
  }

  private func snap(to index: Int) {
    guard cards.indices.contains(index) else { return }
    withAnimation(reduceMotion ? nil : FinanceMotion.snap) {
      selectedID = cards[index].id
      drag = 0
    }
  }

  // MARK: Gesture

  /// A horizontal drag moves the carousel; the axis is locked on the first ~10 pt, so a
  /// vertical drag is left to the page scroll.
  private func swipe(_ metrics: FinanceWalletMetrics, selected: Int) -> some Gesture {
    DragGesture(minimumDistance: 10)
      .updating($touching) { _, state, _ in state = true }
      .onChanged { value in
        if !dragMoved { dragMoved = true }
        guard expanded, cards.count > 1 else { return }
        if lock == .open {
          lock =
            abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
        }
        guard lock == .horizontal else { return }
        if !dragging { dragging = true }
        drag = resisted(value.translation.width, selected: selected, pitch: metrics.pitch)
      }
      .onEnded { value in
        finish(value, metrics: metrics, selected: selected)
        clearDragMark()
      }
  }

  /// Edges pull back like a rubber band; one drag never moves more than one card.
  private func resisted(_ dx: CGFloat, selected: Int, pitch: CGFloat) -> CGFloat {
    let blocked = (selected == 0 && dx > 0) || (selected == cards.count - 1 && dx < 0)
    return max(-pitch, min(pitch, blocked ? dx * 0.3 : dx))
  }

  /// Snap by distance (18 % of the card) or by a flick (a fraction of the predicted run-out).
  private func finish(_ value: DragGesture.Value, metrics: FinanceWalletMetrics, selected: Int) {
    defer {
      lock = .open
      dragging = false
    }
    guard lock == .horizontal else { return }
    let travel = value.translation.width
    let momentum = value.predictedEndTranslation.width - travel
    let intent = travel + momentum * 0.4
    var target = selected
    if abs(intent) > metrics.carouselWidth * 0.18 { target += intent < 0 ? 1 : -1 }
    snap(to: min(max(target, 0), cards.count - 1))
  }

  // MARK: Footer

  /// Only the open carousel has a footer: the dots and, until the first collapse, a caption.
  /// The stack itself is opened and closed by tapping a card.
  @ViewBuilder private var footer: some View {
    if expanded {
      VStack(spacing: 0) {
        if cards.count > 1 { dots }
        if !hintSeen { collapseHint }
      }
      .transition(.opacity)
    }
  }

  private var collapseHint: some View {
    Text(format.text("Нажмите на карту, чтобы свернуть", "Tap a card to collapse"))
      .ritmFont(11)
      .foregroundStyle(RitmTheme.muted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 16)
      .padding(.bottom, 4)
      .transition(.opacity)
      .accessibilityHidden(true)
  }

  private var dots: some View {
    HStack(spacing: 0) {
      ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
        let active = index == selectedIndex
        Button {
          snap(to: index)
        } label: {
          Capsule()
            .fill(active ? RitmTheme.accentColor : RitmTheme.accentColor.opacity(0.28))
            .frame(width: active ? 18 : 6, height: 6)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(format.name(card))
        .accessibilityAddTraits(active ? .isSelected : [])
      }
    }
    .frame(maxWidth: .infinity)
    .animation(reduceMotion ? nil : FinanceMotion.snap, value: selectedID)
  }
}

/// The 48 pt «Настроить карты» icon button in the page heading.
struct FinanceCustomizeButton: View {
  let format: FinanceFormat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "slider.horizontal.3")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 48, height: 48)
        .ritmGlass(in: Circle(), interactive: true)
        .contentShape(Circle())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(format.text("Настроить карты", "Customize cards"))
  }
}
