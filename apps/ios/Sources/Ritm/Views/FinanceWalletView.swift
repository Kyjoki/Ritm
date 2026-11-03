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
  static let stagger = 0.03
}

/// Where one card sits: its top-centre offset, scale, z-order and how much it is dimmed.
struct FinanceCardPlacement {
  let x: CGFloat
  let y: CGFloat
  let scale: CGFloat
  let z: Double
  let dim: Double
}

/// Pure geometry of the wallet (finance.js `stackGeom` / `carouselGeom`). Every card is 350 pt
/// wide with the 85.6 : 54 face; cards scale about their top edge. The stack shows a 44 pt
/// strip of every card behind the selected one, the carousel scales neighbours to 92 %.
struct FinanceWalletMetrics {
  static let ratio: CGFloat = 54 / 85.6
  static let strip: CGFloat = 44
  static let neighbourScale: CGFloat = 0.92
  static let gap: CGFloat = 12
  static let carouselTop: CGFloat = 12
  static let stackBottom: CGFloat = 16
  /// The prototype screen is 390 pt wide; the 350 pt cards are laid out in it, centred.
  static let designWidth: CGFloat = 390

  let width: CGFloat
  let count: Int

  var cardWidth: CGFloat { max(220, min(350, width - 40)) }
  var cardHeight: CGFloat { cardWidth * Self.ratio }
  /// The centred card of the carousel is 300 pt wide on a 350 pt card.
  var carouselWidth: CGFloat { cardWidth * 300 / 350 }
  var carouselScale: CGFloat { carouselWidth / cardWidth }
  /// Distance between the centres of the selected card and its neighbour.
  var pitch: CGFloat { carouselWidth / 2 + Self.gap + carouselWidth * Self.neighbourScale / 2 }
  private var rowWidth: CGFloat { carouselWidth * Self.neighbourScale + Self.gap }

  var stackedHeight: CGFloat {
    (CGFloat(max(count, 1) - 1) * Self.strip + cardHeight + Self.stackBottom).rounded()
  }
  /// Cards, then 6 pt, the 44 pt dots and 22 pt of caption room.
  var expandedHeight: CGFloat {
    (Self.carouselTop + cardHeight * carouselScale + 6 + 44 + 22).rounded()
  }

  func height(expanded: Bool) -> CGFloat { expanded ? expandedHeight : stackedHeight }

  /// `drag` is the live horizontal finger offset; the fractional card position follows it, so
  /// scale and spacing change continuously while dragging.
  func place(index: Int, selected: Int, expanded: Bool, drag: CGFloat) -> FinanceCardPlacement {
    if expanded {
      let offset = CGFloat(index - selected) + drag / pitch
      let near = abs(offset)
      let scale = carouselScale * (1 - (1 - Self.neighbourScale) * min(near, 1))
      let x = near <= 1 ? offset * pitch : (offset < 0 ? -1 : 1) * (pitch + (near - 1) * rowWidth)
      return FinanceCardPlacement(
        x: x, y: Self.carouselTop + cardHeight * (carouselScale - scale) / 2, scale: scale,
        z: 100 - (near * 10).rounded(), dim: 0.14 * Double(min(near, 1)))
    }
    let depth = index == selected ? 0 : (index < selected ? index + 1 : index)
    return FinanceCardPlacement(
      x: 0, y: CGFloat(count - 1 - depth) * Self.strip, scale: 1 - 0.04 * CGFloat(depth),
      z: Double(count - depth), dim: 0.035 * Double(depth))
  }
}

// MARK: - Card face

struct FinanceCardStyle {
  let colors: [Color]
  let glow: Color
  let symbol: String

  /// A card's gradient stops (`--k-*`) and glow (`--kg-*`), the same in light and dark.
  private static func palette(_ theme: FinanceCardTheme) -> (UInt32, UInt32, UInt32, UInt32, Double) {
    switch theme {
    case .violet: (0x55309F, 0x6D46C2, 0x8860DA, 0x7B52D0, 0.55)
    case .indigo: (0x263891, 0x4058BD, 0x5E78E0, 0x4A63CC, 0.55)
    case .plum: (0x66217F, 0x96418F, 0xBB5FA8, 0xA0489A, 0.5)
    case .teal: (0x08505A, 0x1C7D6E, 0x2C9580, 0x2A9684, 0.5)
    case .graphite: (0x232F48, 0x44588A, 0x6279AE, 0x4E6592, 0.55)
    case .rose: (0x7D1F45, 0xAE3F6B, 0xCF6A8F, 0xBE4B73, 0.5)
    case .sand: (0x6B4A22, 0x97702F, 0xB88B49, 0xAA7D3C, 0.5)
    case .forest: (0x123F28, 0x236A46, 0x388A5C, 0x32875A, 0.5)
    }
  }

  private static func symbol(
    _ kind: FinanceCard.Kind, _ currency: FinanceCurrency, plain: Bool
  ) -> String {
    switch kind {
    case .account: currency == .KZT ? "wallet.bifold" : "dollarsign"
    case .deposit: plain ? "wallet.bifold" : "dollarsign.circle"
    case .stocks: "chart.line.uptrend.xyaxis"
    }
  }

  static func style(
    theme: FinanceCardTheme, kind: FinanceCard.Kind, currency: FinanceCurrency = .KZT,
    plain: Bool = false
  ) -> FinanceCardStyle {
    let p = palette(theme)
    return FinanceCardStyle(
      colors: [Color(rgb: p.0), Color(rgb: p.1), Color(rgb: p.2)],
      glow: Color(rgb: p.3, opacity: p.4), symbol: symbol(kind, currency, plain: plain))
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

/// The two wave lines and the soft fill of a card, drawn in the prototype's 350 x 221 box.
private struct FinanceCardWave: Shape {
  enum Part { case fill, lineA, lineB }
  let odd: Bool
  let part: Part

  func path(in rect: CGRect) -> Path {
    let sx = rect.width / 350
    let sy = rect.height / 221
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
    var path = Path()
    switch (odd, part) {
    case (false, .lineA):
      path.move(to: p(-10, 190))
      path.addCurve(to: p(215, 105), control1: p(80, 190), control2: p(150, 150))
      path.addCurve(to: p(360, 20), control1: p(280, 60), control2: p(320, 30))
    case (false, .lineB):
      path.move(to: p(-10, 215))
      path.addCurve(to: p(230, 140), control1: p(90, 215), control2: p(160, 180))
      path.addCurve(to: p(360, 70), control1: p(300, 100), control2: p(330, 80))
    case (false, .fill):
      path.move(to: p(-10, 221))
      path.addLine(to: p(-10, 205))
      path.addCurve(to: p(245, 120), control1: p(90, 205), control2: p(170, 170))
      path.addCurve(to: p(360, 60), control1: p(320, 70), control2: p(330, 70))
      path.addLine(to: p(360, 221))
      path.closeSubpath()
    case (true, .lineA):
      path.move(to: p(-10, 150))
      path.addCurve(to: p(190, 170), control1: p(60, 120), control2: p(120, 190))
      path.addCurve(to: p(360, 110), control1: p(260, 150), control2: p(300, 90))
    case (true, .lineB):
      path.move(to: p(-10, 182))
      path.addCurve(to: p(200, 196), control1: p(70, 152), control2: p(130, 212))
      path.addCurve(to: p(360, 142), control1: p(270, 180), control2: p(310, 122))
    case (true, .fill):
      path.move(to: p(-10, 221))
      path.addLine(to: p(-10, 175))
      path.addCurve(to: p(200, 188), control1: p(70, 150), control2: p(130, 205))
      path.addCurve(to: p(360, 135), control1: p(270, 171), control2: p(310, 115))
      path.addLine(to: p(360, 221))
      path.closeSubpath()
    }
    return path
  }
}

/// One card (`.card`): gradient, top-right sheen, wave lines, the face (name, balance, icon,
/// currency) and the one-line strip that replaces the face when the card sits behind others.
struct FinanceCardFace: View {
  let name: String
  /// Optional second line under the name (the masked number, a deposit or portfolio note).
  let subtitle: String?
  let balance: String
  let meta: String
  let style: FinanceCardStyle
  let compact: Bool
  let selected: Bool
  let width: CGFloat
  /// 0...1 black overlay, the prototype's `filter: brightness()` for cards behind the front one.
  var dim: Double = 0
  var odd = false

  private let onCard2 = Color.white.opacity(0.84)

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    let height = width * FinanceWalletMetrics.ratio
    ZStack(alignment: .topLeading) {
      shape.fill(style.gradient)
      shape.fill(
        RadialGradient(
          colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
          center: UnitPoint(x: 0.94, y: 0), startRadius: 0,
          endRadius: 0.46 * hypot(0.94 * width, height)))
      FinanceCardWave(odd: odd, part: .fill).fill(Color.white.opacity(0.1))
      FinanceCardWave(odd: odd, part: .lineA).stroke(Color.white.opacity(0.34), lineWidth: 1.3)
      FinanceCardWave(odd: odd, part: .lineB).stroke(Color.white.opacity(0.34), lineWidth: 1.3)
      face.opacity(compact ? 0 : 1)
      strip.opacity(compact ? 1 : 0)
      Color.black.opacity(dim)
    }
    .frame(width: width, height: height)
    .clipShape(shape)
    .overlay { shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1) }
    .overlay(alignment: .topTrailing) { badge }
    .background {
      shape.fill(style.colors[1])
        .shadow(
          color: selected ? style.glow : Color.black.opacity(0.3), radius: selected ? 20 : 11,
          y: selected ? 16 : 10)
    }
    .foregroundStyle(Color.white)
    .animation(.easeOut(duration: 0.22), value: compact)
  }

  private var face: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 1) {
        Text(name)
          .ritmFont(17, weight: .semibold, tracking: -0.04)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle).ritmFont(12).foregroundStyle(onCard2).lineLimit(1)
        }
      }
      .padding(.trailing, 40)
      Text(balance)
        .ritmFont(32, weight: .bold, tracking: -0.055)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.top, 10)
      Spacer(minLength: 0)
      HStack(alignment: .center) {
        RitmSymbol(style.symbol)
          .font(.system(size: 24, weight: .regular))
          .frame(width: 50, height: 50)
          .background(Circle().fill(Color.white.opacity(0.2)))
        Spacer(minLength: 8)
        Text(meta).ritmFont(11.5, weight: .medium).foregroundStyle(onCard2).lineLimit(1)
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var strip: some View {
    HStack(spacing: 10) {
      Text(name).ritmFont(15, weight: .semibold, tracking: -0.02).lineLimit(1)
      Spacer(minLength: 0)
      Text(balance)
        .ritmFont(15, weight: .semibold)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .padding(.horizontal, 22)
    .frame(height: FinanceWalletMetrics.strip)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  /// `.check`: a white 28 pt disc with a violet tick that pops in on the chosen carousel card.
  private var badge: some View {
    RitmSymbol("checkmark")
      .font(.system(size: 14, weight: .heavy))
      .foregroundStyle(Color(rgb: 0x5C37B0))
      .frame(width: 28, height: 28)
      .background(Circle().fill(Color.white))
      .padding(14)
      .scaleEffect(selected ? 1 : 0.2)
      .opacity(selected ? 1 : 0)
      .animation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.32).delay(selected ? 0.22 : 0), value: selected)
  }
}

/// Screen-reader behaviour of one card: a button that says what a tap does.
private struct FinanceCardAccessibility: ViewModifier {
  let label: String
  let hint: String
  let current: Bool
  let activate: () -> Void

  func body(content: Content) -> some View {
    content
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(label)
      .accessibilityHint(hint)
      .accessibilityAction(named: Text(hint), activate)
      .accessibilityAddTraits(current ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
  }
}

// MARK: - Wallet

private enum FinanceDragLock { case open, horizontal, vertical }

/// The Apple-Wallet-style stack that opens into a horizontal carousel. One `ForEach` over the
/// cards with stable ids: each card's offset, scale and dimming are computed from the state
/// (stacked or expanded, selected index, live drag), so there are no clones to hide afterwards.
struct FinanceWalletView: View {
  /// In the owner's order.
  let cards: [FinanceCard]
  /// Card id -> theme, resolved by the caller from the default order.
  let themes: [String: FinanceCardTheme]
  let format: FinanceFormat
  /// Ids of extra accounts the owner calls «Счёт» rather than «Депозит».
  var plainIDs: Set<String> = []
  @Binding var expanded: Bool
  @Binding var selectedID: String
  /// True while a horizontal drag owns the touch, so the page can stop scrolling.
  @Binding var dragging: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    let metrics = FinanceWalletMetrics(width: FinanceWalletMetrics.designWidth, count: cards.count)
    let selected = selectedIndex
    return ZStack(alignment: .top) {
      ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
        cardView(card, index: index, selected: selected, metrics: metrics)
      }
      footer
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .frame(height: metrics.height(expanded: expanded), alignment: .top)
    .contentShape(Rectangle())
    .simultaneousGesture(swipe(metrics, selected: selected))
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

  // MARK: Cards

  private func balanceText(_ card: FinanceCard) -> String {
    card.balanceMinor.map { format.money($0, card.currency) } ?? "—"
  }

  /// `KZT · тенге`, `USD · доллар`: the currency label at the bottom right of the face.
  private func meta(_ card: FinanceCard) -> String {
    switch card.currency {
    case .KZT: format.text("KZT · тенге", "KZT · tenge")
    case .USD: format.text("USD · доллар", "USD · dollar")
    case .EUR: format.text("EUR · евро", "EUR · euro")
    case .RUB: format.text("RUB · рубль", "RUB · ruble")
    }
  }

  /// The card data has no masked number or rate, so only the asset kind gets a second line.
  private func subtitle(_ card: FinanceCard) -> String? {
    switch card.kind {
    case .account: nil
    case .deposit: plainIDs.contains(card.id) ? nil : format.text("Депозит", "Deposit")
    case .stocks: format.text("Портфель акций", "Stock portfolio")
    }
  }

  /// The stack fans out from the chosen card (30 ms per step) and folds back in reverse.
  private func moveAnimation(index: Int, selected: Int) -> Animation {
    let step = Double(abs(index - selected))
    if expanded {
      let delay = FinanceMotion.stagger * step
      return FinanceMotion.curve(0.38).delay(delay)
    }
    let maxStep = Double(max(selected, cards.count - 1 - selected))
    let delay = 0.025 * (maxStep - step)
    return FinanceMotion.curve(0.34).delay(delay)
  }

  private func cardView(
    _ card: FinanceCard, index: Int, selected: Int, metrics: FinanceWalletMetrics
  ) -> some View {
    let place = metrics.place(index: index, selected: selected, expanded: expanded, drag: drag)
    let current = expanded && index == selected
    let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    let order = cards.map { $0.id }
    return FinanceCardFace(
      name: format.name(card), subtitle: subtitle(card), balance: balanceText(card),
      meta: meta(card),
      style: FinanceCardStyle.style(
        theme: themes[card.id] ?? .violet, kind: card.kind, currency: card.currency,
        plain: plainIDs.contains(card.id)),
      compact: !expanded && index != selected, selected: current, width: metrics.cardWidth,
      dim: place.dim, odd: index % 2 == 1
    )
    .contentShape(shape)
    .onTapGesture { tap(index) }
    .scaleEffect(place.scale, anchor: .top)
    .offset(x: place.x, y: place.y)
    .zIndex(place.z)
    .animation(reduceMotion ? nil : moveAnimation(index: index, selected: selected), value: expanded)
    .animation(reduceMotion ? nil : FinanceMotion.snap, value: order)
    .modifier(
      FinanceCardAccessibility(
        label: format.name(card) + ", " + balanceText(card), hint: tapHint(index: index),
        current: current
      ) { tap(index, fromGesture: false) })
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
    return max(-pitch, min(pitch, blocked ? dx * 0.35 : dx))
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

  /// Only the open carousel has a footer: the dots (44 pt tall, 22 pt from the bottom) and,
  /// until the first collapse, a caption at 4 pt.
  @ViewBuilder private var footer: some View {
    ZStack(alignment: .bottom) {
      dots.padding(.bottom, 22)
      collapseHint.padding(.bottom, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .opacity(expanded ? 1 : 0)
    .allowsHitTesting(expanded)
    .accessibilityHidden(!expanded)
    .zIndex(1000)
  }

  private var collapseHint: some View {
    Text(format.text("Нажмите на карту, чтобы свернуть", "Tap a card to collapse"))
      .ritmFont(11)
      .foregroundStyle(RitmTheme.muted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .frame(height: 14)
      .opacity(hintSeen ? 0 : 1)
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
            .fill(active ? RitmTheme.accentColor : Color(light: 0xE8DDF5, dark: 0x3B2D50))
            .frame(width: active ? 20 : 7, height: 7)
            .frame(width: 26, height: 44)
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

/// The 44 pt «Настроить карты» icon button in the page heading.
struct FinanceCustomizeButton: View {
  let format: FinanceFormat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RitmSymbol("slider.horizontal.3")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 44, height: 44)
        .ritmGlass(in: Circle(), interactive: true)
        .contentShape(Circle())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(format.text("Настроить карты", "Customize cards"))
  }
}
