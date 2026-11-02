import RitmCore
import SwiftUI

/// One compact row under the wallet: «Предстоящие платежи · N» with the sum per currency. It
/// opens the sheet with the list. With nothing due it stays as «Регулярные платежи».
struct PaymentsEntryRow: View {
  @Environment(RitmStore.self) private var store
  let cards: [FinanceCard]
  let format: FinanceFormat
  @State private var showing = false

  var body: some View {
    let summary = store.payments.book.upcoming(today: store.today)
    let active = store.payments.payments.filter { !$0.paused }.count
    return Button { showing = true } label: {
      HStack(spacing: 12) {
        Image(systemName: "calendar.badge.clock")
          .font(.system(size: 18))
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 38, height: 38)
          .background(RitmTheme.soft, in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text(
            summary.count > 0
              ? format.text("Предстоящие платежи · \(summary.count)", "Upcoming payments · \(summary.count)")
              : format.text("Регулярные платежи", "Recurring payments")
          )
          .ritmFont(13, weight: .semibold, tracking: -0.02)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(2)
          if let sub = subtitle(summary, active: active) {
            Text(sub).ritmFont(11).foregroundStyle(RitmTheme.muted).lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if summary.count > 0 {
          VStack(alignment: .trailing, spacing: 0) {
            ForEach(summary.totals, id: \.currency) { total in
              RitmCountText(total.amountMinor) { format.money($0, total.currency) }
                .ritmFont(13, weight: .semibold, tracking: -0.02)
                .foregroundStyle(summary.hasOverdue ? RitmTheme.danger : RitmTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
          }
        }
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
          .accessibilityHidden(true)
      }
      .padding(.vertical, 8)
      .padding(.leading, 12)
      .padding(.trailing, 14)
      .frame(maxWidth: .infinity, minHeight: 60)
      .background { RitmPanelBackground(radius: 23) }
      .contentShape(RoundedRectangle(cornerRadius: 23, style: .circular))
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label(summary))
    .accessibilityAddTraits(.isButton)
    .ritmPageReveal(index: 2)
    .sheet(isPresented: $showing) {
      PaymentsSheet(cards: cards, format: format).environment(store)
    }
    .task(id: store.financeEntries.count) { store.reconcileRecurringPayments() }
  }

  private func subtitle(_ summary: UpcomingPayments, active: Int) -> String? {
    if summary.count > 0 {
      return summary.hasOverdue
        ? format.text("есть просроченные", "some are overdue")
        : format.text("в ближайшие 7 дней", "in the next 7 days")
    }
    return active > 0 ? format.text("ближайших нет", "none due soon") : nil
  }

  private func label(_ summary: UpcomingPayments) -> String {
    guard summary.count > 0 else { return format.text("Регулярные платежи", "Recurring payments") }
    let sums = summary.totals.map { format.money($0.amountMinor, $0.currency) }.joined(separator: ", ")
    return format.text(
      "Предстоящие платежи, \(summary.count), \(sums)", "Upcoming payments, \(summary.count), \(sums)")
  }
}
