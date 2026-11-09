import RitmCore
import SwiftUI

/// The account types of the form: the server's `account` and `stock`, and its `deposit` in two
/// flavours the owner tells apart on this device («Счёт» and «Депозит»).
private enum FinanceAccountTab: Hashable { case main, plain, deposit, stock }

struct FinanceEditor: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let entry: FinanceEntry?
  let entries: [FinanceEntry]
  let accountKinds: FinanceAccountKindStore
  let onSave: () async -> Void
  /// The card the owner is looking at: the account an operation starts on.
  let cardID: String?
  /// A `deposit` entry saved as «Счёт» (no deposit wording); remembered in `accountKinds`.
  @State private var plain: Bool
  @State private var kind: FinanceEntryKind
  @State private var currency: FinanceCurrency
  @State private var amount = ""
  @State private var date = ""
  @State private var category = ""
  @State private var name = ""
  @State private var note = ""
  @State private var exchange = "KASE"
  @State private var ticker = ""
  @State private var quantity = ""
  @State private var unitPrice = ""
  @State private var purchasePrice = ""
  @State private var fromID = ""
  @State private var toID = ""
  /// The account an income or expense is booked into («Счёт»).
  @State private var accountID = ""
  @State private var validation: String?
  @State private var saving = false

  init(
    entry: FinanceEntry?, kind: FinanceEntryKind, currency: FinanceCurrency,
    entries: [FinanceEntry], accountKinds: FinanceAccountKindStore, cardID: String? = nil,
    onSave: @escaping () async -> Void
  ) {
    self.entry = entry
    self.cardID = cardID
    self.entries = entries
    self.accountKinds = accountKinds
    self.onSave = onSave
    // A new extra account starts as «Счёт»; an existing one keeps what the owner chose.
    _plain = State(initialValue: entry.map { accountKinds.isPlain($0.id) } ?? true)
    _kind = State(initialValue: entry?.type ?? kind)
    _currency = State(initialValue: entry?.currency ?? currency)
    _amount = State(initialValue: FinanceDisplay.decimal(entry?.amountMinor ?? entry?.valueMinor))
    _date = State(initialValue: entry?.date ?? entry?.asOf ?? "")
    _category = State(initialValue: entry?.category ?? "")
    _name = State(initialValue: entry?.name ?? "")
    _note = State(initialValue: entry?.note ?? "")
    _exchange = State(initialValue: entry?.exchange ?? "KASE")
    _ticker = State(initialValue: entry?.ticker ?? "")
    _quantity = State(initialValue: entry?.quantity.map(String.init) ?? "")
    _unitPrice = State(initialValue: FinanceDisplay.decimal(entry?.unitPriceMinor))
    _purchasePrice = State(initialValue: FinanceDisplay.decimal(entry?.purchasePriceMinor))
    _fromID = State(initialValue: entry?.fromAccountId ?? "")
    _toID = State(initialValue: entry?.toAccountId ?? "")
    let shownCurrency = entry?.currency ?? currency
    _accountID = State(
      initialValue: entry?.type == .income || entry?.type == .expense
        ? FinanceOperationAccount.preselected(
          entries, currency: shownCurrency, card: entry?.accountId)
        : FinanceOperationAccount.preselected(
          entries, currency: shownCurrency, card: cardID,
          lastUsed: Self.lastAccount(shownCurrency)))
  }
  private var accounts: [FinanceEntry] {
    entries.filter { ($0.type == .account || $0.type == .deposit) && $0.currency == currency }
  }
  private var isTransaction: Bool { kind == .income || kind == .expense || kind == .transfer }

  private var isAccountGroup: Bool { kind == .account || kind == .deposit || kind == .stock }
  private var title: String {
    guard entry == nil else {
      return kind == .deposit
        ? (plain ? store.text("Изменить счёт", "Edit account") : store.text("Изменить депозит", "Edit deposit"))
        : FinanceDisplay.title(kind, language: store.language)
    }
    return isTransaction
      ? store.text("Новая операция", "New operation") : store.text("Новый счёт", "New account")
  }

  var body: some View {
    FinanceSheetFrame(title: title) {
      if entry == nil && store.uncertainWrite {
        Button(store.text("Закрыть и проверить список", "Close and check the list")) { dismiss() }
          .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
          .disabled(saving)
      } else {
        MutationRecoveryView()
      }
      if entry == nil || kind == .deposit { typeControl }
      FinanceField(store.text("Валюта", "Currency")) {
        FinanceSelect(
          options: [FinanceCurrency.KZT, .USD, .EUR, .RUB].map { ($0, currencyTitle($0)) },
          selection: $currency, disabled: entry != nil)
      }
      FinanceField(store.text("Дата", "Date")) {
        DateKeyPicker(title: store.text("Дата", "Date"), value: $date, zone: store.timeZone)
          .labelsHidden()
          .tint(RitmTheme.accentColor)
          .financeInput()
      }
      if kind == .income || kind == .expense { accountPicker }
      if kind == .deposit || kind == .stock {
        FinanceField(store.text("Название", "Name")) {
          FinanceTextInput(placeholder: namePlaceholder, text: $name)
        }
      }
      if kind == .transfer { transferFields }
      if kind == .stock { stockFields }
      if kind != .stock || quantity.isEmpty {
        FinanceField(
          store.text(
            isTransaction ? "Сумма" : "Начальная стоимость",
            isTransaction ? "Amount" : "Opening value")
        ) {
          FinanceAmountInput(placeholder: "0", text: $amount, symbol: sign)
        }
        if kind == .account || kind == .deposit {
          FinanceFormNote(
            text: store.text(
              "Остаток до операций в указанную дату. Переводы после этой даты учитываются отдельно.",
              "Balance before transactions on this date. Later transfers are calculated separately."
            ))
        }
      }
      if kind == .income || kind == .expense { categoryPicker }
      FinanceField(store.text("Заметка", "Note")) {
        TextField(store.text("Необязательно", "Optional"), text: $note, axis: .vertical)
          .lineLimit(1...4)
          .financeInput()
      }
      FinanceFormError(message: validation)
      FinanceFormError(message: store.errorMessage)
      if saving { ProgressView(store.text("Сохраняем…", "Saving…")) }
      FinanceFormButtons(
        cancelTitle: store.text("Отмена", "Cancel"),
        saveTitle: entry == nil && isAccountGroup
          ? store.text("Добавить", "Add") : store.text("Сохранить", "Save"),
        canSave: store.canWrite && !saving,
        cancel: { dismiss() }, save: { Task { await save() } })
    }
    .interactiveDismissDisabled(saving)
    .task {
      if entry == nil, kind == .account, !mainAvailable { kind = .deposit }
      if date.isEmpty { date = store.today }
      if fromID.isEmpty {
        let open = accounts.first { $0.id == cardID }?.id
        fromID = open ?? accounts.first(where: { $0.type == .account })?.id ?? accounts.first?.id ?? ""
      }
      if toID.isEmpty { toID = accounts.first(where: { $0.id != fromID })?.id ?? "" }
    }
    .onChange(of: currency) { _, _ in
      fromID = ""
      toID = ""
      accountID = FinanceOperationAccount.preselected(
        entries, currency: currency, card: cardID, lastUsed: Self.lastAccount(currency))
      // A second main account in one currency is refused: use a named account instead.
      if entry == nil, kind == .account, !mainAvailable { kind = .deposit }
    }
  }

  /// The server keeps one unnamed main account per currency; every further account is a named
  /// `deposit` record (it takes transfers, not income or expenses).
  private var mainAvailable: Bool {
    !entries.contains { $0.type == .account && $0.currency == currency }
  }

  private var namePlaceholder: String {
    kind == .deposit && plain
      ? store.text("Например, Kaspi Gold", "For example, Kaspi Gold")
      : store.text("Название", "Name")
  }

  private var sign: String {
    switch currency {
    case .KZT: "₸"
    case .USD: "$"
    case .EUR: "€"
    case .RUB: "₽"
    }
  }

  private func currencyTitle(_ code: FinanceCurrency) -> String {
    switch code {
    case .KZT: store.text("Тенге (₸)", "Tenge (₸)")
    case .USD: store.text("Доллар США ($)", "US dollar ($)")
    case .EUR: store.text("Евро (€)", "Euro (€)")
    case .RUB: store.text("Рубль (₽)", "Rouble (₽)")
    }
  }

  /// `Расход / Поступление / Перевод` or `Счёт / Депозит / Акции`: only for a new record.
  @ViewBuilder private var typeControl: some View {
    if isTransaction {
      RitmSegmentedControl(
        label: store.text("Тип операции", "Operation type"),
        values: [FinanceEntryKind.expense, .income, .transfer],
        title: { typeTitle($0) }, selection: kindBinding, fontSize: 12.5)
    } else {
      RitmSegmentedControl(
        label: store.text("Тип счёта", "Account type"),
        values: accountTabs,
        title: { tabTitle($0) }, selection: tabBinding, fontSize: 12.5)
    }
  }

  /// «Основной» only while the currency has no main account; an existing deposit-type record
  /// can switch between «Счёт» and «Депозит» but not become another kind of entry.
  private var accountTabs: [FinanceAccountTab] {
    if entry != nil { return [.plain, .deposit] }
    return mainAvailable ? [.main, .plain, .deposit, .stock] : [.plain, .deposit, .stock]
  }

  private func tabTitle(_ tab: FinanceAccountTab) -> String {
    switch tab {
    case .main: store.text("Основной", "Main")
    case .plain: store.text("Счёт", "Account")
    case .deposit: store.text("Депозит", "Deposit")
    case .stock: store.text("Акции", "Stocks")
    }
  }

  private var tabBinding: Binding<FinanceAccountTab> {
    Binding(
      get: {
        switch kind {
        case .account: .main
        case .stock: .stock
        default: plain ? .plain : .deposit
        }
      },
      set: { next in
        switch next {
        case .main: kind = .account
        case .plain:
          kind = .deposit
          plain = true
        case .deposit:
          kind = .deposit
          plain = false
        case .stock: kind = .stock
        }
      })
  }

  private func typeTitle(_ value: FinanceEntryKind) -> String {
    switch value {
    case .expense: store.text("Расход", "Expense")
    case .income: store.text("Поступление", "Income")
    case .transfer: store.text("Перевод", "Transfer")
    case .account: store.text("Основной", "Main")
    case .deposit: store.text("Счёт", "Account")
    case .stock: store.text("Акции", "Stocks")
    }
  }

  private var kindBinding: Binding<FinanceEntryKind> {
    Binding(
      get: { kind },
      set: { next in
        if next != kind { category = "" }
        kind = next
      })
  }

  private var categoryPicker: some View {
    FinanceCategoryPicker(
      income: kind == .income, selection: $category, stored: entry?.category
    )
    .id(kind)
  }

  /// «Счёт»: every account, deposit and card of the chosen currency; the main one is shown as
  /// «Основной счёт». The list follows the currency of the form.
  @ViewBuilder private var accountPicker: some View {
    let options = FinanceOperationAccount.options(entries, currency: currency)
    if !options.isEmpty {
      FinanceField(store.text("Счёт", "Account")) {
        FinanceSelect(
          options: options.map { ($0.id, $0.name ?? store.text("Основной счёт", "Main account")) },
          selection: $accountID)
      }
    }
  }

  private static func lastAccountKey(_ currency: FinanceCurrency) -> String {
    "ritm.finance.lastOperationAccount.\(currency.rawValue)"
  }

  /// The account of the last saved operation in this currency; nil when none was saved.
  private static func lastAccount(_ currency: FinanceCurrency) -> String? {
    UserDefaults.standard.string(forKey: lastAccountKey(currency))
  }

  private var transferFields: some View {
    VStack(alignment: .leading, spacing: 12) {
      FinanceField(store.text("Откуда", "From")) { accountSelect($fromID) }
      FinanceField(store.text("Куда", "To")) { accountSelect($toID) }
      FinanceFormNote(
        text: store.text(
          "Перевод между двумя разными счетами одной валюты. Доходом или расходом не считается.",
          "Move money between different accounts in the same currency. It is not income or spending."
        ))
    }
  }

  private var stockFields: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        FinanceField(store.text("Биржа", "Exchange")) {
          FinanceSelect(
            options: [("KASE", "KASE"), ("AIX", "AIX")], selection: $exchange)
        }
        FinanceField(store.text("Тикер", "Ticker")) {
          FinanceTextInput(
            placeholder: "HSBK", text: $ticker, capitalization: .characters)
        }
      }
      HStack(alignment: .top, spacing: 10) {
        FinanceField(store.text("Количество", "Quantity")) {
          FinanceTextInput(placeholder: "0", text: $quantity, keyboard: .numberPad)
        }
        FinanceField(store.text("Цена покупки", "Purchase price")) {
          FinanceAmountInput(placeholder: "0", text: $purchasePrice, symbol: sign)
        }
      }
      FinanceField(store.text("Текущая цена", "Current price")) {
        FinanceAmountInput(placeholder: "0", text: $unitPrice, symbol: sign)
      }
      if let count = Int(quantity), count > 0, count <= 1_000_000_000,
        let price = FinanceDisplay.minor(unitPrice), price <= 1_000_000_000_000 / count
      {
        FinanceFormNote(
          text: store.text("Текущая стоимость: ", "Current valuation: ")
            + FinanceDisplay.money(price * count, currency: currency, language: store.language))
      }
      FinanceFormNote(
        text: store.text(
          "Укажите цену самостоятельно. Автоматического обновления котировок нет. Для изменения цены отредактируйте эту запись.",
          "Enter the price yourself. Quotes do not update automatically. Edit this record to update its price."
        ))
    }
  }

  private func accountSelect(_ selection: Binding<String>) -> some View {
    let named = accounts.map { ($0.id, $0.name ?? store.text("Основной счёт", "Main account")) }
    return FinanceSelect(
      options: [("", store.text("Выберите счёт", "Choose account"))] + named,
      selection: selection)
  }
  private func savedToast(name: String) -> String {
    if entry != nil { return store.text("Запись сохранена", "Record saved") }
    switch kind {
    case .income, .expense, .transfer:
      return store.text("Операция добавлена", "Transaction added")
    case .account, .deposit:
      return name.isEmpty
        ? store.text("Счёт добавлен", "Account added")
        : store.text("Счёт «\(name)» добавлен", "Account “\(name)” added")
    default:
      return store.text("Запись добавлена", "Record added")
    }
  }
  private func save() async {
    validation = nil
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard HabitSchedule.isValidDate(date), trimmedNote.utf16.count <= 1000,
      !(kind == .deposit || kind == .stock)
        || (!trimmedName.isEmpty && trimmedName.utf16.count <= 120),
      !(kind == .income || kind == .expense)
        || (!trimmedCategory.isEmpty && trimmedCategory.utf16.count <= 80)
    else {
      validation = store.text(
        "Проверьте дату, название (до 120 символов), категорию (до 80) и заметку (до 1000).",
        "Check the date, name (120 characters), category (80), and note (1000).")
      return
    }
    var value = FinanceDisplay.minor(amount)
    var count: Int?
    var price: Int?
    var purchase: Int?
    let symbol = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if kind == .stock {
      if quantity.isEmpty && !unitPrice.isEmpty {
        validation = store.text(
          "Для цены одной акции укажите количество.", "Enter a quantity for the price per share.")
        return
      }
      if !quantity.isEmpty {
        count = Int(quantity)
        price = FinanceDisplay.minor(unitPrice)
        guard let count, count > 0, count <= 1_000_000_000,
          let price, price <= 1_000_000_000_000 / count
        else {
          validation = store.text(
            "Введите целое количество акций и корректную цену.",
            "Enter a whole share quantity and a valid price.")
          return
        }
        value = count * price
      }
      if !purchasePrice.isEmpty { purchase = FinanceDisplay.minor(purchasePrice) }
      guard
        (symbol.isEmpty && entry != nil)
          || symbol.range(of: #"^[A-Z0-9._-]{1,30}$"#, options: .regularExpression) != nil,
        entry != nil || (count != nil && purchase != nil),
        purchasePrice.isEmpty || purchase != nil,
        purchase == nil || (count != nil && purchase! <= 1_000_000_000_000 / count!)
      else {
        validation = store.text(
          "Укажите тикер, целое количество и цену покупки одной акции.",
          "Enter a ticker, whole quantity, and purchase price per share.")
        return
      }
    }
    guard let value, !isTransaction || value > 0 else {
      validation = store.text(
        "Введите корректную сумму с точностью до двух знаков. Операция должна быть больше нуля.",
        "Enter an amount with up to two decimal places. Transactions must be greater than zero.")
      return
    }
    if kind == .transfer {
      guard fromID != toID, accounts.contains(where: { $0.id == fromID }),
        accounts.contains(where: { $0.id == toID })
      else {
        validation = store.text(
          "Выберите два разных счёта одной валюты.",
          "Choose two different accounts in the same currency.")
        return
      }
    }
    let input = FinanceEntryInput(
      type: kind, currency: currency, note: trimmedNote,
      amountMinor: isTransaction ? value : nil, valueMinor: isTransaction ? nil : value,
      date: isTransaction ? date : nil, asOf: isTransaction ? nil : date,
      name: kind == .deposit || kind == .stock ? trimmedName : nil,
      category: kind == .income || kind == .expense ? trimmedCategory : nil,
      accountId: kind == .income || kind == .expense
        ? FinanceOperationAccount.requestAccountID(accountID, entries: entries, currency: currency)
        : nil,
      fromAccountId: kind == .transfer ? fromID : nil, toAccountId: kind == .transfer ? toID : nil,
      exchange: kind == .stock && !symbol.isEmpty ? exchange : nil,
      ticker: kind == .stock && !symbol.isEmpty ? symbol : nil,
      quantity: count, unitPriceMinor: price, purchasePriceMinor: purchase)
    saving = true
    let result = await store.write { client in
      if let entry {
        return try await client.updateFinanceEntry(
          id: entry.id, entry: input, expectedUpdatedAt: entry.updatedAt)
      }
      return try await client.createFinanceEntry(input)
    }
    saving = false
    if let saved = result {
      if saved.type == .deposit { accountKinds.set(plain: plain, for: saved.id) }
      if saved.type == .income || saved.type == .expense, !accountID.isEmpty {
        UserDefaults.standard.set(accountID, forKey: Self.lastAccountKey(saved.currency))
      }
      // A new operation announces itself with the banner (store.notices), not a toast.
      let announcedByBanner = entry == nil && (kind == .income || kind == .expense || kind == .transfer)
      if !announcedByBanner { store.toasts.show(savedToast(name: trimmedName)) }
      await onSave()
      dismiss()
    }
  }
}
