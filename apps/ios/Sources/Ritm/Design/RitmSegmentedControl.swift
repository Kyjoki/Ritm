import SwiftUI

/// The one segmented control of the app (Today/Tomorrow, Calendar view, Habits period, Finance
/// period, currency and history filter, the assistant mode): the prototype's `.seg`.
///
/// The track is a calm glass capsule (the accent at 7 % over the translucent tile) with a thin
/// specular rim and an even 4 pt inner padding. The thumb is a capsule filled with the Ritm
/// violet (the gradient of the primary button with a glossy veil); it slides between options in
/// 0.3 s and is clipped to the track's inner capsule, so it can never poke out of the track. The
/// selected label is bold in the on-accent ink, unselected labels are semibold in `--seg-off`;
/// every option is 44 pt tall inside the 4 pt padding, 52 pt with the track. No blur anywhere.
struct RitmSegmentedControl<Value: Hashable>: View {
  let label: String
  let values: [Value]
  let title: (Value) -> String
  @Binding var selection: Value
  var fontSize: CGFloat = 13
  /// `false` sizes every option to its label (a control next to other buttons).
  var fillsWidth = true
  @Namespace private var indicator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

  /// A plain ease-out slide (`cubic-bezier(.2, .8, .2, 1)`, .3 s); Reduce Motion switches at once.
  private var slide: Animation? {
    reduceMotion ? nil : RitmMotion.easeOut(0.30)
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(values, id: \.self) { value in option(value) }
    }
    // The thumbs live in the options' backgrounds; clipping here keeps every frame of the slide
    // inside the inner rounded rectangle.
    .clipShape(Capsule())
    .padding(4)
    .background { track }
    .animation(slide, value: selection)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  /// `color-mix(accent 7%, lg-tile)` with the inset well and the specular rim.
  private var track: some View {
    let shape = Capsule()
    return ZStack {
      shape.fill(RitmTheme.mix(RitmTheme.accentColor, 0.07, into: RitmTheme.glassTile))
      shape.stroke(
        LinearGradient(
          stops: [
            .init(color: Color(light: 0x3E236B, dark: 0x000000, lightOpacity: 0.09, darkOpacity: 0.35), location: 0),
            .init(color: .clear, location: 0.35),
          ], startPoint: .top, endPoint: .bottom),
        lineWidth: 3
      )
      .clipShape(shape)
      shape
        .stroke(
          contrast == .increased ? AnyShapeStyle(RitmTheme.text) : AnyShapeStyle(RitmGlassTokens.rim),
          lineWidth: 2
        )
        .clipShape(shape)
    }
  }

  private func option(_ value: Value) -> some View {
    let active = value == selection
    return Button {
      selection = value
    } label: {
      ZStack {
        // The bold face reserves the width, so the row does not shift when the selection moves.
        Text(title(value)).ritmFont(fontSize, weight: .bold, tracking: -0.01).hidden()
        Text(title(value))
          .ritmFont(fontSize, weight: active ? .bold : .semibold, tracking: -0.01)
          .foregroundStyle(active ? RitmTheme.ctaInk : RitmTheme.segmentOff)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 10)
      .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
      .background {
        if active {
          RitmAccentThumb().matchedGeometryEffect(id: "thumb", in: indicator)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(RitmSegmentPressStyle())
    .accessibilityLabel(title(value))
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

/// `.seg button:active { opacity: .8 }`: a press dims the option, nothing moves.
private struct RitmSegmentPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
  }
}

/// The violet thumb: the call-to-action gradient with a glossy veil, a lit top edge and a
/// hairline inner rim. No shadow, so nothing of it can draw outside the track.
struct RitmAccentThumb: View {
  var body: some View {
    let shape = Capsule()
    shape
      .fill(RitmTheme.ctaGradient)
      .overlay { shape.fill(RitmGlassTokens.ctaVeil) }
      .overlay {
        shape.strokeBorder(
          LinearGradient(
            stops: [
              .init(color: Color.white.opacity(0.5), location: 0),
              .init(color: Color.white.opacity(0.12), location: 0.3),
              .init(color: Color.white.opacity(0.12), location: 1),
            ], startPoint: .top, endPoint: .bottom),
          lineWidth: 1)
      }
  }
}
