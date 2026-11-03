import RitmCore
import SwiftUI

/// Names, amounts and dates for the finance page, so every block formats an entry the same way.
struct FinanceFormat {
  let language: Language
  let zone: String
  let cards: [FinanceCard]

  func text(_ ru: String, _ en: String) -> String { language == .ru ? ru : en }

  /// «Основной счёт» (+ « · USD» when there is more than one main account), the deposit name,
  /// «Акции».
  func name(_ card: FinanceCard) -> String {
    switch card.kind {
    case .account:
      let many = cards.filter { $0.kind == .account }.count > 1
      return text("Основной счёт", "Main account") + (many ? " · \(card.currency.rawValue)" : "")
    case .deposit:
      return card.name ?? text("Депозит", "Deposit")
    case .stocks:
      let many = cards.filter { $0.kind == .stocks }.count > 1
      return text("Акции", "Stocks") + (many ? " · \(card.currency.rawValue)" : "")
    }
  }

  func name(of cardID: String?) -> String? {
    guard let cardID, let card = cards.first(where: { $0.id == cardID }) else { return nil }
    return name(card)
  }

  func money(_ minor: Int, _ currency: FinanceCurrency) -> String {
    FinanceDisplay.money(minor, currency: currency, language: language)
  }

  /// `+420 000 ₸` / `−185 000 ₸`; zero has no sign.
  func signed(_ minor: Int, _ currency: FinanceCurrency) -> String {
    (minor > 0 ? "+" : minor < 0 ? "−" : "") + money(abs(minor), currency)
  }

  func date(_ key: String, template: String = "d MMM") -> String {
    FeatureDate.label(key, zone: zone, language: language, template: template)
  }

  func periodTitle(_ period: FinancePeriod) -> String {
    switch period {
    case .week: text("Неделя", "Week")
    case .month: text("Месяц", "Month")
    case .year: text("Год", "Year")
    }
  }

  func range(_ interval: (start: String, end: String)) -> String {
    date(interval.start) + " – " + date(interval.end)
  }

  func typeName(_ kind: FinanceEntryKind) -> String {
    switch kind {
    case .income: text("Поступление", "Income")
    case .expense: text("Расход", "Expense")
    case .transfer: text("Перевод", "Transfer")
    case .account: text("Основной счёт", "Main account")
    case .deposit: text("Депозит", "Deposit")
    case .stock: text("Акции", "Stocks")
    }
  }

  /// Category, else note; transfers and assets use their own names.
  func title(_ entry: FinanceEntry) -> String {
    switch entry.type {
    case .income, .expense:
      let category = (entry.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !category.isEmpty { return text(category, FinanceCategories.englishName(for: category)) }
      let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
      return note.isEmpty ? typeName(entry.type) : note
    case .transfer: return typeName(.transfer)
    case .account: return typeName(.account)
    case .deposit, .stock: return entry.name ?? typeName(entry.type)
    }
  }

  func subtitle(_ entry: FinanceEntry, includeAccount: Bool) -> String {
    var parts: [String] = []
    if let key = entry.date ?? entry.asOf { parts.append(date(key)) }
    if entry.type == .transfer {
      if let from = name(of: entry.fromAccountId), let to = name(of: entry.toAccountId) {
        parts.append("\(from) → \(to)")
      }
    } else if includeAccount,
      let account = name(of: FinanceWallet.cardID(for: entry, cards: cards))
    {
      parts.append(account)
    }
    return parts.joined(separator: " · ")
  }

  func amount(_ entry: FinanceEntry) -> String {
    let minor = entry.amountMinor ?? 0
    switch entry.type {
    case .income: return signed(minor, entry.currency)
    case .expense: return signed(-minor, entry.currency)
    case .transfer: return money(minor, entry.currency)
    case .account, .deposit, .stock: return money(entry.valueMinor ?? 0, entry.currency)
    }
  }

  func tone(_ entry: FinanceEntry) -> Color {
    switch entry.type {
    case .income: FinanceTone.income
    case .expense: FinanceTone.expense
    default: RitmTheme.text
    }
  }

  /// «29 октября, 6:24 PM» for the moment the record was created (times use AM/PM).
  func addedAt(_ iso: String) -> String? {
    guard let instant = FeatureDate.instant(iso) else { return nil }
    let clock = DateFormatter()
    clock.locale = Locale(identifier: "en_US_POSIX")
    clock.timeZone = TimeZone(identifier: zone)
    clock.dateFormat = "h:mm a"
    let key = HabitSchedule.dateKey(instant, timeZone: zone)
    return date(key, template: "d MMMM") + ", " + clock.string(from: instant)
  }
}

/// A tappable operation line: icon tile, title with its details, signed amount. In the dated
/// history (`capsule`) it is the prototype's `.fh-row`: a 56 pt panel capsule of radius 22.
struct FinanceOperationRow: View {
  let entry: FinanceEntry
  let format: FinanceFormat
  let includeAccount: Bool
  /// A rounded panel around the row (radius 22) for the dated history.
  var capsule = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        RitmSymbol(symbol)
          .font(.system(size: 17, weight: .regular))
          .foregroundStyle(entry.type == .income ? FinanceTone.income : RitmTheme.accentColor)
          .frame(width: 40, height: 40)
          .background(
            entry.type == .income ? FinanceTone.incomeSoft : RitmTheme.soft,
            in: RoundedRectangle(cornerRadius: 12, style: .circular)
          )
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text(format.title(entry))
            .ritmFont(12.5, weight: .bold, tracking: -0.02)
            .foregroundStyle(RitmTheme.text)
            .lineLimit(1)
          Text(meta)
            .ritmFont(10.5)
            .foregroundStyle(RitmTheme.muted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The amount keeps its own column: the title and meta truncate, never the sum.
        Text(format.amount(entry))
          .ritmFont(12.5, weight: .bold, tracking: -0.02)
          .monospacedDigit()
          .foregroundStyle(amountTone)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .layoutPriority(1)
        RitmSymbol("chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
          .padding(.leading, -4)
          .accessibilityHidden(true)
      }
      .frame(minHeight: 56)
      .padding(.horizontal, capsule ? 12 : 0)
      .background {
        if capsule {
          let shape = RoundedRectangle(cornerRadius: 22, style: .circular)
          shape.fill(RitmTheme.panel)
            .overlay { shape.fill(RitmTheme.panelSheen) }
            .overlay { shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityElement(children: .combine)
  }

  private var symbol: String { FinanceDetailStyle.symbol(entry) }

  /// `.op-a`: income green, a transfer muted, an expense in the plain text colour.
  private var amountTone: Color {
    switch entry.type {
    case .income: FinanceTone.income
    case .transfer: RitmTheme.muted
    default: RitmTheme.text
    }
  }

  /// `.op-m`: the note and the account (the date is in the gutter); transfers name both ends.
  private var meta: String {
    guard capsule else { return format.subtitle(entry, includeAccount: includeAccount) }
    var parts: [String] = []
    let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
    if entry.type == .transfer {
      if let from = format.name(of: entry.fromAccountId), let to = format.name(of: entry.toAccountId) {
        parts.append("\(from) → \(to)")
      }
    } else {
      if !note.isEmpty, note != format.title(entry) { parts.append(note) }
      if includeAccount,
        let account = format.name(of: FinanceWallet.cardID(for: entry, cards: format.cards))
      {
        parts.append(account)
      }
    }
    return parts.isEmpty ? format.typeName(entry.type) : parts.joined(separator: " · ")
  }
}

enum FinanceDetailStyle {
  /// Income and expense show their category icon; the rest keep the transfer or asset symbol.
  static func symbol(_ entry: FinanceEntry) -> String {
    switch entry.type {
    case .income, .expense: FinanceCategories.symbol(for: entry.category)
    case .transfer: "arrow.left.arrow.right"
    default: FinanceDisplay.symbol(entry.type)
    }
  }
  static func accent(_ kind: FinanceEntryKind) -> Color {
    switch kind {
    case .income: FinanceTone.income
    case .expense: FinanceTone.expense
    default: RitmTheme.accentColor
    }
  }
  static func soft(_ kind: FinanceEntryKind) -> Color {
    switch kind {
    case .income: FinanceTone.incomeSoft
    case .expense: FinanceTone.expenseSoft
    default: RitmTheme.soft
    }
  }
}

/// Details of one record: type, signed amount, account, category, dates and note. Looks the
/// record up live, so an edit shows at once and a deleted record closes the sheet.
struct FinanceDetailSheet: View {
  let entryID: String
  let onEdit: (FinanceEntry) -> Void
  let onDelete: (FinanceEntry) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var bodyHeight: CGFloat = 0
  @State private var actionsHeight: CGFloat = 0

  /// The sheet is as tall as its content (header, facts, buttons), up to the full screen; the
  /// facts scroll while the buttons stay pinned and fully visible.
  private var detents: Set<PresentationDetent> {
    let total = bodyHeight + actionsHeight
    return total > 0 ? [.height(total), .large] : [.medium, .large]
  }

  var body: some View {
    let entries = store.financeEntries
    let cards = FinanceWallet.cards(entries, today: store.today)
    let format = FinanceFormat(language: store.language, zone: store.timeZone, cards: cards)
    return ZStack {
      RitmBackground()
      if let entry = entries.first(where: { $0.id == entryID }) {
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              header(entry, format)
              facts(entry, format, cards)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
          }
          .scrollIndicators(.hidden)
          .scrollBounceBehavior(.basedOnSize)
          actions(entry)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
        }
      } else {
        RitmEmptyState(
          symbol: "tray",
          title: store.text("Запись недоступна", "Record unavailable"),
          message: store.text("Возможно, её уже удалили.", "It may have been deleted."))
          .padding(20)
      }
    }
    .presentationDetents(detents)
    .ritmSheetGrabber()
    .presentationCornerRadius(22)
  }

  private func header(_ entry: FinanceEntry, _ format: FinanceFormat) -> some View {
    HStack(alignment: .center, spacing: 14) {
      RitmSymbol(FinanceDetailStyle.symbol(entry))
      .font(.system(size: 20, weight: .medium))
      .foregroundStyle(FinanceDetailStyle.accent(entry.type))
      .frame(width: 52, height: 52)
      .background(
        FinanceDetailStyle.soft(entry.type), in: RoundedRectangle(cornerRadius: 14, style: .circular)
      )
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(format.typeName(entry.type).uppercased())
          .ritmText(.eyebrow)
          .foregroundStyle(RitmTheme.accentColor)
        Text(format.amount(entry))
          .ritmFont(30, weight: .semibold, tracking: -0.05)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .foregroundStyle(format.tone(entry))
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  private func facts(_ entry: FinanceEntry, _ format: FinanceFormat, _ cards: [FinanceCard])
    -> some View
  {
    let account = format.name(of: FinanceWallet.cardID(for: entry, cards: cards))
    let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
    let card = cards.first { $0.id == entry.id }
    return RitmCard {
      VStack(alignment: .leading, spacing: 0) {
        row(store.text("Тип", "Type"), format.typeName(entry.type))
        if entry.type == .transfer {
          row(store.text("Откуда", "From"), format.name(of: entry.fromAccountId) ?? "—")
          row(store.text("Куда", "To"), format.name(of: entry.toAccountId) ?? "—")
        } else if let account, entry.type == .income || entry.type == .expense {
          row(store.text("Счёт", "Account"), account)
        }
        if let category = entry.category, !category.isEmpty {
          row(
            store.text("Категория", "Category"),
            store.text(category, FinanceCategories.englishName(for: category)))
        }
        if let name = entry.name, entry.type == .deposit || entry.type == .stock {
          row(store.text("Название", "Name"), name)
        }
        if entry.type == .stock { stockRows(entry, format) }
        if let card, let balance = card.balanceMinor {
          row(store.text("Текущий остаток", "Current balance"), format.money(balance, card.currency))
        }
        if let key = entry.date ?? entry.asOf {
          row(
            entry.date == nil ? store.text("На дату", "As of") : store.text("Дата", "Date"),
            format.date(key, template: "d MMMM yyyy"))
        }
        if let added = format.addedAt(entry.createdAt) {
          row(store.text("Добавлено", "Added"), added)
        }
        if !note.isEmpty { row(store.text("Заметка", "Note"), note, last: true) }
      }
    }
  }

  @ViewBuilder private func stockRows(_ entry: FinanceEntry, _ format: FinanceFormat) -> some View {
    if let ticker = entry.ticker {
      row(store.text("Тикер", "Ticker"), ticker + (entry.exchange.map { " · " + $0 } ?? ""))
    }
    if let quantity = entry.quantity {
      row(store.text("Количество", "Quantity"), "\(quantity)")
    }
    if let price = entry.unitPriceMinor {
      row(store.text("Цена", "Price"), format.money(price, entry.currency))
    }
    if let purchase = entry.purchasePriceMinor {
      row(store.text("Цена покупки", "Purchase price"), format.money(purchase, entry.currency))
    }
  }

  private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        Text(label).ritmFont(11).foregroundStyle(RitmTheme.muted)
        Spacer(minLength: 8)
        Text(value)
          .ritmFont(12, weight: .medium)
          .multilineTextAlignment(.trailing)
          .foregroundStyle(RitmTheme.text)
      }
      .padding(.vertical, 11)
      if !last { Rectangle().fill(RitmTheme.line).frame(height: 1) }
    }
    .accessibilityElement(children: .combine)
  }

  private func actions(_ entry: FinanceEntry) -> some View {
    VStack(spacing: 10) {
      if entry.type == .stock, let url = quoteURL(entry) {
        Link(destination: url) {
          Text(store.text("Открыть страницу биржи", "Open exchange page"))
        }
        .buttonStyle(RitmSecondaryButtonStyle())
      }
      HStack(spacing: 10) {
        Button {
          onEdit(entry)
          dismiss()
        } label: {
          Label { Text(store.text("Изменить", "Edit")) } icon: { RitmSymbol("pencil") }.frame(maxWidth: .infinity)
        }
        .buttonStyle(RitmSecondaryButtonStyle())
        .disabled(!store.canWrite)
        Button {
          onDelete(entry)
          dismiss()
        } label: {
          Label { Text(store.text("Удалить", "Delete")) } icon: { RitmSymbol("trash") }
            .ritmText(.button)
            .foregroundStyle(RitmTheme.danger)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RitmTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 13, style: .circular))
        }
        .buttonStyle(RitmPressStyle())
        .disabled(!store.canWrite)
        .opacity(store.canWrite ? 1 : 0.6)
      }
      Button(store.text("Закрыть", "Close")) { dismiss() }
        .buttonStyle(RitmPrimaryButtonStyle())
    }
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
}
