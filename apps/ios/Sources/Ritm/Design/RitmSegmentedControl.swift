import SwiftUI

/// The one segmented control of the app (Calendar view, Habits period, Finance period and
/// currency). The selected option sits on a clearly filled indicator that slides between
/// options: in the dark theme an accent-tinted gradient with a 1 pt accent border and a soft glow,
/// in the light theme a raised white pill with a shadow. The selected label is bold in the accent
/// ink, unselected labels stay readable, every option is at least 44 pt tall.
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
  @Environment(\.colorScheme) private var scheme

  /// `cubic-bezier(.2, .8, .2, 1)` in 0.28 s; Reduce Motion switches at once.
  private var slide: Animation? {
    reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
  }

  var body: some View {
    HStack(spacing: 3) {
      ForEach(values, id: \.self) { value in option(value) }
    }
    .padding(3)
    .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 14, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
    }
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
          pill.matchedGeometryEffect(id: "indicator", in: indicator)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .accessibilityLabel(title(value))
    .accessibilityAddTraits(active ? .isSelected : [])
  }

  @ViewBuilder private var pill: some View {
    let shape = RoundedRectangle(cornerRadius: 11, style: .circular)
    if scheme == .dark {
      shape
        .fill(
          LinearGradient(
            colors: [
              RitmTheme.mix(RitmTheme.accentColor, 0.34, into: RitmTheme.panel),
              RitmTheme.mix(RitmTheme.accentColor, 0.2, into: RitmTheme.panel),
            ], startPoint: .top, endPoint: .bottom)
        )
        .overlay { shape.strokeBorder(RitmTheme.accentColor, lineWidth: 1) }
        .shadow(color: RitmTheme.accentColor.opacity(0.35), radius: 8)
    } else {
      shape
        .fill(Color.white)
        .overlay { shape.strokeBorder(RitmTheme.accentColor.opacity(0.18), lineWidth: 1) }
        .shadow(color: Color(rgb: 0x3F235F, opacity: 0.16), radius: 6, y: 3)
    }
  }
}
