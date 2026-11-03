import RitmCore
import SwiftUI

// Building blocks of the settings page (proto/sections/settings.js `.sec-settings` at 390 pt).
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

/// A web `<select>`: the current value with a chevron, options in a menu.
struct SettingsSelect<Value: Hashable>: View {
  let options: [(Value, String)]
  @Binding var selection: Value

  var body: some View {
    Menu {
      Picker("", selection: $selection) {
        ForEach(options.indices, id: \.self) { index in
          Text(options[index].1).tag(options[index].0)
        }
      }
    } label: {
      HStack {
        Text(options.first { $0.0 == selection }?.1 ?? "").lineLimit(1)
        Spacer(minLength: 8)
        RitmSymbol("chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(RitmTheme.muted)
      }
      .foregroundStyle(RitmTheme.text)
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
  }
}

/// `.s-hint`: 10 pt muted, 11 pt above.
struct SettingsHint: View {
  let text: String
  var body: some View {
    Text(text).ritmFont(10, lineSpacing: 3.5).foregroundStyle(RitmTheme.muted).padding(.top, 11)
  }
}

/// `.s-sw`: a 44 × 28 switch, accent when on, the line colour when off, 8 pt of extra hit area.
struct SettingsSwitch: View {
  @Binding var isOn: Bool
  let label: String
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      Capsule()
        .fill(isOn ? RitmTheme.accentColor : RitmTheme.line)
        .frame(width: 44, height: 28)
        .overlay(alignment: .leading) {
          Circle().fill(Color.white).frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .padding(3)
            .offset(x: isOn ? 16 : 0)
        }
        .animation(reduceMotion ? nil : RitmMotion.easeOut(0.2), value: isOn)
        .contentShape(Rectangle().inset(by: -8))
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.5)
    .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
  }
}

/// `.s-swrow`: title (and an optional note) on the left, the switch on the right, 74 pt tall.
struct SettingsSwitchRow: View {
  let title: String
  var note: String?
  @Binding var isOn: Bool
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).ritmFont(13).foregroundStyle(RitmTheme.text)
        if let note { Text(note).ritmFont(10, lineSpacing: 3).foregroundStyle(RitmTheme.muted) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      SettingsSwitch(isOn: $isOn, label: title)
    }
    .padding(.vertical, 17)
    .frame(minHeight: 74)
    .opacity(isEnabled ? 1 : 0.55)
  }
}

/// `hr` between rows: a 1 pt line.
struct SettingsDivider: View {
  var body: some View { Rectangle().fill(RitmTheme.line).frame(height: 1) }
}

/// One of the three theme tiles with its miniature (`.s-tile`).
struct SettingsThemeTile: View {
  let theme: Theme
  let title: String
  let symbol: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        preview
        HStack(spacing: 4) {
          RitmSymbol(symbol).font(.system(size: 13))
          Text(title).lineLimit(1).minimumScaleFactor(0.8)
          if selected { RitmSymbol("checkmark").font(.system(size: 11, weight: .bold)) }
        }
        .ritmFont(11)
        .padding(.top, 10)
        .padding(.bottom, 6)
      }
      .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
      .padding(6)
      .frame(maxWidth: .infinity, minHeight: 104)
      .background {
        if selected { RoundedRectangle(cornerRadius: 14, style: .circular).fill(RitmTheme.soft) }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .circular)
          .strokeBorder(selected ? RitmTheme.accentColor : RitmTheme.line, lineWidth: 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .circular))
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private static let light = (base: Color(rgb: 0xF7F5FB), bar: Color(rgb: 0x30233F), block: Color(rgb: 0xE8DEF5))
  private static let dark = (base: Color(rgb: 0x171120), bar: Color(rgb: 0x271C36), block: Color(rgb: 0x3C2B51))

  /// A sidebar strip and two content blocks, in the colours of that theme.
  private var preview: some View {
    let palette = theme == .dark ? Self.dark : Self.light
    return HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 3, style: .circular).fill(palette.bar).frame(width: 18)
      VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 3, style: .circular).fill(theme == .system ? Color.clear : palette.block)
        RoundedRectangle(cornerRadius: 3, style: .circular).fill(theme == .system ? Color.clear : palette.block)
      }
    }
    .padding(8)
    .frame(height: 68)
    .background {
      if theme == .system {
        HStack(spacing: 0) { Self.light.base; Self.dark.base }
      } else {
        palette.base
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .circular))
    .accessibilityHidden(true)
  }
}

/// `.s-conn`: provider icon, name and status, actions on the right.
struct SettingsConnectionRow<Actions: View>: View {
  let symbol: String
  let name: String
  let status: String
  let connected: Bool
  let notes: [String]
  @ViewBuilder let actions: Actions

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      RitmSymbol(symbol)
        .font(.system(size: 17))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 36, height: 36)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 11, style: .circular))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        Text(name).ritmFont(13, weight: .medium).foregroundStyle(RitmTheme.text)
        HStack(spacing: 5) {
          Circle().fill(connected ? RitmTheme.accentColor : RitmTheme.muted).frame(width: 5, height: 5)
          Text(status)
        }
        .ritmFont(10)
        .foregroundStyle(connected ? RitmTheme.accentColor : RitmTheme.muted)
        .padding(.top, 5)
        ForEach(notes, id: \.self) { note in
          Text(note).ritmFont(10, lineSpacing: 3.5).foregroundStyle(RitmTheme.muted).padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 2) { actions }
    }
    .padding(.vertical, 16)
    .overlay(alignment: .top) { SettingsDivider() }
    .accessibilityElement(children: .contain)
  }
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
