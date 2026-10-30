import SwiftUI

/// The one segmented control of the app (Today/Tomorrow, Calendar view, Habits period, Finance
/// period, currency and history filter, the assistant mode).
///
/// The track is a calm glass capsule with a thin rim and an even 4 pt inner padding. The thumb is
/// a capsule filled with the Ritm violet (the gradient of the primary button, a soft inner
/// highlight on top); it slides between options and is clipped to the track's inner capsule, so it
/// can never poke out of the track. The selected label is semibold in the on-accent ink,
/// unselected labels stay muted but readable; every option is at least 40 pt tall inside the
/// 4 pt padding, 48 pt with the track.
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

  /// A plain ease-out slide; Reduce Motion switches at once.
  private var slide: Animation? {
    reduceMotion ? nil : .easeOut(duration: 0.30)
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(values, id: \.self) { value in option(value) }
    }
    // The thumbs live in the options' backgrounds; clipping here keeps every frame of the slide
    // inside the inner rounded rectangle.
    .clipShape(Capsule())
    .padding(4)
    .ritmGlass(in: Capsule())
    .animation(slide, value: selection)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  private func option(_ value: Value) -> some View {
    let active = value == selection
    return Button {
      selection = value
    } label: {
      ZStack {
        // The semibold face reserves the width, so the row does not shift when the selection moves.
        Text(title(value)).ritmFont(fontSize, weight: .semibold).hidden()
        Text(title(value))
          .ritmFont(fontSize, weight: active ? .semibold : .medium)
          .foregroundStyle(active ? RitmTheme.ctaInk : RitmTheme.muted)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, fillsWidth ? 8 : 16)
      .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 40)
      .background {
        if active {
          RitmAccentThumb().matchedGeometryEffect(id: "thumb", in: indicator)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(title(value))
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

/// The violet thumb: the primary button's gradient with a soft highlight under the top edge and a
/// hairline inner rim. No shadow, so nothing of it can draw outside the track.
struct RitmAccentThumb: View {
  var body: some View {
    let shape = Capsule()
    shape
      .fill(RitmTheme.ctaGradient)
      .overlay {
        shape.fill(
          LinearGradient(
            stops: [
              .init(color: Color.white.opacity(0.30), location: 0),
              .init(color: Color.white.opacity(0), location: 0.5),
            ], startPoint: .top, endPoint: .bottom))
      }
      .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1) }
  }
}
