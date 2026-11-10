import RitmCore
import SwiftUI

/// «Telegram»: the bot, the private chat, and the reminders sent there with their lead time.
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
  private var enabled: Bool { model.reminderDraft?.enabled ?? telegram?.reminders?.enabled ?? false }
  private var lead: Int { model.reminderDraft?.lead ?? telegram?.reminders?.leadMinutes ?? 10 }

  var body: some View {
    SettingsPage(title: "Telegram") {
      SettingsStatusHeader(title: statusTitle, detail: statusDetail, tone: tone)
      if !configured {
        SettingsButtonStack {
          SettingsActionButton(title: store.text("Подключить бота", "Connect a bot")) { secretEditor = .telegram }
        }
      } else {
        chat
        if linked { reminders }
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

  // MARK: Reminders

  private var reminders: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsCaption(text: store.text("Напоминания", "Reminders")).padding(.top, 20)
      SettingsGroup {
        SettingsToggleRow(
          icon: "bell", title: store.text("Напоминания в Telegram", "Telegram reminders"),
          subtitle: deliveryText,
          isOn: Binding(
            get: { enabled }, set: { value in Task { await model.saveReminders(enabled: value, lead: lead) } }))
        .disabled(!store.canWrite)
      }
      if enabled {
        SettingsCaption(text: store.text("Напомнить за, мин", "Remind me, min before")).padding(.top, 20)
        RitmSegmentedControl(
          label: store.text("Когда напомнить", "When to remind"), values: SettingsSummary.leadChoices,
          title: { SettingsSummary.leadSegment($0, model.language) },
          selection: Binding(
            get: { lead }, set: { value in Task { await model.saveReminders(enabled: true, lead: value) } }),
          fontSize: 12
        )
        .disabled(!store.canWrite)
      }
      SettingsButtonStack {
        SettingsActionButton(
          title: store.text("Тестовое уведомление", "Test notification"), icon: "paperplane", kind: .secondary
        ) { Task { await model.testTelegram() } }
        .disabled(!store.canWrite)
      }
      SettingsFootnote(
        text: store.text(
          "В личном чате отправь /menu, чтобы открыть кнопки быстрых дел, плана и итога. Сообщения не передаются ИИ.",
          "Send /menu in the private chat to open quick task, plan and summary buttons. Messages are not passed to AI."))
    }
  }

  private var deliveryText: String {
    let reminders = telegram?.reminders
    if reminders?.ready == true { return store.text("Автоматическая отправка работает", "Automatic delivery is working") }
    return reminders?.problem.flatMap { SettingsSummary.telegramProblem($0, model.language) }
      ?? store.text("Ожидание планировщика или привязки чата", "Waiting for the scheduler or a linked chat")
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
