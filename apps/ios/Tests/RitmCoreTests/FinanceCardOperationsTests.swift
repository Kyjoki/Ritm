import Foundation
import XCTest

@testable import RitmCore

/// Income and expense booked into a named account (Halyk, Kaspi Gold) instead of the main one.
final class FinanceCardOperationsTests: XCTestCase {
  private let today = "2026-10-29"

  private func snapshot(
    _ id: String, _ type: FinanceEntryKind, _ value: Int, name: String? = nil,
    currency: FinanceCurrency = .KZT, created: String
  ) -> FinanceEntry {
    FinanceEntry(
      id: id,
      input: .init(
        type: type, currency: currency, valueMinor: value, asOf: "2026-09-01", name: name),
      createdAt: created, updatedAt: created)
  }

  private func operation(
    _ id: String, _ type: FinanceEntryKind, _ amount: Int, _ date: String, category: String,
    account: String? = nil, currency: FinanceCurrency = .KZT
  ) -> FinanceEntry {
    FinanceEntry(
      id: id,
      input: .init(
        type: type, currency: currency, amountMinor: amount, date: date, category: category,
        accountId: account),
      createdAt: date + "T12:00:00Z", updatedAt: date + "T12:00:00Z")
  }

  private func transfer(_ id: String, from: String, to: String, _ amount: Int, _ date: String)
    -> FinanceEntry
  {
    FinanceEntry(
      id: id,
      input: .init(
        type: .transfer, amountMinor: amount, date: date, fromAccountId: from, toAccountId: to),
      createdAt: date + "T15:00:00Z", updatedAt: date + "T15:00:00Z")
  }

  /// Main 10 000.00, Halyk 5 000.00, Kaspi Gold 2 000.00; USD main and a USD deposit.
  private var entries: [FinanceEntry] {
    [
      snapshot("main", .account, 1_000_000, created: "2026-09-01T08:00:00Z"),
      snapshot("halyk", .deposit, 500_000, name: "Halyk", created: "2026-09-02T08:00:00Z"),
      snapshot("kaspi", .deposit, 200_000, name: "Kaspi Gold", created: "2026-09-03T08:00:00Z"),
      snapshot("usd", .account, 100_000, currency: .USD, created: "2026-09-01T09:00:00Z"),
      snapshot(
        "usd-dep", .deposit, 50_000, name: "Wise", currency: .USD, created: "2026-09-04T09:00:00Z"),
      operation("e-main", .expense, 10_000, "2026-10-20", category: "Food"),
      operation("e-main-id", .expense, 5_000, "2026-10-21", category: "Taxi", account: "main"),
      operation("e-halyk", .expense, 30_000, "2026-10-25", category: "Food", account: "halyk"),
      operation("i-halyk", .income, 100_000, "2026-10-26", category: "Salary", account: "halyk"),
      operation("i-kaspi", .income, 20_000, "2026-10-27", category: "Gift", account: "kaspi"),
      operation("e-usd", .expense, 1_000, "2026-10-27", category: "Food", currency: .USD),
      operation(
        "e-wise", .expense, 4_000, "2026-10-28", category: "Food", account: "usd-dep",
        currency: .USD),
      transfer("t-1", from: "main", to: "halyk", 50_000, "2026-10-28"),
    ]
  }

  private var cards: [FinanceCard] { FinanceWallet.cards(entries, today: today) }
  private func card(_ id: String) throws -> FinanceCard {
    try XCTUnwrap(cards.first { $0.id == id })
  }

  // MARK: - Balances

  func testBalancesFollowTheAccountOfEachOperation() throws {
    XCTAssertEqual(try card("main").balanceMinor, 1_000_000 - 10_000 - 5_000 - 50_000)
    XCTAssertEqual(try card("halyk").balanceMinor, 500_000 - 30_000 + 100_000 + 50_000)
    XCTAssertEqual(try card("kaspi").balanceMinor, 220_000)
    XCTAssertEqual(try card("usd").balanceMinor, 99_000)
    XCTAssertEqual(try card("usd-dep").balanceMinor, 46_000)
  }

  func testTotalsPerCurrencyAreTheSameWhereverTheOperationWasBooked() {
    let allOnMain = entries.map { entry -> FinanceEntry in
      var copy = entry
      if copy.type == .income || copy.type == .expense { copy.accountId = nil }
      return copy
    }
    XCTAssertEqual(
      FinanceWallet.totals(FinanceWallet.cards(allOnMain, today: today)),
      FinanceWallet.totals(cards))
  }

  func testAnOperationBeforeTheCardSnapshotDoesNotCount() throws {
    var all = entries
    all.append(operation("early", .expense, 99_000, "2026-08-31", category: "Old", account: "halyk"))
    let halyk = try XCTUnwrap(FinanceWallet.cards(all, today: today).first { $0.id == "halyk" })
    XCTAssertEqual(halyk.balanceMinor, 620_000)
  }

  // MARK: - Per-card history and analytics

  func testHistoryHoldsExactlyTheOperationsOfTheCard() throws {
    XCTAssertEqual(
      FinanceWallet.history(entries, card: try card("main")).map(\.id),
      ["t-1", "e-main-id", "e-main"])
    XCTAssertEqual(
      FinanceWallet.history(entries, card: try card("halyk")).map(\.id),
      ["t-1", "i-halyk", "e-halyk"])
    XCTAssertEqual(FinanceWallet.history(entries, card: try card("kaspi")).map(\.id), ["i-kaspi"])
    XCTAssertEqual(FinanceWallet.history(entries, card: try card("usd")).map(\.id), ["e-usd"])
    XCTAssertEqual(FinanceWallet.history(entries, card: try card("usd-dep")).map(\.id), ["e-wise"])
  }

  func testStatsOfEachCardCountItsOwnOperationsAndTransfers() throws {
    XCTAssertEqual(
      FinanceWallet.stats(entries, card: try card("main"), period: .month, today: today),
      FinancePeriodStats(expenseMinor: 15_000, transfersOutMinor: 50_000))
    XCTAssertEqual(
      FinanceWallet.stats(entries, card: try card("halyk"), period: .month, today: today),
      FinancePeriodStats(incomeMinor: 100_000, expenseMinor: 30_000, transfersInMinor: 50_000))
    XCTAssertEqual(
      FinanceWallet.stats(entries, card: try card("kaspi"), period: .month, today: today),
      FinancePeriodStats(incomeMinor: 20_000))
    // The overview still counts every operation of the currency once.
    XCTAssertEqual(
      FinanceWallet.overviewStats(entries, currency: .KZT, period: .month, today: today),
      FinancePeriodStats(incomeMinor: 120_000, expenseMinor: 45_000))
  }

  func testCategoriesAndSeriesFollowTheCard() throws {
    let halyk = try card("halyk")
    let shares = FinanceWallet.categories(entries, card: halyk, period: .month, today: today)
    XCTAssertEqual(shares.map(\.name), ["Food"])
    XCTAssertEqual(shares.map(\.amountMinor), [30_000])
    XCTAssertEqual(
      FinanceWallet.categories(entries, card: try card("main"), period: .month, today: today)
        .map(\.amountMinor), [10_000, 5_000])
    let series = FinanceWallet.balanceSeries(entries, card: halyk, period: .week, today: today)
    XCTAssertEqual(series.last, FinancePoint(date: today, valueMinor: halyk.balanceMinor ?? -1))
    XCTAssertEqual(series.first, FinancePoint(date: "2026-10-25", valueMinor: 470_000))
    let overview = FinanceWallet.overviewSeries(
      entries, currency: .KZT, period: .week, today: today)
    XCTAssertEqual(overview.last?.valueMinor, 935_000 + 620_000 + 220_000)
  }

  func testCardIDFollowsTheAccountOfTheOperation() {
    func id(_ entryID: String) -> String? {
      FinanceWallet.cardID(for: entries.first { $0.id == entryID }!, cards: cards)
    }
    XCTAssertEqual(id("e-main"), "main")
    XCTAssertEqual(id("e-main-id"), "main")
    XCTAssertEqual(id("e-halyk"), "halyk")
    XCTAssertEqual(id("i-kaspi"), "kaspi")
    XCTAssertEqual(id("e-wise"), "usd-dep")
    let gone = operation("x", .expense, 1, "2026-10-01", category: "?", account: "deleted")
    XCTAssertEqual(FinanceWallet.cardID(for: gone, cards: cards), "main", "falls back to main")
  }

  // MARK: - Options and preselection

  func testOptionsListMainFirstThenNamedAccountsOfTheCurrency() {
    let kzt = FinanceOperationAccount.options(entries, currency: .KZT)
    XCTAssertEqual(kzt.map(\.id), ["main", "halyk", "kaspi"])
    XCTAssertEqual(kzt.map(\.name), [nil, "Halyk", "Kaspi Gold"])
    XCTAssertTrue(kzt[0].isMain)
    XCTAssertEqual(
      FinanceOperationAccount.options(entries, currency: .USD).map(\.id), ["usd", "usd-dep"])
    XCTAssertTrue(FinanceOperationAccount.options(entries, currency: .EUR).isEmpty)
    let stock = FinanceEntry(
      id: "s", input: .init(type: .stock, valueMinor: 1, asOf: "2026-09-01", name: "A"),
      createdAt: "c")
    XCTAssertEqual(FinanceOperationAccount.options(entries + [stock], currency: .KZT).count, 3)
  }

  func testPreselectionPrefersTheOpenCardThenLastUsedThenMain() {
    func pick(card: String? = nil, last: String? = nil, _ currency: FinanceCurrency = .KZT)
      -> String
    {
      FinanceOperationAccount.preselected(entries, currency: currency, card: card, lastUsed: last)
    }
    XCTAssertEqual(pick(card: "halyk", last: "kaspi"), "halyk")
    XCTAssertEqual(pick(last: "kaspi"), "kaspi")
    XCTAssertEqual(pick(), "main", "opened from the overview")
    XCTAssertEqual(pick(card: "usd-dep"), "main", "a card of another currency is not an option")
    XCTAssertEqual(pick(card: "usd-dep", .USD), "usd-dep")
    XCTAssertEqual(pick(card: "gone", last: "gone"), "main")
    XCTAssertEqual(pick(.EUR), "")
    let onlyDeposit = entries.filter { $0.id != "main" }
    XCTAssertEqual(
      FinanceOperationAccount.preselected(onlyDeposit, currency: .KZT), "halyk",
      "no main account: the first account")
  }

  func testRequestAccountIDIsNilForTheMainAccount() {
    func send(_ id: String, _ currency: FinanceCurrency = .KZT) -> String? {
      FinanceOperationAccount.requestAccountID(id, entries: entries, currency: currency)
    }
    XCTAssertNil(send("main"))
    XCTAssertEqual(send("halyk"), "halyk")
    XCTAssertNil(send(""))
    XCTAssertNil(send("usd-dep"), "another currency")
    XCTAssertNil(send("unknown"))
  }

  // MARK: - Request encoding

  private func json(_ input: FinanceEntryInput) throws -> [String: Any] {
    let data = try JSONEncoder().encode(input)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  func testAccountIDIsOmittedForTheMainAccountAndSentForANamedOne() throws {
    let main = FinanceEntryInput(
      type: .expense, amountMinor: 100, date: "2026-10-29", category: "Food",
      accountId: FinanceOperationAccount.requestAccountID(
        "main", entries: entries, currency: .KZT))
    XCTAssertNil(try json(main)["accountId"])
    let named = FinanceEntryInput(
      type: .income, amountMinor: 100, date: "2026-10-29", category: "Salary",
      accountId: FinanceOperationAccount.requestAccountID(
        "halyk", entries: entries, currency: .KZT))
    XCTAssertEqual(try json(named)["accountId"] as? String, "halyk")
    // Only income and expense carry it.
    let move = FinanceEntryInput(
      type: .transfer, amountMinor: 100, date: "2026-10-29", accountId: "halyk",
      fromAccountId: "a", toAccountId: "b")
    XCTAssertNil(try json(move)["accountId"])
  }

  func testAccountIDDecodesFromTheServerAndRoundTrips() throws {
    let text = """
      {"id":"e1","type":"expense","currency":"KZT","note":"","amountMinor":500,
       "date":"2026-10-29","category":"Food","accountId":"halyk",
       "createdAt":"2026-10-29T10:00:00Z","updatedAt":"2026-10-29T10:00:00Z"}
      """
    let entry = try JSONDecoder().decode(FinanceEntry.self, from: Data(text.utf8))
    XCTAssertEqual(entry.accountId, "halyk")
    let again = try JSONDecoder().decode(FinanceEntry.self, from: JSONEncoder().encode(entry))
    XCTAssertEqual(again, entry)
    let legacy = text.replacingOccurrences(of: "\"accountId\":\"halyk\",", with: "")
    XCTAssertNil(try JSONDecoder().decode(FinanceEntry.self, from: Data(legacy.utf8)).accountId)
  }

  // MARK: - Wallet purchases

  private func purchase(card: String?, currency: FinanceCurrency = .KZT) -> WalletPurchase {
    WalletPurchase(
      id: "w", merchant: "Cafe", amountMinor: 1_000, currency: currency, card: card,
      date: "2026-10-29", receivedAt: "2026-10-29T10:00:00Z")
  }

  func testPurchaseCardLabelMatchesAnAccountNameIgnoringCase() {
    func match(_ label: String?) -> String {
      WalletAccountMatch.defaultAccountID(for: purchase(card: label), entries: entries)
    }
    XCTAssertEqual(match("Kaspi Gold"), "kaspi")
    XCTAssertEqual(match("kaspi gold"), "kaspi")
    XCTAssertEqual(match("Kaspi Gold Visa"), "kaspi", "label contains the name")
    XCTAssertEqual(match("Halyk Bank"), "halyk")
    XCTAssertEqual(match("Gold"), "kaspi", "name contains the label")
    XCTAssertEqual(match("•••• 1234"), "main", "masked label never matches")
    XCTAssertEqual(match("Sber"), "main")
    XCTAssertEqual(match(nil), "main")
    XCTAssertEqual(match("   "), "main")
  }

  func testPurchaseMatchStaysInItsCurrencyAndPrefersTheLongestName() {
    XCTAssertEqual(
      WalletAccountMatch.defaultAccountID(
        for: purchase(card: "Kaspi Gold", currency: .USD), entries: entries), "usd")
    var all = entries
    all.append(snapshot("kaspi-red", .deposit, 1, name: "Kaspi", created: "2026-09-05T08:00:00Z"))
    XCTAssertEqual(
      WalletAccountMatch.defaultAccountID(for: purchase(card: "Kaspi Gold"), entries: all), "kaspi")
    XCTAssertEqual(
      WalletAccountMatch.defaultAccountID(for: purchase(card: "Kaspi Red"), entries: all),
      "kaspi-red")
    XCTAssertEqual(
      WalletAccountMatch.defaultAccountID(for: purchase(card: "x", currency: .EUR), entries: all),
      "")
  }

  func testWalletExpenseCarriesTheAccountOnlyWhenItIsNotMain() throws {
    let main = WalletEntryBuilder.expense(from: purchase(card: nil), category: "Кафе")
    XCTAssertNil(main.accountId)
    XCTAssertNil(try json(main)["accountId"])
    let named = WalletEntryBuilder.expense(
      from: purchase(card: "Kaspi Gold"), category: "Кафе", accountID: "kaspi")
    XCTAssertEqual(named.accountId, "kaspi")
    XCTAssertEqual(try json(named)["accountId"] as? String, "kaspi")
  }
}
