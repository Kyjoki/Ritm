import Foundation
import XCTest

@testable import RitmCore

final class FinanceWalletTests: XCTestCase {
  private let today = "2026-10-29"  // Thursday

  private func snapshot(
    _ id: String, _ type: FinanceEntryKind, _ value: Int, asOf: String,
    currency: FinanceCurrency = .KZT, name: String? = nil, created: String
  ) -> FinanceEntry {
    FinanceEntry(
      id: id,
      input: .init(type: type, currency: currency, valueMinor: value, asOf: asOf, name: name),
      createdAt: created, updatedAt: created)
  }

  private func operation(
    _ id: String, _ type: FinanceEntryKind, _ amount: Int, _ date: String, category: String,
    note: String = "", currency: FinanceCurrency = .KZT, created: String
  ) -> FinanceEntry {
    FinanceEntry(
      id: id,
      input: .init(
        type: type, currency: currency, note: note, amountMinor: amount, date: date,
        category: category),
      createdAt: created, updatedAt: created)
  }

  private func transfer(
    _ id: String, from: String, to: String, _ amount: Int, _ date: String, note: String = "",
    created: String
  ) -> FinanceEntry {
    FinanceEntry(
      id: id,
      input: .init(
        type: .transfer, note: note, amountMinor: amount, date: date, fromAccountId: from,
        toAccountId: to),
      createdAt: created, updatedAt: created)
  }

  /// KZT account 10 000.00 from 1 Sep; deposits Reserve (created later) and Travel; one stock;
  /// a USD account, a USD deposit that has not started and a EUR deposit without an account.
  /// The array order is deliberately not the card order.
  private var entries: [FinanceEntry] {
    [
      snapshot("eur-dep", .deposit, 40_000, asOf: "2026-10-01", currency: .EUR, name: "Euro", created: "2026-10-01T09:00:00Z"),
      snapshot("dep-a", .deposit, 500_000, asOf: "2026-09-01", name: "Reserve", created: "2026-09-02T08:00:00Z"),
      snapshot("usd-main", .account, 100_000, asOf: "2026-10-01", currency: .USD, created: "2026-10-01T08:00:00Z"),
      snapshot("kzt-main", .account, 1_000_000, asOf: "2026-09-01", created: "2026-09-01T08:00:00Z"),
      snapshot("dep-b", .deposit, 200_000, asOf: "2026-09-01", name: "Travel", created: "2026-09-01T09:00:00Z"),
      snapshot("usd-future", .deposit, 90_000, asOf: "2026-11-15", currency: .USD, name: "Later", created: "2026-10-02T08:00:00Z"),
      FinanceEntry(
        id: "stock-1",
        input: .init(
          type: .stock, valueMinor: 300_000, asOf: "2026-09-15", name: "Alpha", exchange: "KASE",
          ticker: "AAA", quantity: 10, unitPriceMinor: 30_000, purchasePriceMinor: 25_000),
        createdAt: "2026-09-15T08:00:00Z", updatedAt: "2026-09-15T08:00:00Z"),
      operation("exp-pre", .expense, 99_999, "2026-08-31", category: "Before snapshot", created: "2026-09-02T12:00:00Z"),
      operation("exp-sep", .expense, 15_000, "2026-09-20", category: "Rent", created: "2026-09-20T12:00:00Z"),
      operation("exp-taxi", .expense, 10_000, "2026-10-25", category: "Taxi", created: "2026-10-25T12:00:00Z"),
      operation("exp-food", .expense, 30_000, "2026-10-26", category: "Food", created: "2026-10-26T12:00:00Z"),
      operation("inc-1", .income, 400_000, "2026-10-27", category: "Salary", created: "2026-10-27T12:00:00Z"),
      operation("usd-exp", .expense, 5_000, "2026-10-27", category: "Food", currency: .USD, created: "2026-10-27T13:00:00Z"),
      operation("eur-exp", .expense, 1_000, "2026-10-28", category: "Coffee", currency: .EUR, created: "2026-10-28T09:00:00Z"),
      operation("exp-food2", .expense, 20_000, "2026-10-28", category: " Food ", created: "2026-10-28T12:00:00Z"),
      transfer("tr-1", from: "kzt-main", to: "dep-a", 100_000, "2026-10-28", created: "2026-10-28T15:00:00Z"),
      transfer("tr-2", from: "dep-a", to: "kzt-main", 25_000, "2026-10-29", note: " Back to main ", created: "2026-10-29T08:00:00Z"),
      operation("exp-future", .expense, 7_000, "2026-10-30", category: "Gifts", created: "2026-10-29T09:00:00Z"),
    ]
  }

  private var cards: [FinanceCard] { FinanceWallet.cards(entries, today: today) }
  private func card(_ id: String) throws -> FinanceCard {
    try XCTUnwrap(cards.first { $0.id == id })
  }

  func testCardsFollowCurrencyOrderThenAccountDepositsAndStocks() throws {
    XCTAssertEqual(
      cards.map(\.id),
      ["kzt-main", "dep-b", "dep-a", "stocks-KZT", "usd-main", "usd-future", "eur-dep"])
    XCTAssertEqual(cards.map(\.kind), [.account, .deposit, .deposit, .stocks, .account, .deposit, .deposit])
    XCTAssertEqual(try card("dep-a").name, "Reserve")
    XCTAssertNil(try card("kzt-main").name)
    XCTAssertEqual(try card("kzt-main").balanceMinor, 1_250_000)
    XCTAssertEqual(try card("dep-a").balanceMinor, 575_000)
    XCTAssertEqual(try card("dep-b").balanceMinor, 200_000)
    XCTAssertEqual(try card("stocks-KZT").balanceMinor, 300_000)
    XCTAssertEqual(try card("stocks-KZT").asOf, "2026-09-15")
    XCTAssertEqual(try card("usd-main").balanceMinor, 95_000)
    XCTAssertNil(try card("usd-future").balanceMinor, "not started yet")
    XCTAssertTrue(FinanceWallet.cards([], today: today).isEmpty)
  }

  func testTotalsNeverMixCurrencies() {
    XCTAssertEqual(
      FinanceWallet.totals(cards),
      [
        FinanceTotal(currency: .KZT, amountMinor: 2_325_000),
        FinanceTotal(currency: .USD, amountMinor: 95_000),
        FinanceTotal(currency: .EUR, amountMinor: 40_000),
      ])
    let notStarted = FinanceCard(id: "d", kind: .deposit, currency: .RUB)
    XCTAssertEqual(FinanceWallet.totals([notStarted]), [FinanceTotal(currency: .RUB, amountMinor: 0)])
    XCTAssertTrue(FinanceWallet.totals([]).isEmpty)
  }

  func testTransfersAreNeitherIncomeNorExpense() throws {
    let main = try card("kzt-main")
    let month = FinanceWallet.stats(entries, card: main, period: .month, today: today)
    XCTAssertEqual(month.incomeMinor, 400_000)
    XCTAssertEqual(month.expenseMinor, 60_000)
    XCTAssertEqual(month.transfersInMinor, 25_000)
    XCTAssertEqual(month.transfersOutMinor, 100_000)
    XCTAssertEqual(month.netMinor, 265_000)
    // Monday 26th: the Sunday taxi ride and the future gift are outside the week.
    let week = FinanceWallet.stats(entries, card: main, period: .week, today: today)
    XCTAssertEqual(week.expenseMinor, 50_000)
    let overview = FinanceWallet.overviewStats(entries, currency: .KZT, period: .month, today: today)
    XCTAssertEqual(overview, FinancePeriodStats(incomeMinor: 400_000, expenseMinor: 60_000))
    XCTAssertEqual(
      FinanceWallet.overviewStats(entries, currency: .USD, period: .month, today: today).expenseMinor,
      5_000)
  }

  func testDepositsIgnoreIncomeAndExpenseAndStocksAreEmpty() throws {
    let reserve = FinanceWallet.stats(entries, card: try card("dep-a"), period: .month, today: today)
    XCTAssertEqual(
      reserve,
      FinancePeriodStats(transfersInMinor: 100_000, transfersOutMinor: 25_000))
    XCTAssertEqual(reserve.netMinor, 75_000)
    XCTAssertEqual(
      FinanceWallet.stats(entries, card: try card("dep-b"), period: .year, today: today), .zero)
    XCTAssertEqual(
      FinanceWallet.stats(entries, card: try card("stocks-KZT"), period: .year, today: today), .zero)
  }

  func testStatsStartAtTheSnapshotAndSkipCardsThatHaveNotStarted() throws {
    // The September rent counts for the year only; the August expense predates the snapshot.
    let year = FinanceWallet.stats(entries, card: try card("kzt-main"), period: .year, today: today)
    XCTAssertEqual(year.expenseMinor, 75_000)
    XCTAssertEqual(
      FinanceWallet.stats(entries, card: try card("usd-future"), period: .month, today: today), .zero)
  }

  func testIntervalEdges() {
    func range(_ period: FinancePeriod, _ day: String) -> [String] {
      let value = FinanceWallet.interval(period, today: day)
      return [value.start, value.end]
    }
    XCTAssertEqual(range(.week, "2026-10-26"), ["2026-10-26", "2026-10-26"], "Monday")
    XCTAssertEqual(range(.week, "2026-10-29"), ["2026-10-26", "2026-10-29"])
    XCTAssertEqual(range(.week, "2026-11-01"), ["2026-10-26", "2026-11-01"], "Sunday")
    XCTAssertEqual(range(.month, "2026-11-01"), ["2026-11-01", "2026-11-01"], "the 1st")
    XCTAssertEqual(range(.year, "2026-11-01"), ["2026-01-01", "2026-11-01"])
    XCTAssertEqual(range(.week, "2027-01-01"), ["2026-12-28", "2027-01-01"], "Jan 1 on a Friday")
    XCTAssertEqual(range(.month, "2027-01-01"), ["2027-01-01", "2027-01-01"])
    XCTAssertEqual(range(.year, "2027-01-01"), ["2027-01-01", "2027-01-01"])
    XCTAssertEqual(range(.week, "bad"), ["bad", "bad"])
  }

  func testWeekSeriesStartsTheDayBeforeAndEndsTodayAtTheCardBalance() throws {
    let main = try card("kzt-main")
    let series = FinanceWallet.balanceSeries(entries, card: main, period: .week, today: today)
    XCTAssertEqual(
      series,
      [
        FinancePoint(date: "2026-10-25", valueMinor: 975_000),
        FinancePoint(date: "2026-10-26", valueMinor: 945_000),
        FinancePoint(date: "2026-10-27", valueMinor: 1_345_000),
        FinancePoint(date: "2026-10-28", valueMinor: 1_225_000),
        FinancePoint(date: "2026-10-29", valueMinor: 1_250_000),
      ])
    XCTAssertEqual(series.last?.valueMinor, main.balanceMinor)
    XCTAssertTrue(
      FinanceWallet.balanceSeries(entries, card: try card("usd-future"), period: .week, today: today)
        .isEmpty)
  }

  func testMonthSeriesAndSeriesOnIntervalEdges() throws {
    let main = try card("kzt-main")
    let month = FinanceWallet.balanceSeries(entries, card: main, period: .month, today: today)
    XCTAssertEqual(month.count, 30)
    XCTAssertEqual(month.first, FinancePoint(date: "2026-09-30", valueMinor: 985_000))
    XCTAssertEqual(month.last?.date, today)

    func dates(_ period: FinancePeriod, _ day: String) -> [String] {
      let dayCard = FinanceWallet.cards(entries, today: day).first { $0.id == "kzt-main" }!
      return FinanceWallet.balanceSeries(entries, card: dayCard, period: period, today: day).map(\.date)
    }
    XCTAssertEqual(dates(.week, "2026-10-26"), ["2026-10-25", "2026-10-26"])
    XCTAssertEqual(dates(.month, "2026-10-01"), ["2026-09-30", "2026-10-01"])
    XCTAssertEqual(dates(.year, "2027-01-01"), ["2026-12-31", "2027-01-01"])
  }

  func testYearSeriesUsesMonthEndsThenToday() throws {
    let series = FinanceWallet.balanceSeries(
      entries, card: try card("kzt-main"), period: .year, today: today)
    // Nothing before the 1 Sep snapshot: the series starts on that day, then month ends.
    XCTAssertEqual(series.map(\.date), ["2026-09-01", "2026-09-30", "2026-10-29"])
    XCTAssertEqual(series.map(\.valueMinor), [1_000_000, 985_000, 1_250_000])
    XCTAssertEqual(series.map(\.date), ["2026-09-01", "2026-09-30", "2026-10-29"])
    XCTAssertEqual(series.map(\.valueMinor), [1_000_000, 985_000, 1_250_000])
    let older = snapshot("old", .account, 50_000, asOf: "2025-06-10", created: "c")
    let wide = FinanceWallet.cards([older], today: today)[0]
    let wideDates = FinanceWallet.balanceSeries([older], card: wide, period: .year, today: today)
      .map(\.date)
    XCTAssertEqual(
      wideDates,
      [
        "2025-12-31", "2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31",
        "2026-06-30", "2026-07-31", "2026-08-31", "2026-09-30", "2026-10-29",
      ])
  }

  func testSeriesStartAtTheSnapshotInsideTheInterval() throws {
    let account = snapshot("a", .account, 80_000, asOf: "2026-10-27", created: "c0")
    let spend = operation("e", .expense, 5_000, "2026-10-28", category: "Food", created: "c1")
    let all = [account, spend]
    let main = try XCTUnwrap(FinanceWallet.cards(all, today: today).first)
    XCTAssertEqual(
      FinanceWallet.balanceSeries(all, card: main, period: .week, today: today),
      [
        FinancePoint(date: "2026-10-27", valueMinor: 80_000),
        FinancePoint(date: "2026-10-28", valueMinor: 75_000),
        FinancePoint(date: "2026-10-29", valueMinor: 75_000),
      ])
    XCTAssertEqual(
      FinanceWallet.overviewSeries(all, currency: .KZT, period: .week, today: today).map(\.date),
      ["2026-10-27", "2026-10-28", "2026-10-29"])
    let snapshotToday = snapshot("t", .account, 10, asOf: today, created: "c")
    let card = FinanceWallet.cards([snapshotToday], today: today)[0]
    XCTAssertEqual(
      FinanceWallet.balanceSeries([snapshotToday], card: card, period: .month, today: today)
        .map(\.date),
      [today])
  }

  func testOverviewStatsStartAtTheAccountSnapshot() {
    let account = snapshot("a", .account, 80_000, asOf: "2026-10-10", created: "c0")
    let before = operation("b", .income, 9_000, "2026-10-05", category: "Old", created: "c1")
    let after = operation("c", .expense, 3_000, "2026-10-12", category: "Food", created: "c2")
    XCTAssertEqual(
      FinanceWallet.overviewStats(
        [account, before, after], currency: .KZT, period: .month, today: today),
      FinancePeriodStats(expenseMinor: 3_000))
    XCTAssertEqual(
      FinanceWallet.overviewStats([before, after], currency: .KZT, period: .month, today: today),
      .zero, "no account in this currency")
    let later = snapshot("l", .account, 1, asOf: "2026-11-01", created: "c3")
    XCTAssertEqual(
      FinanceWallet.overviewStats([later, after], currency: .KZT, period: .month, today: today),
      .zero, "account not started")
  }

  func testOverviewSeriesSumsOneCurrencyOnly() {
    let kzt = FinanceWallet.overviewSeries(entries, currency: .KZT, period: .week, today: today)
    XCTAssertEqual(
      kzt.map(\.valueMinor), [1_975_000, 1_945_000, 2_345_000, 2_325_000, 2_325_000])
    XCTAssertEqual(kzt.first?.date, "2026-10-25")
    XCTAssertEqual(kzt.last?.date, today)
    XCTAssertEqual(
      FinanceWallet.overviewSeries(entries, currency: .USD, period: .week, today: today).last?
        .valueMinor, 95_000)
    XCTAssertTrue(
      FinanceWallet.overviewSeries(entries, currency: .RUB, period: .week, today: today).isEmpty)
  }

  func testCategoriesKeepTopAndFoldTheRest() throws {
    let account = snapshot("a", .account, 1_000_000, asOf: "2026-10-01", created: "c0")
    let expenses = [
      operation("1", .expense, 30_000, "2026-10-05", category: "Food", created: "c1"),
      operation("2", .expense, 20_000, "2026-10-06", category: " Food ", created: "c2"),
      operation("3", .expense, 120_000, "2026-10-07", category: "Rent", created: "c3"),
      operation("4", .expense, 10_000, "2026-10-08", category: "Taxi", created: "c4"),
      operation("5", .expense, 15_000, "2026-10-09", category: "Fun", created: "c5"),
      operation("6", .expense, 5_000, "2026-10-10", category: "Gym", created: "c6"),
      operation("7", .expense, 2_000, "2026-10-11", category: "Books", created: "c7"),
      operation("8", .expense, 9_999, "2026-10-12", category: "Dollars", currency: .USD, created: "c8"),
      operation("9", .income, 9_999, "2026-10-12", category: "Gift", created: "c9"),
    ]
    let all = [account] + expenses
    let main = try XCTUnwrap(FinanceWallet.cards(all, today: today).first)
    let top = FinanceWallet.categories(all, card: main, period: .month, today: today)
    XCTAssertEqual(top.map(\.name), ["Rent", "Food", "Fun", "Taxi", nil])
    XCTAssertEqual(top.map(\.amountMinor), [120_000, 50_000, 15_000, 10_000, 7_000])
    XCTAssertEqual(top.reduce(0) { $0 + $1.share }, 1, accuracy: 0.000_001)
    XCTAssertEqual(top[0].share, 120.0 / 202.0, accuracy: 0.000_001)
    XCTAssertEqual(
      top.reduce(0) { $0 + $1.amountMinor },
      FinanceWallet.stats(all, card: main, period: .month, today: today).expenseMinor)
    let wide = FinanceWallet.categories(all, card: main, period: .month, today: today, limit: 10)
    XCTAssertEqual(wide.count, 6)
    XCTAssertEqual(wide.last?.name, "Books")
    let narrow = FinanceWallet.categories(all, card: main, period: .month, today: today, limit: 2)
    XCTAssertEqual(narrow.map(\.name), ["Rent", nil])
    XCTAssertEqual(narrow.last?.amountMinor, 82_000)
    let deposit = FinanceCard(id: "d", kind: .deposit, currency: .KZT, asOf: "2026-10-01")
    XCTAssertTrue(FinanceWallet.categories(all, card: deposit, period: .month, today: today).isEmpty)
  }

  func testDistributionSharesOfPositiveBalancesWithinOneCurrency() {
    let shares = FinanceWallet.distribution(cards, currency: .KZT)
    XCTAssertEqual(shares.map(\.cardID), ["kzt-main", "dep-b", "dep-a", "stocks-KZT"])
    XCTAssertEqual(shares[0].share, 1_250_000.0 / 2_325_000.0, accuracy: 0.000_001)
    XCTAssertEqual(shares.reduce(0) { $0 + $1.share }, 1, accuracy: 0.000_001)
    XCTAssertEqual(FinanceWallet.distribution(cards, currency: .USD).map(\.cardID), ["usd-main"])
    let overdrawn = [
      FinanceCard(id: "a", kind: .account, currency: .RUB, balanceMinor: -500),
      FinanceCard(id: "b", kind: .deposit, currency: .RUB, balanceMinor: 100),
    ]
    XCTAssertEqual(FinanceWallet.distribution(overdrawn, currency: .RUB).map(\.cardID), ["b"])
    XCTAssertTrue(FinanceWallet.distribution(cards, currency: .RUB).isEmpty)
  }

  func testHistoryOrderAndMembership() throws {
    XCTAssertEqual(
      FinanceWallet.history(entries, card: try card("kzt-main")).map(\.id),
      [
        "exp-future", "tr-2", "tr-1", "exp-food2", "inc-1", "exp-food", "exp-taxi", "exp-sep",
        "exp-pre",
      ])
    XCTAssertEqual(
      FinanceWallet.history(entries, card: try card("dep-a")).map(\.id), ["tr-2", "tr-1"])
    XCTAssertTrue(FinanceWallet.history(entries, card: try card("dep-b")).isEmpty)
    XCTAssertEqual(
      FinanceWallet.history(entries, card: try card("stocks-KZT")).map(\.id), ["stock-1"])
    XCTAssertEqual(
      FinanceWallet.history(entries, card: try card("usd-main")).map(\.id), ["usd-exp"])
  }

  func testCardIDMapping() throws {
    let all = cards
    func id(_ entryID: String) -> String? {
      FinanceWallet.cardID(for: entries.first { $0.id == entryID }!, cards: all)
    }
    XCTAssertEqual(id("inc-1"), "kzt-main")
    XCTAssertEqual(id("usd-exp"), "usd-main")
    XCTAssertNil(id("eur-exp"), "EUR has no account card")
    XCTAssertEqual(id("tr-1"), "dep-a", "the receiving card wins")
    XCTAssertEqual(id("tr-2"), "kzt-main")
    XCTAssertEqual(id("stock-1"), "stocks-KZT")
    XCTAssertEqual(id("kzt-main"), "kzt-main")
    XCTAssertEqual(id("dep-b"), "dep-b")
    let orphan = transfer("t", from: "kzt-main", to: "gone", 1, "2026-10-29", created: "c")
    XCTAssertEqual(FinanceWallet.cardID(for: orphan, cards: all), "kzt-main")
    let lost = transfer("t", from: "x", to: "y", 1, "2026-10-29", created: "c")
    XCTAssertNil(FinanceWallet.cardID(for: lost, cards: all))
  }

  func testRecentAcrossCurrenciesAndPositions() {
    XCTAssertEqual(
      FinanceWallet.recent(entries, limit: 5).map(\.id),
      ["exp-future", "tr-2", "tr-1", "exp-food2", "eur-exp"])
    XCTAssertTrue(FinanceWallet.recent(entries, limit: 0).isEmpty)
    let bigger = FinanceEntry(
      id: "stock-2", input: .init(type: .stock, valueMinor: 800_000, asOf: "2026-10-10", name: "Beta"),
      createdAt: "2026-10-10T08:00:00Z")
    let positions = FinanceWallet.positions(entries + [bigger], currency: .KZT)
    XCTAssertEqual(positions.map(\.id), ["stock-2", "stock-1"])
    XCTAssertNil(positions[0].gainMinor)
    XCTAssertEqual(positions[1].gainMinor, 50_000)
    XCTAssertEqual(positions[1].quantity, 10)
    XCTAssertEqual(positions[1].ticker, "AAA")
    XCTAssertTrue(FinanceWallet.positions(entries, currency: .USD).isEmpty)
  }

  func testNoticesStartFromTheBaselineNewestFirstWithTitlesAndCards() throws {
    let baseline = "2026-10-28T10:00:00Z"
    let notices = FinanceNotices.notices(entries, since: baseline, cards: cards)
    XCTAssertEqual(notices.map(\.id), ["exp-future", "tr-2", "tr-1", "exp-food2"])
    XCTAssertEqual(notices.map(\.title), ["Gifts", "Back to main", "", "Food"])
    XCTAssertEqual(notices.map(\.cardID), ["kzt-main", "kzt-main", "dep-a", "kzt-main"])
    XCTAssertEqual(notices.map(\.kind), [.expense, .transfer, .transfer, .expense])
    let first = try XCTUnwrap(notices.first)
    XCTAssertEqual(first.amountMinor, 7_000)
    XCTAssertEqual(first.currency, .KZT)
    XCTAssertEqual(first.date, "2026-10-30")
    XCTAssertEqual(first.createdAt, "2026-10-29T09:00:00Z")
  }

  func testBaselineHidesOldHistoryAndTheLimitCapsTheList() {
    XCTAssertEqual(FinanceNotices.baseline(entries), "2026-10-29T09:00:00Z")
    XCTAssertEqual(FinanceNotices.baseline([]), "")
    let first = FinanceNotices.baseline(entries)
    XCTAssertTrue(FinanceNotices.notices(entries, since: first, cards: cards).isEmpty)
    let everything = FinanceNotices.notices(entries, since: "", cards: cards)
    XCTAssertEqual(everything.count, 11, "operations only, no snapshots or stocks")
    XCTAssertEqual(FinanceNotices.notices(entries, since: "", cards: cards, limit: 3).map(\.id), ["exp-future", "tr-2", "tr-1"])
    XCTAssertTrue(FinanceNotices.notices(entries, since: "", cards: cards, limit: 0).isEmpty)
  }
}
