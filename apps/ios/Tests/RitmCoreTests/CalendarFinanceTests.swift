import Foundation
import XCTest

@testable import RitmCore

final class CalendarFinanceTests: XCTestCase {
  func testMonthlyRecurrenceSkipsMissingDayButMonthNavigationClamps() {
    let task = RitmTask(id: "monthly", title: "Monthly", date: "2026-01-31", repeat: .monthly)
    XCTAssertFalse(TaskSchedule.occursOn(task, date: "2026-02-28"))
    XCTAssertTrue(TaskSchedule.occursOn(task, date: "2026-03-31"))
    XCTAssertEqual(TaskSchedule.addMonths(to: "2026-01-31", months: 1), "2026-02-28")
    XCTAssertEqual(TaskSchedule.monthDates(containing: "2028-02-20").count, 29)
  }

  func testRecurringCompletionAndOvernightContinuationUseOriginalDate() throws {
    let task = RitmTask(
      id: "night", title: "Night", date: "2026-10-27", time: "23:30", duration: 90,
      repeat: .daily, completedDates: ["2026-10-28"])
    let entries = TaskSchedule.dayOccurrences([task], date: "2026-10-29")
    let continuation = try XCTUnwrap(entries.first)
    XCTAssertEqual(continuation.key, "night:2026-10-28:continued")
    XCTAssertEqual(continuation.start, 0)
    XCTAssertEqual(continuation.end, 60)
    XCTAssertTrue(continuation.completed)
    XCTAssertEqual(entries.last?.start, 1410)
    XCTAssertEqual(entries.last?.completed, false)
  }

  func testWeeklyScheduleNeverCreatesAnOccurrenceBeforeStart() {
    let task = RitmTask(id: "weekly", title: "Weekly", date: "2026-10-28", repeat: .weekly)
    XCTAssertFalse(TaskSchedule.occursOn(task, date: "2026-10-21"))
    XCTAssertTrue(TaskSchedule.occursOn(task, date: "2026-11-04"))
    XCTAssertFalse(TaskSchedule.occursOn(task, date: "2026-11-05"))
    XCTAssertNil(TaskSchedule.timeMinutes("24:00"))
    XCTAssertEqual(TaskSchedule.minuteTime(-30), "23:30")
  }

  func testTransfersPreserveCombinedBalanceAndIgnoreOtherCurrenciesOrDates() {
    let entries = [
      FinanceEntry(
        id: "account", input: .init(type: .account, valueMinor: 10000, asOf: "2026-10-01")),
      FinanceEntry(
        id: "deposit",
        input: .init(type: .deposit, valueMinor: 20000, asOf: "2026-10-01", name: "Reserve")),
      FinanceEntry(
        id: "transfer",
        input: .init(
          type: .transfer, amountMinor: 2500, date: "2026-10-01", fromAccountId: "account",
          toAccountId: "deposit")),
      FinanceEntry(
        id: "expense",
        input: .init(type: .expense, amountMinor: 1000, date: "2026-10-29", category: "Food")),
      FinanceEntry(
        id: "income",
        input: .init(type: .income, amountMinor: 500, date: "2026-10-29", category: "Gift")),
      FinanceEntry(
        id: "usd",
        input: .init(
          type: .expense, currency: .USD, amountMinor: 999999, date: "2026-10-29",
          category: "Other currency")),
      FinanceEntry(
        id: "past",
        input: .init(
          type: .expense, amountMinor: 999999, date: "2026-09-30", category: "Before snapshot")),
      FinanceEntry(
        id: "future",
        input: .init(
          type: .transfer, amountMinor: 999999, date: "2026-10-30", fromAccountId: "account",
          toAccountId: "deposit")),
    ]
    XCTAssertEqual(
      FinanceLedger.accountBalance(entries: entries, currency: .KZT, today: "2026-10-29"), 7000)
    XCTAssertEqual(
      FinanceLedger.depositBalance(entries: entries, depositId: "deposit", today: "2026-10-29"),
      22500)
    XCTAssertNil(
      FinanceLedger.accountBalance(entries: entries, currency: .USD, today: "2026-10-29"))
    XCTAssertNil(
      FinanceLedger.depositBalance(entries: entries, depositId: "deposit", today: "2026-09-30"))
  }
}
