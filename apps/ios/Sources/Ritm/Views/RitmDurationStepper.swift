import RitmCore
import SwiftUI

/// «Длительность: 1 ч  − +» on its own row of an editor. The two buttons are equal 44 × 44 pt
/// squares with a 12 pt gap, kept at least 12 pt away from the field above; when the text grows
/// with Dynamic Type the buttons drop under the label instead of overlapping it.
struct RitmDurationStepper: View {
  @Binding var duration: Int
  var range: ClosedRange<Int> = 5...720
  var step = 5
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

  private func button(_ symbol: String, _ label: String, _ delta: Int) -> some View {
    let allowed = range.contains(duration + delta)
    return Button {
      change(delta)
    } label: {
      Image(systemName: symbol)
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
    duration = min(range.upperBound, max(range.lowerBound, duration + delta))
  }
}
