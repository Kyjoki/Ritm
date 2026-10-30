import SwiftUI

/// The one segmented control of the app (Calendar view, Habits period, Finance period and
/// currency): a Liquid Glass capsule whose selected option is a drop of glass that slides between
/// options. The selected label is bold in the accent ink, unselected labels stay readable, every
/// option is at least 44 pt tall.
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

  /// `cubic-bezier(.2, .8, .2, 1)` in 0.28 s; Reduce Motion switches at once.
  private var slide: Animation? {
    reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
  }

  var body: some View {
    HStack(spacing: 3) {
      ForEach(values, id: \.self) { value in option(value) }
    }
    .padding(3)
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
        // The bold face reserves the width, so the row does not shift when the selection moves.
        Text(title(value)).ritmFont(fontSize, weight: .bold).hidden()
        Text(title(value))
          .ritmFont(fontSize, weight: active ? .bold : .medium)
          .foregroundStyle(active ? RitmTheme.accentColor : RitmTheme.muted)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 12)
      .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
      .background {
        if active {
          thumb.matchedGeometryEffect(id: "indicator", in: indicator)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: RitmGlassTokens.pressScale))
    .accessibilityLabel(title(value))
    .accessibilityAddTraits(active ? .isSelected : [])
  }

  /// The selection: a drop of glass that slides between the options.
  private var thumb: some View {
    Color.clear.ritmGlassThumb(in: Capsule(), tint: RitmTheme.accentColor.opacity(0.12))
  }
}
