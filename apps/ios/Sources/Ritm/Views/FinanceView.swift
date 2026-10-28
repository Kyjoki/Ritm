import Charts
import RitmCore
import SwiftUI

private enum FinanceSection: String, CaseIterable { case account, deposits, stocks, all }
private struct FinanceEditing: Identifiable {
  let id = UUID()
  var entry: FinanceEntry?
  var kind: FinanceEntryKind
}

struct FinanceView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var entries: [FinanceEntry] = []
  @State private var currency: FinanceCurrency = .KZT
  @State private var section: FinanceSection = .account
  @State private var depositID = ""
  @State private var editing: FinanceEditing?
  @State private var deleting: FinanceEntry?
  @State private var loading = true
  @State private var loaded = false
  @State private var readID = UUID()

  private var visible: [FinanceEntry] { entries.filter { $0.currency == currency } }
  private var account: FinanceEntry? { visible.first { $0.type == .account } }
  private var deposits: [FinanceEntry] { visible.filter { $0.type == .deposit } }
  private var stocks: [FinanceEntry] { visible.filter { $0.type == .stock } }
  private var currentMonth: String { String(store.today.prefix(7)) }
  private func monthSum(_ kind: FinanceEntryKind, month: String? = nil) -> Int {
    visible.filter { $0.type == kind && $0.date?.hasPrefix(month ?? currentMonth) == true }
      .reduce(0) { $0 + ($1.amountMinor ?? 0) }
  }
  private var accountBalance: Int? {
    FinanceLedger.accountBalance(entries: visible, currency: currency, today: store.today)
  }
  private func depositBalance(_ id: String) -> Int? {
    FinanceLedger.depositBalance(entries: visible, depositId: id, today: store.today)
  }
  /// Same amount rule as the web record list: deposits show their balance, other assets
  /// their entered value, operations their amount.
  private func recordAmount(_ entry: FinanceEntry) -> Int {
    switch entry.type {
    case .deposit: depositBalance(entry.id) ?? 0
    case .account, .stock: entry.valueMinor ?? 0
    default: entry.amountMinor ?? 0
    }
  }
  private var total: Int? {
    switch section {
    case .account: return accountBalance
    case .deposits:
      return depositID.isEmpty
        ? deposits.reduce(0) { $0 + (depositBalance($1.id) ?? 0) } : depositBalance(depositID)
    case .stocks: return stocks.reduce(0) { $0 + ($1.valueMinor ?? 0) }
    case .all:
      guard let accountBalance else { return nil }
      return accountBalance + deposits.reduce(0) { $0 + (depositBalance($1.id) ?? 0) }
        + stocks.reduce(0) { $0 + ($1.valueMinor ?? 0) }
    }
  }
  private var records: [FinanceEntry] {
    visible.filter { entry in
      switch section {
      case .all: return true
      case .stocks: return entry.type == .stock
      case .deposits:
        return (entry.type == .deposit && (depositID.isEmpty || entry.id == depositID))
          || (entry.type == .transfer
            && (depositID.isEmpty || entry.fromAccountId == depositID
              || entry.toAccountId == depositID))
      case .account:
        if entry.type == .account { return true }
        if entry.type == .transfer {
          return entry.fromAccountId == account?.id || entry.toAccountId == account?.id
        }
        guard entry.type == .income || entry.type == .expense else { return false }
        guard let account else { return true }
        return (entry.date ?? "") >= (account.asOf ?? "") && (entry.date ?? "") <= store.today
      }
    }.sorted { ($0.date ?? $0.asOf ?? "", $0.createdAt) > ($1.date ?? $1.asOf ?? "", $1.createdAt) }
  }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text(store.text("Деньги под контролем", "Your money, clearly")).font(.largeTitle.bold())
          Text(
            store.text(
              "Личные записи. Без подключения к банкам.", "Personal records. No bank connection.")
          )
          .font(.subheadline).foregroundStyle(.secondary)
          if let message = store.errorMessage { RitmErrorBanner(message: message) }
          MutationRecoveryView()
          filters
          if loading && !loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
          } else if !loaded {
            RitmCard {
              RitmEmptyState(
                symbol: "wifi.exclamationmark",
                title: store.text("Данные недоступны", "Data unavailable"),
                message: store.text("Потяните вниз для повторной загрузки.", "Pull down to retry."))
            }
          } else {
            summaryCard
            if section == .account || section == .all {
              cashFlowChart
              expenseChart
            }
            if section == .stocks { stockResult }
            if section == .deposits || section == .stocks || section == .all { assetsChart }
            recordsCard
          }
        }.padding(20).padding(.bottom, 28).frame(maxWidth: 760).frame(maxWidth: .infinity)
      }.refreshable { await reload() }
    }
    .navigationTitle(store.text("Финансы", "Finance"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          ForEach(
            [FinanceEntryKind.income, .expense, .account, .deposit, .stock, .transfer], id: \.self
          ) { kind in
            Button {
              editing = FinanceEditing(kind: kind)
            } label: {
              Label(
                FinanceDisplay.title(kind, language: store.language),
                systemImage: FinanceDisplay.symbol(kind))
            }
          }
        } label: {
          Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
        }
        .disabled(!store.canWrite || !loaded)
        .accessibilityLabel(store.text("Добавить запись", "Add record"))
      }
    }
    .task(id: navigation.section) { if navigation.section == .finance { await reload() } }
    .onChange(of: store.lastSyncedAt) { _, _ in
      if navigation.section == .finance { Task { await reload() } }
    }
    .onChange(of: currency) { _, _ in depositID = "" }
    .sheet(item: $editing) { route in
      FinanceEditor(entry: route.entry, kind: route.kind, currency: currency, entries: entries) {
        await reload()
      }
    }
    .confirmationDialog(
      store.text("Удалить финансовую запись?", "Delete financial record?"),
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible
    ) {
      Button(store.text("Удалить", "Delete"), role: .destructive) {
        guard let entry = deleting else { return }
        Task {
          if await store.performMutation({
            try await $0.deleteFinanceEntry(id: entry.id, expectedUpdatedAt: entry.updatedAt)
          }) {
            await reload()
          }
        }
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(
        store.text(
          "Действие изменит расчёты. Связанные переводами счета нельзя удалить.",
          "This changes the totals. Accounts linked to transfers cannot be deleted."))
    }
  }

  private var filters: some View {
    VStack(spacing: 12) {
      Picker(store.text("Валюта", "Currency"), selection: $currency) {
        ForEach([FinanceCurrency.KZT, .USD, .EUR, .RUB], id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented)
      Picker(store.text("Раздел", "Section"), selection: $section) {
        Text(store.text("Счёт", "Account")).tag(FinanceSection.account)
        Text(store.text("Депозиты", "Deposits")).tag(FinanceSection.deposits)
        Text(store.text("Акции", "Stocks")).tag(FinanceSection.stocks)
        Text(store.text("Всё", "All")).tag(FinanceSection.all)
      }.pickerStyle(.segmented)
      if section == .deposits, !deposits.isEmpty {
        Picker(store.text("Депозит", "Deposit"), selection: $depositID) {
          Text(store.text("Все депозиты", "All deposits")).tag("")
          ForEach(deposits) { Text($0.name ?? "—").tag($0.id) }
        }.pickerStyle(.menu)
      }
    }
  }

  private var summaryCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 18) {
        Text(sectionTitle).font(.subheadline).foregroundStyle(.secondary)
        Text(total.map(money) ?? store.text("Не задан", "Not set"))
          .font(.largeTitle.bold()).contentTransition(.numericText())
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: total)
        if accountBalance == nil && (section == .account || section == .all) {
          Button(store.text("Задать начальный остаток", "Set opening balance")) {
            editing = FinanceEditing(entry: account, kind: .account)
          }
          .buttonStyle(.bordered).disabled(!store.canWrite)
        }
        if section == .account || section == .all {
          HStack(alignment: .top, spacing: 20) {
            metric(
              store.text("Доход за месяц", "Monthly income"), monthSum(.income),
              symbol: "arrow.down.left")
            metric(
              store.text("Расход за месяц", "Monthly spending"), monthSum(.expense),
              symbol: "arrow.up.right")
          }
        }
        Text(store.text("В расчёте только ", "Totals include only ") + currency.rawValue)
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var sectionTitle: String {
    switch section {
    case .account: store.text("Основной счёт", "Main account")
    case .deposits:
      deposits.first { $0.id == depositID }?.name ?? store.text("Депозиты", "Deposits")
    case .stocks: store.text("Текущая оценка акций", "Current stock valuation")
    case .all: store.text("Общий капитал", "Total balance")
    }
  }
  private func metric(_ title: String, _ amount: Int, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
      Text(money(amount)).font(.headline).contentTransition(.numericText())
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var monthKeys: [String] {
    (-5...0).compactMap {
      TaskSchedule.addMonths(to: String(store.today.prefix(7)) + "-01", months: $0)
    }.map { String($0.prefix(7)) }
  }
  private var cashFlowChart: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Text(store.text("Доходы и расходы", "Income and spending")).font(.headline)
        Chart {
          ForEach(monthKeys, id: \.self) { month in
            BarMark(
              x: .value("Month", String(month.suffix(2))),
              y: .value("Amount", Double(monthSum(.income, month: month)) / 100)
            )
            .foregroundStyle(by: .value("Kind", store.text("Доход", "Income")))
            .position(by: .value("Kind", store.text("Доход", "Income")))
            BarMark(
              x: .value("Month", String(month.suffix(2))),
              y: .value("Amount", Double(monthSum(.expense, month: month)) / 100)
            )
            .foregroundStyle(by: .value("Kind", store.text("Расход", "Expense")))
            .position(by: .value("Kind", store.text("Расход", "Expense")))
          }
        }.chartForegroundStyleScale(range: [RitmTheme.lavender, Color.pink.opacity(0.6)])
          .frame(height: 180).accessibilityLabel(
            store.text("Последние шесть месяцев, ", "Last six months, ") + currency.rawValue
          )
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visible)
      }
    }
  }
  private var expenseGroups: [(String, Int)] {
    let expenses = visible.filter {
      $0.type == .expense && $0.date?.hasPrefix(currentMonth) == true
    }
    return Dictionary(grouping: expenses, by: { $0.category ?? "" }).map {
      ($0.key, $0.value.reduce(0) { $0 + ($1.amountMinor ?? 0) })
    }.sorted { $0.1 > $1.1 }
  }
  private var expenseChart: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Text(store.text("Расходы по категориям", "Spending by category")).font(.headline)
        if expenseGroups.isEmpty {
          Text(store.text("В этом месяце расходов нет.", "No expenses this month."))
            .foregroundStyle(.secondary)
        } else {
          Chart(expenseGroups, id: \.0) { item in
            SectorMark(angle: .value("Amount", item.1), innerRadius: .ratio(0.68), angularInset: 2)
              .foregroundStyle(by: .value("Category", item.0))
          }.frame(height: 190).chartLegend(position: .bottom)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visible)
          ForEach(expenseGroups, id: \.0) { item in
            HStack {
              Text(item.0)
              Spacer()
              Text(money(item.1)).monospacedDigit()
            }.font(.subheadline)
          }
        }
      }
    }
  }
  private var assetsChart: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(store.text("Структура активов", "Asset allocation")).font(.headline)
        ForEach(
          visible.filter { entry in
            section == .all
              ? entry.type == .account || entry.type == .deposit || entry.type == .stock
              : section == .deposits ? entry.type == .deposit : entry.type == .stock
          }
        ) { entry in
          let value =
            entry.type == .account
            ? accountBalance ?? 0
            : entry.type == .deposit ? depositBalance(entry.id) ?? 0 : entry.valueMinor ?? 0
          HStack {
            Image(systemName: FinanceDisplay.symbol(entry.type)).foregroundStyle(.tint)
            Text(entry.name ?? FinanceDisplay.title(entry.type, language: store.language))
            Spacer()
            Text(money(value)).monospacedDigit()
          }.font(.subheadline)
        }
        if stocks.isEmpty && deposits.isEmpty {
          Text(store.text("Добавьте депозит или акции.", "Add a deposit or stocks."))
            .foregroundStyle(.secondary)
        }
      }
    }
  }
  private var stockResult: some View {
    let known = stocks.filter { $0.quantity != nil && $0.purchasePriceMinor != nil }
    let cost = known.reduce(0) { $0 + ($1.quantity ?? 0) * ($1.purchasePriceMinor ?? 0) }
    let gain = known.reduce(0) { $0 + ($1.valueMinor ?? 0) } - cost
    return RitmCard {
      VStack(alignment: .leading, spacing: 10) {
        Text(
          store.text(
            "Результат по известной цене покупки", "Result for holdings with a known purchase price"
          )
        ).font(.headline)
        Text(known.isEmpty ? "—" : money(gain)).font(.title2.bold())
        Text(
          store.text(
            "Цены обновляются вручную. Оценки не являются биржевыми котировками в реальном времени.",
            "Prices are updated manually. Valuations are not live market quotes.")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var recordsCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 16) {
        Text(store.text("История записей", "Records")).font(.headline)
        if records.isEmpty {
          RitmEmptyState(
            symbol: "wallet.pass", title: store.text("Пока нет записей", "No records yet"),
            message: store.text(
              "Добавьте первую запись кнопкой +.", "Add your first record with +."))
        }
        ForEach(records) { entry in
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
              Image(systemName: FinanceDisplay.symbol(entry.type)).foregroundStyle(.tint).frame(
                width: 26)
              VStack(alignment: .leading, spacing: 5) {
                Text(entryTitle(entry)).font(.headline)
                Text(
                  FeatureDate.label(
                    entry.date ?? entry.asOf ?? store.today, zone: store.timeZone,
                    language: store.language)
                ).font(.caption).foregroundStyle(.secondary)
              }
              Spacer(minLength: 4)
              Menu {
                Button(store.text("Изменить", "Edit"), systemImage: "pencil") {
                  editing = FinanceEditing(entry: entry, kind: entry.type)
                }
                Button(store.text("Удалить", "Delete"), systemImage: "trash", role: .destructive) {
                  deleting = entry
                }
              } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
              }.disabled(!store.canWrite)
            }
            Text(money(recordAmount(entry))).font(.title3.weight(.semibold))
            if entry.type == .deposit {
              // The row shows the live balance; the opening value stays visible below (FinancePage).
              Text(
                store.text("Стартовый остаток", "Opening balance") + ": "
                  + money(entry.valueMinor ?? 0)
              )
              .font(.subheadline).foregroundStyle(RitmTheme.muted)
            }
            if entry.type == .transfer {
              Text(accountName(entry.fromAccountId) + " → " + accountName(entry.toAccountId)).font(
                .subheadline)
            }
            if !entry.note.isEmpty {
              Text(entry.note).font(.subheadline).foregroundStyle(.secondary).textSelection(
                .enabled)
            }
            if entry.type == .stock, let url = quoteURL(entry) {
              Link(store.text("Открыть страницу биржи", "Open exchange page"), destination: url)
                .font(.subheadline).frame(minHeight: 44)
            }
          }
          if entry.id != records.last?.id { Divider() }
        }
      }
    }
  }
  private func money(_ amount: Int) -> String {
    FinanceDisplay.money(amount, currency: currency, language: store.language)
  }
  private func entryTitle(_ entry: FinanceEntry) -> String {
    entry.name ?? entry.category ?? FinanceDisplay.title(entry.type, language: store.language)
  }
  private func accountName(_ id: String?) -> String {
    guard let entry = entries.first(where: { $0.id == id }) else {
      return store.text("Счёт недоступен", "Account unavailable")
    }
    return entry.name ?? store.text("Основной счёт", "Main account")
  }
  private func quoteURL(_ entry: FinanceEntry) -> URL? {
    guard let ticker = entry.ticker,
      ticker.range(of: #"^[A-Z0-9._-]{1,30}$"#, options: .regularExpression) != nil
    else { return nil }
    return URL(
      string: entry.exchange == "AIX"
        ? "https://data-feed.aix.kz/symbol/\(ticker)/trading"
        : "https://kase.kz/en/investors/shares/\(ticker)/")
  }
  private func reload() async {
    guard navigation.section == .finance else { return }
    let ticket = UUID()
    readID = ticket
    loading = true
    let result = await store.read { try await $0.finance() }
    guard ticket == readID, !Task.isCancelled else { return }
    if let result {
      entries = result
      loaded = true
    }
    loading = false
  }
}
