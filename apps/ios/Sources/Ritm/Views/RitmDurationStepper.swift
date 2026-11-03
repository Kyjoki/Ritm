import RitmCore
import SwiftUI

/// «Длительность: 1 ч  − +» on its own row of an editor. The two buttons are equal 44 × 44 pt
/// squares with a 12 pt gap, kept at least 12 pt away from the field above; when the text grows
/// with Dynamic Type the buttons drop under the label instead of overlapping it.
struct RitmDurationStepper: View {
  @Binding var duration: Int
  var range: ClosedRange<Int> = 15...720
  var step = 15
  @Environment(RitmStore.self) private var store

  private var title: String {
    store.text("Длительность: ", "Duration: ")
      + DayPlan.durationText(duration, language: store.language)
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        label
        Spacer(minLength: 12)
        buttons
      }
      VStack(alignment: .leading, spacing: 12) {
        label
        buttons
      }
    }
    .padding(.vertical, 8)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Длительность", "Duration"))
    .accessibilityValue(DayPlan.durationText(duration, language: store.language))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: change(step)
      case .decrement: change(-step)
      @unknown default: break
      }
    }
  }

  private var label: some View {
    Text(title)
      .ritmFont(15, weight: .semibold)
      .foregroundStyle(RitmTheme.text)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var buttons: some View {
    HStack(spacing: 12) {
      button("minus", store.text("Уменьшить длительность", "Decrease duration"), -step)
      button("plus", store.text("Увеличить длительность", "Increase duration"), step)
    }
  }

  /// The value a tap leads to: always a multiple of `step`, so 1 h 5 min goes to 1 h 15 min on «+»
  /// and back to 1 h on «−» (an existing off-grid duration snaps to the grid on the first tap).
  private func target(_ delta: Int) -> Int {
    let down = (duration / step) * step
    let raw = delta > 0 ? down + step : (duration % step == 0 ? duration - step : down)
    return min(range.upperBound, max(range.lowerBound, raw))
  }

  private func button(_ symbol: String, _ label: String, _ delta: Int) -> some View {
    let allowed = delta > 0 ? target(delta) > duration : target(delta) < duration
    return Button {
      change(delta)
    } label: {
      RitmSymbol(symbol)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 44, height: 44)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 12, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.95))
    .opacity(allowed ? 1 : 0.4)
    .disabled(!allowed)
    .accessibilityLabel(label)
  }

  private func change(_ delta: Int) {
    let next = target(delta)
    if delta > 0 ? next > duration : next < duration { duration = next }
  }
}
