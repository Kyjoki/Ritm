import RitmCore
import SwiftUI

/// Everything the page can do with an entry; the page owns the sheets and the writes.
struct FinanceActions {
  let canWrite: Bool
  let open: (FinanceEntry) -> Void
  let add: (FinanceEntryKind, FinanceCurrency) -> Void
  let edit: (FinanceEntry) -> Void
  let remove: (FinanceEntry) -> Void
}

// MARK: - Shared pieces

private struct FinanceCardTitle: View {
  let title: String
  var trailing: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).ritmText(.cardTitle).foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      if let trailing { Text(trailing).ritmFont(10).foregroundStyle(RitmTheme.muted) }
    }
  }
}

private struct FinanceEmptyLine: View {
  let text: String
  var body: some View {
    Text(text)
      .ritmFont(11, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private func financeDivider() -> some View {
  Rectangle().fill(RitmTheme.line).frame(height: 1)
}

// MARK: - Overview (cards stacked)

/// «Динамика средств», «Распределение» and «Последние операции» across all accounts.
struct FinanceOverviewSections: View {
  let entries: [FinanceEntry]
  let cards: [FinanceCard]
  let format: FinanceFormat
  let today: String
  let currencies: [FinanceCurrency]
  @Binding var currency: FinanceCurrency
  @Binding var period: FinancePeriod
  let log: FinanceDrawLog
  let actions: FinanceActions
  let openCard: (String) -> Void

  var body: some View {
    VStack(spacing: 12) {
      actionRow.ritmPageReveal(index: 2)
      dynamicsCard
      distributionCard
      recentCard
    }
  }

  private var actionRow: some View {
    HStack(spacing: 10) {
      Menu {
        ForEach([FinanceEntryKind.income, .expense, .transfer], id: \.self) { kind in
          Button {
            actions.add(kind, currency)
          } label: {
            Label(format.typeName(kind), systemImage: FinanceDisplay.symbol(kind))
          }
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
          Text(format.text("Операция", "Operation"))
        }
        .ritmText(.button)
        .foregroundStyle(RitmTheme.ctaInk)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RitmTheme.ctaGradient, in: RoundedRectangle(cornerRadius: 13, style: .circular))
        .shadow(color: RitmTheme.ctaShadow, radius: 13, y: 10)
      }
      .disabled(!actions.canWrite)
      Menu {
        ForEach([FinanceEntryKind.account, .deposit, .stock], id: \.self) { kind in
          Button {
            actions.add(kind, currency)
          } label: {
            Label(format.typeName(kind), systemImage: FinanceDisplay.symbol(kind))
          }
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
          Text(format.text("Счёт", "Account"))
        }
        .ritmText(.button)
        .foregroundStyle(RitmTheme.accentColor)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
          RoundedRectangle(cornerRadius: 13, style: .circular)
            .fill(RitmTheme.panel)
            .overlay {
              RoundedRectangle(cornerRadius: 13, style: .circular)
                .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
            }
        }
      }
      .disabled(!actions.canWrite)
    }
    .opacity(actions.canWrite ? 1 : 0.6)
  }

  private var dynamicsCard: some View {
    let series = FinanceWallet.overviewSeries(
      entries, currency: currency, period: period, today: today)
    let stats = FinanceWallet.overviewStats(entries, currency: currency, period: period, today: today)
    let key = "overview-\(currency.rawValue)-\(period.rawValue)"
    return RitmCard(reveal: 3) {
      VStack(alignment: .leading, spacing: 14) {
        FinanceCardTitle(
          title: format.text("Динамика средств", "Funds over time"),
          trailing: format.range(FinanceWallet.interval(period, today: today)))
        if currencies.count > 1 {
          FinanceSegment(
            label: format.text("Валюта", "Currency"), values: currencies, title: { $0.rawValue },
            selection: $currency)
        }
        FinanceSegment(
          label: format.text("Период", "Period"), values: FinancePeriod.allCases,
          title: { format.periodTitle($0) }, selection: $period)
        FinanceAreaChart(
          points: series, period: period, currency: currency, format: format, drawKey: key, log: log
        )
        .id(key)
        financeDivider()
        FinanceStatTiles(
          stats: [
            counted(
              format.text("Доходы", "Income"), stats.incomeMinor, FinanceTone.income, currency),
            counted(
              format.text("Расходы", "Spending"), -stats.expenseMinor, FinanceTone.expense,
              currency),
            counted(
              format.text("Разница", "Net"), stats.incomeMinor - stats.expenseMinor,
              FinanceTone.net(stats.incomeMinor - stats.expenseMinor), currency),
          ])
      }
    }
  }

  private func counted(
    _ title: String, _ minor: Int, _ tone: Color, _ currency: FinanceCurrency
  ) -> FinanceStat {
    let format = self.format
    return .counted(title: title, amount: minor, tone: tone) { format.signed($0, currency) }
  }

  private var distributionCard: some View {
    let shares = FinanceWallet.distribution(cards, currency: currency)
    let key = "distribution-\(currency.rawValue)-\(shares.count)"
    return RitmCard(reveal: 4) {
      VStack(alignment: .leading, spacing: 14) {
        FinanceCardTitle(
          title: format.text("Распределение по счетам", "Spread across accounts"),
          trailing: currency.rawValue)
        if shares.isEmpty {
          FinanceEmptyLine(
            text: format.text(
              "Пока нет счетов с положительным остатком.", "No account has a positive balance yet."))
        } else {
          FinanceDistributionBar(shares: shares.map(\.share), drawKey: key, log: log).id(key)
          VStack(spacing: 0) {
            ForEach(Array(shares.enumerated()), id: \.element.cardID) { index, share in
              if index > 0 { financeDivider() }
              distributionRow(share, index: index)
            }
          }
        }
      }
    }
  }

  private func distributionRow(_ share: FinanceShare, index: Int) -> some View {
    Button {
      openCard(share.cardID)
    } label: {
      HStack(spacing: 10) {
        Circle().fill(FinanceTone.chart(index)).frame(width: 10, height: 10)
        Text(format.name(of: share.cardID) ?? "—")
          .ritmFont(12, weight: .medium)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
        Spacer(minLength: 6)
        RitmCountText(share.amountMinor) { format.money($0, currency) }
          .ritmFont(12, weight: .semibold)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(1)
        RitmCountText(Int((share.share * 100).rounded())) { "\($0)%" }
          .ritmFont(11)
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 36, alignment: .trailing)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityElement(children: .combine)
  }

  private var recentCard: some View {
    let recent = FinanceWallet.recent(entries, limit: 6)
    return RitmCard(reveal: 5) {
      VStack(alignment: .leading, spacing: 8) {
        FinanceCardTitle(title: format.text("Последние операции", "Recent operations"))
        if recent.isEmpty {
          FinanceEmptyLine(text: format.text("Операций пока нет.", "No operations yet."))
        }
        ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
          if index > 0 { financeDivider() }
          FinanceOperationRow(
            entry: entry, format: format, includeAccount: true, action: { actions.open(entry) })
        }
      }
    }
  }
}

// MARK: - One account (cards expanded)

/// Only the selected card: period results, balance chart, categories or positions, history.
struct FinanceAccountSections: View {
  let card: FinanceCard
  let entries: [FinanceEntry]
  let format: FinanceFormat
  let today: String
  @Binding var period: FinancePeriod
  let log: FinanceDrawLog
  let actions: FinanceActions
  @State private var showAllHistory = false

  private static let historyLimit = 8

  private var entry: FinanceEntry? { entries.first(where: { $0.id == card.id }) }

  var body: some View {
    VStack(spacing: 12) {
      header.ritmPageReveal(index: 2)
      dynamicsCard
      switch card.kind {
      case .account: categoriesCard
      case .deposit: depositCard
      case .stocks: positionsCard
      }
      historyCard
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(format.name(card))
          .ritmFont(22, weight: .semibold, tracking: -0.04)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(2)
          .accessibilityAddTraits(.isHeader)
        balanceLine
          .ritmFont(11)
          .foregroundStyle(RitmTheme.muted)
      }
      Spacer(minLength: 0)
      menu
    }
    .padding(.top, 2)
  }

  /// «Баланс 1 250 000 ₸ · KZT»: the amount counts up when the account opens or changes.
  @ViewBuilder private var balanceLine: some View {
    if let balance = card.balanceMinor {
      let currency = card.currency
      RitmCountText(balance) {
        format.text("Баланс ", "Balance ") + format.money($0, currency) + " · "
          + currency.rawValue
      }
    } else {
      Text(format.text("Данные выбранного счёта", "Selected account"))
    }
  }

  private var menu: some View {
    Menu {
      switch card.kind {
      case .account:
        addButton(.income)
        addButton(.expense)
        addButton(.transfer)
      case .deposit:
        addButton(.transfer)
      case .stocks:
        addButton(.stock)
      }
      if let entry, card.kind != .stocks {
        Button {
          actions.edit(entry)
        } label: {
          Label(format.text("Изменить", "Edit"), systemImage: "pencil")
        }
        Button(role: .destructive) {
          actions.remove(entry)
        } label: {
          Label(format.text("Удалить", "Delete"), systemImage: "trash")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 44, height: 44)
        .background {
          RoundedRectangle(cornerRadius: 13, style: .circular)
            .fill(RitmTheme.panel)
            .overlay {
              RoundedRectangle(cornerRadius: 13, style: .circular)
                .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
            }
        }
    }
    .disabled(!actions.canWrite)
    .accessibilityLabel(format.text("Действия со счётом", "Account actions"))
  }

  private func addButton(_ kind: FinanceEntryKind) -> some View {
    Button {
      actions.add(kind, card.currency)
    } label: {
      Label(format.typeName(kind), systemImage: FinanceDisplay.symbol(kind))
    }
  }

  // MARK: Balance

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
            title: format.text("Оценка", "Valuation"), amount: balance, tone: RitmTheme.text
          ) { format.money($0, currency) }
        }
          ?? FinanceStat(
            title: format.text("Оценка", "Valuation"), value: "—", tone: RitmTheme.text),
        gains.isEmpty
          ? FinanceStat(
            title: format.text("Результат", "Result"), value: "—", tone: FinanceTone.net(result))
          : signed(format.text("Результат", "Result"), result, FinanceTone.net(result)),
        FinanceStat.counted(
          title: format.text("Позиции", "Positions"),
          amount: FinanceWallet.positions(entries, currency: card.currency).count,
          tone: RitmTheme.text
        ) { "\($0)" },
      ]
    case .deposit:
      let value = FinanceWallet.stats(entries, card: card, period: period, today: today)
      return [
        signed(format.text("Пополнения", "Deposits"), value.transfersInMinor, FinanceTone.income),
        signed(format.text("Снятия", "Withdrawals"), -value.transfersOutMinor, FinanceTone.expense),
        signed(format.text("Разница", "Net"), value.netMinor, FinanceTone.net(value.netMinor)),
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

  private var dynamicsCard: some View {
    let series = FinanceWallet.balanceSeries(entries, card: card, period: period, today: today)
    let key = "card-\(card.id)-\(period.rawValue)"
    let moved = FinanceWallet.stats(entries, card: card, period: period, today: today)
    return RitmCard(reveal: 3) {
      VStack(alignment: .leading, spacing: 14) {
        FinanceCardTitle(
          title: format.text("Динамика баланса", "Balance over time"),
          trailing: format.range(FinanceWallet.interval(period, today: today)))
        FinanceSegment(
          label: format.text("Период", "Period"), values: FinancePeriod.allCases,
          title: { format.periodTitle($0) }, selection: $period)
        FinanceAreaChart(
          points: series, period: period, currency: card.currency, format: format, drawKey: key,
          log: log
        )
        .id(key)
        financeDivider()
        FinanceStatTiles(stats: stats)
        if card.kind == .account, moved.transfersInMinor > 0 || moved.transfersOutMinor > 0 {
          Text(
            format.text("Переводы между счетами: ", "Transfers between accounts: ")
              + format.signed(moved.transfersInMinor, card.currency) + " · "
              + format.signed(-moved.transfersOutMinor, card.currency)
          )
          .ritmFont(10)
          .foregroundStyle(RitmTheme.muted)
        }
      }
    }
  }

  // MARK: Kind specific

  private var categoriesCard: some View {
    let slices = FinanceWallet.categories(
      entries, card: card, period: period, today: today)
    let key = "categories-\(card.id)-\(period.rawValue)"
    return RitmCard(reveal: 4) {
      VStack(alignment: .leading, spacing: 14) {
        FinanceCardTitle(title: format.text("Расходы по категориям", "Spending by category"))
        if slices.isEmpty {
          FinanceEmptyLine(
            text: format.text(
              "За этот период расходов нет.", "No spending in this period."))
        } else {
          FinanceDonut(
            slices: slices, currency: card.currency, format: format, drawKey: key, log: log
          )
          .id(key)
        }
      }
    }
  }

  private var depositCard: some View {
    RitmCard(reveal: 4) {
      VStack(alignment: .leading, spacing: 10) {
        FinanceCardTitle(title: format.text("О депозите", "About the deposit"))
        if let entry {
          infoRow(
            format.text("Стартовый остаток", "Opening balance"),
            format.money(entry.valueMinor ?? 0, entry.currency))
          if let asOf = entry.asOf {
            infoRow(format.text("На дату", "As of"), format.date(asOf, template: "d MMMM yyyy"))
          }
        }
        if card.balanceMinor == nil, let asOf = card.asOf {
          FinanceEmptyLine(
            text: format.text(
              "Депозит учитывается с \(format.date(asOf, template: "d MMMM yyyy")).",
              "The deposit counts from \(format.date(asOf, template: "d MMMM yyyy"))."))
        }
        FinanceEmptyLine(
          text: format.text(
            "Баланс = стартовый остаток + переводы. Доходы и расходы депозит не меняют.",
            "Balance = opening balance + transfers. Income and spending never touch a deposit."))
      }
    }
  }

  private func infoRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).ritmFont(11).foregroundStyle(RitmTheme.muted)
      Spacer(minLength: 8)
      Text(value).ritmFont(12, weight: .medium).monospacedDigit().foregroundStyle(RitmTheme.text)
    }
    .accessibilityElement(children: .combine)
  }

  private var positionsCard: some View {
    let positions = FinanceWallet.positions(entries, currency: card.currency)
    return RitmCard(reveal: 4) {
      VStack(alignment: .leading, spacing: 8) {
        FinanceCardTitle(title: format.text("Позиции", "Positions"))
        if positions.isEmpty {
          FinanceEmptyLine(text: format.text("Акций пока нет.", "No stocks yet."))
        }
        ForEach(Array(positions.enumerated()), id: \.element.id) { index, position in
          if index > 0 { financeDivider() }
          positionRow(position)
        }
        FinanceEmptyLine(
          text: format.text(
            "Цены обновляются вручную. Это не биржевые котировки в реальном времени.",
            "Prices are updated manually. They are not live market quotes."))
      }
    }
  }

  private func positionRow(_ position: FinancePosition) -> some View {
    Button {
      if let target = entries.first(where: { $0.id == position.id }) { actions.open(target) }
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(position.name).ritmFont(12, weight: .bold).foregroundStyle(RitmTheme.text).lineLimit(1)
          Text(positionMeta(position)).ritmFont(10).foregroundStyle(RitmTheme.muted).lineLimit(1)
        }
        Spacer(minLength: 6)
        VStack(alignment: .trailing, spacing: 2) {
          Text(format.money(position.valueMinor, card.currency))
            .ritmFont(12, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(RitmTheme.text)
          if let gain = position.gainMinor {
            Text(format.signed(gain, card.currency))
              .ritmFont(10, weight: .medium)
              .monospacedDigit()
              .foregroundStyle(FinanceTone.net(gain))
          }
        }
      }
      .frame(minHeight: 52)
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

  private var historyCard: some View {
    let history = FinanceWallet.history(entries, card: card)
    let shown = showAllHistory ? history : Array(history.prefix(Self.historyLimit))
    return RitmCard(reveal: 5) {
      VStack(alignment: .leading, spacing: 8) {
        FinanceCardTitle(title: format.text("История операций", "Operation history"))
        if history.isEmpty {
          FinanceEmptyLine(text: format.text("По этому счёту операций пока нет.", "No operations on this account yet."))
        }
        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
          if index > 0 { financeDivider() }
          FinanceOperationRow(
            entry: item, format: format, includeAccount: false, action: { actions.open(item) })
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
            .ritmFont(12, weight: .semibold)
            .foregroundStyle(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(RitmPressStyle())
        }
      }
    }
  }
}
