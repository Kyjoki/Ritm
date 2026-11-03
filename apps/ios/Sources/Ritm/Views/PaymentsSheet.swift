import RitmCore
import SwiftUI

private struct PaymentEditRoute: Identifiable {
  let id = UUID()
  var paymentID: String?
}

/// What the owner is asked to confirm. The planned date is captured when the dialog opens, so
/// the confirmation is tied to that occurrence even if the list changes meanwhile.
private struct PaymentPrompt: Identifiable {
  enum Kind { case pay, skip, delete, retry }
  let id = UUID()
  let kind: Kind
  let paymentID: String
  let planned: String
}

/// The list of recurring payments with the actions on each. A due date alone never records an
/// expense; «Оплачено» does, and only after the owner confirms.
struct PaymentsSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let cards: [FinanceCard]
  let format: FinanceFormat
  @State private var editing: PaymentEditRoute?
  @State private var prompt: PaymentPrompt?
  @State private var busy: Set<String> = []

  var body: some View {
    let today = store.today
    let items = store.payments.book.sorted(today: today)
    return ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          header
          Button { editing = PaymentEditRoute(paymentID: nil) } label: {
            Label { Text(format.text("Добавить платёж", "Add payment")) } icon: { RitmSymbol("plus") }
          }
          .buttonStyle(RitmPrimaryButtonStyle())
          .disabled(!cards.contains { $0.kind == .account })
          if items.isEmpty {
            RitmCard {
              RitmEmptyState(
                symbol: "calendar.badge.clock",
                title: format.text("Регулярных платежей нет", "No recurring payments"),
                message: format.text("Добавьте первый платёж.", "Add the first payment."))
            }
          } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, payment in
              card(payment, today: today)
                .ritmPageReveal(index: min(index + 1, 7))
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
    }
    .presentationDetents([.medium, .large])
    .ritmSheetGrabber()
    .presentationCornerRadius(22)
    .sheet(item: $editing) { route in
      PaymentEditorSheet(paymentID: route.paymentID, cards: cards, format: format)
        .environment(store)
    }
    .alert(
      promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
      presenting: prompt
    ) { current in
      Button(confirmTitle(current), role: current.kind == .delete ? .destructive : nil) {
        confirm(current)
      }
      Button(format.text("Отмена", "Cancel"), role: .cancel) {}
    } message: { current in
      Text(message(for: current))
    }
  }

  private func card(_ payment: RecurringPayment, today: String) -> some View {
    PaymentCard(
      payment: payment, format: format, today: today,
      unresolved: store.payments.book.hasUnresolvedAttempt(payment.id),
      working: busy.contains(payment.id), canWrite: store.canWrite,
      pay: { begin(payment) },
      edit: { editing = PaymentEditRoute(paymentID: payment.id) },
      skip: {
        prompt = PaymentPrompt(kind: .skip, paymentID: payment.id, planned: payment.nextDate)
      },
      togglePause: { store.payments.apply { $0.togglingPause(payment.id) } },
      remove: {
        prompt = PaymentPrompt(kind: .delete, paymentID: payment.id, planned: payment.nextDate)
      })
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(format.text("Регулярные платежи", "Recurring payments"))
        .ritmFont(22, weight: .semibold, tracking: -0.04)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 12)
      Button(format.text("Готово", "Done")) { dismiss() }
        .buttonStyle(RitmSecondaryButtonStyle())
    }
    .padding(.top, 28)
  }

  // MARK: Prompts

  private var promptTitle: String {
    switch prompt?.kind {
    case .pay: format.text("Подтвердить оплату?", "Confirm payment?")
    case .skip: format.text("Пропустить платёж?", "Skip this payment?")
    case .delete: format.text("Удалить платёж?", "Delete payment?")
    case .retry: format.text("Расход не найден", "Expense not found")
    case nil: ""
    }
  }

  private func confirmTitle(_ prompt: PaymentPrompt) -> String {
    switch prompt.kind {
    case .pay: format.text("Оплатить", "Pay")
    case .skip: format.text("Пропустить", "Skip")
    case .delete: format.text("Удалить", "Delete")
    case .retry: format.text("Записать снова", "Record again")
    }
  }

  private func message(for prompt: PaymentPrompt) -> String {
    guard let payment = store.payments.book.payment(prompt.paymentID) else { return "" }
    let today = store.today
    let date = format.paymentDate(prompt.planned, today: today)
    let amount = format.money(payment.amountMinor, payment.currency)
    switch prompt.kind {
    case .pay:
      let account = format.accountName(payment.accountID) ?? payment.currency.rawValue
      let when =
        prompt.planned > today
        ? format.text(
          "Раньше срока, за плановую дату \(date).", "Early, for the planned date \(date).")
        : prompt.planned < today
          ? format.text("Просрочен, за \(date).", "Overdue, for \(date).")
          : format.text("За \(date).", "For \(date).")
      return format.text(
        "\(payment.name) · \(amount) · со счёта «\(account)». \(when) Будет записан расход за сегодня.",
        "\(payment.name) · \(amount) · from “\(account)”. \(when) An expense dated today will be recorded."
      )
    case .skip:
      let following = payment.followingDate.map { format.paymentDate($0, today: today) } ?? ""
      return format.text(
        "«\(payment.name)» за \(date) будет пропущен без расхода. Следующая дата: \(following).",
        "“\(payment.name)” for \(date) will be skipped without an expense. Next date: \(following)."
      )
    case .delete:
      return format.text(
        "«\(payment.name)» будет удалён из расписания. Записанные расходы останутся в истории.",
        "“\(payment.name)” will be removed from the schedule. Recorded expenses stay in the history."
      )
    case .retry:
      return format.text(
        "Ответ сервера не получен, и этого расхода нет в истории. Записать расход ещё раз?",
        "No answer from the server was received and the history has no such expense. Record it again?"
      )
    }
  }

  // MARK: Actions

  /// «Оплачено»: if an earlier answer was lost, look at the history first.
  private func begin(_ payment: RecurringPayment) {
    guard !busy.contains(payment.id) else { return }
    if store.payments.book.hasUnresolvedAttempt(payment.id) {
      Task { await check(payment) }
    } else {
      prompt = PaymentPrompt(kind: .pay, paymentID: payment.id, planned: payment.nextDate)
    }
  }

  private func check(_ payment: RecurringPayment) async {
    guard busy.insert(payment.id).inserted else { return }
    defer { busy.remove(payment.id) }
    await store.reloadFinance()
    store.reconcileRecurringPayments()
    guard store.payments.book.hasUnresolvedAttempt(payment.id) else {
      store.toasts.show(format.text("Расход найден в истории", "Expense found in the history"))
      return
    }
    if store.uncertainWrite {
      store.toasts.show(
        format.text(
          "Сначала проверьте историю и подтвердите статус", "Check the history and confirm first"))
    } else {
      prompt = PaymentPrompt(kind: .retry, paymentID: payment.id, planned: payment.nextDate)
    }
  }

  private func confirm(_ current: PaymentPrompt) {
    switch current.kind {
    case .pay:
      Task { await pay(current) }
    case .retry:
      store.releaseRecurringAttempt(id: current.paymentID)
      Task { await pay(current) }
    case .skip:
      let error = store.payments.apply { $0.skipping(current.paymentID, planned: current.planned) }
      store.toasts.show(
        error == nil
          ? format.text("Пропущено · расход не записан", "Skipped · no expense recorded")
          : format.text("Дата платежа уже изменилась", "The payment date has changed"))
    case .delete:
      store.payments.apply { $0.deleting(current.paymentID) }
      store.toasts.show(format.text("Платёж удалён", "Payment deleted"))
    }
  }

  private func pay(_ current: PaymentPrompt) async {
    guard busy.insert(current.paymentID).inserted else { return }
    defer { busy.remove(current.paymentID) }
    switch await store.payRecurring(id: current.paymentID, planned: current.planned) {
    case .paid: break
    case .unknown:
      store.toasts.show(
        format.text(
          "Результат не подтверждён. Проверьте историю", "Result not confirmed. Check the history"))
    case .failed:
      store.toasts.show(format.text("Не удалось записать расход", "Could not record the expense"))
    case .refused(let error):
      store.toasts.show(
        error == .occurrenceRecorded || error == .staleOccurrence
          ? format.text("Эта дата уже учтена", "This date is already handled")
          : format.text("Сейчас оплата недоступна", "Payment is unavailable right now"))
    }
  }
}

// MARK: - Card

private struct PaymentCard: View {
  let payment: RecurringPayment
  let format: FinanceFormat
  let today: String
  let unresolved: Bool
  let working: Bool
  let canWrite: Bool
  let pay: () -> Void
  let edit: () -> Void
  let skip: () -> Void
  let togglePause: () -> Void
  let remove: () -> Void

  var body: some View {
    let status = payment.status(today: today)
    let account = format.accountName(payment.accountID) ?? payment.currency.rawValue
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        RitmSymbol(FinanceCategories.symbol(for: payment.category))
          .font(.system(size: 17))
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 38, height: 38)
          .background(RitmTheme.soft, in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(payment.name)
            .ritmFont(14, weight: .semibold, tracking: -0.02)
            .foregroundStyle(RitmTheme.text)
            .lineLimit(2)
          Text("\(account) · \(payment.currency.rawValue)")
            .ritmFont(11).foregroundStyle(RitmTheme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(format.money(payment.amountMinor, payment.currency))
          .ritmFont(14, weight: .semibold, tracking: -0.02)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.text)
          .multilineTextAlignment(.trailing)
          .lineLimit(2)
          .minimumScaleFactor(0.7)
          .frame(maxWidth: 150, alignment: .trailing)
      }
      meta(status)
      actions(status)
    }
    .padding(12)
    .background { RitmPanelBackground(radius: 20) }
    .opacity(status == .paused ? 0.86 : 1)
    .accessibilityElement(children: .contain)
  }

  private func meta(_ status: PaymentStatus) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        chip(format.statusName(status), tint: status.tint, fill: status.fill, outlined: status == .paused)
        if unresolved {
          chip(
            format.text("проверьте историю", "check the history"), tint: RitmTheme.danger,
            fill: RitmTheme.dangerSoft, outlined: false)
        }
      }
      Text(dateLine(status))
        .ritmFont(11).foregroundStyle(RitmTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func chip(_ title: String, tint: Color, fill: Color, outlined: Bool) -> some View {
    Text(title)
      .ritmFont(10.5, weight: .semibold)
      .foregroundStyle(tint)
      .padding(.horizontal, 9)
      .frame(minHeight: 22)
      .background(fill, in: Capsule())
      .overlay { if outlined { Capsule().strokeBorder(RitmTheme.line) } }
  }

  private func dateLine(_ status: PaymentStatus) -> String {
    let date = format.paymentDate(payment.nextDate, today: today)
    let rel = status == .paused ? "" : " · " + format.relative(payment.nextDate, today: today)
    return "\(date)\(rel) · \(format.periodName(payment.period)) · "
      + format.reminderName(payment.reminderDays).lowercased()
  }

  private func actions(_ status: PaymentStatus) -> some View {
    let paused = status == .paused
    let paidTitle = format.text("Оплачено", "Paid")
    return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
      Button(action: pay) {
        Text(unresolved ? format.text("Проверить оплату", "Check payment") : paidTitle)
          .paymentButtonText()
      }
      .buttonStyle(RitmPrimaryButtonStyle())
      .disabled(paused || working || !canWrite)
      .accessibilityLabel("\(paidTitle): \(payment.name)")
      Button(action: edit) { Text(format.text("Изменить", "Edit")).paymentButtonText() }
        .buttonStyle(RitmSecondaryButtonStyle())
        .accessibilityLabel("\(format.text("Изменить", "Edit")): \(payment.name)")
      Button(action: skip) { Text(format.text("Пропустить", "Skip")).paymentButtonText() }
        .buttonStyle(RitmSecondaryButtonStyle())
        .disabled(paused || working)
        .accessibilityLabel("\(format.text("Пропустить", "Skip")): \(payment.name)")
      Button(action: togglePause) {
        Text(paused ? format.text("Возобновить", "Resume") : format.text("Пауза", "Pause"))
          .paymentButtonText()
      }
      .buttonStyle(RitmSecondaryButtonStyle())
      .accessibilityLabel(
        "\(paused ? format.text("Возобновить", "Resume") : format.text("Поставить на паузу", "Pause")): \(payment.name)"
      )
      Button(role: .destructive, action: remove) {
        Text(format.text("Удалить", "Delete")).paymentButtonText()
      }
      .buttonStyle(PaymentDangerButtonStyle())
      .disabled(working)
      .accessibilityLabel("\(format.text("Удалить платёж", "Delete payment")): \(payment.name)")
    }
  }
}

extension Text {
  /// Long labels wrap instead of hiding, so Dynamic Type keeps every action readable.
  fileprivate func paymentButtonText() -> some View {
    lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
  }
}

private struct PaymentDangerButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmText(.button)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 44)
      .foregroundStyle(RitmTheme.danger)
      .ritmGlass(in: Capsule(), interactive: true)
      .opacity(isEnabled ? 1 : 0.5)
      .environment(\.ritmGlassPressed, configuration.isPressed)
  }
}
