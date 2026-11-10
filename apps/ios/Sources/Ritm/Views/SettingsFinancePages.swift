import RitmCore
import SwiftUI

/// «Покупки из Wallet»: the Shortcuts automation, the Files folder Ritm reads, the import and the
/// step-by-step guide. Everything stays on this iPhone.
struct SettingsWalletPage: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.openURL) private var openURL
  @State private var shortcutsUnavailable = false

  var body: some View {
    SettingsPage(title: store.text("Покупки из Wallet", "Wallet purchases")) {
      SettingsGroup {
        SettingsActionRow(
          icon: "bolt", title: store.text("Автоматизация в Командах", "Automation in Shortcuts"),
          accessory: .chevron, action: openShortcuts)
      }
      if shortcutsUnavailable {
        SettingsFootnote(
          text: store.text(
            "Не удалось открыть «Команды». Откройте приложение вручную.",
            "Could not open Shortcuts. Open the app yourself."),
          tone: .error)
      }
      WalletFolderPanel().padding(.top, 22)
      SettingsCaption(text: store.text("Как настроить", "How to set up")).padding(.top, 26)
      WalletSetupGuide()
    }
  }

  private func openShortcuts() {
    guard let url = URL(string: "shortcuts://") else { return }
    openURL(url) { accepted in shortcutsUnavailable = !accepted }
  }
}

/// «Счета и карты»: the order and the colour of the wallet's cards, kept on this iPhone. Every
/// change reaches the Finance page at once.
struct SettingsAccountsPage: View {
  @Environment(RitmStore.self) private var store
  @Environment(SettingsModel.self) private var model
  @State private var layoutStore = FinanceCardLayoutStore()

  var body: some View {
    let defaultCards = FinanceWallet.cards(store.financeEntries, today: store.today)
    Group {
      if defaultCards.isEmpty {
        SettingsPage(title: title) {
          SettingsFootnote(
            text: store.financeLoaded
              ? store.text("Счетов пока нет. Они появятся здесь, когда вы добавите их в Финансах.",
                "No accounts yet. They appear here once you add them in Finance.")
              : store.text("Загружаем…", "Loading…"))
        }
      } else {
        FinanceCardSettingsSheet(
          defaultCards: defaultCards, layoutStore: layoutStore,
          format: FinanceFormat(language: store.language, zone: store.timeZone, cards: defaultCards),
          embedded: true
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay { SettingsSavedToast() }
        .onChange(of: layoutStore.layout) { _, _ in
          model.showToast(model.text("Сохранено", "Saved"), failed: false)
        }
      }
    }
    .task { if !store.financeLoaded { await store.reloadFinance() } }
  }

  private var title: String { store.text("Счета и карты", "Accounts and cards") }
}

/// «Адрес сервера»: where this iPhone finds Ritm.
struct SettingsServerPage: View {
  @Environment(RitmStore.self) private var store

  var body: some View {
    SettingsPage(title: store.text("Адрес сервера", "Server address")) {
      ServerAddressCard()
    }
  }
}

/// Builds the page a settings row pushes.
struct SettingsDestination: View {
  let route: SettingsRoute

  var body: some View {
    switch route {
    case .profile: SettingsProfilePage()
    case .timeZone: SettingsTimeZonePage()
    case .workDay: SettingsWorkDayPage()
    case .google: SettingsGooglePage()
    case .telegram: SettingsTelegramPage()
    case .openAI: SettingsOpenAIPage()
    case .security: SettingsSecurityPage()
    case .health: SettingsHealthPage()
    case .liveActivity: SettingsLiveActivityPage()
    case .widgets: SettingsWidgetsPage()
    case .wallet: SettingsWalletPage()
    case .accounts: SettingsAccountsPage()
    case .server: SettingsServerPage()
    }
  }
}
