import Foundation
import XCTest

@testable import RitmCore

final class RecurringPaymentsTests: XCTestCase {
  private func payment(
    _ id: String = "p1", amount: Int = 100_000, currency: FinanceCurrency = .KZT,
    next: String = "2026-11-10", period: PaymentPeriod = .month, paused: Bool = false
  ) -> RecurringPayment {
    RecurringPayment(
      id: id, name: "Интернет", amountMinor: amount, accountID: "acc-\(currency.rawValue)",
      currency: currency, category: "Связь", nextDate: next, period: period, paused: paused)
  }

  private func series(_ start: String, _ period: PaymentPeriod, _ count: Int) -> [String] {
    var item = payment(next: start, period: period)
    var result = [start]
    for _ in 0..<count {
      item.nextDate = item.followingDate ?? "?"
      result.append(item.nextDate)
    }
    return result
  }

  // MARK: Dates

  func testMonthEndReturnsToTheAnchorDay() {
    XCTAssertEqual(
      series("2026-01-31", .month, 4), ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"])
    XCTAssertEqual(series("2028-01-31", .month, 2), ["2028-01-31", "2028-02-29", "2028-03-31"])
    XCTAssertEqual(series("2026-12-15", .month, 1), ["2026-12-15", "2027-01-15"])
  }

  func testLeapYearYearlyPayment() {
    XCTAssertEqual(
      series("2028-02-29", .year, 4),
      ["2028-02-29", "2029-02-28", "2030-02-28", "2031-02-28", "2032-02-29"])
    XCTAssertEqual(series("2026-03-10", .year, 1), ["2026-03-10", "2027-03-10"])
  }

  func testWeeklyAddsSevenDaysAcrossMonthsAndYears() {
    XCTAssertEqual(series("2026-12-28", .week, 2), ["2026-12-28", "2027-01-04", "2027-01-11"])
    XCTAssertEqual(series("2028-02-24", .week, 1), ["2028-02-24", "2028-03-02"])
  }

  func testDateArithmeticIsStrictAndCivil() {
    XCTAssertNil(PaymentDates.parse("2026-02-30"))
    XCTAssertNil(PaymentDates.parse("2026-2-3"))
    XCTAssertNil(PaymentDates.parse("1999-01-01"))
    XCTAssertEqual(PaymentDates.adding(days: 1, to: "2026-03-28"), "2026-03-29")
    XCTAssertEqual(PaymentDates.adding(days: -7, to: "2026-03-03"), "2026-02-24")
    XCTAssertEqual(PaymentDates.daysBetween("2026-03-28", "2026-03-30"), 2)
    XCTAssertEqual(PaymentDates.daysBetween("2028-02-28", "2028-03-01"), 2)
  }

  // MARK: Status and summary

  func testStatusAndSoonWindowIncludeOverdue() {
    let today = "2026-11-10"
    XCTAssertEqual(payment(next: "2026-11-08").status(today: today), .overdue)
    XCTAssertEqual(payment(next: today).status(today: today), .today)
    XCTAssertEqual(payment(next: "2026-11-11").status(today: today), .planned)
    XCTAssertEqual(payment(next: "2026-11-08", paused: true).status(today: today), .paused)
    XCTAssertTrue(payment(next: "2026-11-08").isUpcoming(today: today))
    XCTAssertTrue(payment(next: "2026-11-17").isUpcoming(today: today))
    XCTAssertFalse(payment(next: "2026-11-18").isUpcoming(today: today))
    XCTAssertFalse(payment(next: "2026-11-08", paused: true).isUpcoming(today: today))
  }

  func testUpcomingSumsPerCurrencyNeverTogether() {
    let book = PaymentBook(payments: [
      payment("a", amount: 100, next: "2026-11-09"),
      payment("b", amount: 250, next: "2026-11-12"),
      payment("c", amount: 999, currency: .USD, next: "2026-11-10"),
      payment("d", amount: 5, next: "2026-12-30"),
      payment("e", amount: 7, next: "2026-11-11", paused: true),
    ])
    let summary = book.upcoming(today: "2026-11-10")
    XCTAssertEqual(summary.count, 3)
    XCTAssertTrue(summary.hasOverdue)
    XCTAssertEqual(
      summary.totals,
      [FinanceTotal(currency: .KZT, amountMinor: 350), FinanceTotal(currency: .USD, amountMinor: 999)])
    XCTAssertEqual(PaymentBook().upcoming(today: "2026-11-10").count, 0)
  }

  func testSortingPutsOverdueFirstAndPausedLast() {
    let book = PaymentBook(payments: [
      payment("paused", next: "2026-11-01", paused: true), payment("later", next: "2026-11-20"),
      payment("over", next: "2026-11-05"), payment("today", next: "2026-11-10"),
    ])
    XCTAssertEqual(book.sorted(today: "2026-11-10").map(\.id), ["over", "today", "later", "paused"])
  }

  // MARK: Paying

  func testNothingIsCreatedByADueDateAlone() {
    let book = PaymentBook(payments: [payment(next: "2026-11-01")])
    XCTAssertEqual(book.occurrences, [])
    XCTAssertEqual(book.payments[0].nextDate, "2026-11-01")
  }

  func testPaymentWritesExactlyOneExpenseAndAdvancesOnlyAfterConfirmation() throws {
    let book = PaymentBook(payments: [payment(next: "2026-11-10")])
    let started = try book.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").get()
    let input = started.charge.input
    XCTAssertEqual(input.type, .expense)
    XCTAssertEqual(input.amountMinor, 100_000)
    XCTAssertEqual(input.date, "2026-11-10")
    XCTAssertEqual(input.category, "Связь")
    XCTAssertEqual(input.currency, .KZT)
    XCTAssertEqual(input.note, "Регулярный платёж · Интернет · 2026-11-10")
    XCTAssertEqual(started.book.payments[0].nextDate, "2026-11-10", "not moved before confirmation")
    let paid = started.book.confirmingPayment("p1", planned: "2026-11-10", entryID: "e1")
    XCTAssertEqual(paid.payments[0].nextDate, "2026-12-10")
    XCTAssertEqual(paid.occurrence("p1", planned: "2026-11-10")?.state, .paid)
    XCTAssertEqual(paid.occurrence("p1", planned: "2026-11-10")?.entryID, "e1")
  }

  func testDoublePayIsRefusedBeforeAndAfterConfirmation() throws {
    let book = PaymentBook(payments: [payment(next: "2026-11-10")])
    let started = try book.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").get()
    // Second tap while the write is in flight or its answer was lost.
    XCTAssertEqual(
      started.book.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").failureValue,
      .occurrenceRecorded)
    let paid = started.book.confirmingPayment("p1", planned: "2026-11-10", entryID: "e1")
    // A stale dialog for the old date.
    XCTAssertEqual(
      paid.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").failureValue,
      .staleOccurrence)
    // Confirming twice does not move the date twice.
    XCTAssertEqual(paid.confirmingPayment("p1", planned: "2026-11-10", entryID: "e2"), paid)
  }

  func testEarlyPaymentIsBookedTodayForTheStatedPlannedDate() throws {
    let book = PaymentBook(payments: [payment(next: "2026-11-20")])
    let started = try book.beginningPayment("p1", planned: "2026-11-20", today: "2026-11-10").get()
    XCTAssertEqual(started.charge.input.date, "2026-11-10")
    XCTAssertEqual(started.charge.planned, "2026-11-20")
    XCTAssertEqual(
      started.book.confirmingPayment("p1", planned: "2026-11-20", entryID: "e").payments[0].nextDate,
      "2026-12-20")
    XCTAssertEqual(
      book.beginningPayment("p1", planned: "2026-11-25", today: "2026-11-10").failureValue,
      .staleOccurrence)
  }

  func testOverdueIsNeverPaidByItselfAndEachMissedOccurrenceIsSeparate() throws {
    var book = PaymentBook(payments: [payment(next: "2026-09-10")])
    XCTAssertEqual(book.payments[0].status(today: "2026-11-10"), .overdue)
    XCTAssertTrue(book.occurrences.isEmpty)
    for planned in ["2026-09-10", "2026-10-10"] {
      let started = try book.beginningPayment("p1", planned: planned, today: "2026-11-10").get()
      book = started.book.confirmingPayment("p1", planned: planned, entryID: planned)
    }
    XCTAssertEqual(book.payments[0].nextDate, "2026-11-10")
    XCTAssertEqual(book.occurrences.count, 2)
  }

  func testReleaseAfterADefiniteFailureAllowsRetry() throws {
    let book = PaymentBook(payments: [payment()])
    let started = try book.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").get()
    let released = started.book.releasingPayment("p1", planned: "2026-11-10")
    XCTAssertEqual(released, book)
    XCTAssertNoThrow(try released.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").get())
  }

  func testLostResponseIsReconciledWithoutASecondExpense() throws {
    let book = PaymentBook(payments: [payment()])
    let started = try book.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").get()
    XCTAssertTrue(started.book.hasUnresolvedAttempt("p1"))
    // The history does not contain it yet: nothing changes.
    XCTAssertEqual(started.book.reconciling(with: []), started.book)
    let entry = FinanceEntry(
      id: "srv-1", input: started.charge.input, createdAt: "t", updatedAt: "t")
    let fixed = started.book.reconciling(with: [entry])
    XCTAssertFalse(fixed.hasUnresolvedAttempt("p1"))
    XCTAssertEqual(fixed.payments[0].nextDate, "2026-12-10")
    XCTAssertEqual(fixed.occurrence("p1", planned: "2026-11-10")?.entryID, "srv-1")
    // The same entry never satisfies two occurrences.
    XCTAssertEqual(fixed.reconciling(with: [entry]), fixed)
  }

  // MARK: Skip, pause, delete, edit

  func testSkipMovesTheDateWithoutAnExpenseAndCannotRepeat() throws {
    let book = PaymentBook(payments: [payment(next: "2026-01-31")])
    let skipped = try book.skipping("p1", planned: "2026-01-31").get()
    XCTAssertEqual(skipped.payments[0].nextDate, "2026-02-28")
    XCTAssertEqual(skipped.occurrence("p1", planned: "2026-01-31")?.state, .skipped)
    XCTAssertEqual(skipped.skipping("p1", planned: "2026-01-31").failureValue, .staleOccurrence)
    XCTAssertEqual(try skipped.skipping("p1", planned: "2026-02-28").get().payments[0].nextDate, "2026-03-31")
  }

  func testPausedPaymentLeavesUpcomingKeepsHistoryAndCannotBePaidOrSkipped() throws {
    var book = PaymentBook(payments: [payment(next: "2026-11-10")])
    let started = try book.beginningPayment("p1", planned: "2026-11-10", today: "2026-11-10").get()
    book = started.book.confirmingPayment("p1", planned: "2026-11-10", entryID: "e")
    book = book.togglingPause("p1")
    XCTAssertEqual(book.upcoming(today: "2026-12-10").count, 0)
    XCTAssertEqual(book.occurrences.count, 1)
    XCTAssertEqual(book.beginningPayment("p1", planned: "2026-12-10", today: "2026-12-10").failureValue, .paused)
    XCTAssertEqual(book.skipping("p1", planned: "2026-12-10").failureValue, .paused)
    XCTAssertEqual(book.togglingPause("p1").payments[0].paused, false)
  }

  func testDeletingRemovesTheScheduleAndItsLedgerOnly() {
    let book = PaymentBook(
      payments: [payment("a"), payment("b")],
      occurrences: [
        PaymentOccurrence(paymentID: "a", planned: "2026-10-10", state: .paid, entryID: "x"),
        PaymentOccurrence(paymentID: "b", planned: "2026-10-10", state: .paid, entryID: "y"),
      ])
    let after = book.deleting("a")
    XCTAssertEqual(after.payments.map(\.id), ["b"])
    XCTAssertEqual(after.occurrences.map(\.paymentID), ["b"])
  }

  func testEditKeepsAnchorWhenDateIsSameAndRefusesRecordedDate() throws {
    let book = PaymentBook(payments: [payment(next: "2026-02-28", period: .month)])
    var original = book.payments[0]
    original.anchorDay = 31  // anchor from an earlier 31st
    let seeded = PaymentBook(payments: [original])
    var edit = original
    edit.name = "Интернет Плюс"
    XCTAssertEqual(try seeded.updating(edit).get().payments[0].anchorDay, 31)
    edit.nextDate = "2026-03-15"
    XCTAssertEqual(try seeded.updating(edit).get().payments[0].anchorDay, 15)
    let withLedger = PaymentBook(
      payments: [original],
      occurrences: [PaymentOccurrence(paymentID: "p1", planned: "2026-01-28", state: .paid)])
    edit.nextDate = "2026-01-28"
    XCTAssertEqual(withLedger.updating(edit).failureValue, .occurrenceRecorded)
    edit.nextDate = "2026-02-30"
    XCTAssertEqual(seeded.updating(edit).failureValue, .invalid)
  }

  // MARK: Form validation and storage

  func testAmountParsing() {
    XCTAssertEqual(PaymentValidation.amountMinor("1500"), 150_000)
    XCTAssertEqual(PaymentValidation.amountMinor("12,5"), 1_250)
    XCTAssertEqual(PaymentValidation.amountMinor("12.05"), 1_205)
    XCTAssertEqual(PaymentValidation.amountMinor(" 1 200,00 "), 120_000)
    for bad in ["", "0", "0,00", "-5", "1.234", "1,2,3", "abc", ",5", "5.", "1e3", "9999999999999"] {
      XCTAssertNil(PaymentValidation.amountMinor(bad), bad)
    }
    XCTAssertNil(PaymentValidation.cleanName("   "))
    XCTAssertEqual(PaymentValidation.cleanName(" Аренда "), "Аренда")
    XCTAssertNil(PaymentValidation.cleanName(String(repeating: "я", count: 41)))
  }

  func testFileRoundTripAndToleranceToDamage() throws {
    let book = PaymentBook(
      payments: [payment("a"), payment("b", currency: .USD)],
      occurrences: [PaymentOccurrence(paymentID: "a", planned: "2026-10-10", state: .skipped)])
    XCTAssertEqual(PaymentBookFile.decode(try PaymentBookFile.encode(book)), book)
    XCTAssertEqual(PaymentBookFile.decode(Data("not json".utf8)), PaymentBook())
    let damaged = """
      {"version":9,"future":1,"book":{"payments":[
        {"id":"ok","name":"Газ","amountMinor":500,"accountID":"a","currency":"KZT","nextDate":"2026-11-10","extra":true},
        {"id":"bad-date","name":"X","amountMinor":500,"accountID":"a","currency":"KZT","nextDate":"2026-13-40"},
        {"id":"broken"},
        {"id":"zero","name":"Z","amountMinor":0,"accountID":"a","currency":"KZT","nextDate":"2026-11-10"}
      ],"occurrences":[{"nope":1},{"paymentID":"ok","planned":"2026-10-10","state":"paid","note":"","amountMinor":0,"bookedOn":""}]}}
      """
    let loaded = PaymentBookFile.decode(Data(damaged.utf8))
    XCTAssertEqual(loaded.payments.map(\.id), ["ok"])
    XCTAssertEqual(loaded.payments[0].period, .month)
    XCTAssertEqual(loaded.payments[0].reminderDays, 1)
    XCTAssertEqual(loaded.payments[0].anchorDay, 10)
    XCTAssertEqual(loaded.occurrences.count, 1)
  }
}

extension Result {
  fileprivate var failureValue: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }
}
