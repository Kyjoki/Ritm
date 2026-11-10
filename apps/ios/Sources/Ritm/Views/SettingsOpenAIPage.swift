import RitmCore
import SwiftUI

/// «OpenAI»: whether a key is set, set or replace it, delete it. A key kept in the server's
/// environment is managed there and cannot be changed from the phone.
struct SettingsOpenAIPage: View {
  @Environment(RitmStore.self) private var store
  @Environment(SettingsModel.self) private var model
  @State private var secretEditor: IntegrationKind?
  @State private var confirmation: IntegrationKind?

  private var status: AIStatus? { store.bootstrap?.aiStatus }
  private var configured: Bool { status?.configured == true }
  private var managedByServer: Bool { status?.source == "environment" }

  var body: some View {
    SettingsPage(title: "OpenAI") {
      SettingsStatusHeader(title: title, detail: detail, tone: configured ? .ok : .none)
      if managedByServer {
        SettingsFootnote(text: store.text("Настройкой управляет сервер", "The server manages this setting"))
      } else {
        actions
      }
      if let notice = model.notice { SettingsNotice(text: notice) }
    }
    .settingsIntegrationDialogs(secretEditor: $secretEditor, confirmation: $confirmation)
  }

  private var title: String {
    configured ? store.text("Ключ задан", "Key configured") : store.text("Нет ключа", "No key")
  }

  private var detail: String {
    configured
      ? store.text("Модель: ", "Model: ") + (status?.model ?? "")
      : store.text("Нужен для ИИ-подсказок", "Needed for AI suggestions")
  }

  private var actions: some View {
    SettingsButtonStack {
      SettingsActionButton(
        title: configured ? store.text("Заменить ключ", "Replace the key") : store.text("Добавить ключ", "Add a key"),
        icon: "key", kind: configured ? .secondary : .primary
      ) { secretEditor = .ai }
      if status?.source == "saved" {
        SettingsActionButton(title: store.text("Удалить ключ", "Remove the key"), kind: .dangerText) {
          confirmation = .ai
        }
      }
    }
    .disabled(!store.canWrite)
  }
}
