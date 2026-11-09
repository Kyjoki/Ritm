import RitmCore
import SwiftUI

/// «Новые покупки»: Apple Wallet purchases that arrived through Shortcuts and wait for the owner.
/// Each row suggests the category chosen before for that merchant; the owner only confirms.
struct FinanceInboxCard: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var picking: PickRoute?
  /// The account the owner picked per purchase id; without a pick the card label decides.
  @State private var accountChoices: [String: String] = [:]

  private struct PickRoute: Identifiable {
    let id: String
  }

  var body: some View {
    let items = store.wallet.pending
    VStack(spacing: 0) {
      if !items.isEmpty { card(items).transition(cardTransition) }
    }
    .animation(
      reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.34), value: items.map(\.id)
    )
    .sheet(item: $picking) { route in
      FinanceInboxCategorySheet(purchaseID: route.id)
        .environment(store)
    }
  }

  private var cardTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -RitmMotion.revealOffset))
  }

  private var rowTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .opacity.combined(with: .offset(y: -8)),
        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
  }

  // MARK: Card

  private func card(_ items: [WalletPurchase]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      header(count: items.count)
      Text(
        store.text(
          "Эти покупки ждут вашего подтверждения: выберите категорию и подтвердите.",
          "These purchases wait for your confirmation: pick a category and confirm.")
      )
      .ritmFont(11, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      .padding(.bottom, 4)
      ForEach(items) { purchase in
        row(purchase).transition(rowTransition)
      }
      if items.count > 1, store.wallet.state.allHaveCategory { confirmAll(items) }
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { RitmPanelBackground(radius: 23) }
  }

  private func header(count: Int) -> some View {
    HStack(spacing: 10) {
      RitmSymbol("wallet.bifold")
        .font(.system(size: 17))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 19)
        .accessibilityHidden(true)
      Text(store.text("Новые покупки", "New purchases"))
        .ritmFont(16, weight: .semibold, tracking: -0.02)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      Text("\(count)")
        .ritmFont(11, weight: .semibold)
        .monospacedDigit()
        .foregroundStyle(RitmTheme.accentColor)
        .padding(.horizontal, 9)
        .frame(minHeight: 22)
        .background(RitmTheme.soft, in: Capsule())
        .accessibilityLabel(store.text("Ожидают: \(count)", "Waiting: \(count)"))
    }
    .padding(.bottom, 4)
  }

  // MARK: Row

  private func row(_ purchase: WalletPurchase) -> some View {
    let state = RowState(store: store, purchase: purchase)
    return VStack(alignment: .leading, spacing: 10) {
      summary(purchase)
      categoryButton(purchase, state)
      accountRow(purchase)
      actions(purchase, state)
      if let hint = state.hint {
        Text(hint)
          .ritmFont(11, lineSpacing: 3)
          .foregroundStyle(RitmTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
    .accessibilityElement(children: .contain)
  }

  private func summary(_ purchase: WalletPurchase) -> some View {
    let amount = FinanceDisplay.money(
      purchase.amountMinor, currency: purchase.currency, language: store.language)
    let details = [purchase.card, shortDate(purchase.date)].compactMap { $0 }
      .joined(separator: " · ")
    return HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(purchase.merchant)
            .ritmFont(14, weight: .semibold)
            .foregroundStyle(RitmTheme.text)
            .lineLimit(2)
          if purchase.isTest { testBadge }
        }
        Text(details).ritmFont(11).foregroundStyle(RitmTheme.muted).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(amount)
        .ritmFont(15, weight: .semibold)
        .monospacedDigit()
        .foregroundStyle(RitmTheme.text)
        .lineLimit(1)
        .fixedSize()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(purchase.merchant), \(amount)" + (details.isEmpty ? "" : ", \(details)")
        + (purchase.isTest ? store.text(", тест", ", test") : ""))
  }

  private var testBadge: some View {
    Text(store.text("тест", "test"))
      .ritmFont(10, weight: .semibold)
      .foregroundStyle(RitmTheme.accentColor)
      .padding(.horizontal, 7)
      .frame(minHeight: 18)
      .background(RitmTheme.soft, in: Capsule())
  }

  private func categoryButton(_ purchase: WalletPurchase, _ state: RowState) -> some View {
    let category = state.category
    let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
    return Button {
      picking = PickRoute(id: purchase.id)
    } label: {
      HStack(spacing: 10) {
        RitmSymbol(category?.symbol ?? "square.grid.2x2")
          .font(.system(size: 17))
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 34, height: 34)
          .background(RitmTheme.soft, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(
            category.map { store.text($0.label, $0.english) }
              ?? store.text("Выбрать категорию", "Choose a category")
          )
          .ritmFont(13, weight: .medium)
          .foregroundStyle(category == nil ? RitmTheme.accentColor : RitmTheme.text)
          .lineLimit(1)
          if let caption = state.caption {
            Text(caption).ritmFont(10, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
          }
        }
        Spacer(minLength: 8)
        RitmSymbol("chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .background(RitmTheme.glassDense, in: shape)
      .overlay {
        shape.strokeBorder(category == nil ? RitmTheme.accentColor : RitmTheme.line, lineWidth: 1)
      }
      .contentShape(shape)
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .accessibilityLabel(
      category.map {
        store.text("Категория: \($0.label)", "Category: \($0.english)")
          + (state.caption.map { ", \($0)" } ?? "")
      } ?? store.text("Выбрать категорию", "Choose a category")
    )
    .accessibilityHint(store.text("Открывает список категорий", "Opens the category list"))
  }

  // MARK: Account

  private func accountOptions(_ purchase: WalletPurchase) -> [FinanceAccountOption] {
    FinanceOperationAccount.options(store.financeEntries, currency: purchase.currency)
  }

  /// The picked account while it still exists; else the one matching the purchase's card label
  /// («Kaspi Gold»), else the main account.
  private func selectedAccountID(_ purchase: WalletPurchase) -> String {
    if let chosen = accountChoices[purchase.id],
      accountOptions(purchase).contains(where: { $0.id == chosen })
    {
      return chosen
    }
    return WalletAccountMatch.defaultAccountID(for: purchase, entries: store.financeEntries)
  }

  /// nil for the main account, so the request leaves `accountId` out.
  private func requestAccountID(_ purchase: WalletPurchase) -> String? {
    FinanceOperationAccount.requestAccountID(
      selectedAccountID(purchase), entries: store.financeEntries, currency: purchase.currency)
  }

  /// «Счёт» under the category: only when the currency has more than the main account.
  @ViewBuilder private func accountRow(_ purchase: WalletPurchase) -> some View {
    let options = accountOptions(purchase)
    if options.count > 1, !purchase.isTest {
      HStack(spacing: 10) {
        Text(store.text("Счёт", "Account"))
          .ritmFont(12, weight: .medium)
          .foregroundStyle(RitmTheme.muted)
        FinanceSelect(
          options: options.map { ($0.id, $0.name ?? store.text("Основной счёт", "Main account")) },
          selection: Binding(
            get: { selectedAccountID(purchase) },
            set: { accountChoices[purchase.id] = $0 }),
          disabled: store.wallet.booking.contains(purchase.id))
      }
    }
  }

  private func actions(_ purchase: WalletPurchase, _ state: RowState) -> some View {
    HStack(spacing: 8) {
      Button(store.text("Подтвердить", "Confirm")) {
        let account = requestAccountID(purchase)
        Task { await store.confirmWalletPurchase(purchase, accountID: account) }
      }
      .buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
      .disabled(!state.canConfirm)
      .accessibilityLabel(
        store.text("Подтвердить: \(purchase.merchant)", "Confirm: \(purchase.merchant)"))
      Button(store.text("Пропустить", "Skip")) { store.wallet.skip(id: purchase.id) }
        .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
        .disabled(state.isBooking)
        .accessibilityLabel(
          store.text("Пропустить: \(purchase.merchant)", "Skip: \(purchase.merchant)"))
    }
  }

  private func confirmAll(_ items: [WalletPurchase]) -> some View {
    let ready = items.allSatisfy { RowState(store: store, purchase: $0).canConfirm }
    return Button(store.text("Подтвердить все (\(items.count))", "Confirm all (\(items.count))")) {
      let accounts = items.reduce(into: [String: String]()) { result, purchase in
        if let id = requestAccountID(purchase) { result[purchase.id] = id }
      }
      Task { await store.confirmAllWalletPurchases(accountIDs: accounts) }
    }
    .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
    .frame(maxWidth: .infinity)
    .disabled(!ready)
    .padding(.top, 4)
  }

  /// «14.03» from «2026-03-14»; nil for anything else.
  private func shortDate(_ date: String) -> String? {
    let parts = date.split(separator: "-")
    guard parts.count == 3 else { return nil }
    return "\(parts[2]).\(parts[1])"
  }
}

// MARK: - Row state

/// What one row may do right now, and why not.
@MainActor
private struct RowState {
  let store: RitmStore
  let purchase: WalletPurchase

  var category: FinanceCategory? {
    guard let label = purchase.suggestedCategory, !label.isEmpty else { return nil }
    return FinanceCategories.expense.first { $0.label == label }
  }

  /// «предложено» only for what the memory itself suggests; a manual choice says «выбрано».
  var caption: String? {
    guard let label = purchase.suggestedCategory, category != nil else { return nil }
    let remembered = store.wallet.state.memory.suggest(merchant: purchase.merchant) == label
    return remembered ? store.text("предложено", "suggested") : store.text("выбрано", "chosen")
  }

  var isBooking: Bool { store.wallet.booking.contains(purchase.id) }

  private var hasAccount: Bool {
    purchase.isTest || !store.financeLoaded
      || WalletBooking.hasAccount(for: purchase, in: store.financeEntries)
  }

  var canConfirm: Bool {
    category != nil && hasAccount && !isBooking
      && (purchase.isTest || (store.canWrite && store.financeLoaded))
  }

  var hint: String? {
    if category == nil {
      return store.text(
        "Выберите категорию, чтобы подтвердить. Ritm запомнит её для этого магазина.",
        "Choose a category to confirm. Ritm will remember it for this merchant.")
    }
    if !hasAccount {
      let code = purchase.currency.rawValue
      return store.text(
        "Нет счёта в \(code). Задайте стартовый остаток в Финансах, затем подтвердите.",
        "No \(code) account yet. Set an opening balance in Finance, then confirm.")
    }
    if purchase.isTest {
      return store.text(
        "Тестовая покупка: в расходы не записывается.",
        "Test purchase: it is not recorded as spending.")
    }
    if store.isOffline {
      return store.text(
        "Нет связи. Подтвердить можно после восстановления соединения.",
        "No connection. You can confirm once it is back.")
    }
    return nil
  }
}

// MARK: - Category sheet

/// The category picker of the finance editor in a sheet; a tap stores the choice and closes it.
private struct FinanceInboxCategorySheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let purchaseID: String

  private var purchase: WalletPurchase? { store.wallet.pending.first { $0.id == purchaseID } }

  var body: some View {
    FinanceSheetFrame(
      title: store.text("Категория покупки", "Purchase category"), detents: [.medium, .large]
    ) {
      if let purchase {
        let amount = FinanceDisplay.money(
          purchase.amountMinor, currency: purchase.currency, language: store.language)
        Text(purchase.merchant + " · " + amount)
          .ritmFont(12.5)
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
      }
      FinanceCategoryPicker(
        income: false,
        selection: Binding(
          get: { purchase?.suggestedCategory ?? "" },
          set: { choose($0) }))
    }
    .onChange(of: purchase == nil) { _, gone in if gone { dismiss() } }
  }

  private func choose(_ label: String) {
    store.wallet.setCategory(label, for: purchaseID)
    Task {
      try? await Task.sleep(for: .milliseconds(180))
      dismiss()
    }
  }
}
