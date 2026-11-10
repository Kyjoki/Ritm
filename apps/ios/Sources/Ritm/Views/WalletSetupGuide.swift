import RitmCore
import SwiftUI
import UIKit

/// «Как настроить» on the Wallet page: how Apple Pay purchases reach Ritm through a Shortcuts automation. The
/// recommended mode writes each payment to a file in Files and shows a notification from
/// Shortcuts, so Ritm does not open at every payment; the other mode opens Ritm through a link.
/// Everything stays on this iPhone. Layout follows proto/sections/settings.js (`.s-wl-*`).
struct WalletSetupGuide: View {
  private enum Mode: Hashable { case background, opensApp }

  @Environment(RitmStore.self) private var store
  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mode = Mode.background
  @State private var copied = false
  @State private var copyReset: Task<Void, Never>?
  @State private var shortcutsUnavailable = false
  @State private var confirmingClear = false

  private var template: String { WalletLink.template(language: store.language) }
  private var fileName: String { WalletFileImport.fileName }

  var body: some View {
    RitmCard(padding: 20, radius: 24) {
      VStack(alignment: .leading, spacing: 0) {
        WalletNote(
          store.text(
            "Покупки Apple Pay попадают в Ritm через автоматизацию в приложении «Команды». Ritm предложит категорию, а вы только подтвердите.",
            "Apple Pay purchases reach Ritm through an automation in the Shortcuts app. Ritm suggests a category and you only confirm."
          )
        )
        modePicker.padding(.top, 12)
        switch mode {
        case .background: backgroundMode
        case .opensApp: opensAppMode
        }
        testRow.padding(.top, 14)
        memoryRow.padding(.top, 14)
        limits.padding(.top, 16)
      }
    }
    .confirmationDialog(
      store.text("Очистить память магазинов?", "Clear remembered merchants?"),
      isPresented: $confirmingClear, titleVisibility: .visible
    ) {
      Button(store.text("Очистить", "Clear"), role: .destructive) { store.wallet.clearMemory() }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(
        store.text(
          "Ritm забудет, какие категории вы выбирали для магазинов. Новые покупки снова придётся классифицировать вручную.",
          "Ritm will forget the categories you chose for merchants. New purchases will need a category again."
        ))
    }
  }

  private var modePicker: some View {
    RitmSegmentedControl(
      label: store.text("Способ получения покупок", "How purchases arrive"),
      values: [Mode.background, .opensApp],
      title: { value in
        switch value {
        case .background: store.text("Без открытия", "Without opening")
        case .opensApp: store.text("Открывать", "Open")
        }
      },
      selection: $mode, fontSize: 12)
  }

  // MARK: Recommended: file

  private var backgroundMode: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text(store.text("Без открытия приложения", "Without opening the app"))
          .ritmFont(13, weight: .semibold)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        Text(store.text("Рекомендуется", "Recommended"))
          .ritmFont(10, weight: .bold)
          .foregroundStyle(RitmTheme.accentColor)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(RitmTheme.soft, in: Capsule())
      }
      .padding(.top, 14)
      WalletNote(
        store.text(
          "Автоматизация сама дописывает покупку в файл и показывает уведомление, Ritm при этом не открывается. Покупки попадут в «Новые покупки», когда вы откроете Ritm.",
          "The automation appends the purchase to the file and shows a notification by itself; Ritm does not open. Purchases land in New purchases when you open Ritm."
        )
      )
      .padding(.top, 4)
      numberedSteps(backgroundSteps).padding(.top, 14)
      templateBox(template, label: store.text("Строка для «Добавить в файл»", "Line for Append to File"))
        .padding(.top, 14)
      templateBox(notificationText, label: store.text("Текст уведомления", "Notification text"))
        .padding(.top, 8)
      templateButtons(withNewLine: true).padding(.top, 10)
    }
  }

  private var notificationText: String {
    store.text(
      "Новая оплата: <Amount> — <Merchant>. Откройте Ritm, чтобы подтвердить",
      "New payment: <Amount> — <Merchant>. Open Ritm to confirm")
  }

  private var backgroundSteps: [String] {
    [
      store.text(
        "Откройте «Команды» → «Автоматизация» → «+» → «Транзакция».",
        "Open Shortcuts → Automation → + → Transaction."),
      store.text(
        "Нажмите «Выбрать карты» и отметьте нужные. Включите «Выполнить сразу».",
        "Tap Choose Cards and pick yours. Turn on Run Immediately."),
      store.text(
        "Добавьте действие «Добавить в файл»: папка «Ritm», файл \(fileName). В текст вставьте шаблон ниже и добавьте новую строку.",
        "Add the Append to File action: folder “Ritm”, file \(fileName). Paste the template below as the text and add a new line."
      ),
      variablesStep,
      store.text(
        "Добавьте действие «Показать уведомление» с текстом ниже.",
        "Add the Show Notification action with the text below."),
    ]
  }

  /// The same in both modes: the variables of the link.
  private var variablesStep: String {
    store.text(
      "На месте <Amount>, <Merchant>, <Card> и <Date> подставьте переменные «Транзакции»: сумма, продавец, карта, дата. После at= вставьте переменную «Текущая дата» с форматом ISO 8601 и временем: так две одинаковые покупки за день не сольются в одну. Вставленный текст сам не заменяется.",
      "Replace <Amount>, <Merchant>, <Card> and <Date> with the Transaction variables: amount, merchant, card, date. After at= insert the Current Date variable in ISO 8601 with the time, so two identical purchases of one day do not merge. Pasted text is not replaced by itself."
    )
  }

  // MARK: Secondary: link

  private var opensAppMode: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Открывать приложение", "Open the app"))
        .ritmFont(13, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, 14)
      WalletNote(
        store.text(
          "Каждая оплата открывает Ritm на экране через «Открыть URL» и сразу добавляет покупку.",
          "Each payment brings Ritm to the screen through Open URL and adds the purchase right away."
        )
      )
      .padding(.top, 4)
      numberedSteps(opensAppSteps).padding(.top, 14)
      templateBox(template, label: store.text("Ссылка для «Открыть URL»", "Link for Open URL"))
        .padding(.top, 14)
      templateButtons(withNewLine: false).padding(.top, 10)
    }
  }

  private var opensAppSteps: [String] {
    [
      store.text(
        "Откройте «Команды» → «Автоматизация» → «+» → «Транзакция».",
        "Open Shortcuts → Automation → + → Transaction."),
      store.text(
        "Нажмите «Выбрать карты» и отметьте нужные. Включите «Выполнить сразу».",
        "Tap Choose Cards and pick yours. Turn on Run Immediately."),
      store.text(
        "Добавьте действие «Открыть URL» и вставьте ссылку ниже.",
        "Add the Open URL action and paste the link below."),
      variablesStep,
    ]
  }

  // MARK: Shared pieces

  private func numberedSteps(_ items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, text in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text("\(index + 1)")
            .ritmFont(11, weight: .bold)
            .monospacedDigit()
            .foregroundStyle(RitmTheme.accentColor)
            .frame(width: 22, height: 22)
            .background(RitmTheme.soft, in: Circle())
            .accessibilityHidden(true)
          WalletNote(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.text("Шаг \(index + 1). \(text)", "Step \(index + 1). \(text)"))
      }
    }
  }

  /// `.s-wl-url`: a selectable monospaced box with the text to paste into Shortcuts.
  private func templateBox(_ text: String, label: String) -> some View {
    Text(text)
      .font(.system(size: 12, design: .monospaced))
      .lineSpacing(3)
      .foregroundStyle(RitmTheme.text)
      .textSelection(.enabled)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RitmTheme.glassDense, in: RoundedRectangle(cornerRadius: 11, style: .circular))
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .circular)
          .strokeBorder(RitmTheme.line, lineWidth: 1)
      }
      .accessibilityLabel(label)
      .accessibilityValue(text)
  }

  private func templateButtons(withNewLine: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        SettingsSmallButton(
          title: copied ? store.text("Скопировано", "Copied") : store.text("Скопировать", "Copy"),
          action: { copyTemplate(withNewLine: withNewLine) })
        SettingsSmallButton(
          title: store.text("Открыть Команды", "Open Shortcuts"), action: openShortcuts)
      }
      if shortcutsUnavailable {
        WalletNote(
          store.text(
            "Не удалось открыть «Команды». Откройте приложение вручную.",
            "Could not open Shortcuts. Open the app yourself."))
      }
    }
  }

  /// For the file the copied text ends with a line break, so every payment is its own line.
  private func copyTemplate(withNewLine: Bool) {
    UIPasteboard.general.string = withNewLine ? template + "\n" : template
    UIAccessibility.post(
      notification: .announcement, argument: store.text("Шаблон скопирован", "Template copied"))
    withAnimation(reduceMotion ? nil : RitmMotion.easeOut(0.2)) { copied = true }
    copyReset?.cancel()
    copyReset = Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : RitmMotion.easeOut(0.2)) { copied = false }
    }
  }

  private func openShortcuts() {
    guard let url = URL(string: "shortcuts://") else { return }
    openURL(url) { accepted in shortcutsUnavailable = !accepted }
  }

  // MARK: Test and memory

  private var testRow: some View {
    HStack(spacing: 10) {
      SettingsSmallButton(title: store.text("Проверить", "Test")) { store.receiveWalletTest() }
      WalletNote(
        store.text(
          "Добавит «Тестовую покупку» на 1 000 ₸ в «Новые покупки». В расходы она не записывается.",
          "Adds a “Test purchase” of 1,000 ₸ to New purchases. It is not recorded as spending."
        ))
    }
  }

  private var memoryRow: some View {
    let count = store.wallet.rememberedMerchants
    return HStack(spacing: 10) {
      SettingsSmallButton(title: store.text("Очистить память магазинов", "Clear merchant memory")) {
        confirmingClear = true
      }
      .disabled(count == 0)
      WalletNote(
        count == 0
          ? store.text("Пока ничего не запомнено.", "Nothing remembered yet.")
          : store.text("Запомнено магазинов: \(count).", "Merchants remembered: \(count)."))
    }
  }

  // MARK: Limits

  private var limitItems: [String] {
    let common = [
      store.text(
        "Автоматизация может сработать не для каждой банковской карты.",
        "The automation may not fire for every bank card."),
      store.text(
        "Установка с бесплатным Apple ID перестаёт работать через 7 дней: приложение нужно собрать заново.",
        "A build signed with a free Apple ID stops working after 7 days and must be rebuilt."),
      store.text(
        "Покупки и память магазинов хранятся только на этом iPhone. На сервер и в ИИ они не уходят, пока вы не подтвердите покупку.",
        "Purchases and merchant memory stay on this iPhone. Nothing goes to the server or any AI until you confirm a purchase."
      ),
    ]
    switch mode {
    case .background:
      return [
        store.text(
          "Уведомление «Новая оплата» показывают «Команды», а не Ritm.",
          "The New payment notification comes from Shortcuts, not from Ritm."),
        store.text(
          "Покупки появляются в Ritm, когда вы его откроете, а не мгновенно.",
          "Purchases appear in Ritm when you open it, not instantly."),
        store.text(
          "Добавление в файл в фоне на настоящем iPhone ещё не проверено.",
          "Appending to the file in the background has not been verified on a real iPhone yet."),
      ] + common
    case .opensApp:
      return [
        store.text(
          "Ritm открывается на экране при каждой покупке: так работает «Открыть URL».",
          "Ritm comes to the foreground at each payment: that is how Open URL works.")
      ] + common
    }
  }

  /// `.s-wl-lim`: a hairline, the title and bulleted notes.
  private var limits: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsDivider()
      Text(store.text("Что важно знать", "Good to know"))
        .ritmFont(12, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, 10)
      VStack(alignment: .leading, spacing: 6) {
        ForEach(limitItems, id: \.self) { text in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(RitmTheme.muted).frame(width: 4, height: 4).accessibilityHidden(true)
            WalletNote(text)
          }
        }
      }
      .padding(.top, 6)
    }
  }
}
