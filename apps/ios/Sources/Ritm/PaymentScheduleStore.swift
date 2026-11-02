import Foundation
import Observation
import RitmCore

/// The recurring payments («Обязательные платежи») and their paid-occurrence ledger, kept on this
/// iPhone only: a versioned JSON file in Application Support, written atomically. The server has
/// no such model and none of this is ever sent to the assistant or to any AI request.
///
/// The schedules reference account ids that belong to one server, so they are cleared on sign-out
/// and on a server switch, like the other finance caches (see `RitmStore.signOut` and
/// `changeServer`). An expired session does not clear them: the same account signs in again.
@MainActor @Observable
final class PaymentScheduleStore {
  private(set) var book: PaymentBook
  @ObservationIgnored private let url: URL?

  init(directory: URL? = PaymentScheduleStore.defaultDirectory()) {
    url = directory?.appendingPathComponent("payment-schedules.json")
    if let url, let data = try? Data(contentsOf: url) {
      book = PaymentBookFile.decode(data)
    } else {
      book = PaymentBook()
    }
  }

  var payments: [RecurringPayment] { book.payments }

  /// Applies a pure change and saves it. Returns the error of a refused change.
  @discardableResult
  func apply(_ change: (PaymentBook) -> Result<PaymentBook, PaymentError>) -> PaymentError? {
    switch change(book) {
    case .success(let next):
      set(next)
      return nil
    case .failure(let error):
      return error
    }
  }

  func apply(_ change: (PaymentBook) -> PaymentBook) { set(change(book)) }

  /// Forgets everything and removes the file (sign-out, server switch).
  func reset() {
    book = PaymentBook()
    if let url { try? FileManager.default.removeItem(at: url) }
  }

  private func set(_ next: PaymentBook) {
    guard next != book else { return }
    book = next
    save()
  }

  private func save() {
    guard let url, let data = try? PaymentBookFile.encode(book) else { return }
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
  }

  private static func defaultDirectory() -> URL? {
    guard
      let base = try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else { return nil }
    let folder = base.appendingPathComponent("Ritm", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}

// MARK: - Paying

enum RecurringPaymentOutcome: Equatable {
  /// Exactly one expense was recorded and the date moved on.
  case paid
  /// The answer was lost. The occurrence stays locked until the history shows the expense.
  case unknown
  /// Nothing was written and the occurrence can be paid again.
  case failed
  /// Refused before writing (paused, already paid, wrong date, no account of that currency).
  case refused(PaymentError?)
}

extension RitmStore {
  /// Step 1 records the attempt in the ledger, step 2 writes ONE expense through the normal
  /// create path, step 3 confirms and moves the date. A reload (inside `write`) updates the
  /// balances and analytics. A lost answer is never retried here.
  func payRecurring(id: String, planned: String) async -> RecurringPaymentOutcome {
    guard financeLoaded, canWrite, let payment = payments.book.payment(id) else {
      return .refused(nil)
    }
    guard
      financeEntries.contains(where: { $0.type == .account && $0.currency == payment.currency })
    else { return .refused(nil) }
    var charge: PaymentCharge?
    let refusal = payments.apply { book -> Result<PaymentBook, PaymentError> in
      switch book.beginningPayment(id, planned: planned, today: today) {
      case .success(let started):
        charge = started.charge
        return .success(started.book)
      case .failure(let error):
        return .failure(error)
      }
    }
    if let refusal { return .refused(refusal) }
    guard let charge else { return .refused(nil) }
    let input = charge.input
    let created = await write { try await $0.createFinanceEntry(input) }
    if let created {
      payments.apply { $0.confirmingPayment(id, planned: planned, entryID: created.id) }
      toasts.show(text("Оплачено · расход записан", "Paid · expense recorded"))
      return .paid
    }
    if uncertainWrite { return .unknown }
    payments.apply { $0.releasingPayment(id, planned: planned) }
    return .failed
  }

  /// Recognises an expense whose answer was lost (see `PaymentBook.reconciling`).
  func reconcileRecurringPayments() {
    guard financeLoaded else { return }
    let entries = financeEntries
    payments.apply { $0.reconciling(with: entries) }
  }

  /// The owner has looked at the history and the expense is not there: allow paying again.
  func releaseRecurringAttempt(id: String) {
    guard let payment = payments.book.payment(id) else { return }
    payments.apply { $0.releasingPayment(id, planned: payment.nextDate) }
  }
}
