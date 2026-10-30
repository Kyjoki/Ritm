import SwiftUI

// The three overview cards at the top of «Мой день» (DashboardPage.tsx .overview-grid) as they
// stack on a phone: app.css and visual-refresh.css at max-width 760 px.

struct DayProgressCard: View {
  let progress: Double
  let value: String
  /// «3 из 5»: when set, the completed number counts up inside the value text.
  var tally: (completed: Int, total: Int)?
  let caption: String
  let rhythm: [Double]
  let footnote: String
  @Environment(RitmStore.self) private var store

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Твой прогресс", "Your progress"))
        .ritmFont(10, weight: .medium)
        .foregroundStyle(RitmTheme.muted)
      HStack(spacing: 15) {
        DayProgressRing(progress: progress)
        VStack(alignment: .leading, spacing: 5) {
          valueText
            .ritmFont(25, weight: .semibold, tracking: -0.05)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
            .foregroundStyle(RitmTheme.text)
          Text(caption).ritmFont(9).foregroundStyle(RitmTheme.muted)
        }
      }
      .padding(.top, 12)
      .accessibilityElement(children: .combine)
      DayRhythmChart(values: rhythm).padding(.top, 8)
      Text(footnote)
        .ritmFont(10)
        .foregroundStyle(RitmTheme.muted)
        .padding(.top, 10)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
    .background {
      // Only the glow is clipped, so the panel keeps its shadow.
      RitmPanelBackground(raised: true)
        .overlay {
          CornerGlow(color: Color(rgb: 0xAF87E5, opacity: 0.34), x: 0.9, y: 0.02, reach: 0.42)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .circular))
        }
    }
    .ritmPageReveal(index: 0)
  }

  /// The value text; «3 из 5» counts its first number, every other state stays static.
  @ViewBuilder private var valueText: some View {
    if let tally {
      RitmCountText(tally.completed) { done in
        store.text("\(done) из \(tally.total)", "\(done) of \(tally.total)")
      }
    } else {
      Text(value)
    }
  }
}

/// `.progress-ring` on a phone: 55 pt conic ring, 5 pt thick, over the panel colour.
private struct DayProgressRing: View {
  let progress: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // The sweep plays once per page visit; later progress changes animate from the old arc.
    RitmDrawGate(key: 0) { drawn in
      ZStack {
        Circle().fill(RitmTheme.ringTrack)
        Circle()
          .trim(from: 0, to: drawn ? max(0, min(1, progress)) : 0)
          .stroke(RitmTheme.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
          .rotationEffect(.degrees(-90))
          .padding(2.5)
          .animation(reduceMotion ? nil : RitmMotion.sweep, value: drawn)
          .animation(reduceMotion ? nil : RitmMotion.easeOut(RitmMotion.countChange), value: progress)
        Circle().fill(RitmTheme.panel).padding(5)
        Image(systemName: "sparkles")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(RitmTheme.accentColor)
      }
    }
    .frame(width: 55, height: 55)
    .shadow(color: Color(rgb: 0x6A42A5, opacity: 0.15), radius: 10, y: 5)
    .accessibilityHidden(true)
  }
}

/// MotionLine: the busy share of every hour from 9 AM to 9 PM on a 300 × 76 canvas.
private struct DayRhythmChart: View {
  let values: [Double]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // The key is the data set: a ticked checkbox does not change it, so nothing replays.
    RitmDrawGate(key: values) { drawn in
      VStack(spacing: 1) {
        ZStack {
          RhythmGrid().stroke(RitmTheme.accentColor.opacity(0.13), lineWidth: 0.8)
          RhythmLine(values: values, closed: true)
            .fill(RitmTheme.accentColor.opacity(0.17))
            .opacity(drawn ? 1 : 0)
            .animation(reduceMotion ? nil : RitmMotion.areaFade, value: drawn)
          RhythmLine(values: values, closed: false)
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(
              RitmTheme.accentColor,
              style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
            .animation(reduceMotion ? nil : RitmMotion.lineDraw, value: drawn)
        }
        .frame(height: 65)
        HStack {
          Text("9 AM")
          Spacer()
          Text("3 PM")
          Spacer()
          Text("9 PM")
        }
        .ritmFont(9, tracking: 0.03)
        .foregroundStyle(RitmTheme.muted)
      }
    }
    .frame(minHeight: 86, alignment: .top)
    .accessibilityHidden(true)
  }
}

private struct RhythmGrid: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let lines: [CGFloat] = [71, 45, 19]
    for y in lines {
      path.move(to: CGPoint(x: 0, y: y * rect.height / 76))
      path.addLine(to: CGPoint(x: rect.width, y: y * rect.height / 76))
    }
    return path
  }
}

private struct RhythmLine: Shape {
  let values: [Double]
  let closed: Bool

  func path(in rect: CGRect) -> Path {
    let scaleX: CGFloat = rect.width / 300
    let scaleY: CGFloat = rect.height / 76
    let step: CGFloat = 300 / CGFloat(max(1, values.count - 1))
    let points = values.enumerated().map { index, value -> CGPoint in
      CGPoint(x: CGFloat(index) * step * scaleX, y: (66 - CGFloat(value) * 49) * scaleY)
    }
    var path = Path()
    guard let first = points.first else { return path }
    if closed {
      path.move(to: CGPoint(x: 0, y: 72 * scaleY))
      path.addLine(to: first)
    } else {
      path.move(to: first)
    }
    for point in points.dropFirst() { path.addLine(to: point) }
    if closed {
      path.addLine(to: CGPoint(x: rect.width, y: 72 * scaleY))
      path.closeSubpath()
    }
    return path
  }
}

/// `radial-gradient(circle at x y, colour, transparent reach)` sized to the farthest corner.
struct CornerGlow: View {
  let color: Color
  let x: CGFloat
  let y: CGFloat
  let reach: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let height = proxy.size.height
      let corner = hypot(max(x, 1 - x) * width, max(y, 1 - y) * height)
      RadialGradient(
        colors: [color, color.opacity(0)], center: UnitPoint(x: x, y: y), startRadius: 0,
        endRadius: max(1, corner * reach))
    }
    .allowsHitTesting(false)
  }
}

/// `.focus-card`: the violet hero with the next entry and its start time.
struct DayFocusCard: View {
  let eyebrow: String
  let time: String
  let name: String
  let meta: String
  let action: () -> Void

  private let ink = Color(rgb: 0xFAF4FF)
  private let soft = Color(rgb: 0xF7F1FF)

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        Text(eyebrow).ritmFont(10, weight: .medium).foregroundStyle(soft)
        Text(time)
          .ritmFont(34, weight: .medium, tracking: -0.065)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .padding(.top, 14)
          .padding(.bottom, 7)
        Text(name)
          .ritmFont(11, weight: .medium, lineSpacing: 3)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 13)
        HStack {
          Text(meta).ritmFont(9)
          Spacer()
          Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
        }
        .foregroundStyle(soft)
      }
      .foregroundStyle(ink)
      .padding(20)
      .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
      .background {
        let shape = RoundedRectangle(cornerRadius: 23, style: .circular)
        shape.fill(RitmTheme.heroGradient)
          .overlay { CornerGlow(color: Color(rgb: 0xDDB9FF, opacity: 0.3), x: 0.94, y: 0, reach: 0.44) }
          .overlay(alignment: .topTrailing) {
            // The soft falloff circle of `.focus-card::after`.
            Circle()
              .fill(
                RadialGradient(
                  colors: [Color(rgb: 0xBF99ED, opacity: 0.12), .clear], center: .center,
                  startRadius: 0, endRadius: 77)
              )
              .frame(width: 220, height: 220)
              .offset(x: 90, y: -108)
          }
          .clipShape(shape)
          .overlay { shape.strokeBorder(Color(rgb: 0xDABCFC, opacity: 0.32), lineWidth: 1) }
          .shadow(color: Color(rgb: 0x4E307D, opacity: 0.22), radius: 22, y: 20)
      }
      .contentShape(RoundedRectangle(cornerRadius: 23, style: .circular))
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityElement(children: .combine)
    .ritmPageReveal(index: 1)
  }
}

/// `.ai-overview` on a phone: orb and name with the action on one line, the pitch below.
struct DayAssistantCard: View {
  let action: () -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 16) {
        HStack(spacing: 9) {
          RitmOrb(size: 32)
          Text(store.text("Помощник Ritm", "Ritm assistant"))
            .ritmFont(12, weight: .medium)
            .foregroundStyle(RitmTheme.text)
        }
        Spacer(minLength: 0)
        Button(action: action) {
          HStack(spacing: 8) {
            Text(store.text("Спланировать день", "Plan my day")).lineLimit(1)
            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
          }
          .ritmFont(10, weight: .semibold)
          .padding(.horizontal, 10)
          .frame(minHeight: 44)
          .foregroundStyle(RitmTheme.accentColor)
          .ritmGlass(in: Capsule(), interactive: true)
          .contentShape(Capsule())
        }
        .buttonStyle(RitmGlassButtonStyle())
      }
      Text(
        store.text(
          "Поможет собрать удобный план и оставить время для себя.",
          "Helps you build a workable plan and make time for yourself.")
      )
      .ritmFont(10, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
    .background { RitmPanelBackground(raised: true) }
    .ritmPageReveal(index: 2)
  }
}

/// `.ai-dock`: the pill under the page that opens the assistant.
struct DayAssistantDock: View {
  let action: () -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        RitmOrb(size: 32)
        Text(store.text("Спросить ИИ", "Ask AI")).ritmFont(12, weight: .medium)
        Image(systemName: "sparkles").font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
      }
      .foregroundStyle(Color(rgb: 0xF4EAFF))
      .padding(.leading, 8)
      .padding(.trailing, 18)
      .padding(.vertical, 7)
      // The dark under-layer keeps the light label readable in both themes.
      .background(
        RitmTheme.linear([.init(color: Color(rgb: 0x352449), location: 0), .init(color: Color(rgb: 0x30243F), location: 1)], cssAngle: 130)
          .opacity(0.88),
        in: Capsule()
      )
      .ritmGlass(in: Capsule(), interactive: true)
      .contentShape(Capsule())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .frame(maxWidth: .infinity)
  }
}
