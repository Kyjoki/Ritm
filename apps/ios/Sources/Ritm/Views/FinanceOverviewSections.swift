import RitmCore
import SwiftUI

/// Everything the page can do with an entry; the page owns the sheets and the writes.
struct FinanceActions {
  let canWrite: Bool
  let open: (FinanceEntry) -> Void
  /// The third value is the card the operation starts on (nil: the overview).
  let add: (FinanceEntryKind, FinanceCurrency, String?) -> Void
  let edit: (FinanceEntry) -> Void
  let remove: (FinanceEntry) -> Void
}

// MARK: - Overview (cards stacked)

/// The blocks under the stacked wallet, in the prototype's order: «Счёт / Операция» buttons,
/// «Динамика средств», the three tiles with their notes, «Распределение» and «Последние
/// операции». The payments row and the purchases inbox are placed above by the page.
struct FinanceOverviewSections: View {
  let entries: [FinanceEntry]
  let cards: [FinanceCard]
  let format: FinanceFormat
  let today: String
  let currencies: [FinanceCurrency]
  let currency: FinanceCurrency
  @Binding var period: FinancePeriod
  let log: FinanceDrawLog
  let actions: FinanceActions
  let openCard: (String) -> Void
  @State private var showingHistory = false
  @State private var historyFollowUp: FinanceHistoryFollowUp?

  var body: some View {
    VStack(spacing: 14) {
      actionRow.ritmPageReveal(index: 2)
      dynamicsPanel
      statsBlock
      distributionPanel
      recentSection
    }
    .sheet(isPresented: $showingHistory, onDismiss: runHistoryFollowUp) {
      FinanceAllHistorySheet(format: format, onFollowUp: { historyFollowUp = $0 })
    }
  }

  // MARK: Buttons

  /// `.actions`: «+ Счёт» and the primary «+ Операция», two equal columns 10 pt apart.
  private var actionRow: some View {
    HStack(spacing: 10) {
      // The first account in a currency is the main one; every further account is a named one.
      Button {
        let hasMain = entries.contains { $0.type == .account && $0.currency == currency }
        actions.add(hasMain ? .deposit : .account, currency, nil)
      } label: {
        actionLabel(format.text("Счёт", "Account"), prominent: false)
      }
      .buttonStyle(RitmGlassButtonStyle())
      .disabled(!actions.canWrite)
      FinanceOperationMenu(format: format, canWrite: actions.canWrite) { kind in
        actions.add(kind, currency, nil)
      }
    }
    .opacity(actions.canWrite ? 1 : 0.6)
  }

  private func actionLabel(_ title: String, prominent: Bool) -> some View {
    HStack(spacing: 8) {
      RitmSymbol("plus").font(.system(size: 14, weight: .semibold))
      Text(title)
    }
    .ritmFont(12.5, weight: .bold)
    .foregroundStyle(prominent ? RitmTheme.ctaInk : RitmTheme.accentColor)
    .frame(maxWidth: .infinity, minHeight: 48)
    .ritmGlass(in: Capsule(), prominent: prominent, interactive: true)
    .contentShape(Capsule())
  }

  // MARK: Dynamics

  private var dynamicsPanel: some View {
    let series = FinanceWallet.overviewSeries(
      entries, currency: currency, period: period, today: today)
    let key = "overview-\(currency.rawValue)-\(period.rawValue)"
    let firstDay = cards.filter { $0.currency == currency && $0.balanceMinor != nil }
      .compactMap(\.asOf).min()
    var notes: [String] = []
    if let window = financeShortWindow(asOf: firstDay, period: period, today: today, format: format) {
      notes.append(window)
    }
    if currencies.count > 1 {
      notes.append(
        format.text(
          "Средства в других валютах показаны отдельно и не складываются.",
          "Funds in other currencies are shown separately and never added together."))
    }
    return FinancePanel(reveal: 3) {
      FinancePanelHead(
        title: format.text("Динамика средств", "Funds over time"),
        sub: format.text(
          "Только \(financeSymbol(currency)), без пересчёта валют",
          "Only \(financeSymbol(currency)), no currency conversion"))
      FinancePeriodBar(format: format, today: today, period: $period)
      FinanceAreaChart(
        points: series, period: period, currency: currency, format: format, drawKey: key, log: log
      )
      .id(key)
      .padding(.top, 10)
      FinanceNotes(lines: notes)
    }
  }

  // MARK: Tiles

  private var statsBlock: some View {
    let stats = FinanceWallet.overviewStats(entries, currency: currency, period: period, today: today)
    let net = stats.incomeMinor - stats.expenseMinor
    var notes = [
      format.text(
        "Показатели \(format.periodLabel(period)), \(financeSymbol(currency)).",
        "Figures \(format.periodLabel(period)), \(financeSymbol(currency)).")
    ]
    notes.append(contentsOf: otherCurrencyLines())
    notes.append(
      format.text(
        "Переводы между своими счетами не считаются доходом или расходом.",
        "Transfers between your own accounts are not income or spending."))
    return VStack(alignment: .leading, spacing: 0) {
      FinanceStatTiles(
        stats: [
          counted(format.text("Доходы", "Income"), stats.incomeMinor, FinanceTone.income),
          counted(format.text("Расходы", "Spending"), -stats.expenseMinor, FinanceTone.expense),
          counted(format.text("Разница", "Net"), net, FinanceTone.net(net)),
        ])
      FinanceNotes(lines: notes)
    }
    .ritmPageReveal(index: 4)
  }

  /// One line per currency other than the shown one; the totals are never summed.
  private func otherCurrencyLines() -> [String] {
    currencies.filter { $0 != currency }.map { other in
      let value = FinanceWallet.overviewStats(entries, currency: other, period: period, today: today)
      let income = format.signed(value.incomeMinor, other)
      let spending = format.signed(-value.expenseMinor, other)
      let net = format.signed(value.incomeMinor - value.expenseMinor, other)
      return format.text(
        "\(format.currencyIn(other)): доходы \(income) · расходы \(spending) · разница \(net)",
        "\(format.currencyIn(other)): income \(income) · spending \(spending) · net \(net)")
    }
  }

  private func counted(_ title: String, _ minor: Int, _ tone: Color) -> FinanceStat {
    let format = self.format
    let currency = self.currency
    return .counted(title: title, amount: minor, tone: tone) { format.signed($0, currency) }
  }

  // MARK: Distribution

  private var distributionPanel: some View {
    FinancePanel(reveal: 5) {
      FinancePanelHead(
        title: format.text("Распределение", "Distribution"),
        sub: format.text("По счетам, отдельно для каждой валюты", "By account, per currency"))
      VStack(alignment: .leading, spacing: 16) {
        ForEach(currencies, id: \.self) { code in distributionGroup(code) }
      }
      .padding(.top, 4)
    }
  }

  private func distributionGroup(_ code: FinanceCurrency) -> some View {
    let shares = FinanceWallet.distribution(cards, currency: code)
    let total = shares.reduce(0) { $0 + $1.amountMinor }
    let key = "distribution-\(code.rawValue)-\(shares.count)"
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(format.currencyIn(code)).ritmFont(12).foregroundStyle(RitmTheme.muted)
        Spacer(minLength: 0)
        RitmCountText(total) { format.money($0, code) }
          .ritmFont(13, weight: .bold)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
      }
      .padding(.bottom, 8)
      if shares.isEmpty {
        Text(
          format.text(
            "Пока нет счетов с положительным остатком.", "No account has a positive balance yet.")
        )
        .ritmFont(11).foregroundStyle(RitmTheme.muted)
      } else {
        FinanceDistributionBar(shares: shares.map(\.share), drawKey: key, log: log)
          .id(key)
          .padding(.bottom, 6)
        VStack(spacing: 2) {
          ForEach(Array(shares.enumerated()), id: \.element.cardID) { index, share in
            distributionRow(share, index: index, currency: code)
          }
        }
      }
    }
  }

  /// `.legend li`: colour dot, name, amount and share, 36 pt tall.
  private func distributionRow(_ share: FinanceShare, index: Int, currency code: FinanceCurrency)
    -> some View
  {
    Button {
      openCard(share.cardID)
    } label: {
      HStack(spacing: 10) {
        Circle().fill(FinanceTone.chart(index)).frame(width: 10, height: 10)
          .frame(width: 12)
        Text(format.name(of: share.cardID) ?? "—")
          .ritmFont(12.5)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        RitmCountText(share.amountMinor) { format.money($0, code) }
          .ritmFont(12.5)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .layoutPriority(1)
        RitmCountText(Int((share.share * 100).rounded())) { "\($0)%" }
          .ritmFont(11.5)
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 40, alignment: .trailing)
      }
      .frame(minHeight: 36)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityElement(children: .combine)
  }

  // MARK: Recent operations

  private var recentSection: some View {
    let recent = FinanceWallet.recent(entries, limit: 6)
    return VStack(alignment: .leading, spacing: 0) {
      FinancePanelHead(title: format.text("Последние операции", "Recent operations"))
      if recent.isEmpty {
        FinanceEmptyText(text: format.text("Операций пока нет.", "No operations yet."))
      } else {
        FinanceDatedHistory(
          entries: recent, format: format, today: today, includeAccount: true, revealOffset: 6,
          open: actions.open)
        Button {
          showingHistory = true
        } label: {
          Text(format.text("Все операции", "All operations"))
            .ritmFont(12.5, weight: .bold)
            .foregroundStyle(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(RitmPressStyle())
        .padding(.top, 4)
      }
    }
    .ritmPageReveal(index: 6)
  }

  private func runHistoryFollowUp() {
    guard let next = historyFollowUp else { return }
    historyFollowUp = nil
    switch next {
    case .edit(let entry): actions.edit(entry)
    case .delete(let entry): actions.remove(entry)
    }
  }
}
