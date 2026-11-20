import RitmCore
import SwiftUI

/// «Telegram»: the bot, the private chat, and the buttons in it.
struct SettingsTelegramPage: View {
  @Environment(RitmStore.self) private var store
  @Environment(SettingsModel.self) private var model
  @Environment(\.openURL) private var openURL
  @State private var secretEditor: IntegrationKind?
  @State private var confirmation: IntegrationKind?
  @State private var busy = false

  private var telegram: TelegramStatus? { model.telegram }
  private var configured: Bool { telegram?.configured == true }
  private var linked: Bool { telegram?.linked == true }

  var body: some View {
    SettingsPage(title: "Telegram") {
      SettingsStatusHeader(title: statusTitle, detail: statusDetail, tone: tone)
      if !configured {
        SettingsButtonStack {
          SettingsActionButton(title: store.text("Подключить бота", "Connect a bot")) { secretEditor = .telegram }
        }
      } else {
        chat
        if linked { menuHint }
        actions
      }
      if let notice = model.notice { SettingsNotice(text: notice) }
    }
    .settingsIntegrationDialogs(secretEditor: $secretEditor, confirmation: $confirmation)
  }

  // MARK: Status

  private var tone: SettingsTone { linked ? .ok : configured ? .warn : .none }

  private var statusTitle: String {
    if linked { return store.text("Личный чат привязан", "Private chat linked") }
    return configured
      ? store.text("Бот настроен · чат не привязан", "Bot configured · chat not linked")
      : store.text("Не настроен", "Not configured")
  }

  private var statusDetail: String {
    telegram?.botUsername.map { "@" + $0 }
      ?? store.text(
        "Подключи своего бота, затем привяжи личный чат.", "Connect your bot, then link your private chat.")
  }

  // MARK: Chat

  @ViewBuilder private var chat: some View {
    if linked, let account = telegram?.account {
      SettingsGroup {
        SettingsInfoRow(
          icon: "person", title: store.text("Чат", "Chat"),
          value: SettingsTrailing(account.username.map { "@" + $0 } ?? account.firstName))
      }
    } else if let url = model.safePairingURL, !linked {
      pairing(url)
    } else if !linked {
      SettingsButtonStack {
        SettingsActionButton(title: store.text("Привязать чат", "Link chat"), busy: busy) {
          Task {
            busy = true
            await model.pairTelegram()
            busy = false
          }
        }
        .disabled(!store.canWrite)
      }
    }
  }

  private func pairing(_ url: URL) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsFootnote(
        text: store.text(
          "Открой ссылку в Telegram и нажми Start, затем вернись сюда. Ссылка действует 10 минут.",
          "Open the link in Telegram and tap Start, then come back. The link is valid for 10 minutes."))
      SettingsButtonStack {
        SettingsActionButton(title: store.text("Открыть бота в Telegram", "Open the bot in Telegram"), icon: "paperplane") {
          openURL(url)
        }
        SettingsActionButton(title: store.text("Проверить подключение", "Check connection"), kind: .secondary) {
          Task { await model.loadIntegrations() }
        }
      }
    }
  }

  private var menuHint: some View {
    SettingsFootnote(
      text: store.text(
        "В личном чате отправь /menu, чтобы открыть кнопки быстрых дел, плана и итога. Сообщения не передаются ИИ.",
        "Send /menu in the private chat to open quick task, plan and summary buttons. Messages are not passed to AI."))
  }

  // MARK: Actions

  private var actions: some View {
    SettingsButtonStack {
      SettingsActionButton(title: store.text("Сменить бота", "Change bot"), kind: .secondary) {
        secretEditor = .telegram
      }
      SettingsActionButton(title: store.text("Отключить Telegram", "Disconnect Telegram"), kind: .dangerText) {
        confirmation = .telegram
      }
    }
    .disabled(!store.canWrite)
  }

}
