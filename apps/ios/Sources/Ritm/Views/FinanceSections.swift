import RitmCore
import SwiftUI

// MARK: - One account (cards expanded)

/// Only the selected card, in the prototype's order: the header (name, kind and currency,
/// balance, the card-settings button), the three tiles with their note, then by kind the balance
/// chart and the expense categories, the deposit terms or the positions, and the history.
struct FinanceAccountSections: View {
  let card: FinanceCard
  let entries: [FinanceEntry]
  let format: FinanceFormat
  let today: String
  @Binding var period: FinancePeriod
  let log: FinanceDrawLog
  let actions: FinanceActions
  let customize: () -> Void
  /// A `deposit` entry the owner calls «Счёт»: no deposit wording.
  var plain = false
  @State private var showAllHistory = false

  private static let historyLimit = 6

  private var entry: FinanceEntry? { entries.first(where: { $0.id == card.id }) }

  /// A named account that has income or expense of its own shows the account's tiles and
  /// categories; one that only takes transfers keeps the deposit wording.
  private var hasOperations: Bool {
    card.kind == .account || entries.contains { FinanceWallet.operation($0, belongsTo: card) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header.ritmPageReveal(index: 2)
      if card.kind != .stocks { operationRow.ritmPageReveal(index: 2) }
      switch card.kind {
      case .account:
        statsBlock
        dynamicsPanel
        categoriesPanel
      case .deposit:
        statsBlock
        depositPanel
        dynamicsPanel
        if hasOperations { categoriesPanel }
      case .stocks:
        statsBlock
        positionsPanel
      }
      historySection
    }
  }

  // MARK: Header

  private var kindName: String {
    switch card.kind {
    case .account: format.text("Основной счёт", "Main account")
    case .deposit: plain ? format.text("Счёт", "Account") : format.text("Депозит", "Deposit")
    case .stocks: format.text("Брокерский счёт", "Brokerage account")
    }
  }

  private var currencyName: String {
    switch card.currency {
    case .KZT: format.text("Тенге (KZT)", "Tenge (KZT)")
    case .USD: format.text("Доллар США (USD)", "US dollar (USD)")
    case .EUR: format.text("Евро (EUR)", "Euro (EUR)")
    case .RUB: format.text("Российский рубль (RUB)", "Russian rouble (RUB)")
    }
  }

  /// `.d-head`: 22 pt name, 12 pt kind line, 30 pt balance; the settings button sits on the right.
  private var header: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 0) {
        Text(format.name(card))
          .ritmFont(22, weight: .semibold, tracking: -0.05)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(2)
          .accessibilityAddTraits(.isHeader)
        Text(kindName + " · " + currencyName)
          .ritmFont(12)
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 1)
        balanceLine
          .ritmFont(30, weight: .bold, tracking: -0.055)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .padding(.top, 6)
      }
      Spacer(minLength: 0)
      FinanceCustomizeButton(format: format, action: customize)
        .padding(.top, 2)
    }
    .padding(.horizontal, 2)
  }

  /// «+ Операция» right under the header: income, expense or transfer on this very card.
  private var operationRow: some View {
    FinanceOperationMenu(format: format, canWrite: actions.canWrite) { kind in
      actions.add(kind, card.currency, card.id)
    }
    .opacity(actions.canWrite ? 1 : 0.6)
  }

  @ViewBuilder private var balanceLine: some View {
    if let balance = card.balanceMinor {
      let currency = card.currency
      RitmCountText(balance) { format.money($0, currency) }
    } else {
      Text("—")
    }
  }

  // MARK: Tiles

  private var stats: [FinanceStat] {
    let currency = card.currency
    let format = self.format
    func signed(_ title: String, _ minor: Int, _ tone: Color) -> FinanceStat {
      .counted(title: title, amount: minor, tone: tone) { format.signed($0, currency) }
    }
    switch card.kind {
    case .stocks:
      let gains = FinanceWallet.positions(entries, currency: card.currency).compactMap(\.gainMinor)
      let result = gains.reduce(0, +)
      return [
        card.balanceMinor.map { balance in
          FinanceStat.counted(
            title: format.text("Стоимость", "Value"), amount: balance, tone: RitmTheme.text
          ) { format.money($0, currency) }
        }
          ?? FinanceStat(
            title: format.text("Стоимость", "Value"), value: "—", tone: RitmTheme.text),
        FinanceStat.counted(
          title: format.text("Позиции", "Positions"),
          amount: FinanceWallet.positions(entries, currency: card.currency).count,
          tone: RitmTheme.text
        ) { "\($0)" },
        gains.isEmpty
          ? FinanceStat(
            title: format.text("Результат", "Result"), value: "—", tone: FinanceTone.net(result))
          : signed(format.text("Результат", "Result"), result, FinanceTone.net(result)),
      ]
    case .deposit where hasOperations:
      let value = FinanceWallet.stats(entries, card: card, period: period, today: today)
      return [
        signed(format.text("Поступления", "Income"), value.incomeMinor, FinanceTone.income),
        signed(format.text("Расходы", "Spending"), -value.expenseMinor, FinanceTone.expense),
        signed(format.text("Разница", "Net"), value.netMinor, FinanceTone.net(value.netMinor)),
      ]
    case .deposit:
      let value = FinanceWallet.stats(entries, card: card, period: period, today: today)
      return [
        signed(format.text("Пополнения", "Deposits"), value.transfersInMinor, FinanceTone.income),
        signed(format.text("Снятия", "Withdrawals"), -value.transfersOutMinor, FinanceTone.expense),
        signed(format.text("Итого", "Total"), value.netMinor, FinanceTone.net(value.netMinor)),
      ]
    case .account:
      let value = FinanceWallet.stats(entries, card: card, period: period, today: today)
      return [
        signed(format.text("Поступления", "Income"), value.incomeMinor, FinanceTone.income),
        signed(format.text("Расходы", "Spending"), -value.expenseMinor, FinanceTone.expense),
        signed(format.text("Разница", "Net"), value.netMinor, FinanceTone.net(value.netMinor)),
      ]
    }
  }

  private var statsBlock: some View {
    var notes: [String] = []
    switch card.kind {
    case .account:
      notes = [
        format.text(
          "Показатели \(format.periodLabel(period)).", "Figures \(format.periodLabel(period)).")
      ]
    case .deposit where hasOperations:
      notes = [
        format.text(
          "Показатели \(format.periodLabel(period)). Разница включает переводы между своими счетами.",
          "Figures \(format.periodLabel(period)). Net includes transfers between your own accounts.")
      ]
    case .deposit:
      notes = [
        format.text(
          "Показатели \(format.periodLabel(period)). Это переводы между своими счетами, не доходы и не расходы.",
          "Figures \(format.periodLabel(period)). These are transfers from your own accounts, not income or spending."
        )
      ]
    case .stocks: break
    }
    return VStack(alignment: .leading, spacing: 0) {
      FinanceStatTiles(stats: stats)
      FinanceNotes(lines: notes)
    }
    .ritmPageReveal(index: 3)
  }

  // MARK: Chart

  private var dynamicsPanel: some View {
    let series = FinanceWallet.balanceSeries(entries, card: card, period: period, today: today)
    let key = "card-\(card.id)-\(period.rawValue)"
    let notes = [financeShortWindow(asOf: card.asOf, period: period, today: today, format: format)]
      .compactMap { $0 }
    return FinancePanel(reveal: 4) {
      FinancePanelHead(
        title: format.text("Динамика баланса", "Balance over time"), sub: format.name(card))
      FinancePeriodBar(format: format, today: today, period: $period)
      FinanceAreaChart(
        points: series, period: period, currency: card.currency, format: format, drawKey: key,
        log: log
      )
      .id(key)
      .padding(.top, 10)
      FinanceNotes(lines: notes)
    }
  }

  // MARK: Kind specific

  private var categoriesPanel: some View {
    let slices = FinanceWallet.categories(entries, card: card, period: period, today: today)
    let key = "categories-\(card.id)-\(period.rawValue)"
    return FinancePanel(reveal: 5) {
      FinancePanelHead(
        title: format.text("Расходы по категориям", "Spending by category"),
        sub: format.periodTitle(period))
      if slices.isEmpty {
        FinanceEmptyText(
          text: format.text("За этот период расходов нет.", "No spending in this period."))
      } else {
        FinanceDonut(
          slices: slices, currency: card.currency, format: format, drawKey: key, log: log
        )
        .id(key)
      }
    }
  }

  private var depositPanel: some View {
    FinancePanel(reveal: 4) {
      FinancePanelHead(title: plain ? format.text("О счёте", "About the account") : format.text("Условия депозита", "Deposit terms"))
      VStack(alignment: .leading, spacing: 0) {
        if let entry {
          infoRow(
            format.text("Стартовый остаток", "Opening balance"),
            format.money(entry.valueMinor ?? 0, entry.currency), first: true)
          if let asOf = entry.asOf {
            infoRow(format.text("На дату", "As of"), format.date(asOf, template: "d MMMM yyyy"))
          }
        }
      }
      if card.balanceMinor == nil, let asOf = card.asOf {
        FinanceNotes(
          lines: [
            format.text(
              (plain ? "Счёт" : "Депозит")
                + " учитывается с \(format.date(asOf, template: "d MMMM yyyy")).",
              "The account counts from \(format.date(asOf, template: "d MMMM yyyy")).")
          ])
      }
      FinanceNotes(
        lines: [
          format.text(
            "Баланс = стартовый остаток + переводы + доходы и расходы, записанные на этот счёт.",
            "Balance = opening balance + transfers + income and spending recorded on this account.")
        ])
    }
  }

  /// `.kv`: a muted label and a semibold value, 12.5 pt, a hairline above every row but the first.
  private func infoRow(_ label: String, _ value: String, first: Bool = false) -> some View {
    VStack(spacing: 0) {
      if !first { financeDivider() }
      HStack {
        Text(label).ritmFont(12.5).foregroundStyle(RitmTheme.muted)
        Spacer(minLength: 14)
        Text(value)
          .ritmFont(12.5, weight: .semibold)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .layoutPriority(1)
      }
      .padding(.vertical, 10)
    }
    .accessibilityElement(children: .combine)
  }

  private var positionsPanel: some View {
    let positions = FinanceWallet.positions(entries, currency: card.currency)
    return FinancePanel(reveal: 4) {
      FinancePanelHead(title: format.text("Позиции", "Positions"))
      if positions.isEmpty {
        FinanceEmptyText(text: format.text("Акций пока нет.", "No stocks yet."))
      }
      ForEach(Array(positions.enumerated()), id: \.element.id) { index, position in
        if index > 0 { financeDivider() }
        positionRow(position)
      }
      FinanceNotes(
        lines: [
          format.text(
            "Цены обновляются вручную. Это не биржевые котировки в реальном времени.",
            "Prices are updated manually. They are not live market quotes.")
        ])
    }
  }

  /// `.pos-row`: name and value in 13 pt bold, the details and the result in 11 pt under them.
  private func positionRow(_ position: FinancePosition) -> some View {
    Button {
      if let target = entries.first(where: { $0.id == position.id }) { actions.open(target) }
    } label: {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(position.name).ritmFont(13, weight: .bold).foregroundStyle(RitmTheme.text).lineLimit(2)
          Text(positionMeta(position)).ritmFont(11).foregroundStyle(RitmTheme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(format.money(position.valueMinor, card.currency))
            .ritmFont(13, weight: .bold)
            .monospacedDigit()
            .foregroundStyle(RitmTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
          if let gain = position.gainMinor {
            Text(format.signed(gain, card.currency))
              .ritmFont(11)
              .monospacedDigit()
              .foregroundStyle(FinanceTone.net(gain))
              .lineLimit(1)
              .minimumScaleFactor(0.6)
          }
        }
        .layoutPriority(1)
      }
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityElement(children: .combine)
  }

  private func positionMeta(_ position: FinancePosition) -> String {
    var parts: [String] = []
    if let ticker = position.ticker { parts.append(ticker) }
    if let exchange = position.exchange { parts.append(exchange) }
    if let quantity = position.quantity { parts.append("\(quantity) " + format.text("шт.", "pcs")) }
    return parts.joined(separator: " · ")
  }

  // MARK: History

  private var historySection: some View {
    let history = FinanceWallet.history(entries, card: card)
    let shown = showAllHistory ? history : Array(history.prefix(Self.historyLimit))
    return VStack(alignment: .leading, spacing: 0) {
      FinancePanelHead(title: format.text("История операций", "Operation history")) {
        addButton
      }
      if history.isEmpty {
        FinanceEmptyText(
          text: format.text(
            "По этому счёту операций пока нет.", "No operations on this account yet."))
      } else {
        FinanceDatedHistory(
          entries: shown, format: format, today: today, includeAccount: false, revealOffset: 6,
          open: actions.open)
      }
      if history.count > Self.historyLimit {
        Button {
          withAnimation(RitmMotion.indicator) { showAllHistory.toggle() }
        } label: {
          Text(
            showAllHistory
              ? format.text("Свернуть", "Show less")
              : format.text("Показать все (\(history.count))", "Show all (\(history.count))")
          )
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

  /// `.btn.sm`: the small «+ Операция» button of the history header. A brokerage account adds a
  /// position instead; an account or deposit opens the form on «Расход» of this very card.
  private var addButton: some View {
    Button {
      switch card.kind {
      case .account, .deposit: actions.add(.expense, card.currency, card.id)
      case .stocks: actions.add(.stock, card.currency, nil)
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
        Text(
          card.kind == .stocks
            ? format.text("Позиция", "Position") : format.text("Операция", "Operation"))
      }
      .ritmFont(12, weight: .bold)
    }
    .buttonStyle(RitmSecondaryButtonStyle(minHeight: 44))
    .disabled(!actions.canWrite)
    .padding(.top, -8)
  }
}
