import RitmCore
import SwiftUI

/// What the account-actions sheet asks the page to do once it has closed.
enum FinanceCardAction {
  case edit
  case addPosition
  case customize
  case delete
  case reset
}

/// The sheet behind the button in the open card's header: edit the account (or add a position
/// to a brokerage account), open the card settings, or delete the account. The page owns the
/// editor, the settings sheet and the confirmation, and runs the choice after this sheet closes.
struct FinanceAccountActionsSheet: View {
  let card: FinanceCard
  let format: FinanceFormat
  let canWrite: Bool
  var plain = false
  let choose: (FinanceCardAction) -> Void
  @Environment(\.dismiss) private var dismiss

  private var kindLine: String {
    switch card.kind {
    case .account: format.text("Основной счёт", "Main account")
    case .deposit: plain ? format.text("Счёт", "Account") : format.text("Депозит", "Deposit")
    case .stocks: format.text("Брокерский счёт", "Brokerage account")
    }
  }

  var body: some View {
    FinanceSheetFrame(title: format.name(card), detents: [.medium, .large]) {
      Text(kindLine).ritmFont(12).foregroundStyle(RitmTheme.muted)
      if card.kind == .stocks {
        row("plus", format.text("Добавить позицию", "Add a position"), .addPosition)
      } else {
        row("pencil", format.text("Изменить", "Edit"), .edit)
      }
      row("slider.horizontal.3", format.text("Настроить карты", "Customize cards"), .customize)
      deleteRow
      resetRow
      Button(format.text("Закрыть", "Close")) { dismiss() }
        .buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
        .padding(.top, 2)
    }
  }

  private func row(_ symbol: String, _ title: String, _ action: FinanceCardAction) -> some View {
    let enabled = canWrite || action == .customize
    return Button {
      choose(action)
      dismiss()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 16))
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 24)
        Text(title).ritmFont(13.5, weight: .semibold).foregroundStyle(RitmTheme.text)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
      }
      .financeInput()
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.6)
  }

  /// Wipes every finance record (confirmed on the page); reachable even from an open card.
  private var resetRow: some View {
    Button {
      choose(.reset)
      dismiss()
    } label: {
      Label(format.text("Сбросить финансы", "Reset finances"), systemImage: "arrow.counterclockwise")
        .ritmFont(13.5, weight: .semibold)
        .foregroundStyle(RitmTheme.danger)
        .frame(maxWidth: .infinity, minHeight: 48)
    }
    .buttonStyle(RitmPressStyle())
    .disabled(!canWrite)
    .opacity(canWrite ? 1 : 0.6)
  }

  private var deleteRow: some View {
    Button {
      choose(.delete)
      dismiss()
    } label: {
      Label(format.text("Удалить счёт", "Delete account"), systemImage: "trash")
        .ritmFont(13.5, weight: .semibold)
        .foregroundStyle(RitmTheme.danger)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
          RitmTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 13, style: .circular))
    }
    .buttonStyle(RitmPressStyle())
    .disabled(!canWrite)
    .opacity(canWrite ? 1 : 0.6)
  }
}
