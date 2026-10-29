import RitmCore
import SwiftUI

struct FinanceEditor: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let entry: FinanceEntry?
  let entries: [FinanceEntry]
  let onSave: () async -> Void
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
  @State private var validation: String?
  @State private var saving = false

  init(
    entry: FinanceEntry?, kind: FinanceEntryKind, currency: FinanceCurrency,
    entries: [FinanceEntry], onSave: @escaping () async -> Void
  ) {
    self.entry = entry
    self.entries = entries
    self.onSave = onSave
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
  }
  private var accounts: [FinanceEntry] {
    entries.filter { ($0.type == .account || $0.type == .deposit) && $0.currency == currency }
  }
  private var isTransaction: Bool { kind == .income || kind == .expense || kind == .transfer }

  var body: some View {
    NavigationStack {
      Form {
        if let validation { Section { RitmErrorBanner(message: validation) } }
        if let message = store.errorMessage { Section { RitmErrorBanner(message: message) } }
        Section {
          if entry == nil && store.uncertainWrite {
            Button(store.text("Закрыть и проверить список", "Close and check the list")) {
              dismiss()
            }
            .disabled(saving)
          } else {
            MutationRecoveryView()
          }
        }
        Section {
          Picker(store.text("Валюта", "Currency"), selection: $currency) {
            ForEach([FinanceCurrency.KZT, .USD, .EUR, .RUB], id: \.self) {
              Text($0.rawValue).tag($0)
            }
          }.disabled(entry != nil)
          DateKeyPicker(title: store.text("Дата", "Date"), value: $date, zone: store.timeZone)
          if kind == .deposit || kind == .stock {
            TextField(store.text("Название", "Name"), text: $name)
          }
          if kind == .income || kind == .expense {
            categoryPicker
          }
          if kind != .stock || quantity.isEmpty {
            TextField(
              store.text(
                isTransaction ? "Сумма" : "Начальная стоимость",
                isTransaction ? "Amount" : "Opening value"), text: $amount
            ).keyboardType(.decimalPad)
          }
        } footer: {
          if kind == .account || kind == .deposit {
            Text(
              store.text(
                "Остаток до операций в указанную дату. Переводы после этой даты учитываются отдельно.",
                "Balance before transactions on this date. Later transfers are calculated separately."
              ))
          }
        }
        if kind == .transfer {
          Section {
            accountPicker(store.text("Откуда", "From"), selection: $fromID)
            accountPicker(store.text("Куда", "To"), selection: $toID)
          } footer: {
            Text(
              store.text(
                "Перевод между двумя разными счетами одной валюты. Доходом или расходом не считается.",
                "Move money between different accounts in the same currency. It is not income or spending."
              ))
          }
        }
        if kind == .stock { stockFields }
        Section(store.text("Заметка", "Note")) {
          TextField(store.text("Необязательно", "Optional"), text: $note, axis: .vertical)
            .lineLimit(3...7)
        }
        if saving { Section { ProgressView(store.text("Сохраняем…", "Saving…")) } }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(FinanceDisplay.title(kind, language: store.language))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Отмена", "Cancel")) { dismiss() }.disabled(saving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(store.text("Сохранить", "Save")) { Task { await save() } }.disabled(
            !store.canWrite || saving)
        }
      }
      .interactiveDismissDisabled(saving)
      .task {
        if date.isEmpty { date = store.today }
        if fromID.isEmpty {
          fromID = accounts.first(where: { $0.type == .account })?.id ?? accounts.first?.id ?? ""
        }
        if toID.isEmpty { toID = accounts.first(where: { $0.id != fromID })?.id ?? "" }
      }
      .onChange(of: currency) { _, _ in
        fromID = ""
        toID = ""
      }
    }
  }
  private var categoryTiles: [FinanceCategory] {
    let list = kind == .income ? FinanceCategories.income : FinanceCategories.expense
    let stored = (entry?.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stored.isEmpty, !list.contains(where: { $0.label == stored }) else { return list }
    // A category saved elsewhere stays selectable, so editing the record does not lose it.
    return list + [
      FinanceCategory(label: stored, english: stored, symbol: FinanceCategories.symbol(for: stored))
    ]
  }
  private var categoryPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(store.text("Категория", "Category"))
        .ritmFont(12, weight: .semibold)
        .foregroundStyle(RitmTheme.muted)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8
      ) {
        ForEach(categoryTiles, id: \.label) { item in
          FinanceCategoryTile(
            symbol: item.symbol, title: store.text(item.label, item.english),
            selected: category == item.label
          ) { category = item.label }
        }
      }
    }
    .padding(.vertical, 4)
  }
  private var stockFields: some View {
    Section {
      Picker(store.text("Биржа", "Exchange"), selection: $exchange) {
        Text("KASE").tag("KASE")
        Text("AIX").tag("AIX")
      }
      TextField(store.text("Тикер", "Ticker"), text: $ticker).textInputAutocapitalization(
        .characters
      ).autocorrectionDisabled()
      TextField(store.text("Количество акций", "Share quantity"), text: $quantity).keyboardType(
        .numberPad)
      TextField(store.text("Текущая цена одной акции", "Current price per share"), text: $unitPrice)
        .keyboardType(.decimalPad)
      TextField(
        store.text("Цена покупки одной акции", "Purchase price per share"), text: $purchasePrice
      ).keyboardType(.decimalPad)
      if let count = Int(quantity), count > 0, count <= 1_000_000_000,
        let price = FinanceDisplay.minor(unitPrice), price <= 1_000_000_000_000 / count
      {
        LabeledContent(
          store.text("Текущая стоимость", "Current valuation"),
          value: FinanceDisplay.money(price * count, currency: currency, language: store.language))
      }
    } header: {
      Text(store.text("Ручная оценка акций", "Manual stock valuation"))
    } footer: {
      Text(
        store.text(
          "Укажите цену самостоятельно. Автоматического обновления котировок нет. Для изменения цены отредактируйте эту запись.",
          "Enter the price yourself. Quotes do not update automatically. Edit this record to update its price."
        ))
    }
  }
  private func accountPicker(_ title: String, selection: Binding<String>) -> some View {
    Picker(title, selection: selection) {
      Text(store.text("Выберите счёт", "Choose account")).tag("")
      ForEach(accounts) { account in
        Text(account.name ?? store.text("Основной счёт", "Main account")).tag(account.id)
      }
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
    if result != nil {
      await onSave()
      dismiss()
    }
  }
}

private struct FinanceCategoryTile: View {
  let symbol: String
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 19, weight: .regular)).frame(height: 22)
        Text(title).ritmFont(10, weight: .medium).lineLimit(1).minimumScaleFactor(0.7)
      }
      .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.text)
      .frame(maxWidth: .infinity, minHeight: 56)
      .padding(.horizontal, 2)
      .background(selected ? RitmTheme.soft : Color.clear, in: shape)
      .overlay {
        shape.strokeBorder(
          selected ? RitmTheme.accentColor : RitmTheme.line, lineWidth: selected ? 1.5 : 1)
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
