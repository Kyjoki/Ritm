import RitmCore
import SwiftUI
import UIKit

/// «Apple Wallet»: how Apple Pay purchases reach Ritm through a Shortcuts automation. The
/// recommended mode writes each payment to a file in Files and shows a notification from
/// Shortcuts, so Ritm does not open at every payment; the other mode opens Ritm through a link.
/// Everything stays on this iPhone.
struct WalletSettingsCard: View {
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
    SettingsCard(symbol: "wallet.pass", title: "Apple Wallet") {
      VStack(alignment: .leading, spacing: 0) {
        WalletNote(
          store.text(
            "Покупки Apple Pay попадают в Ritm через автоматизацию в приложении «Команды». Ritm предложит категорию, а вы только подтвердите.",
            "Apple Pay purchases reach Ritm through an automation in the Shortcuts app. Ritm suggests a category and you only confirm."
          )
        )
        .padding(.top, 8)
        modePicker.padding(.top, 14)
        switch mode {
        case .background: backgroundMode.padding(.top, 14)
        case .opensApp: opensAppMode.padding(.top, 14)
        }
        testRow.padding(.top, 16)
        memoryRow
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
        case .opensApp: store.text("Открывать приложение", "Open the app")
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
        Text(store.text("рекомендуется", "recommended"))
          .ritmFont(10, weight: .semibold)
          .foregroundStyle(RitmTheme.accentColor)
          .padding(.horizontal, 8)
          .frame(minHeight: 20)
          .background(RitmTheme.soft, in: Capsule())
      }
      WalletNote(
        store.text(
          "«Команды» сами записывают оплату в файл и показывают уведомление. Ritm не открывается: вы подтверждаете покупки, когда откроете его сами.",
          "Shortcuts writes the payment to a file and shows a notification by itself. Ritm does not open; you confirm purchases when you open it yourself."
        )
      )
      .padding(.top, 4)
      numberedSteps(backgroundSteps).padding(.top, 12)
      heading(store.text("Текст для «Добавить в файл»", "Text for Append to File")).padding(.top, 14)
      templateBox.padding(.top, 8)
      templateButtons(withNewLine: true).padding(.top, 10)
      heading(store.text("Папка Ritm", "The Ritm folder")).padding(.top, 16)
      WalletFolderPanel().padding(.top, 8)
    }
  }

  private var backgroundSteps: [String] {
    [
      store.text(
        "В приложении «Файлы» создайте папку Ritm: в iCloud Drive или «На iPhone». Ниже нажмите «Выбрать папку Ritm».",
        "In the Files app create a folder named Ritm, in iCloud Drive or On My iPhone. Below, tap Choose the Ritm folder."
      ),
      store.text(
        "Откройте «Команды» → «Автоматизация» → «+» → «Транзакция». Выберите карты и включите «Выполнить сразу».",
        "Open Shortcuts → Automation → + → Transaction. Pick your cards and turn on Run Immediately."
      ),
      store.text(
        "Добавьте действие «Добавить в файл»: папка Ritm, файл \(fileName). Текст — шаблон ниже, в конце новая строка (Return).",
        "Add the Append to File action: folder Ritm, file \(fileName). The text is the template below, ending with a new line (Return)."
      ),
      variablesStep,
      store.text(
        "Добавьте действие «Показать уведомление» с текстом «Новая оплата: <Amount> — <Merchant>. Откройте Ritm, чтобы подтвердить» (сумма и продавец — переменные).",
        "Add the Show Notification action with the text “New payment: <Amount> — <Merchant>. Open Ritm to confirm” (amount and merchant are variables)."
      ),
    ]
  }


  /// The same in both modes: the variables of the link.
  private var variablesStep: String {
    store.text(
      "На месте <Amount>, <Merchant>, <Card> и <Date> подставьте переменные «Транзакции»: сумма, продавец, карта, дата. После at= вставьте переменную «Текущая дата» и задайте формат ISO 8601 (с временем): по нему Ritm отличает две одинаковые покупки за один день. Вставленный текст сам не заменяется.",
      "Replace <Amount>, <Merchant>, <Card> and <Date> with the Transaction variables: amount, merchant, card, date. After at= insert the Current Date variable and set its format to ISO 8601 (with the time): that is how Ritm tells two identical purchases of one day apart. Pasted text is not replaced by itself."
    )
  }

  // MARK: Secondary: link

  private var opensAppMode: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Открывать приложение", "Open the app"))
        .ritmFont(13, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      WalletNote(
        store.text(
          "Ritm открывается на экране при каждой покупке и сразу показывает её в «Новых покупках».",
          "Ritm comes to the foreground at each payment and shows the purchase in New purchases right away."
        )
      )
      .padding(.top, 4)
      numberedSteps(opensAppSteps).padding(.top, 12)
      templateBox.padding(.top, 14)
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

  private func heading(_ text: String) -> some View {
    Text(text)
      .ritmFont(12, weight: .semibold)
      .foregroundStyle(RitmTheme.text)
      .accessibilityAddTraits(.isHeader)
  }

  private func numberedSteps(_ items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, text in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text("\(index + 1)")
            .ritmFont(11, weight: .semibold)
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

  private var templateBox: some View {
    Text(template)
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(RitmTheme.text)
      .textSelection(.enabled)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RitmTheme.glassDense, in: RoundedRectangle(cornerRadius: 11, style: .circular))
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .circular)
          .strokeBorder(RitmTheme.line, lineWidth: 1)
      }
      .accessibilityLabel(
        mode == .background
          ? store.text("Шаблон для «Добавить в файл»", "Template for Append to File")
          : store.text("Ссылка для «Открыть URL»", "Link for Open URL")
      )
      .accessibilityValue(template)
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
    VStack(alignment: .leading, spacing: 8) {
      heading(store.text("Проверка", "Test"))
      HStack(spacing: 8) {
        SettingsSmallButton(title: store.text("Проверить", "Test")) { store.receiveWalletTest() }
        WalletNote(
          store.text(
            "Добавит «Тестовую покупку» на 1 000 ₸ в «Новые покупки». В расходы она не записывается.",
            "Adds a “Test purchase” of 1,000 ₸ to New purchases. It is not recorded as spending."
          ))
      }
      if mode == .background { numberedSteps(testSteps) }
    }
  }

  private var testSteps: [String] {
    [
      store.text(
        "«Проверить» показывает, что список покупок в Ritm работает. Файл и «Команды» он не проверяет.",
        "Test shows that the purchase list in Ritm works. It does not check the file or Shortcuts."),
      store.text(
        "Оплатите небольшую покупку выбранной картой. Должно прийти уведомление от «Команд», а в «Файлы» → Ritm → \(fileName) появиться новая строка.",
        "Pay for something small with the chosen card. Shortcuts should show a notification and a new line should appear in Files → Ritm → \(fileName)."
      ),
      store.text(
        "Откройте Ritm или потяните «Финансы» вниз. Покупка появится в «Новых покупках».",
        "Open Ritm or pull Finance down. The purchase appears in New purchases."),
      store.text(
        "Нет уведомления или строка не появилась: в фоне запись в файл на вашем iPhone не работает. Используйте режим «Открывать приложение».",
        "No notification or no new line: writing to the file in the background does not work on your iPhone. Use the Open the app mode."
      ),
    ]
  }

  private var memoryRow: some View {
    let count = store.wallet.rememberedMerchants
    return HStack(spacing: 8) {
      SettingsSmallButton(title: store.text("Очистить память магазинов", "Clear merchant memory")) {
        confirmingClear = true
      }
      .disabled(count == 0)
      .opacity(count == 0 ? 0.5 : 1)
      WalletNote(
        count == 0
          ? store.text("Пока ничего не запомнено.", "Nothing remembered yet.")
          : store.text("Запомнено магазинов: \(count).", "Merchants remembered: \(count)."))
    }
    .padding(.top, 8)
  }

  // MARK: Limits

  private var limitItems: [String] {
    let common = [
      store.text(
        "Автоматизация может сработать не для каждой банковской карты.",
        "The automation may not fire for every bank card."),
      store.text(
        "Установка с бесплатным Apple ID перестаёт запускаться через 7 дней: приложение нужно собрать заново.",
        "A build signed with a free Apple ID stops launching after 7 days and must be reinstalled."),
      store.text(
        "Без at= (времени) две полностью одинаковые строки в файле считаются двумя покупками: лишняя лучше потерянной. Лишнюю можно пропустить.",
        "Without at= (the time), two completely identical lines in the file count as two purchases: an extra one is better than a lost one. You can skip the extra."
      ),
      store.text(
        "Покупки и память магазинов хранятся только на этом iPhone. На сервер и в ИИ они не уходят, пока вы не подтвердите покупку.",
        "Purchases and merchant memory stay on this iPhone. Nothing goes to the server or any AI until you confirm a purchase."
      ),
    ]
    switch mode {
    case .background:
      return [
        store.text(
          "Уведомление показывает приложение «Команды», а не Ritm: пока Ritm закрыт, он ничего не присылает.",
          "The notification comes from the Shortcuts app, not from Ritm: while Ritm is closed it sends nothing."
        ),
        store.text(
          "Покупки появляются в Ritm, когда вы его откроете или вернётесь в него, а не сразу после оплаты.",
          "Purchases appear in Ritm when you open it or come back to it, not right after the payment."
        ),
        store.text(
          "Запись в файл в фоне на этом iPhone не проверена: сначала пройдите проверку выше.",
          "Appending to the file in the background has not been verified on this iPhone: run the test above first."
        ),
        store.text(
          "Пока срок установки не истёк, «Команды» продолжают работать и дописывать файл. После переустановки Ritm покупки из файла подтянутся.",
          "When the install expires Shortcuts keeps working and keeps appending to the file. After you reinstall Ritm, the purchases are picked up from the file."
        ),
      ] + common
    case .opensApp:
      return [
        store.text(
          "Ritm открывается на экране при каждой покупке: так работает «Открыть URL».",
          "Ritm comes to the foreground at each payment: that is how Open URL works.")
      ] + common
    }
  }

  private var limits: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(store.text("Что важно знать", "Good to know"))
        .ritmFont(12, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      ForEach(limitItems, id: \.self) { text in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Circle().fill(RitmTheme.muted).frame(width: 4, height: 4).accessibilityHidden(true)
          WalletNote(text)
        }
      }
    }
    .padding(.top, 2)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1).offset(y: -8) }
  }
}
