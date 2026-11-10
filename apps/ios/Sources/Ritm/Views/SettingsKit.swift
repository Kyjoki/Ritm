import RitmCore
import SwiftUI

// The pieces of the redesigned Settings («Список»): inset groups of 46 pt rows with hairlines,
// a status dot, a trailing value and a chevron, and the pushed-page frame. Proto: phone-a.html
// `.grp`, `.row`, `.cap`, `.hint`, `.dot`, `.sw`, `.stat`, `.btn`, `.toast`.

/// A page pushed from the settings list.
enum SettingsRoute: Hashable {
  case profile, timeZone, workDay
  case google, telegram, openAI
  case security, health, liveActivity, widgets
  case wallet, accounts, server
}

extension SettingsTone {
  var color: Color {
    switch self {
    case .none: RitmTheme.muted.opacity(0.55)
    case .ok: Color(light: 0x2F9A74, dark: 0x6FD0AA)
    case .warn: Color(light: 0xC98A1B, dark: 0xF0C36A)
    case .error: RitmTheme.danger
    }
  }
}

/// `.dot`: 8 pt, muted when there is nothing to report.
struct SettingsStatusDot: View {
  let tone: SettingsTone
  var size: CGFloat = 8

  var body: some View {
    Circle().fill(tone.color).frame(width: size, height: size).accessibilityHidden(true)
  }
}

// MARK: - Group and rows

/// `.grp`: the panel with 20 pt corners; a hairline between rows starts 16 pt from the left.
struct SettingsGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { rows in
        ForEach(rows.indices, id: \.self) { index in
          if index > 0 { hairline }
          rows[index]
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .circular))
    .background { RitmPanelBackground(radius: 20) }
  }

  private var hairline: some View {
    Rectangle().fill(RitmTheme.line.opacity(0.78)).frame(height: 1).padding(.leading, 16)
  }
}

/// `.cap`: a 12 pt semibold muted caption above a group.
struct SettingsCaption: View {
  let text: String

  var body: some View {
    Text(text)
      .ritmFont(12, weight: .semibold)
      .foregroundStyle(RitmTheme.muted)
      .padding(.horizontal, 6)
      .padding(.bottom, 7)
      .accessibilityAddTraits(.isHeader)
  }
}

/// `.hint`: a muted 12 pt note under a group.
struct SettingsFootnote: View {
  let text: String
  var tone: SettingsTone = .none

  var body: some View {
    Text(text)
      .ritmFont(12, lineSpacing: 2)
      .foregroundStyle(tone == .error ? RitmTheme.danger : RitmTheme.muted)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 6)
      .padding(.top, 8)
  }
}

/// The value at the right of a row: an optional status dot and a muted 14 pt text.
struct SettingsValue: View {
  let text: String
  var tone: SettingsTone?

  init(_ text: String, tone: SettingsTone? = nil) {
    self.text = text
    self.tone = tone
  }

  init(_ trailing: SettingsTrailing) {
    self.init(trailing.text, tone: trailing.tone)
  }

  var body: some View {
    HStack(spacing: 7) {
      if let tone { SettingsStatusDot(tone: tone) }
      Text(text).lineLimit(2).multilineTextAlignment(.trailing)
    }
    .ritmFont(14)
    .foregroundStyle(RitmTheme.muted)
    .accessibilityElement(children: .combine)
  }
}

struct SettingsRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed ? RitmTheme.soft.opacity(0.7) : Color.clear)
  }
}

enum SettingsAccessory { case none, chevron, menu }

/// `.row`: icon, label (with an optional second line), the trailing content and an accessory.
struct SettingsListRow<Trailing: View>: View {
  var icon: String?
  let title: String
  var subtitle: String?
  var accessory: SettingsAccessory = .none
  var tint: Color?
  @ViewBuilder let trailing: Trailing
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    HStack(spacing: 12) {
      if let icon {
        RitmSymbol(icon)
          .font(.system(size: 21))
          .foregroundStyle(tint ?? RitmTheme.accentColor)
          .frame(width: 24)
          .padding(.trailing, -2)
          .accessibilityHidden(true)
      }
      labels
      trailing
      switch accessory {
      case .none: EmptyView()
      case .chevron:
        RitmSymbol("chevron.right").font(.system(size: 18))
          .foregroundStyle(RitmTheme.muted.opacity(0.7)).padding(.trailing, -4)
          .accessibilityHidden(true)
      case .menu:
        RitmSymbol("chevron.down").font(.system(size: 15)).foregroundStyle(RitmTheme.muted)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    .contentShape(Rectangle())
    .opacity(isEnabled ? 1 : 0.5)
  }

  private var labels: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title)
        .ritmFont(15, weight: .medium, tracking: -0.012)
        .foregroundStyle(tint ?? RitmTheme.text)
        .fixedSize(horizontal: false, vertical: true)
      if let subtitle {
        Text(subtitle)
          .ritmFont(12, lineSpacing: 1)
          .foregroundStyle(RitmTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .layoutPriority(typeSize.isAccessibilitySize ? 0 : 1)
  }
}

extension SettingsListRow where Trailing == EmptyView {
  init(
    icon: String? = nil, title: String, subtitle: String? = nil, accessory: SettingsAccessory = .none,
    tint: Color? = nil
  ) {
    self.init(
      icon: icon, title: title, subtitle: subtitle, accessory: accessory, tint: tint,
      trailing: { EmptyView() })
  }
}

/// A row that pushes a page.
struct SettingsNavRow<Trailing: View>: View {
  let route: SettingsRoute
  var icon: String?
  let title: String
  var subtitle: String?
  @ViewBuilder let trailing: Trailing

  var body: some View {
    NavigationLink(value: route) {
      SettingsListRow(icon: icon, title: title, subtitle: subtitle, accessory: .chevron) {
        trailing
      }
      .accessibilityElement(children: .combine)
    }
    .buttonStyle(SettingsRowButtonStyle())
  }
}

/// A row that does something when tapped.
struct SettingsActionRow<Trailing: View>: View {
  var icon: String?
  let title: String
  var subtitle: String?
  var accessory: SettingsAccessory = .none
  var tint: Color?
  let action: () -> Void
  @ViewBuilder let trailing: Trailing

  var body: some View {
    Button(action: action) {
      SettingsListRow(
        icon: icon, title: title, subtitle: subtitle, accessory: accessory, tint: tint
      ) { trailing }
      .accessibilityElement(children: .combine)
    }
    .buttonStyle(SettingsRowButtonStyle())
  }
}

// MARK: - Switch and menu

/// `.sw`: 48 × 30, the account violet when on, a muted track when off.
struct SettingsKnob: View {
  let isOn: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Capsule()
      .fill(isOn ? Color(light: 0x7651BC, dark: 0x8C66D8) : RitmTheme.muted.opacity(0.34))
      .frame(width: 48, height: 30)
      .overlay(alignment: .leading) {
        Circle().fill(Color.white).frame(width: 26, height: 26)
          .shadow(color: .black.opacity(0.28), radius: 2.5, y: 2)
          .padding(2)
          .offset(x: isOn ? 18 : 0)
      }
      .animation(reduceMotion ? nil : RitmMotion.easeOut(0.26), value: isOn)
      .accessibilityHidden(true)
  }
}

/// A row with a switch; the whole row toggles. VoiceOver sees a switch with the subtitle as hint.
struct SettingsToggleRow: View {
  var icon: String?
  let title: String
  var subtitle: String?
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      SettingsListRow(icon: icon, title: title, subtitle: subtitle) { SettingsKnob(isOn: isOn) }
    }
    .buttonStyle(SettingsRowButtonStyle())
    .sensoryFeedback(.selection, trigger: isOn)
    .accessibilityRepresentation {
      Toggle(title, isOn: $isOn).accessibilityHint(subtitle ?? "")
    }
  }
}

/// A row whose value is picked from a menu (the language).
struct SettingsMenuRow<Value: Hashable>: View {
  var icon: String?
  let title: String
  let options: [(Value, String)]
  @Binding var selection: Value

  var body: some View {
    Menu {
      Picker(title, selection: $selection) {
        ForEach(options.indices, id: \.self) { index in
          Text(options[index].1).tag(options[index].0)
        }
      }
    } label: {
      SettingsListRow(icon: icon, title: title, accessory: .menu) {
        SettingsValue(options.first { $0.0 == selection }?.1 ?? "")
      }
      .accessibilityElement(children: .combine)
    }
    .menuOrder(.fixed)
    .buttonStyle(SettingsRowButtonStyle())
    .sensoryFeedback(.selection, trigger: selection)
  }
}

// MARK: - Buttons and status

/// `.btn`: 46 pt, 15 pt corners. Primary is the accent gradient, secondary a soft plate, danger a
/// rose plate, text no plate.
struct SettingsButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary, danger, text, dangerText }
  let kind: Kind
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 15, style: .circular)
    configuration.label
      .ritmFont(15, weight: .bold, tracking: -0.01)
      .foregroundStyle(ink)
      .frame(maxWidth: .infinity, minHeight: kind == .text || kind == .dangerText ? 44 : 46)
      .padding(.horizontal, 18)
      .background {
        switch kind {
        case .primary:
          shape.fill(RitmTheme.ctaGradient)
            .shadow(color: isEnabled ? RitmTheme.ctaShadow : .clear, radius: 12, y: 5)
        case .secondary: shape.fill(RitmTheme.soft)
        case .danger: shape.fill(RitmTheme.dangerSoft)
        case .text, .dangerText: Color.clear
        }
      }
      .contentShape(shape)
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: configuration.isPressed)
  }

  private var ink: Color {
    switch kind {
    case .primary: RitmTheme.ctaInk
    case .secondary, .text: RitmTheme.accentColor
    case .danger, .dangerText: RitmTheme.danger
    }
  }
}

/// A full-width button; `busy` swaps the label for a spinner and blocks taps.
struct SettingsActionButton: View {
  let title: String
  var icon: String?
  var kind: SettingsButtonStyle.Kind = .primary
  var busy = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        HStack(spacing: 8) {
          if let icon { RitmSymbol(icon).font(.system(size: 18)) }
          Text(title).multilineTextAlignment(.center)
        }
        .opacity(busy ? 0 : 1)
        if busy { ProgressView().tint(kind == .primary ? RitmTheme.ctaInk : RitmTheme.accentColor) }
      }
    }
    .buttonStyle(SettingsButtonStyle(kind: kind))
    .allowsHitTesting(!busy)
    .accessibilityLabel(title)
  }
}

/// `.stat`: a 10 pt dot with a bold line and a muted line under it, on top of a detail page.
struct SettingsStatusHeader: View {
  let title: String
  var detail: String?
  let tone: SettingsTone

  var body: some View {
    HStack(spacing: 12) {
      SettingsStatusDot(tone: tone, size: 10)
      VStack(alignment: .leading, spacing: 0) {
        Text(title).ritmFont(16, weight: .bold, tracking: -0.025).foregroundStyle(RitmTheme.text)
        if let detail {
          Text(detail).ritmFont(12.5).foregroundStyle(RitmTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 4)
    .padding(.top, 2)
    .padding(.bottom, 14)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Saved toast

/// `.toast`: «Сохранено» in a small pill above the bar; a failure stays a little longer.
struct SettingsSavedToast: View {
  @Environment(SettingsModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if let toast = model.toast {
        pill(toast).id(toast.id)
          .transition(
            reduceMotion
              ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 108)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .ignoresSafeArea(.container, edges: .bottom)
    .animation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.2), value: model.toast)
    .allowsHitTesting(false)
  }

  private func pill(_ toast: SettingsToast) -> some View {
    HStack(spacing: 7) {
      RitmSymbol(toast.failed ? "exclamationmark.circle" : "checkmark")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(toast.failed ? RitmTheme.danger : SettingsTone.ok.color)
      Text(toast.text)
        .ritmFont(13, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .lineLimit(3)
    }
    .padding(.leading, 12)
    .padding(.trailing, 15)
    .padding(.vertical, 9)
    .background(RitmTheme.glassDense, in: Capsule())
    .overlay { Capsule().strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
    .shadow(color: RitmTheme.panelShadow, radius: 14, y: 8)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Pushed page

/// The frame of a pushed page: the soft background, a scrolling column (130 pt of room under it
/// for the floating bar), the native title and back button, and the saved toast.
struct SettingsPage<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content
  @Environment(SettingsModel.self) private var model

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) { content }
          .padding(.horizontal, 16)
          .padding(.top, 10)
          .padding(.bottom, 130)
          .frame(maxWidth: 700)
          .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
    }
    .overlay { SettingsSavedToast() }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.visible, for: .navigationBar)
    .onDisappear { Task { await model.settle() } }
  }
}

extension SettingsNavRow where Trailing == EmptyView {
  init(route: SettingsRoute, icon: String? = nil, title: String, subtitle: String? = nil) {
    self.init(route: route, icon: icon, title: title, subtitle: subtitle, trailing: { EmptyView() })
  }
}

extension SettingsActionRow where Trailing == EmptyView {
  init(
    icon: String? = nil, title: String, subtitle: String? = nil,
    accessory: SettingsAccessory = .none, tint: Color? = nil, action: @escaping () -> Void
  ) {
    self.init(
      icon: icon, title: title, subtitle: subtitle, accessory: accessory, tint: tint,
      action: action, trailing: { EmptyView() })
  }
}
