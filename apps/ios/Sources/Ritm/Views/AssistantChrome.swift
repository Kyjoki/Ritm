import SwiftUI

// Shared pieces of the «ИИ-помощник» page (proto/sections/assistant.js): the 13 pt buttons, the
// static orb, the bubbles and the disclosure row. One fill and one contour per box, no glass
// per row, nothing animates while the page is idle.

/// `.a-btn`: a 44 pt rounded button (radius 13) with a raised fill or the primary gradient.
struct AssistantButtonStyle: ButtonStyle {
  enum Kind { case secondary, primary }
  var kind: Kind = .secondary
  /// `.a-btn.sm`: 12 pt label, 11 pt side padding, does not stretch.
  var small = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// `--seg-shadow`: `0 3px 10px`.
  private var softShadow: Color {
    Color(light: 0x3E236B, dark: 0x000000, lightOpacity: 0.09, darkOpacity: 0.25)
  }

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 13, style: .circular)
    let primary = kind == .primary
    configuration.label
      .ritmFont(small ? 12 : 13, weight: .semibold)
      .multilineTextAlignment(.center)
      .foregroundStyle(primary ? RitmTheme.ctaInk : RitmTheme.accentColor)
      .padding(.horizontal, small ? 11 : 14)
      .frame(maxWidth: small ? nil : .infinity, minHeight: 44)
      .background {
        if primary {
          shape.fill(RitmTheme.ctaGradient).shadow(color: RitmTheme.ctaShadow, radius: 11, y: 6)
        } else {
          shape.fill(RitmTheme.glassRaised).shadow(color: softShadow, radius: 5, y: 3)
        }
      }
      .overlay {
        if primary {
          shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        } else {
          shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
        }
      }
      .opacity(isEnabled ? 1 : 0.5)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: configuration.isPressed)
  }
}

/// Icon and label of an `AssistantButtonStyle` button (gap 7).
struct AssistantButtonLabel: View {
  let title: String
  var symbol: String?
  var iconSize: CGFloat = 15

  var body: some View {
    HStack(spacing: 7) {
      if let symbol {
        RitmSymbol(symbol).font(.system(size: iconSize, weight: .regular)).accessibilityHidden(true)
      }
      Text(title)
    }
  }
}

extension View {
  /// A box with one fill and a 1 pt `--line` contour.
  func assistantBox(_ fill: Color, radius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
    return background(fill, in: shape).overlay { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
  }
}

/// `.a-orb`: a pearl sphere from three gradients; static, so it costs nothing while idle.
struct AssistantOrb: View {
  var size: CGFloat = 51

  private static let c0 = Color(rgb: 0x9C77DB)
  private static let c1 = Color(rgb: 0xD798BC)
  private static let c2 = Color(rgb: 0x77A6D4)

  var body: some View {
    Circle()
      .fill(LinearGradient(colors: [Self.c0, Self.c2], startPoint: UnitPoint(x: 0.18, y: 0.07), endPoint: UnitPoint(x: 0.82, y: 0.93)))
      .overlay {
        Circle().fill(
          RadialGradient(
            colors: [Self.c1, Self.c1.opacity(0)], center: UnitPoint(x: 0.7, y: 0.75),
            startRadius: 0, endRadius: size * 0.62))
      }
      .overlay {
        Circle().fill(
          RadialGradient(
            colors: [.white, Color.white.opacity(0)], center: UnitPoint(x: 0.32, y: 0.28),
            startRadius: 0, endRadius: size * 0.28))
      }
      .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1) }
      .frame(width: size, height: size)
      .shadow(color: Self.c0.opacity(0.45), radius: 11, y: 8)
      .accessibilityHidden(true)
  }
}

/// A row that opens and closes its content (`details > summary`): 44 pt tall, accent chevron.
struct AssistantDisclosure<Label: View, Content: View>: View {
  @Binding var isOpen: Bool
  @ViewBuilder let label: Label
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        isOpen.toggle()
      } label: {
        HStack(spacing: 8) {
          label
          Spacer(minLength: 0)
          RitmSymbol("chevron.down")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RitmTheme.accentColor)
            .rotationEffect(.degrees(isOpen ? 180 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOpen)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isOpen ? .isSelected : [])
      if isOpen { content }
    }
  }
}

/// The web's suggestion list and quick chips.
struct AssistantPrompt {
  let title: String
  let subtitle: String
  let english: String
  let englishSubtitle: String
  let symbol: String

  static let all = [
    AssistantPrompt(title: "Что у меня сегодня?", subtitle: "Собрать дела в один план", english: "What's on today?", englishSubtitle: "Gather tasks into one plan", symbol: "calendar"),
    AssistantPrompt(title: "Спланируй неделю", subtitle: "Оставить место для отдыха", english: "Plan my week", englishSubtitle: "Leave room for rest", symbol: "clock"),
    AssistantPrompt(title: "Разбей задачу на шаги", subtitle: "Начать с понятного действия", english: "Break a task into steps", englishSubtitle: "Start with a clear action", symbol: "checklist"),
    AssistantPrompt(title: "Подготовь отчёт о выполненном", subtitle: "Увидеть свой прогресс", english: "Report what I've done", englishSubtitle: "See your progress", symbol: "bubble.left"),
  ]
}

/// The user's bubble: soft fill, one contour, a sharp corner at the bottom right.
struct UserBubble: ViewModifier {
  func body(content: Content) -> some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 15, bottomLeadingRadius: 15, bottomTrailingRadius: 4, topTrailingRadius: 15,
      style: .circular)
    content
      .padding(.vertical, 12)
      .padding(.horizontal, 13)
      .background(RitmTheme.soft, in: shape)
      .overlay { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
  }
}

/// A user message sits on the right and leaves at least 6 % of the row free (max-width: 94%).
struct UserMessageRow<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 20)
      content.modifier(UserBubble())
    }
  }
}

/// `.a-dots`: three dots that pulse while a reply is on its way (only then).
struct AssistantThinkingDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.15, paused: reduceMotion)) { context in
      let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
      HStack(spacing: 3) {
        ForEach(0..<3, id: \.self) { index in
          let shifted = (phase - Double(index) * 0.125 + 1).truncatingRemainder(dividingBy: 1)
          Circle()
            .fill(RitmTheme.accentColor)
            .frame(width: 3, height: 3)
            .opacity(reduceMotion ? 1 : 0.35 + 0.65 * (shifted < 0.5 ? 1 - shifted * 2 : (shifted - 0.5) * 2))
        }
      }
    }
    .accessibilityHidden(true)
  }
}
