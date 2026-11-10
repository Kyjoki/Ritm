import RitmCore
import SwiftUI

/// The sheets and the disconnect confirmation shared by the Google, Telegram and OpenAI pages.
private struct SettingsIntegrationDialogs: ViewModifier {
  @Binding var secretEditor: IntegrationKind?
  @Binding var confirmation: IntegrationKind?
  @Environment(RitmStore.self) private var store
  @Environment(SettingsModel.self) private var model

  private var isConfirming: Binding<Bool> {
    Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
  }

  func body(content: Content) -> some View {
    content
      .sheet(item: $secretEditor, onDismiss: { Task { await model.loadIntegrations() } }) { kind in
        IntegrationSecretEditor(kind: kind, googleSetup: model.googleSetup)
      }
      .confirmationDialog(title, isPresented: isConfirming, titleVisibility: .visible) {
        if let kind = confirmation {
          Button(store.text("Отключить", "Disconnect"), role: .destructive) {
            confirmation = nil
            Task { await model.disconnect(kind) }
          }
        }
      } message: {
        Text(message)
      }
  }

  private var title: String {
    confirmation == .google
      ? store.text("Отключить Google Calendar?", "Disconnect Google Calendar?")
      : store.text("Отключить интеграцию?", "Disconnect this integration?")
  }

  private var message: String {
    confirmation == .google
      ? store.text(
        "Ritm перестанет получать и изменять события. События в Google и подключение другого приложения сохранятся.",
        "Ritm will stop reading and changing events. Your Google events and other apps' access stay as they are.")
      : store.text(
        "Данные на стороне сервиса сохранятся. Подключение в Ritm потребуется настроить снова.",
        "Data in the service stays intact. You will need to reconnect it in Ritm.")
  }
}

extension View {
  func settingsIntegrationDialogs(
    secretEditor: Binding<IntegrationKind?>, confirmation: Binding<IntegrationKind?>
  ) -> some View {
    modifier(SettingsIntegrationDialogs(secretEditor: secretEditor, confirmation: confirmation))
  }
}

/// A row with a value and no action: the state of one part of an integration.
struct SettingsInfoRow: View {
  var icon: String?
  let title: String
  var subtitle: String?
  let value: SettingsTrailing

  var body: some View {
    SettingsListRow(icon: icon, title: title, subtitle: subtitle) { SettingsValue(value) }
      .accessibilityElement(children: .combine)
  }
}

/// The buttons under a status header, 10 pt apart.
struct SettingsButtonStack<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View { VStack(spacing: 10) { content }.padding(.top, 12) }
}

/// «Google»: connect or reconnect, what is granted (Calendar, Tasks, the full palette), the OAuth
/// client and disconnect. Google sign-in happens in the secure browser on the Ritm website.
struct SettingsGooglePage: View {
  @Environment(RitmStore.self) private var store
  @Environment(SettingsModel.self) private var model
  @State private var secretEditor: IntegrationKind?
  @State private var confirmation: IntegrationKind?
  @State private var showingBrowser = false

  private var google: GoogleCalendarStatus? { model.google }
  private var configured: Bool { model.googleSetup?.configured ?? google?.configured ?? false }
  private var connected: Bool { google?.status == .connected }
  private var reauth: Bool { google?.status == .reauthRequired }
  private var accessComplete: Bool { google?.tasksEnabled == true && google?.extendedColors == true }

  var body: some View {
    SettingsPage(title: "Google") {
      SettingsStatusHeader(title: statusTitle, detail: statusDetail, tone: tone)
      if connected { grants }
      actions
      if let notice = model.notice { SettingsNotice(text: notice) }
    }
    .settingsIntegrationDialogs(secretEditor: $secretEditor, confirmation: $confirmation)
    .sheet(
      isPresented: $showingBrowser,
      onDismiss: {
        Task {
          await store.refresh()
          await model.loadIntegrations()
        }
      }
    ) {
      IntegrationBrowser(server: store.serverAddress, onDismiss: { showingBrowser = false })
    }
  }

  // MARK: Status

  private var tone: SettingsTone {
    if connected { return .ok }
    return reauth || !configured ? .warn : .none
  }

  private var statusTitle: String {
    switch google?.status {
    case .connected: store.text("Подключён", "Connected")
    case .reauthRequired: store.text("Нужно подключить заново", "Reconnection needed")
    case .none: store.text("Статус пока не загружен", "Status not loaded yet")
    default:
      configured
        ? store.text("Не подключён", "Not connected")
        : store.text("Нужна настройка OAuth-клиента", "OAuth client setup needed")
    }
  }

  private var statusDetail: String {
    configured
      ? store.text(
        "Основной календарь · просмотр, создание и редактирование событий",
        "Primary calendar · view, create and edit events")
      : store.text(
        "Добавьте Client ID и Client Secret из Google Cloud",
        "Add the Client ID and Client Secret from Google Cloud")
  }

  // MARK: Grants

  private var grants: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsGroup {
        SettingsInfoRow(
          icon: "calendar", title: store.text("Календарь", "Calendar"),
          value: SettingsTrailing(store.text("Подключён", "Connected"), .ok))
        SettingsInfoRow(
          icon: "checkmark", title: store.text("Задачи", "Tasks"),
          value: google?.tasksEnabled == true
            ? SettingsTrailing(store.text("Подключены", "Connected"), .ok)
            : SettingsTrailing(store.text("Не подключены", "Not connected")))
        SettingsInfoRow(
          icon: "square.grid.2x2", title: store.text("Вся палитра цветов", "Full colour palette"),
          value: google?.extendedColors == true
            ? SettingsTrailing(store.text("Включена", "On"), .ok)
            : SettingsTrailing(store.text("Выключена", "Off")))
      }
      if let message = store.googleTasks?.message { SettingsFootnote(text: message) }
      if !accessComplete {
        SettingsFootnote(
          text: store.text(
            "Для задач и новых оттенков Google попросит разрешение на управление календарями.",
            "For tasks and more colours Google asks permission to manage calendars."))
      }
    }
  }

  // MARK: Actions

  private var actions: some View {
    SettingsButtonStack {
      if connected && !accessComplete {
        SettingsActionButton(
          title: store.text("Расширить доступ", "Extend access"), icon: "plus", kind: .secondary
        ) { showingBrowser = true }
      }
      if configured {
        SettingsActionButton(
          title: connected || reauth
            ? store.text("Переподключить", "Reconnect") : store.text("Подключить Google", "Connect Google"),
          icon: connected ? "arrow.clockwise" : nil, kind: connected ? .secondary : .primary
        ) { showingBrowser = true }
      }
      SettingsActionButton(
        title: configured
          ? store.text("Настройки OAuth-клиента", "OAuth client settings")
          : store.text("Настроить OAuth-клиент", "Set up the OAuth client"),
        kind: configured ? .secondary : .primary
      ) { secretEditor = .google }
      .disabled(model.googleSetup?.source == "environment")
      if configured && (connected || reauth) {
        SettingsActionButton(
          title: store.text("Отключить", "Disconnect"), kind: .dangerText
        ) { confirmation = .google }
      }
    }
    .disabled(!store.canWrite)
  }
}
