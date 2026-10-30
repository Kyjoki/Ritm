import RitmCore
import SwiftUI

// Building blocks of the settings page (calendar-settings.css `.settings-*` at 390 px).

/// `.settings-card`: 22 × 20 padding, radius 24, a titled section.
struct SettingsCard<Content: View>: View {
  let symbol: String
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(RitmTheme.accentColor)
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

/// `.settings-field`: a 12 pt label above a 44 pt control.
struct SettingsField<Control: View>: View {
  let label: String
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
    .padding(.top, 16)
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
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(RitmTheme.muted)
      }
      .foregroundStyle(RitmTheme.text)
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
  }
}

struct SettingsHint: View {
  let text: String
  var body: some View {
    Text(text).ritmFont(10, lineSpacing: 4).foregroundStyle(RitmTheme.muted).padding(.top, 11)
  }
}

/// `.settings-switch-row`: title and note on the left, a 44 × 28 switch on the right.
struct SettingsSwitchRow: View {
  let title: String
  let note: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).ritmFont(13).foregroundStyle(RitmTheme.text)
        Text(note).ritmFont(10, lineSpacing: 3).foregroundStyle(RitmTheme.muted)
      }
    }
    .tint(RitmTheme.accentColor)
    .padding(.vertical, 17)
    .frame(minHeight: 74)
  }
}

/// One of the three theme tiles with its miniature (`.settings-theme-option`).
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
          Image(systemName: symbol).font(.system(size: 13))
          Text(title).lineLimit(1).minimumScaleFactor(0.8)
          if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
        }
        .ritmFont(11)
        .padding(.top, 10)
        .padding(.bottom, 6)
      }
      .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
      .padding(6)
      .frame(maxWidth: .infinity, minHeight: 104)
      .background {
        if selected {
          Color.clear.ritmGlassThumb(
            in: RoundedRectangle(cornerRadius: 14, style: .circular),
            tint: RitmTheme.accentColor.opacity(0.14))
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .circular)
          .strokeBorder(selected ? RitmTheme.accentColor.opacity(0.6) : RitmTheme.line, lineWidth: 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .circular))
    }
    .buttonStyle(RitmPressStyle(scale: RitmGlassTokens.pressScale))
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// A sidebar strip and two content blocks, in the colours of that theme.
  private var preview: some View {
    let light = (base: Color(rgb: 0xF7F5FB), bar: Color(rgb: 0x30233F), block: Color(rgb: 0xE8DEF5))
    let dark = (base: Color(rgb: 0x171120), bar: Color(rgb: 0x271C36), block: Color(rgb: 0x3C2B51))
    return HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 3, style: .circular)
        .fill(theme == .dark ? dark.bar : light.bar)
        .frame(width: 18)
      VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 3, style: .circular)
          .fill(theme == .system ? Color.clear : theme == .dark ? dark.block : light.block)
        RoundedRectangle(cornerRadius: 3, style: .circular)
          .fill(theme == .system ? Color.clear : theme == .dark ? dark.block : light.block)
      }
    }
    .padding(8)
    .frame(height: 68)
    .background {
      if theme == .system {
        HStack(spacing: 0) { light.base; dark.base }
      } else {
        theme == .dark ? dark.base : light.base
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .circular))
    .accessibilityHidden(true)
  }
}

/// `.settings-connection-row`: provider icon, name and status, actions on the right.
struct SettingsConnectionRow<Actions: View>: View {
  let symbol: String
  let name: String
  let status: String
  let connected: Bool
  let notes: [String]
  @ViewBuilder let actions: Actions

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
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
          Text(note).ritmFont(10, lineSpacing: 3).foregroundStyle(RitmTheme.muted).padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 0) { actions }
    }
    .padding(.vertical, 16)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
    .accessibilityElement(children: .contain)
  }
}

/// Small secondary button of the connection rows (11 pt, 44 pt tall).
struct SettingsSmallButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .ritmFont(11, weight: .semibold)
        .foregroundStyle(RitmTheme.accentColor)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .ritmGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
    }
    .buttonStyle(RitmGlassButtonStyle())
  }
}
