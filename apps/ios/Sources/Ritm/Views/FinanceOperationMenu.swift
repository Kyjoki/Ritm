import RitmCore
import SwiftUI

/// «+ Операция»: the primary capsule that opens a menu of «Поступление / Расход / Перевод».
/// The overview and the open card share it; `choose` hands the kind to the page.
struct FinanceOperationMenu: View {
  let format: FinanceFormat
  let canWrite: Bool
  let choose: (FinanceEntryKind) -> Void

  var body: some View {
    Menu {
      ForEach([FinanceEntryKind.income, .expense, .transfer], id: \.self) { kind in
        Button {
          choose(kind)
        } label: {
          Label { Text(format.typeName(kind)) } icon: { RitmSymbol(FinanceDisplay.symbol(kind)) }
        }
      }
    } label: {
      HStack(spacing: 8) {
        RitmSymbol("plus").font(.system(size: 14, weight: .semibold))
        Text(format.text("Операция", "Operation"))
      }
      .ritmFont(12.5, weight: .bold)
      .foregroundStyle(RitmTheme.ctaInk)
      .frame(maxWidth: .infinity, minHeight: 48)
      .ritmGlass(in: Capsule(), prominent: true, interactive: true)
      .contentShape(Capsule())
    }
    .disabled(!canWrite)
  }
}
