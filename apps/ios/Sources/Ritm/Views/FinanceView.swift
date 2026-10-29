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
  @State private var overviewCurrency: FinanceCurrency?
  @State private var editing: FinanceEditing?
  @State private var detail: FinanceDetailRoute?
  @State private var followUp: FinanceFollowUp?
  @State private var deleting: FinanceEntry?
  @State private var drawLog = FinanceDrawLog()

  private var cards: [FinanceCard] { FinanceWallet.cards(store.financeEntries, today: store.today) }

  private func format(_ cards: [FinanceCard]) -> FinanceFormat {
    FinanceFormat(language: store.language, zone: store.timeZone, cards: cards)
  }

  var body: some View {
    let cards = self.cards
    return ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          heading
          notices
          content(cards)
          RitmPageFooter()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .scrollDisabled(walletDragging)
      .refreshable { await store.reloadFinance() }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task(id: navigation.section) {
      if navigation.section == .finance { await store.reloadFinance() }
    }
    .onAppear { consumeFocus() }
    .onChange(of: store.financeFocus) { _, _ in consumeFocus() }
    .onChange(of: store.financeLoaded) { _, _ in consumeFocus() }
    .onChange(of: cards.isEmpty) { _, isEmpty in if isEmpty { expanded = false } }
    .sheet(item: $editing) { route in
      FinanceEditor(
        entry: route.entry, kind: route.kind, currency: route.currency,
        entries: store.financeEntries
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

  // MARK: Heading

  private var heading: some View {
    RitmPageHeading(
      eyebrow: (expanded
        ? store.text("Ritm · Карты раскрыты", "Ritm · Cards open")
        : store.text("Ritm · Карты собраны", "Ritm · Cards stacked")).uppercased(),
      title: store.text("Финансы", "Finance"),
      description: expanded
        ? nil
        : store.text(
          "Поступления, расходы и активы — в одной ясной картине.",
          "Income, spending and assets in one clear picture.")
    ) {
      if expanded { backPill }
    }
  }

  private var backPill: some View {
    Button {
      withAnimation(reduceMotion ? nil : FinanceMotion.close) { expanded = false }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "arrow.left").font(.system(size: 14, weight: .medium))
        Text(store.text("Все счета", "All accounts")).ritmFont(13, weight: .semibold)
      }
      .foregroundStyle(RitmTheme.accentColor)
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .background {
        Capsule()
          .fill(RitmTheme.glassRaised)
          .overlay { Capsule().strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
      }
    }
    .buttonStyle(RitmPressStyle())
    .transition(.opacity)
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
      }
    }
  }

  private func loaded(_ cards: [FinanceCard]) -> some View {
    let format = format(cards)
    let selected = cards.first(where: { $0.id == selectedID }) ?? cards.first
    return VStack(alignment: .leading, spacing: 14) {
      if !expanded { totals(cards, format) }
      FinanceWalletView(
        cards: cards, format: format, expanded: $expanded, selectedID: $selectedID,
        dragging: $walletDragging
      )
      .padding(.horizontal, -16)
      ZStack(alignment: .top) {
        if expanded, let selected {
          FinanceAccountSections(
            card: selected, entries: store.financeEntries, format: format, today: store.today,
            period: $period, log: drawLog, actions: actions
          )
          .id(selected.id)
          .transition(.opacity)
        } else if !expanded {
          overview(cards, format)
            .id("overview")
            .transition(.opacity)
        }
      }
      .animation(
        reduceMotion ? nil : .easeInOut(duration: 0.2),
        value: expanded ? "card-" + (selected?.id ?? "") : "overview")
    }
  }

  private func totals(_ cards: [FinanceCard], _ format: FinanceFormat) -> some View {
    let totals = FinanceWallet.totals(cards)
    return VStack(alignment: .leading, spacing: 6) {
      Text(store.text("Всего средств", "Total funds"))
        .ritmFont(12)
        .foregroundStyle(RitmTheme.muted)
      if let first = totals.first {
        Text(format.money(first.amountMinor, first.currency))
          .ritmFont(34, weight: .semibold, tracking: -0.055)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .foregroundStyle(RitmTheme.titleGradient)
          .contentTransition(.numericText())
      }
      if totals.count > 1 {
        Text(
          totals.dropFirst().map { format.money($0.amountMinor, $0.currency) }
            .joined(separator: " · ")
        )
        .ritmFont(17, weight: .medium)
        .monospacedDigit()
        .foregroundStyle(RitmTheme.text)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 2)
    .accessibilityElement(children: .combine)
    .transition(.opacity)
  }

  private func overview(_ cards: [FinanceCard], _ format: FinanceFormat) -> some View {
    let currencies = FinanceWallet.totals(cards).map(\.currency)
    let remembered = overviewCurrency.flatMap { currencies.contains($0) ? $0 : nil }
    let current = remembered ?? currencies.first ?? .KZT
    return FinanceOverviewSections(
      entries: store.financeEntries, cards: cards, format: format, today: store.today,
      currencies: currencies,
      currency: Binding(get: { current }, set: { overviewCurrency = $0 }),
      period: $period, log: drawLog, actions: actions,
      openCard: { id in
        withAnimation(reduceMotion ? nil : FinanceMotion.open) {
          selectedID = id
          expanded = true
        }
      })
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
