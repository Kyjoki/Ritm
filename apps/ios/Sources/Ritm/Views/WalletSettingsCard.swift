import RitmCore
import SwiftUI
import UIKit

/// «Apple Wallet»: how to send Apple Pay purchases to Ritm through a Shortcuts automation, the
/// link to paste, a test button and the memory of merchants. Everything stays on this iPhone.
struct WalletSettingsCard: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var copied = false
  @State private var copyReset: Task<Void, Never>?
  @State private var shortcutsUnavailable = false
  @State private var confirmingClear = false

  private var template: String { WalletLink.template(language: store.language) }

  var body: some View {
    SettingsCard(symbol: "wallet.pass", title: "Apple Wallet") {
      VStack(alignment: .leading, spacing: 0) {
        paragraph(
          store.text(
            "Покупки Apple Pay попадают в Ritm через автоматизацию в приложении «Команды». Ritm предложит категорию, а вы только подтвердите.",
            "Apple Pay purchases reach Ritm through an automation in the Shortcuts app. Ritm suggests a category and you only confirm."
          )
        )
        .padding(.top, 8)
        steps.padding(.top, 14)
        linkBox.padding(.top, 14)
        linkButtons.padding(.top, 10)
        testRow.padding(.top, 14)
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

  // MARK: Steps

  private var steps: some View {
    let items = [
      store.text(
        "Откройте «Команды» → «Автоматизация» → «+» → «Транзакция».",
        "Open Shortcuts → Automation → + → Transaction."),
      store.text(
        "Нажмите «Выбрать карты» и отметьте нужные. Включите «Выполнить сразу».",
        "Tap Choose Cards and pick yours. Turn on Run Immediately."),
      store.text(
        "Добавьте действие «Открыть URL» и вставьте ссылку ниже.",
        "Add the Open URL action and paste the link below."),
      store.text(
        "На месте <Amount>, <Merchant>, <Card> и <Date> подставьте переменные «Транзакции»: сумма, продавец, карта, дата. Вставленный текст сам не заменяется.",
        "Replace <Amount>, <Merchant>, <Card> and <Date> with the Transaction variables: amount, merchant, card, date. Pasted text is not replaced by itself."
      ),
    ]
    return VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, text in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text("\(index + 1)")
            .ritmFont(11, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(RitmTheme.accentColor)
            .frame(width: 22, height: 22)
            .background(RitmTheme.soft, in: Circle())
            .accessibilityHidden(true)
          paragraph(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.text("Шаг \(index + 1). \(text)", "Step \(index + 1). \(text)"))
      }
    }
  }

  // MARK: Link

  private var linkBox: some View {
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
      .accessibilityLabel(store.text("Ссылка для «Открыть URL»", "Link for Open URL"))
      .accessibilityValue(template)
  }

  private var linkButtons: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        SettingsSmallButton(
          title: copied ? store.text("Скопировано", "Copied") : store.text("Скопировать", "Copy"),
          action: copyTemplate)
        SettingsSmallButton(
          title: store.text("Открыть Команды", "Open Shortcuts"), action: openShortcuts)
      }
      if shortcutsUnavailable {
        paragraph(
          store.text(
            "Не удалось открыть «Команды». Откройте приложение вручную.",
            "Could not open Shortcuts. Open the app yourself."))
      }
    }
  }

  private func copyTemplate() {
    UIPasteboard.general.string = template
    UIAccessibility.post(
      notification: .announcement, argument: store.text("Ссылка скопирована", "Link copied"))
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
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        SettingsSmallButton(title: store.text("Проверить", "Test")) { store.receiveWalletTest() }
        paragraph(
          store.text(
            "Добавит «Тестовую покупку» на 1 000 ₸ в «Новые покупки». В расходы она не записывается.",
            "Adds a “Test purchase” of 1,000 ₸ to New purchases. It is not recorded as spending."
          ))
      }
    }
  }

  private var memoryRow: some View {
    let count = store.wallet.rememberedMerchants
    return HStack(spacing: 8) {
      SettingsSmallButton(title: store.text("Очистить память магазинов", "Clear merchant memory")) {
        confirmingClear = true
      }
      .disabled(count == 0)
      .opacity(count == 0 ? 0.5 : 1)
      paragraph(
        count == 0
          ? store.text("Пока ничего не запомнено.", "Nothing remembered yet.")
          : store.text("Запомнено магазинов: \(count).", "Merchants remembered: \(count)."))
    }
    .padding(.top, 8)
  }

  // MARK: Limits

  private var limits: some View {
    let items = [
      store.text(
        "Ritm открывается на экране при каждой покупке: так работает «Открыть URL».",
        "Ritm comes to the foreground at each payment: that is how Open URL works."),
      store.text(
        "Автоматизация может сработать не для каждой банковской карты.",
        "The automation may not fire for every bank card."),
      store.text(
        "Установка с бесплатным Apple ID перестаёт работать через 7 дней: приложение нужно собрать заново.",
        "A build signed with a free Apple ID expires after 7 days and must be reinstalled."),
      store.text(
        "Покупки и память магазинов хранятся только на этом iPhone. На сервер и в ИИ они не уходят, пока вы не подтвердите покупку.",
        "Purchases and merchant memory stay on this iPhone. Nothing goes to the server or any AI until you confirm a purchase."
      ),
    ]
    return VStack(alignment: .leading, spacing: 6) {
      Text(store.text("Что важно знать", "Good to know"))
        .ritmFont(12, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      ForEach(items, id: \.self) { text in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Circle().fill(RitmTheme.muted).frame(width: 4, height: 4).accessibilityHidden(true)
          paragraph(text)
        }
      }
    }
    .padding(.top, 2)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1).offset(y: -8) }
  }

  private func paragraph(_ text: String) -> some View {
    Text(text)
      .ritmFont(11, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
