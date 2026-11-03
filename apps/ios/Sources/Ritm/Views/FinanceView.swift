import RitmCore
import SwiftUI

private struct FinanceEditing: Identifiable {
  let id = UUID()
  var entry: FinanceEntry?
  var kind: FinanceEntryKind
  var currency: FinanceCurrency
}

private struct FinanceDetailRoute: Identifiable {
  let entryID: String
  var id: String { entryID }
}

/// What to do once the detail sheet has finished closing (two sheets cannot swap in one turn).
private enum FinanceFollowUp {
  case edit(FinanceEntry)
  case delete(FinanceEntry)
}

/// A choice made in the account-actions sheet, run once it has closed.
private struct FinanceCardFollowUp {
  let action: FinanceCardAction
  let card: FinanceCard
}

/// «Финансы»: a wallet of cards that opens into a carousel, an overview of every account and
/// the analytics of the selected one. Data comes from `store.financeEntries`.
struct FinanceView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var expanded = false
  @State private var selectedID = ""
  @State private var walletDragging = false
  @State private var period: FinancePeriod = .month
  @State private var editing: FinanceEditing?
  @State private var detail: FinanceDetailRoute?
  @State private var followUp: FinanceFollowUp?
  @State private var deleting: FinanceEntry?
  @State private var drawLog = FinanceDrawLog()
  @State private var layoutStore = FinanceCardLayoutStore()
  @State private var accountKinds = FinanceAccountKindStore()
  @State private var customizing = false
  @State private var accountActions: FinanceCard?
  @State private var cardFollowUp: FinanceCardFollowUp?
  @State private var deletingCard: FinanceCard?
  @State private var deleteFailure: String?
  @State private var confirmingReset = false
  @State private var resetProgress: (done: Int, total: Int)?

  /// The wallet in its default order; colours are resolved against it so they survive reordering.
  private var defaultCards: [FinanceCard] {
    FinanceWallet.cards(store.financeEntries, today: store.today)
  }
  private var cards: [FinanceCard] { layoutStore.ordered(defaultCards) }

  private func format(_ cards: [FinanceCard]) -> FinanceFormat {
    FinanceFormat(language: store.language, zone: store.timeZone, cards: cards)
  }

  var body: some View {
    let cards = self.cards
    return ZStack {
      RitmBackground()
      ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          heading.padding(.horizontal, 20).id(Self.topID)
          notices.padding(.horizontal, 20)
          content(cards)
          RitmPageFooter().padding(.horizontal, 20)
        }
        .padding(.bottom, 28)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .scrollDisabled(walletDragging)
      .refreshable {
        async let imported: Void = store.importWalletFile(userInitiated: true)
        await store.reloadFinance()
        await imported
      }
      .onChange(of: expanded) { _, _ in
        // Opening or closing the carousel starts below the header, never under the top bar.
        withAnimation(reduceMotion ? nil : FinanceMotion.open) { proxy.scrollTo(Self.topID, anchor: .top) }
      }
      }
    }
    .overlay { if let progress = resetProgress { resetOverlay(progress) } }
    .toolbar(.hidden, for: .navigationBar)
    .task(id: navigation.section) {
      if navigation.section == .finance { await store.reloadFinance() }
    }
    .onAppear { consumeFocus() }
    .onChange(of: store.financeFocus) { _, _ in consumeFocus() }
    .onChange(of: store.financeLoaded) { _, _ in consumeFocus() }
    .onChange(of: cards.isEmpty) { _, isEmpty in if isEmpty { expanded = false } }
    .sheet(isPresented: $customizing) {
      FinanceCardSettingsSheet(
        defaultCards: defaultCards, layoutStore: layoutStore, format: format(defaultCards))
    }
    .sheet(item: $editing) { route in
      FinanceEditor(
        entry: route.entry, kind: route.kind, currency: route.currency,
        entries: store.financeEntries, accountKinds: accountKinds
      ) {
        await store.reloadFinance()
      }
    }
    .sheet(item: $detail, onDismiss: runFollowUp) { route in
      FinanceDetailSheet(
        entryID: route.entryID,
        onEdit: { followUp = .edit($0) },
        onDelete: { followUp = .delete($0) })
    }
    .sheet(item: $accountActions, onDismiss: runCardFollowUp) { card in
      FinanceAccountActionsSheet(
        card: card, format: format(cards), canWrite: store.canWrite,
        plain: accountKinds.isPlain(card.id),
        choose: { cardFollowUp = FinanceCardFollowUp(action: $0, card: card) })
    }
    .confirmationDialog(
      deletingCard.map {
        store.text("Удалить счёт «\(format(cards).name($0))»?", "Delete account “\(format(cards).name($0))”?")
      } ?? "",
      isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }),
      titleVisibility: .visible
    ) {
      Button(store.text("Удалить счёт", "Delete account"), role: .destructive) {
        guard let card = deletingCard else { return }
        deletingCard = nil
        Task { await deleteCard(card) }
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(
        deletingCard?.kind == .stocks
          ? store.text(
            "Будут удалены все позиции этого брокерского счёта. Действие изменит расчёты.",
            "Every position of this brokerage account will be deleted. This changes the totals.")
          : store.text(
            "Действие изменит расчёты. Счёт, связанный переводами, удалить нельзя.",
            "This changes the totals. An account linked by transfers cannot be deleted."))
    }
    .confirmationDialog(
      store.text(
        "Удалить все счета, операции, переводы и позиции? Это нельзя отменить.",
        "Delete all accounts, operations, transfers and positions? This cannot be undone."),
      isPresented: $confirmingReset, titleVisibility: .visible
    ) {
      Button(store.text("Удалить всё", "Delete everything"), role: .destructive) {
        Task { await resetFinance() }
      }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    }
    .alert(
      store.text("Не удалось удалить", "Could not delete"),
      isPresented: Binding(get: { deleteFailure != nil }, set: { if !$0 { deleteFailure = nil } })
    ) {
      Button(store.text("Понятно", "OK"), role: .cancel) {}
    } message: {
      Text(deleteFailure ?? "")
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
            await store.reloadFinance()
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

  private static let topID = "finance-top"

  /// The account-actions sheet has closed: run what was chosen in it.
  private func runCardFollowUp() {
    guard let next = cardFollowUp else { return }
    cardFollowUp = nil
    switch next.action {
    case .customize:
      customizing = true
    case .reset:
      confirmingReset = true
    case .delete:
      deletingCard = next.card
    case .addPosition:
      editing = FinanceEditing(entry: nil, kind: .stock, currency: next.card.currency)
    case .edit:
      guard let entry = store.financeEntries.first(where: { $0.id == next.card.id }) else { return }
      editing = FinanceEditing(entry: entry, kind: entry.type, currency: entry.currency)
    }
  }

  /// Deletes an account or deposit entry, or every position of a brokerage account, with the
  /// server's own message when it refuses (accounts linked by transfers stay).
  private func deleteCard(_ card: FinanceCard) async {
    let targets: [FinanceEntry]
    if card.kind == .stocks {
      targets = store.financeEntries.filter { $0.type == .stock && $0.currency == card.currency }
    } else {
      targets = store.financeEntries.filter { $0.id == card.id }
    }
    var failed = false
    for entry in targets {
      let done = await store.performMutation {
        try await $0.deleteFinanceEntry(id: entry.id, expectedUpdatedAt: entry.updatedAt)
      }
      if !done {
        failed = true
        break
      }
    }
    await store.reloadFinance()
    if failed {
      deleteFailure =
        store.errorMessage
        ?? store.text(
          "Сервер не удалил счёт. Если он связан переводами, сначала удалите переводы.",
          "The server did not delete the account. If it is linked by transfers, remove them first.")
      store.errorMessage = nil
    } else {
      for target in targets { accountKinds.remove(target.id) }
      withAnimation(reduceMotion ? nil : FinanceMotion.close) {
        expanded = false
        selectedID = ""
      }
    }
  }

  /// Deletes every finance entry through the per-entry API in a safe order: transfers, then
  /// income and expenses, then positions, then deposits and accounts. Stops at the first refusal
  /// and shows the server's message; reloads at the end either way.
  private func resetFinance() async {
    let order: [FinanceEntryKind] = [.transfer, .income, .expense, .stock, .deposit, .account]
    let entries = store.financeEntries
    let queue = order.flatMap { kind in entries.filter { $0.type == kind } }
    var failed = false
    resetProgress = (0, queue.count)
    for (index, entry) in queue.enumerated() {
      let done = await store.performMutation {
        try await $0.deleteFinanceEntry(id: entry.id, expectedUpdatedAt: entry.updatedAt)
      }
      if !done {
        failed = true
        break
      }
      resetProgress = (index + 1, queue.count)
    }
    await store.reloadFinance()
    resetProgress = nil
    if failed {
      deleteFailure =
        store.errorMessage
        ?? store.text(
          "Сервер отказал в удалении. Попробуйте ещё раз.", "The server refused to delete. Try again.")
      store.errorMessage = nil
    }
    // Colours and order of cards that no longer exist.
    UserDefaults.standard.removeObject(forKey: "ritm.finance.cardLayout.v1")
    layoutStore = FinanceCardLayoutStore()
    accountKinds.clear()
    withAnimation(reduceMotion ? nil : FinanceMotion.close) {
      expanded = false
      selectedID = ""
    }
  }

  private func resetOverlay(_ progress: (done: Int, total: Int)) -> some View {
    ZStack {
      Color.black.opacity(0.4).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView()
        Text(
          store.text(
            "Удаляем… \(progress.done) из \(progress.total)",
            "Deleting… \(progress.done) of \(progress.total)")
        )
        .ritmFont(13, weight: .semibold)
        .monospacedDigit()
        .foregroundStyle(RitmTheme.text)
      }
      .padding(24)
      .background { RitmPanelBackground(radius: 23, raised: true) }
    }
    .transition(.opacity)
    .accessibilityElement(children: .combine)
  }

  /// A quiet destructive text button: wipes every account, operation and position.
  private var resetButton: some View {
    Button {
      confirmingReset = true
    } label: {
      Text(store.text("Сбросить финансы", "Reset finances"))
        .ritmFont(12, weight: .semibold)
        .foregroundStyle(RitmTheme.danger)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(RitmPressStyle())
    .disabled(!store.canWrite)
  }

  // MARK: Heading

  /// `.head`: the title and, on the same 44 pt row, the card-settings button centred on it; the
  /// totals follow 10 pt below the row.
  private var heading: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(store.text("Финансы", "Finance"))
        .ritmText(.pageTitle)
        .foregroundStyle(RitmTheme.titleGradient)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      // The stack opens and collapses by tapping a card; only the card settings stay a button
      // (the open carousel has its own in the account header).
      if !cards.isEmpty, !expanded {
        FinanceCustomizeButton(format: format(cards)) { customizing = true }
      }
    }
    .frame(minHeight: 44)
    .padding(.top, 18)
  }

  @ViewBuilder private var notices: some View {
    if store.isOffline { SyncStatusView().padding(.bottom, 12) }
    if let message = store.errorMessage { RitmErrorBanner(message: message).padding(.bottom, 12) }
    if store.uncertainWrite { MutationRecoveryView().padding(.bottom, 12) }
  }

  // MARK: Content

  @ViewBuilder private func content(_ cards: [FinanceCard]) -> some View {
    if !store.financeLoaded {
      if store.financeFailed {
        RitmCard {
          RitmEmptyState(
            symbol: "wifi.exclamationmark",
            title: store.text("Данные недоступны", "Data unavailable"),
            message: store.text("Потяните вниз для повторной загрузки.", "Pull down to retry."))
        }
      } else {
        ProgressView(store.text("Загружаем финансы…", "Loading finances…"))
          .frame(maxWidth: .infinity, minHeight: 160)
      }
    } else if cards.isEmpty {
      emptyCard
    } else {
      loaded(cards)
    }
  }

  private var emptyCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        RitmEmptyState(
          symbol: "wallet.pass", title: store.text("Пока нет счетов", "No accounts yet"),
          message: store.text(
            "Задайте стартовый остаток основного счёта, чтобы увидеть карты.",
            "Set the opening balance of your main account to see your cards."))
        Button(store.text("Задать стартовый остаток", "Set opening balance")) {
          editing = FinanceEditing(entry: nil, kind: .account, currency: .KZT)
        }
        .buttonStyle(RitmPrimaryButtonStyle())
        .disabled(!store.canWrite)
        if !store.financeEntries.isEmpty { resetButton }
      }
    }
  }

  private func loaded(_ cards: [FinanceCard]) -> some View {
    let format = format(cards)
    let selected = cards.first(where: { $0.id == selectedID }) ?? cards.first
    return VStack(alignment: .leading, spacing: 0) {
      totals(cards, format)
        .padding(.horizontal, 20)
        .padding(.top, 10)
      FinanceWalletView(
        cards: cards, themes: layoutStore.themes(for: defaultCards), format: format,
        plainIDs: accountKinds.plain, expanded: $expanded, selectedID: $selectedID, dragging: $walletDragging
      )
      .padding(.top, 12)
      ZStack(alignment: .top) {
        if expanded, let selected {
          FinanceAccountSections(
            card: selected, entries: store.financeEntries, format: format, today: store.today,
            period: $period, log: drawLog, actions: actions,
            customize: { accountActions = selected },
            plain: accountKinds.isPlain(selected.id)
          )
          .id(selected.id)
          .transition(.opacity)
        } else if !expanded {
          overview(cards, format)
            .id("overview")
            .transition(.opacity)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .animation(
        reduceMotion ? nil : .easeInOut(duration: 0.2),
        value: expanded ? "card-" + (selected?.id ?? "") : "overview")
    }
  }

  /// `.totals`: the caption, the main total (34 pt) and the other currencies beside it (22 pt,
  /// muted, after a dot), and the note that currencies are never added together.
  private func totals(_ cards: [FinanceCard], _ format: FinanceFormat) -> some View {
    let totals = FinanceWallet.totals(cards)
    return VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Всего средств", "Total funds"))
        .ritmFont(12)
        .foregroundStyle(RitmTheme.muted)
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        if let first = totals.first {
          RitmCountText(first.amountMinor) { format.money($0, first.currency) }
            .ritmFont(34, weight: .bold, tracking: -0.055)
            .foregroundStyle(RitmTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        ForEach(Array(totals.dropFirst()), id: \.currency) { total in
          Text("·").ritmFont(22).foregroundStyle(RitmTheme.muted)
          RitmCountText(total.amountMinor) { format.money($0, total.currency) }
            .ritmFont(22, weight: .semibold, tracking: -0.04)
            .foregroundStyle(RitmTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
      }
      if totals.count > 1 {
        Text(store.text("Суммы в разных валютах не складываются.", "Currencies are never added together."))
          .ritmFont(11)
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  /// Under the stack, in the prototype's order: the payments row, the purchases inbox, then the
  /// buttons, the chart, the tiles, the distribution and the recent operations.
  private func overview(_ cards: [FinanceCard], _ format: FinanceFormat) -> some View {
    let currencies = FinanceWallet.totals(cards).map(\.currency)
    let current = currencies.first ?? .KZT
    let waiting = store.wallet.pending.map(\.id)
    return VStack(spacing: 14) {
      PaymentsEntryRow(cards: cards, format: format)
      if !waiting.isEmpty { FinanceInboxCard() }
      FinanceOverviewSections(
        entries: store.financeEntries, cards: cards, format: format, today: store.today,
        currencies: currencies, currency: current, period: $period, log: drawLog,
        actions: actions,
        openCard: { id in
          withAnimation(reduceMotion ? nil : FinanceMotion.open) {
            selectedID = id
            expanded = true
          }
        })
      resetButton
    }
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.34), value: waiting)
  }

  // MARK: Actions

  private var actions: FinanceActions {
    FinanceActions(
      canWrite: store.canWrite,
      open: { detail = FinanceDetailRoute(entryID: $0.id) },
      add: { kind, currency in
        editing = FinanceEditing(entry: nil, kind: kind, currency: currency)
      },
      edit: { entry in
        editing = FinanceEditing(entry: entry, kind: entry.type, currency: entry.currency)
      },
      remove: { deleting = $0 })
  }

  private func runFollowUp() {
    guard let next = followUp else { return }
    followUp = nil
    switch next {
    case .edit(let entry):
      editing = FinanceEditing(entry: entry, kind: entry.type, currency: entry.currency)
    case .delete(let entry):
      deleting = entry
    }
  }

  /// A tapped notification opens the carousel on its card and, if given, the record's details.
  private func consumeFocus() {
    guard let focus = store.financeFocus, store.financeLoaded else { return }
    store.financeFocus = nil
    if cards.contains(where: { $0.id == focus.cardID }) {
      withAnimation(reduceMotion ? nil : FinanceMotion.open) {
        selectedID = focus.cardID
        expanded = true
      }
    }
    if let id = focus.entryID, store.financeEntries.contains(where: { $0.id == id }) {
      detail = FinanceDetailRoute(entryID: id)
    }
  }
}
