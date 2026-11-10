import RitmCore
import SwiftUI

// Building blocks of the sign-in and server cards (proto/sections/settings.js at 390 pt). The
// settings list itself is built from SettingsKit.swift.
// One surface per card; rows and buttons are plain fills, never glass layers.

/// `.s-card`: 22 × 20 padding, radius 24, a titled section.
struct SettingsCard<Content: View>: View {
  let symbol: String
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        RitmSymbol(symbol).font(.system(size: 17)).foregroundStyle(RitmTheme.accentColor)
          .frame(width: 19).accessibilityHidden(true)
        Text(title).ritmFont(16, weight: .semibold, tracking: -0.02).foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
      }
      .padding(.bottom, 5)
      content
    }
    .padding(.vertical, 22)
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { RitmPanelBackground(radius: 24) }
  }
}

/// `.s-field`: a 12 pt label above a 44 pt control (`tight` drops the 16 pt top margin).
struct SettingsField<Control: View>: View {
  let label: String
  var tight = false
  @ViewBuilder let control: Control

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).ritmFont(12, weight: .medium).foregroundStyle(RitmTheme.text)
      control
        .ritmFont(16)
        .foregroundStyle(RitmTheme.text)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RitmTheme.glassDense, in: RoundedRectangle(cornerRadius: 11, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 11, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
        }
    }
    .padding(.top, tight ? 0 : 16)
  }
}

/// `.s-hint`: 10 pt muted, 11 pt above.
struct SettingsHint: View {
  let text: String
  var body: some View {
    Text(text).ritmFont(10, lineSpacing: 3.5).foregroundStyle(RitmTheme.muted).padding(.top, 11)
  }
}

/// `hr` between rows: a 1 pt line.
struct SettingsDivider: View {
  var body: some View { Rectangle().fill(RitmTheme.line).frame(height: 1) }
}

/// `.s-small`: 11 pt semibold accent label on a raised 13 pt-radius plate, 44 pt tall.
struct SettingsSmallButton: View {
  let title: String
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      Text(title)
        .ritmFont(11, weight: .semibold)
        .foregroundStyle(RitmTheme.accentColor)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(RitmTheme.glassRaised, in: RoundedRectangle(cornerRadius: 13, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .circular).strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .circular))
        .opacity(isEnabled ? 1 : 0.6)
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
  }
}

/// `.s-textbtn`: accent 11 pt semibold label without a surface, 44 pt tall.
struct SettingsTextButtonStyle: ButtonStyle {
  var size: CGFloat = 11
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmFont(size, weight: .semibold)
      .foregroundStyle(RitmTheme.accentColor)
      .padding(.horizontal, 8)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
      .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
  }
}

/// `.s-pri`: the 48 pt call to action, radius 14, accent gradient, one soft shadow.
struct SettingsPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    configuration.label
      .ritmFont(13, weight: .semibold)
      .foregroundStyle(RitmTheme.ctaInk)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background {
        shape.fill(RitmTheme.ctaGradient)
          .shadow(color: isEnabled ? RitmTheme.ctaShadow : .clear, radius: 12, y: 5)
      }
      .overlay { shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
      .opacity(isEnabled ? 1 : 0.5)
      .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: configuration.isPressed)
  }
}

/// `.s-notice`: an accent confirmation line with a check.
struct SettingsNotice: View {
  let text: String
  var body: some View {
    Label { Text(text) } icon: { RitmSymbol("checkmark.circle") }
      .ritmFont(11, lineSpacing: 3.5)
      .foregroundStyle(RitmTheme.accentColor)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 8)
  }
}
