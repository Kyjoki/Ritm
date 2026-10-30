import XCTest

@testable import RitmCore

final class FinanceHistoryGroupingTests: XCTestCase {
  private let today = "2026-10-30"

  private func entry(
    _ id: String, _ type: FinanceEntryKind = .expense, date: String? = nil, asOf: String? = nil
  ) -> FinanceEntry {
    FinanceEntry(
      id: id,
      input: FinanceEntryInput(type: type, amountMinor: 1_000, date: date, asOf: asOf),
      createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
  }

  func testGroupsNewestDayFirstAndKeepsOrderInsideADay() {
    let entries = [
      entry("a", date: "2026-10-28"), entry("b", date: "2026-10-30"),
      entry("c", date: "2026-10-28"), entry("d", date: "2026-10-30"),
    ]
    let days = FinanceHistoryGrouping.group(entries, today: today, language: .ru)
    XCTAssertEqual(days.map(\.dateKey), ["2026-10-30", "2026-10-28"])
    XCTAssertEqual(days[0].entries.map(\.id), ["b", "d"])
    XCTAssertEqual(days[1].entries.map(\.id), ["a", "c"])
  }

  func testTodayAndYesterdayHaveRelativeLabels() {
    let entries = [entry("a", date: "2026-10-30"), entry("b", date: "2026-10-29")]
    let russian = FinanceHistoryGrouping.group(entries, today: today, language: .ru)
    XCTAssertEqual(russian.map(\.label), ["Сегодня", "Вчера"])
    XCTAssertEqual(russian.map(\.relative), ["Сегодня", "Вчера"])
    let english = FinanceHistoryGrouping.group(entries, today: today, language: .en)
    XCTAssertEqual(english.map(\.label), ["Today", "Yesterday"])
  }

  func testOlderDayShowsDayMonthAndWeekday() throws {
    let day = try XCTUnwrap(
      FinanceHistoryGrouping.group([entry("a", date: "2026-10-23")], today: today, language: .ru)
        .first)
    XCTAssertEqual(day.label, "23 окт, пт")
    XCTAssertEqual(day.dayNumber, "23")
    XCTAssertEqual(day.month, "окт")
    XCTAssertEqual(day.weekday, "пт")
    XCTAssertNil(day.relative)
  }

  func testEnglishLabelsAndSingleDigitDay() throws {
    let day = try XCTUnwrap(
      FinanceHistoryGrouping.group([entry("a", date: "2026-03-05")], today: today, language: .en)
        .first)
    XCTAssertEqual(day.label, "5 Mar, Thu")
  }

  func testYearAppearsOnlyWhenNotCurrent() throws {
    let day = try XCTUnwrap(
      FinanceHistoryGrouping.group([entry("a", date: "2025-12-31")], today: today, language: .ru)
        .first)
    XCTAssertEqual(day.label, "31 дек 2025, ср")
    XCTAssertEqual(day.month, "дек 2025")
  }

  func testYesterdayAcrossAMonthBoundary() {
    let days = FinanceHistoryGrouping.group(
      [entry("a", date: "2026-02-28")], today: "2026-03-01", language: .ru)
    XCTAssertEqual(days.first?.label, "Вчера")
  }

  func testEntriesWithoutDateUseTheirSnapshotDate() {
    let days = FinanceHistoryGrouping.group(
      [entry("s", .stock, asOf: "2026-10-30")], today: today, language: .ru)
    XCTAssertEqual(days.first?.dateKey, "2026-10-30")
  }

  func testUndatedOperationsGoLast() {
    let days = FinanceHistoryGrouping.group(
      [entry("x"), entry("a", date: "2026-10-01"), entry("y", date: "bad")], today: today,
      language: .ru)
    XCTAssertEqual(days.map(\.dateKey), ["2026-10-01", ""])
    XCTAssertEqual(days.last?.entries.map(\.id), ["x", "y"])
    XCTAssertEqual(days.last?.label, "Без даты")
  }

  func testEmptyInputGivesNoDays() {
    XCTAssertTrue(FinanceHistoryGrouping.group([], today: today, language: .ru).isEmpty)
  }

  func testFilterKeepsOnlyTheChosenType() {
    let entries = [
      entry("e", .expense, date: "2026-10-30"), entry("i", .income, date: "2026-10-30"),
      entry("t", .transfer, date: "2026-10-30"),
    ]
    XCTAssertEqual(FinanceHistoryFilter.all.apply(entries).map(\.id), ["e", "i", "t"])
    XCTAssertEqual(FinanceHistoryFilter.expense.apply(entries).map(\.id), ["e"])
    XCTAssertEqual(FinanceHistoryFilter.income.apply(entries).map(\.id), ["i"])
    XCTAssertEqual(FinanceHistoryFilter.transfer.apply(entries).map(\.id), ["t"])
  }
}
