import RitmCore
import SwiftUI

/// The form of one recurring payment: name, amount, debit account (it decides the currency),
/// expense category, next date, period and reminder. The reminder is stored as a setting only;
/// no notification is scheduled from it.
struct PaymentEditorSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let paymentID: String?
  let cards: [FinanceCard]
  let format: FinanceFormat

  @State private var name = ""
  @State private var amount = ""
  @State private var accountID = ""
  @State private var category = FinanceCategories.expenseMain.first?.label ?? ""
  @State private var nextDate = ""
  @State private var period: PaymentPeriod = .month
  @State private var reminder = 1
  @State private var problem: String?
  @State private var loaded = false

  private var accounts: [FinanceCard] { cards.filter { $0.kind == .account } }
  private var currency: FinanceCurrency {
    accounts.first { $0.id == accountID }?.currency ?? accounts.first?.currency ?? .KZT
  }
  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          header
          field(format.text("Название", "Name")) {
            TextField(format.text("Например, интернет", "For example, internet"), text: $name)
              .textInputAutocapitalization(.sentences)
              .submitLabel(.next)
              .fieldChrome()
          }
          field(format.text("Сумма", "Amount")) {
            HStack(spacing: 8) {
              TextField("0", text: $amount).keyboardType(.decimalPad)
              Text(currency.rawValue).foregroundStyle(RitmTheme.muted)
            }
            .fieldChrome()
          }
          field(format.text("Счёт списания", "Debit account")) {
            Picker(format.text("Счёт списания", "Debit account"), selection: $accountID) {
              ForEach(accounts) { card in Text(format.name(card) + " · " + card.currency.rawValue).tag(card.id) }
            }
            .pickerStyle(.menu)
            .tint(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldChrome()
          }
          FinanceCategoryPicker(income: false, selection: $category, stored: storedCategory)
          field(format.text("Следующая дата платежа", "Next payment date")) {
            DatePicker(
              format.text("Следующая дата платежа", "Next payment date"), selection: dateBinding,
              in: dateRange, displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.calendar, Self.utc)
            .environment(\.timeZone, Self.utc.timeZone)
            .environment(\.locale, Locale(identifier: store.language == .ru ? "ru_RU" : "en_US"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldChrome()
          }
          RitmSegmentedControl(
            label: format.text("Период повтора", "Repeat period"), values: PaymentPeriod.allCases,
            title: format.periodTitle, selection: $period)
          field(format.text("Напоминание", "Reminder")) {
            Picker(format.text("Напоминание", "Reminder"), selection: $reminder) {
              ForEach(RecurringPayment.reminderChoices, id: \.self) { days in
                Text(format.reminderName(days)).tag(days)
              }
            }
            .pickerStyle(.menu)
            .tint(RitmTheme.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldChrome()
          }
          if let problem {
            Text(problem)
              .ritmFont(12, weight: .medium)
              .foregroundStyle(RitmTheme.danger)
              .accessibilityAddTraits(.updatesFrequently)
          }
          Button(format.text("Сохранить", "Save"), action: save)
            .buttonStyle(RitmPrimaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
    }
    .presentationDetents([.large])
    .ritmSheetGrabber()
    .presentationCornerRadius(22)
    .onAppear(perform: load)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(
        paymentID == nil
          ? format.text("Новый платёж", "New payment")
          : format.text("Изменить платёж", "Edit payment")
      )
      .ritmFont(22, weight: .semibold, tracking: -0.04)
      .foregroundStyle(RitmTheme.text)
      .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 12)
      Button(format.text("Отмена", "Cancel")) { dismiss() }
        .buttonStyle(RitmSecondaryButtonStyle())
    }
    .padding(.top, 28)
  }

  private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.muted)
      content()
    }
  }

  // MARK: Dates

  private var dateRange: ClosedRange<Date> {
    let low = Self.utc.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 12)) ?? .distantPast
    let high = Self.utc.date(from: DateComponents(year: 2100, month: 12, day: 31, hour: 12)) ?? .distantFuture
    return low...high
  }

  private var dateBinding: Binding<Date> {
    Binding(
      get: {
        guard let day = PaymentDates.parse(nextDate) else { return Date() }
        return Self.utc.date(
          from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
      },
      set: { value in
        let parts = Self.utc.dateComponents([.year, .month, .day], from: value)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        nextDate = PaymentDates.key(year, month, day)
      })
  }

  // MARK: State

  private var existing: RecurringPayment? {
    paymentID.flatMap { store.payments.book.payment($0) }
  }

  /// A category that is not in the lists stays selectable so editing does not lose it.
  private var storedCategory: String? {
    guard let kept = existing?.category, !FinanceCategories.isKnown(kept) else { return nil }
    return kept
  }

  private func load() {
    guard !loaded else { return }
    loaded = true
    if let item = existing {
      name = item.name
      amount = FinanceDisplay.decimal(item.amountMinor).replacingOccurrences(of: ".", with: ",")
      accountID = accounts.contains { $0.id == item.accountID } ? item.accountID : (accounts.first?.id ?? "")
      category = item.category
      nextDate = item.nextDate
      period = item.period
      reminder = item.reminderDays
    } else {
      accountID = accounts.first?.id ?? ""
      nextDate = PaymentDates.adding(days: 7, to: store.today) ?? store.today
    }
  }

  private func save() {
    guard let cleanName = PaymentValidation.cleanName(name) else {
      problem = format.text(
        "Введите название до \(RecurringPayment.nameLimit) символов.",
        "Enter a name up to \(RecurringPayment.nameLimit) characters.")
      return
    }
    guard let minor = PaymentValidation.amountMinor(amount) else {
      problem = format.text(
        "Сумма: число больше нуля, не более двух знаков после запятой.",
        "Amount: a number above zero with at most two decimals.")
      return
    }
    guard let account = accounts.first(where: { $0.id == accountID }) else {
      problem = format.text("Выберите счёт списания.", "Choose the debit account.")
      return
    }
    let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanCategory.isEmpty, cleanCategory.count <= 80 else {
      problem = format.text("Выберите категорию расхода.", "Choose an expense category.")
      return
    }
    guard PaymentDates.isValid(nextDate) else {
      problem = format.text("Укажите дату следующего платежа.", "Choose the next payment date.")
      return
    }
    let item = RecurringPayment(
      id: existing?.id ?? UUID().uuidString, name: cleanName, amountMinor: minor,
      accountID: account.id, currency: account.currency, category: cleanCategory,
      nextDate: nextDate, period: period, reminderDays: reminder, paused: existing?.paused ?? false)
    if existing == nil {
      store.payments.apply { $0.adding(item) }
      store.toasts.show(format.text("Платёж добавлен", "Payment added"))
    } else {
      if store.payments.apply({ $0.updating(item) }) != nil {
        problem = format.text(
          "За эту дату платёж уже учтён: выберите другую дату.",
          "This date is already handled: choose another date.")
        return
      }
      store.toasts.show(format.text("Изменения сохранены", "Changes saved"))
    }
    dismiss()
  }
}

extension View {
  /// The rounded field surface used by the payment form; at least 48 pt tall.
  fileprivate func fieldChrome() -> some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    return self
      .ritmFont(15)
      .foregroundStyle(RitmTheme.text)
      .padding(.horizontal, 14)
      .frame(minHeight: 48)
      .background(RitmTheme.field, in: shape)
      .overlay { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
  }
}
