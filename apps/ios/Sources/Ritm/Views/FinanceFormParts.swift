import SwiftUI

// The prototype's bottom-sheet form kit (shell.html `.sheet`, `.sh-head`, `.form`, `.fld`,
// `.amt`, `.err`, `.form-row`): one sheet frame, labelled fields, the 46 pt input surface, a
// select, the amount input and the 1 : 1.4 cancel / save row.

/// `.sheet`: the dense glass surface, 20 pt side padding, a 20 pt title row (44 pt tall) and a
/// 12 pt gap between the form's rows.
struct FinanceSheetFrame<Content: View>: View {
  let title: String
  let detents: Set<PresentationDetent>
  private let content: Content

  init(
    title: String, detents: Set<PresentationDetent> = [.large],
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.detents = detents
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .ritmFont(20, weight: .semibold, tracking: -0.045)
          .foregroundStyle(RitmTheme.text)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .accessibilityAddTraits(.isHeader)
        VStack(alignment: .leading, spacing: 12) { content }
          .padding(.top, 10)
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 40)
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.interactively)
    .background(RitmTheme.glassDense.ignoresSafeArea())
    .presentationDetents(detents)
    .presentationBackground(RitmTheme.glassDense)
    .presentationCornerRadius(22)
    .ritmSheetGrabber()
  }
}

/// `.fld`: a 12 pt muted label and its control, 5 pt apart.
struct FinanceField<Content: View>: View {
  let label: String
  private let content: Content

  init(_ label: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).ritmFont(12, weight: .medium).foregroundStyle(RitmTheme.muted)
      content
    }
  }
}

extension View {
  /// `.fld input`: 46 pt tall, 12 pt radius, a hairline border on the field fill, 14 pt text.
  func financeInput() -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
    return self
      .ritmFont(14, weight: .medium)
      .foregroundStyle(RitmTheme.text)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      .background(RitmTheme.field, in: shape)
      .overlay { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
  }
}

/// A single-line text input in the prototype's field surface.
struct FinanceTextInput: View {
  let placeholder: String
  @Binding var text: String
  var keyboard: UIKeyboardType = .default
  var capitalization: TextInputAutocapitalization = .sentences

  var body: some View {
    TextField(placeholder, text: $text)
      .keyboardType(keyboard)
      .textInputAutocapitalization(capitalization)
      .autocorrectionDisabled(keyboard != .default)
      .financeInput()
  }
}

/// `.amt`: an 18 pt bold number input with the currency sign at the right edge.
struct FinanceAmountInput: View {
  let placeholder: String
  @Binding var text: String
  let symbol: String

  var body: some View {
    ZStack(alignment: .trailing) {
      TextField(placeholder, text: $text)
        .keyboardType(.decimalPad)
        .ritmFont(18, weight: .bold)
        .monospacedDigit()
        .padding(.trailing, 28)
        .financeInput()
      Text(symbol)
        .ritmFont(14, weight: .semibold)
        .foregroundStyle(RitmTheme.muted)
        .padding(.trailing, 14)
        .allowsHitTesting(false)
    }
  }
}

/// `.fld select`: the chosen option and a small chevron pair; the options open as a menu.
struct FinanceSelect<Value: Hashable>: View {
  let options: [(value: Value, title: String)]
  @Binding var selection: Value
  var disabled = false

  var body: some View {
    Menu {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        Button {
          selection = option.value
        } label: {
          if option.value == selection {
            Label { Text(option.title) } icon: { RitmSymbol("checkmark") }
          } else {
            Text(option.title)
          }
        }
      }
    } label: {
      HStack(spacing: 8) {
        Text(options.first { $0.value == selection }?.title ?? "")
          .lineLimit(1)
        Spacer(minLength: 0)
        RitmSymbol("chevron.up.chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
      }
      .financeInput()
      .contentShape(Rectangle())
    }
    .disabled(disabled)
    .opacity(disabled ? 0.6 : 1)
  }
}

/// `.err`: a 12 pt danger line (nothing when empty).
struct FinanceFormError: View {
  let message: String?

  var body: some View {
    if let message, !message.isEmpty {
      Text(message)
        .ritmFont(12, weight: .medium)
        .foregroundStyle(RitmTheme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.updatesFrequently)
    }
  }
}

/// A 1 : 1.4 two-column row (`.form-row`, 10 pt apart).
private struct FinanceRatioRow: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
    return CGSize(width: proposal.width ?? 300, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 2 else { return }
    let usable = bounds.width - 10
    let first = usable / 2.4
    subviews[0].place(
      at: bounds.origin, proposal: ProposedViewSize(width: first, height: bounds.height))
    subviews[1].place(
      at: CGPoint(x: bounds.minX + first + 10, y: bounds.minY),
      proposal: ProposedViewSize(width: usable - first, height: bounds.height))
  }
}

/// `.form-row`: «Отмена» and the primary action.
struct FinanceFormButtons: View {
  let cancelTitle: String
  let saveTitle: String
  let canSave: Bool
  let cancel: () -> Void
  let save: () -> Void

  var body: some View {
    FinanceRatioRow {
      Button(cancelTitle, action: cancel)
        .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
      Button(saveTitle, action: save)
        .buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
        .disabled(!canSave)
    }
    .padding(.top, 2)
  }
}

/// `.chart-note` under a field: 11 pt muted.
struct FinanceFormNote: View {
  let text: String

  var body: some View {
    Text(text)
      .ritmFont(11, lineSpacing: 2.5)
      .foregroundStyle(RitmTheme.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}
